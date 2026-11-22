class_name EditorDrawers
extends RefCounted

## Modular Valve Hammer++ / TrenchBroom Drawer Builders for Pootis Builder 2.0!
## Keeps MainApp.gd clean while powering:
##  - Shift+A Face Edit Sheet (UV Scale/Shift/Rot, Lightmap Scale, Justify, Align, Replace, All 29k+ VPK Swatches)
##  - 3D TF2 Prop Browser (Curated + ALL 7,000+ TF2 .mdl Search + Live 3D Spinning Preview)
##  - Shift+E All-450+ FGD Entity Browser (base.fgd + tf.fgd + tf-abs.fgd)
##  - Alt+Enter 4-Tab SmartEdit Object Properties (Class Info + FGD Choices/Flags + Outputs/Inputs + Mini 2D Blueprint)
##  - Vertical Cliff & Displacement Terrain Studio (Normal/World Axis, Paint Alpha Blend, Noise, Sew, Subdivide)
##  - Alt+P Check Map for Problems (Go To Error + 1-Click Fix)
##  - VisGroups, Clip Tool, Tie to Entity, Building Wizard, Skybox/Sun, Compile (CmdSeq.wc presets)

const HudWidgets         = preload("res://scripts/ui/Tf2HudWidgets.gd")
const Tf2CatalogScript   = preload("res://scripts/core/Tf2Catalog.gd")
const Tf2GamemodesScript = preload("res://scripts/core/Tf2Gamemodes.gd")
const Blueprint2DScript  = preload("res://scripts/ui/Blueprint2DView.gd")

static func _lbl(text: String, font: Font, sz: int = 12, col: Color = HudWidgets.COL_TX) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	return l

static func _sec(vbox: VBoxContainer, text: String, fonts: Dictionary) -> void:
	vbox.add_child(_lbl(text, fonts["heading"], 11, HudWidgets.COL_ACC))

