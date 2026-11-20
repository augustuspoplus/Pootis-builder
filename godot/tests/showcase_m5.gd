extends Node3D

const Tf2AssetsScript = preload("res://scripts/core/Tf2Assets.gd")
const MapSceneSyncScript = preload("res://scripts/editor/MapSceneSync.gd")
const EntityVisualsScript = preload("res://scripts/editor/EntityVisuals.gd")
const Tf2GamemodesScript = preload("res://scripts/core/Tf2Gamemodes.gd")

var _stage: int = 0
var _frames: int = 0
var _assets: RefCounted
var _doc: Object
var _sync: Node3D
var _ents: Node3D
var _we: WorldEnvironment
var _cam: Camera3D

const SHOTS := [
	{"mode": "mvm", "pos": Vector3(-16, 18, 28), "target": Vector3(0, 2, 0), "out": "C:/Users/steph/.gemini/antigravity/brain/dc036b95-0d4c-4a2b-8b8a-c124bec47848/m5_mvm_template.png"},
	{"mode": "medieval", "pos": Vector3(-16, 17, 26), "target": Vector3(6, 3, 0), "out": "C:/Users/steph/.gemini/antigravity/brain/dc036b95-0d4c-4a2b-8b8a-c124bec47848/m5_medieval_template.png"},
	{"mode": "pl", "pos": Vector3(-18, 18, 28), "target": Vector3(4, 2, 0), "out": "C:/Users/steph/.gemini/antigravity/brain/dc036b95-0d4c-4a2b-8b8a-c124bec47848/m5_payload_template.png"},
]

func _ready() -> void:
	var core = ClassDB.instantiate("Tf2Core")
	core.mount_tf2("C:/Users/steph/Documents/Git/pootis builder")
	_assets = Tf2AssetsScript.new(core)
	_doc = ClassDB.instantiate("Tf2MapDoc")

	_sync = MapSceneSyncScript.new()
	_sync.setup(_doc, _assets)
	add_child(_sync)

	_ents = EntityVisualsScript.new()
	_ents.setup(_doc, _assets)
	add_child(_ents)

	_we = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.78
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	_we.environment = env
	add_child(_we)

	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.rotation_degrees = Vector3(-40, 35, 0)
	add_child(sun)

	_cam = Camera3D.new()
	_cam.fov = 72.0
	_cam.far = 450.0
	add_child(_cam)

	_load_stage(0)

func _load_stage(i: int) -> void:
	var s: Dictionary = SHOTS[i]
	var meta: Dictionary = Tf2GamemodesScript.build_gamemode_template(_doc, s["mode"])
	_we.environment.sky = _assets.get_sky(meta["sky"])
	_sync.clear_all()
	_sync.sync_all()
	_ents.sync_all()
	_cam.look_at_from_position(s["pos"], s["target"], Vector3.UP)
	_frames = 0

func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 8:
		var s: Dictionary = SHOTS[_stage]
		get_viewport().get_texture().get_image().save_png(s["out"])
		print("Saved M5 shot: ", s["out"])
		_stage += 1
		if _stage >= SHOTS.size():
			get_tree().quit(0)
		else:
			_load_stage(_stage)
