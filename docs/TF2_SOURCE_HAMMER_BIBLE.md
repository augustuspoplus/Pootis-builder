# TF2, Source Engine, Art Direction & Hammer++ / TrenchBroom Reference Bible

> Permanent project memory & design reference for **Pootis Builder 2.0** (and all AI builders & independent review critics). Synthesized from Valve's *Illustrative Rendering in Team Fortress 2* (SIGGRAPH 2007), the Valve Developer Community (VDC), UEAKCrash's *How to Make TF2 Maps* series, TF2Maps.net, `r/hammer`, Hammer++, and TrenchBroom UX studies.

---

## 1. Team Fortress 2 Art Style & Illustrative Rendering (Valve SIGGRAPH 2007)
Valve engineered TF2's look around **instant combat readability** inspired by 1920s–1960s American commercial illustrators (**J.C. Leyendecker**, **Norman Rockwell**, **Dean Cornwell**):

- **Value & Saturation Hierarchy (Most Important Visual Rule):**
  - **Environments / Floors / Walls:** Low-frequency, painterly brushwork with **desaturated, quiet mid-values** so the world never competes with characters or combat effects.
  - **Characters, Pickups & Objectives:** High-contrast silhouettes and **saturated focal colors** (Health/Ammo, Intel, Bomb Cart, Control Points, RED/BLU mercs).
- **Half-Lambert Shading:**
  - Standard Lambert ($N \cdot L$ clamped at 0) creates harsh muddy dark sides.
  - Valve wraps light softly around surfaces: $\text{Half-Lambert} = ((N \cdot L) \times 0.5 + 0.5)^2$.
- **Warped Diffuse Ramp (`$lightwarptexture`):**
  - Pulls shadow sides toward **cool blue/purple ambient tones** instead of dead black, with a subtle **warm reddish/amber terminator** right at the light-shadow edge (classic oil-painting skin & form modeling).
- **Rim Lighting & Soft Cubemaps (`$envmap`):**
  - Subtle view-dependent rim highlights separate props and characters from dark corners.
  - Blurred stylized reflections produce broad painterly highlights instead of noisy photorealistic mirrors.
- **Implication for Pootis Builder 2.0 Rendering:**
  - Never let missing textures or unlit props fall back to harsh pitch-black or neon placeholders; always preserve warm-sun / cool-ambient TF2 contrast, soft Half-Lambert-like fill on props, and matched `env_fog_controller` + skybox harmony.

---

## 2. RED vs. BLU vs. Spytech Architectural Language
Team identity in TF2 comes from **architecture, materials, silhouette, and lighting** — not just slapping bright red/blue paint everywhere:

| Zone | Theme & Era | Materials | Silhouettes & Forms | Lighting |
| :--- | :--- | :--- | :--- | :--- |
| **RED** (*Reliable Excavation Demolition*) | Rustic, agricultural, frontier, domestic (barns, brick mills, mining shacks) | Warm weathered wood planks, aged red brick, rusted corrugated iron roofs | Pitched/gabled barn roofs, overhangs, asymmetrical lived-in timber shapes | Warm incandescent / amber lantern glows |
| **BLU** (*Builders League United*) | Corporate, modern industrial, heavy manufacturing (factories, refineries, yards) | Cool concrete, cinderblock, galvanized sheet metal, steel plates & I-beams | Boxy, orthogonal, industrial flat/sawtooth roofs, smokestacks, cranes | Cool white/cyan fluorescent overhead lights |
| **Spytech / Neutral Mid** | 1960s retro-futurist secret agent lair (James Bond / Googie / IBM mainframes) | Clean white grid tiles (`tile/floor_tile_006a`), charcoal concrete (`concrete/concretefloor008`), glass windows, server banks, subtle team trim (`imetal001` / `imetal002`) | Clean modular corridors, observation booths, overhead vents, industrial turbines | Crisp balanced indoor overhead lamps |

- **Guiding Lines:** Wall trims, ceiling beams, tracks, and subtle lighting pools subconsciously funnel players straight toward objectives without needing text arrows everywhere.

---

## 3. Exact TF2 Gameplay & Spatial Metrics (`1.0 Godot meter = 32 Hammer units`)

