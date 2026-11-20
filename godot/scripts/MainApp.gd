extends Node3D

## Pootis Builder 2.0 — Complete Valve-Grade TF2 Map Creator (Godot 4 Forward+ + Native C++20 GDExtension)
## Integrates:
##   - Mann Co. Welcome Hub (All 12 TF2 Gamemodes + 8 Biomes + All 263 Official TF2 .bsp Maps)
##   - 4-Stage Mockup 3 TF2 Floating HUD (Build | Gameplay | Style & Light | F5 Playtest)
##   - Native C++20 CSG (Box, Wall, Ramp, Stairs, Arch, Building Wizard, Auto-Carve, Push/Pull, Symmetry)
##   - Interactive Source Displacement Terrain Sculpt Studio (Raise / Lower / Smooth / Flatten)
##   - Easy 3D Model Importer (.obj / .glb / .gltf -> live TF2 Prop + Valve .QC/.SMD export)
##   - Real 3D TF2 .mdl Entities + Payload Spline Tracks + 3D Bezier Logic Wires
##   - 6-Class F5 TF2 Playtest Sandbox (Scout, Soldier Rocket-Jump, Demo, Sniper Scope, Engi 1100u Sentry, Heavy)
##   - 1-Click Async Valve Compiler (vbsp/vvis/vrad) + 3D Red Leak Laser + Auto-Seal
##   - Authentic Valve TF2 UI Sound Effects from tf2_sound_misc_dir.vpk

const Tf2AssetsScript        = preload("res://scripts/core/Tf2Assets.gd")
const Tf2BspLoaderScript     = preload("res://scripts/core/Tf2BspLoader.gd")
const Tf2GamemodesScript     = preload("res://scripts/core/Tf2Gamemodes.gd")
const Tf2AudioScript         = preload("res://scripts/core/Tf2Audio.gd")
const Tf2CatalogScript       = preload("res://scripts/core/Tf2Catalog.gd")
const MapSceneSyncScript     = preload("res://scripts/editor/MapSceneSync.gd")
const EntityVisualsScript    = preload("res://scripts/editor/EntityVisuals.gd")
const CompileCtrlScript      = preload("res://scripts/editor/CompileController.gd")
const ModelImporterScript    = preload("res://scripts/editor/ModelImporter.gd")
const SandboxPlayerScript    = preload("res://scripts/playtest/Tf2SandboxPlayer.gd")
const HudWidgets             = preload("res://scripts/ui/Tf2HudWidgets.gd")

const REPO_ROOT := "C:/Users/steph/Documents/Git/pootis builder"
const UPM := 32.0

enum Stage { BUILD, GAMEPLAY, STYLE, PLAYTEST }
enum SymmetryMode { OFF, MIRROR_X, ROT_180 }

# Core native & scene systems
var core: Object
var doc: Object
var assets: RefCounted
var bsp_loader: RefCounted
var audio: Node
var map_sync: Node3D
var ent_vis: Node3D
var compile_ctrl: Node3D
var player: CharacterBody3D
var bsp_root: Node3D
var imported_props_root: Node3D

# Environment & Editor Camera
var we: WorldEnvironment
var sun: DirectionalLight3D
var editor_cam: Camera3D
var sym_plane: MeshInstance3D
var ghost_mesh: MeshInstance3D
var brush_ring: MeshInstance3D
var grid_floor: MeshInstance3D

# Editor State
var stage: int = Stage.BUILD
var active_tool: String = "floor"
var active_material: String = "WOOD/WOOD_WALL002"
var active_prop_mdl: String = "models/props_mining/miningcrate001.mdl"
var active_biome: String = "badlands"
var active_sky: String = "sky_badlands_01"
var symmetry: int = SymmetryMode.OFF
var top_down_2d: bool = false
var grid_m: float = 1.0 # 32u default
var hover_pos: Vector3 = Vector3.ZERO
var hover_valid: bool = false
var viewing_bsp: bool = false
var current_bsp_name: String = ""
var current_bsp_spawn: Vector3 = Vector3(0, 2, 0)
var current_bsp_yaw: float = 0.0

# Building Wizard & Terrain Brush settings
var bld_floors: int = 2
var bld_roof_style: int = 1 # 0=Flat, 1=Gabled, 2=Slanted
var bld_door_side: int = 2
var terrain_mode: int = 0   # 0=Raise, 1=Lower, 2=Smooth, 3=Flatten
var terrain_radius_m: float = 4.5
var terrain_strength_m: float = 1.2
var _terrain_sculpting: bool = false

# Orbit / Fly camera state
var cam_yaw: float = -0.65
var cam_pitch: float = -0.46
var cam_pos: Vector3 = Vector3(24, 18, 28)
var _rmb_looking: bool = false
var _mmb_panning: bool = false
var _last_mouse: Vector2 = Vector2.ZERO

# UI References
var fonts: Dictionary = {}
var hud_layer: CanvasLayer
var overlay_2d: Control
var pie_wheel: Control
var welcome_panel: Control
var top_bar: Control
var bottom_dock: Control
var right_drawer: PanelContainer
var right_drawer_vbox: VBoxContainer
var right_drawer_title: Label
var playtest_hud: Control
var playtest_lbl: Label
var status_toast: Label
var map_title_lbl: Label
var sym_btn: Button
var coach_btn: Button
var stage_btns: Array[Button] = []
var file_dialog: FileDialog

# Screenshot automation state (for overnight visual tests)
var _auto_shots: Array = []
var _auto_shot_idx: int = 0
var _auto_shot_frames: int = 0

func _ready() -> void:
	_init_core_systems()
	_init_3d_world()
	_init_ui()

	# Start with a vibrant live KOTH map in the background behind the Mann Co. Welcome Hub!
	_load_gamemode("koth", "badlands", false)
	_show_welcome_hub(true)

	# Parse optional --shot automation args (e.g. --shot welcome:out.png --shot build:out2.png)
	_parse_cli_shots()

func _init_core_systems() -> void:
	core = ClassDB.instantiate("Tf2Core")
	core.mount_tf2(REPO_ROOT)
	assets = Tf2AssetsScript.new(core)
	bsp_loader = Tf2BspLoaderScript.new(core, assets)
	doc = ClassDB.instantiate("Tf2MapDoc")

	audio = Tf2AudioScript.new()
	audio.name = "Tf2Audio"
	add_child(audio)
	audio.setup(core)

	fonts = HudWidgets.load_fonts(core.get_tf2_dir())

func _init_3d_world() -> void:
	we = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = assets.get_sky(active_sky)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.78
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.ssao_enabled = true
	env.ssao_intensity = 1.15
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.rotation_degrees = Vector3(-40, 35, 0)
	add_child(sun)

	map_sync = MapSceneSyncScript.new()
	map_sync.name = "MapSceneSync"
	map_sync.setup(doc, assets)
	add_child(map_sync)

	ent_vis = EntityVisualsScript.new()
	ent_vis.name = "EntityVisuals"
	ent_vis.setup(doc, assets)
	add_child(ent_vis)

	compile_ctrl = CompileCtrlScript.new()
	compile_ctrl.name = "CompileController"
	add_child(compile_ctrl)
	compile_ctrl.status_changed.connect(_on_compile_status)
	compile_ctrl.compile_finished.connect(_on_compile_finished)

	bsp_root = Node3D.new()
	bsp_root.name = "OfficialBspRoot"
	add_child(bsp_root)

	imported_props_root = Node3D.new()
	imported_props_root.name = "ImportedCustomProps"
	add_child(imported_props_root)

	player = SandboxPlayerScript.new()
	player.name = "Tf2SandboxPlayer"
	add_child(player)
	player.set_active(false)
	player.fired_rocket.connect(func(_o): audio.play("rocket", -10.0))
	player.exploded.connect(func(_p): audio.play("explode", -11.0))
	player.pickup_collected.connect(func(_k): audio.play("medkit", -8.0))

	editor_cam = Camera3D.new()
	editor_cam.fov = 72.0
	editor_cam.far = 650.0
	editor_cam.current = true
	add_child(editor_cam)
	_apply_editor_cam()

	_create_editor_helpers()

