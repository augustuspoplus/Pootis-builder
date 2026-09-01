#include "publish/Workshop.h"

#include <cstdio>
#include <cstdlib>
#include <filesystem>

#include "core/File.h"
#include "core/Log.h"

namespace fs = std::filesystem;

namespace pb::publish {

const char* visibilityName(Visibility v) {
    switch (v) {
        case Visibility::Public: return "Public";
        case Visibility::FriendsOnly: return "Friends only";
        case Visibility::Unlisted: return "Unlisted";
        case Visibility::Private: return "Private (hidden)";
    }
    return "?";
}

namespace {

std::string escapeVdf(const std::string& s) {
    std::string o;
    o.reserve(s.size() + 8);
    for (char c : s) {
        if (c == '"' || c == '\\') o += '\\';
        if (c == '\n') { o += "\\n"; continue; }
        if (c == '\r') continue;
        o += c;
    }
    return o;
}

}  // namespace

bool stageItem(const WorkshopItem& item, const std::string& stageRoot,
               StageResult& out, std::string* err) {
    std::error_code ec;
    if (item.bspPath.empty() || !fs::exists(item.bspPath, ec)) {
        if (err) *err = "no compiled .bsp — build the map first";
        return false;
    }

    out.itemDir = (fs::path(stageRoot) / "workshop_item").string();
    out.contentDir = (fs::path(out.itemDir) / "content").string();
    fs::create_directories(out.contentDir, ec);
    if (ec) {
        if (err) *err = "cannot create " + out.contentDir + " (" + ec.message() + ")";
        return false;
    }

    const std::string mapName = fs::path(item.bspPath).filename().string();
    const fs::path dstBsp = fs::path(out.contentDir) / mapName;
    fs::copy_file(item.bspPath, dstBsp, fs::copy_options::overwrite_existing, ec);
    if (ec) {
        if (err) *err = "cannot copy the .bsp into the item folder (" + ec.message() + ")";
        return false;
    }

    out.previewPath = (fs::path(out.itemDir) / "preview.jpg").string();
    if (!item.previewImage.empty() && fs::exists(item.previewImage, ec)) {
        const std::string ext = fs::path(item.previewImage).extension().string();
        out.previewPath =
            (fs::path(out.itemDir) / (std::string("preview") + (ext.empty() ? ".jpg" : ext)))
                .string();
        fs::copy_file(item.previewImage, out.previewPath,
                      fs::copy_options::overwrite_existing, ec);
    }
    const bool havePreview = fs::exists(out.previewPath, ec);

    // steamcmd-style publish.vdf
    out.vdfPath = (fs::path(out.itemDir) / "publish.vdf").string();
    FILE* f = std::fopen(out.vdfPath.c_str(), "wb");
    if (!f) {
        if (err) *err = "cannot write " + out.vdfPath;
        return false;
    }
    auto kv = [&](const char* k, const std::string& v) {
        std::fprintf(f, "  \"%s\" \"%s\"\n", k, escapeVdf(v).c_str());
    };
    std::fprintf(f, "\"workshopitem\"\n{\n");
    kv("appid", "440");
    if (item.publishedFileId != 0)
        kv("publishedfileid", std::to_string(item.publishedFileId));
    kv("contentfolder", out.contentDir);
    if (havePreview) kv("previewfile", out.previewPath);
    kv("visibility", std::to_string(static_cast<int>(item.visibility)));
    kv("title", item.title);
    kv("description", item.description);
    kv("changenote", item.changeNote);
    std::fprintf(f, "  \"tags\"\n  {\n");
    for (size_t i = 0; i < item.tags.size(); ++i)
        std::fprintf(f, "    \"%zu\" \"%s\"\n", i, escapeVdf(item.tags[i]).c_str());
    std::fprintf(f, "  }\n");
    std::fprintf(f, "}\n");
    std::fclose(f);

    PB_INFO("workshop: staged %s (%s, %zu tags%s)", mapName.c_str(),
            visibilityName(item.visibility), item.tags.size(),
            havePreview ? ", preview" : ", NO preview");
    return true;
}

std::string findSteamcmd() {
    const char* cands[] = {
        "steamcmd.exe",
        "C:/steamcmd/steamcmd.exe",
        "C:/Program Files (x86)/Steam/steamcmd.exe",
        "C:/Program Files/steamcmd/steamcmd.exe",
    };
    for (const char* c : cands)
        if (fileExists(c)) return c;
    if (const char* home = std::getenv("USERPROFILE")) {
        const std::string h = std::string(home) + "/steamcmd/steamcmd.exe";
        if (fileExists(h)) return h;
    }
    return "";
}

std::string steamcmdCommand(const std::string& steamcmd, const std::string& vdfPath,
                            const std::string& steamUser) {
    const std::string exe = steamcmd.empty() ? "steamcmd" : steamcmd;
    const std::string user = steamUser.empty() ? "<your_steam_login>" : steamUser;
    return "\"" + exe + "\" +login " + user + " +workshop_build_item \"" + vdfPath +
           "\" +quit";
}

bool haveInProcessUpload() {
#ifdef PB_HAVE_STEAMWORKS
    return fileExists(executableDir() + "/steam_api64.dll");
#else
    return false;
#endif
}

bool uploadInProcess(const WorkshopItem&, const StageResult&, float*, std::string*,
                     std::string* err) {
#ifdef PB_HAVE_STEAMWORKS
    // Integration point: SteamAPI_Init, SteamUGC()->CreateItem / StartItemUpdate
    // / SetItemTitle / SetItemDescription / SetItemPreview / SetItemContent /
    // SetItemVisibility / SetItemTags / SubmitItemUpdate, then poll
    // GetItemUpdateProgress until the result callback lands.
    if (err) *err = "in-process upload not wired in this build";
    return false;
#else
    if (err)
        *err =
            "This build has no Steamworks SDK. Use the generated steamcmd command, "
            "or drop steam_api64.dll + the SDK next to the exe and rebuild with "
            "PB_HAVE_STEAMWORKS.";
    return false;
#endif
}

}  // namespace pb::publish
