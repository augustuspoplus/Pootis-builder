#include "bsp/BspFile.h"

#include <cstring>
#include <filesystem>

#include "bsp/Lzma.h"
#include "core/File.h"
#include "core/Log.h"

namespace fs = std::filesystem;

namespace pb::bsp {

bool BspFile::load(const std::string& path, std::string* error) {
    auto fail = [&](const std::string& m) {
        if (error) *error = m;
        PB_ERROR("BSP load: %s", m.c_str());
        return false;
    };

    loaded_ = false;
    entities_.clear();
    materialCache_.clear();
    lumpScratch_.clear();
    path_ = path;
    name_ = fs::path(path).stem().string();

    if (!readFile(path, data_)) return fail("cannot read file");
    if (data_.size() < sizeof(Header_t)) return fail("file smaller than BSP header");

    std::memcpy(&header_, data_.data(), sizeof(Header_t));
    if (header_.ident != kBspIdent) return fail("bad magic (not a VBSP file)");
    if (header_.version < 19 || header_.version > 21)
        PB_WARN("BSP version %d is outside the tested 19-21 range", header_.version);

    // Validate lump table against file size.
    for (int i = 0; i < kNumLumps; ++i) {
        const Lump_t& l = header_.lumps[i];
        if (l.filelen < 0 || l.fileofs < 0) return fail("negative lump extent");
        if (l.filelen > 0 &&
            static_cast<size_t>(l.fileofs) + static_cast<size_t>(l.filelen) > data_.size())
            return fail("lump " + std::to_string(i) + " runs past end of file");
    }

    buildTexdataStrings();

    const uint8_t* entPtr = nullptr;
    size_t entLen = 0;
    if (lumpBytes(LUMP_ENTITIES, entPtr, entLen))
        parseEntities(reinterpret_cast<const char*>(entPtr), entLen);

    PB_INFO("Loaded %s  (BSP v%d, %zu entities, rev %d)", name_.c_str(),
            header_.version, entities_.size(), header_.mapRevision);
    loaded_ = true;
    return true;
}

bool BspFile::lumpBytes(int lump, const uint8_t*& ptr, size_t& size) const {
    if (lump < 0 || lump >= kNumLumps) return false;
    const Lump_t& l = header_.lumps[lump];
    if (l.filelen <= 0) return false;

    const uint8_t* raw = data_.data() + l.fileofs;
    const size_t rawLen = static_cast<size_t>(l.filelen);

    // A lump is LZMA-compressed when its fourCC is non-zero *or* the payload
    // itself carries the Valve "LZMA" header (compressed lumps in practice).
    const bool markedCompressed =
        l.fourCC[0] || l.fourCC[1] || l.fourCC[2] || l.fourCC[3];
    if (markedCompressed || isLzmaLump(raw, rawLen)) {
        auto it = lumpScratch_.find(lump);
        if (it == lumpScratch_.end()) {
            std::vector<uint8_t> decoded = decompressLzmaLump(raw, rawLen);
            if (decoded.empty()) {
                PB_WARN("lump %d: LZMA decompression failed", lump);
                return false;
            }
            it = lumpScratch_.emplace(lump, std::move(decoded)).first;
        }
        ptr = it->second.data();
        size = it->second.size();
        return true;
    }

    ptr = raw;
    size = rawLen;
    return true;
}

const uint8_t* BspFile::lighting(size_t& sizeOut, bool& isHdrOut) const {
    const uint8_t* p = nullptr;
    size_t n = 0;
    if (lumpBytes(LUMP_LIGHTING_HDR, p, n) && n > 0) {
        sizeOut = n;
        isHdrOut = true;
        return p;
    }
    if (lumpBytes(LUMP_LIGHTING, p, n) && n > 0) {
        sizeOut = n;
        isHdrOut = false;
        return p;
    }
    sizeOut = 0;
    isHdrOut = false;
    return nullptr;
}

void BspFile::buildTexdataStrings() {
    texStringTable_ = lumpArray<int32_t>(LUMP_TEXDATA_STRING_TABLE);
    const uint8_t* sd = nullptr;
    size_t sdlen = 0;
    if (lumpBytes(LUMP_TEXDATA_STRING_DATA, sd, sdlen)) {
        texStringData_.assign(reinterpret_cast<const char*>(sd),
                              reinterpret_cast<const char*>(sd) + sdlen);
        texStringData_.push_back('\0');
    }
    texData_ = lumpArray<TexData_t>(LUMP_TEXDATA);
}

std::string BspFile::materialName(int texdataIndex) const {
    if (texdataIndex < 0 || texdataIndex >= static_cast<int>(texData_.size()))
        return {};
    auto it = materialCache_.find(texdataIndex);
    if (it != materialCache_.end()) return it->second;

    std::string name;
    const int strId = texData_[texdataIndex].nameStringTableID;
    if (strId >= 0 && strId < static_cast<int>(texStringTable_.size())) {
        const int off = texStringTable_[strId];
        if (off >= 0 && off < static_cast<int>(texStringData_.size()))
            name = std::string(texStringData_.data() + off);
    }
    for (char& c : name) {
        if (c == '\\') c = '/';
        else c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    materialCache_[texdataIndex] = name;
    return name;
}

bool BspFile::texdataDims(int texdataIndex, int& width, int& height) const {
    if (texdataIndex < 0 || texdataIndex >= static_cast<int>(texData_.size()))
        return false;
    width = texData_[texdataIndex].width;
    height = texData_[texdataIndex].height;
    return width > 0 && height > 0;
}

void BspFile::parseEntities(const char* text, size_t len) {
    size_t i = 0;
    auto skipWs = [&] {
        while (i < len && (text[i] == ' ' || text[i] == '\t' || text[i] == '\r' ||
                           text[i] == '\n'))
            ++i;
    };
    auto readQuoted = [&](std::string& out) -> bool {
        if (i >= len || text[i] != '"') return false;
        ++i;
        const size_t start = i;
        while (i < len && text[i] != '"') ++i;
        out.assign(text + start, i - start);
        if (i < len) ++i;  // closing quote
        return true;
    };

    while (i < len) {
        skipWs();
        if (i >= len) break;
        if (text[i] != '{') {
            ++i;
            continue;
        }
        ++i;  // '{'
        Entity ent;
        while (i < len) {
            skipWs();
            if (i < len && text[i] == '}') {
                ++i;
                break;
            }
            std::string key, value;
            if (!readQuoted(key)) break;
            skipWs();
            if (!readQuoted(value)) break;
            ent[key] = value;
        }
        if (!ent.empty()) entities_.push_back(std::move(ent));
    }
}

}  // namespace pb::bsp
