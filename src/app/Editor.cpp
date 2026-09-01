#include "app/Editor.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <initializer_list>
#include <unordered_map>
#include <utility>

#include <imgui.h>
#include <imgui_internal.h>
#include <ImGuizmo.h>

#include <glm/gtc/matrix_transform.hpp>

#include "IconsFontAwesome6.h"
#include "app/PropWidgets.h"
#include "app/Ui.h"
#include "core/File.h"
#include "core/Log.h"
#include "gpu/Gl.h"
#include "decompile/BspSource.h"
#include <stb_image_write.h>

#include "import/ModelImport.h"
#include "import/ObjModel.h"
#include "map/MapMesh.h"
#include "publish/Workshop.h"
#include "map/Raycast.h"
#include "model/StudioModel.h"
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
    modelThumbs_.init(160);
    loadFgd();

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
    if (decompileThread_.joinable()) decompileThread_.join();
    prefs_.save();
    renderer_.clearWorld();
}

void Editor::attachSettings(Settings s, float effectiveScale) {
    prefs_ = std::move(s);
    uiScale_ = effectiveScale;
    showWelcome_ = prefs_.showWelcome;
    applyPrefs();
}

void Editor::applyPrefs() {
    gridSize_ = std::clamp(prefs_.gridSize, 1, 4096);
    snap_ = prefs_.snap;
    flySpeed_ = prefs_.flySpeed;
    autosaveOn_ = prefs_.autosave;
    autosaveMins_ = prefs_.autosaveMins;
    settings_.shadeMode = static_cast<ShadeMode>(std::clamp(prefs_.shadeMode, 0, 3));
    settings_.showGrid = prefs_.showGrid;
    settings_.showProps = prefs_.showProps;
    settings_.showPointEntities = prefs_.showPointEntities;
    settings_.wireOverlay = prefs_.wireOverlay;
    settings_.exposure = prefs_.exposure;
    meshOpts_.lightmapGain = prefs_.lightmapGain;
    meshOpts_.bakeProps = prefs_.bakeProps;
    suppressAutoDecompile_ = !prefs_.autoDecompile;
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

    if (ext == ".pbproj") {
        openProject(path);
        return hasDoc();
    }

    if (ext == ".vmf") {
        std::string err;
        if (!doc_.loadVmf(path, &err)) {
            status_ = "Failed to load VMF: " + err;
            return false;
        }
        bsp_ = BspFile{};
        history_.reset(doc_);
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

    // Q1: auto-decompile to editable brushes in the background.
    if (!suppressAutoDecompile_ && !decompileRunning_ &&
        decompile::available(executableDir())) {
        decompileRunning_ = true;
        decompileDone_ = false;
        decompileVmf_.clear();
        decompileErr_.clear();
        const std::string exeDir = executableDir();
        const std::string bsp = path;
        status_ = bsp_.name() + " — decompiling to editable brushes…";
        decompileThread_ = std::thread([this, exeDir, bsp] {
            std::string err2;
            decompileVmf_ = decompile::bspToVmf(exeDir, bsp, &err2);
            decompileErr_ = err2;
            decompileDone_ = true;
        });
    }
    return true;
}

void Editor::pollDecompile() {
    if (!decompileDone_) return;
    if (decompileThread_.joinable()) decompileThread_.join();
    decompileDone_ = false;
    decompileRunning_ = false;

    if (decompileVmf_.empty()) {
        status_ = "Decompile failed: " + decompileErr_ + " (viewing the raw BSP)";
        return;
    }
    std::string err;
    if (doc_.loadVmf(decompileVmf_, &err)) {
        history_.reset(doc_);
        clearSelection();
        buildAndUpload(meshOpts_);
        status_ = doc_.name() + " — editable: " +
                  std::to_string(doc_.worldSolids().size()) + " brushes, " +
                  std::to_string(doc_.entities().size()) + " entities  "
                  "(decompile is approximate)";
    } else {
        status_ = "Loaded decompile but parse failed: " + err;
    }
}

void Editor::buildAndUpload(const MeshBuildOptions& opts) {
    if (doc_.active()) {
        auto modelForClass = [this](const std::string& cls) -> std::string {
            const fgd::EntityClass* ec = fgd_.flattened(cls);
            return ec ? ec->studioModel : std::string();
        };
        mesh_ = map::buildDocMesh(doc_, materials_, modelForClass);
        if (opts.bakeProps) model::bakePropModels(mesh_, sourceFs_);
    } else {
        mesh_ = buildWorldMesh(bsp_, opts);
        if (opts.bakeProps) model::bakePropModels(mesh_, sourceFs_);
    }

    // Baked prop geometry is appended after the mesh computes its bounds; grow
    // the framing bounds to include it so a lone dropped prop isn't a speck.
    if (doc_.active() && !mesh_.vertices.empty()) {
        glm::vec3 mn(1e30f), mx(-1e30f);
        for (const auto& v : mesh_.vertices) {
            mn = glm::min(mn, v.pos);
            mx = glm::max(mx, v.pos);
        }
        if (mn.x <= mx.x) {
            mesh_.boundsMin = glm::min(mesh_.boundsMin, mn);
            mesh_.boundsMax = glm::max(mesh_.boundsMax, mx);
            mesh_.playBoundsMin = glm::min(mesh_.playBoundsMin, mn - glm::vec3(64));
            mesh_.playBoundsMax = glm::max(mesh_.playBoundsMax, mx + glm::vec3(64));
        }
    }

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
    pollDecompile();
    compiler_.poll();
    ImGuizmo::BeginFrame();
    docMeshDirty_ = false;
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

    // ---- global keyboard shortcuts -------------------------------------------
    // Raw key state (not ImGui's focus-routed chords) so they fire no matter
    // which panel has focus. Suppressed only while typing in a text field.
    {
        ImGuiIO& io = ImGui::GetIO();
        const bool ctrl = io.KeyCtrl;
        const bool shift = io.KeyShift;
        const bool typing = io.WantTextInput;
        auto tap = [&](ImGuiKey k) { return ImGui::IsKeyPressed(k, false); };
        auto ck = [&](ImGuiKey k) { return !typing && ctrl && tap(k); };
        auto pk = [&](ImGuiKey k) { return !typing && !ctrl && tap(k); };

        if (ck(ImGuiKey_O)) promptOpenMap();
        if (ck(ImGuiKey_Z)) { shift ? redo() : undo(); }
        if (ck(ImGuiKey_Y)) redo();
        if (ck(ImGuiKey_S) && hasDoc()) saveMap(shift);  // Ctrl+Shift+S = Save As
        if (ck(ImGuiKey_K)) showPalette_ = true;
        if (ck(ImGuiKey_C)) copySelection();
        if (ck(ImGuiKey_V)) pasteClipboard();
        if (ck(ImGuiKey_X)) { copySelection(); deleteSelection(); }
        if (ck(ImGuiKey_D)) duplicateSelection();
        if (ck(ImGuiKey_A) && hasDoc()) {
            selection_.clear();
            for (int i = 0; i < (int)doc_.worldSolids().size(); ++i)
                selection_.push_back({-1, i});
            rebuildSelectionWire();
            status_ = "Selected all brushes";
        }
        if (ck(ImGuiKey_B) && hasDoc()) {
            showCompile_ = true;
            if (!compiler_.running()) startCompile();
        }
        if (pk(ImGuiKey_Delete) || pk(ImGuiKey_Backspace)) deleteSelection();
        if (pk(ImGuiKey_F) && hasMap()) frameAllViews();
        if (pk(ImGuiKey_F1)) showKeys_ = !showKeys_;
        if (!typing && tap(ImGuiKey_Escape)) {
            if (!placing_.empty()) { placing_.clear(); roadPts_.clear(); roadActive_ = false; }
            else clearSelection();
        }
        if (pk(ImGuiKey_LeftBracket)) rotateSelection(2, shift ? 15.0f : -15.0f);
        if (pk(ImGuiKey_RightBracket)) rotateSelection(2, shift ? -15.0f : 15.0f);
        // Pro gizmo mode: W move / E rotate / R scale — only with a selection
        // and not while RMB-flying (so WASD nav isn't hijacked).
        if (mode_ == Mode::Pro && !typing && !ctrl && !selection_.empty() &&
            !ImGui::IsMouseDown(ImGuiMouseButton_Right)) {
            if (tap(ImGuiKey_W)) gizmoMode_ = 0;
            if (tap(ImGuiKey_E)) gizmoMode_ = 1;
            if (tap(ImGuiKey_R)) gizmoMode_ = 2;
        }
    }

    autosaveTick();
    drawKeysOverlay();
    drawSettingsWindow();

    if (mode_ == Mode::Simple) {
        drawBuildKit();
        drawSelectionPanel();
    } else {
        drawProperties();
        drawOutliner();
        drawTextureBrowser();
        drawModelBrowser();
        drawMaterialList();
        drawEntityCatalog();
        drawHistoryPanel();
        drawMapCheckPanel();
        drawLogPanel();
        drawPrefabPanel();
        drawVisgroupsPanel();
    }
    for (auto& v : views_) drawViewportPanel(v);

    // Manual drag-and-drop: a menu card set dragPlace_ while being dragged;
    // when the mouse is released over a viewport, drop it there. (ImGui's own
    // drag-drop target proved unreliable across docked windows here.)
    if (!dragPlace_.empty() && !ImGui::IsMouseDown(ImGuiMouseButton_Left)) {
        const ImVec2 m = ImGui::GetMousePos();
        for (auto& v : views_) {
            const glm::vec2 mn = v.contentMin, sz = v.contentSize;
            if (sz.x > 1 && m.x >= mn.x && m.x < mn.x + sz.x && m.y >= mn.y &&
                m.y < mn.y + sz.y) {
                const glm::vec3 at = dropWorldPoint(v, m);
                PB_INFO("drop '%s' @ (%.0f %.0f %.0f)", dragPlace_.c_str(), at.x, at.y,
                        at.z);
                placeFromPayload(dragPlace_, at);
                break;
            }
        }
        dragPlace_.clear();
    }

    drawStatusBar();
    drawCompileWindow();
    drawModelImportDialog();
    drawWorkshopWindow();
    drawCommandPalette();
    drawWelcome();

    if (focusPanelFrames_ > 0) {
        ImGui::SetWindowFocus(focusPanel_.c_str());
        --focusPanelFrames_;
    }

    // Live preview while dragging (gizmo, bbox handles, body-move, sub-object).
    // History is recorded once on release.
    if (docMeshDirty_ &&
        (gizmoUsing_ || resizeHandle_ >= 0 || moveDrag_ != 0 || subDragging_)) {
        // On big maps skip the prop re-bake each drag frame — the props snap
        // back on release. Small maps rebuild everything (imperceptible).
        MeshBuildOptions o = meshOpts_;
        if (mesh_.props.size() > 40) o.bakeProps = false;
        buildAndUpload(o);
        rebuildSelectionWire();
    }
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
        ImGui::DockBuilderDockWindow("Properties", left);
        ImGui::DockBuilderDockWindow("Contents", left);
        ImGui::DockBuilderDockWindow("Textures", left);
        ImGui::DockBuilderDockWindow("Models", left);
        ImGui::DockBuilderDockWindow("Materials", left);
        ImGui::DockBuilderDockWindow("Entities", left);
        ImGui::DockBuilderDockWindow("History", left);
        ImGui::DockBuilderDockWindow("Map Check", left);
        ImGui::DockBuilderDockWindow("Log", left);
        ImGui::DockBuilderDockWindow("Prefabs", left);
        ImGui::DockBuilderDockWindow("Visgroups", left);
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
    const float row = ImGui::GetFrameHeight();
    const float barH = std::round(row + dp(18.0f));
    ImGui::PushStyleColor(ImGuiCol_ChildBg, col::bg1);
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(dp(12.0f), 0));
    ImGui::BeginChild("##topbar", ImVec2(0, barH), ImGuiChildFlags_None,
                      ImGuiWindowFlags_NoScrollbar | ImGuiWindowFlags_NoScrollWithMouse);
    ImGui::PopStyleVar();

    ImGui::SetCursorPosY((barH - row) * 0.5f);

    // Brand
    ImGui::PushStyleColor(ImGuiCol_Text, col::acc);
    if (fontBig) ImGui::PushFont(fontBig);
    ImGui::TextUnformatted(ICON_FA_CUBES);
    if (fontBig) ImGui::PopFont();
    ImGui::PopStyleColor();
    ImGui::SameLine(0, dp(8.0f));
    if (fontUiMed) ImGui::PushFont(fontUiMed);
    ImGui::SetCursorPosY((barH - ImGui::GetTextLineHeight()) * 0.5f);
    ImGui::TextUnformatted("Pootis Builder");
    if (fontUiMed) ImGui::PopFont();

    ImGui::SameLine(0, dp(18.0f));
    ImGui::SetCursorPosY((barH - row) * 0.5f);
    if (toolButton(ICON_FA_FOLDER_OPEN "  Open", false, "Open a .bsp  (Ctrl+O)"))
        promptOpenMap();
    ImGui::SameLine(0, dp(2.0f));
    if (toolButton(ICON_FA_DOWNLOAD "  Import")) ImGui::OpenPopup("importMenu");
    if (ImGui::BeginPopup("importMenu")) {
        if (ImGui::MenuItem(ICON_FA_MAP "  Map  (.bsp / .vmf)")) promptOpenMap();
        if (ImGui::MenuItem(ICON_FA_CUBE "  3D model  (.obj)")) openModelImport();
        ImGui::EndPopup();
    }
    ImGui::SameLine(0, dp(2.0f));
    if (toolButton(ICON_FA_FLOPPY_DISK "  Save", false,
                   "Save the map to .vmf  (Ctrl+S,  Ctrl+Shift+S = Save As)")) {
        if (hasDoc())
            saveMap(ImGui::GetIO().KeyShift);
        else
            status_ = "Open or start a map first.";
    }

    // Simple / Pro
    ImGui::SameLine(0, dp(18.0f));
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
        ImGui::SameLine(0, dp(14.0f));
        ImGui::SetCursorPosY((barH - row) * 0.5f);
        const char* const tools[] = {ICON_FA_ARROW_POINTER, ICON_FA_CUBE,
                                     ICON_FA_BEZIER_CURVE,   ICON_FA_SCISSORS,
                                     ICON_FA_IMAGE,          ICON_FA_LIGHTBULB};
        int r = segmented("tool", tools, 6, static_cast<int>(tool_), row);
        if (r >= 0 && r != static_cast<int>(tool_)) {
            tool_ = static_cast<Tool>(r);
            handlesDirty_ = true;
            subDragging_ = false;
        }
        if (ImGui::IsItemHovered())
            ImGui::SetTooltip("Select / Block / Vertex / Clip / Texture / Entity");

        if (tool_ == Tool::Vertex) {
            ImGui::SameLine(0, dp(10.0f));
            ImGui::SetCursorPosY((barH - row) * 0.5f);
            const char* const subs[] = {ICON_FA_CIRCLE_DOT "  Vertex",
                                        ICON_FA_GRIP_LINES "  Edge",
                                        ICON_FA_SQUARE "  Face"};
            int sr = segmented("submode", subs, 3, static_cast<int>(subMode_), row);
            if (sr >= 0 && sr != static_cast<int>(subMode_)) {
                subMode_ = static_cast<SubMode>(sr);
                handlesDirty_ = true;
                subDragging_ = false;
            }
        }
    }

    // Right cluster — measure the buttons so it never overlaps the left side.
    char gridLabel[48];
    std::snprintf(gridLabel, sizeof(gridLabel), ICON_FA_TABLE_CELLS "  Grid %d", gridSize_);
    const char* snapLabel = snap_ ? ICON_FA_CHECK "  Snap" : ICON_FA_XMARK "  Snap";
    auto bw = [&](const char* s) {
        return ImGui::CalcTextSize(s, nullptr, true).x +
               ImGui::GetStyle().FramePadding.x * 2.0f;
    };
    const float gap = dp(2.0f), gap2 = dp(8.0f);
    const float rightW = bw(gridLabel) + gap + bw(snapLabel) + gap + bw(ICON_FA_BARS) +
                         gap2 + bw(ICON_FA_CLOUD_ARROW_UP "  Publish") + gap2 +
                         bw(ICON_FA_PLAY "  Build & play") + dp(6.0f);
    ImGui::SameLine();
    const float curX = ImGui::GetCursorPosX();
    ImGui::SetCursorPosX(std::max(curX + dp(12.0f),
                                  ImGui::GetWindowWidth() - rightW));
    ImGui::SetCursorPosY((barH - row) * 0.5f);

    if (toolButton(gridLabel)) ImGui::OpenPopup("##gridpop");
    if (ImGui::BeginPopup("##gridpop")) {
        for (int g : {1, 2, 4, 8, 16, 32, 64, 128, 256, 512}) {
            char b[16];
            std::snprintf(b, sizeof(b), "%d", g);
            if (ImGui::Selectable(b, g == gridSize_)) gridSize_ = g;
        }
        ImGui::EndPopup();
    }
    ImGui::SameLine(0, gap);
    if (toolButton(snapLabel, snap_)) snap_ = !snap_;

    ImGui::SameLine(0, gap);
    if (toolButton(ICON_FA_GEAR, showSettings_, "Options")) showSettings_ = !showSettings_;

    ImGui::SameLine(0, gap);
    if (toolButton(ICON_FA_BARS)) ImGui::OpenPopup("##viewmenu");
    drawViewMenuPopup();

    ImGui::SameLine(0, gap2);
    if (toolButton(ICON_FA_CLOUD_ARROW_UP "  Publish", showWorkshop_,
                   "Publish the map to the Steam Workshop")) {
        showWorkshop_ = !showWorkshop_;
        if (showWorkshop_ && wsItem_.title.empty() && hasDoc())
            wsItem_.title = doc_.name();
    }

    ImGui::SameLine(0, gap2);
    ImGui::PushStyleColor(ImGuiCol_Button, col::bg2);
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, col::bg3);
    ImGui::PushStyleColor(ImGuiCol_Text, col::acc);
    if (ImGui::Button(ICON_FA_PLAY "  Build & play", ImVec2(0, row))) {
        showCompile_ = true;
        if (!compiler_.running() && hasDoc()) startCompile();
    }
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
    if (ImGui::MenuItem(ICON_FA_GEAR "  Options…")) showSettings_ = true;
    if (ImGui::MenuItem(ICON_FA_KEYBOARD "  Keyboard shortcuts", "F1"))
        showKeys_ = true;
    ImGui::Separator();
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
    if (ImGui::BeginMenu(ICON_FA_WINDOW_RESTORE "  Panels")) {
        if (ImGui::MenuItem("History")) { ImGui::SetWindowFocus("History"); }
        if (ImGui::MenuItem("Map Check")) { ImGui::SetWindowFocus("Map Check"); runMapCheck(); }
        if (ImGui::MenuItem("Command palette", "Ctrl+K")) showPalette_ = true;
        ImGui::EndMenu();
    }
    if (ImGui::BeginMenu(ICON_FA_FLOPPY_DISK "  Autosave")) {
        ImGui::MenuItem("Enabled", nullptr, &autosaveOn_);
        ImGui::SetNextItemWidth(140);
        ImGui::SliderFloat("every (min)", &autosaveMins_, 1.0f, 30.0f, "%.0f");
        ImGui::TextDisabled("writes <map>.autosave.vmf + rolling .bak1-3 on save");
        ImGui::EndMenu();
    }
    if (ImGui::BeginMenu(ICON_FA_FOLDER_TREE "  Project (.pbproj)")) {
        if (ImGui::MenuItem("Save project", "", false, hasDoc())) saveProject(false);
        if (ImGui::MenuItem("Save project as…", "", false, hasDoc())) saveProject(true);
        if (ImGui::MenuItem("Open project…")) {
            const std::string p =
                openFileDialog("Open project", "Pootis project\0*.pbproj\0All\0*.*\0");
            if (!p.empty()) openProject(p);
        }
        ImGui::TextDisabled("bundles the vmf + cordon + camera bookmarks +");
        ImGui::TextDisabled("compile settings + custom-content list");
        ImGui::EndMenu();
    }
    if (ImGui::BeginMenu(ICON_FA_VECTOR_SQUARE "  Cordon")) {
        ImGui::MenuItem("Cordon on (compile only the box)", nullptr, &cordonOn_);
        ImGui::SetNextItemWidth(200);
        ImGui::DragFloat3("min##cordon", &cordonMin_.x, 4.0f, 0, 0, "%.0f");
        ImGui::SetNextItemWidth(200);
        ImGui::DragFloat3("max##cordon", &cordonMax_.x, 4.0f, 0, 0, "%.0f");
        if (ImGui::MenuItem("Set to selection", nullptr, false, !selection_.empty())) {
            glm::vec3 a(1e30f), b(-1e30f);
            for (const auto& r : selection_)
                if (const map::Solid* s = doc_.resolve(r)) {
                    a = glm::min(a, s->boundsMin);
                    b = glm::max(b, s->boundsMax);
                }
            if (a.x <= b.x) {
                cordonMin_ = a - glm::vec3(16);
                cordonMax_ = b + glm::vec3(16);
            }
        }
        if (ImGui::MenuItem("Set to whole map", nullptr, false, hasDoc())) {
            doc_.bounds(cordonMin_, cordonMax_);
        }
        ImGui::EndMenu();
    }
    if (ImGui::BeginMenu(ICON_FA_CAMERA "  Camera")) {
        Camera& c3d = views_[0].camera;
        ImGui::TextDisabled("bookmarks");
        for (int i = 0; i < 6; ++i) {
            ImGui::PushID(i);
            char lbl[32];
            std::snprintf(lbl, sizeof(lbl), "Slot %d%s", i + 1,
                          camMarks_[i].set ? "" : "  (empty)");
            if (ImGui::MenuItem(lbl, nullptr, false, true)) {
                if (camMarks_[i].set) {
                    c3d.pos = camMarks_[i].pos;
                    c3d.yawDeg = camMarks_[i].yaw;
                    c3d.pitchDeg = camMarks_[i].pitch;
                }
            }
            ImGui::SameLine();
            if (ImGui::SmallButton("set")) {
                camMarks_[i] = {true, c3d.pos, c3d.yawDeg, c3d.pitchDeg};
                status_ = fmt("Camera bookmark %d saved", i + 1);
            }
            ImGui::PopID();
        }
        ImGui::Separator();
        ImGui::TextDisabled("go to coordinate");
        ImGui::SetNextItemWidth(180);
        ImGui::DragFloat3("##goto", &gotoCoord_.x, 1.0f, 0, 0, "%.0f");
        if (ImGui::MenuItem("Jump there")) {
            for (auto& v : views_) {
                if (v.kind == ViewKind::Perspective)
                    v.camera.pos = gotoCoord_ - v.camera.forward() * 300.0f;
                else
                    v.camera.orthoCenter = gotoCoord_;
            }
        }
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
        doc_.newBlank("untitled");
        history_.reset(doc_);
        clearSelection();
        mode_ = Mode::Simple;
        layoutDirty_ = true;
        buildAndUpload(meshOpts_);
        for (auto& v : views_) {
            v.camera = Camera{};
            v.camera.kind = v.kind;
        }
        status_ = "New map — pick a piece from the Build Kit and click the grid.";
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
    const float aspect = h > 0 ? static_cast<float>(w) / h : 1.0f;
    p.contentMin = {ImGui::GetCursorScreenPos().x, ImGui::GetCursorScreenPos().y};
    p.contentSize = {static_cast<float>(w), static_cast<float>(h)};
    p.hovered = ImGui::IsWindowHovered();

    handleViewportInput(p);

    p.fb.resize(w, h);
    p.fb.bind();
    renderer_.renderView(p.camera, w, h, settings_);
    Framebuffer::unbind();

    const ImVec2 imgTL = ImGui::GetCursorScreenPos();
    ImGui::Image(static_cast<ImTextureID>(static_cast<intptr_t>(p.fb.colorTexture())),
                 ImVec2(static_cast<float>(w), static_cast<float>(h)), ImVec2(0, 1),
                 ImVec2(1, 0));

    (void)imgTL;  // drop handling is done manually in frame() via dragPlace_

    drawGizmo(p, aspect);

    // Corner label like Hammer.
    ImVec2 tl(p.contentMin.x, p.contentMin.y);
    ImDrawList* dl = ImGui::GetWindowDrawList();
    dl->AddText(ImVec2(tl.x + 8, tl.y + 6), IM_COL32(210, 210, 210, 200), p.title);

    drawEntityTags(p, aspect, dl);
    drawSubObjectOverlay(p, aspect, dl);
    drawFaceOverlay(p, aspect, dl);
    drawClipOverlay(p, aspect, dl);
    drawSelectionDims(p, aspect, dl);
    drawCordonOverlay(p, aspect, dl);
    drawRoadOverlay(p, aspect, dl);

    if (!hasMap() && p.kind == ViewKind::Perspective) {
        const char* msg = "Open a .bsp  —  File > Open BSP  (Ctrl+O)  or drag one in";
        const ImVec2 ts = ImGui::CalcTextSize(msg);
        dl->AddText(ImVec2(tl.x + (p.contentSize.x - ts.x) * 0.5f,
                           tl.y + (p.contentSize.y - ts.y) * 0.5f),
                    IM_COL32(180, 180, 185, 220), msg);
    }
    ImGui::End();
}

void Editor::drawEntityTags(ViewPanel& p, float aspect, ImDrawList* dl) {
    if (!hasDoc() || doc_.entities().empty()) return;
    // Always show entity markers on a hand-built map; on a big decompile (1000+
    // entities) the 3D view only shows them when "Point entities" is on, or it
    // becomes an unreadable scribble.
    const bool few = doc_.entities().size() <= 200;
    if (p.kind == ViewKind::Perspective && !settings_.showPointEntities && !few)
        return;
    const glm::mat4 vp = p.camera.proj(aspect) * p.camera.view();
    const ImVec2 tl(p.contentMin.x, p.contentMin.y);
    const ImVec2 br(tl.x + p.contentSize.x, tl.y + p.contentSize.y);

    // Project a world point to viewport pixels; ok=false when behind the eye.
    auto project = [&](const glm::vec3& w, bool& ok) -> ImVec2 {
        const glm::vec4 c = vp * glm::vec4(w, 1.0f);
        ok = c.w > 1e-4f;
        if (!ok) return {};
        return ImVec2(tl.x + (c.x / c.w * 0.5f + 0.5f) * p.contentSize.x,
                      tl.y + (1.0f - (c.y / c.w * 0.5f + 0.5f)) * p.contentSize.y);
    };
    auto onScreen = [&](const ImVec2& s) {
        return s.x >= tl.x - 64 && s.x <= br.x + 64 && s.y >= tl.y - 64 &&
               s.y <= br.y + 64;
    };
    auto entColor = [&](const std::string& cls, glm::vec3 def) {
        if (const fgd::EntityClass* ec = fgd_.flattened(cls); ec && ec->hasColor)
            return ec->color;
        return def;
    };

    // --- entity centres, by targetname, for connection lines ------------------
    auto centreOf = [&](const map::MapEntity& e) {
        if (e.solids.empty()) return e.origin;
        glm::vec3 mn(1e30f), mx(-1e30f);
        for (const auto& s : e.solids) {
            mn = glm::min(mn, s.boundsMin);
            mx = glm::max(mx, s.boundsMax);
        }
        return 0.5f * (mn + mx);
    };
    std::vector<glm::vec3> centres(doc_.entities().size());
    std::vector<std::pair<std::string, glm::vec3>> named;
    for (size_t i = 0; i < doc_.entities().size(); ++i) {
        centres[i] = centreOf(doc_.entities()[i]);
        const std::string tn = doc_.entities()[i].kv.get("targetname");
        if (!tn.empty()) named.emplace_back(tn, centres[i]);
    }
    std::unordered_multimap<std::string, int> byName;
    byName.reserve(doc_.entities().size());
    for (int i = 0; i < (int)doc_.entities().size(); ++i) {
        const std::string& tn = doc_.entities()[i].kv.get("targetname");
        if (!tn.empty()) byName.emplace(tn, i);
    }

    // --- I/O connection lines (drawn first, behind the boxes) ----------------
    // On a small map every wire is useful context; on a real (often 1000+
    // entity) decompiled map only the selection's own wiring is drawn, or the
    // view would be an unreadable scribble.
    // `linked` collects every entity index at either end of a drawn connection
    // so the label pass can name just those + the selection.
    std::vector<char> linked(doc_.entities().size(), 0);
    const bool wireAll = doc_.entities().size() <= 60;
    const ImU32 wireCol = IM_COL32(196, 150, 230, 165);
    const ImU32 wireSel = IM_COL32(255, 190, 120, 235);
    for (size_t i = 0; i < doc_.entities().size(); ++i) {
        const auto& e = doc_.entities()[i];
        if (e.connections.empty()) continue;
        if (!wireAll && (int)i != selectedEntity_) continue;
        for (const auto& conn : e.connections) {
            std::string tgt = conn.second;
            const size_t comma = tgt.find_first_of(",\x1b");
            if (comma != std::string::npos) tgt = tgt.substr(0, comma);
            if (tgt.empty()) continue;
            auto range = byName.equal_range(tgt);
            for (auto it = range.first; it != range.second; ++it) {
                const int j = it->second;
                bool a, b;
                const ImVec2 s0 = project(centres[i], a);
                const ImVec2 s1 = project(centres[j], b);
                if (!a || !b) continue;
                const bool hot = (int)i == selectedEntity_ || j == selectedEntity_;
                if (hot) { linked[i] = 1; linked[j] = 1; }
                dl->AddLine(s0, s1, hot ? wireSel : wireCol, hot ? 2.0f : 1.3f);
                const ImVec2 d(s1.x - s0.x, s1.y - s0.y);
                const float L = std::sqrt(d.x * d.x + d.y * d.y);
                if (L > 1.0f) {
                    const ImVec2 u(d.x / L, d.y / L), n(-u.y, u.x);
                    const ImVec2 tip(s1.x - u.x * 13, s1.y - u.y * 13);
                    dl->AddTriangleFilled(s1, ImVec2(tip.x + n.x * 6, tip.y + n.y * 6),
                                          ImVec2(tip.x - n.x * 6, tip.y - n.y * 6),
                                          hot ? wireSel : wireCol);
                }
            }
        }
    }

    // --- path_track / path_corner route lines -------------------------------
    // These chain via the `target` key (not the I/O block), so trace them
    // separately and draw the route as a bright polyline with arrowheads.
    {
        const ImU32 routeCol = IM_COL32(120, 230, 120, 230);
        for (int i = 0; i < (int)doc_.entities().size(); ++i) {
            const std::string& c = doc_.entities()[i].classname;
            if (c != "path_track" && c != "path_corner" && c != "move_rope" &&
                c != "keyframe_rope")
                continue;
            const std::string tgt = doc_.entities()[i].kv.get("target");
            if (tgt.empty()) continue;
            auto range = byName.equal_range(tgt);
            for (auto it = range.first; it != range.second; ++it) {
                bool a, b;
                const ImVec2 s0 = project(centres[i], a);
                const ImVec2 s1 = project(centres[it->second], b);
                if (!a || !b) continue;
                dl->AddLine(s0, s1, routeCol, 2.5f);
                const ImVec2 d(s1.x - s0.x, s1.y - s0.y);
                const float L = std::sqrt(d.x * d.x + d.y * d.y);
                if (L > 12.0f) {
                    const ImVec2 u(d.x / L, d.y / L), n(-u.y, u.x);
                    const ImVec2 mid((s0.x + s1.x) * 0.5f, (s0.y + s1.y) * 0.5f);
                    dl->AddTriangleFilled(
                        ImVec2(mid.x + u.x * 8, mid.y + u.y * 8),
                        ImVec2(mid.x - u.x * 4 + n.x * 5, mid.y - u.y * 4 + n.y * 5),
                        ImVec2(mid.x - u.x * 4 - n.x * 5, mid.y - u.y * 4 - n.y * 5),
                        routeCol);
                }
            }
        }
    }

    // --- per-entity helper box + label -------------------------------------
    // A hand-built map labels every entity; a big decompile labels just the
    // selection + what's wired to it (or the view is an unreadable scribble).
    const bool labelAll = few && selectedEntity_ < 0;
    std::vector<ImVec2> labelled;
    auto crowded = [&](const ImVec2& s) {
        for (const auto& q : labelled)
            if (std::fabs(q.x - s.x) < 60.0f && std::fabs(q.y - s.y) < 15.0f)
                return true;
        return false;
    };

    for (int i = 0; i < static_cast<int>(doc_.entities().size()); ++i) {
        const auto& e = doc_.entities()[i];
        const bool sel = (i == selectedEntity_);
        const bool brush = !e.solids.empty();

        bool ok;
        const ImVec2 sp = project(centres[i], ok);
        if (!ok || !onScreen(sp)) continue;

        const glm::vec3 rgb = entColor(e.classname, glm::vec3(0.90f, 0.82f, 0.62f));
        const ImU32 col =
            sel ? IM_COL32(255, 170, 80, 255)
                : IM_COL32((int)(rgb.r * 255), (int)(rgb.g * 255), (int)(rgb.b * 255),
                           235);

        if (!brush) {
            // Wire box sized from the FGD (fallback to a small cube).
            glm::vec3 mn(-8), mx(8);
            if (const fgd::EntityClass* ec = fgd_.flattened(e.classname);
                ec && ec->hasSize) {
                mn = ec->sizeMin;
                mx = ec->sizeMax;
            }
            const glm::vec3 o = e.origin;
            const glm::vec3 cs[8] = {
                o + glm::vec3(mn.x, mn.y, mn.z), o + glm::vec3(mx.x, mn.y, mn.z),
                o + glm::vec3(mx.x, mx.y, mn.z), o + glm::vec3(mn.x, mx.y, mn.z),
                o + glm::vec3(mn.x, mn.y, mx.z), o + glm::vec3(mx.x, mn.y, mx.z),
                o + glm::vec3(mx.x, mx.y, mx.z), o + glm::vec3(mn.x, mx.y, mx.z)};
            ImVec2 pv[8];
            bool all = true;
            for (int k = 0; k < 8; ++k) {
                bool cok;
                pv[k] = project(cs[k], cok);
                all = all && cok;
            }
            if (all) {
                static const int E[12][2] = {{0, 1}, {1, 2}, {2, 3}, {3, 0},
                                             {4, 5}, {5, 6}, {6, 7}, {7, 4},
                                             {0, 4}, {1, 5}, {2, 6}, {3, 7}};
                const ImU32 boxc = sel ? col
                                       : IM_COL32((int)(rgb.r * 255), (int)(rgb.g * 255),
                                                  (int)(rgb.b * 255), 120);
                for (auto& ed : E)
                    dl->AddLine(pv[ed[0]], pv[ed[1]], boxc, sel ? 2.0f : 1.0f);
            }

            // Facing tick from angles "P Y R" (selected entity only).
            const std::string ang = sel ? e.kv.get("angles") : std::string();
            if (!ang.empty()) {
                float pit = 0, yaw = 0, rol = 0;
                std::sscanf(ang.c_str(), "%f %f %f", &pit, &yaw, &rol);
                const float cy = std::cos(yaw * kDeg2Rad), sy = std::sin(yaw * kDeg2Rad);
                const float cp = std::cos(pit * kDeg2Rad), spp = std::sin(pit * kDeg2Rad);
                const glm::vec3 dir(cp * cy, cp * sy, -spp);
                bool eok;
                const ImVec2 e1 = project(e.origin + dir * 40.0f, eok);
                if (eok) dl->AddLine(sp, e1, col, sel ? 2.0f : 1.5f);
            }
        }

        // Clear diamond marker (bigger + outlined so model-less entities like
        // path_track / lights actually read in the 3D view).
        if (!brush) {
            const float rr = sel ? 8.0f : 6.0f;
            const ImVec2 dpts[4] = {{sp.x, sp.y - rr}, {sp.x + rr, sp.y},
                                    {sp.x, sp.y + rr}, {sp.x - rr, sp.y}};
            dl->AddConvexPolyFilled(dpts, 4, col);
            dl->AddPolyline(dpts, 4, IM_COL32(15, 15, 18, 235), ImDrawFlags_Closed,
                            1.6f);
        } else {
            dl->AddRectFilled(ImVec2(sp.x - 3, sp.y - 3), ImVec2(sp.x + 3, sp.y + 3),
                              col);
        }
        if (sel)
            dl->AddRect(ImVec2(sp.x - 9, sp.y - 9), ImVec2(sp.x + 9, sp.y + 9), col, 0,
                        0, 2.0f);

        const bool wantLabel = sel || labelAll || (i < (int)linked.size() && linked[i]);
        if (!wantLabel) continue;
        if (!sel && crowded(sp)) continue;
        labelled.push_back(sp);
        const std::string& tn = e.kv.get("targetname");
        const std::string lbl = tn.empty() ? e.classname : e.classname + "  " + tn;
        dl->AddText(ImVec2(sp.x + 8, sp.y - 7), IM_COL32(20, 20, 22, 220), lbl.c_str());
        dl->AddText(ImVec2(sp.x + 7, sp.y - 8), col, lbl.c_str());
    }
}

