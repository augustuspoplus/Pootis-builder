extends Node3D

## Pootis Builder 2.0 — Valve-Grade TF2 Map Creator (Godot 4 Forward+ + Native C++20 GDExtension)
## Integrates:
##   - Mann Co. Welcome Hub (All 12 TF2 Gamemodes + 8 Biomes + All 263 Official TF2 .bsp Maps)
##   - 4-Stage TF2 Floating HUD (Build | Gameplay | Style & Light | F5 Playtest) + Clean Official-Map Mode
##   - TrenchBroom / Hammer++ 3D Editing: Live Hover Highlight, Click-to-Select Solids & Entities,
##     Instant Del/Backspace Delete, Draggable 3D Face-Pull Arrows, Shift+Drag Clone, R Rotate,
##     [/] Live Grid Snap (8u-128u), Shift+X Clip Tool, Ctrl+T Tie to Entity, Alt+Enter Inspector, VisGroups
##   - Live VPK Texture Swatches (Material Painter + Alt+Click Eyedropper) & 3D Prop Preview Browser
##   - Native C++20 CSG (Box, Wall, Ramp, Stairs, Arch, Building Wizard, Auto-Carve, Push/Pull, Symmetry)
##   - Interactive Source Displacement Terrain Sculpt Studio (Raise / Lower / Smooth / Flatten)
##   - Easy 3D Model Importer (.obj / .glb / .gltf -> live TF2 Prop + Valve .QC/.SMD export)
##   - Real 3D TF2 .mdl Entities + Payload Spline Tracks + 3D Bezier Logic Wires
##   - 6-Class F5 TF2 Playtest Sandbox (+ V Noclip, R Respawn, Rocket-Jump, Sniper Scope, 1100u Sentry)
##   - 1-Click Async Valve Compiler (vbsp/vvis/vrad) + 3D Red Leak Laser + Auto-Seal (-insecure VAC safe)

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
const GRID_STEPS: Array[int] = [8, 16, 32, 64, 128]

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
var active_tool: String = "select"
var active_material: String = "WOOD/WOOD_WALL002"
var active_prop_mdl: String = "models/props_2fort/miningcrate001.mdl"
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

# Selection & Direct 3D Manipulation State (Milestone 17)
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
var _clip_keep_mode: int = 0 # 0=Both, 1=Front, 2=Back

# Building Wizard, Terrain Brush & Browser Search State
var bld_floors: int = 2
var bld_roof_style: int = 1 # 0=Flat, 1=Gabled, 2=Slanted
var bld_door_side: int = 2
var terrain_mode: int = 0   # 0=Raise, 1=Lower, 2=Smooth, 3=Flatten
var terrain_radius_m: float = 4.5
var terrain_strength_m: float = 1.2
var _terrain_sculpting: bool = false
var _mat_search_text: String = ""
var _prop_search_text: String = ""
var _prop_preview_mesh: MeshInstance3D = null

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
var top_bar: Control
var bottom_dock: Control
var selection_bar: PanelContainer
var selection_hbox: HBoxContainer
var right_drawer: PanelContainer
var right_drawer_vbox: VBoxContainer
var right_drawer_title: Label
var playtest_hud: Control
var playtest_lbl: Label
var toast_panel: PanelContainer
var status_toast: Label
var _toast_ttl: float = 0.0
var map_title_lbl: Label
var grid_btn: Button
var sym_btn: Button
var coach_btn: Button
var stage_btns: Array[Button] = []
var file_dialog: FileDialog

# Screenshot automation state
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

	# Glowing RED | BLU Symmetry Plane at X = 0
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
# UI CONSTRUCTION (Finished Floating TF2 HUD + Selection Bar + Top Toast + Welcome Hub)
# ==============================================================================
func _init_ui() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.name = "Tf2HudLayer"
	add_child(hud_layer)

	overlay_2d = HudWidgets.ViewportOverlay.new(self)
	hud_layer.add_child(overlay_2d)

	_build_top_bar()
	_build_toast_pill()
	_build_selection_bar()
	_build_bottom_dock()
	_build_right_drawer()
	_build_playtest_hud()
	_build_welcome_hub()

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
	# Positioned cleanly at TOP-CENTER below the top bar so it NEVER overlaps the bottom dock!
	toast_panel = HudWidgets.HudFrame.new(HudWidgets.COL_ACC, 8.0, false)
	toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_panel.offset_top = 60
	toast_panel.offset_bottom = 94
	toast_panel.offset_left = -310
	toast_panel.offset_right = 310
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.visible = false
	hud_layer.add_child(toast_panel)

	status_toast = Label.new()
	status_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_toast.add_theme_font_override("font", fonts["heading"])
	status_toast.add_theme_font_size_override("font_size", 12)
	status_toast.add_theme_color_override("font_color", HudWidgets.COL_TX)
	status_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.add_child(status_toast)

func _build_selection_bar() -> void:
	# Contextual Floating Selection Pill above the bottom dock whenever a solid or entity is selected!
	selection_bar = HudWidgets.HudFrame.new(HudWidgets.COL_CYAN, 8.0, true)
	selection_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	selection_bar.offset_top = -142
	selection_bar.offset_bottom = -98
	selection_bar.offset_left = -395
	selection_bar.offset_right = 395
	selection_bar.visible = false
	hud_layer.add_child(selection_bar)

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
	tag.add_theme_color_override("font_color", HudWidgets.COL_ACC)

	if selected_solid >= 0:
		var info: Dictionary = doc.get_solid_info(selected_solid)
		var sz: Vector3 = (info.get("bounds_max", Vector3.ZERO) - info.get("bounds_min", Vector3.ZERO)) * UPM
		tag.text = "SOLID #%d (%dx%dx%du)" % [selected_solid, int(round(sz.x)), int(round(sz.z)), int(round(sz.y))]
		selection_hbox.add_child(tag)

		_add_sel_btn("+Tall", func(): _push_selected_top(grid_m))
		_add_sel_btn("-Tall", func(): _push_selected_top(-grid_m))
		_add_sel_btn("Rot 90° (R)", _rotate_selection)
		_add_sel_btn("Clip (Shift+X)", _open_clip_drawer)
		_add_sel_btn("Clone (Ctrl+D)", _duplicate_selection)
		_add_sel_btn("Tie (Ctrl+T)", _open_tie_entity_drawer)
		_add_sel_btn("Props", _open_inspector_drawer)
		_add_sel_btn("Delete (Del)", _delete_selection, 2)
	elif selected_entity >= 0:
		var ents: Array = doc.get_entities()
		var cls := "entity"
		if selected_entity < ents.size():
			cls = str(ents[selected_entity]["classname"])
		tag.text = "ENTITY #%d: %s" % [selected_entity, cls]
		selection_hbox.add_child(tag)

		_add_sel_btn("Rot 90° (R)", _rotate_selection)
		_add_sel_btn("Clone (Ctrl+D)", _duplicate_selection)
		_add_sel_btn("Props (Alt+Enter)", _open_inspector_drawer)
		_add_sel_btn("Delete (Del)", _delete_selection, 2)

