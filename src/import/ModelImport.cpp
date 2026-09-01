#include "import/ModelImport.h"

#include <cctype>
#include <cstdio>
#include <filesystem>

#include "core/Log.h"
#include "map/Solid.h"

namespace fs = std::filesystem;

namespace pb::import {

namespace {

// One triangle -> a convex triangular prism (5 planes): the tri plane, a back
// cap offset by `t` along -n, and the three edge planes.
map::Solid triPrism(const glm::vec3& a, const glm::vec3& b, const glm::vec3& c,
                    float t, const std::string& mat) {
    glm::vec3 n = glm::cross(b - a, c - a);
    const float len = glm::length(n);
    if (len < 1e-9f) return {};
    n /= len;

    std::vector<std::pair<glm::vec3, float>> planes;
    planes.reserve(5);
    planes.emplace_back(n, glm::dot(n, a));                 // front cap
    planes.emplace_back(-n, glm::dot(-n, a - n * t));       // back cap

    const glm::vec3 tri[3] = {a, b, c};
    for (int e = 0; e < 3; ++e) {
        const glm::vec3& p0 = tri[e];
        const glm::vec3& p1 = tri[(e + 1) % 3];
        const glm::vec3& opp = tri[(e + 2) % 3];
        glm::vec3 en = glm::cross(p1 - p0, n);
        if (glm::length(en) < 1e-9f) continue;
        en = glm::normalize(en);
        if (glm::dot(en, opp - p0) > 0.0f) en = -en;   // point away from the triangle
        planes.emplace_back(en, glm::dot(en, p0));
    }
    if (planes.size() < 4) return {};
    return map::Solid::fromPlanes(planes, mat);
}

std::string sanitise(std::string s) {
    for (auto& ch : s) {
        if (!std::isalnum((unsigned char)ch) && ch != '_' && ch != '-') ch = '_';
        else ch = static_cast<char>(std::tolower((unsigned char)ch));
    }
    if (s.empty()) s = "model";
    return s;
}

}  // namespace

bool meshToDetailEntity(const ObjMesh& mesh, const ModelImportOptions& opt,
                        map::MapDocument& doc, map::MapEntity& out,
                        std::string* err) {
    if (mesh.empty()) {
        if (err) *err = "the mesh has no triangles";
        return false;
    }
    if ((int)mesh.tris.size() > opt.maxTris) {
        if (err)
            *err = "mesh has " + std::to_string(mesh.tris.size()) + " triangles (max " +
                   std::to_string(opt.maxTris) +
                   "); simplify/decimate it first or raise the limit";
        return false;
    }

    const glm::vec3 shift = opt.origin - 0.5f * (mesh.boundsMin + mesh.boundsMax);

    out = map::MapEntity{};
    out.id = doc.nextId();
    out.classname = "func_detail";
    out.kv.set("classname", "func_detail");
    out.origin = opt.origin;

    int made = 0, degenerate = 0;
    for (const auto& tri : mesh.tris) {
        map::Solid s = triPrism(tri.p[0] + shift, tri.p[1] + shift, tri.p[2] + shift,
                                opt.shellThickness, opt.material);
        if (!s.valid) { ++degenerate; continue; }
        s.id = doc.nextId();
        out.solids.push_back(std::move(s));
        ++made;
    }
    if (made == 0) {
        if (err) *err = "every triangle was degenerate after conversion";
        return false;
    }
    PB_INFO("model import: %d detail brushes from %zu tris (%d degenerate skipped)",
            made, mesh.tris.size(), degenerate);
    return true;
}

bool meshToPropStage(const ObjMesh& mesh, const ModelImportOptions& opt,
                     const std::string& stageDir, std::string& outModelPath,
                     std::string& outQcPath, std::string* err) {
    if (mesh.empty()) {
        if (err) *err = "the mesh has no triangles";
        return false;
    }
    std::error_code ec;
    fs::create_directories(stageDir, ec);
    const std::string name = sanitise(mesh.name);
    const fs::path smd = fs::path(stageDir) / (name + ".smd");
    const fs::path idle = fs::path(stageDir) / (name + "_idle.smd");
    const fs::path qc = fs::path(stageDir) / (name + ".qc");

    // Reference SMD: one static bone, all triangles.
    auto writeSmd = [&](const fs::path& p, bool withGeo) -> bool {
        FILE* f = std::fopen(p.string().c_str(), "wb");
        if (!f) return false;
        std::fprintf(f, "version 1\nnodes\n0 \"static_prop\" -1\nend\n");
        std::fprintf(f, "skeleton\ntime 0\n0 0 0 0 0 0 0\nend\n");
        std::fprintf(f, "triangles\n");
        if (withGeo) {
            for (const auto& t : mesh.tris) {
                const std::string mat =
                    (t.material >= 0 && t.material < (int)mesh.materials.size() &&
                     !mesh.materials[t.material].empty())
                        ? mesh.materials[t.material]
                        : "prop_default";
                std::fprintf(f, "%s\n", mat.c_str());
                for (int k = 0; k < 3; ++k)
                    std::fprintf(f,
                                 "0  %.4f %.4f %.4f  %.4f %.4f %.4f  %.5f %.5f\n",
                                 t.p[k].x, t.p[k].y, t.p[k].z, t.n[k].x, t.n[k].y,
                                 t.n[k].z, t.uv[k].x, t.uv[k].y);
            }
        } else {
            // A degenerate placeholder triangle keeps studiomdl happy for the
            // idle sequence.
            std::fprintf(f,
                         "prop_default\n0  0 0 0  0 0 1  0 0\n0  1 0 0  0 0 1  1 0\n"
                         "0  0 1 0  0 0 1  0 1\n");
        }
        std::fprintf(f, "end\n");
        std::fclose(f);
        return true;
    };
    if (!writeSmd(smd, true) || !writeSmd(idle, false)) {
        if (err) *err = "cannot write staged SMD into " + stageDir;
        return false;
    }

    FILE* q = std::fopen(qc.string().c_str(), "wb");
    if (!q) {
        if (err) *err = "cannot write " + qc.string();
        return false;
    }
    std::fprintf(q, "$modelname \"%s/%s.mdl\"\n", opt.propDir.c_str(), name.c_str());
    std::fprintf(q, "$body \"body\" \"%s.smd\"\n", name.c_str());
    std::fprintf(q, "$staticprop\n$surfaceprop \"default\"\n");
    std::fprintf(q, "$cdmaterials \"models/%s\"\n", opt.propDir.c_str());
    std::fprintf(q, "$sequence idle \"%s_idle.smd\" fps 30\n", name.c_str());
    std::fprintf(q, "$collisionmodel \"%s.smd\" { $concave $maxconvexpieces 4096 }\n",
                 name.c_str());
    std::fclose(q);

    outModelPath = "models/" + opt.propDir + "/" + name + ".mdl";
    outQcPath = qc.string();
    PB_INFO("model import: staged prop %s (qc %s)", outModelPath.c_str(),
            outQcPath.c_str());
    return true;
}

}  // namespace pb::import