func _create_editor_helpers() -> void:
	# Subtle Hammer 32u/128u Reference Grid on Y = -0.02
	grid_floor = MeshInstance3D.new()
	var gim := ImmediateMesh.new()
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.vertex_color_use_as_albedo = true
	gim.surface_begin(Mesh.PRIMITIVE_LINES, gmat)
	for i in range(-48, 49, 2):
		var major := (i % 8 == 0)
		var c := Color(0.95, 0.72, 0.35, 0.20) if major else Color(0.8, 0.76, 0.70, 0.08)
		gim.surface_set_color(c)
		gim.surface_add_vertex(Vector3(i, -0.02, -48)); gim.surface_add_vertex(Vector3(i, -0.02, 48))
		gim.surface_set_color(c)
		gim.surface_add_vertex(Vector3(-48, -0.02, i)); gim.surface_add_vertex(Vector3(48, -0.02, i))
	gim.surface_end()
	grid_floor.mesh = gim
	add_child(grid_floor)

	# Glowing RED | BLU Symmetry Plane at X = 0!
	sym_plane = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(72.0, 22.0)
	sym_plane.mesh = pm
	sym_plane.rotation_degrees = Vector3(0, 0, 90)
	sym_plane.position = Vector3(0, 10.0, 0)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED
	smat.albedo_color = Color(0.96, 0.64, 0.18, 0.14)
	sym_plane.material_override = smat
	sym_plane.visible = false
	add_child(sym_plane)

	# Ghost Placement Preview Box
	ghost_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4, 1, 4)
	ghost_mesh.mesh = bm
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.96, 0.65, 0.16, 0.28)
	ghost_mesh.material_override = gm
	ghost_mesh.visible = false
	add_child(ghost_mesh)

	# Terrain Sculpt Circular Brush Ring
	brush_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.94
	tm.outer_radius = 1.0
	brush_ring.mesh = tm
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(0.24, 0.92, 0.98, 0.92)
	brush_ring.material_override = bmat
	brush_ring.visible = false
	add_child(brush_ring)

# ==============================================================================
# UI CONSTRUCTION (Mockup 3 Floating TF2 HUD + Welcome Hub + Contextual Drawer)
# ==============================================================================
func _init_ui() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "Tf2HudLayer"
	add_child(hud_layer)

	overlay_2d = HudWidgets.ViewportOverlay.new(self)
	hud_layer.add_child(overlay_2d)

	_build_top_bar()
	_build_bottom_dock()
	_build_right_drawer()
	_build_playtest_hud()
	_build_welcome_hub()

	pie_wheel = HudWidgets.RadialPieWheel.new(fonts["heading"])
	pie_wheel.action_chosen.connect(_on_pie_action)
	hud_layer.add_child(pie_wheel)

	# Floating status toast pill above bottom dock
	status_toast = Label.new()
	status_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	status_toast.offset_top = -132
	status_toast.offset_bottom = -104
	status_toast.offset_left = -280
	status_toast.offset_right = 280
	status_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_toast.add_theme_font_override("font", fonts["heading"])
	status_toast.add_theme_font_size_override("font_size", 13)
	status_toast.add_theme_color_override("font_color", HudWidgets.COL_TX)
	status_toast.visible = false
	hud_layer.add_child(status_toast)

	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.size = Vector2i(760, 500)
	file_dialog.file_selected.connect(_on_file_selected)
	hud_layer.add_child(file_dialog)

func _build_top_bar() -> void:
	top_bar = MarginContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.add_theme_constant_override("margin_left", 10)
	top_bar.add_theme_constant_override("margin_right", 10)
	top_bar.add_theme_constant_override("margin_top", 8)
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(top_bar)

	var bar_hb := HBoxContainer.new()
	bar_hb.add_theme_constant_override("separation", 8)
	bar_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(bar_hb)

	# TOP-LEFT: Title & File Pill
	var left_frame := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 9.0, true)
	bar_hb.add_child(left_frame)
	var lhb := HBoxContainer.new()
	lhb.add_theme_constant_override("separation", 5)
	left_frame.add_child(lhb)

	var brand := Label.new()
	brand.text = "POOTIS BUILDER"
	brand.add_theme_font_override("font", fonts["heading"])
	brand.add_theme_font_size_override("font_size", 14)
	brand.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	lhb.add_child(brand)

	map_title_lbl = Label.new()
	map_title_lbl.text = "| koth"
	map_title_lbl.add_theme_font_override("font", fonts["body"])
	map_title_lbl.add_theme_font_size_override("font_size", 11)
	map_title_lbl.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	lhb.add_child(map_title_lbl)

	for spec in [
		{"t": "Hub", "fn": func(): _show_welcome_hub(true)},
		{"t": "Save", "fn": _save_current_vmf},
		{"t": "Undo", "fn": _do_undo},
		{"t": "Redo", "fn": _do_redo},
	]:
		var b := Button.new()
		b.text = spec["t"]
		HudWidgets.style_tf2_button(b, fonts["body"], 11)
		b.pressed.connect(func(): audio.play("click"); spec["fn"].call())
		lhb.add_child(b)

	var sp1 := Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_hb.add_child(sp1)

	# TOP-CENTER: 4-Stage Stepper Pill!
	var center_frame := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 9.0, true)
	bar_hb.add_child(center_frame)
	var chb := HBoxContainer.new()
	chb.alignment = BoxContainer.ALIGNMENT_CENTER
	chb.add_theme_constant_override("separation", 5)
	center_frame.add_child(chb)

	stage_btns.clear()
	var stages := [
		{"id": Stage.BUILD,    "t": "1. BUILD"},
		{"id": Stage.GAMEPLAY, "t": "2. GAMEPLAY"},
		{"id": Stage.STYLE,    "t": "3. STYLE"},
		{"id": Stage.PLAYTEST, "t": "4. PLAY (F5)"},
	]
	for st in stages:
		var sb := Button.new()
		sb.text = st["t"]
		HudWidgets.style_tf2_button(sb, fonts["heading"], 11, st["id"] == stage)
		var sid: int = st["id"]
		sb.pressed.connect(func(): audio.play("click"); set_stage(sid))
		chb.add_child(sb)
		stage_btns.append(sb)

	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_hb.add_child(sp2)

	# TOP-RIGHT: Symmetry, View, Map Coach, Auto-Seal, Compile!
	var right_frame := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 9.0, true)
	bar_hb.add_child(right_frame)
	var rhb := HBoxContainer.new()
	rhb.alignment = BoxContainer.ALIGNMENT_END
	rhb.add_theme_constant_override("separation", 5)
	right_frame.add_child(rhb)

	sym_btn = Button.new()
	sym_btn.text = "Sym: Off"
	HudWidgets.style_tf2_button(sym_btn, fonts["body"], 11)
	sym_btn.pressed.connect(func(): audio.play("click"); _cycle_symmetry())
	rhb.add_child(sym_btn)

	var view_btn := Button.new()
	view_btn.text = "2D/3D"
	HudWidgets.style_tf2_button(view_btn, fonts["body"], 11)
	view_btn.pressed.connect(func(): audio.play("click"); _toggle_2d_view())
	rhb.add_child(view_btn)

	coach_btn = Button.new()
	coach_btn.text = "Coach"
	HudWidgets.style_tf2_button(coach_btn, fonts["body"], 11)
	coach_btn.pressed.connect(func(): audio.play("click"); _open_coach_drawer())
	rhb.add_child(coach_btn)

	var seal_btn := Button.new()
	seal_btn.text = "Seal"
	HudWidgets.style_tf2_button(seal_btn, fonts["body"], 11)
	seal_btn.pressed.connect(func(): audio.play("carve"); _do_auto_seal())
	rhb.add_child(seal_btn)

	var comp_btn := Button.new()
	comp_btn.text = "COMPILE"
	HudWidgets.style_tf2_button(comp_btn, fonts["heading"], 11, true)
	comp_btn.pressed.connect(func(): audio.play("click"); _open_compile_drawer())
	rhb.add_child(comp_btn)

func _build_bottom_dock() -> void:
	bottom_dock = Control.new()
	bottom_dock.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_dock.offset_top = -94
	bottom_dock.offset_bottom = -10
	bottom_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(bottom_dock)
	_rebuild_bottom_dock()

