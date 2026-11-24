class_name TutorialManager
extends Node

## Milestone 38 — Interactive Guided Tutorials & Live "What Next?" Mission System!
## Gives new & returning TF2 mappers a live, auto-checking floating Mission Tracker
## with 4 hands-on quests, 1-click "Show Me" navigation, and persistent completion!

const HudWidgets = preload("res://scripts/ui/Tf2HudWidgets.gd")
const SAVE_PATH := "user://pootis_tutorials.cfg"

var app: Node3D
var tracker_panel: PanelContainer
var tracker_vbox: VBoxContainer

var active_quest_id: String = ""
var active_step_idx: int = 0
var completed_quests: Dictionary = {} # quest_id -> true
var _step_baseline: Dictionary = {}   # snapshot counts when step started
var _poll_accum: float = 0.0

const QUESTS := [
	{
		"id": "q1_first_arena",
		"title": "1. Build Your First Arena",
		"time": "3 min",
		"desc": "Learn 3D camera movement, rooms, catwalks, and the live TF2 Radar.",
		"steps": [
			{
				"title": "Open Scene Outliner (O) or Select a Brush",
				"tip": "Click any wall/floor in 3D, or press O to inspect every solid & spawn in your map.",
				"show_action": "outliner",
				"check": "sel_or_outliner",
			},
			{
				"title": "Stamp a Smart TF2 Room or Draw a Box",
				"tip": "Open the Room Generator (green icon on left rail) or use Draw Box to add geometry!",
				"show_action": "room_kit",
				"check": "added_solid",
			},
			{
				"title": "Place a Fence or Catwalk with Spline Path",
				"tip": "Select 'Spline Path' on the bottom dock, then click Point A -> Point B in 3D!",
				"show_action": "spline_path",
				"check": "used_spline",
			},
			{
				"title": "Open the Interactive 2D Mini-Map Radar (M)",
				"tip": "Press M to toggle the corner TF2 Radar — click anywhere on it to teleport your camera!",
				"show_action": "minimap",
				"check": "minimap_on",
			},
		],
	},
	{
		"id": "q2_style_lighting",
		"title": "2. Textures, Lighting & Props",
		"time": "3 min",
		"desc": "Paint real TF2 VPK materials, preview SpotLight3D interiors, and scatter cover props.",
		"steps": [
			{
				"title": "Switch to 3. STYLE & Open Face Edit (Shift+A)",
				"tip": "Click '3. STYLE' at top-center, or press Shift+A to browse 29,000+ TF2 textures.",
				"show_action": "materials",
				"check": "in_style",
			},
			{
				"title": "Preview Real TF2 Lighting (Press F3)",
				"tip": "Press F3 to cycle Daylight -> Lit Interior Preview (shows real TF2 SpotLight3D beams!).",
				"show_action": "lit_preview",
				"check": "lit_mode",
			},
			{
				"title": "Scatter TF2 Props with Prop Scatter Brush",
				"tip": "Click 'Prop Scatter' in Style mode, pick a TF2 kit, and click the ground to paint cover!",
				"show_action": "scatter",
				"check": "added_entity",
			},
		],
	},
	{
		"id": "q3_gameplay_playtest",
		"title": "3. Gamemode Logic & F5 Playtest",
		"time": "2 min",
		"desc": "Verify spawns/objectives, inspect Sniper sightlines, and walk inside your map!",
		"steps": [
			{
				"title": "Open the Gamemode Logic Studio",
				"tip": "Switch to 2. GAMEPLAY and click the amber Studio button to verify spawns & objectives.",
				"show_action": "gamemode_studio",
				"check": "in_gameplay",
			},
			{
				"title": "Inspect Sniper Sightlines (Alt+S)",
				"tip": "Press Alt+S to cast 36 color-coded 3D rays (Green <1024u, Amber <2048u, Red >2048u OP!).",
				"show_action": "sightlines",
				"check": "sightline_on",
			},
			{
				"title": "Walk Inside Your Map (Press F5!)",
				"tip": "Press F5 to spawn as Soldier/Scout with rocket jumping, sliding doors & live cap/intel!",
				"show_action": "playtest",
				"check": "entered_playtest",
			},
		],
	},
	{
		"id": "q4_seal_compile",
		"title": "4. Seal & Compile for Real TF2",
		"time": "2 min",
		"desc": "Run Map Balance diagnostics, auto-seal leaks, and compile a real Valve .BSP.",
		"steps": [
			{
				"title": "Run Alt+P Check Map for Problems",
				"tip": "Press Alt+P (or click Check in the top bar) to inspect leaks, spawns & balance.",
				"show_action": "check_problems",
				"check": "opened_check",
			},
			{
				"title": "Ensure Map is Cleanly Sealed (0 Leaks)",
				"tip": "Click Auto-Seal Skybox so Valve's vbsp.exe compiles with zero void leaks!",
				"show_action": "auto_seal",
				"check": "map_sealed",
			},
			{
				"title": "Open Valve Compile Studio (F9)",
				"tip": "Press F9 to compile with real Valve vbsp/vvis/vrad or export a shareable bundle!",
				"show_action": "compile",
				"check": "opened_compile",
			},
		],
	},
]

