#pragma once
#include <imgui.h>

// Shared visual language for the editor chrome: the warm-neutral dark palette
// from the approved UI direction, plus font handles and small widgets.
namespace pb::ui {

// Palette (matches the design mockups; sRGB hex in the comments).
namespace col {
inline const ImVec4 bg0{0.086f, 0.094f, 0.106f, 1.0f};   // #16181b window/base
inline const ImVec4 bg1{0.114f, 0.125f, 0.141f, 1.0f};   // #1d2024 panels
inline const ImVec4 bg2{0.145f, 0.157f, 0.176f, 1.0f};   // #25282d inputs / raised
inline const ImVec4 bg3{0.180f, 0.196f, 0.220f, 1.0f};   // #2e3238 hover
inline const ImVec4 bd{0.200f, 0.216f, 0.243f, 1.0f};    // #33373e hairline
inline const ImVec4 bd2{0.255f, 0.275f, 0.306f, 1.0f};   // #41464e strong border
inline const ImVec4 tx{0.890f, 0.898f, 0.910f, 1.0f};    // #e3e5e8 text
inline const ImVec4 dim{0.596f, 0.620f, 0.651f, 1.0f};   // #989ea6 muted
inline const ImVec4 faint{0.424f, 0.447f, 0.478f, 1.0f}; // #6c727a hint
inline const ImVec4 acc{0.925f, 0.604f, 0.267f, 1.0f};   // #ec9a44 accent
inline const ImVec4 acc2{0.788f, 0.494f, 0.184f, 1.0f};  // #c97e2f accent deep
inline const ImVec4 sel{0.329f, 0.655f, 0.886f, 1.0f};   // #54a7e2 selection
inline const ImVec4 good{0.42f, 0.73f, 0.49f, 1.0f};     // checklist done
}  // namespace col

inline ImU32 u32(const ImVec4& c, float a = 1.0f) {
    return ImGui::GetColorU32(ImVec4(c.x, c.y, c.z, c.w * a));
}

// Font handles, valid after loadFonts().
extern ImFont* fontUi;      // 16px regular  — default
extern ImFont* fontUiMed;   // 16px medium   — labels, headers
extern ImFont* fontBig;     // 21px semibold — titles
extern ImFont* fontMono;    // 14.5px mono   — coordinates, keycaps

// Loads IBM Plex + Font Awesome from <exeDir>/assets/fonts at the given scale
// (1.0 = default). Falls back to the built-in font if the files are missing.
void loadFonts(const char* exeDir, float scale = 1.0f);

// Applies the Pootis Builder style, with all metrics multiplied by `scale`.
void applyStyle(float scale = 1.0f);

// Clears + reloads the font atlas and re-applies the style at a new scale.
// Call once (e.g. after ImGui::Render) when the user changes the UI scale.
void rebuildFonts(const char* exeDir, float scale);

// --- small widgets --------------------------------------------------------

// A segmented control. `labels` are icon+text strings; returns the newly
// picked index, or -1 if unchanged. `count` items, `current` is in/out.
int segmented(const char* id, const char* const labels[], int count, int current,
              float height = 30.0f);

// A flat toolbar button (icon + optional text). Returns true on click.
bool toolButton(const char* label, bool active = false, const char* tooltip = nullptr);

// Section label in the muted uppercase style used across panels.
void sectionLabel(const char* text);

}  // namespace pb::ui
