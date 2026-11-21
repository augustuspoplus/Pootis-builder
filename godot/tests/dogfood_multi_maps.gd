extends Node3D

## Milestone 28 — Multi-Map End-to-End Dogfooding & Real Valve Compile Verification!
## Builds 3 full playable TF2 maps from scratch using Pootis Builder 2.0's native APIs:
##   1. pl_upward_rebuilt.vmf  (Cliffside Payload Canyon + 10-Node Track Spline + Sliding Doors)
##   2. mvm_ironworks.vmf      (Mann vs. Machine Valley + Robot Spawns + Tank Path + Bomb Hatch + .POP Mission)
##   3. koth_snowpeak.vmf      (Winter Snow KOTH Arena + Snowy Pines + Symmetrical RED/BLU Lodges)
## Compiles ALL 3 through real Valve vbsp + vvis + vrad (0 leaks!) and renders GPU verification shots!

const Tf2AssetsScript    = preload("res://scripts/core/Tf2Assets.gd")
const Tf2BspLoaderScript = preload("res://scripts/core/Tf2BspLoader.gd")

const REPO_ROOT := "C:/Users/steph/Documents/Git/pootis builder"
const ART       := "C:/Users/steph/.gemini/antigravity/brain/dc036b95-0d4c-4a2b-8b8a-c124bec47848"

var _core: Object
var _assets: RefCounted
var _loader: RefCounted
var _bsp_root: Node3D
var _we: WorldEnvironment
var _cam: Camera3D
var _queue: Array = []
var _qidx: int = 0
var _frames: int = 0

func _ready() -> void:
	print("=== Milestone 28: Multi-Map Dogfooding (Upward + MvM Ironworks + KOTH Snowpeak) ===")
	_core = ClassDB.instantiate("Tf2Core")
	_core.mount_tf2(REPO_ROOT)
	_assets = Tf2AssetsScript.new(_core)
	_loader = Tf2BspLoaderScript.new(_core, _assets)

	DirAccess.make_dir_recursive_absolute(REPO_ROOT + "/godot/maps")
	var compiler = ClassDB.instantiate("Tf2Compiler")
	var paths: Dictionary = compiler.detect_paths()
	var game_maps: String = str(paths["game_dir"]).path_join("maps")

	var specs := [
		{
			"name": "pl_upward_rebuilt", "sky": "sky_badlands_01",
			"builder": _build_upward,
			"cam_pos": Vector3(-24.0, 14.0, 22.0), "cam_tgt": Vector3(2.0, 3.0, -4.0),
			"out": ART + "/v9_upward_rebuilt_compiled.png",
		},
		{
			"name": "mvm_ironworks", "sky": "sky_dustbowl_01_hdr",
			"builder": _build_mvm_ironworks,
			"cam_pos": Vector3(-20.0, 13.0, 20.0), "cam_tgt": Vector3(2.0, 2.0, -2.0),
			"out": ART + "/v9_mvm_ironworks_compiled.png",
		},
		{
			"name": "koth_snowpeak", "sky": "sky_viaduct_01",
			"builder": _build_koth_snowpeak,
			"cam_pos": Vector3(-12.0, 10.0, 12.0), "cam_tgt": Vector3(2.0, 1.5, -2.0),
			"out": ART + "/v9_koth_snowpeak_compiled.png",
		},
	]

	for sp in specs:
		var mname: String = str(sp["name"])
		var doc = ClassDB.instantiate("Tf2MapDoc")
		(sp["builder"] as Callable).call(doc)
		var vmf_path := REPO_ROOT + "/godot/maps/" + mname + ".vmf"
		var sv: Dictionary = doc.save_vmf(vmf_path)
		print("  Saved %s.vmf: ok=%s solids=%d ents=%d" % [
			mname, str(sv.get("ok", false)), doc.get_solid_count(), doc.get_entity_count()
		])
		compiler.start_compile(vmf_path, true, true, true, false, mname)
		var t0 := Time.get_ticks_msec()
		var st: Dictionary = {}
		while (Time.get_ticks_msec() - t0) < 90000:
			OS.delay_msec(100)
			st = compiler.poll()
			if st.get("finished", false):
				break
		print("  Valve Compile [%s]: succeeded=%s stage=%s leak='%s' elapsed=%.2fs" % [
			mname, str(st.get("succeeded", false)), str(st.get("stage", "")),
			str(st.get("leak_file", "")), float(st.get("elapsed", 0.0))
		])
		if not st.get("succeeded", false):
			var logs: PackedStringArray = st.get("log", PackedStringArray())
			for i in range(max(0, logs.size() - 15), logs.size()):
				print("    [compile] " + logs[i])
			get_tree().quit(1)
			return
		_queue.append({
			"bsp": game_maps.path_join(mname + ".bsp"),
			"sky": sp["sky"], "cam_pos": sp["cam_pos"], "cam_tgt": sp["cam_tgt"], "out": sp["out"],
		})

	_bsp_root = Node3D.new(); add_child(_bsp_root)
	_we = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_we.environment = env; add_child(_we)
	var sun := DirectionalLight3D.new(); sun.light_energy = 1.3; sun.rotation_degrees = Vector3(-42, 35, 0); add_child(sun)
	_cam = Camera3D.new(); _cam.fov = 75.0; _cam.far = 750.0; add_child(_cam)
	_load_next(0)

