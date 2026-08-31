#include "render/Camera.h"

#include <algorithm>

#define GLM_ENABLE_EXPERIMENTAL
#include <glm/gtc/matrix_transform.hpp>

namespace pb {

namespace {
constexpr float kDeg2Rad = 3.14159265358979323846f / 180.0f;
constexpr glm::vec3 kWorldUp{0.0f, 0.0f, 1.0f};
}  // namespace

glm::vec3 Camera::forward() const {
    const float cy = std::cos(yawDeg * kDeg2Rad);
    const float sy = std::sin(yawDeg * kDeg2Rad);
    const float cp = std::cos(pitchDeg * kDeg2Rad);
    const float sp = std::sin(pitchDeg * kDeg2Rad);
    return glm::normalize(glm::vec3(cy * cp, sy * cp, sp));
}

glm::vec3 Camera::right() const {
    return glm::normalize(glm::cross(forward(), kWorldUp));
}

glm::vec3 Camera::up() const {
    return glm::normalize(glm::cross(right(), forward()));
}

glm::vec3 Camera::orthoForwardAxis() const {
    switch (kind) {
        case ViewKind::Top:   return {0.0f, 0.0f, -1.0f};
        case ViewKind::Front: return {0.0f, 1.0f, 0.0f};
        case ViewKind::Side:  return {-1.0f, 0.0f, 0.0f};
        default:              return {0.0f, 1.0f, 0.0f};
    }
}

glm::vec3 Camera::orthoUpAxis() const {
    switch (kind) {
        case ViewKind::Top:   return {0.0f, 1.0f, 0.0f};
        case ViewKind::Front: return {0.0f, 0.0f, 1.0f};
        case ViewKind::Side:  return {0.0f, 0.0f, 1.0f};
        default:              return {0.0f, 0.0f, 1.0f};
    }
}

glm::vec3 Camera::orthoRightAxis() const {
    return glm::normalize(glm::cross(orthoForwardAxis(), orthoUpAxis()));
}

glm::mat4 Camera::view() const {
    if (kind == ViewKind::Perspective)
        return glm::lookAt(pos, pos + forward(), kWorldUp);

    const glm::vec3 fwd = orthoForwardAxis();
    const glm::vec3 eye = orthoCenter - fwd * 50000.0f;
    return glm::lookAt(eye, eye + fwd, orthoUpAxis());
}

glm::mat4 Camera::proj(float aspect) const {
    if (kind == ViewKind::Perspective)
        return glm::perspective(fovDeg * kDeg2Rad, aspect <= 0.0f ? 1.0f : aspect,
                                nearPlane, farPlane);
    const float h = std::max(orthoHalfHeight, 1.0f);
    const float w = h * (aspect <= 0.0f ? 1.0f : aspect);
    return glm::ortho(-w, w, -h, h, -100000.0f, 100000.0f);
}

void Camera::frameBounds(const glm::vec3& mn, const glm::vec3& mx) {
    const glm::vec3 c = 0.5f * (mn + mx);
    const glm::vec3 ext = 0.5f * (mx - mn);
    const float radius = std::max(glm::length(ext), 64.0f);

    if (kind == ViewKind::Perspective) {
        // Place the eye back and above the box, then aim straight at its centre.
        const glm::vec3 dir = glm::normalize(glm::vec3(-0.6f, -0.6f, -0.35f));
        pos = c - dir * (radius * 1.6f);
        const glm::vec3 look = glm::normalize(c - pos);
        pitchDeg = glm::degrees(std::asin(std::clamp(look.z, -1.0f, 1.0f)));
        yawDeg = glm::degrees(std::atan2(look.y, look.x));
    } else {
        orthoCenter = c;
        const glm::vec3 up = orthoUpAxis();
        const glm::vec3 rt = orthoRightAxis();
        const float halfV = std::abs(glm::dot(ext, up));
        const float halfH = std::abs(glm::dot(ext, rt));
        orthoHalfHeight = std::max(halfV, halfH) * 1.15f + 32.0f;
    }
}

void Camera::panOrtho(glm::vec2 pixelDelta, float aspect, glm::ivec2 viewportPx) {
    if (viewportPx.y <= 0) return;
    const float unitsPerPixel = (2.0f * orthoHalfHeight) / static_cast<float>(viewportPx.y);
    orthoCenter -= orthoRightAxis() * (pixelDelta.x * unitsPerPixel);
    orthoCenter += orthoUpAxis() * (pixelDelta.y * unitsPerPixel);
    (void)aspect;
}

void Camera::zoomOrtho(float scroll, glm::vec2 mousePx, float aspect, glm::ivec2 viewportPx) {
    if (viewportPx.y <= 0 || scroll == 0.0f) return;
    const float factor = std::pow(0.88f, scroll);

    // Keep the world point under the cursor stationary.
    const glm::vec2 ndc{
        (mousePx.x / viewportPx.x) * 2.0f - 1.0f,
        1.0f - (mousePx.y / viewportPx.y) * 2.0f,
    };
    const float halfH = orthoHalfHeight;
    const float halfW = halfH * (aspect <= 0.0f ? 1.0f : aspect);
    const glm::vec3 before = orthoCenter + orthoRightAxis() * (ndc.x * halfW) +
                             orthoUpAxis() * (ndc.y * halfH);
    orthoHalfHeight = std::clamp(orthoHalfHeight * factor, 8.0f, 200000.0f);
    const float nHalfH = orthoHalfHeight;
    const float nHalfW = nHalfH * (aspect <= 0.0f ? 1.0f : aspect);
    const glm::vec3 after = orthoCenter + orthoRightAxis() * (ndc.x * nHalfW) +
                            orthoUpAxis() * (ndc.y * nHalfH);
    orthoCenter += before - after;
}

}  // namespace pb
