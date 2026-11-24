class_name Tf2Player
extends CharacterBody3D

## Instant F5 First-Person TF2 Playtest Controller
## Scale: 1 Godot meter = 32 Hammer units
## Exact TF2 metrics: 83u tall (2.59m), 68u eye (2.125m), 48u wide (1.5m),
## sv_gravity 800u/s^2 (25 m/s^2), Scout 400u/s + double jump, 48u crouch-jump!

const UPM := 32.0
const GRAVITY := 800.0 / UPM          # 25.0 m/s^2
const JUMP_VEL := 295.0 / UPM         # ~54u normal jump
const CROUCH_JUMP_VEL := 328.0 / UPM  # ~66u crouch-jump

const CLASS_NAMES := ["SCOUT (400 u/s · 2x Jump)", "SOLDIER (240 u/s)", "HEAVY (230 u/s)"]
const CLASS_SPEEDS := [400.0 / UPM, 240.0 / UPM, 230.0 / UPM]

var class_idx := 0
var air_jumps := 1
var yaw := 0.0
var pitch := 0.0
var active := false

var cam: Camera3D
var col: CollisionShape3D

func _ready() -> void:
	col = CollisionShape3D.new()
	var cap := BoxShape3D.new()
	cap.size = Vector3(48.0 / UPM, 83.0 / UPM, 48.0 / UPM)
	col.shape = cap
	col.position = Vector3(0.0, 41.5 / UPM, 0.0)
	add_child(col)

	cam = Camera3D.new()
	cam.fov = 90.0  # Classic TF2 fov_desired 90!
	cam.position = Vector3(0.0, 68.0 / UPM, 0.0)
	cam.far = 600.0
	add_child(cam)

	floor_max_angle = deg_to_rad(46.0)
	visible = false
	set_physics_process(false)

func enter_playtest(spawn_pos: Vector3, start_yaw: float) -> void:
	global_position = spawn_pos
	velocity = Vector3.ZERO
	yaw = start_yaw
	pitch = 0.0
	air_jumps = 1 if class_idx == 0 else 0
	active = true
	visible = true
	cam.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_physics_process(true)

func exit_playtest() -> void:
	active = false
	visible = false
	cam.current = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_physics_process(false)

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		yaw -= event.relative.x * 0.0024
		pitch = clamp(pitch - event.relative.y * 0.0024, -1.48, 1.48)
		rotation.y = yaw
		cam.rotation.x = pitch
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_1:
			class_idx = 0
		elif event.keycode == KEY_2:
			class_idx = 1
		elif event.keycode == KEY_3:
			class_idx = 2

func _physics_process(delta: float) -> void:
	if not active:
		return
	var crouch := Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C)
	var target_eye := (45.0 if crouch else 68.0) / UPM
	cam.position.y = lerpf(cam.position.y, target_eye, min(1.0, delta * 18.0))

	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= transform.basis.z
	if Input.is_key_pressed(KEY_S): dir += transform.basis.z
	if Input.is_key_pressed(KEY_A): dir -= transform.basis.x
	if Input.is_key_pressed(KEY_D): dir += transform.basis.x
	dir.y = 0.0
	if dir.length() > 0.001:
		dir = dir.normalized()

	var spd: float = CLASS_SPEEDS[class_idx] * (0.45 if crouch else 1.0)
	velocity.x = lerpf(velocity.x, dir.x * spd, min(1.0, delta * 14.0))
	velocity.z = lerpf(velocity.z, dir.z * spd, min(1.0, delta * 14.0))

	if is_on_floor():
		air_jumps = 1 if class_idx == 0 else 0
		if Input.is_key_pressed(KEY_SPACE):
			velocity.y = CROUCH_JUMP_VEL if crouch else JUMP_VEL
	else:
		velocity.y -= GRAVITY * delta
		if Input.is_action_just_pressed("ui_accept") and air_jumps > 0:
			velocity.y = JUMP_VEL
			air_jumps -= 1

	move_and_slide()
	if global_position.y < -20.0:
		global_position = Vector3(0.0, 2.0, 0.0)
		velocity = Vector3.ZERO
