#include "app/Editor.h"

#include <algorithm>
#include <cstring>
#include <filesystem>

#include <imgui.h>
#include <imgui_internal.h>

#include "IconsFontAwesome6.h"
#include "app/Ui.h"
#include "core/File.h"
#include "core/Log.h"
#include "gpu/Gl.h"
#include "map/MapMesh.h"
#include "map/Raycast.h"
#include "platform/FileDialog.h"

namespace fs = std::filesystem;

namespace pb {
namespace {
constexpr float kDeg2Rad = 3.14159265358979323846f / 180.0f;

const char* kTf2Maps =
    "C:/Program Files (x86)/Steam/steamapps/common/Team Fortress 2/tf/maps";

void dropCallback(GLFWwindow* w, int count, const char** paths);
}  // namespace

namespace {
void dropCallback(GLFWwindow* w, int count, const char** paths) {
    auto* self = static_cast<Editor*>(glfwGetWindowUserPointer(w));
    if (self && count > 0 && paths && paths[0]) self->openMap(paths[0]);
}
}  // namespace

void Editor::promptOpenMap() {
    const char* dir = fs::exists(kTf2Maps) ? kTf2Maps : nullptr;
    const std::string picked = openFileDialog(
        "Open a map",
        "Source maps (*.bsp *.vmf)\0*.bsp;*.vmf\0Compiled BSP\0*.bsp\0Hammer VMF\0*.vmf\0"
        "All files\0*.*\0\0",
        dir);
    if (!picked.empty()) openMap(picked);
}

bool Editor::init(GLFWwindow* window) {
    window_ = window;
    if (!renderer_.init()) return false;
    glfwSetWindowUserPointer(window, this);
    glfwSetDropCallback(window, dropCallback);

    sourceFs_.mountDefaults(executableDir());
    materials_.init(&sourceFs_);

    const char* titles[4] = {"3D View", "Top (x/y)", "Front (x/z)", "Side (y/z)"};
    const ViewKind kinds[4] = {ViewKind::Perspective, ViewKind::Top, ViewKind::Front,
                               ViewKind::Side};
    for (int i = 0; i < 4; ++i) {
        views_[i].title = titles[i];
        views_[i].kind = kinds[i];
        views_[i].camera.kind = kinds[i];
    }
    return true;
}

void Editor::shutdown() {
    prefs_.save();
    renderer_.clearWorld();
}

void Editor::attachSettings(Settings s, float effectiveScale) {
    prefs_ = std::move(s);
    uiScale_ = effectiveScale;
    showWelcome_ = prefs_.showWelcome;
}

void Editor::requestUiScale(float scale) {
    scale = std::clamp(scale, 0.75f, 2.5f);
    if (scale == uiScale_) return;
    uiScale_ = scale;
    scaleDirty_ = true;
    prefs_.uiScale = scale;
    prefs_.save();
}

bool Editor::takeFontRebuild(float& outScale) {
    if (!scaleDirty_) return false;
    outScale = uiScale_;
    scaleDirty_ = false;
    return true;
}

bool Editor::openMap(const std::string& path) {
    clearSelection();
    const std::string ext = [&] {
        std::string e = fs::path(path).extension().string();
        std::transform(e.begin(), e.end(), e.begin(), ::tolower);
        return e;
    }();

    if (ext == ".vmf") {
        std::string err;
        if (!doc_.loadVmf(path, &err)) {
            status_ = "Failed to load VMF: " + err;
            return false;
        }
        bsp_ = BspFile{};
        buildAndUpload(meshOpts_);
        frameAllViews();
        status_ = doc_.name() + "  —  " + std::to_string(doc_.worldSolids().size()) +
                  " brushes, " + std::to_string(doc_.entities().size()) + " entities";
        prefs_.pushRecent(path);
        prefs_.save();
        showWelcome_ = false;
        return true;
    }

    if (ext != ".bsp") {
        status_ = "Open a .bsp or .vmf: " + path;
        PB_WARN("%s", status_.c_str());
        return false;
    }

    std::string err;
    if (!bsp_.load(path, &err)) {
        status_ = "Failed to load: " + err;
        return false;
    }
    doc_.clear();
    buildAndUpload(meshOpts_);
    frameAllViews();
    status_ = bsp_.name() + "  —  " + std::to_string(mesh_.drawnFaces) + " faces, " +
              std::to_string(mesh_.pointEntities.size()) + " point ents, " +
              std::to_string(mesh_.props.size()) + " props";
    prefs_.pushRecent(path);
    prefs_.save();
    showWelcome_ = false;
    return true;
}

void Editor::buildAndUpload(const MeshBuildOptions& opts) {
    if (!doc_.empty())
        mesh_ = map::buildDocMesh(doc_, materials_);
    else
        mesh_ = buildWorldMesh(bsp_, opts);
    renderer_.upload(mesh_, &materials_);

    int textured = 0, missing = 0, shown = 0;
    for (const auto& b : mesh_.batches) {
        const auto& info = materials_.get(b.material);
        if (info.width > 0) {
            ++textured;
        } else {
            ++missing;
            if (shown++ < 12) PB_WARN("no texture for material: %s", b.material.c_str());
        }
    }
    PB_INFO("materials: %d textured, %d missing (of %zu)", textured, missing,
            mesh_.batches.size());
}

void Editor::frameAllViews() {
    for (auto& v : views_) v.camera.frameBounds(mesh_.playBoundsMin, mesh_.playBoundsMax);

    // Open the 3D view inside the map at a spawn, the way Hammer does.
    if (mesh_.hasSpawn) {
        Camera& c = views_[0].camera;
        c.pos = mesh_.spawnPos;
        c.yawDeg = mesh_.spawnYaw;
        c.pitchDeg = -8.0f;
    }
}

// ---------------------------------------------------------------------------
// Frame
// ---------------------------------------------------------------------------
void Editor::frame() {
    ImGuiViewport* vp = ImGui::GetMainViewport();
    ImGui::SetNextWindowPos(vp->WorkPos);
    ImGui::SetNextWindowSize(vp->WorkSize);
    ImGui::SetNextWindowViewport(vp->ID);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 0.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0f);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0, 0));
    ImGuiWindowFlags host = ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoCollapse |
                            ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoMove |
                            ImGuiWindowFlags_NoBringToFrontOnFocus |
                            ImGuiWindowFlags_NoNavFocus;
    ImGui::Begin("##PootisHost", nullptr, host);
    ImGui::PopStyleVar(3);

    drawTopBar();

    const ImGuiID dockId = ImGui::GetID("PootisDockV3");
    if (layoutDirty_ || !ImGui::DockBuilderGetNode(dockId)) {
        buildDockLayout(dockId, ImGui::GetContentRegionAvail());
        layoutDirty_ = false;
    }
    ImGui::DockSpace(dockId, ImVec2(0, 0), ImGuiDockNodeFlags_PassthruCentralNode);
    ImGui::End();

    if (ImGui::IsKeyChordPressed(ImGuiMod_Ctrl | ImGuiKey_O)) promptOpenMap();

    if (mode_ == Mode::Simple) {
        drawBuildKit();
        drawSelectionPanel();
    } else {
        drawOutliner();
        drawTextureBrowser();
        drawMaterialList();
        drawEntityCatalog();
    }
    for (auto& v : views_) drawViewportPanel(v);
    drawStatusBar();
    drawWelcome();
}

