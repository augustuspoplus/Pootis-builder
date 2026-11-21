class_name Tf2HudWidgets
extends RefCounted

## Milestone 11 â€” Valve-Grade TF2 In-Game HUD Widgets for Godot 4.
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
		return {"text": "%du â€” Walkable Step (<=18u)" % height_u, "color": COL_GREEN}
	elif height_u <= 48:
		return {"text": "%du â€” Standard Jump (<=48u)" % height_u, "color": COL_GREEN}
	elif height_u <= 64:
		return {"text": "%du â€” Crouch-Jump (<=64u)" % height_u, "color": COL_ACC}
	elif height_u <= 83:
		return {"text": "%du â€” Heavy Height (83u)" % height_u, "color": COL_ACC}
	elif height_u <= 128:
		return {"text": "%du â€” Scout Double-Jump (<=128u)" % height_u, "color": COL_CYAN}
	elif height_u <= 192:
		return {"text": "%du â€” Soldier Rocket-Jump! (192u)" % height_u, "color": COL_RED}
	else:
		return {"text": "%du â€” High Sniper Perch / Wall (%du)" % [height_u, height_u], "color": Color(0.84, 0.56, 1.0)}

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

## Color-coded custom vector icons for ALL non-model Hammer / TF2 entities (Doors, Triggers, Lights, Sound, FX, Logic, AI)!
class EntityBadgeIcon extends Control:
	var kind: String = "relay"

	func _init(p_kind: String = "relay") -> void:
		kind = p_kind
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var half := minf(size.x, size.y) * 0.42
		var rect := Rect2(c - Vector2(half, half), Vector2(half * 2.0, half * 2.0))
		var s := half * 0.65
		var bg := Color(0.22, 0.14, 0.29, 0.96)
		var bd := Color(0.72, 0.45, 0.90, 1.0)
		match kind:
			"door":       bg = Color(0.16, 0.24, 0.30); bd = COL_CYAN
			"trigger":    bg = Color(0.28, 0.21, 0.08); bd = Color(0.96, 0.80, 0.30)
			"hurt":       bg = Color(0.32, 0.10, 0.10); bd = COL_RED
			"jump_pad":   bg = Color(0.10, 0.26, 0.16); bd = COL_GREEN
			"teleporter": bg = Color(0.12, 0.18, 0.30); bd = COL_CYAN
			"light":      bg = Color(0.30, 0.24, 0.08); bd = Color(0.98, 0.84, 0.32)
			"sun":        bg = Color(0.32, 0.21, 0.08); bd = COL_ACC
			"sound":      bg = Color(0.10, 0.24, 0.28); bd = COL_CYAN
			"particle":   bg = Color(0.28, 0.14, 0.09); bd = COL_ACC
			"clip":       bg = Color(0.26, 0.13, 0.24); bd = Color(0.90, 0.44, 0.78)
			"win":        bg = Color(0.12, 0.26, 0.14); bd = COL_GREEN
			"camera":     bg = Color(0.14, 0.20, 0.28); bd = COL_BLU
			"ai":         bg = Color(0.26, 0.14, 0.24); bd = Color(0.90, 0.48, 0.82)

		var sb := StyleBoxFlat.new()
		sb.bg_color = bg; sb.border_color = bd
		sb.set_border_width_all(2); sb.set_corner_radius_all(7)
		sb.draw(get_canvas_item(), rect)

		match kind:
			"door":
				draw_line(c + Vector2(0, -half * 0.82), c + Vector2(0, half * 0.82), bd, 2.0)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s, 0), c + Vector2(-s * 0.35, -s * 0.45), c + Vector2(-s * 0.35, s * 0.45)]), COL_TX)
				draw_colored_polygon(PackedVector2Array([c + Vector2(s, 0), c + Vector2(s * 0.35, -s * 0.45), c + Vector2(s * 0.35, s * 0.45)]), COL_TX)
			"trigger":
				draw_line(c + Vector2(-s, -s), c + Vector2(s, s), bd, 2.0)
				draw_line(c + Vector2(-s, s), c + Vector2(s, -s), bd, 2.0)
				draw_circle(c, s * 0.42, bd)
			"hurt":
				draw_circle(c + Vector2(0, -s * 0.18), s * 0.72, COL_TX)
				draw_rect(Rect2(c + Vector2(-s * 0.38, s * 0.30), Vector2(s * 0.76, s * 0.48)), COL_TX, true)
				draw_circle(c + Vector2(-s * 0.28, -s * 0.22), s * 0.18, bg)
				draw_circle(c + Vector2(s * 0.28, -s * 0.22), s * 0.18, bg)
			"jump_pad":
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(0, -s), c + Vector2(-s * 0.85, -s * 0.05), c + Vector2(-s * 0.34, -s * 0.05),
					c + Vector2(-s * 0.34, s * 0.95), c + Vector2(s * 0.34, s * 0.95), c + Vector2(s * 0.34, -s * 0.05),
					c + Vector2(s * 0.85, -s * 0.05),
				]), bd)
			"teleporter":
				draw_arc(c, s * 0.92, 0.0, TAU * 0.78, 18, bd, 2.4)
				draw_arc(c, s * 0.52, 1.4, TAU * 0.92, 14, COL_ACC, 2.0)
				draw_circle(c, s * 0.20, COL_TX)
			"timer":
				draw_arc(c + Vector2(0, s * 0.12), s * 0.82, 0.0, TAU, 18, COL_TX, 2.0)
				draw_line(c + Vector2(0, s * 0.12), c + Vector2(0, -s * 0.42), COL_ACC, 2.2)
				draw_line(c + Vector2(0, s * 0.12), c + Vector2(s * 0.48, s * 0.28), COL_ACC, 2.0)
				draw_line(c + Vector2(-s * 0.35, -s * 0.92), c + Vector2(s * 0.35, -s * 0.92), COL_TX, 2.2)
			"counter":
				draw_rect(Rect2(c + Vector2(-s * 0.9, -s * 0.55), Vector2(s * 1.8, s * 1.1)), COL_CYAN, false, 1.8)
				draw_line(c + Vector2(-s * 0.3, -s * 0.55), c + Vector2(-s * 0.3, s * 0.55), COL_CYAN, 1.6)
				draw_line(c + Vector2(s * 0.3, -s * 0.55), c + Vector2(s * 0.3, s * 0.55), COL_CYAN, 1.6)
			"light":
				draw_circle(c + Vector2(0, -s * 0.22), s * 0.65, bd)
				draw_rect(Rect2(c + Vector2(-s * 0.34, s * 0.38), Vector2(s * 0.68, s * 0.44)), COL_TX_MUTED, true)
			"sun":
				draw_circle(c, s * 0.52, Color(0.98, 0.85, 0.32))
				for k in range(8):
					var a := float(k) * PI * 0.25
					draw_line(c + Vector2(cos(a), sin(a)) * s * 0.72, c + Vector2(cos(a), sin(a)) * s * 1.05, bd, 2.0)
			"sound":
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-s * 0.9, -s * 0.32), c + Vector2(-s * 0.42, -s * 0.32),
					c + Vector2(s * 0.08, -s * 0.82), c + Vector2(s * 0.08, s * 0.82),
					c + Vector2(-s * 0.42, s * 0.32), c + Vector2(-s * 0.9, s * 0.32),
				]), COL_TX)
				draw_arc(c + Vector2(s * 0.15, 0), s * 0.45, -0.9, 0.9, 10, bd, 2.0)
				draw_arc(c + Vector2(s * 0.22, 0), s * 0.78, -0.9, 0.9, 12, bd, 2.0)
			"particle":
				draw_circle(c + Vector2(-s * 0.45, s * 0.35), s * 0.36, COL_ACC)
				draw_circle(c + Vector2(s * 0.38, s * 0.22), s * 0.42, Color(0.98, 0.82, 0.32))
				draw_circle(c + Vector2(0, -s * 0.38), s * 0.46, bd)
			"clip":
				draw_rect(Rect2(c + Vector2(-s * 0.8, -s * 0.8), Vector2(s * 1.6, s * 1.6)), bd, false, 2.0)
				draw_line(c + Vector2(-s * 0.8, -s * 0.8), c + Vector2(s * 0.8, s * 0.8), bd, 2.0)
			"win":
				draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.55, -s * 0.85), c + Vector2(s * 0.82, -s * 0.38), c + Vector2(-s * 0.55, s * 0.12)]), Color(0.98, 0.84, 0.32))
				draw_line(c + Vector2(-s * 0.55, -s * 0.90), c + Vector2(-s * 0.55, s * 0.92), COL_TX, 2.6)
			"camera":
				draw_rect(Rect2(c + Vector2(-s * 0.85, -s * 0.5), Vector2(s * 1.15, s * 1.0)), COL_TX, false, 2.0)
				draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.35, 0), c + Vector2(s * 0.95, -s * 0.48), c + Vector2(s * 0.95, s * 0.48)]), bd)
			"ai":
				draw_circle(c, s * 0.72, bd)
				draw_circle(c, s * 0.42, bg)
				draw_circle(c, s * 0.18, COL_TX)
				draw_line(c + Vector2(-s, 0), c + Vector2(s, 0), bd, 1.6)
				draw_line(c + Vector2(0, -s), c + Vector2(0, s), bd, 1.6)
			_: # relay lightning bolt
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(s * 0.15, -s), c + Vector2(-s * 0.65, s * 0.10), c + Vector2(0, s * 0.10),
					c + Vector2(-s * 0.22, s), c + Vector2(s * 0.72, -s * 0.12), c + Vector2(s * 0.08, -s * 0.12),
				]), Color(0.98, 0.84, 0.32))

