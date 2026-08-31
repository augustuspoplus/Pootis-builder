#pragma once
#include <cstdio>
#include <string>

namespace pb {

enum class LogLevel { Info, Warn, Error };

void logMessage(LogLevel level, const std::string& msg);

template <class... Args>
std::string fmt(const char* f, Args... args) {
    int n = std::snprintf(nullptr, 0, f, args...);
    std::string s(n < 0 ? 0 : n, '\0');
    if (n > 0) std::snprintf(s.data(), n + 1, f, args...);
    return s;
}

#define PB_INFO(...)  ::pb::logMessage(::pb::LogLevel::Info,  ::pb::fmt(__VA_ARGS__))
#define PB_WARN(...)  ::pb::logMessage(::pb::LogLevel::Warn,  ::pb::fmt(__VA_ARGS__))
#define PB_ERROR(...) ::pb::logMessage(::pb::LogLevel::Error, ::pb::fmt(__VA_ARGS__))

}  // namespace pb
