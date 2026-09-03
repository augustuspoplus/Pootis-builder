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
#include "render/ModelThumbnailer.h"
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
    void setProMode() { setDial(2); }
    void setDial(int stop) {  // 0 Guided · 1 Standard · 2 Full
        mode_ = static_cast<Mode>(std::clamp(stop, 0, 2));
        prefs_.workspaceDial = static_cast<int>(mode_);
        layoutDirty_ = true;
    }
    void debugSelectWorldSolid(int i);  // test hook for headless screenshots
    void debugSelectEntity(int i);
    void debugPlaceEntity(const std::string& cls);
    void debugPlaceKit(const std::string& piece) {
        if (!doc_.active()) { doc_.newBlank("kittest"); history_.reset(doc_); }
        placePiece(piece, glm::vec3(0)); showWelcome_ = false; frameAllViews();
    }
    void debugPerfProbe() {  // time a few consecutive edits on the loaded map
        if (!doc_.active()) return;
        for (int i = 0; i < 4; ++i)
            placePiece("Floor", glm::vec3(i * 256.0f - 4000.0f, -3000.0f, 96.0f));
    }
    void debugPhase1Test();  // exercise entity-brush edit ops on the loaded doc
    void debugModalXform();  // G/R/S numeric transform round-trip check
    void debugDispTest();    // make + sculpt + VMF round-trip a displacement
    void debugLeakTest();    // write a synthetic .lin, load it, verify the trace
    void debugLeakLoad(const std::string& p) { loadPointfile(p); }
    void debugPackScan();    // list the custom assets the loaded map references
    void debugPickTest();    // a prop's click box must match its model, not +-16
    void debugArmKit(const std::string& piece) {  // arm + force the ghost preview
        if (!doc_.active()) { doc_.newBlank("kittest"); history_.reset(doc_); }
        placing_ = piece; debugPreviewAtCenter_ = true; showWelcome_ = false;
    }
    void debugDropModel(const std::string& mdl) {
        if (!doc_.active()) { doc_.newBlank("mdltest"); history_.reset(doc_); }
        placeFgdEntity("prop_static", glm::vec3(0));
        if (!doc_.entities().empty()) doc_.entities().back().kv.set("model", mdl);
        showWelcome_ = false; afterEdit("drop"); frameAllViews();
    }
    void debugBuildSampleMap();
    void debugUndoTest();
    void debugStartCompile(bool fast);
    void debugCompileOut(const std::string& name, const std::string& dir);
    void debugShowWorkshop();
    void debugFocusPanel(const std::string& name) {
        focusPanel_ = name; focusPanelFrames_ = 6;
        for (int i = 1; i < 4; ++i)
            if (name == views_[i].title) viewOpen_[i] = true;  // open a closed 2D view
    }
    void debugSubObjectDemo(int solidIdx, int mode);  // select brush, deform one handle
    void debugTextureDemo(int solidIdx);              // pick faces for the Texture tool
    void debugShapeOp(int op);                        // 0 hollow, 1 carve, 2 clip
    void debugMapCheck() { runMapCheck(); }
    void debugShowPalette() { showPalette_ = true; }
    void debugShowSettings() { showSettings_ = true; showWelcome_ = false; }
    void makeTemplates(const std::string& outDir);
    void debugMakeTemplates(const std::string& d) { makeTemplates(d); }
    void makeTurbine(const std::string& outPath);
    void debugMakeTurbine(const std::string& p) { makeTurbine(p); }
    void debugPlacePrefab(const std::string& p) { placePrefab(p, glm::vec3(0)); }
    void debugDumpProps();
    void debugNoDecompile() { suppressAutoDecompile_ = true; }
    void debugRoad() {
        doc_.newBlank("roadtest");
        history_.reset(doc_);
        showWelcome_ = false;
        // A sharp U-turn — the case where segment gaps used to show.
        roadPts_ = {{-600, 400, 96}, {-200, 400, 96}, {100, 250, 96},
                    {200, 0, 96},    {100, -250, 96}, {-200, -400, 96},
                    {-600, -400, 96}};
        finalizeRoad();
        frameAllViews();
    }
    void debugHill() {
        doc_.newBlank("hilltest");
        history_.reset(doc_);
        showWelcome_ = false;
        placePiece("Hill", glm::vec3(0, 0, 0));
        frameAllViews();
    }
    void debugKitTab(int t) { kitTab_ = t; showWelcome_ = false; }
    // A 3/4 overview of the whole map (for docs/README shots) instead of
    // frameAllViews()'s "stand at a spawn" perspective camera.
    void debugShotOverview() {
        showWelcome_ = false;
        Camera& c = views_[0].camera;
        c.kind = ViewKind::Perspective;
        c.fovDeg = 74.0f;
        // Anchor on a spawn (always valid) and pull back + up for a 3/4 view of
        // the surrounding architecture. Bounds-based framing is unreliable on
        // decompiled maps (skybox brush blows the AABB up).
        const glm::vec3 anchor =
            mesh_.hasSpawn ? mesh_.spawnPos
                           : 0.5f * (mesh_.playBoundsMin + mesh_.playBoundsMax);
        c.yawDeg = (mesh_.hasSpawn ? mesh_.spawnYaw : 0.0f) + 8.0f;
        c.pitchDeg = -21.0f;
        c.pos = anchor - c.forward() * 1250.0f + glm::vec3(0.0f, 0.0f, 780.0f);
    }
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

    // The complexity dial. Guided = pure Build Kit; Standard = kit + the full
    // tool strip + outliner / map-check; Full = the dense Pro layout. Guided and
    // Standard share one friendly docking; only Full swaps the layout.
    enum class Mode { Guided, Standard, Full };
    enum class Tool { Select, Block, Vertex, Clip, Texture, Entity };
    enum class SubMode { Vertex, Edge, Face };

    void buildAndUpload(const MeshBuildOptions& opts);
    void loadFgd();
    void frameAllViews();
    void buildDockLayout(unsigned int dockId, const ImVec2& size);
    void drawTopBar();
    void drawViewMenuPopup();
    void drawWelcome();
    void drawKeysOverlay();
    void drawSettingsWindow();
    void applyPrefs();   // push prefs_ into the live editor state
    void uiScaleMenu();
    void drawViewportPanel(ViewPanel& p, bool* pOpen = nullptr);
    void drawBuildKit();
    void drawSimpleEntities();   // curated plain-language entity list (Simple)
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
    void drawMaterialGrid();  // shared body: Pro dock + Simple kit tab
    void drawModelBrowser();
    void drawModelGrid();   // shared body: Pro "Models" dock + Simple Props tab
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
    // World-space AABB a point entity can be clicked in: the real model
    // bounds when it has one (props are far bigger than the +-16 default),
    // else the FGD size(), else a small box.
    void entityPickBounds(const map::MapEntity& e, glm::vec3& mn, glm::vec3& mx);
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
    void handleSelectionMove(ViewPanel& p);      // click the body + drag to move
    void updateHoverHighlight(ViewPanel& p);     // soft outline under the cursor
    void rebuildHandles();                       // sub-object handles for selection_[0]
    void handleSubObjectInput(ViewPanel& p);
    void drawSubObjectOverlay(ViewPanel& p, float aspect, ImDrawList* dl);
    void handleTextureTool(ViewPanel& p);        // Texture tool: pick faces
    void drawFaceOverlay(ViewPanel& p, float aspect, ImDrawList* dl);
    void drawFaceEditPanel();                    // the Face Edit sheet
    void handleClipTool(ViewPanel& p);           // Clip tool: draw a cut line
    void drawClipOverlay(ViewPanel& p, float aspect, ImDrawList* dl);
    void drawBlockOverlay(ViewPanel& p, float aspect, ImDrawList* dl);
    void applyClip();
    void applyToTexFaces(const std::function<void(map::BrushFace&)>& fn,
                         const char* undoLabel, bool commit);
    void placePiece(const std::string& piece, const glm::vec3& at);
    void finalizeRoad();
    void drawRoadOverlay(ViewPanel& p, float aspect, ImDrawList* dl);
    void drawLeakOverlay(ViewPanel& p, float aspect, ImDrawList* dl);
    bool loadPointfile(const std::string& path);  // vbsp .lin / .pts leak trace
    void frameLeak();
    void drawPlacePreview(ViewPanel& p, float aspect, ImDrawList* dl);
    void placeFgdEntity(const std::string& cls, const glm::vec3& at);
    void tieSelectionToEntity(const std::string& cls);
    void untieSelectionToWorld();  // move selected entity brushes back to world
    glm::vec3 viewPlanePoint(ViewPanel& p, const ImVec2& mouse) const;
    glm::vec3 dropWorldPoint(ViewPanel& p, const ImVec2& mouse);  // smart drop pos
    glm::vec3 snapVec(const glm::vec3& v) const;
    float snapF(float v) const;
    void nudgeSelection(const glm::vec3& worldDelta);
    void deleteSelection();
    void duplicateSelection();
    void copySelection();
    void pasteClipboard();
    void rotateSelection(int axis, float degrees);
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

    // Performance. perfMode_: 0 auto, 1 quality, 2 fast. In fast (or auto on a
    // heavy map) the doc rebuild skips re-baking prop models and re-uses a
    // cached blob of their geometry — placing a wall no longer walks 500 MDLs.
    int perfMode_ = 0;
    struct PropBlob {
        std::vector<bsp::WorldVertex> verts;
        std::vector<uint32_t> indices;          // 0-based within `verts`
        std::vector<bsp::DrawBatch> batches;    // firstIndex 0-based within `indices`
    };
    PropBlob propBlob_;
    size_t propBlobKey_ = 0;
    double lastEditTime_ = 0.0;   // for coalescing rapid edits
    bool heavyDoc() const;        // doc is big enough to auto-throttle
    bool fastEdit() const;        // perfMode_==2 || (auto && heavyDoc)

    std::array<ViewPanel, 4> views_;
    // [0]=3D always on; [1..3]=Top/Front/Side, opened on demand.
    bool viewOpen_[4] = {true, false, false, false};
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
    std::vector<std::pair<std::string, std::vector<int>>> modelCats_;  // group -> idx
    int modelCat_ = 0;                               // 0 = All, 1 = Recent
    std::vector<std::string> recentModels_;
    bool modelListBuilt_ = false;
    render::ModelThumbnailer modelThumbs_;

    // Material browser: every materials/**.vmt, bucketed by theme like the models.
    std::vector<std::string> materialList_;          // name without prefix/suffix
    std::vector<std::pair<std::string, std::vector<int>>> materialCats_;
    int materialCat_ = 1;                            // 0 All · 1 In this map · 2 Recent
    std::vector<std::string> recentMaterials_;
    bool materialListBuilt_ = false;
    void applyBrowserMaterial(const std::string& mat);
    float flySpeed_ = 900.0f;

    std::vector<map::SolidRef> selection_;
    int selectedEntity_ = -1;          // index into doc_.entities(), or -1
    char propFilter_[96] = {0};
    map::History history_;
    int gizmoMode_ = 0;          // 0 move, 1 rotate, 2 scale
    bool gizmoUsing_ = false;
    float gizmoSize_ = 0.17f;    // clip-space size passed to ImGuizmo (Options)
    int gizmoStyle_ = 0;         // 0 = arrows (default), 1 = thick, 2 = fine
    // A gizmo drag is snapshot-based, like the modal G/R/S transform: the
    // selection is captured once at drag start and the cumulative matrix is
    // re-applied to that snapshot every frame. Re-deriving the pivot from the
    // live (already-deformed) selection each frame is what made rotate/scale
    // drift. gizmoView_ pins the drag to one viewport so the other three
    // can't steal it.
    glm::mat4 gizmoMat_{1.0f};       // the matrix ImGuizmo manipulates
    glm::mat4 gizmoStart_{1.0f};     // its value when the drag began
    std::vector<map::Solid> gizmoSnap_;
    std::vector<map::SolidRef> gizmoRefs_;
    int gizmoView_ = -1;             // ViewKind that owns the in-progress drag
    bool selectWholePiece_ = true;  // click a multi-brush piece -> whole vs one part
    bool docMeshDirty_ = false;

    // Bounding-box resize (Select tool, 2D views)
    int resizeHandle_ = -1;      // 0..8: corners 0-3, edges 4-7, -1 none, 8 hover-only
    int resizeHot_ = -1;         // handle under the cursor this frame
    glm::vec3 resizeAnchor_{0};  // world point that stays fixed during the drag
    glm::vec3 resizeStartMin_{0}, resizeStartMax_{0};
    std::vector<map::Solid> resizeSnap_;
    std::vector<map::SolidRef> resizeRefs_;

    // Modal keyboard transform (Blender-style): G / R / S, then X/Y/Z to lock
    // an axis, type a number for an exact amount, Enter commits, Esc cancels.
    struct ModalXform {
        int op = 0;            // 0 none, 1 move, 2 rotate, 3 scale
        int axis = 0;          // 0 free, 1 X, 2 Y, 3 Z
        std::string num;       // typed amount ("" = mouse-driven)
        pb::ViewKind view = pb::ViewKind::Perspective;
        glm::vec2 startMouse{0};
        glm::vec3 pivot{0};
        std::vector<map::Solid> snap;
        std::vector<map::SolidRef> refs;
        glm::vec3 lastDelta{0};   // for the HUD
        float lastVal = 0.0f;
    };
    ModalXform mx_;
    void beginModalXform(int op);
    void updateModalXform();
    void drawModalXformHud(ViewPanel& p, ImDrawList* dl);

    // Snap-to-geometry: while moving, pull a selection bbox corner onto the
    // nearest vertex of another brush. `geoSnapDelta` adjusts a proposed move
    // delta; snapMark_ is the world point it locked to (for the indicator).
    bool snapGeo_ = false;
    glm::vec3 snapMark_{0};
    bool snapMarkOn_ = false;
    bool geoSnapDelta(glm::vec3& d, const glm::vec3& selMn, const glm::vec3& selMx);

    // Body-drag move (Select tool)
    int moveDrag_ = 0;             // 0 none, 1 planar, 2 vertical
    bool movePending_ = false;     // pressed on the body, waiting for a drag
    glm::vec3 moveGrab_{0};        // world point under the cursor at grab
    glm::vec3 moveEntStart_{0};    // point-entity origin at grab
    bool moveIsEnt_ = false;
    map::SolidRef hoverRef_;       // solid under the cursor (Select tool)
    int hoverEnt_ = -1;

    std::vector<map::Solid> clipboard_;
    map::MapEntity clipboardEnt_;
    bool showKeys_ = false;   // F1 shortcut cheat-sheet
    bool showSettings_ = false;

    // Block tool
    bool blockDragging_ = false;
    ViewKind blockView_ = ViewKind::Top;
    glm::vec3 blockA_{0}, blockB_{0};
    float newBrushDepth_ = 128.0f;
    std::string blockMaterial_ = "dev/dev_measuregeneric01b";

    // Texture tool: faces picked for texturing (SolidRef + face index).
    std::vector<std::pair<map::SolidRef, int>> texFaces_;
    char texMaterial_[128] = "dev/dev_measuregeneric01b";
    map::BrushFace texClip_;        // projection lifted by Alt-click (the eyedropper)
    bool texClipSet_ = false;
    float dispRadius_ = 256.0f;     // displacement sculpt brush
    float dispAmount_ = 64.0f;
    void sculptSelectedDisp(float amount);

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

    Mode mode_ = Mode::Standard;
    Tool tool_ = Tool::Select;
    bool layoutDirty_ = true;
    int gridSize_ = 64;
    bool snap_ = true;
    int kitTab_ = 0;
    bool debugPreviewAtCenter_ = false;  // headless: draw the ghost w/o a mouse
    std::string placing_;
    std::string dragPlace_;   // payload of an in-progress menu->viewport drag
    void placeFromPayload(const std::string& payload, const glm::vec3& at);
    float hillRadius_ = 384.0f, hillHeight_ = 320.0f, hillRough_ = 0.32f;
    int hillLayers_ = 7;
    // Parametric shape options (shown while the piece is armed).
    int stairSteps_ = 8;
    float stairRise_ = 16.0f, stairRun_ = 24.0f, stairWidth_ = 128.0f;
    int cylSides_ = 12;
    float cylRadius_ = 96.0f, cylHeight_ = 192.0f;
    int archSegs_ = 8;
    float archRadius_ = 256.0f, archSpan_ = 180.0f, archThick_ = 32.0f,
          archHeight_ = 128.0f;
    float doorOpenDir_ = 0.0f;   // 0=up, 90/180/270 slide directions
    float elevTravel_ = 256.0f;
    float roomHalf_ = 192.0f;    // interior half-extent for Room / spawn rooms
    // Curvy-road spline tool
    std::vector<glm::vec3> roadPts_;
    bool roadActive_ = false;

    // Leak diagnostics: the vbsp pointfile trace, drawn in every viewport
    // until cleared. Auto-loaded when a compile leaks.
    std::vector<glm::vec3> leakLine_;
    bool compileWasRunning_ = false;
    float roadWidth_ = 192.0f, roadThick_ = 16.0f;

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
    std::vector<std::string> packFiles_;    // "<bsp/path>|<abs source>"
    std::vector<std::string> packMissing_;  // referenced but not found (last scan)
    char packAddPath_[512] = {0};
    char compileMapName_[128] = {0};      // rename the output (blank = map name)
    char compileOutDir_[512] = {0};       // extra copy target (blank = tf/maps only)
    size_t compileLogSeen_ = 0;
};

}  // namespace pb
