cmake_minimum_required(VERSION 3.20)
project(pootis_core LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Godot 4 C++ GDExtension bindings (compiled as static lib with C ABI interface)
add_subdirectory(third_party/godot-cpp)

# Reuse existing battle-tested pure C++20 Source/TF2 modules from ../src (zero GUI/GL deps!)
set(PB_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")

add_library(pb_lzma STATIC
    "${PB_ROOT}/third_party/lzma/LzmaDec.c"
)
target_include_directories(pb_lzma PUBLIC "${PB_ROOT}/third_party/lzma")

set(PB_BACKEND_SOURCES
    "${PB_ROOT}/src/core/File.cpp"
    "${PB_ROOT}/src/core/Log.cpp"
    "${PB_ROOT}/src/platform/Process.cpp"
    "${PB_ROOT}/src/source/SourceFs.cpp"
    "${PB_ROOT}/src/source/Vmt.cpp"
    "${PB_ROOT}/src/source/Vpk.cpp"
    "${PB_ROOT}/src/source/Vtf.cpp"
    "${PB_ROOT}/src/bsp/BspFile.cpp"
    "${PB_ROOT}/src/bsp/BspMesh.cpp"
    "${PB_ROOT}/src/bsp/Lzma.cpp"
    "${PB_ROOT}/src/model/StudioModel.cpp"
    "${PB_ROOT}/src/map/BrushEdit.cpp"
    "${PB_ROOT}/src/map/History.cpp"
    "${PB_ROOT}/src/map/Kv.cpp"
    "${PB_ROOT}/src/map/MapDocument.cpp"
    "${PB_ROOT}/src/map/Raycast.cpp"
    "${PB_ROOT}/src/map/Solid.cpp"
    "${PB_ROOT}/src/fgd/Fgd.cpp"
    "${PB_ROOT}/src/compile/MapCompiler.cpp"
    "${PB_ROOT}/src/decompile/BspSource.cpp"
    "${PB_ROOT}/src/publish/AssetScan.cpp"
    "${PB_ROOT}/src/publish/Workshop.cpp"
)

set(GDEXT_SOURCES
    src/gdext/register_types.cpp
    src/gdext/Tf2Core.cpp
    src/gdext/Tf2MapDoc.cpp
    src/gdext/Tf2Compiler.cpp
)

add_library(pootis_core SHARED ${PB_BACKEND_SOURCES} ${GDEXT_SOURCES})

target_include_directories(pootis_core PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${PB_ROOT}/src"
    "${PB_ROOT}/third_party"
    "${PB_ROOT}/third_party/lzma"
    "${CMAKE_CURRENT_SOURCE_DIR}/third_party/glm"
)

target_compile_definitions(pootis_core PRIVATE
    NOMINMAX
    WIN32_LEAN_AND_MEAN
    _USE_MATH_DEFINES
)

target_link_libraries(pootis_core PRIVATE
    godot::cpp
    pb_lzma
)

if(MINGW)
    # Statically bundle MinGW C++/GCC/winpthread runtimes so Godot loads libpootis_core.dll
    # cleanly with ZERO external MinGW DLL dependencies!
    target_link_options(pootis_core PRIVATE
        -static
        -static-libgcc
        -static-libstdc++
    )
    target_link_libraries(pootis_core PRIVATE
        -Wl,-Bstatic -lstdc++ -lgcc -lwinpthread -Wl,-Bdynamic
    )
endif()

set_target_properties(pootis_core PROPERTIES
    PREFIX "lib"
    OUTPUT_NAME "pootis_core"
    RUNTIME_OUTPUT_DIRECTORY "${PB_ROOT}/godot/bin"
    LIBRARY_OUTPUT_DIRECTORY "${PB_ROOT}/godot/bin"
)

# Automatically create/refresh the Desktop shortcut every time pootis_core builds!
add_custom_command(TARGET pootis_core POST_BUILD
    COMMAND powershell -NoProfile -ExecutionPolicy Bypass -File "${PB_ROOT}/update_desktop_shortcut.ps1"
    COMMENT "Updating Pootis Builder 2.0 Desktop shortcut..."
)
