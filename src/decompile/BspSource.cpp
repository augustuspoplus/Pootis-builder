#include "decompile/BspSource.h"

#include <cstdlib>
#include <filesystem>

#include "core/Log.h"
#include "platform/Process.h"

namespace fs = std::filesystem;

namespace pb::decompile {
namespace {

// tools/ lives in the project root, not next to the exe (build/). Search up.
fs::path findToolsJava(const std::string& exeDir) {
    for (const std::string& base :
         {exeDir, exeDir + "/..", exeDir + "/../..", std::string("tools/..")}) {
        fs::path p = fs::path(base) / "tools" / "bin" / "java.exe";
        std::error_code ec;
        if (fs::exists(p, ec)) return p;
    }
    return {};
}

fs::path cacheDir() {
#ifdef _WIN32
    if (const char* la = std::getenv("LOCALAPPDATA")) {
        fs::path d = fs::path(la) / "PootisBuilder" / "decompiled";
        std::error_code ec;
        fs::create_directories(d, ec);
        return d;
    }
#endif
    fs::path d = fs::temp_directory_path() / "PootisBuilder" / "decompiled";
    std::error_code ec;
    fs::create_directories(d, ec);
    return d;
}

}  // namespace

bool available(const std::string& exeDir) {
    return !findToolsJava(exeDir).empty();
}

std::string bspToVmf(const std::string& exeDir, const std::string& bspPath,
                     std::string* err, std::string* log) {
    std::error_code ec;
    if (!fs::exists(bspPath, ec)) {
        if (err) *err = "bsp not found: " + bspPath;
        return {};
    }
    const fs::path java = findToolsJava(exeDir);
    if (java.empty()) {
        if (err) *err = "BSPSource runtime (tools/bin/java.exe) not found";
        return {};
    }

    const std::string name = fs::path(bspPath).stem().string();
    const fs::path vmf = cacheDir() / (name + ".vmf");

    // Reuse the cached decompile if it is newer than the .bsp.
    if (fs::exists(vmf, ec)) {
        const auto vt = fs::last_write_time(vmf, ec);
        const auto bt = fs::last_write_time(bspPath, ec);
        if (!ec && vt >= bt) {
            PB_INFO("decompile: reusing cache %s", vmf.string().c_str());
            return vmf.string();
        }
    }

    PB_INFO("decompile: running BSPSource on %s ...", name.c_str());
    std::string out;
    const int rc = runProcess(
        java.string(),
        {"-m",
         "info.ata4.bspsrc.app/info.ata4.bspsrc.app.src.BspSourceLauncher", "-o",
         vmf.string(), bspPath},
        &out);
    if (log) *log = out;

    if (rc != 0 || !fs::exists(vmf, ec)) {
        if (err)
            *err = "BSPSource failed (exit " + std::to_string(rc) + ")";
        PB_WARN("decompile failed (exit %d):\n%s", rc, out.c_str());
        return {};
    }
    PB_INFO("decompile: wrote %s", vmf.string().c_str());
    return vmf.string();
}

}  // namespace pb::decompile
