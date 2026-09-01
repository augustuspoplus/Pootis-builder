#pragma once
#include <atomic>
#include <functional>
#include <string>
#include <vector>

namespace pb {

// Runs a program with argv-style arguments, no console window, waits for exit.
// Captures merged stdout+stderr into `output`. Returns the process exit code,
// or -1 if the process could not be started.
int runProcess(const std::string& exe, const std::vector<std::string>& args,
               std::string* output = nullptr);

// Same, but streams merged stdout+stderr one line at a time to `onLine` as the
// process runs. If `cancel` becomes true the child is terminated and the exit
// code is reported as 1223 (ERROR_CANCELLED). Returns the exit code, or -1 if
// the process could not be started.
int runProcessStreaming(const std::string& exe,
                        const std::vector<std::string>& args,
                        const std::function<void(const std::string&)>& onLine,
                        const std::atomic<bool>* cancel = nullptr);

// Launches a program detached (no wait, no pipe). Returns true if it started.
bool launchDetached(const std::string& exe, const std::vector<std::string>& args,
                    const std::string& workingDir = {});

}  // namespace pb