func _add_sel_btn(label: String, fn: Callable, team: int = 0) -> void:
	var b := Button.new()
	b.text = label
	HudWidgets.style_tf2_button(b, fonts["body"], 11, false, team)
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

	# TOP-LEFT: Title & File Pill
	var left_frame := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 9.0, true)
	bar_hb.add_child(left_frame)
	var lhb := HBoxContainer.new()
	lhb.add_theme_constant_override("separation", 5)
	left_frame.add_child(lhb)

	var brand := Label.new()
	brand.text = "POOTIS BUILDER"
	brand.add_theme_font_override("font", fonts["heading"])
	brand.add_theme_font_size_override("font_size", 13)
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

	# TOP-CENTER: 4-Stage Stepper Pill
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

	# TOP-RIGHT: Grid Snap, Symmetry, VisGroups, 2D/3D, Coach, Seal, Compile!
	var right_frame := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 9.0, true)
	bar_hb.add_child(right_frame)
	var rhb := HBoxContainer.new()
	rhb.alignment = BoxContainer.ALIGNMENT_END
	rhb.add_theme_constant_override("separation", 4)
	right_frame.add_child(rhb)

	grid_btn = Button.new()
	grid_btn.text = "Grid: 32u"
	grid_btn.tooltip_text = "Cycle Grid Snap ([ smaller, ] larger)"
	HudWidgets.style_tf2_button(grid_btn, fonts["body"], 11)
	grid_btn.pressed.connect(func(): audio.play("click"); _step_grid(1, true))
	rhb.add_child(grid_btn)

	sym_btn = Button.new()
	sym_btn.text = "Sym: Off"
	HudWidgets.style_tf2_button(sym_btn, fonts["body"], 11)
	sym_btn.pressed.connect(func(): audio.play("click"); _cycle_symmetry())
	rhb.add_child(sym_btn)

	var vis_b := Button.new()
	vis_b.text = "Vis"
	vis_b.tooltip_text = "VisGroups Visibility Toggles"
	HudWidgets.style_tf2_button(vis_b, fonts["body"], 11)
	vis_b.pressed.connect(func(): audio.play("click"); _open_visgroups_drawer())
	rhb.add_child(vis_b)

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

	# Dedicated Clean Official Valve Map Mode Bar (no misleading Build buttons or ghosts!)
	if viewing_bsp:
		var oframe := HudWidgets.HudFrame.new(HudWidgets.COL_BLU, 10.0, true)
		oframe.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		oframe.offset_bottom = 0
		oframe.offset_top = -56
		oframe.offset_left = -380
		oframe.offset_right = 380
		bottom_dock.add_child(oframe)

		var ohb := HBoxContainer.new()
		ohb.alignment = BoxContainer.ALIGNMENT_CENTER
		ohb.add_theme_constant_override("separation", 8)
		oframe.add_child(ohb)

		var badge := Label.new()
		badge.text = "OFFICIAL MAP: " + current_bsp_name.get_basename().to_upper()
		badge.add_theme_font_override("font", fonts["heading"])
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_color", HudWidgets.COL_ACC)
		ohb.add_child(badge)

		var walk_b := Button.new()
		walk_b.text = "Walk Inside (F5)"
		HudWidgets.style_tf2_button(walk_b, fonts["heading"], 12, true)
		walk_b.pressed.connect(func(): audio.play("click"); set_stage(Stage.PLAYTEST))
		ohb.add_child(walk_b)

		var fly_b := Button.new()
		fly_b.text = "Noclip Fly (F5+V)"
		HudWidgets.style_tf2_button(fly_b, fonts["body"], 12, false, 3)
		fly_b.pressed.connect(func():
			audio.play("click")
			set_stage(Stage.PLAYTEST)
			player.noclip = true
		)
		ohb.add_child(fly_b)

		var new_b := Button.new()
		new_b.text = "Start Custom Map"
		HudWidgets.style_tf2_button(new_b, fonts["body"], 12)
		new_b.pressed.connect(func(): audio.play("click"); _load_gamemode("koth", "badlands", true))
		ohb.add_child(new_b)

		var hub_b := Button.new()
		hub_b.text = "Workshop Hub"
		HudWidgets.style_tf2_button(hub_b, fonts["body"], 12)
		hub_b.pressed.connect(func(): audio.play("click"); _show_welcome_hub(true))
		ohb.add_child(hub_b)
		return

	var frame := HudWidgets.HudFrame.new(HudWidgets.COL_LIP_AMB, 10.0, true)
	frame.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	frame.offset_bottom = 0
	frame.offset_top = -80
	frame.offset_left = -450
	frame.offset_right = 450
	bottom_dock.add_child(frame)

	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 6)
	frame.add_child(hb)

	var slots: Array = []
	if stage == Stage.BUILD:
		slots = [
			{"id": "select",   "piece": "Pull",     "lbl": "Select/Pull", "tool": true,  "tkind": "Pull"},
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
			{"id": "select",    "piece": "Pull",   "lbl": "Select",    "tool": true, "tkind": "Pull"},
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
			{"id": "wires",     "piece": "Wire",   "lbl": "Wires (L)", "tool": true, "tkind": "Wire"},
		]
	elif stage == Stage.STYLE:
		slots = [
			{"id": "select",    "piece": "Pull",     "lbl": "Select",    "tool": true, "tkind": "Pull"},
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
	right_drawer.offset_left = -340
	right_drawer.offset_top = 66
	right_drawer.offset_bottom = 600
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
	frame.offset_left = -430; frame.offset_right = 430
	frame.offset_top = -76; frame.offset_bottom = 0
	playtest_hud.add_child(frame)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	frame.add_child(vb)

	playtest_lbl = Label.new()
	playtest_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	playtest_lbl.add_theme_font_override("font", fonts["heading"])
	playtest_lbl.add_theme_font_size_override("font_size", 13)
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

	# Right Column: Searchable 263 Official TF2 Maps Browser
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
	search.placeholder_text = "Filter maps (turbine, upward, degroot, ambush...)"
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
		var featured := ["ctf_turbine.bsp", "ctf_2fort.bsp", "pl_upward.bsp", "koth_viaduct.bsp", "koth_sawmill.bsp", "mvm_decoy.bsp", "cp_degrootkeep.bsp", "plr_hightower.bsp", "cp_process_final.bsp", "sd_doomsday.bsp"]
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
			if shown >= 45:
				break
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
			map_list.add_child(mb)
			shown += 1

	populate_maps.call("")
	search.text_changed.connect(populate_maps)

# ==============================================================================
# STAGE, SELECTION & TOOL ACTIONS
# ==============================================================================
func _show_welcome_hub(show: bool) -> void:
	welcome_panel.visible = show
	if show and stage == Stage.PLAYTEST:
		set_stage(Stage.BUILD)

func _clear_selection() -> void:
	selected_solid = -1
	selected_face = -1
	selected_entity = -1
	map_sync.set_selection(-1, -1)
	ent_vis.set_selection(-1)
	_refresh_selection_bar()

func _select_solid(sidx: int, fidx: int = -1) -> void:
	selected_solid = sidx
	selected_face = fidx
	selected_entity = -1
	ent_vis.set_selection(-1)
	map_sync.set_selection(sidx, fidx)
	_refresh_selection_bar()

func _select_entity(eidx: int) -> void:
	selected_entity = eidx
	selected_solid = -1
	selected_face = -1
	map_sync.set_selection(-1, -1)
	ent_vis.set_selection(eidx)
	_refresh_selection_bar()

func _step_grid(dir: int, wrap: bool = false) -> void:
	if wrap:
		grid_idx = (grid_idx + dir) % GRID_STEPS.size()
	else:
		grid_idx = clampi(grid_idx + dir, 0, GRID_STEPS.size() - 1)
	var u: int = GRID_STEPS[grid_idx]
	grid_m = float(u) / UPM
	doc.set_grid_units(u)
	grid_btn.text = "Grid: %du" % u
	_toast("Grid Snap: %du (use [ / ] to resize)" % u)

func set_stage(new_stage: int) -> void:
	if new_stage == Stage.PLAYTEST:
		stage = Stage.PLAYTEST
		_enter_playtest()
	else:
		if stage == Stage.PLAYTEST:
			_exit_playtest()
		stage = new_stage
		if stage == Stage.BUILD:
			active_tool = "select"
		elif stage == Stage.GAMEPLAY:
			active_tool = "spawn_red"
		elif stage == Stage.STYLE:
			active_tool = "materials"
			if not viewing_bsp:
				_open_materials_drawer()

	for i in range(stage_btns.size()):
		HudWidgets.style_tf2_button(stage_btns[i], fonts["heading"], 11, i == stage)
	ghost_mesh.visible = false
	brush_ring.visible = false
	_rebuild_bottom_dock()
	_refresh_selection_bar()
	if stage != Stage.STYLE or viewing_bsp:
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
	_prop_preview_mesh = null
	right_drawer_title.text = title
	for ch in right_drawer_vbox.get_children():
		ch.queue_free()
	right_drawer.visible = true

# ==============================================================================
# HAMMER++ / TRENCHBROOM POWER-TOOL DRAWERS (Inspector, VisGroups, Clip, Tie)
# ==============================================================================
func _open_visgroups_drawer() -> void:
	_clear_drawer("VISGROUPS (LAYER VISIBILITY)")
	var hint := Label.new()
	hint.text = "Toggle editor helper layers cleanly like Hammer++ VisGroups:"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	right_drawer_vbox.add_child(hint)

	var toggles := [
		{"lbl": "Triggers & Respawn Volumes", "val": ent_vis.show_triggers, "fn": func(v: bool): ent_vis.show_triggers = v; ent_vis.sync_all()},
		{"lbl": "3D Props (.mdl)",            "val": ent_vis.show_props,    "fn": func(v: bool): ent_vis.show_props = v; ent_vis.sync_all()},
		{"lbl": "Point Lights",               "val": ent_vis.show_lights,   "fn": func(v: bool): ent_vis.show_lights = v; ent_vis.sync_all()},
		{"lbl": "3D I/O Logic Wires",         "val": ent_vis.show_logic_wires, "fn": func(v: bool): ent_vis.show_logic_wires = v; ent_vis.sync_all()},
		{"lbl": "Playerclip / Clip Brushes",  "val": map_sync.show_clips,   "fn": func(v: bool): map_sync.show_clips = v; map_sync.sync_all()},
		{"lbl": "Skybox Sealing Shell",       "val": map_sync.show_skybox_shell, "fn": func(v: bool): map_sync.show_skybox_shell = v; map_sync.sync_all()},
		{"lbl": "Reference Floor Grid",       "val": grid_floor.visible,    "fn": func(v: bool): grid_floor.visible = v},
	]
	for t in toggles:
		var cb := CheckButton.new()
		cb.text = t["lbl"]
		cb.button_pressed = bool(t["val"])
		cb.add_theme_font_override("font", fonts["body"])
		cb.add_theme_font_size_override("font_size", 12)
		var fn: Callable = t["fn"]
		cb.toggled.connect(func(v: bool): audio.play("click"); fn.call(v))
		right_drawer_vbox.add_child(cb)

func _open_clip_drawer() -> void:
	if selected_solid < 0:
		_toast("Select a brush solid first to slice with Shift+X Clip!")
		return
	_clear_drawer("CLIPPING TOOL (SHIFT+X)")
	var hint := Label.new()
	hint.text = "Slice Solid #%d cleanly along a vertical plane through its center:" % selected_solid
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	right_drawer_vbox.add_child(hint)

	var modes := ["Keep Both Halves (Split)", "Keep Front Half Only", "Keep Back Half Only"]
	for i in range(3):
		var b := Button.new()
		b.text = modes[i]
		HudWidgets.style_tf2_button(b, fonts["body"], 11, _clip_keep_mode == i)
		var mi := i
		b.pressed.connect(func(): _clip_keep_mode = mi; _open_clip_drawer())
		right_drawer_vbox.add_child(b)

	var slice_x := Button.new()
	slice_x.text = "Slice Along X-Axis (North-South Cut)"
	HudWidgets.style_tf2_button(slice_x, fonts["heading"], 12, true)
	slice_x.pressed.connect(func(): _do_clip_selected(Vector3(1, 0, 0)))
	right_drawer_vbox.add_child(slice_x)

	var slice_z := Button.new()
	slice_z.text = "Slice Along Z-Axis (East-West Cut)"
	HudWidgets.style_tf2_button(slice_z, fonts["heading"], 12)
	slice_z.pressed.connect(func(): _do_clip_selected(Vector3(0, 0, 1)))
	right_drawer_vbox.add_child(slice_z)

	var slice_d := Button.new()
	slice_d.text = "Slice 45° Diagonal Corner"
	HudWidgets.style_tf2_button(slice_d, fonts["body"], 12)
	slice_d.pressed.connect(func(): _do_clip_selected(Vector3(1, 0, 1).normalized()))
	right_drawer_vbox.add_child(slice_d)

func _open_tie_entity_drawer() -> void:
	if selected_solid < 0:
		_toast("Select a brush solid first to Tie to Entity (Ctrl+T)!")
		return
	_clear_drawer("TIE TO ENTITY (CTRL+T)")
	var hint := Label.new()
	hint.text = "Convert Solid #%d into a Valve brush entity (Hammer Ctrl+T):" % selected_solid
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	right_drawer_vbox.add_child(hint)

	var presets := [
		{"cls": "func_detail", "lbl": "func_detail (Non-Vis Detail Geometry)", "kv": {}},
		{"cls": "func_door", "lbl": "func_door (Sliding TF2 Spawn Door)", "kv": {"speed": "400", "movedir": "-90 0 0", "wait": "2"}},
		{"cls": "func_respawnroom", "lbl": "func_respawnroom (RED Spawn Zone)", "kv": {"TeamNum": "2"}},
		{"cls": "func_respawnroom", "lbl": "func_respawnroom (BLU Spawn Zone)", "kv": {"TeamNum": "3"}},
		{"cls": "trigger_hurt", "lbl": "trigger_hurt (Death Pit Hazard)", "kv": {"damage": "999", "damagetype": "32"}},
		{"cls": "func_nobuild", "lbl": "func_nobuild (Block Engineer Buildings)", "kv": {}},
		{"cls": "trigger_multiple", "lbl": "trigger_multiple (Logic Trigger)", "kv": {"wait": "1"}},
	]
	for p in presets:
		var b := Button.new()
		b.text = p["lbl"]
		HudWidgets.style_tf2_button(b, fonts["body"], 11)
		var cls_s: String = p["cls"]
		var kv_d: Dictionary = p["kv"]
		b.pressed.connect(func():
			var eidx: int = doc.tie_solid_to_entity(selected_solid, cls_s, kv_d)
			if eidx >= 0:
				doc.record_undo("Tie to " + cls_s)
				map_sync.sync_all()
				ent_vis.sync_all()
				_select_entity(eidx)
				audio.play("carve")
				_toast("Tied brush to %s (Entity #%d)!" % [cls_s, eidx])
				_open_inspector_drawer()
		)
		right_drawer_vbox.add_child(b)

func _open_inspector_drawer() -> void:
	_clear_drawer("OBJECT PROPERTIES (ALT+ENTER)")
	if selected_solid >= 0:
		var info: Dictionary = doc.get_solid_info(selected_solid)
		var bmin: Vector3 = info.get("bounds_min", Vector3.ZERO)
		var bmax: Vector3 = info.get("bounds_max", Vector3.ZERO)
		var sz: Vector3 = (bmax - bmin) * UPM
		var lbl := Label.new()
		lbl.text = "World Solid #%d\nSize: %du x %du x %du\nMaterial: %s" % [
			selected_solid, int(round(sz.x)), int(round(sz.z)), int(round(sz.y)), str(info.get("material", ""))
		]
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.add_theme_font_size_override("font_size", 12)
		right_drawer_vbox.add_child(lbl)

		var row1 := HBoxContainer.new(); right_drawer_vbox.add_child(row1)
		for spec in [
			{"t": "Grow +32u", "fn": func(): doc.resize_solid_footprint(selected_solid, 1.0); _commit_solid_edit("Grow")},
			{"t": "Shrink -32u", "fn": func(): doc.resize_solid_footprint(selected_solid, -1.0); _commit_solid_edit("Shrink")},
		]:
			var b := Button.new(); b.text = spec["t"]; b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			HudWidgets.style_tf2_button(b, fonts["body"], 11)
			b.pressed.connect(spec["fn"])
			row1.add_child(b)

		var paint_b := Button.new()
		paint_b.text = "Apply Active Material (%s)" % active_material.get_file()
		HudWidgets.style_tf2_button(paint_b, fonts["heading"], 11, true)
		paint_b.pressed.connect(func():
			doc.set_solid_material(selected_solid, active_material)
			_commit_solid_edit("Apply Material")
		)
		right_drawer_vbox.add_child(paint_b)

		var mirror_b := Button.new()
		mirror_b.text = "Mirror Across X=0 Centerline"
		HudWidgets.style_tf2_button(mirror_b, fonts["body"], 11)
		mirror_b.pressed.connect(func():
			doc.mirror_solid_x(selected_solid, symmetry == SymmetryMode.ROT_180)
			doc.record_undo("Mirror Solid")
			map_sync.sync_all()
			audio.play("place")
			_toast("Mirrored Solid #%d!" % selected_solid)
		)
		right_drawer_vbox.add_child(mirror_b)
		return

	if selected_entity >= 0:
		var ents: Array = doc.get_entities()
		if selected_entity >= ents.size():
			return
		var e: Dictionary = ents[selected_entity]
		var cls: String = str(e["classname"])
		var kv: Dictionary = e["kv"]
		var hdr := Label.new()
		hdr.text = "Entity #%d — %s" % [selected_entity, cls]
		hdr.add_theme_font_override("font", fonts["heading"])
		hdr.add_theme_font_size_override("font_size", 13)
		hdr.add_theme_color_override("font_color", HudWidgets.COL_ACC)
		right_drawer_vbox.add_child(hdr)

		# Editable common Valve KeyValues
		var fields := ["targetname", "TeamNum", "angles", "model", "skin", "_light"]
		for fkey in fields:
			if kv.has(fkey) or fkey in ["targetname", "angles", "TeamNum"]:
				var row := HBoxContainer.new()
				right_drawer_vbox.add_child(row)
				var kl := Label.new()
				kl.text = fkey
				kl.custom_minimum_size = Vector2(88, 0)
				kl.add_theme_font_size_override("font_size", 11)
				row.add_child(kl)
				var le := LineEdit.new()
				le.text = str(kv.get(fkey, ""))
				le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				var kcopy: String = fkey
				le.text_submitted.connect(func(v: String):
					doc.set_entity_kv(selected_entity, kcopy, v)
					doc.record_undo("Edit " + kcopy)
					ent_vis.sync_all()
					_toast("Set %s = %s" % [kcopy, v])
				)
				row.add_child(le)

		var hint := Label.new()
		hint.text = "Press Enter in any field to apply KeyValue immediately."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
		right_drawer_vbox.add_child(hint)
		return

	var empty := Label.new()
	empty.text = "Click any brush solid or entity in 3D to inspect and edit its Valve properties."
	empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty.add_theme_font_size_override("font_size", 12)
	right_drawer_vbox.add_child(empty)

func _commit_solid_edit(label: String) -> void:
	doc.record_undo(label)
	map_sync.sync_all()
	_refresh_selection_bar()
	audio.play("place")

func _push_selected_top(delta_m: float) -> void:
	if selected_solid < 0:
		return
	if doc.push_pull_normal(selected_solid, Vector3(0, 1, 0), delta_m):
		_commit_solid_edit("Push/Pull Top")

func _do_clip_selected(normal: Vector3) -> void:
	if selected_solid < 0:
		return
	var info: Dictionary = doc.get_solid_info(selected_solid)
	if not info.get("valid", false):
		return
	var mid: Vector3 = (info["bounds_min"] + info["bounds_max"]) * 0.5
	var res: int = doc.clip_solid(selected_solid, mid, normal, _clip_keep_mode)
	if res >= 0:
		doc.record_undo("Clip Solid")
		map_sync.sync_all()
		_select_solid(res, -1)
		audio.play("carve")
		_toast("Clipped solid cleanly!")
	else:
		_toast("Could not clip solid along that plane.")

func _rotate_selection() -> void:
	if selected_solid >= 0:
		if doc.rotate_solid_y(selected_solid, 90.0):
			_commit_solid_edit("Rotate Solid 90°")
			_toast("Rotated Solid #%d by 90°" % selected_solid)
	elif selected_entity >= 0:
		var ents: Array = doc.get_entities()
		if selected_entity < ents.size():
			var ang: String = str(ents[selected_entity]["kv"].get("angles", "0 0 0"))
			var parts := ang.split(" ", false)
			var p := float(parts[0]) if parts.size() > 0 else 0.0
			var y := (float(parts[1]) if parts.size() > 1 else 0.0) + 90.0
			var r := float(parts[2]) if parts.size() > 2 else 0.0
			if y >= 360.0: y -= 360.0
			doc.set_entity_kv(selected_entity, "angles", "%.0f %.0f %.0f" % [p, y, r])
			doc.record_undo("Rotate Entity 90°")
			ent_vis.sync_all()
			audio.play("click")
			_toast("Rotated Entity #%d to %.0f°" % [selected_entity, y])

func _duplicate_selection() -> void:
	if selected_solid >= 0:
		var nid: int = doc.duplicate_solid(selected_solid, Vector3(grid_m, 0, 0))
		if nid >= 0:
			doc.record_undo("Duplicate Solid")
			map_sync.sync_all()
			_select_solid(nid, -1)
			audio.play("place")
			_toast("Cloned Solid #%d! (Use Arrow keys or Drag to move)" % nid)
	elif selected_entity >= 0:
		var nid: int = doc.duplicate_entity(selected_entity, Vector3(grid_m, 0, 0))
		if nid >= 0:
			doc.record_undo("Duplicate Entity")
			ent_vis.sync_all()
			_select_entity(nid)
			audio.play("place")
			_toast("Cloned Entity #%d!" % nid)

func _delete_selection() -> void:
	if selected_solid >= 0:
		var idx := selected_solid
		if doc.delete_solid(idx):
			doc.record_undo("Delete Solid")
			_clear_selection()
			map_sync.sync_all()
			audio.play("carve")
			_toast("Deleted Solid #%d (Ctrl+Z to Undo)" % idx)
	elif selected_entity >= 0:
		var idx := selected_entity
		if doc.delete_entity(idx):
			doc.record_undo("Delete Entity")
			_clear_selection()
			ent_vis.sync_all()
			audio.play("carve")
			_toast("Deleted Entity #%d (Ctrl+Z to Undo)" % idx)

func _nudge_selection(delta: Vector3) -> void:
	if selected_solid >= 0:
		if doc.translate_solid(selected_solid, delta):
			_commit_solid_edit("Nudge Solid")
	elif selected_entity >= 0:
		var ents: Array = doc.get_entities()
		if selected_entity < ents.size():
			var p: Vector3 = ents[selected_entity]["pos"] + delta
			doc.set_entity_pos(selected_entity, p)
			doc.record_undo("Nudge Entity")
			ent_vis.sync_all()

# ==============================================================================
# BUILDING, TERRAIN, BIOMES, LIVE VPK SWATCHES & 3D PROP BROWSER DRAWERS
# ==============================================================================
func _open_building_wizard() -> void:
	_clear_drawer("MODULAR BUILDING WIZARD")
	var info := Label.new()
	info.text = "Click anywhere in the 3D scene to stamp a complete TF2 building with auto-carved doorways, sniper windows & interior stairs!"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_override("font", fonts["body"])
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	right_drawer_vbox.add_child(info)

	var fl_lbl := Label.new(); fl_lbl.text = "Stories (144u each):"; right_drawer_vbox.add_child(fl_lbl)
	var fl_row := HBoxContainer.new(); right_drawer_vbox.add_child(fl_row)
	for f: int in [1, 2, 3]:
		var b := Button.new(); b.text = "%d Floor%s" % [f, "s" if f > 1 else ""]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		HudWidgets.style_tf2_button(b, fonts["heading"], 11, bld_floors == f)
		var fv: int = f
		b.pressed.connect(func(): bld_floors = fv; _open_building_wizard())
		fl_row.add_child(b)

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
	_clear_drawer("VPK MATERIAL PAINTER (SHIFT+A)")
	# Active material live swatch header!
	var top_card := HBoxContainer.new()
	top_card.add_theme_constant_override("separation", 8)
	right_drawer_vbox.add_child(top_card)

	var cur_tex: Texture2D = assets.get_material_swatch(active_material)
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(56, 56)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_SCALE
	preview.texture = cur_tex
	top_card.add_child(preview)

	var info_vb := VBoxContainer.new()
	info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_card.add_child(info_vb)
	var cur_lbl := Label.new()
	cur_lbl.text = active_material.get_file()
	cur_lbl.add_theme_font_override("font", fonts["heading"])
	cur_lbl.add_theme_font_size_override("font_size", 12)
	cur_lbl.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	info_vb.add_child(cur_lbl)
	var hint := Label.new()
	hint.text = "LMB: Paint Face | Alt+Click: Eyedropper"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED)
	info_vb.add_child(hint)

	# Search bar
	var search := LineEdit.new()
	search.placeholder_text = "Filter textures (dev, wood, brick, metal...)"
	search.text = _mat_search_text
	right_drawer_vbox.add_child(search)

	var list_root := VBoxContainer.new()
	list_root.add_theme_constant_override("separation", 6)
	right_drawer_vbox.add_child(list_root)

	var populate := func(flt: String) -> void:
		_mat_search_text = flt
		for ch in list_root.get_children():
			ch.queue_free()
		var fl := flt.to_lower().strip_edges()
		for cat in Tf2CatalogScript.MATERIAL_CATEGORIES.keys():
			var items: Array = []
			for item in Tf2CatalogScript.MATERIAL_CATEGORIES[cat]:
				if fl.is_empty() or str(item["name"]).to_lower().find(fl) != -1 or str(item["mat"]).to_lower().find(fl) != -1 or str(cat).to_lower().find(fl) != -1:
					items.append(item)
			if items.is_empty():
				continue
			var cl := Label.new()
			cl.text = str(cat).to_upper()
			cl.add_theme_font_override("font", fonts["heading"])
			cl.add_theme_font_size_override("font_size", 11)
			cl.add_theme_color_override("font_color", HudWidgets.COL_ACC)
			list_root.add_child(cl)
			var g := GridContainer.new()
			g.columns = 2
			g.add_theme_constant_override("h_separation", 5)
			g.add_theme_constant_override("v_separation", 5)
			list_root.add_child(g)
			for item in items:
				var mp: String = item["mat"]
				var is_act := (active_material == mp)
				var b := Button.new()
				b.custom_minimum_size = Vector2(0, 50)
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				HudWidgets.style_tf2_button(b, fonts["body"], 10, is_act)

				var hb := HBoxContainer.new()
				hb.set_anchors_preset(Control.PRESET_FULL_RECT)
				hb.offset_left = 4; hb.offset_right = -4; hb.offset_top = 4; hb.offset_bottom = -4
				hb.add_theme_constant_override("separation", 6)
				hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
				b.add_child(hb)

				var sw := TextureRect.new()
				sw.custom_minimum_size = Vector2(40, 40)
				sw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				sw.stretch_mode = TextureRect.STRETCH_SCALE
				sw.texture = assets.get_material_swatch(mp)
				sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
				hb.add_child(sw)

				var nl := Label.new()
				nl.text = str(item["name"])
				nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				nl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				nl.add_theme_font_override("font", fonts["body"])
				nl.add_theme_font_size_override("font_size", 10)
				nl.add_theme_color_override("font_color", Color(0.10, 0.07, 0.04) if is_act else HudWidgets.COL_TX)
				nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
				hb.add_child(nl)

				b.pressed.connect(func():
					active_material = mp
					active_tool = "paint"
					audio.play("click")
					_open_materials_drawer()
				)
				g.add_child(b)

	populate.call(_mat_search_text)
	search.text_changed.connect(populate)

