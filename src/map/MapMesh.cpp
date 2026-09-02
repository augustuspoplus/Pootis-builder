#include "map/MapMesh.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <sstream>
#include <unordered_map>

#include "core/Log.h"

namespace pb::map {
namespace {

using bsp::DrawBatch;
using bsp::WorldMesh;
using bsp::WorldVertex;

bool skipFaceMaterial(const std::string& m) {
    return m == "tools/toolsnodraw" || m == "tools/toolsskip" ||
           m == "tools/toolshint" || m == "tools/toolsareaportal" ||
           m == "tools/toolsskybox" || m == "tools/toolsblocklight" ||
           m == "tools/toolsblack";
}

// Trigger / clip / occluder tool brushes render see-through, like Hammer.
bool translucentMaterial(const std::string& m) {
    return m.rfind("tools/", 0) == 0 || m.rfind("glass/", 0) == 0 ||
           m.find("water") != std::string::npos ||
           m.find("trigger") != std::string::npos;
}

float flatShade(const glm::vec3& n) {
    static const glm::vec3 key = glm::normalize(glm::vec3(0.35f, 0.45f, 0.82f));
    return 0.42f + 0.58f * std::clamp(glm::dot(glm::normalize(n), key), 0.0f, 1.0f);
}

// Read a dispinfo sub-block ("normals" / "distances" / "offsets") whose rows are
// "row0" .. "row<gn-1>", each a run of gn*comp space-separated floats.
bool readDispRows(const KvNode* blk, int gn, int comp, std::vector<float>& out) {
    if (!blk) return false;
    out.assign(static_cast<size_t>(gn) * gn * comp, 0.0f);
    for (int r = 0; r < gn; ++r) {
        char key[16];
        std::snprintf(key, sizeof(key), "row%d", r);
        const std::string s = blk->get(key);
        if (s.empty()) return false;
        std::istringstream is(s);
        for (int i = 0; i < gn * comp; ++i)
            if (!(is >> out[static_cast<size_t>(r) * gn * comp + i])) return false;
    }
    return true;
}

// Tessellate one displacement face into `mesh`. Returns false if the dispinfo is
// unusable (caller then falls back to the flat face).
bool emitDispFace(const BrushFace& f, const glm::vec3& off, float tw, float th,
                  std::vector<uint32_t>& idxBucket, WorldMesh& mesh, glm::vec3& bmin,
                  glm::vec3& bmax) {
    const int power = f.dispInfo.getInt("power");
    if (power < 2 || power > 4 || f.verts.size() < 4) return false;
    const int gn = (1 << power) + 1;

    std::vector<float> nrm, dst, ofs;
    if (!readDispRows(f.dispInfo.child("normals"), gn, 3, nrm)) return false;
    if (!readDispRows(f.dispInfo.child("distances"), gn, 1, dst)) return false;
    readDispRows(f.dispInfo.child("offsets"), gn, 3, ofs);  // optional
    const bool haveOfs = ofs.size() == nrm.size();

    glm::vec3 start(0.0f);
    std::sscanf(f.dispInfo.get("startposition").c_str(), " [ %f %f %f ]", &start.x,
                &start.y, &start.z);

    // Corner 0 = the polygonised vertex nearest startposition. f.verts is CCW
    // around the normal, so walk forward for the base quad.
    int c0 = 0;
    float bestD = 1e30f;
    for (int k = 0; k < 4; ++k) {
        const float d = glm::distance(f.verts[k], start);
        if (d < bestD) { bestD = d; c0 = k; }
    }
    const glm::vec3 A = f.verts[c0];
    const glm::vec3 B = f.verts[(c0 + 1) % 4];  // col axis (u)
    const glm::vec3 C = f.verts[(c0 + 2) % 4];  // diagonal
    const glm::vec3 D = f.verts[(c0 + 3) % 4];  // row axis (v)
    const float shade = flatShade(f.planeN);

    std::vector<uint32_t> g(static_cast<size_t>(gn) * gn);
    for (int row = 0; row < gn; ++row) {
        const float tb = float(row) / (gn - 1);
        const glm::vec3 e0 = A + (D - A) * tb;
        const glm::vec3 e1 = B + (C - B) * tb;
        for (int col = 0; col < gn; ++col) {
            const float ta = float(col) / (gn - 1);
            glm::vec3 p = e0 + (e1 - e0) * ta;
            const int i = row * gn + col;
            p += glm::vec3(nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2]) * dst[i];
            if (haveOfs) p += glm::vec3(ofs[i * 3], ofs[i * 3 + 1], ofs[i * 3 + 2]);
            p += off;
            WorldVertex v;
            v.pos = p;
            v.normal = f.planeN;
            v.uv = {0.5f / 8.0f, 0.5f / 8.0f};
            v.texUv = f.texUV(p, tw, th);
            v.tint = glm::vec3(shade);
            g[i] = static_cast<uint32_t>(mesh.vertices.size());
            mesh.vertices.push_back(v);
            bmin = glm::min(bmin, p);
            bmax = glm::max(bmax, p);
        }
    }
    for (int row = 0; row + 1 < gn; ++row)
        for (int col = 0; col + 1 < gn; ++col) {
            const uint32_t a = g[row * gn + col];
            const uint32_t b = g[row * gn + col + 1];
            const uint32_t c = g[(row + 1) * gn + col + 1];
            const uint32_t d = g[(row + 1) * gn + col];
            if ((row + col) & 1)
                idxBucket.insert(idxBucket.end(), {a, b, c, a, c, d});
            else
                idxBucket.insert(idxBucket.end(), {a, b, d, b, c, d});
        }
    // 2D wireframe: just the base-quad outline keeps the ortho views readable.
    for (int k = 0; k < 4; ++k) {
        mesh.wireLines.push_back(f.verts[k] + off);
        mesh.wireLines.push_back(f.verts[(k + 1) % 4] + off);
    }
    return true;
}

void emitSolid(const Solid& s, MaterialLibrary& mats, const glm::vec3& off,
               std::unordered_map<std::string, std::vector<uint32_t>>& buckets,
               WorldMesh& mesh, glm::vec3& bmin, glm::vec3& bmax) {
    // A brush with any displacement face is a "displacement solid": only its
    // displacement surfaces are visible, the other 5 backing faces are not.
    bool dispSolid = false;
    for (const auto& f : s.faces) dispSolid = dispSolid || f.hasDisp;

    for (const auto& f : s.faces) {
        if (f.verts.size() < 3) continue;
        if (dispSolid && !f.hasDisp) continue;
        if (skipFaceMaterial(f.material)) continue;
        const auto& info = mats.get(f.material);
        const float tw = info.width > 0 ? float(info.width) : 128.0f;
        const float th = info.height > 0 ? float(info.height) : 128.0f;
        glm::vec3 n = f.planeN;
        const float shade = flatShade(n);

        // Displacement face: tessellate the power grid instead of a flat fan.
        if (f.hasDisp &&
            emitDispFace(f, off, tw, th, buckets[f.material], mesh, bmin, bmax))
            continue;

        std::vector<uint32_t> ring;
        ring.reserve(f.verts.size());
        for (const glm::vec3& vp : f.verts) {
            const glm::vec3 p = vp + off;
            WorldVertex v;
            v.pos = p;
            v.normal = n;
            v.uv = {0.5f / 8.0f, 0.5f / 8.0f};  // white texel in the tiny atlas
            v.texUv = f.texUV(p, tw, th);
            v.tint = glm::vec3(shade);
            ring.push_back(static_cast<uint32_t>(mesh.vertices.size()));
            mesh.vertices.push_back(v);
            bmin = glm::min(bmin, p);
            bmax = glm::max(bmax, p);
        }
        auto& idx = buckets[f.material];
        for (size_t k = 1; k + 1 < ring.size(); ++k) {
            idx.push_back(ring[0]);
            idx.push_back(ring[k]);
            idx.push_back(ring[k + 1]);
        }
        for (size_t k = 0; k < f.verts.size(); ++k) {
            mesh.wireLines.push_back(f.verts[k] + off);
            mesh.wireLines.push_back(f.verts[(k + 1) % f.verts.size()] + off);
        }
    }
}

}  // namespace

