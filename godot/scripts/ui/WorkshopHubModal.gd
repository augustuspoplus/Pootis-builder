class_name WorkshopHubModal
extends ColorRect

## Milestone 26 — Redesigned Mann Co. Workshop Hub 2.0!
## Properly organized into 3 clear tabs:
##   1. Create New Map (Gamemode + Biome + Map Name Wizard)
##   2. My Saved Maps (Live godot/maps/*.vmf Browser + Duplicate + Open .VMF)
##   3. Official Valve TF2 Maps (Filter by Gamemode + Search + Instant F5 Playtest)

const HudWidgets         = preload("res://scripts/ui/Tf2HudWidgets.gd")
const Tf2GamemodesScript = preload("res://scripts/core/Tf2Gamemodes.gd")

var app: Node3D
var fonts: Dictionary = {}
var active_tab: int = 0
var selected_mode: String = "koth"
var selected_biome: String = "badlands"
var custom_map_name: String = ""
var official_filter_prefix: String = "ALL"
var official_search_text: String = ""

var tab_btns: Array[Button] = []
var body_host: VBoxContainer
var card_frame: PanelContainer

const MODE_DESCRIPTIONS := {
	"koth":     "1 central point — hold for 3:00 to win",
	"ctf":      "Steal enemy Intel briefcase 3 times",
	"pl":       "BLU pushes bomb cart; RED defends",
	"plr":      "Both teams race Payload carts at once",
	"cp_5cp":   "Symmetrical 5-point tug-of-war",
	"cp_ad":    "BLU attacks points A/B; RED defends",
	"mvm":      "6 RED defenders vs. Robot waves & Tanks",
	"medieval": "Melee & bow-only castle capture",
	"arena":    "No respawns — eliminate enemy team",
	"sd":       "Carry Australium onto rising rocket lift",
	"pass":     "TF2 rugby — score JACK in enemy goal",
	"mge_jump": "1v1 duel / rocket-jump training course",
}

const MODE_ICONS := {
	"koth": "cap_point", "pl": "bomb_cart", "plr": "bomb_cart", "ctf": "intel",
	"cp_5cp": "spawn_red", "cp_ad": "cap_point", "mvm": "upgrade_station", "arena": "spawn_blu",
	"medieval": "barrel", "sd": "intel", "pass": "sentry", "mge_jump": "dispenser",
}

func setup(p_app: Node3D) -> void:
	app = p_app
	fonts = app.fonts
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color(0.05, 0.04, 0.03, 0.78)
	_build_shell()

func open_hub(tab_idx: int = -1) -> void:
	if tab_idx >= 0:
		active_tab = tab_idx
	if card_frame != null and get_window() != null:
		var sf := maxf(get_window().content_scale_factor, 0.5)
		var eff_w := float(get_window().size.x) / sf
		var eff_h := float(get_window().size.y) / sf
		card_frame.custom_minimum_size = Vector2(minf(1060.0, maxf(680.0, eff_w - 36.0)), minf(640.0, maxf(420.0, eff_h - 36.0)))
	visible = true
	_rebuild_body()
	if is_inside_tree():
		modulate = Color(1, 1, 1, 0)
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(self, "modulate", Color.WHITE, 0.16)