func _load_next(idx: int) -> void:
	for ch in _bsp_root.get_children(): ch.queue_free()
	var it: Dictionary = _queue[idx]
	_we.environment.sky = _assets.get_sky(str(it["sky"]))
	var res: Dictionary = _loader.load_bsp_into(str(it["bsp"]), _bsp_root)
	print("  Rendered %s: ok=%s surfs=%d props=%d doors=%d" % [
		str(it["bsp"]).get_file(), str(res.get("ok", false)),
		int(res.get("surface_count", 0)), int(res.get("prop_count", 0)), int(res.get("door_count", 0))
	])
	_cam.look_at_from_position(it["cam_pos"], it["cam_tgt"], Vector3.UP)
	_frames = 0

func _process(_delta: float) -> void:
	if _queue.is_empty(): return
	_frames += 1
	if _frames == 10:
		var it: Dictionary = _queue[_qidx]
		get_viewport().get_texture().get_image().save_png(str(it["out"]))
		print("  Saved: " + str(it["out"]))
		_qidx += 1
		if _qidx >= _queue.size():
			print("=== MILESTONE 28 MULTI-MAP DOGFOODING PASSED (0 ERRORS) ===")
			get_tree().quit(0)
		else:
			_load_next(_qidx)

# ==============================================================================
# MAP 1: PL_UPWARD_REBUILT — CLIFFSIDE PAYLOAD CANYON + CURVING TRACK + DOORS!
# ==============================================================================
func _build_upward(doc: Object) -> void:
	doc.new_map("pl_upward_rebuilt", "sky_badlands_01")
	doc.set_grid_units(16)
	var m_dirt  := "NATURE/DIRTGROUND001"
	var m_rock  := "NATURE/BLENDROCKWALLDIRT001"
	var m_wood  := "WOOD/WOOD_WALL002"
	var m_red   := "WOOD/WOOD_WALL007"
	var m_blu   := "WOOD/WOOD_WALL005A"
	var m_roof  := "METAL/METALROOF004A"
	var m_broof := "METAL/METALROOF006A"
	var m_conc  := "CONCRETE/CONCRETEFLOOR007A"
	var m_door  := "METAL/METALDOOR001"

	# Main canyon valley floor + elevated upper ridge for Point B & Final Pit!
	doc.add_box(Vector3(-36, -2, -28), Vector3(36, 0, 28), m_dirt)
	doc.add_box(Vector3(6, 0, -28), Vector3(36, 4.0, 28), m_dirt)
	doc.add_ramp(Vector3(-6, 0, -10), Vector3(6, 4.0, 10), 0, m_dirt)
	# Stratified vertical canyon cliffs framing the north & east hillside!
	doc.make_cliff_wall(Vector3(-34, 0, -26), Vector3(-10, 0, -26), 12.0, 3.0, 3, m_rock, 1.3)
	doc.make_cliff_wall(Vector3(-10, 0, -26), Vector3(14, 0, -26), 14.0, 3.0, 3, m_rock, 1.4)
	doc.make_cliff_wall(Vector3(14, 4, -26), Vector3(34, 4, -26), 11.0, 3.0, 3, m_rock, 1.2)
	doc.sew_displacements()

	# BLU Spawn Building (West valley) with sliding func_door + resupply + spawns!
	doc.add_room(Vector3(-34, 0, -10), Vector3(-22, 6, 10), 0.75, m_conc, m_blu, m_broof, false)
	doc.auto_carve_opening(Vector3(-23.5, 0, -3), Vector3(-20.5, 4.5, 3), m_blu)
	doc.add_brush_entity("func_door", Vector3(-22.4, 0, -2.8), Vector3(-21.9, 4.4, 2.8), m_door, {"targetname": "blu_setup_door", "movedir": "-90 0 0", "speed": "320"})
	doc.add_brush_entity("func_respawnroom", Vector3(-33, 0.2, -9), Vector3(-23, 5, 9), "TOOLS/TOOLSTRIGGER", {"TeamNum": "3"})
	for z: float in [-4.0, 0.0, 4.0]:
		doc.add_point_entity("info_player_teamspawn", Vector3(-28, 0.4, z), {"TeamNum": "3", "angles": "0 0 0"})
	doc.add_point_entity("prop_dynamic", Vector3(-32.5, 0, 0), {"model": "models/props_gameplay/resupply_locker.mdl", "angles": "0 0 0", "solid": "6"})

	# Iconic Upward Wooden Mine Overlook House above Checkpoint A!
	doc.add_building(Vector3(-12, 0, -22), Vector3(2, 0, -11), 2, 1, m_wood, m_conc, m_roof, 0)
	doc.add_box(Vector3(-10, 0, 11), Vector3(4, 3.5, 22), m_wood) # Southern cliffside cover shed

	# RED Final Base & Sliding Spawn Door (East ridge)
	doc.add_room(Vector3(24, 4, -10), Vector3(35, 10, 10), 0.75, m_conc, m_red, m_roof, false)
	doc.auto_carve_opening(Vector3(22.5, 4, -3), Vector3(25.5, 8.5, 3), m_red)
	doc.add_brush_entity("func_door", Vector3(23.8, 4, -2.8), Vector3(24.3, 8.4, 2.8), m_door, {"targetname": "red_spawn_door", "movedir": "-90 0 0", "speed": "320"})
	doc.add_brush_entity("func_respawnroom", Vector3(25, 4.2, -9), Vector3(34, 9, 9), "TOOLS/TOOLSTRIGGER", {"TeamNum": "2"})
	for z: float in [-4.0, 0.0, 4.0]:
		doc.add_point_entity("info_player_teamspawn", Vector3(29, 4.4, z), {"TeamNum": "2", "angles": "0 180 0"})
	doc.add_point_entity("prop_dynamic", Vector3(33.5, 4, 0), {"model": "models/props_gameplay/resupply_locker.mdl", "angles": "0 180 0", "solid": "6"})

	# 10-Node Curving Payload Track Spline climbing the hillside up to RED's Final Bomb Pit!
	var pts := [
		Vector3(-19, 0.2, 0), Vector3(-13, 0.2, 3), Vector3(-7, 0.2, 4),
		Vector3(-1, 1.8, 2),  Vector3(4, 3.6, 0),   Vector3(9, 4.2, -3),
		Vector3(14, 4.2, -5), Vector3(18, 4.2, -2), Vector3(20, 4.2, 3), Vector3(17, 4.2, 8),
	]
	for i in range(pts.size()):
		var kv := {"targetname": "pb_track_%02d" % (i + 1)}
		if i + 1 < pts.size():
			kv["target"] = "pb_track_%02d" % (i + 2)
		doc.add_point_entity("path_track", pts[i], kv)

	# Payload Cart + Checkpoints A & Final + Iconic Upward Props!
	doc.add_point_entity("prop_dynamic", pts[0], {"model": "models/props_trainyard/bomb_cart.mdl", "angles": "0 0 0", "solid": "6"})
	doc.add_point_entity("team_control_point", pts[2], {"point_default_owner": "2", "targetname": "cap_a"})
	doc.add_point_entity("prop_dynamic", pts[2], {"model": "models/props_gameplay/cap_point_base.mdl", "solid": "6"})
	doc.add_point_entity("team_control_point", pts[9], {"point_default_owner": "2", "targetname": "cap_final"})
	doc.add_point_entity("prop_dynamic", pts[9], {"model": "models/props_gameplay/cap_point_base.mdl", "solid": "6"})
	for pp in [
		{"m": "models/props_foliage/tree_pine01.mdl", "p": Vector3(-16, 0, -18)},
		{"m": "models/props_foliage/tree_pine_huge.mdl", "p": Vector3(10, 4, -18)},
		{"m": "models/props_foliage/tree_pine01.mdl", "p": Vector3(22, 4, 16)},
		{"m": "models/props_2fort/miningcrate001.mdl", "p": Vector3(-5, 0, -6)},
		{"m": "models/props_farm/wooden_barrel.mdl", "p": Vector3(-3, 0, -6)},
		{"m": "models/props_nature/rock_worn001.mdl", "p": Vector3(8, 4, 12)},
	]:
		doc.add_point_entity("prop_static", pp["p"], {"model": pp["m"], "angles": "0 30 0", "solid": "6"})
	doc.add_point_entity("item_healthkit_medium", Vector3(-6, 0.2, 10), {})
	doc.add_point_entity("item_ammopack_medium", Vector3(11, 4.2, 6), {})
	doc.add_point_entity("light_environment", Vector3(0, 22, 0), {"angles": "0 45 0", "pitch": "-42", "_light": "255 242 215 450", "_ambient": "165 182 205 190"})
	doc.auto_seal_skybox()

