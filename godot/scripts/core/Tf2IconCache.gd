class_name Tf2IconCache
extends Node

## Non-Blocking Live 3D TF2 Game-Asset Icon Baker & Persistent Disk Cache!
## Renders REAL transparent 3D studio thumbnails straight from Valve's .mdl files
## in TF2 VPKs, saves them to user://icon_cache/, and notifies UI tiles immediately!

signal icon_ready(key: String, tex: Texture2D)

const Tf2IconBakerScript = preload("res://scripts/core/Tf2IconBaker.gd")
const CACHE_DIR := "user://tf2_icon_cache_v2"

# Exact canonical camera framing per iconic TF2 model so every icon shows its iconic front!
const ICON_SPECS := {
	"spawn_red":       {"mdl": "models/player/engineer.mdl",              "rot": Vector3(90, -24, 0),  "pitch": 10.0},
	"spawn_blu":       {"mdl": "models/player/soldier.mdl",               "rot": Vector3(90, 24, 0),   "pitch": 10.0},
	"bot_spawn":       {"mdl": "models/player/heavy.mdl",                 "rot": Vector3(90, -20, 0),  "pitch": 10.0},
	"bomb_cart":       {"mdl": "models/props_trainyard/bomb_cart.mdl",    "rot": Vector3(0, -42, 0),   "pitch": 20.0},
	"health_med":      {"mdl": "models/items/medkit_medium.mdl",          "rot": Vector3(0, 140, 0),   "pitch": 34.0},
	"health_small":    {"mdl": "models/items/medkit_small.mdl",           "rot": Vector3(0, 140, 0),   "pitch": 32.0},
	"health_full":     {"mdl": "models/items/medkit_large.mdl",           "rot": Vector3(0, 140, 0),   "pitch": 28.0},
	"ammo_med":        {"mdl": "models/items/ammopack_medium.mdl",        "rot": Vector3(0, -38, 0),   "pitch": 22.0},
	"ammo_small":      {"mdl": "models/items/ammopack_small.mdl",         "rot": Vector3(0, -38, 0),   "pitch": 22.0},
	"ammo_full":       {"mdl": "models/items/ammopack_large.mdl",         "rot": Vector3(0, -38, 0),   "pitch": 22.0},
	"resupply":        {"mdl": "models/props_gameplay/resupply_locker.mdl","rot": Vector3(0, -24, 0),  "pitch": 14.0},
	"cap_point":       {"mdl": "models/props_gameplay/cap_point_base.mdl","rot": Vector3(0, -35, 0),   "pitch": 42.0},
	"intel":           {"mdl": "models/flag/briefcase.mdl",               "rot": Vector3(0, -38, 0),   "pitch": 24.0},
	"mvm_hatch":       {"mdl": "models/props_mvm/mann_hatch.mdl",         "rot": Vector3(0, -35, 0),   "pitch": 52.0},
	"upgrade_station": {"mdl": "models/props_mvm/mvm_upgrade_center.mdl", "rot": Vector3(0, -118, 0),  "pitch": 16.0},
	"sentry":          {"mdl": "models/buildables/sentry1.mdl",           "rot": Vector3(0, -35, 0),   "pitch": 20.0},
	"dispenser":       {"mdl": "models/buildables/dispenser.mdl",         "rot": Vector3(0, -32, 0),   "pitch": 18.0},
	"light":           {"mdl": "models/props_lights/lamp001.mdl",         "rot": Vector3(0, -38, 0),   "pitch": 20.0},
	"path_node":       {"mdl": "models/props_mining/track_arc_90degree_128.mdl","rot": Vector3(0, -35, 0), "pitch": 44.0},
	"crate":           {"mdl": "models/props_2fort/miningcrate001.mdl",   "rot": Vector3(0, -38, 0),   "pitch": 22.0},
	"barrel":          {"mdl": "models/props_farm/wooden_barrel.mdl",     "rot": Vector3(0, -35, 0),   "pitch": 20.0},
	"hay":             {"mdl": "models/props_farm/haypile001.mdl",        "rot": Vector3(0, -35, 0),   "pitch": 24.0},
	"console":         {"mdl": "models/props_spytech/control_room_console01.mdl", "rot": Vector3(0, -38, 0), "pitch": 22.0},
	"computer":        {"mdl": "models/props_spytech/computer_wall02.mdl","rot": Vector3(0, -28, 0),   "pitch": 16.0},
	"pine":            {"mdl": "models/props_foliage/tree_pine01.mdl",    "rot": Vector3(0, -35, 0),   "pitch": 14.0},
	"rock":            {"mdl": "models/props_nature/rock_worn001.mdl",    "rot": Vector3(0, -35, 0),   "pitch": 22.0},
	"oil_drum":        {"mdl": "models/props_badlands/barrel01.mdl",      "rot": Vector3(0, -35, 0),   "pitch": 20.0},
	"vent":            {"mdl": "models/props_spytech/vent_system_vent01.mdl", "rot": Vector3(0, -38, 0), "pitch": 24.0},
}

var assets: RefCounted
var icon_size: int = 160
var paused: bool = false         # Paused during camera orbit/drag so editor FPS stays rock-solid!
var _cache: Dictionary = {}      # key -> Texture2D
var _failed: Dictionary = {}     # key -> true (negative cache so missing models are never re-queued!)
var _queue: Array = []           # [{key, mdl, rot, pitch}]
var _queued_keys: Dictionary = {}
var _studio: Dictionary = {}
var _active_job: Dictionary = {}
var _wait_frames: int = 0
var _cooldown_frames: int = 0
var _worker_task_id: int = -1
var _worker_raw_result: Dictionary = {}
var _worker_mutex := Mutex.new()

