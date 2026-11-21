extends Node3D

## Milestone 24 — Full ctf_turbine Scratch-Rebuild Dogfooding Test!
## Rebuilds Valve's ctf_turbine (Mid Hall + 3 Turbines + Floating Steel Stairs +
## Glass Vent Observation Booths + Playable Vent Ducts + Separate RED/BLU Spawn Rooms
## with Interactive Sliding func_door + 2-Level Intel Rooms + Spytech Props + Pickups),
## saves godot/maps/ctf_turbine_rebuilt.vmf, compiles with real Valve vbsp+vvis+vrad,
## and renders exact side-by-side comparison shots vs official Valve ctf_turbine.bsp!

const Tf2AssetsScript    = preload("res://scripts/core/Tf2Assets.gd")
const Tf2BspLoaderScript = preload("res://scripts/core/Tf2BspLoader.gd")

const REPO_ROOT := "C:/Users/steph/Documents/Git/pootis builder"
const ART       := "C:/Users/steph/.gemini/antigravity/brain/dc036b95-0d4c-4a2b-8b8a-c124bec47848"

const CAM_POS := Vector3(-13.5, 5.2, 11.5)
const CAM_TGT := Vector3(5.0, 1.5, -2.5)

var _core: Object
var _assets: RefCounted
var _loader: RefCounted
var _bsp_root: Node3D
var _cam: Camera3D
var _queue: Array = []
var _qidx: int = 0
var _frames: int = 0

func _ready() -> void:
	print("=== Milestone 24: Rebuilding ctf_turbine from scratch with Pootis Builder 2.0 ===")
	_core = ClassDB.instantiate("Tf2Core")
	_core.mount_tf2(REPO_ROOT)
	_assets = Tf2AssetsScript.new(_core)
	_loader = Tf2BspLoaderScript.new(_core, _assets)

	var doc = ClassDB.instantiate("Tf2MapDoc")
	_build_turbine_full(doc)
	DirAccess.make_dir_recursive_absolute(REPO_ROOT + "/godot/maps")
	var vmf_path := REPO_ROOT + "/godot/maps/ctf_turbine_rebuilt.vmf"
	var sv: Dictionary = doc.save_vmf(vmf_path)
	print("  Saved ctf_turbine_rebuilt.vmf: ok=%s solids=%d ents=%d" % [
		str(sv.get("ok", false)), doc.get_solid_count(), doc.get_entity_count()
	])

	# Compile with REAL Valve vbsp + vvis + vrad!
	var compiler = ClassDB.instantiate("Tf2Compiler")
	var paths: Dictionary = compiler.detect_paths()
	var built_bsp: String = str(paths["game_dir"]).path_join("maps/ctf_turbine_rebuilt.bsp")
	var valve_bsp: String = str(paths["game_dir"]).path_join("maps/ctf_turbine.bsp")
	compiler.start_compile(vmf_path, true, true, true, false, "ctf_turbine_rebuilt")
	var t0 := Time.get_ticks_msec()
	var st: Dictionary = {}
	while (Time.get_ticks_msec() - t0) < 90000:
		OS.delay_msec(100)
		st = compiler.poll()
		if st.get("finished", false):
			break
	print("  Valve Compile (vbsp+vvis+vrad): succeeded=%s stage=%s leak='%s' elapsed=%.2fs" % [
		str(st.get("succeeded", false)), str(st.get("stage", "")), str(st.get("leak_file", "")), float(st.get("elapsed", 0.0))
	])
	if not st.get("succeeded", false):
		var logs: PackedStringArray = st.get("log", PackedStringArray())
		for i in range(max(0, logs.size() - 20), logs.size()):
			print("    [compile] " + logs[i])
		get_tree().quit(1)
		return

	_bsp_root = Node3D.new()
	add_child(_bsp_root)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = _assets.get_sky("sky_dustbowl_01_hdr")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.25
	sun.rotation_degrees = Vector3(-42, 35, 0)
	add_child(sun)

	_cam = Camera3D.new()
	_cam.fov = 78.0
	_cam.far = 750.0
	add_child(_cam)

	_queue.append({"bsp": built_bsp, "out": ART + "/v6_turbine_rebuilt_compiled.png"})
	if FileAccess.file_exists(valve_bsp):
		_queue.append({"bsp": valve_bsp, "out": ART + "/v6_turbine_original_valve.png"})
	_load_next(0)

