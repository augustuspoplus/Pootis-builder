#include "render/MaterialLibrary.h"

#include <vector>

#include "core/Log.h"

namespace pb {

MaterialLibrary::~MaterialLibrary() { clear(); }

void MaterialLibrary::init(source::SourceFs* fs) {
    fs_ = fs;
    if (!checker_) checker_ = makeChecker();
}

void MaterialLibrary::clear() {
    for (auto& [name, info] : cache_)
        if (info.texture && info.texture != checker_) glDeleteTextures(1, &info.texture);
    cache_.clear();
}

GLuint MaterialLibrary::makeChecker() {
    const int S = 64;
    std::vector<uint8_t> px(S * S * 4);
    for (int y = 0; y < S; ++y)
        for (int x = 0; x < S; ++x) {
            const bool c = ((x / 8) ^ (y / 8)) & 1;
            uint8_t* p = &px[(y * S + x) * 4];
            p[0] = c ? 200 : 40;
            p[1] = c ? 40 : 40;
            p[2] = c ? 200 : 40;
            p[3] = 255;
        }
    GLuint t = 0;
    glGenTextures(1, &t);
    glBindTexture(GL_TEXTURE_2D, t);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, S, S, 0, GL_RGBA, GL_UNSIGNED_BYTE,
                 px.data());
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    return t;
}

GLuint MaterialLibrary::upload(const source::VtfImage& img) {
    GLuint t = 0;
    glGenTextures(1, &t);
    glBindTexture(GL_TEXTURE_2D, t);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, img.width, img.height, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, img.rgba.data());
    glGenerateMipmap(GL_TEXTURE_2D);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
    GLfloat aniso = 0.0f;
    glGetFloatv(0x84FF /*GL_MAX_TEXTURE_MAX_ANISOTROPY*/, &aniso);
    if (aniso > 1.0f)
        glTexParameterf(GL_TEXTURE_2D, 0x84FE /*GL_TEXTURE_MAX_ANISOTROPY*/,
                        aniso > 8.0f ? 8.0f : aniso);
    return t;
}

const MaterialLibrary::Info& MaterialLibrary::get(const std::string& materialName) {
    auto it = cache_.find(materialName);
    if (it != cache_.end()) return it->second;

    Info info;
    info.texture = checker_;
    if (fs_) {
        source::ResolvedMaterial rm = fs_->resolveMaterial(materialName);
        info.found = rm.found;
        info.translucent = rm.translucent;
        info.alphaTest = rm.alphaTest;
        info.tool = rm.isTool || (!rm.found && materialName.rfind("tools/", 0) == 0);
        const std::string tex = !rm.baseTexture.empty() ? rm.baseTexture : materialName;
        source::VtfImage img = fs_->loadTexture(tex);
        if (img.ok()) {
            info.texture = upload(img);
            info.width = img.width;
            info.height = img.height;
        }
    }
    auto [ins, ok] = cache_.emplace(materialName, info);
    return ins->second;
}

bool MaterialLibrary::cached(const std::string& materialName) const {
    return cache_.find(materialName) != cache_.end();
}

}  // namespace pb
