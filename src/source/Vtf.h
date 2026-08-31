#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace pb::source {

struct VtfImage {
    int width = 0;
    int height = 0;
    std::vector<uint8_t> rgba;  // width*height*4, top-left origin
    bool hasAlpha = false;
    float reflectivity[3] = {0.5f, 0.5f, 0.5f};
    bool ok() const { return width > 0 && height > 0 && !rgba.empty(); }
};

// Decodes the largest mip of a VTF (v7.1–7.5) to RGBA8. Handles DXT1/3/5 and
// the common uncompressed layouts; returns !ok() for anything unsupported.
VtfImage decodeVtf(const std::vector<uint8_t>& bytes, const char* debugName = "");

}  // namespace pb::source
