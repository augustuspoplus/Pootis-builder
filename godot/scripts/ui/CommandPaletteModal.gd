class_name CommandPaletteModal
extends ColorRect

## Milestone 29 — Universal Instant Quick-Search Command Palette (Ctrl+K)!
## Search across Editor Actions, all 452 Valve TF2 Entities, Valve Props,
## Saved .VMF Maps, and Official TF2 .BSP Maps with full keyboard navigation.

const HudWidgets         = preload("res://scripts/ui/Tf2HudWidgets.gd")
const Tf2CatalogScript   = preload("res://scripts/core/Tf2Catalog.gd")

var app: Node3D
var fonts: Dictionary = {}
var card_frame: PanelContainer
var search_le: LineEdit
var results_vb: VBoxContainer
var _items: Array[Dictionary] = []
var _selected_idx: int = 0
var _row_btns: Array[Button] = []

func setup(p_app: Node3D) -> void:
	app = p_app
	fonts = app.fonts
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color(0.04, 0.03, 0.02, 0.68)
	visible = false
	_build_shell()

func open_palette() -> void:
	if card_frame != null and get_window() != null:
		var sf := maxf(get_window().content_scale_factor, 0.5)
		var eff_w := float(get_window().size.x) / sf
		var eff_h := float(get_window().size.y) / sf
		card_frame.custom_minimum_size = Vector2(
			minf(680.0, maxf(460.0, eff_w - 40.0)),
			minf(480.0, maxf(300.0, eff_h - 48.0))
		)
	visible = true
	search_le.text = ""
	_selected_idx = 0
	_rebuild_results("")
	search_le.grab_focus()
	if is_inside_tree():
		modulate = Color(1, 1, 1, 0)
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(self, "modulate", Color.WHITE, 0.12)

func close_palette() -> void:
	visible = false
	if get_viewport() != null:
		get_viewport().gui_release_focus()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		if card_frame != null and not card_frame.get_global_rect().has_point(get_global_mouse_position()):
			close_palette()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		var ek := event as InputEventKey
		if ek.keycode == KEY_ESCAPE:
			close_palette()
			get_viewport().set_input_as_handled()
		elif ek.keycode == KEY_DOWN:
			if not _items.is_empty():
				_selected_idx = (_selected_idx + 1) % _items.size()
				_refresh_selection_styles()
			get_viewport().set_input_as_handled()
		elif ek.keycode == KEY_UP:
			if not _items.is_empty():
				_selected_idx = (_selected_idx - 1 + _items.size()) % _items.size()
				_refresh_selection_styles()
			get_viewport().set_input_as_handled()
		elif ek.keycode == KEY_ENTER or ek.keycode == KEY_KP_ENTER:
			if _selected_idx >= 0 and _selected_idx < _items.size():
				_run_item(_items[_selected_idx])
			get_viewport().set_input_as_handled()

func _build_shell() -> void:
	for ch in get_children():
		ch.queue_free()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	card_frame = HudWidgets.HudFrame.new(HudWidgets.COL_ACC, 12.0, true)
	card_frame.custom_minimum_size = Vector2(680, 480)
	center.add_child(card_frame)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card_frame.add_child(vb)

	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	vb.add_child(hdr)

	var ttl := Label.new()
	ttl.text = "QUICK COMMAND PALETTE (CTRL+K)"
	ttl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ttl.add_theme_font_override("font", fonts["heading"])
	ttl.add_theme_font_size_override("font_size", 14)
	ttl.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	hdr.add_child(ttl)

	var hint := Label.new()
	hint.text = "Up/Down Select  |  Enter Run  |  Esc Close"
	hint.add_theme_font_override("font", fonts["mono"])
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	hdr.add_child(hint)

	search_le = LineEdit.new()
	search_le.placeholder_text = "Type a tool, TF2 entity, prop, saved .vmf, or official map (e.g. hollow, sentry, turbine, upward)..."
	search_le.custom_minimum_size = Vector2(0, 36)
	search_le.add_theme_font_override("font", fonts["body"])
	search_le.add_theme_font_size_override("font_size", 13)
	search_le.text_changed.connect(func(t: String): _selected_idx = 0; _rebuild_results(t))
	vb.add_child(search_le)

	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)

	results_vb = VBoxContainer.new()
	results_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results_vb.add_theme_constant_override("separation", 4)
	sc.add_child(results_vb)