func _build_shell() -> void:
	for ch in get_children():
		ch.queue_free()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	card_frame = HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 14.0, true)
	card_frame.custom_minimum_size = Vector2(1060, 640)
	center.add_child(card_frame)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	card_frame.add_child(vb)

	# Header Row
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	vb.add_child(hdr)

	var tvb := VBoxContainer.new()
	tvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hdr.add_child(tvb)

	var title := Label.new()
	title.text = "MANN CO. WORKSHOP HUB"
	title.add_theme_font_override("font", fonts["heading"])
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	tvb.add_child(title)

	var sub := Label.new()
	sub.text = "POOTIS BUILDER 2.0  |  %d Valve FGD Entities  |  16,697 VPK Models  |  %d Official TF2 Maps" % [
		app.core.get_fgd_class_count(), app.core.list_maps().size()
	]
	sub.add_theme_font_override("font", fonts["body"])
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	tvb.add_child(sub)

	var set_b := Button.new(); set_b.text = "Settings"
	HudWidgets.style_tf2_button(set_b, fonts["body"], 12)
	set_b.pressed.connect(func(): app.audio.play("click"); app.settings_modal.open_modal())
	hdr.add_child(set_b)

	var res_b := Button.new(); res_b.text = "Continue Editing"
	HudWidgets.style_tf2_button(res_b, fonts["heading"], 13, true)
	res_b.pressed.connect(func(): app.audio.play("click"); app._show_welcome_hub(false))
	hdr.add_child(res_b)

	# 3-Tab Navigation Bar
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	vb.add_child(tab_row)
	tab_btns.clear()
	var tnames := [
		"1. Create New TF2 Map",
		"2. My Saved Maps (.VMF)",
		"3. Official Valve TF2 Maps (%d)" % app.core.list_maps().size(),
	]
	for i in range(tnames.size()):
		var tb := Button.new()
		tb.text = tnames[i]
		tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tb.custom_minimum_size = Vector2(0, 38)
		HudWidgets.style_tf2_button(tb, fonts["heading"], 12, i == active_tab)
		var ti := i
		tb.pressed.connect(func():
			app.audio.play("click")
			active_tab = ti
			_rebuild_body()
		)
		tab_row.add_child(tb)
		tab_btns.append(tb)

	# Main Tab Body
	body_host = VBoxContainer.new()
	body_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_host.add_theme_constant_override("separation", 8)
	vb.add_child(body_host)

	# Footer Status Bar
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	vb.add_child(foot)

	var tip := Label.new()
	tip.text = "Shortcuts: F5 Walk/Playtest  •  F9 Valve Compile  •  Ctrl+= / Ctrl+- UI Scale  •  Alt+Click Eyedropper"
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip.add_theme_font_override("font", fonts["body"])
	tip.add_theme_font_size_override("font_size", 11)
	tip.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	foot.add_child(tip)

	var vac := Label.new()
	vac.text = "VAC-SAFE (-insecure +sv_lan 1)  •  VPKs Mounted"
	vac.add_theme_font_override("font", fonts["heading"])
	vac.add_theme_font_size_override("font_size", 11)
	vac.add_theme_color_override("font_color", HudWidgets.COL_GREEN)
	foot.add_child(vac)

	_rebuild_body()

func _rebuild_body() -> void:
	for i in range(tab_btns.size()):
		HudWidgets.style_tf2_button(tab_btns[i], fonts["heading"], 12, i == active_tab)
	for ch in body_host.get_children():
		ch.queue_free()

	if active_tab == 0:
		_build_create_tab()
	elif active_tab == 1:
		_build_saved_maps_tab()
	else:
		_build_official_maps_tab()

