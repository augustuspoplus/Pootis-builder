#pragma once
#include <string>

#include <glm/glm.hpp>

#include "import/ObjModel.h"
#include "map/MapDocument.h"

namespace pb::import {

enum class ModelPlacement {
    DetailBrush,  // triangulated into func_detail solids, straight into the VMF
    Prop,         // baked to a Source .mdl by studiomdl on compile, placed as prop_static
};

struct ModelImportOptions {
    ModelPlacement mode = ModelPlacement::DetailBrush;
    std::string material = "dev/dev_measuregeneric01b";  // DetailBrush
    float shellThickness = 2.0f;   // DetailBrush: prism depth behind each tri
    int maxTris = 4096;            // DetailBrush: refuse above this (1 brush/tri)
    glm::vec3 origin{0};           // where to drop it (world units)
    std::string propDir = "pootisbuilder";  // Prop: models/<propDir>/<name>.mdl
};

// DetailBrush mode: fills `out` with a func_detail brush entity (one convex
// triangular prism per input triangle). Returns false with *err on failure
// (empty mesh, or tri count over maxTris).
bool meshToDetailEntity(const ObjMesh& mesh, const ModelImportOptions& opt,
                        map::MapDocument& doc, map::MapEntity& out,
                        std::string* err = nullptr);

// Prop mode: writes <name>.smd + <name>.qc into `stageDir` and returns the
// model path to reference (models/<propDir>/<name>.mdl). MapCompiler runs
// studiomdl on the .qc before vbsp. Returns false with *err on failure.
bool meshToPropStage(const ObjMesh& mesh, const ModelImportOptions& opt,
                     const std::string& stageDir, std::string& outModelPath,
                     std::string& outQcPath, std::string* err = nullptr);

}  // namespace pb::import
