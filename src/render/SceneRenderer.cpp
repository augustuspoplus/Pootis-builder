#include "render/SceneRenderer.h"

#include <cmath>

#include <glm/gtc/matrix_transform.hpp>

#include "core/Log.h"

namespace pb {
namespace {

const char* kWorldVert = R"(#version 330 core
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec2 aUV;
layout(location=3) in vec3 aTint;
uniform mat4 uMVP;
out vec2 vUV;
out vec3 vTint;
void main() {
    vUV = aUV;
    vTint = aTint;
    gl_Position = uMVP * vec4(aPos, 1.0);
}
)";

const char* kWorldFrag = R"(#version 330 core
in vec2 vUV;
in vec3 vTint;
uniform sampler2D uLightmap;
uniform float uExposure;
uniform int uLightingOnly;
out vec4 fragColor;
void main() {
    vec3 base;
    if (uLightingOnly == 1) {
        base = texture(uLightmap, vUV).rgb * vTint;
    } else {
        base = vTint;
    }
    fragColor = vec4(base * uExposure, 1.0);
}
)";

const char* kLineVert = R"(#version 330 core
layout(location=0) in vec3 aPos;
uniform mat4 uMVP;
void main() { gl_Position = uMVP * vec4(aPos, 1.0); }
)";

const char* kLineFrag = R"(#version 330 core
uniform vec4 uColor;
out vec4 fragColor;
void main() { fragColor = uColor; }
)";

}  // namespace

bool SceneRenderer::init() {
    if (!worldShader_.compile(kWorldVert, kWorldFrag, "world")) return false;
    if (!lineShader_.compile(kLineVert, kLineFrag, "line")) return false;
    buildGrid();
    glGenVertexArrays(1, &markerVao_);
    glGenBuffers(1, &markerVbo_);
    return true;
}

void SceneRenderer::buildGrid() {
    std::vector<glm::vec3> lines;
    const int extent = 8192;
    const int step = 128;
    for (int c = -extent; c <= extent; c += step) {
        const float f = static_cast<float>(c);
        lines.push_back({f, -extent, 0.0f});
        lines.push_back({f, extent, 0.0f});
        lines.push_back({-extent, f, 0.0f});
        lines.push_back({extent, f, 0.0f});
    }
    gridCount_ = static_cast<GLsizei>(lines.size());
    glGenVertexArrays(1, &gridVao_);
    glGenBuffers(1, &gridVbo_);
    glBindVertexArray(gridVao_);
    glBindBuffer(GL_ARRAY_BUFFER, gridVbo_);
    glBufferData(GL_ARRAY_BUFFER, lines.size() * sizeof(glm::vec3), lines.data(),
                 GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(glm::vec3), nullptr);
    glBindVertexArray(0);
}

void SceneRenderer::clearWorld() {
    if (worldVao_) glDeleteVertexArrays(1, &worldVao_);
    if (worldVbo_) glDeleteBuffers(1, &worldVbo_);
    if (worldEbo_) glDeleteBuffers(1, &worldEbo_);
    if (wireVao_) glDeleteVertexArrays(1, &wireVao_);
    if (wireVbo_) glDeleteBuffers(1, &wireVbo_);
    if (lightmapTex_) glDeleteTextures(1, &lightmapTex_);
    worldVao_ = worldVbo_ = worldEbo_ = wireVao_ = wireVbo_ = lightmapTex_ = 0;
    indexCount_ = wireCount_ = 0;
    batches_.clear();
    props_.clear();
    pointEntities_.clear();
}

