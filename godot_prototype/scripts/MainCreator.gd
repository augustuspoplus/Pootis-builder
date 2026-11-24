extends Node3D

## Pootis Builder — Godot 4 Forward+ Edition
## Exact 1:1 Valve TF2 In-Game HUD (matching Build A's sleek layout & icons)
## powered by Godot 4 Vulkan Forward+ (4K soft shadows, SSAO, ACES lighting,
## walkable ramps & stairs, 3D/2D blueprint toggle, glowing 3D face-pull arrows,
## authentic Valve TF2 fonts/VPK textures/3D .mdl icons, and instant F5 TF2 Walk Playtest).

const Tf2PlayerScript := preload("res://scripts/Tf2Player.gd")
const VmfExporterScript := preload("res://scripts/VmfExporter.gd")
const HudW := preload("res://scripts/Tf2HudWidgets.gd")

const UPM := 32.0        # 1 Godot meter = 32 Hammer units
const GRID_U := 64.0
const GRID_M := GRID_U / UPM  # 2.0m

const COL_BG0 := Color("#161311")
const COL_BG1 := Color("#1d1916", 0.94)
const COL_BG2 := Color("#292420", 0.96)
const COL_BG3 := Color("#362f29", 0.98)
const COL_BD  := Color("#574c41")
const COL_ACC := Color("#e5872b")
const COL_ACC2 := Color("#cf7336")
const COL_TX  := Color("#f0e6d2")
const COL_DIM := Color("#bfb4a2")
const COL_FAINT := Color("#8a7f70")
const COL_RED := Color("#b8383b")
const COL_BLU := Color("#4c7ea0")
const COL_CYAN := Color("#00e5ff")
const COL_GOOD := Color("#6cc47c")

const BIOMES := [
	{
		"name": "Badlands Desert",
		"map": "badlands_arena",
		"sky": "sky_badlands_01",
		"desc": "Sandstone + Red Brick + Warm Sun",
		"sw1": Color("#b9764a"), "sw2": Color("#e6be8a"),
		"floor_tex": "badlands_floor.png", "wall_tex": "badlands_wall.png", "roof_tex": "badlands_roof.png",
		"floor_vmf": "concrete/concretefloor002", "wall_vmf": "brick/brickwall003a", "roof_vmf": "metal/metalroof006a",
		"floor_col": Color("#c89d72"), "wall_col": Color("#9c4f3c"), "roof_col": Color("#6d6259"),
		"sky_top": Color("#2d4e78"), "sky_hor": Color("#e5a56d"), "gnd_hor": Color("#9a6d4b"),
		"sun_col": Color("#ffe3bd"), "sun_energy": 1.65, "fog_col": Color("#cfa17c"),
	},
	{
		"name": "Alpine Winter",
		"map": "winter_outpost",
		"sky": "sky_alpinestorm_01",
		"desc": "Crisp Snow + Timber + Winter Sky",
		"sw1": Color("#d2e1f0"), "sw2": Color("#5f7d9b"),
		"floor_tex": "winter_floor.png", "wall_tex": "winter_wall.png", "roof_tex": "badlands_roof.png",
		"floor_vmf": "nature/snow_full001", "wall_vmf": "wood/wood_wall002", "roof_vmf": "metal/metalroof005a",
		"floor_col": Color("#dce6f0"), "wall_col": Color("#6e5745"), "roof_col": Color("#546270"),
		"sky_top": Color("#3b6496"), "sky_hor": Color("#c9ddf0"), "gnd_hor": Color("#8da4b8"),
		"sun_col": Color("#f2f7ff"), "sun_energy": 1.50, "fog_col": Color("#b8cde0"),
	},
	{
		"name": "Sawmill Forest",
		"map": "sawmill_yard",
		"sky": "sky_alpinestorm_01",
		"desc": "Wood + Tin Roof + Storm Sky",
		"sw1": Color("#73583e"), "sw2": Color("#556e80"),
		"floor_tex": "sawmill_floor.png", "wall_tex": "sawmill_wall.png", "roof_tex": "badlands_roof.png",
		"floor_vmf": "wood/wood_floor002", "wall_vmf": "wood/wood_wall004", "roof_vmf": "metal/metalroof006a",
		"floor_col": Color("#7a6855"), "wall_col": Color("#574b40"), "roof_col": Color("#4b5961"),
		"sky_top": Color("#283845"), "sky_hor": Color("#7c8c92"), "gnd_hor": Color("#4a544a"),
		"sun_col": Color("#d8e4ea"), "sun_energy": 1.25, "fog_col": Color("#6b7b80"),
	},
	{
		"name": "Spytech Facility",
		"map": "spytech_lab",
		"sky": "sky_upward",
		"desc": "Clean Tile + Computer Wall",
		"sw1": Color("#485f7d"), "sw2": Color("#b9c3cd"),
		"floor_tex": "spytech_floor.png", "wall_tex": "spytech_wall.png", "roof_tex": "badlands_roof.png",
		"floor_vmf": "tile/tilefloor001a", "wall_vmf": "concrete/computerwall003", "roof_vmf": "metal/metalwall001a",
		"floor_col": Color("#8b949e"), "wall_col": Color("#465569"), "roof_col": Color("#38424d"),
		"sky_top": Color("#141e30"), "sky_hor": Color("#4b5d78"), "gnd_hor": Color("#2a3240"),
		"sun_col": Color("#e0ecff"), "sun_energy": 1.40, "fog_col": Color("#3f4e63"),
	},
	{
		"name": "Orange Dev Studio",
		"map": "orange_greybox",
		"sky": "sky_tf2_04",
		"desc": "Classic TF2 Measure Grid Greybox",
		"sw1": Color("#dc7d28"), "sw2": Color("#5f666e"),
		"floor_tex": "orange_floor.png", "wall_tex": "orange_wall.png", "roof_tex": "orange_floor.png",
		"floor_vmf": "dev/dev_measuregeneric01b", "wall_vmf": "dev/dev_measurewall01a", "roof_vmf": "dev/dev_measuregeneric01",
		"floor_col": Color("#6b7178"), "wall_col": Color("#d47c2a"), "roof_col": Color("#555b61"),
		"sky_top": Color("#2a3442"), "sky_hor": Color("#7d6e60"), "gnd_hor": Color("#443d36"),
		"sun_col": Color("#fff0dc"), "sun_energy": 1.45, "fog_col": Color("#6a5e54"),
	},
]

# Authentic Valve TF2 fonts + Font Awesome icons + IBM Plex body font
var font_tf2_bold: Font
var font_tf2_sub: Font
var font_ui: Font
var font_fa: Font
var tex_cache: Dictionary = {}
var icon_cache: Dictionary = {}

# 3D Scene Nodes
var world_env: WorldEnvironment
var sky_mat: ProceduralSkyMaterial
var sun_light: DirectionalLight3D
var ed_cam: Camera3D
var player: CharacterBody3D
var map_root: Node3D
var stamps_root: Node3D
var handles_root: Node3D
var drag_preview: MeshInstance3D
var grid_mesh: MeshInstance3D
var ghost_world_pos := Vector3(-10.0, 0.0, 4.2)

# Editor State
var biome_idx := 0
var stage_idx := 0         # 0 Build, 1 Gameplay, 2 Style, 3 Playtest
var style_tab := 0         # 0 Themes, 1 Materials, 2 Lighting
var compile_prof := 0      # 0 Fast, 1 Final HDR
var launch_tf2_chk := true
var active_tool := "Select"
var symmetry_x := false
var show_ghost := true
var is_2d_ortho := false
var show_env_modal := false
var blocks: Array = []
var stamps: Array = []
var undo_stack: Array = []
var redo_stack: Array = []
var selected_idx := -1

# Camera State (3D Perspective + 2D Blueprint Orthographic)
var cam_pos := Vector3(-22.0, 13.5, 22.0)
var cam_yaw := -0.78
var cam_pitch := -0.44
var saved_3d_pos := Vector3(-22.0, 13.5, 22.0)
var saved_3d_yaw := -0.78
var saved_3d_pitch := -0.44
var ortho_size := 56.0
var rmb_down := false

# Drag-Paint & Glowing Face-Pull Arrow Drag State
var paint_dragging := false
var paint_start := Vector3.ZERO
var paint_end := Vector3.ZERO
var arrow_dragging := false
var arrow_axis := Vector3.ZERO
var arrow_face_sign := 1.0
var arrow_start_pos := Vector3.ZERO
var arrow_start_size := Vector3.ZERO
var arrow_drag_origin := Vector3.ZERO
var arrow_meshes: Array = []

# HUD Nodes
var hud_layer: CanvasLayer
var vp_overlay: Control
var tf2_menu: PopupMenu
var stage_btns: Array = []
var sym_btn: Button
var ghost_btn: Button
var view2d_btn: Button
var right_frame: PanelContainer
var right_vbox: VBoxContainer
var bl_icon_holder: CenterContainer
var bl_title: Label
var bl_dims_a: Label
var bl_dims_h: Label
var bl_actions_box: HBoxContainer
var bc_status_lbl: Label
var float_dim_lbl: Label
var env_modal: PanelContainer
var playtest_hud: Control
var playtest_lbl: Label
var toast_lbl: Label
var toast_timer := 0.0

