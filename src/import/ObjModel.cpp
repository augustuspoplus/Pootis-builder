#include "import/ObjModel.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <sstream>

#include "core/File.h"
#include "core/Log.h"

namespace fs = std::filesystem;

namespace pb::import {

void ObjMesh::recomputeBounds() {
    if (tris.empty()) {
        boundsMin = boundsMax = glm::vec3(0);
        return;
    }
    glm::vec3 mn(1e30f), mx(-1e30f);
    for (const auto& t : tris)
        for (int i = 0; i < 3; ++i) {
            mn = glm::min(mn, t.p[i]);
            mx = glm::max(mx, t.p[i]);
        }
    boundsMin = mn;
    boundsMax = mx;
}

namespace {

// One "f" vertex reference: v/vt/vn (any of vt/vn may be absent, indices 1-based
// and may be negative = relative to the end).
struct FaceRef {
    int v = 0, vt = 0, vn = 0;
};

FaceRef parseRef(const char* s, const char* end) {
    FaceRef r;
    r.v = std::atoi(s);
    const char* slash = static_cast<const char*>(std::memchr(s, '/', end - s));
    if (!slash) return r;
    const char* a = slash + 1;
    if (a < end && *a != '/') r.vt = std::atoi(a);
    const char* slash2 = static_cast<const char*>(std::memchr(a, '/', end - a));
    if (slash2 && slash2 + 1 < end) r.vn = std::atoi(slash2 + 1);
    return r;
}

int resolve(int idx, size_t count) {
    if (idx > 0) return idx - 1;
    if (idx < 0) return static_cast<int>(count) + idx;
    return -1;
}

}  // namespace

bool loadObj(const std::string& path, const ObjLoadOptions& opt, ObjMesh& out,
             std::string* err) {
    const std::string text = readTextFile(path);
    if (text.empty()) {
        if (err) *err = "cannot read " + path;
        return false;
    }

    std::vector<glm::vec3> pos;
    std::vector<glm::vec3> nrm;
    std::vector<glm::vec2> uv;
    out = ObjMesh{};
    out.name = fs::path(path).stem().string();
    out.materials.push_back("");
    int curMat = 0;

    auto fixup = [&](glm::vec3 p) {
        p *= opt.scale;
        if (opt.yUpToZUp) p = glm::vec3(p.x, -p.z, p.y);
        return p;
    };
    auto fixupDir = [&](glm::vec3 d) {
        if (opt.yUpToZUp) d = glm::vec3(d.x, -d.z, d.y);
        const float len = glm::length(d);
        return len > 1e-8f ? d / len : glm::vec3(0, 0, 1);
    };

    std::istringstream in(text);
    std::string line;
    size_t nfaces = 0;
    while (std::getline(in, line)) {
        if (line.empty() || line[0] == '#') continue;
        const char* c = line.c_str();
        while (*c == ' ' || *c == '\t') ++c;

        if (c[0] == 'v' && c[1] == ' ') {
            glm::vec3 p(0);
            std::sscanf(c + 2, "%f %f %f", &p.x, &p.y, &p.z);
            pos.push_back(p);
        } else if (c[0] == 'v' && c[1] == 'n' && c[2] == ' ') {
            glm::vec3 n(0);
            std::sscanf(c + 3, "%f %f %f", &n.x, &n.y, &n.z);
            nrm.push_back(n);
        } else if (c[0] == 'v' && c[1] == 't' && c[2] == ' ') {
            glm::vec2 t(0);
            std::sscanf(c + 3, "%f %f", &t.x, &t.y);
            uv.push_back(t);
        } else if (c[0] == 'f' && (c[1] == ' ' || c[1] == '\t')) {
            // Collect all vertex refs on the line, then fan-triangulate.
            std::vector<FaceRef> refs;
            const char* p = c + 2;
            const char* lineEnd = line.c_str() + line.size();
            while (p < lineEnd) {
                while (p < lineEnd && (*p == ' ' || *p == '\t')) ++p;
                if (p >= lineEnd) break;
                const char* tok = p;
                while (p < lineEnd && *p != ' ' && *p != '\t') ++p;
                refs.push_back(parseRef(tok, p));
            }
            if (refs.size() < 3) continue;
            ++nfaces;
            for (size_t i = 1; i + 1 < refs.size(); ++i) {
                ObjMesh::Tri tri;
                tri.material = curMat;
                const FaceRef fr[3] = {refs[0], refs[i], refs[i + 1]};
                for (int k = 0; k < 3; ++k) {
                    const int vi = resolve(fr[k].v, pos.size());
                    tri.p[k] = (vi >= 0 && vi < (int)pos.size())
                                   ? fixup(pos[vi])
                                   : glm::vec3(0);
                    const int ti = resolve(fr[k].vt, uv.size());
                    tri.uv[k] = (ti >= 0 && ti < (int)uv.size()) ? uv[ti]
                                                                 : glm::vec2(0);
                    const int ni = resolve(fr[k].vn, nrm.size());
                    tri.n[k] = (ni >= 0 && ni < (int)nrm.size()) ? fixupDir(nrm[ni])
                                                                 : glm::vec3(0);
                }
                if (opt.flipWinding) {
                    std::swap(tri.p[1], tri.p[2]);
                    std::swap(tri.uv[1], tri.uv[2]);
                    std::swap(tri.n[1], tri.n[2]);
                }
                if (opt.recomputeNormals || nrm.empty()) {
                    const glm::vec3 fn = glm::normalize(
                        glm::cross(tri.p[1] - tri.p[0], tri.p[2] - tri.p[0]));
                    tri.n[0] = tri.n[1] = tri.n[2] = fn;
                }
                out.tris.push_back(tri);
            }
        } else if (std::strncmp(c, "usemtl", 6) == 0) {
            std::string m = line.substr(line.find("usemtl") + 6);
            while (!m.empty() && (m.front() == ' ' || m.front() == '\t')) m.erase(m.begin());
            while (!m.empty() && (m.back() == '\r' || m.back() == '\n' || m.back() == ' '))
                m.pop_back();
            int found = -1;
            for (size_t k = 0; k < out.materials.size(); ++k)
                if (out.materials[k] == m) found = (int)k;
            if (found < 0) {
                found = (int)out.materials.size();
                out.materials.push_back(m);
            }
            curMat = found;
        }
    }

    out.recomputeBounds();
    if (out.tris.empty()) {
        if (err) *err = "no faces in " + path;
        return false;
    }
    PB_INFO("obj: %s — %zu faces -> %zu tris, %zu verts, bounds %.0f x %.0f x %.0f",
            out.name.c_str(), nfaces, out.tris.size(), pos.size(), out.size().x,
            out.size().y, out.size().z);
    return true;
}

}  // namespace pb::import