void SceneRenderer::upload(const WorldMesh& mesh) {
    clearWorld();
    batches_ = mesh.batches;
    props_ = mesh.props;
    pointEntities_ = mesh.pointEntities;
    boundsMin_ = mesh.boundsMin;
    boundsMax_ = mesh.boundsMax;

    if (!mesh.vertices.empty() && !mesh.indices.empty()) {
        glGenVertexArrays(1, &worldVao_);
        glGenBuffers(1, &worldVbo_);
        glGenBuffers(1, &worldEbo_);
        glBindVertexArray(worldVao_);
        glBindBuffer(GL_ARRAY_BUFFER, worldVbo_);
        glBufferData(GL_ARRAY_BUFFER, mesh.vertices.size() * sizeof(WorldVertex),
                     mesh.vertices.data(), GL_STATIC_DRAW);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, worldEbo_);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, mesh.indices.size() * sizeof(uint32_t),
                     mesh.indices.data(), GL_STATIC_DRAW);
        const GLsizei stride = sizeof(WorldVertex);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, stride,
                              (void*)offsetof(WorldVertex, pos));
        glEnableVertexAttribArray(1);
        glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, stride,
                              (void*)offsetof(WorldVertex, normal));
        glEnableVertexAttribArray(2);
        glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, stride,
                              (void*)offsetof(WorldVertex, uv));
        glEnableVertexAttribArray(3);
        glVertexAttribPointer(3, 3, GL_FLOAT, GL_FALSE, stride,
                              (void*)offsetof(WorldVertex, tint));
        glBindVertexArray(0);
        indexCount_ = static_cast<GLsizei>(mesh.indices.size());
    }

    if (!mesh.wireLines.empty()) {
        glGenVertexArrays(1, &wireVao_);
        glGenBuffers(1, &wireVbo_);
        glBindVertexArray(wireVao_);
        glBindBuffer(GL_ARRAY_BUFFER, wireVbo_);
        glBufferData(GL_ARRAY_BUFFER, mesh.wireLines.size() * sizeof(glm::vec3),
                     mesh.wireLines.data(), GL_STATIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(glm::vec3), nullptr);
        glBindVertexArray(0);
        wireCount_ = static_cast<GLsizei>(mesh.wireLines.size());
    }

    if (mesh.lightmapWidth > 0 && mesh.lightmapHeight > 0 &&
        !mesh.lightmapAtlas.empty()) {
        glGenTextures(1, &lightmapTex_);
        glBindTexture(GL_TEXTURE_2D, lightmapTex_);
        glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB8, mesh.lightmapWidth, mesh.lightmapHeight,
                     0, GL_RGB, GL_UNSIGNED_BYTE, mesh.lightmapAtlas.data());
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    }
}

void SceneRenderer::drawSolid(const glm::mat4& vp, const RenderSettings& s) {
    if (!worldVao_ || indexCount_ == 0) return;
    worldShader_.use();
    worldShader_.set("uMVP", vp);
    worldShader_.set("uExposure", s.exposure);
    worldShader_.set("uLightingOnly", s.lightingOnly ? 1 : 0);
    worldShader_.set("uLightmap", 0);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, lightmapTex_);

    glEnable(GL_DEPTH_TEST);
    glBindVertexArray(worldVao_);
    for (const auto& b : batches_) {
        if (b.translucent) {
            glEnable(GL_BLEND);
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
            glDepthMask(GL_FALSE);
        }
        glDrawElements(GL_TRIANGLES, b.indexCount, GL_UNSIGNED_INT,
                       (void*)(b.firstIndex * sizeof(uint32_t)));
        if (b.translucent) {
            glDepthMask(GL_TRUE);
            glDisable(GL_BLEND);
        }
    }
    glBindVertexArray(0);
}

void SceneRenderer::drawWire(const glm::mat4& vp, const glm::vec3& color, float alpha) {
    if (!wireVao_ || wireCount_ == 0) return;
    lineShader_.use();
    lineShader_.set("uMVP", vp);
    lineShader_.set("uColor", glm::vec4(color, alpha));
    glBindVertexArray(wireVao_);
    glDrawArrays(GL_LINES, 0, wireCount_);
    glBindVertexArray(0);
}

void SceneRenderer::drawGrid(const glm::mat4& vp, ViewKind kind) {
    if (!gridVao_ || gridCount_ == 0) return;
    glm::mat4 model(1.0f);
    if (kind == ViewKind::Front)  // XY grid -> XZ plane
        model = glm::rotate(glm::mat4(1.0f), glm::radians(90.0f), glm::vec3(1, 0, 0));
    else if (kind == ViewKind::Side)  // XY grid -> YZ plane
        model = glm::rotate(glm::mat4(1.0f), glm::radians(90.0f), glm::vec3(0, 1, 0));

    lineShader_.use();
    lineShader_.set("uMVP", vp * model);
    lineShader_.set("uColor", glm::vec4(0.32f, 0.34f, 0.37f, 0.5f));
    glBindVertexArray(gridVao_);
    glDrawArrays(GL_LINES, 0, gridCount_);

    // Axis lines through the origin.
    std::vector<glm::vec3> axes = {
        {-8192, 0, 0}, {8192, 0, 0}, {0, -8192, 0}, {0, 8192, 0}, {0, 0, -8192}, {0, 0, 8192}};
    glBindVertexArray(markerVao_);
    glBindBuffer(GL_ARRAY_BUFFER, markerVbo_);
    glBufferData(GL_ARRAY_BUFFER, axes.size() * sizeof(glm::vec3), axes.data(),
                 GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(glm::vec3), nullptr);
    lineShader_.set("uMVP", vp);
    lineShader_.set("uColor", glm::vec4(0.45f, 0.30f, 0.30f, 0.7f));
    glDrawArrays(GL_LINES, 0, 2);
    lineShader_.set("uColor", glm::vec4(0.30f, 0.45f, 0.30f, 0.7f));
    glDrawArrays(GL_LINES, 2, 2);
    lineShader_.set("uColor", glm::vec4(0.30f, 0.35f, 0.5f, 0.7f));
    glDrawArrays(GL_LINES, 4, 2);
    glBindVertexArray(0);
}

