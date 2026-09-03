#include "net/Json.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>

namespace pb::json {
namespace {

const Value& nullValue() {
    static const Value v;
    return v;
}
const std::string& emptyString() {
    static const std::string s;
    return s;
}

struct Parser {
    const std::string& t;
    size_t i = 0;
    std::string err;

    void ws() {
        while (i < t.size() &&
               (t[i] == ' ' || t[i] == '\t' || t[i] == '\n' || t[i] == '\r'))
            ++i;
    }
    bool lit(const char* s) {
        const size_t n = std::char_traits<char>::length(s);
        if (t.compare(i, n, s) != 0) return false;
        i += n;
        return true;
    }
    void fail(const char* what) {
        if (err.empty()) err = std::string(what) + " at byte " + std::to_string(i);
    }

    static void utf8(std::string& out, unsigned cp) {
        if (cp < 0x80) {
            out += static_cast<char>(cp);
        } else if (cp < 0x800) {
            out += static_cast<char>(0xC0 | (cp >> 6));
            out += static_cast<char>(0x80 | (cp & 0x3F));
        } else if (cp < 0x10000) {
            out += static_cast<char>(0xE0 | (cp >> 12));
            out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            out += static_cast<char>(0x80 | (cp & 0x3F));
        } else {
            out += static_cast<char>(0xF0 | (cp >> 18));
            out += static_cast<char>(0x80 | ((cp >> 12) & 0x3F));
            out += static_cast<char>(0x80 | ((cp >> 6) & 0x3F));
            out += static_cast<char>(0x80 | (cp & 0x3F));
        }
    }

    unsigned hex4() {
        unsigned v = 0;
        for (int k = 0; k < 4 && i < t.size(); ++k, ++i) {
            const char c = t[i];
            v <<= 4;
            if (c >= '0' && c <= '9') v |= static_cast<unsigned>(c - '0');
            else if (c >= 'a' && c <= 'f') v |= static_cast<unsigned>(c - 'a' + 10);
            else if (c >= 'A' && c <= 'F') v |= static_cast<unsigned>(c - 'A' + 10);
            else { fail("bad unicode escape"); return 0; }
        }
        return v;
    }

    bool string(std::string& out) {
        if (i >= t.size() || t[i] != '"') { fail("expected a string"); return false; }
        ++i;
        while (i < t.size()) {
            const char c = t[i++];
            if (c == '"') return true;
            if (c != '\\') { out += c; continue; }
            if (i >= t.size()) break;
            switch (t[i++]) {
                case '"':  out += '"';  break;
                case '\\': out += '\\'; break;
                case '/':  out += '/';  break;
                case 'b':  out += '\b'; break;
                case 'f':  out += '\f'; break;
                case 'n':  out += '\n'; break;
                case 'r':  out += '\r'; break;
                case 't':  out += '\t'; break;
                case 'u': {
                    unsigned cp = hex4();
                    if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < t.size() &&
                        t[i] == '\\' && t[i + 1] == 'u') {
                        i += 2;
                        const unsigned lo = hex4();
                        if (lo >= 0xDC00 && lo <= 0xDFFF)
                            cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                    }
                    utf8(out, cp);
                    break;
                }
                default: fail("bad escape"); return false;
            }
        }
        fail("unterminated string");
        return false;
    }

    Value value(int depth) {
        if (depth > 200) { fail("too deeply nested"); return {}; }
        ws();
        if (i >= t.size()) { fail("unexpected end of input"); return {}; }
        const char c = t[i];
        if (c == 'n') {
            if (lit("null")) return {};
            fail("bad literal");
            return {};
        }
        if (c == 't') {
            if (lit("true")) return Value::boolean(true);
            fail("bad literal");
            return {};
        }
        if (c == 'f') {
            if (lit("false")) return Value::boolean(false);
            fail("bad literal");
            return {};
        }
        if (c == '"') {
            std::string s;
            if (!string(s)) return {};
            return Value::str(std::move(s));
        }
        if (c == '[') {
            ++i;
            Value a = Value::array();
            ws();
            if (i < t.size() && t[i] == ']') { ++i; return a; }
            for (;;) {
                Value e = value(depth + 1);
                if (!err.empty()) return {};
                a.push(std::move(e));
                ws();
                if (i < t.size() && t[i] == ',') { ++i; continue; }
                if (i < t.size() && t[i] == ']') { ++i; return a; }
                fail("expected a comma or a closing bracket");
                return {};
            }
        }
        if (c == '{') {
            ++i;
            Value o = Value::object();
            ws();
            if (i < t.size() && t[i] == '}') { ++i; return o; }
            for (;;) {
                ws();
                std::string k;
                if (!string(k)) return {};
                ws();
                if (i >= t.size() || t[i] != ':') { fail("expected a colon"); return {}; }
                ++i;
                Value v = value(depth + 1);
                if (!err.empty()) return {};
                o.set(k, std::move(v));
                ws();
                if (i < t.size() && t[i] == ',') { ++i; continue; }
                if (i < t.size() && t[i] == '}') { ++i; return o; }
                fail("expected a comma or a closing brace");
                return {};
            }
        }
        const size_t start = i;
        if (i < t.size() && (t[i] == '-' || t[i] == '+')) ++i;
        while (i < t.size() && ((t[i] >= '0' && t[i] <= '9') || t[i] == '.' ||
                                t[i] == 'e' || t[i] == 'E' || t[i] == '-' ||
                                t[i] == '+'))
            ++i;
        if (i == start) { fail("unexpected character"); return {}; }
        return Value::number(
            std::strtod(t.substr(start, i - start).c_str(), nullptr));
    }
};

}  // namespace