func _open_props_drawer() -> void:
	_clear_drawer("3D TF2 PROP BROWSER")
	# Live Rotating 3D Valve .mdl Prop Preview Viewport!
	var pv_frame := PanelContainer.new()
	pv_frame.custom_minimum_size = Vector2(0, 148)
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(0.10, 0.09, 0.08, 1.0)
	psb.border_color = HudWidgets.COL_ACC
	psb.set_border_width_all(1)
	psb.set_corner_radius_all(6)
	pv_frame.add_theme_stylebox_override("panel", psb)
	right_drawer_vbox.add_child(pv_frame)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(280, 140)
	pv_frame.add_child(svc)

	var svp := SubViewport.new()
	svp.own_world_3d = true
	svp.transparent_bg = false
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(svp)

	var pwe := WorldEnvironment.new()
	var penv := Environment.new()
	penv.background_mode = Environment.BG_COLOR
	penv.background_color = Color(0.14, 0.12, 0.11)
	penv.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	penv.ambient_light_color = Color(0.85, 0.84, 0.80)
	penv.ambient_light_energy = 1.0
	pwe.environment = penv
	svp.add_child(pwe)

	var pl := DirectionalLight3D.new()
	pl.rotation_degrees = Vector3(-35, 45, 0)
	pl.light_energy = 1.5
	svp.add_child(pl)

	var pcam := Camera3D.new()
	pcam.fov = 45.0
	svp.add_child(pcam)

	var pmesh: ArrayMesh = assets.get_model_mesh(active_prop_mdl)
	var pmi := MeshInstance3D.new()
	pmi.mesh = pmesh
	svp.add_child(pmi)
	_prop_preview_mesh = pmi
	if pmesh != null:
		var aabb := pmesh.get_aabb()
		var center := aabb.position + aabb.size * 0.5
		var rad := maxf(aabb.size.length() * 0.65, 0.8)
		pmi.position = -center
		pcam.look_at_from_position(Vector3(rad * 1.15, rad * 0.65, rad * 1.15), Vector3.ZERO, Vector3.UP)
	else:
		pcam.look_at_from_position(Vector3(2.5, 1.5, 2.5), Vector3.ZERO, Vector3.UP)

	var active_lbl := Label.new()
	active_lbl.text = "Selected: " + active_prop_mdl.get_file()
	active_lbl.add_theme_font_size_override("font_size", 11)
	active_lbl.add_theme_color_override("font_color", HudWidgets.COL_ACC)
	right_drawer_vbox.add_child(active_lbl)

	var search := LineEdit.new()
	search.placeholder_text = "Filter TF2 props (crate, barrel, pine, computer...)"
	search.text = _prop_search_text
	right_drawer_vbox.add_child(search)

	var list_root := VBoxContainer.new()
	list_root.add_theme_constant_override("separation", 5)
	right_drawer_vbox.add_child(list_root)

	var populate := func(flt: String) -> void:
		_prop_search_text = flt
		for ch in list_root.get_children():
			ch.queue_free()
		var fl := flt.to_lower().strip_edges()
		for cat in Tf2CatalogScript.PROP_CATEGORIES.keys():
			var items: Array = []
			for item in Tf2CatalogScript.PROP_CATEGORIES[cat]:
				if fl.is_empty() or str(item["name"]).to_lower().find(fl) != -1 or str(item["mdl"]).to_lower().find(fl) != -1 or str(cat).to_lower().find(fl) != -1:
					items.append(item)
			if items.is_empty():
				continue
			var cl := Label.new()
			cl.text = str(cat).to_upper()
			cl.add_theme_font_override("font", fonts["heading"])
			cl.add_theme_font_size_override("font_size", 11)
			cl.add_theme_color_override("font_color", HudWidgets.COL_ACC)
			list_root.add_child(cl)
			var g := GridContainer.new(); g.columns = 2; list_root.add_child(g)
			for item in items:
				var b := Button.new()
				b.text = item["name"]
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				HudWidgets.style_tf2_button(b, fonts["body"], 11, active_prop_mdl == item["mdl"])
				var mp: String = item["mdl"]
				var nm: String = item["name"]
				b.pressed.connect(func():
					active_prop_mdl = mp
					active_tool = "place_prop"
					audio.play("click")
					_toast("Click in 3D to place %s" % nm)
					_open_props_drawer()
				)
				g.add_child(b)

	populate.call(_prop_search_text)
	search.text_changed.connect(populate)

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

	var vac_note := Label.new()
	vac_note.text = "VAC-Safe: TF2 always launches with -insecure +sv_lan 1."
	vac_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vac_note.add_theme_font_size_override("font_size", 10)
	vac_note.add_theme_color_override("font_color", HudWidgets.COL_GREEN)
	right_drawer_vbox.add_child(vac_note)

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
	play_tf2_b.text = "Compile & Launch in Real TF2 (-insecure)"
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
	_clear_selection()
	var meta: Dictionary = Tf2GamemodesScript.build_gamemode_template(doc, mode_id, biome_override)
	active_biome = meta["biome"]
	active_sky = meta["sky"]
	_apply_environment_from_biome(active_biome)
	grid_floor.visible = true
	map_sync.clear_all()
	map_sync.sync_all()
	ent_vis.sync_all()
	map_title_lbl.text = "| " + str(meta["map_name"])
	_rebuild_bottom_dock()
	if show_toast:
		_toast("Created %s starter map — sealed & ready to edit or F5 playtest!" % mode_id.to_upper())