func setup(p_app: Node3D) -> void:
	app = p_app
	_load_progress()
	_build_tracker_ui()

func _load_progress() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		for q in QUESTS:
			var qid: String = str(q["id"])
			if bool(cf.get_value("quests", qid, false)):
				completed_quests[qid] = true

func _save_progress() -> void:
	var cf := ConfigFile.new()
	for qid in completed_quests.keys():
		cf.set_value("quests", str(qid), true)
	cf.save(SAVE_PATH)

func _build_tracker_ui() -> void:
	tracker_panel = HudWidgets.HudFrame.new(HudWidgets.COL_GREEN, 9.0, true)
	tracker_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tracker_panel.offset_left = 74
	tracker_panel.offset_top = 66
	tracker_panel.offset_right = 342
	tracker_panel.offset_bottom = 224
	tracker_panel.visible = false
	app.hud_layer.add_child(tracker_panel)

	tracker_vbox = VBoxContainer.new()
	tracker_vbox.add_theme_constant_override("separation", 5)
	tracker_panel.add_child(tracker_vbox)

func get_quest(qid: String) -> Dictionary:
	for q in QUESTS:
		if str(q["id"]) == qid:
			return q
	return {}

func start_quest(qid: String) -> void:
	var q := get_quest(qid)
	if q.is_empty():
		return
	active_quest_id = qid
	active_step_idx = 0
	_snapshot_baseline()
	_refresh_tracker()
	app._toast("Tutorial Started: %s" % str(q["title"]))

func stop_quest() -> void:
	active_quest_id = ""
	if tracker_panel != null:
		tracker_panel.visible = false

func _snapshot_baseline() -> void:
	_step_baseline = {
		"solids": app.doc.get_solid_count() if app.doc != null else 0,
		"ents": app.doc.get_entities().size() if app.doc != null else 0,
	}

func _process(delta: float) -> void:
	if app == null or active_quest_id.is_empty():
		return
	var should_show: bool = (not app.viewing_bsp and app.stage != app.Stage.PLAYTEST and not app.zen_mode and not app.welcome_panel.visible)
	if tracker_panel != null:
		tracker_panel.visible = should_show
	_poll_accum += delta
	if _poll_accum < 0.25:
		return
	_poll_accum = 0.0
	_check_active_step()