func _rebuild_bottom_dock() -> void:
	for ch in bottom_dock.get_children():
		ch.queue_free()
	if stage == Stage.PLAYTEST:
		return

	var frame := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 10.0, true)
	frame.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	frame.offset_bottom = 0
	frame.offset_top = -80
	frame.offset_left = -430
	frame.offset_right = 430
	bottom_dock.add_child(frame)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 6)
	frame.add_child(hb)

	var slots: Array = []
	if stage == Stage.BUILD:
		slots = [
			{"id": "select",   "piece": "Pull",     "lbl": "Pull",     "tool": true,  "tkind": "Pull"},
			{"id": "floor",    "piece": "Floor",    "lbl": "Floor"},
			{"id": "wall",     "piece": "Wall",     "lbl": "Wall"},
			{"id": "building", "piece": "Building", "lbl": "Building"},
			{"id": "ramp",     "piece": "Ramp",     "lbl": "Ramp"},
			{"id": "stairs",   "piece": "Stairs",   "lbl": "Stairs"},
			{"id": "arch",     "piece": "Arch",     "lbl": "Arch"},
			{"id": "carve",    "piece": "Door",     "lbl": "Carve"},
			{"id": "terrain",  "piece": "Terrain",  "lbl": "Terrain",  "tool": true,  "tkind": "Terrain"},
			{"id": "import3d", "piece": "Model",    "lbl": "3D Model", "tool": true,  "tkind": "Model"},
		]
	elif stage == Stage.GAMEPLAY:
		slots = [
			{"id": "spawn_red", "piece": "Spawn",  "lbl": "RED Spawn", "team": 1},
			{"id": "spawn_blu", "piece": "Spawn",  "lbl": "BLU Spawn", "team": 2},
			{"id": "resupply",  "piece": "Box",    "lbl": "Resupply"},
			{"id": "health_med","piece": "Floor",  "lbl": "Health"},
			{"id": "ammo_med",  "piece": "Floor",  "lbl": "Ammo"},
			{"id": "cap_point", "piece": "Floor",  "lbl": "Cap Point"},
			{"id": "intel",     "piece": "Box",    "lbl": "Intel"},
			{"id": "bomb_cart", "piece": "Ramp",   "lbl": "Bomb Cart"},
			{"id": "path_node", "piece": "Stairs", "lbl": "Track"},
			{"id": "upgrade_station", "piece": "Building", "lbl": "MvM Upgr"},
			{"id": "bot_spawn", "piece": "Spawn",  "lbl": "Bot Spawn", "team": 2},
			{"id": "wires",     "piece": "Wire",   "lbl": "Wires (L)", "tool": true, "tkind": "Wire"},
		]
	elif stage == Stage.STYLE:
		slots = [
			{"id": "biomes",    "piece": "Building", "lbl": "Biomes"},
			{"id": "materials", "piece": "Wall",     "lbl": "Materials"},
			{"id": "props",     "piece": "Box",      "lbl": "TF2 Props"},
			{"id": "sky_sun",   "piece": "Terrain",  "lbl": "Sky & Sun", "tool": true, "tkind": "Terrain"},
			{"id": "light",     "piece": "Floor",    "lbl": "Add Light"},
			{"id": "import3d",  "piece": "Model",    "lbl": "Import 3D", "tool": true, "tkind": "Model"},
		]

	for sl in slots:
		var sid: String = sl["id"]
		var is_act := (active_tool == sid)
		var slot_btn := HudWidgets.RailSlot.new(
			sl["piece"], sl["lbl"], null, is_act,
			int(sl.get("team", 0)), bool(sl.get("tool", false)), str(sl.get("tkind", "")), fonts["body"]
		)
		slot_btn.pressed.connect(func(): audio.play("click"); _select_tool(sid))
		hb.add_child(slot_btn)

func _build_right_drawer() -> void:
	right_drawer = HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 10.0, true)
	right_drawer.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_drawer.offset_right = -12
	right_drawer.offset_left = -316
	right_drawer.offset_top = 68
	right_drawer.offset_bottom = 560
	right_drawer.visible = false
	hud_layer.add_child(right_drawer)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	right_drawer.add_child(outer)

	var hdr := HBoxContainer.new()
	outer.add_child(hdr)
	right_drawer_title = Label.new()
	right_drawer_title.text = "TOOL OPTIONS"
	right_drawer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_drawer_title.add_theme_font_override("font", fonts["heading"])
	right_drawer_title.add_theme_font_size_override("font_size", 14)
	right_drawer_title.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	hdr.add_child(right_drawer_title)

	var close_b := Button.new()
	close_b.text = "X"
	HudWidgets.style_tf2_button(close_b, fonts["heading"], 11)
	close_b.pressed.connect(func(): right_drawer.visible = false)
	hdr.add_child(close_b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	right_drawer_vbox = VBoxContainer.new()
	right_drawer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_drawer_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(right_drawer_vbox)

func _build_playtest_hud() -> void:
	playtest_hud = Control.new()
	playtest_hud.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	playtest_hud.offset_top = -98
	playtest_hud.offset_bottom = -12
	playtest_hud.visible = false
	hud_layer.add_child(playtest_hud)

	var frame := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 10.0, true)
	frame.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	frame.offset_left = -390; frame.offset_right = 390
	frame.offset_top = -76; frame.offset_bottom = 0
	playtest_hud.add_child(frame)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	frame.add_child(vb)

	playtest_lbl = Label.new()
	playtest_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	playtest_lbl.add_theme_font_override("font", fonts["heading"])
	playtest_lbl.add_theme_font_size_override("font_size", 14)
	playtest_lbl.add_theme_color_override("font_color", HudWidgets.COL_TX)
	vb.add_child(playtest_lbl)

	var class_row := HBoxContainer.new()
	class_row.alignment = BoxContainer.ALIGNMENT_CENTER
	class_row.add_theme_constant_override("separation", 6)
	vb.add_child(class_row)
	for i in range(SandboxPlayerScript.CLASSES.size()):
		var c: Dictionary = SandboxPlayerScript.CLASSES[i]
		var cb := Button.new()
		cb.text = "%d %s" % [c["id"], c["name"]]
		HudWidgets.style_tf2_button(cb, fonts["body"], 11)
		var ci := i
		cb.pressed.connect(func(): player.set_tf2_class(ci))
		class_row.add_child(cb)

func _build_welcome_hub() -> void:
	welcome_panel = ColorRect.new()
	welcome_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	welcome_panel.color = Color(0.06, 0.05, 0.04, 0.72)
	hud_layer.add_child(welcome_panel)

	var card := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 14.0, true)
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.offset_left = -480; card.offset_right = 480
	card.offset_top = -290; card.offset_bottom = 290
	welcome_panel.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)

	# Header
	var hdr := HBoxContainer.new()
	vb.add_child(hdr)
	var title := Label.new()
	title.text = "MANN CO. MAP WORKSHOP — POOTIS BUILDER 2.0"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", fonts["heading"])
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	hdr.add_child(title)

	var resume_b := Button.new()
	resume_b.text = "Resume Editor"
	HudWidgets.style_tf2_button(resume_b, fonts["heading"], 13, true)
	resume_b.pressed.connect(func(): audio.play("click"); _show_welcome_hub(false))
	hdr.add_child(resume_b)

	var sub := Label.new()
	sub.text = "Pick ANY of the 12 TF2 Gamemodes to start building immediately, or load any of your %d installed official Valve TF2 maps!" % core.list_maps().size()
	sub.add_theme_font_override("font", fonts["body"])
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	vb.add_child(sub)

	# Split: Left = 12 Gamemodes Grid | Right = Official TF2 Maps Browser
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	vb.add_child(cols)

	# Left Column: All 12 TF2 Gamemodes
	var left_col := VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_col.size_flags_stretch_ratio = 1.45
	left_col.add_theme_constant_override("separation", 6)
	cols.add_child(left_col)

	var gm_hdr := Label.new()
	gm_hdr.text = "CREATE NEW TF2 MAP (ALL 12 GAMEMODES)"
	gm_hdr.add_theme_font_override("font", fonts["heading"])
	gm_hdr.add_theme_font_size_override("font_size", 14)
	gm_hdr.add_theme_color_override("font_color", HudWidgets.COL_TX)
	left_col.add_child(gm_hdr)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	left_col.add_child(grid)

	for gm in Tf2GamemodesScript.GAMEMODES:
		var gb := Button.new()
		gb.text = "%s\n(%s)" % [gm["name"], gm["short"]]
		gb.custom_minimum_size = Vector2(0, 62)
		gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(gb, fonts["heading"], 12)
		var mid: String = gm["id"]
		gb.pressed.connect(func():
			audio.play("success", -10.0)
			_load_gamemode(mid)
			_show_welcome_hub(false)
		)
		grid.add_child(gb)

	# Quick Open VMF / Import 3D row
	var foot_l := HBoxContainer.new()
	foot_l.add_theme_constant_override("separation", 8)
	left_col.add_child(foot_l)
	var open_vmf := Button.new()
	open_vmf.text = "Open Existing .VMF..."
	HudWidgets.style_tf2_button(open_vmf, fonts["body"], 12)
	open_vmf.pressed.connect(func(): _open_file_dialog("vmf"))
	foot_l.add_child(open_vmf)

	var open_imp := Button.new()
	open_imp.text = "Import 3D Model (.OBJ/.GLB)..."
	HudWidgets.style_tf2_button(open_imp, fonts["body"], 12)
	open_imp.pressed.connect(func(): _show_welcome_hub(false); _open_file_dialog("model"))
	foot_l.add_child(open_imp)

	# Right Column: Searchable 263 Official TF2 Maps Browser!
	var right_col := VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_col.size_flags_stretch_ratio = 1.0
	right_col.add_theme_constant_override("separation", 6)
	cols.add_child(right_col)

	var bsp_hdr := Label.new()
	bsp_hdr.text = "OFFICIAL TF2 MAPS (%d INSTALLED)" % core.list_maps().size()
	bsp_hdr.add_theme_font_override("font", fonts["heading"])
	bsp_hdr.add_theme_font_size_override("font_size", 14)
	bsp_hdr.add_theme_color_override("font_color", HudWidgets.COL_TX)
	right_col.add_child(bsp_hdr)

	var search := LineEdit.new()
	search.placeholder_text = "Filter maps (turbine, upward, decoy, degroot...)"
	right_col.add_child(search)

	var map_scroll := ScrollContainer.new()
	map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_col.add_child(map_scroll)
	var map_list := VBoxContainer.new()
	map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_list.add_theme_constant_override("separation", 4)
	map_scroll.add_child(map_list)

	var all_maps: PackedStringArray = core.list_maps()
	var populate_maps := func(filter: String) -> void:
		for ch in map_list.get_children():
			ch.queue_free()
		var fl := filter.to_lower().strip_edges()
		var shown := 0
		# Highlight fan-favorite maps across every gamemode first when filter is empty!
		var featured := ["ctf_turbine.bsp", "ctf_2fort.bsp", "pl_upward.bsp", "koth_sawmill.bsp", "mvm_decoy.bsp", "cp_degrootkeep.bsp", "plr_hightower.bsp", "cp_process_final.bsp", "arena_badlands.bsp", "sd_doomsday.bsp"]
		var ordered: Array[String] = []
		if fl.is_empty():
			for fm in featured:
				if all_maps.has(fm):
					ordered.append(fm)
		for m in all_maps:
			if fl.is_empty() or m.to_lower().find(fl) != -1:
				if not ordered.has(m):
					ordered.append(m)
		for m in ordered:
			if shown >= 40:
				break
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 4)
			map_list.add_child(row)
			var mb := Button.new()
			mb.text = m
			mb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			HudWidgets.style_tf2_button(mb, fonts["body"], 11)
			var mcopy := m
			mb.pressed.connect(func():
				audio.play("click")
				_load_official_bsp(mcopy)
				_show_welcome_hub(false)
			)
			row.add_child(mb)
			shown += 1

	populate_maps.call("")
	search.text_changed.connect(populate_maps)