# ==============================================================================
# 1. FULL HAMMER FACE EDIT SHEET (Shift+A) + ALL 29,000+ TF2 VPK MATERIALS!
# ==============================================================================
static func build_materials_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	# Active Material Header
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	vbox.add_child(top)

	var pv := TextureRect.new()
	pv.custom_minimum_size = Vector2(58, 58)
	pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv.stretch_mode = TextureRect.STRETCH_SCALE
	pv.texture = app.assets.get_material_swatch(app.active_material)
	top.add_child(pv)

	var ivb := VBoxContainer.new()
	ivb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(ivb)
	ivb.add_child(_lbl(app.active_material, fonts["heading"], 11, HudWidgets.COL_ACC))
	ivb.add_child(_lbl("Drag Swatch onto 3D Face  |  Shift+Drop = Solid", fonts["body"], 10, HudWidgets.COL_TX_MUTED))

	var act_row := HBoxContainer.new(); act_row.add_theme_constant_override("separation", 4); ivb.add_child(act_row)
	var ap_b := Button.new(); ap_b.text = "Apply Solid"
	HudWidgets.style_tf2_button(ap_b, fonts["body"], 10, true)
	ap_b.pressed.connect(func():
		if app.selected_solid >= 0:
			app.doc.set_solid_material(app.selected_solid, app.active_material)
			app._commit_solid_edit("Apply Material")
	)
	act_row.add_child(ap_b)

	var rep_b := Button.new(); rep_b.text = "Replace"
	rep_b.tooltip_text = "Replace selected solid's material map-wide with active material"
	HudWidgets.style_tf2_button(rep_b, fonts["body"], 10)
	rep_b.pressed.connect(func():
		if app.selected_solid >= 0:
			var si: Dictionary = app.doc.get_solid_info(app.selected_solid)
			var old_m: String = str(si.get("material", ""))
			if not old_m.is_empty():
				var n: int = app.doc.replace_material(old_m, app.active_material)
				app._record_history("Replace Textures")
				app.map_sync.sync_all(true)
				app._toast("Replaced %d faces (%s -> %s)" % [n, old_m.get_file(), app.active_material.get_file()])
	)
	act_row.add_child(rep_b)

	var auto_b := Button.new(); auto_b.text = "Auto-Biome"
	auto_b.tooltip_text = "Auto-apply active biome roof/floor/wall textures to selected solid(s)"
	HudWidgets.style_tf2_button(auto_b, fonts["body"], 10, false, 3)
	auto_b.pressed.connect(func(): app._auto_texture_selected_solids())
	act_row.add_child(auto_b)

	# Hammer Face UV Controls (Scale X/Y, Shift X/Y, Rot, Lightmap Scale, Justify, Align!)
	if app.selected_solid >= 0:
		var fidx: int = maxi(0, app.selected_face)
		var uv: Dictionary = app.doc.get_face_uv(app.selected_solid, fidx)
		if uv.get("ok", false):
			_sec(vbox, "FACE UV & LIGHTMAP (SOLID #%d FACE #%d)" % [app.selected_solid, fidx], fonts)
			var grid := GridContainer.new(); grid.columns = 2; grid.add_theme_constant_override("h_separation", 6); vbox.add_child(grid)
			var us := SpinBox.new(); us.min_value = 0.05; us.max_value = 8.0; us.step = 0.05; us.value = float(uv["u_scale"]); us.prefix = "Scale X: "
			var vs := SpinBox.new(); vs.min_value = 0.05; vs.max_value = 8.0; vs.step = 0.05; vs.value = float(uv["v_scale"]); vs.prefix = "Scale Y: "
			var ux := SpinBox.new(); ux.min_value = -512; ux.max_value = 512; ux.step = 8; ux.value = float(uv["u_shift"]); ux.prefix = "Shift X: "
			var vx := SpinBox.new(); vx.min_value = -512; vx.max_value = 512; vx.step = 8; vx.value = float(uv["v_shift"]); vx.prefix = "Shift Y: "
			var rot := SpinBox.new(); rot.min_value = -360; rot.max_value = 360; rot.step = 15; rot.value = float(uv["rotation"]); rot.prefix = "Rot: "
			var lm := SpinBox.new(); lm.min_value = 4; lm.max_value = 128; lm.step = 4; lm.value = float(uv["lightmap_scale"]); lm.prefix = "LM: "
			for sb: SpinBox in [us, vs, ux, vx, rot, lm]:
				sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				grid.add_child(sb)
			var apply_uv := func(_v: float) -> void:
				app.doc.set_face_uv(app.selected_solid, fidx, us.value, vs.value, ux.value, vx.value, rot.value, lm.value)
				app.map_sync.sync_solid(app.selected_solid)
			for sb: SpinBox in [us, vs, ux, vx, rot, lm]:
				sb.value_changed.connect(apply_uv)

			var jrow := HBoxContainer.new(); jrow.add_theme_constant_override("separation", 3); vbox.add_child(jrow)
			var jmodes := [{"t": "Fit", "m": 0}, {"t": "T", "m": 1}, {"t": "B", "m": 2}, {"t": "L", "m": 3}, {"t": "R", "m": 4}, {"t": "C", "m": 5}]
			for jm in jmodes:
				var jb := Button.new(); jb.text = jm["t"]
				HudWidgets.style_tf2_button(jb, fonts["body"], 10, jm["m"] == 0)
				var mid: int = jm["m"]
				jb.pressed.connect(func():
					app.doc.justify_face_uv(app.selected_solid, fidx, mid)
					app._record_history("Justify UV")
					app.map_sync.sync_solid(app.selected_solid)
				)
				jrow.add_child(jb)
			var aw := Button.new(); aw.text = "World"
			HudWidgets.style_tf2_button(aw, fonts["body"], 10, false, 3)
			aw.pressed.connect(func(): app.doc.align_face_uv(app.selected_solid, fidx, false); app.map_sync.sync_solid(app.selected_solid))
			jrow.add_child(aw)
			var af := Button.new(); af.text = "Face"
			HudWidgets.style_tf2_button(af, fonts["body"], 10)
			af.pressed.connect(func(): app.doc.align_face_uv(app.selected_solid, fidx, true); app.map_sync.sync_solid(app.selected_solid))
			jrow.add_child(af)

	# Curated vs ALL 29,000+ TF2 VPK Textures Mode Switcher!
	var mode_row := HBoxContainer.new(); mode_row.add_theme_constant_override("separation", 4); vbox.add_child(mode_row)
	var b_cur := Button.new(); b_cur.text = "Curated TF2"; b_cur.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudWidgets.style_tf2_button(b_cur, fonts["heading"], 10, not app._mat_browse_all)
	b_cur.pressed.connect(func(): app._mat_browse_all = false; app._open_materials_drawer())
	mode_row.add_child(b_cur)
	var b_all := Button.new(); b_all.text = "ALL 29k+ VPK"; b_all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudWidgets.style_tf2_button(b_all, fonts["heading"], 10, app._mat_browse_all)
	b_all.pressed.connect(func(): app._mat_browse_all = true; app._open_materials_drawer())
	mode_row.add_child(b_all)

	var search := LineEdit.new()
	search.placeholder_text = "Search 29k+ TF2 textures (wood, brick, blend...)"
	search.text = app._mat_search_text
	vbox.add_child(search)

	# Recently Used Materials Quick Strip (1-click reuse without re-searching!)
	if app.recent_materials.size() > 0:
		var rcard := HudWidgets.make_section_card("RECENTLY USED MATERIALS", fonts, HudWidgets.COL_CYAN)
		vbox.add_child(rcard["panel"])
		var rrow := HFlowContainer.new()
		rrow.add_theme_constant_override("h_separation", 4)
		rrow.add_theme_constant_override("v_separation", 4)
		(rcard["vbox"] as VBoxContainer).add_child(rrow)
		for rm in app.recent_materials:
			var rmp: String = str(rm)
			var rb := Button.new()
			rb.custom_minimum_size = Vector2(36, 36)
			rb.tooltip_text = rmp
			HudWidgets.style_tf2_button(rb, fonts["body"], 9, str(app.active_material).to_lower() == rmp.to_lower())
			var rsw := TextureRect.new()
			rsw.set_anchors_preset(Control.PRESET_FULL_RECT)
			rsw.offset_left = 3; rsw.offset_right = -3; rsw.offset_top = 3; rsw.offset_bottom = -3
			rsw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			rsw.stretch_mode = TextureRect.STRETCH_SCALE
			rsw.mouse_filter = Control.MOUSE_FILTER_IGNORE
			app.assets.request_material_swatch_async(rmp, rsw)
			rb.add_child(rsw)
			rb.pressed.connect(func():
				app.active_material = rmp; app.active_tool = "paint"; app.audio.play("click"); app._open_materials_drawer()
			)
			rrow.add_child(rb)

	var list_root := VBoxContainer.new()
	list_root.add_theme_constant_override("separation", 6)
	vbox.add_child(list_root)

	var add_swatch_btn := func(g: GridContainer, label: String, mp: String) -> void:
		var is_act: bool = (str(app.active_material).to_lower() == mp.to_lower())
		var b := HudWidgets.DraggableSwatchButton.new()
		b.mat_path = mp
		b.custom_minimum_size = Vector2(0, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.tooltip_text = "%s\nDrag directly onto any 3D wall/floor face (Shift+Drop = whole solid)!" % mp
		HudWidgets.style_tf2_button(b, fonts["body"], 10, is_act)
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 4; hb.offset_right = -4; hb.offset_top = 4; hb.offset_bottom = -4
		hb.add_theme_constant_override("separation", 6)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(hb)
		var sw := TextureRect.new()
		sw.custom_minimum_size = Vector2(38, 38)
		sw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sw.stretch_mode = TextureRect.STRETCH_SCALE
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.swatch_rect = sw
		# Async non-blocking VTF decode — zero main-thread hitch when scrolling 31,506 materials!
		app.assets.request_material_swatch_async(mp, sw)
		hb.add_child(sw)
		var nl := Label.new()
		nl.text = label
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nl.add_theme_font_override("font", fonts["body"])
		nl.add_theme_font_size_override("font_size", 10)
		nl.add_theme_color_override("font_color", Color(0.10, 0.07, 0.04) if is_act else HudWidgets.COL_TX)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(nl)
		b.pressed.connect(func():
			app.active_material = mp
			app.active_tool = "paint"
			app._track_recent_material(mp)
			app.audio.play("click")
			app._open_materials_drawer()
		)
		g.add_child(b)

	var populate := func(flt: String) -> void:
		app._mat_search_text = flt
		for ch in list_root.get_children():
			ch.queue_free()
		var fl := flt.to_lower().strip_edges()
		if app._mat_browse_all or fl.length() >= 3:
			var found: PackedStringArray = app.core.search_materials(fl, 42)
			list_root.add_child(_lbl("LIVE TF2 VPK RESULTS (%d shown — type to narrow):" % found.size(), fonts["heading"], 10, HudWidgets.COL_CYAN))
			var g := GridContainer.new(); g.columns = 2; g.add_theme_constant_override("h_separation", 4); g.add_theme_constant_override("v_separation", 4); list_root.add_child(g)
			for m in found:
				add_swatch_btn.call(g, str(m).get_file(), str(m))
			return
		for cat in Tf2CatalogScript.MATERIAL_CATEGORIES.keys():
			var items: Array = []
			for item in Tf2CatalogScript.MATERIAL_CATEGORIES[cat]:
				if fl.is_empty() or str(item["name"]).to_lower().find(fl) != -1 or str(item["mat"]).to_lower().find(fl) != -1:
					items.append(item)
			if items.is_empty():
				continue
			_sec(list_root, str(cat).to_upper(), fonts)
			var g := GridContainer.new(); g.columns = 2; g.add_theme_constant_override("h_separation", 4); g.add_theme_constant_override("v_separation", 4); list_root.add_child(g)
			for item in items:
				add_swatch_btn.call(g, str(item["name"]), str(item["mat"]))

	populate.call(app._mat_search_text)
	search.text_changed.connect(populate)

# ==============================================================================
# 2. ORGANIZED VISUAL 3D TF2 PROP BROWSER (Category Boxes + 16,697 VPK Models!)
# ==============================================================================
static func build_props_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts

	# Search bar + Saved Favorites toggle
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	vbox.add_child(top_row)

	var search := LineEdit.new()
	search.placeholder_text = "Search 16,697 TF2 props (snow, pine, crate, barrel...)"
	search.text = app._prop_search_text
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(search)

	var fav_btn := Button.new()
	fav_btn.text = "Saved (%d)" % app._prop_favorites.size()
	HudWidgets.style_tf2_button(fav_btn, fonts["heading"], 10, app._prop_favorites_only)
	fav_btn.pressed.connect(func():
		app.audio.play("click")
		app._prop_favorites_only = not app._prop_favorites_only
		if app._prop_favorites_only:
			app._prop_active_cat = ""
		app._open_props_drawer()
	)
	top_row.add_child(fav_btn)

	# Breadcrumb / Active Box Header when inside a Category Box or Favorites
	var showing_grid: bool = app._prop_favorites_only or not app._prop_active_cat.is_empty() or app._prop_search_text.strip_edges().length() >= 2
	if showing_grid:
		var bc_row := HBoxContainer.new()
		bc_row.add_theme_constant_override("separation", 6)
		vbox.add_child(bc_row)

		var back_b := Button.new()
		back_b.text = "< All Prop Boxes"
		HudWidgets.style_tf2_button(back_b, fonts["heading"], 10)
		back_b.pressed.connect(func():
			app.audio.play("click")
			app._prop_active_cat = ""
			app._prop_favorites_only = false
			app._prop_search_text = ""
			app._open_props_drawer()
		)
		bc_row.add_child(back_b)

		var cat_lbl := "SAVED FAVORITES" if app._prop_favorites_only else (
			str(Tf2CatalogScript.get_prop_box(app._prop_active_cat).get("name", "SEARCH RESULTS")).to_upper()
			if not app._prop_active_cat.is_empty() else "SEARCH RESULTS"
		)
		var bl := _lbl(cat_lbl, fonts["heading"], 12, HudWidgets.COL_ACC)
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		bc_row.add_child(bl)

	# Compact Live Rotating 3D Valve .mdl Preview (when browsing props)
	var pv_row := HBoxContainer.new()
	pv_row.add_theme_constant_override("separation", 8)
	vbox.add_child(pv_row)

	var pv_frame := PanelContainer.new()
	pv_frame.custom_minimum_size = Vector2(96, 86)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.09, 0.08, 0.07, 1.0)
	psb.border_color = HudWidgets.COL_ACC
	psb.set_border_width_all(1); psb.set_corner_radius_all(8)
	pv_frame.add_theme_stylebox_override("panel", psb)
	pv_row.add_child(pv_frame)

	var svc := SubViewportContainer.new()
	svc.stretch = true; svc.custom_minimum_size = Vector2(92, 82)
	pv_frame.add_child(svc)
	var svp := SubViewport.new()
	svp.own_world_3d = true; svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(svp)
	var pwe := WorldEnvironment.new()
	var penv := Environment.new()
	penv.background_mode = Environment.BG_COLOR; penv.background_color = Color(0.11, 0.10, 0.09)
	penv.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	penv.ambient_light_color = Color(0.90, 0.88, 0.84); penv.ambient_light_energy = 1.1
	pwe.environment = penv; svp.add_child(pwe)
	var pl := DirectionalLight3D.new(); pl.rotation_degrees = Vector3(-35, 42, 0); pl.light_energy = 1.5; svp.add_child(pl)
	var pcam := Camera3D.new(); pcam.fov = 40.0; svp.add_child(pcam)
	var pmesh: ArrayMesh = app.assets.get_model_mesh(app.active_prop_mdl)
	var pmi := MeshInstance3D.new(); pmi.mesh = pmesh; svp.add_child(pmi)
	app._prop_preview_mesh = pmi
	if pmesh != null:
		var aabb := pmesh.get_aabb()
		var center := aabb.position + aabb.size * 0.5
		var rad := maxf(aabb.size.length() * 0.60, 0.55)
		pmi.position = -center
		pcam.look_at_from_position(Vector3(rad * 1.15, rad * 0.65, rad * 1.15), Vector3.ZERO, Vector3.UP)
	else:
		pcam.look_at_from_position(Vector3(2.5, 1.5, 2.5), Vector3.ZERO, Vector3.UP)

	var pv_info := VBoxContainer.new()
	pv_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pv_info.add_theme_constant_override("separation", 3)
	pv_row.add_child(pv_info)
	pv_info.add_child(_lbl("ACTIVE PROP", fonts["heading"], 10, HudWidgets.COL_ACC))
	pv_info.add_child(_lbl(app.active_prop_mdl.get_file().get_basename().replace("_", " ").capitalize(), fonts["heading"], 13, HudWidgets.COL_TX))
	pv_info.add_child(_lbl(app.active_prop_mdl, fonts["mono"], 9, HudWidgets.COL_TX_MUTED))
	pv_info.add_child(_lbl("Drag any 3D card onto the map or click to stamp!", fonts["body"], 10, HudWidgets.COL_GREEN))

	# Main Content Area: EITHER Organized Category Boxes OR 3D Prop Grid!
	var list_root := VBoxContainer.new()
	list_root.add_theme_constant_override("separation", 8)
	vbox.add_child(list_root)

	var make_prop_card := func(parent_grid: GridContainer, nm: String, mp: String) -> void:
		var is_sel: bool = (app.active_prop_mdl == mp)
		var is_fav: bool = app._prop_favorites.has(mp)
		var card := HudWidgets.DraggablePropCard.new()
		card.custom_minimum_size = Vector2(118, 122)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.tooltip_text = "%s\n(%s)\nClick to select or drag into 3D!" % [nm, mp]
		card.drag_payload = {"kind": "prop", "mdl": mp, "name": nm}
		var sb_n := StyleBoxFlat.new()
		sb_n.bg_color = Color(0.24, 0.19, 0.14, 0.98) if is_sel else HudWidgets.COL_BG_CARD
		sb_n.border_color = HudWidgets.COL_ACC if is_sel else HudWidgets.COL_SLOT_BD
		sb_n.set_border_width_all(2 if is_sel else 1)
		sb_n.set_corner_radius_all(8)
		var sb_h := sb_n.duplicate()
		sb_h.bg_color = HudWidgets.COL_SLOT_HOV
		sb_h.border_color = HudWidgets.COL_ACC
		card.add_theme_stylebox_override("normal", sb_n)
		card.add_theme_stylebox_override("hover", sb_h)
		card.add_theme_stylebox_override("pressed", sb_h)
		card.focus_mode = Control.FOCUS_NONE

		var cvb := VBoxContainer.new()
		cvb.set_anchors_preset(Control.PRESET_FULL_RECT)
		cvb.offset_left = 5; cvb.offset_right = -5; cvb.offset_top = 5; cvb.offset_bottom = -5
		cvb.add_theme_constant_override("separation", 3)
		cvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(cvb)

		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(72, 74)
		tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic: Texture2D = app.icon_cache.get_icon(mp) if app.icon_cache != null else null
		if ic != null:
			tr.texture = ic
			card.drag_icon = ic
		elif app.icon_cache != null:
			# Update card texture live as soon as the 3D icon baker finishes this .mdl!
			var weak_tr: WeakRef = weakref(tr)
			var weak_card: WeakRef = weakref(card)
			app.icon_cache.icon_ready.connect(func(k: String, tex: Texture2D):
				if k == mp:
					var t_obj = weak_tr.get_ref()
					var c_obj = weak_card.get_ref()
					if t_obj != null:
						t_obj.texture = tex
					if c_obj != null:
						c_obj.drag_icon = tex
			)
		cvb.add_child(tr)

		var nl := Label.new()
		nl.text = nm
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nl.clip_text = true
		nl.add_theme_font_override("font", fonts["body"])
		nl.add_theme_font_size_override("font_size", 10)
		nl.add_theme_color_override("font_color", HudWidgets.COL_ACC if is_sel else HudWidgets.COL_TX)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cvb.add_child(nl)

		# Top-right Favorite Star button
		var star_b := Button.new()
		star_b.text = "*" if is_fav else "+"
		star_b.tooltip_text = "Remove from Saved Favorites" if is_fav else "Save to Favorites"
		star_b.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		star_b.offset_left = -24; star_b.offset_right = -3; star_b.offset_top = 3; star_b.offset_bottom = 22
		star_b.focus_mode = Control.FOCUS_NONE
		var sbs := StyleBoxFlat.new()
		sbs.bg_color = HudWidgets.COL_ACC if is_fav else Color(0.12, 0.10, 0.09, 0.78)
		sbs.set_corner_radius_all(5)
		star_b.add_theme_stylebox_override("normal", sbs)
		star_b.add_theme_stylebox_override("hover", sbs)
		star_b.add_theme_font_size_override("font_size", 11)
		star_b.add_theme_color_override("font_color", Color(0.10, 0.07, 0.04) if is_fav else HudWidgets.COL_TX_MUTED)
		star_b.pressed.connect(func():
			app.audio.play("click")
			if app._prop_favorites.has(mp):
				app._prop_favorites.erase(mp)
			else:
				app._prop_favorites.append(mp)
			Tf2CatalogScript.save_prop_favorites(app._prop_favorites)
			app._open_props_drawer()
		)
		card.add_child(star_b)

		card.pressed.connect(func():
			app.active_prop_mdl = mp
			app.active_tool = "place_prop"
			app.audio.play("click")
			app._refresh_context_bar()
			app._toast("Click in 3D (or drag card) to place " + nm)
			app._open_props_drawer()
		)
		parent_grid.add_child(card)

	var populate := func(flt: String) -> void:
		app._prop_search_text = flt
		for ch in list_root.get_children():
			ch.queue_free()
		var fl := flt.to_lower().strip_edges()

		# Case A: Favorites view
		if app._prop_favorites_only:
			if app._prop_favorites.is_empty():
				list_root.add_child(_lbl("No saved props yet! Click the '+' badge on any prop card to favorite it.", fonts["body"], 11, HudWidgets.COL_TX_MUTED))
				return
			var fg := GridContainer.new(); fg.columns = 3; fg.add_theme_constant_override("h_separation", 6); fg.add_theme_constant_override("v_separation", 6)
			list_root.add_child(fg)
			for mp in app._prop_favorites:
				if not fl.is_empty() and mp.to_lower().find(fl) == -1:
					continue
				make_prop_card.call(fg, mp.get_file().get_basename().replace("_", " ").capitalize(), mp)
			return

		# Case B: Global search across all 16,697 VPK models (when not inside a specific box)
		if app._prop_active_cat.is_empty() and fl.length() >= 2:
			var found: PackedStringArray = app.core.search_models(fl, 45)
			list_root.add_child(_lbl("LIVE VPK SEARCH (%d props matching '%s'):" % [found.size(), fl], fonts["heading"], 10, HudWidgets.COL_CYAN))
			var sg := GridContainer.new(); sg.columns = 3; sg.add_theme_constant_override("h_separation", 6); sg.add_theme_constant_override("v_separation", 6)
			list_root.add_child(sg)
			for m in found:
				var mp := str(m)
				make_prop_card.call(sg, mp.get_file().get_basename().replace("_", " ").capitalize(), mp)
			return

		# Case C: Organized Category Folder Boxes Grid! (Winter, Trees, Crates, Rocks, Industrial, Spytech, Lights, Medieval, Gameplay)
		if app._prop_active_cat.is_empty():
			_sec(list_root, "ORGANIZED PROP BOXES (CLICK A CATEGORY TO BROWSE)", fonts)
			var bg := GridContainer.new()
			bg.columns = 2
			bg.add_theme_constant_override("h_separation", 8)
			bg.add_theme_constant_override("v_separation", 8)
			list_root.add_child(bg)

			for box in Tf2CatalogScript.PROP_FOLDER_BOXES:
				var cid: String = str(box["id"])
				var cname: String = str(box["name"])
				var csub: String = str(box["subtitle"])
				var ccol: Color = box["color"]
				var cicon: String = str(box["icon"])

				var btn := Button.new()
				btn.custom_minimum_size = Vector2(0, 72)
				btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				btn.focus_mode = Control.FOCUS_NONE
				var sb := StyleBoxFlat.new()
				sb.bg_color = HudWidgets.COL_BG_CARD
				sb.border_color = HudWidgets.COL_SLOT_BD
				sb.border_width_left = 4
				sb.border_width_top = 1; sb.border_width_right = 1; sb.border_width_bottom = 1
				sb.border_color = ccol
				sb.set_corner_radius_all(8)
				var sbh := sb.duplicate()
				sbh.bg_color = HudWidgets.COL_SLOT_HOV
				sbh.border_color = HudWidgets.COL_ACC
				btn.add_theme_stylebox_override("normal", sb)
				btn.add_theme_stylebox_override("hover", sbh)
				btn.add_theme_stylebox_override("pressed", sbh)

				var hb := HBoxContainer.new()
				hb.set_anchors_preset(Control.PRESET_FULL_RECT)
				hb.offset_left = 10; hb.offset_right = -8; hb.offset_top = 6; hb.offset_bottom = -6
				hb.add_theme_constant_override("separation", 8)
				hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
				btn.add_child(hb)

				var tr := TextureRect.new()
				tr.custom_minimum_size = Vector2(46, 46)
				tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
				if app.icon_cache != null:
					tr.texture = app.icon_cache.get_icon(cicon)
				hb.add_child(tr)

				var tvb := VBoxContainer.new()
				tvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				tvb.alignment = BoxContainer.ALIGNMENT_CENTER
				tvb.add_theme_constant_override("separation", 2)
				tvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
				hb.add_child(tvb)

				var t1 := _lbl(cname, fonts["heading"], 11, HudWidgets.COL_TX)
				t1.mouse_filter = Control.MOUSE_FILTER_IGNORE
				tvb.add_child(t1)
				var t2 := _lbl(csub, fonts["body"], 9, HudWidgets.COL_TX_MUTED)
				t2.mouse_filter = Control.MOUSE_FILTER_IGNORE
				tvb.add_child(t2)

				btn.pressed.connect(func():
					app.audio.play("click")
					app._prop_active_cat = cid
					app._open_props_drawer()
				)
				bg.add_child(btn)
			return

		# Case D: Inside a selected Category Box -> 3-column Visual 3D Prop Grid!
		var items: Array[Dictionary] = Tf2CatalogScript.get_props_for_box(app.core, app._prop_active_cat, fl, 48)
		if items.is_empty():
			list_root.add_child(_lbl("No props found in this box matching '%s'." % fl, fonts["body"], 11, HudWidgets.COL_TX_MUTED))
			return
		var pg := GridContainer.new()
		pg.columns = 3
		pg.add_theme_constant_override("h_separation", 6)
		pg.add_theme_constant_override("v_separation", 6)
		list_root.add_child(pg)
		for it in items:
			make_prop_card.call(pg, str(it["name"]), str(it["mdl"]))

	populate.call(app._prop_search_text)
	search.text_changed.connect(populate)

	# PLACEMENT OPTIONS FOOTER CARD (Team Skin, Random Yaw, Snap Normal, Scale, Rotate!)
	var opt_card := PanelContainer.new()
	var osb := StyleBoxFlat.new()
	osb.bg_color = Color(0.08, 0.07, 0.06, 0.96)
	osb.border_color = HudWidgets.COL_SLOT_BD
	osb.set_border_width_all(1); osb.set_corner_radius_all(8)
	osb.set_content_margin_all(10)
	opt_card.add_theme_stylebox_override("panel", osb)
	vbox.add_child(opt_card)

	var ovb := VBoxContainer.new()
	ovb.add_theme_constant_override("separation", 6)
	opt_card.add_child(ovb)
	_sec(ovb, "PLACEMENT OPTIONS", fonts)

	var skin_row := HBoxContainer.new(); skin_row.add_theme_constant_override("separation", 5); ovb.add_child(skin_row)
	var slbl := _lbl("Team Skin:", fonts["body"], 11, HudWidgets.COL_TX)
	slbl.custom_minimum_size = Vector2(76, 0)
	skin_row.add_child(slbl)
	var skin_opts := [{"t": "Neutral", "v": 0, "team": 0}, {"t": "RED", "v": 1, "team": 2}, {"t": "BLU", "v": 2, "team": 3}]
	for so in skin_opts:
		var sb_btn := Button.new()
		sb_btn.text = so["t"]
		sb_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(sb_btn, fonts["heading"], 10, app.prop_skin == int(so["v"]), int(so["team"]))
		var sv: int = int(so["v"])
		sb_btn.pressed.connect(func(): app.audio.play("click"); app.prop_skin = sv; app._open_props_drawer())
		skin_row.add_child(sb_btn)

	var ry_cb := CheckButton.new()
	ry_cb.text = "Random Yaw (Trees / Rocks)"
	ry_cb.button_pressed = app.prop_random_yaw
	ry_cb.toggled.connect(func(on: bool): app.prop_random_yaw = on)
	ovb.add_child(ry_cb)

	var sn_cb := CheckButton.new()
	sn_cb.text = "Snap to Surface Normal"
	sn_cb.button_pressed = app.prop_snap_normal
	sn_cb.toggled.connect(func(on: bool): app.prop_snap_normal = on)
	ovb.add_child(sn_cb)

	var sr_row := HBoxContainer.new(); sr_row.add_theme_constant_override("separation", 6); ovb.add_child(sr_row)
	var sc_minus := Button.new(); sc_minus.text = "-"
	HudWidgets.style_tf2_button(sc_minus, fonts["heading"], 11)
	var sc_lbl := _lbl("Scale: %.2fx" % app.prop_scale, fonts["mono"], 11, HudWidgets.COL_TX)
	var sc_plus := Button.new(); sc_plus.text = "+"
	HudWidgets.style_tf2_button(sc_plus, fonts["heading"], 11)
	sc_minus.pressed.connect(func(): app.prop_scale = maxf(0.25, snappedf(app.prop_scale - 0.25, 0.25)); sc_lbl.text = "Scale: %.2fx" % app.prop_scale)
	sc_plus.pressed.connect(func(): app.prop_scale = minf(4.0, snappedf(app.prop_scale + 0.25, 0.25)); sc_lbl.text = "Scale: %.2fx" % app.prop_scale)
	sr_row.add_child(sc_minus); sr_row.add_child(sc_lbl); sr_row.add_child(sc_plus)

	var rot_b := Button.new()
	rot_b.text = "Yaw: %d° (R)" % int(app.prop_yaw_deg)
	rot_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudWidgets.style_tf2_button(rot_b, fonts["body"], 10)
	rot_b.pressed.connect(func():
		app.prop_yaw_deg = fmod(app.prop_yaw_deg + 90.0, 360.0)
		rot_b.text = "Yaw: %d° (R)" % int(app.prop_yaw_deg)
		app.audio.play("click")
	)
	sr_row.add_child(rot_b)

