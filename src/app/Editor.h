#pragma once
#include <array>
#include <atomic>
#include <functional>
#include <memory>
#include <string>
#include <thread>

#include <imgui.h>

#include "app/Settings.h"
#include "bsp/BspFile.h"
#include "bsp/BspMesh.h"
#include "compile/MapCompiler.h"
#include "fgd/Fgd.h"
#include "import/ModelImport.h"
#include "import/ObjModel.h"
#include "map/BrushEdit.h"
#include "map/History.h"
#include "publish/Workshop.h"
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
    void debugSelectEntity(int i);
    void debugPlaceEntity(const std::string& cls);
    void debugBuildSampleMap();
    void debugStartCompile(bool fast);
    void debugShowWorkshop();
    void debugFocusPanel(const std::string& name) { focusPanel_ = name; focusPanelFrames_ = 6; }
    void debugSubObjectDemo(int solidIdx, int mode);  // select brush, deform one handle
    void debugTextureDemo(int solidIdx);              // pick faces for the Texture tool
    void debugShapeOp(int op);                        // 0 hollow, 1 carve, 2 clip
    void debugMapCheck() { runMapCheck(); }
    void debugShowPalette() { showPalette_ = true; }
    void debugPlacePrefab(const std::string& p) { placePrefab(p, glm::vec3(0)); }
    void debugDumpProps();
    void debugNoDecompile() { suppressAutoDecompile_ = true; }
    void debugNewBlank() {
        doc_.newBlank("untitled");
        history_.reset(doc_);
        showWelcome_ = false;
        buildAndUpload(meshOpts_);
        for (auto& v : views_) { v.camera = Camera{}; v.camera.kind = v.kind; }
    }
    void debugCordon(float half) {
        cordonOn_ = true;
        cordonMin_ = glm::vec3(-half);
        cordonMax_ = glm::vec3(half);
    }
    void debugDumpFgd(const std::string& cls);
    void debugImportObj(const std::string& path);  // detail-brush import, headless
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
    enum class SubMode { Vertex, Edge, Face };

    void buildAndUpload(const MeshBuildOptions& opts);
    void loadFgd();
    void frameAllViews();
    void buildDockLayout(unsigned int dockId, const ImVec2& size);
    void drawTopBar();
    void drawViewMenuPopup();
    void drawWelcome();
    void uiScaleMenu();
    void drawViewportPanel(ViewPanel& p);
    void drawBuildKit();
    void openModelImport();
    void reloadModelPreview();
    void drawModelImportDialog();
    void doModelImport();
    void drawWorkshopWindow();
    void captureWorkshopPreview();
    void drawSelectionPanel();
    void drawCompileWindow();
    bool saveMap(bool forceDialog);   // true if written
    void startCompile();
    void drawProperties();
    void drawBrushInspector();
    void drawEntityProperties();   // FGD-driven, for the selected entity
    void drawIoEditor(map::MapEntity& e, bool* committed);
    void syncSelectedEntity();     // set selectedEntity_ from the solid selection
    void drawOutliner();
    void drawMaterialList();
    void drawTextureBrowser();
    void drawModelBrowser();
    void drawEntityCatalog();
    void drawStatusBar();
    void drawHistoryPanel();
    void drawMapCheckPanel();
    void runMapCheck();
    void drawCommandPalette();
    void drawLogPanel();
    void drawVisgroupsPanel();
    void saveProject(bool forceDialog);   // .pbproj bundle
    void openProject(const std::string& path);
    void drawCordonOverlay(ViewPanel& p, float aspect, ImDrawList* dl);
    void handleCordonDrag(ViewPanel& p);
    map::MapDocument buildCompileDoc();   // applies the cordon, adds seal brushes
    void drawPrefabPanel();
    void placePrefab(const std::string& path, const glm::vec3& at);
    void saveSelectionAsPrefab();
    void drawSelectionDims(ViewPanel& p, float aspect, ImDrawList* dl);
    void autosaveTick();
    void writeBackup(const std::string& vmfPath);
    void handleViewportInput(ViewPanel& p);
    void pickAt(ViewPanel& p, const glm::vec2& pxInViewport, bool additive);
    void rebuildSelectionWire();
    void clearSelection();
    void expandSelectionToGroups();   // pull in group-siblings of the picked solids
    void groupSelection();
    void ungroupSelection();
    void afterEdit(const char* label);   // re-mesh + record undo + refresh
    void drawGizmo(ViewPanel& p, float aspect);
    void drawEntityTags(ViewPanel& p, float aspect, ImDrawList* dl);
    void handleBlockTool(ViewPanel& p);
    void handleSelectionResize(ViewPanel& p);    // Hammer-style bbox drag handles
    void rebuildHandles();                       // sub-object handles for selection_[0]
    void handleSubObjectInput(ViewPanel& p);
    void drawSubObjectOverlay(ViewPanel& p, float aspect, ImDrawList* dl);
    void handleTextureTool(ViewPanel& p);        // Texture tool: pick faces
    void drawFaceOverlay(ViewPanel& p, float aspect, ImDrawList* dl);
    void drawFaceEditPanel();                    // the Face Edit sheet
    void handleClipTool(ViewPanel& p);           // Clip tool: draw a cut line
    void drawClipOverlay(ViewPanel& p, float aspect, ImDrawList* dl);
    void applyClip();
    void applyToTexFaces(const std::function<void(map::BrushFace&)>& fn,
                         const char* undoLabel, bool commit);
    void placePiece(const std::string& piece, const glm::vec3& at);
    void placeFgdEntity(const std::string& cls, const glm::vec3& at);
    void tieSelectionToEntity(const std::string& cls);
    glm::vec3 viewPlanePoint(ViewPanel& p, const ImVec2& mouse) const;
    glm::vec3 snapVec(const glm::vec3& v) const;
    float snapF(float v) const;
    void nudgeSelection(const glm::vec3& worldDelta);
    void deleteSelection();
    void duplicateSelection();
    void undo();
    void redo();
    glm::vec3 selectionCenter() const;

    GLFWwindow* window_ = nullptr;
    BspFile bsp_;
    fgd::Fgd fgd_;
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
    std::string focusPanel_;  // debug: focus this dock tab next frame
    int focusPanelFrames_ = 0;
    bool suppressAutoDecompile_ = false;  // debug: inspect the raw BSP view

    // QoL: command palette, map-check, autosave.
    bool showPalette_ = false;
    char paletteQuery_[128] = {0};
    int paletteSel_ = 0;
    struct CheckHit {
        std::string msg;
        int severity = 0;   // 0 info, 1 warning, 2 error
        int entity = -2;    // -2 = no jump, -1 = world solid, >=0 entity index
        int solid = -1;
        glm::vec3 pos{0};
    };
    std::vector<CheckHit> mapCheck_;
    bool mapCheckRan_ = false;
    double lastAutosave_ = 0.0;
    bool autosaveOn_ = true;
    float autosaveMins_ = 5.0f;
    bool logAutoScroll_ = true;
    size_t logSeen_ = 0;

    // Camera bookmarks (per 3D-view state) + go-to-coordinate.
    struct CamMark { bool set = false; glm::vec3 pos{0}; float yaw = 0, pitch = 0; };
    std::array<CamMark, 6> camMarks_;
    glm::vec3 gotoCoord_{0};
    std::string projectPath_;

    char outlinerFilter_[128] = {0};
    char materialFilter_[128] = {0};
    char textureFilter_[128] = {0};
    char modelFilter_[128] = {0};
    std::vector<std::string> modelList_;             // every models/**.mdl, sorted
    std::unordered_map<std::string, std::string> modelFirstMat_;  // path -> material
    bool modelListBuilt_ = false;
    float flySpeed_ = 900.0f;

    std::vector<map::SolidRef> selection_;
    int selectedEntity_ = -1;          // index into doc_.entities(), or -1
    char propFilter_[96] = {0};
    map::History history_;
    int gizmoMode_ = 0;          // 0 move, 1 rotate, 2 scale
    bool gizmoUsing_ = false;
    bool docMeshDirty_ = false;

    // Bounding-box resize (Select tool, 2D views)
    int resizeHandle_ = -1;      // 0..8: corners 0-3, edges 4-7, -1 none, 8 hover-only
    int resizeHot_ = -1;         // handle under the cursor this frame
    glm::vec3 resizeAnchor_{0};  // world point that stays fixed during the drag
    glm::vec3 resizeStartMin_{0}, resizeStartMax_{0};
    std::vector<map::Solid> resizeSnap_;
    std::vector<map::SolidRef> resizeRefs_;

    // Block tool
    bool blockDragging_ = false;
    ViewKind blockView_ = ViewKind::Top;
    glm::vec3 blockA_{0}, blockB_{0};
    float newBrushDepth_ = 128.0f;
    std::string blockMaterial_ = "dev/dev_measuregeneric01b";

    // Texture tool: faces picked for texturing (SolidRef + face index).
    std::vector<std::pair<map::SolidRef, int>> texFaces_;
    char texMaterial_[128] = "dev/dev_measuregeneric01b";

    // Cordon: compile / preview only a boxed region.
    bool cordonOn_ = false;
    bool cordonShow_ = true;
    glm::vec3 cordonMin_{-1024, -1024, -512};
    glm::vec3 cordonMax_{1024, 1024, 512};
    int cordonDragAxis_ = -1;   // 0..5 = -x,+x,-y,+y,-z,+z face being dragged
    ViewKind cordonDragView_ = ViewKind::Top;

    // Clip tool
    bool clipDragging_ = false;
    bool clipArmed_ = false;               // a line has been drawn, awaiting Enter
    ViewKind clipView_ = ViewKind::Top;
    glm::vec3 clipA_{0}, clipB_{0};
    int clipMode_ = 0;                      // 0 keep front, 1 keep back, 2 keep both

    // Sub-object (Vertex/Edge/Face) editing — operates on selection_[0].
    SubMode subMode_ = SubMode::Vertex;
    map::BrushHandles handles_;
    bool handlesDirty_ = true;
    int subSel_ = -1;             // index into verts / edges / faces per subMode_
    int subHot_ = -1;            // hovered handle this frame
    bool subDragging_ = false;
    glm::vec3 subDragStartHit_{0}, subDragStartPos_{0}, subCurPos_{0};

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

    // 3D model import (.obj -> func_detail brushwork, or a baked prop_static)
    bool showModelImport_ = false;
    std::string modelImportPath_;
    std::string modelImportErr_;
    import::ObjMesh modelPreview_;
    import::ObjLoadOptions modelLoadOpts_;
    import::ModelImportOptions modelPlaceOpts_;
    std::vector<std::string> pendingModelQc_;  // .qc files the next compile bakes

    // Steam Workshop publish page
    bool showWorkshop_ = false;
    bool wsStagedOk_ = false;
    publish::WorkshopItem wsItem_;
    publish::StageResult wsStaged_;
    std::string wsErr_;
    char wsIdBuf_[32] = {0};
    char wsUserBuf_[64] = {0};

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
    bool compilePack_ = false;
    std::vector<std::string> packFiles_;  // "<bsp/path>|<abs source>"
    char packAddPath_[512] = {0};
    size_t compileLogSeen_ = 0;
};

}  // namespace pb
