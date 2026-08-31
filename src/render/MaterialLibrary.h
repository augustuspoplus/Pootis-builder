#pragma once
#include <string>
#include <unordered_map>

#include "gpu/Gl.h"
#include "source/SourceFs.h"

namespace pb {

// Turns Source material names into GL textures on demand, backed by a SourceFs
// mount stack. Also serves thumbnails for the material browser.
class MaterialLibrary {
public:
    ~MaterialLibrary();

    void init(source::SourceFs* fs);
    bool ready() const { return fs_ != nullptr; }

    struct Info {
        GLuint texture = 0;   // never 0 once resolved (falls back to a checker)
        bool translucent = false;
        bool alphaTest = false;
        bool found = false;
        bool tool = false;
        int width = 0, height = 0;
    };

    // Resolves + uploads (cached). materialName is the BSP texdata string.
    const Info& get(const std::string& materialName);

    void clear();

private:
    GLuint makeChecker();
    GLuint upload(const source::VtfImage& img);

    source::SourceFs* fs_ = nullptr;
    GLuint checker_ = 0;
    std::unordered_map<std::string, Info> cache_;
};

}  // namespace pb
