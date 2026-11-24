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
uniform mat4 uLightVP;
out vec3 vWorldPos;
out vec3 vNormal;
out vec4 vLightPos;
out vec2 vLmUV;
out vec2 vTexUV;
out vec3 vTint;
void main() {
    vWorldPos = aPos;
    vNormal = aNormal;
    vLightPos = uLightVP * vec4(aPos, 1.0);
    vLmUV = aLmUV;
    vTexUV = aTexUV;
    vTint = aTint;
    gl_Position = uMVP * vec4(aPos, 1.0);
}
)";

const char* kWorldFrag = R"(#version 330 core
in vec3 vWorldPos;
in vec3 vNormal;
in vec4 vLightPos;
in vec2 vLmUV;
in vec2 vTexUV;
in vec3 vTint;
uniform sampler2D uLightmap;   // unit 0
uniform sampler2D uAlbedo;     // unit 1
uniform sampler2D uShadowMap;  // unit 2
uniform float uExposure;
uniform int uShadeMode;        // 0 tex+lm, 1 lightmap grid, 2 flat, 3 tex fullbright
uniform int uAlphaTest;
uniform float uConstAlpha;     // >=0 overrides output alpha (tool/trigger brushes)
uniform int uDynamicLit;       // 1 = VMF live TF2 Half-Lambert + soft shadows
uniform vec3 uSunDir;
uniform vec3 uSunCol;
uniform vec3 uSkyCol;
uniform vec3 uGroundCol;
uniform vec3 uFogCol;
uniform vec3 uCamPos;
out vec4 fragColor;

float calcShadow(vec4 lp, vec3 n) {
    vec3 p = lp.xyz / lp.w * 0.5 + 0.5;
    if (p.z > 0.999 || p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0) return 1.0;
    float bias = max(0.0022 * (1.0 - dot(n, uSunDir)), 0.0006);
    vec2 texel = 1.0 / vec2(textureSize(uShadowMap, 0));
    float vis = 0.0;
    for (int x = -1; x <= 1; ++x) {
        for (int y = -1; y <= 1; ++y) {
            float d = texture(uShadowMap, p.xy + vec2(x, y) * texel).r;
            vis += (p.z - bias <= d) ? 1.0 : 0.0;
        }
    }
    return vis / 9.0;
}

void main() {
    vec4 alb = texture(uAlbedo, vTexUV);
    if (uAlphaTest == 1 && alb.a < 0.5) discard;
    vec3 lm = texture(uLightmap, vLmUV).rgb;
    vec3 n = normalize(vNormal);
    vec3 c;
    if (uShadeMode == 0) {
        if (uDynamicLit == 1) {
            // Authentic Valve TF2 Half-Lambert + warm/cool hemisphere + soft directional shadow
            float ndl = dot(n, normalize(uSunDir));
            float halfLambert = pow(ndl * 0.5 + 0.5, 1.85);
            float sh = mix(0.42, 1.0, calcShadow(vLightPos, n));
            vec3 hemi = mix(uGroundCol, uSkyCol, n.z * 0.5 + 0.5);
            vec3 viewDir = normalize(uCamPos - vWorldPos);
            float rim = pow(1.0 - max(dot(n, viewDir), 0.0), 3.2) * 0.14 * max(n.z * 0.5 + 0.5, 0.2);
            vec3 lit = hemi * 0.55 + uSunCol * halfLambert * sh * 0.78 + uSkyCol * rim;
            c = alb.rgb * vTint * lit;
        } else {
            // Compiled BSP with baked VRAD lightmap: keep crisp baked lighting + gentle depth cue
            c = alb.rgb * lm * vTint;
        }
        // Subtle atmospheric horizon fog so distant structures read with depth
        float dist = length(vWorldPos - uCamPos);
        float fogT = clamp((dist - 1800.0) / 8500.0, 0.0, 0.42);
        c = mix(c, uFogCol, fogT);
    } else if (uShadeMode == 1) {
        c = lm * vTint;
    } else if (uShadeMode == 2) {
        float hl = dot(n, normalize(uSunDir)) * 0.35 + 0.65;
        c = (vTint * 0.72 + 0.14) * hl;
    } else {
        c = alb.rgb;
    }
    float a = uConstAlpha >= 0.0 ? uConstAlpha : 1.0;
    fragColor = vec4(c * uExposure, a);
}
)";

