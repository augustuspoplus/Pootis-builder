#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace pb::publish {

enum class Visibility { Public = 0, FriendsOnly = 1, Unlisted = 2, Private = 3 };

// Everything a TF2 (appid 440) Steam Workshop map submission needs.
struct WorkshopItem {
    std::string title;
    std::string description;
    std::string changeNote = "Initial release";
    Visibility visibility = Visibility::Private;   // safe default
    std::vector<std::string> tags = {"Map"};
    std::string bspPath;         // the compiled .bsp to upload
    std::string previewImage;    // .jpg / .png, < 1 MB
    uint64_t publishedFileId = 0;  // 0 = create new; otherwise update this item
};

struct StageResult {
    std::string itemDir;      // the staged folder
    std::string contentDir;   // <itemDir>/content  (what Steam uploads)
    std::string vdfPath;      // <itemDir>/publish.vdf  (for steamcmd)
    std::string previewPath;  // <itemDir>/preview.jpg
};

// Lays out a Workshop item folder under `stageRoot` (content/<map>.bsp, a
// preview image, and a steamcmd-compatible publish.vdf). Returns false + *err
// on failure (missing bsp, unwritable dir).
bool stageItem(const WorkshopItem& item, const std::string& stageRoot,
               StageResult& out, std::string* err = nullptr);

// Absolute path to steamcmd.exe if one can be found (PATH + common installs),
// else "".
std::string findSteamcmd();

// The command line the user runs to push a staged item (steamcmd prompts for
// its own login; we never handle credentials).
std::string steamcmdCommand(const std::string& steamcmd, const std::string& vdfPath,
                            const std::string& steamUser);

// True when a Steamworks SDK is available to do the upload in-process
// (steam_api64.dll beside the exe and a build with PB_HAVE_STEAMWORKS).
bool haveInProcessUpload();

// Attempts the in-process ISteamUGC upload. Without the SDK this immediately
// returns false with an explanatory *err. `progress` (0..1) and `status` are
// updated as it runs; call from a worker thread.
bool uploadInProcess(const WorkshopItem& item, const StageResult& staged,
                     float* progress, std::string* status, std::string* err);

const char* visibilityName(Visibility v);

}  // namespace pb::publish