var auto_shot_path := ""
var auto_shot_frames := 0

func _ready() -> void:
	_parse_cli_args()
	_load_fonts()
	_load_tf2_cache()
	_setup_3d_environment()
	_setup_camera_and_player()
	_setup_handles_and_previews()
	_build_hud()
	var init_sel := selected_idx
	load_biome(biome_idx, false)
	if init_sel >= 0 and init_sel < blocks.size():
		select_block(init_sel)
	_refresh_hud()

func _parse_cli_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--shot" and i + 1 < args.size():
			auto_shot_path = args[i + 1]
		elif args[i] == "--stage" and i + 1 < args.size():
			stage_idx = int(args[i + 1])
		elif args[i] == "--biome" and i + 1 < args.size():
			biome_idx = clampi(int(args[i + 1]), 0, BIOMES.size() - 1)
		elif args[i] == "--select" and i + 1 < args.size():
			selected_idx = int(args[i + 1])
		elif args[i] == "--env-modal":
			show_env_modal = true

func _load_fonts() -> void:
	var tf2_dirs := [
		"C:/Program Files (x86)/Steam/steamapps/common/Team Fortress 2/tf/resource/",
		"C:/Program Files/Steam/steamapps/common/Team Fortress 2/tf/resource/",
		"D:/SteamLibrary/steamapps/common/Team Fortress 2/tf/resource/",
	]
	for base in tf2_dirs:
		if FileAccess.file_exists(base + "tf2build.ttf"):
			var f := FontFile.new()
			f.load_dynamic_font(base + "tf2build.ttf")
			font_tf2_bold = f
		if FileAccess.file_exists(base + "tf2secondary.ttf"):
			var f2 := FontFile.new()
			f2.load_dynamic_font(base + "tf2secondary.ttf")
			font_tf2_sub = f2
		if font_tf2_bold != null:
			break

	var repo_fonts := ProjectSettings.globalize_path("res://../assets/fonts/")
	if FileAccess.file_exists(repo_fonts + "IBMPlexSans-Regular.ttf"):
		var fu := FontFile.new()
		fu.load_dynamic_font(repo_fonts + "IBMPlexSans-Regular.ttf")
		font_ui = fu
	if FileAccess.file_exists(repo_fonts + "fa-solid-900.ttf"):
		var ffa := FontFile.new()
		ffa.load_dynamic_font(repo_fonts + "fa-solid-900.ttf")
		font_fa = ffa

	if font_ui == null: font_ui = ThemeDB.fallback_font
	if font_tf2_bold == null: font_tf2_bold = font_ui
	if font_tf2_sub == null: font_tf2_sub = font_ui
	if font_fa == null: font_fa = font_ui

func _load_tf2_cache() -> void:
	var base := ProjectSettings.globalize_path("res://assets/tf2_cache/")
	var tex_dir := DirAccess.open(base + "textures")
	if tex_dir != null:
		for fn in tex_dir.get_files():
			if fn.ends_with(".png"):
				var img := Image.load_from_file(base + "textures/" + fn)
				if img != null:
					img.generate_mipmaps()
					tex_cache[fn] = ImageTexture.create_from_image(img)
	var ic_dir := DirAccess.open(base + "icons")
	if ic_dir != null:
		for fn in ic_dir.get_files():
			if fn.ends_with(".png"):
				var img := Image.load_from_file(base + "icons/" + fn)
				if img != null:
					icon_cache[fn] = ImageTexture.create_from_image(img)

func _setup_3d_environment() -> void:
	world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.06
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.65
	env.glow_enabled = true
	env.glow_intensity = 0.22
	env.fog_enabled = true
	env.fog_density = 0.0042
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.72
	world_env.environment = env
	add_child(world_env)

	sun_light = DirectionalLight3D.new()
	sun_light.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	sun_light.shadow_enabled = true
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun_light.directional_shadow_max_distance = 140.0
	sun_light.shadow_bias = 0.03
	sun_light.shadow_blur = 1.6
	add_child(sun_light)

	map_root = Node3D.new()
	add_child(map_root)
	stamps_root = Node3D.new()
	add_child(stamps_root)
	handles_root = Node3D.new()
	add_child(handles_root)

	grid_mesh = _make_ground_grid()
	add_child(grid_mesh)

func _make_ground_grid() -> MeshInstance3D:
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var ext := 48.0
	var step := GRID_M
	var y := 0.015
	for i in range(-24, 25):
		var c := float(i) * step
		var is_major := (i % 4 == 0)
		var col := Color(0.95, 0.80, 0.60, 0.20 if is_major else 0.08)
		if i == 0:
			im.surface_set_color(Color(COL_RED.r, COL_RED.g, COL_RED.b, 0.62))
			im.surface_add_vertex(Vector3(-ext, y, 0.0))
			im.surface_add_vertex(Vector3(ext, y, 0.0))
			im.surface_set_color(Color(COL_BLU.r, COL_BLU.g, COL_BLU.b, 0.62))
			im.surface_add_vertex(Vector3(0.0, y, -ext))
			im.surface_add_vertex(Vector3(0.0, y, ext))
		else:
			im.surface_set_color(col)
			im.surface_add_vertex(Vector3(c, y, -ext))
			im.surface_add_vertex(Vector3(c, y, ext))
			im.surface_add_vertex(Vector3(-ext, y, c))
			im.surface_add_vertex(Vector3(ext, y, c))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	return mi

func _setup_camera_and_player() -> void:
	ed_cam = Camera3D.new()
	ed_cam.fov = 60.0
	ed_cam.far = 500.0
	ed_cam.current = true
	add_child(ed_cam)
	_apply_editor_camera()

	player = Tf2PlayerScript.new()
	add_child(player)

func _setup_handles_and_previews() -> void:
	drag_preview = MeshInstance3D.new()
	drag_preview.mesh = BoxMesh.new()
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(COL_ACC.r, COL_ACC.g, COL_ACC.b, 0.42)
	pm.emission_enabled = true
	pm.emission = COL_ACC
	pm.emission_energy_multiplier = 0.65
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drag_preview.material_override = pm
	drag_preview.visible = false
	add_child(drag_preview)

	# 5 Big Glowing 3D Face-Pull Arrow Handles (+Y Cyan Height, +/-X & +/-Z Amber Side Pull)
	var defs := [
		{"axis": Vector3.UP,      "sign":  1.0, "col": COL_CYAN, "rot": Vector3(0, 0, 0),          "len": 2.0},
		{"axis": Vector3.RIGHT,   "sign":  1.0, "col": COL_ACC,  "rot": Vector3(0, 0, -PI * 0.5),  "len": 1.4},
		{"axis": Vector3.RIGHT,   "sign": -1.0, "col": COL_ACC,  "rot": Vector3(0, 0,  PI * 0.5),  "len": 1.4},
		{"axis": Vector3.BACK,    "sign":  1.0, "col": COL_ACC,  "rot": Vector3( PI * 0.5, 0, 0),  "len": 1.4},
		{"axis": Vector3.BACK,    "sign": -1.0, "col": COL_ACC,  "rot": Vector3(-PI * 0.5, 0, 0),  "len": 1.4},
	]
	for d in defs:
		var root := Node3D.new()
		var amat := StandardMaterial3D.new()
		amat.albedo_color = d["col"]
		amat.emission_enabled = true
		amat.emission = d["col"]
		amat.emission_energy_multiplier = 1.45
		amat.no_depth_test = true
		amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

		var L: float = d["len"]
		var shaft := MeshInstance3D.new()
		var sm := CylinderMesh.new()
		sm.top_radius = 0.085
		sm.bottom_radius = 0.085
		sm.height = L
		shaft.mesh = sm
		shaft.position = Vector3(0, L * 0.5, 0)
		shaft.material_override = amat
		root.add_child(shaft)

		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.28
		cm.height = 0.62
		cone.mesh = cm
		cone.position = Vector3(0, L + 0.25, 0)
		cone.material_override = amat
		root.add_child(cone)

		root.rotation = d["rot"]
		handles_root.add_child(root)
		arrow_meshes.append({"node": root, "axis": d["axis"], "sign": d["sign"], "len": L})
	handles_root.visible = false

