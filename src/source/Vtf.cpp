#include "source/Vtf.h"

#include <algorithm>
#include <cstring>

#include "core/Log.h"

namespace pb::source {
namespace {

enum Fmt {
    RGBA8888 = 0,
    ABGR8888 = 1,
    RGB888 = 2,
    BGR888 = 3,
    RGB565 = 4,
    I8 = 5,
    IA88 = 6,
    P8 = 7,
    A8 = 8,
    RGB888_BLUE = 9,
    BGR888_BLUE = 10,
    ARGB8888 = 11,
    BGRA8888 = 12,
    DXT1 = 13,
    DXT3 = 14,
    DXT5 = 15,
    BGRX8888 = 16,
    BGR565 = 17,
    BGRX5551 = 18,
    BGRA4444 = 19,
    DXT1_A1 = 20,
    BGRA5551 = 21,
    UV88 = 22,
};

constexpr uint32_t VTF_FLAG_ENVMAP = 0x4000;

size_t blockSize(uint32_t fmt) {
    switch (fmt) {
        case DXT1:
        case DXT1_A1: return 8;
        case DXT3:
        case DXT5: return 16;
        default: return 0;
    }
}

size_t bppBytes(uint32_t fmt) {
    switch (fmt) {
        case RGBA8888:
        case ABGR8888:
        case ARGB8888:
        case BGRA8888:
        case BGRX8888: return 4;
        case RGB888:
        case BGR888:
        case RGB888_BLUE:
        case BGR888_BLUE: return 3;
        case RGB565:
        case BGR565:
        case IA88:
        case UV88:
        case BGRX5551:
        case BGRA4444:
        case BGRA5551: return 2;
        case I8:
        case A8:
        case P8: return 1;
        default: return 0;
    }
}

size_t imageBytes(uint32_t fmt, int w, int h) {
    if (size_t bs = blockSize(fmt)) {
        const int bw = (w + 3) / 4, bh = (h + 3) / 4;
        return static_cast<size_t>(std::max(bw, 1)) * std::max(bh, 1) * bs;
    }
    return static_cast<size_t>(w) * h * bppBytes(fmt);
}

void decodeDXTColorBlock(const uint8_t* b, uint8_t out[16][4], bool dxt1) {
    uint16_t c0 = b[0] | (b[1] << 8);
    uint16_t c1 = b[2] | (b[3] << 8);
    auto expand = [](uint16_t c, uint8_t rgb[3]) {
        rgb[0] = static_cast<uint8_t>(((c >> 11) & 0x1f) * 255 / 31);
        rgb[1] = static_cast<uint8_t>(((c >> 5) & 0x3f) * 255 / 63);
        rgb[2] = static_cast<uint8_t>((c & 0x1f) * 255 / 31);
    };
    uint8_t p[4][4];
    expand(c0, p[0]);
    expand(c1, p[1]);
    p[0][3] = p[1][3] = 255;
    if (!dxt1 || c0 > c1) {
        for (int k = 0; k < 3; ++k) {
            p[2][k] = static_cast<uint8_t>((2 * p[0][k] + p[1][k]) / 3);
            p[3][k] = static_cast<uint8_t>((p[0][k] + 2 * p[1][k]) / 3);
        }
        p[2][3] = p[3][3] = 255;
    } else {
        for (int k = 0; k < 3; ++k)
            p[2][k] = static_cast<uint8_t>((p[0][k] + p[1][k]) / 2);
        p[2][3] = 255;
        p[3][0] = p[3][1] = p[3][2] = p[3][3] = 0;
    }
    uint32_t bits = b[4] | (b[5] << 8) | (b[6] << 16) | (b[7] << 24);
    for (int i = 0; i < 16; ++i) {
        const int idx = (bits >> (2 * i)) & 3;
        std::memcpy(out[i], p[idx], 4);
    }
}

// Decodes one 4x4 block into `dst` (RGBA8) at (bx*4, by*4) of a w*h image.
void blitBlock(uint8_t rgba[16][4], std::vector<uint8_t>& dst, int w, int h, int bx,
               int by) {
    for (int py = 0; py < 4; ++py) {
        const int y = by * 4 + py;
        if (y >= h) break;
        for (int px = 0; px < 4; ++px) {
            const int x = bx * 4 + px;
            if (x >= w) break;
            std::memcpy(&dst[(static_cast<size_t>(y) * w + x) * 4], rgba[py * 4 + px], 4);
        }
    }
}

bool decodeMip(uint32_t fmt, const uint8_t* src, size_t srcLen, int w, int h,
               std::vector<uint8_t>& out) {
    out.assign(static_cast<size_t>(w) * h * 4, 255);
    if (imageBytes(fmt, w, h) > srcLen) return false;

    if (fmt == DXT1 || fmt == DXT1_A1 || fmt == DXT3 || fmt == DXT5) {
        const int bw = (w + 3) / 4, bh = (h + 3) / 4;
        const size_t stride = blockSize(fmt);
        const uint8_t* p = src;
        for (int by = 0; by < bh; ++by) {
            for (int bx = 0; bx < bw; ++bx) {
                uint8_t rgba[16][4];
                if (fmt == DXT1 || fmt == DXT1_A1) {
                    decodeDXTColorBlock(p, rgba, true);
                } else if (fmt == DXT3) {
                    decodeDXTColorBlock(p + 8, rgba, false);
                    for (int i = 0; i < 16; ++i) {
                        const int nib = (p[i / 2] >> ((i & 1) * 4)) & 0xf;
                        rgba[i][3] = static_cast<uint8_t>(nib * 17);
                    }
                } else {  // DXT5
                    decodeDXTColorBlock(p + 8, rgba, false);
                    uint8_t a0 = p[0], a1 = p[1];
                    uint8_t at[8] = {a0, a1};
                    if (a0 > a1) {
                        for (int k = 1; k < 7; ++k)
                            at[k + 1] = static_cast<uint8_t>(((7 - k) * a0 + k * a1) / 7);
                    } else {
                        for (int k = 1; k < 5; ++k)
                            at[k + 1] = static_cast<uint8_t>(((5 - k) * a0 + k * a1) / 5);
                        at[6] = 0;
                        at[7] = 255;
                    }
                    uint64_t bits = 0;
                    for (int k = 0; k < 6; ++k) bits |= static_cast<uint64_t>(p[2 + k]) << (8 * k);
                    for (int i = 0; i < 16; ++i)
                        rgba[i][3] = at[(bits >> (3 * i)) & 7];
                }
                blitBlock(rgba, out, w, h, bx, by);
                p += stride;
            }
        }
        return true;
    }

    const size_t n = static_cast<size_t>(w) * h;
    auto px = [&](size_t i) { return src + i * bppBytes(fmt); };
    switch (fmt) {
        case BGRA8888:
        case BGRX8888:
            for (size_t i = 0; i < n; ++i) {
                const uint8_t* s = px(i);
                out[i * 4 + 0] = s[2];
                out[i * 4 + 1] = s[1];
                out[i * 4 + 2] = s[0];
                out[i * 4 + 3] = (fmt == BGRX8888) ? 255 : s[3];
            }
            return true;
        case RGBA8888:
            std::memcpy(out.data(), src, n * 4);
            return true;
        case ABGR8888:
            for (size_t i = 0; i < n; ++i) {
                const uint8_t* s = px(i);
                out[i * 4 + 0] = s[3];
                out[i * 4 + 1] = s[2];
                out[i * 4 + 2] = s[1];
                out[i * 4 + 3] = s[0];
            }
            return true;
        case ARGB8888:
            for (size_t i = 0; i < n; ++i) {
                const uint8_t* s = px(i);
                out[i * 4 + 0] = s[1];
                out[i * 4 + 1] = s[2];
                out[i * 4 + 2] = s[3];
                out[i * 4 + 3] = s[0];
            }
            return true;
        case RGB888:
            for (size_t i = 0; i < n; ++i) {
                const uint8_t* s = px(i);
                out[i * 4 + 0] = s[0];
                out[i * 4 + 1] = s[1];
                out[i * 4 + 2] = s[2];
                out[i * 4 + 3] = 255;
            }
            return true;
        case BGR888:
            for (size_t i = 0; i < n; ++i) {
                const uint8_t* s = px(i);
                out[i * 4 + 0] = s[2];
                out[i * 4 + 1] = s[1];
                out[i * 4 + 2] = s[0];
                out[i * 4 + 3] = 255;
            }
            return true;
        case RGB565:
        case BGR565:
            for (size_t i = 0; i < n; ++i) {
                const uint8_t* s = px(i);
                uint16_t v = s[0] | (s[1] << 8);
                uint8_t r = ((v >> 11) & 0x1f) * 255 / 31;
                uint8_t g = ((v >> 5) & 0x3f) * 255 / 63;
                uint8_t b = (v & 0x1f) * 255 / 31;
                if (fmt == BGR565) std::swap(r, b);
                out[i * 4 + 0] = r;
                out[i * 4 + 1] = g;
                out[i * 4 + 2] = b;
                out[i * 4 + 3] = 255;
            }
            return true;
        case I8:
            for (size_t i = 0; i < n; ++i) {
                out[i * 4 + 0] = out[i * 4 + 1] = out[i * 4 + 2] = src[i];
                out[i * 4 + 3] = 255;
            }
            return true;
        case IA88:
            for (size_t i = 0; i < n; ++i) {
                out[i * 4 + 0] = out[i * 4 + 1] = out[i * 4 + 2] = src[i * 2];
                out[i * 4 + 3] = src[i * 2 + 1];
            }
            return true;
        case A8:
            for (size_t i = 0; i < n; ++i) {
                out[i * 4 + 0] = out[i * 4 + 1] = out[i * 4 + 2] = 255;
                out[i * 4 + 3] = src[i];
            }
            return true;
        case UV88:
            for (size_t i = 0; i < n; ++i) {
                out[i * 4 + 0] = src[i * 2];
                out[i * 4 + 1] = src[i * 2 + 1];
                out[i * 4 + 2] = 255;
                out[i * 4 + 3] = 255;
            }
            return true;
        default: return false;
    }
}

}  // namespace

VtfImage decodeVtf(const std::vector<uint8_t>& bytes, const char* debugName) {
    VtfImage img;
    if (bytes.size() < 64 || std::memcmp(bytes.data(), "VTF\0", 4) != 0) {
        PB_WARN("VTF: bad header (%s)", debugName);
        return img;
    }
    const uint8_t* p = bytes.data();
    auto u32 = [&](size_t o) {
        uint32_t v;
        std::memcpy(&v, p + o, 4);
        return v;
    };
    auto u16 = [&](size_t o) {
        uint16_t v;
        std::memcpy(&v, p + o, 2);
        return v;
    };

    const uint32_t vMajor = u32(4), vMinor = u32(8);
    const uint32_t headerSize = u32(12);
    int width = u16(16), height = u16(18);
    const uint32_t flags = u32(20);
    const uint16_t frames = std::max<uint16_t>(1, u16(24));
    uint8_t mipCount = p[56];
    const uint32_t highFmt = u32(52);
    const uint32_t lowFmt = u32(57);
    const uint8_t lowW = p[61], lowH = p[62];
    (void)vMajor;

    for (int i = 0; i < 3; ++i)
        std::memcpy(&img.reflectivity[i], p + 32 + 4 * i, 4);

    if (width <= 0 || height <= 0 || width > 16384 || height > 16384) return img;
    if (flags & VTF_FLAG_ENVMAP) {
        PB_WARN("VTF: cubemap not decoded (%s)", debugName);
        return img;
    }
    if (mipCount == 0) mipCount = 1;

    // Locate the start of the high-res image data.
    size_t dataStart = headerSize;
    if (vMinor >= 3) {
        const uint32_t numRes = u32(68);
        bool found = false;
        for (uint32_t r = 0; r < numRes && 80 + r * 8 + 8 <= bytes.size(); ++r) {
            const uint8_t* e = p + 80 + r * 8;
            if (e[0] == 0x30 && e[1] == 0x00 && e[2] == 0x00) {
                std::memcpy(&dataStart, e + 4, 4);
                found = true;
                break;
            }
        }
        if (!found) dataStart = headerSize;
    } else if (lowFmt != 0xffffffffu && lowW && lowH) {
        dataStart += imageBytes(lowFmt, lowW, lowH);
    }
    if (dataStart >= bytes.size()) return img;

    // Mips are stored smallest -> largest, `frames` copies each.
    auto mipDim = [](int base, int level) {
        return std::max(1, base >> level);
    };
    size_t offset = dataStart;
    const size_t avail = bytes.size();
    size_t mip0Offset = 0;
    bool have = false;
    for (int level = mipCount - 1; level >= 0; --level) {
        const int mw = mipDim(width, level), mh = mipDim(height, level);
        const size_t one = imageBytes(highFmt, mw, mh);
        for (int f = 0; f < frames; ++f) {
            if (level == 0 && f == 0) {
                mip0Offset = offset;
                have = true;
            }
            offset += one;
            if (offset > avail) {
                // Truncated file: if we already recorded mip0 use it anyway.
                if (have) break;
                return img;
            }
        }
    }
    if (!have) return img;

    std::vector<uint8_t> rgba;
    if (!decodeMip(highFmt, p + mip0Offset, avail - mip0Offset, width, height, rgba)) {
        PB_WARN("VTF: unsupported format %u (%s)", highFmt, debugName);
        return img;
    }
    img.width = width;
    img.height = height;
    img.rgba = std::move(rgba);
    img.hasAlpha = (highFmt == DXT3 || highFmt == DXT5 || highFmt == BGRA8888 ||
                    highFmt == RGBA8888 || highFmt == ABGR8888 || highFmt == ARGB8888 ||
                    highFmt == A8 || highFmt == IA88 || highFmt == DXT1_A1);
    return img;
}

}  // namespace pb::source
