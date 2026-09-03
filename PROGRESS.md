# Progress log (autonomous overnight build)

Newest first. ROADMAP.md milestones A–H are spent; **PLAN.md** is the live plan
(five gated phases to 1.0 + the UI plan).

## Phases + performance batch
- **Phase 5 — content packing auto-detect.** `publish/AssetScan` walks
  the doc's face materials (+ `$basetexture`/`$basetexture2`), entity
  models (+ `.vvd`/`.vtx`/`.phy` siblings) and sound keys.
  `SourceFs::assetOrigin()` classifies each path Base (in an official
  `tf2_*`/`hl2_*` VPK) / Custom (loose → needs bspzip) / Missing;
  `mountDefaults()` now also mounts the sound VPKs so ambient sounds
  don't read as missing. "Scan map for custom content" in the compile
  window auto-fills `packFiles_` (which already feeds bspzip) and lists
  missing refs. `--pack-scan`; test.sh checks the kit output is clean.
  73/73.
- **Phase 5 — ship it (started).** **Leak diagnostics**: `MapCompiler`
  now detects the `.lin`/`.pts` pointfile vbsp drops next to the vmf on a
  leak (`leakFile()`); the editor auto-loads it when a compile finishes
  leaked, parses the x/y/z trace and draws it as a glowing magenta
  polyline in every viewport with a "leaked entity" marker + a Map Check
  section ("Frame the leak" aims the 3D cam down the first segment, "Load
  pointfile…", "Clear"). `--leak-test`. **Map Check** gained real
  compile-blocker checks: skyname-set-but-no-toolsskybox-brush, no
  `env_cubemap`, one-team spawns (TeamNum), spawns-without-func_respawnroom,
  displacement-face-on-a-brush-entity. `test.sh` 72/72.
- **Phase 4 — one adaptive workspace (dial shipped).** `enum Mode {
  Simple, Pro }` → `{ Guided, Standard, Full }`. Guided = pure Build Kit;
  Standard = kit + the full tool strip + Textures / Contents / Map Check
  tabbed in; Full = the old Pro layout. Layout branches key off `!= Full`,
  the tool strip off `!= Guided`. `drawSelectionPanel` now routes to the
  Face-edit panel when the Surface tool is active (mirrors Pro's
  `drawProperties`). Dial position persists via `Settings::workspaceDial`
  / pootis.ini; `setDial(0|1|2)` + `--dial <n>`. Command palette + status
  bar updated. `test.sh` 71/71. Deferred: KitInstance re-optionable
  pieces, preview-everywhere, guided-first-map coach marks.
- **Phase 3 — Surfaces (core done).** Material browser rebuilt on the
  model-browser pattern (30k VMTs themed into groups, All / In this map /
  Recent, full search, click-to-apply to selected faces). Surface tool:
  Alt-click eyedropper + "treat selection as one surface". **Displacements**:
  (a) `BrushFace` keeps the raw `dispinfo` block so decompiled terrain
  round-trips losslessly — before this, saving cp_badlands flattened all
  1191 displacements; (b) `buildDocMesh` tessellates the disp grid so
  terrain renders sculpted in the editor, backing faces hidden;
  (c) `faceMakeDisplacement` (power 2/3/4) + `faceSculptDisplacement`
  (smoothstep raise/lower) + a DISPLACEMENT panel section.
  `--disp-test` 7/7, `test.sh` 71/71. Deferred: `$basetexture2` blend
  paint, interactive drag-sculpt, sew / subdivide / alpha, smoothing-group UI.
- **Repo prep for public GitHub release.** Rewrote `README.md` — it still
  described "milestone 1: BSP load + view" while the editor is now a full
  decompile → edit → compile → playtest tool; the new one covers what
  actually works (loading/rendering, Simple + Pro editing, transforms,
  ship pipeline, QoL) plus build/run/layout and a third-party
  acknowledgements section. Added `.gitattributes` (LF in repo, `eol=lf`
  for `*.sh`, `eol=crlf` for `*.ps1`, binary rules for fonts/assets).
  `gh` 2.99.0 installed to `%LOCALAPPDATA%\Programs\gh`; secret/email/abs-path
  scan of tracked files is clean; `tools/` (BSPSource + JRE) and
  `assets/mapping_resource_pack/` stay gitignored.
  **Licensed GPL-3.0** (`LICENSE` = full FSF text; README "## License"
  section, `Copyright (C) 2026 the Pootis Builder authors`). All bundled/
  fetched deps are GPL-compatible (MIT/Zlib/OFL).
  **Published:** https://github.com/augustuspoplus/Pootis-builder (public,
  branch `main`, 111 commits). Whole history was `filter-branch`'d to
  `Pootis Builder <49472861+augustuspoplus@users.noreply.github.com>` —
  the personal address is nowhere in the pushed repo; local `user.email`
  set to match. See `memory/github-repo.md`.