void Editor::drawGizmo(ViewPanel& p, float aspect) {
    if (!hasDoc() || selection_.empty() || tool_ != Tool::Select) return;

    ImGuizmo::SetOrthographic(p.kind != ViewKind::Perspective);
    ImGuizmo::SetDrawlist();
    ImGuizmo::SetRect(p.contentMin.x, p.contentMin.y, p.contentSize.x, p.contentSize.y);
    ImGuizmo::SetID(static_cast<int>(p.kind));
    ImGuizmo::SetGizmoSizeClipSpace(0.17f * pb::ui::g_scale);  // bigger than the ~0.1 default
    ImGuizmo::AllowAxisFlip(false);
    {
        ImGuizmo::Style& gs = ImGuizmo::GetStyle();
        gs.TranslationLineThickness = 5.0f;
        gs.TranslationLineArrowSize = 8.0f;
        gs.RotationLineThickness = 4.0f;
        gs.ScaleLineThickness = 5.0f;
        gs.CenterCircleSize = 7.0f;
    }

    const glm::mat4 view = p.camera.view();
    const glm::mat4 proj = p.camera.proj(aspect);

    const ImGuizmo::OPERATION op = gizmoMode_ == 1   ? ImGuizmo::ROTATE
                                   : gizmoMode_ == 2 ? ImGuizmo::SCALE
                                                     : ImGuizmo::TRANSLATE;

    glm::mat4 model = glm::translate(glm::mat4(1.0f), selectionCenter());
    glm::mat4 delta(1.0f);
    float snapv[3] = {float(gridSize_), float(gridSize_), float(gridSize_)};
    if (gizmoMode_ == 1) snapv[0] = snapv[1] = snapv[2] = 5.0f;   // 5 deg
    if (gizmoMode_ == 2) snapv[0] = snapv[1] = snapv[2] = 0.05f;  // 5%

    const bool changed = ImGuizmo::Manipulate(&view[0][0], &proj[0][0], op,
                                              ImGuizmo::WORLD, &model[0][0],
                                              &delta[0][0], snap_ ? snapv : nullptr);
    if (changed) {
        for (const auto& r : selection_)
            if (map::Solid* s = doc_.resolve(r)) s->transform(delta);
        docMeshDirty_ = true;
    }
    if (ImGuizmo::IsUsing()) {
        gizmoUsing_ = true;
    } else if (gizmoUsing_) {
        gizmoUsing_ = false;
        afterEdit(gizmoMode_ == 1 ? "Rotate" : gizmoMode_ == 2 ? "Scale" : "Move");
    }
}

glm::vec3 Editor::snapVec(const glm::vec3& v) const {
    if (!snap_ || gridSize_ <= 0) return v;
    const float g = float(gridSize_);
    return glm::round(v / g) * g;
}

float Editor::snapF(float v) const {
    if (!snap_ || gridSize_ <= 0) return v;
    const float g = float(gridSize_);
    return std::round(v / g) * g;
}

// --------------------------------------------------------------------------
// Sub-object (Vertex / Edge / Face) editing
// --------------------------------------------------------------------------
void Editor::rebuildHandles() {
    handlesDirty_ = false;
    handles_ = {};
    subHot_ = -1;
    if (tool_ != Tool::Vertex || selection_.size() != 1) {
        subSel_ = -1;
        return;
    }
    if (const map::Solid* s = doc_.resolve(selection_[0]))
        handles_ = map::extractHandles(*s, 0.5f);
    const int n = subMode_ == SubMode::Vertex ? (int)handles_.verts.size()
                  : subMode_ == SubMode::Edge ? (int)handles_.edges.size()
                                              : (int)handles_.faces.size();
    if (subSel_ >= n) subSel_ = -1;
}

namespace {
// Screen position of a world point in viewport p; ok=false when behind eye.
ImVec2 projectPt(const ViewKind, const glm::mat4& vp, const glm::vec2& cmin,
                 const glm::vec2& csize, const glm::vec3& w, bool& ok) {
    const glm::vec4 c = vp * glm::vec4(w, 1.0f);
    ok = c.w > 1e-4f;
    if (!ok) return {};
    return ImVec2(cmin.x + (c.x / c.w * 0.5f + 0.5f) * csize.x,
                  cmin.y + (1.0f - (c.y / c.w * 0.5f + 0.5f)) * csize.y);
}
}  // namespace

void Editor::handleSubObjectInput(ViewPanel& p) {
    if (tool_ != Tool::Vertex) return;
    if (handlesDirty_) rebuildHandles();
    if (selection_.size() != 1) return;
    map::Solid* s = doc_.resolve(selection_[0]);
    if (!s) return;

    ImGuiIO& io = ImGui::GetIO();
    const glm::mat4 vp = p.camera.proj(p.contentSize.x / std::max(1.0f, p.contentSize.y)) *
                         p.camera.view();
    const ImVec2 mouse = ImGui::GetMousePos();

    // Handle world position for index i in the current sub-mode.
    auto handlePos = [&](int i) -> glm::vec3 {
        if (i < 0) return glm::vec3(0);
        if (subMode_ == SubMode::Vertex) return handles_.verts[i].pos;
        if (subMode_ == SubMode::Edge)
            return 0.5f * (handles_.verts[handles_.edges[i].a].pos +
                           handles_.verts[handles_.edges[i].b].pos);
        return handles_.faces[i].centroid;
    };
    auto vertIdxFor = [&](int i) {
        std::vector<int> out;
        if (i < 0) return out;
        if (subMode_ == SubMode::Vertex) out = {i};
        else if (subMode_ == SubMode::Edge)
            out = {handles_.edges[i].a, handles_.edges[i].b};
        else out = handles_.faces[i].verts;
        return out;
    };
    const int count = subMode_ == SubMode::Vertex ? (int)handles_.verts.size()
                      : subMode_ == SubMode::Edge ? (int)handles_.edges.size()
                                                  : (int)handles_.faces.size();

    // Hover test.
    subHot_ = -1;
    float bestD = 12.0f;
    for (int i = 0; i < count; ++i) {
        bool ok;
        const ImVec2 sp = projectPt(p.kind, vp, p.contentMin, p.contentSize,
                                    handlePos(i), ok);
        if (!ok) continue;
        const float d = std::hypot(sp.x - mouse.x, sp.y - mouse.y);
        if (d < bestD) { bestD = d; subHot_ = i; }
    }

    // Drag plane: screen-parallel through the handle.
    auto planeHit = [&](const ImVec2& m, const glm::vec3& through) {
        glm::vec3 ro, rd;
        p.camera.pixelRay({m.x - p.contentMin.x, m.y - p.contentMin.y}, p.contentSize,
                          ro, rd);
        const glm::vec3 n = p.kind == ViewKind::Perspective
                                ? -p.camera.forward()
                                : p.camera.orthoForwardAxis();
        const float den = glm::dot(n, rd);
        if (std::fabs(den) < 1e-6f) return through;
        const float t = (glm::dot(n, through) - glm::dot(n, ro)) / den;
        return ro + rd * t;
    };

    if (ImGui::IsMouseClicked(ImGuiMouseButton_Left) && p.hovered) {
        subSel_ = subHot_;
        if (subSel_ >= 0) {
            subDragging_ = true;
            subDragStartPos_ = subCurPos_ = handlePos(subSel_);
            subDragStartHit_ = planeHit(mouse, subDragStartPos_);
        }
    }

    if (subDragging_ && ImGui::IsMouseDown(ImGuiMouseButton_Left) && subSel_ >= 0) {
        const glm::vec3 hit = planeHit(mouse, subDragStartPos_);
        glm::vec3 want = subDragStartPos_ + (hit - subDragStartHit_);
        if (snap_) want = snapVec(want);
        const glm::vec3 delta = want - subCurPos_;
        if (glm::dot(delta, delta) > 1e-10f) {
            map::moveVertexHandles(*s, handles_, vertIdxFor(subSel_), delta);
            subCurPos_ = want;
            docMeshDirty_ = true;
            // keep handle cache positions in step so the overlay tracks the drag
            for (int vi : vertIdxFor(subSel_))
                if (vi >= 0 && vi < (int)handles_.verts.size())
                    handles_.verts[vi].pos += delta;
            for (auto& fh : handles_.faces) {
                glm::vec3 c(0);
                for (int vi : fh.verts) c += handles_.verts[vi].pos;
                if (!fh.verts.empty()) fh.centroid = c / (float)fh.verts.size();
            }
        }
    }

    if (subDragging_ && ImGui::IsMouseReleased(ImGuiMouseButton_Left)) {
        subDragging_ = false;
        if (glm::distance(subCurPos_, subDragStartPos_) > 1e-3f) {
            afterEdit(subMode_ == SubMode::Vertex ? "Edit vertex"
                      : subMode_ == SubMode::Edge ? "Edit edge"
                                                  : "Edit face");
            handlesDirty_ = true;
        }
    }
}

void Editor::drawSubObjectOverlay(ViewPanel& p, float aspect, ImDrawList* dl) {
    if (tool_ != Tool::Vertex || selection_.size() != 1) return;
    if (handlesDirty_) rebuildHandles();
    const glm::mat4 vp = p.camera.proj(aspect) * p.camera.view();

    auto pr = [&](const glm::vec3& w, bool& ok) {
        return projectPt(p.kind, vp, p.contentMin, p.contentSize, w, ok);
    };

    const ImU32 cCold = IM_COL32(120, 200, 255, 230);
    const ImU32 cHot = IM_COL32(255, 235, 150, 255);
    const ImU32 cSel = IM_COL32(255, 150, 60, 255);

    if (subMode_ == SubMode::Edge) {
        for (int i = 0; i < (int)handles_.edges.size(); ++i) {
            bool a, b;
            const ImVec2 pa = pr(handles_.verts[handles_.edges[i].a].pos, a);
            const ImVec2 pb = pr(handles_.verts[handles_.edges[i].b].pos, b);
            if (!a || !b) continue;
            const ImU32 c = i == subSel_ ? cSel : i == subHot_ ? cHot : cCold;
            dl->AddLine(pa, pb, c, i == subSel_ ? 3.0f : 1.6f);
            const ImVec2 m((pa.x + pb.x) * 0.5f, (pa.y + pb.y) * 0.5f);
            dl->AddRectFilled(ImVec2(m.x - 3, m.y - 3), ImVec2(m.x + 3, m.y + 3), c);
        }
    } else if (subMode_ == SubMode::Face) {
        for (int i = 0; i < (int)handles_.faces.size(); ++i) {
            const auto& fh = handles_.faces[i];
            const ImU32 c = i == subSel_ ? cSel : i == subHot_ ? cHot : cCold;
            for (size_t k = 0; k < fh.verts.size(); ++k) {
                bool a, b;
                const ImVec2 pa = pr(handles_.verts[fh.verts[k]].pos, a);
                const ImVec2 pb =
                    pr(handles_.verts[fh.verts[(k + 1) % fh.verts.size()]].pos, b);
                if (a && b) dl->AddLine(pa, pb, c, i == subSel_ ? 2.5f : 1.0f);
            }
            bool ok;
            const ImVec2 cc = pr(fh.centroid, ok);
            if (ok) {
                dl->AddCircleFilled(cc, i == subSel_ ? 6.0f : 4.0f, c);
            }
        }
    } else {  // Vertex
        for (int i = 0; i < (int)handles_.verts.size(); ++i) {
            bool ok;
            const ImVec2 sp = pr(handles_.verts[i].pos, ok);
            if (!ok) continue;
            const ImU32 c = i == subSel_ ? cSel : i == subHot_ ? cHot : cCold;
            const float r = i == subSel_ ? 5.0f : i == subHot_ ? 4.5f : 3.5f;
            dl->AddRectFilled(ImVec2(sp.x - r, sp.y - r), ImVec2(sp.x + r, sp.y + r), c);
            dl->AddRect(ImVec2(sp.x - r, sp.y - r), ImVec2(sp.x + r, sp.y + r),
                        IM_COL32(20, 25, 35, 220));
        }
    }

    // Readout of the current handle position while dragging.
    if (subDragging_) {
        char b[64];
        std::snprintf(b, sizeof(b), "%.0f  %.0f  %.0f", subCurPos_.x, subCurPos_.y,
                      subCurPos_.z);
        const ImVec2 tl(p.contentMin.x + 8, p.contentMin.y + p.contentSize.y - 24);
        dl->AddText(ImVec2(tl.x + 1, tl.y + 1), IM_COL32(0, 0, 0, 200), b);
        dl->AddText(tl, IM_COL32(255, 210, 140, 255), b);
    }
}

// --------------------------------------------------------------------------
// Texture / Face-edit tool
// --------------------------------------------------------------------------
void Editor::handleTextureTool(ViewPanel& p) {
    if (tool_ != Tool::Texture || !hasDoc() || !p.hovered) return;
    ImGuiIO& io = ImGui::GetIO();
    if (!ImGui::IsMouseReleased(ImGuiMouseButton_Left) ||
        ImGui::IsMouseDragPastThreshold(ImGuiMouseButton_Left, 4.0f))
        return;

    const ImVec2 m = ImGui::GetMousePos();
    glm::vec3 ro, rd;
    p.camera.pixelRay({m.x - p.contentMin.x, m.y - p.contentMin.y}, p.contentSize, ro,
                      rd);

    map::SolidRef hitRef;
    int hitFace = -1;
    float bestT = 1e30f;
    auto test = [&](const map::Solid& s, int ent, int idx) {
        float t;
        int fi;
        if (s.valid && map::raySolidFace(ro, rd, s, t, fi) && t < bestT) {
            bestT = t;
            hitRef = {ent, idx};
            hitFace = fi;
        }
    };
    const auto& ws = doc_.worldSolids();
    for (int i = 0; i < (int)ws.size(); ++i) test(ws[i], -1, i);
    for (int e = 0; e < (int)doc_.entities().size(); ++e) {
        const auto& es = doc_.entities()[e].solids;
        for (int i = 0; i < (int)es.size(); ++i) test(es[i], e, i);
    }

    if (hitFace < 0) {
        if (!io.KeyShift) texFaces_.clear();
        return;
    }
    const std::pair<map::SolidRef, int> pick{hitRef, hitFace};
    auto it = std::find(texFaces_.begin(), texFaces_.end(), pick);
    if (io.KeyShift) {
        if (it != texFaces_.end())
            texFaces_.erase(it);
        else
            texFaces_.push_back(pick);
    } else {
        texFaces_ = {pick};
    }
    // Load the clicked face's material into the panel field.
    if (const map::Solid* s = doc_.resolve(hitRef);
        s && hitFace < (int)s->faces.size())
        std::snprintf(texMaterial_, sizeof(texMaterial_), "%s",
                      s->faces[hitFace].material.c_str());
    status_ = std::to_string(texFaces_.size()) + " face(s) selected";
}

void Editor::drawFaceOverlay(ViewPanel& p, float aspect, ImDrawList* dl) {
    if (tool_ != Tool::Texture || texFaces_.empty()) return;
    const glm::mat4 vp = p.camera.proj(aspect) * p.camera.view();
    auto pr = [&](const glm::vec3& w, bool& ok) {
        return projectPt(p.kind, vp, p.contentMin, p.contentSize, w, ok);
    };
    for (const auto& [ref, fi] : texFaces_) {
        const map::Solid* s = doc_.resolve(ref);
        if (!s || fi >= (int)s->faces.size()) continue;
        const auto& f = s->faces[fi];
        if (f.verts.size() < 3) continue;
        std::vector<ImVec2> poly;
        bool all = true;
        for (const auto& v : f.verts) {
            bool ok;
            poly.push_back(pr(v, ok));
            all = all && ok;
        }
        if (!all) continue;
        dl->AddConvexPolyFilled(poly.data(), (int)poly.size(),
                                IM_COL32(90, 170, 255, 60));
        for (size_t k = 0; k < poly.size(); ++k)
            dl->AddLine(poly[k], poly[(k + 1) % poly.size()],
                        IM_COL32(120, 200, 255, 235), 2.0f);
    }
}

void Editor::applyToTexFaces(const std::function<void(map::BrushFace&)>& fn,
                             const char* undoLabel, bool commit) {
    if (texFaces_.empty()) return;
    for (const auto& [ref, fi] : texFaces_) {
        map::Solid* s = doc_.resolve(ref);
        if (s && fi < (int)s->faces.size()) fn(s->faces[fi]);
    }
    if (commit)
        afterEdit(undoLabel);
    else
        buildAndUpload(meshOpts_);  // live preview, no undo entry yet
}

void Editor::drawFaceEditPanel() {
    using namespace pb::ui;
    if (fontUiMed) ImGui::PushFont(fontUiMed);
    ImGui::PushStyleColor(ImGuiCol_Text, col::acc);
    ImGui::TextUnformatted(ICON_FA_IMAGE "  Face edit");
    ImGui::PopStyleColor();
    if (fontUiMed) ImGui::PopFont();

    if (texFaces_.empty()) {
        ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
        ImGui::TextWrapped("Click a face in any viewport to texture it. "
                           "Shift-click to add / remove faces.");
        ImGui::PopStyleColor();
        return;
    }
    ImGui::TextDisabled("%zu face(s) selected", texFaces_.size());

    // Representative face for showing current values.
    const map::Solid* rs = doc_.resolve(texFaces_[0].first);
    if (!rs || texFaces_[0].second >= (int)rs->faces.size()) return;
    const map::BrushFace& rf = rs->faces[texFaces_[0].second];
    const auto& minfo = materials_.get(texMaterial_);

    sectionLabel("MATERIAL");
    ImGui::Image(static_cast<ImTextureID>(static_cast<intptr_t>(minfo.texture)),
                 ImVec2(64, 64));
    ImGui::SameLine();
    ImGui::BeginGroup();
    ImGui::SetNextItemWidth(-1);
    ImGui::InputText("##mat", texMaterial_, sizeof(texMaterial_));
    if (ImGui::Button(ICON_FA_CHECK "  Apply material", ImVec2(-1, 0))) {
        std::string mm = texMaterial_;
        applyToTexFaces([&](map::BrushFace& f) { f.material = mm; }, "Apply material",
                        true);
    }
    if (ImGui::Button("Use current browser pick", ImVec2(-1, 0)))
        std::snprintf(texMaterial_, sizeof(texMaterial_), "%s",
                      blockMaterial_.c_str());
    ImGui::EndGroup();
    ImGui::TextDisabled("%dx%d%s", minfo.width, minfo.height,
                        minfo.found ? "" : "  (not found)");

    sectionLabel("PROJECTION");
    auto flabel = [](const char* t) {
        ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
        ImGui::TextUnformatted(t);
        ImGui::PopStyleColor();
    };
    flabel("Shift  X / Y  (texels)");
    float shift[2] = {rf.uAxis.w, rf.vAxis.w};
    ImGui::SetNextItemWidth(-1);
    if (ImGui::DragFloat2("##shift", shift, 1.0f, 0, 0, "%.1f"))
        applyToTexFaces(
            [&](map::BrushFace& f) { f.uAxis.w = shift[0]; f.vAxis.w = shift[1]; },
            "Texture shift", false);
    if (ImGui::IsItemDeactivatedAfterEdit())
        applyToTexFaces([&](map::BrushFace&) {}, "Texture shift", true);
    flabel("Scale  X / Y");
    float scale[2] = {rf.uScale, rf.vScale};
    ImGui::SetNextItemWidth(-1);
    if (ImGui::DragFloat2("##scale", scale, 0.01f, 0.001f, 1000.0f, "%.3f"))
        applyToTexFaces(
            [&](map::BrushFace& f) {
                f.uScale = scale[0] == 0 ? 0.25f : scale[0];
                f.vScale = scale[1] == 0 ? 0.25f : scale[1];
            },
            "Texture scale", false);
    if (ImGui::IsItemDeactivatedAfterEdit())
        applyToTexFaces([&](map::BrushFace&) {}, "Texture scale", true);
    flabel("Rotation");
    float rot = rf.rotation;
    ImGui::SetNextItemWidth(-1);
    if (ImGui::DragFloat("##rot", &rot, 1.0f, -360.0f, 360.0f, "%.0f deg")) {
        const float delta = rot - rf.rotation;
        applyToTexFaces([&](map::BrushFace& f) { map::faceRotateUV(f, delta); },
                        "Texture rotate", false);
    }
    if (ImGui::IsItemDeactivatedAfterEdit())
        applyToTexFaces([&](map::BrushFace&) {}, "Texture rotate", true);
    flabel("Lightmap scale");
    float lm = rf.lightmapScale;
    ImGui::SetNextItemWidth(-1);
    if (ImGui::DragFloat("##lm", &lm, 1.0f, 1.0f, 512.0f, "%.0f"))
        applyToTexFaces([&](map::BrushFace& f) { f.lightmapScale = lm; },
                        "Lightmap scale", false);
    if (ImGui::IsItemDeactivatedAfterEdit())
        applyToTexFaces([&](map::BrushFace&) {}, "Lightmap scale", true);

    sectionLabel("ALIGN");
    if (ImGui::Button("World", ImVec2(-1, 0)))
        applyToTexFaces([&](map::BrushFace& f) { map::faceAlignWorld(f); },
                        "Align to world", true);
    if (ImGui::Button("Face", ImVec2(-1, 0)))
        applyToTexFaces([&](map::BrushFace& f) { map::faceAlignToFace(f); },
                        "Align to face", true);

    sectionLabel("JUSTIFY");
    const int tw = minfo.width, th = minfo.height;
    struct J { const char* label; int mode; };
    const J js[] = {{"Fit", 0},  {"Top", 1},    {"Bottom", 2},
                    {"Left", 3}, {"Right", 4},  {"Center", 5}};
    for (int i = 0; i < 6; ++i) {
        if (i % 3) ImGui::SameLine();
        if (ImGui::Button(js[i].label, ImVec2(88, 0))) {
            const int mode = js[i].mode;
            applyToTexFaces(
                [&](map::BrushFace& f) { map::faceJustifyUV(f, tw, th, mode); },
                "Justify texture", true);
        }
    }
}

// --------------------------------------------------------------------------
// Clip tool  (draw a cut line in a 2D view; Tab cycles keep-front / back /
// both; Enter applies to the selected brushes)
// --------------------------------------------------------------------------
void Editor::handleClipTool(ViewPanel& p) {
    if (tool_ != Tool::Clip || !hasDoc() || p.kind == ViewKind::Perspective) return;
    if (selection_.empty()) return;
    ImGuiIO& io = ImGui::GetIO();

    if (ImGui::IsKeyPressed(ImGuiKey_Tab)) clipMode_ = (clipMode_ + 1) % 3;

    if (p.hovered && ImGui::IsMouseClicked(ImGuiMouseButton_Left)) {
        clipDragging_ = true;
        clipArmed_ = false;
        clipView_ = p.kind;
        clipA_ = clipB_ = snapVec(viewPlanePoint(p, ImGui::GetMousePos()));
    }
    if (clipDragging_ && clipView_ == p.kind) {
        clipB_ = snapVec(viewPlanePoint(p, ImGui::GetMousePos()));
        if (ImGui::IsMouseReleased(ImGuiMouseButton_Left)) {
            clipDragging_ = false;
            clipArmed_ = glm::distance(clipA_, clipB_) > 1.0f;
        }
    }

    if (clipArmed_ && (ImGui::IsKeyPressed(ImGuiKey_Enter) ||
                       ImGui::IsKeyPressed(ImGuiKey_KeypadEnter))) {
        applyClip();
        clipArmed_ = false;
    }
    if (ImGui::IsKeyPressed(ImGuiKey_Escape)) { clipArmed_ = false; clipDragging_ = false; }
}

void Editor::applyClip() {
    if (!clipArmed_ || selection_.empty()) return;
    // Clip plane: contains the drawn line, perpendicular to the view.
    glm::vec3 fwd;
    switch (clipView_) {
        case ViewKind::Top:   fwd = glm::vec3(0, 0, 1); break;
        case ViewKind::Front: fwd = glm::vec3(0, 1, 0); break;
        case ViewKind::Side:  fwd = glm::vec3(1, 0, 0); break;
        default:              fwd = glm::vec3(0, 0, 1); break;
    }
    const glm::vec3 dir = clipB_ - clipA_;
    glm::vec3 n = glm::cross(glm::normalize(dir), fwd);
    if (glm::length(n) < 1e-4f) return;
    n = glm::normalize(n);
    const float d = glm::dot(n, clipA_);
    const std::string mat = blockMaterial_;

    std::vector<map::Solid> added;
    for (const auto& r : selection_) {
        map::Solid* s = doc_.resolve(r);
        if (!s) continue;
        if (clipMode_ == 2) {
            map::Solid back = *s;
            if (back.clip(-n, -d, mat)) { back.id = doc_.nextId(); added.push_back(std::move(back)); }
            if (!s->clip(n, d, mat)) *s = map::Solid();  // front gone
        } else if (clipMode_ == 0) {
            s->clip(n, d, mat);
        } else {
            s->clip(-n, -d, mat);
        }
    }
    // Drop any solids the cut removed entirely; append the "both" back-halves.
    auto& ws = doc_.worldSolids();
    ws.erase(std::remove_if(ws.begin(), ws.end(),
                            [](const map::Solid& s) { return s.faces.empty(); }),
             ws.end());
    for (auto& s : added) ws.push_back(std::move(s));

    selection_.clear();
    clearSelection();
    afterEdit("Clip");
    status_ = "Clipped";
}

