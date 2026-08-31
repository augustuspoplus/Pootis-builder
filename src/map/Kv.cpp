#include "map/Kv.h"

#include <cctype>
#include <sstream>

namespace pb::map {
namespace {

struct Lexer {
    const std::string& s;
    size_t i = 0;

    void skipWs() {
        for (;;) {
            while (i < s.size() && std::isspace(static_cast<unsigned char>(s[i]))) ++i;
            if (i + 1 < s.size() && s[i] == '/' && s[i + 1] == '/') {
                while (i < s.size() && s[i] != '\n') ++i;
                continue;
            }
            break;
        }
    }

    // Returns a token: a quoted string (without quotes), or "{" / "}", or a bare
    // word, or "" at EOF.
    std::string next() {
        skipWs();
        if (i >= s.size()) return {};
        const char c = s[i];
        if (c == '{' || c == '}') {
            ++i;
            return std::string(1, c);
        }
        if (c == '"') {
            ++i;
            const size_t start = i;
            while (i < s.size() && s[i] != '"') ++i;
            std::string out = s.substr(start, i - start);
            if (i < s.size()) ++i;
            return out;
        }
        const size_t start = i;
        while (i < s.size() && !std::isspace(static_cast<unsigned char>(s[i])) &&
               s[i] != '{' && s[i] != '}' && s[i] != '"')
            ++i;
        return s.substr(start, i - start);
    }

    std::string peek() {
        const size_t save = i;
        std::string t = next();
        i = save;
        return t;
    }
};

void parseBlock(Lexer& lex, KvNode& node) {
    for (;;) {
        std::string tok = lex.next();
        if (tok.empty() || tok == "}") return;
        // tok is a key or a block name. Look at what follows.
        std::string nxt = lex.next();
        if (nxt == "{") {
            KvNode child;
            child.name = tok;
            parseBlock(lex, child);
            node.children.push_back(std::move(child));
        } else if (nxt == "}") {
            return;  // malformed; bail
        } else if (nxt.empty()) {
            return;
        } else {
            node.pairs.emplace_back(std::move(tok), std::move(nxt));
        }
    }
}

void writeNode(std::ostringstream& o, const KvNode& n, int indent) {
    const std::string pad(indent, '\t');
    o << pad << n.name << "\n" << pad << "{\n";
    const std::string pad2(indent + 1, '\t');
    for (const auto& p : n.pairs)
        o << pad2 << '"' << p.first << "\" \"" << p.second << "\"\n";
    for (const auto& c : n.children) writeNode(o, c, indent + 1);
    o << pad << "}\n";
}

}  // namespace

KvNode parseKv(const std::string& text) {
    KvNode root;
    root.name = "#root";
    Lexer lex{text};
    for (;;) {
        std::string tok = lex.next();
        if (tok.empty()) break;
        std::string nxt = lex.next();
        if (nxt == "{") {
            KvNode child;
            child.name = tok;
            parseBlock(lex, child);
            root.children.push_back(std::move(child));
        } else if (!nxt.empty() && nxt != "}") {
            root.pairs.emplace_back(std::move(tok), std::move(nxt));
        }
    }
    return root;
}

std::string writeKv(const KvNode& root) {
    std::ostringstream o;
    for (const auto& p : root.pairs)
        o << '"' << p.first << "\" \"" << p.second << "\"\n";
    for (const auto& c : root.children) writeNode(o, c, 0);
    return o.str();
}

}  // namespace pb::map
