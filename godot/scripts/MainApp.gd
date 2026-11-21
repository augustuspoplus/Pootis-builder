extends Node3D

## Pootis Builder 2.0 â€” Complete Valve-Grade TF2 Map Creator (Godot 4 Forward+ + Native C++20 GDExtension)
## Unites ALL 5 Overhaul Phases:
##   1. Responsive HiDPI-Aware Floating TF2 HUD + Extensive 7-Tab Settings Menu (AppSettings + SettingsModal)
##   2. Real 3D TF2 VPK Game-Asset Icons (Tf2IconCache) + True Drag-and-Drop onto 3D Viewport
##   3. Complete TF2 Asset Catalog: ALL 7,000+ .mdl Models, ALL 29,000+ VPK Materials, ALL 450+ TF2+ABS FGD Entities
##   4. Engine-Overhauled Building Tools: Drag-to-Draw Box/Floor, Point-to-Point Chained Walls, Vertex Manipulation (Shift+V),
##      Vertical Rocky Cliff Displacements, Paint Alpha Blending, Auto-Sew, Subdivide, Make Hollow, QuickHide (H/U), Alt+P Check
##   5. Full Official .bsp Dynamic Props (Payload Cart, Cap Points, Pickups) + Interactive Sliding func_door in F5 Playtest!

const Tf2AssetsScript        = preload("res://scripts/core/Tf2Assets.gd")
const Tf2BspLoaderScript     = preload("res://scripts/core/Tf2BspLoader.gd")
const Tf2GamemodesScript     = preload("res://scripts/core/Tf2Gamemodes.gd")
const Tf2AudioScript         = preload("res://scripts/core/Tf2Audio.gd")
const Tf2CatalogScript       = preload("res://scripts/core/Tf2Catalog.gd")
const AppSettingsScript      = preload("res://scripts/core/AppSettings.gd")
const Tf2IconCacheScript     = preload("res://scripts/core/Tf2IconCache.gd")
const Tf2DoorCtrlScript      = preload("res://scripts/core/Tf2DoorController.gd")
const MapSceneSyncScript     = preload("res://scripts/editor/MapSceneSync.gd")
const EntityVisualsScript    = preload("res://scripts/editor/EntityVisuals.gd")
const CompileCtrlScript      = preload("res://scripts/editor/CompileController.gd")
const ModelImporterScript    = preload("res://scripts/editor/ModelImporter.gd")
const SandboxPlayerScript    = preload("res://scripts/playtest/Tf2SandboxPlayer.gd")
const HudWidgets             = preload("res://scripts/ui/Tf2HudWidgets.gd")
const SettingsModalScript    = preload("res://scripts/ui/SettingsModal.gd")
const Blueprint2DScript      = preload("res://scripts/ui/Blueprint2DView.gd")
const EditorDrawersScript    = preload("res://scripts/ui/EditorDrawers.gd")

const UPM := 32.0
const GRID_STEPS: Array[int] = [8, 16, 32, 64, 128]

enum Stage { BUILD, GAMEPLAY, STYLE, PLAYTEST }
enum SymmetryMode { OFF, MIRROR_X, ROT_180 }

var repo_root: String = ""
# Core native & scene systems
var core: Object
var doc: Object
var settings: RefCounted
var assets: RefCounted
var bsp_loader: RefCounted
var icon_cache: Node
var door_ctrl: Node
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
var _prev_stage: int = Stage.BUILD
var active_tool: String = "select"
var active_material: String = "WOOD/WOOD_WALL002"
var active_prop_mdl: String = "models/props_2fort/miningcrate001.mdl"
var active_fgd_entity: String = "info_player_teamspawn"
var active_biome: String = "badlands"
var active_sky: String = "sky_badlands_01"
var active_gamemode: String = "koth"
var _show_all_mode_ents: bool = false
var stairs_open_back: bool = false
var symmetry: int = SymmetryMode.OFF
var top_down_2d: bool = false
var grid_idx: int = 2
var grid_m: float = 1.0 # 32u default
var hover_pos: Vector3 = Vector3.ZERO
var hover_valid: bool = false
var viewing_bsp: bool = false
var current_bsp_name: String = ""
var current_bsp_spawn: Vector3 = Vector3(0, 2, 0)
var current_bsp_yaw: float = 0.0

# Selection, Direct 3D Manipulation & Interactive Drawing State
var selected_solid: int = -1
var selected_solids: Array[int] = []
var selected_face: int = -1
var selected_entity: int = -1
var _dragging_face: bool = false
var _drag_solid: int = -1
var _drag_normal: Vector3 = Vector3.ZERO
var _drag_anchor: Vector3 = Vector3.ZERO
var _drag_accum: float = 0.0
var _dragging_move: bool = false
var _move_last_pos: Vector3 = Vector3.ZERO
var _dragging_gizmo: bool = false
var _gizmo_axis: Vector3 = Vector3.ZERO
var _gizmo_origin: Vector3 = Vector3.ZERO
var _gizmo_accum: float = 0.0
var _dragging_vertex: bool = false
var _drag_vert_idx: int = -1
var _drag_vert_last: Vector3 = Vector3.ZERO
var _drag_vert_pos: Vector3 = Vector3.ZERO

# Interactive Drag-to-Draw Box & Point-to-Point Wall Chain State!
var _drawing_box: bool = false
var _box_start: Vector3 = Vector3.ZERO
var box_height_m: float = 0.5   # 16u slab default (adjustable in Wall/Box drawer!)
var _wall_chain_active: bool = false
var _wall_chain_start: Vector3 = Vector3.ZERO
var wall_height_m: float = 4.5  # 144u standard TF2 story height
var wall_thick_m: float = 0.75  # 24u wall thickness
var _clip_keep_mode: int = 0

# Building Wizard, Terrain Brush, Cliff Controls & Browser Search State
var bld_floors: int = 2
var bld_roof_style: int = 1
var bld_door_side: int = 2
var cliff_facing: int = 0       # 0=South, 1=North, 2=East, 3=West
var cliff_height_m: float = 9.0 # 288u default canyon cliff height
var cliff_power: int = 3        # Power-3 (9x9) Valve displacement grid
var terrain_mode: int = 0       # 0=Raise, 1=Lower, 2=Smooth, 3=Flatten, 4=Alpha+, 5=Alpha-, 6=Noise
var terrain_axis_mode: int = 0  # 0=Face Normal (cliffs!), 1=Up(Z), 2=East(X), 3=North(Y)
var terrain_radius_m: float = 4.5
var terrain_strength_m: float = 1.25
var _terrain_sculpting: bool = false
var _terrain_changed: bool = false
var _terrain_sync_accum: float = 0.0
var _autosave_slot: int = 0
var _mat_search_text: String = ""
var _mat_browse_all: bool = false
var _prop_search_text: String = ""
var _prop_browse_all: bool = false
var _prop_active_cat: String = ""
var _prop_favorites_only: bool = false
var _prop_favorites: Array[String] = []
var _dock_build_cat: String = "shapes"
var _dock_prop_cat: String = "winter"
var _dock_prop_page: int = 0
var _dock_ent_cat: String = "_mode"
var _dock_ent_page: int = 0
var prop_skin: int = 0          # 0=Neutral, 1=RED, 2=BLU
var prop_random_yaw: bool = false
var prop_snap_normal: bool = true
var prop_scale: float = 1.0
var prop_yaw_deg: float = 0.0
var _ent_search_text: String = ""
var _insp_tab: int = 0
var _prop_preview_mesh: MeshInstance3D = null
var _gizmo_root: Node3D = null
var _history_entries: Array[Dictionary] = []
var _history_idx: int = 0
var _history_drawer_open: bool = false
var _autosave_accum: float = 0.0

# Orbit / Fly camera state
var cam_yaw: float = -0.65
var cam_pitch: float = -0.46
var cam_pos: Vector3 = Vector3(24, 18, 28)
var _rmb_looking: bool = false
var _mmb_panning: bool = false

# UI References
var fonts: Dictionary = {}
var hud_layer: CanvasLayer
var overlay_2d: Control
var pie_wheel: Control
var welcome_panel: Control
var settings_modal: ColorRect
var top_bar: Control
var context_bar_wrap: CenterContainer
var context_bar: PanelContainer
var context_hbox: HBoxContainer
var left_rail_panel: PanelContainer
var tool_hover_card: PanelContainer
var tool_hover_title: Label
var tool_hover_key: Label
var tool_hover_desc: Label
var bottom_dock: Control
var selection_bar_wrap: CenterContainer
var selection_bar: PanelContainer
var selection_hbox: HBoxContainer
var right_drawer: PanelContainer
var right_drawer_vbox: VBoxContainer
var right_drawer_title: Label
var split_2d_panel: PanelContainer
var bp_top: Control
var bp_side: Control
var status_pill: PanelContainer
var status_lbl_top: Label
var status_lbl_bot: Label
var playtest_hud: Control
var playtest_lbl: Label
var toast_wrap: CenterContainer
var toast_panel: PanelContainer
var status_toast: Label
var _toast_ttl: float = 0.0
var map_title_lbl: Label
var undo_btn: Button
var redo_btn: Button
var history_btn: Button
var grid_btn: Button
var sym_btn: Button
var coach_btn: Button
var edit_only_top_nodes: Array[Control] = []
var stage_btns: Array[Button] = []
var dock_slot_map: Dictionary = {} # icon_key -> Array[RailSlot]
var file_dialog: FileDialog

# Screenshot automation state
var _auto_shots: Array = []
var _auto_shot_idx: int = 0
var _auto_shot_frames: int = 0

func _ready() -> void:
	_init_core_systems()
	_init_3d_world()
	_init_ui()

	settings.apply_runtime(self)
	_sync_grid_from_settings()
	_load_gamemode("koth", "badlands", false)
	_show_welcome_hub(true)
	_parse_cli_shots()

func _init_core_systems() -> void:
	repo_root = ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()
	settings = AppSettingsScript.new()
	settings.load_from_disk()

	core = ClassDB.instantiate("Tf2Core")
	core.mount_tf2(repo_root)
	assets = Tf2AssetsScript.new(core)
	bsp_loader = Tf2BspLoaderScript.new(core, assets)
	doc = ClassDB.instantiate("Tf2MapDoc")

	audio = Tf2AudioScript.new()
	audio.name = "Tf2Audio"
	add_child(audio)
	audio.setup(core)

	icon_cache = Tf2IconCacheScript.new()
	icon_cache.name = "Tf2IconCache"
	add_child(icon_cache)
	icon_cache.setup(assets, settings.icon_resolution)
	icon_cache.icon_ready.connect(_on_icon_ready)

	door_ctrl = Tf2DoorCtrlScript.new()
	door_ctrl.name = "Tf2DoorController"
	add_child(door_ctrl)
	door_ctrl.door_opened.connect(func(_n): if not settings.sfx_muted: audio.play("carve", -14.0))

	fonts = HudWidgets.load_fonts(core.get_tf2_dir())

func _init_3d_world() -> void:
	we = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = assets.get_sky(active_sky)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.68, 0.70, 0.76)
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_energy = 0.85
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
	ent_vis.door_ctrl = door_ctrl
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
	player.fired_rocket.connect(func(_o): if not settings.sfx_muted: audio.play("rocket", -10.0))
	player.exploded.connect(func(_p): if not settings.sfx_muted: audio.play("explode", -11.0))
	player.pickup_collected.connect(func(_k): if not settings.sfx_muted: audio.play("medkit", -8.0))

	editor_cam = Camera3D.new()
	editor_cam.fov = settings.camera_fov
	editor_cam.far = settings.back_clip_m
	editor_cam.current = true
	add_child(editor_cam)
	_apply_editor_cam()

	_create_editor_helpers()

func _create_editor_helpers() -> void:
	grid_floor = MeshInstance3D.new()
	var gim := ImmediateMesh.new()
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.vertex_color_use_as_albedo = true
	gim.surface_begin(Mesh.PRIMITIVE_LINES, gmat)
	for i in range(-48, 49, 2):
		var major := (i % 8 == 0)
		var c := Color(0.95, 0.72, 0.35, 0.22) if major else Color(0.8, 0.76, 0.70, 0.08)
		gim.surface_set_color(c)
		gim.surface_add_vertex(Vector3(i, -0.02, -48)); gim.surface_add_vertex(Vector3(i, -0.02, 48))
		gim.surface_set_color(c)
		gim.surface_add_vertex(Vector3(-48, -0.02, i)); gim.surface_add_vertex(Vector3(48, -0.02, i))
	gim.surface_end()
	grid_floor.mesh = gim
	add_child(grid_floor)

	sym_plane = MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(72.0, 22.0)
	sym_plane.mesh = pm; sym_plane.rotation_degrees = Vector3(0, 0, 90); sym_plane.position = Vector3(0, 10.0, 0)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.cull_mode = BaseMaterial3D.CULL_DISABLED; smat.albedo_color = Color(0.96, 0.64, 0.18, 0.14)
	sym_plane.material_override = smat; sym_plane.visible = false
	add_child(sym_plane)

	ghost_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(4, 1, 4)
	ghost_mesh.mesh = bm
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.albedo_color = Color(0.96, 0.65, 0.16, 0.28)
	ghost_mesh.material_override = gm; ghost_mesh.visible = false
	add_child(ghost_mesh)

	brush_ring = MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 0.94; tm.outer_radius = 1.0
	brush_ring.mesh = tm
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; bmat.albedo_color = Color(0.24, 0.92, 0.98, 0.92)
	brush_ring.material_override = bmat; brush_ring.visible = false
	add_child(brush_ring)

	# 3D RGB Transform Axis Gizmo (shown on selected solid or entity!)
	_gizmo_root = Node3D.new()
	_gizmo_root.name = "TransformGizmo3D"
	_gizmo_root.visible = false
	add_child(_gizmo_root)
	var axes := [
		{"dir": Vector3.RIGHT,   "rot": Vector3(0, 0, -90), "col": Color(0.96, 0.24, 0.22, 0.96)},
		{"dir": Vector3.UP,      "rot": Vector3(0, 0, 0),   "col": Color(0.24, 0.92, 0.36, 0.96)},
		{"dir": Vector3.BACK,    "rot": Vector3(90, 0, 0),  "col": Color(0.24, 0.56, 0.98, 0.96)},
	]
	for ax in axes:
		var amat := StandardMaterial3D.new()
		amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		amat.no_depth_test = true
		amat.render_priority = 10
		amat.albedo_color = ax["col"]
		var shaft := MeshInstance3D.new()
		var cm := CylinderMesh.new(); cm.top_radius = 0.045; cm.bottom_radius = 0.045; cm.height = 1.65
		shaft.mesh = cm; shaft.material_override = amat
		shaft.rotation_degrees = ax["rot"]
		shaft.position = (ax["dir"] as Vector3) * 0.85
		_gizmo_root.add_child(shaft)
		var tip := MeshInstance3D.new()
		var tm2 := CylinderMesh.new(); tm2.top_radius = 0.0; tm2.bottom_radius = 0.14; tm2.height = 0.40
		tip.mesh = tm2; tip.material_override = amat
		tip.rotation_degrees = ax["rot"]
		tip.position = (ax["dir"] as Vector3) * 1.85
		_gizmo_root.add_child(tip)
	var gdot := MeshInstance3D.new()
	var gs := SphereMesh.new(); gs.radius = 0.14; gs.height = 0.28
	gdot.mesh = gs
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; dmat.no_depth_test = true; dmat.render_priority = 11
	dmat.albedo_color = Color(0.98, 0.82, 0.32, 1.0)
	gdot.material_override = dmat
	_gizmo_root.add_child(gdot)

# ==============================================================================
# UI CONSTRUCTION (Expanded Current Floating TF2 HUD â€” 100% Responsive!)
# ==============================================================================
func _init_ui() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "Tf2HudLayer"
	add_child(hud_layer)

	overlay_2d = HudWidgets.ViewportOverlay.new(self)
	hud_layer.add_child(overlay_2d)

	var ui_theme: Theme = HudWidgets.create_global_theme(fonts)
	get_tree().root.theme = ui_theme

	_prop_favorites = Tf2CatalogScript.load_prop_favorites()

	_build_top_bar()
	_build_context_bar()
	_build_left_rail()
	_build_tool_hover_card()
	_build_toast_pill()
	_build_selection_bar()
	_build_bottom_dock()
	_build_status_pill()
	_build_right_drawer()
	_build_split_2d_pane()
	_build_playtest_hud()
	_build_welcome_hub()

	settings_modal = SettingsModalScript.new()
	settings_modal.setup(settings, fonts, core)
	settings_modal.settings_applied.connect(_on_settings_applied)
	settings_modal.rebuild_icons_requested.connect(func():
		icon_cache.icon_size = clampi(settings.icon_resolution, 96, 256)
		icon_cache.clear_disk_cache()
		_toast("Rebuilding real 3D TF2 VPK icon cache (%dpx)..." % icon_cache.icon_size)
	)
	hud_layer.add_child(settings_modal)

	# Apply global TF2 theme directly onto CanvasLayer control roots (CanvasLayer breaks Window.theme inheritance!)
	for ctrl in [top_bar, context_bar, left_rail_panel, tool_hover_card, bottom_dock, selection_bar, right_drawer, split_2d_panel, welcome_panel, settings_modal]:
		if ctrl is Control:
			(ctrl as Control).theme = ui_theme

	pie_wheel = HudWidgets.RadialPieWheel.new(fonts["heading"])
	pie_wheel.action_chosen.connect(_on_pie_action)
	hud_layer.add_child(pie_wheel)

	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.size = Vector2i(760, 500)
	file_dialog.file_selected.connect(_on_file_selected)
	hud_layer.add_child(file_dialog)

func _build_toast_pill() -> void:
	toast_wrap = CenterContainer.new()
	toast_wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	toast_wrap.offset_top = 100
	toast_wrap.offset_bottom = 136
	toast_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(toast_wrap)

	toast_panel = HudWidgets.HudFrame.new(HudWidgets.COL_ACC, 8.0, false)
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.visible = false
	toast_wrap.add_child(toast_panel)

	status_toast = Label.new()
	status_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_toast.add_theme_font_override("font", fonts["heading"])
	status_toast.add_theme_font_size_override("font_size", 12)
	status_toast.add_theme_color_override("font_color", HudWidgets.COL_TX)
	status_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.add_child(status_toast)

func _build_status_pill() -> void:
	# Compact 2-line bottom-left telemetry pill (never collides with centered dock!)
	status_pill = HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 8.0, true)
	status_pill.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	status_pill.offset_left = 12
	status_pill.offset_bottom = -12
	status_pill.offset_top = -56
	status_pill.offset_right = 235
	status_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(status_pill)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_pill.add_child(vb)

	status_lbl_top = Label.new()
	status_lbl_top.text = "XYZ: 0u, 0u, 0u"
	status_lbl_top.add_theme_font_override("font", fonts["mono"])
	status_lbl_top.add_theme_font_size_override("font_size", 10)
	status_lbl_top.add_theme_color_override("font_color", HudWidgets.COL_TX)
	vb.add_child(status_lbl_top)

	status_lbl_bot = Label.new()
	status_lbl_bot.text = "SEALED | 60 FPS | UI 100%"
	status_lbl_bot.add_theme_font_override("font", fonts["mono"])
	status_lbl_bot.add_theme_font_size_override("font_size", 10)
	status_lbl_bot.add_theme_color_override("font_color", HudWidgets.COL_GREEN)
	vb.add_child(status_lbl_bot)

func _build_context_bar() -> void:
	context_bar_wrap = CenterContainer.new()
	context_bar_wrap.set_anchors_preset(Control.PRESET_TOP_WIDE)
	context_bar_wrap.offset_top = 56
	context_bar_wrap.offset_bottom = 94
	context_bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(context_bar_wrap)

	context_bar = HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 8.0, false)
	context_bar.visible = false
	context_bar_wrap.add_child(context_bar)

	context_hbox = HBoxContainer.new()
	context_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	context_hbox.add_theme_constant_override("separation", 6)
	context_bar.add_child(context_hbox)

func _refresh_context_bar() -> void:
	if context_hbox == null:
		return
	for ch in context_hbox.get_children():
		ch.queue_free()
	if viewing_bsp or stage == Stage.PLAYTEST:
		context_bar.visible = false
		return

	var add_tag := func(txt: String) -> void:
		var l := Label.new()
		l.text = txt
		l.add_theme_font_override("font", fonts["heading"])
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", HudWidgets.COL_ACC)
		context_hbox.add_child(l)

	var add_chip := func(txt: String, act: bool, fn: Callable) -> void:
		var b := Button.new()
		b.text = txt
		HudWidgets.style_tf2_button(b, fonts["body"], 10, act)
		b.pressed.connect(func(): audio.play("click"); fn.call())
		context_hbox.add_child(b)

	if active_tool == "wall":
		context_bar.visible = true
		add_tag.call("WALL CHAIN")
		for th in [0.5, 0.75, 1.0, 2.0]:
			var tv: float = th
			add_chip.call("%du Thick" % int(round(tv * UPM)), absf(wall_thick_m - tv) < 0.05, func(): wall_thick_m = tv; _refresh_context_bar())
		for wh in [4.5, 6.0, 8.0]:
			var wv: float = wh
			add_chip.call("%du High" % int(round(wv * UPM)), absf(wall_height_m - wv) < 0.1, func(): wall_height_m = wv; _refresh_context_bar())
	elif active_tool == "floor":
		context_bar.visible = true
		add_tag.call("DRAG BOX")
		for bh in [0.5, 1.0, 2.0, 4.5, 8.0]:
			var bv: float = bh
			add_chip.call("%du High" % int(round(bv * UPM)), absf(box_height_m - bv) < 0.05, func(): box_height_m = bv; _refresh_context_bar())
		add_chip.call("Mat: " + active_material.get_file().left(14), false, func(): _open_materials_drawer())
	elif active_tool == "stairs":
		context_bar.visible = true
		add_tag.call("STAIRS STYLE")
		add_chip.call("Solid Concrete", not stairs_open_back, func(): stairs_open_back = false; _refresh_context_bar())
		add_chip.call("Open-Back Steel (Turbine)", stairs_open_back, func(): stairs_open_back = true; _refresh_context_bar())
		add_chip.call("Mat: " + active_material.get_file().left(14), false, func(): _open_materials_drawer())
	elif active_tool == "terrain":
		context_bar.visible = true
		add_tag.call("TERRAIN STUDIO")
		add_chip.call("Radius %du" % int(round(terrain_radius_m * UPM)), false, func(): terrain_radius_m = clampf(terrain_radius_m + 1.0, 1.5, 12.0) if terrain_radius_m < 10.0 else 2.5; _refresh_context_bar())
		add_chip.call("Push Out (Cliffs)" if terrain_axis_mode == 0 else "Up & Down (Ground)", true, func(): terrain_axis_mode = 1 if terrain_axis_mode == 0 else 0; _refresh_context_bar(); if right_drawer.visible: _open_terrain_studio())
		add_chip.call("Auto-Sew Seams", false, func(): var n: int = doc.sew_displacements(); _record_history("Sew"); map_sync.sync_all(); _toast("Auto-Sewed %d vertices!" % n))
	elif active_tool == "place_prop":
		context_bar.visible = true
		add_tag.call("PROP: " + active_prop_mdl.get_file().get_basename().to_upper())
		add_chip.call("Yaw %d° (R)" % int(prop_yaw_deg), false, func(): prop_yaw_deg = fmod(prop_yaw_deg + 90.0, 360.0); _refresh_context_bar())
		var sk_names := ["Neutral", "RED", "BLU"]
		add_chip.call("Skin: " + sk_names[clampi(prop_skin, 0, 2)], prop_skin > 0, func(): prop_skin = (prop_skin + 1) % 3; _refresh_context_bar())
		add_chip.call("Prop Boxes...", false, func(): _open_props_drawer())
	elif active_tool == "vertex":
		context_bar.visible = true
		add_tag.call("VERTEX EDIT")
		add_chip.call("Grid %du" % GRID_STEPS[grid_idx], false, func(): _step_grid(1, true); _refresh_context_bar())
		add_chip.call("Done (1)", true, func(): _select_tool("select"))
	else:
		context_bar.visible = false