void Editor::drawClipOverlay(ViewPanel& p, float aspect, ImDrawList* dl) {
    if (tool_ != Tool::Clip || p.kind == ViewKind::Perspective) return;
    if (!(clipDragging_ || clipArmed_) || clipView_ != p.kind) return;
    const glm::mat4 vp = p.camera.proj(aspect) * p.camera.view();
    bool a, b;
    const ImVec2 pa = projectPt(p.kind, vp, p.contentMin, p.contentSize, clipA_, a);
    const ImVec2 pb = projectPt(p.kind, vp, p.contentMin, p.contentSize, clipB_, b);
    if (!a || !b) return;
    dl->AddLine(pa, pb, IM_COL32(255, 90, 90, 240), 2.0f);
    // extend the line across the viewport
    ImVec2 d(pb.x - pa.x, pb.y - pa.y);
    const float L = std::sqrt(d.x * d.x + d.y * d.y);
    if (L > 1.0f) {
        d.x /= L; d.y /= L;
        dl->AddLine(ImVec2(pa.x - d.x * 4000, pa.y - d.y * 4000),
                    ImVec2(pb.x + d.x * 4000, pb.y + d.y * 4000),
                    IM_COL32(255, 90, 90, 90), 1.0f);
    }
    const char* mode = clipMode_ == 0 ? "keep FRONT" : clipMode_ == 1 ? "keep BACK"
                                                                      : "keep BOTH";
    char msg[64];
    std::snprintf(msg, sizeof(msg), "Clip: %s   (Tab mode / Enter apply)", mode);
    dl->AddText(ImVec2(p.contentMin.x + 8, p.contentMin.y + 24),
                IM_COL32(255, 150, 150, 255), msg);
}

void Editor::handleBlockTool(ViewPanel& p) {
    if (tool_ != Tool::Block || !hasDoc() || p.kind == ViewKind::Perspective) return;
    ImGuiIO& io = ImGui::GetIO();

    const glm::vec3 fwd = p.camera.orthoForwardAxis();
    const glm::vec3 planePt = p.camera.orthoCenter;
    const float planeD = glm::dot(fwd, planePt);
    auto worldAt = [&](const ImVec2& m) {
        glm::vec3 ro, rd;
        p.camera.pixelRay({m.x - p.contentMin.x, m.y - p.contentMin.y}, p.contentSize,
                          ro, rd);
        const float denom = glm::dot(fwd, rd);
        const float t = std::fabs(denom) > 1e-6f ? (planeD - glm::dot(fwd, ro)) / denom
                                                 : 0.0f;
        return ro + rd * t;
    };

    if (ImGui::IsMouseClicked(ImGuiMouseButton_Left) && !io.KeyShift) {
        blockDragging_ = true;
        blockView_ = p.kind;
        blockA_ = blockB_ = worldAt(ImGui::GetMousePos());
    }
    if (blockDragging_ && p.kind == blockView_) {
        blockB_ = worldAt(ImGui::GetMousePos());

        // Preview: the box from A..B, third axis extruded by newBrushDepth_.
        glm::vec3 a = snapVec(blockA_), b = snapVec(blockB_);
        const glm::vec3 up = glm::abs(fwd);  // the missing axis
        glm::vec3 mn = glm::min(a, b), mx = glm::max(a, b);
        for (int i = 0; i < 3; ++i)
            if (up[i] > 0.5f) {
                mn[i] = snapVec(glm::vec3(planeD))[i];
                mx[i] = mn[i] + newBrushDepth_;
            }
        map::Solid preview = map::Solid::makeBox(mn, mx, blockMaterial_);
        renderer_.setSelectionWire(map::solidWire(preview));

        if (ImGui::IsMouseReleased(ImGuiMouseButton_Left)) {
            blockDragging_ = false;
            if (glm::length(mx - mn) > 1.0f &&
                (mx.x - mn.x) > 0.5f && (mx.y - mn.y) > 0.5f && (mx.z - mn.z) > 0.5f) {
                preview.id = doc_.nextId();
                doc_.worldSolids().push_back(std::move(preview));
                selection_ = {{-1, static_cast<int>(doc_.worldSolids().size()) - 1}};
                afterEdit("Create brush");
                status_ = "Created brush";
            } else {
                clearSelection();
            }
        }
    }
}

glm::vec3 Editor::dropWorldPoint(ViewPanel& p, const ImVec2& mouse) {
    glm::vec3 ro, rd;
    p.camera.pixelRay({mouse.x - p.contentMin.x, mouse.y - p.contentMin.y},
                      p.contentSize, ro, rd);

    if (p.kind != ViewKind::Perspective) return snapVec(viewPlanePoint(p, mouse));

    // 3D view: prefer a hit on existing brushwork, then the ground, then a
    // point a fixed distance in front of the camera so it always lands in view.
    float bestT = 1e30f;
    for (const auto& s : doc_.worldSolids()) {
        float t;
        if (s.valid && map::raySolid(ro, rd, s, t) && t > 0.0f && t < bestT) bestT = t;
    }
    for (const auto& e : doc_.entities())
        for (const auto& s : e.solids) {
            float t;
            if (s.valid && map::raySolid(ro, rd, s, t) && t > 0.0f && t < bestT)
                bestT = t;
        }
    if (bestT < 1e29f) return snapVec(ro + rd * bestT);

    if (std::fabs(rd.z) > 1e-4f) {
        const float t = -ro.z / rd.z;
        if (t > 1.0f && t < 16384.0f) return snapVec(ro + rd * t);
    }
    return snapVec(ro + rd * 384.0f);
}

glm::vec3 Editor::viewPlanePoint(ViewPanel& p, const ImVec2& m) const {
    glm::vec3 ro, rd;
    p.camera.pixelRay({m.x - p.contentMin.x, m.y - p.contentMin.y}, p.contentSize, ro,
                      rd);
    glm::vec3 n;
    float d;
    if (p.kind == ViewKind::Perspective) {
        n = glm::vec3(0, 0, 1);
        d = 0.0f;  // ground plane
    } else {
        n = p.camera.orthoForwardAxis();
        d = glm::dot(n, p.camera.orthoCenter);
    }
    const float den = glm::dot(n, rd);
    const float t = std::fabs(den) > 1e-6f ? (d - glm::dot(n, ro)) / den : 0.0f;
    return ro + rd * t;
}

void Editor::placePiece(const std::string& piece, const glm::vec3& atRaw) {
    if (!doc_.active()) doc_.newBlank("untitled");
    const glm::vec3 at = snapVec(atRaw);
    const std::string floorMat = "dev/dev_measuregeneric01b";
    const std::string wallMat = "dev/dev_measurewall01a";

    std::vector<map::Solid> made;
    std::vector<map::MapEntity> madeEnts;
    bool asFuncDetail = false;

    auto box = [&](glm::vec3 mn, glm::vec3 mx, const std::string& mat) {
        made.push_back(map::Solid::makeBox(mn, mx, mat));
    };
    // Point entity at a world position with any number of extra key/values.
    auto ent = [&](const char* cls, glm::vec3 pos,
                   std::initializer_list<std::pair<const char*, const char*>> kvs)
        -> map::MapEntity& {
        map::MapEntity e;
        e.id = doc_.nextId();
        e.classname = cls;
        e.origin = pos;
        e.kv.set("classname", cls);
        e.kv.set("origin", std::to_string((int)pos.x) + " " +
                               std::to_string((int)pos.y) + " " +
                               std::to_string((int)pos.z));
        for (const auto& kv : kvs)
            if (kv.second && kv.second[0]) e.kv.set(kv.first, kv.second);
        madeEnts.push_back(std::move(e));
        return madeEnts.back();
    };
    // Brush entity (a box solid tagged with a classname) at a world box.
    auto brushEnt = [&](const char* cls, glm::vec3 mn, glm::vec3 mx,
                        std::initializer_list<std::pair<const char*, const char*>> kvs)
        -> map::MapEntity& {
        map::MapEntity e;
        e.id = doc_.nextId();
        e.classname = cls;
        e.origin = 0.5f * (mn + mx);
        e.kv.set("classname", cls);
        for (const auto& kv : kvs)
            if (kv.second && kv.second[0]) e.kv.set(kv.first, kv.second);
        map::Solid s = map::Solid::makeBox(mn, mx, "tools/toolstrigger");
        s.id = doc_.nextId();
        e.solids.push_back(std::move(s));
        madeEnts.push_back(std::move(e));
        return madeEnts.back();
    };
    auto room = [&](glm::vec3 c, glm::vec3 halfInterior, float th) {
        const glm::vec3 mn = c - halfInterior, mx = c + halfInterior;
        box({mn.x - th, mn.y - th, mn.z - th}, {mx.x + th, mx.y + th, mn.z}, floorMat);
        box({mn.x - th, mn.y - th, mx.z}, {mx.x + th, mx.y + th, mx.z + th}, floorMat);
        box({mn.x - th, mn.y - th, mn.z}, {mx.x + th, mn.y, mx.z}, wallMat);
        box({mn.x - th, mx.y, mn.z}, {mx.x + th, mx.y + th, mx.z}, wallMat);
        box({mn.x - th, mn.y, mn.z}, {mn.x, mx.y, mx.z}, wallMat);
        box({mx.x, mn.y, mn.z}, {mx.x + th, mx.y, mx.z}, wallMat);
    };

    if (piece == "Floor" || piece == "Route") {
        const float hw = piece == "Route" ? 256.0f : 128.0f;
        const float hd = piece == "Route" ? 64.0f : 128.0f;
        box({at.x - hw, at.y - hd, at.z - 16}, {at.x + hw, at.y + hd, at.z}, floorMat);
    } else if (piece == "Wall") {
        box({at.x - 128, at.y - 8, at.z}, {at.x + 128, at.y + 8, at.z + 128}, wallMat);
    } else if (piece == "Ceiling") {
        box({at.x - 128, at.y - 128, at.z}, {at.x + 128, at.y + 128, at.z + 16},
            floorMat);
    } else if (piece == "Pillar") {
        box({at.x - 32, at.y - 32, at.z}, {at.x + 32, at.y + 32, at.z + 192}, wallMat);
    } else if (piece == "Room") {
        room(at + glm::vec3(0, 0, 96), glm::vec3(192, 192, 96), 16.0f);
    } else if (piece == "Ramp") {
        const float x0 = at.x - 128, x1 = at.x + 128, y0 = at.y - 64, y1 = at.y + 64;
        const float z0 = at.z, z1 = at.z + 128;
        glm::vec3 sn = glm::normalize(glm::vec3(-(z1 - z0), 0, (x1 - x0)));
        made.push_back(map::Solid::fromPlanes(
            {{{0, 0, -1}, -z0},
             {{1, 0, 0}, x1},
             {{0, 1, 0}, y1},
             {{0, -1, 0}, -y0},
             {sn, glm::dot(sn, glm::vec3(x0, at.y, z0))}},
            floorMat));
    } else if (piece == "Hill" || piece == "Mountain") {
        // A faceted mound: stacked, shrinking, jittered octagonal prisms.
        const int layers = std::clamp(hillLayers_, 3, 16);
        const int sides = 8;
        auto noise = [](float a, float b) {
            const float s = std::sin(a * 12.9898f + b * 78.233f) * 43758.5453f;
            return s - std::floor(s);  // 0..1, deterministic
        };
        for (int i = 0; i < layers; ++i) {
            const float t0 = float(i) / layers;
            const float t1 = float(i + 1) / layers;
            const float z0 = at.z + t0 * hillHeight_;
            const float z1 = at.z + t1 * hillHeight_ + 0.5f;
            const float baseR = hillRadius_ * (1.0f - t0 * 0.92f);
            const float aoff = noise(float(i), 3.1f) * 0.7f;  // twist each layer
            std::vector<std::pair<glm::vec3, float>> planes;
            planes.push_back({{0, 0, 1}, z1});
            planes.push_back({{0, 0, -1}, -z0});
            for (int k = 0; k < sides; ++k) {
                const float ang = aoff + (k / float(sides)) * 6.2831853f;
                const glm::vec3 n(std::cos(ang), std::sin(ang), 0.0f);
                const float jitter = 1.0f + hillRough_ * (noise(float(i), float(k)) - 0.5f);
                const float r = std::max(24.0f, baseR * jitter);
                planes.push_back({n, glm::dot(n, at) + r});
            }
            map::Solid s = map::Solid::fromPlanes(planes, floorMat);
            if (s.valid) made.push_back(std::move(s));
        }
        asFuncDetail = true;
    } else if (piece == "RED spawn" || piece == "BLU spawn") {
        const bool red = piece[0] == 'R';
        const char* team = red ? "2" : "3";
        room(at + glm::vec3(0, 0, 96), glm::vec3(192, 192, 96), 16.0f);
        for (int i = 0; i < 4; ++i)
            ent("info_player_teamspawn",
                at + glm::vec3((i % 2) * 64 - 32, (i / 2) * 64 - 32, 8),
                {{"TeamNum", team}, {"angles", "0 0 0"}});
        // A resupply locker so the spawn actually refills players.
        brushEnt("func_regenerate",
                 {at.x - 32, at.y + 150, at.z}, {at.x + 32, at.y + 182, at.z + 96},
                 {{"associatedmodel", ""}, {"TeamNum", team}});
    } else if (piece == "Resupply") {
        brushEnt("func_regenerate", {at.x - 32, at.y - 16, at.z},
                 {at.x + 32, at.y + 16, at.z + 96}, {});
    } else if (piece == "Health / ammo") {
        ent("item_healthkit_medium", at + glm::vec3(-24, 0, 8), {});
        ent("item_ammopack_medium", at + glm::vec3(24, 0, 8), {});
    } else if (piece == "Capture point") {
        // A control point + the trigger that captures it, wired together.
        ent("team_control_point", at + glm::vec3(0, 0, 8),
            {{"targetname", "control_point_1"},
             {"point_default_owner", "0"},
             {"point_printname", "Point A"},
             {"point_group", "0"},
             {"point_index", "0"}});
        brushEnt("trigger_capture_area", {at.x - 96, at.y - 96, at.z},
                 {at.x + 96, at.y + 96, at.z + 128},
                 {{"area_cap_point", "control_point_1"},
                  {"team_cap_2", "1"},
                  {"team_cap_3", "1"},
                  {"team_numcap_2", "1"},
                  {"team_numcap_3", "1"}});
        box({at.x - 128, at.y - 128, at.z - 16}, {at.x + 128, at.y + 128, at.z},
            floorMat);
    } else if (piece == "Payload track") {
        // A working payload spine: 4 chained path_track nodes, a func_tracktrain
        // cart sitting on the first, a cap trigger parented to it, and a
        // team_train_watcher spanning the first->last node.
        const int N = 4;
        for (int i = 0; i < N; ++i) {
            const std::string nm = "cart_path_" + std::to_string(i + 1);
            const std::string nxt = "cart_path_" + std::to_string(i + 2);
            ent("path_track", at + glm::vec3(i * 320.0f, 0, 8),
                {{"targetname", nm.c_str()},
                 {"target", i < N - 1 ? nxt.c_str() : ""},
                 {"orientationtype", "1"}});
        }
        brushEnt("func_tracktrain", {at.x - 48, at.y - 40, at.z},
                 {at.x + 48, at.y + 40, at.z + 90},
                 {{"targetname", "cart"},
                  {"target", "cart_path_1"},
                  {"startspeed", "90"},
                  {"speed", "90"},
                  {"bank", "0"},
                  {"orientationtype", "1"},
                  {"wheels", "50"},
                  {"height", "24"}});
        brushEnt("trigger_capture_area", {at.x - 128, at.y - 128, at.z},
                 {at.x + 128, at.y + 128, at.z + 128},
                 {{"targetname", "cart_cap"},
                  {"parentname", "cart"},
                  {"area_cap_point", "control_point_1"},
                  {"team_cancap_3", "1"},
                  {"team_numcap_3", "1"}});
        ent("team_train_watcher", at + glm::vec3(0, 0, 8),
            {{"targetname", "cart_watcher"},
             {"train", "cart"},
             {"start_node", "cart_path_1"},
             {"goal_node", ("cart_path_" + std::to_string(N)).c_str()},
             {"linked_pathtrack_1", "cart_path_1"}});
        ent("team_control_point", at + glm::vec3(N * 320.0f - 320.0f, 0, 8),
            {{"targetname", "control_point_1"},
             {"point_printname", "The Point"},
             {"point_default_owner", "2"},
             {"point_index", "0"}});
    } else if (piece == "Point light") {
        ent("light", at + glm::vec3(0, 0, 128),
            {{"_light", "255 255 224 200"}, {"_constant_attn", "0"},
             {"_linear_attn", "0"}, {"_quadratic_attn", "1"}});
    } else if (piece == "Spot light") {
        ent("light_spot", at + glm::vec3(0, 0, 160),
            {{"_light", "255 255 224 300"}, {"pitch", "-90"},
             {"angles", "-90 0 0"}, {"_cone", "45"}, {"_inner_cone", "30"}});
    } else if (piece == "Sun / sky") {
        ent("light_environment", at + glm::vec3(0, 0, 160),
            {{"pitch", "-45"}, {"angles", "0 220 0"},
             {"_light", "247 233 200 350"}, {"_ambient", "180 190 210 60"},
             {"_lightHDR", "-1 -1 -1 1"}, {"_ambientHDR", "-1 -1 -1 1"}});
    } else {
        box({at.x - 64, at.y - 64, at.z}, {at.x + 64, at.y + 64, at.z + 64}, floorMat);
    }

    selection_.clear();
    if (asFuncDetail && !made.empty()) {
        // One func_detail entity holding all the pieces (keeps vis fast).
        map::MapEntity fd;
        fd.id = doc_.nextId();
        fd.classname = "func_detail";
        fd.kv.set("classname", "func_detail");
        for (auto& s : made) {
            s.id = doc_.nextId();
            fd.solids.push_back(std::move(s));
        }
        doc_.entities().push_back(std::move(fd));
        selection_.push_back(
            {static_cast<int>(doc_.entities().size()) - 1, 0});
    } else {
        for (auto& s : made) {
            s.id = doc_.nextId();
            doc_.worldSolids().push_back(std::move(s));
            selection_.push_back(
                {-1, static_cast<int>(doc_.worldSolids().size()) - 1});
        }
    }
    for (auto& e : madeEnts) doc_.entities().push_back(std::move(e));

    afterEdit(("Add " + piece).c_str());
    status_ = "Placed " + piece;
}

void Editor::finalizeRoad() {
    if (roadPts_.size() < 2) {
        status_ = "Need at least 2 points for a road.";
        return;
    }
    if (!doc_.active()) { doc_.newBlank("untitled"); history_.reset(doc_); }

    // Catmull-Rom through the clicked points (clamped endpoints).
    auto pt = [&](int i) {
        return roadPts_[std::clamp(i, 0, (int)roadPts_.size() - 1)];
    };
    auto cr = [](const glm::vec3& p0, const glm::vec3& p1, const glm::vec3& p2,
                 const glm::vec3& p3, float t) {
        const float t2 = t * t, t3 = t2 * t;
        return 0.5f * ((2.0f * p1) + (-p0 + p2) * t +
                       (2.0f * p0 - 5.0f * p1 + 4.0f * p2 - p3) * t2 +
                       (-p0 + 3.0f * p1 - 3.0f * p2 + p3) * t3);
    };
    std::vector<glm::vec3> path;
    const int per = 8;  // samples per input span
    for (int i = 0; i + 1 < (int)roadPts_.size(); ++i)
        for (int s = 0; s < per; ++s)
            path.push_back(cr(pt(i - 1), pt(i), pt(i + 1), pt(i + 2), s / float(per)));
    path.push_back(roadPts_.back());

    const float hw = roadWidth_ * 0.5f, ht = roadThick_ * 0.5f;
    std::vector<map::Solid> segs;
    for (size_t i = 0; i + 1 < path.size(); ++i) {
        glm::vec3 a = path[i], b = path[i + 1];
        glm::vec3 f = b - a;
        const float len = glm::length(f);
        if (len < 1.0f) continue;
        f /= len;
        glm::vec3 rt = glm::normalize(glm::cross(f, glm::vec3(0, 0, 1)));
        if (!std::isfinite(rt.x)) rt = glm::vec3(1, 0, 0);
        glm::vec3 up = glm::normalize(glm::cross(rt, f));
        const glm::vec3 c = 0.5f * (a + b) - up * ht;  // top of road at the path
        const float hl = len * 0.5f + 1.0f;            // overlap neighbours a hair
        std::vector<std::pair<glm::vec3, float>> planes = {
            {f, glm::dot(f, c) + hl},   {-f, glm::dot(-f, c) + hl},
            {rt, glm::dot(rt, c) + hw}, {-rt, glm::dot(-rt, c) + hw},
            {up, glm::dot(up, c) + ht}, {-up, glm::dot(-up, c) + ht}};
        map::Solid seg = map::Solid::fromPlanes(planes, "dev/dev_measuregeneric01b");
        if (seg.valid) segs.push_back(std::move(seg));
    }
    if (segs.empty()) { status_ = "Road had no usable segments."; return; }

    map::MapEntity fd;
    fd.id = doc_.nextId();
    fd.classname = "func_detail";
    fd.kv.set("classname", "func_detail");
    for (auto& s : segs) { s.id = doc_.nextId(); fd.solids.push_back(std::move(s)); }
    doc_.entities().push_back(std::move(fd));
    selection_ = {{(int)doc_.entities().size() - 1, 0}};

    const size_t n = roadPts_.size();
    roadPts_.clear();
    roadActive_ = false;
    placing_.clear();
    afterEdit("Add road");
    status_ = "Built a road from " + std::to_string(n) + " points.";
}

void Editor::drawRoadOverlay(ViewPanel& p, float aspect, ImDrawList* dl) {
    if (!roadActive_ || roadPts_.empty()) return;
    const glm::mat4 vp = p.camera.proj(aspect) * p.camera.view();
    auto pr = [&](const glm::vec3& w, bool& ok) {
        return projectPt(p.kind, vp, p.contentMin, p.contentSize, w, ok);
    };
    const ImU32 col = IM_COL32(120, 200, 255, 235);
    ImVec2 prev;
    bool havePrev = false;
    for (const auto& w : roadPts_) {
        bool ok;
        const ImVec2 s = pr(w, ok);
        if (!ok) { havePrev = false; continue; }
        dl->AddCircleFilled(s, 4.0f, col);
        if (havePrev) dl->AddLine(prev, s, col, 2.0f);
        prev = s;
        havePrev = true;
    }
    dl->AddText(ImVec2(p.contentMin.x + 8, p.contentMin.y + 40), col,
                "ROAD — click to add points, Enter to build");
}

void Editor::placeFromPayload(const std::string& payload, const glm::vec3& at) {
    if (payload.rfind("@model:", 0) == 0) {
        if (!doc_.active()) { doc_.newBlank("untitled"); history_.reset(doc_); }
        placeFgdEntity("prop_static", at);
        if (!doc_.entities().empty())
            doc_.entities().back().kv.set("model", payload.substr(7));
        afterEdit("Place prop");
        status_ = "Placed  " + payload.substr(payload.rfind('/') + 1);
    } else if (payload.rfind("@ent:", 0) == 0) {
        placeFgdEntity(payload.substr(5), at);
    } else if (payload.rfind("@kit:", 0) == 0) {
        placePiece(payload.substr(5), at);
    } else if (payload.rfind("@prefab:", 0) == 0) {
        placePrefab(payload.substr(8), at);
    } else {
        placePiece(payload, at);
    }
}

void Editor::placeFgdEntity(const std::string& cls, const glm::vec3& atRaw) {
    if (!doc_.active()) doc_.newBlank("untitled");
    const glm::vec3 at = snapVec(atRaw);
    const fgd::EntityClass* ec = fgd_.flattened(cls);

    map::MapEntity e;
    e.id = doc_.nextId();
    e.classname = cls;
    e.origin = at;
    e.kv.set("classname", cls);
    e.kv.set("origin", std::to_string((int)at.x) + " " + std::to_string((int)at.y) +
                           " " + std::to_string((int)at.z));
    // Seed non-empty FGD defaults so the entity is valid out of the box.
    if (ec)
        for (const auto& v : ec->vars)
            if (!v.defaultValue.empty() && v.key != "origin" && v.key != "targetname")
                e.kv.set(v.key, v.defaultValue);

    const bool solid = ec && ec->isSolid();
    if (solid) {
        map::Solid s = map::Solid::makeBox(at - glm::vec3(64, 64, 0),
                                           at + glm::vec3(64, 64, 128),
                                           "tools/toolstrigger");
        s.id = doc_.nextId();
        e.solids.push_back(std::move(s));
    }

    doc_.entities().push_back(std::move(e));
    selectedEntity_ = static_cast<int>(doc_.entities().size()) - 1;
    selection_.clear();
    afterEdit(("Add " + cls).c_str());
    status_ = "Placed " + cls;
}

void Editor::tieSelectionToEntity(const std::string& cls) {
    // Move the selected world solids into a new brush entity.
    std::vector<int> idx;
    for (const auto& r : selection_)
        if (r.entity < 0 && r.solid >= 0) idx.push_back(r.solid);
    if (idx.empty()) return;
    std::sort(idx.rbegin(), idx.rend());

    map::MapEntity e;
    e.id = doc_.nextId();
    e.classname = cls;
    e.kv.set("classname", cls);
    if (const fgd::EntityClass* ec = fgd_.flattened(cls))
        for (const auto& v : ec->vars)
            if (!v.defaultValue.empty() && v.key != "origin")
                e.kv.set(v.key, v.defaultValue);
    for (int i : idx) {
        e.solids.push_back(doc_.worldSolids()[i]);
        doc_.worldSolids().erase(doc_.worldSolids().begin() + i);
    }
    std::reverse(e.solids.begin(), e.solids.end());
    e.origin = e.solids.empty() ? glm::vec3(0) : e.solids.front().center();

    doc_.entities().push_back(std::move(e));
    selection_.clear();
    selectedEntity_ = static_cast<int>(doc_.entities().size()) - 1;
    afterEdit(("Tie to " + cls).c_str());
    status_ = "Tied " + std::to_string(idx.size()) + " brush(es) to " + cls;
}

void Editor::handleViewportInput(ViewPanel& p) {
    if (!p.hovered) return;
    ImGuiIO& io = ImGui::GetIO();
    const float dt = std::clamp(io.DeltaTime, 0.0f, 0.1f);

    // Curvy road: each click adds a spline point; Enter finishes, Esc cancels.
    if (placing_ == "Curvy road") {
        if (ImGui::IsMouseReleased(ImGuiMouseButton_Left) &&
            !ImGui::IsMouseDragPastThreshold(ImGuiMouseButton_Left, 4.0f)) {
            roadPts_.push_back(snapVec(viewPlanePoint(p, ImGui::GetMousePos())));
            roadActive_ = true;
            status_ = std::to_string(roadPts_.size()) +
                      " road point(s) — click more, Enter to build, Esc to cancel";
        }
        if (ImGui::IsKeyPressed(ImGuiKey_Enter) ||
            ImGui::IsKeyPressed(ImGuiKey_KeypadEnter))
            finalizeRoad();
        if (ImGui::IsKeyPressed(ImGuiKey_Escape)) {
            roadPts_.clear();
            roadActive_ = false;
            placing_.clear();
            status_ = "Road cancelled.";
        }
        return;
    }

    // Kit placement: click drops the pending piece.
    if (!placing_.empty() && ImGui::IsMouseReleased(ImGuiMouseButton_Left) &&
        !ImGui::IsMouseDragPastThreshold(ImGuiMouseButton_Left, 4.0f)) {
        const glm::vec3 at = viewPlanePoint(p, ImGui::GetMousePos());
        if (placing_.rfind("@ent:", 0) == 0)
            placeFgdEntity(placing_.substr(5), at);
        else if (placing_.rfind("@kit:", 0) == 0)
            placePiece(placing_.substr(5), at);
        else if (placing_.rfind("@prefab:", 0) == 0)
            placePrefab(placing_.substr(8), at);
        else if (placing_.rfind("@model:", 0) == 0) {
            placeFgdEntity("prop_static", at);
            if (!doc_.entities().empty())
                doc_.entities().back().kv.set("model", placing_.substr(7));
            afterEdit("Place prop");
        } else
            placePiece(placing_, at);
        if (!io.KeyShift) placing_.clear();  // hold Shift to place several
        return;
    }

    handleBlockTool(p);

    // Vertex/Edge/Face editing owns the mouse when a single brush is selected.
    const bool subActive = tool_ == Tool::Vertex && selection_.size() == 1;
    if (subActive) handleSubObjectInput(p);
    handleTextureTool(p);
    handleClipTool(p);
    handleSelectionResize(p);
    handleSelectionMove(p);
    updateHoverHighlight(p);

    if (!io.KeyCtrl && !ImGui::IsMouseDown(ImGuiMouseButton_Right)) {
        if (ImGui::IsKeyPressed(ImGuiKey_W)) gizmoMode_ = 0;
        if (ImGui::IsKeyPressed(ImGuiKey_E)) gizmoMode_ = 1;
        if (ImGui::IsKeyPressed(ImGuiKey_R)) gizmoMode_ = 2;
    }

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

    // Left-click select (no drag) with the Select tool, or with the Vertex tool
    // when the click missed every sub-object handle (so you can pick a brush to
    // start editing / switch to another one).
    const bool vtxPassthrough =
        tool_ == Tool::Vertex && !subDragging_ && subHot_ < 0 &&
        !(subActive && subSel_ >= 0);
    if (hasDoc() && (tool_ == Tool::Select || vtxPassthrough) &&
        resizeHandle_ < 0 && resizeHot_ < 0 && moveDrag_ == 0 &&
        ImGui::IsMouseReleased(ImGuiMouseButton_Left) &&
        !ImGui::IsMouseDragPastThreshold(ImGuiMouseButton_Left, 4.0f)) {
        const ImVec2 m = ImGui::GetMousePos();
        pickAt(p, {m.x - p.contentMin.x, m.y - p.contentMin.y}, io.KeyShift);
        handlesDirty_ = true;
    }
    if (ImGui::IsKeyPressed(ImGuiKey_Escape) && !selection_.empty()) clearSelection();
    if (ImGui::IsKeyPressed(ImGuiKey_Delete)) deleteSelection();
    if (io.KeyCtrl && ImGui::IsKeyPressed(ImGuiKey_D)) duplicateSelection();

    // Arrow-key nudge along the view's axes, one grid step (Shift = 4).
    if (!selection_.empty() && !io.KeyCtrl) {
        const float step = float(gridSize_) * (io.KeyShift ? 4.0f : 1.0f);
        glm::vec3 rt, up;
        if (p.kind == ViewKind::Perspective) {
            rt = glm::normalize(glm::vec3(p.camera.right().x, p.camera.right().y, 0));
            up = glm::vec3(0, 0, 1);
        } else {
            rt = p.camera.orthoRightAxis();
            up = p.camera.orthoUpAxis();
        }
        glm::vec3 d(0);
        if (ImGui::IsKeyPressed(ImGuiKey_RightArrow)) d += rt * step;
        if (ImGui::IsKeyPressed(ImGuiKey_LeftArrow)) d -= rt * step;
        if (ImGui::IsKeyPressed(ImGuiKey_UpArrow)) d += up * step;
        if (ImGui::IsKeyPressed(ImGuiKey_DownArrow)) d -= up * step;
        if (ImGui::IsKeyPressed(ImGuiKey_PageUp)) d += glm::vec3(0, 0, step);
        if (ImGui::IsKeyPressed(ImGuiKey_PageDown)) d -= glm::vec3(0, 0, step);
        if (d != glm::vec3(0))
            nudgeSelection(glm::round(d / step) * step);  // keep on grid
    }
}