# ==============================================================================
# STAGE & TOOL ACTIONS
# ==============================================================================
func _show_welcome_hub(show: bool) -> void:
	welcome_panel.visible = show
	if show and stage == Stage.PLAYTEST:
		set_stage(Stage.BUILD)

func set_stage(new_stage: int) -> void:
	if new_stage == Stage.PLAYTEST:
		stage = Stage.PLAYTEST
		_enter_playtest()
	else:
		if stage == Stage.PLAYTEST:
			_exit_playtest()
		stage = new_stage
		if stage == Stage.BUILD:
			active_tool = "floor"
		elif stage == Stage.GAMEPLAY:
			active_tool = "spawn_red"
		elif stage == Stage.STYLE:
			active_tool = "biomes"
			_open_biomes_drawer()

	for i in range(stage_btns.size()):
		HudWidgets.style_tf2_button(stage_btns[i], fonts["heading"], 11, i == stage)
	ghost_mesh.visible = false
	brush_ring.visible = false
	_rebuild_bottom_dock()
	if stage != Stage.STYLE:
		right_drawer.visible = false
	overlay_2d.queue_redraw()

func _select_tool(sid: String) -> void:
	active_tool = sid
	if sid == "wires":
		ent_vis.show_logic_wires = not ent_vis.show_logic_wires
		ent_vis.sync_all()
		_toast("3D Logic Wires: %s" % ("ON" if ent_vis.show_logic_wires else "OFF"))
	elif sid == "building":
		_open_building_wizard()
	elif sid == "terrain":
		_open_terrain_studio()
	elif sid == "import3d":
		_open_import_model_drawer()
	elif sid == "biomes":
		_open_biomes_drawer()
	elif sid == "materials":
		_open_materials_drawer()
	elif sid == "props":
		_open_props_drawer()
	elif sid == "sky_sun":
		_open_sky_sun_drawer()
	else:
		right_drawer.visible = false
	_rebuild_bottom_dock()

func _clear_drawer(title: String) -> void:
	right_drawer_title.text = title
	for ch in right_drawer_vbox.get_children():
		ch.queue_free()
	right_drawer.visible = true

func _open_building_wizard() -> void:
	_clear_drawer("MODULAR BUILDING WIZARD")
	var info := Label.new()
	info.text = "Click anywhere in the 3D scene to stamp a complete TF2 building with auto-carved doorways, sniper windows & interior stairs!"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_override("font", fonts["body"])
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	right_drawer_vbox.add_child(info)

	# Floors selector (1 / 2 / 3)
	var fl_lbl := Label.new(); fl_lbl.text = "Stories (144u each):"; right_drawer_vbox.add_child(fl_lbl)
	var fl_row := HBoxContainer.new(); right_drawer_vbox.add_child(fl_row)
	for f: int in [1, 2, 3]:
		var b := Button.new(); b.text = "%d Floor%s" % [f, "s" if f > 1 else ""]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["heading"], 11, bld_floors == f)
		var fv: int = f
		b.pressed.connect(func(): bld_floors = fv; _open_building_wizard())
		fl_row.add_child(b)

	# Roof style (Flat / Gabled / Slanted)
	var rf_lbl := Label.new(); rf_lbl.text = "Roof Style:"; right_drawer_vbox.add_child(rf_lbl)
	var rf_row := HBoxContainer.new(); right_drawer_vbox.add_child(rf_row)
	var rnames := ["Flat", "Gabled Barn", "Slanted"]
	for i in range(3):
		var b := Button.new(); b.text = rnames[i]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["body"], 11, bld_roof_style == i)
		var rv := i
		b.pressed.connect(func(): bld_roof_style = rv; _open_building_wizard())
		rf_row.add_child(b)

	# Quick 1-click stamp at center
	var stamp_b := Button.new()
	stamp_b.text = "Stamp Building at Cursor / Origin"
	HudWidgets.style_tf2_button(stamp_b, fonts["heading"], 12, true)
	stamp_b.pressed.connect(func(): _place_tool_at(hover_pos if hover_valid else Vector3.ZERO))
	right_drawer_vbox.add_child(stamp_b)

func _open_terrain_studio() -> void:
	_clear_drawer("DISPLACEMENT TERRAIN STUDIO")
	var new_p := Button.new()
	new_p.text = "+ New Terrain Patch (512u x 512u)"
	HudWidgets.style_tf2_button(new_p, fonts["heading"], 12, true)
	new_p.pressed.connect(func():
		var p := hover_pos if hover_valid else Vector3.ZERO
		doc.make_terrain_patch(p + Vector3(-8, -1, -8), p + Vector3(8, 0, 8), 3, Tf2GamemodesScript.get_biome(active_biome)["floor"])
		doc.record_undo("Add Terrain Patch")
		map_sync.sync_all()
		audio.play("place")
		_toast("Added sculptable Source Displacement patch! Hold LMB to sculpt.")
	)
	right_drawer_vbox.add_child(new_p)

	var mlbl := Label.new(); mlbl.text = "Sculpt Brush Mode:"; right_drawer_vbox.add_child(mlbl)
	var mnames := ["Raise Hill", "Lower Valley", "Smooth", "Flatten"]
	var grid := GridContainer.new(); grid.columns = 2; right_drawer_vbox.add_child(grid)
	for i in range(4):
		var b := Button.new(); b.text = mnames[i]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["body"], 11, terrain_mode == i)
		var mv := i
		b.pressed.connect(func(): terrain_mode = mv; _open_terrain_studio())
		grid.add_child(b)

	var r_lbl := Label.new(); r_lbl.text = "Brush Radius: %du" % int(terrain_radius_m * UPM); right_drawer_vbox.add_child(r_lbl)
	var r_sl := HSlider.new(); r_sl.min_value = 2.0; r_sl.max_value = 12.0; r_sl.step = 0.5; r_sl.value = terrain_radius_m
	r_sl.value_changed.connect(func(v): terrain_radius_m = v; r_lbl.text = "Brush Radius: %du" % int(v * UPM))
	right_drawer_vbox.add_child(r_sl)

	var s_lbl := Label.new(); s_lbl.text = "Strength: %.1fm" % terrain_strength_m; right_drawer_vbox.add_child(s_lbl)
	var s_sl := HSlider.new(); s_sl.min_value = 0.3; s_sl.max_value = 3.5; s_sl.step = 0.1; s_sl.value = terrain_strength_m
	s_sl.value_changed.connect(func(v): terrain_strength_m = v; s_lbl.text = "Strength: %.1fm" % v)
	right_drawer_vbox.add_child(s_sl)

