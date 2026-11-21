class_name Tf2HudWidgets
extends RefCounted

## Milestone 11 — Valve-Grade TF2 In-Game HUD Widgets for Godot 4.
## Authentic TF2 palette (warm charcoal #1D1916 + 4px amber lip #CF7336 + cream text #F0E6D2),
## official Valve TF2 fonts (tf2build.ttf / tf2secondary.ttf), isometric 3D piece icons,
## RED/BLU team crests, and the Q Voice-Menu Radial Pie Wheel!

const COL_BG_HUD   := Color(29.0 / 255.0, 25.0 / 255.0, 22.0 / 255.0, 0.94)
const COL_BG_CARD  := Color(38.0 / 255.0, 33.0 / 255.0, 29.0 / 255.0, 0.96)
const COL_BD_HUD   := Color(87.0 / 255.0, 76.0 / 255.0, 65.0 / 255.0, 0.96)
const COL_LIP_AMB  := Color(207.0 / 255.0, 115.0 / 255.0, 54.0 / 255.0, 1.0)
const COL_SLOT_BG  := Color(43.0 / 255.0, 38.0 / 255.0, 33.0 / 255.0, 0.95)
const COL_SLOT_HOV := Color(62.0 / 255.0, 53.0 / 255.0, 45.0 / 255.0, 0.98)
const COL_SLOT_ACT := Color(76.0 / 255.0, 56.0 / 255.0, 35.0 / 255.0, 0.98)
const COL_SLOT_BD  := Color(82.0 / 255.0, 72.0 / 255.0, 62.0 / 255.0, 0.95)
const COL_ACC      := Color(229.0 / 255.0, 135.0 / 255.0, 43.0 / 255.0, 1.0)
const COL_RED      := Color(184.0 / 255.0, 56.0 / 255.0, 59.0 / 255.0, 1.0)
const COL_BLU      := Color(76.0 / 255.0, 126.0 / 255.0, 160.0 / 255.0, 1.0)
const COL_CYAN     := Color(0.0, 229.0 / 255.0, 1.0, 1.0)
const COL_GREEN    := Color(76.0 / 255.0, 188.0 / 255.0, 96.0 / 255.0, 1.0)
const COL_TX       := Color(240.0 / 255.0, 230.0 / 255.0, 210.0 / 255.0, 1.0)
const COL_TX_MUTED := Color(180.0 / 255.0, 168.0 / 255.0, 150.0 / 255.0, 1.0)

static func load_fonts(tf2_dir: String = "") -> Dictionary:
	var heading_font: Font = null
	var body_font: Font = null
	var mono_font: Font = null

	# Prefer Valve's official installed TF2 fonts if present!
	if not tf2_dir.is_empty():
		var f_build := tf2_dir.path_join("tf/resource/tf2build.ttf")
		var f_sec := tf2_dir.path_join("tf/resource/tf2secondary.ttf")
		if FileAccess.file_exists(f_build):
			var ff := FontFile.new()
			if ff.load_dynamic_font(f_build) == OK:
				heading_font = ff
		if FileAccess.file_exists(f_sec):
			var ff2 := FontFile.new()
			if ff2.load_dynamic_font(f_sec) == OK:
				body_font = ff2

	var load_ttf := func(res_path: String) -> Font:
		var abs_p := ProjectSettings.globalize_path(res_path)
		if FileAccess.file_exists(abs_p):
			var ff := FontFile.new()
			if ff.load_dynamic_font(abs_p) == OK:
				return ff
		return null

	var fallback_semi: Font = load_ttf.call("res://assets/fonts/IBMPlexSans-SemiBold.ttf")
	var fallback_reg: Font = load_ttf.call("res://assets/fonts/IBMPlexSans-Regular.ttf")
	var fallback_mono: Font = load_ttf.call("res://assets/fonts/IBMPlexMono-Medium.ttf")
	if heading_font == null:
		heading_font = fallback_semi
	if body_font == null:
		body_font = fallback_reg if fallback_reg != null else fallback_semi
	mono_font = fallback_mono if fallback_mono != null else body_font

	return {"heading": heading_font, "body": body_font, "mono": mono_font}

