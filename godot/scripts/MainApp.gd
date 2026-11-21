extends Node3D

## Pootis Builder 2.0 — Complete Valve-Grade TF2 Map Creator (Godot 4 Forward+ + Native C++20 GDExtension)
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
var selected_face: int = -1
var selected_entity: int = -1
var _dragging_face: bool = false
var _drag_solid: int = -1
var _drag_normal: Vector3 = Vector3.ZERO
var _drag_anchor: Vector3 = Vector3.ZERO
var _drag_accum: float = 0.0
var _dragging_move: bool = false
var _move_last_pos: Vector3 = Vector3.ZERO
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
var _ent_search_text: String = ""
var _insp_tab: int = 0
var _prop_preview_mesh: MeshInstance3D = null
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
var left_rail_panel: PanelContainer
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

# ==============================================================================
# UI CONSTRUCTION (Expanded Current Floating TF2 HUD — 100% Responsive!)
# ==============================================================================
func _init_ui() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "Tf2HudLayer"
	add_child(hud_layer)

	overlay_2d = HudWidgets.ViewportOverlay.new(self)
	hud_layer.add_child(overlay_2d)

	var ui_theme: Theme = HudWidgets.create_global_theme(fonts)
	get_tree().root.theme = ui_theme

	_build_top_bar()
	_build_left_rail()
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
	for ctrl in [top_bar, left_rail_panel, bottom_dock, selection_bar, right_drawer, split_2d_panel, welcome_panel, settings_modal]:
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
	toast_wrap.offset_top = 60
	toast_wrap.offset_bottom = 96
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

func _build_left_rail() -> void:
	# Slim Floating Hammer Quick-Tool Rail (Matches Mockups 1-3!)
	left_rail_panel = HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 9.0, true)
	left_rail_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left_rail_panel.offset_left = 12
	left_rail_panel.offset_top = 68
	hud_layer.add_child(left_rail_panel)
	_rebuild_left_rail()

func _rebuild_left_rail() -> void:
	for ch in left_rail_panel.get_children():
		ch.queue_free()
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	left_rail_panel.add_child(vb)

	var items := [
		{"id": "select",   "t": "Sel",    "tip": "Select & Face-Pull (1)"},
		{"id": "floor",    "t": "Box",    "tip": "Drag-to-Draw Box / Floor (2)"},
		{"id": "wall",     "t": "Wall",   "tip": "Point-to-Point Wall Chain (3)"},
		{"id": "clip",     "t": "Clip",   "tip": "Clip Solid (Shift+X)"},
		{"id": "vertex",   "t": "Vert",   "tip": "Vertex Manipulation (Shift+V)"},
		{"id": "hollow",   "t": "Hlw",    "tip": "Make Hollow Room"},
		{"id": "carve",    "t": "Crv",    "tip": "Carve Doorway (8)"},
		{"id": "terrain",  "t": "Clf",    "tip": "Cliff & Displacement Studio (9)"},
		{"id": "entities", "t": "Ent",    "tip": "All 450+ FGD Entities (Shift+E)"},
		{"id": "hide",     "t": "Hide",   "tip": "QuickHide Selected (H) / Unhide (U)"},
	]
	for it in items:
		var tid: String = it["id"]
		var is_act := (active_tool == tid)
		var b := Button.new()
		b.text = it["t"]
		b.tooltip_text = it["tip"]
		b.custom_minimum_size = Vector2(44, 34)
		HudWidgets.style_tf2_button(b, fonts["heading"], 10, is_act)
		b.pressed.connect(func():
			audio.play("click")
			if tid == "clip": _open_clip_drawer()
			elif tid == "hollow": _do_hollow_selected()
			elif tid == "entities": _open_fgd_entity_drawer()
			elif tid == "hide": _do_quickhide_selected()
			else: _select_tool(tid)
		)
		vb.add_child(b)

