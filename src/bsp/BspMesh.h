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
    glm::vec2 uv;      // lightmap atlas UV (or white-pixel UV)
    glm::vec2 texUv;   // albedo/material UV
    glm::vec3 tint;    // multiplier applied to the lightmap sample
    float blend = 0.0f; // displacement WorldVertexTransition alpha [0..1]
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
    bool baked = false;         // model geometry folded into the batches
};

struct PointEntity {
    std::string classname;
    std::string targetname;
    glm::vec3 pos{0.0f};
};

// Interactive sliding door brush sub-model (*N) separated from static world geometry
// so F5 playtest can smoothly slide spawn doors & gates open when approached!
struct InteractiveDoor {
    std::string targetname;
    glm::vec3 origin{0.0f};
    glm::vec3 movedir{0.0f, 0.0f, 1.0f}; // Source Z-up unit slide direction
    float travel = 112.0f;               // Hammer units to slide
    float speed = 320.0f;                // Hammer units / sec
    bool startLocked = false;            // spawnflags bit 2048 (Starts Locked)
    glm::vec3 boundsMin{0.0f};
    glm::vec3 boundsMax{0.0f};
    std::vector<WorldVertex> vertices;
    std::vector<uint32_t> indices;
    std::vector<DrawBatch> batches;
    std::vector<PropInstance> attachedProps; // prop_dynamic door models parented to this func_door!
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
    std::vector<InteractiveDoor> doors;

    glm::vec3 boundsMin{0.0f};
    glm::vec3 boundsMax{0.0f};

    // Trimmed bounds of the playable area (excludes the 3D skybox and stray
    // far geometry); use this for default camera framing.
    glm::vec3 playBoundsMin{0.0f};
    glm::vec3 playBoundsMax{0.0f};

    // A representative player spawn, for the "open inside the map" 3D camera.
    bool hasSpawn = false;
    glm::vec3 spawnPos{0.0f};
    float spawnYaw = 0.0f;  // degrees, around +Z

    // Extracted light_environment sun orientation & color so Godot sun aligns with Valve VRAD!
    bool hasSun = false;
    float sunPitch = -45.0f;
    float sunYaw = 45.0f;
    glm::vec3 sunColor{1.0f, 0.96f, 0.90f};

    size_t drawnFaces = 0;
    size_t skippedFaces = 0;

    glm::vec3 center() const { return 0.5f * (boundsMin + boundsMax); }
    float radius() const { return 0.5f * glm::length(boundsMax - boundsMin); }
};

struct MeshBuildOptions {
    bool includeTriggers = false;
    bool includeSky = false;
    bool bakeProps = true;   // fold prop_static model geometry into the mesh
    float lightmapGain = 1.0f;
};

// Builds a WorldMesh from a loaded BSP. Never throws; logs and degrades.
WorldMesh buildWorldMesh(const BspFile& bsp, const MeshBuildOptions& opts = {});

}  // namespace pb::bsp