static func make_button_style(bg: Color, border: Color, radius: int = 7, pad_x: int = 12, pad_y: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_x
	sb.content_margin_right = pad_x
	sb.content_margin_top = pad_y
	sb.content_margin_bottom = pad_y
	return sb

static func style_tf2_button(btn: Button, font: Font, font_size: int = 13, accent: bool = false, team: int = 0) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	var bg := COL_ACC if accent else (COL_RED if team == 2 else (COL_BLU if team == 3 else COL_SLOT_BG))
	var bg_h := bg.lightened(0.14) if (accent or team > 0) else COL_SLOT_HOV
	var bd := Color(1, 0.88, 0.65, 0.65) if accent else COL_SLOT_BD
	btn.add_theme_stylebox_override("normal", make_button_style(bg, bd))
	btn.add_theme_stylebox_override("hover", make_button_style(bg_h, COL_ACC))
	btn.add_theme_stylebox_override("pressed", make_button_style(bg.darkened(0.1), COL_ACC))
	if font != null:
		btn.add_theme_font_override("font", font)
	btn.add_theme_font_size_override("font_size", font_size)
	btn.add_theme_color_override("font_color", Color(0.11, 0.08, 0.05) if accent else COL_TX)
	btn.add_theme_color_override("font_hover_color", Color(0.08, 0.05, 0.02) if accent else Color.WHITE)

static func jump_threshold_callout(height_u: int) -> Dictionary:
	if height_u <= 18:
		return {"text": "%du — Walkable Step (<=18u)" % height_u, "color": COL_GREEN}
	elif height_u <= 48:
		return {"text": "%du — Standard Jump (<=48u)" % height_u, "color": COL_GREEN}
	elif height_u <= 64:
		return {"text": "%du — Crouch-Jump (<=64u)" % height_u, "color": COL_ACC}
	elif height_u <= 83:
		return {"text": "%du — Heavy Height (83u)" % height_u, "color": COL_ACC}
	elif height_u <= 128:
		return {"text": "%du — Scout Double-Jump (<=128u)" % height_u, "color": COL_CYAN}
	elif height_u <= 192:
		return {"text": "%du — Soldier Rocket-Jump! (192u)" % height_u, "color": COL_RED}
	else:
		return {"text": "%du — High Sniper Perch / Wall (%du)" % [height_u, height_u], "color": Color(0.84, 0.56, 1.0)}

class HudFrame extends PanelContainer:
	var lip_color: Color = COL_LIP_AMB
	var radius: float = 9.0
	var show_lip: bool = true

	func _init(p_lip: Color = COL_LIP_AMB, p_radius: float = 9.0, p_show_lip: bool = true) -> void:
		lip_color = p_lip
		radius = p_radius
		show_lip = p_show_lip
		var sb := StyleBoxFlat.new()
		sb.bg_color = COL_BG_HUD
		sb.border_color = COL_BD_HUD
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(int(radius))
		sb.shadow_color = Color(0, 0, 0, 0.45)
		sb.shadow_size = 12
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 7
		sb.content_margin_bottom = 11 if show_lip else 7
		add_theme_stylebox_override("panel", sb)

	func _draw() -> void:
		if show_lip:
			var r := Rect2(Vector2(2.0, size.y - 4.0), Vector2(max(0.0, size.x - 4.0), 3.5))
			draw_rect(r, lip_color, true)

class IsoIconCanvas extends Control:
	var piece_name: String = "Floor"
	var hot: bool = false
	var team_accent: int = 0
	var is_tool: bool = false
	var tool_kind: String = ""

	func _init(p_name: String, p_hot: bool = false, p_team: int = 0, p_tool: bool = false, p_tkind: String = "") -> void:
		piece_name = p_name
		hot = p_hot
		team_accent = p_team
		is_tool = p_tool
		tool_kind = p_tkind
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		if team_accent == 1 or team_accent == 2:
			var bg := COL_RED if team_accent == 1 else COL_BLU
			var bsz: float = minf(size.x, size.y) * 0.84
			var rect := Rect2(c - Vector2(bsz, bsz) * 0.5, Vector2(bsz, bsz))
			var sb := StyleBoxFlat.new()
			sb.bg_color = bg
			sb.border_color = Color(1.0, 0.94, 0.86, 0.58)
			sb.set_border_width_all(1)
			sb.set_corner_radius_all(7)
			sb.draw(get_canvas_item(), rect)
			var fg := Color(1.0, 0.97, 0.94, 0.98)
			draw_circle(Vector2(c.x, c.y - bsz * 0.21), bsz * 0.13, fg)
			var body := PackedVector2Array([
				Vector2(c.x - bsz * 0.22, c.y + bsz * 0.26),
				Vector2(c.x - bsz * 0.18, c.y - bsz * 0.04),
				Vector2(c.x + bsz * 0.18, c.y - bsz * 0.04),
				Vector2(c.x + bsz * 0.22, c.y + bsz * 0.26),
			])
			draw_colored_polygon(body, fg)
			return

		if is_tool:
			var col := COL_ACC if hot else COL_CYAN
			var r: float = minf(size.x, size.y) * 0.28
			if tool_kind == "Pull":
				draw_line(c - Vector2(r, 0), c + Vector2(r, 0), col, 2.2, true)
				draw_line(c - Vector2(0, r), c + Vector2(0, r), col, 2.2, true)
				var a := 4.5
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r - 3), c + Vector2(-a, -r + 3), c + Vector2(a, -r + 3)]), col)
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, r + 3), c + Vector2(-a, r - 3), c + Vector2(a, r - 3)]), col)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r - 3, 0), c + Vector2(-r + 3, -a), c + Vector2(-r + 3, a)]), col)
				draw_colored_polygon(PackedVector2Array([c + Vector2(r + 3, 0), c + Vector2(r - 3, -a), c + Vector2(r - 3, a)]), col)
			elif tool_kind == "Terrain":
				var pts := PackedVector2Array([
					c + Vector2(-r * 1.4, r * 0.7), c + Vector2(-r * 0.4, -r * 0.8),
					c + Vector2(r * 0.3, -r * 0.2), c + Vector2(r * 0.9, -r * 0.6),
					c + Vector2(r * 1.4, r * 0.7),
				])
				draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.35))
				draw_polyline(pts, col, 2.2, true)
			elif tool_kind == "Model":
				draw_rect(Rect2(c - Vector2(r, r), Vector2(r * 2, r * 2)), col, false, 2.0)
				draw_line(c + Vector2(0, -r * 0.5), c + Vector2(0, r * 0.5), col, 2.2)
				draw_line(c + Vector2(-r * 0.5, 0), c + Vector2(r * 0.5, 0), col, 2.2)
			else:
				var n0 := c + Vector2(-r * 0.8, -r * 0.55)
				var n1 := c + Vector2( r * 0.8, -r * 0.55)
				var n2 := c + Vector2(0.0, r * 0.65)
				draw_line(n0, n2, col, 2.0, true)
				draw_line(n1, n2, col, 2.0, true)
				draw_line(n0, n1, col, 1.8, true)
				draw_circle(n0, 3.6, col)
				draw_circle(n1, 3.6, col)
				draw_circle(n2, 4.0, col)
			return

		var r: float = minf(size.x, size.y) * 0.36
		var top_c := Color(0.96, 0.65, 0.31, 0.94) if hot else Color(0.62, 0.57, 0.51, 0.85)
		var lft_c := Color(0.82, 0.49, 0.18, 0.94) if hot else Color(0.45, 0.40, 0.35, 0.85)
		var rgt_c := Color(0.65, 0.36, 0.12, 0.94) if hot else Color(0.34, 0.30, 0.25, 0.85)
		var wire := Color(1.0, 0.89, 0.71, 0.98) if hot else Color(0.78, 0.73, 0.66, 0.88)

		var iso := func(x: float, y: float, z: float) -> Vector2:
			return Vector2(c.x + (x - y) * 0.866 * r, c.y + (x + y) * 0.5 * r - z * r)

		var draw_box := func(x0: float, y0: float, z0: float, x1: float, y1: float, z1: float) -> void:
			var t0: Vector2 = iso.call(x0, y0, z1)
			var t1: Vector2 = iso.call(x1, y0, z1)
			var t2: Vector2 = iso.call(x1, y1, z1)
			var t3: Vector2 = iso.call(x0, y1, z1)
			var b1: Vector2 = iso.call(x1, y0, z0)
			var b2: Vector2 = iso.call(x1, y1, z0)
			var b3: Vector2 = iso.call(x0, y1, z0)
			draw_colored_polygon(PackedVector2Array([t0, t1, t2, t3]), top_c)
			draw_colored_polygon(PackedVector2Array([t3, t2, b2, b3]), lft_c)
			draw_colored_polygon(PackedVector2Array([t2, t1, b1, b2]), rgt_c)
			draw_polyline(PackedVector2Array([t0, t1, t2, t3, t0]), wire, 1.1, true)
			draw_polyline(PackedVector2Array([t3, t2, b2, b3, t3]), wire, 1.1, true)
			draw_polyline(PackedVector2Array([t2, t1, b1, b2, t2]), wire, 1.1, true)

		match piece_name:
			"Floor":
				draw_box.call(-0.85, -0.85, -0.18, 0.85, 0.85, 0.18)
			"Wall":
				draw_box.call(-0.85, -0.20, -0.68, 0.85, 0.20, 0.68)
			"Building":
				draw_box.call(-0.75, -0.65, -0.65, 0.75, 0.65, 0.35)
				var r0: Vector2 = iso.call(-0.85, -0.75, 0.35)
				var r1: Vector2 = iso.call( 0.85, -0.75, 0.35)
				var r2: Vector2 = iso.call( 0.85,  0.75, 0.35)
				var r3: Vector2 = iso.call(-0.85,  0.75, 0.35)
				var pk0: Vector2 = iso.call(0.0, -0.75, 0.95)
				var pk1: Vector2 = iso.call(0.0,  0.75, 0.95)
				draw_colored_polygon(PackedVector2Array([r0, pk0, pk1, r3]), COL_RED)
				draw_colored_polygon(PackedVector2Array([pk0, r1, r2, pk1]), COL_RED.darkened(0.22))
				draw_polyline(PackedVector2Array([r0, pk0, r1, r2, pk1, r3, r0]), wire, 1.1, true)
			"Door", "Doorway":
				draw_box.call(-0.85, -0.20, -0.68, -0.28, 0.20, 0.68)
				draw_box.call( 0.28, -0.20, -0.68,  0.85, 0.20, 0.68)
				draw_box.call(-0.28, -0.20,  0.20,  0.28, 0.20, 0.68)
			"Stairs":
				for s in range(3):
					var y0 := -0.75 + s * 0.50
					draw_box.call(-0.65, y0, -0.55, 0.65, y0 + 0.50, -0.45 + (s + 1) * 0.35)
			"Ramp":
				var a: Vector2 = iso.call(-0.8, -0.6, -0.5)
				var b: Vector2 = iso.call( 0.8, -0.6,  0.5)
				var c2: Vector2 = iso.call( 0.8,  0.6,  0.5)
				var d: Vector2 = iso.call(-0.8,  0.6, -0.5)
				var e: Vector2 = iso.call( 0.8,  0.6, -0.5)
				var f: Vector2 = iso.call( 0.8, -0.6, -0.5)
				draw_colored_polygon(PackedVector2Array([a, b, c2, d]), top_c)
				draw_colored_polygon(PackedVector2Array([d, c2, e]), lft_c)
				draw_colored_polygon(PackedVector2Array([b, f, e, c2]), rgt_c)
				draw_polyline(PackedVector2Array([a, b, c2, d, a]), wire, 1.1, true)
			"Arch":
				draw_box.call(-0.85, -0.25, -0.68, -0.42, 0.25, 0.68)
				draw_box.call( 0.42, -0.25, -0.68,  0.85, 0.25, 0.68)
				draw_box.call(-0.42, -0.25,  0.30,  0.42, 0.25, 0.68)
			_:
				draw_box.call(-0.68, -0.68, -0.55, 0.68, 0.68, 0.55)

