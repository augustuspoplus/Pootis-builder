# Progress log (autonomous overnight build)

Newest first. See ROADMAP.md for the plan. Q1 = auto-decompile .bsp on open.
Q2 = Simple-mode kit builds new maps (prioritised). Also doing section G (QoL).

## Now / next
- **Milestone B**: transform gizmo (vendor ImGuizmo) + Block tool (drag box) +
  grid snap on transforms + inspector X/Y/Z·W/D/H fields + undo/redo command
  stack. Then a doc-driven Outliner (current one still reads the BSP path).

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

## Blockers / notes
- Build: PATH needs C:/Qt/Tools/mingw1310_64/bin + CMake_64/bin + Ninja.
  Kill PootisBuilder.exe before `ninja` (locked exe → ld error).
- BSPSource CLI: tools/bspsrc.bat uses `start` (detaches). For headless call
  `tools/bin/java -m info.ata4.bspsrc.app/info.ata4.bspsrc.app.src.BspSourceLauncher`
  directly (or find the cli entrypoint). Existing decompiles for reference:
  `../Pootis Builder Qt/output/decompiled/*.vmf`.
