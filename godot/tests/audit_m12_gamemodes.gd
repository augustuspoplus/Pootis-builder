extends Node3D

const Tf2AssetsScript    = preload("res://scripts/core/Tf2Assets.gd")
const Tf2BspLoaderScript = preload("res://scripts/core/Tf2BspLoader.gd")

const ART := "C:/Users/steph/.gemini/antigravity/brain/dc036b95-0d4c-4a2b-8b8a-c124bec47848"

const AUDIT_MAPS := [
	"ctf_turbine",
	"ctf_2fort",
	"koth_sawmill",
	"pl_upward",
	"plr_hightower",
	"cp_process_final",
	"cp_degrootkeep",
	"mvm_decoy",
	"arena_badlands",
	"sd_doomsday",
	"pass_brickyard",
]

var _core: Object
var _assets: RefCounted
var _loader: RefCounted
var _bsp_root: Node3D
var _we: WorldEnvironment
var _cam: Camera3D
var _idx: int = 0
var _frames: int = 0
var _passed: int = 0
var _available: Array[String] = []

func _ready() -> void:
	print("=== Milestone 12: Multi-Gamemode Official TF2 .BSP Import Audit ===")
	_core = ClassDB.instantiate("Tf2Core")
	_core.mount_tf2("C:/Users/steph/Documents/Git/pootis builder")
	_assets = Tf2AssetsScript.new(_core)
	_loader = Tf2BspLoaderScript.new(_core, _assets)

	var installed: PackedStringArray = _core.list_maps()
	for m in AUDIT_MAPS:
		if installed.has(m + ".bsp") or installed.has(m):
			_available.append(m)

	_bsp_root = Node3D.new()
	add_child(_bsp_root)

	_we = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
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

	if _available.is_empty():
		print("ERROR: No official TF2 maps found!")
		get_tree().quit(1)
		return
	_load_next(0)

func _load_next(i: int) -> void:
	for ch in _bsp_root.get_children():
		ch.queue_free()
	var mname: String = _available[i]
	var t0 := Time.get_ticks_msec()
	var res: Dictionary = _loader.load_bsp_into(mname, _bsp_root)
	var dt_s := float(Time.get_ticks_msec() - t0) / 1000.0
	if not res.get("ok", false):
		print("  [FAIL] %-18s -> %s" % [mname, str(res.get("error", ""))])
	else:
		_passed += 1
		var sky: String = str(res.get("skyname", "sky_badlands_01"))
		_we.environment.sky = _assets.get_sky(sky)
		# Place camera intelligently: inside Turbine's Mid Hall (indoor!), or scenic above play center for outdoor maps!
		var pmin: Vector3 = res["play_bounds_min"]
		var pmax: Vector3 = res["play_bounds_max"]
		var ctr := (pmin + pmax) * 0.5
		if mname == "ctf_turbine":
			# Inside Turbine's famous central Mid Hall!
			_cam.look_at_from_position(Vector3(-12.0, 5.5, 10.0), Vector3(4.0, 2.5, -2.0), Vector3.UP)
		elif mname == "ctf_2fort":
			_cam.look_at_from_position(Vector3(-18.0, 9.0, 14.0), Vector3(0.0, 2.0, 0.0), Vector3.UP)
		else:
			var sp: Vector3 = res.get("spawn_pos", ctr)
			var look_pt := Vector3(ctr.x, sp.y + 2.0, ctr.z)
			var cam_p := look_pt + Vector3(24.0, 18.0, 24.0)
			if mname == "cp_degrootkeep":
				look_pt = Vector3(ctr.x, sp.y + 3.0, ctr.z)
				cam_p = look_pt + Vector3(12.0, 14.0, 32.0)
			elif mname == "mvm_decoy":
				cam_p = Vector3(18.0, 15.0, 26.0); look_pt = Vector3(0.0, 2.0, -8.0)
			elif mname == "plr_hightower":
				look_pt = Vector3(ctr.x, sp.y + 4.0, ctr.z)
				cam_p = look_pt + Vector3(24.0, 18.0, 28.0)
			_cam.look_at_from_position(cam_p, look_pt, Vector3.UP)
		print("  [%2d/%2d] %-18s | surfs=%3d props=%4d pak=%4d sky=%-20s (%.2fs)" % [
			i + 1, _available.size(), mname,
			int(res.get("surface_count", 0)), int(res.get("prop_count", 0)),
			int(res.get("pak_entries", 0)), sky, dt_s
		])
	_frames = 0

func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 8:
		var mname: String = _available[_idx]
		var out_p := "%s/m12_%s.png" % [ART, mname]
		get_viewport().get_texture().get_image().save_png(out_p)
		_idx += 1
		if _idx >= _available.size():
			print("=== MILESTONE 12 AUDIT COMPLETE (%d/%d OFFICIAL TF2 GAMEMODE MAPS IMPORTED & RENDERED!) ===" % [_passed, _available.size()])
			get_tree().quit(0 if _passed == _available.size() else 1)
		else:
			_load_next(_idx)