func setup(p_assets: RefCounted, p_size: int = 160) -> void:
	assets = p_assets
	icon_size = clampi(p_size, 96, 256)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CACHE_DIR))
	if _studio.is_empty():
		_studio = Tf2IconBakerScript.create_studio_viewport(icon_size)
		add_child(_studio["viewport"])
	# Pre-queue all core TF2 gameplay & prop icons (loads instantly from disk if cached!)
	for k in ICON_SPECS.keys():
		get_icon(k)

func is_busy() -> bool:
	return not _queue.is_empty() or not _active_job.is_empty()

func clear_disk_cache() -> void:
	_cache.clear()
	_failed.clear()
	_queue.clear()
	_queued_keys.clear()
	_active_job.clear()
	var dir := DirAccess.open(CACHE_DIR)
	if dir != null:
		dir.list_dir_begin()
		var fn := dir.get_next()
		while not fn.is_empty():
			if fn.ends_with(".png"):
				dir.remove(fn)
			fn = dir.get_next()
		dir.list_dir_end()
	for k in ICON_SPECS.keys():
		get_icon(k)

func _disk_path(key: String) -> String:
	var safe := key.replace("/", "_").replace("\\", "_").replace(":", "_").replace(".", "_")
	return CACHE_DIR.path_join("%s_%d.png" % [safe, icon_size])

func get_icon(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	if _failed.has(key):
		return null
	var dp := _disk_path(key)
	if FileAccess.file_exists(dp):
		var img := Image.new()
		if img.load(dp) == OK:
			var tex := ImageTexture.create_from_image(img)
			_cache[key] = tex
			return tex
	if ICON_SPECS.has(key):
		var sp: Dictionary = ICON_SPECS[key]
		queue_model_icon(key, sp["mdl"], sp["rot"], float(sp["pitch"]))
	elif key.to_lower().ends_with(".mdl"):
		queue_model_icon(key, key, Vector3(0, -38, 0), 22.0)
	return null

func queue_model_icon(key: String, mdl_path: String, rot_deg: Vector3 = Vector3(0, -38, 0), pitch_deg: float = 22.0) -> void:
	if _cache.has(key) or _failed.has(key) or _queued_keys.has(key):
		return
	if DisplayServer.get_name() == "headless":
		return
	_queued_keys[key] = true
	_queue.append({"key": key, "mdl": mdl_path, "rot": rot_deg, "pitch": pitch_deg})

func _process(_delta: float) -> void:
	if assets == null or _studio.is_empty():
		return
	if paused and _active_job.is_empty():
		return
	if _cooldown_frames > 0:
		_cooldown_frames -= 1
		return
	if _active_job.is_empty():
		if _queue.is_empty():
			return
		_active_job = _queue.pop_front()
		var mdl_path := str(_active_job["mdl"])
		if assets.has_cached_model(mdl_path):
			_worker_task_id = -1
			_active_job["stage"] = "mount"
		else:
			# Offload VPK/MDL/VTX/VVD parsing to background WorkerThreadPool so main thread NEVER stalls!
			_active_job["stage"] = "decode"
			var core_ref: Object = assets.core
			_worker_task_id = WorkerThreadPool.add_task(func():
				var raw: Dictionary = core_ref.read_model_data(mdl_path) if core_ref != null else {}
				_worker_mutex.lock()
				_worker_raw_result = raw
				_worker_mutex.unlock()
			)
		return

	if str(_active_job.get("stage", "")) == "decode":
		if _worker_task_id != -1 and not WorkerThreadPool.is_task_completed(_worker_task_id):
			return
		if _worker_task_id != -1:
			WorkerThreadPool.wait_for_task_completion(_worker_task_id)
			_worker_task_id = -1
		_worker_mutex.lock()
		var raw_d := _worker_raw_result
		_worker_raw_result = {}
		_worker_mutex.unlock()
		assets.build_model_from_raw(str(_active_job["mdl"]), raw_d)
		_active_job["stage"] = "mount"
		return

	if str(_active_job.get("stage", "")) == "mount":
		var mesh: ArrayMesh = assets.get_model_mesh(str(_active_job["mdl"]))
		if mesh == null:
			_failed[str(_active_job["key"])] = true
			_queued_keys.erase(_active_job["key"])
			_active_job.clear()
			return
		var holder: MeshInstance3D = _studio["mesh_node"]
		var cam: Camera3D = _studio["camera"]
		holder.mesh = mesh
		holder.rotation_degrees = _active_job["rot"]
		var aabb := mesh.get_aabb()
		var center := aabb.position + aabb.size * 0.5
		var b := Basis.from_euler(holder.rotation)
		holder.position = -(b * center)
		var radius := maxf(aabb.size.length() * 0.48, 0.45)
		var dist := maxf(radius / sin(deg_to_rad(cam.fov * 0.5)) * 1.06, 0.55)
		var pr := deg_to_rad(float(_active_job["pitch"]))
		cam.look_at_from_position(Vector3(0.0, sin(pr) * dist, cos(pr) * dist), Vector3.ZERO, Vector3.UP)
		_wait_frames = 0
		_active_job["stage"] = "capture"
		return

	_wait_frames += 1
	if _wait_frames >= 3:
		var vp: SubViewport = _studio["viewport"]
		var img := vp.get_texture().get_image()
		var key: String = str(_active_job["key"])
		if img != null and img.get_width() > 0:
			img.save_png(_disk_path(key))
			var tex := ImageTexture.create_from_image(img)
			_cache[key] = tex
			icon_ready.emit(key, tex)
		_queued_keys.erase(key)
		_active_job.clear()
		_cooldown_frames = 2