func _collect_candidates(query: String) -> Array[Dictionary]:
	var q := query.to_lower().strip_edges()
	var out: Array[Dictionary] = []

	# 1. High-value Editor Commands & Studios
	var cmds := [
		{"tag": "ACTION", "col": HudWidgets.COL_ACC,  "title": "Compile & Launch in Real TF2 (F9)",        "sub": "Open Valve vbsp/vvis/vrad Compile Studio", "kind": "cmd", "id": "compile"},
		{"tag": "ACTION", "col": HudWidgets.COL_ACC,  "title": "Cycle Lighting: Daylight / Lit Interior / Fullbright (F3)", "sub": "Preview real TF2 light & light_spot illumination or fullbright blockout", "kind": "cmd", "id": "lighting"},
		{"tag": "ACTION", "col": HudWidgets.COL_CYAN, "title": "Visual 3D Entity I/O Wiring (Shift+W)",    "sub": "Click source -> click target entity in 3D for 1-click TF2 outputs", "kind": "cmd", "id": "wire3d"},
		{"tag": "ACTION", "col": HudWidgets.COL_ACC,  "title": "Save Selected Solids as Custom Prefab",    "sub": "Save room/structure to godot/maps/prefabs/ for 1-click reuse", "kind": "cmd", "id": "save_prefab"},
		{"tag": "ACTION", "col": HudWidgets.COL_GREEN,"title": "Export Shareable Map Bundle (.bsp + .vmf + .pop)", "sub": "Package compiled map & install guide into godot/exports/", "kind": "cmd", "id": "export_bundle"},
		{"tag": "ACTION", "col": HudWidgets.COL_ACC,  "title": "Toggle Zen Viewport Mode (Tab)",           "sub": "Hide/show all HUD chrome for clean 3D inspection", "kind": "cmd", "id": "zen"},
		{"tag": "ACTION", "col": HudWidgets.COL_ACC,  "title": "Open Mann Co. Workshop Hub",               "sub": "Create map, open saved .vmf, or walk official maps", "kind": "cmd", "id": "hub"},
		{"tag": "STUDIO", "col": HudWidgets.COL_CYAN, "title": "Scene Outliner & Map Hierarchy (O)",        "sub": "Browse Spawns, Doors, Lights, Props & Solids — click to frame", "kind": "cmd", "id": "outliner"},
		{"tag": "STUDIO", "col": HudWidgets.COL_ACC,  "title": "View & Workspace Studio",                   "sub": "Lighting (F3), Symmetry, Split 2D, VisGroups & Camera Bookmarks", "kind": "cmd", "id": "view_studio"},
		{"tag": "STUDIO", "col": HudWidgets.COL_GREEN,"title": "Smart TF2 Room & Layout Generator",         "sub": "1-click complete RED/BLU Spawn Rooms, Hallways, Sniper Decks & Mid Arenas", "kind": "cmd", "id": "room_kit"},
		{"tag": "STUDIO", "col": HudWidgets.COL_GREEN,"title": "3D Prop Scatter & Foliage Brush",           "sub": "Click to paint grounded clusters of pines, rocks, crates & consoles", "kind": "cmd", "id": "scatter"},
		{"tag": "STUDIO", "col": HudWidgets.COL_CYAN, "title": "3D Spline Path / Fence / Catwalk Builder",  "sub": "Click A -> B -> C in 3D to lay aligned fences, guardrails, catwalks & cover", "kind": "cmd", "id": "spline_path"},
		{"tag": "ACTION", "col": HudWidgets.COL_CYAN, "title": "Drop Selection to Floor (End)",             "sub": "Snap selected solid(s) or entity cleanly flush onto the surface below", "kind": "cmd", "id": "drop_floor"},
		{"tag": "ACTION", "col": HudWidgets.COL_ACC,  "title": "Auto-Texture Selected Solid (Active Biome)","sub": "Auto-apply biome roof, floor & wall textures by face normal", "kind": "cmd", "id": "auto_biome"},
		{"tag": "ACTION", "col": HudWidgets.COL_CYAN, "title": "Focus Camera on Selection (F)",             "sub": "Frame the 3D camera smoothly onto the active solid or entity", "kind": "cmd", "id": "focus"},
		{"tag": "STUDIO", "col": Color(0.74, 0.42, 0.96), "title": "Mann vs. Machine (MvM) Studio",        "sub": "Robot Spawns, Tank Track & Valve .pop Wave Exporter", "kind": "cmd", "id": "mvm_studio"},
		{"tag": "STUDIO", "col": Color(0.98, 0.80, 0.20), "title": "Payload Track Spline Studio",          "sub": "Click-to-chain auto-linked path_track rails & landmarks", "kind": "cmd", "id": "payload_studio"},
		{"tag": "TOOL",   "col": HudWidgets.COL_CYAN, "title": "Face Edit Sheet & 29k+ TF2 Materials (Shift+A)", "sub": "Paint faces, edit UVs, browse all Valve textures", "kind": "cmd", "id": "materials"},
		{"tag": "TOOL",   "col": HudWidgets.COL_CYAN, "title": "Interactive 3D Clip Plane (Shift+X)",      "sub": "Click Point A -> Point B in 3D to slice selected brush", "kind": "cmd", "id": "clip3d"},
		{"tag": "TOOL",   "col": HudWidgets.COL_CYAN, "title": "Make Hollow Room (Selected Solid)",        "sub": "Turn a solid box into 6 sealed walls", "kind": "cmd", "id": "hollow"},
		{"tag": "TOOL",   "col": HudWidgets.COL_CYAN, "title": "Mirror Selected BLU <-> RED (180 deg)",    "sub": "Clone symmetrically across map center & swap team textures", "kind": "cmd", "id": "mirror"},
		{"tag": "TOOL",   "col": HudWidgets.COL_GREEN,"title": "Auto-Seal Skybox Shell",                   "sub": "Wrap entire map cleanly in TOOLSSKYBOX (0 leaks)", "kind": "cmd", "id": "seal"},
		{"tag": "TOOL",   "col": HudWidgets.COL_GREEN,"title": "Check Map for Problems (Alt+P)",           "sub": "Run leak, spawn, lighting & gamemode diagnostics", "kind": "cmd", "id": "check"},
		{"tag": "TOOL",   "col": HudWidgets.COL_GREEN,"title": "Toggle Split 2D Blueprint Views",          "sub": "Top (X/Y) & Side (X/Z) elevation with jump guides", "kind": "cmd", "id": "split2d"},
		{"tag": "ACTION", "col": HudWidgets.COL_TX,   "title": "Settings & UI Scale (Ctrl+,)",             "sub": "Display scaling 100%-225%, graphics, keybinds, compilers", "kind": "cmd", "id": "settings"},
		{"tag": "PLAY",   "col": HudWidgets.COL_RED,  "title": "Walk Inside Map / Playtest (F5)",          "sub": "First-person TF2 movement, rocket jumping & sliding doors", "kind": "cmd", "id": "playtest"},
	]
	for c in cmds:
		if q.is_empty() or str(c["title"]).to_lower().find(q) != -1 or str(c["sub"]).to_lower().find(q) != -1:
			out.append(c)

	# 2. Saved .VMF Maps
	var maps_dir: String = app.repo_root.path_join("godot/maps")
	var d := DirAccess.open(maps_dir)
	if d != null:
		d.list_dir_begin()
		var fn := d.get_next()
		while not fn.is_empty():
			if not d.current_is_dir() and fn.to_lower().ends_with(".vmf") and not fn.contains("_autosave_"):
				if q.is_empty() or fn.to_lower().find(q) != -1 or "vmf".find(q) != -1:
					out.append({"tag": "VMF", "col": HudWidgets.COL_ACC, "title": "Open Saved Map: " + fn, "sub": maps_dir.path_join(fn), "kind": "vmf", "id": maps_dir.path_join(fn)})
			fn = d.get_next()
		d.list_dir_end()

	# 3. Valve Map Props
	for vp in Tf2CatalogScript.VALVE_MAP_BUILD_PROPS:
		var nm := str(vp["name"])
		var mp := str(vp["mdl"])
		if q.is_empty() or nm.to_lower().find(q) != -1 or mp.to_lower().find(q) != -1 or str(vp["sub"]).to_lower().find(q) != -1:
			out.append({"tag": "PROP", "col": Color(0.92, 0.76, 0.32), "title": nm, "sub": "%s (%s)" % [str(vp["sub"]), mp], "kind": "prop", "id": mp})

	# 4. Live Search All 452 TF2 Entities (when user types >= 2 chars)
	if q.length() >= 2 and app.core != null:
		var all_ents: Array = app.core.list_fgd_classes(0)
		var ent_hits := 0
		for e in all_ents:
			var cls := str(e.get("name", ""))
			var desc := str(e.get("description", ""))
			if cls.to_lower().find(q) != -1 or desc.to_lower().find(q) != -1:
				out.append({"tag": "ENTITY", "col": HudWidgets.COL_CYAN, "title": cls, "sub": desc if not desc.is_empty() else "TF2 Valve FGD Entity", "kind": "entity", "id": cls})
				ent_hits += 1
				if ent_hits >= 10:
					break

	# 5. Official TF2 .BSP Maps (when user types >= 2 chars)
	if q.length() >= 2 and app.core != null:
		var bsp_hits := 0
		for bm in app.core.list_maps():
			var bname := str(bm)
			if bname.to_lower().find(q) != -1:
				out.append({"tag": "TF2 MAP", "col": HudWidgets.COL_BLU, "title": "Walk Official Map: " + bname, "sub": "Load official Valve BSP and walk inside (F5)", "kind": "bsp", "id": bname})
				bsp_hits += 1
				if bsp_hits >= 6:
					break

	return out.slice(0, 24)

