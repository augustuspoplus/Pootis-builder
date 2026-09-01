#pragma once
#include <string>

namespace pb {

// Native "open file" dialog. Returns an empty string if cancelled or
// unsupported on this platform.
std::string openFileDialog(const char* title, const char* filter,
                           const char* initialDir = nullptr);

// Native "save file" dialog. `defaultExt` (e.g. "vmf") is appended when the
// user types a name without an extension. Returns "" if cancelled.
std::string saveFileDialog(const char* title, const char* filter,
                           const char* defaultName = nullptr,
                           const char* defaultExt = nullptr,
                           const char* initialDir = nullptr);

}  // namespace pb
