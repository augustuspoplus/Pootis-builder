cmake_minimum_required(VERSION 3.24)
project(PootisBuilder VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

include(FetchContent)
set(FETCHCONTENT_QUIET OFF)

# ---------------------------------------------------------------------------
# Dependencies
# ---------------------------------------------------------------------------
set(GLFW_BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(GLFW_INSTALL OFF CACHE BOOL "" FORCE)
FetchContent_Declare(glfw
    GIT_REPOSITORY https://github.com/glfw/glfw.git
    GIT_TAG 3.4
    GIT_SHALLOW ON)

FetchContent_Declare(imgui
    GIT_REPOSITORY https://github.com/ocornut/imgui.git
    GIT_TAG docking
    GIT_SHALLOW ON)

FetchContent_Declare(glm
    GIT_REPOSITORY https://github.com/g-truc/glm.git
    GIT_TAG 1.0.1
    GIT_SHALLOW ON)

FetchContent_Declare(stb
    GIT_REPOSITORY https://github.com/nothings/stb.git
    GIT_TAG master
    GIT_SHALLOW ON)

FetchContent_MakeAvailable(glfw imgui glm stb)

# ---------------------------------------------------------------------------
# glad GL loader — glfw's deps/ folder ships the glad2 loader as a single
# header (glad/gl.h); we compile it via src/gpu/glad_impl.c so there is no
# separate generator / python dependency.
# ---------------------------------------------------------------------------
add_library(glad STATIC src/gpu/glad_impl.c)
target_include_directories(glad PUBLIC ${glfw_SOURCE_DIR}/deps)

# ---------------------------------------------------------------------------
# LZMA decoder (7-Zip SDK, public domain) for Source's compressed BSP lumps.
# ---------------------------------------------------------------------------
add_library(lzma STATIC third_party/lzma/LzmaDec.c)
target_include_directories(lzma PUBLIC third_party/lzma)
target_compile_definitions(lzma PRIVATE _7ZIP_ST)

# ---------------------------------------------------------------------------
# Dear ImGui (core + GLFW/OpenGL3 backends)
# ---------------------------------------------------------------------------
add_library(imgui STATIC
    ${imgui_SOURCE_DIR}/imgui.cpp
    ${imgui_SOURCE_DIR}/imgui_draw.cpp
    ${imgui_SOURCE_DIR}/imgui_tables.cpp
    ${imgui_SOURCE_DIR}/imgui_widgets.cpp
    ${imgui_SOURCE_DIR}/imgui_demo.cpp
    ${imgui_SOURCE_DIR}/backends/imgui_impl_glfw.cpp
    ${imgui_SOURCE_DIR}/backends/imgui_impl_opengl3.cpp)
target_include_directories(imgui PUBLIC
    ${imgui_SOURCE_DIR}
    ${imgui_SOURCE_DIR}/backends)
target_link_libraries(imgui PUBLIC glfw)

# ---------------------------------------------------------------------------
# Pootis Builder
# ---------------------------------------------------------------------------
file(GLOB_RECURSE POOTIS_SOURCES CONFIGURE_DEPENDS src/*.cpp)

add_executable(PootisBuilder ${POOTIS_SOURCES})
target_include_directories(PootisBuilder PRIVATE
    src
    third_party
    ${stb_SOURCE_DIR})
target_link_libraries(PootisBuilder PRIVATE
    glad glfw imgui glm::glm lzma
    opengl32 gdi32 comdlg32)

if(WIN32)
    target_compile_definitions(PootisBuilder PRIVATE
        NOMINMAX WIN32_LEAN_AND_MEAN _USE_MATH_DEFINES)
endif()

# Self-contained exe: fold in the MinGW runtime so it runs without the
# compiler's bin/ on PATH.
if(MINGW)
    target_link_options(PootisBuilder PRIVATE
        -static -static-libgcc -static-libstdc++)
endif()

set_target_properties(PootisBuilder PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR})

# Copy shader/assets next to the exe so it runs from the build dir.
add_custom_command(TARGET PootisBuilder POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_SOURCE_DIR}/shaders $<TARGET_FILE_DIR:PootisBuilder>/shaders
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        ${CMAKE_SOURCE_DIR}/assets $<TARGET_FILE_DIR:PootisBuilder>/assets
    VERBATIM)
