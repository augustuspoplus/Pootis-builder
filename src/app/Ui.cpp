#include "app/Ui.h"

#include <algorithm>
#include <cmath>
#include <string>

#include "core/File.h"
#include "core/Log.h"
#include "IconsFontAwesome6.h"

namespace pb::ui {

ImFont* fontUi = nullptr;
ImFont* fontUiMed = nullptr;
ImFont* fontBig = nullptr;
ImFont* fontMono = nullptr;
float g_scale = 1.0f;

void loadFonts(const char* exeDir, float scale) {
    ImGuiIO& io = ImGui::GetIO();
    scale = std::clamp(scale, 0.6f, 3.0f);
    const std::string dir = std::string(exeDir) + "/assets/fonts/";

    auto exists = [&](const char* f) { return fileExists(dir + f); };
    if (!exists("IBMPlexSans-Regular.ttf") || !exists("fa-solid-900.ttf")) {
        PB_WARN("UI fonts not found in %s — using built-in font", dir.c_str());
        io.Fonts->AddFontDefault();
        fontUi = fontUiMed = fontBig = fontMono = io.Fonts->Fonts.back();
        return;
    }

    static const ImWchar faRange[] = {ICON_MIN_FA, ICON_MAX_16_FA, 0};

    ImFontConfig text;
    text.OversampleH = 3;
    text.OversampleV = 1;
    text.PixelSnapH = true;
    text.RasterizerMultiply = 1.06f;  // Plex is a touch light on a dark UI

    // Font Awesome merged inline: sized just under the cap height, nudged onto
    // the text baseline, and given an advance close to its real glyph width so
    // "ICON  text" labels don't get a wide gap.
    auto addWithIcons = [&](const char* file, float size, float iconScale = 0.88f) {
        size = std::round(size * scale);
        ImFont* f = io.Fonts->AddFontFromFileTTF((dir + file).c_str(), size, &text);
        ImFontConfig fa;
        fa.MergeMode = true;
        fa.PixelSnapH = true;
        fa.OversampleH = 2;
        fa.OversampleV = 1;
        fa.GlyphMinAdvanceX = std::round(size * 0.90f);
        fa.GlyphOffset.y = std::round(size * 0.045f) + 1.0f;
        io.Fonts->AddFontFromFileTTF((dir + "fa-solid-900.ttf").c_str(),
                                     std::round(size * iconScale), &fa, faRange);
        return f;
    };

    fontUi = addWithIcons("IBMPlexSans-Regular.ttf", 16.0f);
    fontUiMed = addWithIcons("IBMPlexSans-Medium.ttf", 16.0f);
    fontBig = addWithIcons("IBMPlexSans-SemiBold.ttf", 20.0f);
    fontMono = io.Fonts->AddFontFromFileTTF((dir + "IBMPlexMono-Regular.ttf").c_str(),
                                            std::round(14.5f * scale), &text);
    io.FontDefault = fontUi;
    PB_INFO("UI fonts loaded from %s (scale %.2f)", dir.c_str(), scale);
}

void rebuildFonts(const char* exeDir, float scale) {
    ImGuiIO& io = ImGui::GetIO();
    io.Fonts->Clear();  // the renderer backend re-uploads the atlas next frame
    fontUi = fontUiMed = fontBig = fontMono = nullptr;
    loadFonts(exeDir, scale);
    applyStyle(scale);
}

void applyStyle(float scale) {
    g_scale = std::clamp(scale, 0.6f, 3.0f);
    ImGuiStyle& s = ImGui::GetStyle();
    ImGui::StyleColorsDark(&s);

    s.WindowPadding = ImVec2(10, 10);
    s.FramePadding = ImVec2(10, 5);
    s.ItemSpacing = ImVec2(9, 7);
    s.ItemInnerSpacing = ImVec2(7, 5);
    s.CellPadding = ImVec2(7, 5);
    s.IndentSpacing = 18.0f;
    s.ScrollbarSize = 12.0f;
    s.GrabMinSize = 9.0f;

    s.WindowBorderSize = 1.0f;
    s.ChildBorderSize = 1.0f;
    s.PopupBorderSize = 1.0f;
    s.FrameBorderSize = 0.0f;
    s.TabBorderSize = 0.0f;

    s.WindowRounding = 5.0f;
    s.ChildRounding = 5.0f;
    s.FrameRounding = 5.0f;
    s.PopupRounding = 5.0f;
    s.GrabRounding = 4.0f;
    s.TabRounding = 5.0f;
    s.ScrollbarRounding = 6.0f;

    s.WindowMenuButtonPosition = ImGuiDir_None;
    s.WindowTitleAlign = ImVec2(0.0f, 0.5f);
    s.SeparatorTextBorderSize = 1.0f;
    s.DockingSeparatorSize = 2.0f;

    ImVec4* c = s.Colors;
    c[ImGuiCol_Text] = col::tx;
    c[ImGuiCol_TextDisabled] = col::faint;
    c[ImGuiCol_WindowBg] = col::bg1;
    c[ImGuiCol_ChildBg] = ImVec4(0, 0, 0, 0);
    c[ImGuiCol_PopupBg] = col::bg2;
    c[ImGuiCol_Border] = col::bd;
    c[ImGuiCol_BorderShadow] = ImVec4(0, 0, 0, 0);
    c[ImGuiCol_FrameBg] = col::bg2;
    c[ImGuiCol_FrameBgHovered] = col::bg3;
    c[ImGuiCol_FrameBgActive] = col::bg3;
    c[ImGuiCol_TitleBg] = col::bg1;
    c[ImGuiCol_TitleBgActive] = col::bg2;
    c[ImGuiCol_TitleBgCollapsed] = col::bg1;
    c[ImGuiCol_MenuBarBg] = col::bg1;
    c[ImGuiCol_ScrollbarBg] = ImVec4(0, 0, 0, 0);
    c[ImGuiCol_ScrollbarGrab] = col::bd;
    c[ImGuiCol_ScrollbarGrabHovered] = col::bd2;
    c[ImGuiCol_ScrollbarGrabActive] = col::bd2;
    c[ImGuiCol_CheckMark] = col::acc;
    c[ImGuiCol_SliderGrab] = col::acc;
    c[ImGuiCol_SliderGrabActive] = col::acc2;
    c[ImGuiCol_Button] = col::bg2;
    c[ImGuiCol_ButtonHovered] = col::bg3;
    c[ImGuiCol_ButtonActive] = col::bd2;
    c[ImGuiCol_Header] = col::bg3;
    c[ImGuiCol_HeaderHovered] = col::bd2;
    c[ImGuiCol_HeaderActive] = col::bd2;
    c[ImGuiCol_Separator] = col::bd;
    c[ImGuiCol_SeparatorHovered] = col::acc2;
    c[ImGuiCol_SeparatorActive] = col::acc;
    c[ImGuiCol_ResizeGrip] = col::bd;
    c[ImGuiCol_ResizeGripHovered] = col::acc2;
    c[ImGuiCol_ResizeGripActive] = col::acc;
    c[ImGuiCol_Tab] = col::bg1;
    c[ImGuiCol_TabHovered] = col::bg3;
    c[ImGuiCol_TabActive] = col::bg3;
    c[ImGuiCol_TabUnfocused] = col::bg1;
    c[ImGuiCol_TabUnfocusedActive] = col::bg2;
    c[ImGuiCol_DockingPreview] = ImVec4(col::acc.x, col::acc.y, col::acc.z, 0.32f);
    c[ImGuiCol_DockingEmptyBg] = col::bg0;
    c[ImGuiCol_PlotLines] = col::dim;
    c[ImGuiCol_PlotLinesHovered] = col::acc;
    c[ImGuiCol_PlotHistogram] = col::acc;
    c[ImGuiCol_PlotHistogramHovered] = col::acc2;
    c[ImGuiCol_TableHeaderBg] = col::bg2;
    c[ImGuiCol_TableBorderStrong] = col::bd2;
    c[ImGuiCol_TableBorderLight] = col::bd;
    c[ImGuiCol_TableRowBg] = ImVec4(0, 0, 0, 0);
    c[ImGuiCol_TableRowBgAlt] = ImVec4(1, 1, 1, 0.02f);
    c[ImGuiCol_TextSelectedBg] = ImVec4(col::acc.x, col::acc.y, col::acc.z, 0.35f);
    c[ImGuiCol_NavHighlight] = col::acc;
    c[ImGuiCol_DragDropTarget] = col::acc;
    c[ImGuiCol_ModalWindowDimBg] = ImVec4(0, 0, 0, 0.45f);

    if (scale != 1.0f) s.ScaleAllSizes(std::clamp(scale, 0.6f, 3.0f));
}

// ---------------------------------------------------------------------------

int segmented(const char* id, const char* const labels[], int count, int current,
              float height) {
    if (height <= 0.0f) height = ImGui::GetFrameHeight();
    int picked = -1;
    ImGui::PushID(id);
    ImGuiStyle& st = ImGui::GetStyle();
    ImGui::PushStyleVar(ImGuiStyleVar_ItemSpacing, ImVec2(1, 0));
    ImGui::PushStyleVar(ImGuiStyleVar_FrameRounding, 0.0f);
    for (int i = 0; i < count; ++i) {
        const bool on = i == current;
        ImGui::PushStyleColor(ImGuiCol_Button, on ? col::bg3 : col::bg2);
        ImGui::PushStyleColor(ImGuiCol_ButtonHovered, on ? col::bg3 : col::bd);
        ImGui::PushStyleColor(ImGuiCol_Text, on ? col::acc : col::dim);
        if (i > 0) ImGui::SameLine();
        if (ImGui::Button(labels[i], ImVec2(0, height))) picked = i;
        ImGui::PopStyleColor(3);
    }
    ImGui::PopStyleVar(2);
    ImGui::PopID();
    (void)st;
    return picked;
}

bool toolButton(const char* label, bool active, const char* tooltip, float height) {
    if (height <= 0.0f) height = ImGui::GetFrameHeight();
    ImGui::PushStyleColor(ImGuiCol_Button, active ? col::bg3 : ImVec4(0, 0, 0, 0));
    ImGui::PushStyleColor(ImGuiCol_ButtonHovered, col::bg3);
    ImGui::PushStyleColor(ImGuiCol_Text, active ? col::acc : col::dim);
    const bool hit = ImGui::Button(label, ImVec2(0, height));
    ImGui::PopStyleColor(3);
    if (tooltip && ImGui::IsItemHovered())
        ImGui::SetTooltip("%s", tooltip);
    return hit;
}

void sectionLabel(const char* text) {
    ImGui::PushStyleColor(ImGuiCol_Text, col::faint);
    if (fontUiMed) ImGui::PushFont(fontUiMed);
    ImGui::TextUnformatted(text);
    if (fontUiMed) ImGui::PopFont();
    ImGui::PopStyleColor();
}

}  // namespace pb::ui
