#include "app/Editor.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <string>

#include <GLFW/glfw3.h>
#include <imgui.h>
#include <imgui_internal.h>
#include <stb_image_write.h>

#include "IconsFontAwesome6.h"
#include "app/Ui.h"
#include "core/Log.h"
#include "model/StudioModel.h"
#include "publish/AssetScan.h"
#include "source/Vtf.h"

namespace pb {
namespace {

void drawHudFrame(ImDrawList* dl, const ImVec2& mn, const ImVec2& mx, float rounding,
                  ImU32 bottomAccent = IM_COL32(207, 115, 54, 255)) {
    // Authentic TF2 In-Game HUD card: warm charcoal, 2px border, 4px amber/team bottom lip
    dl->AddRectFilled(mn, mx, IM_COL32(29, 25, 22, 238), rounding);
    dl->AddRectFilled(ImVec2(mn.x, mx.y - 4.0f), mx, bottomAccent, rounding,
                      ImDrawFlags_RoundCornersBottom);
    dl->AddRect(mn, mx, IM_COL32(87, 76, 65, 240), rounding, 0, 1.6f);
}

void drawMiniIsoPiece(ImDrawList* dl, const ImVec2& c, float r, const char* name, bool hot) {
    const ImU32 topC = hot ? IM_COL32(245, 165, 80, 235) : IM_COL32(158, 146, 130, 200);
    const ImU32 lftC = hot ? IM_COL32(210, 126, 46, 235) : IM_COL32(115, 102, 88, 200);
    const ImU32 rgtC = hot ? IM_COL32(166, 92, 30, 235)  : IM_COL32(86, 76, 65, 200);
    const ImU32 wire = hot ? IM_COL32(255, 228, 180, 250) : IM_COL32(198, 186, 168, 215);
    auto iso = [&](float x, float y, float z) {
        return ImVec2(c.x + (x - y) * 0.866f * r, c.y + (x + y) * 0.5f * r - z * r);
    };
    auto box = [&](float x0, float y0, float z0, float x1, float y1, float z1) {
        const ImVec2 t0 = iso(x0, y0, z1), t1 = iso(x1, y0, z1),
                     t2 = iso(x1, y1, z1), t3 = iso(x0, y1, z1);
        const ImVec2 b1 = iso(x1, y0, z0), b2 = iso(x1, y1, z0), b3 = iso(x0, y1, z0);
        dl->AddQuadFilled(t0, t1, t2, t3, topC);
        dl->AddQuadFilled(t3, t2, b2, b3, lftC);
        dl->AddQuadFilled(t2, t1, b1, b2, rgtC);
        dl->AddQuad(t0, t1, t2, t3, wire, 1.1f);
        dl->AddQuad(t3, t2, b2, b3, wire, 1.1f);
        dl->AddQuad(t2, t1, b1, b2, wire, 1.1f);
    };
    const std::string n = name ? name : "";
    if (n == "Floor") {
        box(-0.85f, -0.85f, -0.18f, 0.85f, 0.85f, 0.18f);
    } else if (n == "Wall") {
        box(-0.85f, -0.20f, -0.68f, 0.85f, 0.20f, 0.68f);
    } else if (n == "Doorway" || n == "Window") {
        box(-0.85f, -0.20f, -0.68f, -0.28f, 0.20f, 0.68f);
        box(0.28f, -0.20f, -0.68f, 0.85f, 0.20f, 0.68f);
        box(-0.28f, -0.20f, 0.20f, 0.28f, 0.20f, 0.68f);
    } else if (n == "Stairs") {
        for (int s = 0; s < 3; ++s) {
            const float y0 = -0.75f + s * 0.50f;
            box(-0.65f, y0, -0.55f, 0.65f, y0 + 0.50f, -0.45f + (s + 1) * 0.35f);
        }
    } else if (n == "Ramp") {
        const ImVec2 a = iso(-0.8f, -0.6f, -0.5f), b = iso(0.8f, -0.6f, 0.5f),
                     c2 = iso(0.8f, 0.6f, 0.5f), d = iso(-0.8f, 0.6f, -0.5f),
                     e = iso(0.8f, 0.6f, -0.5f), f = iso(0.8f, -0.6f, -0.5f);
        dl->AddQuadFilled(a, b, c2, d, topC);
        dl->AddTriangleFilled(d, c2, e, lftC);
        dl->AddQuadFilled(b, f, e, c2, rgtC);
        dl->AddQuad(a, b, c2, d, wire, 1.1f);
    } else {
        box(-0.68f, -0.68f, -0.55f, 0.68f, 0.68f, 0.55f);
    }
}

const char* tf2ModelForPiece(const std::string& piece) {
    if (piece == "Health pack" || piece == "Health / ammo")
        return "models/items/medkit_medium.mdl";
    if (piece == "Ammo pack")     return "models/items/ammopack_medium.mdl";
    if (piece == "Resupply")      return "models/props_gameplay/resupply_locker.mdl";
    if (piece == "Capture point") return "models/props_gameplay/cap_point_base.mdl";
    if (piece == "CTF setup")     return "models/flag/briefcase.mdl";
    if (piece == "Payload track") return "models/props_trainyard/bomb_cart.mdl";
    return nullptr;
}

}  // namespace

std::string Editor::detectTf2GameMode() const {
    if (!hasDoc()) return bsp_.loaded() ? "BSP Preview" : "New Map";
    bool hasFlag = false, hasPayload = false, hasKoth = false,
         hasArena = false, hasCp = false;
    for (const auto& e : doc_.entities()) {
        if (e.classname == "item_teamflag" || e.classname == "func_capturezone")
            hasFlag = true;
        else if (e.classname == "team_train_watcher" || e.classname == "func_tracktrain")
            hasPayload = true;
        else if (e.classname == "tf_logic_koth")
            hasKoth = true;
        else if (e.classname == "tf_logic_arena")
            hasArena = true;
        else if (e.classname == "team_control_point")
            hasCp = true;
    }
    if (hasPayload) return "Payload";
    if (hasFlag) return "CTF";
    if (hasKoth) return "KOTH";
    if (hasArena) return "Arena";
    if (hasCp) return "Control Point";
    return "Sandbox";
}

void Editor::createPremadeEnvironment(int envIdx) {
    struct EnvDef {
        const char* mapName;
        const char* floorMat;
        const char* wallMat;
        const char* roofMat;
        const char* skyName;
        int themeIdx;
    };
    static const EnvDef kEnvs[] = {
        {"badlands_arena",  "concrete/concretefloor002", "brick/brickwall003a",       "metal/metalroof006a", "sky_badlands_01",    1},
        {"winter_outpost",  "nature/snow_full001",       "wood/wood_wall002",         "metal/metalroof005a", "sky_alpinestorm_01", 0},
        {"sawmill_yard",    "wood/wood_floor002",        "wood/wood_wall004",         "metal/metalroof006a", "sky_alpinestorm_01", 0},
        {"spytech_lab",     "tile/tilefloor001a",        "concrete/computerwall003",  "metal/metalwall001a", "sky_upward",         2},
        {"orange_greybox",  "dev/dev_measuregeneric01b", "dev/dev_measurewall01a",    "dev/dev_measuregeneric01", "sky_tf2_04",  -1},
    };
    envIdx = std::clamp(envIdx, 0, 4);
    const auto& env = kEnvs[envIdx];

    bsp_ = BspFile();
    sourceFs_.clearBspPak();
    doc_.newBlank(env.mapName);
    doc_.worldExtra().set("skyname", env.skyName);
    settings_.skyBiome = envIdx;
    history_.reset(doc_);
    clearSelection();

    auto addBox = [&](glm::vec3 mn, glm::vec3 mx, const char* mat) {
        map::Solid s = map::Solid::makeBox(mn, mx, mat);
        s.id = doc_.nextId();
        doc_.worldSolids().push_back(std::move(s));
    };

    // Playable sunlit TF2 courtyard with perimeter walls, mid capture platform, and flanking cover
    addBox({-1024, -768, -32}, {1024, 768, 0}, env.floorMat);
    addBox({-1024, -768, 0},   {1024, -736, 224}, env.wallMat);   // South boundary
    addBox({-1024, 736, 0},    {1024, 768, 224},  env.wallMat);   // North boundary
    addBox({-1024, -736, 0},   {-992, 736, 224},  env.wallMat);   // West RED backwall
    addBox({992, -736, 0},     {1024, 736, 224},  env.wallMat);   // East BLU backwall

    // Symmetric TF2 mid cover walls + elevated center point plinth
    addBox({-320, -256, 0}, {-288, 64, 144}, env.wallMat);
    addBox({288, -64, 0},   {320, 256, 144}, env.wallMat);
    addBox({-160, -160, 0}, {160, 160, 24},  env.roofMat);

    // Working gameplay pieces so F5 Walk & PLAY IN TF2 work immediately!
    const bool prevSym = symmetryX_;
    symmetryX_ = false;
    placePiece("RED spawn", glm::vec3(-768, 0, 0), false);
    placePiece("BLU spawn", glm::vec3(768, 0, 0), false);
    placePiece("Capture point", glm::vec3(0, 0, 24), false);
    placePiece("Health pack", glm::vec3(0, -352, 0), false);
    placePiece("Ammo pack", glm::vec3(0, 352, 0), false);
    placePiece("Sun / sky", glm::vec3(0, 0, 320), false);
    placePiece("Skybox seal", glm::vec3(0, 0, 0), false);
    symmetryX_ = prevSym;

    afterEdit("New environment");
    clearSelection();

    showWelcome_ = false;
    showEnvPicker_ = false;
    frameAllViews();
    views_[0].camera.pos = glm::vec3(-720.0f, -820.0f, 460.0f);
    views_[0].camera.yawDeg = 48.0f;
    views_[0].camera.pitchDeg = -25.0f;
    status_ = std::string("Created sunlit TF2 environment: ") + env.mapName + " — press F5 to walk around!";
}

void Editor::resizeSelectedBrushHeight(float deltaZ) {
    if (!hasDoc() || selection_.empty()) return;
    bool changed = false;
    for (const auto& r : selection_) {
        map::Solid* s = doc_.resolve(r);
        if (!s) continue;
        for (int fi = 0; fi < static_cast<int>(s->faces.size()); ++fi) {
            if (s->faces[fi].planeN.z > 0.7f) {
                if (pushPullFace(r, fi, deltaZ)) changed = true;
                break;
            }
        }
    }
    if (changed) {
        afterEdit(deltaZ > 0 ? "Raise height" : "Lower height");
        char buf[64];
        std::snprintf(buf, sizeof(buf), "Height %+.0fu", deltaZ);
        status_ = buf;
    }
}

void Editor::resizeSelectedBrushFootprint(float deltaXY) {
    if (!hasDoc() || selection_.empty()) return;
    bool changed = false;
    for (const auto& r : selection_) {
        map::Solid* s = doc_.resolve(r);
        if (!s) continue;
        for (int fi = 0; fi < static_cast<int>(s->faces.size()); ++fi) {
            if (std::fabs(s->faces[fi].planeN.z) < 0.3f) {
                if (pushPullFace(r, fi, deltaXY)) changed = true;
            }
        }
    }
    if (changed) {
        afterEdit(deltaXY > 0 ? "Grow footprint" : "Shrink footprint");
        char buf[64];
        std::snprintf(buf, sizeof(buf), "Footprint %+.0fu per side", deltaXY);
        status_ = buf;
    }
}

void Editor::drawWorkshopDockLayout(unsigned int dockId, const ImVec2& size) {
    // Mockup 3: 100% full-bleed 3D canvas — ZERO docked sidebars stealing screen!
    ImGui::DockBuilderRemoveNode(dockId);
    ImGui::DockBuilderAddNode(dockId, ImGuiDockNodeFlags_DockSpace);
    ImGui::DockBuilderSetNodeSize(dockId, size.x > 0 ? size : ImVec2(1600, 900));
    ImGui::DockBuilderDockWindow("Top (x/y)", dockId);
    ImGui::DockBuilderDockWindow("Front (x/z)", dockId);
    ImGui::DockBuilderDockWindow("Side (y/z)", dockId);
    ImGui::DockBuilderDockWindow("3D View", dockId);
    ImGui::DockBuilderFinish(dockId);
}

void Editor::drawWorkshopTopBar() {
    // Floating Top-Center Valve TF2 In-Game HUD Pill Bar
    using namespace pb::ui;
    if (walkPlaytest_) return;  // Clean full-screen view during F5 TF2 Walk Playtest!
    ImGuiViewport* vp = ImGui::GetMainViewport();
    const float row = ImGui::GetFrameHeight() + dp(2.0f);
    const float pillH = std::round(row + dp(18.0f));
    const float pillW = std::min(vp->WorkSize.x - dp(20.0f), dp(1260.0f));

    ImGui::SetNextWindowPos(
        ImVec2(vp->WorkPos.x + (vp->WorkSize.x - pillW) * 0.5f, vp->WorkPos.y + dp(10.0f)));
    ImGui::SetNextWindowSize(ImVec2(pillW, pillH));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(dp(10.0f), dp(6.0f)));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0f);
    ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(0, 0, 0, 0));
    ImGui::Begin("##tf2_top_hud", nullptr,
                 ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                     ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoScrollbar |
                     ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoDocking);
    ImGui::PopStyleColor();
    ImGui::PopStyleVar(2);

    ImDrawList* dl = ImGui::GetWindowDrawList();
    const ImVec2 wPos = ImGui::GetWindowPos();
    const ImVec2 wSz = ImGui::GetWindowSize();
    drawHudFrame(dl, wPos, ImVec2(wPos.x + wSz.x, wPos.y + wSz.y), dp(8.0f));

    const float cy = (pillH - row - dp(3.0f)) * 0.5f;
    ImGui::SetCursorPos(ImVec2(dp(10.0f), cy));

    // Brand + Menu button in authentic TF2 Build font
    ImGui::PushStyleColor(ImGuiCol_Button, col::acc);
    ImGui::PushStyleColor(ImGuiCol_Text, col::bg0);
    if (fontTf2) ImGui::PushFont(fontTf2);
    if (ImGui::Button(ICON_FA_WRENCH "  TF2", ImVec2(0, row)))
        ImGui::OpenPopup("##hud_menu");
    if (fontTf2) ImGui::PopFont();
    ImGui::PopStyleColor(2);

    if (ImGui::BeginPopup("##hud_menu")) {
        if (ImGui::MenuItem(ICON_FA_MOUNTAIN_SUN "  New Premade Environment…"))
            showEnvPicker_ = true;
        if (ImGui::MenuItem(ICON_FA_FOLDER_OPEN "  Open Map (.bsp / .vmf)", "Ctrl+O"))
            promptOpenMap();
        if (ImGui::MenuItem(ICON_FA_FLOPPY_DISK "  Save Map (.vmf)", "Ctrl+S", false, hasDoc()))
            saveMap(false);
        if (ImGui::MenuItem(ICON_FA_FLOPPY_DISK "  Save As…", "Ctrl+Shift+S", false, hasDoc()))
            saveMap(true);
        if (ImGui::MenuItem(ICON_FA_CUBE "  Import 3D Model (.obj)…"))
            openModelImport();
        ImGui::Separator();
        ImGui::MenuItem("RED <-> BLU X-Symmetry Mirror", nullptr, &symmetryX_);
        ImGui::MenuItem("TF2 83u Scale Ghost", nullptr, &showScaleGhost_);
        ImGui::MenuItem("Auto-Carve Doorways & Windows", nullptr, &autoCarveDoors_);
        ImGui::Separator();
        if (ImGui::MenuItem(ICON_FA_PEN_RULER "  Switch to Classic Pro Editor")) {
            useWorkshopUi_ = false;
            mode_ = Mode::Full;
            layoutDirty_ = true;
        }
        if (ImGui::MenuItem(ICON_FA_GEAR "  Options…")) showSettings_ = true;
        if (ImGui::MenuItem(ICON_FA_KEYBOARD "  Keyboard Shortcuts", "F1")) showKeys_ = true;
        ImGui::EndPopup();
    }

    ImGui::SameLine(0, dp(6.0f));
    if (toolButton(ICON_FA_ROTATE_LEFT, false, "Undo  (Ctrl+Z)")) undo();
    ImGui::SameLine(0, dp(3.0f));
    if (toolButton(ICON_FA_ROTATE_RIGHT, false, "Redo  (Ctrl+Y)")) redo();
    ImGui::SameLine(0, dp(6.0f));
    if (toolButton(symmetryX_ ? ICON_FA_ARROWS_LEFT_RIGHT " SYM" : ICON_FA_ARROWS_LEFT_RIGHT,
                   symmetryX_, "Toggle RED <-> BLU Mirror Symmetry across X=0"))
        symmetryX_ = !symmetryX_;

    // Center: 4 Clean Stages in bold Valve TF2 typography
    static const char* const kStages[4] = {
        "1. BUILD", "2. GAMEPLAY", "3. STYLE", "4. PLAYTEST"
    };
    const float stBtnW = dp(122.0f);
    const float stGap = dp(4.0f);
    const float stTotal = stBtnW * 4.0f + stGap * 3.0f;
    ImGui::SetCursorPos(ImVec2(std::max(ImGui::GetCursorPosX() + dp(10.0f),
                                        (pillW - stTotal) * 0.5f - dp(28.0f)),
                               cy));
    for (int i = 0; i < 4; ++i) {
        if (i) ImGui::SameLine(0, stGap);
        ImGui::PushID(6100 + i);
        const bool on = (workshopStage_ == i);
        const bool done = (i < workshopStage_);
        ImGui::PushStyleColor(ImGuiCol_Button,
                              on ? col::acc : (done ? ImVec4(0.16f, 0.23f, 0.17f, 1.0f) : col::bg2));
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered, on ? col::acc : col::bg3);
        ImGui::PushStyleColor(ImGuiCol_Text,
                              on ? col::bg0 : (done ? col::good : col::tx));
        if (fontTf2) ImGui::PushFont(fontTf2);
        if (ImGui::Button(kStages[i], ImVec2(stBtnW, row))) {
            workshopStage_ = i;
            if (i != 2) workshopDetailTab_ = 0;
            if (i == 3) runMapCheck();
        }
        if (fontTf2) ImGui::PopFont();
        ImGui::PopStyleColor(3);
        ImGui::PopID();
    }

    // Right end: Environments, 83u Ghost, 3D/2D, F5 WALK, PLAY IN TF2
    const float rightW = dp(356.0f);
    ImGui::SetCursorPos(ImVec2(pillW - rightW - dp(10.0f), cy));
    if (toolButton(ICON_FA_MOUNTAIN_SUN, showEnvPicker_, "Premade TF2 Environments (Desert, Winter, Sawmill, Spytech)"))
        showEnvPicker_ = !showEnvPicker_;
    ImGui::SameLine(0, dp(4.0f));
    if (toolButton(ICON_FA_PERSON, showScaleGhost_, "Toggle TF2 83u Heavy Scale Ghost"))
        showScaleGhost_ = !showScaleGhost_;
    ImGui::SameLine(0, dp(4.0f));
    const bool any2d = viewOpen_[1] || viewOpen_[2] || viewOpen_[3];
    if (toolButton(any2d ? "2D" : "3D/2D", any2d, "Flip 3D / 2D Blueprint  (Space)"))
        swapPipView();
    ImGui::SameLine(0, dp(6.0f));

    // Instant F5 First-Person TF2 Walk/Jump Playtest button!
    ImGui::PushStyleColor(ImGuiCol_Button, ImVec4(0.18f, 0.42f, 0.56f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.24f, 0.52f, 0.68f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_Text, col::tx);
    if (fontTf2) ImGui::PushFont(fontTf2);
    if (ImGui::Button(ICON_FA_PERSON_WALKING " F5 WALK", ImVec2(dp(112.0f), row)))
        toggleWalkPlaytest();
    if (fontTf2) ImGui::PopFont();
    ImGui::PopStyleColor(3);
    if (ImGui::IsItemHovered())
        ImGui::SetTooltip("Drop into instant 1st-person TF2 walk & jump test (no compile!)");

    ImGui::SameLine(0, dp(6.0f));
    ImGui::PushStyleColor(ImGuiCol_Button, col::acc);
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, ImVec4(0.95f, 0.62f, 0.28f, 1.0f));
    ImGui::PushStyleColor(ImGuiCol_Text, col::bg0);
    if (fontTf2) ImGui::PushFont(fontTf2);
    if (ImGui::Button(ICON_FA_PLAY "  PLAY", ImVec2(dp(90.0f), row))) {
        workshopStage_ = 3;
        if (!compiler_.running() && hasDoc()) startCompile();
    }
    if (fontTf2) ImGui::PopFont();
    ImGui::PopStyleColor(3);

    ImGui::End();

    // ---- Premade TF2 Environment Picker Modal (Desert / Winter / Sawmill / Spytech / Dev) ----
    if (showEnvPicker_) {
        const float mw = dp(520.0f), mh = dp(310.0f);
        ImGui::SetNextWindowPos(ImVec2(vp->WorkPos.x + (vp->WorkSize.x - mw) * 0.5f,
                                       vp->WorkPos.y + dp(78.0f)));
        ImGui::SetNextWindowSize(ImVec2(mw, mh));
        ImGui::PushStyleColor(ImGuiCol_WindowBg, col::bg1);
        ImGui::PushStyleColor(ImGuiCol_Border, col::acc);
        ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 2.0f);
        if (ImGui::Begin(ICON_FA_MOUNTAIN_SUN "  Choose Premade TF2 Environment", &showEnvPicker_,
                         ImGuiWindowFlags_NoResize | ImGuiWindowFlags_NoMove |
                             ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_NoDocking)) {
            ImGui::TextDisabled("Starts pre-sealed with skybox, TF2 lighting, and base ground (0 leaks).");
            ImGui::Dummy(ImVec2(0, dp(6.0f)));
            struct EnvCard { const char* ic; const char* name; const char* desc; ImU32 c1; ImU32 c2; };
            static const EnvCard kCards[5] = {
                {ICON_FA_SUN,         "Badlands Desert",  "Sandstone ground, red brick & warm desert sun", IM_COL32(185,118,74,255), IM_COL32(230,190,138,255)},
                {ICON_FA_SNOWFLAKE,   "Alpine Winter",    "Crisp snow ground, timber & cool winter sky",   IM_COL32(210,225,240,255), IM_COL32(95,125,155,255)},
                {ICON_FA_TREE,        "Sawmill Forest",   "Weathered wood, mossy gravel & storm sky",      IM_COL32(115,88,62,255),  IM_COL32(85,110,128,255)},
                {ICON_FA_USER_SECRET, "Spytech Facility", "Clean concrete tile, steel & indoor lighting",  IM_COL32(72,95,125,255),  IM_COL32(185,195,205,255)},
                {ICON_FA_BORDER_ALL,  "Orange Dev Studio","Classic TF2 dev measure grid for greyboxing",   IM_COL32(220,125,40,255), IM_COL32(95,102,110,255)},
            };
            ImDrawList* mdl = ImGui::GetWindowDrawList();
            for (int i = 0; i < 5; ++i) {
                ImGui::PushID(6800 + i);
                const ImVec2 p0 = ImGui::GetCursorScreenPos();
                const float cw = ImGui::GetContentRegionAvail().x;
                const float ch = dp(40.0f);
                if (ImGui::Selectable("##envc", false, 0, ImVec2(cw, ch)))
                    createPremadeEnvironment(i);
                const bool hov = ImGui::IsItemHovered();
                mdl->AddRectFilled(p0, ImVec2(p0.x + cw, p0.y + ch),
                                   hov ? u32(col::bg3) : u32(col::bg2), dp(5.0f));
                mdl->AddRectFilled(p0, ImVec2(p0.x + dp(10.0f), p0.y + ch * 0.5f), kCards[i].c1, dp(5.0f));
                mdl->AddRectFilled(ImVec2(p0.x, p0.y + ch * 0.5f), ImVec2(p0.x + dp(10.0f), p0.y + ch), kCards[i].c2, dp(5.0f));
                mdl->AddRect(p0, ImVec2(p0.x + cw, p0.y + ch), hov ? u32(col::acc) : u32(col::bd), dp(5.0f));
                mdl->AddText(ImVec2(p0.x + dp(18.0f), p0.y + dp(11.0f)), u32(col::acc), kCards[i].ic);
                mdl->AddText(fontUiMed ? fontUiMed : nullptr, 0.0f,
                             ImVec2(p0.x + dp(38.0f), p0.y + dp(4.0f)), u32(col::tx), kCards[i].name);
                mdl->AddText(ImVec2(p0.x + dp(38.0f), p0.y + dp(21.0f)), u32(col::faint), kCards[i].desc);
                ImGui::PopID();
            }
        }
        ImGui::End();
        ImGui::PopStyleVar();
        ImGui::PopStyleColor(2);
    }
}