const char* kShadowVert = R"(#version 330 core
layout(location=0) in vec3 aPos;
uniform mat4 uLightVP;
void main() { gl_Position = uLightVP * vec4(aPos, 1.0); }
)";

const char* kShadowFrag = R"(#version 330 core
void main() {}
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

// Infinite ground grid for the 3D view: a fullscreen triangle whose fragments
// are ray-cast onto the z=0 plane, then shaded as an anti-aliased grid that
// fades with distance. Red = +X world axis, green = +Y (Hammer / Blender look).
const char* kGrid3dVert = R"(#version 330 core
uniform mat4 uInvVP;
uniform vec3 uCamPos;
out vec3 vNear;
out vec3 vFar;
vec3 unproject(vec2 ndc, float z) {
    vec4 p = uInvVP * vec4(ndc, z, 1.0);
    return p.xyz / p.w;
}
void main() {
    vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2) * 2.0 - 1.0;
    vNear = unproject(p, -1.0);
    vFar  = unproject(p,  1.0);
    gl_Position = vec4(p, 0.999999, 1.0);
}
)";

const char* kGrid3dFrag = R"(#version 330 core
in vec3 vNear;
in vec3 vFar;
uniform vec3 uCamPos;
uniform mat4 uVP;
uniform vec3 uSkyHorizon;
uniform vec3 uSkyZenith;
uniform vec3 uSunDir;
uniform vec3 uSunCol;
out vec4 fragColor;

float gridMask(vec2 c, float step) {
    vec2 g = abs(fract(c / step - 0.5) - 0.5) / fwidth(c / step);
    return 1.0 - min(min(g.x, g.y), 1.0);
}
void main() {
    vec3 dir = normalize(vFar - vNear);
    float up = clamp(dir.z, 0.0, 1.0);
    float down = clamp(-dir.z, 0.0, 1.0);
    vec3 sky = mix(uSkyHorizon, uSkyZenith, pow(up, 0.55));
    // Soft sun halo + disc in the 3D TF2 sky dome
    float sunAmt = max(dot(dir, normalize(uSunDir)), 0.0);
    sky += uSunCol * (pow(sunAmt, 14.0) * 0.35 + smoothstep(0.9982, 0.9994, sunAmt) * 1.15);
    // Warm ground haze below horizon so there is never an ugly black void
    vec3 lowerHaze = mix(uSkyHorizon * 0.72, uSkyHorizon * 0.36, pow(down, 0.65));
    vec3 bgCol = (dir.z >= 0.0) ? sky : lowerHaze;

    float t = -vNear.z / (vFar.z - vNear.z);
    if (t <= 0.0) {
        gl_FragDepth = 0.99999;
        fragColor = vec4(bgCol, 1.0);
        return;
    }
    vec3 w = vNear + (vFar - vNear) * t;   // world hit on z=0

    float dist = length(w.xy - uCamPos.xy);
    float fade = clamp(1.0 - dist / 6144.0, 0.0, 1.0);
    fade *= fade;
    if (fade < 0.004) {
        gl_FragDepth = 0.99999;
        fragColor = vec4(bgCol, 1.0);
        return;
    }

    float fine   = gridMask(w.xy, 64.0);   // 1 TF2 grid block
    float coarse = gridMask(w.xy, 512.0);
    vec3  gcol = mix(vec3(0.45, 0.42, 0.38), vec3(0.70, 0.63, 0.54), coarse);
    float ga = max(fine * 0.38, coarse * 0.75);

    float axisW = fwidth(w.x) * 1.6;
    if (abs(w.y) < axisW) { gcol = vec3(0.88, 0.28, 0.26); ga = 0.95; }  // +X RED
    if (abs(w.x) < axisW) { gcol = vec3(0.32, 0.62, 0.88); ga = 0.95; }  // +Y BLU

    // Blend subtle ground grid over atmospheric lower sky haze
    vec4 clip = uVP * vec4(w, 1.0);
    gl_FragDepth = (clip.z / clip.w) * 0.5 + 0.5;
    fragColor = vec4(mix(bgCol, gcol, ga * fade), 1.0);
}
)";

