#include "model/StudioModel.h"

#include <cmath>
#include <cstring>
#include <map>
#include <unordered_map>

#include <glm/gtc/matrix_transform.hpp>

#include "bsp/BspMesh.h"
#include "core/Log.h"
#include "source/SourceFs.h"

namespace pb::model {
namespace {

// ---- little-endian POD readers ------------------------------------------------
template <class T>
T rd(const uint8_t* p) {
    T v;
    std::memcpy(&v, p, sizeof(T));
    return v;
}
int32_t i32(const uint8_t* b, size_t o) { return rd<int32_t>(b + o); }
int16_t i16(const uint8_t* b, size_t o) { return rd<int16_t>(b + o); }
float f32(const uint8_t* b, size_t o) { return rd<float>(b + o); }

std::string cstr(const uint8_t* b, size_t o, size_t cap) {
    const char* s = reinterpret_cast<const char*>(b + o);
    return std::string(s, ::strnlen(s, cap));
}

std::string lower(std::string s) {
    for (auto& c : s) c = (char)::tolower((unsigned char)c);
    return s;
}
std::string norm(std::string s) {
    for (auto& c : s) if (c == '\\') c = '/';
    return lower(std::move(s));
}

// ---- VVD: LOD-0 vertex array (pos/normal/uv), fixups applied ----------------
bool parseVvd(const std::vector<uint8_t>& d, std::vector<StudioVertex>& out) {
    if (d.size() < 64) return false;
    if (i32(d.data(), 0) != 0x56534449) return false;  // 'IDSV'
    const int numLODs = i32(d.data(), 12);
    if (numLODs < 1) return false;
    const int lod0Count = i32(d.data(), 16);
    const int numFixups = i32(d.data(), 48);
    const int fixupStart = i32(d.data(), 52);
    const int vertStart = i32(d.data(), 56);
    if (lod0Count <= 0 || lod0Count > 2000000) return false;

    auto readVert = [&](int idx) -> StudioVertex {
        const size_t o = (size_t)vertStart + (size_t)idx * 48;
        StudioVertex v;
        if (o + 48 > d.size()) return v;
        v.pos = {f32(d.data(), o + 16), f32(d.data(), o + 20), f32(d.data(), o + 24)};
        v.normal = {f32(d.data(), o + 28), f32(d.data(), o + 32), f32(d.data(), o + 36)};
        v.uv = {f32(d.data(), o + 40), f32(d.data(), o + 44)};
        return v;
    };

    out.clear();
    if (numFixups <= 0) {
        out.reserve(lod0Count);
        for (int i = 0; i < lod0Count; ++i) out.push_back(readVert(i));
        return true;
    }
    for (int f = 0; f < numFixups; ++f) {
        const size_t fo = (size_t)fixupStart + (size_t)f * 12;
        if (fo + 12 > d.size()) break;
        const int flod = i32(d.data(), fo);
        const int src = i32(d.data(), fo + 4);
        const int n = i32(d.data(), fo + 8);
        if (flod < 0) continue;  // fixup applies to LOD 0 when lod >= 0
        for (int i = 0; i < n; ++i) out.push_back(readVert(src + i));
    }
    return !out.empty();
}

// ---- MDL: material names + bodypart/model/mesh table -----------------------
struct MdlMesh {
    int material;      // index into skinref[0]
    int vertexoffset;  // relative to its model's vertex block
    int numvertices;
};
struct MdlModel {
    int vertexBase;    // running VVD base for this model
    std::vector<MdlMesh> meshes;
};

struct MdlInfo {
    std::vector<std::string> materials;  // cdmaterial-prefixed, normalised, no ext
    std::vector<MdlModel> models;        // flattened over all bodyparts
    int version = 0;
};

bool parseMdl(const std::vector<uint8_t>& d, MdlInfo& out) {
    if (d.size() < 240) return false;
    if (i32(d.data(), 0) != 0x54534449) return false;  // 'IDST'
    out.version = i32(d.data(), 4);

    const int numTextures = i32(d.data(), 204);
    const int textureIndex = i32(d.data(), 208);
    const int numCd = i32(d.data(), 212);
    const int cdIndex = i32(d.data(), 216);
    const int numSkinRef = i32(d.data(), 220);
    const int skinIndex = i32(d.data(), 228);
    const int numBodyParts = i32(d.data(), 232);
    const int bodyPartIndex = i32(d.data(), 236);

    std::vector<std::string> cds;
    for (int i = 0; i < numCd && i < 64; ++i) {
        const size_t o = (size_t)cdIndex + (size_t)i * 4;
        if (o + 4 > d.size()) break;
        std::string c = norm(cstr(d.data(), i32(d.data(), o), 260));
        while (!c.empty() && (c.front() == '/' || c.front() == ' ')) c.erase(0, 1);
        if (!c.empty() && c.back() != '/') c += '/';
        cds.push_back(c);
    }
    if (cds.empty()) cds.push_back("");

    std::vector<std::string> texNames;
    for (int i = 0; i < numTextures && i < 4096; ++i) {
        const size_t base = (size_t)textureIndex + (size_t)i * 64;
        if (base + 64 > d.size()) break;
        texNames.push_back(norm(cstr(d.data(), base + i32(d.data(), base), 256)));
    }
    // skinref[0]: material index per mesh -> texture slot
    std::vector<int> skin0;
    for (int i = 0; i < numSkinRef && i < 4096; ++i) {
        const size_t o = (size_t)skinIndex + (size_t)i * 2;
        if (o + 2 > d.size()) break;
        skin0.push_back(i16(d.data(), o));
    }

    // Resolve each skinref slot to a full material path. If a texname already
    // contains a slash treat it as a full path; else try each cdmaterials dir.
    auto stripLead = [](std::string s) {
        while (!s.empty() && (s.front() == '/' || s.front() == ' ')) s.erase(0, 1);
        return s;
    };
    for (size_t s = 0; s < skin0.size(); ++s) {
        const int t = skin0[s];
        std::string name = stripLead((t >= 0 && t < (int)texNames.size())
                                         ? texNames[t]
                                         : std::string());
        std::string full = name;
        if (name.find('/') == std::string::npos && !cds.empty())
            full = cds[0] + name;
        out.materials.push_back(stripLead(full));
    }
    if (out.materials.empty() && !texNames.empty())
        out.materials.push_back(cds[0] + texNames[0]);

    // bodyparts -> models -> meshes
    int vbase = 0;
    for (int bp = 0; bp < numBodyParts; ++bp) {
        const size_t bpo = (size_t)bodyPartIndex + (size_t)bp * 16;
        if (bpo + 16 > d.size()) break;
        const int nModels = i32(d.data(), bpo + 4);
        const int modelIdx = i32(d.data(), bpo + 12);
        for (int m = 0; m < nModels; ++m) {
            const size_t mo = bpo + (size_t)modelIdx + (size_t)m * 148;
            if (mo + 148 > d.size()) break;
            const int nMeshes = i32(d.data(), mo + 72);
            const int meshIdx = i32(d.data(), mo + 76);
            const int nVerts = i32(d.data(), mo + 80);
            MdlModel mm;
            mm.vertexBase = vbase;
            for (int e = 0; e < nMeshes; ++e) {
                const size_t eo = mo + (size_t)meshIdx + (size_t)e * 116;
                if (eo + 116 > d.size()) break;
                MdlMesh md;
                md.material = i32(d.data(), eo);
                md.numvertices = i32(d.data(), eo + 8);
                md.vertexoffset = i32(d.data(), eo + 12);
                mm.meshes.push_back(md);
            }
            out.models.push_back(std::move(mm));
            vbase += nVerts;
        }
    }
    return !out.models.empty();
}

// ---- VTX: strip indices, parallel-walked against the MDL model list --------
bool parseVtx(const std::vector<uint8_t>& d, const MdlInfo& mdl,
              const std::vector<StudioVertex>& vvd, StudioModel& out) {
    if (d.size() < 36) return false;
    const int numBodyParts = i32(d.data(), 28);
    const int bodyPartOffset = i32(d.data(), 32);
    // v49 strip-group / strip headers carry two extra topology ints.
    const bool ext = mdl.version >= 49;
    const size_t sgSize = ext ? 33 : 25;
    const size_t stSize = ext ? 35 : 27;

    // Accumulate triangles per skinref-material slot.
    std::map<int, std::vector<uint32_t>> byMat;

    size_t modelFlat = 0;  // index into mdl.models as we walk
    for (int bp = 0; bp < numBodyParts; ++bp) {
        const size_t bpo = (size_t)bodyPartOffset + (size_t)bp * 8;
        if (bpo + 8 > d.size()) break;
        const int nModels = i32(d.data(), bpo);
        const int modelOff = i32(d.data(), bpo + 4);
        for (int m = 0; m < nModels; ++m, ++modelFlat) {
            if (modelFlat >= mdl.models.size()) break;
            const MdlModel& mm = mdl.models[modelFlat];
            const size_t mo = bpo + (size_t)modelOff + (size_t)m * 8;
            if (mo + 8 > d.size()) break;
            const int nLods = i32(d.data(), mo);
            const int lodOff = i32(d.data(), mo + 4);
            if (nLods < 1) continue;
            // LOD 0
            const size_t lo = mo + (size_t)lodOff;
            if (lo + 12 > d.size()) break;
            const int nMeshes = i32(d.data(), lo);
            const int meshOff = i32(d.data(), lo + 4);
            for (int e = 0; e < nMeshes && e < (int)mm.meshes.size(); ++e) {
                const MdlMesh& md = mm.meshes[e];
                const size_t eo = lo + (size_t)meshOff + (size_t)e * 9;
                if (eo + 9 > d.size()) break;
                const int nSg = i32(d.data(), eo);
                const int sgOff = i32(d.data(), eo + 4);
                auto& tris = byMat[md.material];
                for (int g = 0; g < nSg; ++g) {
                    const size_t go = eo + (size_t)sgOff + (size_t)g * sgSize;
                    if (go + sgSize > d.size()) break;
                    const int nVerts = i32(d.data(), go);
                    const int vOff = i32(d.data(), go + 4);
                    const int nInd = i32(d.data(), go + 8);
                    const int iOff = i32(d.data(), go + 12);
                    const int nStrips = i32(d.data(), go + 16);
                    const int stOff = i32(d.data(), go + 20);
                    const uint8_t* vArr = d.data() + go + vOff;      // Vertex_t[9]
                    const uint8_t* iArr = d.data() + go + iOff;      // uint16[]
                    if (go + vOff + (size_t)nVerts * 9 > d.size()) continue;
                    if (go + iOff + (size_t)nInd * 2 > d.size()) continue;

                    auto vvdIndex = [&](int stripIdx) -> int {
                        if (stripIdx < 0 || stripIdx >= nInd) return -1;
                        const int vIdx = rd<uint16_t>(iArr + (size_t)stripIdx * 2);
                        if (vIdx < 0 || vIdx >= nVerts) return -1;
                        const int orig = rd<uint16_t>(vArr + (size_t)vIdx * 9 + 4);
                        return mm.vertexBase + md.vertexoffset + orig;
                    };

                    for (int s = 0; s < nStrips; ++s) {
                        const size_t so = go + (size_t)stOff + (size_t)s * stSize;
                        if (so + stSize > d.size()) break;
                        const int sInd = i32(d.data(), so);
                        const int sIndOff = i32(d.data(), so + 4);
                        // StripHeader_t (packed): numIndices,indexOffset,numVerts,
                        // vertOffset (4 ints) + short numBones @16 + flags @18.
                        const uint8_t sFlags = d[so + 18 < d.size() ? so + 18 : so];
                        const bool trilist = (sFlags & 0x01) != 0;
                        if (trilist) {
                            for (int k = 0; k + 2 < sInd; k += 3) {
                                const int a = vvdIndex(sIndOff + k);
                                const int b = vvdIndex(sIndOff + k + 1);
                                const int c = vvdIndex(sIndOff + k + 2);
                                if (a < 0 || b < 0 || c < 0) continue;
                                tris.insert(tris.end(), {(uint32_t)a, (uint32_t)b, (uint32_t)c});
                            }
                        } else {  // tristrip
                            for (int k = 0; k + 2 < sInd; ++k) {
                                int a = vvdIndex(sIndOff + k);
                                int b = vvdIndex(sIndOff + k + 1);
                                int c = vvdIndex(sIndOff + k + 2);
                                if (a < 0 || b < 0 || c < 0) continue;
                                if (k & 1) std::swap(b, c);
                                tris.insert(tris.end(), {(uint32_t)a, (uint32_t)b, (uint32_t)c});
                            }
                        }
                    }
                }
            }
        }
    }

    // Emit interleaved verts + per-material submeshes.
    out.verts = vvd;
    out.indices.clear();
    out.meshes.clear();
    for (auto& [matSlot, tris] : byMat) {
        if (tris.empty()) continue;
        StudioMesh sm;
        sm.material = (matSlot >= 0 && matSlot < (int)mdl.materials.size())
                          ? mdl.materials[matSlot]
                          : (mdl.materials.empty() ? "" : mdl.materials[0]);
        sm.firstIndex = (uint32_t)out.indices.size();
        sm.indexCount = (uint32_t)tris.size();
        out.indices.insert(out.indices.end(), tris.begin(), tris.end());
        out.meshes.push_back(std::move(sm));
    }
    return !out.indices.empty();
}

std::map<std::string, StudioModel> g_cache;

}  // namespace

const StudioModel& loadStudioModel(source::SourceFs& fs, const std::string& mdlPathIn) {
    const std::string key = norm(mdlPathIn);
    auto it = g_cache.find(key);
    if (it != g_cache.end()) return it->second;

    StudioModel& sm = g_cache[key];  // inserts an ok=false stub

    std::string base = key;
    const size_t dot = base.rfind(".mdl");
    if (dot != std::string::npos) base = base.substr(0, dot);

    auto mdlBytes = fs.read(base + ".mdl");
    auto vvdBytes = fs.read(base + ".vvd");
    auto vtxBytes = fs.read(base + ".dx90.vtx");
    if (!vtxBytes) vtxBytes = fs.read(base + ".vtx");
    if (!vtxBytes) vtxBytes = fs.read(base + ".dx80.vtx");
    if (!mdlBytes || !vvdBytes || !vtxBytes) {
        PB_WARN("model: missing files for %s", key.c_str());
        return sm;
    }

    MdlInfo mdl;
    if (!parseMdl(*mdlBytes, mdl)) {
        PB_WARN("model: bad MDL %s", key.c_str());
        return sm;
    }
    std::vector<StudioVertex> vvd;
    if (!parseVvd(*vvdBytes, vvd)) {
        PB_WARN("model: bad VVD %s", key.c_str());
        return sm;
    }
    if (!parseVtx(*vtxBytes, mdl, vvd, sm)) {
        PB_WARN("model: bad VTX %s", key.c_str());
        sm = StudioModel{};
        return sm;
    }

    glm::vec3 mn(1e30f), mx(-1e30f);
    for (const auto& v : sm.verts) {
        mn = glm::min(mn, v.pos);
        mx = glm::max(mx, v.pos);
    }
    sm.boundsMin = mn;
    sm.boundsMax = mx;
    sm.ok = true;
    return sm;
}

void clearModelCache() { g_cache.clear(); }

void debugDumpModel(source::SourceFs& fs, const std::string& path) {
    const StudioModel& sm = loadStudioModel(fs, path);
    PB_INFO("model %s: ok=%d verts=%zu idx=%zu meshes=%zu bbox=(%.1f %.1f %.1f)-(%.1f %.1f %.1f)",
            path.c_str(), sm.ok, sm.verts.size(), sm.indices.size(), sm.meshes.size(),
            sm.boundsMin.x, sm.boundsMin.y, sm.boundsMin.z, sm.boundsMax.x,
            sm.boundsMax.y, sm.boundsMax.z);
    for (const auto& m : sm.meshes)
        PB_INFO("   mesh mat=%s tris=%u", m.material.c_str(), m.indexCount / 3);
}

int bakePropModels(bsp::WorldMesh& mesh, source::SourceFs& fs) {
    using bsp::DrawBatch;
    using bsp::WorldVertex;
    if (mesh.props.empty()) return 0;

    // White-ish lightmap sample for props (they aren't lightmapped here); a
    // small tint boost compensates for a dark atlas corner in the BSP path.
    const glm::vec2 kLmUV(0.0009f, 0.0009f);
    static const glm::vec3 kKey = glm::normalize(glm::vec3(0.35f, 0.45f, 0.82f));

    // Accumulate new geometry per material, then append as batches.
    std::unordered_map<std::string, std::vector<uint32_t>> buckets;
    const uint32_t vbase0 = (uint32_t)mesh.vertices.size();

    int baked = 0;
    for (auto& prop : mesh.props) {
        if (prop.model.empty()) continue;
        const StudioModel& sm = loadStudioModel(fs, prop.model);
        if (!sm.ok || sm.verts.empty()) continue;

        const float yaw = glm::radians(prop.anglesPYR.y);
        const float pit = glm::radians(prop.anglesPYR.x);
        const float rol = glm::radians(prop.anglesPYR.z);
        const glm::mat3 R =
            glm::mat3(glm::rotate(glm::mat4(1.0f), yaw, glm::vec3(0, 0, 1))) *
            glm::mat3(glm::rotate(glm::mat4(1.0f), pit, glm::vec3(0, 1, 0))) *
            glm::mat3(glm::rotate(glm::mat4(1.0f), rol, glm::vec3(1, 0, 0)));
        const float s = prop.scale > 0.01f ? prop.scale : 1.0f;

        const uint32_t vbase = (uint32_t)mesh.vertices.size();
        mesh.vertices.reserve(mesh.vertices.size() + sm.verts.size());
        for (const auto& mv : sm.verts) {
            WorldVertex wv;
            wv.pos = prop.pos + R * (mv.pos * s);
            wv.normal = R * mv.normal;
            const float nl = glm::clamp(glm::dot(glm::normalize(wv.normal), kKey),
                                        0.0f, 1.0f);
            wv.uv = kLmUV;
            wv.texUv = mv.uv;
            wv.tint = glm::vec3(1.32f * (0.5f + 0.5f * nl));
            mesh.vertices.push_back(wv);
        }
        for (const auto& msh : sm.meshes) {
            auto& idx = buckets[msh.material];
            for (uint32_t k = 0; k < msh.indexCount; ++k)
                idx.push_back(vbase + sm.indices[msh.firstIndex + k]);
        }
        prop.baked = true;
        ++baked;
    }

    for (auto& [mat, idx] : buckets) {
        if (idx.empty()) continue;
        DrawBatch b;
        b.material = mat;
        b.firstIndex = (uint32_t)mesh.indices.size();
        b.indexCount = (uint32_t)idx.size();
        b.translucent = false;
        mesh.indices.insert(mesh.indices.end(), idx.begin(), idx.end());
        mesh.batches.push_back(std::move(b));
    }
    PB_INFO("props: baked %d / %zu (%u new verts)", baked, mesh.props.size(),
            (uint32_t)mesh.vertices.size() - vbase0);
    return baked;
}

}  // namespace pb::model
