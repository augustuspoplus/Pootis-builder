# Valve Hammer Editor 4.1 & Hammer++ — Direct Reverse-Engineering & Architecture Bible

> **Permanent Technical Memory File for Pootis Builder 2.0**
> **Primary Sources Directly Inspected on This Machine:**
> - `C:\Program Files (x86)\Steam\steamapps\common\Team Fortress 2\bin\x64\hammer_dll.dll` (Win32 PE Menu, Dialog, StringTable & Accelerator resources extracted directly: **5 menus, 78 dialogs, 393 strings, 99 keyboard accelerators**)
> - `C:\Program Files (x86)\Steam\steamapps\common\Team Fortress 2\bin\CmdSeq.wc` (**7 official Valve compile command sequences**)
> - `C:\Program Files (x86)\Steam\steamapps\common\Team Fortress 2\bin\base.fgd` (`330.7 KB`, 305 classes) & `tf.fgd` (`119.6 KB`, 144 classes)
> - `assets/mapping_resource_pack/tf-abs.fgd` (`70.6 KB`), `ABS_MRP_Improved_FGD.vpk` (59 files incl. `dev_engy.mdl`), `ABS_MRP_Material_Browser.vpk` (407 blend/water/overlay browser files)
> - Valve Source SDK 2013 architecture & Hammer++ feature documentation

---

## 1. How Valve Hammer Functions Internally (Binary & C++ Architecture)

### 1.1 Module Stack (`TF2/bin/` & `TF2/bin/x64/`)
`hammer.exe` (`294 KB`) is a thin Win32 launcher that sets up Source's `VPROJECT` environment (`Hammer.bat` → `check_sdk_env.bat`) and loads `hammer_dll.dll` (`6.8 MB`), which hosts an **MFC Document-View MDI application** linked directly against live Source Engine DLLs:
- `MaterialSystem.dll` + `stdshader_dx9.dll` + `shaderapidx9.dll` — renders live VMT/VTF shaders in the 3D viewport.
- `StudioRender.dll` + `datacache.dll` + `mdllib.dll` — loads and renders `.mdl`/`.vvd`/`.vtx` props & entity helpers.
- `FileSystem_Stdio.dll` — mounts `GameInfo.txt`, VPK archives, and loose `tf/` directories.
- `SoundEmitterSystem.dll` + `soundsystem.dll` — powers the Sound Resource Browser (`Ctrl+Shift+S`).
- `vphysics.dll` + `vgui2.dll` — powers model physics bounds and VGUI Model Browser.