func _build_tool_hover_card() -> void:
	tool_hover_card = HudWidgets.HudFrame.new(HudWidgets.COL_ACC, 9.0, true)
	tool_hover_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	tool_hover_card.offset_left = 78
	tool_hover_card.offset_top = 68
	tool_hover_card.custom_minimum_size = Vector2(236, 0)
	tool_hover_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tool_hover_card.visible = false
	hud_layer.add_child(tool_hover_card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tool_hover_card.add_child(vb)

	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 6)
	hr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(hr)

	tool_hover_title = Label.new()
	tool_hover_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tool_hover_title.add_theme_font_override("font", fonts["heading"])
	tool_hover_title.add_theme_font_size_override("font_size", 13)
	tool_hover_title.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	hr.add_child(tool_hover_title)

	tool_hover_key = Label.new()
	tool_hover_key.add_theme_font_override("font", fonts["mono"])
	tool_hover_key.add_theme_font_size_override("font_size", 10)
	tool_hover_key.add_theme_color_override("font_color", HudWidgets.COL_TX)
	hr.add_child(tool_hover_key)

	tool_hover_desc = Label.new()
	tool_hover_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tool_hover_desc.add_theme_font_override("font", fonts["body"])
	tool_hover_desc.add_theme_font_size_override("font_size", 11)
	tool_hover_desc.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	vb.add_child(tool_hover_desc)

func _build_left_rail() -> void:
	# Overhauled Left Icon Rail with crisp vector icons + hover tooltip cards!
	left_rail_panel = HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 10.0, true)
	left_rail_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left_rail_panel.offset_left = 12
	left_rail_panel.offset_top = 68
	hud_layer.add_child(left_rail_panel)
	_rebuild_left_rail()

func _rebuild_left_rail() -> void:
	for ch in left_rail_panel.get_children():
		ch.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	left_rail_panel.add_child(vb)

	# Sleek, non-duplicated 5-Tool Core Transform Rail (Move, Push/Pull, Rotate, Clip, Vertex!)
	var items := [
		{"id": "select",    "title": "Select & Move",    "key": "1",       "desc": "Pick solids/entities and drag the 3D RGB arrows to move cleanly on grid."},
		{"id": "push_pull", "title": "Push / Pull Face", "key": "2",       "desc": "Click & drag any face handle out or in like SketchUp/TrenchBroom."},
		{"id": "rotate",    "title": "Rotate 90°",       "key": "R",       "desc": "Rotate the selected brush, prop, or entity by 90° instantly."},
		{"id": "clip",      "title": "Clip / Slice",     "key": "Shift+X", "desc": "Slice selected brush cleanly along a plane to create angles & ramps."},
		{"id": "vertex",    "title": "Vertex Edit",      "key": "Shift+V", "desc": "Drag glowing corner handles (hold Shift for vertical up/down)."},
	]
	for idx in range(items.size()):
		var it: Dictionary = items[idx]
		var tid: String = it["id"]
		var is_act := (active_tool == tid) or (tid == "push_pull" and active_tool == "select" and selected_solid >= 0 and false)
		var b := Button.new()
		b.custom_minimum_size = Vector2(46, 44)
		HudWidgets.style_tf2_button(b, fonts["heading"], 10, is_act)

		var vic := HudWidgets.VectorToolIcon.new(tid, is_act, HudWidgets.COL_ACC)
		vic.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.add_child(vic)
		HudWidgets.attach_spring_anim(b, 1.09)

		var row_y: float = 68.0 + float(idx) * 50.0
		var t_title: String = it["title"]
		var t_key: String = "[" + str(it["key"]) + "]"
		var t_desc: String = it["desc"]
		b.mouse_entered.connect(func():
			if tool_hover_card != null:
				tool_hover_title.text = t_title
				tool_hover_key.text = t_key
				tool_hover_desc.text = t_desc
				tool_hover_card.offset_top = row_y
				tool_hover_card.visible = true
		)
		b.mouse_exited.connect(func():
			if tool_hover_card != null:
				tool_hover_card.visible = false
		)
		b.pressed.connect(func():
			audio.play("click")
			if tool_hover_card != null:
				tool_hover_card.visible = false
			if tid == "clip": _open_clip_drawer()
			elif tid == "rotate": _rotate_selection()
			elif tid == "push_pull": _select_tool("select"); _toast("Push / Pull Mode: Drag any yellow face arrow on the selected brush!")
			else: _select_tool(tid)
		)
		vb.add_child(b)

func _build_selection_bar() -> void:
	selection_bar_wrap = CenterContainer.new()
	selection_bar_wrap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	selection_bar_wrap.offset_top = -196
	selection_bar_wrap.offset_bottom = -152
	selection_bar_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(selection_bar_wrap)

	selection_bar = HudWidgets.HudFrame.new(HudWidgets.COL_CYAN, 8.0, true)
	selection_bar.visible = false
	selection_bar_wrap.add_child(selection_bar)

	selection_hbox = HBoxContainer.new()
	selection_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	selection_hbox.add_theme_constant_override("separation", 5)
	selection_bar.add_child(selection_hbox)

func _refresh_selection_bar() -> void:
	for ch in selection_hbox.get_children():
		ch.queue_free()
	if viewing_bsp or stage == Stage.PLAYTEST or (selected_solid < 0 and selected_entity < 0):
		selection_bar.visible = false
		return

	selection_bar.visible = true
	var tag := Label.new()
	tag.add_theme_font_override("font", fonts["heading"])
	tag.add_theme_font_size_override("font_size", 11)
	tag.add_theme_color_override("font_color", HudWidgets.COL_CYAN)

	if selected_solid >= 0:
		var info: Dictionary = doc.get_solid_info(selected_solid)
		var sz: Vector3 = (info.get("bounds_max", Vector3.ZERO) - info.get("bounds_min", Vector3.ZERO)) * UPM
		if selected_solids.size() > 1:
			tag.text = "%d SOLIDS SELECTED (Ctrl+Click)" % selected_solids.size()
		else:
			tag.text = "SOLID #%d (%dx%dx%du)" % [selected_solid, int(round(sz.x)), int(round(sz.z)), int(round(sz.y))]
		selection_hbox.add_child(tag)
		_add_sel_btn("+Pull", func(): _push_selected_top(grid_m))
		_add_sel_btn("-Push", func(): _push_selected_top(-grid_m))
		_add_sel_btn("Rot 90°", _rotate_selection)
		_add_sel_btn("Mirror BLU/RED", _mirror_selection_to_enemy, 3)
		_add_sel_btn("Clip", _open_clip_drawer)
		_add_sel_btn("Verts", func(): _select_tool("vertex"))
		_add_sel_btn("Hollow", _do_hollow_selected)
		_add_sel_btn("Clone", _duplicate_selection)
		_add_sel_btn("Tie", _open_tie_entity_drawer)
		_add_sel_btn("Props", _open_inspector_drawer)
		_add_sel_btn("Del", _delete_selection, 2)
	elif selected_entity >= 0:
		var ents: Array = doc.get_entities()
		var cls := "entity"
		if selected_entity < ents.size():
			cls = str(ents[selected_entity]["classname"])
		tag.text = "ENT #%d: %s" % [selected_entity, cls]
		selection_hbox.add_child(tag)
		_add_sel_btn("Rot 90° (R)", _rotate_selection)
		_add_sel_btn("Clone (Ctrl+D)", _duplicate_selection)
		_add_sel_btn("SmartEdit (Alt+Enter)", _open_inspector_drawer)
		_add_sel_btn("Delete (Del)", _delete_selection, 2)

func _add_sel_btn(label: String, fn: Callable, team: int = 0) -> void:
	var b := Button.new()
	b.text = label
	HudWidgets.style_tf2_button(b, fonts["body"], 10, false, team)
	b.pressed.connect(func(): audio.play("click"); fn.call())
	selection_hbox.add_child(b)

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

	# TOP-LEFT PILL
	var left_frame := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 9.0, true)
	bar_hb.add_child(left_frame)
	var lhb := HBoxContainer.new()
	lhb.add_theme_constant_override("separation", 5)
	left_frame.add_child(lhb)

	var brand := Label.new()
	brand.text = "POOTIS BUILDER 2.0"
	brand.add_theme_font_override("font", fonts["heading"])
	brand.add_theme_font_size_override("font_size", 13)
	brand.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	lhb.add_child(brand)

	map_title_lbl = Label.new()
	map_title_lbl.text = "| koth"
	map_title_lbl.add_theme_font_override("font", fonts["mono"])
	map_title_lbl.add_theme_font_size_override("font_size", 11)
	map_title_lbl.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	lhb.add_child(map_title_lbl)

	var hub_b := Button.new(); hub_b.text = "Hub"
	HudWidgets.style_tf2_button(hub_b, fonts["body"], 11)
	hub_b.pressed.connect(func(): audio.play("click"); _show_welcome_hub(true))
	lhb.add_child(hub_b)

	edit_only_top_nodes.clear()
	var save_b := Button.new(); save_b.text = "Save"
	HudWidgets.style_tf2_button(save_b, fonts["body"], 11)
	save_b.pressed.connect(func(): _save_current_vmf())
	lhb.add_child(save_b); edit_only_top_nodes.append(save_b)

	undo_btn = Button.new(); undo_btn.text = "Undo"
	HudWidgets.style_tf2_button(undo_btn, fonts["body"], 11)
	undo_btn.pressed.connect(func(): _do_undo())
	lhb.add_child(undo_btn); edit_only_top_nodes.append(undo_btn)

	redo_btn = Button.new(); redo_btn.text = "Redo"
	HudWidgets.style_tf2_button(redo_btn, fonts["body"], 11)
	redo_btn.pressed.connect(func(): _do_redo())
	lhb.add_child(redo_btn); edit_only_top_nodes.append(redo_btn)

	history_btn = Button.new(); history_btn.text = "History"
	history_btn.tooltip_text = "Open Map Edit History Timeline (click any step to undo/redo!)"
	HudWidgets.style_tf2_button(history_btn, fonts["body"], 11)
	history_btn.pressed.connect(func(): audio.play("click"); _open_history_drawer())
	lhb.add_child(history_btn); edit_only_top_nodes.append(history_btn)

	var sp1 := Control.new(); sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sp1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_hb.add_child(sp1)

	# TOP-CENTER: 4-Stage Stepper Pill
	var center_frame := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 9.0, true)
	bar_hb.add_child(center_frame)
	var chb := HBoxContainer.new(); chb.alignment = BoxContainer.ALIGNMENT_CENTER; chb.add_theme_constant_override("separation", 5)
	center_frame.add_child(chb)

	stage_btns.clear()
	for st in [
		{"id": Stage.BUILD,    "t": "1. BUILD"},
		{"id": Stage.GAMEPLAY, "t": "2. GAMEPLAY"},
		{"id": Stage.STYLE,    "t": "3. STYLE"},
		{"id": Stage.PLAYTEST, "t": "4. PLAY (F5)"},
	]:
		var sb := Button.new(); sb.text = st["t"]
		HudWidgets.style_tf2_button(sb, fonts["heading"], 11, st["id"] == stage)
		var sid: int = st["id"]
		sb.pressed.connect(func(): audio.play("click"); set_stage(sid))
		chb.add_child(sb)
		stage_btns.append(sb)
		if sid != Stage.PLAYTEST:
			edit_only_top_nodes.append(sb)

	var sp2 := Control.new(); sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sp2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_hb.add_child(sp2)

	# TOP-RIGHT PILL
	var right_frame := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 9.0, true)
	bar_hb.add_child(right_frame)
	var rhb := HBoxContainer.new(); rhb.alignment = BoxContainer.ALIGNMENT_END; rhb.add_theme_constant_override("separation", 4)
	right_frame.add_child(rhb)

	grid_btn = Button.new(); grid_btn.text = "Grid: 32u"; grid_btn.tooltip_text = "Cycle Grid Snap ([ smaller, ] larger)"
	HudWidgets.style_tf2_button(grid_btn, fonts["body"], 11)
	grid_btn.pressed.connect(func(): audio.play("click"); _step_grid(1, true))
	rhb.add_child(grid_btn); edit_only_top_nodes.append(grid_btn)

	sym_btn = Button.new(); sym_btn.text = "Sym: Off"
	HudWidgets.style_tf2_button(sym_btn, fonts["body"], 11)
	sym_btn.pressed.connect(func(): audio.play("click"); _cycle_symmetry())
	rhb.add_child(sym_btn); edit_only_top_nodes.append(sym_btn)

	var vis_b := Button.new(); vis_b.text = "Vis"
	HudWidgets.style_tf2_button(vis_b, fonts["body"], 11)
	vis_b.pressed.connect(func(): audio.play("click"); _open_visgroups_drawer())
	rhb.add_child(vis_b); edit_only_top_nodes.append(vis_b)

	var split_b := Button.new(); split_b.text = "2D Split"
	HudWidgets.style_tf2_button(split_b, fonts["body"], 11)
	split_b.pressed.connect(func(): audio.play("click"); _toggle_split_2d())
	rhb.add_child(split_b); edit_only_top_nodes.append(split_b)

	coach_btn = Button.new(); coach_btn.text = "Check"
	coach_btn.tooltip_text = "Check Map for Problems (Alt+P) & TF2 Map Coach"
	HudWidgets.style_tf2_button(coach_btn, fonts["body"], 11)
	coach_btn.pressed.connect(func(): audio.play("click"); _open_check_problems_drawer())
	rhb.add_child(coach_btn); edit_only_top_nodes.append(coach_btn)

	var set_b := Button.new(); set_b.text = "Settings"
	set_b.tooltip_text = "Settings & Hammer Configuration (Ctrl+,)"
	HudWidgets.style_tf2_button(set_b, fonts["body"], 11)
	set_b.pressed.connect(func(): audio.play("click"); settings_modal.open_modal())
	rhb.add_child(set_b)

	var comp_btn := Button.new(); comp_btn.text = "COMPILE (F9)"
	HudWidgets.style_tf2_button(comp_btn, fonts["heading"], 11, true)
	comp_btn.pressed.connect(func(): audio.play("click"); _open_compile_drawer())
	rhb.add_child(comp_btn); edit_only_top_nodes.append(comp_btn)

func _build_bottom_dock() -> void:
	bottom_dock = CenterContainer.new()
	bottom_dock.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_dock.offset_top = -148
	bottom_dock.offset_bottom = -8
	bottom_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(bottom_dock)
	_rebuild_bottom_dock()

func _style_dock_tab(btn: Button, accent: Color, active: bool) -> void:
	btn.focus_mode = Control.FOCUS_NONE
	var bg := accent if active else Color(0.14, 0.12, 0.10, 0.96)
	var bd := HudWidgets.COL_TX if active else accent
	btn.add_theme_stylebox_override("normal", HudWidgets.make_button_style(bg, bd, 6, 9, 4))
	btn.add_theme_stylebox_override("hover", HudWidgets.make_button_style(accent.lightened(0.12) if active else Color(0.22, 0.19, 0.16, 0.98), HudWidgets.COL_ACC, 6, 9, 4))
	btn.add_theme_stylebox_override("pressed", HudWidgets.make_button_style(accent, HudWidgets.COL_TX, 6, 9, 4))
	btn.add_theme_font_override("font", fonts["heading"] if active else fonts["body"])
	btn.add_theme_font_size_override("font_size", 10)
	btn.add_theme_color_override("font_color", Color(0.08, 0.07, 0.06) if active else HudWidgets.COL_TX)