void Editor::drawWorkshopSidebar() {
    // Mockup 3: Slim Right-Edge Authentic TF2 Icon Stamp Rail (plus compact stage drawers for Style/Playtest)
    using namespace pb::ui;
    if (walkPlaytest_) return;
    ImGuiViewport* vp = ImGui::GetMainViewport();

    auto getTf2Thumb = [&](const char* mdlPath) -> GLuint {
        if (!mdlPath || !sourceFs_.ready()) return 0;
        if (modelThumbs_.has(mdlPath)) {
            static const model::StudioModel kEmpty;
            return modelThumbs_.get(mdlPath, kEmpty, materials_);
        }
        return modelThumbs_.get(mdlPath, model::loadStudioModel(sourceFs_, mdlPath), materials_);
    };

    if (workshopStage_ == 0 || workshopStage_ == 1) {
        // ---- Slim Right-Edge TF2 Icon Stamp Rail ----
        const float slotW = dp(64.0f);
        const float slotH = dp(62.0f);
        const float pad = dp(8.0f);
        const float gap = dp(5.0f);

        struct RailSlot {
            const char* piece;
            const char* shortLbl;
            const char* tip;
            const char* mdlPath;   // real TF2 .mdl icon when non-null!
            int teamAccent;        // 0 none, 1 RED, 2 BLU
            bool isTool;
            Tool toolVal;
        };
        static const RailSlot kBuildSlots[] = {
            {"Floor",       "Floor",  "Place / Paint Floor",       nullptr, 0, false, Tool::Select},
            {"Wall",        "Wall",   "Place Cover Wall",          nullptr, 0, false, Tool::Select},
            {"Room",        "Room",   "Complete 4-Wall Room",      nullptr, 0, false, Tool::Select},
            {"Doorway",     "Door",   "Auto-Cut Wall Doorway",     nullptr, 0, false, Tool::Select},
            {"Ramp",        "Ramp",   "Walkable TF2 Ramp",         nullptr, 0, false, Tool::Select},
            {"Stairs",      "Stairs", "Parametric TF2 Stairs",     nullptr, 0, false, Tool::Select},
            {"Skybox seal", "Seal",   "1-Click Skybox Leak Seal",  nullptr, 0, false, Tool::Select},
            {"",            "Pull",   "Push/Pull Face Tool (P)",   nullptr, 0, true,  Tool::PushPull},
        };
        static const RailSlot kGameSlots[] = {
            {"RED spawn",     "RED",    "RED Spawn Room + Locker", nullptr,                                      1, false, Tool::Select},
            {"BLU spawn",     "BLU",    "BLU Spawn Room + Locker", nullptr,                                      2, false, Tool::Select},
            {"Health pack",   "Health", "TF2 Medium Health Kit",   "models/items/medkit_medium.mdl",             0, false, Tool::Select},
            {"Ammo pack",     "Ammo",   "TF2 Medium Ammo Box",     "models/items/ammopack_medium.mdl",           0, false, Tool::Select},
            {"Resupply",      "Locker", "TF2 Resupply Locker",     "models/props_gameplay/resupply_locker.mdl",  0, false, Tool::Select},
            {"Capture point", "Point",  "TF2 Control Point",       "models/props_gameplay/cap_point_base.mdl",   0, false, Tool::Select},
            {"CTF setup",     "Intel",  "RED & BLU Briefcases",    "models/flag/briefcase.mdl",                  0, false, Tool::Select},
            {"Payload track", "Cart",   "TF2 Payload Bomb Cart",   "models/props_trainyard/bomb_cart.mdl",       0, false, Tool::Select},
            {"",              "Wire",   "3D Entity Wiring (L)",    nullptr,                                      0, true,  Tool::Wire},
        };

        const RailSlot* slots = (workshopStage_ == 0) ? kBuildSlots : kGameSlots;
        const int count = (workshopStage_ == 0) ? 8 : 9;
        const float railW = slotW + pad * 2.0f;
        const float railH = count * slotH + (count - 1) * gap + pad * 2.0f + dp(6.0f);

        ImGui::SetNextWindowPos(
            ImVec2(vp->WorkPos.x + vp->WorkSize.x - railW - dp(12.0f),
                   vp->WorkPos.y + std::max(dp(64.0f), (vp->WorkSize.y - railH) * 0.5f)));
        ImGui::SetNextWindowSize(ImVec2(railW, railH));
        ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0, 0));
        ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0f);
        ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(0, 0, 0, 0));
        ImGui::Begin("##tf2_right_rail", nullptr,
                     ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                         ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoScrollbar |
                         ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoDocking);
        ImGui::PopStyleColor();
        ImGui::PopStyleVar(2);

        ImDrawList* dl = ImGui::GetWindowDrawList();
        const ImVec2 wPos = ImGui::GetWindowPos();
        const ImVec2 wSz = ImGui::GetWindowSize();
        drawHudFrame(dl, wPos, ImVec2(wPos.x + wSz.x, wPos.y + wSz.y), dp(10.0f));

        for (int i = 0; i < count; ++i) {
            const auto& sl = slots[i];
            const ImVec2 p0(wPos.x + pad, wPos.y + pad + i * (slotH + gap));
            ImGui::SetCursorScreenPos(p0);
            ImGui::PushID(6200 + i);
            const bool active = sl.isTool ? (tool_ == sl.toolVal) : (placing_ == sl.piece);
            ImGui::InvisibleButton("##rslot", ImVec2(slotW, slotH));
            const bool hov = ImGui::IsItemHovered();
            if (ImGui::IsItemClicked()) {
                if (sl.isTool) {
                    tool_ = (tool_ == sl.toolVal) ? Tool::Select : sl.toolVal;
                    placing_.clear();
                    status_ = sl.tip;
                } else if (std::string(sl.piece) == "Skybox seal") {
                    quickSealMap();
                } else {
                    placing_ = sl.piece;
                    status_ = std::string("Armed ") + sl.tip + " — click in 3D to place";
                }
            }
            if (!sl.isTool && ImGui::IsItemActive() &&
                ImGui::IsMouseDragPastThreshold(ImGuiMouseButton_Left, 5.0f)) {
                dragPlace_ = std::string("@kit:") + sl.piece;
                ImGui::SetMouseCursor(ImGuiMouseCursor_Hand);
            }
            if (hov) ImGui::SetTooltip("%s", sl.tip);

            const ImU32 bg = active ? IM_COL32(71, 54, 36, 250)
                           : hov    ? IM_COL32(59, 51, 44, 245)
                                    : IM_COL32(43, 38, 33, 240);
            const ImU32 bd = active           ? u32(col::acc)
                           : sl.teamAccent==1 ? u32(col::teamRed)
                           : sl.teamAccent==2 ? u32(col::teamBlu)
                                              : IM_COL32(82, 72, 62, 235);
            dl->AddRectFilled(p0, ImVec2(p0.x + slotW, p0.y + slotH), bg, dp(8.0f));
            dl->AddRect(p0, ImVec2(p0.x + slotW, p0.y + slotH), bd, dp(8.0f), 0,
                        active ? 2.2f : 1.3f);

            const GLuint tex = sl.mdlPath ? getTf2Thumb(sl.mdlPath) : 0;
            if (tex) {
                const float imgSz = dp(40.0f);
                const ImVec2 i0(p0.x + (slotW - imgSz) * 0.5f, p0.y + dp(3.0f));
                dl->AddImageRounded(static_cast<ImTextureID>((intptr_t)tex), i0,
                                    ImVec2(i0.x + imgSz, i0.y + imgSz), ImVec2(0, 1), ImVec2(1, 0),
                                    IM_COL32_WHITE, dp(5.0f));
            } else if (sl.teamAccent == 1 || sl.teamAccent == 2) {
                const ImU32 crestBg = (sl.teamAccent == 1) ? IM_COL32(184, 56, 59, 255)
                                                           : IM_COL32(88, 133, 162, 255);
                const ImVec2 c0(p0.x + (slotW - dp(34.0f)) * 0.5f, p0.y + dp(6.0f));
                const ImVec2 c1(c0.x + dp(34.0f), c0.y + dp(34.0f));
                dl->AddRectFilled(c0, c1, crestBg, dp(7.0f));
                dl->AddRect(c0, c1, IM_COL32(255, 240, 220, 140), dp(7.0f), 0, 1.2f);
                const char* ic = ICON_FA_PERSON;
                const ImVec2 isz = ImGui::CalcTextSize(ic);
                dl->AddText(ImVec2((c0.x + c1.x - isz.x) * 0.5f, (c0.y + c1.y - isz.y) * 0.5f),
                            IM_COL32(255, 248, 240, 255), ic);
            } else if (sl.isTool) {
                const char* ic = (sl.toolVal == Tool::Wire) ? ICON_FA_DIAGRAM_PROJECT
                                                            : ICON_FA_UP_DOWN_LEFT_RIGHT;
                const ImVec2 isz = ImGui::CalcTextSize(ic);
                dl->AddText(ImVec2(p0.x + (slotW - isz.x) * 0.5f, p0.y + dp(14.0f)),
                            active ? u32(col::acc) : u32(col::cadCyan), ic);
            } else {
                drawMiniIsoPiece(dl, ImVec2(p0.x + slotW * 0.5f, p0.y + dp(23.0f)),
                                 dp(13.0f), sl.piece, active || hov);
            }

            const ImVec2 lsz = ImGui::CalcTextSize(sl.shortLbl);
            dl->AddText(ImVec2(p0.x + (slotW - lsz.x) * 0.5f, p0.y + slotH - dp(16.0f)),
                        active ? u32(col::acc) : u32(col::tx), sl.shortLbl);
            ImGui::PopID();
        }
        ImGui::End();
    } else if (workshopStage_ == 2) {
        // ---- Stage 3 (Style): Floating Right TF2 Theme & Asset Card ----
        const float cw = dp(300.0f);
        const float ch = workshopDetailTab_ == 0 ? dp(360.0f) : std::min(vp->WorkSize.y - dp(120.0f), dp(580.0f));
        ImGui::SetNextWindowPos(
            ImVec2(vp->WorkPos.x + vp->WorkSize.x - cw - dp(14.0f), vp->WorkPos.y + dp(68.0f)));
        ImGui::SetNextWindowSize(ImVec2(cw, ch));
        ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(0.114f, 0.098f, 0.086f, 0.94f));
        ImGui::PushStyleColor(ImGuiCol_Border, col::bd2);
        ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 1.8f);
        ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, dp(8.0f));
        ImGui::Begin("##tf2_style_hud", nullptr,
                     ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                         ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings |
                         ImGuiWindowFlags_NoDocking);
        ImGui::PopStyleVar(2);
        ImGui::PopStyleColor(2);

        sectionLabel("3. TF2 THEME & ASSETS");
        const char* const tabs[] = {"Themes", "Materials", "Props", "Terrain"};
        int r = segmented("hudstabs", tabs, 4, workshopDetailTab_, dp(25.0f));
        if (r >= 0) workshopDetailTab_ = r;
        ImGui::Dummy(ImVec2(0, dp(4.0f)));

        if (workshopDetailTab_ == 0) {
            drawThemeStylerCards();
            if (ImGui::Button(ICON_FA_MOUNTAIN_SUN "  New Premade Environment…", ImVec2(-1, dp(28.0f))))
                showEnvPicker_ = true;
            if (ImGui::Button(ICON_FA_CUBE "  Import 3D Model (.obj)…", ImVec2(-1, dp(28.0f))))
                openModelImport();
        } else if (workshopDetailTab_ == 1) {
            drawMaterialGrid();
        } else if (workshopDetailTab_ == 2) {
            drawModelGrid();
        } else {
            tool_ = Tool::Texture;
            drawFaceEditPanel();
        }
        ImGui::End();
    } else {
        // ---- Stage 4 (Playtest): Floating Right TF2 Playtest & Compile HUD ----
        const float cw = dp(310.0f), ch = dp(405.0f);
        ImGui::SetNextWindowPos(
            ImVec2(vp->WorkPos.x + vp->WorkSize.x - cw - dp(14.0f), vp->WorkPos.y + dp(68.0f)));
        ImGui::SetNextWindowSize(ImVec2(cw, ch));
        ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(0.114f, 0.098f, 0.086f, 0.95f));
        ImGui::PushStyleColor(ImGuiCol_Border, col::acc);
        ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 2.0f);
        ImGui::PushStyleVar(ImGuiStyleVar_WindowRounding, dp(8.0f));
        ImGui::Begin("##tf2_play_hud", nullptr,
                     ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                         ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoSavedSettings |
                         ImGuiWindowFlags_NoDocking);
        ImGui::PopStyleVar(2);
        ImGui::PopStyleColor(2);

        sectionLabel("4. PLAYTEST & SHIP TO TF2");
        int redSpawns = 0, bluSpawns = 0, objectives = 0, lights = 0;
        for (const auto& e : doc_.entities()) {
            if (e.classname == "info_player_teamspawn" || e.classname == "info_player_start") {
                const std::string t = e.kv.get("TeamNum");
                if (t == "2") ++redSpawns;
                else if (t == "3") ++bluSpawns;
                else { ++redSpawns; ++bluSpawns; }
            }
            if (e.classname == "team_control_point" || e.classname == "item_teamflag" ||
                e.classname == "trigger_capture_area" || e.classname == "func_capturezone")
                ++objectives;
            if (e.classname.rfind("light", 0) == 0) ++lights;
        }
        const bool sealed = isMapSealed();

        auto rowCheck = [&](bool ok, const char* lbl, const char* fix, std::function<void()> fn) {
            ImGui::PushStyleColor(ImGuiCol_Text, ok ? col::good : col::warn);
            ImGui::TextUnformatted(ok ? ICON_FA_CIRCLE_CHECK : ICON_FA_TRIANGLE_EXCLAMATION);
            ImGui::PopStyleColor();
            ImGui::SameLine(0, dp(6.0f));
            ImGui::TextUnformatted(lbl);
            if (!ok && fix && fn) {
                ImGui::SameLine();
                if (ImGui::SmallButton(fix)) fn();
            }
        };
        rowCheck(redSpawns > 0, "RED Spawns", "Add##r", [&] { placing_ = "RED spawn"; workshopStage_ = 1; });
        rowCheck(bluSpawns > 0, "BLU Spawns", "Add##b", [&] { placing_ = "BLU spawn"; workshopStage_ = 1; });
        rowCheck(objectives > 0, "Objective (CP/Intel/Cart)", "Add##o", [&] { placing_ = "Capture point"; workshopStage_ = 1; });
        rowCheck(sealed, "Skybox Sealed (0 Leaks)", "1-Click Seal", [&] { quickSealMap(); });
        rowCheck(lights > 0, "TF2 Lighting", "Add Sun", [&] { placePiece("Sun / sky", glm::vec3(0, 0, 160)); });

        ImGui::Dummy(ImVec2(0, dp(6.0f)));
        const char* const profs[] = {"Fast (4s)", "Final HDR"};
        int pr = segmented("hudprof", profs, 2, compileProfile_, dp(26.0f));
        if (pr >= 0) compileProfile_ = pr;
        ImGui::Checkbox("Launch TF2 on finish", &compileLaunch_);
        ImGui::Checkbox("Auto-pack custom assets", &compilePack_);

        if (ImGui::Button(ICON_FA_MAGNIFYING_GLASS "  Scan Custom Assets", ImVec2(-1, 0)) && hasDoc()) {
            const auto refs = publish::scanCustomAssets(doc_, sourceFs_);
            packFiles_.clear();
            packMissing_.clear();
            for (const auto& rf : refs) {
                if (rf.missing) packMissing_.push_back(rf.bspPath);
                else packFiles_.push_back(rf.bspPath + "|" + rf.sourcePath);
            }
            if (!packFiles_.empty()) compilePack_ = true;
            status_ = "Scanned " + std::to_string(packFiles_.size()) + " custom asset(s)";
        }

        ImGui::Dummy(ImVec2(0, dp(6.0f)));
        ImGui::PushStyleColor(ImGuiCol_Button, col::acc);
        ImGui::PushStyleColor(ImGuiCol_Text, col::bg0);
        if (fontUiMed) ImGui::PushFont(fontUiMed);
        if (ImGui::Button(compiler_.running() ? ICON_FA_HOURGLASS_HALF "  Compiling…"
                                              : ICON_FA_PLAY "  Compile & Launch TF2",
                          ImVec2(-1, dp(34.0f)))) {
            if (!compiler_.running() && hasDoc()) startCompile();
            showCompile_ = true;
        }
        if (fontUiMed) ImGui::PopFont();
        ImGui::PopStyleColor(2);
        if (ImGui::Button(ICON_FA_CLOUD_ARROW_UP "  Steam Workshop…", ImVec2(-1, dp(26.0f)))) {
            showWorkshop_ = true;
            if (wsItem_.title.empty() && hasDoc()) wsItem_.title = doc_.name();
        }
        ImGui::End();
    }
}

