#pragma once
#include <map>
#include <string>
#include <vector>

#include <glm/glm.hpp>

namespace pb::fgd {

// The widget family a key maps to in the properties panel.
enum class VarType {
    String,
    Integer,
    Float,
    Bool,
    Choices,
    Flags,
    TargetSource,   // this entity's name
    TargetDest,     // points at another entity's name
    Color255,
    Color1,
    Studio,         // model path
    Sprite,         // sprite/material path
    Material,
    Sound,
    Scene,
    Particle,
    Angle,
    Vector,
    Origin,
    Axis,
    Side,
    SideList,
    NodeDest,
    InstanceFile,
    InstanceVariable,
    PointEntityClass,
    NpcClass,
    FilterClass,
    Decal,
    Unknown,
};

struct Choice {
    std::string value;
    std::string label;
};

struct FlagBit {
    int bit = 0;
    std::string label;
    bool defOn = false;
};

struct Var {
    std::string key;
    VarType type = VarType::String;
    std::string rawType;      // the literal "(...)" contents, for unknown types
    std::string displayName;
    std::string defaultValue;
    std::string help;
    bool readOnly = false;
    bool reportable = false;
    bool inherited = false;   // set by flattened(): came from a base class
    std::vector<Choice> choices;   // Choices
    std::vector<FlagBit> flags;    // Flags
};

struct IO {
    std::string name;
    std::string type;   // void, integer, float, string, bool, ...
    std::string help;
};

enum class ClassKind { Base, Point, Solid, NPC, KeyFrame, Move, Filter, Other };

struct EntityClass {
    ClassKind kind = ClassKind::Other;
    std::string name;
    std::string description;
    std::string help;                 // long help text (first key-less string)
    std::vector<std::string> bases;
    bool hasSize = false;
    glm::vec3 sizeMin{-8}, sizeMax{8};
    bool hasColor = false;
    glm::vec3 color{1.0f, 0.4f, 1.0f};
    std::string studioModel;          // studio("...") / model default
    std::string iconSprite;           // iconsprite("...")

    std::vector<Var> vars;
    std::vector<IO> inputs;
    std::vector<IO> outputs;

    bool isPoint() const { return kind == ClassKind::Point || kind == ClassKind::NPC ||
                                  kind == ClassKind::KeyFrame || kind == ClassKind::Move; }
    bool isSolid() const { return kind == ClassKind::Solid; }
};

// A parsed FGD (with @includes resolved). Point/solid classes are what the
// editor exposes; base classes are kept only to flatten inheritance.
class Fgd {
public:
    // Parses `path` and everything it @includes. Missing includes are skipped
    // with a warning. Returns false only if the top file can't be read.
    bool load(const std::string& path);

    const EntityClass* find(const std::string& name) const;

    // `name`'s keys/inputs/outputs with every base class expanded (Hammer
    // order: bases first, in declaration order; a derived key with the same
    // name overrides the inherited one in place). Cached.
    const EntityClass* flattened(const std::string& name) const;

    // All point / solid classes, sorted by name.
    const std::vector<std::string>& pointClasses() const { return pointClasses_; }
    const std::vector<std::string>& solidClasses() const { return solidClasses_; }

    bool empty() const { return classes_.empty(); }
    size_t size() const { return classes_.size(); }

private:
    void parseText(const std::string& text, const std::string& dir, int depth);
    void indexClasses();

    std::map<std::string, EntityClass> classes_;
    mutable std::map<std::string, EntityClass> flatCache_;
    std::vector<std::string> pointClasses_;
    std::vector<std::string> solidClasses_;
};

VarType varTypeFromString(const std::string& s);
const char* varTypeName(VarType t);

}  // namespace pb::fgd
