#pragma once
#include <string>

namespace pb {

// Native "open file" dialog. Returns an empty string if cancelled or
// unsupported on this platform.
std::string openFileDialog(const char* title, const char* filter,
                           const char* initialDir = nullptr);

}  // namespace pb
