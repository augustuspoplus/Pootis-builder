#include "map/MapMesh.h"

#include <algorithm>
#include <array>
#include <cmath>
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

void emitSolid(const Solid& s, MaterialLibrary& mats, const glm::vec3& off,
               std::unordered_map<std::string, std::vector<uint32_t>>& buckets,
               WorldMesh& mesh, glm::vec3& bmin, glm::vec3& bmax) {
    for (const auto& f : s.faces) {
        if (f.verts.size() < 3) continue;
        if (skipFaceMaterial(f.material)) continue;
        const auto& info = mats.get(f.material);
        const float tw = info.width > 0 ? float(info.width) : 128.0f;
        const float th = info.height > 0 ? float(info.height) : 128.0f;
        glm::vec3 n = f.planeN;
        const float shade = flatShade(n);

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

WorldMesh buildDocMesh(const MapDocument& doc, MaterialLibrary& materials) {
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
