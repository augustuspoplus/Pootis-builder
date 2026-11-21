class_name SettingsModal
extends ColorRect

## Complete 7-Tab Settings & Hammer Configuration Window (Matches Mockup 4!)
## Tabs: 1. Display & UI Scale | 2. Viewport & 3D Views | 3. 2D Views & Grid |
##       4. Controls & Keybinds | 5. TF2, FGDs & Compilers | 6. Playtest & Audio | 7. Auto-Save

signal settings_applied()
signal rebuild_icons_requested()

const HudWidgets = preload("res://scripts/ui/Tf2HudWidgets.gd")

var settings: RefCounted
var fonts: Dictionary = {}
var core: Object
var active_tab: int = 0

var nav_vbox: VBoxContainer
var content_vbox: VBoxContainer
var nav_btns: Array[Button] = []
var _snapshot: Dictionary = {}

const TABS := [
	"1. Display & UI Scale",
	"2. Viewport & 3D Views",
	"3. 2D Views & Grid",
	"4. Controls & Keybinds",
	"5. TF2, FGDs & Compilers",
	"6. Playtest & Audio",
	"7. Auto-Save & Backups",
]

func setup(p_settings: RefCounted, p_fonts: Dictionary, p_core: Object) -> void:
	settings = p_settings
	fonts = p_fonts
	core = p_core
	set_anchors_preset(Control.PRESET_FULL_RECT)
	color = Color(0.05, 0.04, 0.03, 0.74)
	visible = false
	_build_modal()

func open_modal() -> void:
	_snapshot = settings.to_dict()
	visible = true
	_rebuild_tab()

func cancel_modal() -> void:
	if not _snapshot.is_empty():
		settings.from_dict(_snapshot)
		settings_applied.emit()
	visible = false

func _build_modal() -> void:
	for ch in get_children():
		ch.queue_free()

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var card := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 12.0, true)
	card.custom_minimum_size = Vector2(960, 620)
	center.add_child(card)

	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 10)
	card.add_child(root_vb)

	# Header
	var hdr := HBoxContainer.new()
	root_vb.add_child(hdr)
	var title := Label.new()
	title.text = "POOTIS BUILDER 2.0 — SETTINGS & HAMMER CONFIGURATION"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", fonts["heading"])
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	hdr.add_child(title)

	var close_b := Button.new()
	close_b.text = "ESC / Close"
	HudWidgets.style_tf2_button(close_b, fonts["body"], 12)
	close_b.pressed.connect(func(): cancel_modal())
	hdr.add_child(close_b)

	# Body split: Left 7-tab nav | Right content scroll
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	root_vb.add_child(body)

	var nav_col := VBoxContainer.new()
	nav_col.custom_minimum_size = Vector2(225, 0)
	nav_col.add_theme_constant_override("separation", 5)
	body.add_child(nav_col)

	nav_vbox = VBoxContainer.new()
	nav_vbox.add_theme_constant_override("separation", 5)
	nav_col.add_child(nav_vbox)

	nav_btns.clear()
	for i in range(TABS.size()):
		var b := Button.new()
		b.text = TABS[i]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		HudWidgets.style_tf2_button(b, fonts["body"], 12, i == active_tab)
		var ti := i
		b.pressed.connect(func():
			active_tab = ti
			_rebuild_tab()
		)
		nav_vbox.add_child(b)
		nav_btns.append(b)

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav_col.add_child(sp)

	# Permanent VAC-Safe & SDK Status Card
	var vac_card := PanelContainer.new()
	var vsb := StyleBoxFlat.new()
	vsb.bg_color = Color(0.11, 0.22, 0.13, 0.80)
	vsb.border_color = HudWidgets.COL_GREEN
	vsb.set_border_width_all(1)
	vsb.set_corner_radius_all(8)
	vsb.content_margin_left = 10; vsb.content_margin_right = 10
	vsb.content_margin_top = 8; vsb.content_margin_bottom = 8
	vac_card.add_theme_stylebox_override("panel", vsb)
	nav_col.add_child(vac_card)

	var vac_lbl := Label.new()
	var fgd_cnt: int = core.get_fgd_class_count() if core != null else 0
	var tf2_dir: String = core.get_tf2_dir() if core != null else ""
	var has_vbsp := not tf2_dir.is_empty() and (FileAccess.file_exists(tf2_dir.path_join("bin/x64/vbsp.exe")) or FileAccess.file_exists(tf2_dir.path_join("bin/vbsp.exe")))
	vac_lbl.text = "VAC-SAFE MODE LOCKED\nFlags: -insecure +sv_lan 1\nFGD Classes: %d (tf + abs)\nCompilers: %s" % [fgd_cnt, "vbsp/vvis/vrad detected" if has_vbsp else "TF2 SDK not found"]
	vac_lbl.add_theme_font_override("font", fonts["body"])
	vac_lbl.add_theme_font_size_override("font_size", 11)
	vac_lbl.add_theme_color_override("font_color", Color(0.76, 0.96, 0.80))
	vac_card.add_child(vac_lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)

	content_vbox = VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(content_vbox)

	# Footer
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	root_vb.add_child(foot)

	var reset_b := Button.new()
	reset_b.text = "Reset All to Defaults"
	HudWidgets.style_tf2_button(reset_b, fonts["body"], 12)
	reset_b.pressed.connect(func():
		settings.reset_defaults()
		settings.save_to_disk()
		settings_applied.emit()
		_rebuild_tab()
	)
	foot.add_child(reset_b)

	var fsp := Control.new()
	fsp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(fsp)

	var cancel_b := Button.new()
	cancel_b.text = "Cancel"
	HudWidgets.style_tf2_button(cancel_b, fonts["body"], 12)
	cancel_b.pressed.connect(func(): cancel_modal())
	foot.add_child(cancel_b)

	var apply_b := Button.new()
	apply_b.text = "APPLY & SAVE SETTINGS"
	HudWidgets.style_tf2_button(apply_b, fonts["heading"], 13, true)
	apply_b.pressed.connect(func():
		_snapshot = settings.to_dict()
		settings.save_to_disk()
		settings_applied.emit()
		visible = false
	)
	foot.add_child(apply_b)

