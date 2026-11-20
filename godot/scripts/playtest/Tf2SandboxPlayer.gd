class_name Tf2SandboxPlayer
extends CharacterBody3D

## Milestone 6 — Authentic 6-Class TF2 F5 Playtest Sandbox Controller.
## Exact Source TF2 physics (1.0m = 32 Hammer units):
##   Hull: 48x48x83u | Gravity: 800u/s^2 | Jump: 271u/s (48u jump / 64u crouch-jump)
##   Classes 1-6: Scout (double-jump), Soldier (working rocket-jump), Demoman (grenade/sticky),
##                Sniper (RMB scope + Hammer-unit sightline rangefinder),
##                Engineer (1100u Sentry range dome), Heavy (pacing & clearance test).

const UPM := 32.0
const GRAVITY := 800.0 / UPM          # 25.0 m/s^2
const JUMP_SPEED := 271.0 / UPM       # 8.46875 m/s
const CROUCH_EYE := 45.0 / UPM        # 1.406m
const STAND_EYE := 68.0 / UPM         # 2.125m
const SENTRY_RANGE_M := 1100.0 / UPM  # 34.375m (exact TF2 Level 1-3 Sentry radius)

const CLASSES := [
	{"id": 1, "name": "Scout",    "speed_u": 400.0, "hp": 125, "ability": "Double-Jump (Space in air)"},
	{"id": 2, "name": "Soldier",  "speed_u": 240.0, "hp": 200, "ability": "Rocket Launcher (LMB to Rocket-Jump!)"},
	{"id": 3, "name": "Demoman",  "speed_u": 280.0, "hp": 175, "ability": "Grenade Jump (LMB lobbed explosive)"},
	{"id": 4, "name": "Sniper",   "speed_u": 300.0, "hp": 125, "ability": "RMB Scope + Hammer Sightline Rangefinder"},
	{"id": 5, "name": "Engineer", "speed_u": 300.0, "hp": 125, "ability": "LMB Place 1100u Sentry Range Dome"},
	{"id": 6, "name": "Heavy",    "speed_u": 230.0, "hp": 300, "ability": "Slowest Class — Walk-Time & Door Check"},
]

signal fired_rocket(origin: Vector3)
signal exploded(pos: Vector3)
signal pickup_collected(kind: String)

var active: bool = false
var class_idx: int = 1 # 0=Scout, 1=Soldier (default!), 2=Demo, 3=Sniper, 4=Engi, 5=Heavy
var health: int = 200
var max_health: int = 200
var scoped: bool = false
var crouching: bool = false
var _double_jumped: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _fire_cd: float = 0.0
var _elapsed_run: float = 0.0
var _peak_y: float = 0.0
var _ground_y: float = 0.0
var _sightline_u: float = 0.0

var cam: Camera3D
var col_shape: CollisionShape3D
var _vfx_root: Node3D
var _sentry_node: Node3D
var _rockets: Array = [] # [{node, vel, gravity, life}]
var _flashes: Array = [] # [{node, life}]
var _triggers: Array = [] # [{kind, min, max, push_vel, target_pos}]

func _ready() -> void:
	collision_layer = 4
	collision_mask = 3 # World solids (1) + Skybox shell (2)
	floor_max_angle = deg_to_rad(46.0)
	floor_snap_length = 0.35

	col_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(48.0 / UPM, 82.0 / UPM, 48.0 / UPM)
	col_shape.shape = box
	col_shape.position = Vector3(0, 41.0 / UPM, 0)
	add_child(col_shape)

	cam = Camera3D.new()
	cam.fov = 90.0 # Classic TF2 fov_desired 90!
	cam.far = 500.0
	cam.position = Vector3(0, STAND_EYE, 0)
	add_child(cam)

	_vfx_root = Node3D.new()
	_vfx_root.name = "SandboxVFX"
	add_child(_vfx_root)
	_vfx_root.top_level = true

	set_tf2_class(1)

func spawn_at(pos: Vector3, yaw_deg: float = 0.0, entities: Array = []) -> void:
	global_position = pos + Vector3(0, 0.15, 0)
	velocity = Vector3.ZERO
	_yaw = deg_to_rad(yaw_deg)
	_pitch = 0.0
	_elapsed_run = 0.0
	_ground_y = global_position.y
	_peak_y = global_position.y
	scoped = false
	_double_jumped = false
	_build_sandbox_triggers(entities)
	_apply_look()

