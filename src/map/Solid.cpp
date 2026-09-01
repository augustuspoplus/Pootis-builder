#include "map/Solid.h"

#include <algorithm>
#include <cmath>
#include <cstdio>

#include <glm/gtc/matrix_inverse.hpp>
#include <glm/gtc/matrix_transform.hpp>

#include "core/Log.h"

namespace pb::map {
namespace {

constexpr float kBig = 65536.0f;
constexpr float kEps = 0.01f;

glm::vec3 parseVec3(const std::string& s, glm::vec3 def = glm::vec3(0)) {
    glm::vec3 v = def;
    std::sscanf(s.c_str(), " ( %f %f %f )", &v.x, &v.y, &v.z);
    if (v == def) std::sscanf(s.c_str(), " %f %f %f", &v.x, &v.y, &v.z);
    return v;
}

// "[x y z off] scale"
void parseAxis(const std::string& s, glm::vec4& axis, float& scale) {
    float x, y, z, off, sc;
    if (std::sscanf(s.c_str(), " [ %f %f %f %f ] %f", &x, &y, &z, &off, &sc) == 5) {
        axis = {x, y, z, off};
        scale = sc == 0.0f ? 0.25f : sc;
    }
}

void planeFromPoints(BrushFace& f) {
    // VMF points are clockwise viewed from the front; this normal points out.
    const glm::vec3 n = glm::cross(f.p0 - f.p1, f.p2 - f.p1);
    const float len = glm::length(n);
    if (len > 1e-6f) {
        f.planeN = n / len;
        f.planeD = glm::dot(f.planeN, f.p1);
    }
}

// Sutherland-Hodgman clip of `poly` to the half-space dot(n,p) <= d.
void clipToHalfspace(std::vector<glm::vec3>& poly, const glm::vec3& n, float d) {
    if (poly.size() < 3) return;
    std::vector<glm::vec3> out;
    out.reserve(poly.size() + 4);
    for (size_t i = 0; i < poly.size(); ++i) {
        const glm::vec3& a = poly[i];
        const glm::vec3& b = poly[(i + 1) % poly.size()];
        const float da = glm::dot(n, a) - d;
        const float db = glm::dot(n, b) - d;
        const bool ina = da <= kEps;
        const bool inb = db <= kEps;
        if (ina) out.push_back(a);
        if (ina != inb) {
            const float t = da / (da - db);
            out.push_back(a + t * (b - a));
        }
    }
    poly.swap(out);
}

}  // namespace

glm::vec2 BrushFace::texUV(const glm::vec3& pos, float texW, float texH) const {
    const float u = (glm::dot(pos, glm::vec3(uAxis)) + uAxis.w) / (uScale * texW);
    const float v = (glm::dot(pos, glm::vec3(vAxis)) + vAxis.w) / (vScale * texH);
    return {u, v};
}

void Solid::polygonise() {
    valid = false;
    for (auto& f : faces) f.verts.clear();
    if (faces.size() < 4) return;

    for (size_t i = 0; i < faces.size(); ++i) {
        BrushFace& fi = faces[i];
        // A large quad on plane i, oriented CCW around fi.planeN.
        glm::vec3 up = std::fabs(fi.planeN.z) < 0.99f ? glm::vec3(0, 0, 1)
                                                      : glm::vec3(1, 0, 0);
        glm::vec3 u = glm::normalize(glm::cross(up, fi.planeN));
        glm::vec3 v = glm::cross(fi.planeN, u);
        glm::vec3 c = fi.planeN * fi.planeD;
        std::vector<glm::vec3> poly = {
            c - u * kBig - v * kBig,
            c + u * kBig - v * kBig,
            c + u * kBig + v * kBig,
            c - u * kBig + v * kBig,
        };
        for (size_t j = 0; j < faces.size() && poly.size() >= 3; ++j) {
            if (j == i) continue;
            clipToHalfspace(poly, faces[j].planeN, faces[j].planeD);
        }
        if (poly.size() >= 3) fi.verts = std::move(poly);
    }

    int good = 0;
    for (const auto& f : faces)
        if (f.verts.size() >= 3) ++good;
    valid = good >= 4;
    recomputeBounds();
}

void Solid::recomputeBounds() {
    glm::vec3 mn(1e30f), mx(-1e30f);
    for (const auto& f : faces)
        for (const auto& p : f.verts) {
            mn = glm::min(mn, p);
            mx = glm::max(mx, p);
        }
    if (mn.x > mx.x) {
        mn = glm::vec3(0);
        mx = glm::vec3(0);
    }
    boundsMin = mn;
    boundsMax = mx;
}

void Solid::translate(const glm::vec3& dv) {
    for (auto& f : faces) {
        f.planeD += glm::dot(f.planeN, dv);
        f.p0 += dv;
        f.p1 += dv;
        f.p2 += dv;
        f.uAxis.w -= glm::dot(dv, glm::vec3(f.uAxis)) / f.uScale;
        f.vAxis.w -= glm::dot(dv, glm::vec3(f.vAxis)) / f.vScale;
        for (auto& p : f.verts) p += dv;
    }
    boundsMin += dv;
    boundsMax += dv;
}

void Solid::transform(const glm::mat4& m) {
    const glm::mat3 nm = glm::inverseTranspose(glm::mat3(m));
    for (auto& f : faces) {
        f.p0 = glm::vec3(m * glm::vec4(f.p0, 1.0f));
        f.p1 = glm::vec3(m * glm::vec4(f.p1, 1.0f));
        f.p2 = glm::vec3(m * glm::vec4(f.p2, 1.0f));
        for (auto& p : f.verts) p = glm::vec3(m * glm::vec4(p, 1.0f));
        f.planeN = glm::normalize(nm * f.planeN);
        if (!f.verts.empty()) f.planeD = glm::dot(f.planeN, f.verts[0]);
        // UV axes rotate with the solid (offsets left as-is — good enough for now).
        f.uAxis = glm::vec4(glm::normalize(glm::mat3(m) * glm::vec3(f.uAxis)), f.uAxis.w);
        f.vAxis = glm::vec4(glm::normalize(glm::mat3(m) * glm::vec3(f.vAxis)), f.vAxis.w);
    }
    recomputeBounds();
}

void Solid::resizeTo(const glm::vec3& newMin, const glm::vec3& newMax) {
    const glm::vec3 oldSize = glm::max(boundsMax - boundsMin, glm::vec3(1e-4f));
    const glm::vec3 newSize = glm::max(newMax - newMin, glm::vec3(1e-4f));
    const glm::vec3 s = newSize / oldSize;
    glm::mat4 m(1.0f);
    m = glm::translate(m, newMin);
    m = glm::scale(m, s);
    m = glm::translate(m, -boundsMin);
    transform(m);
}

Solid Solid::makeBox(const glm::vec3& mn, const glm::vec3& mx,
                     const std::string& material) {
    Solid s;
    struct FaceDef {
        glm::vec3 n;
        glm::vec4 u, v;
    };
    const FaceDef defs[6] = {
        {{0, 0, 1}, {1, 0, 0, 0}, {0, -1, 0, 0}},   // top
        {{0, 0, -1}, {1, 0, 0, 0}, {0, -1, 0, 0}},  // bottom
        {{1, 0, 0}, {0, 1, 0, 0}, {0, 0, -1, 0}},   // +x
        {{-1, 0, 0}, {0, 1, 0, 0}, {0, 0, -1, 0}},  // -x
        {{0, 1, 0}, {1, 0, 0, 0}, {0, 0, -1, 0}},   // +y
        {{0, -1, 0}, {1, 0, 0, 0}, {0, 0, -1, 0}},  // -y
    };
    for (const auto& d : defs) {
        BrushFace f;
        f.planeN = d.n;
        const glm::vec3 corner{d.n.x > 0 ? mx.x : mn.x, d.n.y > 0 ? mx.y : mn.y,
                               d.n.z > 0 ? mx.z : mn.z};
        f.planeD = glm::dot(d.n, corner);
        f.material = material;
        f.uAxis = d.u;
        f.vAxis = d.v;
        f.planeFromPoints = false;
        s.faces.push_back(f);
    }
    s.polygonise();
    return s;
}

Solid solidFromKv(const KvNode& node) {
    Solid s;
    s.id = node.getInt("id");
    for (const auto& c : node.children) {
        if (c.name == "side") {
            BrushFace f;
            const std::string plane = c.get("plane");
            // "(x y z) (x y z) (x y z)"
            float a[9] = {0};
            if (std::sscanf(plane.c_str(),
                            " ( %f %f %f ) ( %f %f %f ) ( %f %f %f )", &a[0], &a[1],
                            &a[2], &a[3], &a[4], &a[5], &a[6], &a[7], &a[8]) == 9) {
                f.p0 = {a[0], a[1], a[2]};
                f.p1 = {a[3], a[4], a[5]};
                f.p2 = {a[6], a[7], a[8]};
                planeFromPoints(f);
            }
            f.material = c.get("material", "tools/toolsnodraw");
            parseAxis(c.get("uaxis"), f.uAxis, f.uScale);
            parseAxis(c.get("vaxis"), f.vAxis, f.vScale);
            f.rotation = c.getFloat("rotation");
            f.lightmapScale = c.getFloat("lightmapscale", 16.0f);
            f.smoothingGroups = c.getInt("smoothing_groups");
            s.faces.push_back(std::move(f));
        } else if (c.name == "editor") {
            s.extra = c;
            const std::string col = c.get("color");
            glm::vec3 rgb(180);
            if (std::sscanf(col.c_str(), " %f %f %f", &rgb.x, &rgb.y, &rgb.z) == 3)
                s.editorColor = rgb / 255.0f;
        }
    }
    s.polygonise();
    return s;
}

KvNode solidToKv(const Solid& s) {
    KvNode n;
    n.name = "solid";
    n.set("id", std::to_string(s.id));
    char buf[256];
    for (const auto& f : s.faces) {
        KvNode side;
        side.name = "side";
        std::snprintf(buf, sizeof(buf), "(%g %g %g) (%g %g %g) (%g %g %g)", f.p0.x,
                      f.p0.y, f.p0.z, f.p1.x, f.p1.y, f.p1.z, f.p2.x, f.p2.y, f.p2.z);
        side.set("plane", buf);
        side.set("material", f.material);
        std::snprintf(buf, sizeof(buf), "[%g %g %g %g] %g", f.uAxis.x, f.uAxis.y,
                      f.uAxis.z, f.uAxis.w, f.uScale);
        side.set("uaxis", buf);
        std::snprintf(buf, sizeof(buf), "[%g %g %g %g] %g", f.vAxis.x, f.vAxis.y,
                      f.vAxis.z, f.vAxis.w, f.vScale);
        side.set("vaxis", buf);
        side.set("rotation", std::to_string(static_cast<int>(f.rotation)));
        side.set("lightmapscale", std::to_string(static_cast<int>(f.lightmapScale)));
        side.set("smoothing_groups", std::to_string(f.smoothingGroups));
        n.children.push_back(std::move(side));
    }
    return n;
}

}  // namespace pb::map
