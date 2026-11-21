extends Node3D

const Tf2AssetsScript    = preload("res://scripts/core/Tf2Assets.gd")
const Tf2BspLoaderScript = preload("res://scripts/core/Tf2BspLoader.gd")

const ART := "C:/Users/steph/.gemini/antigravity/brain/dc036b95-0d4c-4a2b-8b8a-c124bec47848"

const MAPS := [
	{"name": "cp_degrootkeep_rats", "out": "m15_degrootkeep_rats_fixed.png"},
	{"name": "cp_ambush_event",     "out": "m15_ambush_event_fixed.png"},
	{"name": "sd_doomsday",         "out": "m15_sd_doomsday_fixed.png"},
	{"name": "pl_upward",           "out": "m15_pl_upward_fixed.png"},
]

var _core: Object
var _assets: RefCounted
var _loader: RefCounted
var _bsp_root: Node3D
var _we: WorldEnvironment
var _cam: Camera3D
var _idx: int = 0
var _frames: int = 0

func _ready() -> void:
	print("=== Milestone 15: LZMA/DEFLATE Pakfile + WVT Blend + Half-Lambert Prop Audit ===")
	_core = ClassDB.instantiate("Tf2Core")
	_core.mount_tf2("C:/Users/steph/Documents/Git/pootis builder")
	_assets = Tf2AssetsScript.new(_core)
	_loader = Tf2BspLoaderScript.new(_core, _assets)

	_bsp_root = Node3D.new()
	add_child(_bsp_root)

	_we = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.68, 0.70, 0.76)
	env.ambient_light_sky_contribution = 0.55
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_we.environment = env
	add_child(_we)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.35
	sun.rotation_degrees = Vector3(-42, 35, 0)
	add_child(sun)

	_cam = Camera3D.new()
	_cam.fov = 78.0
	_cam.far = 850.0
	add_child(_cam)

	_load_map(0)

func _load_map(i: int) -> void:
	for ch in _bsp_root.get_children():
		ch.queue_free()
	var m: Dictionary = MAPS[i]
	var res: Dictionary = _loader.load_bsp_into(m["name"], _bsp_root)
	if not res.get("ok", false):
		print("  [FAIL] %s: %s" % [m["name"], str(res.get("error", ""))])
	else:
		var sky: String = str(res.get("skyname", "sky_badlands_01"))
		_we.environment.sky = _assets.get_sky(sky)
		var pmin: Vector3 = res["play_bounds_min"]
		var pmax: Vector3 = res["play_bounds_max"]
		var ctr := (pmin + pmax) * 0.5
		var sp: Vector3 = res.get("spawn_pos", ctr)
		var look_pt := Vector3(ctr.x, sp.y + 4.0, ctr.z)
		var cam_p := look_pt + Vector3(26.0, 18.0, 32.0)
		if m["name"] == "cp_degrootkeep_rats":
			# Look right at the Sandcastle Keep from the attacker spawn courtyard!
			var target_p := sp + Vector3(0.0, 4.0, -32.0)
			cam_p = sp + Vector3(14.0, 18.0, 12.0)
			look_pt = target_p
		elif m["name"] == "cp_ambush_event":
			# Look right down into the playable Ambush Event village courtyard!
			var cp_mid := Vector3(sp.x, sp.y + 2.0, sp.z)
			cam_p = cp_mid + Vector3(16.0, 14.0, -18.0)
			look_pt = cp_mid + Vector3(-10.0, 0.0, 10.0)
		_cam.look_at_from_position(cam_p, look_pt, Vector3.UP)
		print("  [%d/%d] %-22s | pak=%4d surfs=%3d props=%4d (%.2fs)" % [
			i + 1, MAPS.size(), m["name"],
			int(res.get("pak_entries", 0)), int(res.get("surface_count", 0)),
			int(res.get("prop_count", 0)), float(res.get("load_ms", 0)) / 1000.0
		])
	_frames = 0

func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 8:
		var m: Dictionary = MAPS[_idx]
		get_viewport().get_texture().get_image().save_png("%s/%s" % [ART, m["out"]])
		_idx += 1
		if _idx >= MAPS.size():
			print("=== MILESTONE 15 RENDER AUDIT COMPLETE ===")
			get_tree().quit(0)
		else:
			_load_map(_idx)