func _rebuild_bottom_dock() -> void:
	dock_slot_map.clear()
	for ch in bottom_dock.get_children():
		ch.queue_free()
	if stage == Stage.PLAYTEST:
		return

	if viewing_bsp:
		bottom_dock.offset_top = -76
		var oframe := HudWidgets.HudFrame.new(HudWidgets.COL_BLU, 10.0, true)
		bottom_dock.add_child(oframe)
		var ohb := HBoxContainer.new(); ohb.alignment = BoxContainer.ALIGNMENT_CENTER; ohb.add_theme_constant_override("separation", 8)
		oframe.add_child(ohb)

		var badge := Label.new()
		badge.text = "OFFICIAL MAP: " + current_bsp_name.get_basename().to_upper()
		badge.add_theme_font_override("font", fonts["heading"]); badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_color", HudWidgets.COL_ACC)
		ohb.add_child(badge)

		var walk_b := Button.new(); walk_b.text = "Walk Inside (F5)"
		HudWidgets.style_tf2_button(walk_b, fonts["heading"], 12, true)
		walk_b.pressed.connect(func(): audio.play("click"); set_stage(Stage.PLAYTEST))
		ohb.add_child(walk_b)

		var fly_b := Button.new(); fly_b.text = "Noclip Fly (F5+V)"
		HudWidgets.style_tf2_button(fly_b, fonts["body"], 12, false, 3)
		fly_b.pressed.connect(func(): audio.play("click"); set_stage(Stage.PLAYTEST); player.noclip = true)
		ohb.add_child(fly_b)

		var new_b := Button.new(); new_b.text = "Start Custom Map"
		HudWidgets.style_tf2_button(new_b, fonts["body"], 12)
		new_b.pressed.connect(func(): audio.play("click"); _load_gamemode("koth", "badlands", true))
		ohb.add_child(new_b)

		var hub_b := Button.new(); hub_b.text = "Workshop Hub"
		HudWidgets.style_tf2_button(hub_b, fonts["body"], 12)
		hub_b.pressed.connect(func(): audio.play("click"); _show_welcome_hub(true))
		ohb.add_child(hub_b)
		return

	# ==========================================================================
	# 1. BUILD MODE: Multi-Box Architecture, Cutouts, Prefabs, Terrain & Valve Map Props!
	# ==========================================================================
	if stage == Stage.BUILD:
		bottom_dock.offset_top = -148
		var b_tabs := [
			{"id": "shapes",      "name": "1. Core Shapes",    "col": HudWidgets.COL_ACC},
			{"id": "cutouts",     "name": "2. Cutouts & Edit", "col": HudWidgets.COL_CYAN},
			{"id": "prefabs",     "name": "3. TF2 Prefabs",    "col": HudWidgets.COL_GREEN},
			{"id": "terrain",     "name": "4. Terrain & Cliffs","col": Color(0.84, 0.56, 0.34, 1.0)},
			{"id": "valve_props", "name": "5. Valve Map Props","col": Color(0.92, 0.76, 0.32, 1.0)},
		]
		var b_lip := HudWidgets.COL_LIP_AMB
		for bt in b_tabs:
			if str(bt["id"]) == _dock_build_cat:
				b_lip = bt["col"]
		var frame := HudWidgets.HudFrame.new(b_lip, 11.0, true)
		bottom_dock.add_child(frame)
		var bvb := VBoxContainer.new(); bvb.add_theme_constant_override("separation", 6)
		frame.add_child(bvb)

		var tab_row := HBoxContainer.new(); tab_row.alignment = BoxContainer.ALIGNMENT_CENTER; tab_row.add_theme_constant_override("separation", 6)
		bvb.add_child(tab_row)
		for bt in b_tabs:
			var bid: String = str(bt["id"])
			var tb := Button.new(); tb.text = str(bt["name"])
			_style_dock_tab(tb, bt["col"], _dock_build_cat == bid)
			tb.pressed.connect(func(): audio.play("click"); _dock_build_cat = bid; _rebuild_bottom_dock())
			tab_row.add_child(tb)

		var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; hb.add_theme_constant_override("separation", 6)
		bvb.add_child(hb)

		if _dock_build_cat == "valve_props":
			for vp in Tf2CatalogScript.VALVE_MAP_BUILD_PROPS:
				var nm: String = str(vp["name"])
				var sub: String = str(vp["sub"])
				var mp: String = str(vp["mdl"])
				var is_sel: bool = (active_tool == "place_prop" and active_prop_mdl == mp)
				var tex: Texture2D = icon_cache.get_icon(mp) if icon_cache != null else null
				var card := HudWidgets.DockCardSlot.new(nm, sub, tex, "", is_sel, b_lip, fonts["body"], {"kind": "prop", "mdl": mp, "name": nm})
				HudWidgets.attach_spring_anim(card, 1.06)
				card.tooltip_text = "%s (Official Valve %s prop)\nDrag into 3D or Click to stamp!" % [nm, sub]
				if not dock_slot_map.has(mp): dock_slot_map[mp] = []
				(dock_slot_map[mp] as Array).append(card)
				card.pressed.connect(func():
					audio.play("click")
					active_prop_mdl = mp; active_tool = "place_prop"
					_rebuild_bottom_dock(); _refresh_context_bar()
					_toast("Click in 3D or Drag & Drop to place Valve prop: " + nm)
				)
				hb.add_child(card)
			return

		var slots: Array = []
		if _dock_build_cat == "shapes":
			slots = [
				{"id": "floor",    "piece": "Floor",    "lbl": "Draw Box"},
				{"id": "wall",     "piece": "Wall",     "lbl": "Wall Chain"},
				{"id": "ramp",     "piece": "Ramp",     "lbl": "Ramp"},
				{"id": "stairs",   "piece": "Stairs",   "lbl": "Stairs"},
				{"id": "arch",     "piece": "Arch",     "lbl": "Arch"},
				{"id": "pillar",   "piece": "Box",      "lbl": "Pillar"},
				{"id": "import3d", "piece": "Model",    "lbl": "Import 3D", "icon": "crate"},
			]
		elif _dock_build_cat == "cutouts":
			slots = [
				{"id": "carve",    "piece": "Door",     "lbl": "Carve Door"},
				{"id": "carve_win","piece": "Wall",     "lbl": "Carve Window"},
				{"id": "act_hollow","piece": "Box",     "lbl": "Make Hollow"},
				{"id": "act_clone","piece": "Floor",    "lbl": "Duplicate"},
				{"id": "act_tie",  "piece": "Building", "lbl": "Tie Entity"},
				{"id": "act_hide", "piece": "Pull",     "lbl": "QuickHide", "tool": true, "tkind": "Pull"},
			]
		elif _dock_build_cat == "prefabs":
			slots = [
				{"id": "building",       "piece": "Building", "lbl": "Barn Shed"},
				{"id": "prefab_spawn",   "piece": "Building", "lbl": "Spawn Room",  "icon": "resupply"},
				{"id": "prefab_balcony", "piece": "Stairs",   "lbl": "Sniper Deck"},
				{"id": "prefab_mid",     "piece": "Floor",    "lbl": "Mid Platform","icon": "cap_point"},
				{"id": "prefab_cover",   "piece": "Box",      "lbl": "Crate Cover", "icon": "crate"},
				{"id": "prefab_bridge",  "piece": "Ramp",     "lbl": "Catwalk"},
			]
		else:
			slots = [
				{"id": "terrain",        "piece": "Terrain",  "lbl": "Sculpt Studio", "tool": true, "tkind": "Terrain"},
				{"id": "stamp_cliff",    "piece": "Terrain",  "lbl": "Canyon Cliff",  "tool": true, "tkind": "Terrain"},
				{"id": "stamp_hill",     "piece": "Floor",    "lbl": "Rolling Hill"},
				{"id": "stamp_mesa",     "piece": "Box",      "lbl": "Mesa Plateau"},
				{"id": "stamp_crater",   "piece": "Ramp",     "lbl": "Crater Basin"},
				{"id": "act_sew",        "piece": "Pull",     "lbl": "Auto-Sew",      "tool": true, "tkind": "Pull"},
			]

		for sl in slots:
			var sid: String = sl["id"]
			var is_act := (active_tool == sid)
			var ikey: String = str(sl.get("icon", ""))
			var tex: Texture2D = icon_cache.get_icon(ikey) if not ikey.is_empty() else null
			var slot_btn := HudWidgets.RailSlot.new(
				sl["piece"], sl["lbl"], tex, is_act,
				int(sl.get("team", 0)), bool(sl.get("tool", false)), str(sl.get("tkind", "")),
				fonts["body"], {}
			)
			HudWidgets.attach_spring_anim(slot_btn, 1.07)
			if not ikey.is_empty():
				if not dock_slot_map.has(ikey): dock_slot_map[ikey] = []
				(dock_slot_map[ikey] as Array).append(slot_btn)
			slot_btn.pressed.connect(func():
				audio.play("click")
				if sid == "act_hollow": _do_hollow_selected()
				elif sid == "act_clone": _duplicate_selection()
				elif sid == "act_tie": _open_tie_entity_drawer()
				elif sid == "act_hide": _do_quickhide_selected()
				elif sid == "act_sew":
					var n: int = doc.sew_displacements()
					_record_history("Auto-Sew Seams"); map_sync.sync_all(); audio.play("carve")
					_toast("Auto-Sewed %d displacement vertices!" % n)
				elif sid.begins_with("stamp_"):
					_stamp_terrain_quick(sid.trim_prefix("stamp_"))
				else:
					_select_tool(sid)
			)
			hb.add_child(slot_btn)
		return

	# ==========================================================================
	# 2. GAMEPLAY MODE: Gamemode-Aware Multi-Box Entity Dock (Highlights Mode Essentials, Hides Off-Mode!)
	# ==========================================================================
	if stage == Stage.GAMEPLAY:
		bottom_dock.offset_top = -148
		var gm_ess: Dictionary = Tf2CatalogScript.get_gamemode_essentials(active_gamemode)
		var is_mode_tab: bool = (_dock_ent_cat == "_mode")
		var ebox: Dictionary = {} if is_mode_tab else Tf2CatalogScript.get_entity_box(_dock_ent_cat)
		var lip_col: Color = gm_ess["color"] if is_mode_tab else ebox.get("color", HudWidgets.COL_LIP_AMB)
		var frame := HudWidgets.HudFrame.new(lip_col, 11.0, true)
		bottom_dock.add_child(frame)
		var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 6)
		frame.add_child(vb)

		# Top Row: Highlighted Gamemode Essentials + 8 Category Tabs + All Modes Toggle + Search!
		var tabs := HBoxContainer.new(); tabs.alignment = BoxContainer.ALIGNMENT_CENTER; tabs.add_theme_constant_override("separation", 4)
		vb.add_child(tabs)

		var gm_tb := Button.new()
		gm_tb.text = "* " + str(gm_ess["title"])
		_style_dock_tab(gm_tb, gm_ess["color"], is_mode_tab)
		gm_tb.pressed.connect(func(): audio.play("click"); _dock_ent_cat = "_mode"; _dock_ent_page = 0; _rebuild_bottom_dock())
		tabs.add_child(gm_tb)

		for box in Tf2CatalogScript.ENTITY_FOLDER_BOXES:
			var bid: String = str(box["id"])
			var tb := Button.new()
			tb.text = str(box["short"])
			tb.tooltip_text = str(box["name"])
			_style_dock_tab(tb, box["color"], _dock_ent_cat == bid)
			tb.pressed.connect(func():
				audio.play("click")
				_dock_ent_cat = bid
				_dock_ent_page = 0
				_rebuild_bottom_dock()
			)
			tabs.add_child(tb)

		var allm_b := Button.new(); allm_b.text = "All Modes" if not _show_all_mode_ents else "Mode Only"
		allm_b.tooltip_text = "Show entities from all TF2 gamemodes (currently hiding off-mode entities)"
		HudWidgets.style_tf2_button(allm_b, fonts["body"], 9, _show_all_mode_ents)
		allm_b.pressed.connect(func(): audio.play("click"); _show_all_mode_ents = not _show_all_mode_ents; _rebuild_bottom_dock())
		tabs.add_child(allm_b)

		var search_eb := Button.new(); search_eb.text = "Search 452..."
		HudWidgets.style_tf2_button(search_eb, fonts["body"], 9)
		search_eb.pressed.connect(func(): audio.play("click"); _open_fgd_entity_drawer())
		tabs.add_child(search_eb)

		# Bottom Row: < Prev | 8 Gamemode-Filtered Entity Cards with Icons | > Next
		var items: Array[Dictionary] = []
		if is_mode_tab:
			for it in gm_ess["items"]:
				items.append(it)
		else:
			var raw_items: Array[Dictionary] = Tf2CatalogScript.get_entities_for_box(core, _dock_ent_cat, 36)
			for it in raw_items:
				if _show_all_mode_ents or Tf2CatalogScript.is_entity_allowed_for_gamemode(it, active_gamemode):
					items.append(it)
		var per_page := 8
		var total_pages := maxi(1, int(ceil(float(items.size()) / float(per_page))))
		_dock_ent_page = clampi(_dock_ent_page, 0, total_pages - 1)
		var start_i := _dock_ent_page * per_page
		var end_i := mini(items.size(), start_i + per_page)

		var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; row.add_theme_constant_override("separation", 6)
		vb.add_child(row)

		var prev_b := Button.new(); prev_b.text = "<"; prev_b.custom_minimum_size = Vector2(28, 82)
		prev_b.disabled = (_dock_ent_page <= 0)
		HudWidgets.style_tf2_button(prev_b, fonts["heading"], 14)
		prev_b.pressed.connect(func(): audio.play("click"); _dock_ent_page = maxi(0, _dock_ent_page - 1); _rebuild_bottom_dock())
		row.add_child(prev_b)

		for idx in range(start_i, end_i):
			var it: Dictionary = items[idx]
			var nm: String = str(it["name"])
			var cls: String = str(it["cls"])
			var desc: String = str(it["desc"])
			var itype: String = str(it["icon_type"])
			var ikey: String = str(it["icon"])
			var preset: String = str(it.get("preset", ""))
			var is_act: bool = (not preset.is_empty() and active_tool == preset) or (preset.is_empty() and active_tool == "place_fgd_entity" and active_fgd_entity == cls)
			var drag_d: Dictionary = {"kind": "gameplay", "id": preset, "name": nm} if not preset.is_empty() else {"kind": "fgd_entity", "cls": cls, "name": nm}
			var tex: Texture2D = icon_cache.get_icon(ikey) if (itype == "mdl" and icon_cache != null) else null
			var vec_ic: String = ikey if itype != "mdl" else ""
			var card := HudWidgets.DockCardSlot.new(nm, cls, tex, vec_ic, is_act, lip_col, fonts["body"], drag_d)
			HudWidgets.attach_spring_anim(card, 1.06)
			card.tooltip_text = "%s  (%s)\n%s\nDrag into 3D or Click to place!" % [nm, cls, desc]
			if itype == "mdl":
				if not dock_slot_map.has(ikey): dock_slot_map[ikey] = []
				(dock_slot_map[ikey] as Array).append(card)
			card.pressed.connect(func():
				audio.play("click")
				if not preset.is_empty():
					_select_tool(preset)
				else:
					active_fgd_entity = cls
					active_tool = "place_fgd_entity"
					_rebuild_bottom_dock()
					_refresh_context_bar()
					_toast("Click in 3D or Drag & Drop to place %s (%s)" % [nm, cls])
			)
			row.add_child(card)

		var next_b := Button.new(); next_b.text = ">"; next_b.custom_minimum_size = Vector2(28, 82)
		next_b.disabled = (_dock_ent_page >= total_pages - 1)
		HudWidgets.style_tf2_button(next_b, fonts["heading"], 14)
		next_b.pressed.connect(func(): audio.play("click"); _dock_ent_page = mini(total_pages - 1, _dock_ent_page + 1); _rebuild_bottom_dock())
		row.add_child(next_b)
		return

	# ==========================================================================
	# 3. STYLE / PROPS MODE: Multi-Box Prop Category Dock (Winter, Trees, Crates...)
	# ==========================================================================
	bottom_dock.offset_top = -148
	var pbox: Dictionary = Tf2CatalogScript.get_prop_box(_dock_prop_cat)
	var plip: Color = pbox.get("color", HudWidgets.COL_LIP_AMB) if not pbox.is_empty() else HudWidgets.COL_LIP_AMB
	var pframe := HudWidgets.HudFrame.new(plip, 11.0, true)
	bottom_dock.add_child(pframe)
	var pvb := VBoxContainer.new(); pvb.add_theme_constant_override("separation", 6)
	pframe.add_child(pvb)

	# Top Row: Style Tools + All 9 Prop Category Box Tabs + Saved + Search All!
	var ptabs := HBoxContainer.new(); ptabs.alignment = BoxContainer.ALIGNMENT_CENTER; ptabs.add_theme_constant_override("separation", 4)
	pvb.add_child(ptabs)

	var tools_tb := Button.new(); tools_tb.text = "Paint / Sky"
	_style_dock_tab(tools_tb, HudWidgets.COL_ACC, _dock_prop_cat == "_tools")
	tools_tb.pressed.connect(func(): audio.play("click"); _dock_prop_cat = "_tools"; _dock_prop_page = 0; _rebuild_bottom_dock())
	ptabs.add_child(tools_tb)

	for box in Tf2CatalogScript.PROP_FOLDER_BOXES:
		var cid: String = str(box["id"])
		var short_nm: String = str(box["name"]).get_slice(" &", 0)
		var tb := Button.new()
		tb.text = short_nm
		tb.tooltip_text = "%s â€” %s" % [str(box["name"]), str(box["subtitle"])]
		_style_dock_tab(tb, box["color"], _dock_prop_cat == cid)
		tb.pressed.connect(func():
			audio.play("click")
			_dock_prop_cat = cid
			_dock_prop_page = 0
			_rebuild_bottom_dock()
		)
		ptabs.add_child(tb)

	var sav_tb := Button.new(); sav_tb.text = "Saved (%d)" % _prop_favorites.size()
	_style_dock_tab(sav_tb, HudWidgets.COL_ACC, _dock_prop_cat == "_saved")
	sav_tb.pressed.connect(func(): audio.play("click"); _dock_prop_cat = "_saved"; _dock_prop_page = 0; _rebuild_bottom_dock())
	ptabs.add_child(sav_tb)

	var all_pb := Button.new(); all_pb.text = "Browse All..."
	HudWidgets.style_tf2_button(all_pb, fonts["body"], 10)
	all_pb.pressed.connect(func(): audio.play("click"); _open_props_drawer())
	ptabs.add_child(all_pb)

	# Bottom Row: Style Tools OR Paginated 3D Prop Cards for active Category Box!
	var prow := HBoxContainer.new(); prow.alignment = BoxContainer.ALIGNMENT_CENTER; prow.add_theme_constant_override("separation", 6)
	pvb.add_child(prow)

	if _dock_prop_cat == "_tools":
		var tslots := [
			{"id": "select",    "piece": "Pull",     "lbl": "Select Face", "tool": true, "tkind": "Pull"},
			{"id": "materials", "piece": "Wall",     "lbl": "Face Edit"},
			{"id": "props",     "piece": "Box",      "lbl": "Prop Drawer", "icon": "crate"},
			{"id": "biomes",    "piece": "Building", "lbl": "Biomes"},
			{"id": "sky_sun",   "piece": "Terrain",  "lbl": "Sky & Sun",   "tool": true, "tkind": "Terrain"},
			{"id": "light",     "piece": "Floor",    "lbl": "Add Light",   "icon": "light", "drag": {"kind": "gameplay", "id": "light"}},
		]
		for sl in tslots:
			var sid: String = sl["id"]
			var ikey: String = str(sl.get("icon", ""))
			var tex: Texture2D = icon_cache.get_icon(ikey) if not ikey.is_empty() else null
			var slot_btn := HudWidgets.RailSlot.new(
				sl["piece"], sl["lbl"], tex, active_tool == sid,
				0, bool(sl.get("tool", false)), str(sl.get("tkind", "")), fonts["body"], sl.get("drag", {})
			)
			if not ikey.is_empty():
				if not dock_slot_map.has(ikey): dock_slot_map[ikey] = []
				(dock_slot_map[ikey] as Array).append(slot_btn)
			slot_btn.pressed.connect(func(): audio.play("click"); _select_tool(sid))
			prow.add_child(slot_btn)
		return

	var pitems: Array[Dictionary] = []
	if _dock_prop_cat == "_saved":
		for mp in _prop_favorites:
			pitems.append({"name": mp.get_file().get_basename().replace("_", " ").capitalize(), "mdl": mp})
	else:
		pitems = Tf2CatalogScript.get_props_for_box(core, _dock_prop_cat, "", 45)

	var p_per := 8
	var p_pages := maxi(1, int(ceil(float(pitems.size()) / float(p_per))))
	_dock_prop_page = clampi(_dock_prop_page, 0, p_pages - 1)
	var p_start := _dock_prop_page * p_per
	var p_end := mini(pitems.size(), p_start + p_per)

	var pprev := Button.new(); pprev.text = "<"; pprev.custom_minimum_size = Vector2(28, 82)
	pprev.disabled = (_dock_prop_page <= 0)
	HudWidgets.style_tf2_button(pprev, fonts["heading"], 14)
	pprev.pressed.connect(func(): audio.play("click"); _dock_prop_page = maxi(0, _dock_prop_page - 1); _rebuild_bottom_dock())
	prow.add_child(pprev)

	if pitems.is_empty():
		var empty_l := Label.new()
		empty_l.text = "No saved props yet â€” click '+' on any prop in Browse All to save favorites!"
		empty_l.add_theme_font_override("font", fonts["body"]); empty_l.add_theme_font_size_override("font_size", 12)
		empty_l.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
		prow.add_child(empty_l)
	else:
		var cat_sub: String = str(pbox.get("name", "Saved"))
		for idx in range(p_start, p_end):
			var it: Dictionary = pitems[idx]
			var nm: String = str(it["name"])
			var mp: String = str(it["mdl"])
			var is_sel: bool = (active_tool == "place_prop" and active_prop_mdl == mp)
			var tex: Texture2D = icon_cache.get_icon(mp) if icon_cache != null else null
			var card := HudWidgets.DockCardSlot.new(nm, cat_sub, tex, "", is_sel, plip, fonts["body"], {"kind": "prop", "mdl": mp, "name": nm})
			HudWidgets.attach_spring_anim(card, 1.06)
			card.tooltip_text = "%s\n(%s)\nDrag into 3D or Click to stamp  â€¢  Press R to rotate" % [nm, mp]
			if not dock_slot_map.has(mp): dock_slot_map[mp] = []
			(dock_slot_map[mp] as Array).append(card)
			card.pressed.connect(func():
				audio.play("click")
				active_prop_mdl = mp
				active_tool = "place_prop"
				_rebuild_bottom_dock()
				_refresh_context_bar()
				_toast("Click in 3D or Drag & Drop to place " + nm)
			)
			prow.add_child(card)

	var pnext := Button.new(); pnext.text = ">"; pnext.custom_minimum_size = Vector2(28, 82)
	pnext.disabled = (_dock_prop_page >= p_pages - 1)
	HudWidgets.style_tf2_button(pnext, fonts["heading"], 14)
	pnext.pressed.connect(func(): audio.play("click"); _dock_prop_page = mini(p_pages - 1, _dock_prop_page + 1); _rebuild_bottom_dock())
	prow.add_child(pnext)

func _on_icon_ready(key: String, tex: Texture2D) -> void:
	if dock_slot_map.has(key):
		for slot in dock_slot_map[key]:
			if is_instance_valid(slot):
				slot.set_icon_texture(tex)

func _build_right_drawer() -> void:
	right_drawer = HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 10.0, true)
	right_drawer.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_drawer.offset_right = -12
	right_drawer.offset_left = -444
	right_drawer.offset_top = 66
	right_drawer.offset_bottom = -160
	right_drawer.visible = false
	hud_layer.add_child(right_drawer)

	var outer := VBoxContainer.new(); outer.add_theme_constant_override("separation", 6)
	right_drawer.add_child(outer)

	var hdr := HBoxContainer.new(); outer.add_child(hdr)
	right_drawer_title = Label.new()
	right_drawer_title.text = "TOOL OPTIONS"
	right_drawer_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_drawer_title.add_theme_font_override("font", fonts["heading"])
	right_drawer_title.add_theme_font_size_override("font_size", 14)
	right_drawer_title.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	hdr.add_child(right_drawer_title)

	var close_b := Button.new(); close_b.text = "X"
	HudWidgets.style_tf2_button(close_b, fonts["heading"], 11)
	close_b.pressed.connect(func(): right_drawer.visible = false)
	hdr.add_child(close_b)

	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)

	right_drawer_vbox = VBoxContainer.new()
	right_drawer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_drawer_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(right_drawer_vbox)

func _build_split_2d_pane() -> void:
	# Collapsible Split 2D Blueprint Pane (TOP X/Y + SIDE X/Z with 48u/128u/192u jump guides!)
	split_2d_panel = HudWidgets.HudFrame.new(HudWidgets.COL_BLU, 10.0, true)
	split_2d_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	split_2d_panel.offset_right = -12
	split_2d_panel.offset_left = -410
	split_2d_panel.offset_top = 66
	split_2d_panel.offset_bottom = -170
	split_2d_panel.visible = false
	hud_layer.add_child(split_2d_panel)

	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 8)
	split_2d_panel.add_child(vb)

	var hdr := HBoxContainer.new(); vb.add_child(hdr)
	var tl := Label.new(); tl.text = "HAMMER 2D BLUEPRINT SPLIT"; tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.add_theme_font_override("font", fonts["heading"]); tl.add_theme_font_size_override("font_size", 13)
	tl.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	hdr.add_child(tl)
	var xb := Button.new(); xb.text = "X"; HudWidgets.style_tf2_button(xb, fonts["heading"], 10)
	xb.pressed.connect(func(): split_2d_panel.visible = false; settings.show_2d_split = false)
	hdr.add_child(xb)

	bp_top = Blueprint2DScript.new(); bp_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bp_top.setup(doc, fonts["mono"], 0)
	bp_top.solid_clicked.connect(func(sidx: int): _select_solid(sidx, -1); audio.play("click"))
	vb.add_child(bp_top)

	bp_side = Blueprint2DScript.new(); bp_side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bp_side.setup(doc, fonts["mono"], 1)
	bp_side.solid_clicked.connect(func(sidx: int): _select_solid(sidx, -1); audio.play("click"))
	vb.add_child(bp_side)

func _build_playtest_hud() -> void:
	playtest_hud = CenterContainer.new()
	playtest_hud.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	playtest_hud.offset_top = -98
	playtest_hud.offset_bottom = -12
	playtest_hud.visible = false
	hud_layer.add_child(playtest_hud)

	var frame := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 10.0, true)
	playtest_hud.add_child(frame)
	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 4)
	frame.add_child(vb)

	playtest_lbl = Label.new()
	playtest_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	playtest_lbl.add_theme_font_override("font", fonts["heading"])
	playtest_lbl.add_theme_font_size_override("font_size", 13)
	playtest_lbl.add_theme_color_override("font_color", HudWidgets.COL_TX)
	vb.add_child(playtest_lbl)

	var class_row := HBoxContainer.new(); class_row.alignment = BoxContainer.ALIGNMENT_CENTER; class_row.add_theme_constant_override("separation", 6)
	vb.add_child(class_row)
	for i in range(SandboxPlayerScript.CLASSES.size()):
		var c: Dictionary = SandboxPlayerScript.CLASSES[i]
		var cb := Button.new(); cb.text = "%d %s" % [c["id"], c["name"]]
		HudWidgets.style_tf2_button(cb, fonts["body"], 11)
		var ci := i
		cb.pressed.connect(func(): player.set_tf2_class(ci))
		class_row.add_child(cb)