void Editor::buildDockLayout(unsigned int dockId, const ImVec2& size) {
    ImGui::DockBuilderRemoveNode(dockId);
    ImGui::DockBuilderAddNode(dockId, ImGuiDockNodeFlags_DockSpace);
    ImGui::DockBuilderSetNodeSize(dockId, size.x > 0 ? size : ImVec2(1600, 900));

    if (mode_ == Mode::Simple) {
        ImGuiID left, rest, right, center;
        left = ImGui::DockBuilderSplitNode(dockId, ImGuiDir_Left, 0.235f, nullptr, &rest);
        right = ImGui::DockBuilderSplitNode(rest, ImGuiDir_Right, 0.22f, nullptr, &center);
        ImGui::DockBuilderDockWindow("Build Kit", left);
        ImGui::DockBuilderDockWindow("Selection", right);
        ImGui::DockBuilderDockWindow("Top (x/y)", center);
        ImGui::DockBuilderDockWindow("Front (x/z)", center);
        ImGui::DockBuilderDockWindow("Side (y/z)", center);
        ImGui::DockBuilderDockWindow("3D View", center);
    } else {
        ImGuiID left, center;
        left = ImGui::DockBuilderSplitNode(dockId, ImGuiDir_Left, 0.215f, nullptr, &center);
        ImGuiID top, bottom;
        top = ImGui::DockBuilderSplitNode(center, ImGuiDir_Up, 0.5f, nullptr, &bottom);
        ImGuiID tl, tr, bl, br;
        tl = ImGui::DockBuilderSplitNode(top, ImGuiDir_Left, 0.5f, nullptr, &tr);
        bl = ImGui::DockBuilderSplitNode(bottom, ImGuiDir_Left, 0.5f, nullptr, &br);
        ImGui::DockBuilderDockWindow("Contents", left);
        ImGui::DockBuilderDockWindow("Textures", left);
        ImGui::DockBuilderDockWindow("Materials", left);
        ImGui::DockBuilderDockWindow("Entities", left);
        ImGui::DockBuilderDockWindow("3D View", tl);
        ImGui::DockBuilderDockWindow("Top (x/y)", tr);
        ImGui::DockBuilderDockWindow("Front (x/z)", bl);
        ImGui::DockBuilderDockWindow("Side (y/z)", br);
    }
    ImGui::DockBuilderFinish(dockId);
}

// ---------------------------------------------------------------------------
// Top bar
// ---------------------------------------------------------------------------
void Editor::drawTopBar() {
    using namespace pb::ui;
    const float barH = 50.0f;
    ImGui::PushStyleColor(ImGuiCol_ChildBg, col::bg1);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(12, 0));
    ImGui::BeginChild("##topbar", ImVec2(0, barH), ImGuiChildFlags_None,
                      ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);
    ImGui::PopStyleVar();

    const float row = 30.0f;
    ImGui::SetCursorPosY((barH - row) * 0.5f);

    // Brand
    ImGui::PushStyleColor(ImGuiCol_Text, col::acc);
    if (fontBig) ImGui::PushFont(fontBig);
    ImGui::TextUnformatted(ICON_FA_CUBES);
    if (fontBig) ImGui::PopFont();
    ImGui::PopStyleColor();
    ImGui::SameLine(0, 8);
    if (fontUiMed) ImGui::PushFont(fontUiMed);
    ImGui::SetCursorPosY((barH - ImGui::GetTextLineHeight()) * 0.5f);
    ImGui::TextUnformatted("Pootis Builder");
    if (fontUiMed) ImGui::PopFont();

    ImGui::SameLine(0, 16);
    ImGui::SetCursorPosY((barH - row) * 0.5f);
    if (toolButton(ICON_FA_FOLDER_OPEN "  Open", false, "Open a .bsp  (Ctrl+O)"))
        promptOpenMap();
    ImGui::SameLine(0, 2);
    if (toolButton(ICON_FA_DOWNLOAD "  Import map")) promptOpenMap();
    ImGui::SameLine(0, 2);
    if (toolButton(ICON_FA_FLOPPY_DISK "  Save"))
        status_ = "Saving to VMF is not wired up yet.";

    // Simple / Pro
    ImGui::SameLine(0, 16);
    ImGui::SetCursorPosY((barH - row) * 0.5f);
    {
        const char* const modes[] = {ICON_FA_TABLE_CELLS_LARGE "  Simple",
                                     ICON_FA_PEN_RULER "  Pro"};
        int r = segmented("mode", modes, 2, static_cast<int>(mode_), row);
        if (r >= 0 && r != static_cast<int>(mode_)) {
            mode_ = static_cast<Mode>(r);
            layoutDirty_ = true;
        }
    }

    // Tool modes (Pro only)
    if (mode_ == Mode::Pro) {
        ImGui::SameLine(0, 12);
        ImGui::SetCursorPosY((barH - row) * 0.5f);
        const char* const tools[] = {
            ICON_FA_ARROW_POINTER " Select", ICON_FA_CUBE " Block",
            ICON_FA_BEZIER_CURVE " Vertex",  ICON_FA_SCISSORS " Clip",
            ICON_FA_IMAGE " Texture",        ICON_FA_LIGHTBULB " Entity"};
        int r = segmented("tool", tools, 6, static_cast<int>(tool_), row);
        if (r >= 0) tool_ = static_cast<Tool>(r);
    }

    // Right cluster
    const float rightW = 340.0f * uiScale_;
    ImGui::SameLine();
    ImGui::SetCursorPosX(ImGui::GetWindowWidth() - rightW);
    ImGui::SetCursorPosY((barH - row) * 0.5f);

    char gridLabel[48];
    std::snprintf(gridLabel, sizeof(gridLabel), ICON_FA_TABLE_CELLS "  Grid %d", gridSize_);
    if (toolButton(gridLabel)) ImGui::OpenPopup("##gridpop");
    if (ImGui::BeginPopup("##gridpop")) {
        for (int g : {1, 2, 4, 8, 16, 32, 64, 128, 256, 512}) {
            char b[16];
            std::snprintf(b, sizeof(b), "%d", g);
            if (ImGui::Selectable(b, g == gridSize_)) gridSize_ = g;
        }
        ImGui::EndPopup();
    }
    ImGui::SameLine(0, 2);
    if (toolButton(snap_ ? ICON_FA_CHECK "  Snap" : "Snap", snap_)) snap_ = !snap_;

    ImGui::SameLine(0, 2);
    if (toolButton(ICON_FA_BARS)) ImGui::OpenPopup("##viewmenu");
    drawViewMenuPopup();

    ImGui::SameLine(0, 8);
    ImGui::PushStyleColor(ImGuiCol_Button, col::bg2);
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, col::bg3);
    ImGui::PushStyleColor(ImGuiCol_Text, col::acc);
    if (ImGui::Button(ICON_FA_PLAY "  Build & play", ImVec2(0, row)))
        status_ = "Offline vbsp/vvis/vrad + in-game preview is on the roadmap.";
    ImGui::PopStyleColor(3);

    ImGui::EndChild();
    ImGui::PopStyleColor();

    ImGui::GetWindowDrawList()->AddLine(
        ImGui::GetCursorScreenPos(),
        ImVec2(ImGui::GetCursorScreenPos().x + ImGui::GetWindowWidth(),
               ImGui::GetCursorScreenPos().y),
        pb::ui::u32(pb::ui::col::bd));
}

