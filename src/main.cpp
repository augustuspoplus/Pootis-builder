#include "gpu/Gl.h"

#include <imgui.h>
#include <backends/imgui_impl_glfw.h>
#include <backends/imgui_impl_opengl3.h>
#include <stb_image_write.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "app/Editor.h"
#include "core/Log.h"

namespace {

void glfwErrorCallback(int code, const char* desc) {
    PB_ERROR("GLFW error %d: %s", code, desc ? desc : "?");
}

struct Options {
    std::string mapPath;
    std::string screenshotPath;
    pb::ViewKind view = pb::ViewKind::Perspective;
    bool quad = false;
    bool ui = false;  // capture the full docked UI, not just a viewport
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

// A restrained dark theme in the spirit of Hammer's panels.
void applyTheme() {
    ImGui::StyleColorsDark();
    ImGuiStyle& s = ImGui::GetStyle();
    s.WindowRounding = 2.0f;
    s.FrameRounding = 2.0f;
    s.GrabRounding = 2.0f;
    s.TabRounding = 2.0f;
    s.ScrollbarRounding = 2.0f;
    s.WindowBorderSize = 1.0f;
    s.FrameBorderSize = 0.0f;
    s.WindowMenuButtonPosition = ImGuiDir_None;
    ImVec4* c = s.Colors;
    c[ImGuiCol_WindowBg] = ImVec4(0.13f, 0.14f, 0.15f, 1.00f);
    c[ImGuiCol_MenuBarBg] = ImVec4(0.17f, 0.18f, 0.19f, 1.00f);
    c[ImGuiCol_Header] = ImVec4(0.24f, 0.26f, 0.28f, 1.00f);
    c[ImGuiCol_HeaderHovered] = ImVec4(0.30f, 0.33f, 0.36f, 1.00f);
    c[ImGuiCol_Tab] = ImVec4(0.18f, 0.19f, 0.20f, 1.00f);
    c[ImGuiCol_TabActive] = ImVec4(0.26f, 0.34f, 0.42f, 1.00f);
    c[ImGuiCol_TabHovered] = ImVec4(0.32f, 0.40f, 0.48f, 1.00f);
    c[ImGuiCol_Button] = ImVec4(0.24f, 0.26f, 0.28f, 1.00f);
    c[ImGuiCol_FrameBg] = ImVec4(0.10f, 0.11f, 0.12f, 1.00f);
    c[ImGuiCol_TitleBgActive] = ImVec4(0.20f, 0.24f, 0.28f, 1.00f);
    c[ImGuiCol_CheckMark] = ImVec4(0.98f, 0.68f, 0.30f, 1.00f);
    c[ImGuiCol_SliderGrab] = ImVec4(0.98f, 0.68f, 0.30f, 1.00f);
}

int runHeadlessScreenshot(const Options& opt, GLFWwindow* window) {
    pb::Editor editor;
    if (!editor.init(window)) return 2;
    if (!opt.mapPath.empty() && !editor.openMap(opt.mapPath))
        PB_WARN("map did not load; screenshot will show an empty scene");

    std::vector<uint8_t> rgba;

    if (opt.ui) {
        // Drive the real docked UI for a few frames, then grab the window FB.
        for (int i = 0; i < std::max(opt.warmupFrames, 4); ++i) {
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
    if (headless) glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);

    GLFWwindow* window = glfwCreateWindow(opt.width, opt.height, "Pootis Builder",
                                          nullptr, nullptr);
    if (!window) {
        PB_ERROR("glfwCreateWindow failed");
        glfwTerminate();
        return 1;
    }
    glfwMakeContextCurrent(window);
    glfwSwapInterval(headless ? 0 : 1);

    const int glv = gladLoadGL(glfwGetProcAddress);
    if (glv == 0) {
        PB_ERROR("gladLoadGL failed");
        return 1;
    }
    PB_INFO("OpenGL %d.%d — %s", GLAD_VERSION_MAJOR(glv), GLAD_VERSION_MINOR(glv),
            reinterpret_cast<const char*>(glGetString(GL_RENDERER)));

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGui::GetIO().ConfigFlags |= ImGuiConfigFlags_DockingEnable;
    applyTheme();
    ImGui_ImplGlfw_InitForOpenGL(window, true);
    ImGui_ImplOpenGL3_Init("#version 330 core");

    if (headless) {
        const int rc = runHeadlessScreenshot(opt, window);
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
    }

    editor.shutdown();
    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
    glfwDestroyWindow(window);
    glfwTerminate();
    return 0;
}