func _load_official_bsp(map_name: String) -> void:
	_clear_official_bsp()
	_clear_selection()
	map_sync.clear_all()
	ent_vis.clear_all()
	right_drawer.visible = false

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
	grid_floor.visible = false
	sym_plane.visible = false
	ghost_mesh.visible = false
	brush_ring.visible = false
	cam_pos = current_bsp_spawn + Vector3(12, 10, 12)
	_apply_editor_cam()
	_rebuild_bottom_dock()
	_refresh_selection_bar()
	overlay_2d.queue_redraw()
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
		_clear_selection()
		map_sync.sync_all()
		ent_vis.sync_all()
		_toast("Undo")

func _do_redo() -> void:
	if doc.redo():
		_clear_selection()
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
		_clear_selection()
		var r: Dictionary = doc.load_vmf(path)
		if r.get("ok", false):
			active_sky = doc.get_skyname()
			we.environment.sky = assets.get_sky(active_sky)
			grid_floor.visible = true
			map_sync.clear_all()
			map_sync.sync_all()
			ent_vis.sync_all()
			map_title_lbl.text = "| " + doc.get_map_name()
			_rebuild_bottom_dock()
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
	ModelImporterScript.export_tf2_qc_smd(
		REPO_ROOT + "/godot/maps/exported_qc", imp["name"], imp["mesh"], float(imp["scale"])
	)
	audio.play("success", -10.0)
	_toast("Imported %s (%.0fu tall) + exported Valve .QC/.SMD!" % [imp["name"], (imp["size_u"] as Vector3).y])

