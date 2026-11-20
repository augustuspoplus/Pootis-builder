extends SceneTree

const Tf2SandboxPlayerScript = preload("res://scripts/playtest/Tf2SandboxPlayer.gd")
const MapSceneSyncScript = preload("res://scripts/editor/MapSceneSync.gd")

var _failed: bool = false
var _frames: int = 0
var _player: CharacterBody3D
var _did_rocket: bool = false
var _max_vy: float = 0.0

func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
		_failed = true

func _initialize() -> void:
	print("=== Milestone 6: 6-Class F5 TF2 Playtest Sandbox Physics Test ===")

func _setup_scene() -> void:
	var world := Node3D.new()
	root.add_child(world)

	var doc = ClassDB.instantiate("Tf2MapDoc")
	doc.new_map("pb_m6_test", "sky_badlands_01")
	doc.add_box(Vector3(-24, -1, -24), Vector3(24, 0, 24), "CONCRETE/CONCRETEFLOOR007A")
	doc.add_box(Vector3(18, 0, -24), Vector3(19, 10, 24), "BRICK/BRICKWALL001")

	var sync = MapSceneSyncScript.new()
	sync.setup(doc, null)
	world.add_child(sync)
	sync.sync_all()

	_player = Tf2SandboxPlayerScript.new()
	world.add_child(_player)
	_player.set_active(true)
	_player.spawn_at(Vector3(0, 0.2, 0), -90.0) # facing +X toward the brick wall 18m (576u) away

	# Verify all 6 classes
	for i in range(6):
		_player.set_tf2_class(i)
		var t: Dictionary = _player.get_telemetry()
		_check(t["class_id"] == i + 1, "class %d selected (%s)" % [i + 1, t["class_name"]])

	# Test Sniper scope & Hammer-unit rangefinder
	_player.set_tf2_class(3)
	_player.handle_mouse_button(MOUSE_BUTTON_RIGHT, true)
	_check(_player.scoped and abs(_player.cam.fov - 25.0) < 0.5, "Sniper RMB scope toggled FOV 25")
	_player.handle_mouse_button(MOUSE_BUTTON_RIGHT, true)

	# Test Engineer 1100u Sentry Dome placement
	_player.set_tf2_class(4)
	_player.trigger_primary_action()
	_check(_player._sentry_node != null, "Engineer 1100u Sentry Range Dome placed")

	# Switch to Soldier, aim straight down, and prepare to Rocket-Jump!
	_player.set_tf2_class(1)
	_player.crouching = true
	_player._pitch = deg_to_rad(-82.0)
	_player._apply_look()

func _physics_process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_setup_scene()
		return false
	if _frames == 5:
		# Verify Sniper rangefinder measured ~576u to the +X brick wall before we looked down? Let's fire rocket now!
		_player.trigger_primary_action()
		_did_rocket = true
	if _did_rocket:
		_max_vy = max(_max_vy, _player.velocity.y)
	if _frames >= 35:
		print("  Soldier Rocket-Jump peak vertical velocity: %.2f m/s (%.0f u/s)" % [_max_vy, _max_vy * 32.0])
		_check(_max_vy > 9.0, "Soldier Rocket-Jump impulse launched player upward (got %.2f m/s)" % _max_vy)
		if _failed:
			print("=== MILESTONE 6 FAILED ===")
			quit(1)
		else:
			print("=== MILESTONE 6 PASSED (6 Classes + Rocket-Jump + Sniper Scope + Engi 1100u Sentry Dome!) ===")
			quit(0)
		return true
	return false