# ==============================================================================
# 3. ALL-452 TF2 FGD ENTITY BROWSER (Grouped Boxes + Icons for Every Entity!)
# ==============================================================================
static func build_fgd_entity_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	vbox.add_child(_lbl("All %d Valve TF2 + ABS FGD entities organized with clear icons. Active: %s" % [
		app.core.get_fgd_class_count(), app.active_fgd_entity
	], fonts["body"], 11, HudWidgets.COL_TX_MUTED))

	var search := LineEdit.new()
	search.placeholder_text = "Search all 452 TF2 entities (door, light, relay, spawn, trigger...)"
	search.text = app._ent_search_text
	vbox.add_child(search)

	# 8 Grouped Entity Category Chips
	var cgrid := GridContainer.new(); cgrid.columns = 4
	cgrid.add_theme_constant_override("h_separation", 4); cgrid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(cgrid)
	for box in Tf2CatalogScript.ENTITY_FOLDER_BOXES:
		var bid: String = str(box["id"])
		var b := Button.new()
		b.text = str(box["short"])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["heading"], 9, app._dock_ent_cat == bid)
		b.pressed.connect(func():
			app.audio.play("click")
			app._dock_ent_cat = bid
			app._dock_ent_page = 0
			app._rebuild_bottom_dock()
			app._open_fgd_entity_drawer()
		)
		cgrid.add_child(b)

	var list_root := VBoxContainer.new(); list_root.add_theme_constant_override("separation", 5); vbox.add_child(list_root)

	var add_ent_row := func(nm: String, cs: String, desc: String, itype: String, ikey: String, preset: String) -> void:
		var is_act: bool = (app.active_fgd_entity == cs and app.active_tool == "place_fgd_entity")
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["body"], 10, is_act)
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 6; hb.offset_right = -6; hb.offset_top = 4; hb.offset_bottom = -4
		hb.add_theme_constant_override("separation", 8)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(hb)
		if itype == "mdl" and app.icon_cache != null:
			var tr := TextureRect.new()
			tr.custom_minimum_size = Vector2(36, 36)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.texture = app.icon_cache.get_icon(ikey)
			hb.add_child(tr)
		else:
			var eic := HudWidgets.EntityBadgeIcon.new(ikey)
			eic.custom_minimum_size = Vector2(36, 36)
			hb.add_child(eic)
		var tvb := VBoxContainer.new()
		tvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tvb.alignment = BoxContainer.ALIGNMENT_CENTER
		tvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(tvb)
		var l1 := _lbl("%s  (%s)" % [nm, cs], fonts["heading"], 10, Color(0.10, 0.07, 0.04) if is_act else HudWidgets.COL_TX)
		l1.mouse_filter = Control.MOUSE_FILTER_IGNORE; tvb.add_child(l1)
		var l2 := _lbl(desc, fonts["body"], 9, Color(0.20, 0.14, 0.08) if is_act else HudWidgets.COL_TX_MUTED)
		l2.mouse_filter = Control.MOUSE_FILTER_IGNORE; tvb.add_child(l2)
		b.pressed.connect(func():
			app.audio.play("click")
			if not preset.is_empty():
				app.set_stage(app.Stage.GAMEPLAY)
				app._select_tool(preset)
			else:
				app.active_fgd_entity = cs
				app.active_tool = "place_fgd_entity"
				app._toast("Click in 3D to place %s (%s)" % [nm, cs])
			app._open_fgd_entity_drawer()
		)
		list_root.add_child(b)

	var populate := func(flt: String) -> void:
		app._ent_search_text = flt
		for ch in list_root.get_children():
			ch.queue_free()
		var fl := flt.strip_edges()
		if not fl.is_empty():
			var classes: PackedStringArray = app.core.list_fgd_point_classes(fl)
			var shown := 0
			for cls in classes:
				if shown >= 45: break
				var cs := str(cls)
				var ic: Dictionary = Tf2CatalogScript.get_entity_icon_spec(cs)
				var pretty := cs.replace("info_", "").replace("env_", "").replace("logic_", "").replace("tf_", "").replace("_", " ").capitalize()
				add_ent_row.call(pretty, cs, "Valve TF2 FGD entity", str(ic["type"]), str(ic["key"]), "")
				shown += 1
			return
		var items: Array[Dictionary] = Tf2CatalogScript.get_entities_for_box(app.core, app._dock_ent_cat, 36)
		for it in items:
			add_ent_row.call(str(it["name"]), str(it["cls"]), str(it["desc"]), str(it["icon_type"]), str(it["icon"]), str(it.get("preset", "")))

	populate.call(app._ent_search_text)
	search.text_changed.connect(populate)

# ==============================================================================
# 4. HAMMER 4-TAB SMARTEDIT OBJECT PROPERTIES INSPECTOR (Alt+Enter!)
# ==============================================================================
static func build_inspector_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	if app.selected_solid >= 0:
		var info: Dictionary = app.doc.get_solid_info(app.selected_solid)
		var bmin: Vector3 = info.get("bounds_min", Vector3.ZERO)
		var bmax: Vector3 = info.get("bounds_max", Vector3.ZERO)
		var sz: Vector3 = (bmax - bmin) * 32.0
		_sec(vbox, "BRUSH SOLID #%d (%du x %du x %du)" % [app.selected_solid, int(round(sz.x)), int(round(sz.z)), int(round(sz.y))], fonts)
		vbox.add_child(_lbl("Material: %s\nType: %s" % [str(info.get("material", "")), "Displacement" if info.get("is_disp", false) else "World Solid"], fonts["mono"], 11, HudWidgets.COL_TX))

		var r1 := HBoxContainer.new(); r1.add_theme_constant_override("separation", 5); vbox.add_child(r1)
		var b_hol := Button.new(); b_hol.text = "Make Hollow (-16u)"; b_hol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b_hol, fonts["body"], 11)
		b_hol.pressed.connect(func(): app._do_hollow_selected())
		r1.add_child(b_hol)

		var b_tie := Button.new(); b_tie.text = "Tie to Entity (Ctrl+T)"; b_tie.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b_tie, fonts["body"], 11, true)
		b_tie.pressed.connect(func(): app._open_tie_entity_drawer())
		r1.add_child(b_tie)

		var r2 := HBoxContainer.new(); r2.add_theme_constant_override("separation", 5); vbox.add_child(r2)
		var b_disp := Button.new(); b_disp.text = "Make Face Displacement"; b_disp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b_disp, fonts["body"], 11)
		b_disp.pressed.connect(func():
			var fi: int = maxi(0, app.selected_face)
			if app.doc.create_displacement_on_face(app.selected_solid, fi, 3):
				app._commit_solid_edit("Create Displacement")
				app._toast("Converted face #%d into sculptable Power-3 Displacement!" % fi)
		)
		r2.add_child(b_disp)

		var b_hide := Button.new(); b_hide.text = "QuickHide (H)"; b_hide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b_hide, fonts["body"], 11)
		b_hide.pressed.connect(func(): app._do_quickhide_selected())
		r2.add_child(b_hide)

		# Embedded Live Mini 2D Blueprint right inside the Inspector (matches Mockup 1!)
		_sec(vbox, "LIVE 2D BLUEPRINT (TOP X/Y)", fonts)
		var mini2d := Blueprint2DScript.new()
		mini2d.custom_minimum_size = Vector2(300, 155)
		mini2d.setup(app.doc, fonts["mono"], 0)
		mini2d.refresh(app.selected_solid, app.cam_pos)
		vbox.add_child(mini2d)
		return

	if app.selected_entity >= 0:
		var ents: Array = app.doc.get_entities()
		if app.selected_entity >= ents.size():
			return
		var e: Dictionary = ents[app.selected_entity]
		var cls: String = str(e["classname"])
		var kv: Dictionary = e["kv"]
		var fgd: Dictionary = app.core.get_fgd_class_info(cls)

		# 4-Tab Bar: Class Info | Flags | Outputs | Inputs
		var tabs := HBoxContainer.new(); tabs.add_theme_constant_override("separation", 3); vbox.add_child(tabs)
		var tnames := ["Class Info", "Flags", "Outputs (%d)" % (e.get("connections", []) as Array).size(), "Inputs"]
		for i in range(4):
			var tb := Button.new(); tb.text = tnames[i]; tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			HudWidgets.style_tf2_button(tb, fonts["heading"], 10, app._insp_tab == i)
			var ti := i
			tb.pressed.connect(func(): app._insp_tab = ti; app._open_inspector_drawer())
			tabs.add_child(tb)

		# Crisp Entity Visual Header Card (3D Icon + Coords + Quick Actions!)
		var hcard := HudWidgets.make_section_card("", fonts, HudWidgets.COL_ACC)
		vbox.add_child(hcard["panel"])
		var hvb: VBoxContainer = hcard["vbox"]
		var hrow := HBoxContainer.new(); hrow.add_theme_constant_override("separation", 8); hvb.add_child(hrow)
		var ep_u: Vector3 = ((e["bounds_min"] + e["bounds_max"]) * 0.5 if bool(e.get("is_brush", false)) else e["pos"]) * 32.0
		var mdl_key := str(kv.get("model", ""))
		var ic_tex: Texture2D = app.icon_cache.get_icon(mdl_key) if (not mdl_key.is_empty() and app.icon_cache != null) else null
		if ic_tex != null:
			var itr := TextureRect.new(); itr.texture = ic_tex; itr.custom_minimum_size = Vector2(44, 44)
			itr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; itr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			hrow.add_child(itr)
		var itvb := VBoxContainer.new(); itvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL; itvb.add_theme_constant_override("separation", 2); hrow.add_child(itvb)
		itvb.add_child(_lbl("ENTITY #%d — %s" % [app.selected_entity, cls], fonts["heading"], 11, HudWidgets.COL_ACC))
		itvb.add_child(_lbl("XYZ: %du, %du, %du" % [int(ep_u.x), int(-ep_u.z), int(ep_u.y)], fonts["mono"], 10, HudWidgets.COL_TX_MUTED))
		var qrow := HBoxContainer.new(); qrow.add_theme_constant_override("separation", 4); hvb.add_child(qrow)
		for qa in [
			{"t": "Focus (F)", "fn": func(): app._focus_camera_on_selection(), "tm": 0},
			{"t": "Wire 3D",   "fn": func(): app._start_visual_3d_wire(app.selected_entity), "tm": 3},
			{"t": "Rot 90°",   "fn": func(): app._rotate_selection(), "tm": 0},
			{"t": "Clone",     "fn": func(): app._duplicate_selection(), "tm": 0},
		]:
			var qb := Button.new(); qb.text = str(qa["t"]); qb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			HudWidgets.style_tf2_button(qb, fonts["body"], 9, false, int(qa["tm"]))
			var qfn: Callable = qa["fn"]
			qb.pressed.connect(func(): app.audio.play("click"); qfn.call())
			qrow.add_child(qb)

		if fgd.get("found", false) and not str(fgd.get("description", "")).is_empty():
			vbox.add_child(_lbl(str(fgd["description"]), fonts["body"], 10, HudWidgets.COL_TX_MUTED))

		# 1-Click TF2 Light Color & Brightness Studio for light / light_spot!
		if cls == "light" or cls == "light_spot":
			var lcard := HudWidgets.make_section_card("1-CLICK TF2 LIGHTING PRESETS (LIVE F3 PREVIEW)", fonts, Color(1.0, 0.85, 0.35))
			vbox.add_child(lcard["panel"])
			var lvb: VBoxContainer = lcard["vbox"]
			var cur_parts := str(kv.get("_light", "255 240 210 400")).split(" ", false)
			var cur_bright := float(cur_parts[3]) if cur_parts.size() >= 4 else 400.0
			var lg := GridContainer.new(); lg.columns = 2; lg.add_theme_constant_override("h_separation", 5); lg.add_theme_constant_override("v_separation", 5); lvb.add_child(lg)
			for lp in [
				{"t": "Warm Tungsten",    "rgb": "255 205 135", "b": 480},
				{"t": "Cool Spytech",     "rgb": "185 225 255", "b": 460},
				{"t": "RED Base Glow",    "rgb": "255 125 105", "b": 520},
				{"t": "BLU Base Glow",    "rgb": "105 175 255", "b": 520},
				{"t": "Bright Sunbeam",   "rgb": "255 245 215", "b": 780},
				{"t": "Spooky Violet",    "rgb": "205 125 255", "b": 460},
			]:
				var lb := Button.new(); lb.text = str(lp["t"]); lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				HudWidgets.style_tf2_button(lb, fonts["body"], 10)
				var lstr := "%s %d" % [str(lp["rgb"]), int(lp["b"])]
				lb.pressed.connect(func():
					app.doc.set_entity_kv(app.selected_entity, "_light", lstr)
					app._record_history("Set Light Preset")
					app.ent_vis.sync_entity(app.selected_entity, false)
					app.audio.play("click")
					app._open_inspector_drawer()
				)
				lg.add_child(lb)
			var br_sb := SpinBox.new(); br_sb.min_value = 50; br_sb.max_value = 1800; br_sb.step = 50; br_sb.value = cur_bright; br_sb.prefix = "Brightness: "
			br_sb.value_changed.connect(func(v: float):
				var p2 := str(app.doc.get_entities()[app.selected_entity]["kv"].get("_light", "255 240 210 400")).split(" ", false)
				var rgb_s := "%s %s %s" % [p2[0] if p2.size() > 0 else "255", p2[1] if p2.size() > 1 else "240", p2[2] if p2.size() > 2 else "210"]
				app.doc.set_entity_kv(app.selected_entity, "_light", "%s %d" % [rgb_s, int(v)])
				app.ent_vis.sync_entity(app.selected_entity, false)
			)
			lvb.add_child(br_sb)

		if bool(e.get("is_brush", false)):
			var untie_b := Button.new(); untie_b.text = "Move to World (Ctrl+Shift+W)"
			HudWidgets.style_tf2_button(untie_b, fonts["heading"], 11, false, 3)
			untie_b.pressed.connect(func(): app._untie_selected_entity())
			vbox.add_child(untie_b)

		if app._insp_tab == 0:
			# Full FGD SmartEdit KeyValues (Dropdown Choices + Focus-Exit Auto-Commit!)
			var vars: Array = fgd.get("vars", []) if fgd.get("found", false) else []
			var shown_keys := {}
			var pretty_key := func(k: String) -> String:
				var cleaned := k.trim_prefix("_").replace("_", " ")
				return cleaned.capitalize()
			var add_field := func(key: String, disp: String, choices: Array) -> void:
				shown_keys[key] = true
				var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 6); vbox.add_child(row)
				var kl := Label.new(); kl.text = disp if not disp.is_empty() else pretty_key.call(key)
				kl.custom_minimum_size = Vector2(128, 0)
				kl.clip_text = true; kl.tooltip_text = "%s (%s)" % [kl.text, key]
				kl.add_theme_font_size_override("font_size", 11); row.add_child(kl)
				var cur_v: String = str(kv.get(key, ""))
				if not choices.is_empty():
					var ob := OptionButton.new(); ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					var sel_i := 0
					for ci in range(choices.size()):
						var ch: Dictionary = choices[ci]
						ob.add_item("%s: %s" % [str(ch["value"]), str(ch["label"])])
						ob.set_item_metadata(ci, str(ch["value"]))
						if str(ch["value"]) == cur_v:
							sel_i = ci
					ob.select(sel_i)
					ob.item_selected.connect(func(idx: int):
						var nv: String = str(ob.get_item_metadata(idx))
						app.doc.set_entity_kv(app.selected_entity, key, nv)
						app._record_history("Set " + key)
						app.ent_vis.sync_all()
						app._toast("Set %s = %s" % [key, nv])
					)
					row.add_child(ob)
				else:
					var le := LineEdit.new(); le.text = cur_v; le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					var last_saved := [cur_v]
					var commit_kv := func(nv: String) -> void:
						if nv == last_saved[0]:
							return
						last_saved[0] = nv
						app.doc.set_entity_kv(app.selected_entity, key, nv)
						app._record_history("Set " + key)
						app.ent_vis.sync_all()
						app._toast("Set %s = %s" % [key, nv])
					le.text_submitted.connect(commit_kv)
					le.focus_exited.connect(func(): commit_kv.call(le.text))
					row.add_child(le)

			# Always prioritize key gameplay fields first, then ALL FGD vars + raw entity KVs!
			for prio in ["targetname", "TeamNum", "angles", "model", "skin", "_light", "movedir", "speed"]:
				var matched_v := {}
				for v in vars:
					if str(v["key"]) == prio:
						matched_v = v; break
				if not matched_v.is_empty():
					add_field.call(prio, str(matched_v["display_name"]), matched_v.get("choices", []))
				elif kv.has(prio) or prio in ["targetname", "angles"]:
					add_field.call(prio, pretty_key.call(prio), [])
			for v in vars:
				var vk: String = str(v["key"])
				if shown_keys.has(vk) or vk == "spawnflags":
					continue
				add_field.call(vk, str(v["display_name"]), v.get("choices", []))
			for rk in kv.keys():
				var rks := str(rk)
				if shown_keys.has(rks) or rks in ["id", "classname", "origin", "spawnflags"]:
					continue
				add_field.call(rks, pretty_key.call(rks), [])

		elif app._insp_tab == 1:
			# Spawnflags Checkboxes from FGD!
			var cur_sf := int(str(kv.get("spawnflags", "0")).to_int())
			var found_flags := false
			for v in (fgd.get("vars", []) if fgd.get("found", false) else []):
				if str(v["key"]) == "spawnflags":
					for fl in v.get("flags", []):
						found_flags = true
						var bit := int(fl["bit"])
						var cb := CheckBox.new()
						cb.text = str(fl["label"])
						cb.button_pressed = (cur_sf & bit) != 0
						cb.toggled.connect(func(on: bool):
							var sf := int(str(app.doc.get_entities()[app.selected_entity]["kv"].get("spawnflags", "0")).to_int())
							sf = (sf | bit) if on else (sf & ~bit)
							app.doc.set_entity_kv(app.selected_entity, "spawnflags", str(sf))
							app._record_history("Toggle Flag")
						)
						vbox.add_child(cb)
			if not found_flags:
				vbox.add_child(_lbl("No FGD spawnflags defined for this entity class.", fonts["body"], 11, HudWidgets.COL_TX_MUTED))

		elif app._insp_tab == 2:
			var w3d_b := Button.new(); w3d_b.text = "Visual 3D Wire: Click Target Entity (Shift+W)"
			w3d_b.custom_minimum_size = Vector2(0, 34)
			HudWidgets.style_tf2_button(w3d_b, fonts["heading"], 10, true)
			w3d_b.pressed.connect(func(): app.audio.play("click"); app._start_visual_3d_wire(app.selected_entity))
			vbox.add_child(w3d_b)

			# Outputs I/O List with Delete buttons + Full Add Output Builder (Param, Delay, Once Only!)
			var conns: Array = e.get("connections", [])
			for ci in range(conns.size()):
				var c: Dictionary = conns[ci]
				var crow := HBoxContainer.new(); crow.add_theme_constant_override("separation", 4); vbox.add_child(crow)
				var cl := _lbl("* %s -> %s" % [str(c["output"]), str(c["args"])], fonts["mono"], 10, HudWidgets.COL_CYAN)
				cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				crow.add_child(cl)
				var del_c := Button.new(); del_c.text = "X"
				HudWidgets.style_tf2_button(del_c, fonts["body"], 9, false, 2)
				var cidx := ci
				del_c.pressed.connect(func():
					app.doc.remove_connection(app.selected_entity, cidx)
					app._record_history("Remove Output")
					app.ent_vis.sync_all()
					app._open_inspector_drawer()
				)
				crow.add_child(del_c)
			_sec(vbox, "ADD ENTITY I/O OUTPUT", fonts)
			var out_le := LineEdit.new(); out_le.placeholder_text = "Output (e.g. OnCapTeam1 / OnStartTouch)"
			var tgt_le := LineEdit.new(); tgt_le.placeholder_text = "Target Entity Name (e.g. red_door)"
			var inp_le := LineEdit.new(); inp_le.placeholder_text = "Input (e.g. Open / Enable / Trigger)"
			var par_le := LineEdit.new(); par_le.placeholder_text = "Parameter Override (optional)"
			vbox.add_child(out_le); vbox.add_child(tgt_le); vbox.add_child(inp_le); vbox.add_child(par_le)
			var opt_row := HBoxContainer.new(); opt_row.add_theme_constant_override("separation", 8); vbox.add_child(opt_row)
			var del_sb := SpinBox.new(); del_sb.min_value = 0.0; del_sb.max_value = 60.0; del_sb.step = 0.25; del_sb.prefix = "Delay: "; del_sb.suffix = "s"
			del_sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			opt_row.add_child(del_sb)
			var once_cb := CheckBox.new(); once_cb.text = "Once"; opt_row.add_child(once_cb)
			var add_io := Button.new(); add_io.text = "+ Wire 3D Output Connection"
			HudWidgets.style_tf2_button(add_io, fonts["heading"], 11, true)
			add_io.pressed.connect(func():
				if not out_le.text.is_empty() and not tgt_le.text.is_empty() and not inp_le.text.is_empty():
					app.doc.add_connection(app.selected_entity, out_le.text.strip_edges(), tgt_le.text.strip_edges(),
						inp_le.text.strip_edges(), par_le.text.strip_edges(), float(del_sb.value), once_cb.button_pressed)
					app._record_history("Add I/O Output")
					app.ent_vis.sync_all()
					app._toast("Wired %s -> %s :: %s!" % [out_le.text, tgt_le.text, inp_le.text])
					app._open_inspector_drawer()
			)
			vbox.add_child(add_io)

		else:
			# Inputs Reverse Lookup!
			var my_name: String = str(kv.get("targetname", ""))
			var found_in := 0
			if not my_name.is_empty():
				for other in ents:
					for c in other.get("connections", []):
						if str(c["args"]).begins_with(my_name + ","):
							vbox.add_child(_lbl("<- %s (%s) :: %s" % [str(other["classname"]), str(other["targetname"]), str(c["output"])], fonts["mono"], 10, HudWidgets.COL_GREEN))
							found_in += 1
			if found_in == 0:
				vbox.add_child(_lbl("No incoming entity outputs target '%s' yet." % (my_name if not my_name.is_empty() else "(unnamed)"), fonts["body"], 11, HudWidgets.COL_TX_MUTED))
		return

	vbox.add_child(_lbl("Click any solid or entity in 3D to inspect & edit its Hammer properties, FGD SmartEdit choices, flags, and I/O wires.", fonts["body"], 12, HudWidgets.COL_TX_MUTED))

