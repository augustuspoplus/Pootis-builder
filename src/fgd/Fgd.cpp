#include "fgd/Fgd.h"

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <filesystem>

#include "core/File.h"
#include "core/Log.h"

namespace fs = std::filesystem;

namespace pb::fgd {

VarType varTypeFromString(const std::string& s) {
    std::string t;
    for (char c : s) t += static_cast<char>(std::tolower((unsigned char)c));
    if (t == "string") return VarType::String;
    if (t == "integer" || t == "int") return VarType::Integer;
    if (t == "float") return VarType::Float;
    if (t == "bool" || t == "boolean") return VarType::Bool;
    if (t == "choices") return VarType::Choices;
    if (t == "flags") return VarType::Flags;
    if (t == "target_source") return VarType::TargetSource;
    if (t == "target_destination" || t == "target_name_or_class")
        return VarType::TargetDest;
    if (t == "color255") return VarType::Color255;
    if (t == "color1") return VarType::Color1;
    if (t == "studio" || t == "model") return VarType::Studio;
    if (t == "sprite") return VarType::Sprite;
    if (t == "material") return VarType::Material;
    if (t == "sound") return VarType::Sound;
    if (t == "scene") return VarType::Scene;
    if (t == "particlesystem") return VarType::Particle;
    if (t == "angle" || t == "angle_negative_pitch") return VarType::Angle;
    if (t == "vector") return VarType::Vector;
    if (t == "origin") return VarType::Origin;
    if (t == "axis" || t == "vecline") return VarType::Axis;
    if (t == "side") return VarType::Side;
    if (t == "sidelist") return VarType::SideList;
    if (t == "node_dest") return VarType::NodeDest;
    if (t == "instance_file") return VarType::InstanceFile;
    if (t == "instance_variable") return VarType::InstanceVariable;
    if (t == "pointentityclass") return VarType::PointEntityClass;
    if (t == "npcclass") return VarType::NpcClass;
    if (t == "filterclass") return VarType::FilterClass;
    if (t == "decal") return VarType::Decal;
    return VarType::Unknown;
}

const char* varTypeName(VarType t) {
    switch (t) {
        case VarType::String: return "string";
        case VarType::Integer: return "integer";
        case VarType::Float: return "float";
        case VarType::Bool: return "bool";
        case VarType::Choices: return "choices";
        case VarType::Flags: return "flags";
        case VarType::TargetSource: return "name";
        case VarType::TargetDest: return "entity";
        case VarType::Color255: return "color";
        case VarType::Color1: return "color";
        case VarType::Studio: return "model";
        case VarType::Sprite: return "sprite";
        case VarType::Material: return "material";
        case VarType::Sound: return "sound";
        case VarType::Scene: return "scene";
        case VarType::Particle: return "particle";
        case VarType::Angle: return "angle";
        case VarType::Vector: return "vector";
        case VarType::Origin: return "origin";
        case VarType::Axis: return "axis";
        default: return "text";
    }
}

namespace {

// ------------------------------------------------------------------ lexer ----
struct Tok {
    enum Kind { At, Ident, Str, Punct, End } kind = End;
    std::string s;    // Ident / Str text, or the punct char
};

class Lexer {
public:
    explicit Lexer(const std::string& src) : s_(src) {}

    Tok next() {
        if (peeked_) { peeked_ = false; return peekTok_; }
        return scan();
    }
    const Tok& peek() {
        if (!peeked_) { peekTok_ = scan(); peeked_ = true; }
        return peekTok_;
    }
    bool eof() { return peek().kind == Tok::End; }

private:
    void skipTrivia() {
        for (;;) {
            while (i_ < s_.size() &&
                   (unsigned char)s_[i_] <= ' ')
                ++i_;
            if (i_ + 1 < s_.size() && s_[i_] == '/' && s_[i_ + 1] == '/') {
                while (i_ < s_.size() && s_[i_] != '\n') ++i_;
                continue;
            }
            break;
        }
    }