func set_active(on: bool) -> void:
	active = on
	visible = on
	if cam != null:
		cam.current = on
	if not on:
		scoped = false
		if _sentry_node != null and is_instance_valid(_sentry_node):
			_sentry_node.queue_free()
			_sentry_node = null

func set_tf2_class(idx: int) -> void:
	class_idx = clamp(idx, 0, CLASSES.size() - 1)
	max_health = int(CLASSES[class_idx]["hp"])
	health = max_health
	scoped = false
	_fire_cd = 0.0
	if cam != null:
		cam.fov = 90.0

func get_class_info() -> Dictionary:
	return CLASSES[class_idx]

func get_telemetry() -> Dictionary:
	var hspeed := Vector2(velocity.x, velocity.z).length() * UPM
	return {
		"class_id": CLASSES[class_idx]["id"],
		"class_name": CLASSES[class_idx]["name"],
		"ability": CLASSES[class_idx]["ability"],
		"hp": health,
		"max_hp": max_health,
		"speed_u": int(round(hspeed)),
		"on_floor": is_on_floor(),
		"crouching": crouching,
		"scoped": scoped,
		"jump_height_u": int(round(max(0.0, (_peak_y - _ground_y) * UPM))),
		"sightline_u": int(round(_sightline_u)),
		"sightline_warn": _sightline_u > 2048.0,
		"run_time_s": _elapsed_run,
		"pos_u": global_position * UPM,
	}

func handle_mouse_motion(rel: Vector2, sens: float = 0.0024) -> void:
	if not active:
		return
	var s := sens * (0.35 if scoped else 1.0)
	_yaw -= rel.x * s
	_pitch = clamp(_pitch - rel.y * s, deg_to_rad(-88.0), deg_to_rad(88.0))
	_apply_look()

func handle_key_press(keycode: int) -> void:
	if not active:
		return
	match keycode:
		KEY_1: set_tf2_class(0)
		KEY_2: set_tf2_class(1)
		KEY_3: set_tf2_class(2)
		KEY_4: set_tf2_class(3)
		KEY_5: set_tf2_class(4)
		KEY_6: set_tf2_class(5)

func handle_mouse_button(button: int, pressed: bool) -> void:
	if not active:
		return
	if button == MOUSE_BUTTON_LEFT and pressed:
		trigger_primary_action()
	elif button == MOUSE_BUTTON_RIGHT and pressed and class_idx == 3:
		scoped = not scoped
		if cam != null:
			cam.fov = 25.0 if scoped else 90.0

func trigger_primary_action() -> void:
	if _fire_cd > 0.0:
		return
	var origin := cam.global_position + (-cam.global_transform.basis.z) * 0.65
	var fwd := -cam.global_transform.basis.z
	if class_idx == 1: # Soldier Rocket Launcher!
		_fire_projectile(origin, fwd * (1100.0 / UPM), 0.0, Color(1.0, 0.55, 0.15))
		_fire_cd = 0.72
		fired_rocket.emit(origin)
	elif class_idx == 2: # Demoman Grenade/Sticky!
		_fire_projectile(origin, fwd * (880.0 / UPM) + Vector3(0, 4.5, 0), GRAVITY * 0.85, Color(0.85, 0.25, 0.20))
		_fire_cd = 0.60
		fired_rocket.emit(origin)
	elif class_idx == 4: # Engineer Sentry 1100u Range Dome!
		_place_sentry_preview()
		_fire_cd = 0.35