# ==============================================================================
# 5. INTUITIVE TERRAIN & CANYON CLIFF STUDIO (Visual Presets + Blend Painter!)
# ==============================================================================
static func build_terrain_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	_sec(vbox, "1. STAMP TERRAIN OR CANYON CLIFF PRESET", fonts)

	var pgrid := GridContainer.new()
	pgrid.columns = 2
	pgrid.add_theme_constant_override("h_separation", 8)
	pgrid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(pgrid)

	var presets := [
		{"id": "cliff",  "name": "Canyon Cliff",  "sub": "Vertical rocky wall",  "ic": "preset_cliff"},
		{"id": "hill",   "name": "Rolling Hill",  "sub": "Organic ground mound", "ic": "preset_hill"},
		{"id": "mesa",   "name": "Mesa Plateau",  "sub": "Flat-top high ground", "ic": "preset_mesa"},
		{"id": "crater", "name": "Crater Basin",  "sub": "Sunken battle bowl",   "ic": "preset_crater"},
	]
	for pr in presets:
		var pid: String = pr["id"]
		var card := Button.new()
		card.custom_minimum_size = Vector2(0, 74)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = HudWidgets.COL_BG_CARD
		sb.border_color = HudWidgets.COL_ACC if pid == "cliff" else HudWidgets.COL_SLOT_BD
		sb.set_border_width_all(1); sb.set_corner_radius_all(8)
		var sbh := sb.duplicate(); sbh.bg_color = HudWidgets.COL_SLOT_HOV; sbh.border_color = HudWidgets.COL_ACC
		card.add_theme_stylebox_override("normal", sb)
		card.add_theme_stylebox_override("hover", sbh)
		card.add_theme_stylebox_override("pressed", sbh)

		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 6; hb.offset_right = -6; hb.offset_top = 6; hb.offset_bottom = -6
		hb.add_theme_constant_override("separation", 8)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hb)

		var art := HudWidgets.VectorToolIcon.new(pr["ic"], false, HudWidgets.COL_ACC)
		art.custom_minimum_size = Vector2(54, 54)
		hb.add_child(art)

		var tvb := VBoxContainer.new()
		tvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tvb.alignment = BoxContainer.ALIGNMENT_CENTER
		tvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(tvb)
		var l1 := _lbl(pr["name"], fonts["heading"], 11, HudWidgets.COL_TX); l1.mouse_filter = Control.MOUSE_FILTER_IGNORE; tvb.add_child(l1)
		var l2 := _lbl(pr["sub"], fonts["body"], 9, HudWidgets.COL_TX_MUTED); l2.mouse_filter = Control.MOUSE_FILTER_IGNORE; tvb.add_child(l2)

		card.pressed.connect(func():
			var p: Vector3 = app.hover_pos if app.hover_valid else Vector3(0, 0, -6)
			var mat := "NATURE/BLENDROCKWALLDIRT001"
			if pid == "cliff":
				var a := p + Vector3(-8, 0, 0); var b := p + Vector3(8, 0, 0)
				if app.cliff_facing == 1: a = p + Vector3(8, 0, 0); b = p + Vector3(-8, 0, 0)
				elif app.cliff_facing == 2: a = p + Vector3(0, 0, 8); b = p + Vector3(0, 0, -8)
				elif app.cliff_facing == 3: a = p + Vector3(0, 0, -8); b = p + Vector3(0, 0, 8)
				var cid: int = app.doc.make_cliff_wall(a, b, app.cliff_height_m, 2.5, app.cliff_power, mat, 1.2)
				if cid >= 0:
					app.terrain_axis_mode = 0
					app._record_history("Add Canyon Cliff")
					app.map_sync.sync_all(); app._select_solid(cid, -1); app.audio.play("place")
					app._toast("Stamped Canyon Cliff Wall! Hold LMB to sculpt.")
			else:
				var sid: int = app.doc.make_terrain_patch(p + Vector3(-8, -1, -8), p + Vector3(8, 0, 8), 3, Tf2GamemodesScript.get_biome(app.active_biome)["floor"])
				if sid >= 0:
					if pid == "hill":
						app.doc.sculpt_terrain(p, 7.5, 2.6, 0, 1)
						app.doc.sculpt_terrain(p, 6.0, 0.8, 2, 1)
					elif pid == "mesa":
						app.doc.sculpt_terrain(p, 6.8, 3.2, 0, 1)
						app.doc.sculpt_terrain(p, 4.8, 3.0, 3, 1)
					elif pid == "crater":
						app.doc.sculpt_terrain(p, 6.5, 2.4, 1, 1)
					app.terrain_axis_mode = 1
					app._record_history("Add " + pr["name"])
					app.map_sync.sync_all(); app._select_solid(sid, -1); app.audio.play("place")
					app._toast("Stamped %s! Hold LMB in 3D to sculpt." % pr["name"])
		)
		pgrid.add_child(card)

	# Compact Cliff Facing & Height strip (Hammer units!)
	var cf_row := HBoxContainer.new(); cf_row.add_theme_constant_override("separation", 4); vbox.add_child(cf_row)
	var cf_lbl := _lbl("Cliff Facing:", fonts["body"], 10, HudWidgets.COL_TX_MUTED)
	cf_lbl.custom_minimum_size = Vector2(72, 0); cf_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cf_row.add_child(cf_lbl)
	var dir_names: Array[String] = ["South", "North", "East", "West"]
	for di in range(4):
		var db := Button.new(); db.text = dir_names[di]; db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(db, fonts["body"], 10, app.cliff_facing == di)
		var dv := di
		db.pressed.connect(func(): app.cliff_facing = dv; app._open_terrain_studio())
		cf_row.add_child(db)

	var ch_lbl := _lbl("Cliff Height: %du  |  Mesh Detail: Power-%d" % [int(round(app.cliff_height_m * 32.0)), app.cliff_power], fonts["body"], 11, HudWidgets.COL_TX)
	vbox.add_child(ch_lbl)
	var ch_sl := HSlider.new(); ch_sl.min_value = 6.0; ch_sl.max_value = 16.0; ch_sl.step = 1.0; ch_sl.value = app.cliff_height_m
	ch_sl.value_changed.connect(func(v): app.cliff_height_m = v; ch_lbl.text = "Cliff Height: %du  |  Mesh Detail: Power-%d" % [int(round(v * 32.0)), app.cliff_power])
	vbox.add_child(ch_sl)

	_sec(vbox, "2. SCULPT BRUSH (HOLD LMB ON TERRAIN)", fonts)
	var brushes := [
		{"m": 0, "t": "Raise",   "ic": "raise"},
		{"m": 1, "t": "Lower",   "ic": "lower"},
		{"m": 2, "t": "Smooth",  "ic": "smooth"},
		{"m": 3, "t": "Flatten", "ic": "flatten"},
		{"m": 6, "t": "Noise",   "ic": "noise"},
		{"m": 4, "t": "Blend",   "ic": "paint"},
	]
	var bg := GridContainer.new(); bg.columns = 3
	bg.add_theme_constant_override("h_separation", 6); bg.add_theme_constant_override("v_separation", 6)
	vbox.add_child(bg)
	for br in brushes:
		var mv: int = int(br["m"])
		var is_act: bool = (app.terrain_mode == mv) or (mv == 4 and app.terrain_mode == 5)
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["heading"], 10, is_act)
		var bvb := VBoxContainer.new()
		bvb.set_anchors_preset(Control.PRESET_FULL_RECT)
		bvb.offset_top = 4; bvb.offset_bottom = -3
		bvb.alignment = BoxContainer.ALIGNMENT_CENTER
		bvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(bvb)
		var vic := HudWidgets.VectorToolIcon.new(br["ic"], is_act, HudWidgets.COL_ACC)
		vic.custom_minimum_size = Vector2(22, 22)
		vic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		bvb.add_child(vic)
		var bl := _lbl(br["t"], fonts["heading"], 10, Color(0.10, 0.07, 0.04) if is_act else HudWidgets.COL_TX)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bvb.add_child(bl)
		b.pressed.connect(func(): app.audio.play("click"); app.terrain_mode = mv; app._open_terrain_studio())
		bg.add_child(b)

	# Plain-English Sculpt Direction Toggle!
	var dir_row := HBoxContainer.new(); dir_row.add_theme_constant_override("separation", 5); vbox.add_child(dir_row)
	var b_push := Button.new(); b_push.text = "Push Out (Cliffs)"; b_push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudWidgets.style_tf2_button(b_push, fonts["heading"], 10, app.terrain_axis_mode == 0)
	b_push.pressed.connect(func(): app.terrain_axis_mode = 0; app._open_terrain_studio())
	dir_row.add_child(b_push)
	var b_up := Button.new(); b_up.text = "Up & Down (Ground)"; b_up.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudWidgets.style_tf2_button(b_up, fonts["heading"], 10, app.terrain_axis_mode == 1)
	b_up.pressed.connect(func(): app.terrain_axis_mode = 1; app._open_terrain_studio())
	dir_row.add_child(b_up)

	# Visual Side-by-Side Texture Blend Painter (NO cryptic "Paint Alpha+" / "Alpha-"!)
	_sec(vbox, "3. VISUAL TEXTURE BLEND PAINTER", fonts)
	var blend_row := HBoxContainer.new(); blend_row.add_theme_constant_override("separation", 8); vbox.add_child(blend_row)
	var blend_layers := [
		{"m": 4, "name": "Badlands Rock", "mat": "NATURE/ROCKWALL001"},
		{"m": 5, "name": "Canyon Dirt",   "mat": "NATURE/DIRTGROUND001"},
	]
	for bl_item in blend_layers:
		var lm: int = int(bl_item["m"])
		var is_l: bool = (app.terrain_mode == lm)
		var lb := Button.new()
		lb.custom_minimum_size = Vector2(0, 52)
		lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(lb, fonts["body"], 10, is_l)
		var lhb := HBoxContainer.new()
		lhb.set_anchors_preset(Control.PRESET_FULL_RECT)
		lhb.offset_left = 5; lhb.offset_right = -5; lhb.offset_top = 5; lhb.offset_bottom = -5
		lhb.add_theme_constant_override("separation", 6)
		lhb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.add_child(lhb)
		var sw := TextureRect.new()
		sw.custom_minimum_size = Vector2(38, 38)
		sw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sw.stretch_mode = TextureRect.STRETCH_SCALE
		sw.texture = app.assets.get_material_swatch(bl_item["mat"])
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lhb.add_child(sw)
		var ltxt := _lbl("Paint:\n" + bl_item["name"], fonts["body"], 10, Color(0.10, 0.07, 0.04) if is_l else HudWidgets.COL_TX)
		ltxt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ltxt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ltxt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lhb.add_child(ltxt)
		lb.pressed.connect(func():
			app.audio.play("click")
			app.terrain_mode = lm
			app._toast("Texture Blend Brush: Painting %s!" % bl_item["name"])
			app._open_terrain_studio()
		)
		blend_row.add_child(lb)

	var r_lbl := _lbl("Brush Radius: %du" % int(round(app.terrain_radius_m * 32.0)), fonts["body"], 11, HudWidgets.COL_TX); vbox.add_child(r_lbl)
	var r_sl := HSlider.new(); r_sl.min_value = 1.5; r_sl.max_value = 12.0; r_sl.step = 0.5; r_sl.value = app.terrain_radius_m
	r_sl.value_changed.connect(func(v): app.terrain_radius_m = v; r_lbl.text = "Brush Radius: %du" % int(round(v * 32.0)))
	vbox.add_child(r_sl)

	var s_lbl := _lbl("Brush Strength: %du" % int(round(app.terrain_strength_m * 32.0)), fonts["body"], 11, HudWidgets.COL_TX); vbox.add_child(s_lbl)
	var s_sl := HSlider.new(); s_sl.min_value = 0.25; s_sl.max_value = 3.5; s_sl.step = 0.25; s_sl.value = app.terrain_strength_m
	s_sl.value_changed.connect(func(v): app.terrain_strength_m = v; s_lbl.text = "Brush Strength: %du" % int(round(v * 32.0)))
	vbox.add_child(s_sl)

	_sec(vbox, "4. SEAM STITCHING & SMOOTHING", fonts)
	var t_row := HBoxContainer.new(); t_row.add_theme_constant_override("separation", 6); vbox.add_child(t_row)
	var b_sew := Button.new(); b_sew.text = "Auto-Sew All Seams"; b_sew.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_sew.focus_mode = Control.FOCUS_NONE
	b_sew.add_theme_stylebox_override("normal", HudWidgets.make_button_style(Color(0.15, 0.42, 0.22, 0.96), HudWidgets.COL_GREEN, 7, 10, 7))
	b_sew.add_theme_stylebox_override("hover", HudWidgets.make_button_style(Color(0.20, 0.52, 0.28, 1.0), Color(0.7, 1.0, 0.78), 7, 10, 7))
	b_sew.add_theme_stylebox_override("pressed", HudWidgets.make_button_style(Color(0.12, 0.34, 0.18, 1.0), HudWidgets.COL_GREEN, 7, 10, 7))
	b_sew.add_theme_font_override("font", fonts["heading"]); b_sew.add_theme_font_size_override("font_size", 11)
	b_sew.add_theme_color_override("font_color", Color(0.92, 1.0, 0.94))
	b_sew.pressed.connect(func():
		var n: int = app.doc.sew_displacements()
		app._record_history("Sew Displacements"); app.map_sync.sync_all(); app.audio.play("carve")
		app._toast("Auto-Sewed %d displacement seam vertices (0 cracks)!" % n)
	)
	t_row.add_child(b_sew)

	var b_sub := Button.new(); b_sub.text = "Subdivide Smooth"; b_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudWidgets.style_tf2_button(b_sub, fonts["body"], 11)
	b_sub.pressed.connect(func():
		if app.selected_solid >= 0 and app.doc.subdivide_displacement(app.selected_solid):
			app._commit_solid_edit("Subdivide Displacement")
			app._toast("Smoothed displacement surface!")
	)
	t_row.add_child(b_sub)