Value Value::boolean(bool b) {
    Value v;
    v.type_ = Type::Bool;
    v.bool_ = b;
    return v;
}
Value Value::number(double d) {
    Value v;
    v.type_ = Type::Number;
    v.num_ = d;
    return v;
}
Value Value::str(std::string s) {
    Value v;
    v.type_ = Type::String;
    v.str_ = std::move(s);
    return v;
}
Value Value::array() {
    Value v;
    v.type_ = Type::Array;
    return v;
}
Value Value::object() {
    Value v;
    v.type_ = Type::Object;
    return v;
}

bool Value::asBool(bool def) const { return type_ == Type::Bool ? bool_ : def; }
double Value::asNumber(double def) const { return type_ == Type::Number ? num_ : def; }
const std::string& Value::asString() const {
    return type_ == Type::String ? str_ : emptyString();
}
size_t Value::size() const {
    if (type_ == Type::Array) return arr_.size();
    if (type_ == Type::Object) return obj_.size();
    return 0;
}
const Value& Value::operator[](const std::string& key) const {
    for (const auto& kv : obj_)
        if (kv.first == key) return kv.second;
    return nullValue();
}
const Value& Value::operator[](size_t i) const {
    return i < arr_.size() ? arr_[i] : nullValue();
}
bool Value::has(const std::string& key) const {
    for (const auto& kv : obj_)
        if (kv.first == key) return true;
    return false;
}
void Value::set(const std::string& key, Value v) {
    type_ = Type::Object;
    for (auto& kv : obj_)
        if (kv.first == key) { kv.second = std::move(v); return; }
    obj_.emplace_back(key, std::move(v));
}
void Value::push(Value v) {
    type_ = Type::Array;
    arr_.push_back(std::move(v));
}

std::string escape(const std::string& s) {
    std::string o;
    o.reserve(s.size() + 8);
    for (unsigned char c : s) {
        switch (c) {
            case '"':  o += "\\\""; break;
            case '\\': o += "\\\\"; break;
            case '\b': o += "\\b";  break;
            case '\f': o += "\\f";  break;
            case '\n': o += "\\n";  break;
            case '\r': o += "\\r";  break;
            case '\t': o += "\\t";  break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                    o += buf;
                } else {
                    o += static_cast<char>(c);
                }
        }
    }
    return o;
}

std::string Value::dump() const {
    switch (type_) {
        case Type::Null:
            return "null";
        case Type::Bool:
            return bool_ ? "true" : "false";
        case Type::Number: {
            if (num_ == std::floor(num_) && std::fabs(num_) < 1e15)
                return std::to_string(static_cast<long long>(num_));
            char buf[40];
            std::snprintf(buf, sizeof(buf), "%.10g", num_);
            return buf;
        }
        case Type::String:
            return "\"" + escape(str_) + "\"";
        case Type::Array: {
            std::string o = "[";
            for (size_t i = 0; i < arr_.size(); ++i) {
                if (i) o += ',';
                o += arr_[i].dump();
            }
            return o + "]";
        }
        case Type::Object: {
            std::string o = "{";
            bool first = true;
            for (const auto& kv : obj_) {
                if (!first) o += ',';
                first = false;
                o += "\"" + escape(kv.first) + "\":" + kv.second.dump();
            }
            return o + "}";
        }
    }
    return "null";
}

Value parse(const std::string& text, std::string* err) {
    Parser p{text};
    Value v = p.value(0);
    if (!p.err.empty()) {
        if (err) *err = p.err;
        return {};
    }
    p.ws();
    if (p.i != text.size()) {
        if (err) *err = "trailing data at byte " + std::to_string(p.i);
        return {};
    }
    return v;
}

}  // namespace pb::json
