#include "app/Editor.h"

#include <algorithm>
#include <cstring>
#include <filesystem>

#include <imgui.h>
#include <imgui_internal.h>

#include "core/Log.h"
#include "gpu/Gl.h"

namespace fs = std::filesystem;

namespace pb {
namespace {
constexpr float kDeg2Rad = 3.14159265358979323846f / 180.0f;
}

bool Editor::init(GLFWwindow* window) {
    window_ = window;
    if (!renderer_.init()) return false;

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

void Editor::shutdown() { renderer_.clearWorld(); }

bool Editor::openMap(const std::string& path) {
    const std::string ext = [&] {
        std::string e = fs::path(path).extension().string();
        std::transform(e.begin(), e.end(), e.begin(), ::tolower);
        return e;
    }();

    if (ext != ".bsp") {
        status_ = "Only .bsp loading is implemented in this build: " + path;
        PB_WARN("%s", status_.c_str());
        return false;
    }

    std::string err;
    if (!bsp_.load(path, &err)) {
        status_ = "Failed to load: " + err;
        return false;
    }
    buildAndUpload(meshOpts_);
    frameAllViews();
    status_ = bsp_.name() + "  —  " + std::to_string(mesh_.drawnFaces) + " faces, " +
              std::to_string(mesh_.pointEntities.size()) + " point ents, " +
              std::to_string(mesh_.props.size()) + " props";
    return true;
}

void Editor::buildAndUpload(const MeshBuildOptions& opts) {
    mesh_ = buildWorldMesh(bsp_, opts);
    renderer_.upload(mesh_);
}

void Editor::frameAllViews() {
    for (auto& v : views_) v.camera.frameBounds(mesh_.playBoundsMin, mesh_.playBoundsMax);
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
                            ImGuiWindowFlags_NoNavFocus | ImGuiWindowFlags_MenuBar;
    ImGui::Begin("##PootisHost", nullptr, host);
    ImGui::PopStyleVar(3);

    const ImGuiID dockId = ImGui::GetID("PootisDock");

    drawMenuBar();

    if (!ImGui::DockBuilderGetNode(dockId)) {
        ImGui::DockBuilderRemoveNode(dockId);
        ImGui::DockBuilderAddNode(dockId, ImGuiDockNodeFlags_DockSpace);
        ImGui::DockBuilderSetNodeSize(dockId, vp->WorkSize);

        ImGuiID left, center;
        left = ImGui::DockBuilderSplitNode(dockId, ImGuiDir_Left, 0.19f, nullptr, &center);
        ImGuiID top, bottom;
        top = ImGui::DockBuilderSplitNode(center, ImGuiDir_Up, 0.5f, nullptr, &bottom);
        ImGuiID tl, tr, bl, br;
        tl = ImGui::DockBuilderSplitNode(top, ImGuiDir_Left, 0.5f, nullptr, &tr);
        bl = ImGui::DockBuilderSplitNode(bottom, ImGuiDir_Left, 0.5f, nullptr, &br);

        ImGui::DockBuilderDockWindow("Map Contents", left);
        ImGui::DockBuilderDockWindow("Materials", left);
        ImGui::DockBuilderDockWindow("Entities", left);
        ImGui::DockBuilderDockWindow("3D View", tl);
        ImGui::DockBuilderDockWindow("Top (x/y)", tr);
        ImGui::DockBuilderDockWindow("Front (x/z)", bl);
        ImGui::DockBuilderDockWindow("Side (y/z)", br);
        ImGui::DockBuilderFinish(dockId);
    }
    ImGui::DockSpace(dockId, ImVec2(0, 0), ImGuiDockNodeFlags_PassthruCentralNode);
    ImGui::End();

    drawOutliner();
    drawMaterialList();
    drawEntityCatalog();
    for (auto& v : views_) drawViewportPanel(v);
    drawStatusBar();
}

void Editor::drawMenuBar() {
    if (!ImGui::BeginMenuBar()) return;
    if (ImGui::BeginMenu("File")) {
        if (ImGui::MenuItem("Open BSP...", "Ctrl+O")) {
            // Minimal: rely on the map passed on the command line for now.
            status_ = "Pass a .bsp path on the command line (file dialog lands next).";
        }
        ImGui::Separator();
        if (ImGui::MenuItem("Exit")) glfwSetWindowShouldClose(window_, 1);
        ImGui::EndMenu();
    }
    if (ImGui::BeginMenu("View")) {
        ImGui::MenuItem("Grid", nullptr, &settings_.showGrid);
        ImGui::MenuItem("Static props", nullptr, &settings_.showProps);
        ImGui::MenuItem("Point entities", nullptr, &settings_.showPointEntities);
        ImGui::MenuItem("Lightmap shading", nullptr, &settings_.lightingOnly);
        ImGui::MenuItem("Wire overlay (3D)", nullptr, &settings_.wireOverlay);
        ImGui::Separator();
        if (ImGui::MenuItem("Reset layout")) {
            ImGui::DockBuilderRemoveNode(ImGui::GetID("PootisDock"));
        }
        if (ImGui::MenuItem("Frame map", "F") && hasMap()) frameAllViews();
        ImGui::EndMenu();
    }
    if (ImGui::BeginMenu("Lighting")) {
        ImGui::SliderFloat("Exposure", &settings_.exposure, 0.2f, 3.0f, "%.2f");
        if (ImGui::SliderFloat("Lightmap gain", &meshOpts_.lightmapGain, 0.3f, 4.0f,
                               "%.2f")) {
            if (hasMap()) buildAndUpload(meshOpts_);
        }
        ImGui::EndMenu();
    }
    ImGui::TextDisabled("   |   %s", status_.c_str());
    ImGui::EndMenuBar();
}

// ---------------------------------------------------------------------------
// Viewport panels
// ---------------------------------------------------------------------------
void Editor::drawViewportPanel(ViewPanel& p) {
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0, 0));
    ImGui::Begin(p.title);
    ImGui::PopStyleVar();

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
    ImGui::GetWindowDrawList()->AddText(ImVec2(tl.x + 8, tl.y + 6),
                                        IM_COL32(210, 210, 210, 200), p.title);
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
}

// ---------------------------------------------------------------------------
// Panels
// ---------------------------------------------------------------------------
void Editor::drawOutliner() {
    ImGui::Begin("Map Contents");
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
    if (ImGui::Begin("##status", nullptr, flags)) {
        const Camera& c3d = views_[0].camera;
        ImGui::Text("%s", status_.c_str());
        ImGui::SameLine();
        ImGui::TextDisabled("      cam  %.0f %.0f %.0f   yaw %.0f  pitch %.0f", c3d.pos.x,
                            c3d.pos.y, c3d.pos.z, c3d.yawDeg, c3d.pitchDeg);
        if (hasMap()) {
            ImGui::SameLine();
            ImGui::TextDisabled("      verts %zu  tris %zu", mesh_.vertices.size(),
                                mesh_.indices.size() / 3);
        }
    }
    ImGui::End();
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