func _rebuild_results(query: String) -> void:
	for ch in results_vb.get_children():
		ch.queue_free()
	_row_btns.clear()
	_items = _collect_candidates(query)
	if _items.is_empty():
		var l := Label.new()
		l.text = "No matches found for \"%s\"" % query
		l.add_theme_font_override("font", fonts["body"])
		l.add_theme_font_size_override("font_size", 12)
		l.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
		results_vb.add_child(l)
		return

	_selected_idx = clampi(_selected_idx, 0, _items.size() - 1)
	for i in range(_items.size()):
		var it: Dictionary = _items[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 40)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 8; hb.offset_right = -8; hb.offset_top = 4; hb.offset_bottom = -4
		hb.add_theme_constant_override("separation", 8)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(hb)

		var tag_l := Label.new()
		tag_l.text = "[%s]" % str(it["tag"])
		tag_l.custom_minimum_size = Vector2(68, 0)
		tag_l.add_theme_font_override("font", fonts["mono"])
		tag_l.add_theme_font_size_override("font_size", 10)
		tag_l.add_theme_color_override("font_color", it["col"])
		tag_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(tag_l)

		var tvb := VBoxContainer.new()
		tvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tvb.alignment = BoxContainer.ALIGNMENT_CENTER
		tvb.add_theme_constant_override("separation", 1)
		tvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(tvb)

		var t1 := Label.new()
		t1.text = str(it["title"])
		t1.clip_text = true
		t1.add_theme_font_override("font", fonts["heading"])
		t1.add_theme_font_size_override("font_size", 11)
		t1.add_theme_color_override("font_color", HudWidgets.COL_TX)
		t1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tvb.add_child(t1)

		var t2 := Label.new()
		t2.text = str(it["sub"])
		t2.clip_text = true
		t2.add_theme_font_override("font", fonts["body"])
		t2.add_theme_font_size_override("font_size", 10)
		t2.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
		t2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tvb.add_child(t2)

		var idx := i
		b.pressed.connect(func(): _run_item(_items[idx]))
		results_vb.add_child(b)
		_row_btns.append(b)
	_refresh_selection_styles()