# ==============================================================================
# 5B. WALL CHAIN & DRAG-BOX DIMENSIONS DRAWER (Hammer Architecture Controls!)
# ==============================================================================
static func build_wall_box_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	_sec(vbox, "WALL CHAIN & DRAG-BOX DIMENSIONS", fonts)
	vbox.add_child(_lbl("Wall Chain: Click start -> click corners to chain angled walls (ESC to stop).\nDrag Box: Click & drag flat footprint using active material.", fonts["body"], 11, HudWidgets.COL_TX_MUTED))

	var wh_lbl := Label.new(); wh_lbl.text = "Wall Height: %du (%.1fm)" % [int(round(app.wall_height_m * 32.0)), app.wall_height_m]; vbox.add_child(wh_lbl)
	var wh_sl := HSlider.new(); wh_sl.min_value = 2.0; wh_sl.max_value = 12.0; wh_sl.step = 0.5; wh_sl.value = app.wall_height_m
	wh_sl.value_changed.connect(func(v): app.wall_height_m = v; wh_lbl.text = "Wall Height: %du (%.1fm)" % [int(round(v * 32.0)), v])
	vbox.add_child(wh_sl)

	var wt_lbl := Label.new(); wt_lbl.text = "Wall Thickness: %du" % int(round(app.wall_thick_m * 32.0)); vbox.add_child(wt_lbl)
	var wt_sl := HSlider.new(); wt_sl.min_value = 0.25; wt_sl.max_value = 2.0; wt_sl.step = 0.25; wt_sl.value = app.wall_thick_m
	wt_sl.value_changed.connect(func(v): app.wall_thick_m = v; wt_lbl.text = "Wall Thickness: %du" % int(round(v * 32.0)))
	vbox.add_child(wt_sl)

	var bh_lbl := Label.new(); bh_lbl.text = "Drag-Box Height: %du" % int(round(app.box_height_m * 32.0)); vbox.add_child(bh_lbl)
	var bh_sl := HSlider.new(); bh_sl.min_value = 0.5; bh_sl.max_value = 8.0; bh_sl.step = 0.5; bh_sl.value = app.box_height_m
	bh_sl.value_changed.connect(func(v): app.box_height_m = v; bh_lbl.text = "Drag-Box Height: %du" % int(round(v * 32.0)))
	vbox.add_child(bh_sl)

	_sec(vbox, "QUICK TF2 HEIGHT PRESETS", fonts)
	var pr := HBoxContainer.new(); pr.add_theme_constant_override("separation", 4); vbox.add_child(pr)
	for preset in [{"t": "48u Cover", "h": 1.5}, {"t": "144u Story", "h": 4.5}, {"t": "256u Barn", "h": 8.0}]:
		var pb := Button.new(); pb.text = preset["t"]; pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(pb, fonts["body"], 10)
		var hv: float = preset["h"]
		pb.pressed.connect(func(): app.wall_height_m = hv; app.box_height_m = hv; app._open_wall_box_drawer())
		pr.add_child(pb)

# ==============================================================================
# 6. HAMMER ALT+P CHECK MAP FOR PROBLEMS (Go To Error + 1-Click Fix + Fix All!)
# ==============================================================================
static func build_check_problems_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	var probs: Array = app.doc.check_problems()
	var rep: Dictionary = Tf2CatalogScript.analyze_map(app.doc)

	# 1. TF2 Map Balance & Pacing Report Card (Milestone 30!)
	var ents: Array = app.doc.get_entities()
	var red_sp := 0; var blu_sp := 0; var hp_l := 0; var hp_r := 0; var am_l := 0; var am_r := 0
	var sp_positions: Array[Vector3] = []
	var obj_positions: Array[Vector3] = []
	for e in ents:
		var cls := str(e["classname"])
		var ep: Vector3 = e["pos"]
		if cls == "info_player_teamspawn":
			var tn := str(e["kv"].get("TeamNum", "2"))
			if tn == "2": red_sp += 1
			else: blu_sp += 1
			sp_positions.append(ep)
		elif cls.begins_with("item_healthkit"):
			if ep.x < 0.0: hp_l += 1
			else: hp_r += 1
		elif cls.begins_with("item_ammopack"):
			if ep.x < 0.0: am_l += 1
			else: am_r += 1
		elif cls == "team_control_point" or cls == "item_teamflag" or cls == "mapobj_cart_dispenser":
			obj_positions.append(ep)

	var rollout_dist_u := 1800.0
	if not sp_positions.is_empty() and not obj_positions.is_empty():
		var best_d := 1e9
		for sp in sp_positions:
			for op in obj_positions:
				best_d = minf(best_d, sp.distance_to(op) * 32.0)
		rollout_dist_u = maxf(256.0, best_d)
	var scout_s := rollout_dist_u / 400.0
	var soldier_s := rollout_dist_u / 240.0
	var heavy_s := rollout_dist_u / 230.0
	var pace_lbl := "IDEAL TF2 PACING (6-13s)" if (soldier_s >= 5.5 and soldier_s <= 14.0) else ("VERY FAST ARENA (<5.5s)" if soldier_s < 5.5 else "LONG ROLLOUT (>14s)")
	var pace_col := HudWidgets.COL_GREEN if (soldier_s >= 5.5 and soldier_s <= 14.0) else HudWidgets.COL_ACC

	var bcard := HudWidgets.make_section_card("TF2 MAP BALANCE & ROLLOUT ANALYZER", fonts, HudWidgets.COL_CYAN)
	vbox.add_child(bcard["panel"])
	var bvb: VBoxContainer = bcard["vbox"]
	bvb.add_child(_lbl("Map Coach Grade: %s  |  Solids: %d  |  Entities: %d" % [rep["grade"], rep["solids"], rep["entities"]], fonts["heading"], 11, HudWidgets.COL_TX))
	bvb.add_child(_lbl("Rollout Estimate (~%du): Scout %.1fs | Soldier %.1fs | Heavy %.1fs" % [int(rollout_dist_u), scout_s, soldier_s, heavy_s], fonts["mono"], 10, pace_col))
	bvb.add_child(_lbl("Pacing Verdict: %s" % pace_lbl, fonts["body"], 10, pace_col))
	var sp_ok: bool = (red_sp == blu_sp and red_sp > 0) or str(app.active_gamemode) == "mvm"
	var pk_ok: bool = absi(hp_l - hp_r) <= 1 and absi(am_l - am_r) <= 1
	bvb.add_child(_lbl("Spawns: RED %d / BLU %d (%s)" % [red_sp, blu_sp, "Balanced" if sp_ok else "Check Symmetry"], fonts["body"], 10, HudWidgets.COL_GREEN if sp_ok else HudWidgets.COL_ACC))
	bvb.add_child(_lbl("Pickups (L/R Halves): Health %d/%d  |  Ammo %d/%d (%s)" % [hp_l, hp_r, am_l, am_r, "Even" if pk_ok else "Skewed"], fonts["body"], 10, HudWidgets.COL_GREEN if pk_ok else HudWidgets.COL_ACC))

	if probs.is_empty():
		var okc := HudWidgets.make_section_card("COMPILE READINESS", fonts, HudWidgets.COL_GREEN)
		vbox.add_child(okc["panel"])
		(okc["vbox"] as VBoxContainer).add_child(_lbl("OK: Zero map errors detected — ready to compile cleanly in Valve vbsp!", fonts["heading"], 11, HudWidgets.COL_GREEN))
		return

	var fix_all_b := Button.new(); fix_all_b.text = "Fix All Auto-Fixable Problems"
	HudWidgets.style_tf2_button(fix_all_b, fonts["heading"], 11, true)
	fix_all_b.pressed.connect(func():
		for p in probs:
			var fk: String = str(p.get("fix_kind", ""))
			if fk == "auto_seal": app._do_auto_seal()
			elif fk == "add_red_spawn": Tf2GamemodesScript.stamp_preset(app.doc, "spawn", Vector3(-12, 0.5, 0), 2)
			elif fk == "add_blu_spawn": Tf2GamemodesScript.stamp_preset(app.doc, "spawn", Vector3(12, 0.5, 0), 3)
			elif fk == "add_sun": app.doc.add_point_entity("light_environment", Vector3(0, 10, 0), {"_light": "255 245 220 400", "pitch": "-45"})
		app._record_history("Fix All Problems")
		app.map_sync.sync_all(); app.ent_vis.sync_all()
		app._open_check_problems_drawer()
	)
	vbox.add_child(fix_all_b)

	for p in probs:
		var card := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.16, 0.12, 0.10, 0.92)
		sb.border_color = HudWidgets.COL_RED if str(p["severity"]) == "ERROR" else HudWidgets.COL_ACC
		sb.set_border_width_all(1); sb.set_corner_radius_all(6)
		sb.content_margin_left = 8; sb.content_margin_right = 8; sb.content_margin_top = 6; sb.content_margin_bottom = 6
		card.add_theme_stylebox_override("panel", sb)
		vbox.add_child(card)
		var cvb := VBoxContainer.new(); cvb.add_theme_constant_override("separation", 4); card.add_child(cvb)
		cvb.add_child(_lbl("[%s] %s" % [str(p["severity"]), str(p["message"])], fonts["body"], 11, HudWidgets.COL_TX))
		var brow := HBoxContainer.new(); brow.add_theme_constant_override("separation", 5); cvb.add_child(brow)
		var go_b := Button.new(); go_b.text = "Go To"
		HudWidgets.style_tf2_button(go_b, fonts["body"], 10)
		var ppos: Vector3 = p["pos"]
		go_b.pressed.connect(func():
			app.cam_pos = ppos + Vector3(8, 7, 8)
			app.editor_cam.look_at_from_position(app.cam_pos, ppos, Vector3.UP)
			app.cam_yaw = app.editor_cam.rotation.y; app.cam_pitch = app.editor_cam.rotation.x
		)
		brow.add_child(go_b)
		var fk: String = str(p.get("fix_kind", ""))
		if not fk.is_empty():
			var fix_b := Button.new(); fix_b.text = "1-Click Fix"
			HudWidgets.style_tf2_button(fix_b, fonts["heading"], 10, true)
			var sidx: int = int(p.get("solid_idx", -1))
			fix_b.pressed.connect(func():
				if fk == "auto_seal": app._do_auto_seal()
				elif fk == "add_red_spawn": Tf2GamemodesScript.stamp_preset(app.doc, "spawn", Vector3(-12, 0.5, 0), 2); app.ent_vis.sync_all()
				elif fk == "add_blu_spawn": Tf2GamemodesScript.stamp_preset(app.doc, "spawn", Vector3(12, 0.5, 0), 3); app.ent_vis.sync_all()
				elif fk == "add_sun": app.doc.add_point_entity("light_environment", Vector3(0, 10, 0), {"_light": "255 245 220 400", "pitch": "-45"}); app.ent_vis.sync_all()
				elif fk == "delete_solid" and sidx >= 0: app.doc.delete_solid(sidx); app.map_sync.sync_all()
				app._record_history("Fix " + fk)
				app._open_check_problems_drawer()
			)
			brow.add_child(fix_b)