| Metric | Hammer Units | Godot Meters | Gameplay Meaning |
| :--- | :---: | :---: | :--- |
| Player Standing Hull | `48 × 48 × 83u` | `1.5 × 1.5 × 2.59m` | Minimum clearance for Heavy/all classes |
| Standing / Crouched Eye | `68u` / `45u` | `2.125m` / `1.406m` | Cover height checks & sniper windows |
| Max Walkable Stair Step | `18u` (use `8–12u`) | `0.56m` (`0.25–0.38m`) | Always smooth stairs with invisible `playerclip` ramp! |
| Max Walkable Slope | `45.57°` | `45.57°` | Steeper ramps block walking |
| Standard Doorway | `96–128u W × 128u H` | `3–4m × 4m` | Never build narrow HL2 doorways (TF2 is ~1.5x roomier!) |
| Standard Room Ceiling | `144–192u` | `4.5–6.0m` | Room for jumping & explosive fights |
| Standing / Crouch Jump | `48u` / `64u` | `1.5m` / `2.0m` | Basic ledge climb thresholds |
| Scout Double-Jump | `128u` | `4.0m` | Scout-exclusive flank height |
| Soldier / Demo Jump | `192–320u` | `6.0–10.0m` | High ground & rooftop perches |
| Fall Damage Threshold | `269u` | `8.4m` | Safe drop limit |
| Engineer Sentry Radius | `1100u` | `34.375m` | Sightline & choke lockdown radius |
| Sniper Sightline Warning | `> 2048u` | `> 64.0m` | Flag long oppressive sightlines in Map Coach |
| Class Speeds | `230–400 u/s` | `7.2–12.5 m/s` | Heavy `230`, Soldier `240`, Demo `280`, Sniper/Engi `300`, Scout `400` |

---

## 4. Source Engine Technical & Rendering Internals (Must-Get-Right Rules)
- **BSP v20 Pakfile ZIP (Lump 40):**
  - Official Valve, community, and Scream Fortress maps (e.g. `cp_degrootkeep_rats.bsp`, `cp_ambush_event.bsp`) pack custom `.vmt`, `.vtf`, and `.mdl` files inside the BSP Pakfile ZIP using **Method 0 (STORED)**, **Method 8 (DEFLATE)**, AND **Method 14 (LZMA)**! All three MUST be decompressed cleanly, and map-specific caches MUST reset when switching maps!
- **Valve Material System (`.vmt`):**
  - **`Patch` Shader:** Uses `"include" "materials/..."` plus `"replace"` / `"insert"` blocks to inherit from a base VMT while overriding `$basetexture`, `$color`, or `$envmap`. Must resolve recursively!
  - **`WorldVertexTransition`:** Blends `$basetexture` and `$basetexture2` using displacement vertex alpha (`COLOR.a` / blend weight) — critical for natural grass-to-dirt and rock-to-snow transitions!
  - **Alpha & Cutouts:** Respect `$alphatest` (alpha scissor), `$translucent` (alpha blend), `$nocull` (two-sided foliage/fences), and `$color` / `$color2` tinting without turning failed textures pitch-black.
- **Displacements:**
  - Always default to **Power 3** (`9×9` grid = 128 tris/face; Power 2 for small details). **Never use Power 4** (known Source compiler/lighting/crash hazard on `r/hammer`).
  - Support **Sew** on adjacent displacement edges so sculpted hills never tear open.
  - **Never** apply `tools/toolsnodraw` to a displacement face.
- **Optimization & Sealing:**
  - Structural `worldspawn` brushes seal the map against the void (0 leaks); small trim/stairs/details belong in `func_detail` (tied via `Ctrl+T`) so `vvis` stays fast.
  - Hidden exterior faces can use `tools/toolsnodraw` (seals without rendering).
  - Always snap vertices to **power-of-two integer Hammer grids** (`8, 16, 32, 64, 128u`) — off-grid floats cause micro-gaps and leaks!

---

## 5. Hammer++ + TrenchBroom UX Gold Standard (Target Feel for Pootis Builder 2.0)
Combine **TrenchBroom's effortless 3D direct manipulation** with **Hammer++'s TF2 precision** — while keeping our clean floating TF2 HUD:

1. **Proactive 3D Hover & Smart Selection:**
   - Hovering ANY solid, wall, prop, or entity outlines it immediately before clicking.
   - Smart raycast prioritizes props/entities & smaller objects over massive floor slabs underneath.
   - `Click` selects, `Ctrl+Click` multi-selects, `Esc` deselects.