## Bottom-Middle Multi-Box Dock Card (supports BOTH 3D baked TF2 icons AND custom EntityBadgeIcons + Drag-and-Drop!)
class DockCardSlot extends Button:
	var drag_payload: Dictionary = {}
	var _tex_rect: TextureRect = null

	func _init(p_title: String, p_sub: String, p_tex: Texture2D, p_vec_icon: String, p_active: bool, p_accent: Color, p_font: Font, p_drag: Dictionary = {}) -> void:
		drag_payload = p_drag
		custom_minimum_size = Vector2(104, 80)
		focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.22, 0.18, 0.14, 0.98) if p_active else COL_BG_CARD
		sb.border_color = p_accent if p_active else COL_SLOT_BD
		sb.set_border_width_all(2 if p_active else 1)
		sb.set_corner_radius_all(8)
		var sbh := sb.duplicate(); sbh.bg_color = COL_SLOT_HOV; sbh.border_color = p_accent
		add_theme_stylebox_override("normal", sb)
		add_theme_stylebox_override("hover", sbh)
		add_theme_stylebox_override("pressed", sbh)

		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.offset_left = 5; vb.offset_right = -5; vb.offset_top = 4; vb.offset_bottom = -4
		vb.add_theme_constant_override("separation", 1)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vb)

		if not p_vec_icon.is_empty():
			var eic := EntityBadgeIcon.new(p_vec_icon)
			eic.custom_minimum_size = Vector2(46, 46)
			eic.size_flags_vertical = Control.SIZE_EXPAND_FILL
			vb.add_child(eic)
		else:
			_tex_rect = TextureRect.new()
			_tex_rect.custom_minimum_size = Vector2(46, 46)
			_tex_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
			_tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			_tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			_tex_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_tex_rect.texture = p_tex
			vb.add_child(_tex_rect)

		var l1 := Label.new()
		l1.text = p_title
		l1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l1.clip_text = true
		if p_font != null: l1.add_theme_font_override("font", p_font)
		l1.add_theme_font_size_override("font_size", 10)
		l1.add_theme_color_override("font_color", p_accent if p_active else COL_TX)
		l1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(l1)

		if not p_sub.is_empty():
			var l2 := Label.new()
			l2.text = p_sub
			l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			l2.clip_text = true
			if p_font != null: l2.add_theme_font_override("font", p_font)
			l2.add_theme_font_size_override("font_size", 8)
			l2.add_theme_color_override("font_color", COL_TX_MUTED)
			l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vb.add_child(l2)

	func set_icon_texture(tex: Texture2D) -> void:
		if _tex_rect != null:
			_tex_rect.texture = tex

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if drag_payload.is_empty():
			return null
		var pv := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.14, 0.12, 0.10, 0.92); sb.border_color = COL_ACC
		sb.set_border_width_all(2); sb.set_corner_radius_all(8); sb.set_content_margin_all(6)
		pv.add_theme_stylebox_override("panel", sb)
		if _tex_rect != null and _tex_rect.texture != null:
			var tr := TextureRect.new()
			tr.texture = _tex_rect.texture
			tr.custom_minimum_size = Vector2(64, 64)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pv.add_child(tr)
		else:
			var lb := Label.new(); lb.text = str(drag_payload.get("name", drag_payload.get("cls", "Item")))
			pv.add_child(lb)
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
		mouse_filter = Control.MOUSE_FILTER_IGNORE
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

