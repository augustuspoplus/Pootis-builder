class_name Blueprint2DView
extends Control

## Interactive Synced Valve Hammer 2D Blueprint Canvas!
## Mode 0 = TOP (X/Y) Blueprint (brush outlines, all entities, camera cone, pan/zoom/click-select!)
## Mode 1 = SIDE (X/Z) Elevation (dedicated vertical fit + floor-relative 48u/128u/192u TF2 Jump Guides!)

signal solid_clicked(solid_idx: int)

const UPM := 32.0
var doc: Object
var font: Font
var mode: int = 0 # 0=TOP (X/Z in Godot), 1=SIDE (X/Y in Godot)
var selected_solid: int = -1
var camera_pos: Vector3 = Vector3.ZERO
var _zoom: float = 1.0
var _pan_px: Vector2 = Vector2.ZERO
var _panning: bool = false
var _last_solid_rects: Array = [] # [{idx, rect}]
var _geo_dirty: bool = true
var _cached_solids: Array = []
var _cached_ents: Array = []
var _cached_mn: Vector3 = Vector3(-16, 0, -16)
var _cached_mx: Vector3 = Vector3(16, 8, 16)
var _cached_floor_y: float = 0.0

func setup(p_doc: Object, p_font: Font, p_mode: int = 0) -> void:
	doc = p_doc
	font = p_font
	mode = p_mode
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_geo_dirty = true

func mark_geometry_dirty() -> void:
	_geo_dirty = true
	queue_redraw()

func refresh(p_sel_solid: int, p_cam_pos: Vector3, geo_changed: bool = false) -> void:
	if geo_changed:
		_geo_dirty = true
	selected_solid = p_sel_solid
	camera_pos = p_cam_pos
	queue_redraw()