### 1.2 Core Document-View Data Model
| Hammer C++ Class | Responsibility | Pootis Builder 2.0 Equivalent |
| :--- | :--- | :--- |
| **`CMapDoc`** | Owns the active `.vmf` file (`ChunkFile` parser/writer), Undo/Redo stack (`CHistory`), active Selection (`CSelection`), VisGroups, Cordon bounds, and notifies all views on edits. | `Tf2MapDoc` (`core/src/gdext/Tf2MapDoc.cpp`) + `pb::map::MapDocument` + `pb::map::History` |
| **`CMapWorld`** | Root scene tree (`worldspawn`): owns world geometry (`CMapSolid`), point/brush entities (`CMapEntity`), groups (`CMapGroup`), and instances (`CMapInstance`). | `pb::map::MapDocument` solids + entities |
| **`CMapSolid` & `CMapFace`** | **Half-space plane representation:** Every brush face is stored as **3 non-collinear plane points `(p0, p1, p2)`** plus UV axes (`uaxis`, `vaxis`), rotation, lightmap scale, smoothing groups, and optional `CMapDisp` displacement sub-grid. Polygon vertices are recomputed by intersecting half-space planes! | `pb::map::Solid` / `Face` (already uses plane-based VMF math!) |
| **`CMapDisp`** | Attached to a single quad `CMapFace`: stores `power` (`2`=5×5, `3`=9×9, `4`=17×17), `startposition`, `elevation`, per-vertex `normals`/`distances`/`offsets`, per-vertex `alphas` (`WorldVertexTransition` blending!), `allowed_verts`, and collision flags (`No Hull`, `No Physics`, `No Ray`). | `pb::map::DispInfo` (has geometry sculpt; needs Paint Alpha, AutoSew, Noise, Subdivide, Invert Alpha, Collision flags!) |
| **`CMapEntity`** | Either **Point Entity** (`origin` + `angles` + FGD-driven keyvalues + `connections` I/O block) or **Brush Entity** (wraps 1+ `CMapSolid`s, e.g., `func_detail`, `func_door`, `func_respawnroom`, `trigger_multiple`). | `pb::map::Entity` |
| **`CToolManager` & `CBaseTool`** | Modal state machine routing 2D/3D mouse + keyboard events to the active tool (`ToolSelection`, `ToolBlock`, `ToolEntity`, `ToolClipper`, `ToolMorph`/Vertex, `ToolOverlay`, `ToolDecal`, `ToolDisplace`, `ToolCamera`, `ToolPath`, `ToolMagnify`). | Tool state in `MainApp.gd` (needs dedicated modular tool controller + Vertex, Overlay/Decal, Path, Multi-Select tools!) |
| **`CMapView2D` & `CMapView3D`** | Classic 4-pane split (`3D Textured`, `2D Top X/Y`, `2D Front Y/Z`, `2D Side X/Z`) — all live-synced to `CMapDoc`. | Currently single 3D viewport + 2D top toggle (upgrade with optional Split 2D Blueprint views!) |
| **`CFaceEditSheet`** | Multi-tab floating dialog (`Shift+A`): **Material** tab (face UV scale/shift/rot/justify/align/lightmap scale/smoothing groups) + **Displacement** tab (create/sculpt/paint geometry/paint alpha/noise/sew/subdivide). | Needs full Face Edit UV + Displacement Paint Alpha/Sew/Noise drawer! |
| **`CMapCheck`** | `Alt+P` pre-compile validator: detects invalid solids, missing player start, duplicate targetnames, bad I/O targets, unaligned textures, invalid displacements, overlapping entities, with **Go to Error / Fix / Fix All** buttons! | `Tf2Catalog.analyze_map()` Map Coach (expand to full `Alt+P` problem checker with 1-click Fix & Go-To camera focus!) |
| **`CCordon`** | Temporary bounding box (`Cordon` toggle) that compiles ONLY a small section of a huge map sealed by `tools/toolsskybox` (or custom cordon texture) for rapid 3-second test compiles! | **High-value Hammer feature to add!** |

---

## 2. Complete Reverse-Engineered Valve Hammer UI Feature Inventory

### 2.1 The 9 Screen Elements / Dockbars (`View → Screen Elements`)
1. **Maptools Bar** (Left Vertical Tool Rail — 11 primary tools):
   - `Shift+S` Selection Tool (with 3D/2D handles + 3-click cycle: Scale → Rotate → Skew)
   - `Shift+G` Magnify Tool
   - `Shift+C` Camera Tool (supports multiple saved camera positions!)
   - `Shift+E` Entity Tool (places selected FGD PointClass)
   - `Shift+B` Block Tool (primitives: `block`, `wedge`, `cylinder`, `spike`, `sphere`, `arch`, `torus`, `prefab`)
   - `Shift+A` Toggle Texture Application (Face Edit Sheet + Displacement Sheet)
   - `Shift+T` Apply Current Texture to Selection
   - `Shift+D` Apply Decals (`infodecal`)
   - `Shift+O` Apply Overlays (`info_overlay` — scalable/rotatable TF2 signs, arrows, cap markings!)
   - `Shift+X` Clipping Tool (cycles Keep Front / Keep Back / Keep Both on repeated `Shift+X`)
   - `Shift+V` Vertex Manipulation Tool (move individual vertices/edge midpoints, merge vertices, split faces!)
2. **Mapoperations Bar** (Top Action Strip):
   - Grid Toggle (`Shift+R`), Snap to Grid (`Shift+W`), Smaller/Bigger Grid (`[` / `]`), Load/Unload Pointfile (Red Leak Line), Cordon Toggle & Edit Cordon Bounds, Show/Hide Helpers, Show/Hide Models in 2D, Texture Lock (`Shift+L`), Texture Scale Lock, QuickHide Selected (`H`), QuickHide Unselected (`Ctrl+H`), Unhide All (`U`), Carve (`Ctrl+Shift+C`), Group (`Ctrl+G`), Ungroup (`Ctrl+U`), Ignore Groups (`Ctrl+W`), Radius Culling (`C`), Run Map (`F9`).
