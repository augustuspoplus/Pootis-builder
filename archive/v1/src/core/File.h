#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace pb {

// Reads an entire file into memory. Returns false on failure.
bool readFile(const std::string& path, std::vector<uint8_t>& out);

// Reads a text file. Returns empty string on failure.
std::string readTextFile(const std::string& path);

// Directory of the running executable (no trailing slash).
std::string executableDir();

bool fileExists(const std::string& path);

}  // namespace pb