- **README screenshots.** `docs/img/{welcome,simple-build,simple-things}.png`
  (1760×950, headless `--ui`) in a "## Screenshots" table near the top.
  New `--shot-overview` flag + `Editor::debugShotOverview()` reframes the 3D
  view on the whole map (anchored on a spawn, pulled back + up) —
  bounds-based framing is unreliable on decompiled maps (skybox brush blows
  the AABB up). `--panel` now runs before the shot hooks. 69/69.
- **Things list — icons + a lot more of them.** The Simple-mode ▸ Things tab
  had ~20 entries and every non-model item fell back to a generic bolt/cube
  glyph. `SE` now carries a per-item FontAwesome icon and a `group` header;
  the list is ~43 entries in five sections — **Players & goals** (spawn door,
  CTF/KOTH/Arena/Round-timer setups, no-build), **Pickups**, **Doors & movers**
  (working door, elevator, moving platform, button, lever, fan, teleport pair,
  breakable crate), **Volumes & triggers** (death pit, water, clip wall,
  ladder, trigger box), **Atmosphere** (3D sky camera, env_cubemap,
  soundscape, rain/snow, light glow). All 38 glyphs verified present in the
  bundled `fa-solid-900.ttf`; new raw classes (`sky_camera`, `env_cubemap`,
  `env_soundscape`, `func_precipitation`, `env_lightglow`) smoke-tested via
  `--place-ent`. 69/69.
- **Phase 2 — precise transforms** (c880bed → f72923d, essentially done).
  Modal `G`/`R`/`S` + `X`/`Y`/`Z` axis lock + numeric entry + HUD (2D/3D,
  world/entity). "Snap to grid" button; live centre/delta readout on 2D
  drags. **Magnet toggle**: bbox-corner snap onto another brush's nearest
  vertex (cyan ring), in body-drag + modal G. **Block tool**: viewport
  depth field + live "W x H (deep D)". **Alt** when starting R/S = pivot on
  the cursor. `--mx-test` 4/4 (69 total). Left: edge/face snap targets.
- **Phase 1 — brush-entity editing** (93c9917, be788b8, 0a1dbc9). Delete /
  duplicate / clip / untie / tie-picker on entity brushes; "part of <class>"
  identity. `--phase1-test` 4/4 on decompiled cp_process (`func_illusionary`).
  Only cross-entity grouping deferred.
- **Perf: baked-prop cache** (dcdcce3). Every edit re-baked every prop model —
  pl_upward (1748 props → 1.5M verts) was ~18 s per placement. `buildAndUpload`
  now snapshots the baked-prop geometry into a blob keyed by the prop list and
  splices it back when props are unchanged → **~18 s → <30 ms**. Options ▸
  Performance: Auto / Quality / Fast (Fast shows props as boxes on dense maps,
  cutting the decompile bake to ~1 s). GL renderer/driver shown; laptop
  discrete-GPU exports in main.cpp. Top bar now collapses gracefully below
  ~1580 dp so "Build & play" never clips.