# ----------------------------------------------------------------------------
# Biome Loading & Map Construction
# ----------------------------------------------------------------------------
func load_biome(idx: int, show_notice := true) -> void:
	biome_idx = clampi(idx, 0, BIOMES.size() - 1)
	var b: Dictionary = BIOMES[biome_idx]

	sky_mat.sky_top_color = b["sky_top"]
	sky_mat.sky_horizon_color = b["sky_hor"]
	sky_mat.ground_horizon_color = b["gnd_hor"]
	sky_mat.ground_bottom_color = b["gnd_hor"].darkened(0.45)
	sun_light.light_color = b["sun_col"]
	sun_light.light_energy = b["sun_energy"]
	world_env.environment.fog_light_color = b["fog_col"]

	_clear_world()
	# Sunlit TF2 courtyard with perimeter walls, mid cover walls, capture plinth, flank decks & stairs
	add_block(Vector3(0, -0.5, 0),        Vector3(64, 1.0, 48),   "floor", false)
	add_block(Vector3(0, 3.5, 23.5),      Vector3(64, 7.0, 1.0),  "wall",  false)
	add_block(Vector3(0, 3.5, -23.5),     Vector3(64, 7.0, 1.0),  "wall",  false)
	add_block(Vector3(-31.5, 3.5, 0),     Vector3(1.0, 7.0, 46),  "wall",  false)
	add_block(Vector3(31.5, 3.5, 0),      Vector3(1.0, 7.0, 46),  "wall",  false)
	add_block(Vector3(-10.0, 2.25, 2.5),  Vector3(1.25, 4.5, 10.0), "wall", false)
	add_block(Vector3( 10.0, 2.25,-2.5),  Vector3(1.25, 4.5, 10.0), "wall", false)
	add_block(Vector3(0.0, 0.375, 0.0),   Vector3(10.0, 0.75, 10.0), "roof", false)
	add_block(Vector3(-18.0, 1.0, -10.0), Vector3(8.0, 2.0, 6.0), "roof", false)
	add_block(Vector3( 18.0, 1.0,  10.0), Vector3(8.0, 2.0, 6.0), "roof", false)

	add_stamp(Vector3(-24.0, 0.0, 0.0),  "RED", false)
	add_stamp(Vector3( 24.0, 0.0, 0.0),  "BLU", false)
	add_stamp(Vector3(  0.0, 0.75, 0.0), "Point", false)
	add_stamp(Vector3(  0.0, 0.0, 11.0), "Health", false)
	add_stamp(Vector3(  0.0, 0.0,-11.0), "Ammo", false)

	_push_undo("Load " + b["name"])
	show_env_modal = false
	if env_modal != null:
		env_modal.visible = false
	if show_notice:
		_show_toast("Loaded %s — press F5 to walk around!" % b["name"])
	_refresh_hud()

func apply_biome_theme_in_place(idx: int) -> void:
	biome_idx = clampi(idx, 0, BIOMES.size() - 1)
	var b: Dictionary = BIOMES[biome_idx]
	sky_mat.sky_top_color = b["sky_top"]
	sky_mat.sky_horizon_color = b["sky_hor"]
	sky_mat.ground_horizon_color = b["gnd_hor"]
	sky_mat.ground_bottom_color = b["gnd_hor"].darkened(0.45)
	sun_light.light_color = b["sun_col"]
	sun_light.light_energy = b["sun_energy"]
	world_env.environment.fog_light_color = b["fog_col"]
	for blk in blocks:
		var role: String = blk["role"]
		blk["mesh"].material_override = _material_for_role(role)
		blk["vmf_mat"] = b.get(role + "_vmf", b["wall_vmf"])
	_show_toast("Painted map with %s theme!" % b["name"])
	_refresh_hud()

func _clear_world() -> void:
	for b in blocks:
		if is_instance_valid(b["node"]):
			b["node"].queue_free()
	blocks.clear()
	for s in stamps:
		if is_instance_valid(s["node"]):
			s["node"].queue_free()
	stamps.clear()
	selected_idx = -1
	handles_root.visible = false

func _material_for_role(role: String) -> StandardMaterial3D:
	var b: Dictionary = BIOMES[biome_idx]
	var mat := StandardMaterial3D.new()
	var tex_key: String = b.get(role + "_tex", b["floor_tex"])
	if tex_cache.has(tex_key):
		mat.albedo_texture = tex_cache[tex_key]
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
	else:
		mat.albedo_color = b.get(role + "_col", Color("#a08060"))
	mat.roughness = 0.86
	return mat

func add_block(pos: Vector3, sz: Vector3, role: String = "wall", record_undo := true) -> int:
	var bdef: Dictionary = BIOMES[biome_idx]
	var body := StaticBody3D.new()
	body.position = pos

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = sz
	mi.mesh = bm
	mi.material_override = _material_for_role(role)
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = sz
	cs.shape = bs
	body.add_child(cs)

	var idx := blocks.size()
	body.set_meta("block_idx", idx)
	map_root.add_child(body)
	var vmf_mat: String = bdef.get(role + "_vmf", bdef["wall_vmf"])
	blocks.append({
		"node": body, "mesh": mi, "col": cs,
		"pos": pos, "size": sz, "role": role, "vmf_mat": vmf_mat
	})
	if record_undo:
		_push_undo("Add " + role)
	return idx

func _update_block_geom(idx: int) -> void:
	if idx < 0 or idx >= blocks.size():
		return
	var b: Dictionary = blocks[idx]
	b["node"].position = b["pos"]
	(b["mesh"].mesh as BoxMesh).size = b["size"]
	(b["col"].shape as BoxShape3D).size = b["size"]
	if idx == selected_idx:
		_position_handles()
		_refresh_hud()

func add_stamp(pos: Vector3, kind: String, record_undo := true) -> void:
	var root := Node3D.new()
	root.position = pos
	var col := COL_ACC
	match kind:
		"RED": col = COL_RED
		"BLU": col = COL_BLU
		"Health": col = Color("#d9483b")
		"Ammo": col = Color("#8f9474")
		"Locker": col = Color("#cfd6dc")
		"Point": col = COL_ACC
		"Intel": col = COL_RED
		"Cart": col = Color("#4a535c")

	# Low grounded TF2 beacon ring/pad
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.05 if kind == "Point" else 0.52
	cyl.bottom_radius = 1.15 if kind == "Point" else 0.58
	cyl.height = 0.14
	base.mesh = cyl
	base.position = Vector3(0, 0.07, 0)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = col
	bmat.emission_enabled = true
	bmat.emission = col
	bmat.emission_energy_multiplier = 0.25
	base.material_override = bmat
	root.add_child(base)

	var icon_key := kind.to_lower() + ".png"
	if icon_cache.has(icon_key):
		# Transparent-background 3D TF2 .mdl sprite — ZERO square box!
		var sp := Sprite3D.new()
		sp.texture = icon_cache[icon_key]
		sp.pixel_size = 0.014
		sp.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sp.position = Vector3(0, 1.15, 0)
		root.add_child(sp)
	else:
		# Crisp RED / BLU Spawn Pillar Beacon
		var pill := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.34
		cm.height = 1.95
		pill.mesh = cm
		pill.position = Vector3(0, 1.05, 0)
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = col
		pmat.emission_enabled = true
		pmat.emission = col
		pmat.emission_energy_multiplier = 0.45
		pill.material_override = pmat
		root.add_child(pill)

	stamps_root.add_child(root)
	stamps.append({"node": root, "pos": pos, "kind": kind})
	if record_undo:
		_push_undo("Place " + kind)
	_refresh_hud()

func select_block(idx: int) -> void:
	if selected_idx >= 0 and selected_idx < blocks.size():
		var om: StandardMaterial3D = blocks[selected_idx]["mesh"].material_override
		om.emission_enabled = false
	selected_idx = idx
	if selected_idx >= 0 and selected_idx < blocks.size():
		var nm: StandardMaterial3D = blocks[selected_idx]["mesh"].material_override
		nm.emission_enabled = true
		nm.emission = COL_ACC
		nm.emission_energy_multiplier = 0.20
		handles_root.visible = true
		_position_handles()
		ghost_world_pos = blocks[selected_idx]["pos"] + Vector3(0, -blocks[selected_idx]["size"].y * 0.5, blocks[selected_idx]["size"].z * 0.5 + 1.2)
	else:
		handles_root.visible = false
	_refresh_hud()

func _position_handles() -> void:
	if selected_idx < 0 or selected_idx >= blocks.size():
		handles_root.visible = false
		return
	var b: Dictionary = blocks[selected_idx]
	var p: Vector3 = b["pos"]
	var s: Vector3 = b["size"]
	for h in arrow_meshes:
		var ax: Vector3 = h["axis"]
		var sg: float = h["sign"]
		var half := Vector3(s.x * 0.5, s.y * 0.5, s.z * 0.5)
		var face_pos := p + ax * sg * (half.dot(ax.abs()) + 0.12)
		(h["node"] as Node3D).position = face_pos

func _resize_selected_height(delta_u: float) -> void:
	if selected_idx < 0 or selected_idx >= blocks.size():
		return
	var b: Dictionary = blocks[selected_idx]
	var dm: float = delta_u / UPM
	var old_y: float = b["size"].y
	var new_h: float = max(0.5, old_y + dm)
	var actual: float = new_h - old_y
	b["size"].y = new_h
	b["pos"].y += actual * 0.5
	_update_block_geom(selected_idx)
	_push_undo("Height %+.0fu" % delta_u)

func _resize_selected_footprint(delta_u: float) -> void:
	if selected_idx < 0 or selected_idx >= blocks.size():
		return
	var b: Dictionary = blocks[selected_idx]
	var dm: float = delta_u / UPM
	b["size"].x = max(1.0, b["size"].x + dm)
	b["size"].z = max(1.0, b["size"].z + dm)
	_update_block_geom(selected_idx)
	_push_undo("Resize footprint")

func _delete_selected() -> void:
	if selected_idx < 0 or selected_idx >= blocks.size():
		return
	blocks[selected_idx]["node"].queue_free()
	blocks.remove_at(selected_idx)
	for i in range(blocks.size()):
		blocks[i]["node"].set_meta("block_idx", i)
	selected_idx = -1
	handles_root.visible = false
	_push_undo("Delete block")
	_refresh_hud()

