#pragma once
#include <map>
#include <memory>
#include <string>
#include <vector>

namespace pb::json {

// A minimal JSON value — enough to read a model API's reply and to build a
// request body, without pulling in a parser dependency. Objects keep insertion
// order for stable request bodies.
class Value {
public:
    enum class Type { Null, Bool, Number, String, Array, Object };

    Value() = default;
    static Value boolean(bool b);
    static Value number(double d);
    static Value str(std::string s);
    static Value array();
    static Value object();

    Type type() const { return type_; }
    bool isNull() const { return type_ == Type::Null; }

    bool asBool(bool def = false) const;
    double asNumber(double def = 0.0) const;
    const std::string& asString() const;   // "" when not a string
    size_t size() const;                   // array/object element count

    // Lookups return a shared null when absent, so chains never dereference
    // a dangling value: v["choices"][0]["message"]["content"].asString().
    const Value& operator[](const std::string& key) const;
    const Value& operator[](size_t i) const;
    bool has(const std::string& key) const;

    // Builders.
    void set(const std::string& key, Value v);
    void push(Value v);

    std::string dump() const;
    const std::vector<std::pair<std::string, Value>>& members() const { return obj_; }
    const std::vector<Value>& elements() const { return arr_; }

private:
    Type type_ = Type::Null;
    bool bool_ = false;
    double num_ = 0.0;
    std::string str_;
    std::vector<Value> arr_;
    std::vector<std::pair<std::string, Value>> obj_;
};

// Parses `text`. On failure returns a Null value and sets `err` when given.
Value parse(const std::string& text, std::string* err = nullptr);

// JSON string escaping, for hand-built bodies.
std::string escape(const std::string& s);

}  // namespace pb::json
