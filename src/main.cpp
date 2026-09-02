#include "gpu/Gl.h"

#include <imgui.h>
#include <backends/imgui_impl_glfw.h>
#include <backends/imgui_impl_opengl3.h>
#include <stb_image.h>
#include <stb_image_write.h>

#include <cstdint>
#include <fstream>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

#include "app/Editor.h"
#include "app/Settings.h"
#include "app/Ui.h"
#include "core/File.h"
#include "core/Log.h"

namespace {

void glfwErrorCallback(int code, const char* desc) {
    PB_ERROR("GLFW error %d: %s", code, desc ? desc : "?");
}

// Set the window / taskbar icon from a .ico whose frames are PNG-encoded
// (all modern .ico files are). Picks the largest frame.
void setWindowIconFromIco(GLFWwindow* win, const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f) return;
    std::vector<uint8_t> buf((std::istreambuf_iterator<char>(f)),
                             std::istreambuf_iterator<char>());
    if (buf.size() < 6 || buf[2] != 1) return;
    const int count = buf[4] | (buf[5] << 8);
    int bestOfs = 0, bestLen = 0, bestArea = -1;
    for (int i = 0; i < count; ++i) {
        const size_t e = 6 + static_cast<size_t>(i) * 16;
        if (e + 16 > buf.size()) break;
        int w = buf[e] ? buf[e] : 256;
        int h = buf[e + 1] ? buf[e + 1] : 256;
        const uint32_t len = buf[e + 8] | (buf[e + 9] << 8) | (buf[e + 10] << 16) |
                             (buf[e + 11] << 24);
        const uint32_t ofs = buf[e + 12] | (buf[e + 13] << 8) | (buf[e + 14] << 16) |
                             (buf[e + 15] << 24);
        if (ofs + len > buf.size()) continue;
        if (w * h > bestArea) { bestArea = w * h; bestOfs = ofs; bestLen = len; }
    }
    if (bestLen < 8 || buf[bestOfs] != 0x89 || buf[bestOfs + 1] != 'P') return;
    int w = 0, h = 0, ch = 0;
    unsigned char* px = stbi_load_from_memory(buf.data() + bestOfs, bestLen, &w, &h,
                                              &ch, 4);
    if (!px) return;
    GLFWimage img{w, h, px};
    glfwSetWindowIcon(win, 1, &img);
    stbi_image_free(px);
}

struct Options {
    std::string mapPath;
    std::string screenshotPath;
    pb::ViewKind view = pb::ViewKind::Perspective;
    bool quad = false;
    bool ui = false;  // capture the full docked UI, not just a viewport
    bool pro = false;
    int selectSolid = -1;
    int selectEnt = -1;
    bool sampleMap = false;
    bool undoTest = false;
    bool compile = false;
    std::string panel;
    bool subDemo = false;
    bool texDemo = false;
    int shapeOp = -1;
    float scaleOverride = -1.0f;
    bool mapCheck = false;
    bool palette = false;
    bool settings = false;
    std::string makeTpl;
    std::string makeTurbine;
    std::string placePrefabPath;
    int subDemoMode = 0;
    bool workshop = false;
    bool dumpProps = false;
    bool noDecompile = false;
    float cordon = -1.0f;
    bool newBlank = false;
    int shape = 0;  // 1=hill 2=road
    int kitTab = -1;
    std::string mapName, outDir, dropModel;
    bool dumpFgd = false;
    std::string dumpFgdClass;
    std::string importObjPath;
    std::string placeEnt, placeKit, armKit;
    std::string saveVmfPath;
    int width = 1600;
    int height = 950;
    int warmupFrames = 8;
};

pb::ViewKind parseView(const std::string& s) {
    if (s == "top") return pb::ViewKind::Top;
    if (s == "front") return pb::ViewKind::Front;
    if (s == "side") return pb::ViewKind::Side;
    return pb::ViewKind::Perspective;
}