void Editor::pickAt(ViewPanel& p, const glm::vec2& px, bool additive) {
    glm::vec3 ro, rd;
    p.camera.pixelRay(px, p.contentSize, ro, rd);

    map::SolidRef best;
    float bestT = 1e30f;
    auto test = [&](const map::Solid& s, int ent, int idx) {
        float t;
        if (s.valid && !s.hidden && map::raySolid(ro, rd, s, t) && t < bestT) {
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

    // Point entities: ray vs a helper box around the origin (FGD size or +-16).
    int bestPointEnt = -1;
    for (int e = 0; e < static_cast<int>(doc_.entities().size()); ++e) {
        const auto& ent = doc_.entities()[e];
        if (!ent.solids.empty() || ent.hidden) continue;
        glm::vec3 mn(-16), mx(16);
        if (const fgd::EntityClass* ec = fgd_.flattened(ent.classname);
            ec && ec->hasSize) {
            mn = ec->sizeMin;
            mx = ec->sizeMax;
        }
        float t;
        if (map::rayAabb(ro, rd, ent.origin + mn, ent.origin + mx, t) && t < bestT) {
            bestT = t;
            bestPointEnt = e;
            best = {};
        }
    }
    if (bestPointEnt >= 0) {
        selectedEntity_ = bestPointEnt;
        selection_.clear();
        rebuildSelectionWire();
        status_ = doc_.entities()[bestPointEnt].classname + " selected";
        return;
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
    expandSelectionToGroups();
    syncSelectedEntity();
    rebuildSelectionWire();
    status_ = std::to_string(selection_.size()) + " brush(es) selected";
}

void Editor::syncSelectedEntity() {
    // If every selected solid belongs to the same real entity, treat that
    // entity as selected so its properties show; otherwise clear.
    int ent = -2;
    for (const auto& r : selection_) {
        if (ent == -2) ent = r.entity;
        else if (ent != r.entity) ent = -3;
    }
    selectedEntity_ = (ent >= 0) ? ent : -1;
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
    selectedEntity_ = -1;
    renderer_.setSelectionWire({});
    handlesDirty_ = true;
    subSel_ = -1;
    subDragging_ = false;
}

void Editor::expandSelectionToGroups() {
    std::vector<int> groups;
    for (const auto& r : selection_)
        if (const map::Solid* s = doc_.resolve(r); s && s->group > 0 && r.entity < 0)
            if (std::find(groups.begin(), groups.end(), s->group) == groups.end())
                groups.push_back(s->group);
    if (groups.empty()) return;
    const auto& ws = doc_.worldSolids();
    for (int i = 0; i < (int)ws.size(); ++i) {
        if (std::find(groups.begin(), groups.end(), ws[i].group) == groups.end())
            continue;
        map::SolidRef r{-1, i};
        if (std::find(selection_.begin(), selection_.end(), r) == selection_.end())
            selection_.push_back(r);
    }
}

void Editor::groupSelection() {
    int worldSel = 0;
    for (const auto& r : selection_) if (r.entity < 0) ++worldSel;
    if (worldSel < 2) { status_ = "Select 2+ world brushes to group."; return; }
    int gid = 0;
    for (const auto& s : doc_.worldSolids()) gid = std::max(gid, s.group);
    ++gid;
    for (const auto& r : selection_)
        if (map::Solid* s = doc_.resolve(r); s && r.entity < 0) s->group = gid;
    afterEdit("Group");
    status_ = fmt("Grouped %d brushes", worldSel);
}

void Editor::ungroupSelection() {
    int n = 0;
    for (const auto& r : selection_)
        if (map::Solid* s = doc_.resolve(r); s && s->group > 0) { s->group = 0; ++n; }
    if (n) { afterEdit("Ungroup"); status_ = "Ungrouped"; }
}

glm::vec3 Editor::selectionCenter() const {
    glm::vec3 sum(0);
    int n = 0;
    for (const auto& r : selection_)
        if (const map::Solid* s = doc_.resolve(r)) {
            sum += s->center();
            ++n;
        }
    return n ? sum / float(n) : glm::vec3(0);
}

void Editor::afterEdit(const char* label) {
    doc_.markDirty();
    history_.record(doc_, label);
    buildAndUpload(meshOpts_);
    rebuildSelectionWire();
    handlesDirty_ = true;
}

void Editor::nudgeSelection(const glm::vec3& d) {
    if (selection_.empty() || d == glm::vec3(0)) return;
    for (const auto& r : selection_)
        if (map::Solid* s = doc_.resolve(r)) s->translate(d);
    afterEdit("Move");
    status_ = "Moved selection";
}

void Editor::deleteSelection() {
    // A selected point entity (e.g. a dropped prop) deletes on its own.
    if (selection_.empty() && selectedEntity_ >= 0 &&
        selectedEntity_ < static_cast<int>(doc_.entities().size())) {
        doc_.entities().erase(doc_.entities().begin() + selectedEntity_);
        clearSelection();
        afterEdit("Delete entity");
        status_ = "Deleted entity";
        return;
    }
    if (selection_.empty()) return;

    std::vector<int> ws, ents;
    for (const auto& r : selection_) {
        if (r.entity < 0) ws.push_back(r.solid);
        else ents.push_back(r.entity);
    }
    std::sort(ws.rbegin(), ws.rend());
    for (int i : ws)
        if (i < static_cast<int>(doc_.worldSolids().size()))
            doc_.worldSolids().erase(doc_.worldSolids().begin() + i);
    std::sort(ents.rbegin(), ents.rend());
    ents.erase(std::unique(ents.begin(), ents.end()), ents.end());
    for (int i : ents)
        if (i < static_cast<int>(doc_.entities().size()))
            doc_.entities().erase(doc_.entities().begin() + i);
    const size_t n = ws.size() + ents.size();
    clearSelection();
    afterEdit("Delete");
    status_ = "Deleted " + std::to_string(n) + " object(s)";
}

void Editor::copySelection() {
    clipboard_.clear();
    for (const auto& r : selection_)
        if (const map::Solid* s = doc_.resolve(r)) clipboard_.push_back(*s);
    if (clipboard_.empty() && selectedEntity_ >= 0 &&
        selectedEntity_ < static_cast<int>(doc_.entities().size()))
        clipboardEnt_ = doc_.entities()[selectedEntity_];
    else
        clipboardEnt_.classname.clear();
    if (!clipboard_.empty() || !clipboardEnt_.classname.empty())
        status_ = "Copied " +
                  std::to_string(clipboard_.size() +
                                 (clipboardEnt_.classname.empty() ? 0 : 1)) +
                  " object(s)";
}

void Editor::pasteClipboard() {
    if (clipboard_.empty() && clipboardEnt_.classname.empty()) return;
    if (!doc_.active()) { doc_.newBlank("untitled"); history_.reset(doc_); }
    const glm::vec3 off(float(gridSize_), float(gridSize_), 0.0f);
    std::vector<map::SolidRef> sel;
    for (map::Solid s : clipboard_) {
        s.id = doc_.nextId();
        s.translate(off);
        doc_.worldSolids().push_back(std::move(s));
        sel.push_back({-1, static_cast<int>(doc_.worldSolids().size()) - 1});
    }
    if (!clipboardEnt_.classname.empty()) {
        map::MapEntity e = clipboardEnt_;
        e.id = doc_.nextId();
        e.origin += off;
        e.kv.set("origin", std::to_string((int)e.origin.x) + " " +
                               std::to_string((int)e.origin.y) + " " +
                               std::to_string((int)e.origin.z));
        for (auto& s : e.solids) { s.id = doc_.nextId(); s.translate(off); }
        doc_.entities().push_back(std::move(e));
        selectedEntity_ = static_cast<int>(doc_.entities().size()) - 1;
    }
    selection_ = sel;
    afterEdit("Paste");
    status_ = "Pasted";
}

void Editor::rotateSelection(int axis, float degrees) {
    glm::vec3 c(0.0f);
    int n = 0;
    for (const auto& r : selection_)
        if (const map::Solid* s = doc_.resolve(r)) { c += s->center(); ++n; }
    if (n == 0 && selectedEntity_ >= 0 &&
        selectedEntity_ < static_cast<int>(doc_.entities().size())) {
        // Spin a point entity's yaw via its angles key.
        auto& e = doc_.entities()[selectedEntity_];
        float p = 0, y = 0, r = 0;
        std::sscanf(e.kv.get("angles").c_str(), "%f %f %f", &p, &y, &r);
        y = std::fmod(y + degrees, 360.0f);
        e.kv.set("angles", std::to_string((int)p) + " " + std::to_string((int)y) +
                               " " + std::to_string((int)r));
        afterEdit("Rotate");
        status_ = "Rotated entity";
        return;
    }
    if (n == 0) return;
    c /= float(n);
    glm::vec3 ax(0.0f);
    ax[std::clamp(axis, 0, 2)] = 1.0f;
    glm::mat4 m(1.0f);
    m = glm::translate(m, c);
    m = glm::rotate(m, glm::radians(degrees), ax);
    m = glm::translate(m, -c);
    for (const auto& r : selection_)
        if (map::Solid* s = doc_.resolve(r)) s->transform(m);
    afterEdit("Rotate");
    status_ = "Rotated selection";
}

void Editor::duplicateSelection() {
    if (selection_.empty()) return;
    std::vector<map::SolidRef> newSel;
    for (const auto& r : selection_) {
        const map::Solid* s = doc_.resolve(r);
        if (!s || r.entity >= 0) continue;
        map::Solid copy = *s;
        copy.id = doc_.nextId();
        copy.translate(glm::vec3(float(gridSize_), float(gridSize_), 0.0f));
        doc_.worldSolids().push_back(std::move(copy));
        newSel.push_back({-1, static_cast<int>(doc_.worldSolids().size()) - 1});
    }
    selection_ = newSel;
    afterEdit("Duplicate");
    status_ = "Duplicated " + std::to_string(newSel.size()) + " brush(es)";
}

void Editor::drawSettingsWindow() {
    if (!showSettings_) return;
    using namespace pb::ui;
    ImGui::SetNextWindowSize(ImVec2(dp(460), dp(560)), ImGuiCond_FirstUseEver);
    if (!ImGui::Begin(ICON_FA_GEAR "  Options", &showSettings_,
                      ImGuiWindowFlags_NoDocking)) {
        ImGui::End();
        return;
    }
    bool dirty = false;
    auto save = [&] { if (dirty) prefs_.save(); };

    if (ImGui::CollapsingHeader("Interface", ImGuiTreeNodeFlags_DefaultOpen)) {
        const float steps[] = {0.8f, 0.9f, 1.0f, 1.1f, 1.25f, 1.5f, 1.75f, 2.0f};
        ImGui::TextUnformatted("Scale");
        for (float s : steps) {
            char b[16];
            std::snprintf(b, sizeof(b), "%d%%", (int)(s * 100 + 0.5f));
            ImGui::SameLine();
            if (ImGui::RadioButton(b, std::fabs(s - uiScale_) < 0.01f))
                requestUiScale(s);
        }
        if (ImGui::Checkbox("Show the welcome screen on startup", &prefs_.showWelcome))
            dirty = true;
    }

    if (ImGui::CollapsingHeader("Editing", ImGuiTreeNodeFlags_DefaultOpen)) {
        ImGui::SetNextItemWidth(dp(160));
        if (ImGui::SliderInt("Grid size", &prefs_.gridSize, 1, 512)) {
            gridSize_ = prefs_.gridSize;
            dirty = true;
        }
        if (ImGui::Checkbox("Snap to grid", &prefs_.snap)) {
            snap_ = prefs_.snap;
            dirty = true;
        }
        ImGui::SetNextItemWidth(dp(160));
        if (ImGui::SliderFloat("Fly speed", &prefs_.flySpeed, 100.0f, 4000.0f, "%.0f")) {
            flySpeed_ = prefs_.flySpeed;
            dirty = true;
        }
        if (ImGui::Checkbox("Autosave", &prefs_.autosave)) {
            autosaveOn_ = prefs_.autosave;
            dirty = true;
        }
        if (prefs_.autosave) {
            ImGui::SameLine();
            ImGui::SetNextItemWidth(dp(90));
            if (ImGui::SliderFloat("every (min)", &prefs_.autosaveMins, 1.0f, 30.0f,
                                   "%.0f")) {
                autosaveMins_ = prefs_.autosaveMins;
                dirty = true;
            }
        }
    }

    if (ImGui::CollapsingHeader("Viewport", ImGuiTreeNodeFlags_DefaultOpen)) {
        const char* shades[] = {"Textured + lightmap", "Lightmap grid", "Flat",
                                "Textured (fullbright)"};
        ImGui::SetNextItemWidth(dp(220));
        if (ImGui::Combo("3D shading", &prefs_.shadeMode, shades, 4)) {
            settings_.shadeMode = (ShadeMode)prefs_.shadeMode;
            dirty = true;
        }
        auto vb = [&](const char* label, bool* pv, bool* live) {
            if (ImGui::Checkbox(label, pv)) { *live = *pv; dirty = true; }
        };
        vb("Grid", &prefs_.showGrid, &settings_.showGrid);
        ImGui::SameLine();
        vb("Props", &prefs_.showProps, &settings_.showProps);
        ImGui::SameLine();
        vb("Point entities in 3D", &prefs_.showPointEntities,
           &settings_.showPointEntities);
        vb("Wire overlay (3D)", &prefs_.wireOverlay, &settings_.wireOverlay);
        ImGui::SetNextItemWidth(dp(160));
        if (ImGui::SliderFloat("Exposure", &prefs_.exposure, 0.2f, 3.0f, "%.2f")) {
            settings_.exposure = prefs_.exposure;
            dirty = true;
        }
        ImGui::SetNextItemWidth(dp(160));
        if (ImGui::SliderFloat("Lightmap gain", &prefs_.lightmapGain, 0.3f, 4.0f,
                               "%.2f")) {
            meshOpts_.lightmapGain = prefs_.lightmapGain;
            if (hasMap()) buildAndUpload(meshOpts_);
            dirty = true;
        }
    }

    if (ImGui::CollapsingHeader("Advanced")) {
        if (ImGui::Checkbox("Auto-decompile a .bsp to editable brushes on open",
                            &prefs_.autoDecompile)) {
            suppressAutoDecompile_ = !prefs_.autoDecompile;
            dirty = true;
        }
        if (ImGui::Checkbox("Render prop_static / entity models", &prefs_.bakeProps)) {
            meshOpts_.bakeProps = prefs_.bakeProps;
            if (hasMap()) buildAndUpload(meshOpts_);
            dirty = true;
        }
        ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
        ImGui::TextWrapped("Team Fortress 2 folder (leave blank to auto-detect)");
        ImGui::PopStyleColor();
        char tf[512];
        std::snprintf(tf, sizeof(tf), "%s", prefs_.tf2Dir.c_str());
        ImGui::SetNextItemWidth(-90);
        if (ImGui::InputText("##tf2dir", tf, sizeof(tf))) {
            prefs_.tf2Dir = tf;
            dirty = true;
        }
        ImGui::SameLine();
        if (ImGui::Button("Browse…##tf2")) {
            const std::string p = openFileDialog("Pick hl2.exe / tf_win64.exe in "
                                                 "the TF2 folder",
                                                 "All\0*.*\0\0", nullptr);
            if (!p.empty()) {
                prefs_.tf2Dir = fs::path(p).parent_path().string();
                dirty = true;
            }
        }
        ImGui::Dummy(ImVec2(0, 6));
        if (ImGui::Button("Reset window layout")) layoutDirty_ = true;
        ImGui::SameLine();
        if (ImGui::Button("Show shortcut list (F1)")) showKeys_ = true;
    }

    save();
    ImGui::End();
}

void Editor::drawKeysOverlay() {
    if (!showKeys_) return;
    using namespace pb::ui;
    ImGui::SetNextWindowSize(ImVec2(dp(420), 0), ImGuiCond_Appearing);
    if (ImGui::Begin(ICON_FA_KEYBOARD "  Keyboard shortcuts", &showKeys_,
                     ImGuiWindowFlags_NoDocking)) {
        struct KB { const char* k; const char* d; };
        static const KB rows[] = {
            {"Ctrl+Z / Ctrl+Y", "Undo / redo"},
            {"Ctrl+S / Ctrl+Shift+S", "Save / Save As"},
            {"Ctrl+O", "Open a map"},
            {"Ctrl+C / V / X", "Copy / paste / cut selection"},
            {"Ctrl+D", "Duplicate selection"},
            {"Ctrl+A", "Select all brushes"},
            {"Delete / Backspace", "Delete selection"},
            {"[ / ]", "Rotate selection about Z  (Shift = other way)"},
            {"drag the object", "Move it — 3D drags on the ground, Shift = up/down"},
            {"drag a corner box", "Resize that side / corner"},
            {"W / E / R", "Move / rotate / scale gizmo  (Pro, with a selection)"},
            {"F", "Frame the map / selection"},
            {"Esc", "Cancel placement / clear selection"},
            {"Ctrl+K", "Command palette"},
            {"Ctrl+B", "Build & play"},
            {"F1", "This list"},
        };
        if (ImGui::BeginTable("kb", 2, ImGuiTableFlags_SizingStretchProp)) {
            for (const auto& r : rows) {
                ImGui::TableNextRow();
                ImGui::TableNextColumn();
                ImGui::PushStyleColor(ImGuiCol_Text, col::acc);
                ImGui::TextUnformatted(r.k);
                ImGui::PopStyleColor();
                ImGui::TableNextColumn();
                ImGui::TextUnformatted(r.d);
            }
            ImGui::EndTable();
        }
    }
    ImGui::End();
}

void Editor::undo() {
    if (history_.undo(doc_)) {
        clearSelection();
        buildAndUpload(meshOpts_);
        status_ = "Undo";
    }
}

void Editor::redo() {
    if (history_.redo(doc_)) {
        clearSelection();
        buildAndUpload(meshOpts_);
        status_ = "Redo";
    }
}

void Editor::debugBuildSampleMap() {
    bsp_ = BspFile();
    doc_.newBlank("sample");
    history_.reset(doc_);
    clearSelection();
    placePiece("Room", glm::vec3(0, 0, 0));
    placePiece("RED spawn", glm::vec3(768, 0, 0));
    placePiece("BLU spawn", glm::vec3(-768, 0, 0));
    placePiece("Floor", glm::vec3(0, 512, 0));
    placePiece("Ramp", glm::vec3(0, 320, 0));
    placePiece("Pillar", glm::vec3(200, 200, 0));
    placePiece("Capture point", glm::vec3(0, 0, 0));
    placePiece("Health / ammo", glm::vec3(0, 400, 0));
    placePiece("Sun / sky", glm::vec3(0, 0, 0));
    placing_.clear();
    showWelcome_ = false;
    frameAllViews();
    PB_INFO("sample map: %zu world solids, %zu entities",
            doc_.worldSolids().size(), doc_.entities().size());
}

bool Editor::saveVmf(const std::string& path) {
    std::string err;
    const bool ok = doc_.saveVmf(path, &err);
    status_ = ok ? ("Saved " + path) : ("Save failed: " + err);
    return ok;
}

void Editor::loadFgd() {
    // Prefer the game's own tf.fgd (it @includes base.fgd + halflife2.fgd);
    // fall back to a copy bundled under assets/.
    std::string fromGame;
    if (const compile::GamePaths gp = compile::GamePaths::detect(); !gp.gameDir.empty())
        fromGame = fs::path(gp.gameDir).parent_path().string() + "/bin/tf.fgd";
    const std::string guesses[] = {
        fromGame,
        "C:/Program Files (x86)/Steam/steamapps/common/Team Fortress 2/bin/tf.fgd",
        executableDir() + "/assets/fgd/tf.fgd",
        executableDir() + "/../assets/fgd/tf.fgd",
    };
    for (const auto& g : guesses) {
        if (!g.empty() && fileExists(g) && fgd_.load(g)) return;
    }
    PB_WARN("fgd: no tf.fgd found — entity catalogue will be limited");
}

void Editor::debugDumpFgd(const std::string& cls) {
    PB_INFO("fgd: %zu classes, %zu point, %zu solid", fgd_.size(),
            fgd_.pointClasses().size(), fgd_.solidClasses().size());
    const std::string name = cls.empty() ? "info_player_teamspawn" : cls;
    const fgd::EntityClass* ec = fgd_.flattened(name);
    if (!ec) { PB_WARN("fgd: no class '%s'", name.c_str()); return; }
    PB_INFO("== %s : \"%s\"  (%zu keys, %zu inputs, %zu outputs)", ec->name.c_str(),
            ec->description.c_str(), ec->vars.size(), ec->inputs.size(),
            ec->outputs.size());
    for (const auto& v : ec->vars)
        PB_INFO("   %-22s %-10s \"%s\" = \"%s\"  (%zu choices/%zu flags)",
                v.key.c_str(), fgd::varTypeName(v.type), v.displayName.c_str(),
                v.defaultValue.c_str(), v.choices.size(), v.flags.size());
}

void Editor::debugShowWorkshop() {
    showWorkshop_ = true;
    showWelcome_ = false;
    if (wsItem_.title.empty()) wsItem_.title = doc_.name();
    wsItem_.description = "A Team Fortress 2 map built with Pootis Builder.";
}

void Editor::debugStartCompile(bool fast) {
    showCompile_ = true;
    compileProfile_ = fast ? 0 : 1;
    compileLaunch_ = false;  // never launch TF2 from a headless test
    if (!hasDoc()) return;
    if (doc_.path().empty())
        saveVmf(executableDir() + "/_compiletest.vmf");
    startCompile();
}

void Editor::debugCompileOut(const std::string& name, const std::string& dir) {
    std::snprintf(compileMapName_, sizeof(compileMapName_), "%s", name.c_str());
    std::snprintf(compileOutDir_, sizeof(compileOutDir_), "%s", dir.c_str());
}

// ---------------------------------------------------------------------------
// Milestone E — save, compile, play
// ---------------------------------------------------------------------------
bool Editor::saveMap(bool forceDialog) {
    if (!hasDoc()) {
        status_ = "Nothing to save yet.";
        return false;
    }
    std::string out = doc_.path();
    if (out.empty() || forceDialog) {
        const std::string suggested = doc_.name().empty() ? "untitled" : doc_.name();
        out = saveFileDialog("Save map as", "Hammer VMF\0*.vmf\0All files\0*.*\0",
                             suggested.c_str(), "vmf",
                             out.empty() ? nullptr : out.c_str());
        if (out.empty()) return false;  // cancelled
    }
    writeBackup(out);  // roll <out>.bak1..3 before overwriting
    std::string err;
    if (doc_.saveVmf(out, &err)) {
        status_ = "Saved  " + out;
        return true;
    }
    status_ = "Save failed: " + err;
    return false;
}

map::MapDocument Editor::buildCompileDoc() {
    map::MapDocument out = doc_;

    // Visgroup-hidden objects are left out of the compile.
    {
        auto& ws = out.worldSolids();
        ws.erase(std::remove_if(ws.begin(), ws.end(),
                                [](const map::Solid& s) { return s.hidden; }),
                 ws.end());
        auto& es = out.entities();
        es.erase(std::remove_if(es.begin(), es.end(),
                                [](const map::MapEntity& e) { return e.hidden; }),
                 es.end());
    }

    if (!cordonOn_) return out;
    const glm::vec3 mn = glm::min(cordonMin_, cordonMax_);
    const glm::vec3 mx = glm::max(cordonMin_, cordonMax_);
    auto hits = [&](const glm::vec3& bmn, const glm::vec3& bmx) {
        return bmn.x <= mx.x && bmx.x >= mn.x && bmn.y <= mx.y && bmx.y >= mn.y &&
               bmn.z <= mx.z && bmx.z >= mn.z;
    };

    auto& ws = out.worldSolids();
    ws.erase(std::remove_if(ws.begin(), ws.end(),
                            [&](const map::Solid& s) {
                                return !hits(s.boundsMin, s.boundsMax);
                            }),
             ws.end());

    auto& es = out.entities();
    es.erase(std::remove_if(es.begin(), es.end(),
                            [&](const map::MapEntity& e) {
                                if (e.solids.empty()) {
                                    return !(e.origin.x >= mn.x && e.origin.x <= mx.x &&
                                             e.origin.y >= mn.y && e.origin.y <= mx.y &&
                                             e.origin.z >= mn.z && e.origin.z <= mx.z);
                                }
                                for (const auto& s : e.solids)
                                    if (hits(s.boundsMin, s.boundsMax)) return false;
                                return true;
                            }),
             es.end());

    // Seal the region with a nodraw box shell so vbsp doesn't leak.
    const float t = 32.0f;
    map::Solid shellSrc = map::Solid::makeBox(mn - glm::vec3(t), mx + glm::vec3(t),
                                              "tools/toolsnodraw");
    for (auto& w : map::hollow(shellSrc, t)) {
        w.id = out.nextId();
        ws.push_back(std::move(w));
    }
    PB_INFO("cordon: %zu solids, %zu entities kept + 6 seal brushes",
            ws.size() - 6, es.size());
    return out;
}

void Editor::startCompile() {
    if (compiler_.running() || !hasDoc()) return;
    // A compile needs a real .vmf on disk. Save first (prompt if unsaved).
    if (doc_.path().empty()) {
        if (!saveMap(false)) {
            status_ = "Save the map before building.";
            return;
        }
    } else {
        doc_.saveVmf(doc_.path());
    }

    // With the cordon on or anything visgroup-hidden, compile a filtered copy.
    bool anyHidden = false;
    for (const auto& s : doc_.worldSolids()) anyHidden |= s.hidden;
    for (const auto& e : doc_.entities()) anyHidden |= e.hidden;

    std::string compilePath = doc_.path();
    if (cordonOn_ || anyHidden) {
        map::MapDocument cd = buildCompileDoc();
        compilePath = (fs::path(doc_.path()).parent_path() /
                       (doc_.name() + ".cordon.vmf")).string();
        std::string err;
        if (!cd.saveVmf(compilePath, &err, /*updateState=*/false)) {
            status_ = "Filtered export failed: " + err;
            return;
        }
        status_ = cordonOn_ ? "Cordon active — compiling a boxed region."
                            : "Compiling with hidden objects left out.";
    }

    if (!gamePaths_.valid()) gamePaths_ = compile::GamePaths::detect();

    compile::CompileOptions opts;
    opts.profile = compileProfile_ == 0 ? compile::Profile::Fast
                                        : compile::Profile::Final;
    opts.runVvis = compileVvis_;
    opts.runVrad = compileVrad_;
    opts.launchGame = compileLaunch_;
    opts.modelQc = pendingModelQc_;
    if (compilePack_) opts.packFiles = packFiles_;
    opts.mapName = compileMapName_;
    opts.extraOutDir = compileOutDir_;
    compileLogSeen_ = 0;
    compiler_.start(compilePath, opts, gamePaths_);
    status_ = "Compiling " + doc_.name() + " …";
}

void Editor::drawCompileWindow() {
    if (!showCompile_) return;
    using namespace pb::ui;

    ImGui::SetNextWindowSize(ImVec2(720 * uiScale_, 520 * uiScale_),
                             ImGuiCond_FirstUseEver);
    if (!ImGui::Begin(ICON_FA_PLAY "  Build & playtest", &showCompile_)) {
        ImGui::End();
        return;
    }

    const bool running = compiler_.running();

    ImGui::BeginDisabled(running);

    sectionLabel("MAP NAME & OUTPUT");
    if (compileMapName_[0] == 0 && hasDoc())
        std::snprintf(compileMapName_, sizeof(compileMapName_), "%s",
                      doc_.name().c_str());
    ImGui::SetNextItemWidth(-1);
    ImGui::InputTextWithHint("##mapname", "map file name (letters, digits, _)",
                             compileMapName_, sizeof(compileMapName_));
    ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
    ImGui::TextUnformatted("Always installed to the TF2 maps folder so you can "
                           "play it right away.");
    ImGui::PopStyleColor();
    ImGui::SetNextItemWidth(-90);
    ImGui::InputTextWithHint("##outdir", "also copy the .bsp to this folder…",
                             compileOutDir_, sizeof(compileOutDir_));
    ImGui::SameLine();
    if (ImGui::Button("Browse…##outdir")) {
        const std::string d = openFileDialog(
            "Pick any file in the target folder", "All files\0*.*\0\0", nullptr);
        if (!d.empty())
            std::snprintf(compileOutDir_, sizeof(compileOutDir_), "%s",
                          fs::path(d).parent_path().string().c_str());
    }
    ImGui::Dummy(ImVec2(0, 6));

    sectionLabel("PROFILE");
    ImGui::RadioButton("Fast  (quick, for iterating)", &compileProfile_, 0);
    ImGui::SameLine(0, 16);
    ImGui::RadioButton("Final  (full lighting)", &compileProfile_, 1);
    ImGui::Checkbox("Visibility (vvis)", &compileVvis_);
    ImGui::SameLine(0, 16);
    ImGui::Checkbox("Lighting (vrad)", &compileVrad_);
    ImGui::SameLine(0, 16);
    ImGui::Checkbox("Launch TF2 when done", &compileLaunch_);

    if (cordonOn_) {
        ImGui::PushStyleColor(ImGuiCol_Text, col::warn);
        ImGui::TextUnformatted(ICON_FA_VECTOR_SQUARE
                               "  Cordon is ON — only the boxed region compiles.");
        ImGui::PopStyleColor();
    }

    ImGui::Checkbox("Pack custom content into the .bsp (bspzip)", &compilePack_);
    if (compilePack_) {
        ImGui::Indent();
        ImGui::SetNextItemWidth(-90);
        ImGui::InputTextWithHint("##packadd", "absolute path to a material/model/sound",
                                 packAddPath_, sizeof(packAddPath_));
        ImGui::SameLine();
        if (ImGui::Button("Add##pack") && packAddPath_[0]) {
            std::string abs = packAddPath_;
            std::string internal = abs;
            for (const char* root : {"/materials/", "/models/", "/sound/"}) {
                const size_t k = internal.find(root);
                if (k != std::string::npos) { internal = internal.substr(k + 1); break; }
            }
            std::replace(internal.begin(), internal.end(), '\\', '/');
            packFiles_.push_back(internal + "|" + abs);
            packAddPath_[0] = 0;
        }
        int rm = -1;
        for (int i = 0; i < (int)packFiles_.size(); ++i) {
            ImGui::PushID(i);
            ImGui::BulletText("%s", packFiles_[i].substr(0, packFiles_[i].find('|')).c_str());
            ImGui::SameLine();
            if (ImGui::SmallButton("x")) rm = i;
            ImGui::PopID();
        }
        if (rm >= 0) packFiles_.erase(packFiles_.begin() + rm);
        ImGui::Unindent();
    }
    ImGui::EndDisabled();

    if (!gamePaths_.valid()) gamePaths_ = compile::GamePaths::detect();
    if (!gamePaths_.valid()) {
        ImGui::PushStyleColor(ImGuiCol_Text, col::warn);
        ImGui::TextWrapped(ICON_FA_TRIANGLE_EXCLAMATION
                           "  TF2 compile tools not found. Set the TF2_DIR "
                           "environment variable to your Team Fortress 2 folder.");
        ImGui::PopStyleColor();
    } else {
        ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
        ImGui::TextWrapped("%s", gamePaths_.gameDir.c_str());
        ImGui::PopStyleColor();
    }

    ImGui::Dummy(ImVec2(0, 4));
    if (running) {
        char label[96];
        std::snprintf(label, sizeof(label), ICON_FA_STOP "  Stop  (%s, %.0fs)",
                      compiler_.stage().c_str(), compiler_.elapsedSeconds());
        if (ImGui::Button(label, ImVec2(-1, 34 * uiScale_))) compiler_.cancel();
    } else {
        const bool can = hasDoc() && gamePaths_.valid();
        ImGui::BeginDisabled(!can);
        if (ImGui::Button(ICON_FA_PLAY "  Build now", ImVec2(-1, 34 * uiScale_)))
            startCompile();
        ImGui::EndDisabled();
    }

    if (!running && compiler_.finished()) {
        ImGui::PushStyleColor(ImGuiCol_Text,
                              compiler_.succeeded() ? col::good : col::warn);
        ImGui::TextUnformatted(compiler_.succeeded()
                                   ? (compiler_.launched()
                                          ? ICON_FA_CHECK "  Built and launched."
                                          : ICON_FA_CHECK "  Build finished.")
                                   : ICON_FA_XMARK "  Build failed — see the log.");
        ImGui::PopStyleColor();
    }

    ImGui::Dummy(ImVec2(0, 4));
    sectionLabel("LOG");
    ImGui::SameLine();
    ImGui::Checkbox("follow", &compileAutoScroll_);
    if (fontMono) ImGui::PushFont(fontMono);
    ImGui::PushStyleColor(ImGuiCol_ChildBg, col::bg0);
    if (ImGui::BeginChild("##compilelog", ImVec2(0, 0), ImGuiChildFlags_Borders)) {
        const std::vector<std::string> lines = compiler_.log();
        ImGuiListClipper clip;
        clip.Begin(static_cast<int>(lines.size()));
        while (clip.Step())
            for (int i = clip.DisplayStart; i < clip.DisplayEnd; ++i)
                ImGui::TextUnformatted(lines[i].c_str());
        if (compileAutoScroll_ && lines.size() != compileLogSeen_) {
            ImGui::SetScrollHereY(1.0f);
            compileLogSeen_ = lines.size();
        }
    }
    ImGui::EndChild();
    ImGui::PopStyleColor();
    if (fontMono) ImGui::PopFont();

    ImGui::End();
}

void Editor::debugPlaceEntity(const std::string& cls) {
    if (!doc_.active()) { doc_.newBlank("enttest"); history_.reset(doc_); }
    placeFgdEntity(cls, glm::vec3(0, 0, 0));
    showWelcome_ = false;
    PB_INFO("placed %s -> entity %d, %zu keys", cls.c_str(), selectedEntity_,
            selectedEntity_ >= 0 ? doc_.entities()[selectedEntity_].kv.pairs.size() : 0);
}

void Editor::debugSelectEntity(int i) {
    if (i >= 0 && i < static_cast<int>(doc_.entities().size())) {
        selectedEntity_ = i;
        selection_.clear();
        mode_ = Mode::Pro;
        layoutDirty_ = true;
        status_ = "Selected entity " + std::to_string(i) + " (" +
                  doc_.entities()[i].classname + ")";
    }
}

void Editor::debugDumpProps() {
    std::vector<std::string> seen;
    for (size_t i = 0; i < mesh_.props.size(); ++i) {
        const auto& p = mesh_.props[i];
        if (p.model.empty()) continue;
        PB_INFO("prop[%zu] '%s'  pos=(%.0f %.0f %.0f) ang=(%.0f %.0f %.0f) scale=%.2f",
                i, p.model.c_str(), p.pos.x, p.pos.y, p.pos.z, p.anglesPYR.x,
                p.anglesPYR.y, p.anglesPYR.z, p.scale);
        if (std::find(seen.begin(), seen.end(), p.model) != seen.end()) continue;
        seen.push_back(p.model);
        const model::StudioModel& sm = model::loadStudioModel(sourceFs_, p.model);
        const glm::vec3 ext = sm.boundsMax - sm.boundsMin;
        const float span = std::max({ext.x, ext.y, ext.z});
        if (!sm.ok || span > 500.0f || sm.meshes.size() > 6)
            model::debugDumpModel(sourceFs_, p.model);
    }
    PB_INFO("debugDumpProps: %zu instances, %zu unique models", mesh_.props.size(),
            seen.size());
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

void Editor::debugShapeOp(int op) {
    // Build a fresh 2-brush scene so the result is easy to read.
    bsp_ = BspFile();
    doc_.newBlank("shapeop");
    history_.reset(doc_);
    clearSelection();
    doc_.worldSolids().push_back(
        map::Solid::makeBox({-256, -256, 0}, {256, 256, 256},
                            "dev/dev_measuregeneric01b"));
    doc_.worldSolids().back().id = doc_.nextId();
    if (op == 1) {  // carve needs a second (cutter) brush overlapping the first
        doc_.worldSolids().push_back(
            map::Solid::makeBox({-64, -64, 64}, {64, 64, 400},
                                "dev/dev_measurewall01a"));
        doc_.worldSolids().back().id = doc_.nextId();
    }
    mode_ = Mode::Pro;
    showWelcome_ = false;
    buildAndUpload(meshOpts_);

    if (op == 0) {
        for (auto& w : map::hollow(doc_.worldSolids()[0], 24.0f)) {
            w.id = doc_.nextId();
            doc_.worldSolids().push_back(std::move(w));
        }
        doc_.worldSolids().erase(doc_.worldSolids().begin());
    } else if (op == 1) {
        map::Solid cutter = doc_.worldSolids()[1];
        std::vector<map::Solid> rebuilt;
        auto pieces = map::carve(doc_.worldSolids()[0], cutter);
        for (auto& pc : pieces) {
            pc.id = doc_.nextId();
            rebuilt.push_back(std::move(pc));
        }
        doc_.worldSolids() = std::move(rebuilt);
    } else {
        doc_.worldSolids()[0].clip(glm::normalize(glm::vec3(1, 1, 0)), 0.0f,
                                   "dev/dev_measurewall01a");
    }
    int valid = 0;
    for (const auto& s : doc_.worldSolids()) valid += s.valid ? 1 : 0;
    afterEdit("shape op demo");
    frameAllViews();
    PB_INFO("shape-op %d: %zu solids, %d valid", op, doc_.worldSolids().size(), valid);
}

void Editor::debugTextureDemo(int solidIdx) {
    debugSelectWorldSolid(solidIdx);
    mode_ = Mode::Pro;
    tool_ = Tool::Texture;
    layoutDirty_ = true;
    texFaces_.clear();
    const map::Solid* s = doc_.resolve(selection_[0]);
    if (!s) return;
    for (int fi = 0; fi < (int)s->faces.size() && fi < 3; ++fi)
        texFaces_.push_back({{-1, solidIdx}, fi});
    if (!s->faces.empty())
        std::snprintf(texMaterial_, sizeof(texMaterial_), "%s",
                      s->faces[0].material.c_str());
    selection_.clear();  // texture tool works on faces, not the whole brush
    PB_INFO("texture demo: solid %d, %zu faces picked", solidIdx, texFaces_.size());
}

void Editor::debugSubObjectDemo(int solidIdx, int mode) {
    debugSelectWorldSolid(solidIdx);
    tool_ = Tool::Vertex;
    mode_ = Mode::Pro;
    layoutDirty_ = true;
    subMode_ = static_cast<SubMode>(std::clamp(mode, 0, 2));
    handlesDirty_ = true;
    rebuildHandles();
    map::Solid* s = doc_.resolve(selection_[0]);
    if (!s || handles_.verts.empty()) return;
    // Deform: lift handle 0 (and its sub-object group) by +96 on Z.
    subSel_ = 0;
    std::vector<int> vidx;
    if (subMode_ == SubMode::Vertex) vidx = {0};
    else if (subMode_ == SubMode::Edge)
        vidx = {handles_.edges[0].a, handles_.edges[0].b};
    else vidx = handles_.faces[0].verts;
    map::moveVertexHandles(*s, handles_, vidx, glm::vec3(0, 0, 96));
    afterEdit("Edit vertex (demo)");
    rebuildHandles();
    subSel_ = 0;
    PB_INFO("sub-object demo: solid %d, mode %d, %zu verts / %zu edges / %zu faces",
            solidIdx, mode, handles_.verts.size(), handles_.edges.size(),
            handles_.faces.size());
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
              std::string* status, std::string* dragOut = nullptr) {
    using pb::ui::dp;
    const float gap = dp(8.0f);
    const float avail = ImGui::GetContentRegionAvail().x;
    const float cellW = (avail - gap) * 0.5f;
    // Tall enough for the icon+name row plus two wrapped hint lines at any scale.
    const float cellH = ImGui::GetTextLineHeight() * 3.4f + dp(16.0f);
    for (int i = 0; i < count; ++i) {
        if (i % 2) ImGui::SameLine(0, gap);
        ImGui::PushID(i);
        const bool on = *placing == pieces[i].name;
        ImGui::PushStyleColor(ImGuiCol_Button, on ? pb::ui::col::bg3 : pb::ui::col::bg2);
        ImGui::PushStyleColor(ImGuiCol_Border, on ? pb::ui::col::acc : pb::ui::col::bd);
        if (ImGui::BeginChild("card", ImVec2(cellW, cellH),
                              ImGuiChildFlags_Borders | ImGuiChildFlags_FrameStyle)) {
            ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::acc);
            ImGui::TextUnformatted(pieces[i].icon);
            ImGui::PopStyleColor();
            ImGui::SameLine(0, dp(8.0f));
            if (pb::ui::fontUiMed) ImGui::PushFont(pb::ui::fontUiMed);
            ImGui::TextUnformatted(pieces[i].name);
            if (pb::ui::fontUiMed) ImGui::PopFont();
            ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::faint);
            ImGui::PushTextWrapPos(0.0f);
            ImGui::TextUnformatted(pieces[i].hint);
            ImGui::PopTextWrapPos();
            ImGui::PopStyleColor();
        }
        ImGui::EndChild();
        if (ImGui::BeginDragDropSource(ImGuiDragDropFlags_SourceAllowNullID)) {
            ImGui::SetDragDropPayload("PB_KIT", pieces[i].name,
                                     std::strlen(pieces[i].name) + 1);
            ImGui::Text("%s  %s", pieces[i].icon, pieces[i].name);
            ImGui::EndDragDropSource();
            if (dragOut) *dragOut = std::string("@kit:") + pieces[i].name;
        }
        if (ImGui::IsItemClicked()) {
            *placing = pieces[i].name;
            *status = std::string("Placing ") + pieces[i].name +
                      " — click a viewport, or drag me there.";
        }
        if (ImGui::IsItemHovered())
            ImGui::SetTooltip("%s\n%s", pieces[i].name, pieces[i].hint);
        ImGui::PopStyleColor(2);
        ImGui::PopID();
    }
}

}  // namespace

void Editor::debugImportObj(const std::string& path) {
    if (!doc_.active()) { doc_.newBlank("objtest"); history_.reset(doc_); }
    modelImportPath_ = path;
    // "path" may carry a ":prop" suffix to exercise the prop-staging path.
    if (path.size() > 5 && path.substr(path.size() - 5) == ":prop") {
        modelImportPath_ = path.substr(0, path.size() - 5);
        modelPlaceOpts_.mode = import::ModelPlacement::Prop;
    } else {
        modelPlaceOpts_.mode = import::ModelPlacement::DetailBrush;
    }
    reloadModelPreview();
    doModelImport();
    showWelcome_ = false;
    frameAllViews();
}

void Editor::openModelImport() {
    const std::string picked = openFileDialog(
        "Import a 3D model",
        "Wavefront OBJ (*.obj)\0*.obj\0All files\0*.*\0\0", nullptr);
    if (picked.empty()) return;
    modelImportPath_ = picked;
    modelImportErr_.clear();
    if (!selection_.empty())
        modelPlaceOpts_.origin = snapVec(selectionCenter());
    reloadModelPreview();
    showModelImport_ = true;
}

void Editor::reloadModelPreview() {
    if (modelImportPath_.empty()) return;
    modelImportErr_.clear();
    if (!import::loadObj(modelImportPath_, modelLoadOpts_, modelPreview_,
                         &modelImportErr_))
        modelPreview_ = import::ObjMesh{};
}

void Editor::doModelImport() {
    if (modelPreview_.empty()) {
        status_ = modelImportErr_.empty() ? "Load a model first." : modelImportErr_;
        return;
    }
    if (!doc_.active()) doc_.newBlank("untitled");
    std::string err;

    if (modelPlaceOpts_.mode == import::ModelPlacement::DetailBrush) {
        map::MapEntity ent;
        if (!import::meshToDetailEntity(modelPreview_, modelPlaceOpts_, doc_, ent,
                                        &err)) {
            modelImportErr_ = err;
            status_ = "Import failed: " + err;
            return;
        }
        doc_.entities().push_back(std::move(ent));
        const int ei = static_cast<int>(doc_.entities().size()) - 1;
        selection_.clear();
        for (size_t s = 0; s < doc_.entities()[ei].solids.size(); ++s)
            selection_.push_back({ei, static_cast<int>(s)});
        afterEdit("Import model (detail)");
        status_ = "Imported " + modelPreview_.name + " as " +
                  std::to_string(doc_.entities()[ei].solids.size()) +
                  " detail brushes";
    } else {
        std::string stageDir = "PootisBuilder/models";
        if (const char* la = std::getenv("LOCALAPPDATA"))
            stageDir = std::string(la) + "/PootisBuilder/models/" +
                       (doc_.name().empty() ? "untitled" : doc_.name());
        std::string modelPath, qcPath;
        if (!import::meshToPropStage(modelPreview_, modelPlaceOpts_, stageDir,
                                     modelPath, qcPath, &err)) {
            modelImportErr_ = err;
            status_ = "Import failed: " + err;
            return;
        }
        map::MapEntity e;
        e.id = doc_.nextId();
        e.classname = "prop_static";
        e.origin = modelPlaceOpts_.origin;
        e.kv.set("classname", "prop_static");
        e.kv.set("origin", std::to_string((int)e.origin.x) + " " +
                               std::to_string((int)e.origin.y) + " " +
                               std::to_string((int)e.origin.z));
        e.kv.set("model", modelPath);
        e.kv.set("solidity", "2");
        doc_.entities().push_back(std::move(e));
        if (std::find(pendingModelQc_.begin(), pendingModelQc_.end(), qcPath) ==
            pendingModelQc_.end())
            pendingModelQc_.push_back(qcPath);
        afterEdit("Import model (prop)");
        status_ = "Staged prop " + modelPath + " — it bakes on the next Build.";
    }
    showModelImport_ = false;
}

void Editor::drawModelImportDialog() {
    if (!showModelImport_) return;
    using namespace pb::ui;

    ImGui::SetNextWindowSize(ImVec2(460 * uiScale_, 0), ImGuiCond_Always);
    if (!ImGui::Begin(ICON_FA_CUBE "  Import 3D model", &showModelImport_,
                      ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoDocking)) {
        ImGui::End();
        return;
    }

    // File row
    char buf[512];
    std::snprintf(buf, sizeof(buf), "%s", modelImportPath_.c_str());
    ImGui::SetNextItemWidth(-90 * uiScale_);
    ImGui::InputText("##mpath", buf, sizeof(buf), ImGuiInputTextFlags_ReadOnly);
    ImGui::SameLine();
    if (ImGui::Button("Browse…", ImVec2(-1, 0))) {
        const std::string p = openFileDialog(
            "Import a 3D model", "Wavefront OBJ (*.obj)\0*.obj\0All files\0*.*\0\0",
            nullptr);
        if (!p.empty()) { modelImportPath_ = p; reloadModelPreview(); }
    }

    if (!modelImportErr_.empty()) {
        ImGui::PushStyleColor(ImGuiCol_Text, col::warn);
        ImGui::TextWrapped(ICON_FA_TRIANGLE_EXCLAMATION "  %s", modelImportErr_.c_str());
        ImGui::PopStyleColor();
    }
    if (!modelPreview_.empty()) {
        const glm::vec3 s = modelPreview_.size();
        ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
        ImGui::Text("%zu triangles   ·   %.0f × %.0f × %.0f units",
                    modelPreview_.tris.size(), s.x, s.y, s.z);
        ImGui::PopStyleColor();
    }

    ImGui::Dummy(ImVec2(0, 4));
    sectionLabel("ORIENTATION & SCALE");
    bool reload = false;
    reload |= ImGui::DragFloat("Scale", &modelLoadOpts_.scale, 0.01f, 0.001f,
                               10000.0f, "%.3f×", ImGuiSliderFlags_Logarithmic);
    reload |= ImGui::Checkbox("Model is Y-up (convert to Source Z-up)",
                              &modelLoadOpts_.yUpToZUp);
    reload |= ImGui::Checkbox("Flip face winding", &modelLoadOpts_.flipWinding);
    reload |= ImGui::Checkbox("Recompute normals from faces",
                              &modelLoadOpts_.recomputeNormals);
    if (reload) reloadModelPreview();

    ImGui::Dummy(ImVec2(0, 4));
    sectionLabel("PLACE AS");
    const int mode = static_cast<int>(modelPlaceOpts_.mode);
    const char* const modes[] = {"Detail brushwork", "Prop model"};
    const int mr = segmented("mimode", modes, 2, mode, 26 * uiScale_);
    if (mr >= 0) modelPlaceOpts_.mode = static_cast<import::ModelPlacement>(mr);

    if (modelPlaceOpts_.mode == import::ModelPlacement::DetailBrush) {
        ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
        ImGui::TextWrapped(
            "One convex brush per triangle, grouped as func_detail and written "
            "straight into the .vmf. Best for low-poly / blocky meshes.");
        ImGui::PopStyleColor();
        char m[256];
        std::snprintf(m, sizeof(m), "%s", modelPlaceOpts_.material.c_str());
        ImGui::SetNextItemWidth(-1);
        if (ImGui::InputText("Material", m, sizeof(m))) modelPlaceOpts_.material = m;
        ImGui::DragFloat("Shell depth", &modelPlaceOpts_.shellThickness, 0.25f, 0.5f,
                         64.0f, "%.1f u");
        ImGui::DragInt("Max triangles", &modelPlaceOpts_.maxTris, 32, 64, 32768);
        if ((int)modelPreview_.tris.size() > modelPlaceOpts_.maxTris) {
            ImGui::PushStyleColor(ImGuiCol_Text, col::warn);
            ImGui::TextWrapped(ICON_FA_TRIANGLE_EXCLAMATION
                               "  Over the limit — simplify the mesh or raise it.");
            ImGui::PopStyleColor();
        }
    } else {
        ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
        ImGui::TextWrapped(
            "Staged as an SMD + QC and baked to models/%s/<name>.mdl by "
            "studiomdl on the next Build. Placed as prop_static.",
            modelPlaceOpts_.propDir.c_str());
        ImGui::PopStyleColor();
    }

    ImGui::Dummy(ImVec2(0, 4));
    ImGui::DragFloat3("Origin", &modelPlaceOpts_.origin.x, 1.0f, 0, 0, "%.0f");

    ImGui::Dummy(ImVec2(0, 8));
    ImGui::BeginDisabled(modelPreview_.empty());
    if (ImGui::Button(ICON_FA_CHECK "  Import", ImVec2(140 * uiScale_, 0)))
        doModelImport();
    ImGui::EndDisabled();
    ImGui::SameLine();
    if (ImGui::Button("Cancel", ImVec2(100 * uiScale_, 0))) showModelImport_ = false;

    ImGui::End();
}

void Editor::captureWorkshopPreview() {
    std::vector<uint8_t> rgba;
    if (!renderToImage(ViewKind::Perspective, 1200, 900, rgba)) {
        wsErr_ = "could not capture the 3D view";
        return;
    }
    std::string dir = executableDir();
    if (const char* la = std::getenv("LOCALAPPDATA"))
        dir = std::string(la) + "/PootisBuilder/workshop";
    std::error_code ec;
    fs::create_directories(dir, ec);
    const std::string path =
        dir + "/" + (doc_.name().empty() ? "map" : doc_.name()) + "_preview.jpg";
    if (!stbi_write_jpg(path.c_str(), 1200, 900, 4, rgba.data(), 90)) {
        wsErr_ = "could not write " + path;
        return;
    }
    wsItem_.previewImage = path;
    wsErr_.clear();
    status_ = "Captured Workshop preview";
}

void Editor::drawWorkshopWindow() {
    if (!showWorkshop_) return;
    using namespace pb::ui;

    ImGui::SetNextWindowSize(ImVec2(560 * uiScale_, 640 * uiScale_),
                             ImGuiCond_FirstUseEver);
    if (!ImGui::Begin(ICON_FA_CLOUD_ARROW_UP "  Publish to Steam Workshop",
                      &showWorkshop_, ImGuiWindowFlags_NoDocking)) {
        ImGui::End();
        return;
    }

    ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
    ImGui::TextWrapped(
        "Prepares your compiled map as a Steam Workshop submission for Team "
        "Fortress 2. Nothing is uploaded until you press the upload button and "
        "confirm.");
    ImGui::PopStyleColor();
    ImGui::Dummy(ImVec2(0, 6));

    // ---- content (.bsp) ------------------------------------------------
    if (gamePaths_.gameDir.empty()) gamePaths_ = compile::GamePaths::detect();
    const std::string mapName = doc_.name().empty() ? "untitled" : doc_.name();
    std::string bsp = wsItem_.bspPath;
    if (bsp.empty() && !gamePaths_.gameDir.empty())
        bsp = gamePaths_.gameDir + "/maps/" + mapName + ".bsp";
    const bool haveBsp = !bsp.empty() && fileExists(bsp);
    wsItem_.bspPath = bsp;

    sectionLabel("MAP CONTENT");
    if (haveBsp) {
        ImGui::PushStyleColor(ImGuiCol_Text, col::good);
        ImGui::TextUnformatted(ICON_FA_CHECK);
        ImGui::PopStyleColor();
        ImGui::SameLine(0, 8);
        ImGui::TextWrapped("%s", bsp.c_str());
    } else {
        ImGui::PushStyleColor(ImGuiCol_Text, col::warn);
        ImGui::TextWrapped(ICON_FA_TRIANGLE_EXCLAMATION
                           "  No compiled .bsp yet — run Build & play (final "
                           "profile) first, then come back here.");
        ImGui::PopStyleColor();
    }

    ImGui::Dummy(ImVec2(0, 6));
    sectionLabel("PREVIEW IMAGE");
    if (!wsItem_.previewImage.empty() && fileExists(wsItem_.previewImage)) {
        ImGui::TextWrapped("%s", wsItem_.previewImage.c_str());
    } else {
        ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
        ImGui::TextUnformatted("none set");
        ImGui::PopStyleColor();
    }
    if (ImGui::Button(ICON_FA_CAMERA "  Capture from 3D view")) captureWorkshopPreview();
    ImGui::SameLine();
    if (ImGui::Button("Browse…##wsprev")) {
        const std::string p = openFileDialog(
            "Preview image", "Images\0*.jpg;*.jpeg;*.png\0All files\0*.*\0\0", nullptr);
        if (!p.empty()) wsItem_.previewImage = p;
    }

    ImGui::Dummy(ImVec2(0, 6));
    sectionLabel("DETAILS");
    char title[128];
    std::snprintf(title, sizeof(title), "%s", wsItem_.title.c_str());
    ImGui::SetNextItemWidth(-1);
    if (ImGui::InputTextWithHint("##wstitle", "Title", title, sizeof(title)))
        wsItem_.title = title;

    static char descBuf[4096];
    std::snprintf(descBuf, sizeof(descBuf), "%s", wsItem_.description.c_str());
    ImGui::SetNextItemWidth(-1);
    if (ImGui::InputTextMultiline("##wsdesc", descBuf, sizeof(descBuf),
                                  ImVec2(-1, 90 * uiScale_)))
        wsItem_.description = descBuf;
    ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
    ImGui::TextUnformatted("Description");
    ImGui::PopStyleColor();

    char note[256];
    std::snprintf(note, sizeof(note), "%s", wsItem_.changeNote.c_str());
    ImGui::SetNextItemWidth(-1);
    if (ImGui::InputTextWithHint("##wsnote", "Change note", note, sizeof(note)))
        wsItem_.changeNote = note;

    // ---- visibility --------------------------------------------------
    const char* vis[] = {"Public", "Friends only", "Unlisted", "Private (hidden)"};
    int v = static_cast<int>(wsItem_.visibility);
    ImGui::SetNextItemWidth(220 * uiScale_);
    if (ImGui::Combo("Visibility", &v, vis, IM_ARRAYSIZE(vis)))
        wsItem_.visibility = static_cast<publish::Visibility>(v);

    // ---- tags ------------------------------------------------------
    sectionLabel("TAGS");
    auto tagChk = [&](const char* t) {
        bool on = std::find(wsItem_.tags.begin(), wsItem_.tags.end(), t) !=
                  wsItem_.tags.end();
        if (ImGui::Checkbox(t, &on)) {
            auto it = std::find(wsItem_.tags.begin(), wsItem_.tags.end(), t);
            if (on && it == wsItem_.tags.end()) wsItem_.tags.push_back(t);
            if (!on && it != wsItem_.tags.end()) wsItem_.tags.erase(it);
        }
    };
    tagChk("Map");
    ImGui::SameLine(); tagChk("Capture the Flag");
    ImGui::SameLine(); tagChk("Control Point");
    tagChk("Payload");
    ImGui::SameLine(); tagChk("King of the Hill");
    ImGui::SameLine(); tagChk("Attack / Defense");

    // ---- existing item id ----------------------------------------
    sectionLabel("UPDATE AN EXISTING ITEM  (optional)");
    ImGui::SetNextItemWidth(240 * uiScale_);
    ImGui::InputTextWithHint("##wsid", "publishedfileid (leave blank = new)",
                             wsIdBuf_, sizeof(wsIdBuf_));
    wsItem_.publishedFileId = std::strtoull(wsIdBuf_, nullptr, 10);

    ImGui::Dummy(ImVec2(0, 10));
    ImGui::Separator();
    ImGui::Dummy(ImVec2(0, 4));

    // ---- stage + upload ----------------------------------------
    ImGui::BeginDisabled(!haveBsp || wsItem_.title.empty());
    if (ImGui::Button(ICON_FA_BOX_ARCHIVE "  Prepare submission",
                      ImVec2(200 * uiScale_, 0))) {
        std::string dir = executableDir();
        if (const char* la = std::getenv("LOCALAPPDATA"))
            dir = std::string(la) + "/PootisBuilder/workshop/" + mapName;
        wsErr_.clear();
        wsStagedOk_ = publish::stageItem(wsItem_, dir, wsStaged_, &wsErr_);
        status_ = wsStagedOk_ ? "Workshop item staged" : ("Staging failed: " + wsErr_);
    }
    ImGui::EndDisabled();

    if (!wsErr_.empty()) {
        ImGui::PushStyleColor(ImGuiCol_Text, col::warn);
        ImGui::TextWrapped(ICON_FA_TRIANGLE_EXCLAMATION "  %s", wsErr_.c_str());
        ImGui::PopStyleColor();
    }

    if (wsStagedOk_) {
        ImGui::Dummy(ImVec2(0, 4));
        ImGui::PushStyleColor(ImGuiCol_Text, col::good);
        ImGui::TextWrapped(ICON_FA_CHECK "  Staged at %s", wsStaged_.itemDir.c_str());
        ImGui::PopStyleColor();

        const std::string steamcmd = publish::findSteamcmd();
        ImGui::Dummy(ImVec2(0, 4));
        sectionLabel("OPTION A — steamcmd  (recommended)");
        ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
        ImGui::TextWrapped(
            steamcmd.empty()
                ? "steamcmd not found. Install it, then run this from a terminal:"
                : "Run this from a terminal (it will prompt for your Steam login):");
        ImGui::PopStyleColor();
        static char userBuf[64];
        std::snprintf(userBuf, sizeof(userBuf), "%s", wsUserBuf_);
        ImGui::SetNextItemWidth(200 * uiScale_);
        if (ImGui::InputTextWithHint("Steam login", "account name", userBuf,
                                     sizeof(userBuf)))
            std::snprintf(wsUserBuf_, sizeof(wsUserBuf_), "%s", userBuf);
        const std::string cmd =
            publish::steamcmdCommand(steamcmd, wsStaged_.vdfPath, wsUserBuf_);
        char cmdShow[1024];
        std::snprintf(cmdShow, sizeof(cmdShow), "%s", cmd.c_str());
        ImGui::SetNextItemWidth(-1);
        ImGui::InputText("##wscmd", cmdShow, sizeof(cmdShow),
                         ImGuiInputTextFlags_ReadOnly);
        if (ImGui::Button(ICON_FA_COPY "  Copy command"))
            ImGui::SetClipboardText(cmd.c_str());
        ImGui::SameLine();
        if (ImGui::Button(ICON_FA_FOLDER_OPEN "  Open item folder")) {
            const std::string q = "\"" + wsStaged_.itemDir + "\"";
            std::system(("explorer " + q).c_str());
        }

        ImGui::Dummy(ImVec2(0, 6));
        sectionLabel("OPTION B — in-editor upload");
        if (publish::haveInProcessUpload()) {
            if (ImGui::Button(ICON_FA_CLOUD_ARROW_UP "  Upload now"))
                ImGui::OpenPopup("confirmUpload");
        } else {
            ImGui::BeginDisabled(true);
            ImGui::Button(ICON_FA_CLOUD_ARROW_UP "  Upload now");
            ImGui::EndDisabled();
            ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
            ImGui::TextWrapped(
                "Needs the Steamworks SDK: drop steam_api64.dll + the SDK next to "
                "the exe and rebuild with PB_HAVE_STEAMWORKS. Until then use "
                "steamcmd above.");
            ImGui::PopStyleColor();
        }
        if (ImGui::BeginPopupModal("confirmUpload", nullptr,
                                   ImGuiWindowFlags_AlwaysAutoResize)) {
            ImGui::Text("Upload \"%s\" to the PUBLIC Steam Workshop?",
                        wsItem_.title.c_str());
            ImGui::TextDisabled("Visibility: %s",
                                publish::visibilityName(wsItem_.visibility));
            ImGui::Dummy(ImVec2(0, 6));
            if (ImGui::Button("Upload", ImVec2(120, 0))) {
                float pr = 0;
                std::string st;
                wsErr_.clear();
                publish::uploadInProcess(wsItem_, wsStaged_, &pr, &st, &wsErr_);
                if (!wsErr_.empty()) status_ = wsErr_;
                ImGui::CloseCurrentPopup();
            }
            ImGui::SameLine();
            if (ImGui::Button("Cancel", ImVec2(120, 0))) ImGui::CloseCurrentPopup();
            ImGui::EndPopup();
        }

        ImGui::Dummy(ImVec2(0, 4));
        if (ImGui::Button(ICON_FA_UP_RIGHT_FROM_SQUARE "  Open TF2 Workshop page"))
            std::system("start https://steamcommunity.com/app/440/workshop/");
    }

    ImGui::End();
}

void Editor::drawBuildKit() {
    ImGui::Begin("Build Kit");

    if (pb::ui::fontUiMed) ImGui::PushFont(pb::ui::fontUiMed);
    ImGui::TextUnformatted(hasMap() ? bsp_.name().c_str() : "New map");
    if (pb::ui::fontUiMed) ImGui::PopFont();
    ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::faint);
    ImGui::TextWrapped("Pick a piece, then click in a viewport. Everything snaps to the grid.");
    ImGui::PopStyleColor();
    ImGui::Dummy(ImVec2(0, 4));

    if (ImGui::BeginTabBar("kit", ImGuiTabBarFlags_FittingPolicyScroll |
                                      ImGuiTabBarFlags_TabListPopupButton)) {
        if (ImGui::BeginTabItem(ICON_FA_CUBE " Shapes")) {
            static const KitPiece shapes[] = {
                {ICON_FA_BORDER_ALL, "Floor", "Walkable ground area"},
                {ICON_FA_SQUARE, "Wall", "Solid cover"},
                {ICON_FA_TABLE_CELLS_LARGE, "Room", "4 walls + floor + ceiling"},
                {ICON_FA_DIAGRAM_PROJECT, "Ramp", "Change height smoothly"},
                {ICON_FA_GRIP, "Pillar", "Vertical cover"},
                {ICON_FA_MOUND, "Hill", "Faceted mountain / mound of brushwork"},
                {ICON_FA_ROAD, "Curvy road", "Click points, get a smooth road ribbon"},
            };
            ImGui::Dummy(ImVec2(0, 4));
            kitCards(shapes, IM_ARRAYSIZE(shapes), &placing_, &status_, &dragPlace_);
            ImGui::EndTabItem();
        }
        if (ImGui::BeginTabItem(ICON_FA_ARROW_POINTER " Play")) {
            static const KitPiece play[] = {
                {ICON_FA_ARROW_POINTER, "RED spawn", "Team RED respawn room"},
                {ICON_FA_ARROW_POINTER, "BLU spawn", "Team BLU respawn room"},
                {ICON_FA_SQUARE, "Capture point", "Control point + trigger"},
                {ICON_FA_DIAGRAM_PROJECT, "Payload track", "path_track for the cart"},
                {ICON_FA_PLAY, "Resupply", "Regenerate locker"},
                {ICON_FA_LIGHTBULB, "Health / ammo", "Pickup near a route"},
            };
            ImGui::Dummy(ImVec2(0, 4));
            kitCards(play, IM_ARRAYSIZE(play), &placing_, &status_, &dragPlace_);
            ImGui::EndTabItem();
        }
        const ImGuiTabItemFlags tf =
            kitTab_ == 1 ? ImGuiTabItemFlags_SetSelected : 0;
        if (ImGui::BeginTabItem(ICON_FA_BOLT " Things", nullptr, tf)) {
            kitTab_ = 0;  // consume the one-shot
            ImGui::Dummy(ImVec2(0, 4));
            drawSimpleEntities();
            ImGui::EndTabItem();
        }
        if (ImGui::BeginTabItem(ICON_FA_IMAGE " Props")) {
            ImGui::Dummy(ImVec2(0, 4));
            drawModelGrid();
            ImGui::EndTabItem();
        }
        if (ImGui::BeginTabItem(ICON_FA_LIGHTBULB " Light")) {
            static const KitPiece lights[] = {
                {ICON_FA_LIGHTBULB, "Point light", "Local glow"},
                {ICON_FA_LIGHTBULB, "Spot light", "Directional cone"},
                {ICON_FA_LIGHTBULB, "Sun / sky", "light_environment"},
            };
            ImGui::Dummy(ImVec2(0, 4));
            kitCards(lights, IM_ARRAYSIZE(lights), &placing_, &status_, &dragPlace_);
            ImGui::EndTabItem();
        }
        ImGui::EndTabBar();
    }

    ImGui::Dummy(ImVec2(0, 8));
    ImGui::Separator();
    pb::ui::sectionLabel("MAP CHECKLIST");

    const bool useDoc = hasDoc();
    auto countClass = [&](const char* cls) {
        int n = 0;
        if (useDoc) {
            for (const auto& e : doc_.entities())
                if (e.classname == cls) ++n;
        } else {
            for (const auto& e : bsp_.entities()) {
                auto it = e.find("classname");
                if (it != e.end() && it->second == cls) ++n;
            }
        }
        return n;
    };
    auto anyClassPrefix = [&](const char* pfx) {
        const size_t n = std::strlen(pfx);
        if (useDoc) {
            for (const auto& e : doc_.entities())
                if (e.classname.compare(0, n, pfx) == 0) return true;
        } else {
            for (const auto& e : bsp_.entities()) {
                auto it = e.find("classname");
                if (it != e.end() && it->second.compare(0, n, pfx) == 0) return true;
            }
        }
        return false;
    };
    std::string skyname;
    if (useDoc) {
        skyname = doc_.worldExtra().get("skyname");
    } else if (const auto* ws = bsp_.worldspawn()) {
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

void Editor::drawBrushInspector() {
    if (selection_.empty()) {
        ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::faint);
        ImGui::TextWrapped(hasDoc()
                               ? "Click a brush to select it. Drag the gizmo to move "
                                 "it (W move / E rotate / R scale), or type exact "
                                 "sizes below."
                               : "Decompiling… the editable brushes appear here.");
        ImGui::PopStyleColor();
        return;
    }

    // Combined bounds of the selection.
    glm::vec3 mn(1e30f), mx(-1e30f);
    int worldCount = 0;
    for (const auto& r : selection_)
        if (const map::Solid* s = doc_.resolve(r)) {
            mn = glm::min(mn, s->boundsMin);
            mx = glm::max(mx, s->boundsMax);
            if (r.entity < 0) ++worldCount;
        }
    glm::vec3 ctr = 0.5f * (mn + mx);
    glm::vec3 size = mx - mn;

    if (pb::ui::fontUiMed) ImGui::PushFont(pb::ui::fontUiMed);
    ImGui::Text("%zu brush%s selected", selection_.size(),
                selection_.size() == 1 ? "" : "es");
    if (pb::ui::fontUiMed) ImGui::PopFont();

    pb::ui::sectionLabel("POSITION  (centre)");
    glm::vec3 newCtr = ctr;
    ImGui::SetNextItemWidth(-1);
    bool posEdited = ImGui::DragFloat3("##pos", &newCtr.x, 1.0f, 0, 0, "%.0f");
    bool posCommit = ImGui::IsItemDeactivatedAfterEdit();

    pb::ui::sectionLabel("SIZE  (w  d  h)");
    glm::vec3 newSize = size;
    ImGui::SetNextItemWidth(-1);
    bool sizeEdited =
        ImGui::DragFloat3("##size", &newSize.x, 1.0f, 1.0f, 1e6f, "%.0f");
    bool sizeCommit = ImGui::IsItemDeactivatedAfterEdit();

    if (posEdited && newCtr != ctr) {
        const glm::vec3 d = newCtr - ctr;
        for (const auto& r : selection_)
            if (map::Solid* s = doc_.resolve(r)) s->translate(d);
        docMeshDirty_ = true;
    }
    if (sizeEdited && selection_.size() == 1 && newSize != size) {
        newSize = glm::max(newSize, glm::vec3(1.0f));
        if (map::Solid* s = doc_.resolve(selection_[0])) {
            const glm::vec3 c = s->center();
            s->resizeTo(c - newSize * 0.5f, c + newSize * 0.5f);
            docMeshDirty_ = true;
        }
    }
    if (posCommit || sizeCommit) afterEdit("Edit brush");

    ImGui::Dummy(ImVec2(0, 6));
    pb::ui::sectionLabel("MATERIAL");
    if (const map::Solid* s = doc_.resolve(selection_[0])) {
        const std::string m = s->faces.empty() ? "" : s->faces.front().material;
        const auto& info = materials_.get(m);
        ImGui::Image(static_cast<ImTextureID>(static_cast<intptr_t>(info.texture)),
                     ImVec2(48, 48));
        ImGui::SameLine();
        ImGui::TextWrapped("%s", m.c_str());
    }

    ImGui::Dummy(ImVec2(0, 8));
    pb::ui::sectionLabel("ROTATE");
    const float rbw = (ImGui::GetContentRegionAvail().x - 12) / 3.0f;
    if (ImGui::Button(ICON_FA_ROTATE_LEFT " Z", ImVec2(rbw, 0)))
        rotateSelection(2, -90.0f);
    ImGui::SameLine(0, 6);
    if (ImGui::Button(ICON_FA_ROTATE_RIGHT " Z", ImVec2(rbw, 0)))
        rotateSelection(2, 90.0f);
    ImGui::SameLine(0, 6);
    if (ImGui::Button("Tip 90", ImVec2(rbw, 0)))
        rotateSelection(0, 90.0f);
    if (ImGui::IsItemHovered())
        ImGui::SetTooltip("Tip the object onto its side (rotate 90 about X).\n"
                          "Keyboard:  [ and ]  rotate about Z in 15 steps.");

    ImGui::Dummy(ImVec2(0, 8));
    if (ImGui::Button(ICON_FA_CLONE "  Duplicate", ImVec2(-1, 0)))
        duplicateSelection();
    if (ImGui::Button(ICON_FA_TRASH "  Delete", ImVec2(-1, 0))) deleteSelection();

    {
        bool anyGrouped = false;
        for (const auto& r : selection_)
            if (const map::Solid* s = doc_.resolve(r); s && s->group > 0)
                anyGrouped = true;
        if (ImGui::Button(ICON_FA_OBJECT_GROUP "  Group", ImVec2(-1, 0)))
            groupSelection();
        if (anyGrouped &&
            ImGui::Button(ICON_FA_OBJECT_UNGROUP "  Ungroup", ImVec2(-1, 0)))
            ungroupSelection();
    }

    // --- Hollow / Carve ------------------------------------------------------
    ImGui::Dummy(ImVec2(0, 6));
    pb::ui::sectionLabel("SHAPE OPS");
    static float hollowWall = 16.0f;
    ImGui::SetNextItemWidth(90);
    ImGui::DragFloat("wall", &hollowWall, 1.0f, 1.0f, 256.0f, "%.0f");
    ImGui::SameLine();
    if (ImGui::Button("Hollow", ImVec2(-1, 0)) && worldCount > 0) {
        std::vector<map::Solid> add;
        for (const auto& r : selection_) {
            if (r.entity >= 0) continue;
            const map::Solid* s = doc_.resolve(r);
            if (!s) continue;
            for (auto& w : map::hollow(*s, hollowWall)) {
                w.id = doc_.nextId();
                add.push_back(std::move(w));
            }
        }
        if (!add.empty()) {
            // remove the originals (world solids only), then add the shells
            std::vector<int> del;
            for (const auto& r : selection_)
                if (r.entity < 0) del.push_back(r.solid);
            std::sort(del.rbegin(), del.rend());
            for (int idx : del)
                if (idx < (int)doc_.worldSolids().size())
                    doc_.worldSolids().erase(doc_.worldSolids().begin() + idx);
            for (auto& w : add) doc_.worldSolids().push_back(std::move(w));
            clearSelection();
            afterEdit("Hollow");
            status_ = "Hollowed";
        }
    }
    if (selection_.size() == 1 && selection_[0].entity < 0) {
        if (ImGui::Button(ICON_FA_SCISSORS "  Carve (subtract from others)",
                          ImVec2(-1, 0))) {
            const int cutIdx = selection_[0].solid;
            map::Solid cutter = doc_.worldSolids()[cutIdx];
            std::vector<map::Solid> rebuilt;
            for (int i = 0; i < (int)doc_.worldSolids().size(); ++i) {
                if (i == cutIdx) continue;
                auto pieces = map::carve(doc_.worldSolids()[i], cutter);
                for (auto& pc : pieces) {
                    if (!pc.valid) continue;
                    pc.id = doc_.nextId();
                    rebuilt.push_back(std::move(pc));
                }
            }
            doc_.worldSolids() = std::move(rebuilt);
            clearSelection();
            afterEdit("Carve");
            status_ = "Carved";
        }
        if (ImGui::IsItemHovered())
            ImGui::SetTooltip("Subtracts this brush from every other world brush "
                              "it overlaps (the carve brush itself is removed).");
    }

    if (worldCount != static_cast<int>(selection_.size())) {
        ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::faint);
        ImGui::TextWrapped("(some selected brushes belong to entities — brush-entity "
                           "editing is limited for now)");
        ImGui::PopStyleColor();
    }
}