func _build_welcome_hub() -> void:
	welcome_panel = ColorRect.new()
	welcome_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	welcome_panel.color = Color(0.06, 0.05, 0.04, 0.78)
	hud_layer.add_child(welcome_panel)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	welcome_panel.add_child(center)

	var card := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 14.0, true)
	card.custom_minimum_size = Vector2(1040, 620)
	center.add_child(card)

	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)

	var hdr := HBoxContainer.new(); hdr.add_theme_constant_override("separation", 8); vb.add_child(hdr)
	var title_vb := VBoxContainer.new(); title_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL; hdr.add_child(title_vb)
	var title := Label.new()
	title.text = "MANN CO. WORKSHOP HUB"
	title.add_theme_font_override("font", fonts["heading"]); title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	title_vb.add_child(title)

	var sub := Label.new()
	sub.text = "POOTIS BUILDER 2.0  â€”  All 12 TF2 Gamemodes, %d FGD Entities & %d Official Valve TF2 Maps" % [
		core.get_fgd_class_count(), core.list_maps().size()
	]
	sub.add_theme_font_override("font", fonts["body"]); sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	title_vb.add_child(sub)

	var open_vmf_h := Button.new(); open_vmf_h.text = "Open .VMF"
	HudWidgets.style_tf2_button(open_vmf_h, fonts["body"], 12)
	open_vmf_h.pressed.connect(func(): audio.play("click"); _open_file_dialog("vmf"))
	hdr.add_child(open_vmf_h)

	var set_hb := Button.new(); set_hb.text = "Settings"
	HudWidgets.style_tf2_button(set_hb, fonts["body"], 12)
	set_hb.pressed.connect(func(): audio.play("click"); settings_modal.open_modal())
	hdr.add_child(set_hb)

	var resume_b := Button.new(); resume_b.text = "Continue Editing"
	HudWidgets.style_tf2_button(resume_b, fonts["heading"], 13, true)
	resume_b.pressed.connect(func(): audio.play("click"); _show_welcome_hub(false))
	hdr.add_child(resume_b)

	var cols := HBoxContainer.new(); cols.size_flags_vertical = Control.SIZE_EXPAND_FILL; cols.add_theme_constant_override("separation", 16)
	vb.add_child(cols)

	# LEFT COLUMN: VISUAL GAMEMODE STARTER CARDS
	var left_col := VBoxContainer.new(); left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; left_col.size_flags_stretch_ratio = 1.45
	left_col.add_theme_constant_override("separation", 8); cols.add_child(left_col)

	var gm_hdr := Label.new(); gm_hdr.text = "START A NEW TF2 MAP (ALL 12 GAMEMODES)"
	gm_hdr.add_theme_font_override("font", fonts["heading"]); gm_hdr.add_theme_font_size_override("font_size", 13)
	gm_hdr.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	left_col.add_child(gm_hdr)

	var gm_scroll := ScrollContainer.new(); gm_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; left_col.add_child(gm_scroll)
	var grid := GridContainer.new(); grid.columns = 2; grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8)
	gm_scroll.add_child(grid)

	var gm_icons := {
		"koth": "cap_point", "pl": "bomb_cart", "plr": "bomb_cart", "ctf": "intel",
		"cp_5cp": "spawn_red", "cp_ad": "cap_point", "mvm": "upgrade_station", "arena": "spawn_blu",
		"medieval": "barrel", "sd": "intel", "pass": "sentry", "mge_jump": "dispenser",
	}
	for gm in Tf2GamemodesScript.GAMEMODES:
		var mid: String = gm["id"]
		var gb := Button.new()
		gb.custom_minimum_size = Vector2(0, 68); gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gb.focus_mode = Control.FOCUS_NONE
		var gsb := StyleBoxFlat.new()
		gsb.bg_color = HudWidgets.COL_BG_CARD; gsb.border_color = HudWidgets.COL_SLOT_BD
		gsb.set_border_width_all(1); gsb.set_corner_radius_all(9)
		var gsbh := gsb.duplicate(); gsbh.bg_color = HudWidgets.COL_SLOT_HOV; gsbh.border_color = HudWidgets.COL_ACC
		gb.add_theme_stylebox_override("normal", gsb); gb.add_theme_stylebox_override("hover", gsbh); gb.add_theme_stylebox_override("pressed", gsbh)

		var ghb := HBoxContainer.new()
		ghb.set_anchors_preset(Control.PRESET_FULL_RECT)
		ghb.offset_left = 8; ghb.offset_right = -8; ghb.offset_top = 6; ghb.offset_bottom = -6
		ghb.add_theme_constant_override("separation", 10)
		ghb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gb.add_child(ghb)

		var ic_box := PanelContainer.new()
		ic_box.custom_minimum_size = Vector2(52, 52)
		ic_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var isb := StyleBoxFlat.new()
		isb.bg_color = Color(0.10, 0.09, 0.08, 0.96); isb.border_color = HudWidgets.COL_ACC
		isb.set_border_width_all(1); isb.set_corner_radius_all(7)
		ic_box.add_theme_stylebox_override("panel", isb)
		ghb.add_child(ic_box)

		var itr := TextureRect.new()
		itr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		itr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		itr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ikey: String = str(gm_icons.get(mid, "crate"))
		if icon_cache != null:
			var itex: Texture2D = icon_cache.get_icon(ikey)
			if itex != null:
				itr.texture = itex
			else:
				var w_itr: WeakRef = weakref(itr)
				icon_cache.icon_ready.connect(func(k: String, tx: Texture2D):
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
		ghb.add_child(gtvb)
		var g1 := Label.new(); g1.text = str(gm["name"])
		g1.add_theme_font_override("font", fonts["heading"]); g1.add_theme_font_size_override("font_size", 12)
		g1.add_theme_color_override("font_color", HudWidgets.COL_TX); g1.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gtvb.add_child(g1)
		var g2 := Label.new(); g2.text = "%s  â€¢  Starter Arena" % str(gm["short"])
		g2.add_theme_font_override("font", fonts["body"]); g2.add_theme_font_size_override("font_size", 10)
		g2.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED); g2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		gtvb.add_child(g2)

		gb.pressed.connect(func(): audio.play("click"); _load_gamemode(mid); _show_welcome_hub(false))
		grid.add_child(gb)

	var foot_l := HBoxContainer.new(); foot_l.add_theme_constant_override("separation", 8); left_col.add_child(foot_l)
	var open_imp := Button.new(); open_imp.text = "Import 3D Model (.OBJ / .GLB)..."
	HudWidgets.style_tf2_button(open_imp, fonts["body"], 11)
	open_imp.pressed.connect(func(): audio.play("click"); _show_welcome_hub(false); _open_file_dialog("model"))
	foot_l.add_child(open_imp)

	# RIGHT COLUMN: OFFICIAL TF2 MAPS GALLERY WITH GAMEMODE TAGS
	var right_col := VBoxContainer.new(); right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; right_col.size_flags_stretch_ratio = 1.1
	right_col.add_theme_constant_override("separation", 8); cols.add_child(right_col)

	var bsp_hdr := Label.new(); bsp_hdr.text = "EXPLORE OFFICIAL TF2 MAPS (%d INSTALLED)" % core.list_maps().size()
	bsp_hdr.add_theme_font_override("font", fonts["heading"]); bsp_hdr.add_theme_font_size_override("font_size", 13)
	bsp_hdr.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	right_col.add_child(bsp_hdr)

	var search := LineEdit.new(); search.placeholder_text = "Filter 150+ official TF2 maps (upward, turbine, degroot...)"
	right_col.add_child(search)

	var map_scroll := ScrollContainer.new(); map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; right_col.add_child(map_scroll)
	var map_list := VBoxContainer.new(); map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; map_list.add_theme_constant_override("separation", 5)
	map_scroll.add_child(map_list)

	var all_maps: PackedStringArray = core.list_maps()
	var populate_maps := func(filter: String) -> void:
		for ch in map_list.get_children():
			ch.queue_free()
		var fl := filter.to_lower().strip_edges()
		var shown := 0
		var featured := ["pl_upward.bsp", "ctf_turbine.bsp", "ctf_2fort.bsp", "koth_viaduct.bsp", "cp_degrootkeep_rats.bsp", "cp_ambush_event.bsp", "mvm_decoy.bsp", "cp_process_final.bsp", "sd_doomsday.bsp"]
		var ordered: Array[String] = []
		if fl.is_empty():
			for fm in featured:
				if all_maps.has(fm): ordered.append(fm)
		for m in all_maps:
			if fl.is_empty() or m.to_lower().find(fl) != -1:
				if not ordered.has(m): ordered.append(m)
		for m in ordered:
			if shown >= 45: break
			var mcopy := m
			var prefix := m.get_slice("_", 0).to_upper()
			var mb := Button.new()
			mb.custom_minimum_size = Vector2(0, 38)
			mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			HudWidgets.style_tf2_button(mb, fonts["body"], 11)
			var mhb := HBoxContainer.new()
			mhb.set_anchors_preset(Control.PRESET_FULL_RECT)
			mhb.offset_left = 10; mhb.offset_right = -10
			mhb.alignment = BoxContainer.ALIGNMENT_CENTER
			mhb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mb.add_child(mhb)
			var ml := Label.new(); ml.text = m.get_basename()
			ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ml.add_theme_font_override("font", fonts["body"]); ml.add_theme_font_size_override("font_size", 12)
			ml.add_theme_color_override("font_color", HudWidgets.COL_TX); ml.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mhb.add_child(ml)
			var mtag := Label.new(); mtag.text = " " + prefix + " "
			mtag.add_theme_font_override("font", fonts["heading"]); mtag.add_theme_font_size_override("font_size", 10)
			mtag.add_theme_color_override("font_color", HudWidgets.COL_CYAN if prefix in ["PL", "PLR", "CTF"] else HudWidgets.COL_ACC)
			mtag.mouse_filter = Control.MOUSE_FILTER_IGNORE
			mhb.add_child(mtag)
			mb.pressed.connect(func(): audio.play("click"); _load_official_bsp(mcopy); _show_welcome_hub(false))
			map_list.add_child(mb)
			shown += 1

	populate_maps.call("")
	search.text_changed.connect(populate_maps)

	# FOOTER: VPK & VAC-Safe Status Pill
	var foot := HBoxContainer.new(); foot.add_theme_constant_override("separation", 10); vb.add_child(foot)
	var rec := Label.new()
	rec.text = "Tip: Press F5 anytime to playtest with Scout / Soldier / Heavy / Pyro / Demo!"
	rec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rec.add_theme_font_override("font", fonts["body"]); rec.add_theme_font_size_override("font_size", 11)
	rec.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	foot.add_child(rec)
	var vpk_badge := Label.new()
	vpk_badge.text = "  TF2 VPKs Mounted  â€¢  16,697 Models  â€¢  VAC-Safe  "
	vpk_badge.add_theme_font_override("font", fonts["heading"]); vpk_badge.add_theme_font_size_override("font_size", 11)
	vpk_badge.add_theme_color_override("font_color", HudWidgets.COL_GREEN)
	foot.add_child(vpk_badge)

# ==============================================================================
# DRAG-AND-DROP FROM REAL 3D TF2 ASSET TRAY INTO 3D VIEWPORT!
# ==============================================================================
func on_viewport_drag_hover(screen_pos: Vector2, _data: Dictionary) -> void:
	if viewing_bsp:
		return
	var p := _project_screen_to_surface(screen_pos)
	if p["valid"]:
		hover_pos = p["pos"]
		hover_valid = true
		brush_ring.visible = true
		brush_ring.position = hover_pos + Vector3(0, 0.15, 0)
		brush_ring.scale = Vector3(1.2, 1.0, 1.2)

func on_viewport_drop(screen_pos: Vector2, data: Dictionary) -> void:
	brush_ring.visible = false
	if viewing_bsp:
		return
	var p := _project_screen_to_surface(screen_pos)
	if not p["valid"]:
		return
	var pos: Vector3 = p["pos"]
	var kind: String = str(data.get("kind", ""))
	if kind == "gameplay":
		var pid: String = str(data.get("id", ""))
		var preset := pid
		var team := 2
		if pid == "spawn_red": preset = "spawn"; team = 2
		elif pid == "spawn_blu": preset = "spawn"; team = 3
		Tf2GamemodesScript.stamp_preset(doc, preset, pos, team)
		if symmetry != SymmetryMode.OFF:
			var mpos := Vector3(-pos.x, pos.y, -pos.z if symmetry == SymmetryMode.ROT_180 else pos.z)
			Tf2GamemodesScript.stamp_preset(doc, preset, mpos, 3 if team == 2 else 2)
		_record_history("Drop " + pid)
		ent_vis.sync_all()
		audio.play("place")
		_toast("Dropped %s cleanly onto map at (%du, %du, %du)!" % [pid, int(pos.x * UPM), int(-pos.z * UPM), int(pos.y * UPM)])
	elif kind == "fgd_entity":
		var cls: String = str(data.get("cls", active_fgd_entity))
		var eid: int = _place_smart_entity(cls, pos)
		_record_history("Drop " + cls)
		if eid >= 0:
			ent_vis.sync_entity(eid, true)
			_select_entity(eid)
		else:
			ent_vis.sync_all()
		_spawn_place_fx(pos, HudWidgets.COL_CYAN)
		audio.play("place")
		_toast("Dropped TF2 entity %s at (%du, %du, %du)!" % [cls, int(pos.x * UPM), int(-pos.z * UPM), int(pos.y * UPM)])
	elif kind == "prop":
		var mdl: String = str(data.get("mdl", active_prop_mdl))
		var yaw_val: float = randf_range(0.0, 360.0) if prop_random_yaw else prop_yaw_deg
		var kv := {"model": mdl, "angles": "0 %d 0" % int(round(yaw_val)), "solid": "6", "skin": str(prop_skin)}
		if absf(prop_scale - 1.0) > 0.01:
			kv["modelscale"] = "%.2f" % prop_scale
		var eid: int = doc.add_point_entity("prop_static", pos, kv)
		_record_history("Drop Prop")
		if eid >= 0:
			ent_vis.sync_entity(eid, true)
			_select_entity(eid)
		else:
			ent_vis.sync_all()
		_spawn_place_fx(pos, HudWidgets.COL_ACC)
		audio.play("place")
		_toast("Dropped 3D TF2 prop: " + mdl.get_file())

func _project_screen_to_surface(screen_pos: Vector2) -> Dictionary:
	var ro := editor_cam.project_ray_origin(screen_pos)
	var rd := editor_cam.project_ray_normal(screen_pos)
	var rc: Dictionary = doc.raycast_face(ro, rd)
	if rc.get("hit", false):
		var hp: Vector3 = rc["hit_pos"]
		return {"valid": true, "pos": Vector3(snappedf(hp.x, grid_m), snappedf(hp.y, 0.25), snappedf(hp.z, grid_m))}
	if absf(rd.y) > 0.001:
		var t := -ro.y / rd.y
		if t > 0.1 and t < 350.0:
			var hp := ro + rd * t
			return {"valid": true, "pos": Vector3(snappedf(hp.x, grid_m), 0.0, snappedf(hp.z, grid_m))}
	return {"valid": false, "pos": Vector3.ZERO}

# ==============================================================================
# SETTINGS, STAGE, SELECTION & HAMMER ACTIONS
# ==============================================================================
func _on_settings_applied() -> void:
	settings.apply_runtime(self)
	_sync_grid_from_settings()
	split_2d_panel.visible = settings.show_2d_split and not viewing_bsp and stage != Stage.PLAYTEST
	if split_2d_panel.visible:
		right_drawer.visible = false
		_refresh_2d_views()

func _sync_grid_from_settings() -> void:
	var idx := GRID_STEPS.find(settings.default_grid_u)
	if idx >= 0:
		grid_idx = idx
	grid_m = float(GRID_STEPS[grid_idx]) / UPM
	doc.set_grid_units(GRID_STEPS[grid_idx])
	if grid_btn != null:
		grid_btn.text = "Grid: %du" % GRID_STEPS[grid_idx]

func _toggle_split_2d() -> void:
	settings.show_2d_split = not settings.show_2d_split
	split_2d_panel.visible = settings.show_2d_split and not viewing_bsp
	if split_2d_panel.visible:
		right_drawer.visible = false
		_refresh_2d_views()

func _refresh_2d_views() -> void:
	if bp_top != null and split_2d_panel.visible:
		bp_top.refresh(selected_solid, cam_pos)
	if bp_side != null and split_2d_panel.visible:
		bp_side.refresh(selected_solid, cam_pos)

func _sync_mode_visibility() -> void:
	var is_edit := (not viewing_bsp and stage != Stage.PLAYTEST)
	top_bar.visible = (stage != Stage.PLAYTEST)
	left_rail_panel.visible = is_edit
	status_pill.visible = is_edit
	for n in edit_only_top_nodes:
		if is_instance_valid(n):
			n.visible = is_edit
	if not is_edit:
		split_2d_panel.visible = false
		right_drawer.visible = false
		if context_bar != null: context_bar.visible = false
		if tool_hover_card != null: tool_hover_card.visible = false
	_update_3d_gizmo()

func _update_3d_gizmo() -> void:
	if _gizmo_root == null:
		return
	if viewing_bsp or stage == Stage.PLAYTEST:
		_gizmo_root.visible = false
		return
	if selected_solid >= 0:
		var info: Dictionary = doc.get_solid_info(selected_solid)
		var bmin: Vector3 = info.get("bounds_min", Vector3.ZERO)
		var bmax: Vector3 = info.get("bounds_max", Vector3.ZERO)
		_gizmo_root.position = (bmin + bmax) * 0.5
		_gizmo_root.visible = true
	elif selected_entity >= 0:
		var ents: Array = doc.get_entities()
		if selected_entity < ents.size():
			_gizmo_root.position = (ents[selected_entity]["pos"] as Vector3) + Vector3(0, 0.8, 0)
			_gizmo_root.visible = true
		else:
			_gizmo_root.visible = false
	else:
		_gizmo_root.visible = false

func _show_welcome_hub(show: bool) -> void:
	welcome_panel.visible = show
	if show and stage == Stage.PLAYTEST:
		set_stage(Stage.BUILD)

func _clear_selection() -> void:
	selected_solid = -1; selected_solids.clear(); selected_face = -1; selected_entity = -1
	map_sync.set_selection(-1, -1)
	ent_vis.set_selection(-1)
	_refresh_selection_bar()
	_refresh_2d_views()
	_update_3d_gizmo()

func _select_solid(sidx: int, fidx: int = -1, add_to_group: bool = false) -> void:
	if add_to_group and sidx >= 0:
		if selected_solids.has(sidx):
			selected_solids.erase(sidx)
			selected_solid = selected_solids[selected_solids.size() - 1] if not selected_solids.is_empty() else -1
		else:
			selected_solids.append(sidx)
			selected_solid = sidx
	else:
		selected_solids.clear()
		selected_solid = sidx
		if sidx >= 0:
			selected_solids.append(sidx)
	selected_face = fidx; selected_entity = -1
	ent_vis.set_selection(-1)
	map_sync.set_selection(selected_solid, fidx)
	_refresh_selection_bar()
	_refresh_2d_views()
	_update_3d_gizmo()

func _swap_team_material(mat: String) -> String:
	var m := mat.to_upper()
	var swaps := {
		"METAL/IMETAL001": "METAL/IMETAL002",
		"METAL/IMETAL002": "METAL/IMETAL001",
		"CONCRETE/COMPUTERWALL005C": "CONCRETE/COMPUTERWALL003C",
		"CONCRETE/COMPUTERWALL003C": "CONCRETE/COMPUTERWALL005C",
		"WOOD/WOOD_WALL007": "WOOD/WOOD_WALL005A",
		"WOOD/WOOD_WALL005A": "WOOD/WOOD_WALL007",
		"CONCRETE/CONCRETEWALL002A": "CONCRETE/CONCRETEWALL001D",
		"CONCRETE/CONCRETEWALL001D": "CONCRETE/CONCRETEWALL002A",
		"METAL/METALROOF004A": "METAL/METALROOF006A",
		"METAL/METALROOF006A": "METAL/METALROOF004A",
	}
	return str(swaps.get(m, mat))

func _mirror_selection_to_enemy() -> void:
	var targets: Array[int] = selected_solids.duplicate() if not selected_solids.is_empty() else ([selected_solid] if selected_solid >= 0 else [])
	if targets.is_empty():
		_toast("Select one or more solids first (Ctrl+Click for multi-select)!"); return
	var created: int = 0
	for sid in targets:
		var info: Dictionary = doc.get_solid_info(sid)
		var nid: int = doc.mirror_solid_x(sid, true)
		if nid >= 0:
			var swapped := _swap_team_material(str(info.get("material", "")))
			if swapped != str(info.get("material", "")):
				doc.set_solid_material(nid, swapped)
			created += 1
	if created > 0:
		_record_history("Mirror %d Solid(s) to Enemy Side" % created)
		map_sync.sync_all(); _refresh_2d_views(); audio.play("place")
		_toast("Mirrored %d solid(s) 180° to enemy side with automatic RED/BLU texture swap!" % created)

func _select_entity(eidx: int) -> void:
	selected_entity = eidx; selected_solid = -1; selected_face = -1
	map_sync.set_selection(-1, -1)
	ent_vis.set_selection(eidx)
	_refresh_selection_bar()
	_update_3d_gizmo()

func _step_grid(dir: int, wrap: bool = false) -> void:
	grid_idx = (grid_idx + dir) % GRID_STEPS.size() if wrap else clampi(grid_idx + dir, 0, GRID_STEPS.size() - 1)
	var u: int = GRID_STEPS[grid_idx]
	grid_m = float(u) / UPM
	doc.set_grid_units(u)
	grid_btn.text = "Grid: %du" % u
	_toast("Grid Snap: %du (use [ / ] to resize)" % u)

func set_stage(new_stage: int) -> void:
	_wall_chain_active = false
	_drawing_box = false
	if new_stage == Stage.PLAYTEST:
		if stage != Stage.PLAYTEST:
			_prev_stage = stage
		stage = Stage.PLAYTEST
		_enter_playtest()
	else:
		if stage == Stage.PLAYTEST:
			_exit_playtest()
		stage = new_stage
		map_sync.set_vertex_mode(false)
		if stage == Stage.BUILD: active_tool = "select"
		elif stage == Stage.GAMEPLAY: active_tool = "select"
		elif stage == Stage.STYLE:
			active_tool = "materials"
			if not viewing_bsp: _open_materials_drawer()

	for i in range(stage_btns.size()):
		HudWidgets.style_tf2_button(stage_btns[i], fonts["heading"], 11, i == stage)
	ghost_mesh.visible = false; brush_ring.visible = false
	_sync_mode_visibility()
	_rebuild_left_rail()
	_rebuild_bottom_dock()
	_refresh_context_bar()
	_refresh_selection_bar()
	if stage != Stage.STYLE or viewing_bsp:
		right_drawer.visible = false
	overlay_2d.queue_redraw()

