#pragma once
#include <cstdint>
#include <string>
#include <vector>

#include <glm/glm.hpp>

#include "bsp/BspFile.h"

namespace pb::bsp {

struct WorldVertex {
    glm::vec3 pos;
    glm::vec3 normal;
    glm::vec2 uv;     // lightmap atlas UV (or white-pixel UV)
    glm::vec3 tint;   // multiplier applied to the lightmap sample
};

struct DrawBatch {
    std::string material;
    uint32_t firstIndex = 0;
    uint32_t indexCount = 0;
    bool translucent = false;
};

struct PropInstance {
    std::string model;
    glm::vec3 pos{0.0f};
    glm::vec3 anglesPYR{0.0f};  // pitch, yaw, roll (degrees)
    float scale = 1.0f;
};

struct PointEntity {
    std::string classname;
    std::string targetname;
    glm::vec3 pos{0.0f};
};

// CPU-side result of turning a BSP into something drawable.
struct WorldMesh {
    std::vector<WorldVertex> vertices;
    std::vector<uint32_t> indices;
    std::vector<DrawBatch> batches;

    // De-duplicated world edges for the orthographic wireframe views.
    std::vector<glm::vec3> wireLines;  // pairs of endpoints

    // Lightmap atlas (RGB8, row-major, top-left origin).
    std::vector<uint8_t> lightmapAtlas;
    int lightmapWidth = 0;
    int lightmapHeight = 0;

    std::vector<PropInstance> props;
    std::vector<PointEntity> pointEntities;

    glm::vec3 boundsMin{0.0f};
    glm::vec3 boundsMax{0.0f};

    // Trimmed bounds of the playable area (excludes the 3D skybox and stray
    // far geometry); use this for default camera framing.
    glm::vec3 playBoundsMin{0.0f};
    glm::vec3 playBoundsMax{0.0f};

    size_t drawnFaces = 0;
    size_t skippedFaces = 0;

    glm::vec3 center() const { return 0.5f * (boundsMin + boundsMax); }
    float radius() const { return 0.5f * glm::length(boundsMax - boundsMin); }
};

struct MeshBuildOptions {
    bool includeTriggers = false;
    bool includeSky = false;
    float lightmapGain = 1.0f;
};

// Builds a WorldMesh from a loaded BSP. Never throws; logs and degrades.
WorldMesh buildWorldMesh(const BspFile& bsp, const MeshBuildOptions& opts = {});

}  // namespace pb::bsp