void Editor::drawViewMenuPopup() {
    if (!ImGui::BeginPopup("##viewmenu")) return;
    if (ImGui::BeginMenu("3D shading")) {
        auto item = [&](const char* label, ShadeMode m) {
            if (ImGui::MenuItem(label, nullptr, settings_.shadeMode == m))
                settings_.shadeMode = m;
        };
        item("Textured + lightmap", ShadeMode::TexturedLit);
        item("Lightmap grid", ShadeMode::LightmapGrid);
        item("Flat", ShadeMode::Flat);
        item("Textured (fullbright)", ShadeMode::TexturedFull);
        ImGui::EndMenu();
    }
    ImGui::MenuItem("Grid", nullptr, &settings_.showGrid);
    ImGui::MenuItem("Static props", nullptr, &settings_.showProps);
    ImGui::MenuItem("Point entities", nullptr, &settings_.showPointEntities);
    ImGui::MenuItem("Wire overlay (3D)", nullptr, &settings_.wireOverlay);
    ImGui::Separator();
    ImGui::SetNextItemWidth(160);
    ImGui::SliderFloat("Exposure", &settings_.exposure, 0.2f, 3.0f, "%.2f");
    ImGui::SetNextItemWidth(160);
    if (ImGui::SliderFloat("Lightmap gain", &meshOpts_.lightmapGain, 0.3f, 4.0f, "%.2f") &&
        hasMap())
        buildAndUpload(meshOpts_);
    ImGui::Separator();
    if (ImGui::BeginMenu(ICON_FA_MAGNIFYING_GLASS "  Interface scale")) {
        uiScaleMenu();
        ImGui::EndMenu();
    }
    ImGui::Separator();
    if (ImGui::MenuItem("Frame map", "F") && hasMap()) frameAllViews();
    if (ImGui::MenuItem("Reset layout")) layoutDirty_ = true;
    if (ImGui::MenuItem("Welcome screen")) showWelcome_ = true;
    if (ImGui::MenuItem("Exit")) glfwSetWindowShouldClose(window_, 1);
    ImGui::EndPopup();
}

void Editor::uiScaleMenu() {
    const float steps[] = {0.8f, 0.9f, 1.0f, 1.1f, 1.25f, 1.5f, 1.75f, 2.0f};
    for (float s : steps) {
        char label[24];
        std::snprintf(label, sizeof(label), "%d%%", static_cast<int>(s * 100 + 0.5f));
        if (ImGui::MenuItem(label, nullptr, std::abs(s - uiScale_) < 0.001f))
            requestUiScale(s);
    }
}