- **Auto sky-seal** (ef2e16b). One-click "Seal map with sky" under the MAP
  CHECKLIST; the seal piece re-fits (removes the old shell) on re-run; the
  checklist row checks for real `toolsskybox` brushwork.
- **Phase 1 — brush-entity editing** (93c9917). Delete / duplicate work on
  individual entity brushes; `untieSelectionToWorld()`; "part of <class>" +
  "Select all of it" in the Selection panel; the "editing is limited" message
  is gone. Transform already worked. Remaining P1: class-picker for tie,
  cross-entity grouping, sub-object on entity brushes, clip/hollow/carve.

## User-requested batch (editing UX)
- **Reliable card drag + drop preview** (cb51c56): every Build card, Things
  row, model tile and entity-catalog row now uses one manual drag mechanism
  (press + drag-past-threshold → `dragPlace_`, dropped by `frame()` on the
  viewport under the release). The Build cards were the worst — they wrapped
  content in a child window and `BeginDragDropSource`'d *that*, so Wall etc.
  often refused to drag. While a piece is armed or dragged, a green wireframe
  ghost + `name (x y z)` label shows exactly where it'll land.
- **Themed prop categories** (a2aea25): the 16k models bucket into ~20
  recognisable themes with icons — Winter & alpine ❄, Desert & badlands ☀,
  Farm & sawmill, Swamp & jungle 🐸, Medieval ♜, Spytech & sci-fi 🕵,
  Holiday & event 👻, Industrial & urban ⚙, Nature & rock 🌳, Lighting,
  Doors, Furniture, Vehicles, Signs, Gameplay, Junk, Skybox, Half-Life 2 🏙,
  Cosmetics 🧙, Map packs 🗺. Substring match on the folder name.
- **History tab in Simple mode** (bc3cc5d): `drawHistoryPanel` docks beside
  Selection — full-width Undo/Redo, every step in plain language, current
  step marked + auto-scrolled, undone steps dimmed, click to jump.
- **3D-primary viewports** (77079ac): both modes start with only the 3D view;
  top-bar "Top / Front / Side" toggles open each 2D view as a tab beside 3D
  (own close button). Pro's fixed 2×2 removed.
- **Gizmo switcher + options** (2b4bd1a): Blender-header-style
  [move][rotate][scale] toolbar floats top-left of each viewport when a
  brush is selected (W/E/R still work); Options > Viewport gains a gizmo
  "Handle size" slider + Normal/Bold/Fine style, persisted.
- **Whole-piece vs part selection** (a38c048): viewport toolbar toggle —
  clicking a multi-brush piece (Dome, spawn room…) grabs the whole
  func_detail, or just the one brush. Placing a multi-brush piece selects
  the whole thing now.

## Overnight batch — Simple-mode expansion (latest)
- **Phase 1 — model-less entities visible everywhere** (5215d28): any entity
  with no renderable model now draws a class-coloured diamond + label in the
  3D view, and `path_track`/`path_corner` chains draw a green route polyline
  following their `target` keys. Payload "Payload track" kit piece rebuilt as
  a real spine: 4 chained `path_track` + `func_tracktrain "cart"` +
  `trigger_capture_area` parented to the cart + `team_train_watcher` +
  `team_control_point`. Fixes "the payload path never shows up".
- **Phase 2 — props browser grouped** (9fcc5a7): the flat 16k-model grid is
  bucketed into plain-language categories (by the model path's 2nd segment,
  friendly-named, size-sorted) with a category combo + a "Recently used"
  bucket; search overrides the filter.
- **Phase 3 — Simple mode expanded** (ce7e682): ~25 new kit pieces —
  Stairs / Cylinder / Dome / Arch / Wedge / Doorway / Platform / Cover /
  Skybox seal / Clip wall / Water / Trigger box / Ladder / Working door /
  Button / Elevator / Fan / Teleport pair / KOTH point / CTF setup /
  Round timer / Breakable crate / single spawn point. Shape-option sliders
  (steps, radius, sides, span, travel…) in the selection panel when a shape
  is armed. Kit tab bar reorganised: Build / Play / Moving / Zones / Things /
  Props / Light. Map-checklist rows gained "+ Add" buttons that place the
  missing piece.