struct BiomePalette {
    glm::vec3 horizon;
    glm::vec3 zenith;
    glm::vec3 sunDir;
    glm::vec3 sunCol;
    glm::vec3 skyAmbient;
    glm::vec3 groundAmbient;
};

BiomePalette biomePalette(int idx) {
    static const BiomePalette kPal[] = {
        // 0: Badlands Desert — warm TF2 golden canyon sky
        {{0.74f, 0.56f, 0.40f}, {0.32f, 0.45f, 0.62f}, {0.55f, -0.52f, 0.65f},
         {1.15f, 0.96f, 0.78f}, {0.72f, 0.78f, 0.92f}, {0.42f, 0.30f, 0.22f}},
        // 1: Alpine Winter — crisp snow blue-white sky
        {{0.72f, 0.80f, 0.88f}, {0.34f, 0.50f, 0.72f}, {0.42f, -0.60f, 0.68f},
         {1.05f, 1.06f, 1.12f}, {0.78f, 0.86f, 0.98f}, {0.46f, 0.52f, 0.58f}},
        // 2: Sawmill Forest — moody Pacific NW storm sky
        {{0.44f, 0.48f, 0.49f}, {0.20f, 0.26f, 0.32f}, {0.38f, -0.58f, 0.72f},
         {0.92f, 0.95f, 0.98f}, {0.62f, 0.70f, 0.76f}, {0.28f, 0.31f, 0.26f}},
        // 3: Spytech Facility — dramatic twilight slate sky
        {{0.30f, 0.36f, 0.46f}, {0.10f, 0.14f, 0.22f}, {0.50f, -0.45f, 0.74f},
         {0.98f, 0.92f, 0.88f}, {0.52f, 0.64f, 0.82f}, {0.24f, 0.26f, 0.30f}},
        // 4: Orange Dev Studio — warm neutral Mann Co. workshop sky
        {{0.42f, 0.37f, 0.33f}, {0.18f, 0.22f, 0.28f}, {0.48f, -0.56f, 0.67f},
         {1.08f, 0.98f, 0.86f}, {0.66f, 0.72f, 0.82f}, {0.34f, 0.29f, 0.25f}},
    };
    const int i = (idx >= 0 && idx < 5) ? idx : 4;
    return kPal[i];
}

}  // namespace

