extends SceneTree

## Milestone 16 — Automated F5 Playtest Movement, Floor Collision, Jump & Noclip Verification
## Tests BOTH: (1) Custom Tf2MapDoc KOTH arena AND (2) Official Valve ctf_turbine.bsp + pl_upward.bsp!

const Tf2AssetsScript        = preload("res://scripts/core/Tf2Assets.gd")
const Tf2BspLoaderScript     = preload("res://scripts/core/Tf2BspLoader.gd")
const Tf2GamemodesScript     = preload("res://scripts/core/Tf2Gamemodes.gd")
const MapSceneSyncScript     = preload("res://scripts/editor/MapSceneSync.gd")
const SandboxPlayerScript    = preload("res://scripts/playtest/Tf2SandboxPlayer.gd")

var _failed: bool = false
var _phase: int = 0
var _frames: int = 0
var _world: Node3D
var _core: Object
var _assets: RefCounted
var _loader: RefCounted
var _player: CharacterBody3D
var _start_pos: Vector3 = Vector3.ZERO
var _peak_y: float = -999.0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
		_failed = true
	else:
		print("  [PASS] " + msg)

func _initialize() -> void:
	print("=== Milestone 16: Automated F5 Movement & BSP Collision Verification ===")

func _setup_phase(p: int) -> void:
	if _world != null and is_instance_valid(_world):
		_world.free()
	_world = Node3D.new()
	root.add_child(_world)
	_frames = 0
	_peak_y = -999.0

	if _core == null:
		_core = ClassDB.instantiate("Tf2Core")
		_core.mount_tf2("C:/Users/steph/Documents/Git/pootis builder")
		_assets = Tf2AssetsScript.new(_core)
		_loader = Tf2BspLoaderScript.new(_core, _assets)

	_player = SandboxPlayerScript.new()
	_world.add_child(_player)
	_player.set_active(true)
	_player.set_tf2_class(0) # Scout 400 u/s

	if p == 0:
		# Phase 0: Custom KOTH map built by Pootis Builder
		var doc = ClassDB.instantiate("Tf2MapDoc")
		Tf2GamemodesScript.build_gamemode_template(doc, "koth", "badlands")
		var sync = MapSceneSyncScript.new()
		sync.setup(doc, null)
		_world.add_child(sync)
		sync.sync_all()
		_player.spawn_at(Vector3(0, 2.0, 8.0), 0.0)
	elif p == 1:
		# Phase 1: Official Valve ctf_turbine.bsp!
		var bsp_node := Node3D.new()
		_world.add_child(bsp_node)
		var res: Dictionary = _loader.load_bsp_into("ctf_turbine", bsp_node)
		_check(res.get("ok", false), "Loaded official ctf_turbine.bsp for F5 walk test")
		_player.spawn_at(Vector3(-8.0, -7.8, -14.0), 0.0) # Turbine Mid Hall floor!
	elif p == 2:
		# Phase 2: Official Valve pl_upward.bsp at actual spawn_pos!
		var bsp_node := Node3D.new()
		_world.add_child(bsp_node)
		var res: Dictionary = _loader.load_bsp_into("pl_upward", bsp_node)
		_check(res.get("ok", false), "Loaded official pl_upward.bsp for F5 walk test")
		_player.spawn_at(res["spawn_pos"], float(res["spawn_yaw"]))

	_start_pos = _player.global_position

func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _phase == 0 and _frames == 1 and _world == null:
		_setup_phase(0)
		return false

	# Let player settle onto floor for 8 frames, then walk forward for 45 frames, then jump!
	if _frames == 10:
		_start_pos = _player.global_position
		_player.test_input_override = Vector2(0, 1.0) # Hold W!
	if _frames == 35:
		_player.test_jump_override = true
	if _frames == 38:
		_player.test_jump_override = false
	if _frames >= 10:
		_peak_y = max(_peak_y, _player.global_position.y)

	if _frames == 55:
		var end_pos := _player.global_position
		var horiz_dist := Vector2(end_pos.x - _start_pos.x, end_pos.z - _start_pos.z).length()
		var jump_gain := _peak_y - _start_pos.y
		var fell_void := end_pos.y < _start_pos.y - 6.0
		var pname: String = ["Custom KOTH", "Official ctf_turbine.bsp", "Official pl_upward.bsp"][_phase]
		_check(not fell_void, "%s: player stayed solidly on floor (start_y=%.2f end_y=%.2f)" % [pname, _start_pos.y, end_pos.y])
		_check(horiz_dist > 1.5, "%s: WASD walking moved %.2fm (%.0fu) cleanly!" % [pname, horiz_dist, horiz_dist * 32.0])
		_check(jump_gain > 0.7, "%s: Space jump rose +%.2fm (+%.0fu)" % [pname, jump_gain, jump_gain * 32.0])

		# Also test V Noclip fly on Phase 2!
		if _phase == 2:
			_player.handle_key_press(KEY_V)
			var nc_start := _player.global_position
			_player.test_input_override = Vector2(0, 1.0)
			for _k in range(10):
				_player._physics_process(1.0 / 60.0)
			_check(_player.noclip and _player.global_position.distance_to(nc_start) > 1.0,
				"V Noclip free-fly moved %.2fm cleanly!" % _player.global_position.distance_to(nc_start))

		_phase += 1
		if _phase >= 3:
			if _failed:
				print("=== MILESTONE 16 FAILED ===")
				quit(1)
			else:
				print("=== MILESTONE 16 PASSED (F5 Movement, Floor Collision, Jump & Noclip 100% VERIFIED!) ===")
				quit(0)
			return true
		else:
			_setup_phase(_phase)
	return false
