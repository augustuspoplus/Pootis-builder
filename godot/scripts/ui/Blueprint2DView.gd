class_name Blueprint2DView
extends Control

## Live Synced Valve Hammer 2D Blueprint Canvas!
## Mode 0 = TOP (X/Y) Blueprint (RED/BLU brush outlines, entities, selected solid, sightline span)
## Mode 1 = SIDE (X/Z) Elevation (brush silhouettes + dashed 48u Jump / 128u Scout / 192u Rocket-Jump guides!)

const UPM := 32.0
var doc: Object
var font: Font
var mode: int = 0 # 0=TOP (X/Z in Godot), 1=SIDE (X/Y in Godot)
var selected_solid: int = -1
var camera_pos: Vector3 = Vector3.ZERO

func setup(p_doc: Object, p_font: Font, p_mode: int = 0) -> void:
	doc = p_doc
	font = p_font
	mode = p_mode
	clip_contents = true

func refresh(p_sel_solid: int, p_cam_pos: Vector3) -> void:
	selected_solid = p_sel_solid
	camera_pos = p_cam_pos
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 20 or h < 20:
		return

	# Dark blueprint background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.075, 0.09, 0.11, 0.96), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.24, 0.28, 0.33, 0.95), false, 1.5)

	# Compute map bounds (excluding skybox)
	var mn := Vector3(-16, -2, -16)
	var mx := Vector3(16, 12, 16)
	var solids: Array = []
	if doc != null:
		var first := true
		for i in range(doc.get_solid_count()):
			var si: Dictionary = doc.get_solid_info(i)
			if not si.get("valid", false) or si.get("is_skybox", false) or si.get("hidden", false):
				continue
			var b0: Vector3 = si["bounds_min"]
			var b1: Vector3 = si["bounds_max"]
			solids.append({"idx": i, "min": b0, "max": b1})
			if first:
				mn = b0; mx = b1; first = false
			else:
				mn = mn.min(b0); mx = mx.max(b1)

	var span_x := maxf(12.0, mx.x - mn.x)
	var span_v := maxf(10.0, (mx.z - mn.z) if mode == 0 else (mx.y - mn.y + 4.0))
	var pad := 16.0
	var sc := minf((w - pad * 2.0) / span_x, (h - pad * 2.0 - 18.0) / span_v)
	var cx := (mn.x + mx.x) * 0.5
	var cv := ((mn.z + mx.z) * 0.5) if mode == 0 else ((mn.y + mx.y) * 0.5)
	var ox := w * 0.5
	var oy := h * 0.5 + 8.0

	var to_px := func(wx: float, wv: float) -> Vector2:
		if mode == 0:
			return Vector2(ox + (wx - cx) * sc, oy + (wv - cv) * sc)
		return Vector2(ox + (wx - cx) * sc, oy - (wv - cv) * sc)

	# Hammer 64u / 256u blueprint grid lines
	var grid_step_m := 4.0 if sc < 6.0 else 2.0
	var gx := floorf(mn.x / grid_step_m) * grid_step_m
	while gx <= mx.x + grid_step_m:
		var px: float = to_px.call(gx, cv).x
		var major := (int(round(gx)) % 8 == 0)
		draw_line(Vector2(px, 18), Vector2(px, h), Color(0.90, 0.55, 0.20, 0.22) if major else Color(0.45, 0.58, 0.72, 0.12), 1.0)
		gx += grid_step_m
	var gv := floorf((mn.z if mode == 0 else mn.y) / grid_step_m) * grid_step_m
	var gmax := (mx.z if mode == 0 else mx.y) + grid_step_m
	while gv <= gmax:
		var py: float = to_px.call(cx, gv).y
		var major := (int(round(gv)) % 8 == 0)
		draw_line(Vector2(0, py), Vector2(w, py), Color(0.90, 0.55, 0.20, 0.22) if major else Color(0.45, 0.58, 0.72, 0.12), 1.0)
		gv += grid_step_m

	# Draw solids
	for s in solids:
		var b0: Vector3 = s["min"]
		var b1: Vector3 = s["max"]
		var p0: Vector2 = to_px.call(b0.x, b0.z if mode == 0 else b1.y)
		var p1: Vector2 = to_px.call(b1.x, b1.z if mode == 0 else b0.y)
		var r := Rect2(p0, p1 - p0).abs()
		var is_sel := (int(s["idx"]) == selected_solid)
		var mid_x := (b0.x + b1.x) * 0.5
		var col := Color(1.0, 0.68, 0.22, 0.95) if is_sel else (Color(0.86, 0.34, 0.34, 0.72) if mid_x < -1.0 else (Color(0.35, 0.64, 0.86, 0.72) if mid_x > 1.0 else Color(0.65, 0.62, 0.56, 0.65)))
		draw_rect(r, Color(col.r, col.g, col.b, 0.22 if is_sel else 0.10), true)
		draw_rect(r, col, false, 2.0 if is_sel else 1.1)

	# Side view: TF2 Jump-Height Reference Lines (48u Jump, 128u Scout, 192u Rocket-Jump!)
	if mode == 1:
		var guides := [
			{"u": 48,  "lbl": "48u Jump",        "col": Color(0.35, 0.84, 0.45, 0.75)},
			{"u": 128, "lbl": "128u Scout",      "col": Color(0.18, 0.85, 0.96, 0.75)},
			{"u": 192, "lbl": "192u Rocket-Jump","col": Color(0.95, 0.36, 0.34, 0.75)},
		]
		for g in guides:
			var wy := float(g["u"]) / UPM
			var py: float = to_px.call(cx, wy).y
			if py > 20 and py < h - 4:
				draw_dashed_line(Vector2(2, py), Vector2(w - 2, py), g["col"], 1.2, 5.0)
				if font != null:
					draw_string(font, Vector2(6, py - 3), g["lbl"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, g["col"])

	# Entities & Camera dot in Top view
	if doc != null and mode == 0:
		for e in doc.get_entities():
			var cls: String = str(e["classname"])
			var ep: Vector3 = e["pos"]
			var pt: Vector2 = to_px.call(ep.x, ep.z)
			if cls == "info_player_teamspawn":
				var c := Color(0.92, 0.28, 0.28) if str(e["kv"].get("TeamNum", "2")) == "2" else Color(0.28, 0.62, 0.94)
				draw_circle(pt, 3.8, c)
			elif cls == "team_control_point" or cls == "item_teamflag":
				draw_circle(pt, 4.5, Color(0.98, 0.80, 0.20))
		var cp: Vector2 = to_px.call(camera_pos.x, camera_pos.z)
		draw_circle(cp.clamp(Vector2(6, 22), size - Vector2(6, 6)), 4.0, Color(0.20, 0.94, 1.0))

	# Header label
	draw_rect(Rect2(0, 0, w, 18), Color(0.06, 0.07, 0.08, 0.90), true)
	if font != null:
		var title := "TOP (X/Y) BLUEPRINT — Span: %du" % int(round(span_x * UPM)) if mode == 0 else "SIDE (X/Z) ELEVATION — TF2 Jump Guides"
		draw_string(font, Vector2(6, 13), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.90, 0.58, 0.22))
