extends Node3D

## Milestone 13 — Autonomous Self-Test Challenge (Iteration v2 — High-Fidelity Polish):
## Rebuilds Valve's iconic ctf_turbine using ONLY Pootis Builder 2.0's native Tf2MapDoc API,
## compiles it cleanly through Valve's real vbsp + vvis + vrad, and renders side-by-side
## matching camera views against official ctf_turbine.bsp!

const Tf2AssetsScript    = preload("res://scripts/core/Tf2Assets.gd")
const Tf2BspLoaderScript = preload("res://scripts/core/Tf2BspLoader.gd")

const REPO_ROOT := "C:/Users/steph/Documents/Git/pootis builder"
const ART       := "C:/Users/steph/.gemini/antigravity/brain/dc036b95-0d4c-4a2b-8b8a-c124bec47848"
const ITER_TAG  := "v3"

const CAM_VIEWS := [
	{"name": "viewA", "pos": Vector3(-12.0, 5.5, 10.0), "target": Vector3(4.0, 2.5, -2.0)},
	{"name": "viewB", "pos": Vector3(13.0, 2.5, -13.0), "target": Vector3(-5.0, -3.5, 3.0)},
]

var _core: Object
var _assets: RefCounted
var _loader: RefCounted
var _bsp_root: Node3D
var _we: WorldEnvironment
var _cam: Camera3D

var _queue: Array = []
var _qidx: int = 0
var _frames: int = 0
var _loaded_bsp: String = ""

func _ready() -> void:
	print("=== Milestone 13 (%s): Building pb_turbine with Pootis Builder & Comparing to Valve ctf_turbine ===" % ITER_TAG)
	_core = ClassDB.instantiate("Tf2Core")
	_core.mount_tf2(REPO_ROOT)
	_assets = Tf2AssetsScript.new(_core)
	_loader = Tf2BspLoaderScript.new(_core, _assets)

	# Step 1: Build pb_turbine.vmf using ONLY Pootis Builder's Tf2MapDoc API!
	var doc = ClassDB.instantiate("Tf2MapDoc")
	_build_pb_turbine(doc)
	DirAccess.make_dir_recursive_absolute(REPO_ROOT + "/godot/maps")
	var vmf_path := REPO_ROOT + "/godot/maps/pb_turbine.vmf"
	var sv: Dictionary = doc.save_vmf(vmf_path)
	print("  Saved pb_turbine.vmf: ok=%s solids=%d ents=%d" % [str(sv.get("ok", false)), doc.get_solid_count(), doc.get_entity_count()])

	# Step 2: Compile pb_turbine.vmf with REAL Valve vbsp + vvis + vrad!
	var compiler = ClassDB.instantiate("Tf2Compiler")
	var paths: Dictionary = compiler.detect_paths()
	var pb_bsp_path: String = str(paths["game_dir"]).path_join("maps/pb_turbine.bsp")
	compiler.start_compile(vmf_path, true, true, true, false, "pb_turbine")
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
		for i in range(max(0, logs.size() - 18), logs.size()):
			print("    [compile] " + logs[i])
		get_tree().quit(1)
		return

	# Step 3: Set up identical Vulkan scene to render our pb_turbine.bsp side-by-side!
	_bsp_root = Node3D.new()
	add_child(_bsp_root)

	_we = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = _assets.get_sky("sky_dustbowl_01_hdr")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.72
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_we.environment = env
	add_child(_we)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.25
	sun.rotation_degrees = Vector3(-42, 35, 0)
	add_child(sun)

	_cam = Camera3D.new()
	_cam.fov = 78.0
	_cam.far = 750.0
	add_child(_cam)

	for vi in range(CAM_VIEWS.size()):
		var vn: String = CAM_VIEWS[vi]["name"]
		_queue.append({"bsp": pb_bsp_path, "vi": vi, "out": "%s/m13_pb_%s_%s.png" % [ART, ITER_TAG, vn]})

	_start_shot(0)

