#pragma once
#include <string>
#include <vector>

#include <glm/glm.hpp>

#include "map/Kv.h"
#include "map/Solid.h"

namespace pb::map {

struct MapEntity {
    int id = 0;
    std::string classname;
    KvNode kv;  // every key/value (origin, angles, targetname, spawnflags, ...)
    glm::vec3 origin{0};
    std::vector<Solid> solids;  // non-empty for brush entities
    std::vector<std::pair<std::string, std::string>> connections;  // output -> args

    bool isBrush() const { return !solids.empty(); }
    std::string targetname() const { return kv.get("targetname"); }
};

// A reference to one selectable solid. entity == -1 means a world solid.
struct SolidRef {
    int entity = -1;
    int solid = -1;
    bool operator==(const SolidRef& o) const {
        return entity == o.entity && solid == o.solid;
    }
    bool valid() const { return solid >= 0; }
};

// The editable map. Loaded from / saved to VMF; drives the editor.
class MapDocument {
public:
    void clear();
    void newBlank(const std::string& name = "untitled");
    bool loadVmf(const std::string& path, std::string* err = nullptr);
    // updateState=false writes the file without touching path()/name()/dirty()
    // — used for autosaves and backups.
    bool saveVmf(const std::string& path, std::string* err = nullptr,
                 bool updateState = true);
    bool empty() const { return worldSolids_.empty() && entities_.empty(); }
    bool active() const { return active_; }  // a document is open (may be empty)

    std::vector<Solid>& worldSolids() { return worldSolids_; }
    const std::vector<Solid>& worldSolids() const { return worldSolids_; }
    std::vector<MapEntity>& entities() { return entities_; }
    const std::vector<MapEntity>& entities() const { return entities_; }
    KvNode& worldExtra() { return worldExtra_; }
    const std::string& path() const { return path_; }
    const std::string& name() const { return name_; }
    bool dirty() const { return dirty_; }
    void markDirty() { dirty_ = true; }

    Solid* resolve(const SolidRef& r);
    const Solid* resolve(const SolidRef& r) const;
    int nextId() { return ++lastId_; }

    void bounds(glm::vec3& mn, glm::vec3& mx) const;

private:
    KvNode worldExtra_;  // world's own key/values (skyname, detailmaterial, ...)
    std::vector<Solid> worldSolids_;
    std::vector<MapEntity> entities_;
    std::string path_, name_;
    bool dirty_ = false;
    bool active_ = false;
    int lastId_ = 0;
};

}  // namespace pb::map