Options parseArgs(int argc, char** argv) {
    Options o;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&](const char* def) {
            return (i + 1 < argc) ? std::string(argv[++i]) : std::string(def);
        };
        if (a == "--screenshot") o.screenshotPath = next("");
        else if (a == "--ui") o.ui = true;
        else if (a == "--pro") o.pro = true;
        else if (a == "--select") o.selectSolid = std::atoi(next("0").c_str());
        else if (a == "--select-ent") o.selectEnt = std::atoi(next("0").c_str());
        else if (a == "--sample-map") o.sampleMap = true;
        else if (a == "--undo-test") o.undoTest = true;
        else if (a == "--compile") o.compile = true;
        else if (a == "--panel") o.panel = next("");
        else if (a == "--sub-demo") { o.subDemo = true; o.subDemoMode = std::atoi(next("0").c_str()); }
        else if (a == "--tex-demo") o.texDemo = true;
        else if (a == "--shape-op") o.shapeOp = std::atoi(next("0").c_str());
        else if (a == "--scale") o.scaleOverride = static_cast<float>(std::atof(next("1").c_str()));
        else if (a == "--map-check") o.mapCheck = true;
        else if (a == "--palette") o.palette = true;
        else if (a == "--settings") o.settings = true;
        else if (a == "--make-templates") o.makeTpl = next("");
        else if (a == "--make-turbine") o.makeTurbine = next("");
        else if (a == "--place-prefab") o.placePrefabPath = next("");
        else if (a == "--dump-props") o.dumpProps = true;
        else if (a == "--no-decompile") o.noDecompile = true;
        else if (a == "--new-map") o.newBlank = true;
        else if (a == "--hill") o.shape = 1;
        else if (a == "--road") o.shape = 2;
        else if (a == "--kit-tab") o.kitTab = std::atoi(next("0").c_str());
        else if (a == "--map-name") o.mapName = next("");
        else if (a == "--out-dir") o.outDir = next("");
        else if (a == "--drop-model") o.dropModel = next("");
        else if (a == "--cordon") o.cordon = static_cast<float>(std::atof(next("768").c_str()));
        else if (a == "--workshop") o.workshop = true;
        else if (a == "--dump-fgd") { o.dumpFgd = true; o.dumpFgdClass = next(""); }
        else if (a == "--import-obj") o.importObjPath = next("");
        else if (a == "--place-ent") o.placeEnt = next("");
        else if (a == "--place-kit") o.placeKit = next("");
        else if (a == "--arm-kit") o.armKit = next("");
        else if (a == "--save-vmf") o.saveVmfPath = next("");
        else if (a == "--view") {
            const std::string v = next("persp");
            o.quad = (v == "quad");
            o.view = parseView(v);
        }
        else if (a == "--width") o.width = std::atoi(next("1600").c_str());
        else if (a == "--height") o.height = std::atoi(next("950").c_str());
        else if (!a.empty() && a[0] != '-') o.mapPath = a;
    }
    return o;
}

