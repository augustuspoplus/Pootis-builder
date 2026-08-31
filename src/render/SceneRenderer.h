#pragma once
#include <vector>

#include <glm/glm.hpp>

#include "bsp/BspMesh.h"
#include "gpu/Gl.h"
#include "render/Camera.h"
#include "render/Shader.h"

namespace pb {

using bsp::DrawBatch;
using bsp::MeshBuildOptions;
using bsp::PointEntity;
using bsp::PropInstance;
using bsp::WorldMesh;
using bsp::WorldVertex;

struct RenderSettings {
    bool showGrid = true;
    bool showProps = true;
    bool showPointEntities = true;
    bool wireOverlay = false;      // wire on top of solid (perspective)
    bool lightingOnly = true;      // lightmap shading (vs flat white)
    float exposure = 1.0f;
    glm::vec3 clearColor{0.16f, 0.17f, 0.19f};
    glm::vec3 clearColorOrtho{0.09f, 0.10f, 0.11f};
};

// Owns GPU buffers for one loaded map and draws it from any Camera.
class SceneRenderer {
public:
    bool init();
    void upload(const WorldMesh& mesh);
    void clearWorld();

    // Renders into the given rectangle of the currently-bound framebuffer.
    void renderView(const Camera& cam, int pxW, int pxH, const RenderSettings& s,
                    int pxX = 0, int pxY = 0);

    bool hasWorld() const { return indexCount_ > 0 || wireCount_ > 0; }
    glm::vec3 boundsMin() const { return boundsMin_; }
    glm::vec3 boundsMax() const { return boundsMax_; }

private:
    void buildGrid();
    void drawSolid(const glm::mat4& vp, const RenderSettings& s);
    void drawWire(const glm::mat4& vp, const glm::vec3& color, float alpha);
    void drawGrid(const glm::mat4& vp, ViewKind kind);
    void drawMarkers(const glm::mat4& vp, const RenderSettings& s, bool ortho);

    Shader worldShader_;
    Shader lineShader_;

    // World solid mesh.
    GLuint worldVao_ = 0, worldVbo_ = 0, worldEbo_ = 0;
    GLsizei indexCount_ = 0;
    std::vector<DrawBatch> batches_;

    // Wireframe edge list.
    GLuint wireVao_ = 0, wireVbo_ = 0;
    GLsizei wireCount_ = 0;

    // Lightmap atlas.
    GLuint lightmapTex_ = 0;

    // Static grid (XY plane, transformed per view).
    GLuint gridVao_ = 0, gridVbo_ = 0;
    GLsizei gridCount_ = 0;

    // Dynamic marker line buffer.
    GLuint markerVao_ = 0, markerVbo_ = 0;

    std::vector<PropInstance> props_;
    std::vector<PointEntity> pointEntities_;
    glm::vec3 boundsMin_{-512.0f}, boundsMax_{512.0f};
};

}  // namespace pb
