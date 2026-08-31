#include "bsp/Lzma.h"

#include <cstring>

#include "core/Log.h"

extern "C" {
#include "LzmaDec.h"
}

namespace pb::bsp {
namespace {

// Valve's lump header: 'A''M''Z''L' little-endian == "LZMA" bytes in file.
constexpr uint32_t kLzmaId = 0x414D5A4Cu;
constexpr size_t kHeaderSize = 17;  // 4 id + 4 actualSize + 4 lzmaSize + 5 props

void* szAlloc(ISzAllocPtr, size_t size) { return std::malloc(size); }
void szFree(ISzAllocPtr, void* p) { std::free(p); }
const ISzAlloc g_alloc = {szAlloc, szFree};

uint32_t rd32(const uint8_t* p) {
    uint32_t v;
    std::memcpy(&v, p, 4);
    return v;
}

}  // namespace

bool isLzmaLump(const uint8_t* data, size_t size) {
    return data && size >= kHeaderSize && rd32(data) == kLzmaId;
}

std::vector<uint8_t> decompressLzmaLump(const uint8_t* data, size_t size) {
    if (!isLzmaLump(data, size)) return {};

    const uint32_t actualSize = rd32(data + 4);
    const uint32_t lzmaSize = rd32(data + 8);
    const uint8_t* props = data + 12;  // 5 bytes
    const uint8_t* stream = data + kHeaderSize;

    if (kHeaderSize + static_cast<size_t>(lzmaSize) > size) {
        PB_WARN("LZMA lump: stream (%u) longer than lump (%zu)", lzmaSize, size);
        return {};
    }
    if (actualSize == 0 || actualSize > (512u << 20)) {
        PB_WARN("LZMA lump: implausible uncompressed size %u", actualSize);
        return {};
    }

    std::vector<uint8_t> out(actualSize);
    SizeT destLen = actualSize;
    SizeT srcLen = lzmaSize;
    ELzmaStatus status = LZMA_STATUS_NOT_SPECIFIED;

    const SRes res = LzmaDecode(out.data(), &destLen, stream, &srcLen, props, 5,
                                LZMA_FINISH_END, &status, &g_alloc);
    if (res != SZ_OK || destLen != actualSize) {
        PB_WARN("LZMA lump: decode failed (res=%d, got %zu/%u)", res,
                static_cast<size_t>(destLen), actualSize);
        return {};
    }
    return out;
}

}  // namespace pb::bsp
