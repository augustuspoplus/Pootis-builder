#include "map/Raycast.h"

#include <algorithm>
#include <cmath>

namespace pb::map {

bool rayAabb(const glm::vec3& ro, const glm::vec3& rd, const glm::vec3& mn,
             const glm::vec3& mx, float& tHit) {
    float tmin = 0.0f, tmax = 1e30f;
    for (int a = 0; a < 3; ++a) {
        if (std::fabs(rd[a]) < 1e-9f) {
            if (ro[a] < mn[a] || ro[a] > mx[a]) return false;
        } else {
            float inv = 1.0f / rd[a];
            float t1 = (mn[a] - ro[a]) * inv;
            float t2 = (mx[a] - ro[a]) * inv;
            if (t1 > t2) std::swap(t1, t2);
            tmin = std::max(tmin, t1);
            tmax = std::min(tmax, t2);
            if (tmin > tmax) return false;
        }
    }
    tHit = tmin;
    return true;
}

namespace {
bool rayTri(const glm::vec3& ro, const glm::vec3& rd, const glm::vec3& a,
            const glm::vec3& b, const glm::vec3& c, float& t) {
    const glm::vec3 e1 = b - a, e2 = c - a;
    const glm::vec3 p = glm::cross(rd, e2);
    const float det = glm::dot(e1, p);
    if (std::fabs(det) < 1e-8f) return false;
    const float inv = 1.0f / det;
    const glm::vec3 tv = ro - a;
    const float u = glm::dot(tv, p) * inv;
    if (u < -1e-4f || u > 1.0f + 1e-4f) return false;
    const glm::vec3 q = glm::cross(tv, e1);
    const float v = glm::dot(rd, q) * inv;
    if (v < -1e-4f || u + v > 1.0f + 1e-4f) return false;
    const float tt = glm::dot(e2, q) * inv;
    if (tt <= 1e-4f) return false;
    t = tt;
    return true;
}
}  // namespace

bool raySolid(const glm::vec3& ro, const glm::vec3& rd, const Solid& s, float& tHit) {
    float box;
    if (!rayAabb(ro, rd, s.boundsMin - glm::vec3(0.5f), s.boundsMax + glm::vec3(0.5f),
                 box))
        return false;

    bool hit = false;
    float best = 1e30f;
    for (const auto& f : s.faces) {
        for (size_t k = 1; k + 1 < f.verts.size(); ++k) {
            float t;
            if (rayTri(ro, rd, f.verts[0], f.verts[k], f.verts[k + 1], t) && t < best) {
                best = t;
                hit = true;
            }
        }
    }
    if (hit) tHit = best;
    return hit;
}

}  // namespace pb::map
