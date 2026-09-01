#pragma once
#include <string>
#include <vector>

#include "map/MapDocument.h"

namespace pb::map {

// Simple snapshot undo/redo over a MapDocument's brushwork. Snapshots the world
// solids and each entity's brush solids (entity keyvalue editing is handled
// separately). Memory-heavy on huge maps — capped; revisit with deltas later.
class History {
public:
    void reset(const MapDocument& doc);          // clear + take the baseline
    void record(const MapDocument& doc, std::string label);  // after a change

    bool canUndo() const { return index_ > 0; }
    bool canRedo() const { return index_ + 1 < snaps_.size(); }
    const std::string& undoLabel() const;
    const std::string& redoLabel() const;

    bool undo(MapDocument& doc);
    bool redo(MapDocument& doc);

private:
    struct Snap {
        std::string label;
        std::vector<Solid> world;
        std::vector<std::vector<Solid>> entitySolids;
    };
    static Snap capture(const MapDocument& doc, std::string label);
    static void restore(MapDocument& doc, const Snap& s);

    std::vector<Snap> snaps_;
    size_t index_ = 0;
    static constexpr size_t kMax = 32;
};

}  // namespace pb::map
