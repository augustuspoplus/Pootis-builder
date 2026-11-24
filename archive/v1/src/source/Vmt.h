#pragma once
#include <map>
#include <string>
#include <vector>

namespace pb::source {

// Flattened view of a .vmt material.
struct Vmt {
    std::string shader;                       // lowercase, e.g. "lightmappedgeneric"
    std::map<std::string, std::string> kv;    // "$basetexture" -> "concrete/foo"
    std::string includePath;                  // for "patch" materials

    std::string get(const std::string& key, const std::string& def = "") const {
        auto it = kv.find(key);
        return it == kv.end() ? def : it->second;
    }
    bool flag(const std::string& key) const {
        auto it = kv.find(key);
        if (it == kv.end()) return false;
        return it->second == "1" || it->second == "true";
    }
};

// Parses VMT text. `patch` includes are represented via Vmt::includePath and a
// pre-merged kv map (replace/insert blocks are folded into kv).
Vmt parseVmt(const std::string& text);

}  // namespace pb::source
