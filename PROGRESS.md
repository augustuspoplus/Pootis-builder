# Progress log (autonomous overnight build)

Newest first. See ROADMAP.md for the plan. Q1 = auto-decompile .bsp on open.
Q2 = Simple-mode kit builds new maps (prioritised). Also doing section G (QoL).

## Now / next
- **Milestone A, step 1**: `map/Vmf` parser + `map/Solid` (plane polygonisation).
  Then MapDocument + render + ray-pick select.

## Done
- (baseline) BSP loader (LZMA/HDR/v19-21), textured+lightmapped renderer,
  VPK/VMT/VTF pipeline, Simple/Pro UI shell, welcome screen, UI scaling.
- Scheduled 3-hourly continuation cron (session-only, job e9af0746).

## Blockers / notes
- Build: PATH needs C:/Qt/Tools/mingw1310_64/bin + CMake_64/bin + Ninja.
  Kill PootisBuilder.exe before `ninja` (locked exe → ld error).
- BSPSource CLI: tools/bspsrc.bat uses `start` (detaches). For headless call
  `tools/bin/java -m info.ata4.bspsrc.app/info.ata4.bspsrc.app.src.BspSourceLauncher`
  directly (or find the cli entrypoint). Existing decompiles for reference:
  `../Pootis Builder Qt/output/decompiled/*.vmf`.
