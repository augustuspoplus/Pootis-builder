#include "render/Framebuffer.h"

#include <algorithm>

#include "core/Log.h"

namespace pb {

Framebuffer::~Framebuffer() { destroy(); }

void Framebuffer::destroy() {
    if (color_) glDeleteTextures(1, &color_);
    if (depth_) glDeleteRenderbuffers(1, &depth_);
    if (fbo_) glDeleteFramebuffers(1, &fbo_);
    color_ = depth_ = fbo_ = 0;
    w_ = h_ = 0;
}

void Framebuffer::resize(int w, int h) {
    w = std::max(w, 1);
    h = std::max(h, 1);
    if (w == w_ && h == h_ && fbo_) return;

    if (!fbo_) glGenFramebuffers(1, &fbo_);
    if (!color_) glGenTextures(1, &color_);
    if (!depth_) glGenRenderbuffers(1, &depth_);

    glBindTexture(GL_TEXTURE_2D, color_);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glBindRenderbuffer(GL_RENDERBUFFER, depth_);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT24, w, h);

    glBindFramebuffer(GL_FRAMEBUFFER, fbo_);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, color_, 0);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, depth_);

    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
        PB_ERROR("Framebuffer incomplete (%dx%d)", w, h);

    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    w_ = w;
    h_ = h;
}

void Framebuffer::bind() const {
    glBindFramebuffer(GL_FRAMEBUFFER, fbo_);
    glViewport(0, 0, w_, h_);
}

void Framebuffer::unbind() { glBindFramebuffer(GL_FRAMEBUFFER, 0); }

}  // namespace pb
