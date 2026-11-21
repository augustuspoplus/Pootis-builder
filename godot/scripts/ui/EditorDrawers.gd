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
	ivb.add_child(_lbl("LMB: Paint Face | Alt+Click: Eyedropper", fonts["body"], 10, HudWidgets.COL_TX_MUTED))

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
				app.doc.record_undo("Replace Textures")
				app.map_sync.sync_all()
				app._toast("Replaced %d faces (%s -> %s)" % [n, old_m.get_file(), app.active_material.get_file()])
	)
	act_row.add_child(rep_b)

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
					app.doc.record_undo("Justify UV")
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
	search.placeholder_text = "Search 29k+ TF2 textures (wood, brick, blend…)"
	search.text = app._mat_search_text
	vbox.add_child(search)

	var list_root := VBoxContainer.new()
	list_root.add_theme_constant_override("separation", 6)
	vbox.add_child(list_root)

	var add_swatch_btn := func(g: GridContainer, label: String, mp: String) -> void:
		var is_act: bool = (str(app.active_material).to_lower() == mp.to_lower())
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 48)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		sw.texture = app.assets.get_material_swatch(mp)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
# 2. ALL-TF2 3D PROP BROWSER (Curated + ALL 7,000+ .MDL Search + Spinning 3D Preview!)
# ==============================================================================
static func build_props_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	# Live Rotating 3D Valve .mdl Preview SubViewport
	var pv_frame := PanelContainer.new()
	pv_frame.custom_minimum_size = Vector2(0, 140)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.10, 0.09, 0.08, 1.0)
	psb.border_color = HudWidgets.COL_ACC
	psb.set_border_width_all(1); psb.set_corner_radius_all(6)
	pv_frame.add_theme_stylebox_override("panel", psb)
	vbox.add_child(pv_frame)

	var svc := SubViewportContainer.new()
	svc.stretch = true; svc.custom_minimum_size = Vector2(280, 134)
	pv_frame.add_child(svc)
	var svp := SubViewport.new()
	svp.own_world_3d = true; svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(svp)
	var pwe := WorldEnvironment.new()
	var penv := Environment.new()
	penv.background_mode = Environment.BG_COLOR; penv.background_color = Color(0.13, 0.11, 0.10)
	penv.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	penv.ambient_light_color = Color(0.88, 0.86, 0.82); penv.ambient_light_energy = 1.0
	pwe.environment = penv; svp.add_child(pwe)
	var pl := DirectionalLight3D.new(); pl.rotation_degrees = Vector3(-35, 42, 0); pl.light_energy = 1.5; svp.add_child(pl)
	var pcam := Camera3D.new(); pcam.fov = 42.0; svp.add_child(pcam)
	var pmesh: ArrayMesh = app.assets.get_model_mesh(app.active_prop_mdl)
	var pmi := MeshInstance3D.new(); pmi.mesh = pmesh; svp.add_child(pmi)
	app._prop_preview_mesh = pmi
	if pmesh != null:
		var aabb := pmesh.get_aabb()
		var center := aabb.position + aabb.size * 0.5
		var rad := maxf(aabb.size.length() * 0.62, 0.6)
		pmi.position = -center
		pcam.look_at_from_position(Vector3(rad * 1.15, rad * 0.65, rad * 1.15), Vector3.ZERO, Vector3.UP)
	else:
		pcam.look_at_from_position(Vector3(2.5, 1.5, 2.5), Vector3.ZERO, Vector3.UP)

	vbox.add_child(_lbl("Active: " + app.active_prop_mdl, fonts["mono"], 10, HudWidgets.COL_ACC))

	var mrow := HBoxContainer.new(); mrow.add_theme_constant_override("separation", 4); vbox.add_child(mrow)
	var bc := Button.new(); bc.text = "Curated Props"; bc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudWidgets.style_tf2_button(bc, fonts["heading"], 10, not app._prop_browse_all)
	bc.pressed.connect(func(): app._prop_browse_all = false; app._open_props_drawer())
	mrow.add_child(bc)
	var ba := Button.new(); ba.text = "ALL 7,000+ TF2 Models"; ba.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudWidgets.style_tf2_button(ba, fonts["heading"], 10, app._prop_browse_all)
	ba.pressed.connect(func(): app._prop_browse_all = true; app._open_props_drawer())
	mrow.add_child(ba)

	var search := LineEdit.new()
	search.placeholder_text = "Search ALL TF2 .mdl props (2fort, farm, spytech, barrel, train…)"
	search.text = app._prop_search_text
	vbox.add_child(search)

	var list_root := VBoxContainer.new(); list_root.add_theme_constant_override("separation", 5); vbox.add_child(list_root)
	var populate := func(flt: String) -> void:
		app._prop_search_text = flt
		for ch in list_root.get_children():
			ch.queue_free()
		var fl := flt.to_lower().strip_edges()
		if app._prop_browse_all or fl.length() >= 3:
			var found: PackedStringArray = app.core.search_models(fl, 60)
			list_root.add_child(_lbl("ALL TF2 MODELS (%d shown — click to select & place):" % found.size(), fonts["heading"], 10, HudWidgets.COL_CYAN))
			var g := GridContainer.new(); g.columns = 2; list_root.add_child(g)
			for m in found:
				var mp := str(m)
				var b := Button.new()
				b.text = mp.get_file().get_basename()
				b.tooltip_text = mp
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				HudWidgets.style_tf2_button(b, fonts["body"], 10, app.active_prop_mdl == mp)
				b.pressed.connect(func():
					app.active_prop_mdl = mp; app.active_tool = "place_prop"
					app.audio.play("click"); app._toast("Click in 3D to place " + mp.get_file())
					app._open_props_drawer()
				)
				g.add_child(b)
			return
		for cat in Tf2CatalogScript.PROP_CATEGORIES.keys():
			var items: Array = []
			for item in Tf2CatalogScript.PROP_CATEGORIES[cat]:
				if fl.is_empty() or str(item["name"]).to_lower().find(fl) != -1 or str(item["mdl"]).to_lower().find(fl) != -1:
					items.append(item)
			if items.is_empty(): continue
			_sec(list_root, str(cat).to_upper(), fonts)
			var g := GridContainer.new(); g.columns = 2; list_root.add_child(g)
			for item in items:
				var mp: String = item["mdl"]
				var nm: String = item["name"]
				var b := Button.new(); b.text = nm; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				HudWidgets.style_tf2_button(b, fonts["body"], 11, app.active_prop_mdl == mp)
				b.pressed.connect(func():
					app.active_prop_mdl = mp; app.active_tool = "place_prop"
					app.audio.play("click"); app._toast("Click in 3D to place " + nm)
					app._open_props_drawer()
				)
				g.add_child(b)
	populate.call(app._prop_search_text)
	search.text_changed.connect(populate)