func _check_active_step() -> void:
	var q := get_quest(active_quest_id)
	if q.is_empty():
		return
	var steps: Array = q["steps"]
	if active_step_idx >= steps.size():
		return
	var st: Dictionary = steps[active_step_idx]
	var ck: String = str(st["check"])
	var done := false
	match ck:
		"sel_or_outliner":
			done = (app.selected_solid >= 0 or app.selected_entity >= 0 or (app.right_drawer.visible and app.right_drawer_title.text.find("OUTLINER") != -1))
		"added_solid":
			done = app.doc.get_solid_count() > int(_step_baseline.get("solids", 0))
		"used_spline":
			done = (app.active_tool == "spline_path" and app.spline_seg_count > 0) or (app.doc.get_solid_count() >= int(_step_baseline.get("solids", 0)) + 2)
		"minimap_on":
			done = bool(app.minimap_enabled)
		"in_style":
			done = (app.stage == app.Stage.STYLE and app.right_drawer.visible)
		"lit_mode":
			done = (app.lighting_mode == 1)
		"added_entity":
			done = app.doc.get_entities().size() > int(_step_baseline.get("ents", 0))
		"in_gameplay":
			done = (app.stage == app.Stage.GAMEPLAY and app.right_drawer.visible and app.right_drawer_title.text.find("STUDIO") != -1)
		"sightline_on":
			done = bool(app.sightline_active)
		"entered_playtest":
			done = (app.stage == app.Stage.PLAYTEST)
		"opened_check":
			done = (app.right_drawer.visible and app.right_drawer_title.text.find("PROBLEM") != -1) or (app.diag_popover != null and app.diag_popover.visible)
		"map_sealed":
			done = bool(app.doc.is_map_sealed())
		"opened_compile":
			done = (app.right_drawer.visible and app.right_drawer_title.text.find("COMPILE") != -1)

	if done:
		advance_step()

func advance_step() -> void:
	var q := get_quest(active_quest_id)
	if q.is_empty():
		return
	var steps: Array = q["steps"]
	active_step_idx += 1
	app.audio.play("save")
	if active_step_idx >= steps.size():
		completed_quests[active_quest_id] = true
		_save_progress()
		app._toast("Quest Complete: %s! Pick your next quest or ask AI Architect!" % str(q["title"]))
		active_quest_id = ""
		if tracker_panel != null:
			tracker_panel.visible = false
		return
	_snapshot_baseline()
	_refresh_tracker()
	app._toast("Step Done! Next: %s" % str(steps[active_step_idx]["title"]))

func run_show_action(act: String) -> void:
	app.audio.play("click")
	match act:
		"outliner": app._open_outliner_drawer()
		"room_kit": app.set_stage(app.Stage.BUILD); app._open_room_kit_drawer()
		"spline_path": app.set_stage(app.Stage.BUILD); app._select_tool("spline_path")
		"minimap":
			if not app.minimap_enabled: app._toggle_minimap()
		"materials": app.set_stage(app.Stage.STYLE); app._open_materials_drawer()
		"lit_preview": app._set_lighting_mode(1)
		"scatter": app.set_stage(app.Stage.STYLE); app._select_tool("scatter_props")
		"gamemode_studio": app.set_stage(app.Stage.GAMEPLAY); app._open_gamemode_wizard()
		"sightlines":
			if not app.sightline_active: app._toggle_sightline_analyzer()
		"playtest": app.set_stage(app.Stage.PLAYTEST)
		"check_problems": app._open_check_problems_drawer()
		"auto_seal": app._do_auto_seal()
		"compile": app._open_compile_drawer()

