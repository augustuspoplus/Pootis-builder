#include "app/Settings.h"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>

#include "core/File.h"
#include "core/Log.h"

namespace fs = std::filesystem;

namespace pb {

namespace {
constexpr size_t kMaxRecent = 10;
}

std::string Settings::filePath() {
#ifdef _WIN32
    if (const char* la = std::getenv("LOCALAPPDATA")) {
        const fs::path dir = fs::path(la) / "PootisBuilder";
        std::error_code ec;
        fs::create_directories(dir, ec);
        return (dir / "pootis.ini").string();
    }
#endif
    return executableDir() + "/pootis.ini";
}

Settings Settings::load() {
    Settings s;
    std::ifstream f(filePath());
    if (!f) return s;
    std::string line;
    while (std::getline(f, line)) {
        const auto eq = line.find('=');
        if (eq == std::string::npos) continue;
        const std::string key = line.substr(0, eq);
        const std::string val = line.substr(eq + 1);
        auto b = [&] { return val == "1"; };
        auto fnum = [&] { return std::strtof(val.c_str(), nullptr); };
        auto inum = [&] { return std::atoi(val.c_str()); };
        if (key == "ui_scale") s.uiScale = fnum();
        else if (key == "show_welcome") s.showWelcome = b();
        else if (key == "grid_size") s.gridSize = inum();
        else if (key == "snap") s.snap = b();
        else if (key == "fly_speed") s.flySpeed = fnum();
        else if (key == "autosave") s.autosave = b();
        else if (key == "autosave_mins") s.autosaveMins = fnum();
        else if (key == "shade_mode") s.shadeMode = inum();
        else if (key == "gizmo_size") s.gizmoSize = fnum();
        else if (key == "gizmo_style") s.gizmoStyle = inum();
        else if (key == "show_grid") s.showGrid = b();
        else if (key == "show_props") s.showProps = b();
        else if (key == "show_point_ents") s.showPointEntities = b();
        else if (key == "wire_overlay") s.wireOverlay = b();
        else if (key == "exposure") s.exposure = fnum();
        else if (key == "lightmap_gain") s.lightmapGain = fnum();
        else if (key == "auto_decompile") s.autoDecompile = b();
        else if (key == "bake_props") s.bakeProps = b();
        else if (key == "perf_mode") s.perfMode = inum();
        else if (key == "tf2_dir") s.tf2Dir = val;
        else if (key.rfind("recent", 0) == 0 && !val.empty()) s.recent.push_back(val);
    }
    if (s.recent.size() > kMaxRecent) s.recent.resize(kMaxRecent);
    return s;
}

void Settings::save() const {
    std::ofstream f(filePath(), std::ios::trunc);
    if (!f) {
        PB_WARN("could not write settings to %s", filePath().c_str());
        return;
    }
    f << "ui_scale=" << uiScale << "\n";
    f << "show_welcome=" << (showWelcome ? 1 : 0) << "\n";
    f << "grid_size=" << gridSize << "\n";
    f << "snap=" << (snap ? 1 : 0) << "\n";
    f << "fly_speed=" << flySpeed << "\n";
    f << "autosave=" << (autosave ? 1 : 0) << "\n";
    f << "autosave_mins=" << autosaveMins << "\n";
    f << "shade_mode=" << shadeMode << "\n";
    f << "gizmo_size=" << gizmoSize << "\n";
    f << "gizmo_style=" << gizmoStyle << "\n";
    f << "show_grid=" << (showGrid ? 1 : 0) << "\n";
    f << "show_props=" << (showProps ? 1 : 0) << "\n";
    f << "show_point_ents=" << (showPointEntities ? 1 : 0) << "\n";
    f << "wire_overlay=" << (wireOverlay ? 1 : 0) << "\n";
    f << "exposure=" << exposure << "\n";
    f << "lightmap_gain=" << lightmapGain << "\n";
    f << "auto_decompile=" << (autoDecompile ? 1 : 0) << "\n";
    f << "bake_props=" << (bakeProps ? 1 : 0) << "\n";
    f << "perf_mode=" << perfMode << "\n";
    if (!tf2Dir.empty()) f << "tf2_dir=" << tf2Dir << "\n";
    for (size_t i = 0; i < recent.size() && i < kMaxRecent; ++i)
        f << "recent" << i << "=" << recent[i] << "\n";
}

void Settings::pushRecent(const std::string& path) {
    std::string norm = path;
    std::replace(norm.begin(), norm.end(), '\\', '/');
    recent.erase(std::remove_if(recent.begin(), recent.end(),
                                [&](const std::string& p) {
                                    std::string q = p;
                                    std::replace(q.begin(), q.end(), '\\', '/');
                                    return q == norm;
                                }),
                 recent.end());
    recent.insert(recent.begin(), norm);
    if (recent.size() > kMaxRecent) recent.resize(kMaxRecent);
}

}  // namespace pb