# ----------------------------------------------------------------------------
# Undo / Redo Snapshot Stack
# ----------------------------------------------------------------------------
func _snapshot() -> Dictionary:
	var bs: Array = []
	for b in blocks:
		bs.append({"pos": b["pos"], "size": b["size"], "role": b["role"]})
	var ss: Array = []
	for s in stamps:
		ss.append({"pos": s["pos"], "kind": s["kind"]})
	return {"biome": biome_idx, "blocks": bs, "stamps": ss}

func _push_undo(_lbl: String) -> void:
	undo_stack.append(_snapshot())
	if undo_stack.size() > 40:
		undo_stack.pop_front()
	redo_stack.clear()

func _restore_snapshot(snap: Dictionary) -> void:
	biome_idx = snap["biome"]
	_clear_world()
	for b in snap["blocks"]:
		add_block(b["pos"], b["size"], b["role"], false)
	for s in snap["stamps"]:
		add_stamp(s["pos"], s["kind"], false)
	_refresh_hud()

func do_undo() -> void:
	if undo_stack.size() <= 1: return
	redo_stack.append(undo_stack.pop_back())
	_restore_snapshot(undo_stack.back())
	_show_toast("Undo")

func do_redo() -> void:
	if redo_stack.is_empty(): return
	var s: Dictionary = redo_stack.pop_back()
	undo_stack.append(s)
	_restore_snapshot(s)
	_show_toast("Redo")

# ----------------------------------------------------------------------------
# Camera, 3D/2D Blueprint Flip, Click-Drag Building, 3D Arrows & F5 Playtest
# ----------------------------------------------------------------------------
func _apply_editor_camera() -> void:
	if is_2d_ortho:
		ed_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		ed_cam.size = ortho_size
		ed_cam.position = Vector3(cam_pos.x, 80.0, cam_pos.z)
		ed_cam.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	else:
		ed_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		ed_cam.fov = 60.0
		ed_cam.position = cam_pos
		ed_cam.rotation = Vector3(cam_pitch, cam_yaw, 0.0)

func toggle_2d_blueprint() -> void:
	if not is_2d_ortho:
		saved_3d_pos = cam_pos
		saved_3d_yaw = cam_yaw
		saved_3d_pitch = cam_pitch
		cam_pos = Vector3(0.0, 80.0, 0.0)
		is_2d_ortho = true
	else:
		cam_pos = saved_3d_pos
		cam_yaw = saved_3d_yaw
		cam_pitch = saved_3d_pitch
		is_2d_ortho = false
	_apply_editor_camera()
	_refresh_hud()

func toggle_playtest() -> void:
	if not player.active:
		var spawn := Vector3(-18.0, 0.25, 0.0)
		for st in stamps:
			if st["kind"] == "RED":
				spawn = st["pos"] + Vector3(0, 0.25, 0)
				break
		handles_root.visible = false
		drag_preview.visible = false
		hud_layer.get_node("EditorHud").visible = false
		vp_overlay.visible = false
		playtest_hud.visible = true
		player.enter_playtest(spawn, -PI * 0.5)
	else:
		player.exit_playtest()
		ed_cam.current = true
		hud_layer.get_node("EditorHud").visible = true
		vp_overlay.visible = true
		playtest_hud.visible = false
		handles_root.visible = (selected_idx >= 0)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_F5:
			toggle_playtest()
			return
		if player.active:
			if event.keycode == KEY_ESCAPE:
				toggle_playtest()
			return
		if event.keycode == KEY_SPACE:
			toggle_2d_blueprint()
			return
		if event.ctrl_pressed and event.keycode == KEY_Z:
			do_undo(); return
		if event.ctrl_pressed and event.keycode == KEY_Y:
			do_redo(); return
		if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			_delete_selected(); return
		if event.keycode == KEY_ESCAPE:
			active_tool = "Select"
			paint_dragging = false
			drag_preview.visible = false
			float_dim_lbl.visible = false
			_refresh_hud()
			return

	if player.active:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			rmb_down = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if is_2d_ortho: ortho_size = max(14.0, ortho_size * 0.88)
			else: cam_pos += -ed_cam.global_transform.basis.z * 2.5
			_apply_editor_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if is_2d_ortho: ortho_size = min(140.0, ortho_size * 1.12)
			else: cam_pos -= -ed_cam.global_transform.basis.z * 2.5
			_apply_editor_camera()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed: _on_viewport_left_down(mb.position)
			else: _on_viewport_left_up()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if rmb_down:
			if is_2d_ortho:
				cam_pos.x -= mm.relative.x * (ortho_size / 900.0)
				cam_pos.z -= mm.relative.y * (ortho_size / 900.0)
			else:
				cam_yaw -= mm.relative.x * 0.0045
				cam_pitch = clamp(cam_pitch - mm.relative.y * 0.0045, -1.42, 1.42)
			_apply_editor_camera()
		elif arrow_dragging:
			_update_arrow_drag(mm.position)
		elif paint_dragging:
			_update_paint_drag(mm.position)

func _ray_ground(mp: Vector2) -> Variant:
	var ro := ed_cam.project_ray_origin(mp)
	var rd := ed_cam.project_ray_normal(mp)
	if abs(rd.y) < 0.0001: return null
	var t := -ro.y / rd.y
	if t <= 0.0 or t > 400.0: return null
	var p := ro + rd * t
	return Vector3(snappedf(p.x, GRID_M), 0.0, snappedf(p.z, GRID_M))

func _hit_arrow_handle(mp: Vector2) -> int:
	if not handles_root.visible: return -1
	var best := -1
	var best_d := 34.0
	for i in range(arrow_meshes.size()):
		var n: Node3D = arrow_meshes[i]["node"]
		var tip := n.global_transform * Vector3(0, float(arrow_meshes[i]["len"]), 0)
		if ed_cam.is_position_behind(tip): continue
		var sp := ed_cam.unproject_position(tip)
		var d := sp.distance_to(mp)
		if d < best_d:
			best_d = d; best = i
	return best