// ---------------------------------------------------------------------------
// Welcome screen
// ---------------------------------------------------------------------------
void Editor::drawWelcome() {
    if (!showWelcome_) return;
    using namespace pb::ui;

    ImGuiViewport* vp = ImGui::GetMainViewport();
    ImGui::GetBackgroundDrawList()->AddRectFilled(
        vp->Pos, ImVec2(vp->Pos.x + vp->Size.x, vp->Pos.y + vp->Size.y),
        IM_COL32(8, 9, 11, 205));

    const ImVec2 panel(std::min(760.0f * uiScale_, vp->Size.x - 40.0f),
                       std::min(560.0f * uiScale_, vp->Size.y - 40.0f));
    ImGui::SetNextWindowPos(ImVec2(vp->Pos.x + (vp->Size.x - panel.x) * 0.5f,
                                   vp->Pos.y + (vp->Size.y - panel.y) * 0.5f));
    ImGui::SetNextWindowSize(panel);
    ImGui::SetNextWindowFocus();
    ImGui::PushStyleColor(ImGuiCol_WindowBg, col::bg1);
    ImGui::PushStyleColor(ImGuiCol_Border, col::bd2);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(34, 30));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 1.0f);
    ImGui::Begin("##welcome", nullptr,
                 ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                     ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoCollapse |
                     ImGuiWindowFlags_NoDocking | ImGuiWindowFlags_NoSavedSettings);

    ImGui::PushStyleColor(ImGuiCol_Text, col::acc);
    if (fontBig) ImGui::PushFont(fontBig);
    ImGui::TextUnformatted(ICON_FA_CUBES "  Pootis Builder");
    if (fontBig) ImGui::PopFont();
    ImGui::PopStyleColor();
    ImGui::PushStyleColor(ImGuiCol_Text, col::dim);
    ImGui::TextUnformatted("A modern map editor for Team Fortress 2");
    ImGui::PopStyleColor();
    ImGui::Dummy(ImVec2(0, 16));

    const float colW = (ImGui::GetContentRegionAvail().x - 20) / 3.0f;
    auto bigButton = [&](const char* id, const char* icon, const char* title,
                         const char* sub) {
        ImGui::PushStyleColor(ImGuiCol_Button, col::bg2);
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered, col::bg3);
        const bool hit = ImGui::Button(id, ImVec2(colW, 96 * uiScale_));
        ImGui::PopStyleColor(2);
        const ImVec2 mn = ImGui::GetItemRectMin();
        ImDrawList* dl = ImGui::GetWindowDrawList();
        if (fontBig)
            dl->AddText(fontBig, 22.0f * uiScale_, ImVec2(mn.x + 14, mn.y + 12),
                        u32(col::acc), icon);
        dl->AddText(ImVec2(mn.x + 14, mn.y + 42 * uiScale_), u32(col::tx), title);
        dl->AddText(ImVec2(mn.x + 14, mn.y + 42 * uiScale_ + ImGui::GetTextLineHeight() + 2),
                    u32(col::faint), sub);
        return hit;
    };

    if (bigButton("##bNew", ICON_FA_FILE_CIRCLE_PLUS, "New map",
                  "Start from an empty grid")) {
        bsp_ = BspFile();
        renderer_.clearWorld();
        mesh_ = WorldMesh{};
        status_ = "New map — place pieces from the Build Kit.";
        showWelcome_ = false;
    }
    ImGui::SameLine(0, 10);
    if (bigButton("##bOpen", ICON_FA_FOLDER_OPEN, "Open map", "A compiled .bsp"))
        promptOpenMap();
    ImGui::SameLine(0, 10);
    if (bigButton("##bImport", ICON_FA_DOWNLOAD, "Import", ".vmf / .bsp (soon)"))
        promptOpenMap();

    ImGui::Dummy(ImVec2(0, 18));
    sectionLabel("RECENT");
    ImGui::Dummy(ImVec2(0, 4));
    if (prefs_.recent.empty()) {
        ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
        ImGui::TextUnformatted("Nothing yet — the maps you open show up here.");
        ImGui::PopStyleColor();
    } else if (ImGui::BeginChild("recent", ImVec2(0, -46 * uiScale_))) {
        int removeIdx = -1;
        const float rowH = ImGui::GetTextLineHeight() * 2.0f + 12.0f;
        for (size_t i = 0; i < prefs_.recent.size(); ++i) {
            const std::string& path = prefs_.recent[i];
            const std::string name = fs::path(path).filename().string();
            const std::string dir = fs::path(path).parent_path().string();
            ImGui::PushID(static_cast<int>(i));
            if (ImGui::Selectable("##r", false, 0, ImVec2(0, rowH))) {
                if (fs::exists(path)) openMap(path);
                else status_ = "That file has moved: " + path;
            }
            const ImVec2 mn = ImGui::GetItemRectMin();
            ImDrawList* dl = ImGui::GetWindowDrawList();
            dl->AddText(ImVec2(mn.x + 8, mn.y + 4), u32(col::tx), name.c_str());
            dl->AddText(ImVec2(mn.x + 8, mn.y + 6 + ImGui::GetTextLineHeight()),
                        u32(col::faint), dir.c_str());
            ImGui::SameLine();
            ImGui::SetCursorPosX(ImGui::GetCursorPosX() +
                                 ImGui::GetContentRegionAvail().x - 26 * uiScale_);
            ImGui::SetCursorPosY(ImGui::GetCursorPosY() + (rowH - ImGui::GetFrameHeight()) * 0.5f);
            if (ImGui::SmallButton(ICON_FA_XMARK)) removeIdx = static_cast<int>(i);
            ImGui::PopID();
        }
        if (removeIdx >= 0) {
            prefs_.recent.erase(prefs_.recent.begin() + removeIdx);
            prefs_.save();
        }
    }
    if (!prefs_.recent.empty()) ImGui::EndChild();

    ImGui::Separator();
    ImGui::AlignTextToFramePadding();
    ImGui::PushStyleColor(ImGuiCol_Text, col::dim);
    ImGui::TextUnformatted("Interface scale");
    ImGui::PopStyleColor();
    ImGui::SameLine();
    ImGui::SetNextItemWidth(120 * uiScale_);
    char cur[16];
    std::snprintf(cur, sizeof(cur), "%d%%", static_cast<int>(uiScale_ * 100 + 0.5f));
    if (ImGui::BeginCombo("##scale", cur)) {
        uiScaleMenu();
        ImGui::EndCombo();
    }
    ImGui::SameLine(0, 24);
    if (ImGui::Checkbox("Show this on startup", &prefs_.showWelcome)) prefs_.save();

    if (hasMap()) {
        ImGui::SameLine();
        float bw = 168 * uiScale_;
        ImGui::SetCursorPosX(ImGui::GetWindowContentRegionMax().x - bw);
        if (ImGui::Button(ICON_FA_ARROW_RIGHT "  Continue editing", ImVec2(bw, 0)))
            showWelcome_ = false;
    }

    ImGui::End();
    ImGui::PopStyleVar(2);
    ImGui::PopStyleColor(2);
}

// ---------------------------------------------------------------------------
// Viewport panels
// ---------------------------------------------------------------------------
void Editor::drawViewportPanel(ViewPanel& p) {
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0, 0));
    const bool visible = ImGui::Begin(p.title);
    ImGui::PopStyleVar();
    if (!visible) {
        p.hovered = false;
        ImGui::End();
        return;
    }

    const ImVec2 avail = ImGui::GetContentRegionAvail();
    const int w = std::max(16, static_cast<int>(avail.x));
    const int h = std::max(16, static_cast<int>(avail.y));
    p.contentMin = {ImGui::GetCursorScreenPos().x, ImGui::GetCursorScreenPos().y};
    p.contentSize = {static_cast<float>(w), static_cast<float>(h)};
    p.hovered = ImGui::IsWindowHovered();

    handleViewportInput(p);

    p.fb.resize(w, h);
    p.fb.bind();
    renderer_.renderView(p.camera, w, h, settings_);
    Framebuffer::unbind();

    ImGui::Image(static_cast<ImTextureID>(static_cast<intptr_t>(p.fb.colorTexture())),
                 ImVec2(static_cast<float>(w), static_cast<float>(h)), ImVec2(0, 1),
                 ImVec2(1, 0));

    // Corner label like Hammer.
    ImVec2 tl(p.contentMin.x, p.contentMin.y);
    ImDrawList* dl = ImGui::GetWindowDrawList();
    dl->AddText(ImVec2(tl.x + 8, tl.y + 6), IM_COL32(210, 210, 210, 200), p.title);

    if (!hasMap() && p.kind == ViewKind::Perspective) {
        const char* msg = "Open a .bsp  —  File > Open BSP  (Ctrl+O)  or drag one in";
        const ImVec2 ts = ImGui::CalcTextSize(msg);
        dl->AddText(ImVec2(tl.x + (p.contentSize.x - ts.x) * 0.5f,
                           tl.y + (p.contentSize.y - ts.y) * 0.5f),
                    IM_COL32(180, 180, 185, 220), msg);
    }
    ImGui::End();
}

