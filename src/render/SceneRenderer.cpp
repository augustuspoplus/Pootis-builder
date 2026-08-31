#include "render/SceneRenderer.h"

#include <cmath>

#include <glm/gtc/matrix_transform.hpp>

#include "core/Log.h"

namespace pb {
namespace {

const char* kWorldVert = R"(#version 330 core
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec2 aLmUV;
layout(location=3) in vec2 aTexUV;
layout(location=4) in vec3 aTint;
uniform mat4 uMVP;
out vec2 vLmUV;
out vec2 vTexUV;
out vec3 vTint;
void main() {
    vLmUV = aLmUV;
    vTexUV = aTexUV;
    vTint = aTint;
    gl_Position = uMVP * vec4(aPos, 1.0);
}
)";

const char* kWorldFrag = R"(#version 330 core
in vec2 vLmUV;
in vec2 vTexUV;
in vec3 vTint;
uniform sampler2D uLightmap;   // unit 0
uniform sampler2D uAlbedo;     // unit 1
uniform float uExposure;
uniform int uShadeMode;        // 0 tex+lm, 1 lightmap grid, 2 flat, 3 tex fullbright
uniform int uAlphaTest;
uniform float uConstAlpha;     // >=0 overrides output alpha (tool/trigger brushes)
out vec4 fragColor;
void main() {
    vec4 alb = texture(uAlbedo, vTexUV);
    if (uAlphaTest == 1 && alb.a < 0.5) discard;
    vec3 lm = texture(uLightmap, vLmUV).rgb;
    vec3 c;
    if (uShadeMode == 0)      c = alb.rgb * lm * vTint;
    else if (uShadeMode == 1) c = lm * vTint;
    else if (uShadeMode == 2) c = vTint * 0.72 + 0.14;
    else                      c = alb.rgb;
    float a = uConstAlpha >= 0.0 ? uConstAlpha : 1.0;
    fragColor = vec4(c * uExposure, a);
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
    batchTex_.clear();
    batchAlpha_.clear();
    props_.clear();
    pointEntities_.clear();
}

void SceneRenderer::upload(const WorldMesh& mesh, MaterialLibrary* materials) {
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
        glVertexAttribPointer(3, 2, GL_FLOAT, GL_FALSE, stride,
                              (void*)offsetof(WorldVertex, texUv));
        glEnableVertexAttribArray(4);
        glVertexAttribPointer(4, 3, GL_FLOAT, GL_FALSE, stride,
                              (void*)offsetof(WorldVertex, tint));
        glBindVertexArray(0);
        indexCount_ = static_cast<GLsizei>(mesh.indices.size());
    }

    // Resolve a GL albedo texture per draw batch.
    batchTex_.assign(batches_.size(), 0);
    batchAlpha_.assign(batches_.size(), 0);
    if (materials && materials->ready()) {
        for (size_t i = 0; i < batches_.size(); ++i) {
            const auto& info = materials->get(batches_[i].material);
            batchTex_[i] = info.texture;
            batchAlpha_[i] = info.alphaTest ? 1 : (batches_[i].translucent ? 2 : 0);
        }
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
    worldShader_.set("uShadeMode", static_cast<int>(s.shadeMode));
    worldShader_.set("uLightmap", 0);
    worldShader_.set("uAlbedo", 1);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, lightmapTex_);

