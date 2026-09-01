#pragma once
#include <string>
#include <vector>

#include <glm/glm.hpp>

namespace pb::import {

// A triangulated mesh loaded from a Wavefront .obj. Positions are in the file's
// own units/orientation; the importer applies scale + up-axis fixups.
struct ObjMesh {
    struct Tri {
        glm::vec3 p[3];
        glm::vec3 n[3];
        glm::vec2 uv[3];
        int material = 0;   // index into `materials`
    };
    std::vector<Tri> tris;
    std::vector<std::string> materials;   // usemtl names, "" if none
    glm::vec3 boundsMin{0}, boundsMax{0};
    std::string name;

    bool empty() const { return tris.empty(); }
    glm::vec3 size() const { return boundsMax - boundsMin; }
    void recomputeBounds();
};

struct ObjLoadOptions {
    float scale = 1.0f;          // multiplied onto every position
    bool yUpToZUp = true;        // most DCC exports are Y-up; Source is Z-up
    bool flipWinding = false;
    bool recomputeNormals = false;  // ignore file normals, derive from faces
};

// Parses `path`. Returns false (with *err set) on a read/parse failure.
bool loadObj(const std::string& path, const ObjLoadOptions& opt, ObjMesh& out,
             std::string* err = nullptr);

}  // namespace pb::import
