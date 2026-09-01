#pragma once
#include <string>
#include <vector>

#include "fgd/Fgd.h"
#include "map/Kv.h"

namespace pb::ui {

// Renders one FGD key as a typed widget bound to kv[var.key]. Returns true the
// frame the value changes; sets *committed when the edit is "finished" (widget
// deactivated / enter) so the caller can push one undo step.
// `entityNames` feeds target/filter dropdowns.
bool fgdField(const fgd::Var& var, map::KvNode& kv,
              const std::vector<std::string>& entityNames, bool* committed);

// The spawnflags checkbox grid. Reads/writes kv["spawnflags"] as an int mask.
bool fgdFlags(const fgd::Var& spawnflags, map::KvNode& kv, bool* committed);

}  // namespace pb::ui