2. **Instant Editing, Dragging & Deleting:**
   - **`Del` / `Backspace`:** Instantly deletes selected brush(es), wall(s), prop(s), or entity(ies) (fully Undoable via `Ctrl+Z`!).
   - **Direct 3D Face-Pull Dragging:** Grab & drag any of the 6 glowing 3D Face-Pull arrows on a selected brush (or **`Shift+Drag`** any face TrenchBroom-style!) to stretch/shrink walls, floors, and roofs live snapped to grid.
   - **Direct 3D Move / Rotate Gizmos & `Shift+Drag` Clone:** Drag props/entities/brushes along axes, `Shift+Drag` or `Ctrl+D` to duplicate cleanly, `R` to rotate 90°, arrow keys to nudge by 1 grid step.
   - **`[` / `]` Live Grid Size:** Instantly halve/double snap size (`8u ↔ 16u ↔ 32u ↔ 64u ↔ 128u`) with live grid readout on the HUD.
3. **Essential Hammer Power-Tools (Simplified & Visual):**
   - **Clip / Slice Tool (`Shift+X`):** Cleanly split any brush along a cut plane (Keep Both / Front / Back) — far cleaner than Hammer's messy Carve tool!
   - **Visual Face Edit & Material Browser (`Shift+A`):** Live VPK texture swatches (not plain text!), searchable, `Alt+Click` Eyedropper, per-face paint, UV Scale/Shift/Rotate/Fit, plus **Dev Measure Grid** blockout textures (`dev/dev_measuregeneric01`, RED/BLU measure).
   - **Visual 3D Prop Browser:** Rendered 3D prop preview thumbnails + search + quick random yaw/scale.
   - **Tie to Entity (`Ctrl+T`) & Entity Inspector (`Alt+Enter`):** Compact docked TF2 inspector (no modal popups!) to change brush entity type (`worldspawn`, `func_detail`, `func_door`, `func_water`, `trigger_*`), Team (`RED`/`BLU`), Skin, Targetname, and I/O connections.
   - **VisGroups Quick-Toggle:** 1-click checkboxes to toggle visibility of **Triggers**, **Player Clips**, **Props**, **Lights**, **Logic Wires**, and **Skybox Shell**.
   - **Map Problem Checker (`Alt+P` / Map Coach):** Checks sealing, invalid brushes, spawn balance, health/ammo coverage, spawn-to-mid walk times, and >2048u Sniper sightlines with 1-click Auto-Fix.

---

## 6. Independent Multi-AI Critic Rubric (Anti-Confirmation-Bias Standard)
Every major milestone is reviewed cold by independent AI critics (e.g. **Claude 5.5** + **Gemini 4 Argon**) who grade **0–10** across 5 strict pillars (target: **9+/10 on all 5**):
1. **Official `.bsp` Visual Fidelity:** Zero missing grey walls, zero black props, proper `Patch` VMTs, `WorldVertexTransition` terrain blends, and crisp alpha cutouts across Valve, Scream Fortress, and community maps (`cp_degrootkeep_rats`, `cp_ambush_event`, `sd_doomsday`, `pl_upward`, `ctf_turbine`, `mvm_decoy`).
2. **`F5` Playtest Feel & Reliability:** Immediate working WASD + mouse look + jump + crouch-jump + rocket-jump + `V` noclip on BOTH custom and official `.bsp` maps with zero focus traps or stuck spawns.
3. **3D Pointing, Selecting, Dragging & Deleting:** Effortless hover highlight, click-to-select anything, instant `Del` removal, draggable Face-Pull & Move gizmos, `Shift+Drag` clone, `[`/`]` grid snap, `Shift+X` Clip.
4. **UI Polish & Completeness:** Real visual VPK texture swatches & 3D prop thumbnails, zero overlapping toasts/overlays, clean Official Map mode (no stray Build ghosts!), sleek docked Selection & Entity Inspector, authentic TF2 fonts/palette/SFX.
5. **Real-World TF2 Map Creation Proof:** Rebuilt iconic maps (`ctf_turbine` full interior + `koth_viaduct` / `ctf_2fort`) built strictly with Pootis Builder's own tools, compiled cleanly via real Valve `vbsp + vvis + vrad` (0 leaks), and visually verified side-by-side against Valve's originals.
