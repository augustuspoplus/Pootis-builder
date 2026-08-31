#include "core/Log.h"
#include <cstdio>
#include <mutex>
#include <vector>

namespace pb {

namespace {
std::mutex g_mutex;
}

void logMessage(LogLevel level, const std::string& msg) {
    const char* tag = level == LogLevel::Info ? "INFO "
                    : level == LogLevel::Warn ? "WARN "
                                              : "ERROR";
    std::lock_guard<std::mutex> lock(g_mutex);
    std::fprintf(stderr, "[%s] %s\n", tag, msg.c_str());
    std::fflush(stderr);
}

}  // namespace pb
