#pragma once
#include <functional>
#include <string>

#include "bsp/BspMesh.h"
#include "map/MapDocument.h"
#include "render/MaterialLibrary.h"

namespace pb::map {

// classname -> model path ("" if none). Lets the doc mesh show FGD studio()
// helper models for point entities (health kits, ammo, ...) without MapMesh
// depending on the FGD parser.
using ModelForClass = std::function<std::string(const std::string&)>;

// Builds a renderable mesh (same struct the BSP path uses) from the editable
// document, so SceneRenderer / MaterialLibrary work unchanged.
bsp::WorldMesh buildDocMesh(const MapDocument& doc, MaterialLibrary& materials,
                            const ModelForClass& modelForClass = {});

// Wireframe outline (line-pairs) of one solid, for the selection highlight.
std::vector<glm::vec3> solidWire(const Solid& s);

}  // namespace pb::map