func _open_import_model_drawer() -> void:
	_clear_drawer("EASY 3D MODEL IMPORTER")
	var info := Label.new()
	info.text = "Import any 3D model (.OBJ, .GLB, .GLTF) from Blender, Blockbench, or Maya directly into your TF2 map — with automatic TF2 scaling, physics collision, and Valve .QC/.SMD export!"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_override("font", fonts["body"])
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	right_drawer_vbox.add_child(info)

	var pick_b := Button.new()
	pick_b.text = "Browse .OBJ / .GLB / .GLTF..."
	HudWidgets.style_tf2_button(pick_b, fonts["heading"], 13, true)
	pick_b.pressed.connect(func(): _open_file_dialog("model"))
	right_drawer_vbox.add_child(pick_b)

	# Demo built-in sample pylon button if sample exists
	var sample_obj := REPO_ROOT + "/godot/maps/imported_models/custom_pylon.obj"
	if FileAccess.file_exists(sample_obj):
		var sb := Button.new()
		sb.text = "Quick Test: Place Sample Custom Pylon"
		HudWidgets.style_tf2_button(sb, fonts["body"], 11)
		sb.pressed.connect(func(): _import_3d_model_file(sample_obj))
		right_drawer_vbox.add_child(sb)

func _open_biomes_drawer() -> void:
	_clear_drawer("1-CLICK TF2 BIOME THEMES")
	for bkey in Tf2GamemodesScript.BIOMES.keys():
		var b: Dictionary = Tf2GamemodesScript.BIOMES[bkey]
		var btn := Button.new()
		btn.text = "%s (%s)" % [b["name"], b["sky"]]
		HudWidgets.style_tf2_button(btn, fonts["body"], 12, active_biome == bkey)
		var k: String = bkey
		btn.pressed.connect(func():
			audio.play("carve")
			_apply_biome(k)
			_open_biomes_drawer()
		)
		right_drawer_vbox.add_child(btn)

func _open_materials_drawer() -> void:
	_clear_drawer("VPK MATERIAL PAINTER")
	var hint := Label.new()
	hint.text = "Click a surface in 3D to paint! Active: " + active_material.get_file()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	right_drawer_vbox.add_child(hint)

	for cat in Tf2CatalogScript.MATERIAL_CATEGORIES.keys():
		var cl := Label.new()
		cl.text = cat.to_upper()
		cl.add_theme_font_override("font", fonts["heading"])
		cl.add_theme_font_size_override("font_size", 12)
		cl.add_theme_color_override("font_color", HudWidgets.COL_ACC)
		right_drawer_vbox.add_child(cl)
		var g := GridContainer.new(); g.columns = 2; right_drawer_vbox.add_child(g)
		for item in Tf2CatalogScript.MATERIAL_CATEGORIES[cat]:
			var b := Button.new()
			b.text = item["name"]
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			HudWidgets.style_tf2_button(b, fonts["body"], 11, active_material == item["mat"])
			var mp: String = item["mat"]
			b.pressed.connect(func():
				active_material = mp
				active_tool = "paint"
				audio.play("click")
				_open_materials_drawer()
			)
			g.add_child(b)

func _open_props_drawer() -> void:
	_clear_drawer("3D TF2 PROP BROWSER")
	for cat in Tf2CatalogScript.PROP_CATEGORIES.keys():
		var cl := Label.new()
		cl.text = cat.to_upper()
		cl.add_theme_font_override("font", fonts["heading"])
		cl.add_theme_font_size_override("font_size", 12)
		cl.add_theme_color_override("font_color", HudWidgets.COL_ACC)
		right_drawer_vbox.add_child(cl)
		var g := GridContainer.new(); g.columns = 2; right_drawer_vbox.add_child(g)
		for item in Tf2CatalogScript.PROP_CATEGORIES[cat]:
			var b := Button.new()
			b.text = item["name"]
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			HudWidgets.style_tf2_button(b, fonts["body"], 11, active_prop_mdl == item["mdl"])
			var mp: String = item["mdl"]
			b.pressed.connect(func():
				active_prop_mdl = mp
				active_tool = "place_prop"
				audio.play("click")
				_toast("Click in 3D to place %s" % item["name"])
				_open_props_drawer()
			)
			g.add_child(b)

func _open_sky_sun_drawer() -> void:
	_clear_drawer("SKYBOX & SUN STUDIO")
	var yaw_lbl := Label.new(); yaw_lbl.text = "Sun Compass Angle:"; right_drawer_vbox.add_child(yaw_lbl)
	var yaw_sl := HSlider.new(); yaw_sl.min_value = -180; yaw_sl.max_value = 180; yaw_sl.value = sun.rotation_degrees.y
	yaw_sl.value_changed.connect(func(v): sun.rotation_degrees.y = v)
	right_drawer_vbox.add_child(yaw_sl)

	var pitch_lbl := Label.new(); pitch_lbl.text = "Sun Elevation:"; right_drawer_vbox.add_child(pitch_lbl)
	var pitch_sl := HSlider.new(); pitch_sl.min_value = -80; pitch_sl.max_value = -12; pitch_sl.value = sun.rotation_degrees.x
	pitch_sl.value_changed.connect(func(v): sun.rotation_degrees.x = v)
	right_drawer_vbox.add_child(pitch_sl)

	var slbl := Label.new()
	slbl.text = "ALL 47 OFFICIAL VALVE SKYBOXES:"
	slbl.add_theme_font_override("font", fonts["heading"])
	slbl.add_theme_font_size_override("font_size", 12)
	slbl.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	right_drawer_vbox.add_child(slbl)

	for sky in core.list_skyboxes():
		var b := Button.new()
		b.text = sky
		HudWidgets.style_tf2_button(b, fonts["body"], 11, active_sky == sky)
		var sk: String = sky
		b.pressed.connect(func():
			active_sky = sk
			doc.set_skyname(sk)
			we.environment.sky = assets.get_sky(sk)
			audio.play("click")
			_open_sky_sun_drawer()
		)
		right_drawer_vbox.add_child(b)

func _open_coach_drawer() -> void:
	_clear_drawer("TF2 MAP COACH DIAGNOSTICS")
	var rep: Dictionary = Tf2CatalogScript.analyze_map(doc)
	coach_btn.text = "Coach (%s)" % rep["grade"]

	var summary := Label.new()
	summary.text = "Grade: %s\nSealed: %s | Solids: %d | Entities: %d\nSpawns: RED %d / BLU %d\nHealth Kits: %d | Ammo Packs: %d\nSpawn-to-Mid Walk:\n  Heavy: %.1fs | Scout: %.1fs\nLongest Span: ~%du" % [
		rep["grade"], "YES" if rep["sealed"] else "NO (Leak Risk!)",
		rep["solids"], rep["entities"], rep["red_spawns"], rep["blu_spawns"],
		rep["health_kits"], rep["ammo_packs"],
		rep["walk_time_heavy_s"], rep["walk_time_scout_s"], rep["longest_span_u"]
	]
	summary.add_theme_font_override("font", fonts["body"])
	summary.add_theme_font_size_override("font_size", 12)
	summary.add_theme_color_override("font_color", HudWidgets.COL_TX)
	right_drawer_vbox.add_child(summary)

	for w in rep["warnings"]:
		var wl := Label.new()
		wl.text = "! " + str(w)
		wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wl.add_theme_color_override("font_color", HudWidgets.COL_ACC)
		wl.add_theme_font_size_override("font_size", 12)
		right_drawer_vbox.add_child(wl)

func _open_compile_drawer() -> void:
	_clear_drawer("COMPILE TO REAL TF2 (.BSP)")
	var paths: Dictionary = compile_ctrl.detect_paths()
	var plbl := Label.new()
	plbl.text = "Valve Compilers: " + ("READY (" + str(paths["bin_dir"]) + ")" if paths.get("valid", false) else "Not Found")
	plbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plbl.add_theme_font_size_override("font_size", 11)
	right_drawer_vbox.add_child(plbl)

	var fast_b := Button.new()
	fast_b.text = "Fast Compile (vbsp + vvis + vrad)"
	HudWidgets.style_tf2_button(fast_b, fonts["heading"], 12, true)
	fast_b.pressed.connect(func(): _run_compile(true, true, true, false))
	right_drawer_vbox.add_child(fast_b)

	var quick_b := Button.new()
	quick_b.text = "Quick Geometry Check (vbsp only)"
	HudWidgets.style_tf2_button(quick_b, fonts["body"], 12)
	quick_b.pressed.connect(func(): _run_compile(true, false, false, false))
	right_drawer_vbox.add_child(quick_b)

	var play_tf2_b := Button.new()
	play_tf2_b.text = "Compile & Launch in Real TF2!"
	HudWidgets.style_tf2_button(play_tf2_b, fonts["heading"], 12, false, 2)
	play_tf2_b.pressed.connect(func(): _run_compile(true, true, true, true))
	right_drawer_vbox.add_child(play_tf2_b)

	var seal_b := Button.new()
	seal_b.text = "1-Click Auto-Seal Skybox"
	HudWidgets.style_tf2_button(seal_b, fonts["body"], 12)
	seal_b.pressed.connect(_do_auto_seal)
	right_drawer_vbox.add_child(seal_b)