func _build_selection_bar() -> void:
	selection_bar_wrap = CenterContainer.new()
	selection_bar_wrap.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	selection_bar_wrap.offset_top = -150
	selection_bar_wrap.offset_bottom = -106
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
		tag.text = "SOLID #%d (%dx%dx%du)" % [selected_solid, int(round(sz.x)), int(round(sz.z)), int(round(sz.y))]
		selection_hbox.add_child(tag)
		_add_sel_btn("+Pull", func(): _push_selected_top(grid_m))
		_add_sel_btn("-Push", func(): _push_selected_top(-grid_m))
		_add_sel_btn("Rot 90°", _rotate_selection)
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
	for spec in [
		{"t": "Save", "fn": _save_current_vmf},
		{"t": "Undo", "fn": _do_undo},
		{"t": "Redo", "fn": _do_redo},
	]:
		var b := Button.new(); b.text = spec["t"]
		HudWidgets.style_tf2_button(b, fonts["body"], 11)
		b.pressed.connect(func(): audio.play("click"); spec["fn"].call())
		lhb.add_child(b)
		edit_only_top_nodes.append(b)

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
	bottom_dock.offset_top = -102
	bottom_dock.offset_bottom = -10
	bottom_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(bottom_dock)
	_rebuild_bottom_dock()

func _rebuild_bottom_dock() -> void:
	dock_slot_map.clear()
	for ch in bottom_dock.get_children():
		ch.queue_free()
	if stage == Stage.PLAYTEST:
		return

	if viewing_bsp:
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

	var frame := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 10.0, true)
	bottom_dock.add_child(frame)
	var hb := HBoxContainer.new(); hb.alignment = BoxContainer.ALIGNMENT_CENTER; hb.add_theme_constant_override("separation", 6)
	frame.add_child(hb)

	var slots: Array = []
	if stage == Stage.BUILD:
		slots = [
			{"id": "select",   "piece": "Pull",     "lbl": "Select/Pull", "tool": true, "tkind": "Pull"},
			{"id": "floor",    "piece": "Floor",    "lbl": "Drag Box"},
			{"id": "wall",     "piece": "Wall",     "lbl": "Wall Chain"},
			{"id": "building", "piece": "Building", "lbl": "Building"},
			{"id": "ramp",     "piece": "Ramp",     "lbl": "Ramp"},
			{"id": "stairs",   "piece": "Stairs",   "lbl": "Stairs"},
			{"id": "arch",     "piece": "Arch",     "lbl": "Arch"},
			{"id": "carve",    "piece": "Door",     "lbl": "Carve"},
			{"id": "terrain",  "piece": "Terrain",  "lbl": "Cliff/Terr",  "tool": true, "tkind": "Terrain"},
			{"id": "import3d", "piece": "Model",    "lbl": "Import 3D",   "icon": "crate"},
		]
	elif stage == Stage.GAMEPLAY:
		# Select tool + ALL REAL 3D BAKED TF2 GAME-ASSET ICONS + DRAG-AND-DROP PAYLOADS!
		slots = [
			{"id": "select",          "piece": "Pull",     "lbl": "Select/Edit", "tool": true, "tkind": "Pull"},
			{"id": "spawn_red",       "piece": "Spawn",    "lbl": "RED Spawn",   "team": 1, "icon": "spawn_red",       "drag": {"kind": "gameplay", "id": "spawn_red"}},
			{"id": "spawn_blu",       "piece": "Spawn",    "lbl": "BLU Spawn",   "team": 2, "icon": "spawn_blu",       "drag": {"kind": "gameplay", "id": "spawn_blu"}},
			{"id": "bomb_cart",       "piece": "Ramp",     "lbl": "Payload",     "icon": "bomb_cart",                  "drag": {"kind": "gameplay", "id": "bomb_cart"}},
			{"id": "health_med",      "piece": "Floor",    "lbl": "Health Kit",  "icon": "health_med",                 "drag": {"kind": "gameplay", "id": "health_med"}},
			{"id": "ammo_med",        "piece": "Floor",    "lbl": "Ammo Pack",   "icon": "ammo_med",                   "drag": {"kind": "gameplay", "id": "ammo_med"}},
			{"id": "resupply",        "piece": "Box",      "lbl": "Resupply",    "icon": "resupply",                   "drag": {"kind": "gameplay", "id": "resupply"}},
			{"id": "cap_point",       "piece": "Floor",    "lbl": "Cap Point",   "icon": "cap_point",                  "drag": {"kind": "gameplay", "id": "cap_point"}},
			{"id": "intel",           "piece": "Box",      "lbl": "Intel Flag",  "icon": "intel",                      "drag": {"kind": "gameplay", "id": "intel"}},
			{"id": "upgrade_station", "piece": "Building", "lbl": "MvM Upgr",    "icon": "upgrade_station",            "drag": {"kind": "gameplay", "id": "upgrade_station"}},
			{"id": "path_node",       "piece": "Stairs",   "lbl": "Track",       "icon": "path_node",                  "drag": {"kind": "gameplay", "id": "path_node"}},
			{"id": "fgd_all",         "piece": "Wire",     "lbl": "All 450+ Ent","tool": true, "tkind": "Wire"},
		]
	elif stage == Stage.STYLE:
		# Select tool + REAL 3D TF2 PROP DRAG SHELF + MATERIAL PAINTER + BIOMES + SKY!
		slots = [
			{"id": "select",    "piece": "Pull",     "lbl": "Select Face","tool": true, "tkind": "Pull"},
			{"id": "materials", "piece": "Wall",     "lbl": "Face Edit"},
			{"id": "props",     "piece": "Box",      "lbl": "All Props",  "icon": "crate"},
			{"id": "biomes",    "piece": "Building", "lbl": "Biomes"},
			{"id": "sky_sun",   "piece": "Terrain",  "lbl": "Sky & Sun",  "tool": true, "tkind": "Terrain"},
			{"id": "p_barrel",  "piece": "Box",      "lbl": "Barrel",     "icon": "barrel",   "drag": {"kind": "prop", "mdl": "models/props_farm/wooden_barrel.mdl"}},
			{"id": "p_hay",     "piece": "Box",      "lbl": "Hay Bale",   "icon": "hay",      "drag": {"kind": "prop", "mdl": "models/props_farm/haypile001.mdl"}},
			{"id": "p_console", "piece": "Box",      "lbl": "Console",    "icon": "console",  "drag": {"kind": "prop", "mdl": "models/props_spytech/control_room_console01.mdl"}},
			{"id": "p_pine",    "piece": "Box",      "lbl": "Alpine Pine","icon": "pine",     "drag": {"kind": "prop", "mdl": "models/props_foliage/tree_pine01.mdl"}},
			{"id": "p_rock",    "piece": "Box",      "lbl": "Boulder",    "icon": "rock",     "drag": {"kind": "prop", "mdl": "models/props_nature/rock_worn001.mdl"}},
			{"id": "light",     "piece": "Floor",    "lbl": "Add Light",  "icon": "light",    "drag": {"kind": "gameplay", "id": "light"}},
		]

	for sl in slots:
		var sid: String = sl["id"]
		var is_act := (active_tool == sid)
		var ikey: String = str(sl.get("icon", ""))
		var tex: Texture2D = icon_cache.get_icon(ikey) if not ikey.is_empty() else null
		var slot_btn := HudWidgets.RailSlot.new(
			sl["piece"], sl["lbl"], tex, is_act,
			int(sl.get("team", 0)), bool(sl.get("tool", false)), str(sl.get("tkind", "")),
			fonts["body"], sl.get("drag", {})
		)
		if not ikey.is_empty():
			if not dock_slot_map.has(ikey):
				dock_slot_map[ikey] = []
			(dock_slot_map[ikey] as Array).append(slot_btn)
		var drag_d: Dictionary = sl.get("drag", {})
		slot_btn.pressed.connect(func():
			audio.play("click")
			if sid == "fgd_all":
				_open_fgd_entity_drawer()
			elif drag_d.get("kind", "") == "prop":
				active_prop_mdl = str(drag_d["mdl"])
				active_tool = "place_prop"
				_toast("Click in 3D or Drag & Drop to place " + sl["lbl"])
			else:
				_select_tool(sid)
		)
		hb.add_child(slot_btn)

