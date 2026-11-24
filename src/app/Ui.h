#pragma once
#include <imgui.h>
#include <string>

// Shared visual language for the editor chrome: the warm-neutral dark palette
// from the approved UI direction, plus font handles and small widgets.
namespace pb::ui {

// Palette — Direction B: Warm TF2 Mann Co. Workshop charcoal/cream/amber + RED/BLU.
namespace col {
inline const ImVec4 bg0{0.094f, 0.082f, 0.075f, 1.0f};   // #181513 window/base
inline const ImVec4 bg1{0.118f, 0.102f, 0.090f, 1.0f};   // #1e1a17 panels
inline const ImVec4 bg2{0.161f, 0.141f, 0.125f, 1.0f};   // #292420 cards / raised
inline const ImVec4 bg3{0.200f, 0.173f, 0.153f, 1.0f};   // #332c27 hover
inline const ImVec4 bd{0.227f, 0.200f, 0.176f, 1.0f};    // #3a332d hairline
inline const ImVec4 bd2{0.302f, 0.267f, 0.235f, 1.0f};   // #4d443c strong border
inline const ImVec4 tx{0.941f, 0.902f, 0.824f, 1.0f};    // #f0e6d2 warm parchment
inline const ImVec4 dim{0.749f, 0.706f, 0.635f, 1.0f};   // #bfb4a2 muted
inline const ImVec4 faint{0.541f, 0.498f, 0.439f, 1.0f}; // #8a7f70 hint
inline const ImVec4 acc{0.898f, 0.529f, 0.169f, 1.0f};   // #e5872b TF2 amber
inline const ImVec4 acc2{0.745f, 0.420f, 0.125f, 1.0f};  // #be6b20 amber deep
inline const ImVec4 sel{0.329f, 0.655f, 0.886f, 1.0f};   // #54a7e2 selection
inline const ImVec4 teamRed{0.722f, 0.220f, 0.231f, 1.0f}; // #b8383b TF2 RED
inline const ImVec4 teamBlu{0.298f, 0.494f, 0.627f, 1.0f}; // #4c7ea0 TF2 BLU
inline const ImVec4 cadCyan{0.000f, 0.898f, 1.000f, 1.0f}; // #00e5ff CAD accent
inline const ImVec4 good{0.424f, 0.769f, 0.486f, 1.0f};    // #6cc47c checklist done
inline const ImVec4 warn{0.910f, 0.470f, 0.320f, 1.0f};    // #e87852 warning / error
}  // namespace col

inline ImU32 u32(const ImVec4& c, float a = 1.0f) {
    return ImGui::GetColorU32(ImVec4(c.x, c.y, c.z, c.w * a));
}

// Font handles, valid after loadFonts().
extern ImFont* fontUi;      // 16px regular  — default
extern ImFont* fontUiMed;   // 16px medium   — labels, headers (TF2 Secondary when available)
extern ImFont* fontBig;     // 21px semibold — titles (TF2 Build when available)
extern ImFont* fontTf2;     // 17px TF2 Build — HUD buttons, stage pills, counters
extern ImFont* fontMono;    // 14.5px mono   — coordinates, keycaps

// The UI scale currently in effect (set by applyStyle). 1.0 = 100%.
extern float g_scale;

// GPU / driver strings, filled once at startup (shown in Options).
extern std::string g_gpuRenderer;
extern std::string g_gpuVersion;

// `px` device-independent pixels scaled to the active UI scale.
inline float dp(float px) { return px * g_scale; }

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
// height <= 0 uses the current frame height (font-derived, already scaled).
int segmented(const char* id, const char* const labels[], int count, int current,
              float height = 0.0f);

// A flat toolbar button (icon + optional text). Returns true on click.
// height <= 0 uses the current frame height.
bool toolButton(const char* label, bool active = false, const char* tooltip = nullptr,
                float height = 0.0f);

// Section label in the muted uppercase style used across panels.
void sectionLabel(const char* text);

}  // namespace pb::ui