func _select_tool(sid: String) -> void:
	active_tool = sid
	_wall_chain_active = false
	_drawing_box = false
	map_sync.set_vertex_mode(sid == "vertex")
	if sid == "vertex":
		_toast("Vertex Edit (Shift+V): Drag yellow corners (hold Shift to move UP/DOWN vertically!)")
	elif sid == "wall":
		_open_wall_box_drawer()
		_toast("Wall Chain Tool: Click Point A -> Click corners (RMB/Esc ends chain)")
	elif sid == "floor":
		_open_wall_box_drawer()
		_toast("Drag Box Tool: Click & Drag footprint using active material (adjust height on right)")
	elif sid == "building": _open_building_wizard()
	elif sid == "terrain": _open_terrain_studio()
	elif sid == "import3d": _open_import_model_drawer()
	elif sid == "biomes": _open_biomes_drawer()
	elif sid == "materials": _open_materials_drawer()
	elif sid == "props": _open_props_drawer()
	elif sid == "sky_sun": _open_sky_sun_drawer()
	else: right_drawer.visible = false
	_rebuild_left_rail()
	_rebuild_bottom_dock()
	_refresh_context_bar()

func _clear_drawer(title: String) -> void:
	_prop_preview_mesh = null
	_history_drawer_open = (title == "MAP HISTORY TIMELINE")
	if split_2d_panel.visible:
		split_2d_panel.visible = false
		settings.show_2d_split = false
	var was_hidden := not right_drawer.visible
	right_drawer_title.text = title
	for ch in right_drawer_vbox.get_children():
		ch.queue_free()
	right_drawer.visible = true
	if was_hidden and is_inside_tree():
		right_drawer.modulate = Color(1, 1, 1, 0)
		var tw := create_tween()
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(right_drawer, "modulate", Color.WHITE, 0.16)

## Tactile expanding amber/cyan ground ring whenever a brush, prefab, prop, or entity is placed!
func _spawn_place_fx(pos: Vector3, col: Color = HudWidgets.COL_ACC) -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 0.72; tm.outer_radius = 0.92
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col.r, col.g, col.b, 0.90)
	ring.material_override = mat
	ring.position = pos + Vector3(0, 0.12, 0)
	ring.scale = Vector3(0.25, 1.0, 0.25)
	add_child(ring)
	var tw := create_tween().set_parallel(true)
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(ring, "scale", Vector3(2.4, 1.0, 2.4), 0.28)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.28)
	tw.chain().tween_callback(ring.queue_free)

func _stamp_terrain_quick(kind: String) -> void:
	var p: Vector3 = hover_pos if hover_valid else Vector3(0, 0, -6)
	if kind == "cliff":
		var cid: int = doc.make_cliff_wall(p + Vector3(-8, 0, 0), p + Vector3(8, 0, 0), cliff_height_m, 2.5, cliff_power, "NATURE/BLENDROCKWALLDIRT001", 1.2)
		if cid >= 0:
			terrain_axis_mode = 0
			_record_history("Stamp Canyon Cliff"); map_sync.sync_all(); _select_solid(cid, -1)
			_spawn_place_fx(p, HudWidgets.COL_ACC); audio.play("place")
			_toast("Stamped Canyon Cliff! Switch to Sculpt Studio to shape it.")
	else:
		var sid: int = doc.make_terrain_patch(p + Vector3(-8, -1, -8), p + Vector3(8, 0, 8), 3, Tf2GamemodesScript.get_biome(active_biome)["floor"])
		if sid >= 0:
			if kind == "hill":
				doc.sculpt_terrain(p, 7.5, 2.6, 0, 1); doc.sculpt_terrain(p, 6.0, 0.8, 2, 1)
			elif kind == "mesa":
				doc.sculpt_terrain(p, 6.8, 3.2, 0, 1); doc.sculpt_terrain(p, 4.8, 3.0, 3, 1)
			elif kind == "crater":
				doc.sculpt_terrain(p, 6.5, 2.4, 1, 1)
			terrain_axis_mode = 1
			_record_history("Stamp " + kind.capitalize()); map_sync.sync_all(); _select_solid(sid, -1)
			_spawn_place_fx(p, HudWidgets.COL_GREEN); audio.play("place")
			_toast("Stamped %s displacement!" % kind.capitalize())

# Modular Drawer Bridges (delegating to EditorDrawers.gd!)
func _open_materials_drawer() -> void:
	_clear_drawer("FACE EDIT & VPK MATERIALS (SHIFT+A)")
	EditorDrawersScript.build_materials_drawer(self, right_drawer_vbox)

func _open_props_drawer() -> void:
	_clear_drawer("3D TF2 PROP BROWSER (ALL MODELS)")
	EditorDrawersScript.build_props_drawer(self, right_drawer_vbox)

func _open_fgd_entity_drawer() -> void:
	_clear_drawer("ALL 450+ TF2 FGD ENTITIES (SHIFT+E)")
	EditorDrawersScript.build_fgd_entity_drawer(self, right_drawer_vbox)

func _open_inspector_drawer() -> void:
	_clear_drawer("SMARTEDIT PROPERTIES (ALT+ENTER)")
	EditorDrawersScript.build_inspector_drawer(self, right_drawer_vbox)

func _open_terrain_studio() -> void:
	_clear_drawer("CLIFF & TERRAIN DISPLACEMENT STUDIO")
	EditorDrawersScript.build_terrain_drawer(self, right_drawer_vbox)

func _open_wall_box_drawer() -> void:
	_clear_drawer("WALL CHAIN & DRAG-BOX OPTIONS")
	EditorDrawersScript.build_wall_box_drawer(self, right_drawer_vbox)

func _open_check_problems_drawer() -> void:
	_clear_drawer("CHECK MAP FOR PROBLEMS (ALT+P)")
	EditorDrawersScript.build_check_problems_drawer(self, right_drawer_vbox)

func _open_visgroups_drawer() -> void:
	_clear_drawer("VISGROUPS (LAYER VISIBILITY)")
	var toggles := [
		{"lbl": "Triggers & Respawn Volumes", "val": ent_vis.show_triggers,      "fn": func(v: bool): ent_vis.show_triggers = v; ent_vis.sync_all()},
		{"lbl": "3D Props (.mdl)",            "val": ent_vis.show_props,         "fn": func(v: bool): ent_vis.show_props = v; ent_vis.sync_all()},
		{"lbl": "Point Lights",               "val": ent_vis.show_lights,        "fn": func(v: bool): ent_vis.show_lights = v; ent_vis.sync_all()},
		{"lbl": "Logic Entity Markers",       "val": ent_vis.show_logic_markers, "fn": func(v: bool): ent_vis.show_logic_markers = v; ent_vis.sync_all()},
		{"lbl": "3D I/O Logic Wires",         "val": ent_vis.show_logic_wires, "fn": func(v: bool): ent_vis.show_logic_wires = v; ent_vis.sync_all()},
		{"lbl": "Playerclip / Clip Brushes",  "val": map_sync.show_clips,   "fn": func(v: bool): map_sync.show_clips = v; map_sync.sync_all()},
		{"lbl": "Skybox Sealing Shell",       "val": map_sync.show_skybox_shell, "fn": func(v: bool): map_sync.show_skybox_shell = v; map_sync.sync_all()},
		{"lbl": "Reference Floor Grid",       "val": grid_floor.visible,    "fn": func(v: bool): grid_floor.visible = v},
	]
	for t in toggles:
		var cb := CheckButton.new(); cb.text = t["lbl"]; cb.button_pressed = bool(t["val"])
		cb.add_theme_font_override("font", fonts["body"]); cb.add_theme_font_size_override("font_size", 12)
		var fn: Callable = t["fn"]
		cb.toggled.connect(func(v: bool): audio.play("click"); fn.call(v))
		right_drawer_vbox.add_child(cb)
	var uh := Button.new(); uh.text = "Unhide All QuickHidden Objects (U)"
	HudWidgets.style_tf2_button(uh, fonts["heading"], 11, true)
	uh.pressed.connect(_do_unhide_all)
	right_drawer_vbox.add_child(uh)

func _open_clip_drawer() -> void:
	if selected_solid < 0:
		_toast("Select a brush solid first to slice with Shift+X Clip!")
		return
	_clear_drawer("CLIPPING TOOL (SHIFT+X)")
	var modes := ["Keep Both Halves (Split)", "Keep Front Half Only", "Keep Back Half Only"]
	for i in range(3):
		var b := Button.new(); b.text = modes[i]
		HudWidgets.style_tf2_button(b, fonts["body"], 11, _clip_keep_mode == i)
		var mi := i; b.pressed.connect(func(): _clip_keep_mode = mi; _open_clip_drawer())
		right_drawer_vbox.add_child(b)
	for spec in [
		{"t": "Slice Along X-Axis (North-South)", "n": Vector3(1, 0, 0), "acc": true},
		{"t": "Slice Along Z-Axis (East-West)",   "n": Vector3(0, 0, 1), "acc": false},
		{"t": "Slice 45° Diagonal Corner",        "n": Vector3(1, 0, 1).normalized(), "acc": false},
	]:
		var b := Button.new(); b.text = spec["t"]
		HudWidgets.style_tf2_button(b, fonts["heading"], 11, bool(spec["acc"]))
		var nn: Vector3 = spec["n"]
		b.pressed.connect(func(): _do_clip_selected(nn))
		right_drawer_vbox.add_child(b)

func _open_tie_entity_drawer() -> void:
	if selected_solid < 0:
		_toast("Select a brush solid first to Tie to Entity (Ctrl+T)!")
		return
	_clear_drawer("TIE TO ENTITY (CTRL+T)")
	for p in [
		{"cls": "func_detail",      "lbl": "func_detail (Non-Vis Detail Geometry)", "kv": {}},
		{"cls": "func_door",        "lbl": "func_door (Sliding TF2 Spawn Door!)",   "kv": {"speed": "380", "movedir": "-90 0 0", "wait": "2"}},
		{"cls": "func_respawnroom", "lbl": "func_respawnroom (RED Spawn Zone)",     "kv": {"TeamNum": "2"}},
		{"cls": "func_respawnroom", "lbl": "func_respawnroom (BLU Spawn Zone)",     "kv": {"TeamNum": "3"}},
		{"cls": "trigger_hurt",     "lbl": "trigger_hurt (Death Pit Hazard)",       "kv": {"damage": "999", "damagetype": "32"}},
		{"cls": "func_nobuild",     "lbl": "func_nobuild (Block Engi Buildings)",   "kv": {}},
		{"cls": "trigger_multiple", "lbl": "trigger_multiple (Logic Trigger)",      "kv": {"wait": "1"}},
	]:
		var b := Button.new(); b.text = p["lbl"]
		HudWidgets.style_tf2_button(b, fonts["body"], 11)
		var cs: String = p["cls"]; var kv_d: Dictionary = p["kv"]
		b.pressed.connect(func():
			var eidx: int = doc.tie_solid_to_entity(selected_solid, cs, kv_d)
			if eidx >= 0:
				_record_history("Tie to " + cs); map_sync.sync_all(); ent_vis.sync_all()
				_select_entity(eidx); audio.play("carve")
				_toast("Tied solid to %s (#%d)!" % [cs, eidx]); _open_inspector_drawer()
		)
		right_drawer_vbox.add_child(b)

func _open_building_wizard() -> void:
	_clear_drawer("MODULAR BUILDING WIZARD")
	var fl_row := HBoxContainer.new(); right_drawer_vbox.add_child(fl_row)
	for f: int in [1, 2, 3]:
		var b := Button.new(); b.text = "%d Floor%s" % [f, "s" if f > 1 else ""]; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["heading"], 11, bld_floors == f)
		var fv: int = f; b.pressed.connect(func(): bld_floors = fv; _open_building_wizard())
		fl_row.add_child(b)
	var rf_row := HBoxContainer.new(); right_drawer_vbox.add_child(rf_row)
	var rnames := ["Flat", "Gabled Barn", "Slanted"]
	for i in range(3):
		var b := Button.new(); b.text = rnames[i]; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["body"], 11, bld_roof_style == i)
		var rv := i; b.pressed.connect(func(): bld_roof_style = rv; _open_building_wizard())
		rf_row.add_child(b)
	var sb := Button.new(); sb.text = "Stamp Building at Cursor / Origin"
	HudWidgets.style_tf2_button(sb, fonts["heading"], 12, true)
	sb.pressed.connect(func(): _place_tool_at(hover_pos if hover_valid else Vector3.ZERO))
	right_drawer_vbox.add_child(sb)

func _open_import_model_drawer() -> void:
	_clear_drawer("EASY 3D MODEL IMPORTER")
	var pick_b := Button.new(); pick_b.text = "Browse .OBJ / .GLB / .GLTF..."
	HudWidgets.style_tf2_button(pick_b, fonts["heading"], 13, true)
	pick_b.pressed.connect(func(): _open_file_dialog("model"))
	right_drawer_vbox.add_child(pick_b)
	var sample_obj: String = repo_root.path_join("godot/maps/imported_models/custom_pylon.obj")
	if FileAccess.file_exists(sample_obj):
		var sb := Button.new(); sb.text = "Quick Test: Place Sample Custom Pylon"
		HudWidgets.style_tf2_button(sb, fonts["body"], 11)
		sb.pressed.connect(func(): _import_3d_model_file(sample_obj))
		right_drawer_vbox.add_child(sb)

func _open_biomes_drawer() -> void:
	_clear_drawer("1-CLICK TF2 BIOME THEMES")
	for bkey in Tf2GamemodesScript.BIOMES.keys():
		var b: Dictionary = Tf2GamemodesScript.BIOMES[bkey]
		var btn := Button.new(); btn.text = "%s (%s)" % [b["name"], b["sky"]]
		HudWidgets.style_tf2_button(btn, fonts["body"], 12, active_biome == bkey)
		var k: String = bkey
		btn.pressed.connect(func(): audio.play("carve"); _apply_biome(k); _open_biomes_drawer())
		right_drawer_vbox.add_child(btn)

func _open_sky_sun_drawer() -> void:
	_clear_drawer("SKYBOX & SUN STUDIO")
	var yaw_sl := HSlider.new(); yaw_sl.min_value = -180; yaw_sl.max_value = 180; yaw_sl.value = sun.rotation_degrees.y
	yaw_sl.value_changed.connect(func(v): sun.rotation_degrees.y = v); right_drawer_vbox.add_child(yaw_sl)
	var pitch_sl := HSlider.new(); pitch_sl.min_value = -80; pitch_sl.max_value = -12; pitch_sl.value = sun.rotation_degrees.x
	pitch_sl.value_changed.connect(func(v): sun.rotation_degrees.x = v); right_drawer_vbox.add_child(pitch_sl)
	for sky in core.list_skyboxes():
		var b := Button.new(); b.text = sky
		HudWidgets.style_tf2_button(b, fonts["body"], 11, active_sky == sky)
		var sk: String = sky
		b.pressed.connect(func():
			active_sky = sk; doc.set_skyname(sk); we.environment.sky = assets.get_sky(sk)
			audio.play("click"); _open_sky_sun_drawer()
		)
		right_drawer_vbox.add_child(b)

func _open_compile_drawer() -> void:
	_clear_drawer("COMPILE TO REAL TF2 (.BSP)")
	var paths: Dictionary = compile_ctrl.detect_paths()
	var plbl := Label.new()
	plbl.text = "Valve Compilers: %s  |  Default Preset: %s\nVAC-Safe Lock: -insecure +sv_lan 1 ALWAYS ON" % [
		"READY" if paths.get("valid", false) else "Not Found", settings.compile_preset
	]
	plbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; plbl.add_theme_font_size_override("font_size", 11)
	plbl.add_theme_color_override("font_color", HudWidgets.COL_GREEN)
	right_drawer_vbox.add_child(plbl)

	for spec in [
		{"id": "Fast",          "t": "Fast Compile (vbsp + vvis -fast + vrad)", "fast": true,  "vis": true,  "rad": true,  "run": false, "team": 0},
		{"id": "Default",       "t": "Default Standard Compile (Normal VVIS)",  "fast": false, "vis": true,  "rad": true,  "run": false, "team": 0},
		{"id": "Only Entities", "t": "Only Entities / Geometry (vbsp only)",    "fast": true,  "vis": false, "rad": false, "run": false, "team": 0},
		{"id": "HDR Full",      "t": "HDR Full Compile (HDR + LDR Lighting)",   "fast": false, "vis": true,  "rad": true,  "run": false, "team": 0},
		{"id": "HDR Final",     "t": "HDR Final Release Compile",               "fast": false, "vis": true,  "rad": true,  "run": false, "team": 0},
		{"id": "Launch",        "t": "Compile & Launch in Real TF2 (-insecure)","fast": true,  "vis": true,  "rad": true,  "run": true,  "team": 2},
	]:
		var b := Button.new(); b.text = spec["t"]
		var is_def: bool = (str(spec["id"]) == str(settings.compile_preset))
		HudWidgets.style_tf2_button(b, fonts["heading"], 11, is_def, int(spec["team"]))
		var sp: Dictionary = spec
		b.pressed.connect(func(): _run_compile(bool(sp["fast"]), bool(sp["vis"]), bool(sp["rad"]), bool(sp["run"])))
		right_drawer_vbox.add_child(b)

	var seal_b := Button.new(); seal_b.text = "1-Click Auto-Seal Skybox"
	HudWidgets.style_tf2_button(seal_b, fonts["body"], 12); seal_b.pressed.connect(_do_auto_seal)
	right_drawer_vbox.add_child(seal_b)

# ==============================================================================
# SOLID / ENTITY EDIT HELPERS
# ==============================================================================
func _commit_solid_edit(label: String) -> void:
	_record_history(label); map_sync.sync_all(); _refresh_selection_bar(); _refresh_2d_views(); audio.play("place")

func _untie_selected_entity() -> void:
	if selected_entity < 0:
		return
	var ids: PackedInt32Array = doc.untie_brush_entity(selected_entity)
	if not ids.is_empty():
		_record_history("Move to World")
		map_sync.sync_all(); ent_vis.sync_all()
		_select_solid(ids[0], -1)
		audio.play("place")
		_toast("Moved brush entity back to World Solid #%d (Ctrl+Shift+W)!" % ids[0])

func _push_selected_top(delta_m: float) -> void:
	if selected_solid >= 0 and doc.push_pull_normal(selected_solid, Vector3(0, 1, 0), delta_m):
		_commit_solid_edit("Push/Pull Top")

func _do_hollow_selected() -> void:
	if selected_solid < 0:
		_toast("Select a box solid first to Make Hollow!")
		return
	var ids: PackedInt32Array = doc.make_hollow(selected_solid, -0.5)
	if not ids.is_empty():
		_record_history("Make Hollow"); _clear_selection(); map_sync.sync_all(); audio.play("carve")
		_toast("Hollowed solid into %d walls (-16u outward shell)!" % ids.size())

func _do_quickhide_selected() -> void:
	if selected_solid >= 0:
		doc.set_solid_hidden(selected_solid, true)
		_record_history("QuickHide Solid")
		_clear_selection(); map_sync.sync_all()
		_toast("QuickHid solid (press U to Unhide All or Ctrl+Z)")

func _do_unhide_all() -> void:
	var n: int = doc.unhide_all()
	if n > 0: _record_history("Unhide All")
	map_sync.sync_all(); ent_vis.sync_all()
	_toast("Restored %d hidden object(s)!" % n)

func _do_clip_selected(normal: Vector3) -> void:
	if selected_solid < 0: return
	var info: Dictionary = doc.get_solid_info(selected_solid)
	if not info.get("valid", false): return
	var mid: Vector3 = (info["bounds_min"] + info["bounds_max"]) * 0.5
	var res: int = doc.clip_solid(selected_solid, mid, normal, _clip_keep_mode)
	if res >= 0:
		_record_history("Clip Solid"); map_sync.sync_all(); _select_solid(res, -1); audio.play("carve")
		_toast("Clipped solid cleanly!")

func _rotate_selection() -> void:
	if selected_solid >= 0:
		if doc.rotate_solid_y(selected_solid, float(settings.rotate_step_deg)):
			_commit_solid_edit("Rotate Solid")
	elif selected_entity >= 0:
		var ents: Array = doc.get_entities()
		if selected_entity < ents.size():
			var parts := str(ents[selected_entity]["kv"].get("angles", "0 0 0")).split(" ", false)
			var p := float(parts[0]) if parts.size() > 0 else 0.0
			var y := fposmod((float(parts[1]) if parts.size() > 1 else 0.0) + float(settings.rotate_step_deg), 360.0)
			var r := float(parts[2]) if parts.size() > 2 else 0.0
			doc.set_entity_kv(selected_entity, "angles", "%.0f %.0f %.0f" % [p, y, r])
			_record_history("Rotate Entity"); ent_vis.sync_all(); audio.play("click")

func _duplicate_selection() -> void:
	if selected_solid >= 0:
		var nid: int = doc.duplicate_solid(selected_solid, Vector3(grid_m, 0, 0))
		if nid >= 0: _record_history("Duplicate Solid"); map_sync.sync_all(); _select_solid(nid, -1); audio.play("place")
	elif selected_entity >= 0:
		var nid: int = doc.duplicate_entity(selected_entity, Vector3(grid_m, 0, 0))
		if nid >= 0: _record_history("Duplicate Entity"); ent_vis.sync_all(); _select_entity(nid); audio.play("place")

func _delete_selection() -> void:
	if selected_solid >= 0:
		var idx := selected_solid
		if doc.delete_solid(idx):
			_record_history("Delete Solid"); _clear_selection(); map_sync.sync_all(); audio.play("delete")
			_toast("Deleted Solid #%d (Ctrl+Z to Undo)" % idx)
	elif selected_entity >= 0:
		var idx := selected_entity
		if doc.delete_entity(idx):
			_record_history("Delete Entity"); _clear_selection(); ent_vis.sync_all(); audio.play("delete")
			_toast("Deleted Entity #%d (Ctrl+Z to Undo)" % idx)

func _nudge_selection(delta: Vector3) -> void:
	if not settings.arrow_key_nudge: return
	if selected_solid >= 0 and doc.translate_solid(selected_solid, delta):
		_commit_solid_edit("Nudge Solid")
	elif selected_entity >= 0:
		var ents: Array = doc.get_entities()
		if selected_entity < ents.size():
			doc.set_entity_pos(selected_entity, ents[selected_entity]["pos"] + delta)
			_record_history("Nudge Entity"); ent_vis.sync_all()

# ==============================================================================
# MAP LOADING, SAVING, COMPILING & PLAYTEST
# ==============================================================================
func _load_gamemode(mode_id: String, biome_override: String = "", show_toast: bool = true) -> void:
	_clear_official_bsp(); _clear_selection()
	active_gamemode = mode_id
	_dock_ent_cat = "_mode"
	var meta: Dictionary = Tf2GamemodesScript.build_gamemode_template(doc, mode_id, biome_override)
	active_biome = meta["biome"]; active_sky = meta["sky"]
	_apply_environment_from_biome(active_biome)
	grid_floor.visible = settings.show_grid_floor
	map_sync.clear_all(); map_sync.sync_all(); ent_vis.sync_all()
	map_title_lbl.text = "| " + str(meta["map_name"])
	_reset_history("New %s Map" % mode_id.to_upper())
	_sync_mode_visibility(); _rebuild_bottom_dock(); _refresh_2d_views()
	if show_toast: _toast("Created %s starter map â€” sealed & ready to edit or F5 playtest!" % mode_id.to_upper())