    glEnable(GL_DEPTH_TEST);
    glBindVertexArray(worldVao_);
    for (size_t i = 0; i < batches_.size(); ++i) {
        const auto& b = batches_[i];
        const uint8_t alpha = i < batchAlpha_.size() ? batchAlpha_[i] : 0;
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, i < batchTex_.size() ? batchTex_[i] : 0);
        worldShader_.set("uAlphaTest", alpha == 1 ? 1 : 0);
        const bool tool = b.material.rfind("tools/", 0) == 0 ||
                          b.material.find("trigger") != std::string::npos;
        worldShader_.set("uConstAlpha", alpha == 2 ? (tool ? 0.30f : 0.55f) : -1.0f);
        if (alpha == 2) {
            glEnable(GL_BLEND);
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
            glDepthMask(GL_FALSE);
        }
        glDrawElements(GL_TRIANGLES, b.indexCount, GL_UNSIGNED_INT,
                       (void*)(b.firstIndex * sizeof(uint32_t)));
        if (alpha == 2) {
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

void SceneRenderer::drawGrid(const Camera& cam, const glm::mat4& vp, float aspect) {
    // Hammer-style adaptive 2D grid drawn directly on the view plane.
    const glm::vec3 rt = cam.orthoRightAxis();
    const glm::vec3 up = cam.orthoUpAxis();
    const float halfV = cam.orthoHalfHeight;
    const float halfH = halfV * (aspect <= 0.0f ? 1.0f : aspect);
    const float cU = glm::dot(cam.orthoCenter, rt);
    const float cV = glm::dot(cam.orthoCenter, up);

    // Minor spacing: smallest power-of-two Hammer grid that stays >= ~7px.
    float step = 1.0f;
    const float targetWorld = (halfV * 2.0f) / 90.0f;
    while (step < targetWorld && step < 8192.0f) step *= 2.0f;

    auto lineU = [&](float u, float v0, float v1, std::vector<glm::vec3>& out) {
        out.push_back(cam.orthoCenter + rt * (u - cU) + up * (v0 - cV));
        out.push_back(cam.orthoCenter + rt * (u - cU) + up * (v1 - cV));
    };
    auto lineV = [&](float v, float u0, float u1, std::vector<glm::vec3>& out) {
        out.push_back(cam.orthoCenter + rt * (u0 - cU) + up * (v - cV));
        out.push_back(cam.orthoCenter + rt * (u1 - cU) + up * (v - cV));
    };

    const float uMin = cU - halfH, uMax = cU + halfH;
    const float vMin = cV - halfV, vMax = cV + halfV;

    std::vector<glm::vec3> minor, major;
    const float majorStep = step * 8.0f;
    auto emit = [&](float s, std::vector<glm::vec3>& dst) {
        for (float u = std::ceil(uMin / s) * s; u <= uMax; u += s) lineU(u, vMin, vMax, dst);
        for (float v = std::ceil(vMin / s) * s; v <= vMax; v += s) lineV(v, uMin, uMax, dst);
    };
    emit(step, minor);
    emit(majorStep, major);

    lineShader_.use();
    glBindVertexArray(markerVao_);
    glBindBuffer(GL_ARRAY_BUFFER, markerVbo_);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(glm::vec3), nullptr);

    auto blast = [&](std::vector<glm::vec3>& v, const glm::vec4& col) {
        if (v.empty()) return;
        glBufferData(GL_ARRAY_BUFFER, v.size() * sizeof(glm::vec3), v.data(),
                     GL_DYNAMIC_DRAW);
        lineShader_.set("uMVP", vp);
        lineShader_.set("uColor", col);
        glDrawArrays(GL_LINES, 0, static_cast<GLsizei>(v.size()));
    };
    blast(minor, glm::vec4(0.16f, 0.16f, 0.18f, 1.0f));
    blast(major, glm::vec4(0.28f, 0.28f, 0.32f, 1.0f));

    // World axes through the origin, in Hammer orange.
    std::vector<glm::vec3> axes;
    lineU(0.0f, vMin, vMax, axes);
    lineV(0.0f, uMin, uMax, axes);
    blast(axes, glm::vec4(0.62f, 0.34f, 0.14f, 1.0f));

    glBindVertexArray(0);
}

void SceneRenderer::drawMarkers(const glm::mat4& vp, const RenderSettings& s, bool ortho) {
    std::vector<glm::vec3> lines;
    const float r = ortho ? 14.0f : 12.0f;
    auto cross = [&](const glm::vec3& p) {
        lines.push_back(p - glm::vec3(r, 0, 0));
        lines.push_back(p + glm::vec3(r, 0, 0));
        lines.push_back(p - glm::vec3(0, r, 0));
        lines.push_back(p + glm::vec3(0, r, 0));
        lines.push_back(p - glm::vec3(0, 0, r));
        lines.push_back(p + glm::vec3(0, 0, r));
    };

    if (s.showPointEntities || ortho)
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

    if (s.showGrid && ortho) drawGrid(cam, vp, aspect);

    if (ortho) {
        drawWire(vp, glm::vec3(0.82f, 0.85f, 0.90f), 0.95f);
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