void Editor::drawWorkshopReadinessBar() {
    // Mockup 3: Bottom-Left TF2 Health-HUD-Style Active Piece Card + Bottom-Center Readiness Pill
    using namespace pb::ui;
    if (walkPlaytest_) return;
    ImGuiViewport* vp = ImGui::GetMainViewport();

    // ---- 1. Bottom-Left TF2 Health-HUD Active Piece / Selected Brush Card ----
    const float cardW = dp(356.0f);
    const float cardH = dp(104.0f);
    ImGui::SetNextWindowPos(
        ImVec2(vp->WorkPos.x + dp(14.0f), vp->WorkPos.y + vp->WorkSize.y - cardH - dp(14.0f)));
    ImGui::SetNextWindowSize(ImVec2(cardW, cardH));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(dp(10.0f), dp(8.0f)));
    ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0f);
    ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(0, 0, 0, 0));
    ImGui::Begin("##tf2_bl_hud", nullptr,
                 ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                     ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoScrollbar |
                     ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoDocking);
    ImGui::PopStyleColor();
    ImGui::PopStyleVar(2);

    ImDrawList* dl = ImGui::GetWindowDrawList();
    const ImVec2 wPos = ImGui::GetWindowPos();
    const ImVec2 wSz = ImGui::GetWindowSize();
    drawHudFrame(dl, wPos, ImVec2(wPos.x + wSz.x, wPos.y + wSz.y), dp(9.0f));

    // Left framed real TF2 .mdl or isometric icon box
    const float iconBox = dp(72.0f);
    const ImVec2 ibMin(wPos.x + dp(10.0f), wPos.y + dp(12.0f));
    const ImVec2 ibMax(ibMin.x + iconBox, ibMin.y + iconBox);
    dl->AddRectFilled(ibMin, ibMax, IM_COL32(20, 17, 15, 250), dp(7.0f));
    dl->AddRect(ibMin, ibMax, IM_COL32(82, 72, 62, 240), dp(7.0f), 0, 1.4f);

    const std::string activePiece = !placing_.empty() ? placing_ : std::string("Floor");
    const char* mdlPath = tf2ModelForPiece(activePiece);
    GLuint thumb = 0;
    if (mdlPath && sourceFs_.ready()) {
        if (modelThumbs_.has(mdlPath)) {
            static const model::StudioModel kEmpty;
            thumb = modelThumbs_.get(mdlPath, kEmpty, materials_);
        } else {
            thumb = modelThumbs_.get(mdlPath, model::loadStudioModel(sourceFs_, mdlPath), materials_);
        }
    }
    if (thumb) {
        dl->AddImage(static_cast<ImTextureID>((intptr_t)thumb),
                     ImVec2(ibMin.x + 4, ibMin.y + 4), ImVec2(ibMax.x - 4, ibMax.y - 4),
                     ImVec2(0, 1), ImVec2(1, 0));
    } else {
        drawMiniIsoPiece(dl, ImVec2((ibMin.x + ibMax.x) * 0.5f, (ibMin.y + ibMax.y) * 0.5f),
                         dp(21.0f), activePiece.c_str(), true);
    }

    // Right side of HUD card: Title, big dimensions, and chunky ▲/▼/↔ controls!
    ImGui::SetCursorScreenPos(ImVec2(ibMax.x + dp(12.0f), wPos.y + dp(10.0f)));
    ImGui::BeginGroup();

    if (!selection_.empty()) {
        glm::vec3 mn(1e30f), mx(-1e30f);
        for (const auto& r : selection_)
            if (const map::Solid* s = doc_.resolve(r)) {
                mn = glm::min(mn, s->boundsMin);
                mx = glm::max(mx, s->boundsMax);
            }
        const glm::vec3 sz = mx - mn;
        ImGui::PushStyleColor(ImGuiCol_Text, col::acc);
        if (fontUiMed) ImGui::PushFont(fontUiMed);
        ImGui::Text("SELECTED BRUSH (%zu)", selection_.size());
        if (fontUiMed) ImGui::PopFont();
        ImGui::PopStyleColor();

        ImGui::Text("%.0f x %.0fu", sz.x, sz.y);
        ImGui::SameLine(0, dp(8.0f));
        ImGui::PushStyleColor(ImGuiCol_Text, col::cadCyan);
        ImGui::Text("H: %.0fu", sz.z);
        ImGui::PopStyleColor();

        // Big zero-mistake Height & Size bumpers (no tiny corner boxes!)
        ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(dp(7.0f), dp(4.0f)));
        if (ImGui::Button(ICON_FA_ARROW_UP " +48u")) resizeSelectedBrushHeight(+48.0f);
        ImGui::SameLine(0, dp(4.0f));
        if (ImGui::Button(ICON_FA_ARROW_DOWN " -48u")) resizeSelectedBrushHeight(-48.0f);
        ImGui::SameLine(0, dp(4.0f));
        if (ImGui::Button(ICON_FA_MAXIMIZE " Grow")) resizeSelectedBrushFootprint(+64.0f);
        ImGui::SameLine(0, dp(4.0f));
        if (ImGui::Button(ICON_FA_TRASH "##delhud")) deleteSelection();
        ImGui::PopStyleVar();
    } else if (!placing_.empty()) {
        ImGui::PushStyleColor(ImGuiCol_Text, col::acc);
        if (fontUiMed) ImGui::PushFont(fontUiMed);
        ImGui::Text("PLACING: %s", placing_.c_str());
        if (fontUiMed) ImGui::PopFont();
        ImGui::PopStyleColor();
        ImGui::TextDisabled("Click anywhere in 3D to drop · Shift = multi");
        if (ImGui::SmallButton("Cancel (Esc)")) placing_.clear();
    } else {
        const char* hdr = (workshopStage_ == 0) ? "TF2 BUILD KIT"
                        : (workshopStage_ == 1) ? "TF2 GAMEPLAY"
                        : (workshopStage_ == 2) ? "TF2 STYLE & BIOME"
                                                : "TF2 PLAYTEST";
        const char* sub = (workshopStage_ == 0) ? "Pick a piece on the right rail"
                        : (workshopStage_ == 1) ? "Stamp spawns, kits & objectives"
                        : (workshopStage_ == 2) ? "Paint a theme or pick a biome"
                                                : "Check readiness & launch TF2";
        ImGui::PushStyleColor(ImGuiCol_Text, col::acc);
        if (fontUiMed) ImGui::PushFont(fontUiMed);
        ImGui::TextUnformatted(hdr);
        if (fontUiMed) ImGui::PopFont();
        ImGui::PopStyleColor();
        ImGui::TextDisabled("%s", sub);
        ImGui::PushStyleVar(ImGuiStyleVar_FramePadding, ImVec2(dp(7.0f), dp(3.0f)));
        if (workshopStage_ == 2) {
            if (ImGui::Button(ICON_FA_MOUNTAIN_SUN " Environments")) showEnvPicker_ = true;
            ImGui::SameLine(0, dp(5.0f));
            if (ImGui::Button(ICON_FA_SUN " Sun Light")) placing_ = "Sun / sky";
        } else if (workshopStage_ == 3) {
            if (ImGui::Button(ICON_FA_SHIELD_HALVED " 1-Click Seal")) quickSealMap();
            ImGui::SameLine(0, dp(5.0f));
            if (ImGui::Button(ICON_FA_PLAY " Play")) {
                if (hasDoc()) { compileLaunch_ = true; startCompile(); }
            }
        } else {
            char gLbl[24];
            std::snprintf(gLbl, sizeof(gLbl), "Grid %du", gridSize_);
            if (ImGui::Button(gLbl)) {
                gridSize_ = (gridSize_ == 64) ? 32 : (gridSize_ == 32 ? 16 : 64);
            }
            ImGui::SameLine(0, dp(5.0f));
            if (workshopStage_ == 1) {
                if (ImGui::Button(tool_ == Tool::Wire ? "Tool: Wire" : "Wire (L)"))
                    tool_ = Tool::Wire;
            } else {
                if (ImGui::Button(tool_ == Tool::PushPull ? "Tool: Push-Pull" : "Push-Pull (P)"))
                    tool_ = Tool::PushPull;
            }
        }
        ImGui::PopStyleVar();
    }

    ImGui::EndGroup();
    ImGui::End();

    // ---- 2. Bottom-Center Compact TF2 Readiness Pill ----
    int redSpawns = 0, bluSpawns = 0, objectives = 0, lights = 0;
    const bool bspPreview = !hasDoc() && bsp_.loaded();
    if (bspPreview) {
        for (const auto& kv : bsp_.entities()) {
            auto ci = kv.find("classname");
            if (ci == kv.end()) continue;
            const std::string& cn = ci->second;
            if (cn == "info_player_teamspawn" || cn == "info_player_start") {
                auto ti = kv.find("TeamNum");
                const std::string t = (ti != kv.end()) ? ti->second : "";
                if (t == "2") ++redSpawns;
                else if (t == "3") ++bluSpawns;
                else { ++redSpawns; ++bluSpawns; }
            }
            if (cn == "team_control_point" || cn == "item_teamflag" ||
                cn == "trigger_capture_area" || cn == "func_capturezone" ||
                cn == "team_train_watcher")
                ++objectives;
            if (cn.rfind("light", 0) == 0) ++lights;
        }
    } else {
        for (const auto& e : doc_.entities()) {
            if (e.classname == "info_player_teamspawn" || e.classname == "info_player_start") {
                const std::string t = e.kv.get("TeamNum");
                if (t == "2") ++redSpawns;
                else if (t == "3") ++bluSpawns;
                else { ++redSpawns; ++bluSpawns; }
            }
            if (e.classname == "team_control_point" || e.classname == "item_teamflag" ||
                e.classname == "trigger_capture_area" || e.classname == "func_capturezone")
                ++objectives;
            if (e.classname.rfind("light", 0) == 0) ++lights;
        }
    }
    const bool sealed = bspPreview ? true : isMapSealed();

    char pTxt[192];
    std::snprintf(pTxt, sizeof(pTxt),
                  "RED %s (%d)   |   Obj %s (%d)   |   BLU %s (%d)   |   %s   |   Grid %du",
                  redSpawns > 0 ? ICON_FA_CHECK : ICON_FA_XMARK, redSpawns,
                  objectives > 0 ? ICON_FA_CHECK : ICON_FA_XMARK, objectives,
                  bluSpawns > 0 ? ICON_FA_CHECK : ICON_FA_XMARK, bluSpawns,
                  bspPreview ? (ICON_FA_CHECK " Compiled BSP")
                             : (sealed ? ICON_FA_CHECK " Sealed"
                                       : ICON_FA_TRIANGLE_EXCLAMATION " Unsealed"),
                  gridSize_);
    const ImVec2 tSz = ImGui::CalcTextSize(pTxt);
    const float bpW = tSz.x + dp(28.0f);
    const float bpH = dp(28.0f);
    const float bpX = std::max(vp->WorkPos.x + cardW + dp(28.0f),
                               vp->WorkPos.x + (vp->WorkSize.x - bpW) * 0.5f);

    if (bpX + bpW < vp->WorkPos.x + vp->WorkSize.x - dp(14.0f)) {
        ImGui::SetNextWindowPos(ImVec2(bpX, vp->WorkPos.y + vp->WorkSize.y - bpH - dp(14.0f)));
        ImGui::SetNextWindowSize(ImVec2(bpW, bpH));
        ImGui::PushStyleVar(ImGuiStyleVar_WindowPadding, ImVec2(0, 0));
        ImGui::PushStyleVar(ImGuiStyleVar_WindowBorderSize, 0.0f);
        ImGui::PushStyleColor(ImGuiCol_WindowBg, ImVec4(0, 0, 0, 0));
        ImGui::Begin("##tf2_bc_pill", nullptr,
                     ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                         ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoScrollbar |
                         ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoDocking);
        ImGui::PopStyleColor();
        ImGui::PopStyleVar(2);

        ImDrawList* pdl = ImGui::GetWindowDrawList();
        const ImVec2 pm = ImGui::GetWindowPos();
        pdl->AddRectFilled(pm, ImVec2(pm.x + bpW, pm.y + bpH), IM_COL32(25, 22, 19, 228), dp(14.0f));
        pdl->AddRect(pm, ImVec2(pm.x + bpW, pm.y + bpH), IM_COL32(78, 68, 58, 235), dp(14.0f));
        pdl->AddText(ImVec2(pm.x + dp(14.0f), pm.y + (bpH - tSz.y) * 0.5f),
                     sealed && redSpawns && bluSpawns ? u32(col::good) : u32(col::dim), pTxt);
        ImGui::End();
    }
}

