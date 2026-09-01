#include "compile/MapCompiler.h"

#include <chrono>
#include <cstdlib>
#include <filesystem>

#include "core/Log.h"
#include "platform/Process.h"

namespace fs = std::filesystem;

namespace pb::compile {
namespace {

long long nowMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::steady_clock::now().time_since_epoch())
        .count();
}

// Common Steam library locations for TF2.
const char* kSteamGuesses[] = {
    "C:/Program Files (x86)/Steam/steamapps/common/Team Fortress 2",
    "C:/Program Files/Steam/steamapps/common/Team Fortress 2",
    "D:/Steam/steamapps/common/Team Fortress 2",
    "D:/SteamLibrary/steamapps/common/Team Fortress 2",
    "E:/SteamLibrary/steamapps/common/Team Fortress 2",
};

}  // namespace

bool GamePaths::valid() const {
    std::error_code ec;
    return !binDir.empty() && !gameDir.empty() &&
           fs::exists(fs::path(binDir) / "vbsp.exe", ec) &&
           fs::exists(fs::path(gameDir) / "gameinfo.txt", ec);
}

GamePaths GamePaths::detect() {
    auto tryRoot = [](const fs::path& root) -> GamePaths {
        std::error_code ec;
        GamePaths g;
        if (!fs::exists(root / "bin" / "vbsp.exe", ec)) return g;
        g.binDir = (root / "bin").string();
        g.gameDir = (root / "tf").string();
        for (const char* e : {"tf_win64.exe", "tf.exe", "hl2.exe"}) {
            if (fs::exists(root / e, ec)) {
                g.exe = (root / e).string();
                break;
            }
        }
        return g;
    };

    if (const char* env = std::getenv("TF2_DIR")) {
        GamePaths g = tryRoot(env);
        if (g.valid()) return g;
    }
    for (const char* guess : kSteamGuesses) {
        GamePaths g = tryRoot(guess);
        if (g.valid()) return g;
    }
    return {};
}

MapCompiler::~MapCompiler() {
    cancel_ = true;
    if (thread_.joinable()) thread_.join();
}

void MapCompiler::put(const std::string& line) {
    std::lock_guard<std::mutex> lk(mtx_);
    log_.push_back(line);
}

void MapCompiler::setStage(const std::string& s) {
    std::lock_guard<std::mutex> lk(mtx_);
    stage_ = s;
}

std::string MapCompiler::stage() const {
    std::lock_guard<std::mutex> lk(mtx_);
    return stage_;
}

std::string MapCompiler::mapName() const {
    std::lock_guard<std::mutex> lk(mtx_);
    return mapName_;
}

std::vector<std::string> MapCompiler::log() const {
    std::lock_guard<std::mutex> lk(mtx_);
    return log_;
}

double MapCompiler::elapsedSeconds() const {
    const long long end = endMs_ ? endMs_ : nowMs();
    return startMs_ ? (end - startMs_) / 1000.0 : 0.0;
}

void MapCompiler::cancel() {
    if (running_.load()) {
        cancel_ = true;
        put("");
        put("** cancel requested — stopping after the current tool **");
    }
}

void MapCompiler::start(const std::string& vmfPath, const CompileOptions& opts,
                        const GamePaths& paths) {
    if (running_.load()) return;
    if (thread_.joinable()) thread_.join();
    {
        std::lock_guard<std::mutex> lk(mtx_);
        log_.clear();
        stage_.clear();
        mapName_ = fs::path(vmfPath).stem().string();
    }
    cancel_ = false;
    finished_ = false;
    success_ = false;
    launched_ = false;
    running_ = true;
    startMs_ = nowMs();
    endMs_ = 0;
    thread_ = std::thread(&MapCompiler::run, this, vmfPath, opts, paths);
}

void MapCompiler::poll() {
    if (finished_.load() && thread_.joinable()) thread_.join();
}