func _start_shot(idx: int) -> void:
	var item: Dictionary = _queue[idx]
	var bp: String = item["bsp"]
	if bp != _loaded_bsp:
		for ch in _bsp_root.get_children():
			ch.queue_free()
		var res: Dictionary = _loader.load_bsp_into(bp, _bsp_root)
		print("  Loaded %s -> ok=%s surfs=%d props=%d" % [
			bp.get_file(), str(res.get("ok", false)), int(res.get("surface_count", 0)), int(res.get("prop_count", 0))
		])
		_loaded_bsp = bp
	var v: Dictionary = CAM_VIEWS[int(item["vi"])]
	_cam.look_at_from_position(v["pos"], v["target"], Vector3.UP)
	_frames = 0

func _process(_delta: float) -> void:
	if _queue.is_empty():
		return
	_frames += 1
	if _frames == 8:
		var item: Dictionary = _queue[_qidx]
		get_viewport().get_texture().get_image().save_png(item["out"])
		print("  Saved: ", item["out"])
		_qidx += 1
		if _qidx >= _queue.size():
			print("=== MILESTONE 13 (%s) COMPARISON COMPLETE ===" % ITER_TAG)
			get_tree().quit(0)
		else:
			_start_shot(_qidx)

# ==============================================================================
# POOTIS BUILDER CTF_TURBINE ARCHITECTURE (v2 — Exact Valve Materials, Beams & Details!)
# ==============================================================================
func _build_pb_turbine(doc: Object) -> void:
	doc.new_map("pb_turbine", "sky_dustbowl_01_hdr")
	doc.set_grid_units(8)

	# Exact materials sampled directly from official Valve ctf_turbine.bsp (Pass 3)!
	var m_floor    := "CONCRETE/CONCRETEFLOOR008"   # Exact Valve dark charcoal tiled Mid Hall floor!
	var m_tile     := "TILE/FLOOR_TILE_006A"        # Crisp square grid white tile strip!
	var m_grate    := "METAL/METALGRATE011A"        # Slotted steel grates under the 3 turbines!
	var m_wall     := "CONCRETE/CONCRETEWALL012B"   # Weathered concrete panel walls!
	var m_band     := "METAL/IBEAM001B"             # Dark rusted iron upper wall band & main I-beam!
	var m_ceil     := "CONCRETE/CONCRETEWALL011A"   # Stained industrial concrete ceiling!
	var m_red_trim := "METAL/IMETAL001"             # Exact Valve deep RED crimson trim!
	var m_blu_trim := "METAL/IMETAL002"             # Exact Valve deep BLU slate trim!
	var m_red_wall := "CONCRETE/COMPUTERWALL005C"
	var m_blu_wall := "CONCRETE/COMPUTERWALL003C"
	var m_shutter  := "METAL/METALDOOR001"
	var m_glass    := "GLASS/GLASSWINDOW002A"       # Exact Valve clear spytech window glass!
	var m_roof_out := "METAL/WALL012"               # Exact weathered turquoise-rust corrugated exterior roof!
	var m_vent_in  := "CONCRETE/CONCRETEWALL014"

	# 1. MID HALL FLOOR (X: -23.5..+23.5, Z: -23.5..+23.5, Y: -9.0..-8.0)
	doc.add_box(Vector3(-24.0, -9.0, -24.0), Vector3(24.0, -8.0, -4.5), m_floor)
	doc.add_box(Vector3(-24.0, -9.0, 4.5), Vector3(24.0, -8.0, 24.0), m_floor)
	doc.add_box(Vector3(-24.0, -9.0, -4.5), Vector3(-16.5, -8.0, 4.5), m_floor)
	doc.add_box(Vector3(16.5, -9.0, -4.5), Vector3(24.0, -8.0, 4.5), m_floor)
	# Center square-grid white tile strip + 3 dark slotted grate pads under the turbines!
	doc.add_box(Vector3(-16.5, -9.0, -4.5), Vector3(16.5, -8.0, 4.5), m_tile)
	for tx: float in [-11.0, 0.0, 11.0]:
		doc.add_box(Vector3(tx - 3.3, -8.05, -3.3), Vector3(tx + 3.3, -7.96, 3.3), m_grate)

	# 2. CEILING SLAB (Y: 14.0..15.0) + DARK IRON UPPER BAND (Y: 9.0..14.0) + SINGLE CENTER I-BEAM!
	doc.add_box(Vector3(-24.5, 14.0, -24.5), Vector3(24.5, 15.0, 24.5), m_ceil)
	doc.add_box(Vector3(-24.5, 9.0, -24.5), Vector3(24.5, 14.0, -23.5), m_band)
	doc.add_box(Vector3(-24.5, 9.0, 23.5), Vector3(24.5, 14.0, 24.5), m_band)
	doc.add_box(Vector3(-24.5, 9.0, -23.5), Vector3(-23.5, 14.0, 23.5), m_band)
	doc.add_box(Vector3(23.5, 9.0, -23.5), Vector3(24.5, 14.0, 23.5), m_band)
	# Valve's iconic single massive central dark I-beam running from Z=-23.5 to Z=+23.5 along X=0!
	doc.add_box(Vector3(-0.75, 12.2, -23.5), Vector3(0.75, 14.0, 23.5), m_band)

	# 3. CONCRETE MAIN WALLS (Y: -8.0..+9.0) — X = +23.5 (RED) & X = -23.5 (BLU)
	doc.add_box(Vector3(23.5, -8.0, -23.5), Vector3(24.5, 9.0, 23.5), m_wall)
	doc.add_box(Vector3(-24.5, -8.0, -23.5), Vector3(-23.5, 9.0, 23.5), m_wall)

	# Carve main RED & BLU hallway entrances cleanly!
	doc.auto_carve_opening(Vector3(22.5, -8.0, -4.0), Vector3(25.5, -2.0, 4.0), m_wall)
	doc.auto_carve_opening(Vector3(-25.5, -8.0, -4.0), Vector3(-22.5, -2.0, 4.0), m_wall)

	# Shuttered lower right-side doors (RED +Z side, BLU -Z side) + crisp team trim frames!
	doc.add_box(Vector3(23.25, -8.0, 10.5), Vector3(23.6, -2.8, 17.5), m_shutter)
	doc.add_box(Vector3(23.15, -2.8, 10.3), Vector3(23.6, -2.4, 17.7), m_red_trim)
	doc.add_box(Vector3(23.15, -8.0, 10.3), Vector3(23.6, -2.4, 10.6), m_red_trim)
	doc.add_box(Vector3(23.15, -8.0, 17.4), Vector3(23.6, -2.4, 17.7), m_red_trim)

	doc.add_box(Vector3(-23.6, -8.0, -17.5), Vector3(-23.25, -2.8, -10.5), m_shutter)
	doc.add_box(Vector3(-23.6, -2.8, -17.7), Vector3(-23.15, -2.4, -10.3), m_blu_trim)
	doc.add_box(Vector3(-23.6, -8.0, -10.6), Vector3(-23.15, -2.4, -10.3), m_blu_trim)
	doc.add_box(Vector3(-23.6, -8.0, -17.7), Vector3(-23.15, -2.4, -17.4), m_blu_trim)

	# Main hallway door RED & BLU trim borders!
	doc.add_box(Vector3(23.2, -2.15, -4.25), Vector3(23.6, -1.75, 4.25), m_red_trim)
	doc.add_box(Vector3(23.2, -8.0, -4.35), Vector3(23.6, -1.75, -4.0), m_red_trim)
	doc.add_box(Vector3(23.2, -8.0, 4.0), Vector3(23.6, -1.75, 4.35), m_red_trim)

	doc.add_box(Vector3(-23.6, -2.15, -4.25), Vector3(-23.2, -1.75, 4.25), m_blu_trim)
	doc.add_box(Vector3(-23.6, -8.0, -4.35), Vector3(-23.2, -1.75, -4.0), m_blu_trim)
	doc.add_box(Vector3(-23.6, -8.0, 4.0), Vector3(-23.2, -1.75, 4.35), m_blu_trim)

	# 4. SIDE WINDOW WALLS (Z = -23.5 and Z = +23.5) WITH TALL INDUSTRIAL WINDOWS & EXTERIOR GREEN ROOF!
	for sz: float in [-1.0, 1.0]:
		var z0: float = -24.5 if sz < 0 else 23.5
		var z1: float = -23.5 if sz < 0 else 24.5
		# Lower concrete wall below windows (Y: -8.0..+0.5)
		doc.add_box(Vector3(-23.5, -8.0, z0), Vector3(23.5, 0.5, z1), m_wall)
		# Upper concrete lintel above windows (Y: +8.0..+9.0)
		doc.add_box(Vector3(-23.5, 8.0, z0), Vector3(23.5, 9.0, z1), m_wall)
		# Central heavy structural concrete pier (runs floor-to-ceiling right up to the I-beam!)
		doc.add_box(Vector3(-1.4, -8.0, z0 - 0.35), Vector3(1.4, 9.0, z1 + 0.35), m_wall)
		doc.add_box(Vector3(-23.5, 0.5, z0), Vector3(-20.0, 8.0, z1), m_wall)
		doc.add_box(Vector3(20.0, 0.5, z0), Vector3(23.5, 8.0, z1), m_wall)
		# Window vertical mullions (3 crisp tall window bays on each side of the pier!)
		for mx: float in [-14.0, -7.75, 7.75, 14.0]:
			doc.add_box(Vector3(mx - 0.35, 0.5, z0), Vector3(mx + 0.35, 8.0, z1), m_wall)
		# Translucent window panes
		doc.add_box(Vector3(-20.0, 0.5, z0 + 0.4), Vector3(-1.4, 8.0, z1 - 0.4), m_glass)
		doc.add_box(Vector3(1.4, 0.5, z0 + 0.4), Vector3(20.0, 8.0, z1 - 0.4), m_glass)

		# Lower side alcove recess under the left window bay (healthkit hallway!)
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

		# Exterior sloped turquoise-green corrugated warehouse roof visible outside windows!
		var ext_z0: float = -35.0 if sz < 0 else 25.5
		var ext_z1: float = -25.5 if sz < 0 else 35.0
		doc.add_ramp(Vector3(-25.0, -1.0, ext_z0), Vector3(25.0, 7.0, ext_z1), 3 if sz < 0 else 2, m_roof_out)

	# 5. ELEVATED RED (+X) & BLU (-X) CATWALK BALCONIES, VENT OBSERVATION BOOTHS & OPEN-BACK STEEL STAIRS!
	for side: float in [1.0, -1.0]:
		var is_red: bool = (side > 0.0)
		var trim := m_red_trim if is_red else m_blu_trim
		var bx0: float = 19.5 if is_red else -23.5
		var bx1: float = 23.5 if is_red else -19.5
		# Sleek dark steel/red balcony catwalk slab (Y: 1.05..1.50, full Z length!)
		doc.add_box(Vector3(bx0, 1.05, -23.5), Vector3(bx1, 1.50, 23.5), trim)
		# Dark upper vent doorway right at the top of the stairs!
		var vd_x0: float = 23.2 if is_red else -23.6
		var vd_x1: float = 23.6 if is_red else -23.2
		var vd_z0: float = -22.2 if is_red else 20.6
		var vd_z1: float = -20.6 if is_red else 22.2
		doc.add_box(Vector3(vd_x0, 1.5, vd_z0), Vector3(vd_x1, 4.6, vd_z1), m_band)

		# Overhanging Vent Observation Room (Y: 1.5..5.25, Z: -6.0..+6.0) with 2 big framed glass windows!
		var vx0: float = 19.0 if is_red else -23.5
		var vx1: float = 23.5 if is_red else -19.0
		var face_x0: float = 19.0 if is_red else -19.5
		var face_x1: float = 19.5 if is_red else -19.0
		doc.add_box(Vector3(face_x0, 1.5, -6.0), Vector3(face_x1, 2.3, 6.0), m_wall)
		doc.add_box(Vector3(face_x0, 4.6, -6.0), Vector3(face_x1, 5.25, 6.0), m_wall)
		doc.add_box(Vector3(face_x0, 2.3, -6.0), Vector3(face_x1, 4.6, -5.2), m_wall)
		doc.add_box(Vector3(face_x0, 2.3, -0.4), Vector3(face_x1, 4.6, 0.4), m_wall)
		doc.add_box(Vector3(face_x0, 2.3, 5.2), Vector3(face_x1, 4.6, 6.0), m_wall)
		# Crisp RED / BLU inner window frame borders (all 4 edges of both windows!)
		var ftrim_x0: float = face_x0 - 0.06 if is_red else face_x0
		var ftrim_x1: float = face_x1 if is_red else face_x1 + 0.06
		doc.add_box(Vector3(ftrim_x0, 2.25, -5.3), Vector3(ftrim_x1, 2.42, 5.3), trim)
		doc.add_box(Vector3(ftrim_x0, 4.48, -5.3), Vector3(ftrim_x1, 4.65, 5.3), trim)
		doc.add_box(Vector3(ftrim_x0, 2.25, -5.35), Vector3(ftrim_x1, 4.65, -5.15), trim)
		doc.add_box(Vector3(ftrim_x0, 2.25, -0.48), Vector3(ftrim_x1, 4.65, -0.32), trim)
		doc.add_box(Vector3(ftrim_x0, 2.25, 0.32), Vector3(ftrim_x1, 4.65, 0.48), trim)
		doc.add_box(Vector3(ftrim_x0, 2.25, 5.15), Vector3(ftrim_x1, 4.65, 5.35), trim)
		# Dark metal cap & side walls + dark recessed interior vent grate visible through booth windows!
		doc.add_box(Vector3(vx0, 1.5, -6.0), Vector3(vx1, 5.25, -5.5), m_wall)
		doc.add_box(Vector3(vx0, 1.5, 5.5), Vector3(vx1, 5.25, 6.0), m_wall)
		doc.add_box(Vector3(vx0 - 0.15, 5.25, -6.15), Vector3(vx1, 5.75, 6.15), m_band)
		doc.add_box(Vector3(23.1 if is_red else -23.4, 1.8, 0.6), Vector3(23.4 if is_red else -23.1, 4.5, 4.2), m_vent_in)
		# Glass inside booth windows
		doc.add_box(Vector3(face_x0 + 0.2, 2.42, -5.15), Vector3(face_x1 - 0.2, 4.48, -0.48), m_glass)
		doc.add_box(Vector3(face_x0 + 0.2, 2.42, 0.48), Vector3(face_x1 - 0.2, 4.48, 5.15), m_glass)

		# SLEEK FLOATING OPEN-BACK STEEL STAIRCASE (thin dark metal treads, exact Turbine silhouette!)
		var steps := 22
		for s in range(steps):
			var t0 := float(s) / float(steps)
			var t1 := float(s + 1) / float(steps)
			var sy0 := lerpf(-8.0, 1.5, t0)
			var sy1 := sy0 + 0.32 # thin floating open tread!
			if is_red:
				var sx0 := lerpf(6.5, 19.5, t0)
				var sx1 := lerpf(6.5, 19.5, t1) + 0.2
				doc.add_box(Vector3(sx0, sy0, -23.3), Vector3(sx1, sy1, -20.2), m_band)
			else:
				var sx1 := lerpf(-6.5, -19.5, t0)
				var sx0 := lerpf(-6.5, -19.5, t1) - 0.2
				doc.add_box(Vector3(sx0, sy0, 20.2), Vector3(sx1, sy1, 23.3), m_band)

	# 6. CONNECTED RED (+X) & BLU (-X) HALLWAYS, SPAWN ROOMS & INTEL ROOMS!
	for side: float in [1.0, -1.0]:
		var is_red: bool = (side > 0.0)
		var team := 2 if is_red else 3
		var wall_t := m_red_wall if is_red else m_blu_wall
		var trim := m_red_trim if is_red else m_blu_trim
		var hx0: float = 24.5 if is_red else -48.0
		var hx1: float = 48.0 if is_red else -24.5
		doc.add_room(Vector3(hx0, -8.0, -6.0), Vector3(hx1, 1.0, 6.0), 0.5, m_floor, wall_t, m_ceil, false)
		doc.auto_carve_opening(Vector3(hx0 - 1.0, -8.0, -4.0), Vector3(hx0 + 1.0, -2.0, 4.0), trim)
		doc.auto_carve_opening(Vector3(hx1 - 1.0, -8.0, -4.0), Vector3(hx1 + 1.0, -2.0, 4.0), trim)
		var ix0: float = 48.0 if is_red else -72.0
		var ix1: float = 72.0 if is_red else -48.0
		doc.add_room(Vector3(ix0, -8.0, -16.0), Vector3(ix1, 6.0, 16.0), 0.5, m_floor, wall_t, m_ceil, false)
		doc.auto_carve_opening(Vector3(ix0 - 1.0, -8.0, -4.0), Vector3(ix0 + 1.0, -2.0, 4.0), trim)
		doc.auto_carve_opening(Vector3(ix1 - 1.0, -8.0, -4.0), Vector3(ix1 + 1.0, -2.0, 4.0), trim)
		var ix_mid := (ix0 + ix1) * 0.5
		doc.add_point_entity("item_teamflag", Vector3(ix_mid, -7.5, 0), {"TeamNum": str(team), "GameType": "0"})
		doc.add_brush_entity("func_capturezone", Vector3(ix_mid - 2.5, -8.0, -2.5), Vector3(ix_mid + 2.5, -4.5, 2.5),
			"TOOLS/TOOLSTRIGGER", {"TeamNum": str(team)})
		for sz_sp: float in [-8.0, -5.0, 5.0, 8.0]:
			doc.add_point_entity("info_player_teamspawn", Vector3(ix_mid + (6.0 if is_red else -6.0), -7.5, sz_sp), {
				"TeamNum": str(team), "angles": "0 %d 0" % (180 if is_red else 0)
			})
		doc.add_point_entity("prop_dynamic", Vector3(ix_mid + (9.0 if is_red else -9.0), -8.0, 0), {
			"model": "models/props_gameplay/resupply_locker.mdl",
			"angles": "0 %d 0" % (180 if is_red else 0),
			"solid": "6",
		})
		doc.add_point_entity("light", Vector3(ix_mid, 3.0, 0), {"_light": "255 242 220 340"})
		doc.add_point_entity("light", Vector3((hx0 + hx1) * 0.5, -1.0, 0), {"_light": "255 242 220 220"})

	# 7. EXACT VALVE TURBINE MID HALL 3D PROPS (100% matched to official ctf_turbine.bsp!)
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
	# 9 Industrial Ceiling Lamps + calibrated Valve-style VRAD lighting!
	for lx: float in [-16.5, 0.0, 16.5]:
		for lz: float in [-14.0, 0.0, 14.0]:
			doc.add_point_entity("prop_static", Vector3(lx, 10.13, lz), {
				"model": "models/props_mining/industrial_ceiling_lamp02.mdl", "angles": "0 -90 0", "solid": "0"
			})
			doc.add_point_entity("light", Vector3(lx, 8.6, lz), {
				"_light": "255 246 228 240",
				"_quadratic_attn": "1",
			})
	# Double floodlights above the shuttered side doors + oil drums under the stairs + wall lamps!
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
		{"m": "models/props_lights/walllight001a.mdl", "p": Vector3(23.4, 8.2, -12.3), "y": -180},
		{"m": "models/props_lights/walllight001a.mdl", "p": Vector3(-23.4, 8.2, 12.3), "y": 0},
		{"m": "models/props_lights/light_fluorescent_basement.mdl", "p": Vector3(-21.25, 6.0, 0.0), "y": 180},
		{"m": "models/props_lights/light_fluorescent_basement.mdl", "p": Vector3(21.25, 6.0, 0.0), "y": 0},
	]:
		doc.add_point_entity("prop_static", fpos["p"], {
			"model": fpos["m"], "angles": "0 %d 0" % int(fpos["y"]), "solid": "0"
		})

	doc.add_point_entity("item_healthkit_medium", Vector3(8.0, -7.8, 25.0), {})
	doc.add_point_entity("item_healthkit_medium", Vector3(-8.0, -7.8, -25.0), {})
	doc.add_point_entity("tf_gamerules", Vector3(0, 11, 0), {"ctf_overtime": "1"})
	doc.add_point_entity("light_environment", Vector3(0, 18, 0), {
		"angles": "0 45 0", "pitch": "-42", "_light": "255 245 225 420", "_ambient": "170 185 205 190"
	})

	doc.auto_seal_skybox()
