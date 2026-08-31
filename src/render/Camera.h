#pragma once
#include <glm/glm.hpp>

namespace pb {

enum class ViewKind { Perspective, Top, Front, Side };

// A camera for one viewport. Source/Hammer world space is Z-up, X forward,
// Y left; distances are in Hammer units.
class Camera {
public:
    ViewKind kind = ViewKind::Perspective;

    // Perspective (fly) state.
    glm::vec3 pos{0.0f, -600.0f, 400.0f};
    float yawDeg = 90.0f;    // around +Z, 0 = +X
    float pitchDeg = -25.0f;
    float fovDeg = 75.0f;

    // Orthographic state.
    glm::vec3 orthoCenter{0.0f};
    float orthoHalfHeight = 1024.0f;  // world units from center to top edge

    float nearPlane = 4.0f;
    float farPlane = 100000.0f;

    glm::vec3 forward() const;
    glm::vec3 right() const;
    glm::vec3 up() const;

    glm::mat4 view() const;
    glm::mat4 proj(float aspect) const;

    // World-space ray through a pixel of a viewport of the given size.
    void pixelRay(const glm::vec2& px, const glm::vec2& viewportPx, glm::vec3& outOrigin,
                  glm::vec3& outDir) const;

    // Frame an axis-aligned box so it fills the view.
    void frameBounds(const glm::vec3& mn, const glm::vec3& mx);

    // Ortho helpers.
    void panOrtho(glm::vec2 pixelDelta, float aspect, glm::ivec2 viewportPx);
    void zoomOrtho(float scroll, glm::vec2 mousePx, float aspect, glm::ivec2 viewportPx);
    glm::vec3 orthoRightAxis() const;
    glm::vec3 orthoUpAxis() const;
    glm::vec3 orthoForwardAxis() const;
};

}  // namespace pb
