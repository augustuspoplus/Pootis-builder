#include "source/SourceFs.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <filesystem>

#include "core/File.h"
#include "core/Log.h"
#include "source/Vmt.h"

extern "C" {
#include "LzmaDec.h"
}

namespace fs = std::filesystem;

namespace pb::source {
namespace {

void* pakLzmaAlloc(ISzAllocPtr, size_t size) { return std::malloc(size); }
void pakLzmaFree(ISzAllocPtr, void* p) { std::free(p); }
const ISzAlloc g_pakLzmaAlloc = {pakLzmaAlloc, pakLzmaFree};

// Decompress ZIP Method 14 (LZMA): 2-byte version + 2-byte propSize + props + raw LZMA stream.
bool decompressZipLzma(const uint8_t* src, size_t compSize, size_t uncompSize,
                       std::vector<uint8_t>& out) {
    if (!src || compSize < 9 || uncompSize == 0 || uncompSize > (256u << 20)) return false;
    uint16_t propSize = 0;
    std::memcpy(&propSize, src + 2, 2);
    if (propSize != 5 || 4 + static_cast<size_t>(propSize) > compSize) return false;

    const uint8_t* props = src + 4;
    const uint8_t* stream = src + 4 + propSize;
    SizeT srcLen = compSize - 4 - propSize;
    SizeT destLen = uncompSize;
    out.resize(uncompSize);
    ELzmaStatus status = LZMA_STATUS_NOT_SPECIFIED;
    const SRes res = LzmaDecode(out.data(), &destLen, stream, &srcLen, props, 5,
                                LZMA_FINISH_ANY, &status, &g_pakLzmaAlloc);
    if (res != SZ_OK || destLen == 0) {
        out.clear();
        return false;
    }
    out.resize(destLen);
    return true;
}

// Compact RFC 1951 raw DEFLATE (ZIP Method 8) decoder for compressed BSP Pakfiles.
struct BitReader {
    const uint8_t* data;
    size_t size;
    size_t bytePos = 0;
    uint32_t bitBuf = 0;
    int bitCount = 0;