func _physics_process(delta: float) -> void:
	if not active:
		return
	_elapsed_run += delta
	if _fire_cd > 0.0:
		_fire_cd = max(0.0, _fire_cd - delta)

	# Crouch + eye height
	crouching = Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_C)
	if cam != null:
		var target_eye := CROUCH_EYE if crouching else STAND_EYE
		cam.position.y = lerpf(cam.position.y, target_eye, clamp(delta * 16.0, 0.0, 1.0))

	# Movement input
	var inp := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): inp.y += 1.0
	if Input.is_key_pressed(KEY_S): inp.y -= 1.0
	if Input.is_key_pressed(KEY_D): inp.x += 1.0
	if Input.is_key_pressed(KEY_A): inp.x -= 1.0
	if inp.length() > 1.0:
		inp = inp.normalized()

	var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	var wish_dir := (fwd * inp.y + right * inp.x)
	if wish_dir.length() > 0.001:
		wish_dir = wish_dir.normalized()

	var max_spd := (float(CLASSES[class_idx]["speed_u"]) / UPM) * (0.38 if crouching else (0.32 if scoped else 1.0))

	if is_on_floor():
		_double_jumped = false
		_ground_y = global_position.y
		_peak_y = global_position.y
		# Source ground friction + crisp acceleration
		var hvel := Vector3(velocity.x, 0, velocity.z)
		hvel = hvel.move_toward(wish_dir * max_spd, max_spd * 12.0 * delta)
		velocity.x = hvel.x
		velocity.z = hvel.z
		if Input.is_key_pressed(KEY_SPACE):
			velocity.y = JUMP_SPEED * (1.12 if crouching else 1.0)
	else:
		# Authentic Source air-strafing!
		var cur_proj := Vector3(velocity.x, 0, velocity.z).dot(wish_dir)
		var air_cap := minf(max_spd, 30.0 / UPM * 3.5)
		var add_spd := air_cap - cur_proj
		if add_spd > 0.0:
			var accel := minf(add_spd, 14.0 * max_spd * delta)
			velocity.x += wish_dir.x * accel
			velocity.z += wish_dir.z * accel
		velocity.y -= GRAVITY * delta
		# Scout mid-air double jump!
		if class_idx == 0 and not _double_jumped and Input.is_action_just_pressed("ui_accept"):
			velocity.y = JUMP_SPEED * 1.04
			_double_jumped = true
		_peak_y = max(_peak_y, global_position.y)

	move_and_slide()
	_process_triggers()
	_step_projectiles(delta)
	_update_sightline_rangefinder()

func _apply_look() -> void:
	if cam != null:
		cam.rotation = Vector3(_pitch, _yaw, 0)

func _fire_projectile(origin: Vector3, vel: Vector3, grav: float, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mi.material_override = mat
	mi.position = origin
	_vfx_root.add_child(mi)
	_rockets.append({"node": mi, "vel": vel, "gravity": grav, "life": 3.0})

func _step_projectiles(delta: float) -> void:
	var space := get_world_3d().direct_space_state
	var i := _rockets.size() - 1
	while i >= 0:
		var r: Dictionary = _rockets[i]
		r["life"] = float(r["life"]) - delta
		var vel: Vector3 = r["vel"]
		vel.y -= float(r["gravity"]) * delta
		r["vel"] = vel
		var n: Node3D = r["node"]
		var from_p := n.global_position
		var to_p := from_p + vel * delta
		var q := PhysicsRayQueryParameters3D.create(from_p, to_p, 3)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() or float(r["life"]) <= 0.0:
			var exp_pos: Vector3 = hit["position"] if not hit.is_empty() else to_p
			_explode_at(exp_pos)
			n.queue_free()
			_rockets.remove_at(i)
		else:
			n.global_position = to_p
		i -= 1

	var j := _flashes.size() - 1
	while j >= 0:
		var f: Dictionary = _flashes[j]
		f["life"] = float(f["life"]) - delta
		var fn: Node3D = f["node"]
		fn.scale = Vector3.ONE * (1.0 + (0.28 - float(f["life"])) * 7.0)
		if float(f["life"]) <= 0.0:
			fn.queue_free()
			_flashes.remove_at(j)
		j -= 1

func _explode_at(pos: Vector3) -> void:
	# Authentic TF2 splash Rocket-Jump impulse! (radius ~146u = 4.56m)
	var player_center := global_position + Vector3(0, 1.1, 0)
	var diff := player_center - pos
	var dist := diff.length()
	var splash_r := 146.0 / UPM
	if dist < splash_r:
		var falloff := clampf(1.0 - (dist / splash_r) * 0.5, 0.35, 1.0)
		var dir := diff.normalized() if dist > 0.05 else Vector3.UP
		# Classic TF2 rocket jump launches ~580-720 u/s (huge upward + horizontal boost!)
		var impulse_u := (660.0 if crouching else 520.0) * falloff
		velocity += dir * (impulse_u / UPM)
		velocity.y = max(velocity.y, (460.0 if crouching else 340.0) / UPM)
		health = max(25, health - int(round(32.0 * falloff)))
	exploded.emit(pos)

	var fl := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.55
	fl.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.62, 0.16, 0.72)
	fl.material_override = mat
	fl.position = pos
	_vfx_root.add_child(fl)
	_flashes.append({"node": fl, "life": 0.28})