# ==============================================================================
# MAP 2: MVM_IRONWORKS — MANN VS. MACHINE DEFENSE VALLEY + .POP MISSION!
# ==============================================================================
func _build_mvm_ironworks(doc: Object) -> void:
	doc.new_map("mvm_ironworks", "sky_dustbowl_01_hdr")
	doc.set_grid_units(16)
	var m_floor := "CONCRETE/CONCRETEFLOOR007A"
	var m_wall  := "BRICK/BRICKWALL001"
	var m_wood  := "WOOD/WOOD_WALL007"
	var m_steel := "METAL/METALWALL001B"
	var m_roof  := "METAL/METALROOF004A"
	var m_door  := "METAL/METALDOOR001"

	doc.add_box(Vector3(-32, -2, -24), Vector3(32, 0, 24), m_floor)
	doc.add_box(Vector3(-32, 0, -24), Vector3(32, 10, -22), m_wall)
	doc.add_box(Vector3(-32, 0, 22), Vector3(32, 10, 24), m_wall)

	# Elevated BLU Robot Spawn Balcony (West) + Drop-Down Ramp!
	doc.add_box(Vector3(-32, 0, -22), Vector3(-20, 5, 22), m_steel)
	doc.add_ramp(Vector3(-20, 0, -6), Vector3(-12, 5, 6), 1, m_steel)
	doc.add_point_entity("info_player_teamspawn", Vector3(-25, 5.4, -4), {"TeamNum": "3", "targetname": "spawnbot"})
	doc.add_point_entity("info_player_teamspawn", Vector3(-25, 5.4, 4),  {"TeamNum": "3", "targetname": "spawnbot_giant"})
	doc.add_point_entity("item_teamflag", Vector3(-22, 5.4, 0), {"TeamNum": "3", "GameType": "1", "targetname": "intel"})

	# Central Industrial Cover Buildings + Flank Lanes!
	doc.add_building(Vector3(-8, 0, -18), Vector3(4, 0, -8), 1, 1, m_wall, m_steel, m_roof, 0)
	doc.add_building(Vector3(-8, 0, 8),   Vector3(4, 0, 18), 1, 1, m_wall, m_steel, m_roof, 2)

	# Tank Track Path from Robot Spawn straight to RED's Bomb Hatch!
	var tpts := [Vector3(-18, 0.3, 0), Vector3(-6, 0.3, 0), Vector3(6, 0.3, 0), Vector3(16, 0.3, 0)]
	for i in range(tpts.size()):
		var kv := {"targetname": "pb_track_%02d" % (i + 1)}
		if i + 1 < tpts.size(): kv["target"] = "pb_track_%02d" % (i + 2)
		doc.add_point_entity("path_track", tpts[i], kv)

	# MvM Bomb Hatch Pit + Capture Zone!
	doc.add_point_entity("prop_dynamic", Vector3(17, 0.05, 0), {"model": "models/props_mvm/mann_hatch.mdl", "solid": "6"})
	doc.add_brush_entity("func_capturezone", Vector3(15, 0, -2), Vector3(19, 3, 2), "TOOLS/TOOLSTRIGGER", {"TeamNum": "3"})

	# RED Defender Spawn Room + Upgrade Station + Interactive Sliding Door!
	doc.add_room(Vector3(22, 0, -10), Vector3(32, 6, 10), 0.75, m_floor, m_wood, m_roof, false)
	doc.auto_carve_opening(Vector3(20.5, 0, -3), Vector3(23.5, 4.5, 3), m_wood)
	doc.add_brush_entity("func_door", Vector3(21.8, 0, -2.8), Vector3(22.3, 4.4, 2.8), m_door, {"targetname": "red_mvm_door", "movedir": "-90 0 0", "speed": "340"})
	doc.add_brush_entity("func_respawnroom", Vector3(23, 0.2, -9), Vector3(31, 5, 9), "TOOLS/TOOLSTRIGGER", {"TeamNum": "2"})
	doc.add_point_entity("prop_dynamic", Vector3(27, 0, -7.5), {"model": "models/props_mvm/mvm_upgrade_center.mdl", "angles": "0 90 0", "solid": "6"})
	doc.add_brush_entity("func_upgradestation", Vector3(25, 0, -8.5), Vector3(29, 4, -5.5), "TOOLS/TOOLSTRIGGER", {})
	for z: float in [-3.0, 0.0, 3.0]:
		doc.add_point_entity("info_player_teamspawn", Vector3(27, 0.4, z), {"TeamNum": "2", "angles": "0 180 0"})
	doc.add_point_entity("prop_dynamic", Vector3(30.5, 0, 0), {"model": "models/props_gameplay/resupply_locker.mdl", "angles": "0 180 0", "solid": "6"})
	doc.add_point_entity("tf_logic_mann_vs_machine", Vector3(0, 8, 0), {})
	doc.add_point_entity("light_environment", Vector3(0, 18, 0), {"angles": "0 35 0", "pitch": "-45", "_light": "255 235 205 420", "_ambient": "150 165 190 180"})
	doc.auto_seal_skybox()

	# Also export matching Valve .POP wave mission file!
	var pop_f := FileAccess.open(REPO_ROOT + "/godot/maps/mvm_ironworks_normal.pop", FileAccess.WRITE)
	if pop_f != null:
		pop_f.store_string("#base robot_giant.pop\n#base robot_standard.pop\nWaveSchedule\n{\n\tStartingCurrency 800\n\tRespawnWaveTime 4\n\tWave { WaveSpawn { Where spawnbot TotalCount 16 MaxActive 6 SpawnCount 2 TotalCurrency 400 TFBot { Class Scout Skill Easy } } }\n}\n")

