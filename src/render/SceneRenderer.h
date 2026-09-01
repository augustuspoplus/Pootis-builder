#pragma once
#include <vector>

#include <glm/glm.hpp>

#include "bsp/BspMesh.h"
#include "gpu/Gl.h"
#include "render/Camera.h"
#include "render/MaterialLibrary.h"
#include "render/Shader.h"

namespace pb {

using bsp::DrawBatch;
using bsp::MeshBuildOptions;
using bsp::PointEntity;
using bsp::PropInstance;
using bsp::WorldMesh;
using bsp::WorldVertex;

enum class ShadeMode { TexturedLit = 0, LightmapGrid = 1, Flat = 2, TexturedFull = 3 };

struct RenderSettings {
    bool showGrid = true;
    bool showProps = true;
    bool showPointEntities = false;  // 3D view clutter; on for the 2D views
    bool wireOverlay = false;        // wire on top of solid (perspective)
    ShadeMode shadeMode = ShadeMode::TexturedLit;
    float exposure = 1.15f;
    glm::vec3 clearColor{0.055f, 0.06f, 0.07f};       // Hammer 3D: near-black
    glm::vec3 clearColorOrtho{0.016f, 0.016f, 0.02f};
};

// Owns GPU buffers for one loaded map and draws it from any Camera.
class SceneRenderer {
public:
    bool init();
    void upload(const WorldMesh& mesh, MaterialLibrary* materials = nullptr);
    void clearWorld();

    // Renders into the given rectangle of the currently-bound framebuffer.
    void renderView(const Camera& cam, int pxW, int pxH, const RenderSettings& s,
                    int pxX = 0, int pxY = 0);

    // Bright overlay outline for the current selection (line-pairs, world space).
    void setSelectionWire(const std::vector<glm::vec3>& lines);

    bool hasWorld() const { return indexCount_ > 0 || wireCount_ > 0; }
    glm::vec3 boundsMin() const { return boundsMin_; }
    glm::vec3 boundsMax() const { return boundsMax_; }

private:
    void buildGrid();
    void drawSolid(const glm::mat4& vp, const RenderSettings& s);
    void drawWire(const glm::mat4& vp, const glm::vec3& color, float alpha);
    void drawGrid(const Camera& cam, const glm::mat4& vp, float aspect);
    void drawGroundGrid3D(const Camera& cam, float aspect);
    void drawOriginMarker(const glm::mat4& vp);
    void drawMarkers(const glm::mat4& vp, const RenderSettings& s, bool ortho);

    Shader worldShader_;
    Shader lineShader_;
    Shader grid3dShader_;
    GLuint grid3dVao_ = 0;

    // World solid mesh.
    GLuint worldVao_ = 0, worldVbo_ = 0, worldEbo_ = 0;
    GLsizei indexCount_ = 0;
    std::vector<DrawBatch> batches_;
    std::vector<GLuint> batchTex_;      // parallel to batches_ (0 = untextured)
    std::vector<uint8_t> batchAlpha_;   // 0 opaque, 1 alpha-test, 2 blend

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

    // Selection outline.
    GLuint selVao_ = 0, selVbo_ = 0;
    GLsizei selCount_ = 0;
    void drawSelectionWire(const glm::mat4& vp);

    std::vector<PropInstance> props_;
    std::vector<PointEntity> pointEntities_;
    glm::vec3 boundsMin_{-512.0f}, boundsMax_{512.0f};
};

}  // namespace pb
