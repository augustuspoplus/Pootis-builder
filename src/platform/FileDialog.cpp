#include "platform/FileDialog.h"

#ifdef _WIN32
#  include <windows.h>
#  include <commdlg.h>
#endif

namespace pb {

#ifdef _WIN32
std::string openFileDialog(const char* title, const char* filter,
                           const char* initialDir) {
    char buffer[MAX_PATH] = {0};

    OPENFILENAMEA ofn = {};
    ofn.lStructSize = sizeof(ofn);
    ofn.hwndOwner = GetActiveWindow();
    ofn.lpstrFilter = filter;  // "Label\0*.bsp\0...\0\0"
    ofn.lpstrFile = buffer;
    ofn.nMaxFile = sizeof(buffer);
    ofn.lpstrTitle = title;
    ofn.lpstrInitialDir = initialDir;
    ofn.Flags = OFN_FILEMUSTEXIST | OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR |
                OFN_EXPLORER;

    if (GetOpenFileNameA(&ofn)) return std::string(buffer);
    return {};
}
#else
std::string openFileDialog(const char*, const char*, const char*) { return {}; }
#endif

}  // namespace pb