func _on_viewport_left_down(mp: Vector2) -> void:
	var hi := _hit_arrow_handle(mp)
	if hi >= 0 and selected_idx >= 0:
		arrow_dragging = true
		arrow_axis = arrow_meshes[hi]["axis"]
		arrow_face_sign = arrow_meshes[hi]["sign"]
		arrow_start_pos = blocks[selected_idx]["pos"]
		arrow_start_size = blocks[selected_idx]["size"]
		arrow_drag_origin = (arrow_meshes[hi]["node"] as Node3D).global_position
		return

	if active_tool == "Floor" or active_tool == "Wall":
		var g = _ray_ground(mp)
		if g != null:
			paint_dragging = true
			paint_start = g
			paint_end = g
			_update_paint_drag(mp)
		return

	if active_tool != "Select" and active_tool != "Pull":
		var g = _ray_ground(mp)
		if g != null:
			_place_kit_at(active_tool, g)
		return

	var ro := ed_cam.project_ray_origin(mp)
	var rd := ed_cam.project_ray_normal(mp)
	var q := PhysicsRayQueryParameters3D.create(ro, ro + rd * 300.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit["collider"].has_meta("block_idx"):
		select_block(int(hit["collider"].get_meta("block_idx")))
	else:
		select_block(-1)

func _place_kit_at(tool_name: String, g: Vector3) -> void:
	match tool_name:
		"Room":
			add_block(g + Vector3(0, 2.5, -5.0), Vector3(10.0, 5.0, 0.75), "wall", false)
			add_block(g + Vector3(0, 2.5,  5.0), Vector3(10.0, 5.0, 0.75), "wall", false)
			add_block(g + Vector3(-5.0, 2.5, 0), Vector3(0.75, 5.0, 10.0), "wall", false)
			add_block(g + Vector3( 5.0, 2.5, 0), Vector3(0.75, 5.0, 10.0), "wall", false)
			_push_undo("Place Room")
		"Door":
			# TF2 Doorway Arch (112u tall clear opening!)
			add_block(g + Vector3(-2.5, 2.5, 0), Vector3(2.0, 5.0, 0.75), "wall", false)
			add_block(g + Vector3( 2.5, 2.5, 0), Vector3(2.0, 5.0, 0.75), "wall", false)
			add_block(g + Vector3( 0.0, 4.25, 0), Vector3(3.0, 1.5, 0.75), "wall", false)
			_push_undo("Place Doorway")
		"Stairs":
			# 6 walkable 16u TF2 steps (total height 96u = 3.0m)
			for s in range(6):
				var sh := (s + 1) * 0.5
				add_block(g + Vector3(0, sh * 0.5, -2.5 + s * 1.0), Vector3(4.0, sh, 1.0), "roof", false)
			_push_undo("Place Stairs")
		"Ramp":
			# Smooth 8-step low-rise walkable TF2 ramp
			for s in range(8):
				var sh := (s + 1) * 0.35
				add_block(g + Vector3(0, sh * 0.5, -3.5 + s * 1.0), Vector3(4.0, sh, 1.0), "roof", false)
			_push_undo("Place Ramp")
		"Seal":
			_show_toast("Map is auto-sealed with leak-free skybox on export!")
		"Wire":
			_show_toast("Logic Wiring: click two gameplay entities to link")
		_:
			add_stamp(g, tool_name, true)
			if symmetry_x and abs(g.x) > 1.0:
				var mk := "BLU" if tool_name == "RED" else ("RED" if tool_name == "BLU" else tool_name)
				add_stamp(Vector3(-g.x, g.y, g.z), mk, false)

func _update_arrow_drag(mp: Vector2) -> void:
	var ro := ed_cam.project_ray_origin(mp)
	var rd := ed_cam.project_ray_normal(mp)
	var ax := arrow_axis * arrow_face_sign
	var w0 := ro - arrow_drag_origin
	var b := ax.dot(rd)
	var d := ax.dot(w0)
	var e := rd.dot(w0)
	var denom := 1.0 - b * b
	if abs(denom) < 0.0001: return
	var snapped := snappedf((b * e - d) / denom, 1.0)
	var blk: Dictionary = blocks[selected_idx]
	var ns := arrow_start_size
	var np := arrow_start_pos
	if arrow_axis == Vector3.UP:
		var nh: float = max(0.5, ns.y + snapped)
		var diff: float = nh - ns.y
		ns.y = nh; np.y += diff * 0.5
	elif arrow_axis == Vector3.RIGHT:
		var nw: float = max(1.0, ns.x + snapped)
		var diff: float = nw - ns.x
		ns.x = nw; np.x += diff * 0.5 * arrow_face_sign
	elif arrow_axis == Vector3.BACK:
		var nl: float = max(1.0, ns.z + snapped)
		var diff: float = nl - ns.z
		ns.z = nl; np.z += diff * 0.5 * arrow_face_sign
	blk["pos"] = np; blk["size"] = ns
	_update_block_geom(selected_idx)

func _update_paint_drag(mp: Vector2) -> void:
	var g = _ray_ground(mp)
	if g == null: return
	paint_end = g
	var mn := paint_start.min(paint_end)
	var mx := paint_start.max(paint_end)
	var sx: float = max(GRID_M, mx.x - mn.x)
	var sz: float = max(GRID_M, mx.z - mn.z)
	var sy: float = 0.5 if active_tool == "Floor" else 4.0
	var cy: float = -0.25 if active_tool == "Floor" else 2.0
	drag_preview.position = Vector3((mn.x + mx.x) * 0.5, cy, (mn.z + mx.z) * 0.5)
	(drag_preview.mesh as BoxMesh).size = Vector3(sx, sy, sz)
	drag_preview.visible = true
	float_dim_lbl.text = "%s: %.0f x %.0fu · H: %.0fu" % [active_tool, sx * UPM, sz * UPM, sy * UPM]
	float_dim_lbl.position = mp + Vector2(16, -24)
	float_dim_lbl.visible = true

func _on_viewport_left_up() -> void:
	if arrow_dragging:
		arrow_dragging = false
		_push_undo("Pull face")
	if paint_dragging:
		paint_dragging = false
		drag_preview.visible = false
		float_dim_lbl.visible = false
		var sz := (drag_preview.mesh as BoxMesh).size
		var p := drag_preview.position
		var role := "floor" if active_tool == "Floor" else "wall"
		var idx := add_block(p, sz, role, false)
		if symmetry_x and abs(p.x) > 1.0:
			add_block(Vector3(-p.x, p.y, p.z), sz, role, false)
		_push_undo("Paint " + active_tool)
		select_block(idx)

func _process(delta: float) -> void:
	if vp_overlay != null and vp_overlay.visible:
		vp_overlay.queue_redraw()

	if auto_shot_path != "":
		auto_shot_frames += 1
		if auto_shot_frames == 12:
			var img := get_viewport().get_texture().get_image()
			img.save_png(auto_shot_path)
			get_tree().quit()
			return

	if toast_timer > 0.0:
		toast_timer -= delta
		if toast_timer <= 0.0 and toast_lbl != null:
			toast_lbl.visible = false

	if player.active:
		playtest_lbl.text = "TF2 WALK PLAYTEST  |  %s  |  WASD Move · Space Jump · Ctrl Crouch · 1/2/3 Class · F5 / Esc Exit" % Tf2PlayerScript.CLASS_NAMES[player.class_idx]
		return

	if rmb_down and not is_2d_ortho:
		var spd := 22.0 * (2.5 if Input.is_key_pressed(KEY_SHIFT) else 1.0) * delta
		var b := ed_cam.global_transform.basis
		if Input.is_key_pressed(KEY_W): cam_pos -= b.z * spd
		if Input.is_key_pressed(KEY_S): cam_pos += b.z * spd
		if Input.is_key_pressed(KEY_A): cam_pos -= b.x * spd
		if Input.is_key_pressed(KEY_D): cam_pos += b.x * spd
		if Input.is_key_pressed(KEY_E): cam_pos.y += spd
		if Input.is_key_pressed(KEY_Q): cam_pos.y -= spd
		_apply_editor_camera()

# Crisp 2D viewport overlays: Cyan H: 144u arrow badge + TF2 83u Heavy scale silhouette!
func draw_viewport_2d_overlay(c: Control) -> void:
	if player.active: return
	# 1. Floating H: XXXu badge right beside the glowing 3D Cyan Height Arrow
	if handles_root.visible and selected_idx >= 0 and selected_idx < blocks.size():
		var blk: Dictionary = blocks[selected_idx]
		var top_arrow: Node3D = arrow_meshes[0]["node"]
		var tip_w := top_arrow.global_transform * Vector3(0, float(arrow_meshes[0]["len"]) + 0.55, 0)
		if not ed_cam.is_position_behind(tip_w):
			var sp := ed_cam.unproject_position(tip_w)
			var txt := "H: %.0fu" % (float(blk["size"].y) * UPM)
			var tsz := font_ui.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			var rect := Rect2(sp + Vector2(10, -12), Vector2(tsz.x + 14, 22))
			c.draw_rect(rect, Color(0.08, 0.075, 0.07, 0.90), true)
			c.draw_rect(rect, COL_CYAN, false, 1.4)
			c.draw_string(font_ui, rect.position + Vector2(7, 15), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#e0faff"))

	# 2. Authentic Build A TF2 83u Scale Ghost Silhouette + 48u crouch-jump / 72u double-jump ticks
	if show_ghost and not is_2d_ortho:
		var foot := ghost_world_pos
		var head := foot + Vector3(0, 83.0 / UPM, 0)
		if not ed_cam.is_position_behind(foot) and not ed_cam.is_position_behind(head):
			var sf := ed_cam.unproject_position(foot)
			var sh := ed_cam.unproject_position(head)
			var ph: float = abs(sf.y - sh.y)
			if ph > 24.0 and ph < 500.0:
				var cx := sf.x
				var head_r := ph * 0.11
				var head_c := Vector2(cx, sh.y + head_r)
				var torso_t := sh.y + head_r * 2.2
				var torso_b := sh.y + ph * 0.68
				var tw := ph * 0.24
				c.draw_arc(head_c, head_r, 0, TAU, 20, COL_CYAN, 1.8, true)
				var trect := Rect2(Vector2(cx - tw, torso_t), Vector2(tw * 2.0, torso_b - torso_t))
				c.draw_rect(trect, Color(0.0, 0.85, 1.0, 0.22), true)
				c.draw_rect(trect, COL_CYAN, false, 1.6)
				c.draw_line(Vector2(cx - tw * 0.45, torso_b), Vector2(cx - tw * 0.55, sf.y), COL_CYAN, 1.8, true)
				c.draw_line(Vector2(cx + tw * 0.45, torso_b), Vector2(cx + tw * 0.55, sf.y), COL_CYAN, 1.8, true)
				c.draw_string(font_ui, Vector2(cx - 22, sh.y - 6), "TF2 83u", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_CYAN)
				# 48u crouch-jump + 72u double-jump height markers
				var y48 := sf.y - ph * (48.0 / 83.0)
				var y72 := sf.y - ph * (72.0 / 83.0)
				c.draw_line(Vector2(cx + tw + 4, y48), Vector2(cx + tw + 16, y48), COL_CYAN, 1.5)
				c.draw_string(font_ui, Vector2(cx + tw + 20, y48 + 4), "48u crouch-jump", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_CYAN)
				c.draw_line(Vector2(cx + tw + 4, y72), Vector2(cx + tw + 16, y72), COL_ACC, 1.5)
				c.draw_string(font_ui, Vector2(cx + tw + 20, y72 + 4), "72u double-jump", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_ACC)

# ----------------------------------------------------------------------------
# Exact 1:1 Build A Valve TF2 In-Game HUD
# ----------------------------------------------------------------------------
func _flat_btn(txt: String, bg: Color, fg: Color, fnt: Font, fsz := 15, min_sz := Vector2(0, 30), flat_idle := false) -> Button:
	var btn := Button.new()
	btn.text = txt
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = min_sz
	btn.add_theme_font_override("font", fnt)
	btn.add_theme_font_size_override("font_size", fsz)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg)
	var sn := StyleBoxFlat.new()
	sn.bg_color = Color(0, 0, 0, 0) if flat_idle else bg
	sn.set_corner_radius_all(5)
	sn.content_margin_left = 8; sn.content_margin_right = 8
	sn.content_margin_top = 3; sn.content_margin_bottom = 3
	var sh := sn.duplicate()
	sh.bg_color = bg.lightened(0.14) if not flat_idle else COL_BG3
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sh)
	return btn