// ---------------------------------------------------------------------------
// Intuitive 3D Click-Drag Painting for Floors & Walls (Zero tiny handles!)
// ---------------------------------------------------------------------------
void Editor::handlePaintDrag(ViewPanel& p) {
    if (!hasDoc() || p.kind != ViewKind::Perspective) return;
    const bool paintable = (placing_ == "Floor" || placing_ == "Wall");
    if (!paintable) {
        paintDragging_ = false;
        return;
    }

    auto rayGround = [&](const ImVec2& mp, glm::vec3& out) -> bool {
        glm::vec3 ro, rd;
        p.camera.pixelRay({mp.x - p.contentMin.x, mp.y - p.contentMin.y}, p.contentSize, ro, rd);
        if (std::fabs(rd.z) < 1e-4f) return false;
        const float t = -ro.z / rd.z;
        if (t <= 0.0f || t > 16000.0f) return false;
        glm::vec3 h = ro + rd * t;
        out = glm::vec3(snapF(h.x), snapF(h.y), 0.0f);
        return true;
    };

    if (!paintDragging_) {
        if (p.hovered && ImGui::IsMouseClicked(ImGuiMouseButton_Left) && !ImGui::IsAnyItemHovered()) {
            glm::vec3 hit;
            if (rayGround(ImGui::GetMousePos(), hit)) {
                paintDragging_ = true;
                paintStart_ = hit;
                paintEnd_ = hit;
            }
        }
        return;
    }

    glm::vec3 cur;
    if (rayGround(ImGui::GetMousePos(), cur)) paintEnd_ = cur;

    if (ImGui::IsMouseReleased(ImGuiMouseButton_Left)) {
        paintDragging_ = false;
        const glm::vec3 d = glm::abs(paintEnd_ - paintStart_);
        if (d.x < 16.0f && d.y < 16.0f) {
            // Short click falls back to standard piece drop at cursor
            placePiece(placing_, paintStart_);
        } else {
            glm::vec3 mn(std::min(paintStart_.x, paintEnd_.x),
                         std::min(paintStart_.y, paintEnd_.y),
                         placing_ == "Floor" ? -16.0f : 0.0f);
            glm::vec3 mx(std::max(paintStart_.x, paintEnd_.x),
                         std::max(paintStart_.y, paintEnd_.y),
                         placing_ == "Floor" ? 0.0f : 128.0f);
            if (mx.x - mn.x < 16.0f) {
                mn.x -= 8.0f;
                mx.x += 8.0f;
            }
            if (mx.y - mn.y < 16.0f) {
                mn.y -= 8.0f;
                mx.y += 8.0f;
            }
            const char* mat = (placing_ == "Floor") ? "concrete/concretefloor002"
                                                    : "brick/brickwall003a";
            map::Solid s = map::Solid::makeBox(mn, mx, mat);
            s.id = doc_.nextId();
            const int idx = static_cast<int>(doc_.worldSolids().size());
            doc_.worldSolids().push_back(std::move(s));
            selection_ = {{-1, idx}};
            if (symmetryX_ && (std::fabs(mn.x + mx.x) > 16.0f)) {
                glm::vec3 mmn(-mx.x, mn.y, mn.z), mmx(-mn.x, mx.y, mx.z);
                map::Solid ms = map::Solid::makeBox(mmn, mmx, mat);
                ms.id = doc_.nextId();
                doc_.worldSolids().push_back(std::move(ms));
            }
            afterEdit(placing_ == "Floor" ? "Paint floor" : "Paint wall");
            rebuildSelectionWire();
        }
        if (!ImGui::GetIO().KeyShift) placing_.clear();
    }
}