void Editor::handleViewportInput(ViewPanel& p) {
    if (!p.hovered) return;
    ImGuiIO& io = ImGui::GetIO();
    const float dt = std::clamp(io.DeltaTime, 0.0f, 0.1f);

    if (p.kind == ViewKind::Perspective) {
        if (ImGui::IsMouseDragging(ImGuiMouseButton_Right, 0.0f)) {
            p.camera.yawDeg -= io.MouseDelta.x * 0.15f;
            p.camera.pitchDeg = std::clamp(p.camera.pitchDeg - io.MouseDelta.y * 0.15f,
                                           -89.0f, 89.0f);
        }
        const bool rmb = ImGui::IsMouseDown(ImGuiMouseButton_Right);
        if (rmb) {
            float speed = flySpeed_ * dt * (io.KeyShift ? 3.0f : 1.0f);
            glm::vec3 fwd = p.camera.forward();
            glm::vec3 right = p.camera.right();
            if (ImGui::IsKeyDown(ImGuiKey_W)) p.camera.pos += fwd * speed;
            if (ImGui::IsKeyDown(ImGuiKey_S)) p.camera.pos -= fwd * speed;
            if (ImGui::IsKeyDown(ImGuiKey_D)) p.camera.pos += right * speed;
            if (ImGui::IsKeyDown(ImGuiKey_A)) p.camera.pos -= right * speed;
            if (ImGui::IsKeyDown(ImGuiKey_E)) p.camera.pos.z += speed;
            if (ImGui::IsKeyDown(ImGuiKey_Q)) p.camera.pos.z -= speed;
        }
        if (io.MouseWheel != 0.0f)
            p.camera.pos += p.camera.forward() * (io.MouseWheel * 120.0f);
    } else {
        const bool pan = ImGui::IsMouseDragging(ImGuiMouseButton_Middle, 0.0f) ||
                         (ImGui::IsMouseDragging(ImGuiMouseButton_Left, 0.0f) &&
                          ImGui::IsKeyDown(ImGuiKey_Space));
        if (pan)
            p.camera.panOrtho({io.MouseDelta.x, io.MouseDelta.y}, 1.0f,
                              {static_cast<int>(p.contentSize.x),
                               static_cast<int>(p.contentSize.y)});
        if (io.MouseWheel != 0.0f) {
            const ImVec2 m = ImGui::GetMousePos();
            p.camera.zoomOrtho(io.MouseWheel,
                               {m.x - p.contentMin.x, m.y - p.contentMin.y}, 1.0f,
                               {static_cast<int>(p.contentSize.x),
                                static_cast<int>(p.contentSize.y)});
        }
    }

    if (ImGui::IsKeyPressed(ImGuiKey_F) && hasMap()) frameAllViews();

    // Left-click select (no drag) with the Select tool on an editable document.
    if (hasDoc() && tool_ == Tool::Select &&
        ImGui::IsMouseReleased(ImGuiMouseButton_Left) &&
        !ImGui::IsMouseDragPastThreshold(ImGuiMouseButton_Left, 4.0f)) {
        const ImVec2 m = ImGui::GetMousePos();
        pickAt(p, {m.x - p.contentMin.x, m.y - p.contentMin.y}, io.KeyShift);
    }
    if (ImGui::IsKeyPressed(ImGuiKey_Escape) && !selection_.empty()) clearSelection();
    if (ImGui::IsKeyPressed(ImGuiKey_Delete) && !selection_.empty()) {
        // Delete world solids (highest index first). Entity-brush delete later.
        std::vector<int> ws;
        for (const auto& r : selection_)
            if (r.entity < 0) ws.push_back(r.solid);
        std::sort(ws.rbegin(), ws.rend());
        for (int i : ws)
            if (i < static_cast<int>(doc_.worldSolids().size()))
                doc_.worldSolids().erase(doc_.worldSolids().begin() + i);
        doc_.markDirty();
        clearSelection();
        buildAndUpload(meshOpts_);
        status_ = "Deleted " + std::to_string(ws.size()) + " brush(es)";
    }
}

void Editor::pickAt(ViewPanel& p, const glm::vec2& px, bool additive) {
    glm::vec3 ro, rd;
    p.camera.pixelRay(px, p.contentSize, ro, rd);

    map::SolidRef best;
    float bestT = 1e30f;
    auto test = [&](const map::Solid& s, int ent, int idx) {
        float t;
        if (s.valid && map::raySolid(ro, rd, s, t) && t < bestT) {
            bestT = t;
            best = {ent, idx};
        }
    };
    const auto& ws = doc_.worldSolids();
    for (int i = 0; i < static_cast<int>(ws.size()); ++i) test(ws[i], -1, i);
    for (int e = 0; e < static_cast<int>(doc_.entities().size()); ++e) {
        const auto& es = doc_.entities()[e].solids;
        for (int i = 0; i < static_cast<int>(es.size()); ++i) test(es[i], e, i);
    }

    if (!best.valid()) {
        if (!additive) clearSelection();
        return;
    }
    if (additive) {
        auto it = std::find(selection_.begin(), selection_.end(), best);
        if (it != selection_.end())
            selection_.erase(it);
        else
            selection_.push_back(best);
    } else {
        selection_ = {best};
    }
    rebuildSelectionWire();
    status_ = std::to_string(selection_.size()) + " brush(es) selected";
}

void Editor::rebuildSelectionWire() {
    std::vector<glm::vec3> lines;
    for (const auto& r : selection_)
        if (const map::Solid* s = doc_.resolve(r)) {
            auto w = map::solidWire(*s);
            lines.insert(lines.end(), w.begin(), w.end());
        }
    renderer_.setSelectionWire(lines);
}

void Editor::clearSelection() {
    selection_.clear();
    renderer_.setSelectionWire({});
}

void Editor::debugSelectWorldSolid(int i) {
    if (i >= 0 && i < static_cast<int>(doc_.worldSolids().size())) {
        selection_ = {{-1, i}};
        rebuildSelectionWire();
        const map::Solid* s = doc_.resolve(selection_[0]);
        if (s)
            for (auto& v : views_) {
                if (v.kind == ViewKind::Perspective) {
                    v.camera.pos = s->center() - v.camera.forward() * 320.0f;
                } else {
                    v.camera.orthoCenter = s->center();
                }
            }
    }
}

// ---------------------------------------------------------------------------
// Simple mode: Build Kit + Selection
// ---------------------------------------------------------------------------
namespace {

struct KitPiece {
    const char* icon;
    const char* name;
    const char* hint;
};

void kitCards(const KitPiece* pieces, int count, std::string* placing,
              std::string* status) {
    const float avail = ImGui::GetContentRegionAvail().x;
    const float cellW = (avail - 10.0f) * 0.5f;
    for (int i = 0; i < count; ++i) {
        if (i % 2) ImGui::SameLine(0, 10);
        ImGui::PushID(i);
        const bool on = *placing == pieces[i].name;
        ImGui::PushStyleColor(ImGuiCol_Button, on ? pb::ui::col::bg3 : pb::ui::col::bg2);
        ImGui::PushStyleColor(ImGuiCol_Border,
                              on ? pb::ui::col::acc : pb::ui::col::bd);
        if (ImGui::BeginChild("card", ImVec2(cellW, 64),
                              ImGuiChildFlags_Borders | ImGuiChildFlags_FrameStyle)) {
            ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::acc);
            ImGui::TextUnformatted(pieces[i].icon);
            ImGui::PopStyleColor();
            ImGui::SameLine(0, 8);
            ImGui::TextUnformatted(pieces[i].name);
            ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::faint);
            ImGui::TextWrapped("%s", pieces[i].hint);
            ImGui::PopStyleColor();
        }
        ImGui::EndChild();
        if (ImGui::IsItemClicked()) {
            *placing = pieces[i].name;
            *status = std::string("Placing ") + pieces[i].name +
                      " — click in a viewport to drop it.";
        }
        ImGui::PopStyleColor(2);
        ImGui::PopID();
    }
}

}  // namespace