func _on_icon_ready(key: String, tex: Texture2D) -> void:
	if dock_slot_map.has(key):
		for slot in dock_slot_map[key]:
			if is_instance_valid(slot):
				slot.set_icon_texture(tex)

func _build_right_drawer() -> void:
	right_drawer = HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 10.0, true)
	right_drawer.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right_drawer.offset_right = -12
	right_drawer.offset_left = -376
	right_drawer.offset_top = 66
	right_drawer.offset_bottom = -170
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
	welcome_panel.color = Color(0.06, 0.05, 0.04, 0.72)
	hud_layer.add_child(welcome_panel)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	welcome_panel.add_child(center)

	var card := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 14.0, true)
	card.custom_minimum_size = Vector2(920, 560)
	center.add_child(card)

	var vb := VBoxContainer.new(); vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)

	var hdr := HBoxContainer.new(); vb.add_child(hdr)
	var title := Label.new()
	title.text = "MANN CO. MAP WORKSHOP — POOTIS BUILDER 2.0"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_override("font", fonts["heading"]); title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	hdr.add_child(title)

	var set_hb := Button.new(); set_hb.text = "Settings"
	HudWidgets.style_tf2_button(set_hb, fonts["body"], 12)
	set_hb.pressed.connect(func(): audio.play("click"); settings_modal.open_modal())
	hdr.add_child(set_hb)

	var resume_b := Button.new(); resume_b.text = "Resume Editor"
	HudWidgets.style_tf2_button(resume_b, fonts["heading"], 13, true)
	resume_b.pressed.connect(func(): audio.play("click"); _show_welcome_hub(false))
	hdr.add_child(resume_b)

	var sub := Label.new()
	sub.text = "Pick ANY of the 12 TF2 Gamemodes to build (with all %d TF2+ABS FGD entities & VPK assets), or open any of your %d official Valve TF2 maps!" % [
		core.get_fgd_class_count(), core.list_maps().size()
	]
	sub.add_theme_font_override("font", fonts["body"]); sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	vb.add_child(sub)

	var cols := HBoxContainer.new(); cols.size_flags_vertical = Control.SIZE_EXPAND_FILL; cols.add_theme_constant_override("separation", 14)
	vb.add_child(cols)

	var left_col := VBoxContainer.new(); left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; left_col.size_flags_stretch_ratio = 1.45
	left_col.add_theme_constant_override("separation", 6); cols.add_child(left_col)

	var gm_hdr := Label.new(); gm_hdr.text = "CREATE NEW TF2 MAP (ALL 12 GAMEMODES)"
	gm_hdr.add_theme_font_override("font", fonts["heading"]); gm_hdr.add_theme_font_size_override("font_size", 13)
	left_col.add_child(gm_hdr)

	var grid := GridContainer.new(); grid.columns = 3; grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8); grid.add_theme_constant_override("v_separation", 8)
	left_col.add_child(grid)

	for gm in Tf2GamemodesScript.GAMEMODES:
		var gb := Button.new()
		gb.text = "%s\n(%s)" % [gm["name"], gm["short"]]
		gb.custom_minimum_size = Vector2(0, 58); gb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(gb, fonts["heading"], 12)
		var mid: String = gm["id"]
		gb.pressed.connect(func(): audio.play("click"); _load_gamemode(mid); _show_welcome_hub(false))
		grid.add_child(gb)

	var foot_l := HBoxContainer.new(); foot_l.add_theme_constant_override("separation", 8); left_col.add_child(foot_l)
	var open_vmf := Button.new(); open_vmf.text = "Open Existing .VMF..."
	HudWidgets.style_tf2_button(open_vmf, fonts["body"], 12)
	open_vmf.pressed.connect(func(): _open_file_dialog("vmf"))
	foot_l.add_child(open_vmf)
	var open_imp := Button.new(); open_imp.text = "Import 3D Model (.OBJ/.GLB)..."
	HudWidgets.style_tf2_button(open_imp, fonts["body"], 12)
	open_imp.pressed.connect(func(): _show_welcome_hub(false); _open_file_dialog("model"))
	foot_l.add_child(open_imp)

	var right_col := VBoxContainer.new(); right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL; right_col.size_flags_stretch_ratio = 1.0
	right_col.add_theme_constant_override("separation", 6); cols.add_child(right_col)

	var bsp_hdr := Label.new(); bsp_hdr.text = "OFFICIAL TF2 MAPS (%d INSTALLED)" % core.list_maps().size()
	bsp_hdr.add_theme_font_override("font", fonts["heading"]); bsp_hdr.add_theme_font_size_override("font_size", 13)
	right_col.add_child(bsp_hdr)

	var search := LineEdit.new(); search.placeholder_text = "Filter maps (upward, turbine, degroot, ambush...)"
	right_col.add_child(search)

	var map_scroll := ScrollContainer.new(); map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; right_col.add_child(map_scroll)
	var map_list := VBoxContainer.new(); map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL; map_list.add_theme_constant_override("separation", 4)
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
			var mb := Button.new(); mb.text = m; mb.alignment = HORIZONTAL_ALIGNMENT_LEFT; mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			HudWidgets.style_tf2_button(mb, fonts["body"], 11)
			var mcopy := m
			mb.pressed.connect(func(): audio.play("click"); _load_official_bsp(mcopy); _show_welcome_hub(false))
			map_list.add_child(mb)
			shown += 1

	populate_maps.call("")
	search.text_changed.connect(populate_maps)

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
		doc.record_undo("Drop " + pid)
		ent_vis.sync_all()
		audio.play("place")
		_toast("Dropped %s cleanly onto map at (%du, %du, %du)!" % [pid, int(pos.x * UPM), int(-pos.z * UPM), int(pos.y * UPM)])
	elif kind == "prop":
		var mdl: String = str(data.get("mdl", active_prop_mdl))
		var eid: int = doc.add_point_entity("prop_static", pos, {"model": mdl, "angles": "0 0 0", "solid": "6"})
		doc.record_undo("Drop Prop")
		ent_vis.sync_all()
		if eid >= 0: _select_entity(eid)
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

