#pragma once
#include <string>
#include <utility>
#include <vector>

namespace pb::map {

// A generic Valve KeyValues node: an ordered list of "key" "value" pairs plus
// named child blocks. Used for VMF (and FGD-ish) parsing and re-serialisation.
struct KvNode {
    std::string name;
    std::vector<std::pair<std::string, std::string>> pairs;
    std::vector<KvNode> children;

    const std::string* find(const std::string& key) const {
        for (const auto& p : pairs)
            if (p.first == key) return &p.second;
        return nullptr;
    }
    std::string get(const std::string& key, const std::string& def = "") const {
        const std::string* v = find(key);
        return v ? *v : def;
    }
    int getInt(const std::string& key, int def = 0) const {
        const std::string* v = find(key);
        return v ? std::atoi(v->c_str()) : def;
    }
    float getFloat(const std::string& key, float def = 0.0f) const {
        const std::string* v = find(key);
        return v ? static_cast<float>(std::atof(v->c_str())) : def;
    }
    const KvNode* child(const std::string& n) const {
        for (const auto& c : children)
            if (c.name == n) return &c;
        return nullptr;
    }
    void set(const std::string& key, const std::string& value) {
        for (auto& p : pairs)
            if (p.first == key) {
                p.second = value;
                return;
            }
        pairs.emplace_back(key, value);
    }
};

// Parses a KeyValues / VMF document. Returns a synthetic root whose children are
// the top-level blocks (world, entity, versioninfo, ...).
KvNode parseKv(const std::string& text);

// Serialises a node's children (the top-level blocks) back to VMF text.
std::string writeKv(const KvNode& root);

}  // namespace pb::map
