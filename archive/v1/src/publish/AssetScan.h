#pragma once
#include <string>
#include <vector>

namespace pb::map {
class MapDocument;
}
namespace pb::source {
class SourceFs;
}

namespace pb::publish {

// One asset the map references that isn't part of the base game — either a
// loose/custom file that must be bspzip'd into the .bsp, or a broken reference.
struct AssetRef {
    enum Kind { Material, Texture, Model, Sound };
    Kind kind = Material;
    std::string bspPath;     // internal path, e.g. "materials/foo/bar.vtf"
    std::string sourcePath;  // absolute loose file, or "" when missing
    bool missing = false;    // referenced but found nowhere
};

// Walk `doc` for every material / texture / model / sound it references and
// return the ones SourceFs classifies as Custom or Missing (base-game assets
// are dropped). De-duplicated, sorted by bspPath.
std::vector<AssetRef> scanCustomAssets(const map::MapDocument& doc,
                                       source::SourceFs& fs);

// "<bspPath>|<sourcePath>" for each non-missing entry — the shape
// CompileOptions::packFiles expects.
std::vector<std::string> toPackList(const std::vector<AssetRef>& refs);

}  // namespace pb::publish
