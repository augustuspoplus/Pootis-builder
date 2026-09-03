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
    bool any() const {
        return !floor.empty() || !wall.empty() || !ceiling.empty() ||
               !trim.empty() || !accent.empty();
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
MaterialPick suggestMaterials(const Config& cfg, const std::string& mood,
                              const std::vector<std::string>& pool,
                              std::string* err);

}  // namespace pb::ai
