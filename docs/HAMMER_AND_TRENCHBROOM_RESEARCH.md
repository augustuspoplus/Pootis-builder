# Hammer, Hammer++, TrenchBroom, UEAKCrash & `r/hammer` UX Research

> Permanent deep-dive research log stored in `pootis builder/docs/` so every session and AI critic remembers the exact tool mechanics, hotkeys, pain points, and workflow habits of real TF2 / Source Engine mappers.

---

## 1. UEAKCrash — *"How to Make TF2 Maps"* Playlist Lessons
Key foundations taught to virtually every modern TF2 mapper:
- **Setup & Resource Packs:** Beginners immediately install **A Boojum Snark's Ultimate Mapping Resource Pack** (curated TF2 prop library, gamemode prefabs, FGD upgrades, lighting/skybox reference) because vanilla Hammer's raw 30,000+ material & 16,000+ model lists are overwhelming. *(Pootis Builder 2.0 already mounts ABS MRP + all 8 TF2 VPKs automatically!)*
- **Blockout / Grayboxing First (`a1` → `a2`):**
  - Build core scale, sightlines, chokes, height advantage, and spawn-to-mid timing with **Dev Measure Grid textures** (`dev/dev_measuregeneric01`, RED/BLU measure grids) before detailing.
  - Drop a **player scale reference** (`72u–83u` tall Heavy/merc silhouette) into rooms early so doorways (`96–128u W × 128u H`), corridors, and ceilings (`144–192u`) never feel cramped.
  - Test early & often (`a1` playtest) — fast iteration beats spending 3 weeks detailing a broken layout.
- **Core Geometry Rules:**
  - Respect the **power-of-two grid** (`8, 16, 32, 64, 128u`); off-grid floating coordinates cause micro-gaps and leaks.
  - Keep **stairs smooth** (`8–12u` rise, `<= 18u` max step, always covered by an invisible `tools/toolsplayerclip` ramp so players glide instead of bouncing).
  - Build **doors** as `func_door` paired with `trigger_multiple` and `filter_activator_tfteam` for team-locked spawn doors.
  - Build **water** with a water material ONLY on the top face and `tools/toolsnodraw` on the other 5 faces.
- **Optimization & Lighting Habits:**
  - Structural `worldspawn` brushes seal the map; decorative trim/pillars/stairs become **`func_detail`** (`Ctrl+T`) so `vvis` stays fast.
  - Hidden exterior faces get `tools/toolsnodraw` (seals without rendering).
  - Match `light_environment` sun pitch/yaw/color + `env_fog_controller` to the chosen Valve skybox; never leave maps fullbright or pitch-black.

---

## 2. Valve Hammer Editor — Exact Core Tools & Muscle-Memory Hotkeys
Real Source mappers live on these shortcuts — supporting them alongside simple clickable TF2 buttons lets beginners click easily while veterans fly:

| Hotkey | Hammer Tool / Action | Exact Behavior Mappers Expect |
| :--- | :--- | :--- |
| **`Shift + S`** | Selection / Pointer Tool | Hover highlights object, Left-Click selects, `Ctrl+Click` multi-selects, `Esc` deselects |
| **`Shift + B`** | Block / Brush Tool | Drag footprint + height on grid, press `Enter` (or click) to create solid |
| **`Shift + X`** | Clipping Tool | Draw cut line across selected brush; press `Shift+X` repeatedly to cycle **Keep Both / Keep Front / Keep Back**; `Enter` executes cut |
| **`Shift + V`** | Vertex Edit Tool | Shows white vertex & yellow midpoint handles; drag vertices to make slopes/ramps/wedges without leaving concave errors |
| **`Shift + A`** | Face Edit Sheet (Texture App) | Click individual brush faces (`Ctrl+Click` multi-face); **Alt+Right-Click** wraps/aligns texture seamlessly across adjacent angled faces; **Eyedropper** picks material; UV Scale / Shift / Rotation / Fit / Justify |
| **`Shift + T`** | Apply Current Texture | Instantly paints all faces of selected brush(es) |
| **`Shift + Drag`** | Quick Clone / Duplicate | Leaves original in place and drags a snapped duplicate on the grid |
| **`Del` / `Backspace`** | Delete Selection | Immediately removes selected solid(s), wall(s), prop(s), or entity(ies) cleanly (100% undoable!) |
| **`[` / `]`** | Grid Size Down / Up | Halves/doubles integer Hammer grid (`1 ↔ 2 ↔ 4 ↔ 8 ↔ 16 ↔ 32 ↔ 64 ↔ 128u`) |
| **`Shift + W`** | Toggle Grid Snap | Temporarily toggle grid snapping (`Alt+Drag` for free movement) |
| **`Arrow Keys`** | Grid Nudge | Moves selected object(s) by exactly 1 grid unit per tap |
| **`Ctrl + T`** | Tie to Entity | Converts selected brush(es) into `func_detail` (default), `func_door`, `trigger_*`, `func_water`, etc. |
| **`Alt + Enter`** | Object Properties | Opens selected entity's KeyValues, Flags, Model/Skin, and Inputs/Outputs inspector |
| **`Alt + P`** | Check for Problems | Scans for leaks, invalid/degenerate brushes, missing spawns, off-grid vertices, duplicate IDs |
| **`Shift + Z`** | Maximize Active Viewport | Toggles focused 3D view vs 2D/Blueprint views |