    Tok scan() {
        skipTrivia();
        Tok t;
        if (i_ >= s_.size()) { t.kind = Tok::End; return t; }
        char c = s_[i_];
        if (c == '@') {
            ++i_;
            std::string w;
            while (i_ < s_.size() && (std::isalnum((unsigned char)s_[i_]) || s_[i_] == '_'))
                w += s_[i_++];
            t.kind = Tok::At;
            t.s = w;
            return t;
        }
        if (c == '"') {
            ++i_;
            std::string str;
            for (;;) {
                while (i_ < s_.size() && s_[i_] != '"') str += s_[i_++];
                if (i_ < s_.size()) ++i_;  // closing quote
                // string continuation:  "a" + "b"
                size_t save = i_;
                skipTrivia();
                if (i_ < s_.size() && s_[i_] == '+') {
                    ++i_;
                    skipTrivia();
                    if (i_ < s_.size() && s_[i_] == '"') { ++i_; continue; }
                }
                i_ = save;
                break;
            }
            t.kind = Tok::Str;
            t.s = str;
            return t;
        }
        if (std::isalnum((unsigned char)c) || c == '_' || c == '.' || c == '-') {
            std::string w;
            while (i_ < s_.size() &&
                   (std::isalnum((unsigned char)s_[i_]) || s_[i_] == '_' ||
                    s_[i_] == '.' || s_[i_] == '-'))
                w += s_[i_++];
            t.kind = Tok::Ident;
            t.s = w;
            return t;
        }
        // single-char punctuation
        ++i_;
        t.kind = Tok::Punct;
        t.s = std::string(1, c);
        return t;
    }

