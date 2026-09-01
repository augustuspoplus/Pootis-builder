#include "map/History.h"

#include "core/Log.h"

namespace pb::map {

namespace {
const std::string kNone;
}

History::Snap History::capture(const MapDocument& doc, std::string label) {
    Snap s;
    s.label = std::move(label);
    s.world = doc.worldSolids();
    s.entitySolids.reserve(doc.entities().size());
    for (const auto& e : doc.entities()) s.entitySolids.push_back(e.solids);
    return s;
}

void History::restore(MapDocument& doc, const Snap& s) {
    doc.worldSolids() = s.world;
    for (size_t i = 0; i < doc.entities().size() && i < s.entitySolids.size(); ++i)
        doc.entities()[i].solids = s.entitySolids[i];
    doc.markDirty();
}

void History::reset(const MapDocument& doc) {
    snaps_.clear();
    snaps_.push_back(capture(doc, "Open"));
    index_ = 0;
}

void History::record(const MapDocument& doc, std::string label) {
    if (snaps_.empty()) {
        reset(doc);
        return;
    }
    snaps_.resize(index_ + 1);  // drop redo tail
    snaps_.push_back(capture(doc, std::move(label)));
    if (snaps_.size() > kMax) {
        snaps_.erase(snaps_.begin());
    }
    index_ = snaps_.size() - 1;
}

const std::string& History::undoLabel() const {
    return canUndo() ? snaps_[index_].label : kNone;
}
const std::string& History::redoLabel() const {
    return canRedo() ? snaps_[index_ + 1].label : kNone;
}

bool History::undo(MapDocument& doc) {
    if (!canUndo()) return false;
    --index_;
    restore(doc, snaps_[index_]);
    return true;
}

bool History::redo(MapDocument& doc) {
    if (!canRedo()) return false;
    ++index_;
    restore(doc, snaps_[index_]);
    return true;
}

const std::string& History::labelAt(size_t i) const {
    return i < snaps_.size() ? snaps_[i].label : kNone;
}

bool History::jumpTo(MapDocument& doc, size_t i) {
    if (i >= snaps_.size() || i == index_) return false;
    index_ = i;
    restore(doc, snaps_[index_]);
    return true;
}

}  // namespace pb::map