void Editor::drawPaintDragOverlay(ViewPanel& p, float aspect, ImDrawList* dl) {
    if (!paintDragging_ || p.kind != ViewKind::Perspective) return;
    glm::vec3 mn(std::min(paintStart_.x, paintEnd_.x),
                 std::min(paintStart_.y, paintEnd_.y),
                 placing_ == "Floor" ? -16.0f : 0.0f);
    glm::vec3 mx(std::max(paintStart_.x, paintEnd_.x),
                 std::max(paintStart_.y, paintEnd_.y),
                 placing_ == "Floor" ? 0.0f : 128.0f);
    if (mx.x - mn.x < 16.0f) { mn.x -= 8.0f; mx.x += 8.0f; }
    if (mx.y - mn.y < 16.0f) { mn.y -= 8.0f; mx.y += 8.0f; }

    const glm::mat4 vp = p.camera.proj(aspect) * p.camera.view();
    auto pr = [&](const glm::vec3& w, bool& ok) -> ImVec2 {
        const glm::vec4 c = vp * glm::vec4(w, 1.0f);
        ok = c.w > 1e-4f;
        if (!ok) return {};
        return ImVec2(p.contentMin.x + (c.x / c.w * 0.5f + 0.5f) * p.contentSize.x,
                      p.contentMin.y + (1.0f - (c.y / c.w * 0.5f + 0.5f)) * p.contentSize.y);
    };

    glm::vec3 c[8] = {
        {mn.x, mn.y, mn.z}, {mx.x, mn.y, mn.z}, {mx.x, mx.y, mn.z}, {mn.x, mx.y, mn.z},
        {mn.x, mn.y, mx.z}, {mx.x, mn.y, mx.z}, {mx.x, mx.y, mx.z}, {mn.x, mx.y, mx.z},
    };
    ImVec2 sc[8];
    bool ok[8];
    for (int i = 0; i < 8; ++i) sc[i] = pr(c[i], ok[i]);
    if (ok[4] && ok[5] && ok[6] && ok[7]) {
        ImVec2 top[4] = {sc[4], sc[5], sc[6], sc[7]};
        dl->AddConvexPolyFilled(top, 4, IM_COL32(236, 154, 68, 75));
    }
    const int e[12][2] = {{0,1},{1,2},{2,3},{3,0},{4,5},{5,6},{6,7},{7,4},{0,4},{1,5},{2,6},{3,7}};
    for (auto& pr2 : e)
        if (ok[pr2[0]] && ok[pr2[1]])
            dl->AddLine(sc[pr2[0]], sc[pr2[1]], IM_COL32(255, 190, 90, 255), 2.5f);

    bool okc;
    const ImVec2 mid = pr(glm::vec3((mn.x + mx.x) * 0.5f, (mn.y + mx.y) * 0.5f, mx.z + 18.0f), okc);
    if (okc) {
        char lbl[96];
        std::snprintf(lbl, sizeof(lbl), "%s: %.0f x %.0f x %.0fu",
                      placing_.c_str(), mx.x - mn.x, mx.y - mn.y, mx.z - mn.z);
        const ImVec2 ts = ImGui::CalcTextSize(lbl);
        dl->AddRectFilled(ImVec2(mid.x - ts.x * 0.5f - 8, mid.y - 12),
                          ImVec2(mid.x + ts.x * 0.5f + 8, mid.y + ts.y - 4),
                          IM_COL32(24, 21, 18, 240), 5.0f);
        dl->AddRect(ImVec2(mid.x - ts.x * 0.5f - 8, mid.y - 12),
                    ImVec2(mid.x + ts.x * 0.5f + 8, mid.y + ts.y - 4),
                    IM_COL32(236, 154, 68, 255), 5.0f);
        dl->AddText(ImVec2(mid.x - ts.x * 0.5f, mid.y - 8), IM_COL32(255, 240, 215, 255), lbl);
    }
}