    const std::string& s_;
    size_t i_ = 0;
    bool peeked_ = false;
    Tok peekTok_;
};

bool isPunct(const Tok& t, char c) {
    return t.kind == Tok::Punct && t.s.size() == 1 && t.s[0] == c;
}

glm::vec3 parseVec3(const std::string& s, glm::vec3 def) {
    glm::vec3 v = def;
    std::sscanf(s.c_str(), "%f %f %f", &v.x, &v.y, &v.z);
    return v;
}

// Skip a balanced [ ... ] or ( ... ) block (the opener is the next token).
void skipBalanced(Lexer& lx, char open, char close) {
    if (!isPunct(lx.peek(), open)) return;
    lx.next();
    int depth = 1;
    while (!lx.eof() && depth > 0) {
        Tok t = lx.next();
        if (isPunct(t, open)) ++depth;
        else if (isPunct(t, close)) --depth;
    }
}

}  // namespace

// ---------------------------------------------------------------- parser ----
void Fgd::parseText(const std::string& text, const std::string& dir, int depth) {
    if (depth > 8) return;
    Lexer lx(text);

    while (!lx.eof()) {
        Tok t = lx.next();
        if (t.kind != Tok::At) continue;
        std::string at = t.s;
        for (auto& ch : at) ch = static_cast<char>(std::tolower((unsigned char)ch));

        if (at == "include") {
            if (lx.peek().kind == Tok::Str) {
                std::string inc = lx.next().s;
                fs::path p = fs::path(dir) / inc;
                std::string sub = readTextFile(p.string());
                if (sub.empty()) {
                    PB_WARN("fgd: cannot open include %s", p.string().c_str());
                } else {
                    parseText(sub, p.parent_path().string(), depth + 1);
                }
            }
            continue;
        }

        ClassKind kind;
        if (at == "baseclass") kind = ClassKind::Base;
        else if (at == "pointclass") kind = ClassKind::Point;
        else if (at == "solidclass") kind = ClassKind::Solid;
        else if (at == "npcclass") kind = ClassKind::NPC;
        else if (at == "keyframeclass") kind = ClassKind::KeyFrame;
        else if (at == "moveclass") kind = ClassKind::Move;
        else if (at == "filterclass") kind = ClassKind::Filter;
        else {
            // @mapsize(...), @MaterialExclusion [...], @AutoVisGroup ... [...] etc.
            // Consume up to and including the next top-level [...] or (...) if any,
            // otherwise nothing.
            while (!lx.eof() && !isPunct(lx.peek(), '[') && lx.peek().kind != Tok::At)
                lx.next();
            if (isPunct(lx.peek(), '[')) skipBalanced(lx, '[', ']');
            continue;
        }

        EntityClass ec;
        ec.kind = kind;

        // Header attributes until '='
        while (!lx.eof() && !isPunct(lx.peek(), '=')) {
            Tok a = lx.next();
            if (a.kind != Tok::Ident) continue;
            std::string attr = a.s;
            for (auto& ch : attr) ch = static_cast<char>(std::tolower((unsigned char)ch));
            if (!isPunct(lx.peek(), '(')) continue;
            // collect the (...) args as a list of tokens
            lx.next();  // (
            std::vector<Tok> args;
            int d = 1;
            while (!lx.eof() && d > 0) {
                Tok x = lx.next();
                if (isPunct(x, '(')) { ++d; args.push_back(x); }
                else if (isPunct(x, ')')) { if (--d > 0) args.push_back(x); }
                else args.push_back(x);
            }
            if (attr == "base") {
                for (const auto& x : args)
                    if (x.kind == Tok::Ident) ec.bases.push_back(x.s);
            } else if (attr == "size") {
                std::string a1, a2;
                bool second = false;
                for (const auto& x : args) {
                    if (isPunct(x, ',')) { second = true; continue; }
                    if (x.kind == Tok::Ident)
                        (second ? a2 : a1) += (((second ? a2 : a1).empty()) ? "" : " ") + x.s;
                }
                ec.hasSize = true;
                ec.sizeMin = parseVec3(a1, glm::vec3(-8));
                ec.sizeMax = parseVec3(a2, glm::vec3(8));
            } else if (attr == "color") {
                std::string c;
                for (const auto& x : args)
                    if (x.kind == Tok::Ident) c += (c.empty() ? "" : " ") + x.s;
                ec.hasColor = true;
                ec.color = parseVec3(c, glm::vec3(255)) / 255.0f;
            } else if (attr == "studio" || attr == "studioprop" || attr == "model") {
                for (const auto& x : args)
                    if (x.kind == Tok::Str) { ec.studioModel = x.s; break; }
            } else if (attr == "iconsprite" || attr == "sprite") {
                for (const auto& x : args)
                    if (x.kind == Tok::Str) { ec.iconSprite = x.s; break; }
            }
        }

        if (!isPunct(lx.peek(), '=')) continue;
        lx.next();  // =
        if (lx.peek().kind != Tok::Ident) continue;
        ec.name = lx.next().s;
        if (isPunct(lx.peek(), ':')) {
            lx.next();
            if (lx.peek().kind == Tok::Str) ec.description = lx.next().s;
            // an optional extra help string:  = name : "desc" : "help"
            if (isPunct(lx.peek(), ':')) {
                lx.next();
                if (lx.peek().kind == Tok::Str) ec.help = lx.next().s;
            }
        }

        // Body
        if (isPunct(lx.peek(), '[')) {
            lx.next();
            while (!lx.eof() && !isPunct(lx.peek(), ']')) {
                Tok head = lx.next();
                if (head.kind != Tok::Ident) continue;
                std::string lname = head.s;
                std::string low = lname;
                for (auto& ch : low) ch = static_cast<char>(std::tolower((unsigned char)ch));

                if (low == "input" || low == "output") {
                    IO io;
                    if (lx.peek().kind == Tok::Ident) io.name = lx.next().s;
                    if (isPunct(lx.peek(), '(')) {
                        lx.next();
                        if (lx.peek().kind == Tok::Ident) io.type = lx.next().s;
                        while (!lx.eof() && !isPunct(lx.peek(), ')')) lx.next();
                        if (isPunct(lx.peek(), ')')) lx.next();
                    }
                    if (isPunct(lx.peek(), ':')) {
                        lx.next();
                        if (lx.peek().kind == Tok::Str) io.help = lx.next().s;
                    }
                    if (low == "input") ec.inputs.push_back(std::move(io));
                    else ec.outputs.push_back(std::move(io));
                    continue;
                }

                // A key:  name(type) [: "Display" [: default [: "help"]]] [= [..]]
                Var v;
                v.key = lname;
                if (isPunct(lx.peek(), '(')) {
                    lx.next();
                    std::string ty;
                    while (!lx.eof() && !isPunct(lx.peek(), ')')) {
                        Tok x = lx.next();
                        ty += x.s;
                    }
                    if (isPunct(lx.peek(), ')')) lx.next();
                    v.rawType = ty;
                    v.type = varTypeFromString(ty);
                }
                // optional "readonly" / "report" markers
                while (lx.peek().kind == Tok::Ident) {
                    std::string m = lx.next().s;
                    for (auto& ch : m) ch = static_cast<char>(std::tolower((unsigned char)ch));
                    if (m == "readonly") v.readOnly = true;
                    else if (m == "report") v.reportable = true;
                }
                // up to 3 colon-separated slots: display : default : help
                for (int slot = 0; slot < 3; ++slot) {
                    if (!isPunct(lx.peek(), ':')) break;
                    lx.next();  // ':'
                    if (lx.peek().kind == Tok::Str || lx.peek().kind == Tok::Ident) {
                        const std::string val = lx.next().s;
                        if (slot == 0) v.displayName = val;
                        else if (slot == 1) v.defaultValue = val;
                        else v.help = val;
                    }
                }

                if (isPunct(lx.peek(), '=')) {
                    lx.next();
                    if (isPunct(lx.peek(), '[')) {
                        lx.next();
                        while (!lx.eof() && !isPunct(lx.peek(), ']')) {
                            Tok kv = lx.next();
                            std::string keyval = kv.s;
                            if (!isPunct(lx.peek(), ':')) continue;
                            lx.next();
                            std::string label;
                            if (lx.peek().kind == Tok::Str || lx.peek().kind == Tok::Ident)
                                label = lx.next().s;
                            if (v.type == VarType::Flags) {
                                FlagBit fb;
                                fb.bit = std::atoi(keyval.c_str());
                                fb.label = label;
                                if (isPunct(lx.peek(), ':')) {
                                    lx.next();
                                    if (lx.peek().kind == Tok::Ident ||
                                        lx.peek().kind == Tok::Str)
                                        fb.defOn = std::atoi(lx.next().s.c_str()) != 0;
                                }
                                v.flags.push_back(std::move(fb));
                            } else {
                                Choice c;
                                c.value = keyval;
                                c.label = label;
                                // choices may carry an extra ": help" — skip it
                                while (isPunct(lx.peek(), ':')) {
                                    lx.next();
                                    if (lx.peek().kind == Tok::Str ||
                                        lx.peek().kind == Tok::Ident)
                                        lx.next();
                                }
                                v.choices.push_back(std::move(c));
                            }
                        }
                        if (isPunct(lx.peek(), ']')) lx.next();
                    }
                }

                if (low == "spawnflags") v.type = VarType::Flags;
                ec.vars.push_back(std::move(v));
            }
            if (isPunct(lx.peek(), ']')) lx.next();
        }

        if (ec.name.empty()) continue;
        // Later definitions win (tf.fgd overrides base.fgd), like Hammer.
        classes_[ec.name] = std::move(ec);
    }
}

void Fgd::indexClasses() {
    pointClasses_.clear();
    solidClasses_.clear();
    for (const auto& [name, ec] : classes_) {
        if (ec.isPoint()) pointClasses_.push_back(name);
        else if (ec.isSolid()) solidClasses_.push_back(name);
    }
    std::sort(pointClasses_.begin(), pointClasses_.end());
    std::sort(solidClasses_.begin(), solidClasses_.end());
}

bool Fgd::load(const std::string& path) {
    classes_.clear();
    flatCache_.clear();
    const std::string text = readTextFile(path);
    if (text.empty()) {
        PB_WARN("fgd: cannot read %s", path.c_str());
        return false;
    }
    parseText(text, fs::path(path).parent_path().string(), 0);
    indexClasses();
    PB_INFO("fgd: %zu classes from %s (%zu point, %zu solid)", classes_.size(),
            fs::path(path).filename().string().c_str(), pointClasses_.size(),
            solidClasses_.size());
    return true;
}

const EntityClass* Fgd::find(const std::string& name) const {
    auto it = classes_.find(name);
    return it == classes_.end() ? nullptr : &it->second;
}

const EntityClass* Fgd::flattened(const std::string& name) const {
    auto cached = flatCache_.find(name);
    if (cached != flatCache_.end()) return &cached->second;

    const EntityClass* base = find(name);
    if (!base) return nullptr;

    EntityClass out = *base;
    out.vars.clear();
    out.inputs.clear();
    out.outputs.clear();

    auto addVar = [&](const Var& v, bool inherited) {
        for (auto& e : out.vars)
            if (e.key == v.key) {
                Var merged = v;
                merged.inherited = e.inherited && inherited;
                e = merged;
                return;
            }
        out.vars.push_back(v);
        out.vars.back().inherited = inherited;
    };
    auto addIO = [&](std::vector<IO>& dst, const IO& io) {
        for (auto& e : dst)
            if (e.name == io.name) { e = io; return; }
        dst.push_back(io);
    };

    // Depth-first over bases (in declaration order), then this class. Vars from
    // `name` itself are "own"; anything reached through a base is "inherited".
    std::vector<std::string> stack;
    auto expand = [&](const std::string& cn, bool inherited, auto&& self) -> void {
        const EntityClass* c = find(cn);
        if (!c) return;
        if (std::find(stack.begin(), stack.end(), cn) != stack.end()) return;
        stack.push_back(cn);
        for (const auto& b : c->bases) self(b, true, self);
        for (const auto& v : c->vars) addVar(v, inherited);
        for (const auto& io : c->inputs) addIO(out.inputs, io);
        for (const auto& io : c->outputs) addIO(out.outputs, io);
        stack.pop_back();
    };
    expand(name, false, expand);

    // Inherit a model/color/size from a base if this class didn't set one.
    if (out.studioModel.empty() || !out.hasColor || !out.hasSize) {
        for (const auto& b : base->bases) {
            const EntityClass* bc = flattened(b);
            if (!bc) continue;
            if (out.studioModel.empty()) out.studioModel = bc->studioModel;
            if (!out.hasColor && bc->hasColor) { out.hasColor = true; out.color = bc->color; }
            if (!out.hasSize && bc->hasSize) {
                out.hasSize = true; out.sizeMin = bc->sizeMin; out.sizeMax = bc->sizeMax;
            }
        }
    }

    auto [ins, ok] = flatCache_.emplace(name, std::move(out));
    return &ins->second;
}

}  // namespace pb::fgd