# ==============================================================================
# 7. VISUAL MAP HISTORY TIMELINE (Click any past/future step to Undo/Redo!)
# ==============================================================================
static func build_history_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	var entries: Array = app._history_entries
	var cur_idx: int = app._history_idx

	var top := HBoxContainer.new(); top.add_theme_constant_override("separation", 6); vbox.add_child(top)
	var b_u := Button.new(); b_u.text = "Undo (Ctrl+Z)"; b_u.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_u.disabled = (cur_idx <= 0)
	HudWidgets.style_tf2_button(b_u, fonts["heading"], 11, cur_idx > 0)
	b_u.pressed.connect(func(): app._do_undo())
	top.add_child(b_u)

	var b_r := Button.new(); b_r.text = "Redo (Ctrl+Y)"; b_r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b_r.disabled = (cur_idx >= entries.size() - 1)
	HudWidgets.style_tf2_button(b_r, fonts["heading"], 11, cur_idx < entries.size() - 1)
	b_r.pressed.connect(func(): app._do_redo())
	top.add_child(b_r)

	vbox.add_child(_lbl("Map Edit Timeline - Step %d of %d (click any step to jump there!)" % [
		cur_idx + 1, maxi(1, entries.size())
	], fonts["body"], 11, HudWidgets.COL_TX_MUTED))

	# Show newest edits at top so recent actions are immediately visible!
	for rev in range(entries.size() - 1, -1, -1):
		var ent: Dictionary = entries[rev]
		var is_cur: bool = (rev == cur_idx)
		var is_future: bool = (rev > cur_idx)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 38)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.28, 0.20, 0.12, 0.98) if is_cur else (Color(0.11, 0.10, 0.09, 0.80) if is_future else HudWidgets.COL_BG_CARD)
		sb.border_color = HudWidgets.COL_ACC if is_cur else (Color(0.28, 0.25, 0.22, 0.70) if is_future else HudWidgets.COL_SLOT_BD)
		sb.border_width_left = 4 if is_cur else 1
		sb.border_width_top = 1; sb.border_width_right = 1; sb.border_width_bottom = 1
		sb.set_corner_radius_all(7)
		var sbh := sb.duplicate(); sbh.bg_color = HudWidgets.COL_SLOT_HOV; sbh.border_color = HudWidgets.COL_ACC
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sbh)
		btn.add_theme_stylebox_override("pressed", sbh)

		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 10; hb.offset_right = -10
		hb.add_theme_constant_override("separation", 8)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(hb)

		var prefix := "> " if is_cur else ("" if not is_future else "(redo) ")
		var l1 := Label.new()
		l1.text = "%s#%d  %s" % [prefix, rev, str(ent["label"])]
		l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l1.clip_text = true
		l1.add_theme_font_override("font", fonts["heading"] if is_cur else fonts["body"])
		l1.add_theme_font_size_override("font_size", 11)
		l1.add_theme_color_override("font_color", HudWidgets.COL_ACC if is_cur else (HudWidgets.COL_TX_MUTED if is_future else HudWidgets.COL_TX))
		l1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(l1)

		var l2 := Label.new()
		l2.text = str(ent["time"])
		l2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l2.add_theme_font_override("font", fonts["mono"])
		l2.add_theme_font_size_override("font_size", 10)
		l2.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
		l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(l2)

		var target_i := rev
		btn.pressed.connect(func(): app._jump_to_history(target_i))
		vbox.add_child(btn)

# ==============================================================================
# 8. MANN VS. MACHINE (MvM) STUDIO — ROBOT SPAWNS, TANK TRACKS & .POP EXPORTER!
# ==============================================================================
static func build_mvm_studio(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	var c1 := HudWidgets.make_section_card("1. STAMP MVM ROBOTS & BASE OBJECTIVES", fonts, Color(0.74, 0.42, 0.96))
	vbox.add_child(c1["panel"])
	var v1: VBoxContainer = c1["vbox"]
	v1.add_child(_lbl("Click any MvM piece below to stamp it at your cursor (or spawn directly onto the map).", fonts["body"], 10, HudWidgets.COL_TX_MUTED))

	var r1 := GridContainer.new(); r1.columns = 2
	r1.add_theme_constant_override("h_separation", 6); r1.add_theme_constant_override("v_separation", 6)
	v1.add_child(r1)

	var mvm_tools := [
		{"t": "Robot Spawn",     "cls": "info_player_teamspawn", "kv": {"TeamNum": "3", "targetname": "spawnbot"}},
		{"t": "Giant Bot Spawn", "cls": "info_player_teamspawn", "kv": {"TeamNum": "3", "targetname": "spawnbot_giant"}},
		{"t": "Sniper Bot Hint", "cls": "info_player_teamspawn", "kv": {"TeamNum": "3", "targetname": "spawnbot_mission_sniper"}},
		{"t": "Robot Bomb",      "cls": "item_teamflag",         "kv": {"TeamNum": "3", "GameType": "1", "targetname": "intel"}},
		{"t": "MvM Bomb Hatch",  "preset": "mvm_hatch"},
		{"t": "Upgrade Station", "preset": "upgrade_station"},
		{"t": "RED Defender",    "preset": "spawn_red"},
		{"t": "Tank Track Node", "tool": "payload_track"},
	]
	for mt in mvm_tools:
		var b := Button.new(); b.text = str(mt["t"]); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["heading"], 10)
		b.pressed.connect(func():
			app.audio.play("click")
			var p: Vector3 = app.hover_pos if app.hover_valid else Vector3(0, 0.2, 0)
			if mt.has("tool"):
				app._select_tool(str(mt["tool"]))
			elif mt.has("preset"):
				app._select_tool(str(mt["preset"]))
			else:
				var eid: int = app.doc.add_point_entity(str(mt["cls"]), p, mt["kv"])
				app._record_history("Place " + str(mt["t"]))
				if eid >= 0:
					app.ent_vis.sync_entity(eid, true); app._select_entity(eid)
				app._spawn_place_fx(p, Color(0.74, 0.42, 0.96))
				app._toast("Stamped MvM %s!" % str(mt["t"]))
		)
		r1.add_child(b)

	var c2 := HudWidgets.make_section_card("2. WAVE MISSION BUILDER (.POP FILE EXPORTER)", fonts, HudWidgets.COL_ACC)
	vbox.add_child(c2["panel"])
	var v2: VBoxContainer = c2["vbox"]
	v2.add_child(_lbl("Generate a real Valve TF2 Mann vs. Machine .pop wave mission file for your map!", fonts["body"], 10, HudWidgets.COL_TX_MUTED))

	var wg := GridContainer.new(); wg.columns = 2; wg.add_theme_constant_override("h_separation", 6); v2.add_child(wg)
	var cash_sb := SpinBox.new(); cash_sb.min_value = 200; cash_sb.max_value = 5000; cash_sb.step = 100; cash_sb.value = app.mvm_start_cash; cash_sb.prefix = "Start $: "
	var w1_sb := SpinBox.new(); w1_sb.min_value = 4; w1_sb.max_value = 60; w1_sb.step = 2; w1_sb.value = app.mvm_w1_scouts; w1_sb.prefix = "W1 Scouts: "
	var w2_sb := SpinBox.new(); w2_sb.min_value = 4; w2_sb.max_value = 60; w2_sb.step = 2; w2_sb.value = app.mvm_w2_soldiers; w2_sb.prefix = "W2 Soldiers: "
	var w3_sb := SpinBox.new(); w3_sb.min_value = 1; w3_sb.max_value = 12; w3_sb.step = 1; w3_sb.value = app.mvm_w3_giants; w3_sb.prefix = "W3 Giants: "
	for sb: SpinBox in [cash_sb, w1_sb, w2_sb, w3_sb]:
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL; wg.add_child(sb)
	cash_sb.value_changed.connect(func(v): app.mvm_start_cash = int(v))
	w1_sb.value_changed.connect(func(v): app.mvm_w1_scouts = int(v))
	w2_sb.value_changed.connect(func(v): app.mvm_w2_soldiers = int(v))
	w3_sb.value_changed.connect(func(v): app.mvm_w3_giants = int(v))

	var tank_cb := CheckButton.new(); tank_cb.text = "Include Boss Tank in Wave 3"; tank_cb.button_pressed = app.mvm_has_tank
	tank_cb.toggled.connect(func(on: bool): app.mvm_has_tank = on)
	v2.add_child(tank_cb)

	var exp_b := Button.new(); exp_b.text = "Export Valve MvM .POP Mission File"
	exp_b.custom_minimum_size = Vector2(0, 38)
	HudWidgets.style_tf2_button(exp_b, fonts["heading"], 11, true)
	exp_b.pressed.connect(func():
		var out_p: String = app.export_mvm_pop_mission()
		app.audio.play("save")
		app._toast("Exported MvM Wave Mission: " + out_p.get_file())
	)
	v2.add_child(exp_b)

# ==============================================================================
# 9. PAYLOAD TRACK SPLINE STUDIO — CLICK-TO-CHAIN TRACK NODES & CHECKPOINTS!
# ==============================================================================
static func build_payload_studio(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	var c1 := HudWidgets.make_section_card("1. CLICK-TO-CHAIN PAYLOAD TRACK SPLINE", fonts, Color(0.98, 0.80, 0.20))
	vbox.add_child(c1["panel"])
	var v1: VBoxContainer = c1["vbox"]
	v1.add_child(_lbl("Click points along your map to automatically build & link Payload track nodes (pb_track_01 -> 02 -> 03...) with live 3D yellow rails!", fonts["body"], 10, HudWidgets.COL_TX_MUTED))

	var chain_b := Button.new()
	chain_b.text = "ACTIVE: Click 3D to Add Track Node" if app.active_tool == "payload_track" else "Start Clicking Payload Track Spline"
	chain_b.custom_minimum_size = Vector2(0, 38)
	HudWidgets.style_tf2_button(chain_b, fonts["heading"], 11, true)
	chain_b.pressed.connect(func(): app.audio.play("click"); app._select_tool("payload_track"))
	v1.add_child(chain_b)

	var reset_b := Button.new(); reset_b.text = "Reset Track Chain Counter (Current: %d nodes)" % app._payload_track_idx
	HudWidgets.style_tf2_button(reset_b, fonts["body"], 10)
	reset_b.pressed.connect(func(): app.audio.play("click"); app._payload_track_idx = 0; app._open_payload_studio())
	v1.add_child(reset_b)

	var c2 := HudWidgets.make_section_card("2. STAMP PAYLOAD LANDMARKS", fonts, HudWidgets.COL_ACC)
	vbox.add_child(c2["panel"])
	var pg := GridContainer.new(); pg.columns = 2; pg.add_theme_constant_override("h_separation", 6); pg.add_theme_constant_override("v_separation", 6)
	(c2["vbox"] as VBoxContainer).add_child(pg)
	for item in [
		{"t": "Payload Cart",  "preset": "bomb_cart"},
		{"t": "Checkpoint",    "preset": "cap_point"},
		{"t": "Setup Gate",    "cls": "func_door"},
		{"t": "BLU Spawn",     "preset": "spawn_blu"},
		{"t": "RED Spawn",     "preset": "spawn_red"},
		{"t": "Resupply",      "preset": "resupply"},
	]:
		var b := Button.new(); b.text = str(item["t"]); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["heading"], 10)
		b.pressed.connect(func():
			app.audio.play("click")
			if item.has("preset"):
				app._select_tool(str(item["preset"]))
			else:
				app.active_fgd_entity = str(item["cls"]); app.active_tool = "place_fgd_entity"
				app._toast("Click in 3D to place " + str(item["t"]))
		)
		pg.add_child(b)

