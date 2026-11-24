#include "publish/AssetScan.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <set>

#include "map/MapDocument.h"
#include "map/Solid.h"
#include "source/SourceFs.h"

namespace pb::publish {
namespace {

using source::SourceFs;

std::string lower(std::string s) {
    for (char& c : s) c = static_cast<char>(std::tolower((unsigned char)c));
    return s;
}
bool ends(const std::string& s, const char* suf) {
    const size_t n = std::strlen(suf);
    return s.size() >= n && s.compare(s.size() - n, n, suf) == 0;
}

// A tool material never needs packing (it's in the base game and stripped by
// vbsp anyway).
bool isToolMat(const std::string& m) { return m.rfind("tools/", 0) == 0; }

struct Scan {
    SourceFs& fs;
    std::vector<AssetRef>& out;
    std::set<std::string> seen;

    void consider(AssetRef::Kind kind, const std::string& bspPath) {
        const std::string key = lower(bspPath);
        if (!seen.insert(key).second) return;
        const auto origin = fs.assetOrigin(key);
        if (origin == SourceFs::AssetOrigin::Base) return;
        AssetRef r;
        r.kind = kind;
        r.bspPath = key;
        if (origin == SourceFs::AssetOrigin::Missing) {
            r.missing = true;
        } else {
            r.sourcePath = fs.loosePath(key);
            if (r.sourcePath.empty()) return;  // in a non-official vpk: skip for now
        }
        out.push_back(std::move(r));
    }

    void material(std::string name) {
        name = lower(name);
        if (name.empty() || isToolMat(name)) return;
        consider(AssetRef::Material, "materials/" + name + ".vmt");
        const auto rm = fs.resolveMaterial(name);
        for (const std::string& t : {rm.baseTexture, rm.baseTexture2})
            if (!t.empty())
                consider(AssetRef::Texture, "materials/" + lower(t) + ".vtf");
    }

    void model(std::string mdl) {
        mdl = lower(mdl);
        if (mdl.empty() || mdl[0] == '*' || !ends(mdl, ".mdl")) return;
        if (mdl.rfind("models/", 0) != 0) mdl = "models/" + mdl;
        const std::string stem = mdl.substr(0, mdl.size() - 4);
        consider(AssetRef::Model, mdl);
        for (const char* ext :
             {".vvd", ".dx90.vtx", ".dx80.vtx", ".sw.vtx", ".vtx", ".phy"}) {
            const std::string sib = stem + ext;
            if (!fs.loosePath(sib).empty() ||
                fs.assetOrigin(sib) == SourceFs::AssetOrigin::Custom)
                consider(AssetRef::Model, sib);
        }
    }

    void sound(std::string s) {
        s = lower(s);
        if (s.empty()) return;
        if (!(ends(s, ".wav") || ends(s, ".mp3"))) return;  // not a soundscape name
        if (s.rfind("sound/", 0) != 0) s = "sound/" + s;
        consider(AssetRef::Sound, s);
    }
};

}  // namespace

std::vector<AssetRef> scanCustomAssets(const map::MapDocument& doc, SourceFs& fs) {
    std::vector<AssetRef> out;
    Scan sc{fs, out, {}};

    auto doSolids = [&](const std::vector<map::Solid>& solids) {
        for (const auto& s : solids)
            for (const auto& f : s.faces) sc.material(f.material);
    };
    doSolids(doc.worldSolids());
    for (const auto& e : doc.entities()) {
        doSolids(e.solids);
        sc.model(e.kv.get("model"));
        // Common sound-bearing keys across ambient_generic / trigger / etc.
        for (const char* k : {"message", "noise", "noise1", "sound", "soundname"})
            sc.sound(e.kv.get(k));
    }

    std::sort(out.begin(), out.end(), [](const AssetRef& a, const AssetRef& b) {
        return a.bspPath < b.bspPath;
    });
    return out;
}

std::vector<std::string> toPackList(const std::vector<AssetRef>& refs) {
    std::vector<std::string> out;
    for (const auto& r : refs)
        if (!r.missing && !r.sourcePath.empty())
            out.push_back(r.bspPath + "|" + r.sourcePath);
    return out;
}

}  // namespace pb::publish
