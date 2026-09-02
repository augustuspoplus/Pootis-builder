#pragma once
#include <string>
#include <vector>

#include "map/MapDocument.h"

namespace pb::map {

// Simple snapshot undo/redo over a MapDocument. Snapshots the world solids and
// the full entity list (classnames, key/values, origin, connections, brush
// solids), so adding, deleting, moving and re-keying entities all undo.
// Memory-heavy on huge maps — capped; revisit with deltas later.
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

    // For the history panel: every step, and jump straight to one.
    size_t count() const { return snaps_.size(); }
    size_t current() const { return index_; }
    const std::string& labelAt(size_t i) const;
    bool jumpTo(MapDocument& doc, size_t i);

private:
    struct Snap {
        std::string label;
        std::vector<Solid> world;
        std::vector<MapEntity> entities;
    };
    static Snap capture(const MapDocument& doc, std::string label);
    static void restore(MapDocument& doc, const Snap& s);

    std::vector<Snap> snaps_;
    size_t index_ = 0;
    static constexpr size_t kMax = 32;
};

}  // namespace pb::map
