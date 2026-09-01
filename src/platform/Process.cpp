#include "platform/Process.h"

#ifdef _WIN32
#  include <windows.h>
#endif

#include <chrono>
#include <thread>

#include "core/Log.h"

namespace pb {

#ifdef _WIN32

namespace {
std::string quoteArg(const std::string& a) {
    if (!a.empty() && a.find_first_of(" \t\"") == std::string::npos) return a;
    std::string out = "\"";
    for (size_t i = 0; i < a.size(); ++i) {
        size_t bs = 0;
        while (i < a.size() && a[i] == '\\') {
            ++bs;
            ++i;
        }
        if (i == a.size()) {
            out.append(bs * 2, '\\');
            break;
        }
        if (a[i] == '"') {
            out.append(bs * 2 + 1, '\\');
            out.push_back('"');
        } else {
            out.append(bs, '\\');
            out.push_back(a[i]);
        }
    }
    out.push_back('"');
    return out;
}

std::string buildCmd(const std::string& exe, const std::vector<std::string>& args) {
    std::string cmd = quoteArg(exe);
    for (const auto& a : args) cmd += ' ' + quoteArg(a);
    return cmd;
}
}  // namespace

int runProcess(const std::string& exe, const std::vector<std::string>& args,
               std::string* output) {
    std::string cmd = buildCmd(exe, args);

    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;

    HANDLE rd = nullptr, wr = nullptr;
    if (!CreatePipe(&rd, &wr, &sa, 0)) return -1;
    SetHandleInformation(rd, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOA si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdOutput = wr;
    si.hStdError = wr;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);

    PROCESS_INFORMATION pi{};
    std::vector<char> mutableCmd(cmd.begin(), cmd.end());
    mutableCmd.push_back('\0');

    const BOOL ok = CreateProcessA(nullptr, mutableCmd.data(), nullptr, nullptr, TRUE,
                                   CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi);
    CloseHandle(wr);
    if (!ok) {
        CloseHandle(rd);
        PB_WARN("runProcess: could not start %s (err %lu)", exe.c_str(),
                GetLastError());
        return -1;
    }

    char buf[4096];
    DWORD n = 0;
    while (ReadFile(rd, buf, sizeof(buf), &n, nullptr) && n > 0)
        if (output) output->append(buf, n);
    CloseHandle(rd);

    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    return static_cast<int>(code);
}

int runProcessStreaming(const std::string& exe,
                        const std::vector<std::string>& args,
                        const std::function<void(const std::string&)>& onLine,
                        const std::atomic<bool>* cancel) {
    std::string cmd = buildCmd(exe, args);

    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;

    HANDLE rd = nullptr, wr = nullptr;
    if (!CreatePipe(&rd, &wr, &sa, 0)) return -1;
    SetHandleInformation(rd, HANDLE_FLAG_INHERIT, 0);

    STARTUPINFOA si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdOutput = wr;
    si.hStdError = wr;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);

    PROCESS_INFORMATION pi{};
    std::vector<char> mutableCmd(cmd.begin(), cmd.end());
    mutableCmd.push_back('\0');

    const BOOL ok = CreateProcessA(nullptr, mutableCmd.data(), nullptr, nullptr, TRUE,
                                   CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi);
    CloseHandle(wr);
    if (!ok) {
        CloseHandle(rd);
        PB_WARN("runProcessStreaming: could not start %s (err %lu)", exe.c_str(),
                GetLastError());
        return -1;
    }

    std::string pending;
    auto flushLines = [&](bool final) {
        size_t nl;
        while ((nl = pending.find('\n')) != std::string::npos) {
            std::string line = pending.substr(0, nl);
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (onLine) onLine(line);
            pending.erase(0, nl + 1);
        }
        if (final && !pending.empty()) {
            if (onLine) onLine(pending);
            pending.clear();
        }
    };

    bool cancelled = false;
    char buf[4096];
    for (;;) {
        if (cancel && cancel->load()) {
            TerminateProcess(pi.hProcess, 1223);
            cancelled = true;
            break;
        }
        DWORD avail = 0;
        if (!PeekNamedPipe(rd, nullptr, 0, nullptr, &avail, nullptr)) break;  // pipe closed
        if (avail == 0) {
            if (WaitForSingleObject(pi.hProcess, 0) == WAIT_OBJECT_0) {
                // Drain whatever is left after the process exited.
                DWORD n = 0;
                while (PeekNamedPipe(rd, nullptr, 0, nullptr, &avail, nullptr) &&
                       avail > 0 && ReadFile(rd, buf, sizeof(buf), &n, nullptr) && n > 0)
                    pending.append(buf, n), flushLines(false);
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
            continue;
        }
        DWORD n = 0;
        if (!ReadFile(rd, buf, sizeof(buf), &n, nullptr) || n == 0) break;
        pending.append(buf, n);
        flushLines(false);
    }
    flushLines(true);
    CloseHandle(rd);

    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 0;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    return cancelled ? 1223 : static_cast<int>(code);
}

bool launchDetached(const std::string& exe, const std::vector<std::string>& args,
                    const std::string& workingDir) {
    std::string cmd = buildCmd(exe, args);
    STARTUPINFOA si{};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi{};
    std::vector<char> mutableCmd(cmd.begin(), cmd.end());
    mutableCmd.push_back('\0');
    const BOOL ok = CreateProcessA(
        nullptr, mutableCmd.data(), nullptr, nullptr, FALSE, 0, nullptr,
        workingDir.empty() ? nullptr : workingDir.c_str(), &si, &pi);
    if (!ok) {
        PB_WARN("launchDetached: could not start %s (err %lu)", exe.c_str(),
                GetLastError());
        return false;
    }
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    return true;
}

#else
int runProcess(const std::string&, const std::vector<std::string>&, std::string*) {
    return -1;
}
int runProcessStreaming(const std::string&, const std::vector<std::string>&,
                        const std::function<void(const std::string&)>&,
                        const std::atomic<bool>*) {
    return -1;
}
bool launchDetached(const std::string&, const std::vector<std::string>&,
                    const std::string&) {
    return false;
}
#endif

}  // namespace pb
