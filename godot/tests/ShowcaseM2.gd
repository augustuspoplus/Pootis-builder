extends Node3D

## Milestone 2 Visual GPU Verification Scene:
## Renders REAL 3D TF2 .mdl props streamed live from VPKs on a real Badlands floor
## under Valve's REAL 6-face sky_badlands_01 skybox with Godot 4 Forward+ 4K shadows & SSAO!

const Tf2AssetsScript := preload("res://scripts/core/Tf2Assets.gd")

var shot_path := ""
var frames := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--shot" and i + 1 < args.size():
			shot_path = args[i + 1]

	var core = ClassDB.instantiate(&"Tf2Core")
	core.mount_tf2(ProjectSettings.globalize_path("res://.."))
	var assets = Tf2AssetsScript.new(core)

	# 1. Real Valve TF2 6-face sky_badlands_01 Skybox + SSAO + ACES
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = assets.get_sky("sky_badlands_01", 2048, 1024)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.78
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.05
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.5
	we.environment = env
	add_child(we)

	# 2. Warm TF2 Badlands directional sunlight casting 4K soft shadows
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-36.0, -42.0, 0.0)
	sun.light_color = Color("#ffe6c4")
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_blur = 1.4
	add_child(sun)

	# 3. Ground & back wall textured directly from TF2 VPKs
	var floor_mi := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(28.0, 0.5, 22.0)
	floor_mi.mesh = fbox
	floor_mi.position = Vector3(0, -0.25, 0)
	floor_mi.material_override = assets.get_material("concrete/concretefloor002", true)
	add_child(floor_mi)

	var wall_mi := MeshInstance3D.new()
	var wbox := BoxMesh.new()
	wbox.size = Vector3(16.0, 4.5, 0.75)
	wall_mi.mesh = wbox
	wall_mi.position = Vector3(0, 2.25, -5.5)
	wall_mi.material_override = assets.get_material("brick/brickwall003a", true)
	add_child(wall_mi)

	# 4. Real 3D TF2 .mdl props streamed live from VPKs!
	add_child(assets.spawn_prop("models/props_trainyard/bomb_cart.mdl",      Vector3(-3.8, 0.9, -0.4), Vector3(0,  28, 0)))
	add_child(assets.spawn_prop("models/props_gameplay/resupply_locker.mdl", Vector3( 0.0, 0.0, -4.4), Vector3(0,   0, 0)))
	add_child(assets.spawn_prop("models/props_gameplay/cap_point_base.mdl",  Vector3( 0.5, 0.0,  1.2), Vector3(0,   0, 0)))
	add_child(assets.spawn_prop("models/items/medkit_medium.mdl",            Vector3( 3.2, 0.0,  1.8), Vector3(0, -25, 0)))
	add_child(assets.spawn_prop("models/items/ammopack_medium.mdl",          Vector3( 4.6, 0.0,  1.4), Vector3(0,  20, 0)))
	add_child(assets.spawn_prop("models/flag/briefcase.mdl",                 Vector3( 0.5, 0.55, 1.2), Vector3(0,  35, 0)))
	add_child(assets.spawn_prop("models/props_foliage/tree_pine01.mdl",      Vector3(-7.5, 0.0, -5.5), Vector3(0,  15, 0)))
	add_child(assets.spawn_prop("models/props_2fort/miningcrate001.mdl",     Vector3( 4.8, 0.0, -3.5), Vector3(0, -18, 0)))

	# 5. Hero 3/4 camera framing both props and the real Valve sky_badlands_01 horizon!
	var cam := Camera3D.new()
	cam.fov = 52.0
	cam.current = true
	add_child(cam)
	cam.look_at_from_position(Vector3(3.2, 3.4, 8.6), Vector3(-0.2, 1.5, -1.5), Vector3.UP)

func _process(_delta: float) -> void:
	if shot_path != "":
		frames += 1
		if frames == 12:
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot_path)
			get_tree().quit()
