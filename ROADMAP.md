# Pootis Builder — roadmap to a usable editor

Status as of this commit: the app **loads and renders** any TF2 `.bsp` (textured +
lightmapped, LZMA + HDR), has the Simple/Pro shell, welcome screen and UI scaling.
It is still a **viewer** — there is no editable geometry yet. Everything below is
about closing that gap.

## Decisions taken (override any of these if you disagree)

1. **Editing an existing map = decompile it to VMF** with the bundled BSPSource,
   then edit the VMF. This is approximate (compiled BSPs drop brushwork) but it's
   the only real path. A raw `.bsp` still opens instantly as a *view*; an explicit
   **"Decompile to edit"** action produces the editable version.
2. **Native save format = `.vmf`** (Hammer-compatible, compiles with Valve's
   vbsp/vvis/vrad).
3. **Undo/redo = command stack** (each edit is a reversible command).
4. **Transform gizmo = vendored ImGuizmo** (MIT, ~2 files).

## Answered

- **Q1 → auto-decompile every `.bsp` on open** into editable brushes (BSPSource
  in the background). Keep a spinner/progress; big maps take a few seconds.
- **Q2 → prioritise the Simple-mode kit building new maps.** The shared editing
  model still comes first (both modes need it), then the kit gets wired to emit
  real brushwork before deep sub-object tooling.
- Do more than 3D editing — see section **G** for quality-of-life features.

## Milestones

### A — Editable document + selection  ← in progress
- `map/Vmf` — parse Valve VMF (world solids, entities, connections, dispinfo).
- `map/Solid` — brush = set of planes; polygonise (plane-intersection → faces
  with ordered verts); bounds; transform.
- `map/MapDocument` — solids + entities + selection + undo stack.
- Render editable solids (reuse SceneRenderer batching + MaterialLibrary).
- Ray-pick in any viewport → select a solid; highlight it.
- Open `.vmf` directly; open `.bsp` → offer "Decompile to edit".

### B — Transform + block tool
- ImGuizmo move/rotate/scale in the 3D view; handles + drag in the 2D views.
- Grid snapping on every transform.
- Block tool: drag a box in a viewport → new brush.
- Delete / duplicate / clone; the inspector X/Y/Z · W/D/H fields (drag-scrub + type).

### C — Sub-object editing
- Object / Vertex / Edge / Face modes; drag with snapping.
- Face: assign material, shift/scale/rotate UVs (the Texture tool).
- Clip, hollow, carve.

### D — Entities
- FGD parser (`bin/tf.fgd` + bundled `tf-abs.fgd`) → entity catalogue.
- Place point/brush entities; FGD-driven properties panel; entity I/O editor.
- Entity sprites/helpers in the viewports.
- **Properties panel UX** (applies to brushes + entities): plain-language field
  labels and inline help from the FGD, grouped into collapsible sections, common
  fields promoted to the top, "advanced" fields tucked below — but nothing
  removed. Every field typed (enum → dropdown, flags → checkboxes, color →
  swatch+picker, angles → dial, material/model → picker with thumbnail,
  target → entity dropdown). Live preview of the change in the viewport.

### Everything gets a preview
Design rule for the whole UI: every pickable thing shows what it is before you
commit. Textures + models already have thumbnails; extend to entities (sprite/
model preview), prefabs (rendered thumbnail), kit pieces (mini 3D preview),
sky/fog/lighting presets (preview swatch), colors (swatch), and a hover preview
in every list.

### E — Save, compile, play
- VMF writer.
- Run `vbsp`/`vvis`/`vrad` with a live log panel; fast + final profiles.
- Launch TF2 `-insecure +sv_lan 1 +map <name>`.

### F — Simple-mode kit is real
- Kit pieces (Floor/Wall/Room/Ramp/Route) emit real brushwork.
- Map checklist reads the live document; one-click "add spawn room" etc.

### Parallel — visual fidelity
- prop_static MDL/VVD/VTX rendering (props are boxes now).
- Displacement geometry.
- `$basetexture2` blend materials.

### G — Beyond editing: quality-of-life (interleave with A–F)
- **Autosave** + rolling `.vmf` backups; crash-recovery on next launch.
- **Undo history panel** (jump to any past state).
- **Map check** (Hammer's "check for problems"): invalid/duplicate brushes,
  leaks, entities with dangling I/O targets, missing materials/models, no
  spawns, no light, out-of-bounds geometry — clickable results.
- **Command palette** (Ctrl+K): every action, entity, texture by name.
- **Prefab library** — the ABS pack ships ~60 prefab VMFs; drop-in placement.
- **Instances** (func_instance / VMF instance) with in-place edit.
- **Cordon** — compile/preview only a boxed region.
- **Measure tool** + live dimensions on drag in every view.
- **Visgroups / layers** with show/hide/lock; auto-visgroups by class.
- **Groups** (group/ungroup, nested).
- **Project files** (`.pbproj`) bundling the vmf + camera bookmarks + build
  settings + custom-content list.
- **Custom content packing** (bspzip) on compile.
- **Camera bookmarks**; "go to coordinate".
- **Snap presets** (grid + angle), per-view.
- **Log / console panel** for compile output and editor messages.
- **Asset favourites** — pin textures/models/entities.
- **Keybind customisation**.
- **Simple-mode tutorial** — 3-step interactive first-map walkthrough.
- **In-editor changelog / tips** on the welcome screen.

### H — External 3D model import (do LAST, after A–G)
Import meshes in common formats (OBJ, glTF/GLB, FBX, STL, DAE, PLY) directly
into the editor. Options: (a) reference as a prop, converting to Source
MDL on compile via studiomdl, or (b) drop as `func_brush`/`func_detail` display
geometry. Uses a vendored importer (assimp, or cgltf + fast_obj + a small FBX
reader). Preview in the asset browser; place like any prop; pack the source
mesh + generated MDL into the bsp on build.

## "Good state" bar
Milestones **A + B + E** = open a map, move/add/delete brushwork, save, and test
it in-game. C, D, F + G turn it into a genuine Hammer replacement and then some.
H is the stretch goal once the rest is solid.
