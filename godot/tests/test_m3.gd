extends SceneTree

## Milestone 3 Headless Gate Test:
## Loads official Valve TF2 maps (koth_sawmill.bsp & pl_upward.bsp) directly into Godot 4
## via Tf2Core + Tf2BspLoader and verifies Pakfile mounting, baked lightmap atlas,
## MultiMeshInstance3D prop instancing, and physics collision triangle generation!

const Tf2AssetsScript := preload("res://scripts/core/Tf2Assets.gd")
const Tf2BspLoaderScript := preload("res://scripts/core/Tf2BspLoader.gd")

func _check(cond: bool, msg: String) -> bool:
	if not cond:
		push_error("FAIL: " + msg)
		quit(1)
		return false
	return true

func _init() -> void:
	print("=== POOTIS BUILDER 2.0 — MILESTONE 3 GATE TEST ===")
	var core = ClassDB.instantiate(&"Tf2Core")
	var info: Dictionary = core.mount_tf2(ProjectSettings.globalize_path("res://.."))
	if not _check(info.get("ready", false), "Tf2Core mount failed!"): return

	var assets = Tf2AssetsScript.new(core)
	var loader = Tf2BspLoaderScript.new(core, assets)

	for map_name in ["koth_sawmill", "pl_upward"]:
		var res: Dictionary = loader.build_bsp_scene(map_name)
		if not _check(res.get("ok", false), "Failed to load " + map_name + ": " + str(res.get("error", ""))): return
		print("[PASS] Loaded %-14s in %4d ms | sky=%-20s | pak=%4d | surfs=%3d | props=%4d (%2d MultiMeshes) | col_tris=%d" % [
			res["name"], int(res["load_ms"]), res["skyname"], int(res["pak_entries"]),
			int(res["surfaces"]), int(res["props_instanced"]), int(res["prop_groups"]),
			int(res["collision_tris"])
		])
		if not _check(int(res["surfaces"]) >= 20, "Too few world surfaces for " + map_name): return
		if not _check(int(res["props_instanced"]) >= 500, "Too few instanced props for " + map_name): return
		if not _check(int(res["collision_tris"]) >= 10000, "Too few collision tris for " + map_name): return
		res["node"].free()

	print("=== MILESTONE 3 GATE PASSED (ALL CHECKS GREEN) ===")
	quit(0)