- **Phase 4 — welcome-screen templates**: 6 bundled starter maps in
  `assets/templates/` (empty_room, arena, ctf_2base, payload, cp_push,
  trade_box), generated by `Editor::makeTemplates()` from the kit itself
  (`--make-templates <dir>`). Welcome screen gets a "From a template" row
  that loads one into Simple mode. All 6 verified loading clean (6–24 solids,
  2–21 entities).
- **Phase 5 — the turbine challenge** (dd… follow-up): `Editor::makeTurbine()`
  reconstructs ctf_turbine's plan from the kit's own brush primitives —
  180-degree rotational symmetry about Z (BLU half authored once, echoed to
  RED by (x,y)->(-x,-y)), true Hammer scale (~7200u base-to-base, ~3500u
  wide), central turbine room with a stacked-cylinder fan over an open pit +
  catwalk ring, mirrored offset spawns, main halls, basement intel rooms at
  the far diagonal corners, crawl vents, stairwells, an upper gallery. Real
  spawn / flag / observer coordinates lifted from the decompiled .vmf. Ships
  as `assets/templates/turbine_lookalike.vmf` (7th welcome card) and is
  regenerated by `--make-templates`. Verified: 120 world solids / 39 entities,
  loads clean, and **compiles leak-free through vbsp + vvis + vrad** to a
  2.4 MB lit .bsp (5658 tris).
- **Phase 6 — test sweep**: headless verification pass —
  - 43 kit pieces (`--place-kit` + `--save-vmf`): all emit geometry/entities,
    no crashes.
  - 18 curated Things entities (`--place-ent`): all place with FGD-seeded
    keys, no crashes.
  - 25 stock TF2 maps across every mode/era (2fort, snakewater, mannworks,
    degrootkeep, up to 242k tris / 1855 disps): all load and build a world
    mesh, zero errors.
  - All 7 welcome templates load clean.
  - **Regression found + fixed**: the open-floor templates (arena, ctf_2base,
    payload, cp_push) leaked — no walls/ceiling. Added a trailing
    `Skybox seal` pass + dropped the sun to z=384; all 7 now compile
    leak-free through vbsp.
  - **Undo bug found + fixed**: `map::History` only snapshotted brush
    geometry, never the entity list — so undoing a kit piece that places
    entities (spawns, points, lights, props) orphaned them, and
    moving / re-keying a point entity couldn't be undone at all. History
    now snapshots the full entity list. `--undo-test` (place / rotate /
    delete round-trip) passes 5/5.
- **More Simple pieces** (post-sweep): Window, Spiral stairs, Fence,
  Crate stack (Build); Spawn door = `func_respawnroomvisualizer` (Moving);
  Death pit, No-build zone (Zones); Spectator camera (Things).
- **Second hardening pass**:
  - `Skybox seal` now also encloses every point-entity origin, and
    `makeTemplates()` seals *after* placing the sun (z=192) — the
    payload/arena/ctf/cp templates were still leaking a high
    `light_environment`; now all 7 vbsp leak-free (verified standalone).
  - `path_track` / `path_corner` labels show just the targetname and
    stagger vertically, so a payload spine reads cleanly in 2D and 3D.
  - Added **Arena logic** (`tf_logic_arena` + mid point + master, Play)
    and **Moving platform** (`func_movelinear` on a button, Moving).
  - Decompile sweep: ctf_2fort / koth_viaduct / cp_gravelpit / pl_upward
    run the full BSPSource → editable-VMF path (1.3k–3.6k solids,
    4.7k–5.9k entities) and render textured with props.
  - Options persistence confirmed: all 16 keys + the recent-files MRU
    round-trip through `%LOCALAPPDATA%\PootisBuilder\pootis.ini`.
  - Full 52-piece kit re-sweep: 0 empty, 0 crashes.