static func _make_toggle_icon(on: bool) -> ImageTexture:
	var w := 42
	var h := 22
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var track_col := COL_ACC if on else Color(0.28, 0.25, 0.22, 1.0)
	var border_col := Color(0.96, 0.72, 0.42, 1.0) if on else Color(0.55, 0.49, 0.43, 1.0)
	var knob_col := Color(0.98, 0.96, 0.92, 1.0) if on else Color(0.78, 0.73, 0.67, 1.0)
	var r := float(h) * 0.5 - 1.0
	var cy := float(h) * 0.5
	for y in range(h):
		for x in range(w):
			var cx := clampf(float(x), r + 1.0, float(w) - r - 2.0)
			var d := Vector2(float(x) - cx, float(y) - cy).length()
			if d <= r:
				img.set_pixel(x, y, border_col if d >= r - 1.5 else track_col)
	var kx := float(w) - r - 1.0 if on else r + 1.0
	var kr := r - 3.0
	for y in range(h):
		for x in range(w):
			var d := Vector2(float(x) - kx, float(y) - cy).length()
			if d <= kr:
				img.set_pixel(x, y, knob_col)
	return ImageTexture.create_from_image(img)

static func create_global_theme(fonts: Dictionary) -> Theme:
	var th := Theme.new()
	var body_f: Font = fonts.get("body", null)
	if body_f != null:
		th.default_font = body_f
	th.default_font_size = 12

	var inp_sb := StyleBoxFlat.new()
	inp_sb.bg_color = Color(0.08, 0.07, 0.06, 0.96)
	inp_sb.border_color = Color(0.38, 0.33, 0.28, 0.90)
	inp_sb.set_border_width_all(1)
	inp_sb.set_corner_radius_all(5)
	inp_sb.set_content_margin_all(5)
	inp_sb.content_margin_left = 8; inp_sb.content_margin_right = 8

	var inp_focus := inp_sb.duplicate()
	inp_focus.border_color = COL_ACC
	inp_focus.set_border_width_all(2)

	for cls in ["LineEdit", "TextEdit"]:
		th.set_stylebox("normal", cls, inp_sb)
		th.set_stylebox("focus", cls, inp_focus)
		th.set_color("font_color", cls, COL_TX)
		th.set_color("font_placeholder_color", cls, COL_TX_MUTED)
		th.set_font_size("font_size", cls, 12)

	th.set_stylebox("normal", "OptionButton", inp_sb)
	th.set_stylebox("hover", "OptionButton", inp_focus)
	th.set_stylebox("pressed", "OptionButton", inp_focus)
	th.set_color("font_color", "OptionButton", COL_TX)
	th.set_font_size("font_size", "OptionButton", 12)

	var pop_sb := StyleBoxFlat.new()
	pop_sb.bg_color = Color(0.11, 0.10, 0.09, 0.98)
	pop_sb.border_color = COL_ACC
	pop_sb.set_border_width_all(1)
	pop_sb.set_corner_radius_all(6)
	pop_sb.set_content_margin_all(4)
	th.set_stylebox("panel", "PopupMenu", pop_sb)
	th.set_color("font_color", "PopupMenu", COL_TX)
	th.set_font_size("font_size", "PopupMenu", 12)

	var on_ic := _make_toggle_icon(true)
	var off_ic := _make_toggle_icon(false)
	th.set_icon("checked", "CheckButton", on_ic)
	th.set_icon("unchecked", "CheckButton", off_ic)
	th.set_icon("checked_disabled", "CheckButton", on_ic)
	th.set_icon("unchecked_disabled", "CheckButton", off_ic)
	th.set_color("font_color", "CheckButton", COL_TX)
	th.set_font_size("font_size", "CheckButton", 12)
	return th

