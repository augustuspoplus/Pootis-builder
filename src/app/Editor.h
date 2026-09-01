#pragma once
#include <array>
#include <atomic>
#include <memory>
#include <string>
#include <thread>

#include <imgui.h>

#include "app/Settings.h"
#include "bsp/BspFile.h"
#include "bsp/BspMesh.h"
#include "compile/MapCompiler.h"
#include "map/History.h"
#include "map/MapDocument.h"
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
    void debugSelectWorldSolid(int i);  // test hook for headless screenshots
    void debugBuildSampleMap();
    void debugStartCompile(bool fast);
    bool saveVmf(const std::string& path);

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

    bool hasMap() const { return bsp_.loaded() || doc_.active(); }
    bool hasDoc() const { return doc_.active(); }
    bool busy() const { return decompileRunning_.load() || compiler_.running(); }
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
    void drawCompileWindow();
    bool saveMap(bool forceDialog);   // true if written
    void startCompile();
    void drawProperties();
    void drawBrushInspector();
    void drawOutliner();
    void drawMaterialList();
    void drawTextureBrowser();
    void drawEntityCatalog();
    void drawStatusBar();
    void handleViewportInput(ViewPanel& p);
    void pickAt(ViewPanel& p, const glm::vec2& pxInViewport, bool additive);
    void rebuildSelectionWire();
    void clearSelection();
    void afterEdit(const char* label);   // re-mesh + record undo + refresh
    void drawGizmo(ViewPanel& p, float aspect);
    void handleBlockTool(ViewPanel& p);
    void placePiece(const std::string& piece, const glm::vec3& at);
    glm::vec3 viewPlanePoint(ViewPanel& p, const ImVec2& mouse) const;
    glm::vec3 snapVec(const glm::vec3& v) const;
    void nudgeSelection(const glm::vec3& worldDelta);
    void deleteSelection();
    void duplicateSelection();
    void undo();
    void redo();
    glm::vec3 selectionCenter() const;

    GLFWwindow* window_ = nullptr;
    BspFile bsp_;
    map::MapDocument doc_;
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

    std::vector<map::SolidRef> selection_;
    map::History history_;
    int gizmoMode_ = 0;          // 0 move, 1 rotate, 2 scale
    bool gizmoUsing_ = false;
    bool docMeshDirty_ = false;

    // Block tool
    bool blockDragging_ = false;
    ViewKind blockView_ = ViewKind::Top;
    glm::vec3 blockA_{0}, blockB_{0};
    float newBrushDepth_ = 128.0f;
    std::string blockMaterial_ = "dev/dev_measuregeneric01b";

    Mode mode_ = Mode::Simple;
    Tool tool_ = Tool::Select;
    bool layoutDirty_ = true;
    int gridSize_ = 64;
    bool snap_ = true;
    int kitTab_ = 0;
    std::string placing_;

    // Background BSP -> VMF decompile.
    std::thread decompileThread_;
    std::atomic<bool> decompileRunning_{false};
    std::atomic<bool> decompileDone_{false};
    std::string decompileVmf_;
    std::string decompileErr_;
    void pollDecompile();

    Settings prefs_;
    float uiScale_ = 1.0f;
    bool scaleDirty_ = false;
    bool showWelcome_ = true;

    // Compile + playtest (Milestone E).
    compile::MapCompiler compiler_;
    compile::GamePaths gamePaths_;
    bool showCompile_ = false;
    int compileProfile_ = 0;   // 0 fast, 1 final
    bool compileVvis_ = true;
    bool compileVrad_ = true;
    bool compileLaunch_ = true;
    bool compileAutoScroll_ = true;
    size_t compileLogSeen_ = 0;
};

}  // namespace pb