func _build_hud() -> void:
	hud_layer = CanvasLayer.new()
	add_child(hud_layer)

	vp_overlay = HudW.ViewportOverlay.new(self)
	hud_layer.add_child(vp_overlay)

	var root := Control.new()
	root.name = "EditorHud"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(root)

	# 1. Sleek Top-Center Valve TF2 HUD Pill Bar (Exact Build A proportions!)
	var top_bar := HudW.HudFrame.new(COL_ACC2, 8.0, true)
	top_bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_bar.offset_top = 10
	top_bar.offset_left = -630
	top_bar.offset_right = 630
	top_bar.offset_bottom = 58
	root.add_child(top_bar)

	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 5)
	top_bar.add_child(th)

	var brand := _flat_btn("TF2", COL_ACC, COL_BG0, font_tf2_bold, 16, Vector2(74, 30))
	brand.pressed.connect(func():
		var r := brand.get_global_rect()
		tf2_menu.position = Vector2i(int(r.position.x), int(r.position.y + r.size.y + 4))
		tf2_menu.popup()
	)
	th.add_child(brand)

	tf2_menu = PopupMenu.new()
	tf2_menu.add_item("New Premade TF2 Environment...", 0)
	tf2_menu.add_item("Export Pre-Sealed .VMF Map", 1)
	tf2_menu.add_separator()
	tf2_menu.add_item("Toggle RED <-> BLU Symmetry", 2)
	tf2_menu.add_item("Toggle 83u Heavy Scale Ghost", 3)
	tf2_menu.add_item("Flip 3D / 2D Blueprint (Space)", 4)
	tf2_menu.id_pressed.connect(func(id: int):
		match id:
			0: _toggle_env_modal()
			1: _export_current_vmf()
			2: symmetry_x = not symmetry_x; _refresh_hud()
			3: show_ghost = not show_ghost; _refresh_hud()
			4: toggle_2d_blueprint()
	)
	root.add_child(tf2_menu)

	# Crisp icon-only Undo, Redo, Symmetry buttons (Font Awesome 6!)
	var ubtn := _flat_btn("\uf0e2", COL_BG2, COL_TX, font_fa, 13, Vector2(30, 30), true)
	ubtn.tooltip_text = "Undo (Ctrl+Z)"
	ubtn.pressed.connect(do_undo)
	th.add_child(ubtn)
	var rbtn := _flat_btn("\uf01e", COL_BG2, COL_TX, font_fa, 13, Vector2(30, 30), true)
	rbtn.tooltip_text = "Redo (Ctrl+Y)"
	rbtn.pressed.connect(do_redo)
	th.add_child(rbtn)
	sym_btn = _flat_btn("\uf337", COL_BG2, COL_TX, font_fa, 13, Vector2(32, 30), true)
	sym_btn.tooltip_text = "Toggle RED <-> BLU Mirror Symmetry across X=0"
	sym_btn.pressed.connect(func():
		symmetry_x = not symmetry_x
		_show_toast("RED <-> BLU Symmetry: " + ("ON" if symmetry_x else "OFF"))
		_refresh_hud()
	)
	th.add_child(sym_btn)

	var sp1 := Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(sp1)

	# 4 Clean Valve TF2 Stage Tabs
	var stage_names := ["1. BUILD", "2. GAMEPLAY", "3. STYLE", "4. PLAYTEST"]
	for i in range(4):
		var sb := _flat_btn(stage_names[i], COL_BG2, COL_TX, font_tf2_bold, 15, Vector2(122, 30))
		var idx := i
		sb.pressed.connect(func():
			stage_idx = idx
			active_tool = "Select"
			_refresh_hud()
		)
		stage_btns.append(sb)
		th.add_child(sb)

	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(sp2)

	# Right utility icons: Biomes, 83u Ghost, 3D/2D, F5 WALK, PLAY
	var env_btn := _flat_btn("\ue52f", COL_BG2, COL_TX, font_fa, 13, Vector2(32, 30), true)
	env_btn.tooltip_text = "Premade TF2 Environments (Desert, Winter, Sawmill, Spytech)"
	env_btn.pressed.connect(_toggle_env_modal)
	th.add_child(env_btn)

	ghost_btn = _flat_btn("\uf183", COL_BG2, COL_TX, font_fa, 14, Vector2(32, 30), false)
	ghost_btn.tooltip_text = "Toggle TF2 83u Heavy Scale Ghost"
	ghost_btn.pressed.connect(func():
		show_ghost = not show_ghost
		_refresh_hud()
	)
	th.add_child(ghost_btn)

	view2d_btn = _flat_btn("3D/2D", COL_BG2, COL_DIM, font_ui, 13, Vector2(54, 30), true)
	view2d_btn.tooltip_text = "Flip 3D / 2D Blueprint (Space)"
	view2d_btn.pressed.connect(toggle_2d_blueprint)
	th.add_child(view2d_btn)

	var walk_btn := _flat_btn("F5 WALK", Color("#2d6c90"), COL_TX, font_tf2_bold, 15, Vector2(106, 30))
	walk_btn.tooltip_text = "Instant 1st-person TF2 walk & double-jump playtest (no compile!)"
	walk_btn.pressed.connect(toggle_playtest)
	th.add_child(walk_btn)

	var play_btn := _flat_btn("▶  PLAY", COL_ACC, COL_BG0, font_tf2_bold, 15, Vector2(92, 30))
	play_btn.tooltip_text = "Export pre-sealed .VMF & Playtest in TF2"
	play_btn.pressed.connect(func():
		stage_idx = 3
		_refresh_hud()
		_export_current_vmf()
	)
	th.add_child(play_btn)

	# 2. Floating Right-Edge Authentic TF2 Stamp Rail (auto-sized tightly!)
	right_frame = HudW.HudFrame.new(COL_ACC2, 10.0, true)
	right_frame.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	right_frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_frame.grow_vertical = Control.GROW_DIRECTION_BOTH
	right_frame.offset_right = -12
	root.add_child(right_frame)

	right_vbox = VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 5)
	right_frame.add_child(right_vbox)

	# 3. Floating Bottom-Left TF2 Health-HUD Card (Exact Build A 356x104!)
	var bl_card := HudW.HudFrame.new(COL_ACC2, 9.0, true)
	bl_card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bl_card.offset_left = 14
	bl_card.offset_bottom = -14
	bl_card.offset_right = 376
	bl_card.offset_top = -120
	root.add_child(bl_card)

	var blh := HBoxContainer.new()
	blh.add_theme_constant_override("separation", 12)
	bl_card.add_child(blh)

	var ibox := PanelContainer.new()
	ibox.custom_minimum_size = Vector2(74, 74)
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color("#14110f")
	isb.border_color = Color("#463d34")
	isb.set_border_width_all(1)
	isb.set_corner_radius_all(7)
	ibox.add_theme_stylebox_override("panel", isb)
	blh.add_child(ibox)
	bl_icon_holder = CenterContainer.new()
	bl_icon_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	ibox.add_child(bl_icon_holder)

	var blv := VBoxContainer.new()
	blv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blv.add_theme_constant_override("separation", 4)
	blh.add_child(blv)

	bl_title = Label.new()
	bl_title.add_theme_font_override("font", font_tf2_sub)
	bl_title.add_theme_font_size_override("font_size", 16)
	bl_title.add_theme_color_override("font_color", COL_ACC)
	blv.add_child(bl_title)

	var dim_row := HBoxContainer.new()
	dim_row.add_theme_constant_override("separation", 8)
	blv.add_child(dim_row)
	bl_dims_a = Label.new()
	bl_dims_a.add_theme_font_override("font", font_ui)
	bl_dims_a.add_theme_font_size_override("font_size", 13)
	bl_dims_a.add_theme_color_override("font_color", COL_TX)
	dim_row.add_child(bl_dims_a)
	bl_dims_h = Label.new()
	bl_dims_h.add_theme_font_override("font", font_ui)
	bl_dims_h.add_theme_font_size_override("font_size", 13)
	bl_dims_h.add_theme_color_override("font_color", COL_CYAN)
	dim_row.add_child(bl_dims_h)

	bl_actions_box = HBoxContainer.new()
	bl_actions_box.add_theme_constant_override("separation", 5)
	blv.add_child(bl_actions_box)

	# 4. Floating Bottom-Center Compact TF2 Readiness Pill
	var bc_pill := HudW.HudFrame.new(COL_ACC2, 14.0, false)
	bc_pill.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bc_pill.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bc_pill.offset_bottom = -14
	bc_pill.offset_top = -44
	root.add_child(bc_pill)

	bc_status_lbl = Label.new()
	bc_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bc_status_lbl.add_theme_font_override("font", font_ui)
	bc_status_lbl.add_theme_font_size_override("font_size", 13)
	bc_status_lbl.add_theme_color_override("font_color", COL_GOOD)
	bc_pill.add_child(bc_status_lbl)

	# 5. Live Drag-Paint Dimension Pill
	float_dim_lbl = Label.new()
	float_dim_lbl.add_theme_font_override("font", font_ui)
	float_dim_lbl.add_theme_font_size_override("font_size", 13)
	float_dim_lbl.add_theme_color_override("font_color", COL_TX)
	var fdsb := StyleBoxFlat.new()
	fdsb.bg_color = Color("#181512", 0.94)
	fdsb.border_color = COL_ACC
	fdsb.set_border_width_all(1)
	fdsb.set_corner_radius_all(5)
	fdsb.content_margin_left = 8; fdsb.content_margin_right = 8
	fdsb.content_margin_top = 4; fdsb.content_margin_bottom = 4
	float_dim_lbl.add_theme_stylebox_override("normal", fdsb)
	float_dim_lbl.visible = false
	root.add_child(float_dim_lbl)

	# 6. Transient Toast (hidden on boot so sky stays 100% clean!)
	toast_lbl = Label.new()
	toast_lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_lbl.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_lbl.offset_top = 68
	toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_lbl.add_theme_font_override("font", font_ui)
	toast_lbl.add_theme_font_size_override("font_size", 13)
	toast_lbl.add_theme_color_override("font_color", COL_TX)
	toast_lbl.add_theme_stylebox_override("normal", fdsb)
	toast_lbl.visible = false
	root.add_child(toast_lbl)

	# 7. Premade Environment Starter Gallery Modal
	env_modal = HudW.HudFrame.new(COL_ACC2, 10.0, true)
	env_modal.set_anchors_preset(Control.PRESET_CENTER)
	env_modal.offset_left = -270; env_modal.offset_right = 270
	env_modal.offset_top = -195; env_modal.offset_bottom = 195
	env_modal.visible = show_env_modal
	root.add_child(env_modal)

	var ev := VBoxContainer.new()
	ev.add_theme_constant_override("separation", 7)
	env_modal.add_child(ev)
	var eh := Label.new()
	eh.text = "CHOOSE PREMADE TF2 ENVIRONMENT"
	eh.add_theme_font_override("font", font_tf2_bold)
	eh.add_theme_font_size_override("font_size", 18)
	eh.add_theme_color_override("font_color", COL_ACC)
	ev.add_child(eh)
	var esub := Label.new()
	esub.text = "Starts pre-sealed with TF2 skybox, directional shadows, and playable courtyard."
	esub.add_theme_font_override("font", font_ui)
	esub.add_theme_font_size_override("font_size", 12)
	esub.add_theme_color_override("font_color", COL_FAINT)
	ev.add_child(esub)

	for i in range(BIOMES.size()):
		ev.add_child(_make_biome_card(i, false))

	var close_btn := _flat_btn("Close", COL_BG3, COL_DIM, font_ui, 13, Vector2(90, 28))
	close_btn.pressed.connect(func(): env_modal.visible = false)
	ev.add_child(close_btn)

	# 8. Instant F5 Walk Playtest Overlay
	playtest_hud = Control.new()
	playtest_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	playtest_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	playtest_hud.visible = false
	hud_layer.add_child(playtest_hud)

	var ch_h := ColorRect.new()
	ch_h.color = Color(1, 0.96, 0.88, 0.9)
	ch_h.set_anchors_preset(Control.PRESET_CENTER)
	ch_h.offset_left = -8; ch_h.offset_right = 8; ch_h.offset_top = -1; ch_h.offset_bottom = 1
	playtest_hud.add_child(ch_h)
	var ch_v := ColorRect.new()
	ch_v.color = Color(1, 0.96, 0.88, 0.9)
	ch_v.set_anchors_preset(Control.PRESET_CENTER)
	ch_v.offset_left = -1; ch_v.offset_right = 1; ch_v.offset_top = -8; ch_v.offset_bottom = 8
	playtest_hud.add_child(ch_v)

	var ppanel := HudW.HudFrame.new(Color("#4ca0d2"), 8.0, true)
	ppanel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	ppanel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	ppanel.offset_bottom = -18; ppanel.offset_top = -54
	playtest_hud.add_child(ppanel)
	playtest_lbl = Label.new()
	playtest_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	playtest_lbl.add_theme_font_override("font", font_ui)
	playtest_lbl.add_theme_font_size_override("font_size", 14)
	playtest_lbl.add_theme_color_override("font_color", COL_TX)
	ppanel.add_child(playtest_lbl)