func _sec(title: String) -> void:
	var l := Label.new()
	l.text = title
	l.add_theme_font_override("font", fonts["heading"])
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	content_vbox.add_child(l)

func _toggle_row(label: String, desc: String, val: bool, fn: Callable) -> void:
	var hb := HBoxContainer.new()
	content_vbox.add_child(hb)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	var l1 := Label.new(); l1.text = label
	l1.add_theme_font_override("font", fonts["body"]); l1.add_theme_font_size_override("font_size", 13)
	vb.add_child(l1)
	var l2 := Label.new(); l2.text = desc
	l2.add_theme_font_size_override("font_size", 11); l2.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	vb.add_child(l2)
	var cb := CheckButton.new()
	cb.button_pressed = val
	cb.toggled.connect(func(v: bool): fn.call(v); settings_applied.emit())
	hb.add_child(cb)

func _slider_row(label: String, desc: String, min_v: float, max_v: float, step_v: float, cur_v: float, suffix: String, fn: Callable, apply_on_drag_end: bool = false) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	content_vbox.add_child(hb)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	var l1 := Label.new(); l1.text = label
	l1.add_theme_font_override("font", fonts["body"]); l1.add_theme_font_size_override("font_size", 13)
	vb.add_child(l1)
	var l2 := Label.new(); l2.text = desc
	l2.add_theme_font_size_override("font_size", 11); l2.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	vb.add_child(l2)
	var sl := HSlider.new()
	sl.custom_minimum_size = Vector2(180, 24)
	sl.min_value = min_v; sl.max_value = max_v; sl.step = step_v; sl.value = cur_v
	hb.add_child(sl)
	var vl := Label.new()
	vl.custom_minimum_size = Vector2(64, 0)
	vl.text = "%.0f%s" % [cur_v, suffix] if step_v >= 1.0 else "%.2f%s" % [cur_v, suffix]
	vl.add_theme_font_override("font", fonts["mono"])
	vl.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	hb.add_child(vl)
	sl.value_changed.connect(func(v: float):
		vl.text = "%.0f%s" % [v, suffix] if step_v >= 1.0 else "%.2f%s" % [v, suffix]
		fn.call(v)
		if not apply_on_drag_end:
			settings_applied.emit()
	)
	if apply_on_drag_end:
		sl.drag_ended.connect(func(_changed: bool): settings_applied.emit())