// ---------------------------------------------------------------------------
// Instant F5 In-Editor TF2 First-Person Walk / Crouch-Jump / Double-Jump Test
// ---------------------------------------------------------------------------
void Editor::toggleWalkPlaytest() {
    if (!walkPlaytest_) {
        walkPlaytest_ = true;
        walkSavedCamPos_ = views_[0].camera.pos;
        walkSavedYaw_ = views_[0].camera.yawDeg;
        walkSavedPitch_ = views_[0].camera.pitchDeg;
        walkVel_ = glm::vec3(0.0f);
        walkOnGround_ = false;
        walkAirJumps_ = 0;

        // Spawn at first RED spawn if present, else safely above ground at origin
        walkPos_ = glm::vec3(0.0f, -256.0f, 32.0f);
        if (hasDoc()) {
            for (const auto& e : doc_.entities()) {
                if (e.classname == "info_player_teamspawn" || e.classname == "info_player_start") {
                    walkPos_ = e.origin + glm::vec3(0.0f, 0.0f, 8.0f);
                    break;
                }
            }
        }
        views_[0].camera.pos = walkPos_ + glm::vec3(0.0f, 0.0f, 68.0f);
        views_[0].camera.pitchDeg = 0.0f;
        status_ = "TF2 F5 Walk Playtest — WASD Move · Space Jump · Ctrl Crouch · 1/2/3 Class · F5/Esc Exit";
    } else {
        walkPlaytest_ = false;
        views_[0].camera.pos = walkSavedCamPos_;
        views_[0].camera.yawDeg = walkSavedYaw_;
        views_[0].camera.pitchDeg = walkSavedPitch_;
        if (window_) glfwSetInputMode(window_, GLFW_CURSOR, GLFW_CURSOR_NORMAL);
        status_ = "Exited TF2 Walk Playtest.";
    }
}