int runHeadlessScreenshot(const Options& opt, GLFWwindow* window, float uiScale) {
    pb::Editor editor;
    if (!editor.init(window)) return 2;
    editor.attachSettings(pb::Settings::load(), uiScale);
    if (opt.pro) editor.setProMode();
    if (opt.noDecompile) editor.debugNoDecompile();
    if (!opt.mapPath.empty() && !editor.openMap(opt.mapPath))
        PB_WARN("map did not load; screenshot will show an empty scene");
    if (opt.sampleMap) editor.debugBuildSampleMap();
    if (opt.undoTest) editor.debugUndoTest();
    if (!opt.importObjPath.empty()) editor.debugImportObj(opt.importObjPath);
    if (!opt.placeEnt.empty()) editor.debugPlaceEntity(opt.placeEnt);
    if (!opt.placeKit.empty()) editor.debugPlaceKit(opt.placeKit);
    if (!opt.armKit.empty()) editor.debugArmKit(opt.armKit);
    if (!opt.placePrefabPath.empty()) editor.debugPlacePrefab(opt.placePrefabPath);
    if (opt.selectSolid >= 0) editor.debugSelectWorldSolid(opt.selectSolid);
    if (opt.selectEnt >= 0) editor.debugSelectEntity(opt.selectEnt);
    if (opt.newBlank) editor.debugNewBlank();
    if (!opt.dropModel.empty()) editor.debugDropModel(opt.dropModel);
    if (opt.kitTab >= 0) editor.debugKitTab(opt.kitTab);
    if (opt.shape == 1) editor.debugHill();
    if (opt.shape == 2) editor.debugRoad();
    if (opt.cordon > 0.0f) editor.debugCordon(opt.cordon);
    if (!opt.mapName.empty() || !opt.outDir.empty()) editor.debugCompileOut(opt.mapName, opt.outDir);
    if (opt.compile) editor.debugStartCompile(true);
    if (opt.subDemo) editor.debugSubObjectDemo(0, opt.subDemoMode);
    if (opt.texDemo) editor.debugTextureDemo(0);
    if (opt.shapeOp >= 0) editor.debugShapeOp(opt.shapeOp);
    if (opt.mapCheck) editor.debugMapCheck();
    if (opt.palette) editor.debugShowPalette();
    if (opt.settings) editor.debugShowSettings();
    if (!opt.makeTpl.empty()) editor.debugMakeTemplates(opt.makeTpl);
    if (!opt.makeTurbine.empty()) editor.debugMakeTurbine(opt.makeTurbine);
    if (!opt.saveVmfPath.empty()) editor.saveVmf(opt.saveVmfPath);
    if (!opt.panel.empty()) editor.debugFocusPanel(opt.panel);
    if (opt.dumpProps) editor.debugDumpProps();
    if (opt.workshop) editor.debugShowWorkshop();

    std::vector<uint8_t> rgba;

    if (opt.ui) {
        // Drive the real docked UI; wait out any background decompile (max ~12s).
        for (int i = 0; i < 3000; ++i) {
            if (i >= std::max(opt.warmupFrames, 4) && !editor.busy()) break;
            glfwPollEvents();
            ImGui_ImplOpenGL3_NewFrame();
            ImGui_ImplGlfw_NewFrame();
            ImGui::NewFrame();
            editor.frame();
            ImGui::Render();
            int fbw = 0, fbh = 0;
            glfwGetFramebufferSize(window, &fbw, &fbh);
            glViewport(0, 0, fbw, fbh);
            glClearColor(0.10f, 0.10f, 0.11f, 1.0f);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
            glfwSwapBuffers(window);
            if (editor.busy()) glfwWaitEventsTimeout(0.004);
        }
        int fbw = opt.width, fbh = opt.height;
        glfwGetFramebufferSize(window, &fbw, &fbh);
        rgba.assign(static_cast<size_t>(fbw) * fbh * 4, 0);
        glPixelStorei(GL_PACK_ALIGNMENT, 1);
        glReadPixels(0, 0, fbw, fbh, GL_RGBA, GL_UNSIGNED_BYTE, rgba.data());
        std::vector<uint8_t> tmp(static_cast<size_t>(fbw) * 4);
        for (int y = 0; y < fbh / 2; ++y) {
            uint8_t* p = rgba.data() + static_cast<size_t>(y) * fbw * 4;
            uint8_t* q = rgba.data() + static_cast<size_t>(fbh - 1 - y) * fbw * 4;
            std::memcpy(tmp.data(), p, tmp.size());
            std::memcpy(p, q, tmp.size());
            std::memcpy(q, tmp.data(), tmp.size());
        }
        if (!stbi_write_png(opt.screenshotPath.c_str(), fbw, fbh, 4, rgba.data(), fbw * 4)) {
            PB_ERROR("failed to write %s", opt.screenshotPath.c_str());
            return 4;
        }
        PB_INFO("wrote %s (%dx%d, full UI)", opt.screenshotPath.c_str(), fbw, fbh);
        editor.shutdown();
        return 0;
    }

    // A few frames so drivers settle.
    for (int i = 0; i < opt.warmupFrames; ++i) {
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        glfwSwapBuffers(window);
        glfwPollEvents();
    }

    const bool ok = opt.quad ? editor.renderQuadToImage(opt.width, opt.height, rgba)
                             : editor.renderToImage(opt.view, opt.width, opt.height, rgba);
    if (!ok) return 3;
    if (!stbi_write_png(opt.screenshotPath.c_str(), opt.width, opt.height, 4, rgba.data(),
                        opt.width * 4)) {
        PB_ERROR("failed to write %s", opt.screenshotPath.c_str());
        return 4;
    }
    PB_INFO("wrote %s (%dx%d)", opt.screenshotPath.c_str(), opt.width, opt.height);
    editor.shutdown();
    return 0;
}

}  // namespace

