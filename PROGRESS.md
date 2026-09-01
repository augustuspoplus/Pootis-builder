# Progress log (autonomous overnight build)

Newest first. See ROADMAP.md for the plan. Q1 = auto-decompile .bsp on open.
Q2 = Simple-mode kit builds new maps (prioritised). Also doing section G (QoL).

## Now / next
- **Milestone E**: run vbsp/vvis/vrad on the saved VMF with a live log panel
  (fast/final profiles), then launch TF2 `-insecure +sv_lan 1 +map <name>`.
  This closes the "good state" bar (A + B + E = open, edit, save, playtest).
- Then **Milestone D** (FGD parser + entity catalogue + FGD-driven properties
  panel), **Milestone C** (sub-object editing), interleaving **G** QoL items.
- Doc-driven Outliner rewrite still pending (reads the BSP path).

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