void Editor::updateWalkPlaytest(ViewPanel& p, float dt) {
    if (!walkPlaytest_ || p.kind != ViewKind::Perspective) return;
    ImGuiIO& io = ImGui::GetIO();

    if (ImGui::IsKeyPressed(ImGuiKey_Escape) || ImGui::IsKeyPressed(ImGuiKey_F5)) {
        toggleWalkPlaytest();
        return;
    }
    if (ImGui::IsKeyPressed(ImGuiKey_1)) walkClass_ = 0;  // Scout (400 u/s + Double Jump)
    if (ImGui::IsKeyPressed(ImGuiKey_2)) walkClass_ = 1;  // Soldier (240 u/s)
    if (ImGui::IsKeyPressed(ImGuiKey_3)) walkClass_ = 2;  // Heavy (230 u/s)

    // Mouse look while dragging RMB or LMB (keeps cursor usable without trapping user!)
    if (ImGui::IsMouseDragging(ImGuiMouseButton_Right, 0.0f) ||
        ImGui::IsMouseDragging(ImGuiMouseButton_Left, 0.0f)) {
        p.camera.yawDeg -= io.MouseDelta.x * 0.18f;
        p.camera.pitchDeg = std::clamp(p.camera.pitchDeg - io.MouseDelta.y * 0.18f, -85.0f, 85.0f);
    }

    const bool crouch = ImGui::IsKeyDown(ImGuiKey_LeftCtrl) || ImGui::IsKeyDown(ImGuiKey_C);
    const float baseSpeed = (walkClass_ == 0) ? 400.0f : (walkClass_ == 1 ? 240.0f : 230.0f);
    const float moveSpeed = crouch ? baseSpeed * 0.45f : baseSpeed;

    glm::vec3 fwd = p.camera.forward();
    fwd.z = 0.0f;
    if (glm::length(fwd) > 1e-4f) fwd = glm::normalize(fwd);
    glm::vec3 rt = glm::normalize(glm::cross(fwd, glm::vec3(0, 0, 1)));

    glm::vec3 wish(0.0f);
    if (ImGui::IsKeyDown(ImGuiKey_W)) wish += fwd;
    if (ImGui::IsKeyDown(ImGuiKey_S)) wish -= fwd;
    if (ImGui::IsKeyDown(ImGuiKey_D)) wish += rt;
    if (ImGui::IsKeyDown(ImGuiKey_A)) wish -= rt;
    if (glm::length(wish) > 1e-4f) wish = glm::normalize(wish);

    walkVel_.x = wish.x * moveSpeed;
    walkVel_.y = wish.y * moveSpeed;
    walkVel_.z -= 800.0f * dt;  // Authentic Source TF2 gravity (sv_gravity 800)

    if (ImGui::IsKeyPressed(ImGuiKey_Space)) {
        if (walkOnGround_) {
            // TF2 jump: ~289 u/s (52u normal, ~64u crouch-jump!)
            walkVel_.z = crouch ? 320.0f : 292.0f;
            walkOnGround_ = false;
            walkAirJumps_ = (walkClass_ == 0) ? 1 : 0;  // Scout gets Double Jump!
        } else if (walkAirJumps_ > 0) {
            walkVel_.z = 295.0f;
            --walkAirJumps_;
        }
    }

    // Swept AABB collision against all solid world brushes (48x48x83u TF2 player hull)
    const float halfW = 24.0f;
    const float hullH = crouch ? 55.0f : 83.0f;
    auto overlapsAny = [&](const glm::vec3& pos) -> bool {
        if (!hasDoc()) return pos.z < 0.0f;
        const glm::vec3 pMin(pos.x - halfW, pos.y - halfW, pos.z);
        const glm::vec3 pMax(pos.x + halfW, pos.y + halfW, pos.z + hullH);
        for (const auto& s : doc_.worldSolids()) {
            if (!s.valid || s.hidden) continue;
            if (!s.faces.empty() && s.faces[0].material.find("toolsskybox") != std::string::npos)
                continue;
            if (pMax.x > s.boundsMin.x && pMin.x < s.boundsMax.x &&
                pMax.y > s.boundsMin.y && pMin.y < s.boundsMax.y &&
                pMax.z > s.boundsMin.z && pMin.z < s.boundsMax.z)
                return true;
        }
        return false;
    };

    // Move X/Y with 18u TF2 stair step-up!
    glm::vec3 nextXY = walkPos_ + glm::vec3(walkVel_.x * dt, 0.0f, 0.0f);
    if (!overlapsAny(nextXY)) walkPos_.x = nextXY.x;
    else if (!overlapsAny(nextXY + glm::vec3(0, 0, 18.0f))) walkPos_ = nextXY + glm::vec3(0, 0, 18.0f);

    nextXY = walkPos_ + glm::vec3(0.0f, walkVel_.y * dt, 0.0f);
    if (!overlapsAny(nextXY)) walkPos_.y = nextXY.y;
    else if (!overlapsAny(nextXY + glm::vec3(0, 0, 18.0f))) walkPos_ = nextXY + glm::vec3(0, 0, 18.0f);

    // Move Z + ground contact
    glm::vec3 nextZ = walkPos_ + glm::vec3(0.0f, 0.0f, walkVel_.z * dt);
    if (!overlapsAny(nextZ)) {
        walkPos_.z = nextZ.z;
        walkOnGround_ = false;
    } else {
        if (walkVel_.z < 0.0f) {
            walkOnGround_ = true;
            walkAirJumps_ = (walkClass_ == 0) ? 1 : 0;
        }
        walkVel_.z = 0.0f;
    }
    if (walkPos_.z < -512.0f) {
        walkPos_ = glm::vec3(0.0f, 0.0f, 32.0f);
        walkVel_ = glm::vec3(0.0f);
    }

    const float eyeH = crouch ? 45.0f : 68.0f;
    p.camera.pos = walkPos_ + glm::vec3(0.0f, 0.0f, eyeH);
}

