#pragma once
#include <string>
#include <vector>

#include <glm/glm.hpp>

#include "ai/AiBackend.h"

namespace pb::ai {

// One kit placement the model asked for, after validation.
struct PlanItem {
    std::string piece;   // guaranteed to be a real kit piece name
    glm::vec3 pos{0.0f}; // grid-snapped, clamped inside Source's map limits
    float size = 0.0f;   // 0 = leave the editor's current value alone
    float height = 0.0f;
    int steps = 0;
};

struct Plan {
    std::vector<PlanItem> items;
    std::string note;
    std::vector<std::string> rejected;  // what we threw away, for the status line
};

// Source refuses geometry beyond +-16384; keep well inside it.
constexpr float kMaxCoord = 15000.0f;
constexpr size_t kMaxPieces = 60;

// Turn a model reply into a plan. Every piece name must appear in `kit` or the
// item is dropped; coordinates are clamped and snapped. Exposed separately from
// the network call so it can be tested on canned replies.
Plan validatePlan(const std::string& reply, const std::vector<std::string>& kit,
                  int gridSize);

// Ask for a layout. Blocking.
Plan requestGreybox(const Config& cfg, const std::string& brief,
                    const std::vector<std::string>& kit, int gridSize,
                    std::string* err);

}  // namespace pb::ai