void Editor::drawSimpleEntities() {
    using namespace pb::ui;
    struct SE { const char* name; const char* spec; const char* hint; };
    // spec: "kit:<Name>" -> placePiece, otherwise a raw entity classname.
    static const SE items[] = {
        {"RED spawn room", "kit:RED spawn", "Where RED players start (room + spawns)"},
        {"BLU spawn room", "kit:BLU spawn", "Where BLU players start (room + spawns)"},
        {"One spawn point", "info_player_teamspawn", "A single respawn spot"},
        {"Capture point", "kit:Capture point", "Stand on it to capture"},
        {"Payload path", "kit:Payload track", "Track nodes for the cart"},
        {"Resupply cabinet", "kit:Resupply", "Refills health and ammo"},
        {"Small health", "item_healthkit_small", "+ a bit of health"},
        {"Medium health", "item_healthkit_medium", "+ half health"},
        {"Full health", "item_healthkit_full", "Full heal"},
        {"Small ammo", "item_ammopack_small", ""},
        {"Medium ammo", "item_ammopack_medium", ""},
        {"Full ammo", "item_ammopack_full", ""},
        {"Intel briefcase", "item_teamflag", "The flag for CTF"},
        {"Hurt zone", "trigger_hurt", "Brush trigger — hurts players inside"},
        {"Push / jump pad", "trigger_push", "Brush trigger — shoves players"},
        {"Sliding door", "func_door", "Select a brush, then click this"},
        {"Ambient sound", "ambient_generic", "A looping sound at a spot"},
        {"Particle effect", "info_particle_system", "Smoke / fire / sparks"},
        {"Map fog", "env_fog_controller", "Map-wide fog colour + distance"},
    };

    ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
    ImGui::TextWrapped("Click one, then click in a viewport (or drag it in).");
    ImGui::PopStyleColor();
    ImGui::Dummy(ImVec2(0, 4));

    const float cell = dp(46.0f);
    ImDrawList* dl = ImGui::GetWindowDrawList();
    for (const auto& it : items) {
        const bool isKit = std::strncmp(it.spec, "kit:", 4) == 0;
        const std::string cls = isKit ? "" : it.spec;
        const std::string payload = isKit ? std::string("@kit:") + (it.spec + 4)
                                          : std::string("@ent:") + cls;
        const bool on = placing_ == payload;

        GLuint tex = 0;
        const fgd::EntityClass* ec = cls.empty() ? nullptr : fgd_.flattened(cls);
        if (ec && !ec->studioModel.empty()) {
            const std::string& mp = ec->studioModel;
            tex = modelThumbs_.get(mp, model::loadStudioModel(sourceFs_, mp),
                                   materials_);
        }

        ImGui::PushID(it.name);
        // One full-width hit target for the whole row (icon + label).
        const ImVec2 p0 = ImGui::GetCursorScreenPos();
        const float rowW = ImGui::GetContentRegionAvail().x;
        if (ImGui::Selectable("##row", on, 0, ImVec2(rowW, cell))) {
            placing_ = payload;
            status_ = std::string("Placing ") + it.name +
                      " — click a viewport, or drag it in.";
        }
        if (ImGui::BeginDragDropSource(ImGuiDragDropFlags_SourceAllowNullID)) {
            if (isKit)
                ImGui::SetDragDropPayload("PB_KIT", it.spec + 4,
                                         std::strlen(it.spec + 4) + 1);
            else
                ImGui::SetDragDropPayload("PB_ENTITY", cls.c_str(), cls.size() + 1);
            ImGui::TextUnformatted(it.name);
            ImGui::EndDragDropSource();
            dragPlace_ = payload;
        }
        if (ImGui::IsItemHovered() && cls.size())
            ImGui::SetTooltip("%s  (%s)", it.name, cls.c_str());

        // Draw the icon + text over the selectable's rect.
        const float pad = dp(4.0f);
        const ImVec2 icTL(p0.x + pad, p0.y + pad);
        const float ic = cell - pad * 2.0f;
        if (tex) {
            dl->AddImage(static_cast<ImTextureID>((intptr_t)tex), icTL,
                         ImVec2(icTL.x + ic, icTL.y + ic));
        } else {
            glm::vec3 rgb = ec && ec->hasColor ? ec->color : glm::vec3(0.55f);
            dl->AddRectFilled(icTL, ImVec2(icTL.x + ic, icTL.y + ic),
                              IM_COL32((int)(rgb.r * 255), (int)(rgb.g * 255),
                                       (int)(rgb.b * 255), 60),
                              3.0f);
            dl->AddText(ImVec2(icTL.x + ic * 0.30f, icTL.y + ic * 0.22f),
                        IM_COL32((int)(rgb.r * 255), (int)(rgb.g * 255),
                                 (int)(rgb.b * 255), 255),
                        isKit ? ICON_FA_CUBES : ICON_FA_BOLT);
        }
        const float tx = p0.x + cell + dp(4.0f);
        dl->AddText(fontUiMed ? fontUiMed : nullptr, 0.0f, ImVec2(tx, p0.y + pad),
                    u32(col::tx), it.name);
        if (it.hint[0])
            dl->AddText(ImVec2(tx, p0.y + pad + ImGui::GetTextLineHeight() + 1),
                        u32(col::faint), it.hint);
        if (on)
            dl->AddRect(p0, ImVec2(p0.x + rowW, p0.y + cell), u32(col::acc), 3.0f, 0,
                        2.0f);
        ImGui::PopID();
    }
}

