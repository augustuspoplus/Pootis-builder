class_name Tf2DoorController
extends Node

## Interactive TF2 func_door Slide & Proximity Controller for F5 Playtest!
## Works seamlessly on BOTH Official Valve .bsp maps (pl_upward, ctf_turbine, etc.)
## AND Custom Pootis Builder .vmf maps so spawn doors & gates smoothly slide open
## when the player walks near them and close behind them!

signal door_opened(targetname: String)

var _doors: Array = [] # [{node, closed_pos, movedir, travel_m, speed_m, trigger_pos, trigger_r, open_t, was_open, name}]

func clear() -> void:
	_doors.clear()

func register_door(node: Node3D, closed_pos: Vector3, movedir: Vector3, travel_m: float,
		speed_m: float, trigger_r: float = 4.6, targetname: String = "") -> void:
	if node == null:
		return
	var dir := movedir.normalized() if movedir.length_squared() > 0.001 else Vector3.UP
	_doors.append({
		"node": node,
		"closed_pos": closed_pos,
		"movedir": dir,
		"travel_m": maxf(1.2, travel_m),
		"speed_m": clampf(speed_m, 3.0, 24.0),
		"trigger_r": maxf(3.2, trigger_r),
		"open_t": 0.0,
		"was_open": false,
		"name": targetname,
	})

func reset_all_closed() -> void:
	for d in _doors:
		d["open_t"] = 0.0
		d["was_open"] = false
		var n: Node3D = d["node"]
		if is_instance_valid(n):
			n.position = d["closed_pos"]

func get_door_count() -> int:
	return _doors.size()

func tick(player_pos: Vector3, delta: float) -> void:
	for d in _doors:
		var n: Node3D = d["node"]
		if not is_instance_valid(n):
			continue
		var cpos: Vector3 = d["closed_pos"]
		var dist := player_pos.distance_to(cpos)
		var want_open := dist <= float(d["trigger_r"])
		var target_t := 1.0 if want_open else 0.0
		var cur_t: float = float(d["open_t"])
		var rate: float = float(d["speed_m"]) / maxf(0.5, float(d["travel_m"]))
		if cur_t < target_t:
			cur_t = minf(1.0, cur_t + rate * delta)
		elif cur_t > target_t:
			cur_t = maxf(0.0, cur_t - rate * 0.75 * delta)
		if want_open and not bool(d["was_open"]):
			d["was_open"] = true
			door_opened.emit(str(d["name"]))
		elif not want_open and cur_t <= 0.01:
			d["was_open"] = false
		d["open_t"] = cur_t
		n.position = cpos + (d["movedir"] as Vector3) * (float(d["travel_m"]) * cur_t)
