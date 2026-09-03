#pragma once
#include <string>
#include <vector>

#include "ai/AiBackend.h"

namespace pb::ai {

// One material per surface role. Empty entries mean "the model didn't give a
// usable answer for this slot" — the caller leaves those faces alone.
struct MaterialPick {
    std::string floor, wall, ceiling, trim, accent;
    std::string note;  // one short line from the model, for the status bar

    // The rest of the art pass: the same mood should drive sky, fog and sun,
    // not just the brush textures. -1 / sentinels mean "the model didn't say".
    std::string skyname;              // validated against the game's skyboxes
    int fogR = -1, fogG = -1, fogB = -1;
    float fogStart = -1.0f, fogEnd = -1.0f;
    int sunR = -1, sunG = -1, sunB = -1;
    float sunPitch = 1e9f, sunYaw = 1e9f;

    bool anyMaterial() const {
        return !floor.empty() || !wall.empty() || !ceiling.empty() ||
               !trim.empty() || !accent.empty();
    }
    bool hasFog() const { return fogR >= 0 && fogEnd > 0.0f; }
    bool hasSun() const { return sunPitch < 1e8f || sunR >= 0; }
    bool any() const {
        return anyMaterial() || !skyname.empty() || hasFog() || hasSun();
    }
};

// Score the full material list against `mood` and return a shortlist small
// enough to put in a prompt. Deterministic and network-free, so it is unit
// testable on its own. Always mixes in a spread of the common construction
// buckets so the model has something sane to fall back on.
std::vector<std::string> buildPool(const std::vector<std::string>& all,
                                   const std::string& mood, size_t maxN = 180);

// Ask the model to fill the roles from `pool`. Every returned name is checked
// against `pool` — anything invented is dropped rather than applied. Blocking.
// `skies` are the sky names the game actually has (sky_tf2_04, sky_alpine_01,
// ...); anything else the model names is discarded.
MaterialPick suggestMaterials(const Config& cfg, const std::string& mood,
                              const std::vector<std::string>& pool,
                              const std::vector<std::string>& skies,
                              std::string* err);

}  // namespace pb::ai
