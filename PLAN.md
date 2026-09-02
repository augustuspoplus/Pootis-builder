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