func _build_create_tab() -> void:
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 14)
	body_host.add_child(split)

	# Left: 12 Gamemode Cards
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.55
	left.add_theme_constant_override("separation", 6)
	split.add_child(left)

	var lh := Label.new()
	lh.text = "STEP 1: PICK A TF2 GAMEMODE (AUTO-CONFIGURES ENTITIES & GAMEPLAY DOCK)"
	lh.add_theme_font_override("font", fonts["heading"]); lh.add_theme_font_size_override("font_size", 12)
	lh.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	left.add_child(lh)

	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; left.add_child(sc)
	var grid := GridContainer.new(); grid.columns = 2; grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8)
	sc.add_child(grid)

	for gm in Tf2GamemodesScript.GAMEMODES:
		var mid: String = str(gm["id"])
		var is_sel := (selected_mode == mid)
		var gb := Button.new()
		gb.custom_minimum_size = Vector2(0, 68); gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gb.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.24, 0.18, 0.12, 0.98) if is_sel else HudWidgets.COL_BG_CARD
		sb.border_color = HudWidgets.COL_ACC if is_sel else HudWidgets.COL_SLOT_BD
		sb.set_border_width_all(2 if is_sel else 1); sb.set_corner_radius_all(9)
		var sbh := sb.duplicate(); sbh.bg_color = HudWidgets.COL_SLOT_HOV; sbh.border_color = HudWidgets.COL_ACC
		gb.add_theme_stylebox_override("normal", sb); gb.add_theme_stylebox_override("hover", sbh); gb.add_theme_stylebox_override("pressed", sbh)

		var hb := HBoxContainer.new()
		hb.set_anchors_preset(Control.PRESET_FULL_RECT)
		hb.offset_left = 8; hb.offset_right = -8; hb.offset_top = 6; hb.offset_bottom = -6
		hb.add_theme_constant_override("separation", 10)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gb.add_child(hb)

		var ic_box := PanelContainer.new(); ic_box.custom_minimum_size = Vector2(52, 52); ic_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var isb := StyleBoxFlat.new()
		isb.bg_color = Color(0.10, 0.09, 0.08, 0.96); isb.border_color = HudWidgets.COL_ACC if is_sel else HudWidgets.COL_SLOT_BD
		isb.set_border_width_all(1); isb.set_corner_radius_all(7)
		ic_box.add_theme_stylebox_override("panel", isb); hb.add_child(ic_box)

		var itr := TextureRect.new()
		itr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		itr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		itr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ikey: String = str(MODE_ICONS.get(mid, "crate"))
		if app.icon_cache != null:
			var itex: Texture2D = app.icon_cache.get_icon(ikey)
			if itex != null:
				itr.texture = itex
			else:
				var w_itr: WeakRef = weakref(itr)
				app.icon_cache.icon_ready.connect(func(k: String, tx: Texture2D):
					if k == ikey:
						var o = w_itr.get_ref()
						if o != null: o.texture = tx
				)
		ic_box.add_child(itr)

		var gtvb := VBoxContainer.new()
		gtvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gtvb.alignment = BoxContainer.ALIGNMENT_CENTER
		gtvb.add_theme_constant_override("separation", 2)
		gtvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(gtvb)
		var g1 := Label.new(); g1.text = "%s (%s)" % [str(gm["name"]), str(gm["short"])]
		g1.add_theme_font_override("font", fonts["heading"]); g1.add_theme_font_size_override("font_size", 11)
		g1.add_theme_color_override("font_color", HudWidgets.COL_ACC if is_sel else HudWidgets.COL_TX)
		g1.mouse_filter = Control.MOUSE_FILTER_IGNORE; gtvb.add_child(g1)
		var g2 := Label.new(); g2.text = str(MODE_DESCRIPTIONS.get(mid, "TF2 starter arena"))
		g2.clip_text = true
		g2.add_theme_font_override("font", fonts["body"]); g2.add_theme_font_size_override("font_size", 10)
		g2.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
		g2.mouse_filter = Control.MOUSE_FILTER_IGNORE; gtvb.add_child(g2)

		var default_biome: String = str(gm.get("biome", "badlands"))
		gb.pressed.connect(func():
			app.audio.play("click")
			selected_mode = mid
			selected_biome = default_biome
			_rebuild_body()
		)
		grid.add_child(gb)

	# Right: Step 2 Customize Biome + Create Button
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 0.95
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.11, 0.10, 0.09, 0.96); rsb.border_color = HudWidgets.COL_SLOT_BD
	rsb.set_border_width_all(1); rsb.set_corner_radius_all(10); rsb.set_content_margin_all(14)
	right.add_theme_stylebox_override("panel", rsb)
	split.add_child(right)

	var rsc := ScrollContainer.new()
	rsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(rsc)
	var rvb := VBoxContainer.new()
	rvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rvb.add_theme_constant_override("separation", 8)
	rsc.add_child(rvb)
	var rh := Label.new(); rh.text = "STEP 2: CHOOSE THEME & LAUNCH"
	rh.add_theme_font_override("font", fonts["heading"]); rh.add_theme_font_size_override("font_size", 13)
	rh.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	rvb.add_child(rh)

	var nl := Label.new(); nl.text = "Custom Map Name (optional):"
	nl.add_theme_font_override("font", fonts["body"]); nl.add_theme_font_size_override("font_size", 11)
	rvb.add_child(nl)
	var name_le := LineEdit.new()
	name_le.placeholder_text = "e.g. %s_my_arena" % selected_mode.replace("cp_", "cp")
	name_le.text = custom_map_name
	name_le.text_changed.connect(func(t: String): custom_map_name = t)
	rvb.add_child(name_le)

	var bl := Label.new(); bl.text = "Visual Theme / Biome:"
	bl.add_theme_font_override("font", fonts["body"]); bl.add_theme_font_size_override("font_size", 11)
	rvb.add_child(bl)
	var bgrid := GridContainer.new(); bgrid.columns = 2
	bgrid.add_theme_constant_override("h_separation", 6); bgrid.add_theme_constant_override("v_separation", 6)
	rvb.add_child(bgrid)
	for bk in Tf2GamemodesScript.BIOMES.keys():
		var bkey := str(bk)
		var binfo: Dictionary = Tf2GamemodesScript.BIOMES[bkey]
		var bb := Button.new()
		bb.text = str(binfo["name"])
		bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(bb, fonts["body"], 11, selected_biome == bkey)
		bb.pressed.connect(func(): app.audio.play("click"); selected_biome = bkey; _rebuild_body())
		bgrid.add_child(bb)

	var sp := Control.new(); sp.size_flags_vertical = Control.SIZE_EXPAND_FILL; rvb.add_child(sp)

	var create_b := Button.new()
	create_b.text = "CREATE %s MAP & START BUILDING" % selected_mode.to_upper()
	create_b.custom_minimum_size = Vector2(0, 48)
	HudWidgets.style_tf2_button(create_b, fonts["heading"], 13, true)
	create_b.pressed.connect(func():
		app.audio.play("save")
		app._load_gamemode(selected_mode, selected_biome, true)
		if not custom_map_name.strip_edges().is_empty():
			app.map_title_lbl.text = "| " + custom_map_name.strip_edges()
		app._show_welcome_hub(false)
	)
	rvb.add_child(create_b)

	var quick_row := HBoxContainer.new(); quick_row.add_theme_constant_override("separation", 6); rvb.add_child(quick_row)
	var open_vmf := Button.new(); open_vmf.text = "Open .VMF File..."; open_vmf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudWidgets.style_tf2_button(open_vmf, fonts["body"], 11)
	open_vmf.pressed.connect(func(): app.audio.play("click"); app._open_file_dialog("vmf"))
	quick_row.add_child(open_vmf)
	var imp_b := Button.new(); imp_b.text = "Import 3D Model..."; imp_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudWidgets.style_tf2_button(imp_b, fonts["body"], 11)
	imp_b.pressed.connect(func(): app.audio.play("click"); app._show_welcome_hub(false); app._open_file_dialog("model"))
	quick_row.add_child(imp_b)