---

## 3. What Hammer++ Fixed (Why TF2Maps.net Swears By It)
1. **Real-Time 3D Lighting & Shadow Preview** — No more "blind mapping" waiting for `vrad` just to check brightness or sun direction.
2. **Modern 3D Transform Gizmos** — Click-and-drag X/Y/Z **Move arrows**, **Rotate rings**, and **Scale/Face-Pull handles** directly inside the 3D viewport instead of fighting 2D orthographic views.
3. **Smart Selection Outlines & Glows** — Clear visual highlight on hovered & selected objects so you stop accidentally selecting the giant 2048u floor underneath a crate or doorway!
4. **Accurate Prop, Material & Particle Previews** — Real `.mdl` props, live texture thumbnails, color pickers (`C`), and overlay preservation when clipping.
5. **Rock-Solid Undo/Redo & Searchable Browsers** — Instant autocomplete search for textures, models, entity classes, and I/O outputs.
6. **Cordons & VisGroups** — Toggle Triggers, Player Clips, Props, Lights, Skybox, and Detail brushes on/off cleanly, or Cordon-box one room to compile in 1 second.

---

## 4. What TrenchBroom Does Even Better Than Hammer++ (`r/hammer` Consensus)
Mappers on `r/hammer` constantly praise **TrenchBroom** for feeling like "digital clay" instead of 1990s CAD:
1. **3D-First Direct Manipulation:** Hold **`Shift + Drag` directly on ANY brush face** in 3D to push, pull, or extrude it immediately — no hunting for menus or typing numbers!
2. **Docked Inspector Panels (Zero Modal Pop-Up Dialogs):** Entity properties, material picker, and object actions live cleanly docked at the edge of the screen — never blocking the 3D view with stacked Windows 98 dialog boxes.
3. **Proactive Hover Feedback:** Moving the mouse across the 3D scene immediately highlights the exact face, brush, or entity you are pointing at before you even click.
4. **Mathematically Safe Geometry:** Automatically prunes degenerate sliver planes and prevents accidental concave/broken brushes while dragging.

---

## 5. Top `r/hammer` Beginner Pitfalls Pootis Builder 2.0 Must Prevent Automatically
1. **Never Recommend Destructive "Carve" Slivers:** Hammer's raw Carve creates broken micro-brushes and leaks. Offer clean **Clipping (`Shift+X`)** AND ensure our Doorway Carve automatically prunes sliver planes (< 1 sq Hammer unit) so `vbsp.exe` never hits `FloatPlane: bad normal`.
2. **Eliminate Off-Grid Decimal Gaps:** Always snap brush coordinates cleanly to integer Hammer units on save/drag so microscopic 0.1u gaps never cause leaks.
3. **Eliminate the "Mystery Leak":** Provide **1-Click Auto-Seal Skybox** + glowing **3D Red Leak Laser** directly from `.lin` pointfiles.
4. **Protect Displacements:** Default to **Power 3** (never Power 4 which crashes Source compilers!), support **Sew** across adjacent edges, never apply `tools/toolsnodraw` to displacements, and support `WorldVertexTransition` dual-texture alpha blending.
5. **Protect Entity & Prop Visuals:** Never let a packed/compressed BSP asset or `Patch` VMT silently turn into a grey wall or pitch-black prop — decompress STORED + DEFLATE + LZMA Pakfile entries and resolve `"Patch"` inheritance cleanly!
