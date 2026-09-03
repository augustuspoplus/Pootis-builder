#pragma once
#include <memory>
#include <optional>
#include <string>
#include <vector>

#include "source/Vpk.h"
#include "source/Vtf.h"

namespace pb::source {

struct ResolvedMaterial {
    bool found = false;
    std::string shader;
    std::string baseTexture;
    std::string baseTexture2;   // WorldVertexTransition blend
    std::string toolTexture;    // %tooltexture / %compilewireframe fallbacks
    std::string surfaceProp;
    bool translucent = false;
    bool alphaTest = false;
    bool noCull = false;
    bool selfIllum = false;
    bool isTool = false;        // tools/ material (nodraw, clip, ...)
};

// Read-only mount stack over the installed game's VPKs + loose files + the ABS
// Mapping Resource Pack. All lookups are case-insensitive, `/`-separated,
// rooted at the game dir (so paths look like "materials/dev/foo.vtf").
class SourceFs {
public:
    void addLooseRoot(const std::string& dir);
    bool addVpk(const std::string& vpkPath);

    // Mounts the installed TF2 content and the bundled ABS pack (exeDir is used
    // to find assets/mapping_resource_pack/). Safe to call when TF2 is absent.
    void mountDefaults(const std::string& exeDir);

    bool ready() const { return !vpks_.empty() || !looseRoots_.empty(); }

    std::optional<std::vector<uint8_t>> read(const std::string& path) const;

    // All mounted files under `prefix` (e.g. "models/props") ending in `ext`
    // (e.g. ".mdl"), de-duplicated and sorted. For the model / asset browsers.
    std::vector<std::string> listFiles(const std::string& prefix,
                                       const std::string& ext) const;

    enum class AssetOrigin { Missing, Base, Custom };
    // Where a "materials/…vtf" / "models/…mdl" / "sound/…" path lives:
    //   Base    — in an official game VPK (every player already has it)
    //   Custom  — only loose, or in a non-official VPK (needs bspzip packing)
    //   Missing — not found anywhere (a broken reference)
    AssetOrigin assetOrigin(const std::string& path) const;
    // Absolute path of the loose file backing `path`, or "" if it isn't loose.
    std::string loosePath(const std::string& path) const;

    // name: material path without "materials/" prefix or ".vmt" suffix.
    ResolvedMaterial resolveMaterial(std::string name) const;

    // texRel: e.g. "concrete/concretefloor001a" (no "materials/", no ".vtf").
    VtfImage loadTexture(std::string texRel) const;

    size_t vpkCount() const { return vpks_.size(); }

private:
    std::vector<std::unique_ptr<Vpk>> vpks_;
    std::vector<std::string> looseRoots_;
};

}  // namespace pb::source
