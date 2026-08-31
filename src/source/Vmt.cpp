#include "source/Vmt.h"

#include <algorithm>
#include <cctype>

namespace pb::source {
namespace {

std::string lower(std::string s) {
    for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    return s;
}

// Minimal KeyValues tokenizer: quoted or bare tokens, `{` `}` punctuation,
// `//` line comments.
struct Lexer {
    const std::string& s;
    size_t i = 0;

    void skip() {
        for (;;) {
            while (i < s.size() && std::isspace(static_cast<unsigned char>(s[i]))) ++i;
            if (i + 1 < s.size() && s[i] == '/' && s[i + 1] == '/') {
                while (i < s.size() && s[i] != '\n') ++i;
                continue;
            }
            break;
        }
    }

    bool next(std::string& out) {
        skip();
        if (i >= s.size()) return false;
        if (s[i] == '{' || s[i] == '}') {
            out = std::string(1, s[i++]);
            return true;
        }
        if (s[i] == '"') {
            ++i;
            const size_t start = i;
            while (i < s.size() && s[i] != '"') ++i;
            out = s.substr(start, i - start);
            if (i < s.size()) ++i;
            return true;
        }
        const size_t start = i;
        while (i < s.size() && !std::isspace(static_cast<unsigned char>(s[i])) &&
               s[i] != '{' && s[i] != '}')
            ++i;
        out = s.substr(start, i - start);
        return !out.empty();
    }
};

// Reads the body of a { } block into kv (recursively flattening nested blocks,
// which is enough for patch replace/insert and proxies we ignore).
void readBlock(Lexer& lex, std::map<std::string, std::string>& kv,
               std::string* includeOut) {
    std::string tok;
    while (lex.next(tok)) {
        if (tok == "}") return;
        std::string key = lower(tok);
        std::string val;
        if (!lex.next(val)) return;
        if (val == "{") {
            if (key == "replace" || key == "insert") {
                readBlock(lex, kv, includeOut);
            } else {
                std::map<std::string, std::string> discard;
                readBlock(lex, discard, includeOut);
            }
            continue;
        }
        if (key == "include")
            { if (includeOut) *includeOut = val; }
        else
            kv[key] = val;
    }
}

}  // namespace

Vmt parseVmt(const std::string& text) {
    Vmt out;
    Lexer lex{text};
    std::string tok;
    if (!lex.next(tok)) return out;
    out.shader = lower(tok);
    if (!lex.next(tok) || tok != "{") return out;
    readBlock(lex, out.kv, &out.includePath);
    return out;
}

}  // namespace pb::source