bool SceneRenderer::init() {
    if (!worldShader_.compile(kWorldVert, kWorldFrag, "world")) return false;
    if (!shadowShader_.compile(kShadowVert, kShadowFrag, "shadow")) return false;
    if (!lineShader_.compile(kLineVert, kLineFrag, "line")) return false;
    if (!grid3dShader_.compile(kGrid3dVert, kGrid3dFrag, "grid3d")) return false;
    glGenVertexArrays(1, &grid3dVao_);
    buildGrid();
    glGenVertexArrays(1, &markerVao_);
    glGenBuffers(1, &markerVbo_);
    glGenVertexArrays(1, &selVao_);
    glGenBuffers(1, &selVbo_);
    glGenVertexArrays(1, &hovVao_);
    glGenBuffers(1, &hovVbo_);

    // 2048x2048 directional shadow depth texture
    glGenFramebuffers(1, &shadowFbo_);
    glGenTextures(1, &shadowTex_);
    glBindTexture(GL_TEXTURE_2D, shadowTex_);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24, 2048, 2048, 0,
                 GL_DEPTH_COMPONENT, GL_FLOAT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_BORDER);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_BORDER);
    const float border[4] = {1.0f, 1.0f, 1.0f, 1.0f};
    glTexParameterfv(GL_TEXTURE_2D, GL_TEXTURE_BORDER_COLOR, border);
    glBindFramebuffer(GL_FRAMEBUFFER, shadowFbo_);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, shadowTex_, 0);
    glDrawBuffer(GL_NONE);
    glReadBuffer(GL_NONE);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
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

    hasBakedLightmap_ = (mesh.lightmapWidth > 8 && mesh.lightmapHeight > 8 &&
                         !mesh.lightmapAtlas.empty());
    shadowDirty_ = true;

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

void SceneRenderer::renderShadowMap() {
    shadowDirty_ = false;
    if (!shadowFbo_ || !worldVao_ || indexCount_ == 0) return;

    const glm::vec3 center = 0.5f * (boundsMin_ + boundsMax_);
    const glm::vec3 ext = glm::max(boundsMax_ - boundsMin_, glm::vec3(512.0f));
    const float rad = glm::min(glm::max(glm::length(ext) * 0.55f, 640.0f), 4096.0f);
    const glm::vec3 ldir = glm::normalize(sunDir_);
    const glm::mat4 lview = glm::lookAt(center + ldir * (rad * 1.6f), center, glm::vec3(0, 0, 1));
    const glm::mat4 lproj = glm::ortho(-rad, rad, -rad, rad, 16.0f, rad * 4.0f);
    lightVp_ = lproj * lview;

    GLint prevFbo = 0, prevVp[4];
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prevFbo);
    glGetIntegerv(GL_VIEWPORT, prevVp);

    glBindFramebuffer(GL_FRAMEBUFFER, shadowFbo_);
    glViewport(0, 0, 2048, 2048);
    glClear(GL_DEPTH_BUFFER_BIT);
    glEnable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);

    shadowShader_.use();
    shadowShader_.set("uLightVP", lightVp_);
    glBindVertexArray(worldVao_);
    for (size_t i = 0; i < batches_.size(); ++i) {
        const auto& b = batches_[i];
        // Skip skybox/trigger/tool brushes so the skybox shell doesn't shadow the whole map!
        if (b.material.rfind("tools/", 0) == 0 ||
            b.material.find("skybox") != std::string::npos ||
            b.material.find("trigger") != std::string::npos)
            continue;
        const uint8_t alpha = i < batchAlpha_.size() ? batchAlpha_[i] : 0;
        if (alpha == 2) continue;
        glDrawElements(GL_TRIANGLES, b.indexCount, GL_UNSIGNED_INT,
                       (void*)(b.firstIndex * sizeof(uint32_t)));
    }
    glBindVertexArray(0);

    glBindFramebuffer(GL_FRAMEBUFFER, static_cast<GLuint>(prevFbo));
    glViewport(prevVp[0], prevVp[1], prevVp[2], prevVp[3]);
}