func _cycle_symmetry() -> void:
	symmetry = (symmetry + 1) % 3
	sym_plane.visible = (symmetry != SymmetryMode.OFF) and not viewing_bsp
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
# F5 PLAYTEST TRANSITION (Focus-Safe + Auto-Recapture!)
# ==============================================================================
func _enter_playtest() -> void:
	get_viewport().gui_release_focus()
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
				var to_mid := Vector2(-sp.x, -sp.z)
				yaw = rad_to_deg(atan2(-to_mid.x, -to_mid.y))
				break
	editor_cam.current = false
	player.spawn_at(sp, yaw, ents)
	player.set_active(true)
	playtest_hud.visible = true
	selection_bar.visible = false
	sym_plane.visible = false
	ghost_mesh.visible = false
	brush_ring.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _exit_playtest() -> void:
	player.set_active(false)
	editor_cam.current = true
	playtest_hud.visible = false
	sym_plane.visible = (symmetry != SymmetryMode.OFF) and not viewing_bsp
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ==============================================================================
# 3D INTERACTION, DIRECT FACE-PULL, SHIFT+DRAG CLONE, SCULPTING & HOTKEYS
# ==============================================================================
func _is_typing_in_ui() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit

func _unhandled_input(event: InputEvent) -> void:
	if welcome_panel.visible:
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			_show_welcome_hub(false)
		return

	if event is InputEventKey:
		if _is_typing_in_ui() and event.keycode != KEY_ESCAPE:
			return
		if event.pressed and not event.echo:
			if event.keycode == KEY_F5:
				set_stage(Stage.BUILD if stage == Stage.PLAYTEST else Stage.PLAYTEST)
				return
			if event.keycode == KEY_ESCAPE:
				if stage == Stage.PLAYTEST:
					set_stage(Stage.BUILD)
				elif selected_solid >= 0 or selected_entity >= 0:
					_clear_selection()
				elif right_drawer.visible:
					right_drawer.visible = false
				return
			if stage == Stage.PLAYTEST:
				player.handle_key_press(event.keycode)
				return

			# Hammer++ / TrenchBroom Editor Hotkeys
			if event.keycode == KEY_Q:
				pie_wheel.open_at(get_viewport().get_mouse_position())
				return
			elif event.keycode == KEY_L:
				_select_tool("wires")
			elif event.keycode == KEY_Z and event.ctrl_pressed:
				_do_undo()
			elif event.keycode == KEY_Y and event.ctrl_pressed:
				_do_redo()
			elif event.keycode == KEY_S and event.ctrl_pressed:
				_save_current_vmf()
			elif event.keycode == KEY_D and event.ctrl_pressed:
				_duplicate_selection()
			elif event.keycode == KEY_T and event.ctrl_pressed:
				_open_tie_entity_drawer()
			elif event.keycode == KEY_X and event.shift_pressed:
				_open_clip_drawer()
			elif event.keycode == KEY_A and event.shift_pressed:
				set_stage(Stage.STYLE)
				_open_materials_drawer()
			elif (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and event.alt_pressed:
				_open_inspector_drawer()
			elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
				_delete_selection()
			elif event.keycode == KEY_BRACKETLEFT:
				_step_grid(-1)
			elif event.keycode == KEY_BRACKETRIGHT:
				_step_grid(1)
			elif event.keycode == KEY_R:
				_rotate_selection()
			elif event.keycode == KEY_SPACE:
				_toggle_2d_view()
			elif selected_solid >= 0 or selected_entity >= 0:
				# Arrow-key grid nudging!
				var fwd_h := Vector3(-editor_cam.global_transform.basis.z.x, 0.0, -editor_cam.global_transform.basis.z.z).normalized()
				var right_h := Vector3(editor_cam.global_transform.basis.x.x, 0.0, editor_cam.global_transform.basis.x.z).normalized()
				# Snap camera basis to primary cardinal axis for exact Hammer nudging!
				var snap_axis := func(v: Vector3) -> Vector3:
					return Vector3(signf(v.x), 0.0, 0.0) if absf(v.x) >= absf(v.z) else Vector3(0.0, 0.0, signf(v.z))
				if event.keycode == KEY_UP: _nudge_selection(snap_axis.call(fwd_h) * grid_m)
				elif event.keycode == KEY_DOWN: _nudge_selection(-snap_axis.call(fwd_h) * grid_m)
				elif event.keycode == KEY_RIGHT: _nudge_selection(snap_axis.call(right_h) * grid_m)
				elif event.keycode == KEY_LEFT: _nudge_selection(-snap_axis.call(right_h) * grid_m)
				elif event.keycode == KEY_PAGEUP: _nudge_selection(Vector3(0, grid_m, 0))
				elif event.keycode == KEY_PAGEDOWN: _nudge_selection(Vector3(0, -grid_m, 0))
			elif stage == Stage.BUILD and not viewing_bsp:
				var num_tools := {
					KEY_1: "select", KEY_2: "floor", KEY_3: "wall", KEY_4: "building",
					KEY_5: "ramp", KEY_6: "stairs", KEY_7: "arch", KEY_8: "carve", KEY_9: "terrain"
				}
				if num_tools.has(event.keycode):
					_select_tool(num_tools[event.keycode])
		elif not event.pressed and event.keycode == KEY_Q:
			pie_wheel.close_and_commit()
			return

	if stage == Stage.PLAYTEST:
		if event is InputEventMouseMotion:
			player.handle_mouse_motion(event.relative)
		elif event is InputEventMouseButton:
			if event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			player.handle_mouse_button(event.button_index, event.pressed)
		return

	if event is InputEventMouseMotion:
		if pie_wheel.visible:
			pie_wheel.update_pointer(event.position)
			return
		if _dragging_face:
			_update_face_drag(event.position)
			return
		if _dragging_move:
			_update_move_drag(event.position)
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
			if not event.pressed:
				if _dragging_face:
					_dragging_face = false
					doc.record_undo("Push/Pull Face")
					_refresh_selection_bar()
					return
				if _dragging_move:
					_dragging_move = false
					doc.record_undo("Move Selection")
					_refresh_selection_bar()
					return
			if active_tool == "terrain":
				_terrain_sculpting = event.pressed
				if event.pressed and hover_valid:
					_do_terrain_sculpt_stroke()
				elif not event.pressed:
					doc.record_undo("Sculpt Terrain")
			elif event.pressed:
				_handle_left_click(event.position, event.shift_pressed, event.alt_pressed)

func _ray_plane_point(screen_pos: Vector2, plane_y: float) -> Vector3:
	var ro := editor_cam.project_ray_origin(screen_pos)
	var rd := editor_cam.project_ray_normal(screen_pos)
	if absf(rd.y) < 0.001:
		return _move_last_pos
	var t := (plane_y - ro.y) / rd.y
	if t <= 0.1 or t > 400.0:
		return _move_last_pos
	var p := ro + rd * t
	return Vector3(snappedf(p.x, grid_m), plane_y, snappedf(p.z, grid_m))

func _project_ray_onto_axis(ro: Vector3, rd: Vector3, origin: Vector3, axis: Vector3) -> float:
	# Closest point parameter t along line (origin + t * axis) to ray (ro + s * rd)
	var w0 := origin - ro
	var a := axis.dot(axis)
	var b := axis.dot(rd)
	var c := rd.dot(rd)
	var d := axis.dot(w0)
	var e := rd.dot(w0)
	var denom := a * c - b * b
	if absf(denom) < 0.0001:
		return 0.0
	return (b * e - c * d) / denom

func _update_face_drag(screen_pos: Vector2) -> void:
	var ro := editor_cam.project_ray_origin(screen_pos)
	var rd := editor_cam.project_ray_normal(screen_pos)
	var raw_t := _project_ray_onto_axis(ro, rd, _drag_anchor, _drag_normal)
	var snapped_t := snappedf(raw_t, grid_m)
	var step := snapped_t - _drag_accum
	if absf(step) >= grid_m * 0.5:
		if doc.push_pull_normal(_drag_solid, _drag_normal, step):
			_drag_accum = snapped_t
			map_sync.sync_solid(_drag_solid)
			map_sync.set_selection(_drag_solid, -1)
			_refresh_selection_bar()
			audio.play("click", -14.0)

func _update_move_drag(screen_pos: Vector2) -> void:
	var p := _ray_plane_point(screen_pos, _move_last_pos.y)
	var delta := p - _move_last_pos
	if delta.length_squared() > 0.001:
		_move_last_pos = p
		if selected_solid >= 0:
			doc.translate_solid(selected_solid, delta)
			map_sync.sync_solid(selected_solid)
			map_sync.set_selection(selected_solid, -1)
		elif selected_entity >= 0:
			var ents: Array = doc.get_entities()
			if selected_entity < ents.size():
				doc.set_entity_pos(selected_entity, ents[selected_entity]["pos"] + delta)
				ent_vis.sync_all()

func _pick_scene_object(ro: Vector3, rd: Vector3) -> Dictionary:
	var rc_ent: Dictionary = doc.raycast_entity(ro, rd)
	var rc_face: Dictionary = doc.raycast_face(ro, rd)
	var hit_e: bool = rc_ent.get("hit", false)
	var hit_f: bool = rc_face.get("hit", false)
	if hit_e and hit_f:
		# Prioritize entities if closer or resting on top of the hit brush (within 0.65m)
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
		_toast("Viewing official %s — click 'Walk Inside (F5)' below!" % current_bsp_name)
		return
	var ro := editor_cam.project_ray_origin(screen_pos)
	var rd := editor_cam.project_ray_normal(screen_pos)

	if active_tool == "select":
		# 1. Check 3D Face-Pull Handle Arrows first!
		if selected_solid >= 0:
			var h: Dictionary = map_sync.hit_test_face_handle(ro, rd)
			if not h.is_empty():
				_dragging_face = true
				_drag_solid = int(h["solid_idx"])
				_drag_normal = h["normal"]
				_drag_anchor = h["pos"]
				_drag_accum = 0.0
				audio.play("click")
				return

		# 2. Raycast Entities & Solids
		var pick := _pick_scene_object(ro, rd)
		if pick["kind"] == "entity":
			var eidx: int = pick["idx"]
			if shift_held:
				var nid: int = doc.duplicate_entity(eidx, Vector3.ZERO)
				if nid >= 0:
					ent_vis.sync_all()
					eidx = nid
					_toast("Shift+Drag Cloned Entity #%d!" % nid)
			_select_entity(eidx)
			_dragging_move = true
			_move_last_pos = _ray_plane_point(screen_pos, (pick["hit_pos"] as Vector3).y)
			audio.play("click")
		elif pick["kind"] == "solid":
			var sidx: int = pick["idx"]
			var fidx: int = pick["face"]
			if shift_held:
				# TrenchBroom/Hammer Shift+Drag: clone solid and drag!
				var nid: int = doc.duplicate_solid(sidx, Vector3.ZERO)
				if nid >= 0:
					map_sync.sync_all()
					sidx = nid
					_select_solid(sidx, -1)
					_dragging_move = true
					_move_last_pos = _ray_plane_point(screen_pos, (pick["hit_pos"] as Vector3).y)
					audio.play("place")
					_toast("Shift+Drag Cloned Solid #%d!" % nid)
					return
			_select_solid(sidx, fidx)
			audio.play("click")
		else:
			_clear_selection()
		return

	if active_tool == "paint":
		var rc: Dictionary = doc.raycast_face(ro, rd)
		if rc.get("hit", false):
			if alt_held:
				# Hammer Eyedropper (Alt+Click)!
				var sinfo: Dictionary = doc.get_solid_info(int(rc["solid_idx"]))
				var picked_mat: String = str(sinfo.get("material", active_material))
				if not picked_mat.is_empty():
					active_material = picked_mat
					audio.play("click")
					_toast("Eyedropper picked: " + active_material)
					if right_drawer.visible:
						_open_materials_drawer()
				return
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
		if not created_solids.is_empty() and created_solids[0] >= 0:
			_select_solid(created_solids[0], -1)
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
			var eid: int = doc.add_point_entity("prop_static", pos, {"model": active_prop_mdl, "angles": "0 0 0", "solid": "6"})
			doc.record_undo("Place Prop")
			ent_vis.sync_all()
			if eid >= 0:
				_select_entity(eid)
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
	# Official Valve Map Mode: NEVER show ghost blocks, hover wireframes, or jump badges!
	if viewing_bsp:
		hover_valid = false
		ghost_mesh.visible = false
		brush_ring.visible = false
		map_sync.set_hover(-1)
		ent_vis.set_hover(-1)
		overlay_2d.queue_redraw()
		return

	var ro := editor_cam.project_ray_origin(screen_pos)
	var rd := editor_cam.project_ray_normal(screen_pos)
	var hit_p := Vector3.ZERO
	hover_valid = false

	# Proactive TrenchBroom/Hammer++ 3D Hover Highlighting in Select & Paint modes!
	if active_tool == "select" or active_tool == "paint":
		var pick := _pick_scene_object(ro, rd)
		if pick["kind"] == "entity" and active_tool == "select":
			ent_vis.set_hover(pick["idx"])
			map_sync.set_hover(-1)
		elif pick["kind"] == "solid":
			map_sync.set_hover(pick["idx"])
			ent_vis.set_hover(-1)
		else:
			map_sync.set_hover(-1)
			ent_vis.set_hover(-1)
		ghost_mesh.visible = false
		brush_ring.visible = false
		overlay_2d.queue_redraw()
		return
	else:
		map_sync.set_hover(-1)
		ent_vis.set_hover(-1)

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
	# Auto-hide top toast pill
	if _toast_ttl > 0.0:
		_toast_ttl -= delta
		if _toast_ttl <= 0.0:
			toast_panel.visible = false

	# Gently spin 3D Prop Browser preview model
	if _prop_preview_mesh != null and is_instance_valid(_prop_preview_mesh):
		_prop_preview_mesh.rotate_y(delta * 0.85)

	# Smooth WASD fly camera in Editor mode (disabled when typing in search/inspector fields!)
	if stage != Stage.PLAYTEST and not welcome_panel.visible and not _is_typing_in_ui():
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
		editor_cam.position = cam_pos
		editor_cam.rotation = Vector3(cam_pitch, cam_yaw, 0.0)

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

	# Live Jump-Threshold Ruler Callout next to Ghost Block (NEVER shown in Official BSP mode!)
	if ghost_mesh.visible and not welcome_panel.visible and not viewing_bsp:
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
	toast_panel.visible = true
	_toast_ttl = 4.2

# ==============================================================================
# CLI SCREENSHOT AUTOMATION HOOK (for GPU visual verification & Critic Reviews!)
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
		"selection":
			_show_welcome_hub(false)
			_load_gamemode("koth", "badlands", false)
			set_stage(Stage.BUILD)
			_select_tool("select")
			right_drawer.visible = false
			cam_pos = Vector3(18, 13, 20); cam_yaw = 0.68; cam_pitch = -0.44
			_apply_editor_cam()
			# Select a prominent solid in the middle of the arena to show 3D Face-Pull cones & Selection Action Bar!
			var best_s := 1
			for s_i in range(doc.get_solid_count()):
				var si: Dictionary = doc.get_solid_info(s_i)
				if not si.get("is_skybox", false) and s_i > 1:
					best_s = s_i
					break
			_select_solid(best_s, 0)
			_toast("Drag glowing Face-Pull arrows, press Del to remove, or Shift+X to Clip!")
		"swatches":
			_show_welcome_hub(false)
			_load_gamemode("koth", "alpine", false)
			set_stage(Stage.STYLE)
			_open_materials_drawer()
			cam_pos = Vector3(22, 16, 26); cam_yaw = 0.65; cam_pitch = -0.42
			_apply_editor_cam()
		"props3d":
			_show_welcome_hub(false)
			_load_gamemode("koth", "badlands", false)
			set_stage(Stage.STYLE)
			_open_props_drawer()
			cam_pos = Vector3(22, 16, 26); cam_yaw = 0.65; cam_pitch = -0.42
			_apply_editor_cam()
		"inspector":
			_show_welcome_hub(false)
			_load_gamemode("koth", "badlands", false)
			set_stage(Stage.BUILD)
			_select_tool("select")
			_select_solid(2, 0)
			_open_inspector_drawer()
			cam_pos = Vector3(18, 13, 20); cam_yaw = 0.68; cam_pitch = -0.44
			_apply_editor_cam()
		"visgroups":
			_show_welcome_hub(false)
			_load_gamemode("mvm", "mvm", false)
			set_stage(Stage.GAMEPLAY)
			_open_visgroups_drawer()
			cam_pos = Vector3(-16, 17, 26); cam_yaw = -0.58; cam_pitch = -0.46
			_apply_editor_cam()
		"official_degroot":
			_show_welcome_hub(false)
			_load_official_bsp("cp_degrootkeep_rats.bsp")
			cam_pos = current_bsp_spawn + Vector3(12, 14, 18)
			editor_cam.look_at_from_position(cam_pos, current_bsp_spawn + Vector3(0, 3, -6), Vector3.UP)
			cam_yaw = editor_cam.rotation.y
			cam_pitch = editor_cam.rotation.x
		"f5_turbine":
			_show_welcome_hub(false)
			_load_official_bsp("ctf_turbine.bsp")
			set_stage(Stage.PLAYTEST)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	if _auto_shot_frames == 12:
		var sh: Dictionary = _auto_shots[_auto_shot_idx]
		get_viewport().get_texture().get_image().save_png(sh["out"])
		print("Saved App Shot [%s]: %s" % [sh["mode"], sh["out"]])
		_auto_shot_idx += 1
		if _auto_shot_idx >= _auto_shots.size():
			get_tree().quit(0)
		else:
			_setup_auto_shot(_auto_shot_idx)