func _build_saved_maps_tab() -> void:
	var hdr := HBoxContainer.new(); hdr.add_theme_constant_override("separation", 8); body_host.add_child(hdr)
	var l := Label.new()
	l.text = "YOUR SAVED POOTIS BUILDER MAPS (godot/maps/*.vmf)"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_override("font", fonts["heading"]); l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	hdr.add_child(l)
	var browse_b := Button.new(); browse_b.text = "Browse Any .VMF..."
	HudWidgets.style_tf2_button(browse_b, fonts["body"], 11, true)
	browse_b.pressed.connect(func(): app.audio.play("click"); app._open_file_dialog("vmf"))
	hdr.add_child(browse_b)

	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; body_host.add_child(sc)
	var list := VBoxContainer.new(); list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; list.add_theme_constant_override("separation", 6)
	sc.add_child(list)

	var maps_dir: String = app.repo_root.path_join("godot/maps")
	var files: Array[String] = []
	var da := DirAccess.open(maps_dir)
	if da != null:
		da.list_dir_begin()
		var fn := da.get_next()
		while not fn.is_empty():
			if not da.current_is_dir() and fn.to_lower().ends_with(".vmf") and fn.find("autosave") == -1:
				files.append(fn)
			fn = da.get_next()
		da.list_dir_end()
	files.sort()

	if files.is_empty():
		var el := Label.new(); el.text = "No saved .vmf maps yet! Create one in Tab 1 and click Save (Ctrl+S)."
		el.add_theme_font_override("font", fonts["body"]); el.add_theme_font_size_override("font_size", 13)
		el.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
		list.add_child(el)
		return

	for fn in files:
		var full_p := maps_dir.path_join(fn)
		var kb := int(FileAccess.get_file_as_bytes(full_p).size() / 1024)
		var prefix := fn.get_slice("_", 0).to_upper()
		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = HudWidgets.COL_BG_CARD; sb.border_color = HudWidgets.COL_SLOT_BD
		sb.set_border_width_all(1); sb.set_corner_radius_all(8)
		sb.content_margin_left = 12; sb.content_margin_right = 12; sb.content_margin_top = 8; sb.content_margin_bottom = 8
		row.add_theme_stylebox_override("panel", sb)
		list.add_child(row)

		var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 10); row.add_child(hb)
		var tag := Label.new(); tag.text = "[%s]" % prefix
		tag.custom_minimum_size = Vector2(64, 0)
		tag.add_theme_font_override("font", fonts["heading"]); tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", HudWidgets.COL_CYAN if prefix in ["PL", "CTF", "MVM"] else HudWidgets.COL_ACC)
		hb.add_child(tag)

		var nl := Label.new(); nl.text = "%s  (%d KB)" % [fn, kb]
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nl.add_theme_font_override("font", fonts["body"]); nl.add_theme_font_size_override("font_size", 13)
		hb.add_child(nl)

		var open_b := Button.new(); open_b.text = "Open in Editor"
		HudWidgets.style_tf2_button(open_b, fonts["heading"], 11, true)
		var p_copy := full_p
		open_b.pressed.connect(func():
			app.audio.play("click")
			app._load_vmf_file(p_copy)
		)
		hb.add_child(open_b)