# ==============================================================================
# MAP LOADING, SAVING, COMPILING & 3D MODEL IMPORTING
# ==============================================================================
func _load_gamemode(mode_id: String, biome_override: String = "", show_toast: bool = true) -> void:
	_clear_official_bsp()
	var meta: Dictionary = Tf2GamemodesScript.build_gamemode_template(doc, mode_id, biome_override)
	active_biome = meta["biome"]
	active_sky = meta["sky"]
	_apply_environment_from_biome(active_biome)
	map_sync.clear_all()
	map_sync.sync_all()
	ent_vis.sync_all()
	map_title_lbl.text = "| " + str(meta["map_name"])
	if show_toast:
		_toast("Created %s starter map — sealed & ready to edit or F5 playtest!" % mode_id.to_upper())

func _load_official_bsp(map_name: String) -> void:
	_clear_official_bsp()
	map_sync.clear_all()
	for ch in ent_vis.ents_root.get_children():
		ch.queue_free()

	var res: Dictionary = bsp_loader.load_bsp_into(map_name, bsp_root)
	if not res.get("ok", false):
		_toast("Could not load %s: %s" % [map_name, str(res.get("error", ""))])
		return

	viewing_bsp = true
	current_bsp_name = map_name
	active_sky = str(res.get("skyname", "sky_badlands_01"))
	we.environment.sky = assets.get_sky(active_sky)
	current_bsp_spawn = res.get("spawn_pos", Vector3(0, 2, 0))
	current_bsp_yaw = float(res.get("spawn_yaw", 0.0))
	map_title_lbl.text = "| [OFFICIAL] " + map_name
	cam_pos = current_bsp_spawn + Vector3(12, 10, 12)
	_apply_editor_cam()
	_toast("Loaded official %s (%d props, %.2fs) — press F5 to walk inside!" % [
		map_name, int(res.get("prop_count", 0)), float(res.get("load_ms", 0.0)) / 1000.0
	])

func _clear_official_bsp() -> void:
	viewing_bsp = false
	current_bsp_name = ""
	for ch in bsp_root.get_children():
		ch.queue_free()
	for ch in imported_props_root.get_children():
		ch.queue_free()

func _apply_biome(bkey: String) -> void:
	active_biome = bkey
	var b: Dictionary = Tf2GamemodesScript.get_biome(bkey)
	active_sky = b["sky"]
	doc.set_skyname(active_sky)
	doc.apply_theme_materials(b["floor"], b["wall"], b["roof"])
	doc.record_undo("Apply %s Biome" % b["name"])
	_apply_environment_from_biome(bkey)
	map_sync.sync_all()
	_toast("Applied %s biome & %s skybox!" % [b["name"], active_sky])

func _apply_environment_from_biome(bkey: String) -> void:
	var b: Dictionary = Tf2GamemodesScript.get_biome(bkey)
	we.environment.sky = assets.get_sky(b["sky"])
	sun.light_color = b["sun_color"]
	sun.rotation_degrees = b["sun_angles"]

func _save_current_vmf() -> String:
	DirAccess.make_dir_recursive_absolute(REPO_ROOT + "/godot/maps")
	var mname: String = doc.get_map_name()
	if mname.is_empty():
		mname = "pb_untitled"
	var path := REPO_ROOT + "/godot/maps/" + mname + ".vmf"
	var r: Dictionary = doc.save_vmf(path)
	if r.get("ok", false):
		_toast("Saved " + path.get_file())
		return path
	_toast("Save failed: " + str(r.get("error", "")))
	return ""

func _do_undo() -> void:
	if doc.undo():
		map_sync.sync_all()
		ent_vis.sync_all()
		_toast("Undo")

func _do_redo() -> void:
	if doc.redo():
		map_sync.sync_all()
		ent_vis.sync_all()
		_toast("Redo")

func _do_auto_seal() -> void:
	doc.auto_seal_skybox()
	doc.record_undo("Auto-Seal Skybox")
	compile_ctrl.clear_leak_laser()
	map_sync.sync_all()
	_toast("Map sealed cleanly with invisible TOOLSSKYBOX shell!")

func _run_compile(fast: bool, vvis: bool, vrad: bool, launch_tf2: bool) -> void:
	var vmf := _save_current_vmf()
	if vmf.is_empty():
		return
	var ok: bool = compile_ctrl.start_compile(vmf, fast, vvis, vrad, launch_tf2, doc.get_map_name())
	if ok:
		_toast("Compiling %s with Valve vbsp..." % doc.get_map_name())

func _on_compile_status(st: Dictionary) -> void:
	_toast("Compiling [%s] %.1fs..." % [str(st.get("stage", "")), float(st.get("elapsed", 0.0))])

func _on_compile_finished(st: Dictionary) -> void:
	var leak: String = str(st.get("leak_file", ""))
	if not leak.is_empty():
		_toast("LEAK DETECTED! Red 3D Leak Laser drawn — click 'Seal' to fix!")
	elif st.get("succeeded", false):
		audio.play("success", -8.0)
		_toast("Compile SUCCEEDED (%.1fs) — 0 leaks!" % float(st.get("elapsed", 0.0)))
	else:
		_toast("Compile failed in stage: " + str(st.get("stage", "")))

func _open_file_dialog(kind: String) -> void:
	file_dialog.set_meta("kind", kind)
	if kind == "vmf":
		file_dialog.title = "Open Valve Map File (.vmf)"
		file_dialog.filters = PackedStringArray(["*.vmf ; Valve Map Files"])
	else:
		file_dialog.title = "Import 3D Model (.obj, .glb, .gltf)"
		file_dialog.filters = PackedStringArray(["*.obj, *.glb, *.gltf ; 3D Models"])
	file_dialog.popup_centered()

func _on_file_selected(path: String) -> void:
	var kind: String = str(file_dialog.get_meta("kind", "model"))
	if kind == "vmf":
		_clear_official_bsp()
		var r: Dictionary = doc.load_vmf(path)
		if r.get("ok", false):
			active_sky = doc.get_skyname()
			we.environment.sky = assets.get_sky(active_sky)
			map_sync.clear_all()
			map_sync.sync_all()
			ent_vis.sync_all()
			map_title_lbl.text = "| " + doc.get_map_name()
			_show_welcome_hub(false)
			_toast("Opened " + path.get_file())
	else:
		_import_3d_model_file(path)

func _import_3d_model_file(path: String) -> void:
	var imp: Dictionary = ModelImporterScript.import_model(path, 2.5, 1.0)
	if not imp.get("ok", false):
		_toast("Import error: " + str(imp.get("error", "")))
		return
	var node: Node3D = imp["node"]
	var pos := hover_pos if hover_valid else Vector3(0, 0, 0)
	node.position = pos
	imported_props_root.add_child(node)
	# Also export Valve .QC + .SMD automatically into godot/maps/exported_qc/!
	var qc_res: Dictionary = ModelImporterScript.export_tf2_qc_smd(
		REPO_ROOT + "/godot/maps/exported_qc", imp["name"], imp["mesh"], float(imp["scale"])
	)
	audio.play("success", -10.0)
	_toast("Imported %s (%.0fu tall) + exported Valve .QC/.SMD!" % [imp["name"], (imp["size_u"] as Vector3).y])

func _cycle_symmetry() -> void:
	symmetry = (symmetry + 1) % 3
	sym_plane.visible = (symmetry != SymmetryMode.OFF)
	var names := ["Sym: Off", "Sym: Mirror", "Sym: 180°"]
	sym_btn.text = names[symmetry]
	_toast("Symmetry Mode: " + names[symmetry])

func _toggle_2d_view() -> void:
	top_down_2d = not top_down_2d
	if top_down_2d:
		editor_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		editor_cam.size = 56.0
		editor_cam.look_at_from_position(Vector3(cam_pos.x, 80.0, cam_pos.z), Vector3(cam_pos.x, 0.0, cam_pos.z), Vector3(0, 0, -1))
	else:
		editor_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		_apply_editor_cam()

# ==============================================================================
# F5 PLAYTEST TRANSITION
# ==============================================================================
func _enter_playtest() -> void:
	var sp := Vector3(0, 1.5, 0)
	var yaw := 0.0
	var ents: Array = []
	if viewing_bsp:
		sp = current_bsp_spawn
		yaw = current_bsp_yaw
	else:
		ents = doc.get_entities()
		for e in ents:
			if str(e["classname"]) == "info_player_teamspawn":
				sp = e["pos"]
				# Face toward arena center (0, 0) so player immediately looks out the doorway!
				var to_mid := Vector2(-sp.x, -sp.z)
				yaw = rad_to_deg(atan2(-to_mid.x, -to_mid.y))
				break
	editor_cam.current = false
	player.spawn_at(sp, yaw, ents)
	player.set_active(true)
	playtest_hud.visible = true
	sym_plane.visible = false
	ghost_mesh.visible = false
	brush_ring.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _exit_playtest() -> void:
	player.set_active(false)
	editor_cam.current = true
	playtest_hud.visible = false
	sym_plane.visible = (symmetry != SymmetryMode.OFF)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ==============================================================================
