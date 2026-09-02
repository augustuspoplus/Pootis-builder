#pragma once
#include <string>
#include <vector>

namespace pb {

// Small persisted user settings (UI scale, recent maps). Stored as a flat
// key=value file under %LOCALAPPDATA%\PootisBuilder, or next to the exe as a
// fallback.
struct Settings {
    float uiScale = 0.0f;       // 0 = "auto" (use the monitor content scale)
    bool showWelcome = true;

    // Editing
    int gridSize = 64;
    bool snap = true;
    float flySpeed = 900.0f;
    bool autosave = true;
    float autosaveMins = 5.0f;

    // Viewport
    int shadeMode = 0;         // ShadeMode
    float gizmoSize = 0.17f;   // move/rotate/scale handle size (clip space)
    int gizmoStyle = 0;        // 0 normal, 1 bold, 2 fine
    bool showGrid = true;
    bool showProps = true;
    bool showPointEntities = false;
    bool wireOverlay = false;
    float exposure = 1.15f;
    float lightmapGain = 1.0f;

    // Advanced
    bool autoDecompile = true; // decompile .bsp on open
    bool bakeProps = true;     // render prop_static models
    std::string tf2Dir;        // override for the TF2 install

    std::vector<std::string> recent;  // most-recent first, capped

    static Settings load();
    void save() const;

    void pushRecent(const std::string& path);

private:
    static std::string filePath();
};

}  // namespace pb