void MapCompiler::run(std::string vmfPath, CompileOptions opts, GamePaths paths) {
    std::error_code ec;
    const std::string name = fs::path(vmfPath).stem().string();
    const bool fast = opts.profile == Profile::Fast;

    auto onLine = [this](const std::string& l) { put(l); };
    auto stagePrefix = [&](const char* tool) {
        put("");
        put(std::string("=== ") + tool + " ===");
        setStage(tool);
    };

    put(std::string("Compiling ") + name + "  (" + (fast ? "fast" : "final") +
        " profile)");
    put("game:  " + paths.gameDir);
    put("vmf:   " + vmfPath);

    if (!paths.valid()) {
        put("");
        put("ERROR: could not find the TF2 compile tools (bin/vbsp.exe).");
        put("Set the TF2_DIR environment variable to your Team Fortress 2 folder.");
        finished_ = true;
        running_ = false;
        endMs_ = nowMs();
        return;
    }

    // Newer vbsp/vvis/vrad refuse to write their .log/.prt outside a content
    // path the game "owns", so compile from <game>/mapsrc/ and copy the .bsp out.
    const fs::path workDir = fs::path(paths.gameDir) / "mapsrc";
    fs::create_directories(workDir, ec);
    const fs::path workVmf = workDir / (name + ".vmf");
    const fs::path bsp = workDir / (name + ".bsp");
    fs::copy_file(vmfPath, workVmf, fs::copy_options::overwrite_existing, ec);
    if (ec) {
        put("ERROR: could not stage the vmf into " + workDir.string() + " (" +
            ec.message() + ")");
        finished_ = true;
        running_ = false;
        endMs_ = nowMs();
        return;
    }
    vmfPath = workVmf.string();

    const std::string vbsp = (fs::path(paths.binDir) / "vbsp.exe").string();
    const std::string vvis = (fs::path(paths.binDir) / "vvis.exe").string();
    const std::string vrad = (fs::path(paths.binDir) / "vrad.exe").string();

    int rc = 0;

    // ---- studiomdl (imported models -> .mdl) -----------------------------
    if (!opts.modelQc.empty()) {
        const std::string studiomdl =
            (fs::path(paths.binDir) / "studiomdl.exe").string();
        if (!fs::exists(studiomdl, ec)) {
            put("\n(no studiomdl.exe — skipping " +
                std::to_string(opts.modelQc.size()) + " model bake(s))");
        } else {
            for (const auto& qc : opts.modelQc) {
                if (cancel_.load()) break;
                if (!fs::exists(qc, ec)) { put("  missing qc: " + qc); continue; }
                stagePrefix("studiomdl");
                put("  " + qc);
                rc = runProcessStreaming(
                    studiomdl,
                    {"-game", paths.gameDir, "-nop4", "-verbose", qc},
                    onLine, &cancel_);
                if (rc != 0)
                    put("  studiomdl returned " + std::to_string(rc) +
                        " — the prop may be missing in-game.");
            }
        }
    }

    // ---- vbsp -------------------------------------------------------------
    stagePrefix("vbsp");
    rc = runProcessStreaming(
        vbsp, {"-game", paths.gameDir, "-verbose", vmfPath}, onLine, &cancel_);
    if (cancel_.load()) { put("\ncancelled."); finished_ = true; running_ = false; endMs_ = nowMs(); return; }
    if (rc != 0 || !fs::exists(bsp, ec)) {
        put("\nvbsp failed (exit " + std::to_string(rc) + "). Stopping.");
        finished_ = true;
        running_ = false;
        endMs_ = nowMs();
        return;
    }

    // ---- vvis -----------------------------------------------------------
    if (opts.runVvis) {
        stagePrefix("vvis");
        std::vector<std::string> a = {"-game", paths.gameDir};
        if (fast) a.push_back("-fast");
        a.push_back(bsp.string());
        rc = runProcessStreaming(vvis, a, onLine, &cancel_);
        if (cancel_.load()) { put("\ncancelled."); finished_ = true; running_ = false; endMs_ = nowMs(); return; }
        if (rc != 0) put("\nvvis returned " + std::to_string(rc) +
                         " — continuing anyway.");
    } else {
        put("\n(skipping vvis)");
    }

    // ---- vrad -----------------------------------------------------------
    if (opts.runVrad) {
        stagePrefix("vrad");
        std::vector<std::string> a = {"-game", paths.gameDir};
        if (fast) {
            a.push_back("-fast");
            a.push_back("-noextra");
            a.push_back("-bounce");
            a.push_back("2");
        } else {
            a.push_back("-final");
            a.push_back("-StaticPropLighting");
            a.push_back("-StaticPropPolys");
            a.push_back("-TextureShadows");
        }
        a.push_back(bsp.string());
        rc = runProcessStreaming(vrad, a, onLine, &cancel_);
        if (cancel_.load()) { put("\ncancelled."); finished_ = true; running_ = false; endMs_ = nowMs(); return; }
        if (rc != 0) put("\nvrad returned " + std::to_string(rc) +
                         " — the map may be fullbright.");
    } else {
        put("\n(skipping vrad — map will be fullbright)");
    }

    // ---- copy into the game -------------------------------------------
    stagePrefix("copy");
    const fs::path dst = fs::path(paths.gameDir) / "maps" / (name + ".bsp");
    fs::create_directories(dst.parent_path(), ec);
    fs::copy_file(bsp, dst, fs::copy_options::overwrite_existing, ec);
    if (ec) {
        put("ERROR: could not copy the .bsp into " + dst.string() + " (" +
            ec.message() + ")");
        finished_ = true;
        running_ = false;
        endMs_ = nowMs();
        return;
    }
    put("copied -> " + dst.string());
    success_ = true;

    // ---- launch ------------------------------------------------------
    if (opts.launchGame && !cancel_.load()) {
        stagePrefix("launch");
        if (paths.exe.empty()) {
            put("no TF2 executable found; open the map manually with  map " + name);
        } else {
            const bool ok = launchDetached(
                paths.exe,
                {"-steam", "-insecure", "-novid", "+sv_lan", "1", "+map", name},
                fs::path(paths.exe).parent_path().string());
            launched_ = ok;
            put(ok ? "launched TF2 on " + name
                   : "could not start " + paths.exe);
        }
    }

    setStage("done");
    put("\nDONE in " + std::to_string((int)elapsedSeconds()) + "s.");
    finished_ = true;
    running_ = false;
    endMs_ = nowMs();
}

}  // namespace pb::compile