# 3D INTERACTION, PLACEMENT, SCULPTING & INPUT
# ==============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if welcome_panel.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_show_welcome_hub(false)
		return

	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_F5:
				set_stage(Stage.BUILD if stage == Stage.PLAYTEST else Stage.PLAYTEST)
				return
			if event.keycode == KEY_ESCAPE and stage == Stage.PLAYTEST:
				set_stage(Stage.BUILD)
				return
			if stage == Stage.PLAYTEST:
				player.handle_key_press(event.keycode)
				return
			if event.keycode == KEY_Q:
				pie_wheel.open_at(get_viewport().get_mouse_position())
				return
			if event.keycode == KEY_L:
				_select_tool("wires")
			elif event.keycode == KEY_Z and event.ctrl_pressed:
				_do_undo()
			elif event.keycode == KEY_Y and event.ctrl_pressed:
				_do_redo()
			elif event.keycode == KEY_S and event.ctrl_pressed:
				_save_current_vmf()
			elif event.keycode == KEY_SPACE:
				_toggle_2d_view()
		elif not event.pressed and event.keycode == KEY_Q:
			pie_wheel.close_and_commit()
			return

	if stage == Stage.PLAYTEST:
		if event is InputEventMouseMotion:
			player.handle_mouse_motion(event.relative)
		elif event is InputEventMouseButton:
			player.handle_mouse_button(event.button_index, event.pressed)
		return

	if event is InputEventMouseMotion:
		if pie_wheel.visible:
			pie_wheel.update_pointer(event.position)
			return
		if _rmb_looking and not top_down_2d:
			cam_yaw -= event.relative.x * 0.0035
			cam_pitch = clamp(cam_pitch - event.relative.y * 0.0035, -1.48, 1.48)
			_apply_editor_cam()
		elif _mmb_panning:
			var r := editor_cam.global_transform.basis.x
			var u := editor_cam.global_transform.basis.y
			cam_pos -= r * event.relative.x * 0.04 - u * event.relative.y * 0.04
			_apply_editor_cam()
		else:
			_update_hover(event.position)
			if _terrain_sculpting and active_tool == "terrain" and hover_valid:
				_do_terrain_sculpt_stroke()

	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_rmb_looking = event.pressed
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_mmb_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if top_down_2d:
				editor_cam.size = max(12.0, editor_cam.size * 0.88)
			else:
				cam_pos += (-editor_cam.global_transform.basis.z) * 2.2
				_apply_editor_cam()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if top_down_2d:
				editor_cam.size = min(180.0, editor_cam.size * 1.12)
			else:
				cam_pos -= (-editor_cam.global_transform.basis.z) * 2.2
				_apply_editor_cam()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if active_tool == "terrain":
				_terrain_sculpting = event.pressed
				if event.pressed and hover_valid:
					_do_terrain_sculpt_stroke()
				elif not event.pressed:
					doc.record_undo("Sculpt Terrain")
			elif event.pressed:
				_handle_left_click(event.position)

func _handle_left_click(screen_pos: Vector2) -> void:
	if viewing_bsp:
		_toast("Viewing official %s — press F5 to walk inside, or click Hub to start editing!" % current_bsp_name)
		return
	var ro := editor_cam.project_ray_origin(screen_pos)
	var rd := editor_cam.project_ray_normal(screen_pos)

	if active_tool == "select":
		var rc: Dictionary = doc.raycast_face(ro, rd)
		if rc.get("hit", false):
			map_sync.set_selection(int(rc["solid_idx"]), int(rc["face_idx"]))
			audio.play("click")
		else:
			map_sync.set_selection(-1)
		return

	if active_tool == "paint":
		var rc: Dictionary = doc.raycast_face(ro, rd)
		if rc.get("hit", false):
			doc.set_face_material(int(rc["solid_idx"]), int(rc["face_idx"]), active_material)
			doc.record_undo("Paint Face")
			map_sync.sync_solid(int(rc["solid_idx"]))
			audio.play("place")
		return

	if hover_valid:
		_place_tool_at(hover_pos)

func _place_tool_at(pos: Vector3) -> void:
	var b: Dictionary = Tf2GamemodesScript.get_biome(active_biome)
	var created_solids: Array[int] = []

	if stage == Stage.BUILD:
		match active_tool:
			"floor":
				created_solids.append(doc.add_box(pos + Vector3(-4, -0.5, -4), pos + Vector3(4, 0, 4), b["floor"]))
			"wall":
				created_solids.append(doc.add_box(pos + Vector3(-4, 0, -0.5), pos + Vector3(4, 4.5, 0.5), b["wall"]))
			"building":
				var ids: PackedInt32Array = doc.add_building(
					pos + Vector3(-4, 0, -4), pos + Vector3(4, 0, 4),
					bld_floors, bld_roof_style, b["wall"], b["accent"], b["roof"], bld_door_side
				)
				for i in ids: created_solids.append(i)
			"ramp":
				created_solids.append(doc.add_ramp(pos + Vector3(-2, 0, -2), pos + Vector3(2, 2.5, 2), 0, b["accent"]))
			"stairs":
				var ids: PackedInt32Array = doc.add_stairs(pos + Vector3(-2, 0, -2), pos + Vector3(2, 2.5, 2), 0, 6, b["accent"])
				for i in ids: created_solids.append(i)
			"arch":
				var ids: PackedInt32Array = doc.add_arch(pos, 6.0, 1.5, 5.0, 5, b["wall"])
				for i in ids: created_solids.append(i)
			"carve":
				var n: int = doc.auto_carve_opening(pos + Vector3(-1.75, 0, -1.5), pos + Vector3(1.75, 3.5, 1.5), b["wall"])
				if n > 0:
					audio.play("carve")
					_toast("Carved clean 112u TF2 doorway!")
		if symmetry != SymmetryMode.OFF:
			var rot180 := (symmetry == SymmetryMode.ROT_180)
			for sid in created_solids:
				if sid >= 0:
					doc.mirror_solid_x(sid, rot180)
		doc.record_undo("Place " + active_tool)
		map_sync.sync_all()
		audio.play("place")

	elif stage == Stage.GAMEPLAY:
		var preset := active_tool
		var team := 2
		if preset == "spawn_red":
			preset = "spawn"; team = 2
		elif preset == "spawn_blu":
			preset = "spawn"; team = 3
		Tf2GamemodesScript.stamp_preset(doc, preset, pos, team)
		if symmetry != SymmetryMode.OFF:
			var mpos := Vector3(-pos.x, pos.y, -pos.z if symmetry == SymmetryMode.ROT_180 else pos.z)
			Tf2GamemodesScript.stamp_preset(doc, preset, mpos, 3 if team == 2 else 2)
		doc.record_undo("Place " + active_tool)
		ent_vis.sync_all()
		audio.play("place")

	elif stage == Stage.STYLE:
		if active_tool == "place_prop":
			doc.add_point_entity("prop_static", pos, {"model": active_prop_mdl, "angles": "0 0 0", "solid": "6"})
			doc.record_undo("Place Prop")
			ent_vis.sync_all()
			audio.play("place")
		elif active_tool == "light":
			Tf2GamemodesScript.stamp_preset(doc, "light", pos, 2)
			doc.record_undo("Place Light")
			ent_vis.sync_all()
			audio.play("place")

func _do_terrain_sculpt_stroke() -> void:
	var n: int = doc.sculpt_terrain(hover_pos, terrain_radius_m, terrain_strength_m * 0.18, terrain_mode)
	if n > 0:
		map_sync.sync_all()

func _update_hover(screen_pos: Vector2) -> void:
	var ro := editor_cam.project_ray_origin(screen_pos)
	var rd := editor_cam.project_ray_normal(screen_pos)
	var hit_p := Vector3.ZERO
	hover_valid = false

	if not viewing_bsp:
		var rc: Dictionary = doc.raycast_face(ro, rd)
		if rc.get("hit", false):
			hit_p = rc["hit_pos"]
			hover_valid = true
	if not hover_valid and abs(rd.y) > 0.001:
		var t := -ro.y / rd.y
		if t > 0.1 and t < 350.0:
			hit_p = ro + rd * t
			hover_valid = true

	if hover_valid:
		hover_pos = Vector3(snappedf(hit_p.x, grid_m), snappedf(hit_p.y, 0.5), snappedf(hit_p.z, grid_m))
		if active_tool == "terrain":
			ghost_mesh.visible = false
			brush_ring.visible = true
			brush_ring.position = hover_pos + Vector3(0, 0.15, 0)
			brush_ring.scale = Vector3(terrain_radius_m, 1.0, terrain_radius_m)
		elif stage == Stage.BUILD and active_tool in ["floor", "wall", "building", "ramp", "stairs", "arch", "carve"]:
			brush_ring.visible = false
			ghost_mesh.visible = true
			var sz := Vector3(8, 0.5, 8)
			if active_tool == "wall": sz = Vector3(8, 4.5, 1)
			elif active_tool == "building": sz = Vector3(8, bld_floors * 4.5, 8)
			elif active_tool == "ramp" or active_tool == "stairs": sz = Vector3(4, 2.5, 4)
			elif active_tool == "arch": sz = Vector3(6, 5.0, 1.5)
			elif active_tool == "carve": sz = Vector3(3.5, 3.5, 3.0)
			(ghost_mesh.mesh as BoxMesh).size = sz
			ghost_mesh.position = hover_pos + Vector3(0, sz.y * 0.5, 0)
		else:
			ghost_mesh.visible = false
			brush_ring.visible = false
	else:
		ghost_mesh.visible = false
		brush_ring.visible = false
	overlay_2d.queue_redraw()

