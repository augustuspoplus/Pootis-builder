#include "map/MapDocument.h"

#include <cstdio>
#include <filesystem>

#include "core/File.h"
#include "core/Log.h"

namespace fs = std::filesystem;

namespace pb::map {
namespace {

glm::vec3 parseVec3(const std::string& s, glm::vec3 def = glm::vec3(0)) {
    glm::vec3 v = def;
    if (std::sscanf(s.c_str(), " %f %f %f", &v.x, &v.y, &v.z) < 1) return def;
    return v;
}

MapEntity entityFromKv(const KvNode& node) {
    MapEntity e;
    e.id = node.getInt("id");
    e.classname = node.get("classname");
    e.origin = parseVec3(node.get("origin"));
    for (const auto& p : node.pairs) e.kv.pairs.push_back(p);
    for (const auto& c : node.children) {
        if (c.name == "solid") {
            e.solids.push_back(solidFromKv(c));
        } else if (c.name == "connections") {
            for (const auto& p : c.pairs) e.connections.push_back(p);
        }
        // "editor", "hidden", "group" blocks: kept implicitly by re-emit later.
    }
    return e;
}

}  // namespace

void MapDocument::clear() {
    worldExtra_ = {};
    active_ = false;
    worldSolids_.clear();
    entities_.clear();
    path_.clear();
    name_.clear();
    dirty_ = false;
    lastId_ = 0;
}

void MapDocument::newBlank(const std::string& name) {
    clear();
    name_ = name;
    lastId_ = 1;
    worldExtra_.set("skyname", "sky_day01_01");
    worldExtra_.set("detailmaterial", "detail/detailsprites");
    worldExtra_.set("detailvbsp", "detail.vbsp");
    active_ = true;
    dirty_ = true;
}

bool MapDocument::loadVmf(const std::string& path, std::string* err) {
    clear();
    const std::string text = readTextFile(path);
    if (text.empty()) {
        if (err) *err = "cannot read " + path;
        return false;
    }
    const KvNode root = parseKv(text);

    for (const auto& block : root.children) {
        if (block.name == "world") {
            for (const auto& p : block.pairs) worldExtra_.pairs.push_back(p);
            for (const auto& c : block.children) {
                if (c.name == "solid") {
                    Solid s = solidFromKv(c);
                    lastId_ = std::max(lastId_, s.id);
                    worldSolids_.push_back(std::move(s));
                }
            }
        } else if (block.name == "entity") {
            MapEntity e = entityFromKv(block);
            lastId_ = std::max(lastId_, e.id);
            for (const auto& s : e.solids) lastId_ = std::max(lastId_, s.id);
            entities_.push_back(std::move(e));
        }
    }

    path_ = path;
    name_ = fs::path(path).stem().string();
    active_ = true;
    size_t validBrushes = 0;
    for (const auto& s : worldSolids_)
        if (s.valid) ++validBrushes;
    PB_INFO("VMF loaded: %s — %zu world solids (%zu valid), %zu entities",
            name_.c_str(), worldSolids_.size(), validBrushes, entities_.size());
    return true;
}

bool MapDocument::saveVmf(const std::string& path, std::string* err,
                          bool updateState) {
    KvNode root;

    KvNode ver;
    ver.name = "versioninfo";
    ver.set("editorversion", "400");
    ver.set("editorbuild", "8000");
    ver.set("mapversion", "1");
    ver.set("formatversion", "100");
    ver.set("prefab", "0");
    root.children.push_back(ver);

    KvNode world;
    world.name = "world";
    world.set("id", "1");
    world.set("mapversion", "1");
    world.set("classname", "worldspawn");
    for (const auto& p : worldExtra_.pairs)
        if (p.first != "id" && p.first != "classname" && p.first != "mapversion")
            world.set(p.first, p.second);
    if (!world.find("skyname")) world.set("skyname", "sky_day01_01");
    for (const auto& s : worldSolids_) world.children.push_back(solidToKv(s));
    root.children.push_back(std::move(world));

    for (const auto& e : entities_) {
        KvNode en;
        en.name = "entity";
        en.set("id", std::to_string(e.id));
        for (const auto& p : e.kv.pairs)
            if (p.first != "id") en.set(p.first, p.second);
        if (!en.find("classname")) en.set("classname", e.classname);
        if (!e.connections.empty()) {
            KvNode con;
            con.name = "connections";
            for (const auto& c : e.connections) con.pairs.push_back(c);
            en.children.push_back(std::move(con));
        }
        for (const auto& s : e.solids) en.children.push_back(solidToKv(s));
        root.children.push_back(std::move(en));
    }

    const std::string out = writeKv(root);
    std::string ok;
    {
        std::error_code ec;
        const fs::path parent = fs::path(path).parent_path();
        if (!parent.empty()) fs::create_directories(parent, ec);
        FILE* f = std::fopen(path.c_str(), "wb");
        if (!f) {
            if (err) *err = "cannot write " + path;
            return false;
        }
        std::fwrite(out.data(), 1, out.size(), f);
        std::fclose(f);
    }
    if (updateState) {
        path_ = path;
        name_ = fs::path(path).stem().string();
        dirty_ = false;
    }
    PB_INFO("VMF %s: %s (%zu bytes)", updateState ? "saved" : "written",
            path.c_str(), out.size());
    return true;
}

Solid* MapDocument::resolve(const SolidRef& r) {
    if (r.solid < 0) return nullptr;
    if (r.entity < 0) {
        return r.solid < static_cast<int>(worldSolids_.size())
                   ? &worldSolids_[r.solid]
                   : nullptr;
    }
    if (r.entity >= static_cast<int>(entities_.size())) return nullptr;
    auto& s = entities_[r.entity].solids;
    return r.solid < static_cast<int>(s.size()) ? &s[r.solid] : nullptr;
}

const Solid* MapDocument::resolve(const SolidRef& r) const {
    return const_cast<MapDocument*>(this)->resolve(r);
}

void MapDocument::bounds(glm::vec3& mn, glm::vec3& mx) const {
    mn = glm::vec3(1e30f);
    mx = glm::vec3(-1e30f);
    auto add = [&](const Solid& s) {
        if (!s.valid) return;
        mn = glm::min(mn, s.boundsMin);
        mx = glm::max(mx, s.boundsMax);
    };
    for (const auto& s : worldSolids_) add(s);
    for (const auto& e : entities_) {
        for (const auto& s : e.solids) add(s);
        if (e.solids.empty()) {
            mn = glm::min(mn, e.origin - glm::vec3(16));
            mx = glm::max(mx, e.origin + glm::vec3(16));
        }
    }
    if (mn.x > mx.x) {
        mn = glm::vec3(-512);
        mx = glm::vec3(512);
    }
}

}  // namespace pb::map