func _place_sentry_preview() -> void:
	var space := get_world_3d().direct_space_state
	var from_p := cam.global_position
	var to_p := from_p + (-cam.global_transform.basis.z) * 12.0
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from_p, to_p, 1))
	var pos: Vector3 = hit["position"] if not hit.is_empty() else (global_position + (-cam.global_transform.basis.z) * 3.0)

	if _sentry_node != null and is_instance_valid(_sentry_node):
		_sentry_node.queue_free()

	_sentry_node = Node3D.new()
	_sentry_node.position = pos

	# Translucent 1100u TF2 Sentry Range Sphere!
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = SENTRY_RANGE_M
	sm.height = SENTRY_RANGE_M * 2.0
	dome.mesh = sm
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dmat.albedo_color = Color(0.95, 0.28, 0.18, 0.12)
	dome.material_override = dmat
	_sentry_node.add_child(dome)

	# Sentry pedestal core
	var core := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.1, 1.3, 1.1)
	core.mesh = bm
	core.position = Vector3(0, 0.65, 0)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.88, 0.28, 0.20)
	core.material_override = cmat
	_sentry_node.add_child(core)

	_vfx_root.add_child(_sentry_node)

func _update_sightline_rangefinder() -> void:
	if cam == null:
		return
	var space := get_world_3d().direct_space_state
	var from_p := cam.global_position
	var to_p := from_p + (-cam.global_transform.basis.z) * 250.0
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from_p, to_p, 3))
	if not hit.is_empty():
		_sightline_u = from_p.distance_to(hit["position"]) * UPM
	else:
		_sightline_u = 0.0

func _build_sandbox_triggers(entities: Array) -> void:
	_triggers.clear()
	var targets := {}
	for e in entities:
		var tname: String = str(e["kv"].get("targetname", ""))
		if not tname.is_empty():
			targets[tname] = e["pos"]
	for e in entities:
		var cls: String = str(e["classname"])
		if cls == "trigger_push" and e.get("is_brush", false):
			var spd := float(str(e["kv"].get("speed", "700"))) / UPM
			_triggers.append({"kind": "push", "min": e["bounds_min"], "max": e["bounds_max"], "push_vel": Vector3(0, spd, 0)})
		elif cls == "trigger_teleport" and e.get("is_brush", false):
			var tgt: String = str(e["kv"].get("target", ""))
			if targets.has(tgt):
				_triggers.append({"kind": "teleport", "min": e["bounds_min"], "max": e["bounds_max"], "target_pos": targets[tgt]})
		elif cls.begins_with("item_healthkit"):
			_triggers.append({"kind": "health", "pos": e["pos"]})

func _process_triggers() -> void:
	var p := global_position + Vector3(0, 1.0, 0)
	for tr in _triggers:
		var kind: String = tr["kind"]
		if kind == "push":
			var mn: Vector3 = tr["min"]
			var mx: Vector3 = tr["max"]
			if p.x >= mn.x and p.x <= mx.x and p.y >= mn.y and p.y <= mx.y and p.z >= mn.z and p.z <= mx.z:
				velocity.y = max(velocity.y, (tr["push_vel"] as Vector3).y)
		elif kind == "teleport":
			var mn: Vector3 = tr["min"]
			var mx: Vector3 = tr["max"]
			if p.x >= mn.x and p.x <= mx.x and p.y >= mn.y and p.y <= mx.y and p.z >= mn.z and p.z <= mx.z:
				global_position = (tr["target_pos"] as Vector3) + Vector3(0, 0.25, 0)
				velocity = Vector3.ZERO
		elif kind == "health" and health < max_health:
			if p.distance_to(tr["pos"]) < 1.5:
				health = max_health
				pickup_collected.emit("health")