# ==============================================================================
# 10. VISUAL 3D ENTITY I/O SMART WIRE PRESET DRAWER (Shift+W -> Click Target!)
# ==============================================================================
static func build_wire_preset_drawer(app: Node3D, vbox: VBoxContainer, src_idx: int, tgt_idx: int) -> void:
	var fonts: Dictionary = app.fonts
	var ents: Array = app.doc.get_entities()
	if src_idx < 0 or tgt_idx < 0 or src_idx >= ents.size() or tgt_idx >= ents.size():
		return
	var se: Dictionary = ents[src_idx]
	var te: Dictionary = ents[tgt_idx]
	var scls := str(se["classname"])
	var tcls := str(te["classname"])
	var tname := str(te["kv"].get("targetname", ""))
	if tname.is_empty():
		tname = "%s_%02d" % [tcls.get_slice("_", 1) if tcls.find("_") != -1 else tcls, tgt_idx]
		app.doc.set_entity_kv(tgt_idx, "targetname", tname)

	var c1 := HudWidgets.make_section_card("WIRE CONNECTION PAIR", fonts, HudWidgets.COL_CYAN)
	vbox.add_child(c1["panel"])
	var v1: VBoxContainer = c1["vbox"]
	v1.add_child(_lbl("SOURCE: #%d %s" % [src_idx, scls], fonts["heading"], 11, HudWidgets.COL_ACC))
	v1.add_child(_lbl("TARGET: #%d %s (name: %s)" % [tgt_idx, tcls, tname], fonts["heading"], 11, HudWidgets.COL_CYAN))

	var presets: Array = []
	if tcls == "func_door":
		if scls.begins_with("trigger_"):
			presets.append({"lbl": "Auto-Open & Close Door (Touch)", "pairs": [["OnStartTouch", "Open"], ["OnEndTouchAll", "Close"]]})
			presets.append({"lbl": "Open Door Once (OnStartTouch)", "pairs": [["OnStartTouch", "Open"]]})
		elif scls == "func_button":
			presets.append({"lbl": "Toggle Door on Button Press (OnPressed -> Toggle)", "pairs": [["OnPressed", "Toggle"]]})
			presets.append({"lbl": "Open Door on Press (OnPressed -> Open)", "pairs": [["OnPressed", "Open"]]})
		else:
			presets.append({"lbl": "Open Door (OnTrigger -> Open)", "pairs": [["OnTrigger", "Open"]]})
	elif tcls == "light" or tcls == "light_spot":
		presets.append({"lbl": "Toggle Light (OnTrigger -> Toggle)", "pairs": [["OnTrigger", "Toggle"]]})
		presets.append({"lbl": "Turn Light On (OnTrigger -> TurnOn)", "pairs": [["OnTrigger", "TurnOn"]]})
	elif tcls == "ambient_generic":
		presets.append({"lbl": "Play Sound FX (OnStartTouch -> PlaySound)", "pairs": [["OnStartTouch", "PlaySound"]]})
	elif tcls == "info_particle_system":
		presets.append({"lbl": "Start Particles (OnTrigger -> Start)", "pairs": [["OnTrigger", "Start"]]})
	elif scls == "team_control_point":
		presets.append({"lbl": "On RED Capture -> Trigger", "pairs": [["OnCapTeam1", "Trigger"]]})
		presets.append({"lbl": "On BLU Capture -> Trigger", "pairs": [["OnCapTeam2", "Trigger"]]})
	elif scls == "func_button":
		presets.append({"lbl": "On Button Press -> Trigger", "pairs": [["OnPressed", "Trigger"]]})
	elif scls.begins_with("trigger_"):
		presets.append({"lbl": "On Player Enter -> Trigger", "pairs": [["OnStartTouch", "Trigger"]]})
		presets.append({"lbl": "On Player Enter -> Enable", "pairs": [["OnStartTouch", "Enable"]]})
	if presets.is_empty():
		presets.append({"lbl": "Standard Relay Trigger (OnTrigger -> Trigger)", "pairs": [["OnTrigger", "Trigger"]]})
		presets.append({"lbl": "Enable Target (OnTrigger -> Enable)", "pairs": [["OnTrigger", "Enable"]]})
		presets.append({"lbl": "Disable Target (OnTrigger -> Disable)", "pairs": [["OnTrigger", "Disable"]]})

	var c2 := HudWidgets.make_section_card("1-CLICK TF2 SMART WIRE PRESETS", fonts, HudWidgets.COL_ACC)
	vbox.add_child(c2["panel"])
	var v2: VBoxContainer = c2["vbox"]
	for pr in presets:
		var b := Button.new(); b.text = str(pr["lbl"]); b.clip_text = true
		HudWidgets.style_tf2_button(b, fonts["heading"], 10, pr == presets[0])
		var pairs: Array = pr["pairs"]
		b.pressed.connect(func():
			for pair in pairs:
				app.doc.add_connection(src_idx, str(pair[0]), tname, str(pair[1]), "", 0.0, false)
			app._record_history("Visual 3D Wire -> " + tname)
			app.ent_vis.sync_all()
			app.audio.play("success")
			app._toast("Wired %s -> %s! Glowing 3D logic wire created." % [scls, tname])
			app._select_entity(src_idx)
			app._insp_tab = 2
			app._open_inspector_drawer()
		)
		v2.add_child(b)

# ==============================================================================
# 11. ORGANIZED SCENE OUTLINER & MAP LAYERS STUDIO (O)
# ==============================================================================
static func build_outliner_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	var ents: Array = app.doc.get_entities()
	var scount: int = app.doc.get_solid_count()

	var hdr_card := HudWidgets.make_section_card("MAP HIERARCHY  •  %d SOLIDS  •  %d ENTITIES" % [scount, ents.size()], fonts, HudWidgets.COL_ACC)
	vbox.add_child(hdr_card["panel"])
	var hvb: VBoxContainer = hdr_card["vbox"]

	var flt_le := LineEdit.new()
	flt_le.placeholder_text = "Filter scene (door, spawn, light, crate, solid)..."
	flt_le.text = app._outliner_search
	hvb.add_child(flt_le)

	var list_host := VBoxContainer.new()
	list_host.add_theme_constant_override("separation", 6)
	vbox.add_child(list_host)

	var populate := func(q_raw: String) -> void:
		app._outliner_search = q_raw
		for ch in list_host.get_children():
			ch.queue_free()
		var q := q_raw.to_lower().strip_edges()

		var groups := [
			{"id": "spawns", "title": "SPAWNS & TEAMS",     "col": HudWidgets.COL_RED,           "items": []},
			{"id": "obj",    "title": "OBJECTIVES & MODE",  "col": Color(0.98, 0.80, 0.20),      "items": []},
			{"id": "doors",  "title": "DOORS & LOGIC I/O",  "col": HudWidgets.COL_CYAN,          "items": []},
			{"id": "lights", "title": "LIGHTING & SKY",     "col": Color(1.0, 0.88, 0.45),       "items": []},
			{"id": "props",  "title": "3D PROPS & PICKUPS", "col": HudWidgets.COL_GREEN,         "items": []},
		]
		for i in range(ents.size()):
			var e: Dictionary = ents[i]
			var cls := str(e["classname"])
			var kv: Dictionary = e["kv"]
			var tn := str(kv.get("targetname", ""))
			var mdl := str(kv.get("model", "")).get_file().get_basename()
			var label := cls
			if not tn.is_empty(): label = "%s (%s)" % [tn, cls]
			elif not mdl.is_empty(): label = "%s (%s)" % [mdl, cls]
			if not q.is_empty() and label.to_lower().find(q) == -1:
				continue
			var ep: Vector3 = (e["bounds_min"] + e["bounds_max"]) * 0.5 if e.get("is_brush", false) else e["pos"]
			var item := {"idx": i, "label": label, "pos": ep, "cls": cls}
			if cls in ["info_player_teamspawn", "func_respawnroom", "func_regenerate"]:
				(groups[0]["items"] as Array).append(item)
			elif cls in ["team_control_point", "item_teamflag", "path_track", "mapobj_cart_dispenser", "func_capturezone", "trigger_capture_area", "func_upgradestation"] or cls.begins_with("tf_logic_"):
				(groups[1]["items"] as Array).append(item)
			elif cls in ["func_door", "func_button"] or cls.begins_with("trigger_") or cls.begins_with("logic_") or cls == "ambient_generic":
				(groups[2]["items"] as Array).append(item)
			elif cls.begins_with("light") or cls == "env_sun" or cls == "env_fog_controller":
				(groups[3]["items"] as Array).append(item)
			else:
				(groups[4]["items"] as Array).append(item)

		for g in groups:
			var gitems: Array = g["items"]
			if gitems.is_empty():
				continue
			var gid: String = str(g["id"])
			var collapsed: bool = bool(app._outliner_collapsed.get(gid, false)) and q.is_empty()
			var card := HudWidgets.make_section_card("", fonts, g["col"])
			list_host.add_child(card["panel"])
			var cvb: VBoxContainer = card["vbox"]

			var gh := Button.new()
			gh.text = "%s %s (%d)" % ["+" if collapsed else "-", str(g["title"]), gitems.size()]
			gh.alignment = HORIZONTAL_ALIGNMENT_LEFT
			HudWidgets.style_tf2_button(gh, fonts["heading"], 10, false)
			gh.pressed.connect(func():
				app.audio.play("click")
				app._outliner_collapsed[gid] = not bool(app._outliner_collapsed.get(gid, false))
				app._open_outliner_drawer()
			)
			cvb.add_child(gh)

			if not collapsed:
				var lim := mini(gitems.size(), 18)
				for k in range(lim):
					var it: Dictionary = gitems[k]
					var eidx: int = int(it["idx"])
					var epos: Vector3 = it["pos"]
					var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 4); cvb.add_child(row)
					var rb := Button.new()
					rb.text = "#%d %s" % [eidx, str(it["label"])]
					rb.alignment = HORIZONTAL_ALIGNMENT_LEFT
					rb.clip_text = true
					rb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
					rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					HudWidgets.style_tf2_button(rb, fonts["body"], 10, app.selected_entity == eidx)
					rb.pressed.connect(func():
						app.audio.play("click")
						app._select_entity(eidx)
						app._focus_camera_on_pos(epos, 10.0)
					)
					row.add_child(rb)
					var wb := Button.new(); wb.text = "Wire"
					wb.tooltip_text = "Visual 3D Wire from this entity (Shift+W)"
					HudWidgets.style_tf2_button(wb, fonts["body"], 9, false, 3)
					wb.pressed.connect(func(): app.audio.play("click"); app._select_entity(eidx); app._start_visual_3d_wire(eidx))
					row.add_child(wb)
				if gitems.size() > lim:
					cvb.add_child(_lbl("... +%d more (type above to filter)" % (gitems.size() - lim), fonts["mono"], 9, HudWidgets.COL_TX_MUTED))

		# World Geometry Summary Card
		var wcard := HudWidgets.make_section_card("WORLD GEOMETRY & CLIFFS (%d SOLIDS)" % scount, fonts, HudWidgets.COL_TX_MUTED)
		list_host.add_child(wcard["panel"])
		var wvb: VBoxContainer = wcard["vbox"]
		var shown_s := 0
		for s in range(scount):
			var si: Dictionary = app.doc.get_solid_info(s)
			if not si.get("valid", false) or si.get("is_skybox", false):
				continue
			var mat_nm := str(si.get("material", "brush")).get_file()
			var slbl := "Solid #%d (%s)" % [s, mat_nm]
			if not q.is_empty() and slbl.to_lower().find(q) == -1:
				continue
			var smid: Vector3 = (si["bounds_min"] + si["bounds_max"]) * 0.5
			var sb := Button.new(); sb.text = slbl; sb.alignment = HORIZONTAL_ALIGNMENT_LEFT; sb.clip_text = true
			sb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			HudWidgets.style_tf2_button(sb, fonts["body"], 10, app.selected_solid == s)
			var sid_c := s
			sb.pressed.connect(func():
				app.audio.play("click"); app._select_solid(sid_c, -1); app._focus_camera_on_pos(smid, 13.0)
			)
			wvb.add_child(sb)
			shown_s += 1
			if shown_s >= 12:
				wvb.add_child(_lbl("Showing first 12 matching solids (of %d)" % scount, fonts["mono"], 9, HudWidgets.COL_TX_MUTED))
				break

	populate.call(app._outliner_search)
	flt_le.text_changed.connect(populate)

# ==============================================================================
# 12. ORGANIZED VIEW & WORKSPACE STUDIO (Replaces Cryptic Top-Bar Abbreviations!)
# ==============================================================================
static func build_viewport_menu_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts

	# 1. Viewport Lighting (F3)
	var c1 := HudWidgets.make_section_card("1. VIEWPORT LIGHTING PREVIEW (F3)", fonts, Color(1.0, 0.85, 0.35))
	vbox.add_child(c1["panel"])
	var lrow := HBoxContainer.new(); lrow.add_theme_constant_override("separation", 4); (c1["vbox"] as VBoxContainer).add_child(lrow)
	var lmodes := [{"id": 0, "t": "Daylight"}, {"id": 1, "t": "Lit Interior"}, {"id": 2, "t": "Fullbright"}]
	for lm in lmodes:
		var b := Button.new(); b.text = str(lm["t"]); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["heading"], 10, app.lighting_mode == int(lm["id"]))
		var mid: int = int(lm["id"])
		b.pressed.connect(func(): app.audio.play("click"); app._set_lighting_mode(mid); app._open_viewport_menu_drawer())
		lrow.add_child(b)

	# 2. Build Symmetry Mode
	var c2 := HudWidgets.make_section_card("2. MIRROR / SYMMETRY BUILDING", fonts, HudWidgets.COL_CYAN)
	vbox.add_child(c2["panel"])
	var srow := HBoxContainer.new(); srow.add_theme_constant_override("separation", 4); (c2["vbox"] as VBoxContainer).add_child(srow)
	var smodes := [{"id": 0, "t": "Off"}, {"id": 1, "t": "Mirror X"}, {"id": 2, "t": "180° CTF/CP"}]
	for sm in smodes:
		var b := Button.new(); b.text = str(sm["t"]); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["heading"], 10, app.symmetry == int(sm["id"]))
		var sid: int = int(sm["id"])
		b.pressed.connect(func():
			app.audio.play("click"); app.symmetry = sid
			app.sym_plane.visible = (app.symmetry != 0) and not app.viewing_bsp
			app._open_viewport_menu_drawer()
		)
		srow.add_child(b)

	# 3. Workspace Panels & Visibility
	var c3 := HudWidgets.make_section_card("3. WORKSPACE PANELS & VISGROUPS", fonts, HudWidgets.COL_ACC)
	vbox.add_child(c3["panel"])
	var v3: VBoxContainer = c3["vbox"]
	var g3 := GridContainer.new(); g3.columns = 2; g3.add_theme_constant_override("h_separation", 6); g3.add_theme_constant_override("v_separation", 6)
	v3.add_child(g3)
	for act in [
		{"t": "Scene Outliner (O)",   "fn": func(): app._open_outliner_drawer()},
		{"t": "Mini-Map Radar (M)",   "fn": func(): app._toggle_minimap()},
		{"t": "Sniper Sightlines (Alt+S)", "fn": func(): app._toggle_sightline_analyzer()},
		{"t": "Split 2D Blueprints",  "fn": func(): app._toggle_split_2d()},
		{"t": "VisGroups & Layers",   "fn": func(): app._open_visgroups_drawer()},
		{"t": "Map Diagnostics",      "fn": func(): app._toggle_diagnostics_popover()},
		{"t": "Zen Viewport (Tab)",   "fn": func(): app._toggle_zen_mode()},
		{"t": "Focus Selection (F)",  "fn": func(): app._focus_camera_on_selection()},
	]:
		var b := Button.new(); b.text = str(act["t"]); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["body"], 10)
		var fn: Callable = act["fn"]
		b.pressed.connect(func(): app.audio.play("click"); fn.call())
		g3.add_child(b)

	# 4. Camera Bookmarks (Ctrl+1..4 Save / Alt+1..4 Jump!)
	var c4 := HudWidgets.make_section_card("4. CAMERA VIEWPOINT BOOKMARKS", fonts, HudWidgets.COL_GREEN)
	vbox.add_child(c4["panel"])
	var v4: VBoxContainer = c4["vbox"]
	v4.add_child(_lbl("Save key angles (Mid, RED Spawn, BLU Spawn, Vents) for 1-click jumping!", fonts["body"], 10, HudWidgets.COL_TX_MUTED))
	for slot in range(1, 5):
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 5); v4.add_child(row)
		var has_bm: bool = app._cam_bookmarks.has(slot)
		var jmp := Button.new()
		jmp.text = "Jump View %d (Alt+%d)%s" % [slot, slot, "" if has_bm else " — Empty"]
		jmp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		jmp.disabled = not has_bm
		HudWidgets.style_tf2_button(jmp, fonts["heading"], 10, has_bm)
		var s_id := slot
		jmp.pressed.connect(func(): app.audio.play("click"); app._jump_camera_bookmark(s_id))
		row.add_child(jmp)
		var sav := Button.new(); sav.text = "Save"
		HudWidgets.style_tf2_button(sav, fonts["body"], 10)
		sav.pressed.connect(func(): app.audio.play("save"); app._save_camera_bookmark(s_id); app._open_viewport_menu_drawer())
		row.add_child(sav)

