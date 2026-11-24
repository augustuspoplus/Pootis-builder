#pragma once
#include <string>
#include <vector>

#include <glm/glm.hpp>

namespace pb::source {
class SourceFs;
}
namespace pb::bsp {
struct WorldMesh;
}

namespace pb::model {

struct StudioVertex {
    glm::vec3 pos{0};
    glm::vec3 normal{0, 0, 1};
    glm::vec2 uv{0};
};

// One drawable chunk of a model: a triangle-index range into `verts` that all
// share one material.
struct StudioMesh {
    std::string material;   // resolved "<cdmaterial><texname>" (no .vmt)
    uint32_t firstIndex = 0;
    uint32_t indexCount = 0;
};

struct StudioModel {
    bool ok = false;
    std::vector<StudioVertex> verts;
    std::vector<uint32_t> indices;
    std::vector<StudioMesh> meshes;
    glm::vec3 boundsMin{0}, boundsMax{0};
};

// Loads <mdlPath> plus its .vvd / .dx90.vtx siblings from the mounted game
// content. LOD 0 only, bind pose (static props are rigid). Results are cached
// by path; a failed load returns an empty model with ok=false (caller should
// fall back to a box).
const StudioModel& loadStudioModel(source::SourceFs& fs, const std::string& mdlPath);

void clearModelCache();

// Debug: log one model's parse result (vert/tri counts, bbox, per-mesh tris).
void debugDumpModel(source::SourceFs& fs, const std::string& path);

// Loads every prop model in `mesh.props`, transforms it to world space and
// appends the geometry to `mesh` as new material batches. Props that load are
// flagged `baked` so the renderer stops drawing their placeholder box.
// Returns the number of props baked.
int bakePropModels(bsp::WorldMesh& mesh, source::SourceFs& fs);

}  // namespace pb::model
