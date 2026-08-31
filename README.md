# Pootis Builder

A from-scratch, native modern replacement for TF2's Hammer editor.
Native C++ / OpenGL 3.3 core, Dear ImGui docking UI, GLFW window — the same
architecture family as Hammer and TrenchBroom.

This is a separate program from the earlier `Pootis Builder Qt` and
`Pootis Builder Web` prototypes (kept only for reference).

## Status — milestone 1: BSP load + faithful view

Working:

- **Direct BSP v19–21 loader** (`src/bsp/`) — reads the lumps itself, no
  intermediate tools. Faces, edges, texinfo, texdata/material names, models,
  entities, `LUMP_LIGHTING`, and static props (`GAME_LUMP` `sprp`).
- **Lightmapped 3D render** — per-face lightmap samples decoded (RGBE → sRGB)
  and packed into an atlas; the 3D view reads like the compiled map.
- **Hammer-style 4-viewport layout** — 3D + Top/Front/Side orthographic
  wireframe views, docked with Dear ImGui; resizable/rearrangeable.
- **Panels** — Map Contents (world stats, static-prop list, entity list),
  Materials (every material in view), Entities (class histogram).
- **Camera** — 3D fly-cam (hold RMB + WASD/QE, wheel dolly); ortho pan
  (MMB or Space+LMB) and cursor-anchored zoom. `F` frames the map.
- **Headless screenshots** for automated comparison against Hammer.

Not yet (next milestones): VPK/VMT/VTF albedo textures, prop MDL meshes,
displacements, BSPSource decompile-to-editable-brushes, brush/entity editing,
FGD catalog, vbsp/vvis/vrad build + in-game preview. Parity checklist mirrors
`../Pootis Builder Qt/docs/HAMMER_FEATURE_MATRIX.md`.

"Perfect" BSP→brush decompilation is not physically possible (compiled BSPs
discard original brushwork; BSPSource recovered ~31% of turbine's brush faces
exactly). This tool instead renders the compiled BSP faithfully — which is what
matches "how Hammer loads a map" visually — and will add decompile as a
separate, clearly-approximate editable import.

## Build

Toolchain ships with Qt (no extra installs): MinGW GCC 13, CMake, Ninja.

```bash
./build.ps1            # or:
cmake -S . -B build -G Ninja -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++
cmake --build build
```

First configure clones GLFW, Dear ImGui (docking), GLM and stb via
`FetchContent`.

## Run

```bash
build/PootisBuilder.exe "C:/Program Files (x86)/Steam/steamapps/common/Team Fortress 2/tf/maps/ctf_turbine.bsp"
```

Primary test map: **ctf_turbine**.

### Headless captures (Hammer comparison)

```bash
build/PootisBuilder.exe <map.bsp> --screenshot out.png --view persp|top|front|side|quad
build/PootisBuilder.exe <map.bsp> --screenshot out.png --ui        # full docked UI
```

## Layout

```
src/core/     logging, file IO
src/gpu/      GL loader shim (glad2 from glfw/deps)
src/bsp/      BspFormat / BspFile / BspMesh  — the loader + renderable-mesh builder
src/render/   Shader, Framebuffer, Camera, SceneRenderer
src/app/      Editor — viewports, panels, input
```