class RailSlot extends Button:
	var iso_canvas: IsoIconCanvas
	var tex_rect: TextureRect
	var lbl: Label
	var drag_payload: Dictionary = {}

	func _init(p_piece: String, p_label: String, p_tex: Texture2D, p_active: bool,
			p_team: int, p_is_tool: bool, p_tkind: String, p_font: Font, p_drag: Dictionary = {}) -> void:
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(76, 74)
		drag_payload = p_drag

		var bd_col := COL_ACC if p_active else (COL_RED if p_team == 1 else (COL_BLU if p_team == 2 else COL_SLOT_BD))
		var bg_col := COL_SLOT_ACT if p_active else (Color(0.28, 0.13, 0.13, 0.95) if p_team == 1 else (Color(0.13, 0.21, 0.29, 0.95) if p_team == 2 else COL_SLOT_BG))

		var sn := StyleBoxFlat.new()
		sn.bg_color = bg_col
		sn.border_color = bd_col
		sn.set_border_width_all(2 if p_active else 1)
		sn.set_corner_radius_all(8)
		sn.content_margin_left = 3; sn.content_margin_right = 3
		sn.content_margin_top = 4; sn.content_margin_bottom = 3
		var sh := sn.duplicate()
		sh.bg_color = COL_SLOT_HOV
		sh.border_color = COL_ACC
		add_theme_stylebox_override("normal", sn)
		add_theme_stylebox_override("hover", sh)
		add_theme_stylebox_override("pressed", sh)

		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.add_theme_constant_override("separation", 1)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vb)

		tex_rect = TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(60, 48)
		tex_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(tex_rect)

		iso_canvas = IsoIconCanvas.new(p_piece, p_active, p_team, p_is_tool, p_tkind)
		iso_canvas.custom_minimum_size = Vector2(60, 48)
		iso_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vb.add_child(iso_canvas)

		if p_tex != null:
			tex_rect.texture = p_tex
			tex_rect.visible = true
			iso_canvas.visible = false
		else:
			tex_rect.visible = false
			iso_canvas.visible = true

		lbl = Label.new()
		lbl.text = p_label
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if p_font != null:
			lbl.add_theme_font_override("font", p_font)
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", COL_ACC if p_active else COL_TX)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(lbl)

	func set_icon_texture(tex: Texture2D) -> void:
		if tex != null and tex_rect != null:
			tex_rect.texture = tex
			tex_rect.visible = true
			if iso_canvas != null:
				iso_canvas.visible = false

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if drag_payload.is_empty():
			return null
		var pv := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.11, 0.09, 0.08, 0.90)
		sb.border_color = COL_CYAN
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		pv.add_theme_stylebox_override("panel", sb)
		var vb := VBoxContainer.new()
		pv.add_child(vb)
		if tex_rect != null and tex_rect.texture != null:
			var tr := TextureRect.new()
			tr.texture = tex_rect.texture
			tr.custom_minimum_size = Vector2(72, 72)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			vb.add_child(tr)
		var dl := Label.new()
		dl.text = "Drop: " + lbl.text
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.add_theme_font_size_override("font_size", 11)
		dl.add_theme_color_override("font_color", COL_CYAN)
		vb.add_child(dl)
		set_drag_preview(pv)
		return drag_payload