void Editor::drawSelectionPanel() {
    ImGui::Begin("Selection");
    if (!placing_.empty()) {
        const char* pn = placing_.rfind("@ent:", 0) == 0 ? placing_.c_str() + 5
                                                         : placing_.c_str();
        if (pb::ui::fontUiMed) ImGui::PushFont(pb::ui::fontUiMed);
        ImGui::Text(ICON_FA_ARROW_POINTER "  Placing %s", pn);
        if (pb::ui::fontUiMed) ImGui::PopFont();
        ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::dim);
        ImGui::TextWrapped("Click in a viewport to drop it.");
        ImGui::PopStyleColor();
        if (placing_ == "Hill" || placing_ == "Mountain") {
            ImGui::Dummy(ImVec2(0, 6));
            pb::ui::sectionLabel("HILL");
            ImGui::SetNextItemWidth(-1);
            ImGui::SliderFloat("radius", &hillRadius_, 64.0f, 4096.0f, "%.0f");
            ImGui::SetNextItemWidth(-1);
            ImGui::SliderFloat("height", &hillHeight_, 32.0f, 4096.0f, "%.0f");
            ImGui::SetNextItemWidth(-1);
            ImGui::SliderFloat("roughness", &hillRough_, 0.0f, 1.0f, "%.2f");
            ImGui::SetNextItemWidth(-1);
            ImGui::SliderInt("layers", &hillLayers_, 3, 16);
        }
        if (placing_ == "Curvy road") {
            ImGui::Dummy(ImVec2(0, 6));
            pb::ui::sectionLabel("ROAD");
            ImGui::SetNextItemWidth(-1);
            ImGui::SliderFloat("width", &roadWidth_, 32.0f, 1024.0f, "%.0f");
            ImGui::SetNextItemWidth(-1);
            ImGui::SliderFloat("thickness", &roadThick_, 4.0f, 128.0f, "%.0f");
            ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::dim);
            ImGui::TextWrapped("Click points in a 2D view. Enter builds the "
                               "curve, Esc cancels.");
            ImGui::PopStyleColor();
            if (roadPts_.size() >= 2 && ImGui::Button("Build road now", ImVec2(-1, 0)))
                finalizeRoad();
        }
        ImGui::Dummy(ImVec2(0, 6));
        if (ImGui::Button("Cancel", ImVec2(-1, 0))) placing_.clear();
    } else if (selectedEntity_ >= 0 &&
               selectedEntity_ < static_cast<int>(doc_.entities().size())) {
        drawEntityProperties();
    } else if (hasDoc()) {
        drawBrushInspector();
    } else if (hasMap()) {
        pb::ui::sectionLabel("THIS MAP");
        ImGui::Dummy(ImVec2(0, 4));
        const glm::vec3 span = mesh_.playBoundsMax - mesh_.playBoundsMin;
        ImGui::BulletText("%zu point ents, %zu props", mesh_.pointEntities.size(),
                          mesh_.props.size());
        ImGui::BulletText("play area  %.0f x %.0f x %.0f", span.x, span.y, span.z);
    } else {
        ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::faint);
        ImGui::TextWrapped("Open a .bsp (Ctrl+O) or drag one onto the window to get "
                           "started.");
        ImGui::PopStyleColor();
    }
    ImGui::End();
}

void Editor::drawProperties() {
    ImGui::Begin("Properties");
    if (tool_ == Tool::Texture && hasDoc())
        drawFaceEditPanel();
    else if (selectedEntity_ >= 0 &&
        selectedEntity_ < static_cast<int>(doc_.entities().size()))
        drawEntityProperties();
    else if (hasDoc())
        drawBrushInspector();
    else
        ImGui::TextDisabled("Load a map to edit brushes.");
    ImGui::End();
}

void Editor::drawIoEditor(map::MapEntity& e, bool* committed) {
    using namespace pb::ui;
    // VMF connection: "OutputName" "target,InputName,parameter,delay,timesToFire"
    if (ImGui::BeginTable("io", 6,
                          ImGuiTableFlags_Borders | ImGuiTableFlags_SizingStretchProp |
                              ImGuiTableFlags_RowBg)) {
        ImGui::TableSetupColumn("On (output)");
        ImGui::TableSetupColumn("Target");
        ImGui::TableSetupColumn("Input");
        ImGui::TableSetupColumn("Parameter");
        ImGui::TableSetupColumn("Delay", ImGuiTableColumnFlags_WidthFixed, 46);
        ImGui::TableSetupColumn("##x", ImGuiTableColumnFlags_WidthFixed, 24);
        ImGui::TableHeadersRow();

        int removeRow = -1;
        for (int i = 0; i < static_cast<int>(e.connections.size()); ++i) {
            auto& c = e.connections[i];
            // split the value on commas into 5 slots
            std::array<std::string, 5> f;
            {
                std::string s = c.second;
                size_t start = 0;
                for (int k = 0; k < 5; ++k) {
                    size_t comma = s.find(',', start);
                    f[k] = s.substr(start, comma == std::string::npos
                                               ? std::string::npos
                                               : comma - start);
                    if (comma == std::string::npos) break;
                    start = comma + 1;
                }
            }
            ImGui::PushID(i);
            ImGui::TableNextRow();
            auto cell = [&](int col, std::string& v, float w) {
                ImGui::TableSetColumnIndex(col);
                char b[160];
                std::snprintf(b, sizeof(b), "%s", v.c_str());
                ImGui::SetNextItemWidth(w > 0 ? w : -1);
                ImGui::PushID(col);
                if (ImGui::InputText("##c", b, sizeof(b))) v = b;
                if (committed && ImGui::IsItemDeactivatedAfterEdit()) *committed = true;
                ImGui::PopID();
            };
            cell(0, c.first, -1);
            cell(1, f[1], -1);
            cell(2, f[2], -1);
            cell(3, f[3], -1);
            cell(4, f[4], 40);
            ImGui::TableSetColumnIndex(5);
            if (ImGui::SmallButton(ICON_FA_XMARK)) removeRow = i;
            ImGui::PopID();

            std::string joined = f[1];
            for (int k = 2; k < 5; ++k) joined += "," + f[k];
            c.second = joined;
        }
        ImGui::EndTable();
        if (removeRow >= 0) {
            e.connections.erase(e.connections.begin() + removeRow);
            if (committed) *committed = true;
        }
    }
    if (ImGui::SmallButton(ICON_FA_PLUS "  Add output")) {
        e.connections.push_back({"OnTrigger", ",Trigger,,0,-1"});
        if (committed) *committed = true;
    }
}