func _rebuild_tab() -> void:
	# Consistent Title Case typography across ALL 7 nav buttons (never jumps to ALL-CAPS on active tab!)
	for i in range(nav_btns.size()):
		HudWidgets.style_tf2_button(nav_btns[i], fonts["body"], 13, i == active_tab)
	for ch in content_vbox.get_children():
		ch.queue_free()

	match active_tab:
		0: # Display & UI Scale
			_sec("DISPLAY, DPI & LIVE INTERFACE SCALING")
			_toggle_row("Automatic Monitor DPI Scaling",
				"Adapts gently on narrow displays while keeping 1080p/1440p/4K crisp with zero double-scaling.",
				settings.auto_dpi, func(v): settings.auto_dpi = v)
			_slider_row("UI Scale Multiplier", "Applies cleanly on mouse release (or use Ctrl+= / Ctrl+- anytime for instant zoom!).",
				75.0, 225.0, 5.0, settings.ui_scale * 100.0, "%",
				func(v): settings.ui_scale = v / 100.0, true)
			var pr_row := HBoxContainer.new()
			pr_row.add_theme_constant_override("separation", 6)
			content_vbox.add_child(pr_row)
			for pct: int in [100, 125, 150, 175, 200, 225]:
				var pb := Button.new()
				pb.text = "%d%%" % pct
				HudWidgets.style_tf2_button(pb, fonts["body"], 12, absf(settings.ui_scale * 100.0 - float(pct)) < 2.5)
				var pv := float(pct) / 100.0
				pb.pressed.connect(func(): settings.ui_scale = pv; settings_applied.emit(); _rebuild_tab())
				pr_row.add_child(pb)

			var wm_row := HBoxContainer.new()
			wm_row.add_theme_constant_override("separation", 6)
			content_vbox.add_child(wm_row)
			var wl := Label.new(); wl.text = "Window Mode: "; wl.custom_minimum_size = Vector2(140, 0); wm_row.add_child(wl)
			var wmodes: Array[String] = ["Windowed", "Maximized", "Fullscreen"]
			for wi in range(wmodes.size()):
				var wb := Button.new(); wb.text = wmodes[wi]
				HudWidgets.style_tf2_button(wb, fonts["body"], 12, settings.window_mode == wi)
				var wv := wi
				wb.pressed.connect(func(): settings.window_mode = wv; settings_applied.emit(); _rebuild_tab())
				wm_row.add_child(wb)

			_toggle_row("VSync Enabled", "Prevents screen tearing in the 3D viewport.",
				settings.vsync, func(v): settings.vsync = v)
			_toggle_row("Show Split 2D Blueprint Pane", "Shows interactive Hammer 2D Top X/Y & Side X/Z elevation views beside 3D.",
				settings.show_2d_split, func(v): settings.show_2d_split = v)

			_sec("REAL 3D TF2 GAME-ASSET ICON CACHE")
			var ir_row := HBoxContainer.new()
			ir_row.add_theme_constant_override("separation", 6)
			content_vbox.add_child(ir_row)
			var irl := Label.new(); irl.text = "3D Icon Resolution: "; irl.custom_minimum_size = Vector2(140, 0); ir_row.add_child(irl)
			for rpx: int in [128, 160, 224]:
				var rb_sz := Button.new(); rb_sz.text = "%dpx" % rpx
				HudWidgets.style_tf2_button(rb_sz, fonts["body"], 12, settings.icon_resolution == rpx)
				var rv := rpx
				rb_sz.pressed.connect(func(): settings.icon_resolution = rv; rebuild_icons_requested.emit(); _rebuild_tab())
				ir_row.add_child(rb_sz)

			var ib_row := HBoxContainer.new()
			content_vbox.add_child(ib_row)
			var il := Label.new()
			il.text = "Renders real TF2 .mdl items (Payload, Medkit, Ammo, Locker, Props) at %dpx MSAA." % settings.icon_resolution
			il.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			il.add_theme_font_size_override("font_size", 12)
			ib_row.add_child(il)
			var rb := Button.new()
			rb.text = "Rebuild 3D Icon Cache"
			HudWidgets.style_tf2_button(rb, fonts["body"], 12)
			rb.pressed.connect(func(): rebuild_icons_requested.emit())
			ib_row.add_child(rb)

		1: # Viewport & 3D Views
			_sec("3D VIEWPORT QUALITY (HAMMER 3D VIEWS)")
			_slider_row("Camera Field of View", "3D editor perspective FOV (Hammer default 75°).",
				50.0, 105.0, 1.0, settings.camera_fov, "°", func(v): settings.camera_fov = v)
			_slider_row("Back Clipping Plane", "Far draw distance in meters (1m = 32 Hammer units).",
				200.0, 1600.0, 50.0, settings.back_clip_m, "m", func(v): settings.back_clip_m = v)
			_toggle_row("Screen-Space Ambient Occlusion (SSAO)", "Adds realistic TF2 crevice shading around walls & props.",
				settings.ssao_enabled, func(v): settings.ssao_enabled = v)
			_toggle_row("Live Valve 6-Face Skybox Background", "Renders real TF2 skybox panorama behind your map.",
				settings.show_skybox_bg, func(v): settings.show_skybox_bg = v)
			var ms_row := HBoxContainer.new(); content_vbox.add_child(ms_row)
			var ml := Label.new(); ml.text = "Anti-Aliasing (MSAA): "; ms_row.add_child(ml)
			for i in range(3):
				var nm: String = ["Off", "2x MSAA", "4x MSAA"][i]
				var b := Button.new(); b.text = nm
				HudWidgets.style_tf2_button(b, fonts["body"], 11, settings.msaa_level == i)
				var mv := i
				b.pressed.connect(func(): settings.msaa_level = mv; settings_applied.emit(); _rebuild_tab())
				ms_row.add_child(b)

		2: # 2D Views & Grid
			_sec("GRID SNAP & 2D BLUEPRINT OPTIONS (HAMMER 2D VIEWS)")
			var gr_row := HBoxContainer.new(); content_vbox.add_child(gr_row)
			var gl := Label.new(); gl.text = "Default Grid Snap: "; gr_row.add_child(gl)
			for u: int in [8, 16, 32, 64, 128]:
				var b := Button.new(); b.text = "%du" % u
				HudWidgets.style_tf2_button(b, fonts["body"], 11, settings.default_grid_u == u)
				var uv := u
				b.pressed.connect(func(): settings.default_grid_u = uv; settings_applied.emit(); _rebuild_tab())
				gr_row.add_child(b)
			_toggle_row("Show 3D Reference Floor Grid", "32u / 128u Hammer floor grid in custom map mode.",
				settings.show_grid_floor, func(v): settings.show_grid_floor = v)
			_toggle_row("Show TF2 Jump-Height Ruler Callouts", "Displays 18u Step / 48u Jump / 128u Scout / 192u Rocket-Jump height badges.",
				settings.show_jump_callouts, func(v): settings.show_jump_callouts = v)
			_toggle_row("Arrow Keys Nudge Selected Object", "Nudges selected solids/entities by 1 grid unit (Hammer classic).",
				settings.arrow_key_nudge, func(v): settings.arrow_key_nudge = v)

		3: # Controls & Keybinds
			_sec("CAMERA NAVIGATION & KEYBIND SCHEME")
			_slider_row("Editor Fly Speed", "WASD movement speed in 3D view (hold Shift for 2.2x).",
				8.0, 50.0, 1.0, settings.fly_speed, " m/s", func(v): settings.fly_speed = v)
			_slider_row("Mouse Look Sensitivity", "Right-click mouselook responsiveness.",
				1.0, 10.0, 0.5, settings.mouse_sens * 1000.0, "", func(v): settings.mouse_sens = v / 1000.0)
			_toggle_row("Invert Mouse Y Axis", "Reverses vertical look direction in 3D editor & playtest.",
				settings.invert_y, func(v): settings.invert_y = v)
			_sec("ACTIVE HAMMER++ / TRENCHBROOM SHORTCUT REFERENCE")
			var kb := Label.new()
			kb.text = "Del / Backspace : Delete Selected   |   [ / ] : Smaller / Larger Grid\nShift+X : Clip Solid   |   Shift+V : Vertex Edit   |   Shift+A : Face Edit\nCtrl+T : Tie to Entity   |   Alt+Enter : SmartEdit Inspector   |   Alt+P : Check Map\nCtrl+D / Shift+Drag : Clone   |   R : Rotate 90°   |   H / U : QuickHide / Unhide\nF5 : Playtest Sandbox (V: Noclip, R: Respawn)   |   F9 : Compile BSP"
			kb.add_theme_font_override("font", fonts["mono"])
			kb.add_theme_font_size_override("font_size", 11)
			kb.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
			content_vbox.add_child(kb)

		4: # TF2, FGDs & Compilers
			_sec("VALVE TF2 SDK, FGDS & CMDSEQ.WC COMPILE PRESETS")
			var tf_dir: String = core.get_tf2_dir() if core != null else "(not found)"
			var dl := Label.new()
			dl.text = "Detected TF2 Directory: %s\nMounted FGDs: base.fgd + tf.fgd + tf-abs.fgd (%d classes)\nMounted Resource Packs: ABS_MRP_Material_Browser.vpk + ABS_MRP_Improved_FGD.vpk" % [
				tf_dir, core.get_fgd_class_count() if core != null else 0
			]
			dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			dl.add_theme_font_size_override("font_size", 12)
			content_vbox.add_child(dl)

			var pr_lbl := Label.new(); pr_lbl.text = "Default F9 Compile Preset (from Hammer CmdSeq.wc):"; content_vbox.add_child(pr_lbl)
			var cp_row := HBoxContainer.new(); cp_row.add_theme_constant_override("separation", 6); content_vbox.add_child(cp_row)
			for p: String in ["Fast", "Default", "Only Entities", "HDR Full", "HDR Final"]:
				var b := Button.new(); b.text = p
				HudWidgets.style_tf2_button(b, fonts["body"], 11, settings.compile_preset == p)
				var pv := p
				b.pressed.connect(func(): settings.compile_preset = pv; _rebuild_tab())
				cp_row.add_child(b)

			_toggle_row("Auto-Seal Unsealed Maps Before Compile", "Automatically wraps map in TOOLSSKYBOX if unsealed.",
				settings.auto_seal_on_compile, func(v): settings.auto_seal_on_compile = v)

		5: # Playtest & Audio
			_sec("F5 PLAYTEST SANDBOX & VALVE TF2 AUDIO")
			var cl_row := HBoxContainer.new(); content_vbox.add_child(cl_row)
			var cl_l := Label.new(); cl_l.text = "Default F5 Class: "; cl_row.add_child(cl_l)
			var cnames := ["Scout", "Soldier", "Demoman", "Sniper", "Engineer", "Heavy"]
			for i in range(cnames.size()):
				var b := Button.new(); b.text = cnames[i]
				HudWidgets.style_tf2_button(b, fonts["body"], 11, settings.default_playtest_class == i)
				var ci := i
				b.pressed.connect(func(): settings.default_playtest_class = ci; _rebuild_tab())
				cl_row.add_child(b)
			_slider_row("Playtest FOV", "First-person camera field of view during F5 walk/playtest.",
				70.0, 110.0, 1.0, settings.playtest_fov, "°", func(v): settings.playtest_fov = v)
			_slider_row("Noclip Fly Speed (V)", "Free-fly speed inside maps during F5 + V Noclip.",
				6.0, 36.0, 1.0, settings.noclip_speed, " m/s", func(v): settings.noclip_speed = v)
			_toggle_row("Mute TF2 UI Sound Effects", "Mutes Valve VPK button clicks, carve & rocket sounds.",
				settings.sfx_muted, func(v): settings.sfx_muted = v)

		6: # Auto-Save & Backups
			_sec("AUTO-SAVE & VMF BACKUP ROTATION (HAMMER GENERAL)")
			_toggle_row("Enable Periodic Auto-Save", "Saves automatic backup .vmf copies into godot/maps/autosave/.",
				settings.autosave_enabled, func(v): settings.autosave_enabled = v)
			_slider_row("Auto-Save Interval", "Minutes between automatic map backups.",
				1.0, 30.0, 1.0, float(settings.autosave_minutes), " min", func(v): settings.autosave_minutes = int(v))
			_slider_row("Max Backup Iterations", "Number of rolling backup .vmf files kept on disk.",
				1.0, 25.0, 1.0, float(settings.backup_count), " files", func(v): settings.backup_count = int(v))
