#include "platform/Process.h"

#ifdef _WIN32
#  include <windows.h>
#endif

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
}  // namespace

int runProcess(const std::string& exe, const std::vector<std::string>& args,
               std::string* output) {
    std::string cmd = quoteArg(exe);
    for (const auto& a : args) cmd += ' ' + quoteArg(a);

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

#else
int runProcess(const std::string&, const std::vector<std::string>&, std::string*) {
    return -1;
}
#endif

}  // namespace pb