void Editor::drawEntityProperties() {
    using namespace pb::ui;
    map::MapEntity& e = doc_.entities()[selectedEntity_];
    const fgd::EntityClass* ec = fgd_.flattened(e.classname);

    if (fontUiMed) ImGui::PushFont(fontUiMed);
    ImGui::PushStyleColor(ImGuiCol_Text, col::acc);
    ImGui::Text(ICON_FA_CIRCLE_NODES "  %s", e.classname.c_str());
    ImGui::PopStyleColor();
    if (fontUiMed) ImGui::PopFont();
    if (ec && !ec->description.empty()) {
        ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
        ImGui::TextWrapped("%s", ec->description.c_str());
        ImGui::PopStyleColor();
    }
    if (!ec) {
        ImGui::PushStyleColor(ImGuiCol_Text, col::warn);
        ImGui::TextWrapped(ICON_FA_TRIANGLE_EXCLAMATION
                           "  Not in the FGD — showing raw keys only.");
        ImGui::PopStyleColor();
    }

    bool committed = false;

    // Name is the thing you reach for most — keep it pinned at the top.
    {
        char nm[128];
        std::snprintf(nm, sizeof(nm), "%s", e.kv.get("targetname").c_str());
        ImGui::SetNextItemWidth(-1);
        if (ImGui::InputTextWithHint("##tn", "targetname (name)", nm, sizeof(nm)))
            e.kv.set("targetname", nm);
        if (ImGui::IsItemDeactivatedAfterEdit()) committed = true;
    }

    ImGui::SetNextItemWidth(-1);
    ImGui::InputTextWithHint("##pf", ICON_FA_MAGNIFYING_GLASS " filter keys",
                             propFilter_, sizeof(propFilter_));
    const std::string filt = propFilter_;
    auto match = [&](const fgd::Var& v) {
        if (filt.empty()) return true;
        auto has = [&](const std::string& s) {
            auto it = std::search(
                s.begin(), s.end(), filt.begin(), filt.end(),
                [](char a, char b) { return std::tolower(a) == std::tolower(b); });
            return it != s.end();
        };
        return has(v.key) || has(v.displayName);
    };

    // Names for target dropdowns.
    std::vector<std::string> names;
    for (const auto& other : doc_.entities()) {
        const std::string n = other.kv.get("targetname");
        if (!n.empty() && std::find(names.begin(), names.end(), n) == names.end())
            names.push_back(n);
    }
    std::sort(names.begin(), names.end());

    ImGui::Dummy(ImVec2(0, 4));
    sectionLabel("PROPERTIES");
    const fgd::Var* spawnflags = nullptr;
    int inheritedShown = 0;
    if (ec) {
        // This class's own keys first (the ones you usually came here to set).
        for (const auto& v : ec->vars) {
            if (v.type == fgd::VarType::Flags || v.key == "spawnflags") {
                spawnflags = &v;
                continue;
            }
            if (v.key == "targetname" || v.inherited) continue;
            if (!match(v)) continue;
            if (pb::ui::fgdField(v, e.kv, names, &committed)) docMeshDirty_ = true;
        }
        for (const auto& v : ec->vars)
            if (v.inherited && v.key != "targetname" &&
                v.type != fgd::VarType::Flags && match(v))
                ++inheritedShown;

        if (inheritedShown > 0) {
            ImGui::Dummy(ImVec2(0, 2));
            if (ImGui::CollapsingHeader("Shared keys (angles, parent, render, …)",
                                        filt.empty() ? 0
                                                     : ImGuiTreeNodeFlags_DefaultOpen)) {
                for (const auto& v : ec->vars) {
                    if (v.inherited && v.key != "targetname" &&
                        v.type != fgd::VarType::Flags && match(v))
                        if (pb::ui::fgdField(v, e.kv, names, &committed))
                            docMeshDirty_ = true;
                }
            }
        }
    }

    if (spawnflags && filt.empty()) {
        ImGui::Dummy(ImVec2(0, 4));
        sectionLabel("FLAGS");
        if (pb::ui::fgdFlags(*spawnflags, e.kv, &committed)) docMeshDirty_ = true;
    }

    // Any keys not described by the FGD — always editable, never hidden.
    if (filt.empty()) {
        std::vector<const std::pair<std::string, std::string>*> extra;
        for (const auto& p : e.kv.pairs) {
            if (p.first == "classname" || p.first == "id") continue;
            bool known = (p.first == "targetname" || p.first == "spawnflags");
            if (ec)
                for (const auto& v : ec->vars)
                    if (v.key == p.first) known = true;
            if (!known) extra.push_back(&p);
        }
        if (!extra.empty()) {
            ImGui::Dummy(ImVec2(0, 4));
            if (ImGui::CollapsingHeader("Other keys (not in FGD)",
                                        ImGuiTreeNodeFlags_DefaultOpen)) {
                for (const auto* p : extra) {
                    char b[320];
                    std::snprintf(b, sizeof(b), "%s", p->second.c_str());
                    ImGui::SetNextItemWidth(-1);
                    ImGui::PushID(p->first.c_str());
                    if (ImGui::InputText(p->first.c_str(), b, sizeof(b))) {
                        e.kv.set(p->first, b);
                        docMeshDirty_ = true;
                    }
                    if (ImGui::IsItemDeactivatedAfterEdit()) committed = true;
                    ImGui::PopID();
                }
            }
        }
    }

    ImGui::Dummy(ImVec2(0, 6));
    sectionLabel("OUTPUTS  (I/O)");
    drawIoEditor(e, &committed);

    ImGui::Dummy(ImVec2(0, 8));
    if (ImGui::Button(ICON_FA_TRASH "  Delete entity")) {
        doc_.entities().erase(doc_.entities().begin() + selectedEntity_);
        selectedEntity_ = -1;
        afterEdit("Delete entity");
        return;
    }

    // Keep origin/x-y-z in sync and record one undo step per finished edit.
    if (docMeshDirty_) {
        const std::string o = e.kv.get("origin");
        if (!o.empty()) {
            glm::vec3 v = e.origin;
            std::sscanf(o.c_str(), "%f %f %f", &v.x, &v.y, &v.z);
            e.origin = v;
        }
    }
    if (committed) {
        afterEdit("Edit entity");
    } else if (docMeshDirty_) {
        buildAndUpload(meshOpts_);
    }
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

    std::string needle;

    if (hasDoc()) {
        ImGui::Text(ICON_FA_DIAGRAM_PROJECT "  %s%s",
                    doc_.name().empty() ? "untitled" : doc_.name().c_str(),
                    doc_.dirty() ? " *" : "");
        ImGui::Separator();
        ImGui::SetNextItemWidth(-1);
        ImGui::InputTextWithHint("##filter", ICON_FA_MAGNIFYING_GLASS " filter",
                                 outlinerFilter_, sizeof(outlinerFilter_));
        needle = outlinerFilter_;
        std::transform(needle.begin(), needle.end(), needle.begin(), ::tolower);
        auto pass = [&](const std::string& s) {
            if (needle.empty()) return true;
            std::string t = s;
            std::transform(t.begin(), t.end(), t.begin(), ::tolower);
            return t.find(needle) != std::string::npos;
        };
        auto focusOn = [&](const glm::vec3& c) {
            for (auto& v : views_) {
                if (v.kind == ViewKind::Perspective)
                    v.camera.pos = c - v.camera.forward() * 320.0f;
                else
                    v.camera.orthoCenter = c;
            }
        };

        const auto& ents = doc_.entities();
        const auto& world = doc_.worldSolids();

        // ---- Entities ----------------------------------------------------
        int shown = 0;
        for (const auto& e : ents)
            if (pass(e.classname) || pass(e.kv.get("targetname"))) ++shown;
        char eh[64];
        std::snprintf(eh, sizeof(eh), "Entities  (%d)###ents", (int)ents.size());
        if (ImGui::CollapsingHeader(eh, ImGuiTreeNodeFlags_DefaultOpen)) {
            if (ImGui::BeginChild("entlist", ImVec2(0, 240))) {
                for (int i = 0; i < (int)ents.size(); ++i) {
                    const auto& e = ents[i];
                    const std::string tn = e.kv.get("targetname");
                    if (!pass(e.classname) && !pass(tn)) continue;
                    ImGui::PushID(i);
                    glm::vec3 rgb(0.85f, 0.78f, 0.6f);
                    if (const fgd::EntityClass* ec = fgd_.flattened(e.classname);
                        ec && ec->hasColor)
                        rgb = ec->color;
                    ImGui::ColorButton("##c",
                                       ImVec4(rgb.r, rgb.g, rgb.b, 1.0f),
                                       ImGuiColorEditFlags_NoTooltip |
                                           ImGuiColorEditFlags_NoDragDrop,
                                       ImVec2(10, 10));
                    ImGui::SameLine(0, 6);
                    std::string lbl = (e.solids.empty() ? "" : ICON_FA_CUBE "  ") +
                                      e.classname;
                    if (!tn.empty()) lbl += "  [" + tn + "]";
                    if (ImGui::Selectable(lbl.c_str(), selectedEntity_ == i,
                                          ImGuiSelectableFlags_AllowDoubleClick)) {
                        selectedEntity_ = i;
                        selection_.clear();
                        if (!e.solids.empty())
                            selection_.push_back({i, 0});
                        rebuildSelectionWire();
                        status_ = e.classname + " selected";
                        if (ImGui::IsMouseDoubleClicked(0)) {
                            glm::vec3 c = e.origin;
                            if (!e.solids.empty())
                                c = 0.5f * (e.solids[0].boundsMin + e.solids[0].boundsMax);
                            focusOn(c);
                        }
                    }
                    ImGui::PopID();
                }
                if (ents.empty())
                    ImGui::TextDisabled("No entities yet — add from the catalogue.");
            }
            ImGui::EndChild();
        }

        // ---- World brushes --------------------------------------------------
        char wh[64];
        std::snprintf(wh, sizeof(wh), "World brushes  (%d)###world", (int)world.size());
        if (ImGui::CollapsingHeader(wh, ImGuiTreeNodeFlags_DefaultOpen)) {
            if (ImGui::BeginChild("worldlist", ImVec2(0, 220))) {
                for (int i = 0; i < (int)world.size(); ++i) {
                    const auto& s = world[i];
                    const std::string mat =
                        s.faces.empty() ? std::string("brush") : s.faces[0].material;
                    char row[160];
                    std::snprintf(row, sizeof(row), "brush %d   %s", s.id, mat.c_str());
                    if (!pass(row)) continue;
                    const bool sel =
                        std::find(selection_.begin(), selection_.end(),
                                  map::SolidRef{-1, i}) != selection_.end();
                    ImGui::PushID(1000000 + i);
                    if (ImGui::Selectable(row, sel,
                                          ImGuiSelectableFlags_AllowDoubleClick)) {
                        if (!ImGui::GetIO().KeyShift) selection_.clear();
                        selection_.push_back({-1, i});
                        selectedEntity_ = -1;
                        rebuildSelectionWire();
                        status_ = std::to_string(selection_.size()) + " brush(es) selected";
                        if (ImGui::IsMouseDoubleClicked(0)) focusOn(s.center());
                    }
                    if (!s.valid && ImGui::IsItemHovered())
                        ImGui::SetTooltip("invalid brush (not convex / <4 planes)");
                    ImGui::PopID();
                }
                if (world.empty())
                    ImGui::TextDisabled("No world brushwork yet.");
            }
            ImGui::EndChild();
        }
        ImGui::End();
        return;
    }

    // ---- BSP-only view: keep the read-only stats -----------------------------
    ImGui::Text("%s", bsp_.name().c_str());
    ImGui::Separator();
    ImGui::InputTextWithHint("##filter", "filter", outlinerFilter_,
                             sizeof(outlinerFilter_));
    needle = outlinerFilter_;
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

void Editor::drawModelBrowser() {
    ImGui::Begin("Models");
    drawModelGrid();
    ImGui::End();
}

void Editor::drawModelGrid() {
    using namespace pb::ui;
    if (!sourceFs_.ready()) {
        ImGui::TextDisabled("No game content mounted (install / locate TF2).");
        return;
    }
    if (!modelListBuilt_) {
        modelList_ = sourceFs_.listFiles("models/", ".mdl");
        modelListBuilt_ = true;
        PB_INFO("model browser: %zu models", modelList_.size());
    }

    ImGui::SetNextItemWidth(-1);
    ImGui::InputTextWithHint("##mdlfilter",
                             ICON_FA_MAGNIFYING_GLASS " filter models (e.g. props_2fort)",
                             modelFilter_, sizeof(modelFilter_));
    std::string needle = modelFilter_;
    std::transform(needle.begin(), needle.end(), needle.begin(), ::tolower);

    std::vector<const std::string*> shown;
    shown.reserve(256);
    for (const auto& m : modelList_) {
        if (!needle.empty() && m.find(needle) == std::string::npos) continue;
        shown.push_back(&m);
        if (shown.size() >= 4000) break;
    }
    ImGui::TextDisabled("%zu / %zu models   —   click one, then click a viewport",
                        shown.size(), modelList_.size());
    if (!placing_.empty() && placing_.rfind("@model:", 0) == 0) {
        ImGui::SameLine();
        if (ImGui::SmallButton("cancel")) placing_.clear();
    }

    const float cell = dp(84.0f);
    const int cols = std::max(1, (int)(ImGui::GetContentRegionAvail().x / (cell + dp(8.0f))));
    if (ImGui::BeginChild("mdlgrid")) {
        int budget = 3;  // resolve at most a few MDLs per frame to stay smooth
        ImGuiListClipper clip;
        clip.Begin((int)((shown.size() + cols - 1) / cols), cell + dp(30.0f));
        while (clip.Step()) {
            for (int row = clip.DisplayStart; row < clip.DisplayEnd; ++row) {
                for (int cIdx = 0; cIdx < cols; ++cIdx) {
                    const int i = row * cols + cIdx;
                    if (i >= (int)shown.size()) break;
                    const std::string& path = *shown[i];
                    ImGui::PushID(i);

                    // Icon = a real rendered 3/4-view of the model, cached;
                    // rendered a few per frame so scrolling stays smooth.
                    GLuint tex = 0;
                    if (modelThumbs_.has(path)) {
                        tex = modelThumbs_.get(path, model::loadStudioModel(sourceFs_, path),
                                               materials_);
                    } else if (budget > 0) {
                        tex = modelThumbs_.get(
                            path, model::loadStudioModel(sourceFs_, path), materials_);
                        --budget;
                    }

                    const bool on = placing_ == "@model:" + path;
                    std::string label = path.substr(path.rfind('/') + 1);
                    if (label.size() > 4) label.resize(label.size() - 4);  // .mdl

                    ImGui::BeginGroup();
                    if (tex)
                        ImGui::ImageButton("##b", static_cast<ImTextureID>((intptr_t)tex),
                                           ImVec2(cell, cell));
                    else {
                        ImGui::PushStyleColor(ImGuiCol_Button, col::bg2);
                        ImGui::Button(ICON_FA_CUBE "##t", ImVec2(cell + 8, cell + 8));
                        ImGui::PopStyleColor();
                    }
                    const bool cardHit = ImGui::IsItemClicked();
                    if (ImGui::BeginDragDropSource(ImGuiDragDropFlags_SourceAllowNullID)) {
                        const std::string payload = "@model:" + path;
                        ImGui::SetDragDropPayload("PB_MODEL", payload.c_str(),
                                                 payload.size() + 1);
                        if (tex)
                            ImGui::Image(static_cast<ImTextureID>((intptr_t)tex),
                                         ImVec2(64, 64));
                        ImGui::TextUnformatted(label.c_str());
                        ImGui::EndDragDropSource();
                        dragPlace_ = payload;
                    }
                    if (on)
                        ImGui::GetWindowDrawList()->AddRect(
                            ImGui::GetItemRectMin(), ImGui::GetItemRectMax(),
                            u32(col::acc), 3.0f, 0, 2.0f);
                    ImGui::PushTextWrapPos(ImGui::GetCursorPosX() + cell);
                    ImGui::TextWrapped("%s", label.c_str());
                    ImGui::PopTextWrapPos();
                    ImGui::EndGroup();
                    if (cardHit) {
                        placing_ = "@model:" + path;
                        status_ = "Placing prop  " + label +
                                  "  — click a viewport (or drag me there)";
                    }
                    if (ImGui::IsItemHovered())
                        ImGui::SetTooltip("%s\ndrag into a viewport, or click then "
                                          "click the grid",
                                          path.c_str());
                    if (cIdx + 1 < cols) ImGui::SameLine();
                    ImGui::PopID();
                }
            }
        }
    }
    ImGui::EndChild();
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
    using namespace pb::ui;
    ImGui::Begin("Entities");

    if (fgd_.empty()) {
        ImGui::TextDisabled("No FGD loaded — entity catalogue unavailable.");
        ImGui::End();
        return;
    }

    ImGui::SetNextItemWidth(-1);
    ImGui::InputTextWithHint("##entfilter", ICON_FA_MAGNIFYING_GLASS " search entities",
                             materialFilter_, sizeof(materialFilter_));
    const std::string filt = materialFilter_;
    auto icontains = [](const std::string& h, const std::string& n) {
        if (n.empty()) return true;
        auto it = std::search(h.begin(), h.end(), n.begin(), n.end(),
                              [](char a, char b) {
                                  return std::tolower(a) == std::tolower(b);
                              });
        return it != h.end();
    };

    if (!placing_.empty() && placing_.rfind("@ent:", 0) == 0) {
        ImGui::PushStyleColor(ImGuiCol_Text, col::acc);
        ImGui::Text(ICON_FA_ARROW_POINTER "  Placing %s — click a viewport",
                    placing_.c_str() + 5);
        ImGui::PopStyleColor();
        if (ImGui::SmallButton("Cancel##ent")) placing_.clear();
        ImGui::Separator();
    }

    const bool haveBrushSel =
        !selection_.empty() &&
        std::all_of(selection_.begin(), selection_.end(),
                    [](const map::SolidRef& r) { return r.entity < 0; });

    auto row = [&](const std::string& cls, bool solid) {
        const fgd::EntityClass* ec = fgd_.find(cls);
        if (!filt.empty() && !icontains(cls, filt) &&
            !(ec && icontains(ec->description, filt)))
            return;
        ImGui::PushID(cls.c_str());
        const bool sel = placing_ == "@ent:" + cls;
        if (ImGui::Selectable("##r", sel, 0, ImVec2(0, 30))) {
            if (solid && haveBrushSel) {
                tieSelectionToEntity(cls);
                placing_.clear();
            } else {
                placing_ = "@ent:" + cls;
                status_ = "Placing " + cls + " — click a viewport, or drag me there.";
            }
        }
        if (!solid && ImGui::BeginDragDropSource(ImGuiDragDropFlags_SourceAllowNullID)) {
            ImGui::SetDragDropPayload("PB_ENTITY", cls.c_str(), cls.size() + 1);
            ImGui::TextUnformatted(cls.c_str());
            ImGui::EndDragDropSource();
            dragPlace_ = "@ent:" + cls;
        }
        ImGui::SameLine(6);
        if (ec && ec->hasColor) {
            ImGui::ColorButton(
                "##c",
                ImVec4(ec->color.r, ec->color.g, ec->color.b, 1.0f),
                ImGuiColorEditFlags_NoTooltip | ImGuiColorEditFlags_NoBorder,
                ImVec2(12, 12));
            ImGui::SameLine(0, 6);
        } else {
            ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
            ImGui::TextUnformatted(solid ? ICON_FA_CUBE : ICON_FA_LIGHTBULB);
            ImGui::PopStyleColor();
            ImGui::SameLine(0, 6);
        }
        ImGui::TextUnformatted(cls.c_str());
        if (ec && !ec->description.empty()) {
            ImGui::SameLine(0, 8);
            ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
            ImGui::TextUnformatted(ec->description.c_str());
            ImGui::PopStyleColor();
        }
        ImGui::PopID();
    };

    if (haveBrushSel) {
        ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
        ImGui::TextWrapped("%zu brush(es) selected — pick a brush entity to tie "
                           "them to it.", selection_.size());
        ImGui::PopStyleColor();
    }

    if (ImGui::BeginChild("entlist", ImVec2(0, 0))) {
        if (ImGui::CollapsingHeader("Point entities", ImGuiTreeNodeFlags_DefaultOpen)) {
            for (const auto& c : fgd_.pointClasses()) row(c, false);
        }
        if (ImGui::CollapsingHeader("Brush entities", ImGuiTreeNodeFlags_DefaultOpen)) {
            for (const auto& c : fgd_.solidClasses()) row(c, true);
        }
    }
    ImGui::EndChild();
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
// Quality-of-life: history panel, map check, command palette, autosave
// ---------------------------------------------------------------------------
void Editor::drawHistoryPanel() {
    ImGui::Begin("History");
    if (!hasDoc()) {
        ImGui::TextDisabled("No editable map open.");
        ImGui::End();
        return;
    }
    ImGui::TextDisabled("%zu steps  (Ctrl+Z / Ctrl+Y)", history_.count());
    ImGui::SameLine();
    if (ImGui::SmallButton(ICON_FA_ROTATE_LEFT) && history_.canUndo()) undo();
    ImGui::SameLine();
    if (ImGui::SmallButton(ICON_FA_ROTATE_RIGHT) && history_.canRedo()) redo();
    ImGui::Separator();

    if (ImGui::BeginChild("hist")) {
        for (size_t i = 0; i < history_.count(); ++i) {
            const bool cur = i == history_.current();
            ImGui::PushID((int)i);
            char row[160];
            std::snprintf(row, sizeof(row), "%2zu  %s", i,
                          history_.labelAt(i).c_str());
            if (ImGui::Selectable(row, cur) && !cur) {
                history_.jumpTo(doc_, i);
                clearSelection();
                buildAndUpload(meshOpts_);
                status_ = "Jumped to: " + history_.labelAt(i);
            }
            if (cur) {
                ImGui::SameLine();
                ImGui::TextColored(pb::ui::col::acc, ICON_FA_ARROW_LEFT " now");
            }
            ImGui::PopID();
        }
    }
    ImGui::EndChild();
    ImGui::End();
}

void Editor::runMapCheck() {
    mapCheck_.clear();
    mapCheckRan_ = true;
    if (!hasDoc()) return;
    auto add = [&](int sev, std::string m, int ent = -2, int sol = -1,
                   glm::vec3 p = glm::vec3(0)) {
        mapCheck_.push_back({std::move(m), sev, ent, sol, p});
    };

    int spawns = 0, lights = 0, objectives = 0, invalid = 0;
    glm::vec3 dmn(1e9f), dmx(-1e9f);
    for (int i = 0; i < (int)doc_.worldSolids().size(); ++i) {
        const auto& s = doc_.worldSolids()[i];
        if (!s.valid) { ++invalid; add(2, "Invalid world brush (not convex / <4 planes)", -1, i, s.center()); }
        dmn = glm::min(dmn, s.boundsMin);
        dmx = glm::max(dmx, s.boundsMax);
        const glm::vec3 sz = s.boundsMax - s.boundsMin;
        if (std::max({sz.x, sz.y, sz.z}) > 16384.0f)
            add(1, "Very large brush (>16384u) — check it's intentional", -1, i, s.center());
    }
    // Collect targetnames for dangling-I/O detection.
    std::vector<std::string> names;
    for (const auto& e : doc_.entities()) {
        const std::string tn = e.kv.get("targetname");
        if (!tn.empty()) names.push_back(tn);
    }
    for (int i = 0; i < (int)doc_.entities().size(); ++i) {
        const auto& e = doc_.entities()[i];
        const std::string& c = e.classname;
        if (c == "info_player_teamspawn" || c == "info_player_start") ++spawns;
        if (c.rfind("light", 0) == 0) ++lights;
        if (c == "team_control_point" || c == "trigger_capture_area" ||
            c == "func_capturezone" || c.rfind("func_tracktrain", 0) == 0)
            ++objectives;
        for (const auto& conn : e.connections) {
            std::string tgt = conn.second.substr(0, conn.second.find_first_of(",\x1b"));
            if (tgt.empty() || tgt == "!activator" || tgt == "!self" ||
                tgt == "!player")
                continue;
            if (std::find(names.begin(), names.end(), tgt) == names.end())
                add(2,
                    c + " fires \"" + conn.first + "\" at missing target \"" + tgt +
                        "\"",
                    i, -1, e.origin);
        }
        // Missing model/material references are resolved lazily; flag obvious ones.
        const std::string mdl = e.kv.get("model");
        if (!mdl.empty() && mdl[0] != '*' && mdl.find(".mdl") == std::string::npos &&
            mdl.find(".vmf") == std::string::npos)
            add(1, c + " model \"" + mdl + "\" has no .mdl extension", i, -1, e.origin);
    }

    if (spawns < 1) add(2, "No player spawns (info_player_teamspawn)");
    else if (spawns < 2) add(1, "Only one spawn point — add a few per team");
    if (lights < 1) add(1, "No lights — the map will be fullbright");
    if (objectives < 1) add(1, "No objective entity (control point / cap zone / cart)");
    if (doc_.worldExtra().get("skyname").empty())
        add(2, "worldspawn has no skyname — the map won't seal");
    if (doc_.worldSolids().empty())
        add(2, "No world brushwork at all");

    if (mapCheck_.empty()) add(0, "No problems found. Nice.");
    // errors first, then warnings, then info
    std::stable_sort(mapCheck_.begin(), mapCheck_.end(),
                     [](const CheckHit& a, const CheckHit& b) {
                         return a.severity > b.severity;
                     });
}

void Editor::drawMapCheckPanel() {
    ImGui::Begin("Map Check");
    if (ImGui::Button(ICON_FA_STETHOSCOPE "  Run check", ImVec2(-1, 0))) runMapCheck();
    if (!mapCheckRan_) {
        ImGui::TextDisabled("Checks spawns, lights, skybox, invalid brushes, "
                            "dangling I/O targets, oversized geometry.");
        ImGui::End();
        return;
    }
    int err = 0, warn = 0;
    for (const auto& h : mapCheck_) {
        if (h.severity == 2) ++err;
        else if (h.severity == 1) ++warn;
    }
    ImGui::Text("%d error%s, %d warning%s", err, err == 1 ? "" : "s", warn,
                warn == 1 ? "" : "s");
    ImGui::Separator();
    if (ImGui::BeginChild("mc")) {
        for (size_t i = 0; i < mapCheck_.size(); ++i) {
            const auto& h = mapCheck_[i];
            const ImVec4 c = h.severity == 2   ? pb::ui::col::warn
                             : h.severity == 1 ? pb::ui::col::acc
                                               : pb::ui::col::good;
            const char* ic = h.severity == 2   ? ICON_FA_CIRCLE_EXCLAMATION
                             : h.severity == 1 ? ICON_FA_TRIANGLE_EXCLAMATION
                                               : ICON_FA_CIRCLE_CHECK;
            ImGui::PushID((int)i);
            ImGui::PushStyleColor(ImGuiCol_Text, c);
            ImGui::TextUnformatted(ic);
            ImGui::PopStyleColor();
            ImGui::SameLine();
            const bool clickable = h.entity != -2;
            if (ImGui::Selectable(h.msg.c_str(), false,
                                  clickable ? 0 : ImGuiSelectableFlags_Disabled) &&
                clickable) {
                if (h.entity >= 0) {
                    selectedEntity_ = h.entity;
                    selection_.clear();
                } else if (h.solid >= 0) {
                    selection_ = {{-1, h.solid}};
                    selectedEntity_ = -1;
                }
                rebuildSelectionWire();
                for (auto& v : views_) {
                    if (v.kind == ViewKind::Perspective)
                        v.camera.pos = h.pos - v.camera.forward() * 400.0f;
                    else
                        v.camera.orthoCenter = h.pos;
                }
            }
            ImGui::PopID();
        }
    }
    ImGui::EndChild();
    ImGui::End();
}

void Editor::drawCommandPalette() {
    if (!showPalette_) return;
    ImGuiViewport* vp = ImGui::GetMainViewport();
    ImGui::SetNextWindowPos(ImVec2(vp->GetCenter().x, vp->WorkPos.y + vp->WorkSize.y * 0.18f),
                            ImGuiCond_Always, ImVec2(0.5f, 0.0f));
    ImGui::SetNextWindowSize(ImVec2(std::min(560.0f * pb::ui::g_scale, vp->WorkSize.x * 0.8f), 0));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(12, 12));
    if (ImGui::Begin("##palette", &showPalette_,
                     ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                         ImGuiWindowFlags_NoDocking | ImGuiWindowFlags_NoSavedSettings)) {
        struct Cmd { const char* name; std::function<void()> run; };
        std::vector<Cmd> cmds = {
            {"Save map", [&] { saveMap(false); }},
            {"Save map as…", [&] { saveMap(true); }},
            {"Build & play", [&] { showCompile_ = true; if (hasDoc()) startCompile(); }},
            {"Run map check", [&] { runMapCheck(); }},
            {"Frame map (F)", [&] { if (hasMap()) frameAllViews(); }},
            {"Undo", [&] { undo(); }},
            {"Redo", [&] { redo(); }},
            {"Tool: Select", [&] { tool_ = Tool::Select; }},
            {"Tool: Block", [&] { tool_ = Tool::Block; }},
            {"Tool: Vertex/Edge/Face", [&] { tool_ = Tool::Vertex; }},
            {"Tool: Clip", [&] { tool_ = Tool::Clip; }},
            {"Tool: Texture", [&] { tool_ = Tool::Texture; }},
            {"Switch to Simple mode", [&] { mode_ = Mode::Simple; layoutDirty_ = true; }},
            {"Switch to Pro mode", [&] { mode_ = Mode::Pro; layoutDirty_ = true; }},
            {"Reset window layout", [&] { layoutDirty_ = true; }},
            {"Open map…", [&] { promptOpenMap(); }},
            {"Import 3D model…", [&] { openModelImport(); }},
            {"Publish to Steam Workshop", [&] { showWorkshop_ = true; }},
        };
        // Entity classes are matched straight from fgd_ below (not copied into
        // `cmds`) so the palette stays cheap.

        ImGui::PushItemWidth(-1);
        if (ImGui::IsWindowAppearing()) ImGui::SetKeyboardFocusHere();
        ImGui::InputTextWithHint("##q", ICON_FA_MAGNIFYING_GLASS "  Type a command or entity…",
                                 paletteQuery_, sizeof(paletteQuery_));
        ImGui::PopItemWidth();
        const std::string q = paletteQuery_;
        auto icontains = [](const std::string& h, const std::string& n) {
            if (n.empty()) return true;
            auto it = std::search(h.begin(), h.end(), n.begin(), n.end(),
                                  [](char a, char b) {
                                      return std::tolower(a) == std::tolower(b);
                                  });
            return it != h.end();
        };

        struct Row { std::string label; int kind; int idx; };  // kind 0 cmd, 1 entity
        std::vector<Row> rows;
        for (int i = 0; i < (int)cmds.size(); ++i)
            if (cmds[i].name && icontains(cmds[i].name, q))
                rows.push_back({cmds[i].name, 0, i});
        if (q.size() >= 2)
            for (int i = 0; i < (int)fgd_.pointClasses().size(); ++i)
                if (icontains(fgd_.pointClasses()[i], q)) {
                    rows.push_back({"Place entity:  " + fgd_.pointClasses()[i], 1, i});
                    if (rows.size() > 60) break;
                }

        if (paletteSel_ >= (int)rows.size()) paletteSel_ = (int)rows.size() - 1;
        if (paletteSel_ < 0) paletteSel_ = 0;
        if (ImGui::IsKeyPressed(ImGuiKey_DownArrow)) ++paletteSel_;
        if (ImGui::IsKeyPressed(ImGuiKey_UpArrow)) --paletteSel_;
        paletteSel_ = std::clamp(paletteSel_, 0, std::max(0, (int)rows.size() - 1));

        const bool go = ImGui::IsKeyPressed(ImGuiKey_Enter) ||
                        ImGui::IsKeyPressed(ImGuiKey_KeypadEnter);
        ImGui::BeginChild("rows", ImVec2(0, 260));
        for (int i = 0; i < (int)rows.size(); ++i) {
            const bool sel = i == paletteSel_;
            if (ImGui::Selectable(rows[i].label.c_str(), sel) || (go && sel)) {
                if (rows[i].kind == 0) {
                    cmds[rows[i].idx].run();
                } else {
                    placing_ = "@ent:" + fgd_.pointClasses()[rows[i].idx];
                    status_ = "Click in a viewport to place " +
                              fgd_.pointClasses()[rows[i].idx];
                }
                showPalette_ = false;
                paletteQuery_[0] = 0;
                paletteSel_ = 0;
            }
        }
        ImGui::EndChild();
        if (ImGui::IsKeyPressed(ImGuiKey_Escape)) showPalette_ = false;
    }
    ImGui::End();
    ImGui::PopStyleVar();
}

void Editor::writeBackup(const std::string& vmfPath) {
    std::error_code ec;
    if (!fs::exists(vmfPath, ec)) return;
    const fs::path p(vmfPath);
    auto bak = [&](int n) { return p.string() + ".bak" + std::to_string(n); };
    fs::remove(bak(3), ec);
    for (int n = 2; n >= 1; --n)
        if (fs::exists(bak(n), ec))
            fs::rename(bak(n), bak(n + 1), ec);
    fs::copy_file(vmfPath, bak(1), fs::copy_options::overwrite_existing, ec);
}

void Editor::drawLogPanel() {
    ImGui::Begin("Log");
    ImGui::Checkbox("follow", &logAutoScroll_);
    ImGui::SameLine();
    if (ImGui::SmallButton("copy all")) {
        std::string all;
        for (const auto& l : logTail(2000)) all += l.text + "\n";
        ImGui::SetClipboardText(all.c_str());
    }
    ImGui::Separator();
    if (pb::ui::fontMono) ImGui::PushFont(pb::ui::fontMono);
    ImGui::PushStyleColor(ImGuiCol_ChildBg, pb::ui::col::bg0);
    if (ImGui::BeginChild("##log", ImVec2(0, 0), ImGuiChildFlags_Borders)) {
        const auto lines = logTail(800);
        ImGuiListClipper clip;
        clip.Begin((int)lines.size());
        while (clip.Step())
            for (int i = clip.DisplayStart; i < clip.DisplayEnd; ++i) {
                const auto& l = lines[i];
                const ImVec4 c = l.level == LogLevel::Error ? pb::ui::col::warn
                                 : l.level == LogLevel::Warn ? pb::ui::col::acc
                                                             : pb::ui::col::dim;
                ImGui::PushStyleColor(ImGuiCol_Text, c);
                ImGui::TextUnformatted(l.text.c_str());
                ImGui::PopStyleColor();
            }
        const size_t seq = logSeq();
        if (logAutoScroll_ && seq != logSeen_) {
            ImGui::SetScrollHereY(1.0f);
            logSeen_ = seq;
        }
    }
    ImGui::EndChild();
    ImGui::PopStyleColor();
    if (pb::ui::fontMono) ImGui::PopFont();
    ImGui::End();
}

void Editor::saveProject(bool forceDialog) {
    if (!hasDoc()) { status_ = "Open a map before saving a project."; return; }
    if (doc_.path().empty() && !saveMap(false)) return;  // project references the vmf

    std::string out = projectPath_;
    if (out.empty() || forceDialog) {
        out = saveFileDialog("Save project", "Pootis project\0*.pbproj\0",
                             doc_.name().c_str(), "pbproj",
                             out.empty() ? nullptr : out.c_str());
        if (out.empty()) return;
    }
    projectPath_ = out;

    map::KvNode root;
    root.name = "#root";
    map::KvNode pj;
    pj.name = "pbproj";
    pj.set("version", "1");
    pj.set("vmf", doc_.path());
    pj.set("grid", std::to_string(gridSize_));
    pj.set("cordon", cordonOn_ ? "1" : "0");
    char b[96];
    std::snprintf(b, sizeof(b), "%g %g %g", cordonMin_.x, cordonMin_.y, cordonMin_.z);
    pj.set("cordon_min", b);
    std::snprintf(b, sizeof(b), "%g %g %g", cordonMax_.x, cordonMax_.y, cordonMax_.z);
    pj.set("cordon_max", b);
    pj.set("compile_profile", std::to_string(compileProfile_));
    pj.set("compile_pack", compilePack_ ? "1" : "0");
    for (int i = 0; i < 6; ++i) {
        if (!camMarks_[i].set) continue;
        std::snprintf(b, sizeof(b), "%g %g %g %g %g", camMarks_[i].pos.x,
                      camMarks_[i].pos.y, camMarks_[i].pos.z, camMarks_[i].yaw,
                      camMarks_[i].pitch);
        pj.set("cam" + std::to_string(i), b);
    }
    for (const auto& pf : packFiles_) pj.set("pack", pf);
    root.children.push_back(std::move(pj));

    const std::string text = map::writeKv(root);
    FILE* f = std::fopen(out.c_str(), "wb");
    if (!f) { status_ = "Could not write " + out; return; }
    std::fwrite(text.data(), 1, text.size(), f);
    std::fclose(f);
    status_ = "Saved project  " + fs::path(out).filename().string();
    prefs_.pushRecent(out);
    prefs_.save();
}

void Editor::openProject(const std::string& path) {
    const std::string text = readTextFile(path);
    if (text.empty()) { status_ = "Cannot read " + path; return; }
    const map::KvNode root = map::parseKv(text);
    const map::KvNode* pj = root.child("pbproj");
    if (!pj) { status_ = "Not a Pootis project: " + path; return; }
    projectPath_ = path;

    const std::string vmf = pj->get("vmf");
    if (!vmf.empty() && !openMap(vmf)) {
        status_ = "Project's map is missing: " + vmf;
        return;
    }
    if (int g = pj->getInt("grid")) gridSize_ = g;
    cordonOn_ = pj->getInt("cordon") != 0;
    std::sscanf(pj->get("cordon_min").c_str(), "%f %f %f", &cordonMin_.x,
                &cordonMin_.y, &cordonMin_.z);
    std::sscanf(pj->get("cordon_max").c_str(), "%f %f %f", &cordonMax_.x,
                &cordonMax_.y, &cordonMax_.z);
    compileProfile_ = pj->getInt("compile_profile");
    compilePack_ = pj->getInt("compile_pack") != 0;
    for (int i = 0; i < 6; ++i) {
        const std::string s = pj->get("cam" + std::to_string(i));
        if (s.empty()) continue;
        CamMark m;
        m.set = std::sscanf(s.c_str(), "%f %f %f %f %f", &m.pos.x, &m.pos.y, &m.pos.z,
                            &m.yaw, &m.pitch) == 5;
        if (m.set) camMarks_[i] = m;
    }
    packFiles_.clear();
    for (const auto& kv : pj->pairs)
        if (kv.first == "pack") packFiles_.push_back(kv.second);
    status_ = "Opened project  " + fs::path(path).filename().string();
    prefs_.pushRecent(path);
    prefs_.save();
}

void Editor::drawVisgroupsPanel() {
    ImGui::Begin("Visgroups");
    if (!hasDoc()) {
        ImGui::TextDisabled("Open an editable map to use visgroups.");
        ImGui::End();
        return;
    }
    ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::faint);
    ImGui::TextWrapped("Toggle whole categories of the map on and off. Hidden "
                       "objects don't render or pick, and are skipped by compile.");
    ImGui::PopStyleColor();

    // Auto categories: predicate over an entity or a world solid.
    struct Cat {
        const char* label;
        std::function<bool(const map::MapEntity*)> entMatch;
        std::function<bool(const map::Solid&)> worldMatch;
    };
    auto pfx = [](const std::string& s, const char* p) {
        return s.rfind(p, 0) == 0;
    };
    std::vector<Cat> cats = {
        {"World brushwork", nullptr, [](const map::Solid&) { return true; }},
        {"Tool brushes",
         nullptr,
         [](const map::Solid& s) {
             return !s.faces.empty() && s.faces[0].material.rfind("tools/", 0) == 0;
         }},
        {"Lights",
         [pfx](const map::MapEntity* e) { return pfx(e->classname, "light"); },
         nullptr},
        {"Triggers",
         [pfx](const map::MapEntity* e) { return pfx(e->classname, "trigger"); },
         nullptr},
        {"Props",
         [pfx](const map::MapEntity* e) { return pfx(e->classname, "prop_"); },
         nullptr},
        {"Logic / relays",
         [pfx](const map::MapEntity* e) {
             return pfx(e->classname, "logic_") || pfx(e->classname, "math_") ||
                    pfx(e->classname, "filter_") ||
                    pfx(e->classname, "point_template");
         },
         nullptr},
        {"Spawns & pickups",
         [pfx](const map::MapEntity* e) {
             return pfx(e->classname, "info_player") || pfx(e->classname, "item_") ||
                    pfx(e->classname, "func_regenerate");
         },
         nullptr},
        {"Brush entities (func_*)",
         [pfx](const map::MapEntity* e) {
             return pfx(e->classname, "func_") && !e->solids.empty();
         },
         nullptr},
    };

    ImGui::Separator();
    bool changed = false;
    for (auto& c : cats) {
        int total = 0, hidden = 0;
        if (c.worldMatch) {
            for (auto& s : doc_.worldSolids())
                if (c.worldMatch(s)) { ++total; hidden += s.hidden ? 1 : 0; }
        }
        if (c.entMatch) {
            for (auto& e : doc_.entities())
                if (c.entMatch(&e)) { ++total; hidden += e.hidden ? 1 : 0; }
        }
        if (total == 0) continue;
        bool vis = hidden < total;
        ImGui::PushID(c.label);
        if (ImGui::Checkbox("##v", &vis)) {
            if (c.worldMatch)
                for (auto& s : doc_.worldSolids())
                    if (c.worldMatch(s)) s.hidden = !vis;
            if (c.entMatch)
                for (auto& e : doc_.entities())
                    if (c.entMatch(&e)) {
                        e.hidden = !vis;
                        for (auto& s : e.solids) s.hidden = !vis;
                    }
            changed = true;
        }
        ImGui::SameLine();
        ImGui::Text("%s", c.label);
        ImGui::SameLine();
        ImGui::TextDisabled("(%d)", total);
        ImGui::PopID();
    }

    ImGui::Separator();
    if (ImGui::Button(ICON_FA_EYE "  Show everything", ImVec2(-1, 0))) {
        for (auto& s : doc_.worldSolids()) s.hidden = false;
        for (auto& e : doc_.entities()) {
            e.hidden = false;
            for (auto& s : e.solids) s.hidden = false;
        }
        changed = true;
    }
    if (changed) {
        clearSelection();
        buildAndUpload(meshOpts_);
        rebuildSelectionWire();
    }
    ImGui::End();
}