func _rebuild_geo_cache() -> void:
	_geo_dirty = false
	_cached_solids.clear()
	_cached_ents.clear()
	_cached_mn = Vector3(-16, 0, -16)
	_cached_mx = Vector3(16, 8, 16)
	_cached_floor_y = 0.0
	if doc == null:
		return
	var first := true
	for i in range(doc.get_solid_count()):
		var si: Dictionary = doc.get_solid_info(i)
		if not si.get("valid", false) or si.get("is_skybox", false) or si.get("hidden", false):
			continue
		var b0: Vector3 = si["bounds_min"]
		var b1: Vector3 = si["bounds_max"]
		_cached_solids.append({"idx": i, "min": b0, "max": b1})
		if first:
			_cached_mn = b0; _cached_mx = b1; first = false
		else:
			_cached_mn = _cached_mn.min(b0); _cached_mx = _cached_mx.max(b1)
		if (b1.x - b0.x) > 12.0 and (b1.z - b0.z) > 12.0 and (b1.y - b0.y) <= 2.0:
			_cached_floor_y = b1.y
	if mode == 0:
		for e in doc.get_entities():
			var cls: String = str(e["classname"])
			if cls == "info_player_teamspawn" or cls == "team_control_point" or cls == "item_teamflag" or cls.begins_with("item_healthkit") or cls.begins_with("item_ammopack"):
				_cached_ents.append({"cls": cls, "pos": e["pos"], "team": str(e["kv"].get("TeamNum", "2"))})

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = clampf(_zoom * 1.15, 0.45, 5.0); queue_redraw(); accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = clampf(_zoom / 1.15, 0.45, 5.0); queue_redraw(); accept_event()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mb.pressed; accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if mb.double_click:
				_zoom = 1.0; _pan_px = Vector2.ZERO; queue_redraw(); accept_event(); return
			var best_idx := -1
			var best_area := 1e30
			for sr in _last_solid_rects:
				var r: Rect2 = sr["rect"]
				if r.has_point(mb.position):
					var area := r.size.x * r.size.y
					if area < best_area:
						best_area = area
						best_idx = int(sr["idx"])
			if best_idx >= 0:
				solid_clicked.emit(best_idx)
				accept_event()
	elif event is InputEventMouseMotion and _panning:
		_pan_px += (event as InputEventMouseMotion).relative
		queue_redraw()
		accept_event()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 20 or h < 20:
		return

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.075, 0.09, 0.11, 0.97), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.26, 0.30, 0.36, 0.95), false, 1.5)

	if _geo_dirty:
		_rebuild_geo_cache()
	var mn := _cached_mn
	var mx := _cached_mx
	var solids: Array = _cached_solids
	var floor_y := _cached_floor_y

	var span_x := maxf(12.0, mx.x - mn.x)
	var pad := 16.0
	var right_gutter := 112.0 if mode == 1 else pad
	var draw_w := maxf(40.0, w - pad - right_gutter)
	var draw_h := maxf(40.0, h - 24.0 - pad * 1.4)

	var sc_x: float
	var sc_y: float
	if mode == 0:
		var span_z := maxf(10.0, mx.z - mn.z)
		var sc := minf(draw_w / span_x, draw_h / span_z) * _zoom
		sc_x = sc; sc_y = sc
	else:
		# Dedicated vertical fit for Side Elevation so 48u / 128u / 192u jump guides have clean vertical separation!
		var min_v := minf(mn.y, floor_y - 1.0)
		var max_v := maxf(mx.y + 1.5, floor_y + 7.5)
		sc_x = (draw_w / span_x) * _zoom
		sc_y = (draw_h / maxf(6.5, max_v - min_v)) * _zoom

	var cx := (mn.x + mx.x) * 0.5
	var cv := ((mn.z + mx.z) * 0.5) if mode == 0 else ((minf(mn.y, floor_y - 1.0) + maxf(mx.y + 1.5, floor_y + 7.5)) * 0.5)
	var ox := pad + draw_w * 0.5 + _pan_px.x
	var oy := 22.0 + draw_h * 0.5 + _pan_px.y

	var to_px := func(wx: float, wv: float) -> Vector2:
		if mode == 0:
			return Vector2(ox + (wx - cx) * sc_x, oy + (wv - cv) * sc_y)
		return Vector2(ox + (wx - cx) * sc_x, oy - (wv - cv) * sc_y)

	# Hammer 64u / 256u grid lines
	var grid_step_x := 4.0 if sc_x < 6.0 else 2.0
	var gx := floorf(mn.x / grid_step_x) * grid_step_x
	while gx <= mx.x + grid_step_x:
		var px: float = to_px.call(gx, cv).x
		if px >= 0 and px <= w:
			var major := (int(round(gx)) % 8 == 0)
			draw_line(Vector2(px, 20), Vector2(px, h), Color(0.90, 0.55, 0.20, 0.22) if major else Color(0.45, 0.58, 0.72, 0.12), 1.0)
		gx += grid_step_x
	var grid_step_v := 4.0 if sc_y < 6.0 else 2.0
	var gv_min := (mn.z if mode == 0 else floor_y - 2.0)
	var gv_max := (mx.z if mode == 0 else maxf(mx.y + 2.0, floor_y + 8.0))
	var gv := floorf(gv_min / grid_step_v) * grid_step_v
	while gv <= gv_max + grid_step_v:
		var py: float = to_px.call(cx, gv).y
		if py >= 20 and py <= h:
			var major := (int(round(gv)) % 8 == 0)
			draw_line(Vector2(0, py), Vector2(w, py), Color(0.90, 0.55, 0.20, 0.22) if major else Color(0.45, 0.58, 0.72, 0.12), 1.0)
		gv += grid_step_v

	# Draw solids & cache hit rects for click-to-select!
	_last_solid_rects.clear()
	for s in solids:
		var b0: Vector3 = s["min"]
		var b1: Vector3 = s["max"]
		var p0: Vector2 = to_px.call(b0.x, b0.z if mode == 0 else b1.y)
		var p1: Vector2 = to_px.call(b1.x, b1.z if mode == 0 else b0.y)
		var r := Rect2(p0, p1 - p0).abs()
		_last_solid_rects.append({"idx": s["idx"], "rect": r})
		var is_sel := (int(s["idx"]) == selected_solid)
		var col := Color(1.0, 0.68, 0.22, 0.96) if is_sel else Color(0.62, 0.70, 0.78, 0.70)
		draw_rect(r, Color(col.r, col.g, col.b, 0.24 if is_sel else 0.11), true)
		draw_rect(r, col, false, 2.0 if is_sel else 1.1)

	# Side view: Floor-relative TF2 Jump-Height Guides with crisp right-gutter pills (ZERO overlap!)
	if mode == 1:
		var guides := [
			{"u": 48,  "lbl": "48u Jump",   "col": Color(0.35, 0.88, 0.48, 0.90)},
			{"u": 128, "lbl": "128u Scout", "col": Color(0.20, 0.88, 0.98, 0.90)},
			{"u": 192, "lbl": "192u RJ",    "col": Color(0.96, 0.40, 0.36, 0.90)},
		]
		var prev_pill_y := h + 30.0
		for g in guides:
			var wy := floor_y + float(g["u"]) / UPM
			var py: float = to_px.call(cx, wy).y
			if py > 22.0 and py < h - 6.0:
				var gx_end := w - right_gutter + 6.0
				draw_dashed_line(Vector2(4, py), Vector2(gx_end, py), g["col"], 1.3, 5.0)
				# Ensure minimum 18px vertical spacing between right-side label pills
				var pill_y := minf(py, prev_pill_y - 18.0)
				prev_pill_y = pill_y
				var pr := Rect2(gx_end + 4.0, pill_y - 8.5, right_gutter - 14.0, 16.0)
				draw_rect(pr, Color(0.08, 0.09, 0.11, 0.94), true)
				draw_rect(pr, g["col"], false, 1.0)
				if font != null:
					draw_string(font, Vector2(pr.position.x + 5.0, pr.position.y + 12.0), g["lbl"], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, g["col"])

	# Entities & Camera dot in Top view (cached — zero GDExtension overhead during pan/zoom!)
	if doc != null and mode == 0:
		for e in _cached_ents:
			var cls: String = e["cls"]
			var ep: Vector3 = e["pos"]
			var pt: Vector2 = to_px.call(ep.x, ep.z)
			if cls == "info_player_teamspawn":
				var c := Color(0.94, 0.30, 0.28) if e["team"] == "2" else Color(0.28, 0.64, 0.96)
				draw_circle(pt, 4.0, c)
			elif cls == "team_control_point" or cls == "item_teamflag":
				draw_circle(pt, 4.8, Color(0.98, 0.80, 0.20))
			elif cls.begins_with("item_healthkit"):
				draw_circle(pt, 3.0, Color(0.32, 0.86, 0.45))
			elif cls.begins_with("item_ammopack"):
				draw_circle(pt, 3.0, Color(0.92, 0.68, 0.25))
		var cp: Vector2 = to_px.call(camera_pos.x, camera_pos.z)
		draw_circle(cp.clamp(Vector2(6, 24), size - Vector2(6, 6)), 4.2, Color(0.20, 0.94, 1.0))

	# Header label
	draw_rect(Rect2(0, 0, w, 20), Color(0.06, 0.07, 0.08, 0.94), true)
	if font != null:
		var title := "TOP (X/Y) — Span: %du (Click/Wheel/RMB)" % int(round(span_x * UPM)) if mode == 0 else "SIDE (X/Z) — Floor-Relative TF2 Jump Guides"
		draw_string(font, Vector2(6, 14), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.92, 0.62, 0.26))