# ==============================================================================
# MAP 3: KOTH_SNOWPEAK — WINTER SNOW KOTH ARENA WITH CLEAN WINTER PROPS!
# ==============================================================================
func _build_koth_snowpeak(doc: Object) -> void:
	doc.new_map("koth_snowpeak", "sky_viaduct_01")
	doc.set_grid_units(16)
	var m_snow := "NATURE/SNOW_FULL001"
	var m_conc := "CONCRETE/CONCRETEFLOOR001A"
	var m_red  := "WOOD/WOOD_WALL007"
	var m_blu  := "WOOD/WOOD_WALL005A"
	var m_roof := "METAL/METALROOF004A"
	var m_broof:= "METAL/METALROOF006A"
	var m_door := "METAL/METALDOOR001"

	doc.add_box(Vector3(-28, -2, -20), Vector3(28, 0, 20), m_snow)
	doc.add_box(Vector3(-28, 0, -20), Vector3(28, 8, -18), m_conc)
	doc.add_box(Vector3(-28, 0, 18),  Vector3(28, 8, 20),  m_conc)

	# Central Elevated Stone KOTH Control Point + Dual Ramps!
	doc.add_box(Vector3(-5, 0, -5), Vector3(5, 1.5, 5), m_conc)
	doc.add_ramp(Vector3(-8, 0, -3), Vector3(-5, 1.5, 3), 0, m_snow)
	doc.add_ramp(Vector3(5, 0, -3),  Vector3(8, 1.5, 3),  1, m_snow)
	doc.add_point_entity("team_control_point", Vector3(0, 1.6, 0), {"point_default_owner": "0", "targetname": "koth_cap"})
	doc.add_point_entity("prop_dynamic", Vector3(0, 1.55, 0), {"model": "models/props_gameplay/cap_point_base.mdl", "solid": "6"})
	doc.add_brush_entity("trigger_capture_area", Vector3(-4, 1.5, -4), Vector3(4, 5.5, 4), "TOOLS/TOOLSTRIGGER", {"area_cap_point": "koth_cap"})
	doc.add_point_entity("tf_logic_koth", Vector3(0, 9, 0), {"timer_length": "180"})

	# Symmetrical RED (-X) & BLU (+X) Winter Lodges with Sliding Spawn Doors!
	for side: float in [-1.0, 1.0]:
		var is_red := (side < 0.0)
		var team := 2 if is_red else 3
		var x0 := -27.0 if is_red else 17.0
		var x1 := -17.0 if is_red else 27.0
		var dx := -17.0 if is_red else 17.0
		doc.add_room(Vector3(x0, 0, -8), Vector3(x1, 6, 8), 0.75, m_conc, m_red if is_red else m_blu, m_roof if is_red else m_broof, false)
		doc.auto_carve_opening(Vector3(dx - 1.5, 0, -2.5), Vector3(dx + 1.5, 4.2, 2.5), m_red if is_red else m_blu)
		doc.add_brush_entity("func_door", Vector3(dx - 0.25, 0, -2.4), Vector3(dx + 0.25, 4.1, 2.4), m_door, {"movedir": "-90 0 0", "speed": "340"})
		doc.add_point_entity("info_player_teamspawn", Vector3((x0 + x1) * 0.5, 0.4, -2), {"TeamNum": str(team), "angles": "0 %d 0" % (0 if is_red else 180)})
		doc.add_point_entity("info_player_teamspawn", Vector3((x0 + x1) * 0.5, 0.4, 2),  {"TeamNum": str(team), "angles": "0 %d 0" % (0 if is_red else 180)})
		doc.add_point_entity("prop_dynamic", Vector3(x0 + 1.5 if is_red else x1 - 1.5, 0, 0), {"model": "models/props_gameplay/resupply_locker.mdl", "angles": "0 %d 0" % (0 if is_red else 180), "solid": "6"})

	# Genuine Snowy Pines framed around the perimeter (clear center sightlines!)
	for sp in [Vector3(-18, 0, -15), Vector3(18, 0, -15), Vector3(-18, 0, 15), Vector3(18, 0, 15)]:
		doc.add_point_entity("prop_static", sp, {"model": "models/props_foliage/tree_pine_extrasmall_snow.mdl", "angles": "0 45 0", "solid": "6"})
	doc.add_point_entity("item_healthkit_medium", Vector3(0, 0.2, -10), {})
	doc.add_point_entity("item_ammopack_medium", Vector3(0, 0.2, 10), {})
	doc.add_point_entity("light_environment", Vector3(0, 18, 0), {"angles": "0 45 0", "pitch": "-38", "_light": "225 238 255 410", "_ambient": "165 188 215 210"})
	doc.auto_seal_skybox()
