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
    std::vector<std::string> recent;  // most-recent first, capped

    static Settings load();
    void save() const;

    void pushRecent(const std::string& path);

private:
    static std::string filePath();
};

}  // namespace pb
