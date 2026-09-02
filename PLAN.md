# Pootis Builder — next: five gaps to 1.0

The original roadmap (ROADMAP.md, milestones A–H) is essentially spent: A–F, C, D
are done, most of section G is done. The app **loads any TF2 `.bsp` faithfully**
and **builds a greybox fast**. It is not yet a tool you'd finish a shippable map
in. Five gaps stand between here and there, and they are **gated** — finish one
before starting the next, because each is the ground the next stands on.

Shareable version of this plan (status grid + rationale):
https://claude.ai/code/artifact/b0d70464-a7af-46ab-bda2-cd76ab3cb6e5

## Where it stands (HEAD 63ab736)

| System | State |
| --- | --- |
| BSP viewer & renderer (textures, lightmaps, HDR, LZMA, props, displacements) | solid |
| Decompile → editable VMF (BSPSource, lossy) | works |
| Simple-mode kit (52 pieces, options, drag+ghost, 7 templates, checklist) | solid |
| Save · compile · play (`vbsp/vvis/vrad`, live log, `+map`, `bspzip`) | works |
| Transforms (gizmo + 2D handles + body-drag + grid snap) | thin — no keyboard G/R/S, no numeric, no snap-to-vertex |
| Brush-entity editing | **blocked** — "editing is limited for now"; real maps are mostly brush entities |
| Sub-object vertex/edge/face | thin — Pro-only, one solid at a time |
| Texture / UV tool | thin — approximate UV basis, no `$basetexture2`, no lightmap workflow |
| Displacements | view only — no sculpt / sew / alpha paint / create |
| Quality-of-life (autosave, history, map-check, palette, prefabs, cordon, visgroups, .pbproj) | deep |

## The five phases

### Phase 1 — Edit any brush, anywhere
Real maps are 60%+ brush entities; right now they're second-class.
- Mixed world + entity brush selections behave identically for transform / delete /
  duplicate / clip / hollow / carve.
- Grouping + visgroups work across entity boundaries.
- Vertex/edge/face editing works on an entity's brush.
- One-key tie-to-entity / move-to-world with a class picker; keyvalues + I/O survive.
- Remove the "brush-entity editing is limited" message — its absence = phase shipped.
- **Done when:** open decompiled `cp_process_final`, move a `func_detail` wall, reshape a
  trigger, retie a brush — no dead ends.

### Phase 2 — Precise transforms
Everyday editing feel. No way to say "move it exactly 64 on X".
- Keyboard ops: `G`/`R`/`S`, then `X`/`Y`/`Z` to constrain (Shift+axis = plane), type a
  number, Enter commits, Esc cancels. Thin op layer over the existing transform code.
- Live numeric readout during any drag (delta + absolute), editable inline.
- Snap targets: grid (have it) + vertex / edge-midpoint / face-centre of other brushes;
  "snap selection to grid".
- 2D views as first-class editing surfaces: draw a brush by corners with live dims, drag
  an edge to a typed value, box-select, typed block-tool depth.
- Rotate/scale about a chosen pivot (selection centre / cursor / picked point).
- **Done when:** build a room to exact dimensions entirely in the 2D views.

### Phase 3 — Surfaces
A map's look is 90% surfaces; the texture tool is rough and displacements are read-only.
- Face-edit tool on a correct UV basis: world/face align that holds under rotation,
  fit / centre / justify, per-face lightmap scale, smoothing groups, "treat as one".
- Blend materials: paint `$basetexture2` alpha on a face or displacement, live preview.
- Displacement editing: create from a face (power 2/3/4); raise / lower / smooth / noise
  with falloff; sew to neighbours; paint alpha; subdivide. Sculpt in 3D, numeric in 2D.
- Material browser filtered to in-map + full VMT search, themed grouping like the models.
- **Done when:** retexture a room, blend two ground materials, reshape a hillside — all
  in Pootis Builder.

### Phase 4 — Simple ↔ Pro, one document
Simple is expansive; the seam to Pro is abrupt and "everything previews" is half-true.
- A kit piece stays a live, re-optionable object until "bake to brushes"; option panels
  persist across a mode switch.
- Pro's outliner lists those pieces with parameters editable.
- Finish the preview rule: rendered thumbnails for entities / prefabs / sky-fog-light
  presets; hover-preview in every list; kit cards with a mini 3D preview.
- The 3-step guided first map in Simple mode.
- **Done when:** a beginner starts in Simple, grows into Pro on the same map, never hits
  "you can't edit that here".

### Phase 5 — Ship it
The compile-test loop and content pipeline aren't fast/trustworthy enough yet.
- Iteration loop: tuned fast-compile profile, changed-leaves-only where possible, auto
  `+map` reload of the running game, compile-time budget shown.
- Map check that catches real problems: leak → draw the line to the hole and frame it;
  pointfile load; hint/skip suggestions; nodraw-the-void; dangling entity I/O; missing
  assets with a fix button; displacement errors.
- Content packing: every referenced custom material/model/sound auto-detected and
  `bspzip`'d in, with a review list.