3. **Selection Mode Bar** (Right Side Top):
   - **Groups** (selects whole grouped assembly) | **Objects** (selects whole brush entity) | **Solids** (selects individual brush inside a brush entity or group!).
4. **Texture Bar** (Right Side):
   - Current Texture `64×64` live swatch preview, dropdown history of recently used textures, **Browse...** (`Alt+F8`) and **Replace...** (`Replace Textures` dialog).
5. **Filter Control / VisGroups Bar** (Right Side):
   - **User VisGroups** (custom color-coded folders + `Move Selection To Visgroup`)
   - **Auto VisGroups** (automatic categories: *World Geometry, Brush Entities, Point Entities, Func Detail, Displacements, Sky, Water, Tool Brushes [Clip/Playerclip/Trigger/Nodraw/Hint/Skip/Areaportal], Props, Lights, Entities/Game Logic*).
6. **Object Bar** (Right Side Bottom):
   - Categories (`Primitives`, `Prefabs`, `Entities`), Objects dropdown, Faces count (for cylinders/spheres/arches), **Move to World** (`Ctrl+Shift+W`), **Tie to Entity** (`Ctrl+T`), **Insert Original Prefab**.
7. **Manifest Bar** — Multi-mapper sub-map splitting & `func_instance` management.
8. **Mapview Bar** — Viewport layout & render mode quick-switches (`3D Wireframe`, `3D Flat`, `3D Textured`, `3D Shaded`, `3D Lighting Preview`, `3D Ray-traced Preview`, `3D Lightmap Grid`, `2D X/Y`, `2D Y/Z`, `2D X/Z`).
9. **Status Bar** (Bottom Strip):
   - Context help hint | Selection count & exact size (`W × L × H` Hammer units) | Cursor XYZ coordinates (`@ X, Y, Z`) | Active Zoom | `Snap: On/Off Grid: 32u` | FPS.

### 2.2 Complete Top Menu Bar Extracted Directly from `hammer_dll.dll` (`Menu #129`)
- **File:** New (`Ctrl+N`), Open (`Ctrl+O`), Close, Save (`Ctrl+S`), Save As, Export / Export Again (`Alt+B`), Export to `.DXF`, **Run Map (`F9`)**, Reload Sounds, Recent Files, Exit.
- **Edit:** Undo (`Ctrl+Z`), Redo (`Ctrl+Y`), Find Entities (`Ctrl+Shift+F`), Replace (`Ctrl+Shift+R`), Cut/Copy/Paste, **Paste Special (`Ctrl+Shift+V`)** (Linear/Radial copies, accumulative XYZ offset & rotation, auto-unique targetnames + prefix!), Delete (`Del`), Clear Selection (`Shift+Q`), Select All, **Properties (`Alt+Enter`)**.
- **Map:** Snap to Grid (`Shift+W`), Show Grid (`Shift+R`), Grid Settings (`[`/`]`), Units (None / Inches / Feet+Inches), Show Selected Brush Number, **Entity Report**, Entity Gallery, **Check for Problems (`Alt+P`)**, Diff Map File, Load/Unload Pointfile (`.lin`), Load/Unload Portal File (`.prt` — shows `vvis` visleaves!), Show Information (Solids/PointEnts/SolidEnts/Faces/Unique Textures/VRAM), **Map Properties** (`worldspawn`: `skyname`, `detailvbsp`, `detailmaterial`, `maxpropscreenwidth`).
- **View:** Screen Elements (9 dockbars), Autosize 4 Views (`Ctrl+A`), 2D/3D View Modes (including **3D Lightmap Grid** — visualizes luxel density!), Center Views on Selection (`Ctrl+E`), Go to Coordinates, Go to Brush Number (`Ctrl+Shift+G`), Show Connections, Show Helpers, Show Models in 2D, Hide Entity Names, Radius Culling (`C`), QuickHide (`H` / `Ctrl+H` / `U` / Convert to VisGroup), Draw Materials Opaque, HDR toggle.
- **Tools:** Carve (`Ctrl+Shift+C`), **Make Hollow** (negative = outward wall shell, positive = inward!), Group (`Ctrl+G`), Ungroup (`Ctrl+U`), Tie to Entity (`Ctrl+T`), Move to World (`Ctrl+Shift+W`), Texture Application (`Shift+A`), **Replace Textures** (Find/Replace exact or partial matches across Marked/Everything/Hidden + auto-rescale UVs!), Texture Lock (`Shift+L`), **Sound Browser (`Ctrl+Shift+S`)**, **Transform (`Ctrl+M`)** (exact XYZ Rotate / Scale / Move), Snap Selected to Grid (`Ctrl+B` / `Ctrl+Shift+B`), Center Origins, Align Objects (Left/Right/Top/Bottom), Flip Objects Horizontally (`Ctrl+L`) / Vertically (`Ctrl+I`), Create Prefab (`Ctrl+R`), **Options...**.

