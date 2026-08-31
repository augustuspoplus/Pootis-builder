#pragma once
#include "bsp/BspMesh.h"
#include "map/MapDocument.h"
#include "render/MaterialLibrary.h"

namespace pb::map {

// Builds a renderable mesh (same struct the BSP path uses) from the editable
// document, so SceneRenderer / MaterialLibrary work unchanged.
bsp::WorldMesh buildDocMesh(const MapDocument& doc, MaterialLibrary& materials);

// Wireframe outline (line-pairs) of one solid, for the selection highlight.
std::vector<glm::vec3> solidWire(const Solid& s);

}  // namespace pb::map
