#include "bsp/BspMesh.h"
#include "bsp/Lzma.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <unordered_map>

#include "core/Log.h"

namespace pb::bsp {
namespace {

glm::vec3 toVec(const Vector_t& v) { return {v.x, v.y, v.z}; }

glm::vec3 parseVec3(const std::string& s, glm::vec3 def = glm::vec3(0.0f)) {
    glm::vec3 out = def;
    if (std::sscanf(s.c_str(), "%f %f %f", &out.x, &out.y, &out.z) < 1) return def;
    return out;
}

float srgbEncode(float c) {
    c = std::clamp(c, 0.0f, 1.0f);
    return c <= 0.0031308f ? 12.92f * c : 1.055f * std::pow(c, 1.0f / 2.4f) - 0.055f;
}

glm::vec3 rgbeToSrgb(const ColorRGBExp32& s, float gain) {
    const float m = std::ldexp(1.0f, s.exponent) / 255.0f;  // 2^exp / 255
    glm::vec3 lin(s.r * m, s.g * m, s.b * m);
    lin *= gain;
    lin = glm::max(lin, glm::vec3(0.015f));  // keep unlit corners readable
    return {srgbEncode(lin.x), srgbEncode(lin.y), srgbEncode(lin.z)};
}

// Simple growing shelf packer for per-face lightmap rectangles.
struct LightmapPacker {
    static constexpr int kAtlasW = 2048;
    static constexpr int kMaxAtlasH = 8192;
    int cursorX = 0, cursorY = 0, shelfH = 0, atlasH = 0;
    bool overflow = false;

    // Reserve a small white block at the origin for unlit faces.
    void reserveWhite() { cursorX = 6; shelfH = 4; atlasH = 6; }

