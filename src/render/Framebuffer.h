#pragma once
#include "gpu/Gl.h"

namespace pb {

// Off-screen render target (RGBA8 colour + depth24) shown inside an ImGui panel.
class Framebuffer {
public:
    Framebuffer() = default;
    ~Framebuffer();
    Framebuffer(const Framebuffer&) = delete;
    Framebuffer& operator=(const Framebuffer&) = delete;

    void resize(int w, int h);
    void bind() const;
    static void unbind();

    GLuint colorTexture() const { return color_; }
    int width() const { return w_; }
    int height() const { return h_; }

private:
    void destroy();
    GLuint fbo_ = 0, color_ = 0, depth_ = 0;
    int w_ = 0, h_ = 0;
};

}  // namespace pb