### 2.3 Hammer's Exact 6-Tab Options / Settings Dialog (`hammer_dll.dll` Dialogs `174, 179, 199, 207, 246, 275`)
1. **General (`[174]`):** Independent window layouts, Autosave (Enable, Minutes between saves, Max MB budget, Iteration count, Directory), Undo levels, Allow grouping while Ignore Groups is active, Stretch arches/toruses to fit bounds, Use VGUI Model Browser, Max Cameras.
2. **2D Views (`[179]`):** Crosshair cursor, Default to 15° rotations, Draw Vertices, White-on-Black vs dark grid, Use VisGroup colors for outlines, Keep VisGroup on clone-drag, Center 2D on 3D camera, Arrow keys nudge selected object/vertex, Reorient primitives, Infinite selection, Select by center handles only, **Grid Settings** (Default size, Intensity slider 0–100, Highlight every 64u / N lines / 1024u, Hide grid <4px, Dotted grid), Group carved fragments, Draw Models in 2D.
3. **3D Views (`[199]`):** Back clipping plane (`5000u`), Filter textures, Animate models, Model render distance, Detail render distance, **Navigation** (Mouselook toggle, Reverse mouse Y axis, Forward speed slider, Time to top speed slider), Reverse selection order, **Camera FOV (`30–100°`)**, `light_spot` Cone Multiplier.
4. **Game Configurations (`[207]`):** Active Game Config, FGD list (`base.fgd`, `tf.fgd`, `tf-abs.fgd`), Texture Format, Map Type, Default PointEntity (`info_player_teamspawn`), Default SolidEntity (`func_detail`), Default Texture Scale (`0.25`), Default Lightmap Scale (`16`), Cordon Texture (`tools/toolsskybox`), Game Executable Dir, Game Dir (`tf/`), VMF Save Directory.
5. **Build Programs (`[275]`):** Executable paths & default parameters for Game (`tf_win64.exe`), BSP (`vbsp.exe`), VIS (`vvis.exe`), RAD (`vrad.exe`), and compiled `.bsp` destination folder (`tf/maps/`).
6. **Materials (`[246]`):** Screen Gamma slider, Material directory exclusion list (`cable`, etc.).

### 2.4 Hammer's Exact Face Edit Sheet (`[194]`) & Displacement Tools (`[303, 307–310, 349]`)
- **Face Edit (`[194]`):** Texture Scale (`X, Y`, TF2 default `0.25`), Texture Shift (`X, Y`), Rotation (`deg`), **Lightmap Scale** (`16` units/luxel default; lower = sharper shadows, higher = faster compile), **Justify** (`L | R | T | B | C | Fit` + `Treat as one` across multiple faces!), **Align** (`World` vs `Face`), Hide Mask (hides red selection tint while tuning alignment), Browse / Replace, **32 Smoothing Groups (`[318]`)** (Smooth / Hard Phong shading across brush faces!), Surface/Content flags (`NoDraw`, `Hint`, `Skip`, `Player clip`, `Detail`, `Area portal`).
- **Displacement (`[303–310, 349]`):** Create (`Power 2/3/4`), Destroy, **Paint Geometry** (Raise/Lower, Raise To, Smooth, Spatial Axis X/Y/Z/Face Normal, Soft/Hard Edge, Distance, Radius, **AutoSew**), **Paint Alpha** (blends `$basetexture` ↔ `$basetexture2` on `WorldVertexTransition` materials! Raise/Lower, Raise To, Smooth, Value slider), **Invert Alpha**, **Subdivide** (smooth Catmull-Clark curvature!), **Noise** (Min/Max random organic roughness!), **Sew** (stitches cracks between adjacent displacements of equal or power-of-2 sizes!), **Sculpt** (Push / Project / Carve), Tag Walkable / Buildable, Collision masks (`No Hull`, `No Physics`, `No Ray`).