int main(int argc, char** argv) {
    const Options opt = parseArgs(argc, argv);
    const bool headless = !opt.screenshotPath.empty();

    glfwSetErrorCallback(glfwErrorCallback);
    if (!glfwInit()) {
        PB_ERROR("glfwInit failed");
        return 1;
    }
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    if (headless || opt.dumpFgd) glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);

    GLFWwindow* window = glfwCreateWindow(opt.width, opt.height, "Pootis Builder",
                                          nullptr, nullptr);
    if (!window) {
        PB_ERROR("glfwCreateWindow failed");
        glfwTerminate();
        return 1;
    }
    glfwMakeContextCurrent(window);
    glfwSwapInterval(headless ? 0 : 1);
    if (!headless)
        setWindowIconFromIco(window, pb::executableDir() + "/assets/PootisBuilder.ico");

    const int glv = gladLoadGL(glfwGetProcAddress);
    if (glv == 0) {
        PB_ERROR("gladLoadGL failed");
        return 1;
    }
    PB_INFO("OpenGL %d.%d — %s", GLAD_VERSION_MAJOR(glv), GLAD_VERSION_MINOR(glv),
            reinterpret_cast<const char*>(glGetString(GL_RENDERER)));

    pb::Settings settings = pb::Settings::load();
    float uiScale = settings.uiScale;
    if (uiScale <= 0.0f) {
        float sx = 1.0f, sy = 1.0f;
        glfwGetWindowContentScale(window, &sx, &sy);
        uiScale = sx > 0.0f ? sx : 1.0f;
    }
    if (opt.scaleOverride > 0.0f) uiScale = opt.scaleOverride;  // --scale (debug)
    uiScale = std::clamp(uiScale, 0.8f, 2.5f);

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGui::GetIO().ConfigFlags |= ImGuiConfigFlags_DockingEnable;
    pb::ui::loadFonts(pb::executableDir().c_str(), uiScale);
    pb::ui::applyStyle(uiScale);
    ImGui_ImplGlfw_InitForOpenGL(window, true);
    ImGui_ImplOpenGL3_Init("#version 330 core");

    if (opt.dumpFgd) {
        pb::Editor editor;
        int rc = 2;
        if (editor.init(window)) {
            editor.debugDumpFgd(opt.dumpFgdClass);
            editor.shutdown();
            rc = 0;
        }
        ImGui_ImplOpenGL3_Shutdown();
        ImGui_ImplGlfw_Shutdown();
        ImGui::DestroyContext();
        glfwDestroyWindow(window);
        glfwTerminate();
        return rc;
    }

    if (headless) {
        const int rc = runHeadlessScreenshot(opt, window, uiScale);
        ImGui_ImplOpenGL3_Shutdown();
        ImGui_ImplGlfw_Shutdown();
        ImGui::DestroyContext();
        glfwDestroyWindow(window);
        glfwTerminate();
        return rc;
    }

    pb::Editor editor;
    if (!editor.init(window)) {
        PB_ERROR("editor init failed");
        return 2;
    }
    editor.attachSettings(std::move(settings), uiScale);
    if (opt.pro) editor.setProMode();
    if (opt.noDecompile) editor.debugNoDecompile();
    if (!opt.mapPath.empty()) editor.openMap(opt.mapPath);

    while (!glfwWindowShouldClose(window)) {
        glfwPollEvents();
        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();
        ImGui::NewFrame();

        editor.frame();

        ImGui::Render();
        int fbw = 0, fbh = 0;
        glfwGetFramebufferSize(window, &fbw, &fbh);
        glViewport(0, 0, fbw, fbh);
        glClearColor(0.10f, 0.10f, 0.11f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
        glfwSwapBuffers(window);

        float newScale = 1.0f;
        if (editor.takeFontRebuild(newScale))
            pb::ui::rebuildFonts(pb::executableDir().c_str(), newScale);
    }

    editor.shutdown();
    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
    glfwDestroyWindow(window);
    glfwTerminate();
    return 0;
}