func _show_welcome_hub(show: bool) -> void:
	welcome_panel.visible = show
	if show and stage == Stage.PLAYTEST:
		set_stage(Stage.BUILD)

func _clear_selection() -> void:
	selected_solid = -1; selected_face = -1; selected_entity = -1
	map_sync.set_selection(-1, -1)
	ent_vis.set_selection(-1)
	_refresh_selection_bar()
	_refresh_2d_views()

func _select_solid(sidx: int, fidx: int = -1) -> void:
	selected_solid = sidx; selected_face = fidx; selected_entity = -1
	ent_vis.set_selection(-1)
	map_sync.set_selection(sidx, fidx)
	_refresh_selection_bar()
	_refresh_2d_views()

func _select_entity(eidx: int) -> void:
	selected_entity = eidx; selected_solid = -1; selected_face = -1
	map_sync.set_selection(-1, -1)
	ent_vis.set_selection(eidx)
	_refresh_selection_bar()

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

func _clear_drawer(title: String) -> void:
	_prop_preview_mesh = null
	if split_2d_panel.visible:
		split_2d_panel.visible = false
		settings.show_2d_split = false
	right_drawer_title.text = title
	for ch in right_drawer_vbox.get_children():
		ch.queue_free()
	right_drawer.visible = true

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
				doc.record_undo("Tie to " + cs); map_sync.sync_all(); ent_vis.sync_all()
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
	doc.record_undo(label); map_sync.sync_all(); _refresh_selection_bar(); _refresh_2d_views(); audio.play("place")