func _build_official_maps_tab() -> void:
	var frow := HBoxContainer.new(); frow.add_theme_constant_override("separation", 6); body_host.add_child(frow)
	for pf in ["ALL", "PL", "CTF", "KOTH", "CP", "MVM", "SD", "ARENA"]:
		var pf_c: String = str(pf)
		var b := Button.new(); b.text = pf_c
		HudWidgets.style_tf2_button(b, fonts["heading"], 10, official_filter_prefix == pf_c)
		b.pressed.connect(func(): app.audio.play("click"); official_filter_prefix = pf_c; _rebuild_body())
		frow.add_child(b)

	var search := LineEdit.new()
	search.placeholder_text = "Search all installed Valve TF2 maps (upward, turbine, viaduct, degroot, decoy...)"
	search.text = official_search_text
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frow.add_child(search)

	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; body_host.add_child(sc)
	var list := GridContainer.new(); list.columns = 2; list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("h_separation", 8); list.add_theme_constant_override("v_separation", 6)
	sc.add_child(list)

	var all_maps: PackedStringArray = app.core.list_maps()
	var populate := func(flt: String) -> void:
		official_search_text = flt
		for ch in list.get_children():
			ch.queue_free()
		var fl := flt.to_lower().strip_edges()
		var featured := ["pl_upward.bsp", "ctf_turbine.bsp", "ctf_2fort.bsp", "koth_viaduct.bsp", "cp_degrootkeep.bsp", "cp_degrootkeep_rats.bsp", "mvm_decoy.bsp", "cp_process_final.bsp", "sd_doomsday.bsp", "pl_badwater.bsp"]
		var ordered: Array[String] = []
		if fl.is_empty() and official_filter_prefix == "ALL":
			for fm in featured:
				if all_maps.has(fm): ordered.append(fm)
		for m in all_maps:
			var mp := str(m)
			var pre := mp.get_slice("_", 0).to_upper()
			if official_filter_prefix != "ALL" and pre != official_filter_prefix:
				continue
			if not fl.is_empty() and mp.to_lower().find(fl) == -1:
				continue
			if not ordered.has(mp):
				ordered.append(mp)
		var shown := 0
		for m in ordered:
			if shown >= 60: break
			var mcopy := m
			var pre := m.get_slice("_", 0).to_upper()
			var card := PanelContainer.new()
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var sb := StyleBoxFlat.new()
			sb.bg_color = HudWidgets.COL_BG_CARD; sb.border_color = HudWidgets.COL_SLOT_BD
			sb.set_border_width_all(1); sb.set_corner_radius_all(8)
			sb.content_margin_left = 10; sb.content_margin_right = 8; sb.content_margin_top = 6; sb.content_margin_bottom = 6
			card.add_theme_stylebox_override("panel", sb)
			list.add_child(card)

			var hb := HBoxContainer.new(); hb.add_theme_constant_override("separation", 8); card.add_child(hb)
			var tg := Label.new(); tg.text = pre; tg.custom_minimum_size = Vector2(46, 0)
			tg.add_theme_font_override("font", fonts["heading"]); tg.add_theme_font_size_override("font_size", 10)
			tg.add_theme_color_override("font_color", HudWidgets.COL_CYAN if pre in ["PL", "CTF", "MVM"] else HudWidgets.COL_ACC)
			hb.add_child(tg)

			var nl := Label.new(); nl.text = m.get_basename(); nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; nl.clip_text = true
			nl.add_theme_font_override("font", fonts["body"]); nl.add_theme_font_size_override("font_size", 12)
			hb.add_child(nl)

			var walk_b := Button.new(); walk_b.text = "Walk (F5)"
			HudWidgets.style_tf2_button(walk_b, fonts["heading"], 10, true)
			walk_b.pressed.connect(func():
				app.audio.play("click")
				app._load_official_bsp(mcopy)
				app._show_welcome_hub(false)
				app.set_stage(app.Stage.PLAYTEST)
			)
			hb.add_child(walk_b)

			var remix_b := Button.new(); remix_b.text = "Remix"
			remix_b.tooltip_text = "Decompile official Valve .bsp into editable .vmf and open in Editor!"
			HudWidgets.style_tf2_button(remix_b, fonts["body"], 10, false, 3)
			remix_b.pressed.connect(func():
				app.audio.play("click")
				app._show_welcome_hub(false)
				app._remix_official_bsp(mcopy)
			)
			hb.add_child(remix_b)

			var view_b := Button.new(); view_b.text = "Inspect"
			HudWidgets.style_tf2_button(view_b, fonts["body"], 10)
			view_b.pressed.connect(func():
				app.audio.play("click")
				app._load_official_bsp(mcopy)
				app._show_welcome_hub(false)
			)
			hb.add_child(view_b)
			shown += 1

	populate.call(official_search_text)
	search.text_changed.connect(populate)