- **Third pass**:
  - Props browser: the category dropdown is now a real **collapsible,
    scrollable category list** under a "Categories" header (Simple + Pro
    both use `drawModelGrid`). Player cosmetics (~10.5k of 16k models) split
    into their own "Cosmetics (hats)" bucket; workshop packs bucket by pack
    name; sub-12 buckets fold to "Other". `--kit-tab N` now selects any of
    the seven kit tabs (for the screenshot sweep).
  - Option panels added for **Room** ("half-size"), **Spiral stairs**
    (steps / rise / diameter) and **Moving platform** (travel).
  - Drag-drop re-verified for all three payloads (`@kit:`, `@ent:`,
    `@model:`) via the headless `--place-kit / --place-ent / --drop-model`
    hooks.
  - Turbine reconstruction fleshed out (144 solids) — spawn annex + hall
    flank room per side widen the silhouette toward the real decompiled
    top-down; still vbsp leak-free.
- **Fourth pass — full Phase-6 sweep** (now `test.sh` at the repo root):
  40 raw stock maps, 6 decompiles (`--ui`, so it waits for BSPSource),
  52 kit pieces, 15 Things, undo, 7 templates + their vbsp compiles,
  Options persistence. First run 120/128 caught two real regressions —
  **empty_room + trade_box leaked** (sun above a 192-tall Room, no explicit
  seal). Fixed with a low sun + `seal()` pass; the other 6 misses were a
  harness bug (non-UI `--view` doesn't block for the async decompile).
  Re-run: **129 / 129 green**.
- Added **Lever** (Moving tab) — a toggle/stay `func_button`, vs the
  momentary Button.
- `test.sh` [quick] committed as the standing regression check.

## Visual fidelity (done)
- **prop_static models**: `model/StudioModel` parses MDL + VVD + VTX (LOD 0,
  bind pose); `bakePropModels` folds every prop's geometry into the BSP
  WorldMesh transformed to world space. Verified ctf_turbine 406/406.
  `--no-decompile` inspects the raw BSP + baked props; `--dump-props` prints
  per-instance / per-model diagnostics.
- **Displacements**: `BspMesh` builds the (2^power+1)^2 grid per dispinfo face
  (bilinear base quad + dispvert push), reusing the flat-face lightmap/UV
  projection. Verified hoodoo/gorge/badwater.
- Fixed the D.5 entity overlay flooding the 3D view on big decompiled maps —
  perspective now respects `showPointEntities`; connection lines past 60
  entities only draw for the selection.

## Editing feel (latest)
- Drag the object body to move it (3D = ground plane, Shift = vertical; 2D =
  view plane). Bigger, DPI-scaled resize handles + a bigger ImGuizmo.
- Live preview during handle-resize / body-move (was gizmo-only) so geometry
  follows the cursor; prop re-bake skipped mid-drag on >40-prop maps.
- Hover outline: soft blue wireframe on whatever the cursor is over.
- Shortcuts made global (raw key state, not focus-routed) — Ctrl+Z etc. work
  from any panel.
- Options window (gear button / View menu): interface, editing, viewport,
  advanced; persisted to pootis.ini via applyPrefs().
- prop_static + FGD studio() models (health kits, ammo, flags) render in the
  editable doc, not just the raw BSP view. cdmaterials leading-slash fixed.
- Manual menu->viewport drag placement; drop lands under the cursor.

## Simple-mode polish (latest)
- **Things tab**: curated plain-language entity list (spawn rooms, capture
  point, payload path, resupply, health/ammo, intel, hurt/push triggers,
  door, sound, particles, fog) with real model-render preview icons.
- Model browser: **real 3D thumbnails** (ModelThumbnailer -> offscreen FBO,
  cached) instead of the raw texture atlas; wired into the Simple Props tab
  too. **Drag-and-drop** from any menu card (model / kit / entity) straight
  onto a viewport -> drops at the cursor (rect-based DragDropTargetCustom).
- **Keyboard shortcuts**: Ctrl+Z/Y/S/O/C/V/X/D/A/B/K, Del, F, Esc, [ ]
  rotate, W/E/R gizmo, F1 cheat-sheet. copy/paste/cut + rotateSelection;
  Delete now also removes point entities.
- **Rotate** buttons in the selection panel (turn 90 about Z, tip onto side).
- **Windows app icon** (src/win/app.rc via staged windres) + runtime GLFW
  window icon from assets/PootisBuilder.ico.
- Kit tab bar no longer collapses to "..." in the narrow dock (scroll +
  popup button); kit cards size to their text.

## 3D view / editing UX (done this pass)
- Infinite ground grid in the 3D view (distance fade, red +X / green +Y axes)
  + a world-origin ring marker while the map is empty.
- Drag-to-resize: 8-handle bounding box in the 2D views (corner = 2 axes,
  edge = 1) AND 6 face-centre handles in the 3D view (ray vs world-axis).
  Snapshot + affine remap, grid-snapped, one "Resize" undo step.
- Models browser — 16k+ game models, filterable thumbnail grid, click-to-drop
  as prop_static.
- Build Kit cards size to their text (no more clipped hints).
- New Shapes: **Hill** (faceted mound of jittered octagonal prisms, r/h/
  roughness/layers sliders) and **Curvy road** (click points -> Catmull-Rom
  spline -> ribbon of oriented road brushes). Both land as one func_detail.

## Now / next
- **Milestones A–F, C, D done. Section G well underway** (see below).
- **Section G still to do:** instances (func_instance), asset favourites,
  keybind customisation, Simple-mode tutorial + welcome tips, a dedicated
  measure tool. (cordon, bspzip, visgroups, .pbproj, camera bookmarks, log
  panel, map-check, palette, history, autosave — all DONE.)
- Visual fidelity remaining: `$basetexture2` blend materials; real
  iconsprite / rendered-model thumbnails (browser uses first-material now).
- Prop models: LOD only, no per-prop lighting/skins; no neighbour-stitching
  on displacement seams (Valve's CDispNeighbor data is skipped).

## UI scaling
- `ui::g_scale` + `dp(px)`; top bar, fonts and icons are DPI-aware. Font
  Awesome merge retuned (advance ~0.9em, pixel-snapped baseline). Top-bar
  right cluster measures itself so it never overlaps. `--scale <f>` previews
  a scale headlessly. Verified clean at 100% and 150%.

## Section G — quality of life (done so far)
- Autosave (`<map>.autosave.vmf`, menu-configurable interval) + rolling
  `.vmf.bak1-3` on every real save. `MapDocument::saveVmf(…, updateState)`.
- History panel — full undo stack, click any step to jump. Log panel —
  `core/Log` ring buffer, severity colours, follow-scroll, copy-all.
- Map Check — spawns / lights / skybox / objective / invalid + oversized
  brushes / dangling I/O targets; severity-sorted, click to select+frame.
- Command palette (Ctrl+K) — actions, tool switches, "Place entity: <class>".
- Live selection dimensions (w×h) in every ortho view.
- Camera bookmarks ×6 + go-to-coordinate (View ▸ Camera).
- Brush groups (Solid.group, VMF editor{groupid} round-trip; pick one → whole
  group selects; Group/Ungroup in the inspector).
- Prefab library — panel lists prefab .vmf files, click-to-drop with fresh
  ids at the snapped cursor; "Save selection as prefab…".

## Side quests (user-requested, done out of roadmap order)
- **3D model import** — `import/ObjModel` (OBJ loader) + `import/ModelImport`:
  - "Detail brushwork": one convex tri-prism per triangle → func_detail in the
    VMF (tri-count cap). Verified: pyramid.obj → 6 brushes, all 4 views.
  - "Prop model": SMD + QC staged, baked to a real .mdl by studiomdl on the
    next Build (`MapCompiler` modelQc pass). Verified studiomdl output.
  - Top-bar "Import ▾" menu (Map / 3D model) + import dialog with live preview.
- **Publish to Steam Workshop** — `publish/Workshop`: stages a Workshop item
  folder (content/.bsp + preview jpg + steamcmd `publish.vdf`, appid 440).
  Top-bar "Publish" window: bsp check, capture-preview, title/desc/notes,
  visibility, gamemode tags, update-existing id. Hand-off via generated
  steamcmd command; in-process ISteamUGC upload is behind `PB_HAVE_STEAMWORKS`
  (SDK not bundled — can't be fetched here).

## "Good state" bar — REACHED
A + B + E all done: open a map (or start one), move/add/delete brushwork with
the gizmo + block tool + kit, save to VMF, compile with vbsp/vvis/vrad and
playtest in TF2.

## Done
- (baseline) BSP loader, renderer, VPK pipeline, Simple/Pro UI, welcome, scaling.
- Scheduled 3-hourly continuation cron (session-only, job e9af0746).
- **Milestone A** — editable document:
  - A.1 `map/Kv` (KeyValues parse+write), `map/Solid` (brush plane-set →
    polygonise via big-quad clipping), `map/MapDocument` (VMF load/save),
    `map/MapMesh` (buildDocMesh → shared WorldMesh). tool/trigger brushes
    render see-through.
  - A.2 `Camera::pixelRay` + `map/Raycast`; left-click pick, shift-toggle,
    Esc/Delete; `SceneRenderer::setSelectionWire` bright outline overlay.
  - A.3 `platform/Process` (CreateProcess, no window) + `decompile/BspSource`
    (bundled BSPSource CLI, cached under %LOCALAPPDATA%/PootisBuilder/decompiled).
    Opening a .bsp shows the fast BSP view immediately, then swaps to editable
    brushes in the background. Opening a .vmf loads it directly.
  - Verified: ctf_turbine.vmf 1039/1039 solids; cp_badlands.bsp auto-decompiled
    → 3345 editable brushes rendering in all views.
- **Milestone B** — transform + block tool:
  - B.1 undo/redo command stack (`map/History`, 32-deep snapshots), arrow-key
    nudge with grid snap, Ctrl+D duplicate, Ctrl+S save-VMF.
  - B.2 ImGuizmo move/rotate/scale in every viewport (per-view ID, snap).
  - B.3/B.4 Block tool (drag a box in any view → new brush) + brush inspector
    (centre X/Y/Z, size W/D/H drag-scrub + type, material swatch, dup/delete).
- **Milestone E** — save, compile, play:
  - `compile/MapCompiler` background worker: vbsp → vvis → vrad with a
    line-buffered live log, Fast/Final profiles, per-tool cancel; copies the
    `.bsp` into `<game>/maps/` and launches TF2 `-insecure +sv_lan 1 +map`.
  - Compiles run from `<game>/mapsrc/` — the Nov-2025 tools refuse to write
    their `.log`/`.prt` outside a game-owned content path.
  - `platform/Process::runProcessStreaming` (per-line callback + cancel) and
    `launchDetached`; `platform/FileDialog::saveFileDialog` (native Save As).
  - "Build & play" window: profile picker, vvis/vrad/launch toggles, mono
    log with follow-scroll, Stop. Save / Ctrl+S / Ctrl+Shift+S wired for real.
  - Verified headless: sample map → 270 KB bsp built + copied to tf/maps,
    vrad lump table streamed into the log panel.
- **Milestone C** — sub-object editing:
  - C.1 `map/BrushEdit` — welded vertex/edge/face handles from a solid's
    polygonised loops; drag on a screen-parallel plane with grid snap, then
    refit every touched face plane (Newell normal, keeps orientation). Top-bar
    Vertex/Edge/Face sub-mode switch; overlay handles in all four viewports;
    click empty space falls back to brush picking.
  - C.2 Texture / Face-edit tool: shift-click faces in any viewport (fill +
    outline overlay), Properties panel becomes a Face-edit sheet — material
    picker w/ thumbnail, Shift X/Y, Scale X/Y, Rotation, Lightmap scale,
    World/Face align, Fit/Top/Bottom/Left/Right/Center justify.
    `map/Solid` faceAlignWorld/faceAlignToFace/faceRotateUV/faceJustifyUV;
    `raySolidFace()`.
  - C.3 Clip tool — drag a cut line in a 2D view (plane ⟂ that view), Tab
    cycles keep-front/back/both, Enter applies. `Solid::clip(n,d,mat)`.
  - C.4 Hollow (`hollow()` — 6 AABB slabs) + Carve (`carve()` — convex
    subtraction into pieces) buttons in the brush inspector.
- **Milestone D** — entities:
  - D.1 `fgd/Fgd` — lexer + recursive-descent .fgd parser; resolves @include
    (base.fgd, halflife2.fgd), @PointClass/@SolidClass/@BaseClass headers,
    keys (type/display/default/help), choices + flags, input/output.
    `flattened()` expands bases in Hammer order + caches; 446 classes from
    tf.fgd (274 point / 98 solid).
  - D.2 `app/PropWidgets` — FGD-driven properties panel: typed widget per key
    (int/float/bool/choices→combo/flags→checkboxes/color→swatch+brightness/
    angles→vec3/target→entity dropdown/…), label-above-field layout, help
    tooltips, "Other keys (not in FGD)" catch-all, I/O connections editor
    (add/remove rows, output & target dropdowns).
  - D.3 entity catalogue browser (FGD point/solid classes, search) +
    place-on-grid + "tie to entity" for selected brushes.
  - D.4/D.5 entity helpers in every viewport: class-coloured wire box sized
    from FGD size(), I/O connection lines with arrowheads (hot when tied to
    the selection), facing tick from `angles`, decluttered labels.
  - D.6 doc-driven Contents/Outliner — live Entities + World-brushes lists,
    click-to-select (mirrors viewport), double-click to frame.
  - D.7 properties panel splits the class's own keys (promoted) from inherited
    "Shared keys" (collapsed); nothing hidden.
- **Milestone F** — Simple-mode kit is real:
  - `MapDocument::newBlank()` + `active()`; "New map" opens a blank editable doc.
  - `Editor::placePiece()` — every Build Kit card emits real brushwork/entities
    on the snapped grid: Floor/Wall/Room/Ramp/Route/Pillar/Ceiling brushes;
    RED/BLU spawn rooms (4×`info_player_teamspawn` + `func_regenerate`);
    Capture point (`team_control_point` + wired `trigger_capture_area` + pad);
    Payload track (chained `path_track`); Resupply; Health/ammo (medkit+ammo);
    Point/Spot/Sun lights.
  - `viewPlanePoint()` click-to-drop (ground plane in 3D, view plane in ortho),
    hold Shift to place several. `Solid::fromPlanes()` for wedges.
  - MAP CHECKLIST now reads the live document; all 5 rows tick as pieces land.
  - `--sample-map` / `--save-vmf` headless hooks: 22 solids + 15 entities →
    valid 37 KB VMF, checklist 5/5.

## Blockers / notes
- Build: PATH needs C:/Qt/Tools/mingw1310_64/bin + CMake_64/bin + Ninja.
  Kill PootisBuilder.exe before `ninja` (locked exe → ld error).
- Git identity is set locally in this repo (Pootis Builder / the user's email).
- BSPSource CLI: tools/bspsrc.bat uses `start` (detaches). For headless call
  `tools/bin/java -m info.ata4.bspsrc.app/info.ata4.bspsrc.app.src.BspSourceLauncher`
  directly. Existing decompiles for reference:
  `../Pootis Builder Qt/output/decompiled/*.vmf`.
- vbsp/vvis/vrad live at
  `C:/Program Files (x86)/Steam/steamapps/common/Team Fortress 2/bin/`.
  Game dir = `.../Team Fortress 2/tf`. hammer.bat / hammer++ for reference runs.
