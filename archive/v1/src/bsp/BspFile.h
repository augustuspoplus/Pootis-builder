#pragma once
#include <cstdint>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

#include "bsp/BspFormat.h"

namespace pb::bsp {

using Entity = std::unordered_map<std::string, std::string>;

// Loads a Source .bsp into memory and gives typed, bounds-checked views over
// the lumps that the renderer needs.
class BspFile {
public:
    bool load(const std::string& path, std::string* error = nullptr);

    bool loaded() const { return loaded_; }
    int version() const { return header_.version; }
    const std::string& path() const { return path_; }
    const std::string& name() const { return name_; }

    // Typed lump accessors (empty span if the lump is missing/compressed).
    template <class T>
    std::vector<T> lumpArray(int lump) const {
        const uint8_t* p = nullptr;
        size_t bytes = 0;
        if (!lumpBytes(lump, p, bytes) || bytes < sizeof(T)) return {};
        std::vector<T> out(bytes / sizeof(T));
        std::memcpy(out.data(), p, out.size() * sizeof(T));
        return out;
    }

    bool lumpBytes(int lump, const uint8_t*& ptr, size_t& size) const;

    // Whole-file view (game lump static-prop offsets are file-absolute).
    const uint8_t* fileData() const { return data_.data(); }
    size_t fileSize() const { return data_.size(); }
    int lumpOffset(int lump) const {
        return (lump >= 0 && lump < kNumLumps) ? header_.lumps[lump].fileofs : 0;
    }
    int lumpLength(int lump) const {
        return (lump >= 0 && lump < kNumLumps) ? header_.lumps[lump].filelen : 0;
    }

    // Raw lightmap lump (HDR preferred when present).
    const uint8_t* lighting(size_t& sizeOut, bool& isHdrOut) const;

    // texdata string resolved to a material path, lowercase, forward slashes.
    std::string materialName(int texdataIndex) const;

    // Material texture dimensions vbsp used when it baked texture UVs.
    bool texdataDims(int texdataIndex, int& width, int& height) const;

    const std::vector<Entity>& entities() const { return entities_; }
    const Entity* worldspawn() const {
        return entities_.empty() ? nullptr : &entities_.front();
    }

private:
    void parseEntities(const char* text, size_t len);
    void buildTexdataStrings();

    bool loaded_ = false;
    std::string path_;
    std::string name_;
    std::vector<uint8_t> data_;
    Header_t header_{};

    // Lazily-decompressed storage for LZMA-compressed lumps, keyed by lump id.
    mutable std::unordered_map<int, std::vector<uint8_t>> lumpScratch_;

    std::vector<int32_t> texStringTable_;
    std::vector<char> texStringData_;
    std::vector<TexData_t> texData_;
    mutable std::unordered_map<int, std::string> materialCache_;

    std::vector<Entity> entities_;
};

}  // namespace pb::bsp