std::vector<glm::vec3> solidWire(const Solid& s) {
    std::vector<glm::vec3> out;
    for (const auto& f : s.faces)
        for (size_t k = 0; k < f.verts.size(); ++k) {
            out.push_back(f.verts[k]);
            out.push_back(f.verts[(k + 1) % f.verts.size()]);
        }
    return out;
}

WorldMesh buildDocMesh(const MapDocument& doc, MaterialLibrary& materials,
                       const ModelForClass& modelForClass) {
    WorldMesh mesh;

    // 8x8 white lightmap atlas so the shared shader's lightmap sample == 1.
    mesh.lightmapWidth = mesh.lightmapHeight = 8;
    mesh.lightmapAtlas.assign(8 * 8 * 3, 255);

    std::unordered_map<std::string, std::vector<uint32_t>> buckets;
    glm::vec3 bmin(1e30f), bmax(-1e30f);

    for (const auto& s : doc.worldSolids())
        if (s.valid && !s.hidden)
            emitSolid(s, materials, glm::vec3(0), buckets, mesh, bmin, bmax);

    for (const auto& e : doc.entities()) {
        if (e.hidden) continue;
        for (const auto& s : e.solids)
            if (s.valid && !s.hidden)
                emitSolid(s, materials, glm::vec3(0), buckets, mesh, bmin, bmax);
    }

    for (auto& [mat, idx] : buckets) {
        if (idx.empty()) continue;
        DrawBatch b;
        b.material = mat;
        b.firstIndex = static_cast<uint32_t>(mesh.indices.size());
        b.indexCount = static_cast<uint32_t>(idx.size());
        b.translucent = translucentMaterial(mat);
        mesh.indices.insert(mesh.indices.end(), idx.begin(), idx.end());
        mesh.batches.push_back(std::move(b));
    }

    if (mesh.vertices.empty()) {
        bmin = glm::vec3(-256);
        bmax = glm::vec3(256);
    }
    mesh.boundsMin = bmin;
    mesh.boundsMax = bmax;

    // Point entities + spawn framing.
    std::array<std::vector<float>, 3> ax;
    for (const auto& e : doc.entities()) {
        if (!e.solids.empty() || e.hidden) continue;

        // Bake a real model for prop_* (its model key) and for any point
        // entity the FGD gives a studio() helper (health kits, ammo, flags…),
        // so the doc render shows the model instead of a plain box.
        std::string mdl = e.kv.get("model");
        if (mdl.empty() && e.classname.rfind("prop_", 0) != 0 && modelForClass)
            mdl = modelForClass(e.classname);
        if (mdl.empty())  // any *.mdl-valued key (flag_model, etc.)
            for (const auto& kv : e.kv.pairs)
                if (kv.second.size() > 4 &&
                    kv.second.compare(kv.second.size() - 4, 4, ".mdl") == 0) {
                    mdl = kv.second;
                    break;
                }
        if (!mdl.empty()) {
            bsp::PropInstance pi;
            pi.model = mdl;
            pi.pos = e.origin;
            float p = 0, y = 0, r = 0;
            std::sscanf(e.kv.get("angles").c_str(), "%f %f %f", &p, &y, &r);
            pi.anglesPYR = {p, y, r};
            pi.scale = e.kv.getFloat("modelscale");
            if (pi.scale <= 0.01f) pi.scale = 1.0f;
            mesh.props.push_back(std::move(pi));
        }

        bsp::PointEntity pe;
        pe.classname = e.classname;
        pe.targetname = e.targetname();
        pe.pos = e.origin;
        mesh.pointEntities.push_back(std::move(pe));
        ax[0].push_back(e.origin.x);
        ax[1].push_back(e.origin.y);
        ax[2].push_back(e.origin.z);
        if ((e.classname == "info_player_teamspawn" ||
             e.classname == "info_player_start") &&
            !mesh.hasSpawn) {
            mesh.hasSpawn = true;
            mesh.spawnPos = e.origin + glm::vec3(0, 0, 64);
            mesh.spawnYaw = e.kv.getFloat("angles") ? 0.0f : 0.0f;
        }
    }

    mesh.playBoundsMin = mesh.boundsMin;
    mesh.playBoundsMax = mesh.boundsMax;
    if (ax[0].size() >= 8) {
        glm::vec3 lo(0), hi(0);
        for (int a = 0; a < 3; ++a) {
            std::sort(ax[a].begin(), ax[a].end());
            const size_t n = ax[a].size();
            const size_t k = std::max<size_t>(1, n / 10);
            lo[a] = ax[a][k];
            hi[a] = ax[a][n - 1 - k];
        }
        const glm::vec3 pad = glm::max(glm::vec3(256.0f), 0.15f * (hi - lo));
        mesh.playBoundsMin = lo - pad;
        mesh.playBoundsMax = hi + pad;
    }

    mesh.drawnFaces = mesh.indices.size() / 3;
    PB_INFO("Doc mesh: %zu verts, %zu tris, %zu batches, %zu point ents",
            mesh.vertices.size(), mesh.indices.size() / 3, mesh.batches.size(),
            mesh.pointEntities.size());
    return mesh;
}

}  // namespace pb::map
