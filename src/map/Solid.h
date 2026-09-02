#pragma once
#include <string>
#include <vector>

#include <glm/glm.hpp>

#include "map/Kv.h"

namespace pb::map {

// One face of a brush: an outward-facing plane plus its material/UV projection.
// `verts` is filled by Solid::polygonise() (CCW around `plane` xyz).
struct BrushFace {
    glm::vec3 planeN{0, 0, 1};   // outward normal (unit)
    float planeD = 0.0f;         // dot(planeN, p) == planeD on the plane
    std::string material = "tools/toolsnodraw";
    glm::vec4 uAxis{1, 0, 0, 0}; // xyz dir + w offset (texels)
    glm::vec4 vAxis{0, -1, 0, 0};
    float uScale = 0.25f, vScale = 0.25f;
    float rotation = 0.0f;
    float lightmapScale = 16.0f;
    int smoothingGroups = 0;

    // Displacement: the raw Source "dispinfo" block (power / startposition /
    // normals / distances / offsets / alphas / triangle tags). Kept verbatim so
    // decompiled terrain round-trips through load -> save losslessly. `disp`
    // holds the parsed grid once it is rendered or edited.
    KvNode dispInfo;
    bool hasDisp = false;

    std::vector<glm::vec3> verts;

    // Source plane points (kept for lossless round-trip of untouched faces).
    glm::vec3 p0{0}, p1{0}, p2{0};
    bool planeFromPoints = true;

    glm::vec2 texUV(const glm::vec3& pos, float texW, float texH) const;
};

// A convex brush = an intersection of half-spaces {p : dot(faceN,p) <= faceD}.
struct Solid {
    int id = 0;
    int group = 0;  // 0 = ungrouped; solids sharing an id select together
    bool hidden = false;  // transient: hidden by a visgroup
    std::vector<BrushFace> faces;
    glm::vec3 boundsMin{0}, boundsMax{0};
    glm::vec3 editorColor{0.7f, 0.55f, 0.35f};
    bool valid = false;
    KvNode extra;  // "editor" block etc., preserved for save

    void polygonise();          // fill every face's verts from the plane set
    void recomputeBounds();
    void translate(const glm::vec3& d);
    void transform(const glm::mat4& m);  // rebuilds planes from moved geometry
    void resizeTo(const glm::vec3& newMin, const glm::vec3& newMax);  // affine bounds fit
    glm::vec3 center() const { return 0.5f * (boundsMin + boundsMax); }

    // Axis-aligned box brush from min/max with one material on all 6 sides.
    static Solid makeBox(const glm::vec3& mn, const glm::vec3& mx,
                         const std::string& material);

    // Convex brush from a set of outward half-space planes (dot(n,p) <= d).
    static Solid fromPlanes(const std::vector<std::pair<glm::vec3, float>>& planes,
                            const std::string& material);

    // Cut with the half-space dot(n,p) <= d: adds the plane as a new face and
    // re-polygonises. `cutMaterial` textures the exposed face. Returns false
    // (and leaves the solid unchanged) if the cut would remove the whole brush.
    bool clip(const glm::vec3& n, float d, const std::string& cutMaterial);
};

Solid solidFromKv(const KvNode& solidNode);
KvNode solidToKv(const Solid& s);

// Shell `s` into `wall`-thick slabs (uses its AABB). Returns up to 6 boxes.
std::vector<Solid> hollow(const Solid& s, float wall);

// Convex carve: `target` minus `cutter`, as a set of convex pieces. Returns
// { target } unchanged when the two do not overlap; {} when target is wholly
// inside cutter.
std::vector<Solid> carve(const Solid& target, const Solid& cutter);

// --- Texture / UV tool helpers (operate on one polygonised face) -----------
// Reset the U/V axes to world-axis alignment for the face's dominant normal
// (Hammer's default projection). Clears rotation; keeps scale + offset.
void faceAlignWorld(BrushFace& f);
// Project the U/V axes into the face plane (u along an in-plane tangent,
// v = n x u). Clears rotation; keeps scale + offset.
void faceAlignToFace(BrushFace& f);
// Rotate the current U/V axes by `deltaDeg` about the face normal.
void faceRotateUV(BrushFace& f, float deltaDeg);
// Justify the texture across the face's extent. mode: 0 fit, 1 top, 2 bottom,
// 3 left, 4 right, 5 center. texW/texH are the material's pixel size.
void faceJustifyUV(BrushFace& f, int texW, int texH, int mode);

}  // namespace pb::map