func _untie_selected_entity() -> void:
	if selected_entity < 0:
		return
	var ids: PackedInt32Array = doc.untie_brush_entity(selected_entity)
	if not ids.is_empty():
		doc.record_undo("Move to World")
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
		doc.record_undo("Make Hollow"); _clear_selection(); map_sync.sync_all(); audio.play("carve")
		_toast("Hollowed solid into %d walls (-16u outward shell)!" % ids.size())

func _do_quickhide_selected() -> void:
	if selected_solid >= 0:
		doc.set_solid_hidden(selected_solid, true)
		doc.record_undo("QuickHide Solid")
		_clear_selection(); map_sync.sync_all()
		_toast("QuickHid solid (press U to Unhide All or Ctrl+Z)")

func _do_unhide_all() -> void:
	var n: int = doc.unhide_all()
	if n > 0: doc.record_undo("Unhide All")
	map_sync.sync_all(); ent_vis.sync_all()
	_toast("Restored %d hidden object(s)!" % n)

func _do_clip_selected(normal: Vector3) -> void:
	if selected_solid < 0: return
	var info: Dictionary = doc.get_solid_info(selected_solid)
	if not info.get("valid", false): return
	var mid: Vector3 = (info["bounds_min"] + info["bounds_max"]) * 0.5
	var res: int = doc.clip_solid(selected_solid, mid, normal, _clip_keep_mode)
	if res >= 0:
		doc.record_undo("Clip Solid"); map_sync.sync_all(); _select_solid(res, -1); audio.play("carve")
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
			doc.record_undo("Rotate Entity"); ent_vis.sync_all(); audio.play("click")

func _duplicate_selection() -> void:
	if selected_solid >= 0:
		var nid: int = doc.duplicate_solid(selected_solid, Vector3(grid_m, 0, 0))
		if nid >= 0: doc.record_undo("Duplicate Solid"); map_sync.sync_all(); _select_solid(nid, -1); audio.play("place")
	elif selected_entity >= 0:
		var nid: int = doc.duplicate_entity(selected_entity, Vector3(grid_m, 0, 0))
		if nid >= 0: doc.record_undo("Duplicate Entity"); ent_vis.sync_all(); _select_entity(nid); audio.play("place")

