#pragma once
#include <atomic>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace pb::compile {

enum class Profile { Fast, Final };

struct CompileOptions {
    Profile profile = Profile::Fast;
    bool runVvis = true;
    bool runVrad = true;
    bool launchGame = true;
    // .qc files to bake into models/ with studiomdl before vbsp runs (from
    // "import 3D model -> as prop"). Safe to leave empty.
    std::vector<std::string> modelQc;
    // Extra files to pack into the .bsp with bspzip after vrad. Each entry is
    // "<internal/bsp/path>|<absolute source path>". Empty = no packing.
    std::vector<std::string> packFiles;
};

// Where TF2 and its compile tools live.
struct GamePaths {
    std::string binDir;   // .../Team Fortress 2/bin
    std::string gameDir;  // .../Team Fortress 2/tf
    std::string exe;      // .../Team Fortress 2/tf_win64.exe
    bool valid() const;
    static GamePaths detect();
};

// Runs vbsp -> vvis -> vrad on a saved .vmf on a background thread, copies the
// resulting .bsp into the game's maps/ folder and (optionally) launches TF2 on
// it. All state is polled from the UI thread; the log is line-buffered.
class MapCompiler {
public:
    ~MapCompiler();

    void start(const std::string& vmfPath, const CompileOptions& opts,
               const GamePaths& paths);
    void cancel();
    void poll();  // join the worker once it has finished; call every frame

    bool running() const { return running_.load(); }
    bool finished() const { return finished_.load(); }
    bool succeeded() const { return success_.load(); }
    bool launched() const { return launched_.load(); }
    std::string stage() const;
    std::string mapName() const;
    std::vector<std::string> log() const;
    double elapsedSeconds() const;

private:
    void run(std::string vmfPath, CompileOptions opts, GamePaths paths);
    void put(const std::string& line);
    void setStage(const std::string& s);

    mutable std::mutex mtx_;
    std::vector<std::string> log_;
    std::string stage_;
    std::string mapName_;
    std::thread thread_;
    std::atomic<bool> running_{false};
    std::atomic<bool> finished_{false};
    std::atomic<bool> success_{false};
    std::atomic<bool> launched_{false};
    std::atomic<bool> cancel_{false};
    long long startMs_ = 0;
    long long endMs_ = 0;
};

}  // namespace pb::compile