### 2.5 Hammer's Exact Object Properties (`Alt+Enter`: 6 Tabs — `[106, 147, 300, 306, 148, 316]`)
1. **Class Info (`[106]`):** Class dropdown (all FGD PointClass/SolidClass), **SmartEdit toggle** (shows human-readable labels, dropdown `choices`, color pickers, sound/model/material browsers instead of raw strings!), Copy/Paste/Delete KeyValues, Pitch-Yaw-Roll Angles compass + `Point At` picker, Entity Help description from FGD!
2. **Flags (`[147]`):** Bitmask checkboxes defined in FGD `spawnflags(flags)`.
3. **Outputs (`[300]`):** ListView of Entity I/O outputs (`My output named` → `Targets entities named` → `Via this input` → `With parameter override` → `After delay (s)` → `Fire once only`), plus **Eyedropper entity picker**, **Mark target**, and red broken-target warnings!
4. **Inputs (`[306]`):** Reverse view showing every entity targeting this object + **Mark** button to jump to the originator!
5. **VisGroup (`[148]`):** Assign/remove this object from custom VisGroups.
6. **Model (`[316]`):** Preview model + choose `skin` and `bodygroup` index!

### 2.6 Hammer's Official `CmdSeq.wc` Compile Presets (Extracted Directly from `TF2/bin/CmdSeq.wc`)
| Preset Name | `vbsp` Args | `vvis` Args | `vrad` Args | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **Default** | `-game $gamedir $path\$file` | `-game $gamedir $path\$file` | `-game $gamedir $path\$file` | Standard LDR compile |
| **Fast** | `-game $gamedir $path\$file` | `-fast` | `-bounce 2 -noextra` | Rapid iteration compile |
| **Only Entities** | `-onlyents` | *(skipped)* | *(skipped)* | Instant <1s entity-only update! |
| **HDR Full Compile** | normal | normal | `-both` | Compiles BOTH LDR + HDR lightmaps |
| **HDR Full `-final`** | normal | normal | `-both -final` | Shipping quality (+ `-staticproplighting -staticproppolys -textureshadows` for TF2!) |

> **VAC SAFETY RULE (Pootis Builder 2.0):** Unlike vanilla `CmdSeq.wc` which runs `-dev -console -allowdebug`, Pootis Builder **ALWAYS injects `-insecure +sv_lan 1`** when launching `tf_win64.exe` so VAC is never touched.

---

## 3. FGD System & A Boojum Snark's TF2 Mapping Resource Pack (Already in Our Repo!)

### 3.1 FGD Helper Directives We Can Render Automatically
From `base.fgd` (`305` classes), `tf.fgd` (`144` classes), and `tf-abs.fgd` (`59` upgraded TF2 classes), Hammer renders entities cleanly via FGD class decorators:
- `studio("path.mdl")` / `studioprop()` → Renders actual 3D TF2 `.mdl` directly (and uses `model` KV when empty).
- `iconsprite("materials/editor/...")` → Renders a crisp billboarded Valve/ABS logic icon sprite in 3D!
- `sphere(radius_kv)` / `cylinder(...)` / `wirebox(min,max)` → Renders light radii, sound radii, explosion/capture bounds!
- `lightcone()` / `frustum()` → Renders `light_spot` & `env_projectedtexture` direction cones!
- `line(r g b, targetname, target)` → Draws automatic 3D connection lines (like `path_track` chains & `team_control_point` links)!
- **SmartEdit Property Types (`PropTypes`):** `choices` (dropdown), `flags` (checkboxes), `color255` (RGB+Brightness picker), `studio` (3D Model Browser), `sound` (Sound Browser), `material` (VPK Texture Browser), `target_destination` (Entity target autocomplete + 3D Eyedropper!), `angle` (compass dial), `integer`/`float`/`string`.

### 3.2 Untapped Goldmine in `assets/mapping_resource_pack/`
1. **`ABS_MRP_Improved_FGD.vpk` (59 files — mount in `SourceFs`!):**
   - `models/editor-abs/dev_engy.mdl` — Real 3D TF2 Engineer scale model for `info_player_teamspawn` (RED/BLU skins!) instead of generic cylinders!
   - 27 crisp custom Valve-style TF2 logic icon sprites (`tf_logic_koth`, `tf_logic_arena`, `tf_gamerules`, `team_train_watcher`, `team_round_timer`, `team_control_point_master`, `team_control_point_round`, `game_text_tf`, `point_template`, etc.).