func _delete_selection() -> void:
	if selected_solid >= 0:
		var idx := selected_solid
		if doc.delete_solid(idx):
			doc.record_undo("Delete Solid"); _clear_selection(); map_sync.sync_all(); audio.play("carve")
			_toast("Deleted Solid #%d (Ctrl+Z to Undo)" % idx)
	elif selected_entity >= 0:
		var idx := selected_entity
		if doc.delete_entity(idx):
			doc.record_undo("Delete Entity"); _clear_selection(); ent_vis.sync_all(); audio.play("carve")
			_toast("Deleted Entity #%d (Ctrl+Z to Undo)" % idx)

func _nudge_selection(delta: Vector3) -> void:
	if not settings.arrow_key_nudge: return
	if selected_solid >= 0 and doc.translate_solid(selected_solid, delta):
		_commit_solid_edit("Nudge Solid")
	elif selected_entity >= 0:
		var ents: Array = doc.get_entities()
		if selected_entity < ents.size():
			doc.set_entity_pos(selected_entity, ents[selected_entity]["pos"] + delta)
			doc.record_undo("Nudge Entity"); ent_vis.sync_all()

# ==============================================================================
# MAP LOADING, SAVING, COMPILING & PLAYTEST
# ==============================================================================
func _load_gamemode(mode_id: String, biome_override: String = "", show_toast: bool = true) -> void:
	_clear_official_bsp(); _clear_selection()
	var meta: Dictionary = Tf2GamemodesScript.build_gamemode_template(doc, mode_id, biome_override)
	active_biome = meta["biome"]; active_sky = meta["sky"]
	_apply_environment_from_biome(active_biome)
	grid_floor.visible = settings.show_grid_floor
	map_sync.clear_all(); map_sync.sync_all(); ent_vis.sync_all()
	map_title_lbl.text = "| " + str(meta["map_name"])
	_sync_mode_visibility(); _rebuild_bottom_dock(); _refresh_2d_views()
	if show_toast: _toast("Created %s starter map — sealed & ready to edit or F5 playtest!" % mode_id.to_upper())

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
	_toast("Loaded %s (%d props, %d sliding doors, %.2fs) — press F5 to walk inside!" % [
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
	doc.record_undo("Apply " + b["name"]); _apply_environment_from_biome(bkey); map_sync.sync_all()
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
		_toast("Saved " + path.get_file())
		return path
	_toast("Save failed: " + str(r.get("error", ""))); return ""

func _do_undo() -> void:
	if doc.undo(): _clear_selection(); map_sync.sync_all(); ent_vis.sync_all(); _toast("Undo")

func _do_redo() -> void:
	if doc.redo(): _clear_selection(); map_sync.sync_all(); ent_vis.sync_all(); _toast("Redo")

func _do_auto_seal() -> void:
	doc.auto_seal_skybox(); doc.record_undo("Auto-Seal Skybox"); compile_ctrl.clear_leak_laser(); map_sync.sync_all()
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
		_toast("LEAK DETECTED! Red 3D Leak Laser drawn — open Check (Alt+P) to seal!")
	elif st.get("succeeded", false):
		audio.play("success", -8.0)
		_toast("Compile SUCCEEDED (%.1fs) — 0 leaks!" % float(st.get("elapsed", 0.0)))
	else:
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
				if _dragging_vertex:
					_dragging_vertex = false; doc.record_undo("Move Vertex"); _refresh_selection_bar()
				if _dragging_face:
					_dragging_face = false; doc.record_undo("Push/Pull Face"); _refresh_selection_bar()
				if _dragging_move:
					_dragging_move = false; doc.record_undo("Move Selection"); _refresh_selection_bar()
				if _drawing_box:
					_finish_drag_box()
				if _terrain_sculpting:
					_terrain_sculpting = false
					if _terrain_changed:
						map_sync.sync_all(); doc.record_undo("Sculpt Terrain"); _terrain_changed = false
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
		doc.record_undo("Draw Box"); map_sync.sync_all(); _select_solid(sid, -1); audio.play("place")

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
		_toast("Viewing official %s — click 'Walk Inside (F5)' below!" % current_bsp_name); return
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
			if shift_held:
				var nid: int = doc.duplicate_solid(sidx, Vector3.ZERO)
				if nid >= 0:
					map_sync.sync_all(); _select_solid(nid, -1); _dragging_move = true
					_move_last_pos = _ray_plane_point(screen_pos, (pick["hit_pos"] as Vector3).y); audio.play("place")
					_toast("Shift+Drag Cloned Solid #%d!" % nid); return
			_select_solid(sidx, fidx); audio.play("click")
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
				doc.record_undo("Paint Face"); map_sync.sync_solid(sidx); audio.play("place")
			else:
				audio.play("click")
			if right_drawer.visible: _open_materials_drawer()
		return

	if active_tool == "floor" and hover_valid:
		_drawing_box = true; _box_start = hover_pos; return

	if active_tool == "wall" and hover_valid:
		if not _wall_chain_active:
			_wall_chain_active = true; _wall_chain_start = hover_pos
			_toast("Wall Chain started — click next corner (RMB or Esc to finish)")
		else:
			var b: Dictionary = Tf2GamemodesScript.get_biome(active_biome)
			var wmat: String = active_material if not active_material.is_empty() else str(b["wall"])
			var wid: int = doc.add_wall_segment(_wall_chain_start, hover_pos, wall_height_m, wall_thick_m, wmat)
			if wid >= 0:
				if symmetry != SymmetryMode.OFF: doc.mirror_solid_x(wid, symmetry == SymmetryMode.ROT_180)
				doc.record_undo("Draw Wall"); map_sync.sync_all(); _select_solid(wid, -1); audio.play("place")
				_wall_chain_start = hover_pos
		return

	if hover_valid:
		_place_tool_at(hover_pos)

func _place_tool_at(pos: Vector3) -> void:
	var b: Dictionary = Tf2GamemodesScript.get_biome(active_biome)
	if active_tool == "place_fgd_entity":
		var eid: int = doc.add_point_entity(active_fgd_entity, pos, {"angles": "0 0 0"})
		doc.record_undo("Place " + active_fgd_entity); ent_vis.sync_all()
		if eid >= 0: _select_entity(eid)
		audio.play("place"); return
	if active_tool == "place_prop":
		var eid: int = doc.add_point_entity("prop_static", pos, {"model": active_prop_mdl, "angles": "0 0 0", "solid": "6"})
		doc.record_undo("Place Prop"); ent_vis.sync_all()
		if eid >= 0: _select_entity(eid)
		audio.play("place"); return

	var created_solids: Array[int] = []
	if stage == Stage.BUILD:
		match active_tool:
			"building":
				for i in doc.add_building(pos + Vector3(-4, 0, -4), pos + Vector3(4, 0, 4), bld_floors, bld_roof_style, b["wall"], b["accent"], b["roof"], bld_door_side):
					created_solids.append(i)
			"ramp": created_solids.append(doc.add_ramp(pos + Vector3(-2, 0, -2), pos + Vector3(2, 2.5, 2), 0, b["accent"]))
			"stairs":
				for i in doc.add_stairs(pos + Vector3(-2, 0, -2), pos + Vector3(2, 2.5, 2), 0, 6, b["accent"]): created_solids.append(i)
			"arch":
				for i in doc.add_arch(pos, 6.0, 1.5, 5.0, 5, b["wall"]): created_solids.append(i)
			"carve":
				if doc.auto_carve_opening(pos + Vector3(-1.75, 0, -1.5), pos + Vector3(1.75, 3.5, 1.5), b["wall"]) > 0:
					audio.play("carve"); _toast("Carved clean 112u TF2 doorway!")
		if symmetry != SymmetryMode.OFF:
			for sid in created_solids:
				if sid >= 0: doc.mirror_solid_x(sid, symmetry == SymmetryMode.ROT_180)
		doc.record_undo("Place " + active_tool); map_sync.sync_all()
		if not created_solids.is_empty() and created_solids[0] >= 0: _select_solid(created_solids[0], -1)
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
		doc.record_undo("Place " + active_tool); ent_vis.sync_all(); audio.play("place")
	elif stage == Stage.STYLE and active_tool == "light":
		Tf2GamemodesScript.stamp_preset(doc, "light", pos, 2)
		doc.record_undo("Place Light"); ent_vis.sync_all(); audio.play("place")

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
			var txt := "%dx%dx%du — %s" % [int(round(sz.x * UPM)), int(round(sz.z * UPM)), h_u, callout["text"]]
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