func _make_biome_card(i: int, in_place: bool) -> Button:
	var b: Dictionary = BIOMES[i]
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(246, 46)
	var sn := StyleBoxFlat.new()
	sn.bg_color = COL_BG2
	sn.border_color = COL_ACC if biome_idx == i else COL_BD
	sn.set_border_width_all(1)
	sn.set_corner_radius_all(6)
	sn.content_margin_left = 0; sn.content_margin_right = 8
	sn.content_margin_top = 4; sn.content_margin_bottom = 4
	var sh := sn.duplicate()
	sh.bg_color = COL_BG3
	sh.border_color = COL_ACC
	btn.add_theme_stylebox_override("normal", sn)
	btn.add_theme_stylebox_override("hover", sh)
	btn.add_theme_stylebox_override("pressed", sh)

	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.add_theme_constant_override("separation", 10)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(hb)

	# Dual biome color swatch bar on the left edge (exact Build A look!)
	var sw := VBoxContainer.new()
	sw.custom_minimum_size = Vector2(8, 0)
	sw.add_theme_constant_override("separation", 0)
	sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c1 := ColorRect.new(); c1.color = b["sw1"]; c1.size_flags_vertical = Control.SIZE_EXPAND_FILL; c1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var c2 := ColorRect.new(); c2.color = b["sw2"]; c2.size_flags_vertical = Control.SIZE_EXPAND_FILL; c2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sw.add_child(c1); sw.add_child(c2)
	hb.add_child(sw)

	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 1)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t1 := Label.new()
	t1.text = b["name"]
	t1.add_theme_font_override("font", font_tf2_sub)
	t1.add_theme_font_size_override("font_size", 14)
	t1.add_theme_color_override("font_color", COL_TX)
	var t2 := Label.new()
	t2.text = b["desc"]
	t2.add_theme_font_override("font", font_ui)
	t2.add_theme_font_size_override("font_size", 11)
	t2.add_theme_color_override("font_color", COL_FAINT)
	vb.add_child(t1); vb.add_child(t2)
	hb.add_child(vb)

	var bi := i
	btn.pressed.connect(func():
		if in_place: apply_biome_theme_in_place(bi)
		else: load_biome(bi, true)
	)
	return btn

func _toggle_env_modal() -> void:
	env_modal.visible = not env_modal.visible

func _show_toast(msg: String) -> void:
	if toast_lbl == null: return
	toast_lbl.text = msg
	toast_lbl.visible = true
	toast_timer = 3.0