void SceneRenderer::drawSolid(const glm::mat4& vp, const glm::vec3& camPos,
                              const RenderSettings& s) {
    if (!worldVao_ || indexCount_ == 0) return;
    const BiomePalette pal = biomePalette(s.skyBiome);
    sunDir_ = pal.sunDir;
    const bool dynLit = s.dynamicLighting && !hasBakedLightmap_;
    if (dynLit && shadowDirty_) renderShadowMap();

    worldShader_.use();
    worldShader_.set("uMVP", vp);
    worldShader_.set("uLightVP", lightVp_);
    worldShader_.set("uExposure", s.exposure);
    worldShader_.set("uShadeMode", static_cast<int>(s.shadeMode));
    worldShader_.set("uDynamicLit", dynLit ? 1 : 0);
    worldShader_.set("uSunDir", glm::normalize(pal.sunDir));
    worldShader_.set("uSunCol", pal.sunCol);
    worldShader_.set("uSkyCol", pal.skyAmbient);
    worldShader_.set("uGroundCol", pal.groundAmbient);
    worldShader_.set("uFogCol", pal.horizon);
    worldShader_.set("uCamPos", camPos);
    worldShader_.set("uLightmap", 0);
    worldShader_.set("uAlbedo", 1);
    worldShader_.set("uShadowMap", 2);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, lightmapTex_);
    glActiveTexture(GL_TEXTURE2);
    glBindTexture(GL_TEXTURE_2D, shadowTex_);

    glEnable(GL_DEPTH_TEST);
    glBindVertexArray(worldVao_);
    for (size_t i = 0; i < batches_.size(); ++i) {
        const auto& b = batches_[i];
        // Hide tools/toolsskybox shell inside 3D editor so you see the real 3D sky dome!
        if (b.material.find("toolsskybox") != std::string::npos) continue;
        const uint8_t alpha = i < batchAlpha_.size() ? batchAlpha_[i] : 0;
        glActiveTexture(GL_TEXTURE1);
        glBindTexture(GL_TEXTURE_2D, i < batchTex_.size() ? batchTex_[i] : 0);
        worldShader_.set("uAlphaTest", alpha == 1 ? 1 : 0);
        const bool tool = b.material.rfind("tools/", 0) == 0 ||
                          b.material.find("trigger") != std::string::npos;
        worldShader_.set("uConstAlpha", alpha == 2 ? (tool ? 0.25f : 0.55f) : -1.0f);
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

void SceneRenderer::drawGroundGrid3D(const Camera& cam, float aspect,
                                     const RenderSettings& s) {
    const glm::mat4 vp = cam.proj(aspect) * cam.view();
    const BiomePalette pal = biomePalette(s.skyBiome);
    grid3dShader_.use();
    grid3dShader_.set("uInvVP", glm::inverse(vp));
    grid3dShader_.set("uVP", vp);
    grid3dShader_.set("uCamPos", cam.pos);
    grid3dShader_.set("uSkyHorizon", pal.horizon);
    grid3dShader_.set("uSkyZenith", pal.zenith);
    grid3dShader_.set("uSunDir", glm::normalize(pal.sunDir));
    grid3dShader_.set("uSunCol", pal.sunCol);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glEnable(GL_DEPTH_TEST);
    glDepthMask(GL_FALSE);
    glBindVertexArray(grid3dVao_);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glBindVertexArray(0);
    glDepthMask(GL_TRUE);
    glDisable(GL_BLEND);
}

void SceneRenderer::drawOriginMarker(const glm::mat4& vp) {
    // A small ring + XYZ axis ticks at the world origin — a "you are here"
    // reference for an empty map.
    std::vector<glm::vec3> lines;
    const float r = 24.0f;
    for (int i = 0; i < 48; ++i) {
        const float a0 = (i / 48.0f) * 6.2831853f;
        const float a1 = ((i + 1) / 48.0f) * 6.2831853f;
        lines.push_back({std::cos(a0) * r, std::sin(a0) * r, 0.0f});
        lines.push_back({std::cos(a1) * r, std::sin(a1) * r, 0.0f});
    }
    lineShader_.use();
    lineShader_.set("uMVP", vp);
    glBindVertexArray(markerVao_);
    glBindBuffer(GL_ARRAY_BUFFER, markerVbo_);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(glm::vec3), nullptr);
    auto blast = [&](const std::vector<glm::vec3>& v, const glm::vec4& c) {
        glBufferData(GL_ARRAY_BUFFER, v.size() * sizeof(glm::vec3), v.data(),
                     GL_DYNAMIC_DRAW);
        lineShader_.set("uColor", c);
        glDrawArrays(GL_LINES, 0, static_cast<GLsizei>(v.size()));
    };
    blast(lines, glm::vec4(0.9f, 0.9f, 0.95f, 0.9f));
    blast({{-40, 0, 0}, {40, 0, 0}}, glm::vec4(0.85f, 0.24f, 0.24f, 1.0f));
    blast({{0, -40, 0}, {0, 40, 0}}, glm::vec4(0.36f, 0.72f, 0.30f, 1.0f));
    blast({{0, 0, 0}, {0, 0, 56}}, glm::vec4(0.36f, 0.55f, 0.95f, 1.0f));
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
            if (p.baked) continue;  // real model geometry is in the batches now
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

void SceneRenderer::setSelectionWire(const std::vector<glm::vec3>& lines) {
    selCount_ = static_cast<GLsizei>(lines.size());
    if (selCount_ == 0) return;
    glBindVertexArray(selVao_);
    glBindBuffer(GL_ARRAY_BUFFER, selVbo_);
    glBufferData(GL_ARRAY_BUFFER, lines.size() * sizeof(glm::vec3), lines.data(),
                 GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(glm::vec3), nullptr);
    glBindVertexArray(0);
}

void SceneRenderer::setHoverWire(const std::vector<glm::vec3>& lines) {
    hovCount_ = static_cast<GLsizei>(lines.size());
    if (hovCount_ == 0) return;
    glBindVertexArray(hovVao_);
    glBindBuffer(GL_ARRAY_BUFFER, hovVbo_);
    glBufferData(GL_ARRAY_BUFFER, lines.size() * sizeof(glm::vec3), lines.data(),
                 GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(glm::vec3), nullptr);
    glBindVertexArray(0);
}

void SceneRenderer::drawSelectionWire(const glm::mat4& vp) {
    if (hovCount_ > 0) {
        lineShader_.use();
        lineShader_.set("uMVP", vp);
        lineShader_.set("uColor", glm::vec4(0.55f, 0.80f, 1.0f, 0.85f));  // soft blue
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glDisable(GL_DEPTH_TEST);
        glBindVertexArray(hovVao_);
        glDrawArrays(GL_LINES, 0, hovCount_);
        glBindVertexArray(0);
        glEnable(GL_DEPTH_TEST);
        glDisable(GL_BLEND);
    }
    if (selCount_ == 0) return;
    lineShader_.use();
    lineShader_.set("uMVP", vp);
    glBindVertexArray(selVao_);
    // Faint pass through occluders, then a bright depth-tested pass on top.
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glDisable(GL_DEPTH_TEST);
    lineShader_.set("uColor", glm::vec4(0.98f, 0.66f, 0.30f, 0.28f));
    glDrawArrays(GL_LINES, 0, selCount_);
    glEnable(GL_DEPTH_TEST);
    glDepthFunc(GL_LEQUAL);
    lineShader_.set("uColor", glm::vec4(1.0f, 0.72f, 0.34f, 1.0f));
    glDrawArrays(GL_LINES, 0, selCount_);
    glDepthFunc(GL_LESS);
    glDisable(GL_BLEND);
    glBindVertexArray(0);
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
    if (!ortho) drawGroundGrid3D(cam, aspect, s);

    if (ortho) {
        drawWire(vp, glm::vec3(0.82f, 0.85f, 0.90f), 0.95f);
        drawMarkers(vp, s, true);
    } else {
        if (!hasWorld()) drawOriginMarker(vp);   // empty map: show where 0,0,0 is
        drawSolid(vp, cam.pos, s);
        if (s.wireOverlay) {
            glEnable(GL_BLEND);
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
            drawWire(vp, glm::vec3(0.0f), 0.25f);
            glDisable(GL_BLEND);
        }
        drawMarkers(vp, s, false);
    }
    drawSelectionWire(vp);
}

}  // namespace pb
