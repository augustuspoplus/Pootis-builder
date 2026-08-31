#include "source/Vpk.h"

#include <algorithm>
#include <cstring>
#include <fstream>

#include "core/File.h"
#include "core/Log.h"

namespace pb::source {
namespace {
constexpr uint32_t kVpkSignature = 0x55aa1234u;
constexpr uint16_t kInlineArchive = 0x7fffu;
}  // namespace

std::string Vpk::normalise(std::string s) {
    for (char& c : s) {
        if (c == '\\') c = '/';
        else c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    if (!s.empty() && s.front() == '/') s.erase(s.begin());
    return s;
}

bool Vpk::open(const std::string& path) {
    entries_.clear();
    path_ = path;

    std::vector<uint8_t> data;
    if (!readFile(path, data) || data.size() < 12) {
        PB_WARN("VPK: cannot read %s", path.c_str());
        return false;
    }

    const uint8_t* p = data.data();
    auto u32 = [&](size_t off) {
        uint32_t v;
        std::memcpy(&v, p + off, 4);
        return v;
    };

    if (u32(0) != kVpkSignature) {
        PB_WARN("VPK: bad signature in %s", path.c_str());
        return false;
    }
    const uint32_t version = u32(4);
    const uint32_t treeSize = u32(8);
    const size_t headerSize = (version == 2) ? 28 : 12;
    if (version != 1 && version != 2) {
        PB_WARN("VPK: unsupported version %u", version);
        return false;
    }
    if (headerSize + treeSize > data.size()) {
        PB_WARN("VPK: tree runs past EOF in %s", path.c_str());
        return false;
    }
    treeOffset_ = static_cast<uint32_t>(headerSize + treeSize);

    // "<prefix>_dir.vpk" -> "<prefix>", else strip ".vpk".
    if (path.size() > 8 && path.compare(path.size() - 8, 8, "_dir.vpk") == 0)
        archivePrefix_ = path.substr(0, path.size() - 8);
    else if (path.size() > 4 && path.compare(path.size() - 4, 4, ".vpk") == 0)
        archivePrefix_ = path.substr(0, path.size() - 4);
    else
        archivePrefix_ = path;

    size_t i = headerSize;
    const size_t treeEnd = headerSize + treeSize;
    auto readStr = [&](std::string& out) -> bool {
        const size_t start = i;
        while (i < treeEnd && p[i] != '\0') ++i;
        if (i >= treeEnd) return false;
        out.assign(reinterpret_cast<const char*>(p + start), i - start);
        ++i;  // skip NUL
        return true;
    };

    while (i < treeEnd) {
        std::string ext;
        if (!readStr(ext) || ext.empty()) break;
        while (i < treeEnd) {
            std::string dir;
            if (!readStr(dir) || dir.empty()) break;
            while (i < treeEnd) {
                std::string name;
                if (!readStr(name) || name.empty()) break;
                if (i + 18 > treeEnd) return false;

                Entry e;
                e.crc = u32(i);
                uint16_t preloadBytes;
                std::memcpy(&preloadBytes, p + i + 4, 2);
                std::memcpy(&e.archiveIndex, p + i + 6, 2);
                e.offset = u32(i + 8);
                e.length = u32(i + 12);
                // uint16 terminator at i+16
                i += 18;
                if (preloadBytes) {
                    if (i + preloadBytes > data.size()) return false;
                    e.preload.assign(p + i, p + i + preloadBytes);
                    i += preloadBytes;
                }

                std::string full = (dir == " ") ? name : dir + "/" + name;
                full += "." + ext;
                entries_.emplace(normalise(std::move(full)), std::move(e));
            }
        }
    }

    PB_INFO("VPK mounted: %s (%zu files)", path.c_str(), entries_.size());
    return !entries_.empty();
}

std::string Vpk::archivePathFor(uint16_t archiveIndex) const {
    char suffix[16];
    std::snprintf(suffix, sizeof(suffix), "_%03u.vpk", archiveIndex);
    return archivePrefix_ + suffix;
}

std::optional<std::vector<uint8_t>> Vpk::read(const std::string& vpkPath) const {
    auto it = entries_.find(normalise(vpkPath));
    if (it == entries_.end()) return std::nullopt;
    const Entry& e = it->second;

    std::vector<uint8_t> out = e.preload;
    if (e.length == 0) return out;

    std::string archive;
    uint64_t base = 0;
    if (e.archiveIndex == kInlineArchive) {
        archive = path_;
        base = treeOffset_;
    } else {
        archive = archivePathFor(e.archiveIndex);
        base = 0;
    }

    std::ifstream f(archive, std::ios::binary);
    if (!f) {
        PB_WARN("VPK: missing archive %s", archive.c_str());
        return std::nullopt;
    }
    f.seekg(static_cast<std::streamoff>(base + e.offset), std::ios::beg);
    const size_t head = out.size();
    out.resize(head + e.length);
    if (!f.read(reinterpret_cast<char*>(out.data() + head), e.length)) {
        PB_WARN("VPK: short read for %s", vpkPath.c_str());
        return std::nullopt;
    }
    return out;
}

}  // namespace pb::source