void Editor::drawPrefabPanel() {
    ImGui::Begin("Prefabs");
    ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::faint);
    ImGui::TextWrapped("Reusable chunks of brushwork + entities. Click one, then "
                       "click in a viewport to drop it (snaps to grid).");
    ImGui::PopStyleColor();

    if (hasDoc() && !selection_.empty() &&
        ImGui::Button(ICON_FA_FLOPPY_DISK "  Save selection as prefab…", ImVec2(-1, 0)))
        saveSelectionAsPrefab();
    ImGui::Separator();

    static std::vector<std::string> dirs = {
        executableDir() + "/assets/prefabs",
        executableDir() + "/../assets/prefabs",
        std::string(kTf2Maps).substr(0, std::string(kTf2Maps).size() - 5) + "/prefabs",
    };
    int shown = 0;
    for (const auto& d : dirs) {
        std::error_code ec;
        if (!fs::is_directory(d, ec)) continue;
        for (auto& de : fs::directory_iterator(d, ec)) {
            if (de.path().extension() != ".vmf") continue;
            ++shown;
            const std::string full = de.path().string();
            const std::string name = de.path().stem().string();
            const bool on = placing_ == "@prefab:" + full;
            ImGui::PushID(full.c_str());
            if (ImGui::Selectable(name.c_str(), on)) {
                placing_ = "@prefab:" + full;
                status_ = "Click in a viewport to place prefab '" + name + "'";
            }
            if (ImGui::IsItemHovered()) ImGui::SetTooltip("%s", full.c_str());
            ImGui::PopID();
        }
    }
    if (shown == 0) {
        ImGui::PushStyleColor(ImGuiCol_Text, pb::ui::col::faint);
        ImGui::TextWrapped("No prefabs found. Drop .vmf files in "
                           "<app>/assets/prefabs/, or use the button above.");
        ImGui::PopStyleColor();
    }
    ImGui::End();
}

void Editor::placePrefab(const std::string& path, const glm::vec3& atRaw) {
    if (!doc_.active()) doc_.newBlank("untitled");
    map::MapDocument tmp;
    std::string err;
    if (!tmp.loadVmf(path, &err)) {
        status_ = "Prefab load failed: " + err;
        return;
    }
    glm::vec3 mn, mx;
    tmp.bounds(mn, mx);
    const glm::vec3 anchor(0.5f * (mn.x + mx.x), 0.5f * (mn.y + mx.y), mn.z);
    const glm::vec3 d = snapVec(atRaw) - anchor;

    selection_.clear();
    for (auto s : tmp.worldSolids()) {
        s.id = doc_.nextId();
        s.group = 0;
        s.translate(d);
        doc_.worldSolids().push_back(std::move(s));
        selection_.push_back({-1, (int)doc_.worldSolids().size() - 1});
    }
    for (auto e : tmp.entities()) {
        e.id = doc_.nextId();
        for (auto& s : e.solids) { s.id = doc_.nextId(); s.translate(d); }
        e.origin += d;
        e.kv.set("origin", std::to_string((int)e.origin.x) + " " +
                               std::to_string((int)e.origin.y) + " " +
                               std::to_string((int)e.origin.z));
        doc_.entities().push_back(std::move(e));
    }
    afterEdit("Insert prefab");
    status_ = "Placed prefab (" + std::to_string(tmp.worldSolids().size()) +
              " brushes, " + std::to_string(tmp.entities().size()) + " entities)";
}

void Editor::saveSelectionAsPrefab() {
    if (selection_.empty()) return;
    const std::string dir = executableDir() + "/assets/prefabs";
    std::error_code ec;
    fs::create_directories(dir, ec);
    const std::string out = saveFileDialog(
        "Save prefab", "Hammer VMF\0*.vmf\0", "prefab", "vmf", dir.c_str());
    if (out.empty()) return;

    map::MapDocument tmp;
    tmp.newBlank(fs::path(out).stem().string());
    for (const auto& r : selection_) {
        const map::Solid* s = doc_.resolve(r);
        if (!s) continue;
        if (r.entity < 0) {
            tmp.worldSolids().push_back(*s);
        } else {
            const auto& e = doc_.entities()[r.entity];
            map::MapEntity ce = e;
            tmp.entities().push_back(std::move(ce));
        }
    }
    std::string err;
    if (tmp.saveVmf(out, &err, /*updateState=*/false))
        status_ = "Saved prefab  " + fs::path(out).filename().string();
    else
        status_ = "Prefab save failed: " + err;
}

void Editor::drawCordonOverlay(ViewPanel& p, float aspect, ImDrawList* dl) {
    if (!cordonOn_ && !(cordonShow_ && p.kind != ViewKind::Perspective)) return;
    if (!cordonOn_) return;
    const glm::vec3 mn = glm::min(cordonMin_, cordonMax_);
    const glm::vec3 mx = glm::max(cordonMin_, cordonMax_);
    const glm::mat4 vp = p.camera.proj(aspect) * p.camera.view();
    const glm::vec3 c[8] = {
        {mn.x, mn.y, mn.z}, {mx.x, mn.y, mn.z}, {mx.x, mx.y, mn.z}, {mn.x, mx.y, mn.z},
        {mn.x, mn.y, mx.z}, {mx.x, mn.y, mx.z}, {mx.x, mx.y, mx.z}, {mn.x, mx.y, mx.z}};
    ImVec2 s[8];
    bool ok = true;
    for (int i = 0; i < 8; ++i) {
        bool o;
        s[i] = projectPt(p.kind, vp, p.contentMin, p.contentSize, c[i], o);
        ok = ok && o;
    }
    if (!ok) return;
    static const int E[12][2] = {{0, 1}, {1, 2}, {2, 3}, {3, 0}, {4, 5}, {5, 6},
                                 {6, 7}, {7, 4}, {0, 4}, {1, 5}, {2, 6}, {3, 7}};
    const ImU32 col = IM_COL32(255, 90, 70, 230);
    for (auto& e : E) dl->AddLine(s[e[0]], s[e[1]], col, 1.5f);
    dl->AddText(ImVec2(p.contentMin.x + 8, p.contentMin.y + 40), col, "CORDON");
}

void Editor::handleCordonDrag(ViewPanel&) {}  // numeric editing only, for now

namespace {
// World axis indices spanned by an ortho view: {right, up}.
inline void orthoAxes(ViewKind k, int& u, int& v) {
    switch (k) {
        case ViewKind::Top:   u = 0; v = 1; break;  // X, Y
        case ViewKind::Front: u = 0; v = 2; break;  // X, Z
        default:              u = 1; v = 2; break;  // Side: Y, Z
    }
}
}  // namespace

void Editor::handleSelectionResize(ViewPanel& p) {
    if (tool_ != Tool::Select || selection_.empty() || gizmoUsing_) {
        resizeHot_ = -1;
        return;
    }
    const bool persp = p.kind == ViewKind::Perspective;

    glm::vec3 mn(1e30f), mx(-1e30f);
    for (const auto& r : selection_)
        if (const map::Solid* s = doc_.resolve(r)) {
            mn = glm::min(mn, s->boundsMin);
            mx = glm::max(mx, s->boundsMax);
        }
    if (mn.x > mx.x) { resizeHot_ = -1; return; }

    int au = 0, av = 1;
    if (!persp) orthoAxes(p.kind, au, av);
    const float aspect = p.contentSize.x / std::max(1.0f, p.contentSize.y);
    const glm::mat4 vp = p.camera.proj(aspect) * p.camera.view();
    const glm::vec3 ctr = 0.5f * (mn + mx);
    const int nHandles = persp ? 6 : 8;

    // Perspective: 6 face-centre handles, one per +/- world axis.
    // Ortho: 4 corners + 4 edge midpoints in the view plane.
    auto handleWorld = [&](int h) {
        glm::vec3 w = ctr;
        if (persp) {
            const int ax = h / 2;
            w[ax] = (h & 1) ? mx[ax] : mn[ax];
            return w;
        }
        const float lo[2] = {mn[au], mn[av]}, hi[2] = {mx[au], mx[av]};
        const float mid[2] = {ctr[au], ctr[av]};
        float cu = mid[0], cv = mid[1];
        switch (h) {
            case 0: cu = lo[0]; cv = lo[1]; break;
            case 1: cu = hi[0]; cv = lo[1]; break;
            case 2: cu = hi[0]; cv = hi[1]; break;
            case 3: cu = lo[0]; cv = hi[1]; break;
            case 4: cu = lo[0]; cv = mid[1]; break;
            case 5: cu = hi[0]; cv = mid[1]; break;
            case 6: cu = mid[0]; cv = lo[1]; break;
            case 7: cu = mid[0]; cv = hi[1]; break;
        }
        w[au] = cu;
        w[av] = cv;
        return w;
    };
    auto project = [&](const glm::vec3& w) {
        const glm::vec4 c = vp * glm::vec4(w, 1.0f);
        if (c.w <= 1e-4f) return ImVec2(-9999, -9999);
        return ImVec2(p.contentMin.x + (c.x / c.w * 0.5f + 0.5f) * p.contentSize.x,
                      p.contentMin.y + (1.0f - (c.y / c.w * 0.5f + 0.5f)) * p.contentSize.y);
    };

    const ImVec2 m = ImGui::GetMousePos();
    resizeHot_ = -1;
    if (resizeHandle_ < 0) {
        float best = pb::ui::dp(persp ? 17.0f : 14.0f);
        for (int h = 0; h < nHandles; ++h) {
            const ImVec2 s = project(handleWorld(h));
            const float d = std::hypot(s.x - m.x, s.y - m.y);
            if (d < best) { best = d; resizeHot_ = h; }
        }
    }

    if (resizeHot_ >= 0 && p.hovered && ImGui::IsMouseClicked(ImGuiMouseButton_Left)) {
        resizeHandle_ = resizeHot_;
        resizeStartMin_ = mn;
        resizeStartMax_ = mx;
        resizeAnchor_ = ctr;
        const int h = resizeHandle_;
        if (persp) {
            const int ax = h / 2;
            resizeAnchor_[ax] = (h & 1) ? mn[ax] : mx[ax];  // opposite face
        } else {
            if (h == 0 || h == 3 || h == 4) resizeAnchor_[au] = mx[au];
            if (h == 1 || h == 2 || h == 5) resizeAnchor_[au] = mn[au];
            if (h == 0 || h == 1 || h == 6) resizeAnchor_[av] = mx[av];
            if (h == 2 || h == 3 || h == 7) resizeAnchor_[av] = mn[av];
        }
        resizeSnap_.clear();
        resizeRefs_.clear();
        for (const auto& r : selection_)
            if (const map::Solid* s = doc_.resolve(r)) {
                resizeSnap_.push_back(*s);
                resizeRefs_.push_back(r);
            }
    }

    if (resizeHandle_ >= 0 && ImGui::IsMouseDown(ImGuiMouseButton_Left)) {
        const int h = resizeHandle_;
        glm::vec3 nmn = resizeStartMin_, nmx = resizeStartMax_;

        auto applyAxis = [&](int ax, float coord) {
            if (resizeAnchor_[ax] == resizeStartMin_[ax])
                nmx[ax] = std::max(coord, resizeAnchor_[ax] + 1.0f);
            else
                nmn[ax] = std::min(coord, resizeAnchor_[ax] - 1.0f);
        };

        if (persp) {
            const int ax = h / 2;
            glm::vec3 ro, rd;
            p.camera.pixelRay({m.x - p.contentMin.x, m.y - p.contentMin.y},
                              p.contentSize, ro, rd);
            // Closest approach between the ray and the world-axis line through ctr.
            glm::vec3 u(0.0f);
            u[ax] = 1.0f;
            const glm::vec3 w0 = ctr - ro;
            const float b = glm::dot(u, rd), c = glm::dot(rd, rd);
            const float d = glm::dot(u, w0), e = glm::dot(rd, w0);
            const float denom = c - b * b;
            const float t = std::fabs(denom) > 1e-5f ? (b * e - c * d) / denom : 0.0f;
            applyAxis(ax, snapF(ctr[ax] + t));
        } else {
            const glm::vec3 hit = snapVec(viewPlanePoint(p, m));
            if (h != 6 && h != 7) applyAxis(au, hit[au]);
            if (h != 4 && h != 5) applyAxis(av, hit[av]);
        }

        const glm::vec3 os = glm::max(resizeStartMax_ - resizeStartMin_,
                                      glm::vec3(1e-3f));
        const glm::vec3 sc = glm::max(nmx - nmn, glm::vec3(1.0f)) / os;
        glm::mat4 mtx(1.0f);
        mtx = glm::translate(mtx, nmn);
        mtx = glm::scale(mtx, sc);
        mtx = glm::translate(mtx, -resizeStartMin_);
        for (size_t i = 0; i < resizeRefs_.size(); ++i)
            if (map::Solid* s = doc_.resolve(resizeRefs_[i])) {
                *s = resizeSnap_[i];
                s->transform(mtx);
            }
        docMeshDirty_ = true;
    }

    if (resizeHandle_ >= 0 && ImGui::IsMouseReleased(ImGuiMouseButton_Left)) {
        resizeHandle_ = -1;
        resizeSnap_.clear();
        resizeRefs_.clear();
        afterEdit("Resize");
    }
}

// Soft outline of whatever the cursor is over, so you can see what a click or
// drag will grab before you commit.
void Editor::updateHoverHighlight(ViewPanel& p) {
    const bool busy = gizmoUsing_ || resizeHandle_ >= 0 || moveDrag_ != 0 ||
                      subDragging_ || movePending_;
    if (!hasDoc() || tool_ != Tool::Select || !placing_.empty() || busy) {
        if ((hoverRef_.valid() || hoverEnt_ >= 0)) {
            hoverRef_ = {};
            hoverEnt_ = -1;
            renderer_.setHoverWire({});
        }
        return;
    }
    if (!p.hovered) return;  // another panel may own the hover this frame

    glm::vec3 ro, rd;
    const ImVec2 m = ImGui::GetMousePos();
    p.camera.pixelRay({m.x - p.contentMin.x, m.y - p.contentMin.y}, p.contentSize,
                      ro, rd);

    float bestT = 1e30f;
    map::SolidRef hit;
    int hitEnt = -1;
    auto test = [&](const map::Solid& s, int ent, int idx) {
        float t;
        if (s.valid && !s.hidden && map::raySolid(ro, rd, s, t) && t > 0 && t < bestT) {
            bestT = t;
            hit = {ent, idx};
            hitEnt = -1;
        }
    };
    for (int i = 0; i < (int)doc_.worldSolids().size(); ++i)
        test(doc_.worldSolids()[i], -1, i);
    for (int e = 0; e < (int)doc_.entities().size(); ++e) {
        const auto& ent = doc_.entities()[e];
        if (ent.hidden) continue;
        for (int i = 0; i < (int)ent.solids.size(); ++i) test(ent.solids[i], e, i);
        if (ent.solids.empty()) {  // point entity: small box
            float t;
            map::Solid box = map::Solid::makeBox(ent.origin - glm::vec3(18),
                                                 ent.origin + glm::vec3(18), "");
            if (map::raySolid(ro, rd, box, t) && t > 0 && t < bestT) {
                bestT = t;
                hit = {};
                hitEnt = e;
            }
        }
    }

    // Don't highlight what's already selected.
    bool selected = hitEnt >= 0 ? (hitEnt == selectedEntity_)
                                : std::find(selection_.begin(), selection_.end(),
                                            hit) != selection_.end();

    if ((hit == hoverRef_ && hitEnt == hoverEnt_)) return;  // unchanged
    hoverRef_ = hit;
    hoverEnt_ = hitEnt;

    std::vector<glm::vec3> wire;
    if (!selected) {
        if (hitEnt >= 0) {
            const glm::vec3 o = doc_.entities()[hitEnt].origin;
            map::Solid box = map::Solid::makeBox(o - glm::vec3(18), o + glm::vec3(18),
                                                 "");
            wire = map::solidWire(box);
        } else if (const map::Solid* s = doc_.resolve(hit)) {
            wire = map::solidWire(*s);
        }
    }
    renderer_.setHoverWire(wire);
}

// Grab anywhere on the selected object and drag it. 3D view moves along the
// ground (hold Shift for up/down); the 2D views move in the view plane.
void Editor::handleSelectionMove(ViewPanel& p) {
    if (tool_ != Tool::Select || gizmoUsing_ || resizeHandle_ >= 0 ||
        resizeHot_ >= 0)
        return;

    const bool haveBrush = !selection_.empty();
    const bool haveEnt = !haveBrush && selectedEntity_ >= 0 &&
                         selectedEntity_ < (int)doc_.entities().size();
    if (!haveBrush && !haveEnt) return;

    glm::vec3 mn(1e30f), mx(-1e30f);
    if (haveBrush) {
        for (const auto& r : selection_)
            if (const map::Solid* s = doc_.resolve(r)) {
                mn = glm::min(mn, s->boundsMin);
                mx = glm::max(mx, s->boundsMax);
            }
    } else {
        mn = doc_.entities()[selectedEntity_].origin - glm::vec3(20);
        mx = doc_.entities()[selectedEntity_].origin + glm::vec3(20);
    }
    if (mn.x > mx.x) return;
    const glm::vec3 ctr = 0.5f * (mn + mx);
    const ImVec2 m = ImGui::GetMousePos();
    const bool persp = p.kind == ViewKind::Perspective;
    glm::vec3 ro, rd;
    p.camera.pixelRay({m.x - p.contentMin.x, m.y - p.contentMin.y}, p.contentSize,
                      ro, rd);

    auto planePt = [&](float planeZ, bool vertical) -> glm::vec3 {
        if (vertical) {
            // closest approach of the ray to the vertical line through ctr
            const glm::vec3 u(0, 0, 1);
            const glm::vec3 w0 = ctr - ro;
            const float b = glm::dot(u, rd), c = glm::dot(rd, rd);
            const float dd = glm::dot(u, w0), e = glm::dot(rd, w0);
            const float den = c - b * b;
            const float t = std::fabs(den) > 1e-5f ? (b * e - c * dd) / den : 0.0f;
            return glm::vec3(ctr.x, ctr.y, ctr.z + t);
        }
        if (std::fabs(rd.z) < 1e-4f) return ctr;
        const float t = (planeZ - ro.z) / rd.z;
        return ro + rd * t;
    };

    // ---- arm on press over the body; only becomes a move once you drag ----
    if (moveDrag_ == 0 && !movePending_ && p.hovered &&
        ImGui::IsMouseClicked(ImGuiMouseButton_Left)) {
        bool over = false;
        if (persp) {
            float t;
            if (haveBrush) {
                for (const auto& r : selection_)
                    if (const map::Solid* s = doc_.resolve(r))
                        if (s->valid && map::raySolid(ro, rd, *s, t)) { over = true; break; }
            }
            if (!over) {  // fall back to the projected bbox
                const glm::mat4 vp =
                    p.camera.proj(p.contentSize.x / std::max(1.0f, p.contentSize.y)) *
                    p.camera.view();
                const glm::vec4 cc = vp * glm::vec4(ctr, 1.0f);
                if (cc.w > 1e-4f) {
                    const ImVec2 sp(
                        p.contentMin.x + (cc.x / cc.w * 0.5f + 0.5f) * p.contentSize.x,
                        p.contentMin.y +
                            (1.0f - (cc.y / cc.w * 0.5f + 0.5f)) * p.contentSize.y);
                    over = std::hypot(sp.x - m.x, sp.y - m.y) < pb::ui::dp(28.0f);
                }
            }
        } else {
            // inside the projected 2D box, inset so the edge handles still win
            const glm::mat4 vp =
                p.camera.proj(p.contentSize.x / std::max(1.0f, p.contentSize.y)) *
                p.camera.view();
            auto pr = [&](const glm::vec3& w) {
                const glm::vec4 c = vp * glm::vec4(w, 1.0f);
                return ImVec2(
                    p.contentMin.x + (c.x / c.w * 0.5f + 0.5f) * p.contentSize.x,
                    p.contentMin.y + (1.0f - (c.y / c.w * 0.5f + 0.5f)) * p.contentSize.y);
            };
            const ImVec2 a = pr(mn), b = pr(mx);
            const float x0 = std::min(a.x, b.x) + 10, x1 = std::max(a.x, b.x) - 10;
            const float y0 = std::min(a.y, b.y) + 10, y1 = std::max(a.y, b.y) - 10;
            over = m.x > x0 && m.x < x1 && m.y > y0 && m.y < y1;
        }
        if (over) {
            movePending_ = true;
            moveIsEnt_ = haveEnt;
            if (haveEnt) moveEntStart_ = doc_.entities()[selectedEntity_].origin;
            resizeSnap_.clear();
            resizeRefs_.clear();
            if (haveBrush)
                for (const auto& r : selection_)
                    if (const map::Solid* s = doc_.resolve(r)) {
                        resizeSnap_.push_back(*s);
                        resizeRefs_.push_back(r);
                    }
        }
    }

    // Promote to an actual move once the cursor leaves the click point.
    if (movePending_ && moveDrag_ == 0 &&
        ImGui::IsMouseDragPastThreshold(ImGuiMouseButton_Left, 4.0f)) {
        moveDrag_ = (persp && ImGui::GetIO().KeyShift) ? 2 : 1;
        moveGrab_ = planePt(ctr.z, moveDrag_ == 2);
    }

    // ---- dragging ----
    if (moveDrag_ != 0 && ImGui::IsMouseDown(ImGuiMouseButton_Left)) {
        const glm::vec3 now = planePt(moveGrab_.z, moveDrag_ == 2);
        glm::vec3 d = now - moveGrab_;
        if (moveDrag_ == 1) d.z = 0.0f;
        else d = glm::vec3(0, 0, d.z);
        d = snapVec(d);
        if (d != glm::vec3(0)) {
            if (moveIsEnt_) {
                auto& e = doc_.entities()[selectedEntity_];
                e.origin = moveEntStart_ + d;
                e.kv.set("origin", std::to_string((int)e.origin.x) + " " +
                                       std::to_string((int)e.origin.y) + " " +
                                       std::to_string((int)e.origin.z));
            } else {
                for (size_t i = 0; i < resizeRefs_.size(); ++i)
                    if (map::Solid* s = doc_.resolve(resizeRefs_[i])) {
                        *s = resizeSnap_[i];
                        s->translate(d);
                    }
            }
            docMeshDirty_ = true;
        }
    }

    if (ImGui::IsMouseReleased(ImGuiMouseButton_Left)) {
        const bool didMove = moveDrag_ != 0;
        moveDrag_ = 0;
        movePending_ = false;
        resizeSnap_.clear();
        resizeRefs_.clear();
        if (didMove) {
            afterEdit("Move");
            status_ = moveIsEnt_ ? "Moved entity" : "Moved selection";
        }
    }
}

void Editor::drawSelectionDims(ViewPanel& p, float aspect, ImDrawList* dl) {
    if (selection_.empty()) return;
    glm::vec3 mn(1e30f), mx(-1e30f);
    for (const auto& r : selection_)
        if (const map::Solid* s = doc_.resolve(r)) {
            mn = glm::min(mn, s->boundsMin);
            mx = glm::max(mx, s->boundsMax);
        }
    if (mn.x > mx.x) return;
    const glm::mat4 vp = p.camera.proj(aspect) * p.camera.view();
    auto pr = [&](const glm::vec3& w, bool& ok) {
        return projectPt(p.kind, vp, p.contentMin, p.contentSize, w, ok);
    };

    // 3D view: 6 face-centre handles + a faint box, no dimension text.
    if (p.kind == ViewKind::Perspective) {
        if (tool_ != Tool::Select) return;
        const glm::vec3 ctr = 0.5f * (mn + mx);
        for (int hnd = 0; hnd < 6; ++hnd) {
            const int ax = hnd / 2;
            glm::vec3 wp = ctr;
            wp[ax] = (hnd & 1) ? mx[ax] : mn[ax];
            bool ok;
            const ImVec2 s = pr(wp, ok);
            if (!ok) continue;
            const bool hot = (hnd == resizeHot_ || hnd == resizeHandle_);
            const float r = pb::ui::dp(hot ? 10.0f : 7.0f);
            const ImU32 hc = hot ? IM_COL32(255, 180, 90, 255)
                                 : IM_COL32(255, 214, 150, 235);
            dl->AddRectFilled(ImVec2(s.x - r, s.y - r), ImVec2(s.x + r, s.y + r), hc,
                              pb::ui::dp(2.0f));
            dl->AddRect(ImVec2(s.x - r, s.y - r), ImVec2(s.x + r, s.y + r),
                        IM_COL32(15, 15, 18, 235), pb::ui::dp(2.0f), 0, 1.5f);
        }
        return;
    }

    bool a, b;
    const ImVec2 s0 = pr(mn, a);
    const ImVec2 s1 = pr(mx, b);
    if (!a || !b) return;
    const glm::vec3 rt = p.camera.orthoRightAxis(), up = p.camera.orthoUpAxis();
    const float w = std::fabs(glm::dot(mx - mn, rt));
    const float h = std::fabs(glm::dot(mx - mn, up));
    const float x0 = std::min(s0.x, s1.x), x1 = std::max(s0.x, s1.x);
    const float y0 = std::min(s0.y, s1.y), y1 = std::max(s0.y, s1.y);
    const ImU32 c = IM_COL32(255, 210, 140, 220);
    char b1[32], b2[32];
    std::snprintf(b1, sizeof(b1), "%.0f", w);
    std::snprintf(b2, sizeof(b2), "%.0f", h);
    dl->AddText(ImVec2((x0 + x1) * 0.5f - ImGui::CalcTextSize(b1).x * 0.5f, y0 - 16), c, b1);
    dl->AddText(ImVec2(x1 + 4, (y0 + y1) * 0.5f - 7), c, b2);
    dl->AddRect(ImVec2(x0, y0), ImVec2(x1, y1), IM_COL32(255, 210, 140, 90));

    // Hammer-style resize handles (Select tool only).
    if (tool_ != Tool::Select) return;
    const ImVec2 pts[8] = {
        {x0, y0}, {x1, y0}, {x1, y1}, {x0, y1},
        {x0, (y0 + y1) * 0.5f}, {x1, (y0 + y1) * 0.5f},
        {(x0 + x1) * 0.5f, y0}, {(x0 + x1) * 0.5f, y1}};
    for (int i = 0; i < 8; ++i) {
        const bool hot = (i == resizeHot_ || i == resizeHandle_);
        const float r = pb::ui::dp(hot ? 8.5f : 6.0f);
        const ImU32 hc = hot ? IM_COL32(255, 180, 90, 255)
                             : IM_COL32(255, 214, 150, 230);
        dl->AddRectFilled(ImVec2(pts[i].x - r, pts[i].y - r),
                          ImVec2(pts[i].x + r, pts[i].y + r), hc, pb::ui::dp(2.0f));
        dl->AddRect(ImVec2(pts[i].x - r, pts[i].y - r),
                    ImVec2(pts[i].x + r, pts[i].y + r), IM_COL32(15, 15, 18, 235),
                    pb::ui::dp(2.0f), 0, 1.5f);
    }
}

void Editor::autosaveTick() {
    if (!autosaveOn_ || !hasDoc() || !doc_.dirty()) return;
    const double now = ImGui::GetTime();
    if (lastAutosave_ == 0.0) { lastAutosave_ = now; return; }
    if (now - lastAutosave_ < autosaveMins_ * 60.0) return;
    lastAutosave_ = now;

    std::string base = doc_.path();
    if (base.empty())
        base = (fs::path(executableDir()) / "autosave" /
                ((doc_.name().empty() ? "untitled" : doc_.name()) + ".vmf"))
                   .string();
    const std::string as = base + ".autosave.vmf";
    std::string err;
    if (doc_.saveVmf(as, &err, /*updateState=*/false))
        status_ = "Autosaved  " + fs::path(as).filename().string();
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