void SceneRenderer::drawMarkers(const glm::mat4& vp, const RenderSettings& s, bool ortho) {
    std::vector<glm::vec3> lines;
    const float r = ortho ? 24.0f : 16.0f;
    auto cross = [&](const glm::vec3& p) {
        lines.push_back(p - glm::vec3(r, 0, 0));
        lines.push_back(p + glm::vec3(r, 0, 0));
        lines.push_back(p - glm::vec3(0, r, 0));
        lines.push_back(p + glm::vec3(0, r, 0));
        lines.push_back(p - glm::vec3(0, 0, r));
        lines.push_back(p + glm::vec3(0, 0, r));
    };

    if (s.showPointEntities)
        for (const auto& e : pointEntities_) cross(e.pos);

    if (!lines.empty()) {
        lineShader_.use();
        lineShader_.set("uMVP", vp);
        lineShader_.set("uColor", glm::vec4(0.95f, 0.75f, 0.30f, 0.85f));
        glBindVertexArray(markerVao_);
        glBindBuffer(GL_ARRAY_BUFFER, markerVbo_);
        glBufferData(GL_ARRAY_BUFFER, lines.size() * sizeof(glm::vec3), lines.data(),
                     GL_DYNAMIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(glm::vec3), nullptr);
        glDrawArrays(GL_LINES, 0, static_cast<GLsizei>(lines.size()));
        glBindVertexArray(0);
    }

    // Static props as boxes.
    if (s.showProps && !props_.empty()) {
        std::vector<glm::vec3> box;
        const glm::vec3 h(20.0f);
        auto edge = [&](glm::vec3 a, glm::vec3 b) {
            box.push_back(a);
            box.push_back(b);
        };
        for (const auto& p : props_) {
            const glm::vec3 c = p.pos;
            glm::vec3 v[8];
            for (int i = 0; i < 8; ++i)
                v[i] = c + glm::vec3((i & 1) ? h.x : -h.x, (i & 2) ? h.y : -h.y,
                                     (i & 4) ? h.z : -h.z);
            int e[12][2] = {{0, 1}, {1, 3}, {3, 2}, {2, 0}, {4, 5}, {5, 7},
                            {7, 6}, {6, 4}, {0, 4}, {1, 5}, {2, 6}, {3, 7}};
            for (auto& pr : e) edge(v[pr[0]], v[pr[1]]);
        }
        lineShader_.use();
        lineShader_.set("uMVP", vp);
        lineShader_.set("uColor", glm::vec4(0.45f, 0.75f, 0.95f, 0.5f));
        glBindVertexArray(markerVao_);
        glBindBuffer(GL_ARRAY_BUFFER, markerVbo_);
        glBufferData(GL_ARRAY_BUFFER, box.size() * sizeof(glm::vec3), box.data(),
                     GL_DYNAMIC_DRAW);
        glEnableVertexAttribArray(0);
        glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(glm::vec3), nullptr);
        glDrawArrays(GL_LINES, 0, static_cast<GLsizei>(box.size()));
        glBindVertexArray(0);
    }
}

void SceneRenderer::renderView(const Camera& cam, int pxW, int pxH,
                               const RenderSettings& s, int pxX, int pxY) {
    const bool ortho = cam.kind != ViewKind::Perspective;
    const glm::vec3 bg = ortho ? s.clearColorOrtho : s.clearColor;
    glViewport(pxX, pxY, pxW, pxH);
    glEnable(GL_SCISSOR_TEST);
    glScissor(pxX, pxY, pxW, pxH);
    glClearColor(bg.r, bg.g, bg.b, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glDisable(GL_SCISSOR_TEST);
    glEnable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);

    const float aspect = pxH > 0 ? static_cast<float>(pxW) / pxH : 1.0f;
    const glm::mat4 vp = cam.proj(aspect) * cam.view();

    if (s.showGrid && ortho) drawGrid(vp, cam.kind);

    if (ortho) {
        drawWire(vp, glm::vec3(0.80f, 0.82f, 0.86f), 0.9f);
        drawMarkers(vp, s, true);
    } else {
        drawSolid(vp, s);
        if (s.wireOverlay) {
            glEnable(GL_BLEND);
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
            drawWire(vp, glm::vec3(0.0f), 0.25f);
            glDisable(GL_BLEND);
        }
        drawMarkers(vp, s, false);
    }
}

}  // namespace pb
