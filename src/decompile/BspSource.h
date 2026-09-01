#pragma once
#include <string>

namespace pb::decompile {

// Decompiles a .bsp to a .vmf using the bundled BSPSource. Caches by map name +
// mtime under %LOCALAPPDATA%/PootisBuilder/decompiled. Returns the vmf path, or
// an empty string on failure (message left in `err`).
std::string bspToVmf(const std::string& exeDir, const std::string& bspPath,
                     std::string* err = nullptr, std::string* log = nullptr);

// True when the BSPSource runtime is present next to the app.
bool available(const std::string& exeDir);

}  // namespace pb::decompile