    bool need(int n) {
        while (bitCount < n) {
            if (bytePos >= size) return false;
            bitBuf |= static_cast<uint32_t>(data[bytePos++]) << bitCount;
            bitCount += 8;
        }
        return true;
    }
    uint32_t bits(int n) {
        if (!need(n)) return 0;
        const uint32_t v = bitBuf & ((1u << n) - 1u);
        bitBuf >>= n;
        bitCount -= n;
        return v;
    }
    void alignByte() {
        const int drop = bitCount & 7;
        bitBuf >>= drop;
        bitCount -= drop;
    }
};

struct HuffTable {
    int count[16]{};
    int symbol[288]{};
    bool build(const int* lengths, int n) {
        std::memset(count, 0, sizeof(count));
        for (int i = 0; i < n; ++i)
            if (lengths[i] > 0 && lengths[i] < 16) count[lengths[i]]++;
        int offs[16]{};
        for (int len = 1; len < 15; ++len) offs[len + 1] = offs[len] + count[len];
        for (int i = 0; i < n; ++i)
            if (lengths[i] > 0 && lengths[i] < 16) symbol[offs[lengths[i]]++] = i;
        return true;
    }
    int decode(BitReader& br) const {
        int code = 0, first = 0, index = 0;
        for (int len = 1; len <= 15; ++len) {
            if (!br.need(1)) return -1;
            code |= static_cast<int>(br.bits(1));
            const int c = count[len];
            if (code - c < first) return symbol[index + (code - first)];
            index += c;
            first = (first + c) << 1;
            code <<= 1;
        }
        return -1;
    }
};

bool decompressZipDeflate(const uint8_t* src, size_t compSize, size_t uncompSize,
                          std::vector<uint8_t>& out) {
    static const int kLenBase[29] = {
        3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258};
    static const int kLenExt[29] = {
        0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0};
    static const int kDistBase[30] = {
        1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,
        1025,1537,2049,3073,4097,6145,8193,12289,16385,24577};
    static const int kDistExt[30] = {
        0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13};
    static const int kOrder[19] = {16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15};

    out.clear();
    if (uncompSize > 0 && uncompSize < (256u << 20)) out.reserve(uncompSize);
    BitReader br{src, compSize};
    bool bfinal = false;
    while (!bfinal) {
        if (!br.need(3)) return false;
        bfinal = br.bits(1) != 0;
        const uint32_t btype = br.bits(2);
        if (btype == 0) {
            br.alignByte();
            if (!br.need(32)) return false;
            const uint16_t len = static_cast<uint16_t>(br.bits(16));
            const uint16_t nlen = static_cast<uint16_t>(br.bits(16));
            if ((len ^ 0xFFFFu) != nlen) return false;
            for (uint16_t i = 0; i < len; ++i) {
                if (!br.need(8)) return false;
                out.push_back(static_cast<uint8_t>(br.bits(8)));
            }
        } else if (btype == 1 || btype == 2) {
            HuffTable litLen, distTab;
            int lengths[320]{};
            if (btype == 1) {
                int i = 0;
                for (; i <= 143; ++i) lengths[i] = 8;
                for (; i <= 255; ++i) lengths[i] = 9;
                for (; i <= 279; ++i) lengths[i] = 7;
                for (; i <= 287; ++i) lengths[i] = 8;
                litLen.build(lengths, 288);
                for (int j = 0; j < 30; ++j) lengths[j] = 5;
                distTab.build(lengths, 30);
            } else {
                const int hlit = static_cast<int>(br.bits(5)) + 257;
                const int hdist = static_cast<int>(br.bits(5)) + 1;
                const int hclen = static_cast<int>(br.bits(4)) + 4;
                int clens[19]{};
                for (int i = 0; i < hclen; ++i) clens[kOrder[i]] = static_cast<int>(br.bits(3));
                HuffTable codeTab;
                codeTab.build(clens, 19);
                int idx = 0;
                while (idx < hlit + hdist) {
                    const int sym = codeTab.decode(br);
                    if (sym < 0) return false;
                    if (sym < 16) {
                        lengths[idx++] = sym;
                    } else if (sym == 16) {
                        if (idx == 0) return false;
                        const int rep = static_cast<int>(br.bits(2)) + 3;
                        const int prev = lengths[idx - 1];
                        for (int r = 0; r < rep && idx < hlit + hdist; ++r) lengths[idx++] = prev;
                    } else if (sym == 17) {
                        const int rep = static_cast<int>(br.bits(3)) + 3;
                        for (int r = 0; r < rep && idx < hlit + hdist; ++r) lengths[idx++] = 0;
                    } else if (sym == 18) {
                        const int rep = static_cast<int>(br.bits(7)) + 11;
                        for (int r = 0; r < rep && idx < hlit + hdist; ++r) lengths[idx++] = 0;
                    } else return false;
                }
                litLen.build(lengths, hlit);
                distTab.build(lengths + hlit, hdist);
            }
            for (;;) {
                const int sym = litLen.decode(br);
                if (sym < 0) return false;
                if (sym < 256) {
                    out.push_back(static_cast<uint8_t>(sym));
                } else if (sym == 256) {
                    break;
                } else {
                    const int lc = sym - 257;
                    if (lc < 0 || lc >= 29) return false;
                    const int mlen = kLenBase[lc] + static_cast<int>(br.bits(kLenExt[lc]));
                    const int dc = distTab.decode(br);
                    if (dc < 0 || dc >= 30) return false;
                    const size_t mdist = static_cast<size_t>(kDistBase[dc] + static_cast<int>(br.bits(kDistExt[dc])));
                    if (mdist == 0 || mdist > out.size()) return false;
                    for (int k = 0; k < mlen; ++k) out.push_back(out[out.size() - mdist]);
                }
            }
        } else {
            return false;
        }
    }
    return true;
}

std::string lower(std::string s) {
    for (char& c : s) {
        if (c == '\\') c = '/';
        else c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    return s;
}

const char* kTf2Root =
    "C:/Program Files (x86)/Steam/steamapps/common/Team Fortress 2";

}  // namespace

void SourceFs::addLooseRoot(const std::string& dir) {
    if (fs::exists(dir)) {
        looseRoots_.push_back(dir);
        PB_INFO("SourceFs: loose root %s", dir.c_str());
    }
}

bool SourceFs::addVpk(const std::string& vpkPath) {
    if (!fs::exists(vpkPath)) return false;
    auto v = std::make_unique<Vpk>();
    if (!v->open(vpkPath)) return false;
    vpks_.push_back(std::move(v));
    return true;
}

void SourceFs::clearBspPak() {
    pakBlob_.clear();
    pakEntries_.clear();
}

size_t SourceFs::mountBspPak(const uint8_t* data, size_t size) {
    clearBspPak();
    if (!data || size < 30) return 0;
    pakBlob_.assign(data, data + size);

    auto u16 = [&](size_t off) -> uint16_t {
        uint16_t v = 0;
        std::memcpy(&v, pakBlob_.data() + off, 2);
        return v;
    };
    auto u32 = [&](size_t off) -> uint32_t {
        uint32_t v = 0;
        std::memcpy(&v, pakBlob_.data() + off, 4);
        return v;
    };

    // Locate End of Central Directory (0x06054b50) near the tail of the ZIP.
    size_t eocd = std::string::npos;
    const size_t minPos = size > 65557 ? size - 65557 : 0;
    for (size_t p = size - 22;; --p) {
        if (u32(p) == 0x06054b50u) {
            eocd = p;
            break;
        }
        if (p == minPos) break;
    }
    if (eocd == std::string::npos) return 0;

    const uint16_t entries = u16(eocd + 10);
    const uint32_t cdOff = u32(eocd + 16);
    size_t cur = cdOff;
    for (uint16_t i = 0; i < entries && cur + 46 <= size; ++i) {
        if (u32(cur) != 0x02014b50u) break;
        const uint16_t method = u16(cur + 10);
        const uint32_t compSize = u32(cur + 20);
        const uint32_t uncompSize = u32(cur + 24);
        const uint16_t nameLen = u16(cur + 28);
        const uint16_t extraLen = u16(cur + 30);
        const uint16_t cmtLen = u16(cur + 32);
        const uint32_t localOff = u32(cur + 42);
        if (cur + 46 + nameLen > size) break;

        std::string name(reinterpret_cast<const char*>(pakBlob_.data() + cur + 46),
                         nameLen);
        cur += 46 + nameLen + extraLen + cmtLen;

        // Support STORED (0), DEFLATE (8), AND LZMA (14) used by Valve/community bspzip -repack!
        if ((method != 0 && method != 8 && method != 14) ||
            localOff + 30 > size || u32(localOff) != 0x04034b50u)
            continue;
        const uint16_t lNameLen = u16(localOff + 26);
        const uint16_t lExtraLen = u16(localOff + 28);
        const size_t dataOff = localOff + 30 + lNameLen + lExtraLen;
        if (dataOff + compSize > size) continue;

        std::string key = lower(std::move(name));
        while (!key.empty() && key.front() == '/') key.erase(key.begin());
        if (!key.empty()) pakEntries_[key] = {dataOff, compSize, uncompSize, method};
    }
    if (!pakEntries_.empty())
        PB_INFO("SourceFs: mounted %zu packed BSP pakfile entries", pakEntries_.size());
    return pakEntries_.size();
}

void SourceFs::mountDefaults(const std::string& exeDir) {
    const std::string tf = std::string(kTf2Root) + "/tf";
    const std::string hl2 = std::string(kTf2Root) + "/hl2";

    addLooseRoot(tf);
    addLooseRoot(hl2);
    addVpk(tf + "/tf2_textures_dir.vpk");
    addVpk(tf + "/tf2_misc_dir.vpk");
    addVpk(tf + "/tf2_sound_misc_dir.vpk");
    addVpk(tf + "/tf2_sound_vo_english_dir.vpk");
    addVpk(hl2 + "/hl2_misc_dir.vpk");
    addVpk(hl2 + "/hl2_textures_dir.vpk");
    addVpk(hl2 + "/hl2_sound_misc_dir.vpk");

    // Bundled ABS Mapping Resource Pack (material browser + improved FGD helper models/sprites).
    for (const std::string& base : {exeDir, exeDir + "/..", std::string(".")}) {
        const std::string p1 = base + "/assets/mapping_resource_pack/ABS_MRP_Material_Browser.vpk";
        const std::string p2 = base + "/assets/mapping_resource_pack/ABS_MRP_Improved_FGD.vpk";
        bool any = false;
        if (fs::exists(p1)) { addVpk(p1); any = true; }
        if (fs::exists(p2)) { addVpk(p2); any = true; }
        if (any) break;
    }

    PB_INFO("SourceFs: %zu VPKs, %zu loose roots mounted", vpks_.size(),
            looseRoots_.size());
}

std::optional<std::vector<uint8_t>> SourceFs::read(const std::string& path) const {
    const std::string key = lower(path);
    if (auto it = pakEntries_.find(key); it != pakEntries_.end()) {
        const auto& sp = it->second;
        const uint8_t* ptr = pakBlob_.data() + sp.offset;
        if (sp.method == 0) {
            return std::vector<uint8_t>(ptr, ptr + sp.compSize);
        }
        std::vector<uint8_t> decomp;
        if (sp.method == 14 && decompressZipLzma(ptr, sp.compSize, sp.uncompSize, decomp)) {
            return decomp;
        }
        if (sp.method == 8 && decompressZipDeflate(ptr, sp.compSize, sp.uncompSize, decomp)) {
            return decomp;
        }
    }
    for (const std::string& root : looseRoots_) {
        const std::string full = root + "/" + key;
        if (fs::exists(full)) {
            std::vector<uint8_t> data;
            if (readFile(full, data)) return data;
        }
    }
    for (const auto& v : vpks_) {
        if (auto d = v->read(key)) return d;
    }
    return std::nullopt;
}

namespace {
bool isOfficialVpk(const std::string& p) {
    std::string f = p;
    const size_t sl = f.find_last_of("/\\");
    if (sl != std::string::npos) f = f.substr(sl + 1);
    for (char& c : f) c = static_cast<char>(::tolower((unsigned char)c));
    return f.rfind("tf2_", 0) == 0 || f.rfind("hl2_", 0) == 0;
}
}  // namespace

std::string SourceFs::loosePath(const std::string& path) const {
    const std::string key = lower(path);
    for (const std::string& root : looseRoots_) {
        const std::string full = root + "/" + key;
        std::error_code ec;
        if (fs::exists(full, ec)) return full;
    }
    return {};
}

SourceFs::AssetOrigin SourceFs::assetOrigin(const std::string& path) const {
    const std::string key = lower(path);
    for (const auto& v : vpks_)
        if (isOfficialVpk(v->sourcePath()) && v->contains(key))
            return AssetOrigin::Base;
    if (!loosePath(path).empty()) return AssetOrigin::Custom;
    for (const auto& v : vpks_)
        if (v->contains(key)) return AssetOrigin::Custom;  // a non-official VPK
    return AssetOrigin::Missing;
}

std::vector<std::string> SourceFs::listFiles(const std::string& prefix,
                                            const std::string& ext) const {
    const std::string pfx = lower(prefix);
    const std::string ex = lower(ext);
    std::vector<std::string> out;
    auto want = [&](const std::string& p) {
        return p.size() > ex.size() && p.compare(0, pfx.size(), pfx) == 0 &&
               p.compare(p.size() - ex.size(), ex.size(), ex) == 0;
    };
    for (const auto& v : vpks_)
        for (const auto& [name, entry] : v->entries())
            if (want(name)) out.push_back(name);
    for (const std::string& root : looseRoots_) {
        std::error_code ec;
        const fs::path base = fs::path(root) / pfx;
        if (!fs::is_directory(base, ec)) continue;
        for (auto it = fs::recursive_directory_iterator(base, ec);
             it != fs::recursive_directory_iterator(); it.increment(ec)) {
            if (ec || !it->is_regular_file()) continue;
            std::string rel = lower(fs::relative(it->path(), root, ec).generic_string());
            if (want(rel)) out.push_back(std::move(rel));
        }
    }
    std::sort(out.begin(), out.end());
    out.erase(std::unique(out.begin(), out.end()), out.end());
    return out;
}

VtfImage SourceFs::loadTexture(std::string texRel) const {
    texRel = lower(texRel);
    if (texRel.rfind("materials/", 0) != 0) texRel = "materials/" + texRel;
    if (texRel.size() < 4 || texRel.compare(texRel.size() - 4, 4, ".vtf") != 0)
        texRel += ".vtf";
    auto bytes = read(texRel);
    if (!bytes) return {};
    return decodeVtf(*bytes, texRel.c_str());
}

// VBSP writes per-cubemap patched materials as
// "maps/<mapname>/<original>_<x>_<y>_<z>" and WorldVertexTransition patches as
// "maps/<mapname>/<original>_wvt_patch" inside the BSP pakfile.
// Fall back to the original material when a patch isn't present.
static std::string stripCubemapPatch(const std::string& in) {
    if (in.rfind("maps/", 0) != 0) return in;
    const size_t firstSlash = in.find('/', 5);
    if (firstSlash == std::string::npos) return in;
    std::string rest = in.substr(firstSlash + 1);
    const std::string wvt = "_wvt_patch";
    if (rest.size() > wvt.size() &&
        rest.compare(rest.size() - wvt.size(), wvt.size(), wvt) == 0) {
        rest.erase(rest.size() - wvt.size());
        return rest;
    }
    // Trim three trailing "_<signed int>" groups.
    for (int i = 0; i < 3; ++i) {
        const size_t us = rest.find_last_of('_');
        if (us == std::string::npos) return in;
        const std::string tail = rest.substr(us + 1);
        if (tail.empty()) return in;
        for (size_t k = 0; k < tail.size(); ++k)
            if (!std::isdigit(static_cast<unsigned char>(tail[k])) &&
                !(k == 0 && tail[k] == '-'))
                return in;
        rest.erase(us);
    }
    return rest;
}

ResolvedMaterial SourceFs::resolveMaterial(std::string name) const {
    ResolvedMaterial out;
    name = lower(name);
    if (name.rfind("materials/", 0) == 0) name.erase(0, 10);
    if (name.size() > 4 && name.compare(name.size() - 4, 4, ".vmt") == 0)
        name.erase(name.size() - 4);

    if (!read("materials/" + name + ".vmt")) {
        const std::string stripped = stripCubemapPatch(name);
        if (stripped != name && read("materials/" + stripped + ".vmt")) name = stripped;
    }
    out.isTool = name.rfind("tools/", 0) == 0;

    Vmt vmt;
    std::string cur = "materials/" + name + ".vmt";
    for (int depth = 0; depth < 4; ++depth) {
        auto bytes = read(cur);
        if (!bytes) break;
        Vmt parsed = parseVmt(std::string(bytes->begin(), bytes->end()));
        // Merge: existing keys win only if already set by an outer patch.
        for (auto& [k, v] : parsed.kv) vmt.kv.emplace(k, v);
        if (vmt.shader.empty() || parsed.shader != "patch") vmt.shader = parsed.shader;
        if (parsed.shader == "patch" && !parsed.includePath.empty()) {
            cur = lower(parsed.includePath);
            if (cur.rfind("materials/", 0) != 0) cur = "materials/" + cur;
            if (cur.size() < 4 || cur.compare(cur.size() - 4, 4, ".vmt") != 0) cur += ".vmt";
            out.found = true;
            continue;
        }
        out.found = true;
        break;
    }
    if (!out.found) return out;

    if (vmt.shader != "patch" && !vmt.shader.empty()) out.shader = vmt.shader;

    out.baseTexture = vmt.get("$basetexture");
    if (out.baseTexture.empty()) out.baseTexture = vmt.get("$hdrbasetexture");
    if (out.baseTexture.empty()) out.baseTexture = vmt.get("$hdrcompressedtexture");
    out.baseTexture2 = vmt.get("$basetexture2");
    out.surfaceProp = vmt.get("$surfaceprop");
    out.additive = vmt.flag("$additive");
    out.translucent = vmt.flag("$translucent") || out.additive;
    out.alphaTest = vmt.flag("$alphatest");
    out.noCull = vmt.flag("$nocull");
    out.selfIllum = vmt.flag("$selfillum");
    // Parse VMT $color / $color2 RGB tint (either [r g b] in 0..1 or {r g b} in 0..255)
    std::string colStr = vmt.get("$color2");
    if (colStr.empty()) colStr = vmt.get("$color");
    if (!colStr.empty()) {
        float r = 1.0f, g = 1.0f, b = 1.0f;
        const bool is255 = colStr.find('{') != std::string::npos;
        std::string clean = colStr;
        for (char& ch : clean) {
            if (ch == '[' || ch == ']' || ch == '{' || ch == '}') ch = ' ';
        }
        if (std::sscanf(clean.c_str(), " %f %f %f", &r, &g, &b) == 3) {
            if (is255 || r > 1.5f || g > 1.5f || b > 1.5f) {
                r /= 255.0f; g /= 255.0f; b /= 255.0f;
            }
            out.colorTint[0] = std::clamp(r, 0.05f, 1.5f);
            out.colorTint[1] = std::clamp(g, 0.05f, 1.5f);
            out.colorTint[2] = std::clamp(b, 0.05f, 1.5f);
        }
    }
    if (out.baseTexture.empty()) out.baseTexture = vmt.get("%tooltexture");
    return out;
}

}  // namespace pb::source
