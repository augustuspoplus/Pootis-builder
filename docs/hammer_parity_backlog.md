# Pootis Builder 2.0 — Valve Hammer++ & TF2 Feature Parity Backlog

> Living engineering roadmap used by `scripts/self_review_loop.ps1`, `/schedule`, and `/teamwork` self-improvement runs.  
> Every autonomous cycle picks the highest-priority `[ ]` item, implements it, and verifies **0 test failures + 0 Valve BSP leaks + live GPU UI pass**.

---

## Shipped Core Parity (Milestones 1–45)
- [x] **Native C++20 VPK/BSP/MDL/VTF/FGD Reader** (29,669+ VPK textures, 16,697+ `.mdl` models, 452 FGD classes from `tf.fgd` + `tf-abs.fgd`)
- [x] **Real Valve SDK Compiler Pipeline** (`vbsp.exe`, `vvis.exe`, `vrad.exe`, 3D Leak Laser, Auto-Seal Skybox, VAC-safe `-insecure +sv_lan 1` launch)
- [x] **Brush Geometry & Hammer++ Tools** (Drag Box, Chained Walls, Ramps, Open-Back Stairs, Arches, Make Hollow, Interactive 3D Clip Plane `Shift+X`, Vertex Edit `Shift+V`, Multi-Solid Marquee Select, Group Rotate `R`, Drop-to-Floor `End`, 3D Spline Fences/Catwalks)
- [x] **Vertical Cliffs & Displacements** (Power-3 cliffs, Face Normal sculpting, WorldVertexTransition alpha paint, Auto-Sew Seams, Subdivide)
- [x] **Face Edit & Drag-and-Drop Materials (`Shift+A`)** (UV Scale/Shift/Rot, Lightmap Scale, Fit/Justify, World/Face Align, Auto-Biome, Map-Wide Replace)
- [x] **Live Lighting Studio (`F3`)** (Daylight / Lit Interior / Fullbright, 4-component `_light`, real `SpotLight3D` cones, 1-click TF2 light presets)
- [x] **Visual 3D Entity I/O Wiring (`Shift+W`)** + 4-Tab SmartEdit Inspector (`Alt+Enter`) + Official BSP Remix (`BSPSource`)
- [x] **Live `F5` TF2 Playtest Sandbox** (6 classes, rocket jumping, sliding `func_door`, Payload Cart spline + healing, Control Point capture, CTF Intel pickup & capture, Rollout Stopwatch, Live Playtest Radar `M`)
- [x] **TF2 Level-Design Analysis Tools** (`Alt+P` Balance Analyzer, `Alt+S` 360° Sniper Sightline Heat-Rays, `Alt+R` 3D TF2 Tape Measure & Jump Ruler, `M` Corner Radar, Live Diagnostics & `Turbo/Balanced/Ultra` FPS Tuner)
- [x] **Onboarding & Hybrid AI** (Interactive Guided Tutorials `F1`, 5-Provider AI Map Architect `Ctrl+J`, 9-Map Official Valve TF2 DNA Corpus `tf2_design_dna.json`, 100-Pt Auto-Scorer & AI Model Arena Leaderboard)

---

## Prioritized Next Upgrades (Hammer++ / TrenchBroom / TF2 Excellence)

### P0 — Highest Impact Next
- [ ] **`func_detail` Auto-Optimizer & Hint/Skip Assistant:** Automatically detect small/angled/stair/catwalk brushes and offer 1-click conversion to `func_detail` (massive `vvis.exe` compile speedup on real Valve TF2 maps, just like Hammer++ best practices).
- [ ] **Cordon Bounds Compile Mode (Hammer++ Parity):** Let mappers draw a 3D Cordon Box around just one room/choke to compile & test a slice of a huge map in <2 seconds with automatic temporary skybox sealing.
- [ ] **Real-Time TF2 Soundscape & Ambient Audio Previewer:** Browse mounted `sound/` VPK clips (`ambient_generic`, `env_soundscape`) and play real Valve TF2 ambient sounds directly in the editor & `F5` playtest.

### P1 — High-Value Studio & Hammer++ Tools
- [ ] **Automatic `env_cubemap` Placer & Reflections Helper:** 1-click placement of `env_cubemap` nodes at eye height (`+64u`) across every room/courtyard so specular metal/glass materials look authentic in compiled TF2.
- [ ] **VisLeaf / Portal Preview (`Load Portal File .prt`):** Parse Valve `vbsp`'s `.prt` portal file and render 3D blue visleaf lines right inside the viewport so mappers can visually optimize TF2 FPS like pro Valve level designers.
- [ ] **Lightmap Grid Density Overlay (`Shift+L`):** Render Hammer++'s iconic checkerboard lightmap luxel density overlay onto brushes so users can tune Lightmap Scale (`4`–`128`) visually before running `vrad.exe`.
- [ ] **AI-Generated MvM `.pop` Wave Designer & Robot Path Preview:** Let the AI Architect generate complete multi-wave Mann vs. Machine `.pop` files (`T_TFBot_Giant_*`, Tanks, Support Spies/Snipers) synced with `spawnbot` markers.

### P2 — Advanced Mapping & Multi-Model Ecosystem
- [ ] **Live Online Multi-Model Arena Bake-Off:** Send the same prompt in parallel via `HTTPRequest` to Gemini + Claude + GPT + Ollama simultaneously, compile each winner with real `vbsp.exe`, and track ELO ratings in `leaderboard.json`.
- [ ] **Instanced Prefabs (`func_instance` Parity):** Edit a reusable cover/doorway/pillar instance once and propagate updates to every copy across the map.
- [ ] **3D Skybox Camera (`sky_camera`) Studio:** Dedicated 1/16th-scale 3D skybox builder with live 16× preview around the playable arena.
