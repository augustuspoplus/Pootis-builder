extends Node3D

## Milestone 3 Visual GPU Verification Scene:
## Loads any official Valve TF2 .bsp (default: koth_sawmill) with baked lightmaps,
## MultiMeshInstance3D static props, Pakfile textures, and real 6-face TF2 skybox!

const Tf2AssetsScript := preload("res://scripts/core/Tf2Assets.gd")
const Tf2BspLoaderScript := preload("res://scripts/core/Tf2BspLoader.gd")

var map_name := "koth_sawmill"
var shot_path := ""
var frames := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--map" and i + 1 < args.size():
			map_name = args[i + 1]
		elif args[i] == "--shot" and i + 1 < args.size():
			shot_path = args[i + 1]

	var core = ClassDB.instantiate(&"Tf2Core")
	core.mount_tf2(ProjectSettings.globalize_path("res://.."))
	var assets = Tf2AssetsScript.new(core)
	var loader = Tf2BspLoaderScript.new(core, assets)

	var res: Dictionary = loader.build_bsp_scene(map_name)
	if not res.get("ok", false):
		push_error("Failed to load BSP: " + str(res.get("error", "")))
		get_tree().quit(1)
		return

	add_child(res["node"])
	print("ShowcaseM3 loaded %s in %d ms (%d props in %d MultiMeshes, sky=%s)" % [
		res["name"], int(res["load_ms"]), int(res["props_instanced"]),
		int(res["prop_groups"]), res["skyname"]
	])

	# Real Valve 6-face TF2 skybox from the BSP's worldspawn!
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = assets.get_sky(str(res["skyname"]), 1024, 512)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.80
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.02
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	sun.light_color = Color("#fff0db")
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)

	# Frame the map's playable bounds from an elevated 3/4 overview angle!
	var pmin: Vector3 = res["play_bounds_min"]
	var pmax: Vector3 = res["play_bounds_max"]
	var center := (pmin + pmax) * 0.5
	var ext := (pmax - pmin)
	var rad: float = maxf(ext.length() * 0.36, 25.0)
	var cam := Camera3D.new()
	cam.fov = 56.0
	cam.far = 800.0
	cam.current = true
	add_child(cam)
	cam.look_at_from_position(center + Vector3(-rad * 0.65, rad * 0.48, rad * 0.65),
							  center + Vector3(0.0, -ext.y * 0.12, 0.0), Vector3.UP)

func _process(_delta: float) -> void:
	if shot_path != "":
		frames += 1
		if frames == 12:
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot_path)
			get_tree().quit()