## Authentic TF2 "Q" Voice-Menu Radial Pie Wheel!
class RadialPieWheel extends Control:
	signal action_chosen(action_id: String)

	var items: Array = [
		{"id": "box",      "label": "Box Block"},
		{"id": "building", "label": "Building"},
		{"id": "ramp",     "label": "Ramp"},
		{"id": "stairs",   "label": "Stairs"},
		{"id": "carve",    "label": "Carve Door"},
		{"id": "terrain",  "label": "Sculpt Hill"},
		{"id": "mirror",   "label": "Symmetry"},
		{"id": "playtest", "label": "F5 Playtest"},
	]
	var font: Font
	var hovered: int = -1
	var center_pt: Vector2 = Vector2.ZERO

	func _init(p_font: Font) -> void:
		font = p_font
		set_anchors_preset(Control.PRESET_FULL_RECT)
		visible = false

	func open_at(screen_pos: Vector2) -> void:
		center_pt = screen_pos
		hovered = -1
		visible = true
		queue_redraw()

	func close_and_commit() -> void:
		if not visible:
			return
		visible = false
		if hovered >= 0 and hovered < items.size():
			action_chosen.emit(items[hovered]["id"])

	func update_pointer(screen_pos: Vector2) -> void:
		if not visible:
			return
		var d := screen_pos - center_pt
		if d.length() < 34.0:
			hovered = -1
		else:
			var ang := fposmod(atan2(d.y, d.x) + PI * 0.5 + PI / items.size(), TAU)
			hovered = int(floor(ang / (TAU / items.size()))) % items.size()
		queue_redraw()

	func _draw() -> void:
		if not visible:
			return
		var r_in := 42.0
		var r_out := 148.0
		var n := items.size()
		var step := TAU / float(n)
		for i in range(n):
			var a0 := -PI * 0.5 - step * 0.5 + i * step
			var a1 := a0 + step - 0.04
			var pts := PackedVector2Array()
			var segs := 10
			for s in range(segs + 1):
				var a := lerpf(a0, a1, float(s) / segs)
				pts.append(center_pt + Vector2(cos(a), sin(a)) * r_out)
			for s in range(segs, -1, -1):
				var a := lerpf(a0, a1, float(s) / segs)
				pts.append(center_pt + Vector2(cos(a), sin(a)) * r_in)
			var hot := (i == hovered)
			draw_colored_polygon(pts, COL_SLOT_ACT if hot else COL_BG_HUD)
			draw_polyline(pts, COL_ACC if hot else COL_BD_HUD, 2.0 if hot else 1.2, true)
			var mid_a := (a0 + a1) * 0.5
			var lp := center_pt + Vector2(cos(mid_a), sin(mid_a)) * ((r_in + r_out) * 0.52)
			if font != null:
				var txt: String = items[i]["label"]
				var tsz := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
				draw_string(font, lp - Vector2(tsz.x * 0.5, -5), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
					COL_ACC if hot else COL_TX)
		# Center badge
		draw_circle(center_pt, r_in - 4.0, COL_BG_HUD)
		draw_arc(center_pt, r_in - 4.0, 0, TAU, 32, COL_LIP_AMB, 2.5, true)
		if font != null:
			draw_string(font, center_pt + Vector2(-24, 5), "QUICK", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COL_ACC)

class ViewportOverlay extends Control:
	var owner_ed: Node3D

	func _init(p_owner: Node3D) -> void:
		owner_ed = p_owner
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
		if data is Dictionary and data.has("kind") and owner_ed != null:
			owner_ed.on_viewport_drag_hover(at_position, data)
			return true
		return false

	func _drop_data(at_position: Vector2, data: Variant) -> void:
		if data is Dictionary and data.has("kind") and owner_ed != null:
			owner_ed.on_viewport_drop(at_position, data)

	func _draw() -> void:
		if owner_ed == null:
			return
		owner_ed.draw_viewport_2d_overlay(self)
