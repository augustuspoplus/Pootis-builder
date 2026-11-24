class_name Tf2HudWidgets
extends RefCounted

## Custom Valve TF2 In-Game HUD Widgets for Godot 4
## Exact visual parity with Build A's sleek charcoal + 4px amber bottom-lip aesthetic,
## crisp isometric 3D piece icons, RED/BLU team spawn crests, and live 3D viewport badges.

const COL_BG_HUD := Color(29.0 / 255.0, 25.0 / 255.0, 22.0 / 255.0, 0.94)
const COL_BD_HUD := Color(87.0 / 255.0, 76.0 / 255.0, 65.0 / 255.0, 0.96)
const COL_LIP_AMB := Color(207.0 / 255.0, 115.0 / 255.0, 54.0 / 255.0, 1.0)
const COL_SLOT_BG := Color(43.0 / 255.0, 38.0 / 255.0, 33.0 / 255.0, 0.95)
const COL_SLOT_HOV := Color(59.0 / 255.0, 51.0 / 255.0, 44.0 / 255.0, 0.97)
const COL_SLOT_ACT := Color(71.0 / 255.0, 54.0 / 255.0, 36.0 / 255.0, 0.98)
const COL_SLOT_BD := Color(82.0 / 255.0, 72.0 / 255.0, 62.0 / 255.0, 0.95)
const COL_ACC := Color(229.0 / 255.0, 135.0 / 255.0, 43.0 / 255.0, 1.0)
const COL_RED := Color(184.0 / 255.0, 56.0 / 255.0, 59.0 / 255.0, 1.0)
const COL_BLU := Color(76.0 / 255.0, 126.0 / 255.0, 160.0 / 255.0, 1.0)
const COL_CYAN := Color(0.0, 229.0 / 255.0, 1.0, 1.0)
const COL_TX := Color(240.0 / 255.0, 230.0 / 255.0, 210.0 / 255.0, 1.0)

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
		sb.border_width_left = 1
		sb.border_width_right = 1
		sb.border_width_top = 1
		sb.border_width_bottom = 1
		sb.corner_radius_top_left = int(radius)
		sb.corner_radius_top_right = int(radius)
		sb.corner_radius_bottom_left = int(radius)
		sb.corner_radius_bottom_right = int(radius)
		sb.shadow_color = Color(0, 0, 0, 0.42)
		sb.shadow_size = 10
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 7
		sb.content_margin_bottom = 10 if show_lip else 7
		add_theme_stylebox_override("panel", sb)

	func _draw() -> void:
		if show_lip:
			var r := Rect2(Vector2(2.0, size.y - 4.0), Vector2(max(0.0, size.x - 4.0), 3.5))
			draw_rect(r, lip_color, true)

class IsoIconCanvas extends Control:
	var piece_name: String = "Floor"
	var hot: bool = false
	var team_accent: int = 0   # 0 none, 1 RED, 2 BLU
	var is_tool: bool = false
	var tool_kind: String = "" # "Pull" or "Wire"

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
			# Crisp TF2 merc head + shoulders silhouette
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
				# Crisp 4-way Push/Pull cross arrows
				draw_line(c - Vector2(r, 0), c + Vector2(r, 0), col, 2.2, true)
				draw_line(c - Vector2(0, r), c + Vector2(0, r), col, 2.2, true)
				var a := 4.5
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r - 3), c + Vector2(-a, -r + 3), c + Vector2(a, -r + 3)]), col)
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, r + 3), c + Vector2(-a, r - 3), c + Vector2(a, r - 3)]), col)
				draw_colored_polygon(PackedVector2Array([c + Vector2(-r - 3, 0), c + Vector2(-r + 3, -a), c + Vector2(-r + 3, a)]), col)
				draw_colored_polygon(PackedVector2Array([c + Vector2(r + 3, 0), c + Vector2(r - 3, -a), c + Vector2(r - 3, a)]), col)
			else:
				# Crisp 3-node logic Wire diagram
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

		# Authentic Build A 3D Isometric Piece Vector Drawing
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
			"Seal":
				draw_box.call(-0.72, -0.72, -0.60, 0.72, 0.72, 0.60)
			_:
				draw_box.call(-0.68, -0.68, -0.55, 0.68, 0.68, 0.55)

class RailSlot extends Button:
	var iso_canvas: IsoIconCanvas
	var lbl: Label
	var team_accent: int = 0
	var is_active_slot: bool = false

	func _init(p_piece: String, p_label: String, p_tex: Texture2D, p_active: bool,
			p_team: int, p_is_tool: bool, p_tkind: String, p_font: Font) -> void:
		team_accent = p_team
		is_active_slot = p_active
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(64, 62)

		var bd_col := COL_ACC if p_active else (COL_RED if p_team == 1 else (COL_BLU if p_team == 2 else COL_SLOT_BD))
		var bg_col := COL_SLOT_ACT if p_active else COL_SLOT_BG

		var sn := StyleBoxFlat.new()
		sn.bg_color = bg_col
		sn.border_color = bd_col
		sn.set_border_width_all(2 if p_active else 1)
		sn.set_corner_radius_all(8)
		sn.content_margin_left = 2; sn.content_margin_right = 2
		sn.content_margin_top = 3; sn.content_margin_bottom = 2
		var sh := sn.duplicate()
		sh.bg_color = COL_SLOT_HOV
		sh.border_color = COL_ACC if not p_active else COL_ACC
		add_theme_stylebox_override("normal", sn)
		add_theme_stylebox_override("hover", sh)
		add_theme_stylebox_override("pressed", sh)

		var vb := VBoxContainer.new()
		vb.set_anchors_preset(Control.PRESET_FULL_RECT)
		vb.add_theme_constant_override("separation", 0)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vb)

		if p_tex != null:
			var tr := TextureRect.new()
			tr.texture = p_tex
			tr.custom_minimum_size = Vector2(56, 40)
			tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			vb.add_child(tr)
		else:
			iso_canvas = IsoIconCanvas.new(p_piece, p_active, p_team, p_is_tool, p_tkind)
			iso_canvas.custom_minimum_size = Vector2(56, 40)
			iso_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
			vb.add_child(iso_canvas)

		lbl = Label.new()
		lbl.text = p_label
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_override("font", p_font)
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", COL_ACC if p_active else COL_TX)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(lbl)

class ViewportOverlay extends Control:
	var owner_ed: Node3D

	func _init(p_owner: Node3D) -> void:
		owner_ed = p_owner
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if owner_ed == null:
			return
		owner_ed.draw_viewport_2d_overlay(self)
