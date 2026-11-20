extends Node3D

const Tf2AssetsScript = preload("res://scripts/core/Tf2Assets.gd")
const MapSceneSyncScript = preload("res://scripts/editor/MapSceneSync.gd")

var _frames: int = 0
var _out_path: String = "C:/Users/steph/.gemini/antigravity/brain/dc036b95-0d4c-4a2b-8b8a-c124bec47848/m4_csg_building_terrain.png"

func _ready() -> void:
	var core = ClassDB.instantiate("Tf2Core")
	core.mount_tf2("C:/Users/steph/Documents/Git/pootis builder")
	var assets = Tf2AssetsScript.new(core)

	var doc = ClassDB.instantiate("Tf2MapDoc")
	doc.load_vmf("C:/Users/steph/Documents/Git/pootis builder/godot/maps/pb_m4_test.vmf")

	var sync = MapSceneSyncScript.new()
	sync.setup(doc, assets)
	add_child(sync)
	sync.sync_all()
	sync.set_selection(1) # Highlight the ramp with 3D amber wireframe + face-pull handles

	# Real Valve TF2 skybox + Sun
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = assets.get_sky("sky_badlands_01")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.85)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.rotation_degrees = Vector3(-42, 38, 0)
	add_child(sun)

	var cam := Camera3D.new()
	cam.fov = 72.0
	cam.far = 400.0
	add_child(cam)
	cam.look_at_from_position(Vector3(14.0, 14.0, 22.0), Vector3(-2.0, 2.5, -2.0), Vector3.UP)

func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 8:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out_path)
		print("Saved M4 screenshot: ", _out_path)
		get_tree().quit(0)