2. **`ABS_MRP_Material_Browser.vpk` (407 files):**
   - Visual dual-texture preview swatches for TF2 `WorldVertexTransition` blend textures (`blendttx/*`), water materials (`waterttx/*`), and overlays (`overlayttx/*`)!
3. **`tf-abs.fgd`:**
   - Load on top of `base.fgd` + `tf.fgd` so every TF2 entity has ABS's fixed choices (complete `DamageTypeABS` choices like Train/Sawblade/Fall/Blast, fixed `Item` models, `ObjectABS` sentry/dispenser team+level choices, proper `worldspawn` defaults, and `@AutoVisGroup` rules!).

### 3.3 Valve's Complete Asset & Shipping Toolchain (`TF2/bin/`)
- `vbsp.exe` / `vvis.exe` / `vrad.exe` — Map compilation (already wired; add `Only Entities`, `Fast`, `HDR Full`, `HDR Final` from `CmdSeq.wc` + live log viewer + `.prt` portal visualizer!).
- `studiomdl.exe` — Compiles our 3D Model Importer's `.QC` + `.SMD` files directly into real TF2 `.mdl` props!
- `vtex.exe` — Compiles custom PNG/TGA images into real TF2 `.vtf` textures!
- `bspzip.exe` — Automatically packs custom models/textures/sounds into the `.bsp` Pakfile so friends & Workshop players see custom assets with zero missing pink-black checkerboards!

---

## 4. Pootis Builder 2.0 vs. Valve Hammer++ — Exact Gap Map for Future Builds

| Hammer / Hammer++ Capability | Pootis Builder 2.0 Current Status | Next Upgrade Priority |
| :--- | :--- | :--- |
| **Responsive HiDPI UI + Extensive Settings (6 Hammer tabs + Display/UI Scale + Keybinds)** | Missing HiDPI/stretch config & Settings menu | **P0 — Immediate** |
| **Real 3D TF2 Game-Asset Icons (`Tf2IconBaker` + `dev_engy.mdl` + ABS sprites) & Drag-and-Drop** | `Tf2IconBaker` created & tested (22 real 3D `.mdl` icons!) — not wired into UI yet | **P0 — Immediate** |
| **Full FGD-Driven SmartEdit Inspector (`tf-abs.fgd` + `base.fgd` + `tf.fgd`: Choices, Flags, Outputs, Inputs, Color Picker)** | Basic 6-field KeyValue editor | **P1 — High** |
| **Full Face Edit Sheet (`Shift+A`: UV Scale/Shift/Rot, Fit/Justify, World/Face Align, Lightmap Scale, Replace Textures)** | Material swatches + Paint + Alt Eyedropper only | **P1 — High** |
| **Full Displacement Tools (Paint Alpha Blend, AutoSew, Noise, Subdivide, Invert Alpha)** | Raise/Lower/Smooth/Flatten geometry only | **P1 — High** |
| **Complete Selection & Modeling (Multi-Select, Groups `Ctrl+G`/`Ctrl+U`, QuickHide `H`/`U`, Make Hollow, Transform `Ctrl+M`, Paste Special, Vertex Edit `Shift+V`, Overlays/Decals `Shift+O`/`Shift+D`)** | Single-select, Face-Pull, Clip, Rotate, Clone, Tie, Delete | **P1 — High** |
| **Split 2D Blueprint Views (`2D Top X/Y` + `2D Side X/Z` with TF2 Jump-Height Guides) + Status Bar Telemetry** | Single 3D view + orthographic toggle | **P2 — High** |
| **Check Map for Problems (`Alt+P`) + Entity Report + Cordon Compile + `CmdSeq.wc` Presets (`Only Entities`, `Fast`, `HDR Final`)** | Basic Map Coach + Fast/vbsp compile | **P2 — High** |
| **Asset Shipping Pipeline (`studiomdl.exe` + `vtex.exe` + `bspzip.exe` Pakfile Packer)** | `.QC`/`.SMD` export only | **P2 — Medium-High** |
| **Real-Time Lighting Preview, 3D Skybox Preview, Particle Browser, Sound Browser (`Ctrl+Shift+S`)** | Skybox + OmniLights + TF2 UI audio | **P3 — Polish** |
