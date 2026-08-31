#pragma once
#include <cstdint>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace pb::source {

// Reader for Valve VPK v1/v2 archives, including single-file VPKs (archive
// index 0x7fff) and multi-part `_dir.vpk` + `_NNN.vpk` sets.
class Vpk {
public:
    struct Entry {
        uint32_t crc = 0;
        uint16_t archiveIndex = 0;
        uint32_t offset = 0;   // within the archive (or after the tree for 0x7fff)
        uint32_t length = 0;
        std::vector<uint8_t> preload;
    };

    // `path` may be the `_dir.vpk` or a plain `.vpk`.
    bool open(const std::string& path);

    bool contains(const std::string& vpkPath) const {
        return entries_.count(normalise(vpkPath)) != 0;
    }
    std::optional<std::vector<uint8_t>> read(const std::string& vpkPath) const;

    const std::map<std::string, Entry>& entries() const { return entries_; }
    const std::string& sourcePath() const { return path_; }

    static std::string normalise(std::string s);

private:
    std::string archivePathFor(uint16_t archiveIndex) const;

    std::string path_;
    std::string archivePrefix_;  // ".../foo" for ".../foo_dir.vpk"
    uint32_t treeOffset_ = 0;    // offset of file data for 0x7fff entries
    std::map<std::string, Entry> entries_;
};

}  // namespace pb::source