func _refresh_hud() -> void:
	if stage_btns.is_empty(): return

	# Top stage stepper highlight (exact Build A colors)
	for i in range(4):
		var on := (stage_idx == i)
		var done := (i < stage_idx)
		var bg := COL_ACC if on else (Color("#273b29") if done else COL_BG2)
		var fg := COL_BG0 if on else (COL_GOOD if done else COL_TX)
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(5)
		sb.content_margin_left = 8; sb.content_margin_right = 8
		sb.content_margin_top = 3; sb.content_margin_bottom = 3
		stage_btns[i].add_theme_stylebox_override("normal", sb)
		stage_btns[i].add_theme_color_override("font_color", fg)

	# Utility button active highlights
	var sym_sb := StyleBoxFlat.new()
	sym_sb.bg_color = COL_ACC if symmetry_x else Color(0, 0, 0, 0)
	sym_sb.set_corner_radius_all(5)
	sym_btn.add_theme_stylebox_override("normal", sym_sb)
	sym_btn.add_theme_color_override("font_color", COL_BG0 if symmetry_x else COL_TX)

	var gh_sb := StyleBoxFlat.new()
	gh_sb.bg_color = Color("#4a3622") if show_ghost else Color(0, 0, 0, 0)
	gh_sb.set_corner_radius_all(5)
	ghost_btn.add_theme_stylebox_override("normal", gh_sb)
	ghost_btn.add_theme_color_override("font_color", COL_ACC if show_ghost else COL_DIM)

	view2d_btn.text = "2D" if is_2d_ortho else "3D/2D"
	view2d_btn.add_theme_color_override("font_color", COL_ACC if is_2d_ortho else COL_DIM)

	# Rebuild Right-Edge TF2 Stamp Rail / Stage Drawer
	for ch in right_vbox.get_children():
		ch.queue_free()

	if stage_idx == 0:
		right_frame.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		right_frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		right_frame.grow_vertical = Control.GROW_DIRECTION_BOTH
		right_frame.offset_right = -12; right_frame.offset_left = -96
		right_frame.offset_top = 0; right_frame.offset_bottom = 0
		var b_slots := [
			["Floor", "Floor", false], ["Wall", "Wall", false], ["Room", "Room", false],
			["Door", "Door", false], ["Ramp", "Ramp", false], ["Stairs", "Stairs", false],
			["Seal", "Seal", false], ["Pull", "Pull", true],
		]
		for sl in b_slots:
			var sid: String = sl[0]
			var active := (active_tool == sid) or (sid == "Pull" and active_tool == "Select")
			var slot := HudW.RailSlot.new(sid, sl[1], null, active, 0, sl[2], sid, font_ui)
			slot.pressed.connect(func():
				active_tool = "Select" if sid == "Pull" else sid
				if sid == "Seal": _place_kit_at("Seal", Vector3.ZERO)
				elif sid in ["Floor", "Wall"]: _show_toast("Drag on ground in 3D to paint %s!" % sid)
				else: _show_toast("Click in 3D to place %s" % sid)
				_refresh_hud()
			)
			right_vbox.add_child(slot)

	elif stage_idx == 1:
		right_frame.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
		right_frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		right_frame.grow_vertical = Control.GROW_DIRECTION_BOTH
		right_frame.offset_right = -12; right_frame.offset_left = -96
		right_frame.offset_top = 0; right_frame.offset_bottom = 0
		var g_slots := [
			["RED", "RED", "", 1, false],
			["BLU", "BLU", "", 2, false],
			["Health", "Health", "health.png", 0, false],
			["Ammo", "Ammo", "ammo.png", 0, false],
			["Locker", "Locker", "locker.png", 0, false],
			["Point", "Point", "point.png", 0, false],
			["Intel", "Intel", "intel.png", 0, false],
			["Cart", "Cart", "cart.png", 0, false],
			["Wire", "Wire", "", 0, true],
		]
		for sl in g_slots:
			var gid: String = sl[0]
			var tex: Texture2D = icon_cache.get(sl[2], null) if sl[2] != "" else null
			var slot := HudW.RailSlot.new(gid, sl[1], tex, active_tool == gid, sl[3], sl[4], gid, font_ui)
			slot.pressed.connect(func():
				active_tool = gid
				_show_toast("Click anywhere in 3D to drop " + gid)
				_refresh_hud()
			)
			right_vbox.add_child(slot)

	elif stage_idx == 2:
		right_frame.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		right_frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		right_frame.grow_vertical = Control.GROW_DIRECTION_END
		right_frame.offset_right = -14; right_frame.offset_top = 72
		right_frame.offset_left = -310; right_frame.offset_bottom = 0
		var hdr := Label.new()
		hdr.text = "3. TF2 THEME & ASSETS"
		hdr.add_theme_font_override("font", font_tf2_sub)
		hdr.add_theme_font_size_override("font_size", 14)
		hdr.add_theme_color_override("font_color", COL_DIM)
		right_vbox.add_child(hdr)

		var sub_lbl := Label.new()
		sub_lbl.text = "1-Click TF2 Theme Styler"
		sub_lbl.add_theme_font_override("font", font_ui)
		sub_lbl.add_theme_font_size_override("font_size", 13)
		sub_lbl.add_theme_color_override("font_color", COL_TX)
		right_vbox.add_child(sub_lbl)

		for i in range(4):
			right_vbox.add_child(_make_biome_card(i, true))
		var new_env := _flat_btn("New Premade Environment...", COL_BG2, COL_TX, font_ui, 13, Vector2(246, 32))
		new_env.pressed.connect(_toggle_env_modal)
		right_vbox.add_child(new_env)

	else:
		right_frame.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		right_frame.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		right_frame.grow_vertical = Control.GROW_DIRECTION_END
		right_frame.offset_right = -14; right_frame.offset_top = 72
		right_frame.offset_left = -310; right_frame.offset_bottom = 0
		var hdr := Label.new()
		hdr.text = "4. PLAYTEST & SHIP TO TF2"
		hdr.add_theme_font_override("font", font_tf2_sub)
		hdr.add_theme_font_size_override("font_size", 14)
		hdr.add_theme_color_override("font_color", COL_DIM)
		right_vbox.add_child(hdr)

		var n_r := 0; var n_b := 0; var n_o := 0
		for st in stamps:
			if st["kind"] == "RED": n_r += 1
			elif st["kind"] == "BLU": n_b += 1
			elif st["kind"] in ["Point", "Intel", "Cart"]: n_o += 1
		var checks := [
			[n_r > 0, "RED Spawns (%d)" % n_r],
			[n_b > 0, "BLU Spawns (%d)" % n_b],
			[n_o > 0, "Objective (CP/Intel/Cart)"],
			[true,    "Skybox Auto-Sealed (0 Leaks)"],
			[true,    "TF2 Sunlight & Skybox"],
		]
		for ch in checks:
			var l := Label.new()
			l.text = ("✓  " if ch[0] else "✕  ") + ch[1]
			l.add_theme_font_override("font", font_ui)
			l.add_theme_font_size_override("font_size", 13)
			l.add_theme_color_override("font_color", COL_GOOD if ch[0] else COL_ACC)
			right_vbox.add_child(l)

		var f5b := _flat_btn("F5  Instant Walk Playtest", Color("#2d6c90"), COL_TX, font_tf2_bold, 15, Vector2(246, 36))
		f5b.pressed.connect(toggle_playtest)
		right_vbox.add_child(f5b)

		var exb := _flat_btn("▶  Export .VMF for TF2", COL_ACC, COL_BG0, font_tf2_bold, 15, Vector2(246, 38))
		exb.pressed.connect(_export_current_vmf)
		right_vbox.add_child(exb)

	# Bottom-Left TF2 Health-HUD Card (Exact Build A layout!)
	for ch in bl_icon_holder.get_children(): ch.queue_free()
	for ch in bl_actions_box.get_children(): ch.queue_free()

	var ikey := active_tool.to_lower() + ".png"
	if icon_cache.has(ikey) and selected_idx < 0:
		var tr := TextureRect.new()
		tr.texture = icon_cache[ikey]
		tr.custom_minimum_size = Vector2(58, 58)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		bl_icon_holder.add_child(tr)
	else:
		var piece_vis := active_tool if active_tool in ["Floor", "Wall", "Room", "Door", "Ramp", "Stairs"] else "Floor"
		var iso := HudW.IsoIconCanvas.new(piece_vis, true, 0, false, "")
		iso.custom_minimum_size = Vector2(62, 62)
		bl_icon_holder.add_child(iso)

	if selected_idx >= 0 and selected_idx < blocks.size():
		var sb: Dictionary = blocks[selected_idx]
		var sz: Vector3 = sb["size"] * UPM
		bl_title.text = "SELECTED BRUSH (1)"
		bl_dims_a.text = "%.0f x %.0fu" % [sz.x, sz.z]
		bl_dims_h.text = "H: %.0fu" % sz.y
		var b_up := _flat_btn("▲ +48u", COL_BG2, COL_TX, font_ui, 12, Vector2(60, 26))
		b_up.pressed.connect(func(): _resize_selected_height(48.0))
		var b_dn := _flat_btn("▼ -48u", COL_BG2, COL_TX, font_ui, 12, Vector2(60, 26))
		b_dn.pressed.connect(func(): _resize_selected_height(-48.0))
		var b_gr := _flat_btn("Grow", COL_BG2, COL_TX, font_ui, 12, Vector2(52, 26))
		b_gr.pressed.connect(func(): _resize_selected_footprint(64.0))
		var b_dl := _flat_btn("\uf1f8", COL_BG2, COL_TX, font_fa, 12, Vector2(30, 26))
		b_dl.pressed.connect(_delete_selected)
		bl_actions_box.add_child(b_up); bl_actions_box.add_child(b_dn)
		bl_actions_box.add_child(b_gr); bl_actions_box.add_child(b_dl)
	else:
		var hdrs := ["TF2 BUILD KIT", "TF2 GAMEPLAY", "TF2 STYLE & BIOME", "TF2 PLAYTEST"]
		var subs := ["Pick a piece on the right rail", "Stamp spawns, kits & objectives",
					 "Paint a theme or pick a biome", "Verify readiness & launch TF2"]
		bl_title.text = hdrs[stage_idx]
		bl_dims_a.text = subs[stage_idx]
		bl_dims_h.text = ""
		var bg := _flat_btn("Grid 64u", COL_BG2, COL_TX, font_ui, 12, Vector2(66, 26))
		bl_actions_box.add_child(bg)
		if stage_idx == 2:
			var be := _flat_btn("Environments", COL_BG2, COL_TX, font_ui, 12, Vector2(96, 26))
			be.pressed.connect(_toggle_env_modal)
			bl_actions_box.add_child(be)
		else:
			var bp := _flat_btn("Paint Floor", COL_BG2, COL_TX, font_ui, 12, Vector2(82, 26))
			bp.pressed.connect(func(): active_tool = "Floor"; stage_idx = 0; _refresh_hud())
			bl_actions_box.add_child(bp)

	# Bottom-Center Readiness Pill (exact Build A format!)
	var n_red := 0; var n_blu := 0; var n_obj := 0
	for st in stamps:
		if st["kind"] == "RED": n_red += 1
		elif st["kind"] == "BLU": n_blu += 1
		elif st["kind"] in ["Point", "Intel", "Cart"]: n_obj += 1
	bc_status_lbl.text = "RED %s (%d)   |   Obj %s (%d)   |   BLU %s (%d)   |   ✓ Sealed   |   Grid 64u" % [
		"✓" if n_red > 0 else "✕", n_red,
		"✓" if n_obj > 0 else "✕", n_obj,
		"✓" if n_blu > 0 else "✕", n_blu,
	]

func _export_current_vmf() -> void:
	var b: Dictionary = BIOMES[biome_idx]
	var out_path := ProjectSettings.globalize_path("res://exported_%s.vmf" % b["map"])
	if VmfExporterScript.export_vmf(out_path, b["map"], b["sky"], blocks, stamps):
		_show_toast("Exported leak-free TF2 map: exported_%s.vmf" % b["map"])
	else:
		_show_toast("Failed to export .vmf")