func _on_pie_action(aid: String) -> void:
	audio.play("click")
	match aid:
		"box": set_stage(Stage.BUILD); _select_tool("floor")
		"building": set_stage(Stage.BUILD); _select_tool("building")
		"ramp": set_stage(Stage.BUILD); _select_tool("ramp")
		"stairs": set_stage(Stage.BUILD); _select_tool("stairs")
		"carve": set_stage(Stage.BUILD); _select_tool("carve")
		"terrain": set_stage(Stage.BUILD); _select_tool("terrain")
		"mirror": _cycle_symmetry()
		"playtest": set_stage(Stage.PLAYTEST)

func _process(delta: float) -> void:
	# Smooth WASD fly camera in Editor mode (while holding RMB or anytime in 3D!)
	if stage != Stage.PLAYTEST and not welcome_panel.visible:
		var spd := 22.0 * (2.2 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		var mv := Vector3.ZERO
		var fwd := -editor_cam.global_transform.basis.z
		var right := editor_cam.global_transform.basis.x
		if Input.is_key_pressed(KEY_W): mv += fwd
		if Input.is_key_pressed(KEY_S): mv -= fwd
		if Input.is_key_pressed(KEY_D): mv += right
		if Input.is_key_pressed(KEY_A): mv -= right
		if Input.is_key_pressed(KEY_E): mv += Vector3.UP
		if Input.is_key_pressed(KEY_C): mv -= Vector3.UP
		if mv.length_squared() > 0.001:
			cam_pos += mv.normalized() * spd * delta
			_apply_editor_cam()

	if stage == Stage.PLAYTEST:
		var t: Dictionary = player.get_telemetry()
		var sl_txt := " | Sightline: %du%s" % [t["sightline_u"], " [LONG!]" if t["sightline_warn"] else ""]
		playtest_lbl.text = "%s (%d/%d HP) | %d u/s | Jump: %du | Time: %.1fs%s | ESC: Exit" % [
			t["class_name"], t["hp"], t["max_hp"], t["speed_u"], t["jump_height_u"], t["run_time_s"], sl_txt
		]
		overlay_2d.queue_redraw()

	_step_cli_shots()

func _apply_editor_cam() -> void:
	if top_down_2d:
		editor_cam.look_at_from_position(Vector3(cam_pos.x, 80.0, cam_pos.z), Vector3(cam_pos.x, 0.0, cam_pos.z), Vector3(0, 0, -1))
	else:
		editor_cam.position = cam_pos
		editor_cam.rotation = Vector3(cam_pitch, cam_yaw, 0.0)

func draw_viewport_2d_overlay(canvas: Control) -> void:
	var vp := canvas.size
	if stage == Stage.PLAYTEST:
		var c := vp * 0.5
		if player.scoped:
			# Authentic TF2 Sniper Scope Overlay with outer mask!
			var rad: float = min(vp.x, vp.y) * 0.42
			canvas.draw_arc(c, rad + 220.0, 0, TAU, 72, Color(0.03, 0.03, 0.03, 0.96), 440.0)
			canvas.draw_arc(c, rad, 0, TAU, 72, Color(0.14, 0.12, 0.10, 1.0), 4.0)
			canvas.draw_line(Vector2(c.x - rad, c.y), Vector2(c.x + rad, c.y), Color(0.08, 0.08, 0.08, 0.90), 1.5)
			canvas.draw_line(Vector2(c.x, c.y - rad), Vector2(c.x, c.y + rad), Color(0.08, 0.08, 0.08, 0.90), 1.5)
			canvas.draw_circle(c, 3.5, HudWidgets.COL_RED)
		else:
			canvas.draw_line(c - Vector2(8, 0), c + Vector2(8, 0), Color(1, 0.96, 0.86, 0.9), 2.0)
			canvas.draw_line(c - Vector2(0, 8), c + Vector2(0, 8), Color(1, 0.96, 0.86, 0.9), 2.0)
		return

	# Live Jump-Threshold Ruler Callout next to Ghost Block!
	if ghost_mesh.visible and not welcome_panel.visible:
		var sz := (ghost_mesh.mesh as BoxMesh).size
		var h_u := int(round(sz.y * UPM))
		var callout := HudWidgets.jump_threshold_callout(h_u)
		var top_world := ghost_mesh.position + Vector3(0, sz.y * 0.5 + 0.5, 0)
		if not editor_cam.is_position_behind(top_world):
			var sp := editor_cam.unproject_position(top_world)
			var txt := "%dx%dx%du — %s" % [int(sz.x * UPM), int(sz.z * UPM), h_u, callout["text"]]
			var f: Font = fonts["heading"]
			var tsz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			var r := Rect2(sp - Vector2(tsz.x * 0.5 + 8, 22), Vector2(tsz.x + 16, 22))
			canvas.draw_rect(r, HudWidgets.COL_BG_HUD, true)
			canvas.draw_rect(r, callout["color"], false, 1.5)
			canvas.draw_string(f, sp - Vector2(tsz.x * 0.5, 7), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, callout["color"])

func _toast(msg: String) -> void:
	status_toast.text = msg
	status_toast.visible = true

# ==============================================================================
# CLI SCREENSHOT AUTOMATION HOOK (for headless/GPU visual verification!)
# ==============================================================================
func _parse_cli_shots() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--shot" and i + 1 < args.size():
			var spec := args[i + 1]
			var colon := spec.find(":")
			if colon > 0:
				_auto_shots.append({"mode": spec.substr(0, colon), "out": spec.substr(colon + 1)})
	if not _auto_shots.is_empty():
		_setup_auto_shot(0)

func _setup_auto_shot(idx: int) -> void:
	var sh: Dictionary = _auto_shots[idx]
	var mode: String = sh["mode"]
	_auto_shot_frames = 0
	match mode:
		"welcome":
			_show_welcome_hub(true)
		"build":
			_show_welcome_hub(false)
			set_stage(Stage.BUILD)
			_select_tool("building")
			symmetry = SymmetryMode.ROT_180
			sym_plane.visible = true
			sym_btn.text = "Sym: 180°"
			cam_pos = Vector3(24, 18, 28); cam_yaw = 0.65; cam_pitch = -0.45
			_apply_editor_cam()
			hover_pos = Vector3(8, 0, -4); hover_valid = true
			_update_hover(Vector2(640, 360))
		"radial":
			_show_welcome_hub(false)
			set_stage(Stage.BUILD)
			right_drawer.visible = false
			pie_wheel.open_at(Vector2(640, 360))
			pie_wheel.update_pointer(Vector2(720, 300))
		"gameplay":
			_show_welcome_hub(false)
			pie_wheel.visible = false
			_load_gamemode("mvm", "mvm", false)
			set_stage(Stage.GAMEPLAY)
			cam_pos = Vector3(-16, 17, 26); cam_yaw = -0.58; cam_pitch = -0.46
			_apply_editor_cam()
		"style":
			_show_welcome_hub(false)
			_load_gamemode("koth", "alpine", false)
			set_stage(Stage.STYLE)
			_open_materials_drawer()
			cam_pos = Vector3(22, 16, 26); cam_yaw = 0.65; cam_pitch = -0.42
			_apply_editor_cam()
		"playtest":
			_show_welcome_hub(false)
			right_drawer.visible = false
			set_stage(Stage.PLAYTEST)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			player.set_tf2_class(3) # Sniper scope demo!
			player.handle_mouse_button(MOUSE_BUTTON_RIGHT, true)

func _step_cli_shots() -> void:
	if _auto_shots.is_empty():
		return
	_auto_shot_frames += 1
	if _auto_shot_frames == 10:
		var sh: Dictionary = _auto_shots[_auto_shot_idx]
		get_viewport().get_texture().get_image().save_png(sh["out"])
		print("Saved App Shot [%s]: %s" % [sh["mode"], sh["out"]])
		_auto_shot_idx += 1
		if _auto_shot_idx >= _auto_shots.size():
			get_tree().quit(0)
		else:
			_setup_auto_shot(_auto_shot_idx)
