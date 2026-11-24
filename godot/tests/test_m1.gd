extends SceneTree

## Milestone 1 Gate Verification Test (non-hanging explicit exit codes)
## Proves libpootis_core.dll loads cleanly in Godot 4.7.2, mounts Steam TF2 VPKs,
## parses tf.fgd (446+ classes), discovers installed TF2 .bsp maps, and decodes
## a real TF2 VPK .vmt/.vtf texture directly into a Godot Image!

func _check(cond: bool, msg: String) -> bool:
	if not cond:
		push_error("FAIL: " + msg)
		quit(1)
		return false
	return true

func _init() -> void:
	print("=== POOTIS BUILDER 2.0 — MILESTONE 1 GATE TEST ===")
	if not _check(ClassDB.class_exists(&"Tf2Core"), "Tf2Core GDExtension class not registered!"): return
	print("[PASS] Tf2Core native C++20 GDExtension class registered in Godot 4.7.2!")

	var core = ClassDB.instantiate(&"Tf2Core")
	var repo_root := ProjectSettings.globalize_path("res://..")
	var info: Dictionary = core.mount_tf2(repo_root)
	print("Mount info: ", info)

	if not _check(info.get("ready", false) == true, "SourceFs not ready!"): return
	if not _check(int(info.get("fgd_classes", 0)) >= 400, "Expected >= 400 TF2 FGD classes!"): return
	if not _check(int(info.get("map_count", 0)) >= 1, "Expected installed TF2 .bsp maps!"): return
	if not _check(int(info.get("material_count", 0)) >= 1000, "Expected >= 1000 TF2 VMT materials!"): return
	if not _check(int(info.get("model_count", 0)) >= 500, "Expected >= 500 TF2 MDL models!"): return

	var maps: PackedStringArray = core.list_maps()
	print("[PASS] Discovered %d TF2 .bsp maps (sample: %s, %s, %s)" % [
		maps.size(),
		maps[0] if maps.size() > 0 else "",
		maps[1] if maps.size() > 1 else "",
		maps[2] if maps.size() > 2 else "",
	])

	var cp_fgd: Dictionary = core.get_fgd_class_info("team_control_point")
	if not _check(cp_fgd.get("found", false) == true, "team_control_point missing from FGD!"): return
	print("[PASS] FGD lookup team_control_point -> vars=%d inputs=%d outputs=%d" % [
		int(cp_fgd["var_count"]), int(cp_fgd["input_count"]), int(cp_fgd["output_count"])
	])

	var mat: Dictionary = core.read_material_rgba("brick/brickwall003a")
	if not _check(mat.get("ok", false) == true, "Could not decode brick/brickwall003a from VPK!"): return
	var w := int(mat["width"])
	var h := int(mat["height"])
	var rgba: PackedByteArray = mat["rgba"]
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, rgba)
	if not _check(img != null and not img.is_empty(), "Godot Image creation failed!"): return
	print("[PASS] Live VPK decode brick/brickwall003a -> %dx%d RGBA8 (%d bytes) -> Godot Image OK!" % [
		w, h, rgba.size()
	])

	print("=== MILESTONE 1 GATE PASSED (ALL CHECKS GREEN) ===")
	quit(0)
