# Progress log (autonomous overnight build)

Newest first. See ROADMAP.md for the plan. Q1 = auto-decompile .bsp on open.
Q2 = Simple-mode kit builds new maps (prioritised). Also doing section G (QoL).

## Now / next
- **Milestone D**: FGD parser (`bin/tf.fgd` + bundled `tf-abs.fgd`) → entity
  catalogue; place point/brush entities; FGD-driven properties panel (plain
  labels, collapsible groups, typed widgets, nothing removed, live preview);
  entity I/O connections editor; entity sprites/helpers in the viewports.
- Then **Milestone C** (sub-object editing), interleaving **G** QoL items.
- Doc-driven Outliner rewrite still pending (reads the BSP path).

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