func _load_next(idx: int) -> void:
	for ch in _bsp_root.get_children():
		ch.queue_free()
	var item: Dictionary = _queue[idx]
	var res: Dictionary = _loader.load_bsp_into(item["bsp"], _bsp_root)
	print("  Rendered %s: ok=%s surfs=%d props=%d doors=%d" % [
		str(item["bsp"]).get_file(), str(res.get("ok", false)),
		int(res.get("surface_count", 0)), int(res.get("prop_count", 0)), int(res.get("door_count", 0))
	])
	_cam.look_at_from_position(CAM_POS, CAM_TGT, Vector3.UP)
	_frames = 0

func _process(_delta: float) -> void:
	if _queue.is_empty(): return
	_frames += 1
	if _frames == 10:
		var item: Dictionary = _queue[_qidx]
		get_viewport().get_texture().get_image().save_png(item["out"])
		print("  Saved: " + item["out"])
		_qidx += 1
		if _qidx >= _queue.size():
			get_tree().quit(0)
		else:
			_load_next(_qidx)

func _build_turbine_full(doc: Object) -> void:
	doc.new_map("ctf_turbine_rebuilt", "sky_dustbowl_01_hdr")
	doc.set_grid_units(8)

	var m_floor    := "CONCRETE/CONCRETEFLOOR008"
	var m_tile     := "TILE/FLOOR_TILE_006A"
	var m_grate    := "METAL/METALGRATE011A"
	var m_wall     := "CONCRETE/CONCRETEWALL012B"
	var m_band     := "METAL/IBEAM001B"
	var m_ceil     := "CONCRETE/CONCRETEWALL011A"
	var m_red_trim := "METAL/IMETAL001"
	var m_blu_trim := "METAL/IMETAL002"
	var m_red_wall := "CONCRETE/COMPUTERWALL005C"
	var m_blu_wall := "CONCRETE/COMPUTERWALL003C"
	var m_shutter  := "METAL/METALDOOR001"
	var m_glass    := "GLASS/GLASSWINDOW002A"
	var m_roof_out := "METAL/WALL012"
	var m_vent_in  := "METAL/METALWALL002A"

	# 1. MID TURBINE HALL FLOOR + WHITE TILE STRIP + 3 GRATE PADS
	doc.add_box(Vector3(-24.0, -9.0, -24.0), Vector3(24.0, -8.0, -4.5), m_floor)
	doc.add_box(Vector3(-24.0, -9.0, 4.5), Vector3(24.0, -8.0, 24.0), m_floor)
	doc.add_box(Vector3(-24.0, -9.0, -4.5), Vector3(-16.5, -8.0, 4.5), m_floor)
	doc.add_box(Vector3(16.5, -9.0, -4.5), Vector3(24.0, -8.0, 4.5), m_floor)
	doc.add_box(Vector3(-16.5, -9.0, -4.5), Vector3(16.5, -8.0, 4.5), m_tile)
	for tx: float in [-11.0, 0.0, 11.0]:
		doc.add_box(Vector3(tx - 3.3, -8.05, -3.3), Vector3(tx + 3.3, -7.96, 3.3), m_grate)

	# 2. CEILING SLAB + DARK IRON UPPER BAND + MASSIVE CENTRAL I-BEAM
	doc.add_box(Vector3(-24.5, 14.0, -24.5), Vector3(24.5, 15.0, 24.5), m_ceil)
	doc.add_box(Vector3(-24.5, 9.0, -24.5), Vector3(24.5, 14.0, -23.5), m_band)
	doc.add_box(Vector3(-24.5, 9.0, 23.5), Vector3(24.5, 14.0, 24.5), m_band)
	doc.add_box(Vector3(-24.5, 9.0, -23.5), Vector3(-23.5, 14.0, 23.5), m_band)
	doc.add_box(Vector3(23.5, 9.0, -23.5), Vector3(24.5, 14.0, 23.5), m_band)
	doc.add_box(Vector3(-0.75, 12.2, -23.5), Vector3(0.75, 14.0, 23.5), m_band)

	# 3. MAIN RED (+X) & BLU (-X) WALLS + CARVED ENTRANCES + TEAM TRIM
	doc.add_box(Vector3(23.5, -8.0, -23.5), Vector3(24.5, 9.0, 23.5), m_wall)
	doc.add_box(Vector3(-24.5, -8.0, -23.5), Vector3(-23.5, 9.0, 23.5), m_wall)
	doc.auto_carve_opening(Vector3(22.5, -8.0, -4.0), Vector3(25.5, -2.0, 4.0), m_wall)
	doc.auto_carve_opening(Vector3(-25.5, -8.0, -4.0), Vector3(-22.5, -2.0, 4.0), m_wall)
	# Carve playable upper Vent Duct entrances behind both Vent Observation Booths!
	doc.auto_carve_opening(Vector3(22.5, 1.5, -2.5), Vector3(25.5, 4.5, 2.5), m_vent_in)
	doc.auto_carve_opening(Vector3(-25.5, 1.5, -2.5), Vector3(-22.5, 4.5, 2.5), m_vent_in)

	# Lower side shuttered doors + team trims
	doc.add_box(Vector3(23.25, -8.0, 10.5), Vector3(23.6, -2.8, 17.5), m_shutter)
	doc.add_box(Vector3(23.15, -2.8, 10.3), Vector3(23.6, -2.4, 17.7), m_red_trim)
	doc.add_box(Vector3(23.15, -8.0, 10.3), Vector3(23.6, -2.4, 10.6), m_red_trim)
	doc.add_box(Vector3(23.15, -8.0, 17.4), Vector3(23.6, -2.4, 17.7), m_red_trim)

	doc.add_box(Vector3(-23.6, -8.0, -17.5), Vector3(-23.25, -2.8, -10.5), m_shutter)
	doc.add_box(Vector3(-23.6, -2.8, -17.7), Vector3(-23.15, -2.4, -10.3), m_blu_trim)
	doc.add_box(Vector3(-23.6, -8.0, -10.6), Vector3(-23.15, -2.4, -10.3), m_blu_trim)
	doc.add_box(Vector3(-23.6, -8.0, -17.7), Vector3(-23.15, -2.4, -17.4), m_blu_trim)

	# Main hallway door trim borders
	doc.add_box(Vector3(23.2, -2.15, -4.25), Vector3(23.6, -1.75, 4.25), m_red_trim)
	doc.add_box(Vector3(23.2, -8.0, -4.35), Vector3(23.6, -1.75, -4.0), m_red_trim)
	doc.add_box(Vector3(23.2, -8.0, 4.0), Vector3(23.6, -1.75, 4.35), m_red_trim)
	doc.add_box(Vector3(-23.6, -2.15, -4.25), Vector3(-23.2, -1.75, 4.25), m_blu_trim)
	doc.add_box(Vector3(-23.6, -8.0, -4.35), Vector3(-23.2, -1.75, -4.0), m_blu_trim)
	doc.add_box(Vector3(-23.6, -8.0, 4.0), Vector3(-23.2, -1.75, 4.35), m_blu_trim)

	# 4. SIDE WINDOW WALLS + ALCOVES + EXTERIOR SLOPED ROOFS
	for sz: float in [-1.0, 1.0]:
		var z0: float = -24.5 if sz < 0 else 23.5
		var z1: float = -23.5 if sz < 0 else 24.5
		doc.add_box(Vector3(-23.5, -8.0, z0), Vector3(23.5, 0.5, z1), m_wall)
		doc.add_box(Vector3(-23.5, 8.0, z0), Vector3(23.5, 9.0, z1), m_wall)
		doc.add_box(Vector3(-1.4, -8.0, z0 - 0.35), Vector3(1.4, 9.0, z1 + 0.35), m_wall)
		doc.add_box(Vector3(-23.5, 0.5, z0), Vector3(-20.0, 8.0, z1), m_wall)
		doc.add_box(Vector3(20.0, 0.5, z0), Vector3(23.5, 8.0, z1), m_wall)
		for mx: float in [-14.0, -7.75, 7.75, 14.0]:
			doc.add_box(Vector3(mx - 0.35, 0.5, z0), Vector3(mx + 0.35, 8.0, z1), m_wall)
		doc.add_box(Vector3(-20.0, 0.5, z0 + 0.4), Vector3(-1.4, 8.0, z1 - 0.4), m_glass)
		doc.add_box(Vector3(1.4, 0.5, z0 + 0.4), Vector3(20.0, 8.0, z1 - 0.4), m_glass)
		if sz < 0:
			doc.auto_carve_opening(Vector3(-15.5, -8.0, -25.0), Vector3(-7.0, -3.5, -23.0), m_wall)
			doc.add_box(Vector3(-16.0, -8.5, -28.0), Vector3(-6.5, -8.0, -23.5), m_floor)
			doc.add_box(Vector3(-16.0, -3.5, -28.0), Vector3(-6.5, -3.0, -23.5), m_wall)
			doc.add_box(Vector3(-16.0, -8.0, -28.5), Vector3(-6.5, -3.5, -28.0), m_shutter)
			doc.add_box(Vector3(-16.5, -8.0, -28.0), Vector3(-16.0, -3.5, -23.5), m_wall)
			doc.add_box(Vector3(-6.5, -8.0, -28.0), Vector3(-6.0, -3.5, -23.5), m_wall)
		else:
			doc.auto_carve_opening(Vector3(7.0, -8.0, 23.0), Vector3(15.5, -3.5, 25.0), m_wall)
			doc.add_box(Vector3(6.5, -8.5, 23.5), Vector3(16.0, -8.0, 28.0), m_floor)
			doc.add_box(Vector3(6.5, -3.5, 23.5), Vector3(16.0, -3.0, 28.0), m_wall)
			doc.add_box(Vector3(6.5, -8.0, 28.0), Vector3(16.0, -3.5, 28.5), m_shutter)
			doc.add_box(Vector3(6.0, -8.0, 23.5), Vector3(6.5, -3.5, 28.0), m_wall)
			doc.add_box(Vector3(16.0, -8.0, 23.5), Vector3(16.5, -3.5, 28.0), m_wall)
		var ext_z0: float = -35.0 if sz < 0 else 25.5
		var ext_z1: float = -25.5 if sz < 0 else 35.0
		doc.add_ramp(Vector3(-25.0, -1.0, ext_z0), Vector3(25.0, 7.0, ext_z1), 3 if sz < 0 else 2, m_roof_out)

	# 5. CATWALK BALCONIES + VENT OBSERVATION BOOTHS + OPEN-BACK STEEL STAIRS + GUARDRAILS!
	for side: float in [1.0, -1.0]:
		var is_red: bool = (side > 0.0)
		var trim := m_red_trim if is_red else m_blu_trim
		var bx0: float = 19.5 if is_red else -23.5
		var bx1: float = 23.5 if is_red else -19.5
		doc.add_box(Vector3(bx0, 1.05, -23.5), Vector3(bx1, 1.50, 23.5), trim)
		# Crisp catwalk safety railing along Mid edge (leaving gap at stairs!)
		var rx0: float = 19.5 if is_red else -19.75
		var rx1: float = 19.75 if is_red else -19.5
		doc.add_box(Vector3(rx0, 2.35, 6.0), Vector3(rx1, 2.55, 23.0), m_band)
		doc.add_box(Vector3(rx0, 2.35, -19.5), Vector3(rx1, 2.55, -6.0), m_band)
		for pz: float in [-18.0, -12.0, -6.2, 6.2, 12.0, 18.0]:
			doc.add_box(Vector3(rx0, 1.5, pz - 0.12), Vector3(rx1, 2.55, pz + 0.12), m_band)

		# Vent Observation Booth (with glass windows + team frames)
		var vx0: float = 19.0 if is_red else -23.5
		var vx1: float = 23.5 if is_red else -19.0
		var face_x0: float = 19.0 if is_red else -19.5
		var face_x1: float = 19.5 if is_red else -19.0
		doc.add_box(Vector3(face_x0, 1.5, -6.0), Vector3(face_x1, 2.3, 6.0), m_wall)
		doc.add_box(Vector3(face_x0, 4.6, -6.0), Vector3(face_x1, 5.25, 6.0), m_wall)
		doc.add_box(Vector3(face_x0, 2.3, -6.0), Vector3(face_x1, 4.6, -5.2), m_wall)
		doc.add_box(Vector3(face_x0, 2.3, -0.4), Vector3(face_x1, 4.6, 0.4), m_wall)
		doc.add_box(Vector3(face_x0, 2.3, 5.2), Vector3(face_x1, 4.6, 6.0), m_wall)
		var ftrim_x0: float = face_x0 - 0.06 if is_red else face_x0
		var ftrim_x1: float = face_x1 if is_red else face_x1 + 0.06
		doc.add_box(Vector3(ftrim_x0, 2.25, -5.3), Vector3(ftrim_x1, 2.42, 5.3), trim)
		doc.add_box(Vector3(ftrim_x0, 4.48, -5.3), Vector3(ftrim_x1, 4.65, 5.3), trim)
		doc.add_box(Vector3(ftrim_x0, 2.25, -5.35), Vector3(ftrim_x1, 4.65, -5.15), trim)
		doc.add_box(Vector3(ftrim_x0, 2.25, -0.48), Vector3(ftrim_x1, 4.65, -0.32), trim)
		doc.add_box(Vector3(ftrim_x0, 2.25, 0.32), Vector3(ftrim_x1, 4.65, 0.48), trim)
		doc.add_box(Vector3(ftrim_x0, 2.25, 5.15), Vector3(ftrim_x1, 4.65, 5.35), trim)
		doc.add_box(Vector3(vx0, 1.5, -6.0), Vector3(vx1, 5.25, -5.5), m_wall)
		doc.add_box(Vector3(vx0, 1.5, 5.5), Vector3(vx1, 5.25, 6.0), m_wall)
		doc.add_box(Vector3(vx0 - 0.15, 5.25, -6.15), Vector3(vx1, 5.75, 6.15), m_band)
		doc.add_box(Vector3(face_x0 + 0.2, 2.42, -5.15), Vector3(face_x1 - 0.2, 4.48, -0.48), m_glass)
		doc.add_box(Vector3(face_x0 + 0.2, 2.42, 0.48), Vector3(face_x1 - 0.2, 4.48, 5.15), m_glass)

		# Playable Upper Vent Duct Tunnel connecting Mid Booth to Intel Room!
		var dx0: float = 24.5 if is_red else -48.5
		var dx1: float = 48.5 if is_red else -24.5
		doc.add_room(Vector3(dx0, 1.5, -2.5), Vector3(dx1, 4.5, 2.5), 0.4, m_vent_in, m_vent_in, m_vent_in, false)
		doc.auto_carve_opening(Vector3(dx0 - 0.8, 1.5, -2.0), Vector3(dx0 + 0.8, 4.2, 2.0), m_vent_in)
		doc.auto_carve_opening(Vector3(dx1 - 0.8, 1.5, -2.0), Vector3(dx1 + 0.8, 4.2, 2.0), m_vent_in)

		# Open-Back Floating Steel Stairs
		var steps := 22
		for s in range(steps):
			var t0 := float(s) / float(steps)
			var t1 := float(s + 1) / float(steps)
			var sy0 := lerpf(-8.0, 1.5, t0)
			var sy1 := sy0 + 0.32
			if is_red:
				var sx0 := lerpf(6.5, 19.5, t0)
				var sx1 := lerpf(6.5, 19.5, t1) + 0.2
				doc.add_box(Vector3(sx0, sy0, -23.3), Vector3(sx1, sy1, -20.2), m_band)
			else:
				var sx1 := lerpf(-6.5, -19.5, t0)
				var sx0 := lerpf(-6.5, -19.5, t1) - 0.2
				doc.add_box(Vector3(sx0, sy0, 20.2), Vector3(sx1, sy1, 23.3), m_band)

	# 6. CONNECTED RED & BLU HALLWAYS + SEPARATE SPAWN ROOMS (WITH INTERACTIVE SLIDING DOORS!) + 2-LEVEL INTEL ROOMS!
	for side: float in [1.0, -1.0]:
		var is_red: bool = (side > 0.0)
		var team := 2 if is_red else 3
		var wall_t := m_red_wall if is_red else m_blu_wall
		var trim := m_red_trim if is_red else m_blu_trim

		# Main Hallway
		var hx0: float = 24.5 if is_red else -48.0
		var hx1: float = 48.0 if is_red else -24.5
		doc.add_room(Vector3(hx0, -8.0, -6.0), Vector3(hx1, 1.0, 6.0), 0.5, m_floor, wall_t, m_ceil, false)
		doc.auto_carve_opening(Vector3(hx0 - 1.0, -8.0, -4.0), Vector3(hx0 + 1.0, -2.0, 4.0), trim)
		doc.auto_carve_opening(Vector3(hx1 - 1.0, -8.0, -4.0), Vector3(hx1 + 1.0, -2.0, 4.0), trim)

		# Separate Team Spawn Room off the Hallway with REAL Interactive Sliding func_door!
		var sp_x0: float = 30.0 if is_red else -42.0
		var sp_x1: float = 42.0 if is_red else -30.0
		var sp_z0: float = 6.0 if is_red else -18.0
		var sp_z1: float = 18.0 if is_red else -6.0
		doc.add_room(Vector3(sp_x0, -8.0, sp_z0), Vector3(sp_x1, 0.5, sp_z1), 0.5, m_tile, wall_t, m_ceil, false)
		var door_z: float = 6.0 if is_red else -6.0
		doc.auto_carve_opening(Vector3(sp_x0 + 3.5, -8.0, door_z - 1.0), Vector3(sp_x1 - 3.5, -3.5, door_z + 1.0), trim)
		doc.add_brush_entity("func_door",
			Vector3(sp_x0 + 3.6, -8.0, door_z - 0.25), Vector3(sp_x1 - 3.6, -3.5, door_z + 0.25),
			m_shutter, {"targetname": ("red_spawn_door" if is_red else "blu_spawn_door"), "movedir": "-90 0 0", "speed": "380"})
		doc.add_brush_entity("func_respawnroom",
			Vector3(sp_x0 + 0.6, -7.8, sp_z0 + 0.6), Vector3(sp_x1 - 0.6, -1.0, sp_z1 - 0.6),
			"TOOLS/TOOLSTRIGGER", {"TeamNum": str(team)})
		var sp_cx := (sp_x0 + sp_x1) * 0.5
		var sp_cz := (sp_z0 + sp_z1) * 0.5
		for dx_s: float in [-3.0, 0.0, 3.0]:
			doc.add_point_entity("info_player_teamspawn", Vector3(sp_cx + dx_s, -7.6, sp_cz), {
				"TeamNum": str(team), "angles": "0 %d 0" % (-90 if is_red else 90)
			})
		doc.add_point_entity("prop_dynamic", Vector3(sp_cx, -8.0, sp_z1 - 1.2 if is_red else sp_z0 + 1.2), {
			"model": "models/props_gameplay/resupply_locker.mdl",
			"angles": "0 %d 0" % (-90 if is_red else 90), "solid": "6"
		})
		doc.add_point_entity("light", Vector3(sp_cx, -1.5, sp_cz), {"_light": "255 245 225 280"})

		# 2-Level Intel Room (with raised balcony, pillar, Spytech consoles & Intel Briefcase!)
		var ix0: float = 48.0 if is_red else -72.0
		var ix1: float = 72.0 if is_red else -48.0
		doc.add_room(Vector3(ix0, -8.0, -16.0), Vector3(ix1, 6.0, 16.0), 0.5, m_floor, wall_t, m_ceil, false)
		doc.auto_carve_opening(Vector3(ix0 - 1.0, -8.0, -4.0), Vector3(ix0 + 1.0, -2.0, 4.0), trim)
		doc.auto_carve_opening(Vector3(ix1 - 1.0, -8.0, -4.0), Vector3(ix1 + 1.0, -2.0, 4.0), trim)
		# Vent Drop Balcony inside Intel Room!
		var bal_x0: float = ix0 + 0.5 if is_red else ix1 - 6.0
		var bal_x1: float = ix0 + 6.0 if is_red else ix1 - 0.5
		doc.add_box(Vector3(bal_x0, 0.8, -10.0), Vector3(bal_x1, 1.3, 10.0), trim)
		# Central Intel room cover pillar
		var ix_mid := (ix0 + ix1) * 0.5
		doc.add_box(Vector3(ix_mid - 1.5, -8.0, -8.5), Vector3(ix_mid + 1.5, 6.0, -5.5), m_wall)
		# Intel Briefcase + Capture Zone + Spytech Consoles + Health/Ammo!
		doc.add_point_entity("item_teamflag", Vector3(ix_mid + (4.0 if is_red else -4.0), -7.5, 0), {"TeamNum": str(team), "GameType": "0"})
		doc.add_brush_entity("func_capturezone", Vector3(ix_mid + (1.5 if is_red else -6.5), -8.0, -2.5), Vector3(ix_mid + (6.5 if is_red else -1.5), -4.5, 2.5),
			"TOOLS/TOOLSTRIGGER", {"TeamNum": str(team)})
		doc.add_point_entity("prop_static", Vector3(ix1 - 2.0 if is_red else ix0 + 2.0, -8.0, 8.0), {
			"model": "models/props_spytech/computer_wall02.mdl", "angles": "0 %d 0" % (180 if is_red else 0), "solid": "6"
		})
		doc.add_point_entity("prop_static", Vector3(ix1 - 2.0 if is_red else ix0 + 2.0, -8.0, -8.0), {
			"model": "models/props_spytech/control_room_console01.mdl", "angles": "0 %d 0" % (180 if is_red else 0), "solid": "6"
		})
		doc.add_point_entity("item_healthkit_medium", Vector3(ix_mid, -7.8, 12.0), {})
		doc.add_point_entity("item_ammopack_medium", Vector3(ix_mid, -7.8, -12.0), {})
		doc.add_point_entity("light", Vector3(ix_mid, 3.0, 0), {"_light": "255 242 220 340"})
		doc.add_point_entity("light", Vector3((hx0 + hx1) * 0.5, -1.0, 0), {"_light": "255 242 220 220"})

	# 7. ICONIC TURBINE MID HALL PROPS (3 Generators, 2 Shipping Containers, 9 Ceiling Lamps, Floodlights, Drums)
	for tx: float in [-11.0, 0.0, 11.0]:
		doc.add_point_entity("prop_static", Vector3(tx, -8.0, 0.0), {
			"model": "models/props_mining/generator01.mdl", "angles": "0 0 0", "solid": "6"
		})
	doc.add_point_entity("prop_static", Vector3(0.0, -8.0, -10.0), {
		"model": "models/props_vehicles/train_flatcar_container.mdl", "angles": "0 0 0", "solid": "6", "skin": "1"
	})
	doc.add_point_entity("prop_static", Vector3(0.0, -8.0, 10.0), {
		"model": "models/props_vehicles/train_flatcar_container.mdl", "angles": "0 180 0", "solid": "6", "skin": "0"
	})
	for lx: float in [-16.5, 0.0, 16.5]:
		for lz: float in [-14.0, 0.0, 14.0]:
			doc.add_point_entity("prop_static", Vector3(lx, 10.13, lz), {
				"model": "models/props_mining/industrial_ceiling_lamp02.mdl", "angles": "0 -90 0", "solid": "0"
			})
			doc.add_point_entity("light", Vector3(lx, 8.6, lz), {"_light": "255 246 228 240", "_quadratic_attn": "1"})
	for fpos in [
		{"m": "models/props_lights/flood_light_base001.mdl",  "p": Vector3(23.5, -2.2, 14.0),  "y": -180},
		{"m": "models/props_lights/flood_light_left001.mdl",  "p": Vector3(23.3, -2.2, 13.7),  "y": 158},
		{"m": "models/props_lights/flood_light_right001.mdl", "p": Vector3(23.3, -2.2, 14.3),  "y": -167},
		{"m": "models/props_lights/flood_light_base001.mdl",  "p": Vector3(-23.5, -2.2, -14.0),"y": 0},
		{"m": "models/props_lights/flood_light_left001.mdl",  "p": Vector3(-23.3, -2.2, -13.7),"y": -22},
		{"m": "models/props_lights/flood_light_right001.mdl", "p": Vector3(-23.3, -2.2, -14.3),"y": 13},
		{"m": "models/props_2fort/oildrum.mdl", "p": Vector3(22.6, -8.0, -22.6), "y": 0},
		{"m": "models/props_2fort/oildrum.mdl", "p": Vector3(21.6, -8.0, -22.6), "y": 40},
		{"m": "models/props_2fort/oildrum.mdl", "p": Vector3(-22.6, -8.0, 22.6), "y": 0},
		{"m": "models/props_2fort/oildrum.mdl", "p": Vector3(-21.6, -8.0, 22.6), "y": 40},
	]:
		doc.add_point_entity("prop_static", fpos["p"], {"model": fpos["m"], "angles": "0 %d 0" % int(fpos["y"]), "solid": "0"})

	doc.add_point_entity("item_healthkit_medium", Vector3(8.0, -7.8, 25.0), {})
	doc.add_point_entity("item_healthkit_medium", Vector3(-8.0, -7.8, -25.0), {})
	doc.add_point_entity("item_ammopack_medium", Vector3(13.0, -7.8, 25.0), {})
	doc.add_point_entity("item_ammopack_medium", Vector3(-13.0, -7.8, -25.0), {})
	doc.add_point_entity("tf_gamerules", Vector3(0, 11, 0), {"ctf_overtime": "1"})
	doc.add_point_entity("light_environment", Vector3(0, 18, 0), {
		"angles": "0 45 0", "pitch": "-42", "_light": "255 245 225 420", "_ambient": "170 185 205 190"
	})
	doc.auto_seal_skybox()
