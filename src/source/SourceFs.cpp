#include "source/SourceFs.h"

#include <algorithm>
#include <cctype>
#include <filesystem>

#include "core/File.h"
#include "core/Log.h"
#include "source/Vmt.h"

namespace fs = std::filesystem;

namespace pb::source {
namespace {

std::string lower(std::string s) {
    for (char& c : s) {
        if (c == '\\') c = '/';
        else c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    return s;
}

const char* kTf2Root =
    "C:/Program Files (x86)/Steam/steamapps/common/Team Fortress 2";

}  // namespace

void SourceFs::addLooseRoot(const std::string& dir) {
    if (fs::exists(dir)) {
        looseRoots_.push_back(dir);
        PB_INFO("SourceFs: loose root %s", dir.c_str());
    }
}

bool SourceFs::addVpk(const std::string& vpkPath) {
    if (!fs::exists(vpkPath)) return false;
    auto v = std::make_unique<Vpk>();
    if (!v->open(vpkPath)) return false;
    vpks_.push_back(std::move(v));
    return true;
}

void SourceFs::mountDefaults(const std::string& exeDir) {
    const std::string tf = std::string(kTf2Root) + "/tf";
    const std::string hl2 = std::string(kTf2Root) + "/hl2";

    addLooseRoot(tf);
    addLooseRoot(hl2);
    addVpk(tf + "/tf2_textures_dir.vpk");
    addVpk(tf + "/tf2_misc_dir.vpk");
    addVpk(hl2 + "/hl2_misc_dir.vpk");
    addVpk(hl2 + "/hl2_textures_dir.vpk");

    // Bundled ABS Mapping Resource Pack (common Hammer dev/measure textures).
    for (const std::string& base : {exeDir, exeDir + "/..", std::string(".")}) {
        const std::string p = base + "/assets/mapping_resource_pack/ABS_MRP_Material_Browser.vpk";
        if (fs::exists(p)) {
            addVpk(p);
            break;
        }
    }

    PB_INFO("SourceFs: %zu VPKs, %zu loose roots mounted", vpks_.size(),
            looseRoots_.size());
}

std::optional<std::vector<uint8_t>> SourceFs::read(const std::string& path) const {
    const std::string key = lower(path);
    for (const std::string& root : looseRoots_) {
        const std::string full = root + "/" + key;
        if (fs::exists(full)) {
            std::vector<uint8_t> data;
            if (readFile(full, data)) return data;
        }
    }
    for (const auto& v : vpks_) {
        if (auto d = v->read(key)) return d;
    }
    return std::nullopt;
}

VtfImage SourceFs::loadTexture(std::string texRel) const {
    texRel = lower(texRel);
    if (texRel.rfind("materials/", 0) != 0) texRel = "materials/" + texRel;
    if (texRel.size() < 4 || texRel.compare(texRel.size() - 4, 4, ".vtf") != 0)
        texRel += ".vtf";
    auto bytes = read(texRel);
    if (!bytes) return {};
    return decodeVtf(*bytes, texRel.c_str());
}

// VBSP writes per-cubemap patched materials as
// "maps/<mapname>/<original>_<x>_<y>_<z>" and packs them in the BSP pakfile.
// When the pakfile is not mounted, fall back to the original material.
static std::string stripCubemapPatch(const std::string& in) {
    if (in.rfind("maps/", 0) != 0) return in;
    const size_t firstSlash = in.find('/', 5);
    if (firstSlash == std::string::npos) return in;
    std::string rest = in.substr(firstSlash + 1);  // "<original>_<x>_<y>_<z>"
    // Trim three trailing "_<signed int>" groups.
    for (int i = 0; i < 3; ++i) {
        const size_t us = rest.find_last_of('_');
        if (us == std::string::npos) return in;
        const std::string tail = rest.substr(us + 1);
        if (tail.empty()) return in;
        for (size_t k = 0; k < tail.size(); ++k)
            if (!std::isdigit(static_cast<unsigned char>(tail[k])) &&
                !(k == 0 && tail[k] == '-'))
                return in;
        rest.erase(us);
    }
    return rest;
}

ResolvedMaterial SourceFs::resolveMaterial(std::string name) const {
    ResolvedMaterial out;
    name = lower(name);
    if (name.rfind("materials/", 0) == 0) name.erase(0, 10);
    if (name.size() > 4 && name.compare(name.size() - 4, 4, ".vmt") == 0)
        name.erase(name.size() - 4);

    if (!read("materials/" + name + ".vmt")) {
        const std::string stripped = stripCubemapPatch(name);
        if (stripped != name && read("materials/" + stripped + ".vmt")) name = stripped;
    }
    out.isTool = name.rfind("tools/", 0) == 0;

    Vmt vmt;
    std::string cur = "materials/" + name + ".vmt";
    for (int depth = 0; depth < 4; ++depth) {
        auto bytes = read(cur);
        if (!bytes) break;
        Vmt parsed = parseVmt(std::string(bytes->begin(), bytes->end()));
        // Merge: existing keys win only if already set by an outer patch.
        for (auto& [k, v] : parsed.kv) vmt.kv.emplace(k, v);
        if (vmt.shader.empty() || parsed.shader != "patch") vmt.shader = parsed.shader;
        if (parsed.shader == "patch" && !parsed.includePath.empty()) {
            cur = lower(parsed.includePath);
            if (cur.rfind("materials/", 0) != 0) cur = "materials/" + cur;
            out.found = true;
            continue;
        }
        out.found = true;
        break;
    }
    if (!out.found) return out;

    if (vmt.shader != "patch" && !vmt.shader.empty()) out.shader = vmt.shader;

    out.baseTexture = vmt.get("$basetexture");
    out.baseTexture2 = vmt.get("$basetexture2");
    out.surfaceProp = vmt.get("$surfaceprop");
    out.translucent = vmt.flag("$translucent") || vmt.flag("$additive");
    out.alphaTest = vmt.flag("$alphatest");
    out.noCull = vmt.flag("$nocull");
    out.selfIllum = vmt.flag("$selfillum");
    if (out.baseTexture.empty()) out.baseTexture = vmt.get("%tooltexture");
    return out;
}

}  // namespace pb::source
