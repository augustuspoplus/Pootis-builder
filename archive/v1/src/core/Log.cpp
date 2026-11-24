#include "core/Log.h"
#include <cstdio>
#include <deque>
#include <mutex>

namespace pb {

namespace {
std::mutex g_mutex;
std::deque<LogLine> g_ring;
size_t g_seq = 0;
constexpr size_t kRingMax = 2000;
}  // namespace

void logMessage(LogLevel level, const std::string& msg) {
    const char* tag = level == LogLevel::Info ? "INFO "
                    : level == LogLevel::Warn ? "WARN "
                                              : "ERROR";
    std::lock_guard<std::mutex> lock(g_mutex);
    std::fprintf(stderr, "[%s] %s\n", tag, msg.c_str());
    std::fflush(stderr);
    g_ring.push_back({level, msg});
    if (g_ring.size() > kRingMax) g_ring.pop_front();
    ++g_seq;
}

std::vector<LogLine> logTail(size_t max) {
    std::lock_guard<std::mutex> lock(g_mutex);
    std::vector<LogLine> out;
    const size_t n = g_ring.size();
    const size_t start = n > max ? n - max : 0;
    out.reserve(n - start);
    for (size_t i = start; i < n; ++i) out.push_back(g_ring[i]);
    return out;
}

size_t logSeq() {
    std::lock_guard<std::mutex> lock(g_mutex);
    return g_seq;
}

}  // namespace pb