- Workshop publish end-to-end: thumbnail, description, tags, changenote, real upload,
  tested against an actual submission.
- **Done when:** decompile → edit → compile → play → publish, no step back to Valve's tools.

## Runs alongside (ships in small pieces on top of the active phase)
- **Fidelity:** `$basetexture2` in the viewport, soundscape / particle / `env_cubemap`
  helpers, a water plane, a 3D-skybox scale-linked preview.
- **The turbine bar:** keep rebuilding `ctf_turbine` from the kit until a side-by-side with
  the decompile is genuinely hard to call. The honest integration test.
- **Stability:** `./test.sh` green on every commit; crash-recovery from autosave exercised.

## Not now
- FBX / glTF import beyond OBJ — vendored-importer rabbit hole; after 1.0.
- VScript / a visual I/O graph — keyvalue + connections editor is enough to ship a map.
- Hammer++ instance depth (parameters, manifest maps) — basic `func_instance` is in.
- Other Source games — TF2 FGD/content paths are wired throughout; post-1.0 refactor.
- Real-time collaboration — not a solo-mapper need.

## The 1.0 bar (one sentence)
Decompile `cp_process_final`, fix a sightline, retexture a room, adjust a displacement,
pack it, compile it, and **play it** — without opening Hammer once.

---

# UI plan — one workspace

Companion to the phases above. Shareable version (with layout diagrams):
https://claude.ai/code/artifact/e26c3dca-fabd-4152-8425-82ffd9053980

Today Simple and Pro are two different apps on one engine — different panels, different
layout, jarring switch. Every phase above would be built twice or pick a side. Fix:
**one adaptive workspace with a complexity dial, not a mode switch.**

## Foundation (do first — gates every phase)
- **One inspector component.** World brush, entity, face, kit piece, displacement — all
  render in the same panel: identity header (+ `part of: func_detail #12` line), context
  sections, every field typed (reuse `app/PropWidgets` as the universal field kit),
  promoted/advanced split, live viewport preview. Nothing removed.
- **Panel grammar.** Every panel = header (title + overflow) · optional filter row ·
  scroll body · optional footer action. The floating windows (Options, Compile, Publish,
  Import) become docked panels under this grammar.
- **Semantic colour, separate from the orange accent.** good / warning / critical triad
  for map-check severity, field validation, compile status — encoded by shape + label too.
- **Shortcut registry.** Every control shows its key (tooltip min); F1 sheet + command
  palette generated from the same registry so they can't drift.

## One workspace (the core move — ships with Phase 4)
- **3-stop complexity dial:** Guided · Standard · Full. Shows/hides panels + advanced
  fields; does NOT load a different app. Map, selection, camera, undo untouched on change.
  Guided ≈ today's Simple, Full ≈ today's Pro, middle is continuous.
- **Left tool rail** (always visible): Select · Draw brush · Vertex/Edge/Face · Clip ·
  Surface · Displacement · Entity · Measure. Replaces the Pro-only top-bar tool strip +
  scattered viewport toggles. Active tool's params in a context bar under it.
- **Kit / asset panel** — Build Kit + models + prefabs + entity catalogue, one tabbed
  browser, available at every dial stop.
- **Inspector + Outliner / History / Map Check** as sibling tabs, one click away always.

## UI work per phase
- **P1 brush-entity:** Outliner → primary tab; "part of / select siblings / tie / untie"
  in the selection header with a class picker; real combined-state fields for mixed
  selections (replace the greyed-out apology).
- **P2 precise transform:** transform HUD (G/R/S overlay, axis lit in its colour, live
  value + text cursor); 2D rulers + dimension-entry field on every drag; snap-target
  picker (grid/vertex/edge-mid/face-centre) + in-range dot; movable pivot marker.
- **P3 surfaces:** Surface tool + context bar (themed material picker, visual UV grid,
  lightmap stepper, align toggle, treat-as-one); displacement brush palette
  (raise/lower/smooth/noise/alpha) + falloff-curve editor + radius/strength readout;
  blend-material paint shows both source textures + alpha under cursor.
- **P4 continuity:** the dial ships (Simple/Pro merge); kit pieces = first-class Outliner
  objects with re-openable option panels until "bake to brushes"; finish preview-
  everywhere (entity/prefab/preset thumbnails, hover previews, mini-3D kit cards);
  guided first map = dismissible coach-marks on the real workspace.
- **P5 ship:** compile → a "run bar" (profile · est. time · one button · progress ·
  "reload in game"), log one expand away; Map Check → review surface (grouped by
  severity, expand-to-fix, "fix all safe", jump-to-problem, leak drawn as a line to the
  hole); Publish → 3-step wizard (identity · preview+packing list · notes).

## Cross-cutting
- Toasts for async results; inline field validation; one shared "busy" affordance.
- Command palette = universal entry point, shortcuts shown; empty-viewport state points
  to it.
- Every panel has a useful empty state.
- Visible focus ring everywhere; severity by shape+label; reduced-motion honoured;
  `dp()` scaling honest 100–200%.

## UI bar (one sentence)
A new user and a veteran use the **same screen** — the veteran just turned the dial up.
