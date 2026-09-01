#pragma once
#include <string>
#include <unordered_map>

#include "gpu/Gl.h"
#include "render/Shader.h"

namespace pb {
class MaterialLibrary;
}
namespace pb::model {
struct StudioModel;
}

namespace pb::render {

// Renders a small textured 3/4-view preview of a StudioModel into an offscreen
// FBO and hands back a GL texture id, cached by model path. Cheap enough to
// call a few times per frame while a list scrolls.
class ModelThumbnailer {
public:
    ~ModelThumbnailer();
    bool init(int size = 160);

    // Returns a cached texture for `path`, rendering it from `model` on the
    // first request (returns 0 if the model isn't ok).
    GLuint get(const std::string& path, const model::StudioModel& model,
               MaterialLibrary& materials);

    bool has(const std::string& path) const { return cache_.count(path) != 0; }
    void clear();

private:
    GLuint render(const model::StudioModel& model, MaterialLibrary& materials);

    int size_ = 160;
    GLuint fbo_ = 0, depth_ = 0;
    GLuint vao_ = 0, vbo_ = 0, ebo_ = 0;
    Shader prog_;
    std::unordered_map<std::string, GLuint> cache_;
};

}  // namespace pb::render
