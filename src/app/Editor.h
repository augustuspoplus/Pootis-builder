#pragma once
#include <array>
#include <memory>
#include <string>

#include <imgui.h>

#include "app/Settings.h"
#include "bsp/BspFile.h"
#include "bsp/BspMesh.h"
#include "render/Camera.h"
#include "render/Framebuffer.h"
#include "render/MaterialLibrary.h"
#include "render/SceneRenderer.h"
#include "source/SourceFs.h"

struct GLFWwindow;

namespace pb {

using bsp::BspFile;
using bsp::MeshBuildOptions;
using bsp::WorldMesh;

// Top-level editor: owns the loaded map, the four Hammer-style viewports and
// the docked ImGui panels.
class Editor {
public:
    bool init(GLFWwindow* window);
    void shutdown();

    bool openMap(const std::string& path);
    void promptOpenMap();  // native file dialog
    void setProMode() { mode_ = Mode::Pro; layoutDirty_ = true; }

    // Persisted settings + UI scaling (the font atlas rebuild is done by the
    // caller so it happens outside a frame).
    void attachSettings(Settings s, float effectiveScale);
    void requestUiScale(float scale);
    bool takeFontRebuild(float& outScale);
    void showWelcome() { showWelcome_ = true; }

    // Per-frame: process viewport input, render the four views to FBOs, then
    // emit the ImGui layout. Call between ImGui::NewFrame and ImGui::Render.
    void frame();

    // Offscreen single-view render for --screenshot. Returns RGBA8 rows top-down.
    bool renderToImage(ViewKind view, int w, int h, std::vector<uint8_t>& rgba);

    // Offscreen 2x2 render matching the default editor layout.
    bool renderQuadToImage(int w, int h, std::vector<uint8_t>& rgba);

    bool hasMap() const { return bsp_.loaded(); }
    const std::string& status() const { return status_; }

private:
    struct ViewPanel {
        const char* title;
        ViewKind kind;
        Camera camera;
        Framebuffer fb;
        bool hovered = false;
        glm::vec2 contentMin{0.0f};
        glm::vec2 contentSize{0.0f};
    };

    enum class Mode { Simple, Pro };
    enum class Tool { Select, Block, Vertex, Clip, Texture, Entity };

    void buildAndUpload(const MeshBuildOptions& opts);
    void frameAllViews();
    void buildDockLayout(unsigned int dockId, const ImVec2& size);
    void drawTopBar();
    void drawViewMenuPopup();
    void drawWelcome();
    void uiScaleMenu();
    void drawViewportPanel(ViewPanel& p);
    void drawBuildKit();
    void drawSelectionPanel();
    void drawOutliner();
    void drawMaterialList();
    void drawTextureBrowser();
    void drawEntityCatalog();
    void drawStatusBar();
    void handleViewportInput(ViewPanel& p);

    GLFWwindow* window_ = nullptr;
    BspFile bsp_;
    WorldMesh mesh_;
    source::SourceFs sourceFs_;
    MaterialLibrary materials_;
    SceneRenderer renderer_;
    RenderSettings settings_;
    MeshBuildOptions meshOpts_;

    std::array<ViewPanel, 4> views_;
    std::string status_ = "No map loaded";
    std::string pendingOpen_;

    char outlinerFilter_[128] = {0};
    char materialFilter_[128] = {0};
    char textureFilter_[128] = {0};
    float flySpeed_ = 900.0f;

    Mode mode_ = Mode::Simple;
    Tool tool_ = Tool::Select;
    bool layoutDirty_ = true;
    int gridSize_ = 64;
    bool snap_ = true;
    int kitTab_ = 0;
    std::string placing_;

    Settings prefs_;
    float uiScale_ = 1.0f;
    bool scaleDirty_ = false;
    bool showWelcome_ = true;
};

}  // namespace pb
