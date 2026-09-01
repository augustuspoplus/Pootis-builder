# Progress log (autonomous overnight build)

Newest first. See ROADMAP.md for the plan. Q1 = auto-decompile .bsp on open.
Q2 = Simple-mode kit builds new maps (prioritised). Also doing section G (QoL).

## Now / next
- **Milestones A–F + D + C are all done.** Remaining roadmap: section **G**
  (QoL — autosave/backups, undo history panel, map-check, Ctrl+K command
  palette, prefab library, instances, cordon, measure tool, visgroups,
  groups, .pbproj, bspzip packing, camera bookmarks, snap presets, log
  panel, favourites, keybinds, tutorial) and the visual-fidelity parallel
  track (prop MDL rendering, displacements, blend materials).
- Optional polish: iconsprite/model rendering for point entities (boxes +
  tags today); entity thumbnail in the catalogue header.

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