void Editor::drawBuildKit() {
    ImGui::Begin("Build Kit");

    if (pb::ui::fontUiMed) ImGui::PushFont(pb::ui::fontUiMed);
    ImGui::TextUnformatted(hasMap() ? bsp_.name().c_str() : "New map");
    if (pb::ui::fontUiMed) ImGui::PopFont();
    ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::faint);
    ImGui::TextWrapped("Pick a piece, then click in a viewport. Everything snaps to the grid.");
    ImGui::PopStyleColor();
    ImGui::Dummy(ImVec2(0, 4));

    if (ImGui::BeginTabBar("kit", ImGuiTabBarFlags_FittingPolicyResizeDown)) {
        if (ImGui::BeginTabItem(ICON_FA_CUBE "  Shapes")) {
            static const KitPiece shapes[] = {
                {ICON_FA_BORDER_ALL, "Floor", "Walkable ground area"},
                {ICON_FA_SQUARE, "Wall", "Solid cover"},
                {ICON_FA_TABLE_CELLS_LARGE, "Room", "4 walls + floor + ceiling"},
                {ICON_FA_DIAGRAM_PROJECT, "Ramp", "Change height smoothly"},
                {ICON_FA_DRAW_POLYGON, "Route", "Draw a path, get sections"},
                {ICON_FA_GRIP, "Pillar", "Vertical cover"},
            };
            ImGui::Dummy(ImVec2(0, 4));
            kitCards(shapes, IM_ARRAYSIZE(shapes), &placing_, &status_);
            ImGui::EndTabItem();
        }
        if (ImGui::BeginTabItem(ICON_FA_ARROW_POINTER "  Play")) {
            static const KitPiece play[] = {
                {ICON_FA_ARROW_POINTER, "RED spawn", "Team RED respawn room"},
                {ICON_FA_ARROW_POINTER, "BLU spawn", "Team BLU respawn room"},
                {ICON_FA_SQUARE, "Capture point", "Control point + trigger"},
                {ICON_FA_DIAGRAM_PROJECT, "Payload track", "path_track for the cart"},
                {ICON_FA_PLAY, "Resupply", "Regenerate locker"},
                {ICON_FA_LIGHTBULB, "Health / ammo", "Pickup near a route"},
            };
            ImGui::Dummy(ImVec2(0, 4));
            kitCards(play, IM_ARRAYSIZE(play), &placing_, &status_);
            ImGui::EndTabItem();
        }
        if (ImGui::BeginTabItem(ICON_FA_IMAGE "  Props")) {
            ImGui::Dummy(ImVec2(0, 4));
            ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::dim);
            ImGui::TextWrapped(
                "The model browser lands here — pick from the installed TF2 props "
                "and drop them on the grid.");
            ImGui::PopStyleColor();
            ImGui::EndTabItem();
        }
        if (ImGui::BeginTabItem(ICON_FA_LIGHTBULB "  Light")) {
            static const KitPiece lights[] = {
                {ICON_FA_LIGHTBULB, "Point light", "Local glow"},
                {ICON_FA_LIGHTBULB, "Spot light", "Directional cone"},
                {ICON_FA_LIGHTBULB, "Sun / sky", "light_environment"},
            };
            ImGui::Dummy(ImVec2(0, 4));
            kitCards(lights, IM_ARRAYSIZE(lights), &placing_, &status_);
            ImGui::EndTabItem();
        }
        ImGui::EndTabBar();
    }

    ImGui::Dummy(ImVec2(0, 8));
    ImGui::Separator();
    pb::ui::sectionLabel("MAP CHECKLIST");

    auto countClass = [&](const char* cls) {
        int n = 0;
        for (const auto& e : bsp_.entities()) {
            auto it = e.find("classname");
            if (it != e.end() && it->second == cls) ++n;
        }
        return n;
    };
    auto anyClassPrefix = [&](const char* pfx) {
        const size_t n = std::strlen(pfx);
        for (const auto& e : bsp_.entities()) {
            auto it = e.find("classname");
            if (it != e.end() && it->second.compare(0, n, pfx) == 0) return true;
        }
        return false;
    };
    std::string skyname;
    if (const auto* ws = bsp_.worldspawn()) {
        auto it = ws->find("skyname");
        if (it != ws->end()) skyname = it->second;
    }

    struct Row {
        bool ok;
        const char* label;
    };
    const Row rows[] = {
        {countClass("info_player_teamspawn") >= 2 || countClass("info_player_start") >= 1,
         "Spawn points placed"},
        {!skyname.empty(), "Skybox set (seals the map)"},
        {countClass("team_control_point") > 0 || countClass("trigger_capture_area") > 0 ||
             countClass("func_capturezone") > 0,
         "An objective (capture / flag)"},
        {anyClassPrefix("item_health") || anyClassPrefix("item_ammo") ||
             countClass("func_regenerate") > 0,
         "Health and ammo on the routes"},
        {countClass("light") > 0 || countClass("light_environment") > 0 ||
             countClass("light_spot") > 0,
         "Lights in the level"},
    };
    int done = 0;
    for (const Row& r : rows)
        if (r.ok) ++done;
    ImGui::Dummy(ImVec2(0, 2));
    char frac[24];
    std::snprintf(frac, sizeof(frac), "%d / %d", done, (int)IM_ARRAYSIZE(rows));
    ImGui::PushStyleColor(ImGuiCol_PlotHistogram, pb::ui::col::acc);
    ImGui::ProgressBar((float)done / IM_ARRAYSIZE(rows), ImVec2(-1, 6), "");
    ImGui::PopStyleColor();
    ImGui::SameLine();
    ImGui::TextDisabled("%s", frac);
    ImGui::Dummy(ImVec2(0, 4));
    for (const Row& r : rows) {
        ImGui::PushStyleColor(ImGuiCol_Text, r.ok ? pb::ui::col::good : pb::ui::col::faint);
        ImGui::TextUnformatted(r.ok ? ICON_FA_CHECK : ICON_FA_SQUARE);
        ImGui::PopStyleColor();
        ImGui::SameLine(0, 9);
        ImGui::PushStyleColor(ImGuiCol_Text,
                              r.ok ? pb::ui::col::tx : pb::ui::col::dim);
        ImGui::TextUnformatted(r.label);
        ImGui::PopStyleColor();
    }

    ImGui::End();
}

