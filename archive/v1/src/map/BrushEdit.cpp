#include "map/BrushEdit.h"

#include <algorithm>
#include <cmath>

namespace pb::map {
namespace {

int weldIndex(std::vector<VertHandle>& out, const glm::vec3& p, float weld) {
    const float w2 = weld * weld;
    for (int i = 0; i < static_cast<int>(out.size()); ++i) {
        const glm::vec3 d = out[i].pos - p;
        if (glm::dot(d, d) <= w2) return i;
    }
    out.push_back({p, {}});
    return static_cast<int>(out.size()) - 1;
}

// Newell's method: area-weighted normal of an arbitrary (near-)planar loop.
glm::vec3 newellNormal(const std::vector<glm::vec3>& v) {
    glm::vec3 n(0.0f);
    for (size_t i = 0; i < v.size(); ++i) {
        const glm::vec3& a = v[i];
        const glm::vec3& b = v[(i + 1) % v.size()];
        n.x += (a.y - b.y) * (a.z + b.z);
        n.y += (a.z - b.z) * (a.x + b.x);
        n.z += (a.x - b.x) * (a.y + b.y);
    }
    return n;
}

}  // namespace

BrushHandles extractHandles(const Solid& s, float weld) {
    BrushHandles h;

    for (int f = 0; f < static_cast<int>(s.faces.size()); ++f) {
        const auto& face = s.faces[f];
        for (int vi = 0; vi < static_cast<int>(face.verts.size()); ++vi) {
            const int hi = weldIndex(h.verts, face.verts[vi], weld);
            h.verts[hi].refs.emplace_back(f, vi);
        }
    }

    // Faces: centroid + welded corner indices.
    for (int f = 0; f < static_cast<int>(s.faces.size()); ++f) {
        const auto& face = s.faces[f];
        if (face.verts.size() < 3) continue;
        FaceHandle fh;
        fh.face = f;
        glm::vec3 c(0.0f);
        for (const auto& p : face.verts) {
            c += p;
            fh.verts.push_back(weldIndex(h.verts, p, weld));
        }
        fh.centroid = c / static_cast<float>(face.verts.size());
        h.faces.push_back(std::move(fh));
    }

    // Edges: each face loop segment, de-duplicated by unordered handle pair.
    auto hasEdge = [&](int a, int b) {
        for (const auto& e : h.edges)
            if ((e.a == a && e.b == b) || (e.a == b && e.b == a)) return true;
        return false;
    };
    for (const auto& face : s.faces) {
        const size_t n = face.verts.size();
        if (n < 2) continue;
        for (size_t i = 0; i < n; ++i) {
            const int a = weldIndex(h.verts, face.verts[i], weld);
            const int b = weldIndex(h.verts, face.verts[(i + 1) % n], weld);
            if (a != b && !hasEdge(a, b)) h.edges.push_back({a, b});
        }
    }

    return h;
}

bool moveVertexHandles(Solid& s, const BrushHandles& h,
                       const std::vector<int>& handleIdx, const glm::vec3& delta) {
    if (glm::dot(delta, delta) < 1e-12f) return true;

    std::vector<int> touchedFaces;
    for (int hi : handleIdx) {
        if (hi < 0 || hi >= static_cast<int>(h.verts.size())) continue;
        for (const auto& [f, vi] : h.verts[hi].refs) {
            if (f < 0 || f >= static_cast<int>(s.faces.size())) continue;
            auto& fv = s.faces[f].verts;
            if (vi < 0 || vi >= static_cast<int>(fv.size())) continue;
            fv[vi] += delta;
            if (std::find(touchedFaces.begin(), touchedFaces.end(), f) ==
                touchedFaces.end())
                touchedFaces.push_back(f);
        }
    }

    // Refit each touched face's plane from its updated loop, keeping the old
    // outward orientation.
    for (int f : touchedFaces) {
        auto& face = s.faces[f];
        if (face.verts.size() < 3) return false;
        glm::vec3 n = newellNormal(face.verts);
        const float len = glm::length(n);
        if (len < 1e-6f) return false;
        n /= len;
        if (glm::dot(n, face.planeN) < 0.0f) n = -n;
        glm::vec3 c(0.0f);
        for (const auto& p : face.verts) c += p;
        c /= static_cast<float>(face.verts.size());
        face.planeN = n;
        face.planeD = glm::dot(n, c);
        face.planeFromPoints = false;
        // Refresh the plane triple used for VMF round-trip.
        face.p0 = face.verts[0];
        face.p1 = face.verts.size() > 1 ? face.verts[1] : face.verts[0];
        face.p2 = face.verts.size() > 2 ? face.verts[2] : face.verts[0];
    }

    s.recomputeBounds();
    s.valid = s.faces.size() >= 4;
    return true;
}

}  // namespace pb::map
