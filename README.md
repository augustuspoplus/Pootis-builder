# Pootis Builder

A from-scratch, native replacement for Team Fortress 2's **Hammer** map editor.
C++ / OpenGL 3.3 core, Dear ImGui docking UI, GLFW window — the same architecture
family as Hammer and TrenchBroom, with no Source SDK dependency.

Open a compiled `.bsp` and it renders like the game loaded it — lightmaps, props,
displacements, materials. Decompile it to editable brushwork, or start a new map
from a template and build it with a friendly one-click kit. Then compile with
`vbsp` / `vvis` / `vrad` and play it in TF2 without opening Valve's tools once.

> Status: well past the original "load + view" milestone. The editor can take a
> map from decompile → edit → compile → playtest today. See `PLAN.md` for the
> five gated phases to a 1.0 anyone could finish a shippable map in, and
> `PROGRESS.md` for the running build log.

## What works

**Loading & rendering**
- Direct **BSP v19–21** loader (`src/bsp/`) — reads the lumps itself, no
  intermediate tools. Faces, edges, texinfo, models, entities, `LUMP_LIGHTING`
  (LDR + HDR, LZMA-compressed lumps), `GAME_LUMP` static props.
- **Lightmapped 3D view** — per-face lightmap samples decoded (RGBE → sRGB) and
  packed into an atlas; the scene reads like the compiled map.
- **VPK / VMT / VTF pipeline** (`src/source/`) — real albedo textures from the
  game's packs and loose folders; DXT1/3/5 + BGRA8888.
- **`prop_static` models** — `model/StudioModel` parses MDL + VVD + VTX (LOD 0);
  props are baked into the world mesh in world space.
- **Displacements** — the `(2^power+1)^2` grid per `dispinfo` face, rendered with
  the flat-face lightmap/UV projection.

**Editing**
- **Hammer-style 4-viewport layout** — 3D + Top/Front/Side, docked with Dear
  ImGui, resizable/rearrangeable. 3D fly-cam, ortho pan + cursor-anchored zoom.
- **Simple mode** — a one-click **Build Kit**: floors/walls/rooms/ramps, shapes
  (stairs, arch, cylinder, dome, wedge, hill, curvy road), and a plain-language
  **Things** list of ~40 gameplay entities (spawn rooms, CTF/KOTH/Arena/Payload
  setups, doors, buttons, elevators, triggers, health/ammo, atmosphere). Every
  card drops real brushwork/entities on the grid; drag-and-drop from any card.
- **Pro mode** — brush drawing + the block tool, vertex/edge/face sub-object
  editing, clip / hollow / carve, groups, visgroups.
- **Transforms** — gizmo, 8-handle 2D bounding box + 6 face handles in 3D, body
  drag, and Blender-style modal `G` / `R` / `S` → axis lock → type an exact
  amount. Grid snap + snap-to-geometry magnet.
- **Entities** — FGD-driven property panel (typed widget per key, flags, I/O
  connections editor), entity helpers drawn in every viewport (class-coloured
  boxes, I/O lines, facing ticks), brush ↔ entity tie/untie.

**Ship it**
- **Decompile** to an editable VMF via bundled BSPSource (clearly approximate —
  compiled BSPs discard original brushwork).
- **Compile + play** — `vbsp` / `vvis` / `vrad` with a live log panel, then
  launch TF2 on the result (`+map`). Fast-compile profile.
- **Map Check** — spawns / lights / skybox / objective / leaked / invalid +
  oversized brushes / dangling I/O; severity-sorted, click to select & frame.
- **Steam Workshop** publish staging (item folder + preview + `publish.vdf`).
- **OBJ import** — as detail brushwork, or staged to a real `.mdl` via
  `studiomdl` on the next build.

**Quality of life**
- Autosave + rolling `.bak`, full undo history panel, command palette (`Ctrl+K`),
  camera bookmarks, prefab library, cordon, `.pbproj` project bundles, Options
  persisted to `pootis.ini`, DPI-aware UI (100–200 %).

## Build

Toolchain ships with Qt (MinGW GCC 13, CMake, Ninja) — no extra installs. Any
recent GCC/Clang + CMake ≥ 3.20 + a GL 3.3 driver also works.

```bash
./build.ps1            # Windows / Qt toolchain helper
# or, directly:
cmake -S . -B build -G Ninja -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++
cmake --build build
```

First configure pulls GLFW, Dear ImGui (docking), GLM, stb and ImGuizmo via
CMake `FetchContent`.

## Run

```bash
build/PootisBuilder.exe "C:/Program Files (x86)/Steam/steamapps/common/Team Fortress 2/tf/maps/ctf_turbine.bsp"
```

With no argument it opens the welcome screen (new map / template / recent).
A TF2 install is auto-detected for materials, models and the compilers; set
`TF2DIR` to override.

Headless captures for the Hammer-comparison loop:

```bash
build/PootisBuilder.exe <map.bsp> --screenshot out.png --view persp|top|front|side|quad
build/PootisBuilder.exe <map.bsp> --screenshot out.png --ui          # full docked UI
```

`test.sh` is a headless regression sweep (stock maps, every kit card, undo,
templates + their `vbsp` compiles).

## Layout

```
src/core/       logging, file IO, paths
src/bsp/        BspFormat / BspFile / BspMesh — lump loader + renderable mesh
src/source/     Vpk / Vmt / Vtf — the material pipeline
src/model/      StudioModel — MDL/VVD/VTX prop geometry
src/render/     Shader, Framebuffer, Camera, SceneRenderer, thumbnails
src/map/        MapDocument, Solid, brush edit ops, History (snapshot undo)
src/fgd/        FGD parser (tf.fgd)
src/compile/    vbsp/vvis/vrad driver, studiomdl pass
src/decompile/  BSPSource runner
src/import/     OBJ loader + import-to-brush / import-to-model
src/publish/    Steam Workshop staging
src/app/        Editor — viewports, panels, tools, Simple/Pro UI
```

## Acknowledgements

Team Fortress 2, the Source engine, Hammer, the BSP/VMF/VMT/VTF formats and the
`tf.fgd` entity definitions are Valve's. This is an independent tool and is not
affiliated with or endorsed by Valve.

Bundled / fetched third-party code: [Dear ImGui](https://github.com/ocornut/imgui)
(MIT), [GLFW](https://www.glfw.org/) (Zlib), [GLM](https://github.com/g-truc/glm)
(MIT), [stb](https://github.com/nothings/stb) (public domain / MIT),
[ImGuizmo](https://github.com/CedricGuillemet/ImGuizmo) (MIT),
[IconFontCppHeaders](https://github.com/juliettef/IconFontCppHeaders) (Zlib).
Fonts: [IBM Plex](https://github.com/IBM/plex) and
[Font Awesome 6 Free](https://fontawesome.com/) (both SIL OFL 1.1).
Decompilation uses [BSPSource](https://github.com/ata4/bspsrc) (run out-of-process).
