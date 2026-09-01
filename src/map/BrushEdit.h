#pragma once
#include <utility>
#include <vector>

#include <glm/glm.hpp>

#include "map/Solid.h"

namespace pb::map {

// Sub-object handles for one solid, derived from its polygonised faces.
// Vertex editing treats the per-face vertex loops as authoritative: a drag
// moves every face-corner welded to a handle, then each touched face's plane
// is refitted from its (possibly no-longer-planar) loop.

struct VertHandle {
    glm::vec3 pos{0};
    // (faceIndex, vertIndexWithinThatFace) pairs that share this corner.
    std::vector<std::pair<int, int>> refs;
};

struct EdgeHandle {
    int a = 0, b = 0;  // indices into BrushHandles::verts
};

struct FaceHandle {
    int face = 0;
    glm::vec3 centroid{0};
    std::vector<int> verts;  // indices into BrushHandles::verts
};

struct BrushHandles {
    std::vector<VertHandle> verts;
    std::vector<EdgeHandle> edges;
    std::vector<FaceHandle> faces;
};

// Build vertex / edge / face handles for `s` (corners closer than `weld` are
// treated as the same vertex).
BrushHandles extractHandles(const Solid& s, float weld = 0.5f);

// Offset the given vertex handles by `delta` and refit the affected planes.
// `handleIdx` indexes into `h.verts`. `s` and `h` must have been produced
// together. Returns false if the result is degenerate (caller should undo).
bool moveVertexHandles(Solid& s, const BrushHandles& h,
                       const std::vector<int>& handleIdx, const glm::vec3& delta);

}  // namespace pb::map