# ==============================================================================
# 3. ALL-450+ TF2 FGD ENTITY BROWSER (Shift+E — base.fgd + tf.fgd + tf-abs.fgd!)
# ==============================================================================
static func build_fgd_entity_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	vbox.add_child(_lbl("Browse & place ANY of the %d Valve TF2 + ABS FGD entity classes! Active: %s" % [
		app.core.get_fgd_class_count(), app.active_fgd_entity
	], fonts["body"], 11, HudWidgets.COL_TX_MUTED))

	var search := LineEdit.new()
	search.placeholder_text = "Search all TF2 entities (tf_, info_, item_, light, env_, logic_…)"
	search.text = app._ent_search_text
	vbox.add_child(search)

	var list_root := VBoxContainer.new(); list_root.add_theme_constant_override("separation", 4); vbox.add_child(list_root)
	var populate := func(flt: String) -> void:
		app._ent_search_text = flt
		for ch in list_root.get_children():
			ch.queue_free()
		var classes: PackedStringArray = app.core.list_fgd_point_classes(flt.strip_edges())
		var shown := 0
		for cls in classes:
			if shown >= 55: break
			var cs := str(cls)
			var b := Button.new()
			b.text = cs
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			HudWidgets.style_tf2_button(b, fonts["mono"], 11, app.active_fgd_entity == cs)
			b.pressed.connect(func():
				app.active_fgd_entity = cs
				app.active_tool = "place_fgd_entity"
				app.audio.play("click")
				app._toast("Click in 3D to place FGD entity: " + cs)
				app._open_fgd_entity_drawer()
			)
			list_root.add_child(b)
			shown += 1
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

		_sec(vbox, "ENTITY #%d — %s" % [app.selected_entity, cls], fonts)
		if fgd.get("found", false) and not str(fgd.get("description", "")).is_empty():
			vbox.add_child(_lbl(str(fgd["description"]), fonts["body"], 10, HudWidgets.COL_TX_MUTED))

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
						app.doc.record_undo("Set " + key)
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
						app.doc.record_undo("Set " + key)
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
							app.doc.record_undo("Toggle Flag")
						)
						vbox.add_child(cb)
			if not found_flags:
				vbox.add_child(_lbl("No FGD spawnflags defined for this entity class.", fonts["body"], 11, HudWidgets.COL_TX_MUTED))

		elif app._insp_tab == 2:
			# Outputs I/O List with Delete buttons + Full Add Output Builder (Param, Delay, Once Only!)
			var conns: Array = e.get("connections", [])
			for ci in range(conns.size()):
				var c: Dictionary = conns[ci]
				var crow := HBoxContainer.new(); crow.add_theme_constant_override("separation", 4); vbox.add_child(crow)
				var cl := _lbl("• %s -> %s" % [str(c["output"]), str(c["args"])], fonts["mono"], 10, HudWidgets.COL_CYAN)
				cl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				crow.add_child(cl)
				var del_c := Button.new(); del_c.text = "X"
				HudWidgets.style_tf2_button(del_c, fonts["body"], 9, false, 2)
				var cidx := ci
				del_c.pressed.connect(func():
					app.doc.remove_connection(app.selected_entity, cidx)
					app.doc.record_undo("Remove Output")
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
					app.doc.record_undo("Add I/O Output")
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
# 5. VERTICAL CLIFF & DISPLACEMENT TERRAIN STUDIO (Phase 3 Engine Overhaul!)
# ==============================================================================
static func build_terrain_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	_sec(vbox, "CREATE DISPLACEMENTS (FLOORS & VERTICAL CLIFFS)", fonts)
	var b_floor := Button.new(); b_floor.text = "+ Flat Ground Patch (512×512u Power-3)"
	HudWidgets.style_tf2_button(b_floor, fonts["heading"], 11, true)
	b_floor.pressed.connect(func():
		var p: Vector3 = app.hover_pos if app.hover_valid else Vector3.ZERO
		app.doc.make_terrain_patch(p + Vector3(-8, -1, -8), p + Vector3(8, 0, 8), 3, Tf2GamemodesScript.get_biome(app.active_biome)["floor"])
		app.doc.record_undo("Add Terrain Patch")
		app.map_sync.sync_all(); app.audio.play("place")
		app._toast("Added Power-3 Ground Displacement! Hold LMB to sculpt.")
	)
	vbox.add_child(b_floor)

	# Cliff Facing Direction + Height controls!
	var cf_row := HBoxContainer.new(); cf_row.add_theme_constant_override("separation", 4); vbox.add_child(cf_row)
	var dir_names: Array[String] = ["South", "North", "East", "West"]
	for di in range(4):
		var db := Button.new(); db.text = dir_names[di]; db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(db, fonts["body"], 10, app.cliff_facing == di)
		var dv := di
		db.pressed.connect(func(): app.cliff_facing = dv; app._open_terrain_studio())
		cf_row.add_child(db)

	var ch_lbl := Label.new(); ch_lbl.text = "Cliff Height: %du  |  Power: %d" % [int(round(app.cliff_height_m * 32.0)), app.cliff_power]
	vbox.add_child(ch_lbl)
	var ch_sl := HSlider.new(); ch_sl.min_value = 6.0; ch_sl.max_value = 16.0; ch_sl.step = 1.0; ch_sl.value = app.cliff_height_m
	ch_sl.value_changed.connect(func(v): app.cliff_height_m = v; ch_lbl.text = "Cliff Height: %du  |  Power: %d" % [int(round(v * 32.0)), app.cliff_power])
	vbox.add_child(ch_sl)

	var b_cliff := Button.new(); b_cliff.text = "+ Vertical Rocky Cliff Wall (512×%du!)" % int(round(app.cliff_height_m * 32.0))
	HudWidgets.style_tf2_button(b_cliff, fonts["heading"], 11, false, 3)
	b_cliff.pressed.connect(func():
		var p: Vector3 = app.hover_pos if app.hover_valid else Vector3(0, 0, -10)
		var mat := "NATURE/BLENDROCKWALLDIRT001"
		var a := p + Vector3(-8, 0, 0); var b := p + Vector3(8, 0, 0)
		if app.cliff_facing == 1: a = p + Vector3(8, 0, 0); b = p + Vector3(-8, 0, 0)
		elif app.cliff_facing == 2: a = p + Vector3(0, 0, 8); b = p + Vector3(0, 0, -8)
		elif app.cliff_facing == 3: a = p + Vector3(0, 0, -8); b = p + Vector3(0, 0, 8)
		var cid: int = app.doc.make_cliff_wall(a, b, app.cliff_height_m, 2.5, app.cliff_power, mat, 1.2)
		if cid >= 0:
			app.doc.record_undo("Add Rocky Cliff Wall")
			app.map_sync.sync_all(); app._select_solid(cid, -1); app.audio.play("place")
			app._toast("Built stratified TF2 Canyon Cliff Wall! Sculpt with Axis = Face Nrm.")
	)
	vbox.add_child(b_cliff)

	_sec(vbox, "SCULPT & PAINT ALPHA MODE", fonts)
	var mnames := ["Raise", "Lower", "Smooth", "Flatten", "Paint Alpha+", "Paint Alpha-", "Rock Noise"]
	var g := GridContainer.new(); g.columns = 2; vbox.add_child(g)
	for i in range(mnames.size()):
		var b := Button.new(); b.text = mnames[i]; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["body"], 10, app.terrain_mode == i)
		var mv := i
		b.pressed.connect(func(): app.terrain_mode = mv; app._open_terrain_studio())
		g.add_child(b)

	_sec(vbox, "SCULPT AXIS (HAMMER Z-UP AXES)", fonts)
	var ax_row := HBoxContainer.new(); ax_row.add_theme_constant_override("separation", 3); vbox.add_child(ax_row)
	var anames := ["Face Nrm", "Up (Z)", "East (X)", "North (Y)"]
	for i in range(4):
		var b := Button.new(); b.text = anames[i]; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["body"], 10, app.terrain_axis_mode == i)
		var av := i
		b.pressed.connect(func(): app.terrain_axis_mode = av; app._open_terrain_studio())
		ax_row.add_child(b)

	var r_lbl := Label.new(); r_lbl.text = "Brush Radius: %du" % int(round(app.terrain_radius_m * 32.0)); vbox.add_child(r_lbl)
	var r_sl := HSlider.new(); r_sl.min_value = 1.5; r_sl.max_value = 12.0; r_sl.step = 0.5; r_sl.value = app.terrain_radius_m
	r_sl.value_changed.connect(func(v): app.terrain_radius_m = v; r_lbl.text = "Brush Radius: %du" % int(round(v * 32.0)))
	vbox.add_child(r_sl)

	var s_lbl := Label.new(); s_lbl.text = "Brush Strength: %du" % int(round(app.terrain_strength_m * 32.0)); vbox.add_child(s_lbl)
	var s_sl := HSlider.new(); s_sl.min_value = 0.25; s_sl.max_value = 3.5; s_sl.step = 0.25; s_sl.value = app.terrain_strength_m
	s_sl.value_changed.connect(func(v): app.terrain_strength_m = v; s_lbl.text = "Brush Strength: %du" % int(round(v * 32.0)))
	vbox.add_child(s_sl)

	_sec(vbox, "HAMMER SEW & SUBDIVIDE", fonts)
	var t_row := HBoxContainer.new(); t_row.add_theme_constant_override("separation", 5); vbox.add_child(t_row)
	var b_sew := Button.new(); b_sew.text = "Sew All Edges"; b_sew.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudWidgets.style_tf2_button(b_sew, fonts["heading"], 11)
	b_sew.pressed.connect(func():
		var n: int = app.doc.sew_displacements()
		app.doc.record_undo("Sew Displacements"); app.map_sync.sync_all(); app.audio.play("carve")
		app._toast("Sewed %d displacement seam vertices cleanly (0 cracks)!" % n)
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
	vbox.add_child(_lbl("Map Coach Grade: %s  |  Problems Found: %d\nSolids: %d  |  Entities: %d  |  Heavy Walk: %.1fs" % [
		rep["grade"], probs.size(), rep["solids"], rep["entities"], rep["walk_time_heavy_s"]
	], fonts["body"], 11, HudWidgets.COL_GREEN if probs.is_empty() else HudWidgets.COL_ACC))

	if probs.is_empty():
		vbox.add_child(_lbl("✓ Zero map errors detected — ready to compile cleanly in Valve vbsp!", fonts["heading"], 12, HudWidgets.COL_GREEN))
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
		app.doc.record_undo("Fix All Problems")
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
				app.doc.record_undo("Fix " + fk)
				app._open_check_problems_drawer()
			)
			brow.add_child(fix_b)