func _load_official_bsp(map_name: String) -> void:
	_clear_official_bsp(); _clear_selection()
	map_sync.clear_all(); ent_vis.clear_all(); door_ctrl.clear()

	var res: Dictionary = bsp_loader.load_bsp_into(map_name, bsp_root, door_ctrl)
	if not res.get("ok", false):
		_toast("Could not load %s: %s" % [map_name, str(res.get("error", ""))])
		return

	viewing_bsp = true; current_bsp_name = map_name
	active_sky = str(res.get("skyname", "sky_badlands_01"))
	we.environment.sky = assets.get_sky(active_sky)
	if bool(res.get("has_sun", false)):
		sun.rotation_degrees = Vector3(float(res.get("sun_pitch", -45.0)), float(res.get("sun_yaw", 45.0)) - 90.0, 0.0)
		sun.light_color = res.get("sun_color", Color(1.0, 0.96, 0.90))
	current_bsp_spawn = res.get("spawn_pos", Vector3(0, 2, 0))
	current_bsp_yaw = float(res.get("spawn_yaw", 0.0))
	map_title_lbl.text = "| [OFFICIAL] " + map_name
	grid_floor.visible = false; sym_plane.visible = false; ghost_mesh.visible = false; brush_ring.visible = false
	cam_pos = current_bsp_spawn + Vector3(12, 10, 12)
	_apply_editor_cam()
	_sync_mode_visibility(); _rebuild_bottom_dock(); _refresh_selection_bar(); overlay_2d.queue_redraw()
	_toast("Loaded %s (%d props, %d sliding doors, %.2fs) â€” press F5 to walk inside!" % [
		map_name, int(res.get("prop_count", 0)), int(res.get("door_count", 0)), float(res.get("load_ms", 0.0)) / 1000.0
	])

func _clear_official_bsp() -> void:
	viewing_bsp = false; current_bsp_name = ""; door_ctrl.clear()
	for ch in bsp_root.get_children(): ch.queue_free()
	for ch in imported_props_root.get_children(): ch.queue_free()

func _apply_biome(bkey: String) -> void:
	active_biome = bkey
	var b: Dictionary = Tf2GamemodesScript.get_biome(bkey)
	active_sky = b["sky"]; doc.set_skyname(active_sky)
	doc.apply_theme_materials(b["floor"], b["wall"], b["roof"])
	_record_history("Apply " + b["name"]); _apply_environment_from_biome(bkey); map_sync.sync_all()
	_toast("Applied %s biome & %s skybox!" % [b["name"], active_sky])

func _apply_environment_from_biome(bkey: String) -> void:
	var b: Dictionary = Tf2GamemodesScript.get_biome(bkey)
	we.environment.sky = assets.get_sky(b["sky"]); sun.light_color = b["sun_color"]; sun.rotation_degrees = b["sun_angles"]

func _save_current_vmf() -> String:
	DirAccess.make_dir_recursive_absolute(repo_root.path_join("godot/maps"))
	var mname: String = doc.get_map_name()
	if mname.is_empty(): mname = "pb_untitled"
	var path := repo_root.path_join("godot/maps/" + mname + ".vmf")
	var r: Dictionary = doc.save_vmf(path)
	if r.get("ok", false):
		doc.clear_dirty()
		audio.play("save")
		_toast("Saved " + path.get_file())
		return path
	audio.play("warn")
	_toast("Save failed: " + str(r.get("error", ""))); return ""

func _time_stamp_str() -> String:
	var dt := Time.get_time_dict_from_system()
	return "%02d:%02d:%02d" % [int(dt["hour"]), int(dt["minute"]), int(dt["second"])]

func _reset_history(initial_label: String = "Initial Map") -> void:
	_history_entries.clear()
	_history_entries.append({"label": initial_label, "time": _time_stamp_str()})
	_history_idx = 0
	_update_history_buttons()
	if _history_drawer_open and right_drawer.visible:
		_open_history_drawer()

func _record_history(label: String) -> void:
	doc.record_undo(label)
	if _history_idx < _history_entries.size() - 1:
		_history_entries.resize(_history_idx + 1)
	_history_entries.append({"label": label, "time": _time_stamp_str()})
	if _history_entries.size() > 64:
		_history_entries.pop_front()
	_history_idx = _history_entries.size() - 1
	_update_history_buttons()
	if _history_drawer_open and right_drawer.visible:
		_open_history_drawer()

func _update_history_buttons() -> void:
	if undo_btn != null:
		var can_u := (_history_idx > 0)
		undo_btn.disabled = not can_u
		undo_btn.tooltip_text = "Undo: %s (Ctrl+Z)" % str(_history_entries[_history_idx]["label"]) if can_u else "Nothing to Undo"
	if redo_btn != null:
		var can_r := (_history_idx < _history_entries.size() - 1)
		redo_btn.disabled = not can_r
		redo_btn.tooltip_text = "Redo: %s (Ctrl+Y)" % str(_history_entries[_history_idx + 1]["label"]) if can_r else "Nothing to Redo"
	if history_btn != null:
		history_btn.text = "History (%d)" % maxi(1, _history_entries.size())

func _open_history_drawer() -> void:
	_clear_drawer("MAP HISTORY TIMELINE")
	EditorDrawersScript.build_history_drawer(self, right_drawer_vbox)

func _jump_to_history(target_idx: int) -> void:
	target_idx = clampi(target_idx, 0, _history_entries.size() - 1)
	if target_idx == _history_idx:
		return
	var moved := false
	var going_back := (target_idx < _history_idx)
	while _history_idx > target_idx:
		if not doc.undo(): break
		_history_idx -= 1; moved = true
	while _history_idx < target_idx:
		if not doc.redo(): break
		_history_idx += 1; moved = true
	if moved:
		_clear_selection(); map_sync.sync_all(); ent_vis.sync_all()
		_update_history_buttons()
		audio.play("undo" if going_back else "redo")
		_toast("Jumped to History #%d: %s" % [_history_idx, str(_history_entries[_history_idx]["label"])])
		if _history_drawer_open and right_drawer.visible:
			_open_history_drawer()

func _do_undo() -> void:
	if doc.undo():
		var undone_lbl: String = str(_history_entries[_history_idx]["label"]) if _history_idx < _history_entries.size() else "Last Edit"
		_history_idx = maxi(0, _history_idx - 1)
		_clear_selection(); map_sync.sync_all(); ent_vis.sync_all()
		_update_history_buttons()
		audio.play("undo")
		_toast("Undid: %s (Ctrl+Y to Redo)" % undone_lbl)
		if _history_drawer_open and right_drawer.visible:
			_open_history_drawer()
	else:
		audio.play("warn")
		_toast("Nothing to Undo")

func _do_redo() -> void:
	if doc.redo():
		_history_idx = mini(_history_entries.size() - 1, _history_idx + 1)
		var redone_lbl: String = str(_history_entries[_history_idx]["label"]) if _history_idx < _history_entries.size() else "Edit"
		_clear_selection(); map_sync.sync_all(); ent_vis.sync_all()
		_update_history_buttons()
		audio.play("redo")
		_toast("Redid: %s" % redone_lbl)
		if _history_drawer_open and right_drawer.visible:
			_open_history_drawer()
	else:
		audio.play("warn")
		_toast("Nothing to Redo")

func _do_auto_seal() -> void:
	doc.auto_seal_skybox(); _record_history("Auto-Seal Skybox"); compile_ctrl.clear_leak_laser(); map_sync.sync_all()
	audio.play("save")
	_toast("Map sealed cleanly with invisible TOOLSSKYBOX shell!")

func _run_compile(fast: bool, vvis: bool, vrad: bool, launch_tf2: bool) -> void:
	if settings.auto_seal_on_compile and not doc.is_map_sealed():
		doc.auto_seal_skybox()
	var vmf := _save_current_vmf()
	if vmf.is_empty(): return
	if compile_ctrl.start_compile(vmf, fast, vvis, vrad, launch_tf2, doc.get_map_name()):
		_toast("Compiling %s with Valve vbsp..." % doc.get_map_name())

func _on_compile_status(st: Dictionary) -> void:
	_toast("Compiling [%s] %.1fs..." % [str(st.get("stage", "")), float(st.get("elapsed", 0.0))])

func _on_compile_finished(st: Dictionary) -> void:
	if not str(st.get("leak_file", "")).is_empty():
		audio.play("warn")
		_toast("LEAK DETECTED! Red 3D Leak Laser drawn â€” open Check (Alt+P) to seal!")
	elif st.get("succeeded", false):
		audio.play("success")
		_toast("Compile SUCCEEDED (%.1fs) â€” 0 leaks!" % float(st.get("elapsed", 0.0)))
	else:
		audio.play("warn")
		_toast("Compile failed in stage: " + str(st.get("stage", "")))

func _open_file_dialog(kind: String) -> void:
	file_dialog.set_meta("kind", kind)
	file_dialog.title = "Open Valve Map File (.vmf)" if kind == "vmf" else "Import 3D Model (.obj, .glb, .gltf)"
	file_dialog.filters = PackedStringArray(["*.vmf ; Valve Map Files"] if kind == "vmf" else ["*.obj, *.glb, *.gltf ; 3D Models"])
	file_dialog.popup_centered()

func _on_file_selected(path: String) -> void:
	if str(file_dialog.get_meta("kind", "model")) == "vmf":
		var r: Dictionary = doc.load_vmf(path)
		if not r.get("ok", false):
			_toast("Failed to open %s: %s" % [path.get_file(), str(r.get("error", "invalid VMF"))])
			return
		_clear_official_bsp(); _clear_selection()
		doc.clear_dirty()
		active_sky = doc.get_skyname(); we.environment.sky = assets.get_sky(active_sky)
		grid_floor.visible = settings.show_grid_floor
		map_sync.clear_all(); map_sync.sync_all(); ent_vis.sync_all()
		map_title_lbl.text = "| " + doc.get_map_name()
		_sync_mode_visibility(); _rebuild_bottom_dock(); _show_welcome_hub(false)
		_toast("Opened " + path.get_file())
	else:
		_import_3d_model_file(path)

func _import_3d_model_file(path: String) -> void:
	var imp: Dictionary = ModelImporterScript.import_model(path, 2.5, 1.0)
	if not imp.get("ok", false): _toast("Import error: " + str(imp.get("error", ""))); return
	var node: Node3D = imp["node"]; node.position = hover_pos if hover_valid else Vector3.ZERO
	imported_props_root.add_child(node)
	ModelImporterScript.export_tf2_qc_smd(repo_root.path_join("godot/maps/exported_qc"), imp["name"], imp["mesh"], float(imp["scale"]))
	audio.play("success", -10.0)
	_toast("Imported %s (%.0fu tall) + exported Valve .QC/.SMD!" % [imp["name"], (imp["size_u"] as Vector3).y])

func _cycle_symmetry() -> void:
	symmetry = (symmetry + 1) % 3
	sym_plane.visible = (symmetry != SymmetryMode.OFF) and not viewing_bsp
	var names := ["Sym: Off", "Sym: Mirror", "Sym: 180°"]
	sym_btn.text = names[symmetry]; _toast("Symmetry Mode: " + names[symmetry])

func _toggle_2d_view() -> void:
	top_down_2d = not top_down_2d
	if top_down_2d:
		editor_cam.projection = Camera3D.PROJECTION_ORTHOGONAL; editor_cam.size = 56.0
		editor_cam.look_at_from_position(Vector3(cam_pos.x, 80.0, cam_pos.z), Vector3(cam_pos.x, 0.0, cam_pos.z), Vector3(0, 0, -1))
	else:
		editor_cam.projection = Camera3D.PROJECTION_PERSPECTIVE; _apply_editor_cam()

func _enter_playtest() -> void:
	get_viewport().gui_release_focus()
	toast_panel.visible = false
	var sp := Vector3(0, 1.5, 0); var yaw := 0.0; var ents: Array = []
	if viewing_bsp:
		sp = current_bsp_spawn; yaw = current_bsp_yaw
	else:
		ents = doc.get_entities()
		for e in ents:
			if str(e["classname"]) == "info_player_teamspawn":
				sp = e["pos"]
				var to_mid := Vector2(-sp.x, -sp.z)
				yaw = rad_to_deg(atan2(-to_mid.x, -to_mid.y))
				break
	door_ctrl.reset_all_closed()
	ent_vis.set_playtest_mode(true)
	editor_cam.current = false
	player.spawn_at(sp, yaw, ents)
	player.set_tf2_class(settings.default_playtest_class)
	player.set_active(true)
	playtest_hud.visible = true; selection_bar.visible = false
	sym_plane.visible = false; ghost_mesh.visible = false; brush_ring.visible = false
	_sync_mode_visibility()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _exit_playtest() -> void:
	player.set_active(false); editor_cam.current = true; playtest_hud.visible = false
	ent_vis.set_playtest_mode(false)
	door_ctrl.reset_all_closed()
	sym_plane.visible = (symmetry != SymmetryMode.OFF) and not viewing_bsp
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ==============================================================================
# 3D INTERACTION, DRAG-BOX, WALL CHAIN, VERTEX DRAG, FACE-PULL & HOTKEYS
# ==============================================================================
func _is_typing_in_ui() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit

func _input(event: InputEvent) -> void:
	# Always catch mouse button RELEASES & ESC focus release even over HUD panels so drags/mouselook NEVER get stuck!
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_rmb_looking = false
			elif mb.button_index == MOUSE_BUTTON_MIDDLE:
				_mmb_panning = false
			elif mb.button_index == MOUSE_BUTTON_LEFT:
				if _dragging_gizmo:
					_dragging_gizmo = false; _record_history("Move Axis"); _refresh_selection_bar(); _update_3d_gizmo()
				if _dragging_vertex:
					_dragging_vertex = false; _record_history("Move Vertex"); _refresh_selection_bar()
				if _dragging_face:
					_dragging_face = false; _record_history("Push/Pull Face"); _refresh_selection_bar()
				if _dragging_move:
					_dragging_move = false; _record_history("Move Selection"); _refresh_selection_bar()
				if _drawing_box:
					_finish_drag_box()
				if _terrain_sculpting:
					_terrain_sculpting = false
					if _terrain_changed:
						map_sync.sync_all(); _record_history("Sculpt Terrain"); _terrain_changed = false
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _is_typing_in_ui():
			get_viewport().gui_release_focus()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if settings_modal.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			settings_modal.cancel_modal()
		return
	if welcome_panel.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_show_welcome_hub(false)
		return

	if event is InputEventKey:
		if _is_typing_in_ui() and event.keycode != KEY_ESCAPE:
			return
		if event.pressed and not event.echo:
			if event.keycode == KEY_COMMA and event.ctrl_pressed:
				settings_modal.open_modal(); return
			if event.keycode == KEY_F5:
				set_stage(_prev_stage if stage == Stage.PLAYTEST else Stage.PLAYTEST); return
			if event.keycode == KEY_F9 and not viewing_bsp and stage != Stage.PLAYTEST:
				_open_compile_drawer(); return
			if event.keycode == KEY_ESCAPE:
				if stage == Stage.PLAYTEST: set_stage(_prev_stage)
				elif _wall_chain_active: _wall_chain_active = false; ghost_mesh.visible = false; _toast("Finished wall chain")
				elif _drawing_box: _drawing_box = false; ghost_mesh.visible = false
				elif selected_solid >= 0 or selected_entity >= 0: _clear_selection()
				elif right_drawer.visible: right_drawer.visible = false
				return
			if stage == Stage.PLAYTEST:
				player.handle_key_press(event.keycode); return
			if event.keycode == KEY_Q:
				pie_wheel.open_at(get_viewport().get_mouse_position()); return
			elif event.keycode == KEY_L:
				ent_vis.show_logic_wires = not ent_vis.show_logic_wires; ent_vis.sync_all()
			elif event.keycode == KEY_Z and event.ctrl_pressed and event.shift_pressed: _do_redo()
			elif event.keycode == KEY_Z and event.ctrl_pressed: _do_undo()
			elif event.keycode == KEY_Y and event.ctrl_pressed: _do_redo()
			elif event.keycode == KEY_S and event.ctrl_pressed: _save_current_vmf()
			elif (event.keycode == KEY_EQUAL or event.keycode == KEY_KP_ADD) and event.ctrl_pressed:
				settings.ui_scale = clampf(snappedf(settings.ui_scale + 0.15, 0.05), 0.75, 2.25)
				settings.save_to_disk(); _on_settings_applied(); audio.play("click")
				_toast("UI Scale: %d%%  (Ctrl+= / Ctrl+- to zoom)" % int(round(settings.ui_scale * 100.0)))
			elif (event.keycode == KEY_MINUS or event.keycode == KEY_KP_SUBTRACT) and event.ctrl_pressed:
				settings.ui_scale = clampf(snappedf(settings.ui_scale - 0.15, 0.05), 0.75, 2.25)
				settings.save_to_disk(); _on_settings_applied(); audio.play("click")
				_toast("UI Scale: %d%%  (Ctrl+= / Ctrl+- to zoom)" % int(round(settings.ui_scale * 100.0)))
			elif event.keycode == KEY_0 and event.ctrl_pressed:
				settings.ui_scale = 1.15
				settings.save_to_disk(); _on_settings_applied(); audio.play("click")
				_toast("UI Scale reset to 115%")
			elif event.keycode == KEY_D and event.ctrl_pressed: _duplicate_selection()
			elif event.keycode == KEY_W and event.ctrl_pressed and event.shift_pressed: _untie_selected_entity()
			elif event.keycode == KEY_T and event.ctrl_pressed: _open_tie_entity_drawer()
			elif event.keycode == KEY_X and event.shift_pressed: _open_clip_drawer()
			elif event.keycode == KEY_V and event.shift_pressed: _select_tool("vertex")
			elif event.keycode == KEY_E and event.shift_pressed: _open_fgd_entity_drawer()
			elif event.keycode == KEY_A and event.shift_pressed: set_stage(Stage.STYLE); _open_materials_drawer()
			elif event.keycode == KEY_P and event.alt_pressed: _open_check_problems_drawer()
			elif (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and event.alt_pressed: _open_inspector_drawer()
			elif event.keycode == KEY_DELETE: _delete_selection()
			elif event.keycode == KEY_BRACKETLEFT: _step_grid(-1)
			elif event.keycode == KEY_BRACKETRIGHT: _step_grid(1)
			elif event.keycode == KEY_R and not event.ctrl_pressed: _rotate_selection()
			elif event.keycode == KEY_H and not event.ctrl_pressed: _do_quickhide_selected()
			elif event.keycode == KEY_U and not event.ctrl_pressed: _do_unhide_all()
			elif event.keycode == KEY_SPACE: _toggle_2d_view()
			elif selected_solid >= 0 or selected_entity >= 0:
				var fwd_h := Vector3(-editor_cam.global_transform.basis.z.x, 0.0, -editor_cam.global_transform.basis.z.z).normalized()
				var right_h := Vector3(editor_cam.global_transform.basis.x.x, 0.0, editor_cam.global_transform.basis.x.z).normalized()
				var snap_axis := func(v: Vector3) -> Vector3:
					return Vector3(signf(v.x), 0.0, 0.0) if absf(v.x) >= absf(v.z) else Vector3(0.0, 0.0, signf(v.z))
				if event.keycode == KEY_UP: _nudge_selection(snap_axis.call(fwd_h) * grid_m)
				elif event.keycode == KEY_DOWN: _nudge_selection(-snap_axis.call(fwd_h) * grid_m)
				elif event.keycode == KEY_RIGHT: _nudge_selection(snap_axis.call(right_h) * grid_m)
				elif event.keycode == KEY_LEFT: _nudge_selection(-snap_axis.call(right_h) * grid_m)
				elif event.keycode == KEY_PAGEUP: _nudge_selection(Vector3(0, grid_m, 0))
				elif event.keycode == KEY_PAGEDOWN: _nudge_selection(Vector3(0, -grid_m, 0))
			elif stage == Stage.BUILD and not viewing_bsp:
				var num_tools := {KEY_1: "select", KEY_2: "floor", KEY_3: "wall", KEY_4: "building", KEY_5: "ramp", KEY_6: "stairs", KEY_7: "arch", KEY_8: "carve", KEY_9: "terrain"}
				if num_tools.has(event.keycode): _select_tool(num_tools[event.keycode])
		elif not event.pressed and event.keycode == KEY_Q:
			pie_wheel.close_and_commit(); return

	if stage == Stage.PLAYTEST:
		if event is InputEventMouseMotion:
			var rel: Vector2 = event.relative
			if settings.invert_y: rel.y = -rel.y
			player.handle_mouse_motion(rel)
		elif event is InputEventMouseButton:
			if event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			player.handle_mouse_button(event.button_index, event.pressed)
		return

	if event is InputEventMouseMotion:
		if pie_wheel.visible: pie_wheel.update_pointer(event.position); return
		if _dragging_gizmo: _update_gizmo_drag(event.position); return
		if _dragging_vertex: _update_vertex_drag(event.position, event.shift_pressed); return
		if _dragging_face: _update_face_drag(event.position); return
		if _dragging_move: _update_move_drag(event.position); return
		if _rmb_looking and not top_down_2d:
			var dy: float = -event.relative.y if settings.invert_y else event.relative.y
			cam_yaw -= event.relative.x * settings.mouse_sens
			cam_pitch = clamp(cam_pitch - dy * settings.mouse_sens, -1.48, 1.48)
			_apply_editor_cam()
		elif _mmb_panning:
			var r := editor_cam.global_transform.basis.x; var u := editor_cam.global_transform.basis.y
			cam_pos -= r * event.relative.x * 0.04 - u * event.relative.y * 0.04
			_apply_editor_cam()
		else:
			_update_hover(event.position)
			if _terrain_sculpting and active_tool == "terrain" and hover_valid:
				_do_terrain_sculpt_stroke()

	elif event is InputEventMouseButton:
		if event.pressed:
			get_viewport().gui_release_focus()
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed and _wall_chain_active:
				_wall_chain_active = false; ghost_mesh.visible = false; _toast("Ended wall chain")
			_rmb_looking = event.pressed
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_mmb_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			if top_down_2d: editor_cam.size = max(12.0, editor_cam.size * 0.88)
			else: cam_pos += (-editor_cam.global_transform.basis.z) * 2.2; _apply_editor_cam()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			if top_down_2d: editor_cam.size = min(180.0, editor_cam.size * 1.12)
			else: cam_pos -= (-editor_cam.global_transform.basis.z) * 2.2; _apply_editor_cam()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if active_tool == "terrain":
				_terrain_sculpting = true; _terrain_changed = false
				if hover_valid: _do_terrain_sculpt_stroke()
			else:
				_handle_left_click(event.position, event.shift_pressed, event.alt_pressed)

func _finish_drag_box() -> void:
	_drawing_box = false
	var a := _box_start
	var c := hover_pos
	var dx := absf(c.x - a.x); var dz := absf(c.z - a.z)
	var mat: String = active_material if not active_material.is_empty() else str(Tf2GamemodesScript.get_biome(active_biome)["floor"])
	var h := maxf(0.25, box_height_m)
	var sid: int = -1
	if dx < grid_m * 0.6 and dz < grid_m * 0.6:
		sid = doc.add_box(a + Vector3(-4, 0, -4), a + Vector3(4, h, 4), mat)
	else:
		var mn := Vector3(minf(a.x, c.x), a.y, minf(a.z, c.z))
		var mx := Vector3(maxf(a.x, c.x), a.y + h, maxf(a.z, c.z))
		if mx.x - mn.x < grid_m: mx.x = mn.x + grid_m
		if mx.z - mn.z < grid_m: mx.z = mn.z + grid_m
		sid = doc.add_box(mn, mx, mat)
	if sid >= 0:
		if symmetry != SymmetryMode.OFF:
			doc.mirror_solid_x(sid, symmetry == SymmetryMode.ROT_180)
		_record_history("Draw Box"); map_sync.sync_all(); _select_solid(sid, -1); audio.play("place")

func _ray_plane_point(screen_pos: Vector2, plane_y: float) -> Vector3:
	var ro := editor_cam.project_ray_origin(screen_pos)
	var rd := editor_cam.project_ray_normal(screen_pos)
	if absf(rd.y) < 0.001: return _move_last_pos
	var t := (plane_y - ro.y) / rd.y
	if t <= 0.1 or t > 400.0: return _move_last_pos
	var p := ro + rd * t
	return Vector3(snappedf(p.x, grid_m), plane_y, snappedf(p.z, grid_m))

func _project_ray_onto_axis(ro: Vector3, rd: Vector3, origin: Vector3, axis: Vector3) -> float:
	var w0 := origin - ro
	var a := axis.dot(axis); var b := axis.dot(rd); var c := rd.dot(rd)
	var d := axis.dot(w0); var e := rd.dot(w0)
	var denom := a * c - b * b
	return 0.0 if absf(denom) < 0.0001 else (b * e - c * d) / denom

func _hit_test_gizmo_axis(ro: Vector3, rd: Vector3) -> Vector3:
	if _gizmo_root == null or not _gizmo_root.visible:
		return Vector3.ZERO
	var orig := _gizmo_root.position
	var best_ax := Vector3.ZERO
	var best_dist := 0.36
	for ax: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		var t := clampf(_project_ray_onto_axis(ro, rd, orig, ax), 0.15, 2.15)
		var pt_on_ax := orig + ax * t
		var s := maxf(0.0, (pt_on_ax - ro).dot(rd))
		var pt_on_ray := ro + rd * s
		var d := pt_on_ax.distance_to(pt_on_ray)
		if d < best_dist:
			best_dist = d
			best_ax = ax
	return best_ax

func _update_gizmo_drag(screen_pos: Vector2) -> void:
	var ro := editor_cam.project_ray_origin(screen_pos); var rd := editor_cam.project_ray_normal(screen_pos)
	var snapped_t := snappedf(_project_ray_onto_axis(ro, rd, _gizmo_origin, _gizmo_axis), grid_m)
	var step := snapped_t - _gizmo_accum
	if absf(step) < grid_m * 0.5:
		return
	var delta := _gizmo_axis * step
	if selected_solid >= 0:
		doc.translate_solid(selected_solid, delta)
		map_sync.sync_solid(selected_solid)
		_refresh_2d_views()
	elif selected_entity >= 0:
		doc.translate_entity(selected_entity, delta)
		ent_vis.sync_entity(selected_entity, false)
	_gizmo_accum = snapped_t
	_update_3d_gizmo()

func _update_face_drag(screen_pos: Vector2) -> void:
	var ro := editor_cam.project_ray_origin(screen_pos); var rd := editor_cam.project_ray_normal(screen_pos)
	var snapped_t := snappedf(_project_ray_onto_axis(ro, rd, _drag_anchor, _drag_normal), grid_m)
	var step := snapped_t - _drag_accum
	if absf(step) >= grid_m * 0.5 and doc.push_pull_normal(_drag_solid, _drag_normal, step):
		_drag_accum = snapped_t; map_sync.sync_solid(_drag_solid); map_sync.set_selection(_drag_solid, -1); _refresh_selection_bar(); audio.play("click", -14.0)

func _update_vertex_drag(screen_pos: Vector2, vertical_mode: bool = false) -> void:
	var p: Vector3
	if vertical_mode:
		# Hold Shift during Shift+V vertex drag to move the corner UP/DOWN vertically for sloped roofs & ramps!
		var ro := editor_cam.project_ray_origin(screen_pos); var rd := editor_cam.project_ray_normal(screen_pos)
		var ty := snappedf(_project_ray_onto_axis(ro, rd, _drag_vert_pos, Vector3.UP), grid_m)
		p = Vector3(_drag_vert_pos.x, _drag_vert_pos.y + ty, _drag_vert_pos.z)
	else:
		p = _ray_plane_point(screen_pos, _drag_vert_pos.y)
	var delta := p - _drag_vert_pos
	if delta.length_squared() >= grid_m * grid_m * 0.25:
		if doc.move_solid_vertex_at(selected_solid, _drag_vert_pos, delta):
			_drag_vert_pos = p
			_drag_vert_last = p
			map_sync.sync_solid(selected_solid); map_sync.set_selection(selected_solid, -1); _refresh_selection_bar(); audio.play("click", -14.0)

func _update_move_drag(screen_pos: Vector2) -> void:
	var p := _ray_plane_point(screen_pos, _move_last_pos.y)
	var delta := p - _move_last_pos
	if delta.length_squared() > 0.001:
		_move_last_pos = p
		if selected_solid >= 0:
			doc.translate_solid(selected_solid, delta); map_sync.sync_solid(selected_solid); map_sync.set_selection(selected_solid, -1)
		elif selected_entity >= 0:
			var ents: Array = doc.get_entities()
			if selected_entity < ents.size():
				doc.set_entity_pos(selected_entity, ents[selected_entity]["pos"] + delta); ent_vis.sync_all()

func _pick_scene_object(ro: Vector3, rd: Vector3) -> Dictionary:
	var rc_ent: Dictionary = doc.raycast_entity(ro, rd)
	var rc_face: Dictionary = doc.raycast_face(ro, rd)
	var hit_e: bool = rc_ent.get("hit", false); var hit_f: bool = rc_face.get("hit", false)
	if hit_e and hit_f:
		if float(rc_ent["t"]) <= float(rc_face["t"]) + 0.65:
			return {"kind": "entity", "idx": int(rc_ent["entity_idx"]), "hit_pos": rc_ent["hit_pos"]}
		return {"kind": "solid", "idx": int(rc_face["solid_idx"]), "face": int(rc_face["face_idx"]), "normal": rc_face["normal"], "hit_pos": rc_face["hit_pos"]}
	elif hit_e:
		return {"kind": "entity", "idx": int(rc_ent["entity_idx"]), "hit_pos": rc_ent["hit_pos"]}
	elif hit_f:
		return {"kind": "solid", "idx": int(rc_face["solid_idx"]), "face": int(rc_face["face_idx"]), "normal": rc_face["normal"], "hit_pos": rc_face["hit_pos"]}
	return {"kind": "none"}

func _handle_left_click(screen_pos: Vector2, shift_held: bool = false, alt_held: bool = false) -> void:
	if viewing_bsp:
		_toast("Viewing official %s â€” click 'Walk Inside (F5)' below!" % current_bsp_name); return
	var ro := editor_cam.project_ray_origin(screen_pos); var rd := editor_cam.project_ray_normal(screen_pos)

	if active_tool == "vertex":
		if selected_solid >= 0:
			var vh: Dictionary = map_sync.hit_test_vertex_handle(ro, rd)
			if not vh.is_empty():
				_dragging_vertex = true; _drag_vert_idx = int(vh["vert_idx"]); _drag_vert_last = vh["pos"]; _drag_vert_pos = vh["pos"]
				audio.play("click"); return
		var pick := _pick_scene_object(ro, rd)
		if pick["kind"] == "solid": _select_solid(pick["idx"], pick["face"]); audio.play("click")
		else: _clear_selection()
		return

	if active_tool == "select":
		# 1) Test interactive draggable 3D RGB Transform Gizmo arrows first!
		if selected_solid >= 0 or selected_entity >= 0:
			var g_ax := _hit_test_gizmo_axis(ro, rd)
			if g_ax != Vector3.ZERO:
				_dragging_gizmo = true; _gizmo_axis = g_ax; _gizmo_origin = _gizmo_root.position
				_gizmo_accum = snappedf(_project_ray_onto_axis(ro, rd, _gizmo_origin, _gizmo_axis), grid_m)
				audio.play("click"); return
		if selected_solid >= 0:
			var h: Dictionary = map_sync.hit_test_face_handle(ro, rd)
			if not h.is_empty():
				_dragging_face = true; _drag_solid = int(h["solid_idx"]); _drag_normal = h["normal"]; _drag_anchor = h["pos"]; _drag_accum = 0.0
				audio.play("click"); return
		var pick := _pick_scene_object(ro, rd)
		if pick["kind"] == "entity":
			var eidx: int = pick["idx"]
			if shift_held:
				var nid: int = doc.duplicate_entity(eidx, Vector3.ZERO)
				if nid >= 0: ent_vis.sync_all(); eidx = nid; _toast("Shift+Drag Cloned Entity #%d!" % nid)
			_select_entity(eidx); _dragging_move = true; _move_last_pos = _ray_plane_point(screen_pos, (pick["hit_pos"] as Vector3).y); audio.play("click")
			if stage == Stage.GAMEPLAY: _open_inspector_drawer()
		elif pick["kind"] == "solid":
			var sidx: int = pick["idx"]; var fidx: int = pick["face"]
			if alt_held:
				var sinfo: Dictionary = doc.get_solid_info(sidx)
				var pm: String = str(sinfo.get("material", ""))
				if not pm.is_empty():
					active_material = pm; audio.play("click"); _refresh_context_bar()
					_toast("Build Eyedropper picked material: " + active_material.get_file())
				return
			if shift_held:
				var nid: int = doc.duplicate_solid(sidx, Vector3.ZERO)
				if nid >= 0:
					map_sync.sync_all(); _select_solid(nid, -1); _dragging_move = true
					_move_last_pos = _ray_plane_point(screen_pos, (pick["hit_pos"] as Vector3).y); audio.play("place")
					_toast("Shift+Drag Cloned Solid #%d!" % nid); return
			_select_solid(sidx, fidx, Input.is_key_pressed(KEY_CTRL)); audio.play("click")
			if stage == Stage.STYLE and right_drawer.visible: _open_materials_drawer()
		else: _clear_selection()
		return

	if active_tool == "paint" or active_tool == "materials":
		var rc: Dictionary = doc.raycast_face(ro, rd)
		if rc.get("hit", false):
			var sidx := int(rc["solid_idx"]); var fidx := int(rc["face_idx"])
			_select_solid(sidx, fidx)
			if alt_held:
				var pm: String = str(rc.get("material", active_material))
				if not pm.is_empty():
					active_material = pm; audio.play("click"); _toast("Eyedropper picked: " + active_material)
			elif active_tool == "paint":
				doc.set_face_material(sidx, fidx, active_material)
				_record_history("Paint Face"); map_sync.sync_solid(sidx); audio.play("place")
			else:
				audio.play("click")
			if right_drawer.visible: _open_materials_drawer()
		return

	if active_tool == "floor" and hover_valid:
		_drawing_box = true; _box_start = hover_pos; return

	if active_tool == "wall" and hover_valid:
		if not _wall_chain_active:
			_wall_chain_active = true; _wall_chain_start = hover_pos
			_toast("Wall Chain started â€” click next corner (RMB or Esc to finish)")
		else:
			var b: Dictionary = Tf2GamemodesScript.get_biome(active_biome)
			var wmat: String = active_material if not active_material.is_empty() else str(b["wall"])
			var wid: int = doc.add_wall_segment(_wall_chain_start, hover_pos, wall_height_m, wall_thick_m, wmat)
			if wid >= 0:
				if symmetry != SymmetryMode.OFF: doc.mirror_solid_x(wid, symmetry == SymmetryMode.ROT_180)
				_record_history("Draw Wall"); map_sync.sync_all(); _select_solid(wid, -1); audio.play("place")
				_wall_chain_start = hover_pos
		return

	if hover_valid:
		_place_tool_at(hover_pos)

## Smart entity placement: brush entities (func_door, trigger_*, func_respawnroom, func_nobuild, etc.)
## automatically create real 3D solid/trigger brush volumes instead of 0-size point entities!
func _place_smart_entity(cls: String, pos: Vector3) -> int:
	if cls == "func_door":
		return doc.add_brush_entity("func_door", pos + Vector3(-2.0, 0.0, -0.25), pos + Vector3(2.0, 4.0, 0.25),
			"METAL/METALDOOR001", {"movedir": "-90 0 0", "speed": "380"})
	if cls.begins_with("trigger_") or cls in ["func_respawnroom", "func_capturezone", "func_nobuild", "func_upgradestation", "func_nav_blocker", "func_nav_prefer", "func_clip_vphysics"]:
		var kv := {}
		if cls == "trigger_hurt": kv = {"damage": "50", "damagetype": "0"}
		elif cls == "trigger_push": kv = {"pushdir": "-90 0 0", "speed": "650"}
		elif cls == "func_respawnroom" or cls == "func_capturezone": kv = {"TeamNum": "2"}
		return doc.add_brush_entity(cls, pos + Vector3(-2.5, 0.0, -2.5), pos + Vector3(2.5, 3.5, 2.5), "TOOLS/TOOLSTRIGGER", kv)
	return doc.add_point_entity(cls, pos, {"angles": "0 0 0"})

func _place_tool_at(pos: Vector3) -> void:
	var b: Dictionary = Tf2GamemodesScript.get_biome(active_biome)
	if active_tool == "place_fgd_entity":
		var eid: int = _place_smart_entity(active_fgd_entity, pos)
		_record_history("Place " + active_fgd_entity)
		if eid >= 0:
			ent_vis.sync_entity(eid, true)
			_select_entity(eid)
		else:
			ent_vis.sync_all()
		_spawn_place_fx(pos, HudWidgets.COL_CYAN)
		audio.play("place"); return
	if active_tool == "place_prop":
		var yaw_val: float = randf_range(0.0, 360.0) if prop_random_yaw else prop_yaw_deg
		var kv := {"model": active_prop_mdl, "angles": "0 %d 0" % int(round(yaw_val)), "solid": "6", "skin": str(prop_skin)}
		if absf(prop_scale - 1.0) > 0.01:
			kv["modelscale"] = "%.2f" % prop_scale
		var eid: int = doc.add_point_entity("prop_static", pos, kv)
		_record_history("Place Prop")
		if eid >= 0:
			ent_vis.sync_entity(eid, true)
			_select_entity(eid)
		else:
			ent_vis.sync_all()
		_spawn_place_fx(pos, HudWidgets.COL_ACC)
		audio.play("place"); return

	var created_solids: Array[int] = []
	if stage == Stage.BUILD:
		match active_tool:
			"building":
				for i in doc.add_building(pos + Vector3(-4, 0, -4), pos + Vector3(4, 0, 4), bld_floors, bld_roof_style, b["wall"], b["accent"], b["roof"], bld_door_side):
					created_solids.append(i)
			"pillar":
				created_solids.append(doc.add_box(pos + Vector3(-1, 0, -1), pos + Vector3(1, wall_height_m, 1), b["accent"]))
			"ramp": created_solids.append(doc.add_ramp(pos + Vector3(-2, 0, -2), pos + Vector3(2, 2.5, 2), 0, b["accent"]))
			"stairs":
				if stairs_open_back:
					for s in range(8):
						var t0 := float(s) / 8.0
						var t1 := float(s + 1) / 8.0
						var sy := lerpf(0.0, 2.5, t0)
						var sx0 := lerpf(-2.0, 2.0, t0)
						var sx1 := lerpf(-2.0, 2.0, t1) + 0.08
						created_solids.append(doc.add_box(pos + Vector3(sx0, sy, -1.5), pos + Vector3(sx1, sy + 0.22, 1.5), "METAL/IBEAM001B"))
				else:
					for i in doc.add_stairs(pos + Vector3(-2, 0, -2), pos + Vector3(2, 2.5, 2), 0, 6, b["accent"]): created_solids.append(i)
			"arch":
				for i in doc.add_arch(pos, 6.0, 1.5, 5.0, 5, b["wall"]): created_solids.append(i)
			"carve":
				if doc.auto_carve_opening(pos + Vector3(-1.75, 0, -1.5), pos + Vector3(1.75, 3.5, 1.5), b["wall"]) > 0:
					audio.play("carve"); _toast("Carved clean 112u TF2 doorway!")
			"carve_win":
				if doc.auto_carve_opening(pos + Vector3(-2.0, 1.5, -1.5), pos + Vector3(2.0, 3.5, 1.5), b["wall"]) > 0:
					audio.play("carve"); _toast("Carved clean 128x64u TF2 sniper window!")
			"prefab_spawn":
				for i in doc.add_building(pos + Vector3(-6, 0, -5), pos + Vector3(6, 0, 5), 1, 0, b["wall"], b["accent"], b["roof"], 2):
					created_solids.append(i)
				Tf2GamemodesScript.stamp_preset(doc, "resupply", pos + Vector3(0, 0.1, -3.5), 2)
				Tf2GamemodesScript.stamp_preset(doc, "spawn", pos + Vector3(-2.5, 0.2, 0), 2)
				Tf2GamemodesScript.stamp_preset(doc, "spawn", pos + Vector3(2.5, 0.2, 0), 2)
				ent_vis.sync_all()
				_toast("Stamped Ready-to-Play TF2 Spawn Room (walls + resupply + 2 spawns)!")
			"prefab_balcony":
				created_solids.append(doc.add_box(pos + Vector3(-4, 3.5, -2.5), pos + Vector3(4, 4.0, 2.5), b["accent"]))
				created_solids.append(doc.add_box(pos + Vector3(-4, 4.0, 2.0), pos + Vector3(4, 5.2, 2.5), b["wall"]))
				for i in doc.add_stairs(pos + Vector3(4, 0, -2.0), pos + Vector3(8, 3.5, 2.0), 1, 8, b["accent"]):
					created_solids.append(i)
				_toast("Stamped TF2 Sniper Deck + Guard Rail + Stairs!")
			"prefab_mid":
				created_solids.append(doc.add_box(pos + Vector3(-4, 0, -4), pos + Vector3(4, 1.0, 4), b["accent"]))
				created_solids.append(doc.add_ramp(pos + Vector3(-6, 0, -2), pos + Vector3(-4, 1.0, 2), 0, b["floor"]))
				created_solids.append(doc.add_ramp(pos + Vector3(4, 0, -2), pos + Vector3(6, 1.0, 2), 1, b["floor"]))
				Tf2GamemodesScript.stamp_preset(doc, "cap_point", pos + Vector3(0, 1.05, 0), 0)
				ent_vis.sync_all()
				_toast("Stamped Mid Control Point Platform with dual ramps!")
			"prefab_cover":
				created_solids.append(doc.add_box(pos + Vector3(-2.0, 0, -1.0), pos + Vector3(0.5, 2.0, 1.0), "DEV/DEV_MEASURECRATE01"))
				created_solids.append(doc.add_box(pos + Vector3(0.5, 0, -1.5), pos + Vector3(2.5, 1.5, 1.5), "DEV/DEV_MEASURECRATE01"))
				_toast("Stamped TF2 Crouch/Stand Crate Cover Cluster!")
			"prefab_bridge":
				created_solids.append(doc.add_box(pos + Vector3(-6, 3.0, -2), pos + Vector3(6, 3.5, 2), "METAL/METALGRATE011A"))
				created_solids.append(doc.add_box(pos + Vector3(-6, 3.5, -2), pos + Vector3(6, 4.5, -1.75), b["accent"]))
				created_solids.append(doc.add_box(pos + Vector3(-6, 3.5, 1.75), pos + Vector3(6, 4.5, 2), b["accent"]))
				_toast("Stamped Steel Catwalk Bridge!")
		if symmetry != SymmetryMode.OFF:
			for sid in created_solids:
				if sid >= 0: doc.mirror_solid_x(sid, symmetry == SymmetryMode.ROT_180)
		_record_history("Place " + active_tool); map_sync.sync_all()
		if not created_solids.is_empty() and created_solids[0] >= 0: _select_solid(created_solids[0], -1)
		_spawn_place_fx(pos, HudWidgets.COL_ACC)
		audio.play("place")
	elif stage == Stage.GAMEPLAY:
		var preset := active_tool; var team := 2
		if preset == "spawn_red": preset = "spawn"; team = 2
		elif preset == "spawn_blu": preset = "spawn"; team = 3
		Tf2GamemodesScript.stamp_preset(doc, preset, pos, team)
		if symmetry != SymmetryMode.OFF:
			var mpos := Vector3(-pos.x, pos.y, -pos.z if symmetry == SymmetryMode.ROT_180 else pos.z)
			var mteam := (3 if team == 2 else 2) if preset in ["spawn", "intel", "resupply"] else team
			Tf2GamemodesScript.stamp_preset(doc, preset, mpos, mteam)
		_record_history("Place " + active_tool); ent_vis.sync_all(); audio.play("place")
	elif stage == Stage.STYLE and active_tool == "light":
		Tf2GamemodesScript.stamp_preset(doc, "light", pos, 2)
		_record_history("Place Light"); ent_vis.sync_all(); audio.play("place")

func _do_terrain_sculpt_stroke() -> void:
	var n: int = doc.sculpt_terrain_ex(hover_pos, terrain_radius_m, terrain_strength_m * 0.18, terrain_mode, terrain_axis_mode)
	if n > 0:
		_terrain_changed = true
		if _terrain_sync_accum >= 0.045:
			_terrain_sync_accum = 0.0
			map_sync.sync_all()

func _update_hover(screen_pos: Vector2) -> void:
	if viewing_bsp:
		hover_valid = false; ghost_mesh.visible = false; brush_ring.visible = false
		map_sync.set_hover(-1); ent_vis.set_hover(-1); overlay_2d.queue_redraw(); return

	var ro := editor_cam.project_ray_origin(screen_pos); var rd := editor_cam.project_ray_normal(screen_pos)

	# Always compute live 3D cursor XYZ coordinate (fixes frozen XYZ: 0u, 0u, 0u in Select/Paint/Vertex!)
	if active_tool == "terrain":
		# Smooth UNSNAPPED direct raycast onto displaced cliffs & terrain surfaces!
		var rc_t: Dictionary = doc.raycast_face(ro, rd)
		if rc_t.get("hit", false):
			hover_valid = true; hover_pos = rc_t["hit_pos"]
		else:
			var pt := _project_screen_to_surface(screen_pos)
			hover_valid = pt["valid"]; hover_pos = pt["pos"]
	elif _drawing_box:
		# Lock drag-box cursor strictly to the starting horizontal Y plane (no jumpy wall/roof spikes!)
		hover_valid = true; hover_pos = _ray_plane_point(screen_pos, _box_start.y)
	else:
		var proj := _project_screen_to_surface(screen_pos)
		hover_valid = proj["valid"]; hover_pos = proj["pos"]

	if active_tool == "select" or active_tool == "paint" or active_tool == "materials" or active_tool == "vertex":
		var pick := _pick_scene_object(ro, rd)
		if pick["kind"] == "entity" and active_tool == "select":
			ent_vis.set_hover(pick["idx"]); map_sync.set_hover(-1)
		elif pick["kind"] == "solid":
			map_sync.set_hover(pick["idx"]); ent_vis.set_hover(-1)
		else:
			map_sync.set_hover(-1); ent_vis.set_hover(-1)
		ghost_mesh.visible = false; brush_ring.visible = false; overlay_2d.queue_redraw(); return
	else:
		map_sync.set_hover(-1); ent_vis.set_hover(-1)

	if hover_valid:
		if active_tool == "terrain":
			ghost_mesh.visible = false; brush_ring.visible = true
			brush_ring.position = hover_pos + Vector3(0, 0.15, 0); brush_ring.scale = Vector3(terrain_radius_m, 1.0, terrain_radius_m)
		elif _drawing_box:
			brush_ring.visible = false; ghost_mesh.visible = true; ghost_mesh.rotation = Vector3.ZERO
			var h := maxf(0.25, box_height_m)
			var sz := Vector3(maxf(grid_m, absf(hover_pos.x - _box_start.x)), h, maxf(grid_m, absf(hover_pos.z - _box_start.z)))
			(ghost_mesh.mesh as BoxMesh).size = sz
			ghost_mesh.position = Vector3((_box_start.x + hover_pos.x) * 0.5, _box_start.y + h * 0.5, (_box_start.z + hover_pos.z) * 0.5)
		elif _wall_chain_active and active_tool == "wall":
			brush_ring.visible = false; ghost_mesh.visible = true
			var d := hover_pos - _wall_chain_start
			var len_m := maxf(0.5, Vector2(d.x, d.z).length())
			(ghost_mesh.mesh as BoxMesh).size = Vector3(len_m, wall_height_m, wall_thick_m)
			ghost_mesh.position = (_wall_chain_start + hover_pos) * 0.5 + Vector3(0, wall_height_m * 0.5, 0)
			ghost_mesh.rotation = Vector3(0, -atan2(d.z, d.x), 0)
		elif stage == Stage.BUILD and active_tool in ["floor", "wall", "building", "ramp", "stairs", "arch", "carve"]:
			brush_ring.visible = false; ghost_mesh.visible = true; ghost_mesh.rotation = Vector3.ZERO
			var sz := Vector3(8, maxf(0.25, box_height_m), 8)
			if active_tool == "wall": sz = Vector3(wall_thick_m, wall_height_m, wall_thick_m)
			elif active_tool == "building": sz = Vector3(8, bld_floors * 4.5, 8)
			elif active_tool == "ramp" or active_tool == "stairs": sz = Vector3(4, 2.5, 4)
			elif active_tool == "arch": sz = Vector3(6, 5.0, 1.5)
			elif active_tool == "carve": sz = Vector3(3.5, 3.5, 3.0)
			(ghost_mesh.mesh as BoxMesh).size = sz
			ghost_mesh.position = hover_pos + Vector3(0, sz.y * 0.5, 0)
		else:
			ghost_mesh.visible = false; brush_ring.visible = false
	else:
		ghost_mesh.visible = false; brush_ring.visible = false
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
	_terrain_sync_accum += delta
	if icon_cache != null:
		icon_cache.paused = (_rmb_looking or _mmb_panning or _dragging_face or _dragging_move or _dragging_gizmo or _dragging_vertex or _terrain_sculpting)
	if _toast_ttl > 0.0:
		_toast_ttl -= delta
		if _toast_ttl <= 0.0: toast_panel.visible = false
	if _prop_preview_mesh != null and is_instance_valid(_prop_preview_mesh):
		_prop_preview_mesh.rotate_y(delta * 0.85)

	# Rolling Auto-Save honoring settings.backup_count (1..N rotating slots!)
	if settings.autosave_enabled and not viewing_bsp and stage != Stage.PLAYTEST:
		_autosave_accum += delta
		if _autosave_accum >= float(settings.autosave_minutes) * 60.0:
			_autosave_accum = 0.0
			var as_dir := repo_root.path_join("godot/maps/autosave")
			DirAccess.make_dir_recursive_absolute(as_dir)
			var max_b: int = maxi(1, int(settings.backup_count))
			_autosave_slot = (_autosave_slot % max_b) + 1
			doc.save_vmf(as_dir.path_join("%s_autosave_%02d.vmf" % [doc.get_map_name(), _autosave_slot]))

	# Gate 3D WASD/E/C fly on RMB-held (and zero Ctrl/Alt modifiers) so Ctrl+S/Ctrl+D/Shift+A/Shift+E NEVER move the camera!
	var no_mod := not Input.is_key_pressed(KEY_CTRL) and not Input.is_key_pressed(KEY_ALT)
	if _rmb_looking and no_mod and stage != Stage.PLAYTEST and not welcome_panel.visible and not settings_modal.visible and not _is_typing_in_ui():
		var spd: float = float(settings.fly_speed) * (2.2 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		var mv := Vector3.ZERO
		var fwd := -editor_cam.global_transform.basis.z; var right := editor_cam.global_transform.basis.x
		if Input.is_key_pressed(KEY_W): mv += fwd
		if Input.is_key_pressed(KEY_S): mv -= fwd
		if Input.is_key_pressed(KEY_D): mv += right
		if Input.is_key_pressed(KEY_A): mv -= right
		if Input.is_key_pressed(KEY_E): mv += Vector3.UP
		if Input.is_key_pressed(KEY_C): mv -= Vector3.UP
		if mv.length_squared() > 0.001:
			cam_pos += mv.normalized() * spd * delta
			_apply_editor_cam()
			_refresh_2d_views()

	# Update top-left dirty indicator + bottom-left compact telemetry pill
	if not viewing_bsp and map_title_lbl != null:
		var dirty_s := "*" if doc.is_dirty() else ""
		var want_t := "| %s%s" % [doc.get_map_name(), dirty_s]
		if map_title_lbl.text != want_t:
			map_title_lbl.text = want_t
	if status_pill.visible:
		status_lbl_top.text = "XYZ: %du, %du, %du" % [int(hover_pos.x * UPM), int(-hover_pos.z * UPM), int(hover_pos.y * UPM)]
		var sealed_s := "SEALED" if doc.is_map_sealed() else "UNSEALED"
		status_lbl_bot.text = "%s | %d FPS | UI %d%%" % [sealed_s, Engine.get_frames_per_second(), int(round(settings.ui_scale * 100.0))]
		status_lbl_bot.add_theme_color_override("font_color", HudWidgets.COL_GREEN if doc.is_map_sealed() else HudWidgets.COL_RED)

	if stage == Stage.PLAYTEST:
		# Live interactive sliding func_door simulation (works on official .bsp AND custom maps!)
		door_ctrl.tick(player.global_position, delta)
		var t: Dictionary = player.get_telemetry()
		var nc_txt := " [NOCLIP]" if t.get("noclip", false) else ""
		var sl_txt := " | Sightline: %du%s" % [t["sightline_u"], " [LONG!]" if t["sightline_warn"] else ""]
		playtest_lbl.text = "%s%s (%d/%d HP) | %d u/s | Jump: %du%s | V: Noclip | R: Respawn | ESC: Exit" % [
			t["class_name"], nc_txt, t["hp"], t["max_hp"], t["speed_u"], t["jump_height_u"], sl_txt
		]
		overlay_2d.queue_redraw()

	_step_cli_shots()

func _apply_editor_cam() -> void:
	if top_down_2d:
		editor_cam.look_at_from_position(Vector3(cam_pos.x, 80.0, cam_pos.z), Vector3(cam_pos.x, 0.0, cam_pos.z), Vector3(0, 0, -1))
	else:
		editor_cam.position = cam_pos; editor_cam.rotation = Vector3(cam_pitch, cam_yaw, 0.0)

func draw_viewport_2d_overlay(canvas: Control) -> void:
	var vp := canvas.size
	if stage == Stage.PLAYTEST:
		var c := vp * 0.5
		if player.scoped:
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

	if ghost_mesh.visible and settings.show_jump_callouts and not welcome_panel.visible and not viewing_bsp:
		var sz := (ghost_mesh.mesh as BoxMesh).size
		var h_u := int(round(sz.y * UPM))
		var callout := HudWidgets.jump_threshold_callout(h_u)
		var top_world := ghost_mesh.position + Vector3(0, sz.y * 0.5 + 0.5, 0)
		if not editor_cam.is_position_behind(top_world):
			var sp := editor_cam.unproject_position(top_world)
			var txt := "%dx%dx%du â€” %s" % [int(round(sz.x * UPM)), int(round(sz.z * UPM)), h_u, callout["text"]]
			var f: Font = fonts["heading"]
			var tsz := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			var r := Rect2(sp - Vector2(tsz.x * 0.5 + 8, 22), Vector2(tsz.x + 16, 22))
			canvas.draw_rect(r, HudWidgets.COL_BG_HUD, true)
			canvas.draw_rect(r, callout["color"], false, 1.5)
			canvas.draw_string(f, sp - Vector2(tsz.x * 0.5, 7), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, callout["color"])

func _toast(msg: String) -> void:
	status_toast.text = msg; toast_panel.visible = true; _toast_ttl = 4.2

# ==============================================================================
# CLI SCREENSHOT AUTOMATION HOOK (for GPU visual verification & Multi-AI Critics!)
# ==============================================================================
func _parse_cli_shots() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--shot" and i + 1 < args.size():
			var spec := args[i + 1]; var colon := spec.find(":")
			if colon > 0: _auto_shots.append({"mode": spec.substr(0, colon), "out": spec.substr(colon + 1)})
	if not _auto_shots.is_empty(): _setup_auto_shot(0)

func _setup_auto_shot(idx: int) -> void:
	var sh: Dictionary = _auto_shots[idx]
	var mode: String = sh["mode"]
	_auto_shot_frames = 0
	settings_modal.visible = false
	split_2d_panel.visible = false
	match mode:
		"v2_build":
			_show_welcome_hub(false); _load_gamemode("koth", "badlands", false); set_stage(Stage.BUILD)
			_select_solid(2, 0); _open_inspector_drawer()
			cam_pos = Vector3(18, 13, 21); cam_yaw = 0.68; cam_pitch = -0.44; _apply_editor_cam()
		"v2_gameplay":
			_show_welcome_hub(false); _load_gamemode("payload", "badlands", false); set_stage(Stage.GAMEPLAY)
			_select_entity(2); _insp_tab = 0; _open_inspector_drawer()
			cam_pos = Vector3(20, 14, 24); cam_yaw = 0.62; cam_pitch = -0.44; _apply_editor_cam()
		"v2_style":
			_show_welcome_hub(false); _load_gamemode("koth", "alpine", false); set_stage(Stage.STYLE)
			_select_solid(2, 0); _open_materials_drawer()
			cam_pos = Vector3(20, 14, 24); cam_yaw = 0.65; cam_pitch = -0.42; _apply_editor_cam()
		"v2_settings":
			_show_welcome_hub(false); _load_gamemode("koth", "badlands", false); set_stage(Stage.BUILD)
			settings_modal.open_modal()
		"v2_split2d":
			_show_welcome_hub(false); _load_gamemode("koth", "badlands", false); set_stage(Stage.BUILD)
			_select_solid(2, 0); settings.show_2d_split = true; split_2d_panel.visible = true; right_drawer.visible = false
			cam_pos = Vector3(18, 13, 21); cam_yaw = 0.68; cam_pitch = -0.44; _apply_editor_cam(); _refresh_2d_views()
		"v2_cliff":
			_show_welcome_hub(false); _load_gamemode("koth", "badlands", false); set_stage(Stage.BUILD)
			doc.make_cliff_wall(Vector3(-12, 0, -14), Vector3(12, 0, -14), 10.0, 3.0, 3, "NATURE/BLENDROCKWALLDIRT001", 1.3)
			map_sync.sync_all(); _select_tool("terrain")
			cam_pos = Vector3(13.5, 7.5, 3.0); editor_cam.look_at_from_position(cam_pos, Vector3(-1.5, 3.8, -13.0), Vector3.UP)
			cam_yaw = editor_cam.rotation.y; cam_pitch = editor_cam.rotation.x
		"v2_upward":
			_show_welcome_hub(false); _load_official_bsp("pl_upward.bsp")
			# Find pl_upward's actual Payload Bomb Cart or Capture Point so we frame it directly!
			var target_pos := current_bsp_spawn + Vector3(0, 2, -6)
			if bsp_root.get_child_count() > 0:
				var sp_node := bsp_root.get_child(0).get_node_or_null("StaticProps/bomb_cart")
				if sp_node is MultiMeshInstance3D and sp_node.multimesh.instance_count > 0:
					target_pos = sp_node.multimesh.get_instance_transform(0).origin + Vector3(0, 1.5, 0)
			cam_pos = target_pos + Vector3(7.5, 5.5, 9.0)
			editor_cam.look_at_from_position(cam_pos, target_pos, Vector3.UP)
			cam_yaw = editor_cam.rotation.y; cam_pitch = editor_cam.rotation.x
		"v2_upward_cap":
			if not viewing_bsp: _show_welcome_hub(false); _load_official_bsp("pl_upward.bsp")
			var cap_pos := current_bsp_spawn + Vector3(0, 2, -6)
			if bsp_root.get_child_count() > 0:
				var cp_node := bsp_root.get_child(0).get_node_or_null("StaticProps/cappoint_hologram")
				if cp_node is MultiMeshInstance3D and cp_node.multimesh.instance_count > 0:
					cap_pos = cp_node.multimesh.get_instance_transform(0).origin + Vector3(0, 1.5, 0)
			cam_pos = cap_pos + Vector3(9.0, 6.0, 9.0)
			editor_cam.look_at_from_position(cam_pos, cap_pos, Vector3.UP)
			cam_yaw = editor_cam.rotation.y; cam_pitch = editor_cam.rotation.x
		"v3_hub":
			_load_gamemode("koth", "badlands", false); set_stage(Stage.BUILD)
			_show_welcome_hub(true)
		"v3_build_rail":
			_show_welcome_hub(false); _load_gamemode("koth", "badlands", false); set_stage(Stage.BUILD)
			_select_tool("wall"); _select_solid(2, 0); right_drawer.visible = false
			cam_pos = Vector3(18, 13, 21); cam_yaw = 0.68; cam_pitch = -0.44; _apply_editor_cam()
		"v3_prop_boxes":
			_show_welcome_hub(false); _load_gamemode("koth", "alpine", false); set_stage(Stage.STYLE)
			_prop_active_cat = ""; _prop_favorites_only = false; _prop_search_text = ""
			_open_props_drawer()
			cam_pos = Vector3(20, 14, 24); cam_yaw = 0.65; cam_pitch = -0.42; _apply_editor_cam()
		"v3_prop_winter":
			_show_welcome_hub(false); _load_gamemode("koth", "alpine", false); set_stage(Stage.STYLE)
			_prop_active_cat = "winter"; _prop_favorites_only = false; _prop_search_text = ""
			_open_props_drawer()
			cam_pos = Vector3(20, 14, 24); cam_yaw = 0.65; cam_pitch = -0.42; _apply_editor_cam()
		"v3_terrain":
			_show_welcome_hub(false); _load_gamemode("koth", "badlands", false); set_stage(Stage.BUILD)
			doc.make_cliff_wall(Vector3(-12, 0, -14), Vector3(12, 0, -14), 10.0, 3.0, 3, "NATURE/BLENDROCKWALLDIRT001", 1.3)
			map_sync.sync_all(); _select_tool("terrain")
			cam_pos = Vector3(13.5, 7.5, 3.0); editor_cam.look_at_from_position(cam_pos, Vector3(-1.5, 3.8, -13.0), Vector3.UP)
			cam_yaw = editor_cam.rotation.y; cam_pitch = editor_cam.rotation.x
		"v4_dock_props_winter":
			_show_welcome_hub(false); _load_gamemode("koth", "alpine", false); set_stage(Stage.STYLE)
			right_drawer.visible = false; _dock_prop_cat = "winter"; _dock_prop_page = 0; _rebuild_bottom_dock()
			cam_pos = Vector3(20, 14, 24); cam_yaw = 0.65; cam_pitch = -0.42; _apply_editor_cam()
		"v4_dock_ents_obj":
			_show_welcome_hub(false); _load_gamemode("pl", "badlands", false); set_stage(Stage.GAMEPLAY)
			right_drawer.visible = false; _dock_ent_cat = "objectives"; _dock_ent_page = 0; _rebuild_bottom_dock()
			cam_pos = Vector3(20, 14, 24); cam_yaw = 0.65; cam_pitch = -0.42; _apply_editor_cam()
		"v4_dock_ents_doors":
			_show_welcome_hub(false); _load_gamemode("koth", "badlands", false); set_stage(Stage.GAMEPLAY)
			_dock_ent_cat = "doors"; _dock_ent_page = 0; _rebuild_bottom_dock(); _open_fgd_entity_drawer()
			cam_pos = Vector3(20, 14, 24); cam_yaw = 0.65; cam_pitch = -0.42; _apply_editor_cam()
		"v5_icons_and_history":
			_show_welcome_hub(false); _load_gamemode("koth", "badlands", false); set_stage(Stage.GAMEPLAY)
			doc.add_point_entity("logic_relay", Vector3(-4.0, 0.2, 4.0), {"targetname": "door_relay"})
			_record_history("Place Logic Relay")
			doc.add_point_entity("trigger_hurt", Vector3(0.0, 0.2, 5.5), {"targetname": "lava_pit"})
			_record_history("Place Kill / Hurt Pit")
			doc.add_point_entity("ambient_generic", Vector3(4.0, 0.2, 4.0), {"targetname": "wind_sfx"})
			_record_history("Place Ambient Sound")
			doc.add_point_entity("info_particle_system", Vector3(2.0, 0.2, 1.5), {"targetname": "sparks_fx"})
			_record_history("Place Particle FX")
			ent_vis.sync_all()
			_open_history_drawer()
			cam_pos = Vector3(9.0, 7.5, 13.5); editor_cam.look_at_from_position(cam_pos, Vector3(0.5, 1.2, 3.5), Vector3.UP)
			cam_yaw = editor_cam.rotation.y; cam_pitch = editor_cam.rotation.x
		"v6_turbine_editor":
			_show_welcome_hub(false); _clear_official_bsp(); _clear_selection()
			doc.load_vmf(repo_root.path_join("godot/maps/ctf_turbine_rebuilt.vmf"))
			active_sky = doc.get_skyname(); we.environment.sky = assets.get_sky(active_sky)
			map_sync.clear_all(); map_sync.sync_all(); ent_vis.sync_all()
			map_title_lbl.text = "| ctf_turbine_rebuilt"
			_dock_build_cat = "shapes"; set_stage(Stage.BUILD); _select_solid(4, 0)
			cam_pos = Vector3(-13.5, 5.2, 11.5); editor_cam.look_at_from_position(cam_pos, Vector3(5.0, 1.5, -2.5), Vector3.UP)
			cam_yaw = editor_cam.rotation.y; cam_pitch = editor_cam.rotation.x
		"v6_turbine_prefabs":
			_show_welcome_hub(false); _dock_build_cat = "prefabs"; set_stage(Stage.BUILD); _select_solid(4, 0)
			cam_pos = Vector3(-13.5, 5.2, 11.5); editor_cam.look_at_from_position(cam_pos, Vector3(5.0, 1.5, -2.5), Vector3.UP)
			cam_yaw = editor_cam.rotation.y; cam_pitch = editor_cam.rotation.x
		"v7_mvm_dock":
			_show_welcome_hub(false); _load_gamemode("mvm", "mvm", false); set_stage(Stage.GAMEPLAY)
			right_drawer.visible = false; _dock_ent_cat = "_mode"; _rebuild_bottom_dock()
			cam_pos = Vector3(20, 14, 24); cam_yaw = 0.65; cam_pitch = -0.42; _apply_editor_cam()
		"v7_valve_props":
			_show_welcome_hub(false); _load_gamemode("ctf", "spytech", false); set_stage(Stage.BUILD)
			right_drawer.visible = false; _dock_build_cat = "valve_props"; _rebuild_bottom_dock()
			cam_pos = Vector3(20, 14, 24); cam_yaw = 0.65; cam_pitch = -0.42; _apply_editor_cam()
		"v7_clean_winter":
			_show_welcome_hub(false); _load_gamemode("koth", "winter", false); set_stage(Stage.STYLE)
			right_drawer.visible = false; _dock_prop_cat = "winter"; _dock_prop_page = 0; _rebuild_bottom_dock()
			cam_pos = Vector3(20, 14, 24); cam_yaw = 0.65; cam_pitch = -0.42; _apply_editor_cam()
	if not viewing_bsp and not settings_modal.visible:
		_update_hover(get_viewport().get_visible_rect().size * Vector2(0.42, 0.52))

func _step_cli_shots() -> void:
	if _auto_shots.is_empty(): return
	if icon_cache != null and icon_cache.is_busy():
		return
	_auto_shot_frames += 1
	var target_frame := 28
	if _auto_shot_frames >= target_frame:
		var sh: Dictionary = _auto_shots[_auto_shot_idx]
		get_viewport().get_texture().get_image().save_png(sh["out"])
		print("Saved App Shot [%s]: %s" % [sh["mode"], sh["out"]])
		_auto_shot_idx += 1
		if _auto_shot_idx >= _auto_shots.size():
			get_tree().quit(0)
		else:
			_setup_auto_shot(_auto_shot_idx)
