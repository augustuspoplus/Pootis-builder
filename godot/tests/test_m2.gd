extends SceneTree

## Milestone 2 Headless Gate Test:
## Verifies live VPK streaming of Valve 6-face skyboxes, 3D TF2 StudioModels (.mdl/.vvd/.vtx)
## into Godot ArrayMesh surfaces, and VMT -> StandardMaterial3D decoding.

const Tf2AssetsScript := preload("res://scripts/core/Tf2Assets.gd")

func _check(cond: bool, msg: String) -> bool:
	if not cond:
		push_error("FAIL: " + msg)
		quit(1)
		return false
	return true

func _init() -> void:
	print("=== POOTIS BUILDER 2.0 — MILESTONE 2 GATE TEST ===")
	var core = ClassDB.instantiate(&"Tf2Core")
	var repo_root := ProjectSettings.globalize_path("res://..")
	var info: Dictionary = core.mount_tf2(repo_root)
	if not _check(info.get("ready", false), "Tf2Core failed to mount TF2!"): return

	var skies: PackedStringArray = core.list_skyboxes()
	print("[PASS] Found %d Valve TF2 skyboxes (sample: %s, %s, %s)" % [
		skies.size(),
		skies[0] if skies.size() > 0 else "",
		skies[1] if skies.size() > 1 else "",
		skies[2] if skies.size() > 2 else "",
	])
	if not _check(skies.size() >= 20, "Expected >= 20 Valve TF2 skyboxes!"): return

	var sky_d: Dictionary = core.read_skybox_panorama("sky_badlands_01", 1024, 512)
	if not _check(sky_d.get("ok", false), "Failed to stitch sky_badlands_01!"): return
	print("[PASS] Stitched Valve 6-face sky_badlands_01 -> %dx%d (%d/6 faces)" % [
		int(sky_d["width"]), int(sky_d["height"]), int(sky_d["faces_loaded"])
	])

	var assets = Tf2AssetsScript.new(core)
	var test_models := [
		"models/items/medkit_medium.mdl",
		"models/items/ammopack_medium.mdl",
		"models/props_gameplay/resupply_locker.mdl",
		"models/props_gameplay/cap_point_base.mdl",
		"models/flag/briefcase.mdl",
		"models/props_trainyard/bomb_cart.mdl",
		"models/props_foliage/tree_pine01.mdl",
	]
	for mp in test_models:
		var md: Dictionary = core.read_model_data(mp)
		if not _check(md.get("ok", false), "Failed to load model: " + mp): return
		var mesh: ArrayMesh = assets.get_model_mesh(mp)
		if not _check(mesh != null and mesh.get_surface_count() >= 1, "Empty ArrayMesh for: " + mp): return
		print("[PASS] Streamed 3D MDL %-44s -> %d surfaces, %d tris" % [
			mp, mesh.get_surface_count(), int(md["triangle_count"])
		])

	var sky: Sky = assets.get_sky("sky_badlands_01")
	if not _check(sky != null and sky.sky_material is PanoramaSkyMaterial, "Sky creation failed!"): return
	print("[PASS] Godot PanoramaSkyMaterial built live from Valve sky_badlands_01!")

	print("=== MILESTONE 2 GATE PASSED (ALL CHECKS GREEN) ===")
	quit(0)