void Editor::drawWalkPlaytestHud(const ViewPanel& p, ImDrawList* dl) {
    if (!walkPlaytest_ || p.kind != ViewKind::Perspective) return;
    using namespace pb::ui;
    // Crisp TF2 crosshair in center of viewport
    const ImVec2 c(p.contentMin.x + p.contentSize.x * 0.5f, p.contentMin.y + p.contentSize.y * 0.5f);
    dl->AddLine(ImVec2(c.x - 10, c.y), ImVec2(c.x - 3, c.y), IM_COL32(245, 240, 225, 220), 2.0f);
    dl->AddLine(ImVec2(c.x + 3, c.y), ImVec2(c.x + 10, c.y), IM_COL32(245, 240, 225, 220), 2.0f);
    dl->AddLine(ImVec2(c.x, c.y - 10), ImVec2(c.x, c.y - 3), IM_COL32(245, 240, 225, 220), 2.0f);
    dl->AddLine(ImVec2(c.x, c.y + 3), ImVec2(c.x, c.y + 10), IM_COL32(245, 240, 225, 220), 2.0f);

    const char* clsName = (walkClass_ == 0) ? "SCOUT (400 u/s · 2x Jump)"
                        : (walkClass_ == 1) ? "SOLDIER (240 u/s)"
                                            : "HEAVY (230 u/s)";
    char bar[256];
    std::snprintf(bar, sizeof(bar),
                  "TF2 WALK PLAYTEST  |  %s  |  Drag Mouse Look · WASD Move · Space Jump · Ctrl Crouch · 1/2/3 Class · F5/Esc Exit",
                  clsName);
    const ImVec2 ts = ImGui::CalcTextSize(bar);
    const float w = ts.x + dp(32.0f), h = dp(34.0f);
    const ImVec2 mn(c.x - w * 0.5f, p.contentMin.y + p.contentSize.y - h - dp(18.0f));
    drawHudFrame(dl, mn, ImVec2(mn.x + w, mn.y + h), dp(8.0f), IM_COL32(76, 160, 210, 255));
    dl->AddText(ImVec2(mn.x + dp(16.0f), mn.y + (h - ts.y) * 0.5f - dp(2.0f)),
                IM_COL32(242, 236, 222, 255), bar);
}

// ---------------------------------------------------------------------------
// Asset & BSP Exporter Bridge for Build B (Godot 4 Prototype)
// ---------------------------------------------------------------------------
bool Editor::exportGodotKit(const std::string& outDir, const std::string& optionalBspPath) {
    namespace fs = std::filesystem;
    std::error_code ec;
    fs::create_directories(fs::path(outDir) / "textures", ec);
    fs::create_directories(fs::path(outDir) / "icons", ec);
    fs::create_directories(fs::path(outDir) / "maps", ec);

    // 1. Export real TF2 VPK textures for all 5 premade biomes as PNGs
    struct TexPair { const char* outName; const char* matPath; };
    static const TexPair kTex[] = {
        {"badlands_floor.png", "concrete/concretefloor002"},
        {"badlands_wall.png",  "brick/brickwall003a"},
        {"badlands_roof.png",  "metal/metalroof006a"},
        {"winter_floor.png",   "nature/snow_full001"},
        {"winter_wall.png",    "wood/wood_wall002"},
        {"sawmill_floor.png",  "wood/wood_floor002"},
        {"sawmill_wall.png",   "wood/wood_wall004"},
        {"spytech_floor.png",  "tile/tilefloor001a"},
        {"spytech_wall.png",   "concrete/computerwall003"},
        {"orange_floor.png",   "dev/dev_measuregeneric01b"},
        {"orange_wall.png",    "dev/dev_measurewall01a"},
    };
    int texOk = 0;
    for (const auto& t : kTex) {
        std::string vtfPath = "materials/" + std::string(t.matPath) + ".vtf";
        auto bytesOpt = sourceFs_.read(vtfPath);
        if (!bytesOpt) {
            if (auto vmtOpt = sourceFs_.read("materials/" + std::string(t.matPath) + ".vmt")) {
                std::string txt(vmtOpt->begin(), vmtOpt->end());
                const size_t pos = txt.find("basetexture");
                if (pos != std::string::npos) {
                    const size_t q1 = txt.find('"', pos + 11);
                    const size_t q2 = (q1 != std::string::npos) ? txt.find('"', q1 + 1) : std::string::npos;
                    if (q2 != std::string::npos) {
                        std::string bt = txt.substr(q1 + 1, q2 - q1 - 1);
                        std::replace(bt.begin(), bt.end(), '\\', '/');
                        bytesOpt = sourceFs_.read("materials/" + bt + ".vtf");
                    }
                }
            }
        }
        if (bytesOpt && !bytesOpt->empty()) {
            const auto img = source::decodeVtf(*bytesOpt, t.matPath);
            if (img.ok()) {
                const std::string p = (fs::path(outDir) / "textures" / t.outName).string();
                stbi_write_png(p.c_str(), img.width, img.height, 4, img.rgba.data(), img.width * 4);
                ++texOk;
            }
        }
    }

    // 2. Render & export real 3D TF2 .mdl item icons via ModelThumbnailer
    struct IconPair { const char* outName; const char* mdlPath; };
    static const IconPair kIcons[] = {
        {"health.png", "models/items/medkit_medium.mdl"},
        {"ammo.png",   "models/items/ammopack_medium.mdl"},
        {"locker.png", "models/props_gameplay/resupply_locker.mdl"},
        {"point.png",  "models/props_gameplay/cap_point_base.mdl"},
        {"intel.png",  "models/flag/briefcase.mdl"},
        {"cart.png",   "models/props_trainyard/bomb_cart.mdl"},
    };
    int iconOk = 0;
    for (const auto& ic : kIcons) {
        const auto mdl = model::loadStudioModel(sourceFs_, ic.mdlPath);
        const GLuint tex = modelThumbs_.get(ic.mdlPath, mdl, materials_);
        if (tex) {
            glBindTexture(GL_TEXTURE_2D, tex);
            GLint tw = 0, th = 0;
            glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_WIDTH, &tw);
            glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_HEIGHT, &th);
            if (tw > 0 && th > 0) {
                std::vector<uint8_t> rgba(static_cast<size_t>(tw) * th * 4, 0);
                glPixelStorei(GL_PACK_ALIGNMENT, 1);
                glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, rgba.data());
                std::vector<uint8_t> rowBuf(static_cast<size_t>(tw) * 4);
                for (int y = 0; y < th / 2; ++y) {
                    uint8_t* a = rgba.data() + static_cast<size_t>(y) * tw * 4;
                    uint8_t* b = rgba.data() + static_cast<size_t>(th - 1 - y) * tw * 4;
                    std::memcpy(rowBuf.data(), a, static_cast<size_t>(tw) * 4);
                    std::memcpy(a, b, static_cast<size_t>(tw) * 4);
                    std::memcpy(b, rowBuf.data(), static_cast<size_t>(tw) * 4);
                }
                const std::string p = (fs::path(outDir) / "icons" / ic.outName).string();
                stbi_write_png(p.c_str(), tw, th, 4, rgba.data(), tw * 4);
                ++iconOk;
            }
        }
    }

    // 3. Optionally export a compiled TF2 .bsp to a Godot-ready OBJ mesh!
    if (!optionalBspPath.empty()) {
        debugNoDecompile();
        if (openMap(optionalBspPath) && bsp_.loaded()) {
            bsp::MeshBuildOptions mopts;
            bsp::WorldMesh mesh = bsp::buildWorldMesh(bsp_, mopts);
            const std::string objPath = (fs::path(outDir) / "maps" / (bsp_.name() + ".obj")).string();
            std::ofstream os(objPath);
            if (os) {
                os << "# Exported from TF2 BSP by Pootis Builder Bridge\n";
                constexpr float S = 1.0f / 32.0f;
                for (const auto& v : mesh.vertices)
                    os << "v " << (v.pos.x * S) << " " << (v.pos.z * S) << " " << (-v.pos.y * S) << "\n";
                for (const auto& v : mesh.vertices)
                    os << "vn " << v.normal.x << " " << v.normal.z << " " << (-v.normal.y) << "\n";
                for (const auto& v : mesh.vertices)
                    os << "vt " << v.texUv.x << " " << (1.0f - v.texUv.y) << "\n";
                for (size_t i = 0; i + 2 < mesh.indices.size(); i += 3) {
                    const uint32_t a = mesh.indices[i] + 1;
                    const uint32_t b = mesh.indices[i + 1] + 1;
                    const uint32_t c = mesh.indices[i + 2] + 1;
                    os << "f " << a << "/" << a << "/" << a << " "
                       << b << "/" << b << "/" << b << " "
                       << c << "/" << c << "/" << c << "\n";
                }
                PB_INFO("Exported TF2 BSP mesh to %s (%zu verts, %zu tris)",
                        objPath.c_str(), mesh.vertices.size(), mesh.indices.size() / 3);
            }
        }
    }

    PB_INFO("Godot Kit Export complete -> %s (%d TF2 textures, %d TF2 3D icons)",
            outDir.c_str(), texOk, iconOk);
    return true;
}

}  // namespace pb