func _refresh_selection_styles() -> void:
	for i in range(_row_btns.size()):
		var is_sel := (i == _selected_idx)
		var bg := Color(0.26, 0.19, 0.12, 0.98) if is_sel else HudWidgets.COL_BG_CARD
		var bd := HudWidgets.COL_ACC if is_sel else HudWidgets.COL_SLOT_BD
		_row_btns[i].add_theme_stylebox_override("normal", HudWidgets.make_button_style(bg, bd, 7, 6, 4))
		_row_btns[i].add_theme_stylebox_override("hover", HudWidgets.make_button_style(HudWidgets.COL_SLOT_HOV, HudWidgets.COL_ACC, 7, 6, 4))

func _run_item(it: Dictionary) -> void:
	close_palette()
	app.audio.play("click")
	var kind := str(it["kind"])
	var id := str(it["id"])
	if kind == "cmd":
		match id:
			"compile": app._open_compile_drawer()
			"lighting": app._cycle_lighting_mode()
			"wire3d": app._start_visual_3d_wire(app.selected_entity)
			"save_prefab": app._save_selection_as_prefab()
			"export_bundle": app._export_map_bundle()
			"outliner": app._open_outliner_drawer()
			"view_studio": app._open_viewport_menu_drawer()
			"room_kit": app._open_room_kit_drawer()
			"scatter": app.set_stage(app.Stage.STYLE); app.active_tool = "scatter_props"; app._open_scatter_drawer()
			"spline_path": app.set_stage(app.Stage.BUILD); app.active_tool = "spline_path"; app._open_spline_drawer(); app._refresh_context_bar()
			"drop_floor": app._drop_selection_to_floor()
			"auto_biome": app._auto_texture_selected_solids()
			"focus": app._focus_camera_on_selection()
			"zen": app._toggle_zen_mode()
			"hub": app._show_welcome_hub(true)
			"mvm_studio": app.set_stage(app.Stage.GAMEPLAY); app._open_mvm_studio()
			"payload_studio": app.set_stage(app.Stage.GAMEPLAY); app._open_payload_studio()
			"materials": app.set_stage(app.Stage.STYLE); app._open_materials_drawer()
			"clip3d": app.set_stage(app.Stage.BUILD); app._select_tool("clip_3d")
			"hollow": app._do_hollow_selected()
			"mirror": app._do_mirror_team_selected()
			"seal": app._do_auto_seal()
			"check": app._open_check_problems_drawer()
			"split2d": app._toggle_split_2d()
			"settings": app.settings_modal.open_modal()
			"playtest": app.set_stage(app.Stage.PLAYTEST)
	elif kind == "vmf":
		app._load_vmf_file(id)
	elif kind == "bsp":
		app._load_official_bsp(id)
		app.set_stage(app.Stage.PLAYTEST)
	elif kind == "prop":
		app.set_stage(app.Stage.STYLE)
		app.active_prop_mdl = id
		app.active_tool = "place_prop"
		app._track_recent_prop(id)
		app._rebuild_bottom_dock(); app._refresh_context_bar()
		app._toast("Equipped prop: " + id.get_file().get_basename())
	elif kind == "entity":
		app.set_stage(app.Stage.GAMEPLAY)
		app.active_fgd_entity = id
		app.active_tool = "place_fgd_entity"
		app._rebuild_bottom_dock(); app._refresh_context_bar()
		app._toast("Equipped TF2 entity: " + id)
