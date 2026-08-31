#pragma once
#include <glm/glm.hpp>

#include "map/Solid.h"

namespace pb::map {

// Ray vs a convex brush (its polygonised faces). Returns the nearest positive
// hit distance in `tHit`. `rd` need not be normalised — `tHit` is in units of rd.
bool raySolid(const glm::vec3& ro, const glm::vec3& rd, const Solid& s, float& tHit);

bool rayAabb(const glm::vec3& ro, const glm::vec3& rd, const glm::vec3& mn,
             const glm::vec3& mx, float& tHit);

}  // namespace pb::map