func _refresh_tracker() -> void:
	if tracker_vbox == null or active_quest_id.is_empty():
		return
	for ch in tracker_vbox.get_children():
		ch.queue_free()
	var q := get_quest(active_quest_id)
	if q.is_empty():
		tracker_panel.visible = false
		return
	var steps: Array = q["steps"]
	if active_step_idx >= steps.size():
		tracker_panel.visible = false
		return
	var st: Dictionary = steps[active_step_idx]
	var fonts: Dictionary = app.fonts

	var hdr := HBoxContainer.new(); tracker_vbox.add_child(hdr)
	var tl := Label.new()
	tl.text = "STEP %d/%d — %s" % [active_step_idx + 1, steps.size(), str(q["title"]).get_slice(". ", 1)]
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL; tl.clip_text = true
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.add_theme_font_override("font", fonts["heading"]); tl.add_theme_font_size_override("font_size", 11)
	tl.add_theme_color_override("font_color", HudWidgets.COL_GREEN)
	hdr.add_child(tl)
	var xb := Button.new(); xb.text = "X"; HudWidgets.style_tf2_button(xb, fonts["heading"], 9)
	xb.pressed.connect(stop_quest); hdr.add_child(xb)

	var st_lbl := Label.new(); st_lbl.text = str(st["title"]); st_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st_lbl.add_theme_font_override("font", fonts["heading"]); st_lbl.add_theme_font_size_override("font_size", 12)
	st_lbl.add_theme_color_override("font_color", HudWidgets.COL_TX)
	tracker_vbox.add_child(st_lbl)

	var tip_lbl := Label.new(); tip_lbl.text = str(st["tip"]); tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_lbl.add_theme_font_override("font", fonts["body"]); tip_lbl.add_theme_font_size_override("font_size", 10)
	tip_lbl.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	tracker_vbox.add_child(tip_lbl)

	var brow := HBoxContainer.new(); brow.add_theme_constant_override("separation", 5); tracker_vbox.add_child(brow)
	var show_b := Button.new(); show_b.text = "Show Me / Open Tool"; show_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudWidgets.style_tf2_button(show_b, fonts["heading"], 10, true)
	var act: String = str(st["show_action"])
	show_b.pressed.connect(func(): run_show_action(act))
	brow.add_child(show_b)

	var skip_b := Button.new(); skip_b.text = "Next >"
	HudWidgets.style_tf2_button(skip_b, fonts["body"], 10)
	skip_b.pressed.connect(advance_step)
	brow.add_child(skip_b)

	tracker_panel.visible = true

static func build_tutorial_hub_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	var tm: TutorialManager = app.tutorial_mgr

	var done_cnt := tm.completed_quests.size() if tm != null else 0
	var c1 := HudWidgets.make_section_card("INTERACTIVE TF2 MAPPER ACADEMY (%d/%d COMPLETE)" % [done_cnt, QUESTS.size()], fonts, HudWidgets.COL_GREEN)
	vbox.add_child(c1["panel"])
	var v1: VBoxContainer = c1["vbox"]

	var intro := Label.new()
	intro.text = "Not sure what to build next? Pick any hands-on quest below — each step auto-completes as you work and has a 1-click 'Show Me' button!"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_override("font", fonts["body"]); intro.add_theme_font_size_override("font_size", 10)
	intro.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	v1.add_child(intro)

	for q in QUESTS:
		var qid: String = str(q["id"])
		var is_done: bool = tm != null and tm.completed_quests.has(qid)
		var is_act: bool = tm != null and tm.active_quest_id == qid
		var badge := "[DONE] " if is_done else ("[ACTIVE] " if is_act else "")
		var b := Button.new()
		b.text = "%s%s  (%s)\n%s" % [badge, str(q["title"]), str(q["time"]), str(q["desc"])]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		HudWidgets.style_tf2_button(b, fonts["body"], 10, is_act, 3 if is_done else 0)
		b.pressed.connect(func():
			app.audio.play("click")
			tm.start_quest(qid)
			app.right_drawer.visible = false
		)
		v1.add_child(b)

	var c2 := HudWidgets.make_section_card("QUICK SHORTCUT CHEAT SHEET", fonts, HudWidgets.COL_ACC)
	vbox.add_child(c2["panel"])
	var v2: VBoxContainer = c2["vbox"]
	for line in [
		"RMB + WASD / E / C : Fly Camera (Shift = Fast)",
		"Ctrl+K : Instant Search Any Tool, Entity, Prop or Map",
		"F5 : Walk Inside Map (Soldier/Scout + Rocket Jump)",
		"F3 : Cycle Daylight / Lit Interior / Fullbright",
		"M : Corner Radar   |   Alt+S : Sniper Sightlines",
		"End : Drop to Floor  |  R : Rotate  |  Ctrl+Z : Undo",
		"F9 : Compile with Valve vbsp/vvis/vrad for Real TF2",
	]:
		var l := Label.new(); l.text = line; l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_override("font", fonts["mono"]); l.add_theme_font_size_override("font_size", 10)
		l.add_theme_color_override("font_color", HudWidgets.COL_TX)
		v2.add_child(l)
