#include "render/ModelThumbnailer.h"

#include <vector>

#include <glm/glm.hpp>
#include <glm/gtc/matrix_transform.hpp>

#include "core/Log.h"
#include "model/StudioModel.h"
#include "render/MaterialLibrary.h"

namespace pb::render {

namespace {
const char* kVert = R"(#version 330 core
layout(location=0) in vec3 aPos;
layout(location=1) in vec3 aNormal;
layout(location=2) in vec2 aUv;
uniform mat4 uMVP;
out vec3 vN;
out vec2 vUv;
void main() {
    vN = aNormal;
    vUv = aUv;
    gl_Position = uMVP * vec4(aPos, 1.0);
}
)";
const char* kFrag = R"(#version 330 core
in vec3 vN;
in vec2 vUv;
uniform sampler2D uTex;
uniform int uHasTex;
uniform vec3 uLight;
out vec4 frag;
void main() {
    vec3 base = uHasTex == 1 ? texture(uTex, vUv).rgb : vec3(0.62);
    float l = 0.32 + 0.68 * max(dot(normalize(vN), normalize(uLight)), 0.0);
    // gentle rim so dark props still read against the dark cell
    float rim = pow(1.0 - abs(normalize(vN).y), 3.0) * 0.15;
    frag = vec4(base * l + rim, 1.0);
}
)";
}  // namespace

ModelThumbnailer::~ModelThumbnailer() { clear(); }

bool ModelThumbnailer::init(int size) {
    size_ = size;
    if (!prog_.compile(kVert, kFrag, "modelthumb")) return false;

    glGenFramebuffers(1, &fbo_);
    glGenRenderbuffers(1, &depth_);
    glBindRenderbuffer(GL_RENDERBUFFER, depth_);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, size_, size_);
    glBindRenderbuffer(GL_RENDERBUFFER, 0);

    glGenVertexArrays(1, &vao_);
    glGenBuffers(1, &vbo_);
    glGenBuffers(1, &ebo_);
    return true;
}

void ModelThumbnailer::clear() {
    for (auto& [k, t] : cache_)
        if (t) glDeleteTextures(1, &t);
    cache_.clear();
}

GLuint ModelThumbnailer::get(const std::string& path,
                             const model::StudioModel& model,
                             MaterialLibrary& materials) {
    auto it = cache_.find(path);
    if (it != cache_.end()) return it->second;
    const GLuint tex = model.ok ? render(model, materials) : 0;
    cache_[path] = tex;
    return tex;
}

GLuint ModelThumbnailer::render(const model::StudioModel& model,
                               MaterialLibrary& materials) {
    // Interleaved VBO: pos(3) normal(3) uv(2).
    std::vector<float> vtx;
    vtx.reserve(model.verts.size() * 8);
    for (const auto& v : model.verts) {
        vtx.insert(vtx.end(), {v.pos.x, v.pos.y, v.pos.z, v.normal.x, v.normal.y,
                               v.normal.z, v.uv.x, v.uv.y});
    }
    glBindVertexArray(vao_);
    glBindBuffer(GL_ARRAY_BUFFER, vbo_);
    glBufferData(GL_ARRAY_BUFFER, vtx.size() * sizeof(float), vtx.data(),
                 GL_STATIC_DRAW);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo_);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, model.indices.size() * sizeof(uint32_t),
                 model.indices.data(), GL_STATIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 8 * sizeof(float), (void*)0);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 8 * sizeof(float),
                          (void*)(3 * sizeof(float)));
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 2, GL_FLOAT, GL_FALSE, 8 * sizeof(float),
                          (void*)(6 * sizeof(float)));

    GLuint tex = 0;
    glGenTextures(1, &tex);
    glBindTexture(GL_TEXTURE_2D, tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, size_, size_, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

    GLint prevFbo = 0, prevVp[4];
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prevFbo);
    glGetIntegerv(GL_VIEWPORT, prevVp);

    glBindFramebuffer(GL_FRAMEBUFFER, fbo_);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, tex, 0);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER,
                              depth_);
    glViewport(0, 0, size_, size_);
    glClearColor(0.10f, 0.105f, 0.12f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glEnable(GL_DEPTH_TEST);
    glDisable(GL_CULL_FACE);

    // Frame the model's bounding sphere from a fixed 3/4 angle.
    const glm::vec3 c = 0.5f * (model.boundsMin + model.boundsMax);
    const float radius =
        glm::max(0.5f * glm::length(model.boundsMax - model.boundsMin), 4.0f);
    const glm::vec3 dir = glm::normalize(glm::vec3(0.75f, -1.0f, 0.55f));
    const float fovy = glm::radians(38.0f);
    const float dist = radius / std::tan(fovy * 0.5f) * 1.15f;
    const glm::vec3 eye = c - dir * dist;
    const glm::mat4 view =
        glm::lookAt(eye, c, glm::vec3(0, 0, 1));
    const glm::mat4 proj =
        glm::perspective(fovy, 1.0f, glm::max(dist - radius * 2.0f, 1.0f),
                         dist + radius * 3.0f);
    const glm::mat4 mvp = proj * view;

    prog_.use();
    prog_.set("uMVP", mvp);
    prog_.set("uLight", glm::vec3(0.4f, -0.7f, 0.9f));
    prog_.set("uTex", 0);
    glActiveTexture(GL_TEXTURE0);

    for (const auto& m : model.meshes) {
        const auto& info = materials.get(m.material);
        // Only bind a texture that actually resolved — the checker fallback
        // reads as purple/black noise on a thumbnail, so show flat grey instead.
        const bool hasTex = info.texture != 0 && info.found;
        prog_.set("uHasTex", hasTex ? 1 : 0);
        if (hasTex) glBindTexture(GL_TEXTURE_2D, info.texture);
        glDrawElements(GL_TRIANGLES, (GLsizei)m.indexCount, GL_UNSIGNED_INT,
                       (void*)(m.firstIndex * sizeof(uint32_t)));
    }

    glBindVertexArray(0);
    glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prevFbo);
    glViewport(prevVp[0], prevVp[1], prevVp[2], prevVp[3]);
    return tex;
}

}  // namespace pb::render