void Editor::drawSelectionPanel() {
    ImGui::Begin("Selection");
    if (!placing_.empty()) {
        if (pb::ui::fontUiMed) ImGui::PushFont(pb::ui::fontUiMed);
        ImGui::Text(ICON_FA_ARROW_POINTER "  Placing %s", placing_.c_str());
        if (pb::ui::fontUiMed) ImGui::PopFont();
        ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::dim);
        ImGui::TextWrapped("Click in a viewport to drop it. Brush placement is coming "
                           "with the editing tools.");
        ImGui::PopStyleColor();
        ImGui::Dummy(ImVec2(0, 6));
        if (ImGui::Button("Cancel", ImVec2(-1, 0))) placing_.clear();
    } else if (hasMap()) {
        pb::ui::sectionLabel("THIS MAP");
        ImGui::Dummy(ImVec2(0, 4));
        const glm::vec3 span = mesh_.playBoundsMax - mesh_.playBoundsMin;
        ImGui::BulletText("%zu entities, %zu props", bsp_.entities().size(),
                          mesh_.props.size());
        ImGui::BulletText("play area  %.0f x %.0f x %.0f", span.x, span.y, span.z);
        ImGui::Dummy(ImVec2(0, 10));
        ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::faint);
        ImGui::TextWrapped("Click something in the map to edit it. Selection and the "
                           "transform gizmo are the next milestone.");
        ImGui::PopStyleColor();
    } else {
        ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::faint);
        ImGui::TextWrapped("Open a .bsp (Ctrl+O) or drag one onto the window to get "
                           "started.");
        ImGui::PopStyleColor();
    }
    ImGui::End();
}

// ---------------------------------------------------------------------------
// Panels
// ---------------------------------------------------------------------------
void Editor::drawOutliner() {
    ImGui::Begin("Contents");
    if (!hasMap()) {
        ImGui::TextDisabled("No map loaded.");
        ImGui::End();
        return;
    }
    ImGui::Text("%s", bsp_.name().c_str());
    ImGui::Separator();
    ImGui::InputTextWithHint("##filter", "filter", outlinerFilter_,
                             sizeof(outlinerFilter_));
    std::string needle = outlinerFilter_;
    std::transform(needle.begin(), needle.end(), needle.begin(), ::tolower);
    auto pass = [&](const std::string& s) {
        if (needle.empty()) return true;
        std::string t = s;
        std::transform(t.begin(), t.end(), t.begin(), ::tolower);
        return t.find(needle) != std::string::npos;
    };

    if (ImGui::CollapsingHeader("World geometry", ImGuiTreeNodeFlags_DefaultOpen)) {
        ImGui::BulletText("%zu faces drawn (%zu skipped)", mesh_.drawnFaces,
                          mesh_.skippedFaces);
        ImGui::BulletText("%zu draw batches", mesh_.batches.size());
        ImGui::BulletText("bounds  %.0f %.0f %.0f  ->  %.0f %.0f %.0f", mesh_.boundsMin.x,
                          mesh_.boundsMin.y, mesh_.boundsMin.z, mesh_.boundsMax.x,
                          mesh_.boundsMax.y, mesh_.boundsMax.z);
    }
    if (ImGui::CollapsingHeader("Static props", ImGuiTreeNodeFlags_DefaultOpen)) {
        ImGui::Text("%zu props", mesh_.props.size());
        if (ImGui::BeginChild("props", ImVec2(0, 180))) {
            for (size_t i = 0; i < mesh_.props.size(); ++i) {
                const auto& pr = mesh_.props[i];
                if (!pass(pr.model)) continue;
                ImGui::PushID(static_cast<int>(i));
                if (ImGui::Selectable(pr.model.empty() ? "(prop)" : pr.model.c_str())) {
                    for (auto& v : views_) {
                        if (v.kind == ViewKind::Perspective)
                            v.camera.pos = pr.pos - v.camera.forward() * 200.0f;
                        else
                            v.camera.orthoCenter = pr.pos;
                    }
                }
                ImGui::PopID();
            }
        }
        ImGui::EndChild();
    }
    if (ImGui::CollapsingHeader("Entities", ImGuiTreeNodeFlags_DefaultOpen)) {
        if (ImGui::BeginChild("ents", ImVec2(0, 220))) {
            for (size_t i = 0; i < mesh_.pointEntities.size(); ++i) {
                const auto& e = mesh_.pointEntities[i];
                std::string label = e.classname;
                if (!e.targetname.empty()) label += "  [" + e.targetname + "]";
                if (!pass(label)) continue;
                ImGui::PushID(static_cast<int>(i + 100000));
                if (ImGui::Selectable(label.c_str())) {
                    for (auto& v : views_) {
                        if (v.kind == ViewKind::Perspective)
                            v.camera.pos = e.pos - v.camera.forward() * 200.0f;
                        else
                            v.camera.orthoCenter = e.pos;
                    }
                }
                ImGui::PopID();
            }
        }
        ImGui::EndChild();
    }
    ImGui::End();
}

void Editor::drawTextureBrowser() {
    ImGui::Begin("Textures");
    if (!sourceFs_.ready()) {
        ImGui::TextDisabled("No game content mounted.");
        ImGui::End();
        return;
    }
    ImGui::InputTextWithHint("##texfilter", "filter materials in map", textureFilter_,
                             sizeof(textureFilter_));
    std::string needle = textureFilter_;
    std::transform(needle.begin(), needle.end(), needle.begin(), ::tolower);

    if (!hasMap()) {
        ImGui::TextDisabled("Load a map to see its textures.");
        ImGui::End();
        return;
    }

    const float cell = 96.0f;
    const float avail = ImGui::GetContentRegionAvail().x;
    const int cols = std::max(1, static_cast<int>(avail / (cell + 8.0f)));
    ImGui::Text("%zu materials", mesh_.batches.size());
    if (ImGui::BeginChild("texgrid")) {
        int col = 0;
        for (const auto& b : mesh_.batches) {
            if (!needle.empty()) {
                std::string t = b.material;
                std::transform(t.begin(), t.end(), t.begin(), ::tolower);
                if (t.find(needle) == std::string::npos) continue;
            }
            const auto& info = materials_.get(b.material);
            ImGui::BeginGroup();
            ImGui::Image(static_cast<ImTextureID>(static_cast<intptr_t>(info.texture)),
                         ImVec2(cell, cell));
            std::string shortName = b.material;
            const size_t slash = shortName.find_last_of('/');
            if (slash != std::string::npos) shortName = shortName.substr(slash + 1);
            ImGui::PushTextWrapPos(ImGui::GetCursorPos().x + cell);
            ImGui::TextWrapped("%s", shortName.c_str());
            ImGui::PopTextWrapPos();
            ImGui::EndGroup();
            if (ImGui::IsItemHovered())
                ImGui::SetTooltip("%s\n%dx%d%s%s", b.material.c_str(), info.width,
                                  info.height, info.found ? "" : "  (vmt not found)",
                                  info.tool ? "  [tool]" : "");
            if (++col % cols != 0) ImGui::SameLine();
        }
    }
    ImGui::EndChild();
    ImGui::End();
}

void Editor::drawMaterialList() {
    ImGui::Begin("Materials");
    if (!hasMap()) {
        ImGui::TextDisabled("No map loaded.");
        ImGui::End();
        return;
    }
    ImGui::InputTextWithHint("##matfilter", "filter", materialFilter_,
                             sizeof(materialFilter_));
    std::string needle = materialFilter_;
    std::transform(needle.begin(), needle.end(), needle.begin(), ::tolower);
    ImGui::Separator();
    ImGui::Text("%zu materials in view", mesh_.batches.size());
    if (ImGui::BeginChild("matlist")) {
        for (const auto& b : mesh_.batches) {
            if (!needle.empty()) {
                std::string t = b.material;
                std::transform(t.begin(), t.end(), t.begin(), ::tolower);
                if (t.find(needle) == std::string::npos) continue;
            }
            ImGui::Selectable(b.material.empty() ? "(unnamed)" : b.material.c_str());
            if (ImGui::IsItemHovered())
                ImGui::SetTooltip("%u triangles%s", b.indexCount / 3,
                                  b.translucent ? "  (translucent)" : "");
        }
    }
    ImGui::EndChild();
    ImGui::End();
}

