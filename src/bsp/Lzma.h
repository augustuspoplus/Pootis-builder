#pragma once
#include <cstdint>
#include <vector>

namespace pb::bsp {

// True when `data` starts with the Valve LZMA lump header ("LZMA" magic).
bool isLzmaLump(const uint8_t* data, size_t size);

// Decompresses a Source-engine LZMA-compressed lump: a 17-byte Valve header
// (id, uncompressed size, compressed size, 5 LZMA property bytes) followed by
// the raw LZMA stream. Returns an empty vector on any failure.
std::vector<uint8_t> decompressLzmaLump(const uint8_t* data, size_t size);

}  // namespace pb::bsp