## Crisp vector-drawn icons for the Left Tool Rail, Terrain Sculpt Brushes, and Terrain Presets!
class VectorToolIcon extends Control:
	var icon_id: String = "select"
	var active: bool = false
	var tint: Color = COL_ACC

	func _init(p_id: String, p_active: bool = false, p_tint: Color = COL_ACC) -> void:
		icon_id = p_id
		active = p_active
		tint = p_tint
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var s := minf(size.x, size.y) * 0.36
		var col := Color(0.10, 0.07, 0.04, 1.0) if active else tint
		var mut := Color(0.24, 0.16, 0.08, 0.7) if active else COL_TX_MUTED
		match icon_id:
			"select":
				var pts := PackedVector2Array([
					c + Vector2(-s * 0.65, -s * 0.90),
					c + Vector2(-s * 0.65, s * 0.80),
					c + Vector2(-s * 0.10, s * 0.35),
					c + Vector2(s * 0.35, s * 0.95),
					c + Vector2(s * 0.62, s * 0.78),
					c + Vector2(s * 0.18, s * 0.18),
					c + Vector2(s * 0.80, s * 0.18),
				])
				draw_colored_polygon(pts, col)
			"floor": # 3D Box
				draw_rect(Rect2(c + Vector2(-s * 0.85, -s * 0.45), Vector2(s * 1.35, s * 1.35)), col, false, 2.0)
				draw_polyline(PackedVector2Array([
					c + Vector2(-s * 0.85, -s * 0.45),
					c + Vector2(-s * 0.30, -s * 0.95),
					c + Vector2(s * 1.00, -s * 0.95),
					c + Vector2(s * 0.50, -s * 0.45),
				]), col, 2.0)
				draw_polyline(PackedVector2Array([
					c + Vector2(s * 1.00, -s * 0.95),
					c + Vector2(s * 1.00, s * 0.38),
					c + Vector2(s * 0.50, s * 0.90),
				]), col, 2.0)
			"wall": # Brick Wall
				draw_rect(Rect2(c + Vector2(-s, -s * 0.72), Vector2(s * 2.0, s * 1.44)), col, false, 2.0)
				draw_line(c + Vector2(-s, 0), c + Vector2(s, 0), col, 2.0)
				draw_line(c + Vector2(0, -s * 0.72), c + Vector2(0, 0), col, 2.0)
				draw_line(c + Vector2(-s * 0.45, 0), c + Vector2(-s * 0.45, s * 0.72), col, 2.0)
				draw_line(c + Vector2(s * 0.45, 0), c + Vector2(s * 0.45, s * 0.72), col, 2.0)
			"clip": # Diagonal Slice
				draw_rect(Rect2(c + Vector2(-s * 0.75, -s * 0.75), Vector2(s * 1.5, s * 1.5)), mut, false, 1.5)
				draw_line(c + Vector2(-s * 0.95, s * 0.85), c + Vector2(s * 0.95, -s * 0.85), col, 2.6)
				draw_circle(c + Vector2(-s * 0.95, s * 0.85), 2.5, col)
				draw_circle(c + Vector2(s * 0.95, -s * 0.85), 2.5, col)
			"vertex": # Triangle with Vertex Handles
				var a := c + Vector2(-s * 0.85, s * 0.72)
				var b := c + Vector2(0, -s * 0.85)
				var d := c + Vector2(s * 0.88, s * 0.55)
				draw_polyline(PackedVector2Array([a, b, d, a]), col, 1.8)
				for pt in [a, b, d]:
					draw_circle(pt, 3.3, col)
			"hollow": # Nested Hollow Room
				draw_rect(Rect2(c + Vector2(-s * 0.9, -s * 0.9), Vector2(s * 1.8, s * 1.8)), col, false, 2.0)
				draw_rect(Rect2(c + Vector2(-s * 0.42, -s * 0.42), Vector2(s * 0.84, s * 0.84)), col, false, 1.8)
			"carve": # Doorway Arch
				draw_arc(c + Vector2(0, -s * 0.1), s * 0.75, PI, TAU, 16, col, 2.4)
				draw_line(c + Vector2(-s * 0.75, -s * 0.1), c + Vector2(-s * 0.75, s * 0.85), col, 2.4)
				draw_line(c + Vector2(s * 0.75, -s * 0.1), c + Vector2(s * 0.75, s * 0.85), col, 2.4)
				draw_line(c + Vector2(-s * 1.0, s * 0.85), c + Vector2(s * 1.0, s * 0.85), mut, 1.5)
			"terrain": # Mountain Cliff Peaks
				draw_polyline(PackedVector2Array([
					c + Vector2(-s, s * 0.75),
					c + Vector2(-s * 0.3, -s * 0.75),
					c + Vector2(s * 0.15, s * 0.08),
					c + Vector2(s * 0.55, -s * 0.42),
					c + Vector2(s, s * 0.75),
					c + Vector2(-s, s * 0.75),
				]), col, 2.0)
			"entities": # Map Pin
				draw_arc(c + Vector2(0, -s * 0.28), s * 0.55, 0, TAU, 18, col, 2.0)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-s * 0.42, s * 0.08),
					c + Vector2(s * 0.42, s * 0.08),
					c + Vector2(0, s * 0.92),
				]), col)
			"hide": # Visibility Eye
				draw_arc(c + Vector2(0, s * 0.45), s * 1.05, deg_to_rad(220), deg_to_rad(320), 16, col, 2.0)
				draw_arc(c + Vector2(0, -s * 0.45), s * 1.05, deg_to_rad(40), deg_to_rad(140), 16, col, 2.0)
				draw_circle(c, s * 0.34, col)
			"raise":
				draw_line(c + Vector2(0, s * 0.85), c + Vector2(0, -s * 0.75), col, 2.4)
				draw_polyline(PackedVector2Array([c + Vector2(-s * 0.55, -s * 0.2), c + Vector2(0, -s * 0.8), c + Vector2(s * 0.55, -s * 0.2)]), col, 2.4)
			"lower":
				draw_line(c + Vector2(0, -s * 0.85), c + Vector2(0, s * 0.75), col, 2.4)
				draw_polyline(PackedVector2Array([c + Vector2(-s * 0.55, s * 0.2), c + Vector2(0, s * 0.8), c + Vector2(s * 0.55, s * 0.2)]), col, 2.4)
			"smooth":
				draw_arc(c + Vector2(-s * 0.45, 0), s * 0.45, PI, TAU, 12, col, 2.2)
				draw_arc(c + Vector2(s * 0.45, 0), s * 0.45, 0, PI, 12, col, 2.2)
			"flatten":
				draw_line(c + Vector2(-s * 0.9, s * 0.3), c + Vector2(s * 0.9, s * 0.3), col, 2.6)
				draw_line(c + Vector2(0, -s * 0.75), c + Vector2(0, s * 0.1), col, 2.0)
			"noise":
				draw_polyline(PackedVector2Array([
					c + Vector2(-s, s * 0.4), c + Vector2(-s * 0.5, -s * 0.55),
					c + Vector2(0, s * 0.35), c + Vector2(s * 0.5, -s * 0.7), c + Vector2(s, s * 0.4),
				]), col, 2.2)
			"paint":
				draw_circle(c + Vector2(-s * 0.2, s * 0.25), s * 0.42, col)
				draw_line(c + Vector2(s * 0.1, -s * 0.05), c + Vector2(s * 0.85, -s * 0.8), col, 2.8)
			"preset_cliff":
				draw_colored_polygon(PackedVector2Array([
					Vector2(4, size.y - 4), Vector2(4, size.y * 0.22),
					Vector2(size.x * 0.44, size.y * 0.22), Vector2(size.x * 0.62, size.y * 0.68),
					Vector2(size.x - 4, size.y * 0.72), Vector2(size.x - 4, size.y - 4),
				]), Color(0.68, 0.38, 0.24, 0.88))
				draw_polyline(PackedVector2Array([
					Vector2(4, size.y * 0.22), Vector2(size.x * 0.44, size.y * 0.22),
					Vector2(size.x * 0.62, size.y * 0.68), Vector2(size.x - 4, size.y * 0.72),
				]), COL_ACC, 2.0)
			"preset_hill":
				var pts := PackedVector2Array([Vector2(4, size.y - 4)])
				for i in range(13):
					var t := float(i) / 12.0
					var y := size.y * (0.78 - 0.52 * sin(t * PI))
					pts.append(Vector2(lerpf(4.0, size.x - 4.0, t), y))
				pts.append(Vector2(size.x - 4, size.y - 4))
				draw_colored_polygon(pts, Color(0.32, 0.58, 0.32, 0.85))
			"preset_mesa":
				draw_colored_polygon(PackedVector2Array([
					Vector2(4, size.y - 4), Vector2(size.x * 0.22, size.y * 0.28),
					Vector2(size.x * 0.78, size.y * 0.28), Vector2(size.x - 4, size.y - 4),
				]), Color(0.76, 0.48, 0.26, 0.88))
				draw_line(Vector2(size.x * 0.22, size.y * 0.28), Vector2(size.x * 0.78, size.y * 0.28), COL_ACC, 2.2)
			"preset_crater":
				draw_colored_polygon(PackedVector2Array([
					Vector2(4, size.y - 4), Vector2(4, size.y * 0.36),
					Vector2(size.x * 0.24, size.y * 0.32), Vector2(size.x * 0.5, size.y * 0.78),
					Vector2(size.x * 0.76, size.y * 0.32), Vector2(size.x - 4, size.y * 0.36),
					Vector2(size.x - 4, size.y - 4),
				]), Color(0.46, 0.42, 0.38, 0.88))

## Draggable 3D TF2 Prop Card (click to stamp OR drag directly into the 3D viewport!)
class DraggablePropCard extends Button:
	var drag_payload: Dictionary = {}
	var drag_icon: Texture2D = null

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if drag_payload.is_empty():
			return null
		var pv := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.14, 0.12, 0.10, 0.92)
		sb.border_color = COL_ACC
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(8)
		sb.set_content_margin_all(6)
		pv.add_theme_stylebox_override("panel", sb)
		if drag_icon != null:
			var tr := TextureRect.new()
			tr.texture = drag_icon
			tr.custom_minimum_size = Vector2(68, 68)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pv.add_child(tr)
		else:
			var lb := Label.new()
			lb.text = str(drag_payload.get("name", "Prop"))
			pv.add_child(lb)
		set_drag_preview(pv)
		return drag_payload
