#pragma once
#include <string>
#include <vector>

namespace pb {

// Runs a program with argv-style arguments, no console window, waits for exit.
// Captures merged stdout+stderr into `output`. Returns the process exit code,
// or -1 if the process could not be started.
int runProcess(const std::string& exe, const std::vector<std::string>& args,
               std::string* output = nullptr);

}  // namespace pb