void Editor::drawEntityCatalog() {
    ImGui::Begin("Entities");
    if (!hasMap()) {
        ImGui::TextDisabled("No map loaded.");
        ImGui::End();
        return;
    }
    // Count classes.
    std::vector<std::pair<std::string, int>> counts;
    for (const auto& ent : bsp_.entities()) {
        auto it = ent.find("classname");
        if (it == ent.end()) continue;
        auto f = std::find_if(counts.begin(), counts.end(),
                              [&](auto& c) { return c.first == it->second; });
        if (f == counts.end())
            counts.emplace_back(it->second, 1);
        else
            f->second++;
    }
    std::sort(counts.begin(), counts.end(),
              [](auto& a, auto& b) { return a.second > b.second; });
    ImGui::Text("%zu entities, %zu classes", bsp_.entities().size(), counts.size());
    ImGui::Separator();
    if (ImGui::BeginTable("classes", 2,
                          ImGuiTableFlags_RowBg | ImGuiTableFlags_ScrollY |
                              ImGuiTableFlags_Borders)) {
        ImGui::TableSetupColumn("class");
        ImGui::TableSetupColumn("count", ImGuiTableColumnFlags_WidthFixed, 60.0f);
        ImGui::TableHeadersRow();
        for (auto& c : counts) {
            ImGui::TableNextRow();
            ImGui::TableNextColumn();
            ImGui::TextUnformatted(c.first.c_str());
            ImGui::TableNextColumn();
            ImGui::Text("%d", c.second);
        }
        ImGui::EndTable();
    }
    ImGui::End();
}

void Editor::drawStatusBar() {
    ImGuiViewport* vp = ImGui::GetMainViewport();
    const float h = ImGui::GetFrameHeight();
    ImGui::SetNextWindowPos(ImVec2(vp->WorkPos.x, vp->WorkPos.y + vp->WorkSize.y - h));
    ImGui::SetNextWindowSize(ImVec2(vp->WorkSize.x, h));
    ImGuiWindowFlags flags = ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_NoDocking |
                             ImGuiWindowFlags_NoNav | ImGuiWindowFlags_NoMove |
                             ImGuiWindowFlags_NoSavedSettings;
    ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, 0.0f);
    ImGui::PushStyleColor(ImGuiCol_WindowBg, pb::ui::col::bg1);
    if (ImGui::Begin("##status", nullptr, flags)) {
        const Camera& c3d = views_[0].camera;
        ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::acc);
        ImGui::TextUnformatted(mode_ == Mode::Simple ? "Simple" : "Pro");
        ImGui::PopStyleColor();
        ImGui::SameLine(0, 14);
        ImGui::Text("%s", status_.c_str());
        ImGui::SameLine(0, 18);
        if (pb::ui::fontMono) ImGui::PushFont(pb::ui::fontMono);
        ImGui::TextDisabled("cam %.0f %.0f %.0f  yaw %.0f  pitch %.0f", c3d.pos.x,
                            c3d.pos.y, c3d.pos.z, c3d.yawDeg, c3d.pitchDeg);
        if (hasMap()) {
            ImGui::SameLine(0, 18);
            ImGui::TextDisabled("%zu tris", mesh_.indices.size() / 3);
        }
        if (pb::ui::fontMono) ImGui::PopFont();
    }
    ImGui::End();
    ImGui::PopStyleColor();
    ImGui::PopStyleVar();
}

// ---------------------------------------------------------------------------
// Offscreen screenshot
// ---------------------------------------------------------------------------
bool Editor::renderToImage(ViewKind view, int w, int h, std::vector<uint8_t>& rgba) {
    Camera cam;
    cam.kind = view;
    if (hasMap()) cam.frameBounds(mesh_.playBoundsMin, mesh_.playBoundsMax);

    Framebuffer fb;
    fb.resize(w, h);
    fb.bind();
    renderer_.renderView(cam, w, h, settings_);

    rgba.assign(static_cast<size_t>(w) * h * 4, 0);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, rgba.data());
    Framebuffer::unbind();

    // Flip vertically so row 0 is the top.
    const size_t rowBytes = static_cast<size_t>(w) * 4;
    std::vector<uint8_t> tmp(rowBytes);
    for (int y = 0; y < h / 2; ++y) {
        uint8_t* a = rgba.data() + y * rowBytes;
        uint8_t* b = rgba.data() + (h - 1 - y) * rowBytes;
        std::memcpy(tmp.data(), a, rowBytes);
        std::memcpy(a, b, rowBytes);
        std::memcpy(b, tmp.data(), rowBytes);
    }
    return true;
}

bool Editor::renderQuadToImage(int w, int h, std::vector<uint8_t>& rgba) {
    for (auto& v : views_) v.camera.kind = v.kind;
    if (hasMap()) frameAllViews();

    Framebuffer fb;
    fb.resize(w, h);
    fb.bind();
    glDisable(GL_SCISSOR_TEST);
    glViewport(0, 0, w, h);
    glClearColor(0.05f, 0.05f, 0.06f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    const int hw = w / 2, hh = h / 2;
    const int gap = 1;
    // Match the on-screen dock order: 3D top-left, Top top-right,
    // Front bottom-left, Side bottom-right. FBO origin is bottom-left.
    struct Q {
        int idx, x, y;
    } quads[4] = {
        {0, 0, hh + gap},        // 3D  (top-left)
        {1, hw + gap, hh + gap}, // Top (top-right)
        {2, 0, 0},               // Front (bottom-left)
        {3, hw + gap, 0},        // Side (bottom-right)
    };
    for (const Q& q : quads)
        renderer_.renderView(views_[q.idx].camera, hw - gap, hh - gap, settings_, q.x,
                             q.y);

    rgba.assign(static_cast<size_t>(w) * h * 4, 0);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, rgba.data());
    Framebuffer::unbind();

    const size_t rowBytes = static_cast<size_t>(w) * 4;
    std::vector<uint8_t> tmp(rowBytes);
    for (int y = 0; y < h / 2; ++y) {
        uint8_t* a = rgba.data() + y * rowBytes;
        uint8_t* b = rgba.data() + (h - 1 - y) * rowBytes;
        std::memcpy(tmp.data(), a, rowBytes);
        std::memcpy(a, b, rowBytes);
        std::memcpy(b, tmp.data(), rowBytes);
    }
    return true;
}

}  // namespace pb