# ==============================================================================
# 13. SMART TF2 ROOM & LAYOUT GENERATOR STUDIO (1-Click Complete Playable Rooms!)
# ==============================================================================
static func build_room_kit_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts

	var c1 := HudWidgets.make_section_card("1. TEAM THEME FOR GENERATED ROOMS", fonts, HudWidgets.COL_ACC)
	vbox.add_child(c1["panel"])
	var trow := HBoxContainer.new(); trow.add_theme_constant_override("separation", 6); (c1["vbox"] as VBoxContainer).add_child(trow)
	for tm in [{"id": 2, "t": "RED Team", "col": 2}, {"id": 3, "t": "BLU Team", "col": 3}, {"id": 0, "t": "Neutral", "col": 0}]:
		var b := Button.new(); b.text = str(tm["t"]); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["heading"], 10, app._room_kit_team == int(tm["id"]), int(tm["col"]))
		var tid: int = int(tm["id"])
		b.pressed.connect(func(): app.audio.play("click"); app._room_kit_team = tid; app._open_room_kit_drawer())
		trow.add_child(b)

	var c2 := HudWidgets.make_section_card("2. 1-CLICK COMPLETE TF2 STRUCTURES", fonts, HudWidgets.COL_GREEN)
	vbox.add_child(c2["panel"])
	var v2: VBoxContainer = c2["vbox"]
	v2.add_child(_lbl("Stamps complete, TF2-proportioned rooms with sliding doors, interior spotlights, resupply lockers, and team spawns!", fonts["body"], 10, HudWidgets.COL_TX_MUTED))

	var kits := [
		{"id": "spawn_full", "t": "Complete TF2 Spawn Room", "desc": "Room + sliding door + resupply + 4 spawns + spotlight"},
		{"id": "hallway",    "t": "Choke Hallway Connector", "desc": "192u corridor + 2 doorway openings + 2 ceiling lights"},
		{"id": "balcony",    "t": "Sniper Battlement Deck",  "desc": "Elevated ledge + rail + open steel stairs + medkit"},
		{"id": "mid_arena",  "t": "Mid Control Point Arena", "desc": "Raised cap point + dual ramps + cover + pickups"},
	]
	for kt in kits:
		var b := Button.new()
		b.text = "%s\n%s" % [str(kt["t"]), str(kt["desc"])]
		b.custom_minimum_size = Vector2(0, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		HudWidgets.style_tf2_button(b, fonts["body"], 10, kt == kits[0])
		var kid: String = str(kt["id"])
		b.pressed.connect(func():
			app.audio.play("carve")
			app._stamp_smart_room_kit(kid)
		)
		v2.add_child(b)

# ==============================================================================
# 14. 3D PROP SCATTER / FOLIAGE & COVER BRUSH STUDIO
# ==============================================================================
static func build_scatter_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts

	var c1 := HudWidgets.make_section_card("1. CHOOSE TF2 PROP SCATTER KIT", fonts, HudWidgets.COL_GREEN)
	vbox.add_child(c1["panel"])
	var v1: VBoxContainer = c1["vbox"]
	v1.add_child(_lbl("Click anywhere in 3D to paint naturally rotated & scaled prop clusters grounded cleanly onto terrain & cliffs (1-step Undo)!", fonts["body"], 10, HudWidgets.COL_TX_MUTED))

	var kits := [
		{"id": "winter_pines", "t": "Winter Snowy Pines"},
		{"id": "badlands",     "t": "Badlands Rocks & Shrubs"},
		{"id": "farm_cover",   "t": "Farm Crates & Barrels"},
		{"id": "spytech",      "t": "Spytech Consoles"},
		{"id": "industrial",   "t": "Industrial Oil Drums"},
		{"id": "active_prop",  "t": "Scatter Active Prop"},
	]
	var kg := GridContainer.new(); kg.columns = 2; kg.add_theme_constant_override("h_separation", 5); kg.add_theme_constant_override("v_separation", 5)
	v1.add_child(kg)
	for k in kits:
		var kid: String = str(k["id"])
		var b := Button.new(); b.text = str(k["t"]); b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["heading"], 10, app.scatter_kit == kid)
		b.pressed.connect(func():
			app.audio.play("click")
			app.scatter_kit = kid
			app.active_tool = "scatter_props"
			app._open_scatter_drawer()
		)
		kg.add_child(b)

	var c2 := HudWidgets.make_section_card("2. BRUSH RADIUS, DENSITY & VARIATION", fonts, HudWidgets.COL_ACC)
	vbox.add_child(c2["panel"])
	var v2: VBoxContainer = c2["vbox"]
	var g2 := GridContainer.new(); g2.columns = 2; g2.add_theme_constant_override("h_separation", 6); v2.add_child(g2)

	var rad_sb := SpinBox.new(); rad_sb.min_value = 96; rad_sb.max_value = 640; rad_sb.step = 32; rad_sb.value = app.scatter_radius_m * 32.0; rad_sb.prefix = "Radius: "; rad_sb.suffix = "u"
	rad_sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rad_sb.value_changed.connect(func(v: float): app.scatter_radius_m = v / 32.0)
	g2.add_child(rad_sb)

	var cnt_sb := SpinBox.new(); cnt_sb.min_value = 2; cnt_sb.max_value = 16; cnt_sb.step = 1; cnt_sb.value = app.scatter_count; cnt_sb.prefix = "Props: "
	cnt_sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cnt_sb.value_changed.connect(func(v: float): app.scatter_count = int(v))
	g2.add_child(cnt_sb)

	var rot_cb := CheckButton.new(); rot_cb.text = "Random Yaw Rotation (0°–360°)"; rot_cb.button_pressed = app.scatter_rand_yaw
	rot_cb.toggled.connect(func(on: bool): app.scatter_rand_yaw = on)
	v2.add_child(rot_cb)

	var sc_cb := CheckButton.new(); sc_cb.text = "Natural Scale Variation (0.85x–1.18x)"; sc_cb.button_pressed = app.scatter_rand_scale
	sc_cb.toggled.connect(func(on: bool): app.scatter_rand_scale = on)
	v2.add_child(sc_cb)

	var act_b := Button.new()
	act_b.text = "ACTIVE: Click 3D Ground to Stamp Cluster" if app.active_tool == "scatter_props" else "Activate Prop Scatter Brush"
	act_b.custom_minimum_size = Vector2(0, 38)
	HudWidgets.style_tf2_button(act_b, fonts["heading"], 11, true)
	act_b.pressed.connect(func(): app.audio.play("click"); app.active_tool = "scatter_props"; app._open_scatter_drawer(); app._toast("Prop Scatter Brush active — click ground/cliffs in 3D!"))
	v2.add_child(act_b)

# ==============================================================================
# 15. 3D SPLINE PATH / FENCE / GUARDRAIL / CATWALK BUILDER (Milestone 33)
# ==============================================================================
static func build_spline_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts

	var c1 := HudWidgets.make_section_card("1. CHOOSE SPLINE STRUCTURE STYLE", fonts, HudWidgets.COL_CYAN)
	vbox.add_child(c1["panel"])
	var v1: VBoxContainer = c1["vbox"]
	v1.add_child(_lbl("Click Point A -> B -> C in the 3D viewport to lay continuous aligned TF2 fences, guardrails, catwalks, or barriers! Press Esc or RMB to finish a chain.", fonts["body"], 10, HudWidgets.COL_TX_MUTED))

	var presets := [
		{"id": "fence",     "t": "Wooden Fence Line",  "sub": "Farm/Badlands boundary fence with posts"},
		{"id": "guardrail", "t": "Steel Guardrail",    "sub": "Industrial waist-high handrail + posts"},
		{"id": "catwalk",   "t": "Elevated Catwalk",   "sub": "Metal grate walkway + twin safety rails"},
		{"id": "barrier",   "t": "Concrete Barrier",   "sub": "Chest-high combat cover wall (48u)"},
	]
	for pr in presets:
		var pid: String = str(pr["id"])
		var b := Button.new()
		b.text = "%s\n%s" % [str(pr["t"]), str(pr["sub"])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		HudWidgets.style_tf2_button(b, fonts["body"], 10, app.spline_preset == pid)
		b.pressed.connect(func():
			app.audio.play("click")
			app.spline_preset = pid
			app.active_tool = "spline_path"
			app._open_spline_drawer()
			app._refresh_context_bar()
		)
		v1.add_child(b)

	var c2 := HudWidgets.make_section_card("2. DIMENSIONS & CHAIN CONTROLS", fonts, HudWidgets.COL_ACC)
	vbox.add_child(c2["panel"])
	var v2: VBoxContainer = c2["vbox"]
	var g2 := GridContainer.new(); g2.columns = 2; g2.add_theme_constant_override("h_separation", 6); v2.add_child(g2)

	var h_sb := SpinBox.new(); h_sb.min_value = 32; h_sb.max_value = 192; h_sb.step = 8; h_sb.value = app.spline_height_m * 32.0; h_sb.prefix = "Height: "; h_sb.suffix = "u"
	h_sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_sb.value_changed.connect(func(v: float): app.spline_height_m = v / 32.0)
	g2.add_child(h_sb)

	var w_sb := SpinBox.new(); w_sb.min_value = 8; w_sb.max_value = 160; w_sb.step = 8; w_sb.value = app.spline_width_m * 32.0; w_sb.prefix = "Width: "; w_sb.suffix = "u"
	w_sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	w_sb.value_changed.connect(func(v: float): app.spline_width_m = v / 32.0)
	g2.add_child(w_sb)

	var state_txt := "CHAIN ACTIVE (%d segments placed) — Click next point or Finish" % app.spline_seg_count if app.spline_chain_active else "Ready: Click Point A in 3D to start spline chain"
	v2.add_child(_lbl(state_txt, fonts["mono"], 10, HudWidgets.COL_GREEN if app.spline_chain_active else HudWidgets.COL_TX_MUTED))

	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 6); v2.add_child(row)
	var start_b := Button.new(); start_b.text = "Activate Spline Tool"; start_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudWidgets.style_tf2_button(start_b, fonts["heading"], 10, true)
	start_b.pressed.connect(func(): app.audio.play("click"); app.active_tool = "spline_path"; app._refresh_context_bar(); app._toast("Spline Path Builder active — click A -> B -> C in 3D!"))
	row.add_child(start_b)

	var fin_b := Button.new(); fin_b.text = "Finish Chain (Esc)"
	HudWidgets.style_tf2_button(fin_b, fonts["body"], 10)
	fin_b.pressed.connect(func():
		app.audio.play("click")
		app.spline_chain_active = false
		app.spline_seg_count = 0
		app._open_spline_drawer()
		app._toast("Finished spline chain — click anywhere to start a new one!")
	)
	row.add_child(fin_b)

# ==============================================================================
# 16. SMART TF2 GAMEMODE LOGIC STUDIO (CTF / KOTH / 5CP / A/D — Milestone 35)
# ==============================================================================
static func build_gamemode_wizard_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	var mode: String = str(app.active_gamemode)
	var ents: Array = app.doc.get_entities()

	var red_sp := 0; var blu_sp := 0; var has_rules := false; var has_koth := false
	var has_cp_master := false; var cp_cnt := 0; var red_flag := 0; var blu_flag := 0
	var red_cap := 0; var blu_cap := 0
	for e in ents:
		var cls := str(e.get("classname", ""))
		var kv: Dictionary = e.get("kv", {})
		var team := str(kv.get("TeamNum", "0"))
		if cls == "info_player_teamspawn":
			if team == "2": red_sp += 1
			elif team == "3": blu_sp += 1
		elif cls == "tf_gamerules": has_rules = true
		elif cls == "tf_logic_koth": has_koth = true
		elif cls == "team_control_point_master": has_cp_master = true
		elif cls == "team_control_point": cp_cnt += 1
		elif cls == "item_teamflag":
			if team == "2": red_flag += 1
			elif team == "3": blu_flag += 1
		elif cls == "func_capturezone":
			if team == "2": red_cap += 1
			elif team == "3": blu_cap += 1

	var c1 := HudWidgets.make_section_card("1. %s GAMEMODE LOGIC CHECKLIST" % mode.to_upper(), fonts, HudWidgets.COL_CYAN)
	vbox.add_child(c1["panel"])
	var v1: VBoxContainer = c1["vbox"]

	var add_chk := func(ok: bool, lbl_txt: String) -> void:
		var l := _lbl(("[OK] " if ok else "[MISSING] ") + lbl_txt, fonts["mono"], 10, HudWidgets.COL_GREEN if ok else HudWidgets.COL_ACC)
		v1.add_child(l)

	add_chk.call(has_rules, "tf_gamerules (Global TF2 Rules)")
	add_chk.call(red_sp >= 1 and blu_sp >= 1, "Team Spawns: %d RED / %d BLU" % [red_sp, blu_sp])
	if mode == "ctf":
		add_chk.call(red_flag >= 1 and blu_flag >= 1, "Intelligence Briefcases: %d RED / %d BLU" % [red_flag, blu_flag])
		add_chk.call(red_cap >= 1 and blu_cap >= 1, "Capture Zones: %d RED / %d BLU" % [red_cap, blu_cap])
	elif mode == "koth":
		add_chk.call(has_koth, "tf_logic_koth (3:00 King of the Hill Timer)")
		add_chk.call(cp_cnt >= 1, "Mid Control Point (%d found)" % cp_cnt)
	else:
		add_chk.call(has_cp_master, "team_control_point_master (CP Chain Logic)")
		add_chk.call(cp_cnt >= 3, "Control Points (%d found — 3 or 5 recommended)" % cp_cnt)

	var c2 := HudWidgets.make_section_card("2. ONE-CLICK GAMEMODE ENTITY STAMPS", fonts, HudWidgets.COL_ACC)
	vbox.add_child(c2["panel"])
	var v2: VBoxContainer = c2["vbox"]
	v2.add_child(_lbl("Automatically wires valid Valve TF2 gamemode entities so your map plays immediately in F5 Playtest AND compiled real TF2!", fonts["body"], 10, HudWidgets.COL_TX_MUTED))

	var actions := [
		{"id": "fix_ctf",    "t": "Stamp Complete CTF Logic\nAdds RED & BLU Intel Briefcases + Capture Zones + Gamerules"},
		{"id": "fix_koth",   "t": "Stamp Complete KOTH Logic\nAdds tf_logic_koth + Mid Control Point + Trigger Capture Area"},
		{"id": "fix_5cp",    "t": "Stamp Symmetrical 3CP Chain\nAdds CP Master + BLU Base / Mid / RED Base Control Points"},
		{"id": "fix_spawns", "t": "Stamp RED & BLU Spawn Kits\nAdds 4 RED + 4 BLU Team Spawns + Resupply Cabinets"},
	]
	for act in actions:
		var aid: String = str(act["id"])
		var is_rec := (mode == "ctf" and aid == "fix_ctf") or (mode == "koth" and aid == "fix_koth") or ((mode == "cp" or mode == "ad") and aid == "fix_5cp")
		var b := Button.new()
		b.text = str(act["t"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		HudWidgets.style_tf2_button(b, fonts["body"], 10, is_rec)
		b.pressed.connect(func():
			app.audio.play("place")
			app._apply_gamemode_wizard_stamp(aid)
			app._open_gamemode_wizard()
		)
		v2.add_child(b)

	var test_b := Button.new()
	test_b.text = "Test Objective Live in F5 Playtest!"
	test_b.custom_minimum_size = Vector2(0, 36)
	HudWidgets.style_tf2_button(test_b, fonts["heading"], 11, false, 3)
	test_b.pressed.connect(func(): app.audio.play("click"); app.set_stage(app.Stage.PLAYTEST))
	v2.add_child(test_b)