    bool place(int w, int h, int& outX, int& outY) {
        if (overflow) return false;
        w = std::max(w, 1);
        h = std::max(h, 1);
        if (cursorX + w > kAtlasW) {
            cursorX = 0;
            cursorY += shelfH + 1;
            shelfH = 0;
        }
        if (cursorY + h + 1 > kMaxAtlasH) {
            overflow = true;
            return false;
        }
        outX = cursorX;
        outY = cursorY;
        cursorX += w + 1;
        shelfH = std::max(shelfH, h);
        atlasH = std::max(atlasH, cursorY + shelfH + 1);
        return true;
    }
};

bool isSkippableSurface(uint32_t flags, const MeshBuildOptions& opts) {
    if ((flags & SURF_NODRAW) || (flags & SURF_HINT) || (flags & SURF_SKIP)) return true;
    if (!opts.includeSky && ((flags & SURF_SKY) || (flags & SURF_SKY2D))) return true;
    if (!opts.includeTriggers && (flags & SURF_TRIGGER)) return true;
    return false;
}

void parseStaticProps(const BspFile& bsp, WorldMesh& mesh) {
    const uint8_t* file = bsp.fileData();
    const size_t fileSize = bsp.fileSize();
    const int glOff = bsp.lumpOffset(LUMP_GAME_LUMP);
    const int glLen = bsp.lumpLength(LUMP_GAME_LUMP);
    if (glOff <= 0 || glLen < 4 ||
        static_cast<size_t>(glOff) + static_cast<size_t>(glLen) > fileSize)
        return;

    const uint8_t* gl = file + glOff;
    int32_t count = 0;
    std::memcpy(&count, gl, 4);
    if (count < 0 || count > 64) return;

    for (int i = 0; i < count; ++i) {
        const size_t hoff = 4 + static_cast<size_t>(i) * sizeof(GameLumpHeader_t);
        if (hoff + sizeof(GameLumpHeader_t) > static_cast<size_t>(glLen)) return;
        GameLumpHeader_t h{};
        std::memcpy(&h, gl + hoff, sizeof(h));
        if (h.id != 0x73707270) continue;  // 'sprp'

        // fileofs is absolute in PC Source BSPs; fall back to lump-relative.
        size_t base = static_cast<size_t>(h.fileofs);
        if (base + 4 > fileSize) base = static_cast<size_t>(glOff) + h.fileofs;
        if (base + 4 > fileSize) continue;
        const uint8_t* q = file + base;
        const uint8_t* end = file + std::min<size_t>(
                                       fileSize, base + static_cast<size_t>(h.filelen));
        if (h.filelen <= 0 || end <= q) end = file + fileSize;

        // Modern TF2 BSPs (ctf_2fort, cp_process_final, pl_upward, etc.) LZMA-compress
        // the sprp game lump; decompress it before parsing the prop dictionary.
        std::vector<uint8_t> decomp;
        if ((h.flags & 1) || isLzmaLump(q, fileSize - base)) {
            decomp = decompressLzmaLump(q, fileSize - base);
            if (decomp.empty()) continue;
            q = decomp.data();
            end = decomp.data() + decomp.size();
        }

        auto take = [&](size_t n) -> const uint8_t* {
            if (q + n > end) return nullptr;
            const uint8_t* r = q;
            q += n;
            return r;
        };

        const uint8_t* p = take(4);
        if (!p) continue;
        int32_t dictEntries = 0;
        std::memcpy(&dictEntries, p, 4);
        if (dictEntries < 0 || dictEntries > 200000) continue;
        std::vector<std::string> names;
        names.reserve(dictEntries);
        bool ok = true;
        for (int d = 0; d < dictEntries; ++d) {
            const uint8_t* nm = take(128);
            if (!nm) {
                ok = false;
                break;
            }
            names.emplace_back(reinterpret_cast<const char*>(nm),
                               strnlen(reinterpret_cast<const char*>(nm), 128));
        }
        if (!ok) continue;

        p = take(4);
        if (!p) continue;
        int32_t leafEntries = 0;
        std::memcpy(&leafEntries, p, 4);
        if (leafEntries < 0 || !take(static_cast<size_t>(leafEntries) * 2)) continue;

        p = take(4);
        if (!p) continue;
        int32_t propCount = 0;
        std::memcpy(&propCount, p, 4);
        if (propCount <= 0 || propCount > 500000) continue;

        const size_t remaining = static_cast<size_t>(end - q);
        const size_t stride = remaining / static_cast<size_t>(propCount);
        if (stride < 24 || stride > 256) continue;

        for (int pi = 0; pi < propCount; ++pi) {
            const uint8_t* r = q + static_cast<size_t>(pi) * stride;
            if (r + 26 > end) break;
            PropInstance inst;
            std::memcpy(&inst.pos, r, 12);
            std::memcpy(&inst.anglesPYR, r + 12, 12);
            uint16_t type = 0;
            std::memcpy(&type, r + 24, 2);
            inst.model = (type < names.size()) ? names[type] : std::string();
            mesh.props.push_back(std::move(inst));
        }
        break;  // consumed the sprp lump
    }
}

}  // namespace

WorldMesh buildWorldMesh(const BspFile& bsp, const MeshBuildOptions& opts) {
    WorldMesh mesh;

    const auto verts = bsp.lumpArray<Vector_t>(LUMP_VERTEXES);
    const auto edges = bsp.lumpArray<Edge_t>(LUMP_EDGES);
    const auto surfedges = bsp.lumpArray<int32_t>(LUMP_SURFEDGES);
    auto faces = bsp.lumpArray<Face_t>(LUMP_FACES);
    if (faces.empty()) faces = bsp.lumpArray<Face_t>(LUMP_FACES_HDR);
    const auto texinfos = bsp.lumpArray<TexInfo_t>(LUMP_TEXINFO);
    const auto planes = bsp.lumpArray<Plane_t>(LUMP_PLANES);
    const auto models = bsp.lumpArray<Model_t>(LUMP_MODELS);
    const auto dispVerts = bsp.lumpArray<DispVert_t>(LUMP_DISP_VERTS);
    const uint8_t* dispInfoRaw = nullptr;
    size_t dispInfoBytes = 0;
    bsp.lumpBytes(LUMP_DISPINFO, dispInfoRaw, dispInfoBytes);
    const int dispInfoCount =
        dispInfoRaw ? static_cast<int>(dispInfoBytes / kDispInfoSize) : 0;
    auto dispInfoAt = [&](int idx, DispInfoHead_t& out) -> bool {
        if (idx < 0 || idx >= dispInfoCount) return false;
        std::memcpy(&out, dispInfoRaw + static_cast<size_t>(idx) * kDispInfoSize,
                    sizeof(DispInfoHead_t));
        return true;
    };

    if (verts.empty() || edges.empty() || surfedges.empty() || faces.empty() ||
        texinfos.empty()) {
        PB_ERROR("BSP mesh: required geometry lumps missing");
        return mesh;
    }

    size_t lightingSize = 0;
    bool lightingHdr = false;
    const uint8_t* lighting = bsp.lighting(lightingSize, lightingHdr);

    // ---- entity brush-model offsets + interactive func_door separation ----
    struct FaceRange {
        int first, count;
        glm::vec3 offset;
        int doorIdx = -1;
    };
    std::vector<FaceRange> ranges;
    if (!models.empty())
        ranges.push_back({models[0].firstface, models[0].numfaces, glm::vec3(0.0f), -1});
    for (const auto& ent : bsp.entities()) {
        auto it = ent.find("model");
        if (it == ent.end() || it->second.empty() || it->second[0] != '*') continue;
        const int idx = std::atoi(it->second.c_str() + 1);
        if (idx <= 0 || idx >= static_cast<int>(models.size())) continue;

        std::string cls;
        if (auto ci = ent.find("classname"); ci != ent.end()) cls = ci->second;
        // Skip invisible trigger/clip/volume brush entities from world geometry & collision!
        if (!opts.includeTriggers &&
            (cls.rfind("trigger_", 0) == 0 || cls == "func_respawnroom" ||
             cls == "func_capturezone" || cls == "func_nobuild" ||
             cls == "func_regenerate" || cls == "func_respawnroomvisualizer" ||
             cls.rfind("func_areaportal", 0) == 0 || cls == "func_occluder" ||
             cls == "func_nav_blocker" || cls == "func_nav_avoid" ||
             cls == "func_nav_prefer" || cls == "func_viscluster")) {
            continue;
        }
        // Skip explicitly StartDisabled brush blockers (e.g. stage gates that start hidden/disabled)
        if (auto sd = ent.find("StartDisabled"); sd != ent.end() && sd->second == "1" && cls == "func_brush") {
            continue;
        }

        glm::vec3 origin(0.0f);
        if (auto oit = ent.find("origin"); oit != ent.end()) origin = parseVec3(oit->second);

        if (cls == "func_door") {
            InteractiveDoor door;
            if (auto ti = ent.find("targetname"); ti != ent.end()) door.targetname = ti->second;
            door.origin = origin;
            glm::vec3 mdir(0.0f, 0.0f, 1.0f);
            if (auto mi = ent.find("movedir"); mi != ent.end()) {
                const glm::vec3 pyr = parseVec3(mi->second);
                const float pr = glm::radians(pyr.x);
                const float yr = glm::radians(pyr.y);
                // Source movedir: pitch=-90 is UP (+Z), pitch=90 is DOWN (-Z), yaw=around +Z
                mdir = glm::vec3(std::cos(pr) * std::cos(yr),
                                 std::cos(pr) * std::sin(yr),
                                 -std::sin(pr));
                if (glm::length(mdir) > 0.01f) mdir = glm::normalize(mdir);
                else mdir = glm::vec3(0.0f, 0.0f, 1.0f);
            }
            door.movedir = mdir;
            if (auto si = ent.find("speed"); si != ent.end()) {
                float sp = static_cast<float>(std::atof(si->second.c_str()));
                if (sp > 10.0f) door.speed = sp;
            }
            float lip = 8.0f;
            if (auto li = ent.find("lip"); li != ent.end())
                lip = static_cast<float>(std::atof(li->second.c_str()));
            const glm::vec3 dmin = toVec(models[idx].mins) + origin;
            const glm::vec3 dmax = toVec(models[idx].maxs) + origin;
            door.boundsMin = dmin;
            door.boundsMax = dmax;
            const glm::vec3 dsz = dmax - dmin;
            const float proj = std::fabs(mdir.x) * dsz.x + std::fabs(mdir.y) * dsz.y + std::fabs(mdir.z) * dsz.z;
            door.travel = std::max(32.0f, proj - lip);

            const int dIdx = static_cast<int>(mesh.doors.size());
            mesh.doors.push_back(std::move(door));
            ranges.push_back({models[idx].firstface, models[idx].numfaces, origin, dIdx});
        } else {
            ranges.push_back({models[idx].firstface, models[idx].numfaces, origin, -1});
        }
    }

    // ---- pass 1: choose drawable faces + pack lightmaps ----------------
    struct EmitFace {
        int faceIndex;
        glm::vec3 offset;
        int doorIdx = -1;
        int lmX = 0, lmY = 0, lmW = 0, lmH = 0;
        bool lit = false;
    };
    std::vector<EmitFace> emit;
    emit.reserve(faces.size());

    LightmapPacker packer;
    packer.reserveWhite();
    // Both LDR (LUMP_LIGHTING) and HDR (LUMP_LIGHTING_HDR) store ColorRGBExp32
    // samples, so the same RGBE->sRGB path works; HDR just needs a lower gain.
    const bool wantLightmaps = lighting != nullptr;
    const float lmGain = opts.lightmapGain * (lightingHdr ? 0.55f : 1.0f);

    for (const auto& range : ranges) {
        for (int f = range.first; f < range.first + range.count; ++f) {
            if (f < 0 || f >= static_cast<int>(faces.size())) continue;
            const Face_t& face = faces[f];
            if (face.texinfo < 0 || face.texinfo >= static_cast<int>(texinfos.size())) {
                mesh.skippedFaces++;
                continue;
            }
            const uint32_t flags =
                static_cast<uint32_t>(texinfos[face.texinfo].flags);
            if (isSkippableSurface(flags, opts) || face.numedges < 3) {
                mesh.skippedFaces++;
                continue;
            }

            EmitFace ef;
            ef.faceIndex = f;
            ef.offset = range.offset;
            ef.doorIdx = range.doorIdx;

            const int lw = face.lightmapSize[0] + 1;
            const int lh = face.lightmapSize[1] + 1;
            const bool hasLm = wantLightmaps && face.lightofs >= 0 && lw > 0 &&
                               lh > 0 && lw <= 512 && lh <= 512 &&
                               static_cast<size_t>(face.lightofs) +
                                       static_cast<size_t>(lw) * lh * 4 <=
                                   lightingSize;
            if (hasLm && packer.place(lw, lh, ef.lmX, ef.lmY)) {
                ef.lit = true;
                ef.lmW = lw;
                ef.lmH = lh;
            }
            emit.push_back(ef);
        }
    }

    // ---- build lightmap atlas ----------------------------------------
    const int atlasW = LightmapPacker::kAtlasW;
    const int atlasH = std::max(8, packer.atlasH);
    mesh.lightmapWidth = atlasW;
    mesh.lightmapHeight = atlasH;
    mesh.lightmapAtlas.assign(static_cast<size_t>(atlasW) * atlasH * 3, 40);
    // white block for unlit faces
    for (int y = 0; y < 4; ++y)
        for (int x = 0; x < 4; ++x) {
            uint8_t* px = &mesh.lightmapAtlas[(static_cast<size_t>(y) * atlasW + x) * 3];
            px[0] = px[1] = px[2] = 255;
        }
    const float whiteU = 2.0f / atlasW;
    const float whiteV = 2.0f / atlasH;

    for (const auto& ef : emit) {
        if (!ef.lit) continue;
        const Face_t& face = faces[ef.faceIndex];
        const ColorRGBExp32* samples = reinterpret_cast<const ColorRGBExp32*>(
            lighting + face.lightofs);
        for (int y = 0; y < ef.lmH; ++y) {
            for (int x = 0; x < ef.lmW; ++x) {
                const glm::vec3 c = rgbeToSrgb(samples[y * ef.lmW + x], lmGain);
                const size_t di =
                    (static_cast<size_t>(ef.lmY + y) * atlasW + (ef.lmX + x)) * 3;
                mesh.lightmapAtlas[di + 0] = static_cast<uint8_t>(c.r * 255.0f + 0.5f);
                mesh.lightmapAtlas[di + 1] = static_cast<uint8_t>(c.g * 255.0f + 0.5f);
                mesh.lightmapAtlas[di + 2] = static_cast<uint8_t>(c.b * 255.0f + 0.5f);
            }
        }
    }

    // ---- pass 2: emit geometry, grouped by material -----------------
    std::unordered_map<std::string, std::vector<uint32_t>> opaqueIdx, transIdx;
    std::vector<std::unordered_map<std::string, std::vector<uint32_t>>> doorOpaque(mesh.doors.size());
    std::vector<std::unordered_map<std::string, std::vector<uint32_t>>> doorTrans(mesh.doors.size());

    auto addPolyVertexTo = [&](std::vector<WorldVertex>& dstVerts, const Face_t& face,
                               const TexInfo_t& ti, const glm::vec3& p, const glm::vec3& n,
                               const EmitFace& ef, float texW, float texH) {
        WorldVertex v;
        v.pos = p;
        v.normal = n;
        v.texUv = {
            (p.x * ti.textureVecs[0][0] + p.y * ti.textureVecs[0][1] +
             p.z * ti.textureVecs[0][2] + ti.textureVecs[0][3]) / texW,
            (p.x * ti.textureVecs[1][0] + p.y * ti.textureVecs[1][1] +
             p.z * ti.textureVecs[1][2] + ti.textureVecs[1][3]) / texH,
        };
        if (ef.lit) {
            float lu = p.x * ti.lightmapVecs[0][0] + p.y * ti.lightmapVecs[0][1] +
                       p.z * ti.lightmapVecs[0][2] + ti.lightmapVecs[0][3];
            float lv = p.x * ti.lightmapVecs[1][0] + p.y * ti.lightmapVecs[1][1] +
                       p.z * ti.lightmapVecs[1][2] + ti.lightmapVecs[1][3];
            lu -= static_cast<float>(face.lightmapMins[0]);
            lv -= static_cast<float>(face.lightmapMins[1]);
            v.uv = {(ef.lmX + lu + 0.5f) / atlasW, (ef.lmY + lv + 0.5f) / atlasH};
            v.tint = glm::vec3(1.0f);
        } else {
            static const glm::vec3 key = glm::normalize(glm::vec3(0.35f, 0.45f, 0.82f));
            const float s = 0.45f + 0.55f * std::clamp(glm::dot(n, key), 0.0f, 1.0f);
            v.uv = {whiteU, whiteV};
            v.tint = glm::vec3(s);
        }
        const uint32_t index = static_cast<uint32_t>(dstVerts.size());
        dstVerts.push_back(v);
        return index;
    };
    auto addPolyVertex = [&](const Face_t& face, const TexInfo_t& ti,
                             const glm::vec3& p, const glm::vec3& n, const EmitFace& ef,
                             float texW, float texH) {
        return addPolyVertexTo(mesh.vertices, face, ti, p, n, ef, texW, texH);
    };

    std::unordered_map<uint64_t, uint8_t> wireSeen;
    auto addWire = [&](const glm::vec3& a, const glm::vec3& b) {
        auto key = [](const glm::vec3& v) {
            auto q = [](float f) { return static_cast<int64_t>(std::lround(f * 8.0f)); };
            return (static_cast<uint64_t>(q(v.x) & 0x1fffff)) |
                   (static_cast<uint64_t>(q(v.y) & 0x1fffff) << 21) |
                   (static_cast<uint64_t>(q(v.z) & 0x3fffff) << 42);
        };
        uint64_t ka = key(a), kb = key(b);
        uint64_t h = ka ^ (kb * 1099511628211ull);
        if (wireSeen.emplace(h, 1).second) {
            mesh.wireLines.push_back(a);
            mesh.wireLines.push_back(b);
        }
    };

    glm::vec3 bmin(1e30f), bmax(-1e30f);
    int dispFacesEmitted = 0;

    for (const auto& ef : emit) {
        const Face_t& face = faces[ef.faceIndex];
        const TexInfo_t& ti = texinfos[face.texinfo];
        glm::vec3 n = (face.planenum < planes.size())
                          ? toVec(planes[face.planenum].normal)
                          : glm::vec3(0, 0, 1);
        if (face.side) n = -n;
        if (glm::length(n) < 0.5f) n = glm::vec3(0, 0, 1);

        // Gather polygon vertices from surfedges.
        std::vector<glm::vec3> poly;
        poly.reserve(face.numedges);
        for (int e = 0; e < face.numedges; ++e) {
            const int seIndex = face.firstedge + e;
            if (seIndex < 0 || seIndex >= static_cast<int>(surfedges.size())) break;
            const int32_t se = surfedges[seIndex];
            const int ei = se >= 0 ? se : -se;
            if (ei < 0 || ei >= static_cast<int>(edges.size())) break;
            const uint16_t vi = se >= 0 ? edges[ei].v[0] : edges[ei].v[1];
            if (vi >= verts.size()) break;
            poly.push_back(toVec(verts[vi]) + ef.offset);
        }
        if (poly.size() < 3) {
            mesh.skippedFaces++;
            continue;
        }

        const std::string mat = bsp.materialName(ti.texdata);
        const bool translucent = (static_cast<uint32_t>(ti.flags) & SURF_TRANS) ||
                                 (static_cast<uint32_t>(ti.flags) & SURF_WARP) ||
                                 mat.rfind("glass/", 0) == 0 ||
                                 mat.find("water") != std::string::npos;
        auto& dstVerts = (ef.doorIdx >= 0) ? mesh.doors[ef.doorIdx].vertices : mesh.vertices;
        auto& bucket = (ef.doorIdx >= 0)
            ? (translucent ? doorTrans[ef.doorIdx][mat] : doorOpaque[ef.doorIdx][mat])
            : (translucent ? transIdx[mat] : opaqueIdx[mat]);

        int tw = 0, th = 0;
        if (!bsp.texdataDims(ti.texdata, tw, th)) {
            tw = 256;
            th = 256;
        }

        // ---- displacement surface -------------------------------------
        DispInfoHead_t di{};
        if (face.dispinfo >= 0 && poly.size() >= 4 && !dispVerts.empty() &&
            dispInfoAt(face.dispinfo, di) && di.power >= 2 && di.power <= 4) {
            const int gn = (1 << di.power) + 1;           // verts per side
            const int total = gn * gn;
            if (di.dispVertStart < 0 ||
                di.dispVertStart + total > static_cast<int>(dispVerts.size())) {
                mesh.skippedFaces++;
                continue;
            }
            // Rotate the base quad so corner 0 is nearest startPosition.
            const glm::vec3 start(di.startPosition.x, di.startPosition.y,
                                  di.startPosition.z);
            int c0 = 0;
            float bestD = 1e30f;
            for (int k = 0; k < 4; ++k) {
                const float d = glm::distance(poly[k], start + ef.offset);
                if (d < bestD) { bestD = d; c0 = k; }
            }
            // Surfedge polys wind clockwise-from-front; Valve's displacement
            // base quad is CCW, so walk the corners the other way from c0.
            const glm::vec3 A = poly[c0];              // start
            const glm::vec3 B = poly[(c0 + 3) % 4];
            const glm::vec3 C = poly[(c0 + 2) % 4];    // diagonal
            const glm::vec3 D = poly[(c0 + 1) % 4];

            std::vector<uint32_t> gridIdx(total);
            for (int row = 0; row < gn; ++row) {
                const float tb = static_cast<float>(row) / (gn - 1);  // A->D axis
                const glm::vec3 e0 = A + (D - A) * tb;
                const glm::vec3 e1 = B + (C - B) * tb;
                for (int col = 0; col < gn; ++col) {
                    const float ta = static_cast<float>(col) / (gn - 1);  // A->B
                    glm::vec3 p = e0 + (e1 - e0) * ta;
                    const DispVert_t& dv =
                        dispVerts[di.dispVertStart + row * gn + col];
                    p += glm::vec3(dv.vec.x, dv.vec.y, dv.vec.z) * dv.dist;
                    const uint32_t vIdx =
                        addPolyVertex(face, ti, p, n, ef, static_cast<float>(tw),
                                      static_cast<float>(th));
                    mesh.vertices[vIdx].blend = std::clamp(dv.alpha / 255.0f, 0.0f, 1.0f);
                    gridIdx[row * gn + col] = vIdx;
                    bmin = glm::min(bmin, p);
                    bmax = glm::max(bmax, p);
                }
            }
            for (int row = 0; row + 1 < gn; ++row)
                for (int col = 0; col + 1 < gn; ++col) {
                    const uint32_t a = gridIdx[row * gn + col];
                    const uint32_t b = gridIdx[row * gn + col + 1];
                    const uint32_t c = gridIdx[(row + 1) * gn + col + 1];
                    const uint32_t d = gridIdx[(row + 1) * gn + col];
                    if ((row + col) & 1) {
                        bucket.insert(bucket.end(), {a, b, c, a, c, d});
                    } else {
                        bucket.insert(bucket.end(), {a, b, d, b, c, d});
                    }
                }
            // Ortho wireframe: just the base quad outline keeps 2D views tidy.
            for (int k = 0; k < 4; ++k) addWire(poly[k], poly[(k + 1) % 4]);
            mesh.drawnFaces++;
            ++dispFacesEmitted;
            continue;
        }

        std::vector<uint32_t> ring;
        ring.reserve(poly.size());
        for (const glm::vec3& p : poly) {
            ring.push_back(addPolyVertexTo(dstVerts, face, ti, p, n, ef, static_cast<float>(tw),
                                           static_cast<float>(th)));
            bmin = glm::min(bmin, p);
            bmax = glm::max(bmax, p);
        }
        for (size_t k = 1; k + 1 < ring.size(); ++k) {
            bucket.push_back(ring[0]);
            bucket.push_back(ring[k]);
            bucket.push_back(ring[k + 1]);
        }
        for (size_t k = 0; k < poly.size(); ++k)
            addWire(poly[k], poly[(k + 1) % poly.size()]);
        mesh.drawnFaces++;
    }

    // Flatten buckets -> single index buffer + batch ranges (opaque first).
    auto flush = [&](std::unordered_map<std::string, std::vector<uint32_t>>& src,
                     bool translucent) {
        for (auto& [mat, idx] : src) {
            if (idx.empty()) continue;
            DrawBatch b;
            b.material = mat;
            b.translucent = translucent;
            b.firstIndex = static_cast<uint32_t>(mesh.indices.size());
            b.indexCount = static_cast<uint32_t>(idx.size());
            mesh.indices.insert(mesh.indices.end(), idx.begin(), idx.end());
            mesh.batches.push_back(std::move(b));
        }
    };
    flush(opaqueIdx, false);
    flush(transIdx, true);

    // Flatten interactive func_door batches
    for (size_t di = 0; di < mesh.doors.size(); ++di) {
        auto& dr = mesh.doors[di];
        auto flushDoor = [&](std::unordered_map<std::string, std::vector<uint32_t>>& src, bool trans) {
            for (auto& [mat, idx] : src) {
                if (idx.empty()) continue;
                DrawBatch b;
                b.material = mat;
                b.translucent = trans;
                b.firstIndex = static_cast<uint32_t>(dr.indices.size());
                b.indexCount = static_cast<uint32_t>(idx.size());
                dr.indices.insert(dr.indices.end(), idx.begin(), idx.end());
                dr.batches.push_back(std::move(b));
            }
        };
        flushDoor(doorOpaque[di], false);
        flushDoor(doorTrans[di], true);
    }

    if (mesh.vertices.empty()) {
        bmin = glm::vec3(-512.0f);
        bmax = glm::vec3(512.0f);
    }
    mesh.boundsMin = bmin;
    mesh.boundsMax = bmax;

    // ---- entities + static props + dynamic/gameplay entity models ----
    // Map targetname -> origin (and func_tracktrain start node) so parented props like
    // pl_upward's Payload Bomb Cart resolve to their exact live track position!
    std::unordered_map<std::string, glm::vec3> targetOrigins;
    for (const auto& ent : bsp.entities()) {
        auto tit = ent.find("targetname");
        auto oit = ent.find("origin");
        if (tit != ent.end() && !tit->second.empty() && oit != ent.end()) {
            targetOrigins[tit->second] = parseVec3(oit->second);
        }
    }
    // Resolve func_tracktrain initial position to its first path_track target when available
    for (const auto& ent : bsp.entities()) {
        auto cit = ent.find("classname");
        auto tit = ent.find("targetname");
        auto tgt = ent.find("target");
        if (cit != ent.end() && cit->second == "func_tracktrain" &&
            tit != ent.end() && !tit->second.empty() &&
            tgt != ent.end() && !tgt->second.empty()) {
            if (auto pt = targetOrigins.find(tgt->second); pt != targetOrigins.end()) {
                targetOrigins[tit->second] = pt->second;
            }
        }
    }

    static const std::unordered_map<std::string, std::string> kItemModels = {
        {"item_healthkit_small",  "models/items/medkit_small.mdl"},
        {"item_healthkit_medium", "models/items/medkit_medium.mdl"},
        {"item_healthkit_full",   "models/items/medkit_large.mdl"},
        {"item_ammopack_small",   "models/items/ammopack_small.mdl"},
        {"item_ammopack_medium",  "models/items/ammopack_medium.mdl"},
        {"item_ammopack_full",    "models/items/ammopack_large.mdl"},
        {"item_teamflag",         "models/flag/briefcase.mdl"},
    };

    size_t dynPropsAdded = 0;
    for (const auto& ent : bsp.entities()) {
        auto cit = ent.find("classname");
        if (cit == ent.end() || cit->second == "worldspawn") continue;
        const std::string& cls = cit->second;
        auto oit = ent.find("origin");
        glm::vec3 pos(0.0f);
        bool hasPos = false;
        if (oit != ent.end()) {
            pos = parseVec3(oit->second);
            hasPos = true;
            PointEntity pe;
            pe.classname = cls;
            auto tit = ent.find("targetname");
            pe.targetname = tit != ent.end() ? tit->second : std::string();
            pe.pos = pos;
            mesh.pointEntities.push_back(std::move(pe));
        }

        // Skip explicitly invisible/disabled entities (rendermode=10 EF_NODRAW or StartDisabled=1)
        if (auto rm = ent.find("rendermode"); rm != ent.end() && rm->second == "10") continue;
        if (auto sd = ent.find("StartDisabled"); sd != ent.end() && sd->second == "1") continue;

        std::string mdlPath;
        if (cls == "prop_dynamic" || cls == "prop_dynamic_override" ||
            cls == "prop_physics" || cls == "prop_physics_multiplayer" ||
            cls == "prop_physics_override" || cls == "prop_ragdoll") {
            if (auto mi = ent.find("model"); mi != ent.end() && !mi->second.empty() && mi->second[0] != '*') {
                mdlPath = mi->second;
            }
        } else if (auto itm = kItemModels.find(cls); itm != kItemModels.end()) {
            mdlPath = itm->second;
            if (auto pm = ent.find("powerup_model"); pm != ent.end() && !pm->second.empty()) {
                mdlPath = pm->second;
            }
        } else if (cls == "team_control_point") {
            // Official TF2 control points place their cap base prop nearby and project hologram here
            if (auto m0 = ent.find("team_model_0"); m0 != ent.end() && !m0->second.empty())
                mdlPath = m0->second;
            else if (auto m2 = ent.find("team_model_2"); m2 != ent.end() && !m2->second.empty())
                mdlPath = m2->second;
            else
                mdlPath = "models/effects/cappoint_hologram.mdl";
        }

        if (!mdlPath.empty()) {
            // Normalize model slashes & check lowercase .mdl suffix
            std::string normMdl = mdlPath;
            std::replace(normMdl.begin(), normMdl.end(), '\\', '/');
            std::string lowMdl = normMdl;
            std::transform(lowMdl.begin(), lowMdl.end(), lowMdl.begin(),
                           [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
            if (lowMdl.size() > 4 && lowMdl.substr(lowMdl.size() - 4) == ".mdl") {
                if (!hasPos) {
                    if (auto pit = ent.find("parentname"); pit != ent.end()) {
                        if (auto po = targetOrigins.find(pit->second); po != targetOrigins.end()) {
                            pos = po->second;
                            hasPos = true;
                        }
                    }
                }
                if (hasPos) {
                    PropInstance pi;
                    pi.model = normMdl;
                    pi.pos = pos;
                    if (auto ai = ent.find("angles"); ai != ent.end()) pi.anglesPYR = parseVec3(ai->second);
                    if (auto sc = ent.find("modelscale"); sc != ent.end()) {
                        float v = static_cast<float>(std::atof(sc->second.c_str()));
                        if (v > 0.05f && v < 25.0f) pi.scale = v;
                    }
                    mesh.props.push_back(std::move(pi));
                    ++dynPropsAdded;
                }
            }
        }
    }
    parseStaticProps(bsp, mesh);
    PB_INFO("  dynamic/gameplay props: %zu, interactive doors: %zu", dynPropsAdded, mesh.doors.size());

    // Representative spawn point for the default 3D camera.
    for (const char* cls : {"info_player_teamspawn", "info_player_start",
                            "info_player_deathmatch", "info_observer_point"}) {
        for (const auto& ent : bsp.entities()) {
            auto cit = ent.find("classname");
            if (cit == ent.end() || cit->second != cls) continue;
            auto oit = ent.find("origin");
            if (oit == ent.end()) continue;
            mesh.spawnPos = parseVec3(oit->second) + glm::vec3(0, 0, 64);
            auto ait = ent.find("angles");
            if (ait != ent.end()) {
                glm::vec3 a = parseVec3(ait->second);
                mesh.spawnYaw = a.y;  // pitch yaw roll
            }
            mesh.hasSpawn = true;
            break;
        }
        if (mesh.hasSpawn) break;
    }

    // Trimmed playable bounds from point-entity positions (robust against the
    // 3D skybox, which sits far from the real map).
    mesh.playBoundsMin = mesh.boundsMin;
    mesh.playBoundsMax = mesh.boundsMax;
    if (mesh.pointEntities.size() >= 12) {
        std::array<std::vector<float>, 3> ax;
        for (const auto& e : mesh.pointEntities) {
            ax[0].push_back(e.pos.x);
            ax[1].push_back(e.pos.y);
            ax[2].push_back(e.pos.z);
        }
        glm::vec3 lo(0.0f), hi(0.0f);
        for (int a = 0; a < 3; ++a) {
            std::sort(ax[a].begin(), ax[a].end());
            const size_t n = ax[a].size();
            const size_t k = std::max<size_t>(1, n / 10);  // 10% / 90%
            lo[a] = ax[a][k];
            hi[a] = ax[a][n - 1 - k];
        }
        PB_INFO("  ent trim x[%.0f..%.0f] y[%.0f..%.0f] z[%.0f..%.0f] (n=%zu)", lo.x,
                hi.x, lo.y, hi.y, lo.z, hi.z, mesh.pointEntities.size());
        // Pad so walls/ceilings around the entities are included.
        const glm::vec3 pad = glm::max(glm::vec3(256.0f), 0.15f * (hi - lo));
        mesh.playBoundsMin = lo - pad;
        mesh.playBoundsMax = hi + pad;
    }

    PB_INFO("World mesh: %zu verts, %zu tris, %zu batches, %zu drawn / %zu skipped faces, "
            "%d displacements, lightmap %dx%d, %zu props, %zu point ents",
            mesh.vertices.size(), mesh.indices.size() / 3, mesh.batches.size(),
            mesh.drawnFaces, mesh.skippedFaces, dispFacesEmitted, mesh.lightmapWidth,
            mesh.lightmapHeight, mesh.props.size(), mesh.pointEntities.size());
    PB_INFO("  geom bounds  %.0f %.0f %.0f -> %.0f %.0f %.0f", mesh.boundsMin.x,
            mesh.boundsMin.y, mesh.boundsMin.z, mesh.boundsMax.x, mesh.boundsMax.y,
            mesh.boundsMax.z);
    PB_INFO("  play bounds  %.0f %.0f %.0f -> %.0f %.0f %.0f", mesh.playBoundsMin.x,
            mesh.playBoundsMin.y, mesh.playBoundsMin.z, mesh.playBoundsMax.x,
            mesh.playBoundsMax.y, mesh.playBoundsMax.z);
    return mesh;
}

}  // namespace pb::bsp
