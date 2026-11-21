extends SceneTree

## Milestone 17 & 18 Automated Verification Suite:
## Tests all Hammer++/TrenchBroom 3D CSG operations, Entity raycasting/cloning/deletion,
## Live VPK Material Swatches, Clipping (Keep Both/Front/Back), Tie to Entity,
## 90-degree Brush Rotation, Push/Pull Normal, and real Valve vbsp.exe compile (0 leaks!).

const Tf2AssetsScript    = preload("res://scripts/core/Tf2Assets.gd")
const Tf2CatalogScript   = preload("res://scripts/core/Tf2Catalog.gd")
const REPO_ROOT          := "C:/Users/steph/Documents/Git/pootis builder"

var _failed := 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [PASS] ", msg)
	else:
		printerr("  [FAIL] ", msg)
		_failed += 1

func _initialize() -> void:
	print("=== Milestone 17 & 18 Verification Suite ===")
	var core: Object = ClassDB.instantiate("Tf2Core")
	core.mount_tf2(REPO_ROOT)
	var assets := Tf2AssetsScript.new(core)
	var doc: Object = ClassDB.instantiate("Tf2MapDoc")

	# 1. Create clean test room + solid
	doc.new_map("pb_m17_test", "sky_badlands_01")
	var floor_id: int = doc.add_box(Vector3(-12, -1, -12), Vector3(12, 0, 12), "DEV/DEV_MEASUREGENERIC01")
	var wall_id: int = doc.add_box(Vector3(-4, 0, -1), Vector3(4, 4, 1), "DEV/DEV_MEASUREWALL01RED")
	doc.record_undo("Init")
	_check(floor_id == 0 and wall_id == 1, "Initial solids created (count=%d)" % doc.get_solid_count())

	# 2. Push/Pull Normal (+Y stretches height from 4m to 6m)
	var ok_pp: bool = doc.push_pull_normal(wall_id, Vector3(0, 1, 0), 2.0)
	var info_pp: Dictionary = doc.get_solid_info(wall_id)
	var h_pp: float = (info_pp["bounds_max"] as Vector3).y - (info_pp["bounds_min"] as Vector3).y
	_check(ok_pp and absf(h_pp - 6.0) < 0.05, "push_pull_normal(+Y, +2.0m) stretched wall to %.2fm" % h_pp)

	# 3. Rotate Solid 90° around Y (width 8m x depth 2m -> 2m x 8m)
	var ok_rot: bool = doc.rotate_solid_y(wall_id, 90.0)
	var info_rot: Dictionary = doc.get_solid_info(wall_id)
	var sz_rot: Vector3 = (info_rot["bounds_max"] as Vector3) - (info_rot["bounds_min"] as Vector3)
	_check(ok_rot and absf(sz_rot.x - 2.0) < 0.1 and absf(sz_rot.z - 8.0) < 0.1,
		"rotate_solid_y(90) swapped footprint cleanly to %.2fx%.2fm" % [sz_rot.x, sz_rot.z])

	# 4. Clip Solid (Keep Both = 0 splits 1 solid into 2 solids!)
	var before_cnt: int = doc.get_solid_count()
	var clip_id: int = doc.clip_solid(wall_id, Vector3(0, 3, 0), Vector3(0, 0, 1), 0)
	var after_cnt: int = doc.get_solid_count()
	_check(clip_id >= 0 and after_cnt == before_cnt + 1,
		"clip_solid(keep_both) split solid cleanly (%d -> %d solids, new=%d)" % [before_cnt, after_cnt, clip_id])

	# 5. Clip Solid (Keep Front = 1 trims without adding a solid)
	var trim_id: int = doc.clip_solid(clip_id, Vector3(0, 3, 2), Vector3(1, 0, 0), 1)
	_check(trim_id == clip_id and doc.get_solid_count() == after_cnt,
		"clip_solid(keep_front) trimmed cleanly in-place")

	# 6. Tie Solid to Entity (Ctrl+T -> func_detail / func_door)
	var s_before_tie: int = doc.get_solid_count()
	var e_before_tie: int = doc.get_entity_count()
	var tied_eid: int = doc.tie_solid_to_entity(clip_id, "func_detail", {"targetname": "detail_pillar"})
	_check(tied_eid >= 0 and doc.get_solid_count() == s_before_tie - 1 and doc.get_entity_count() == e_before_tie + 1,
		"tie_solid_to_entity(func_detail) moved brush from world to entity #%d" % tied_eid)

	# 7. Point Entity Raycast, Clone & Delete
	var prop_eid: int = doc.add_point_entity("prop_static", Vector3(5, 0, 5), {
		"model": "models/props_2fort/miningcrate001.mdl", "angles": "0 0 0", "solid": "6"
	})
	var rc_e: Dictionary = doc.raycast_entity(Vector3(5, 4, 10), Vector3(0, -3.2, -5).normalized())
	_check(rc_e.get("hit", false) and int(rc_e.get("entity_idx", -1)) == prop_eid,
		"raycast_entity accurately picked prop_static #%d (t=%.2f)" % [prop_eid, float(rc_e.get("t", -1.0))])

	var clone_eid: int = doc.duplicate_entity(prop_eid, Vector3(2, 0, 0))
	_check(clone_eid > prop_eid, "duplicate_entity cloned entity to #%d" % clone_eid)

	var del_ok: bool = doc.delete_entity(clone_eid)
	_check(del_ok, "delete_entity cleanly removed cloned entity #%d" % clone_eid)

	# 8. Delete Solid + Undo restoration
	var del_s_id: int = doc.add_box(Vector3(-8, 0, -8), Vector3(-6, 2, -6), "BRICK/BRICKWALL001")
	doc.record_undo("Before Delete")
	var cnt_pre_del: int = doc.get_solid_count()
	var ok_del_s: bool = doc.delete_solid(del_s_id)
	doc.record_undo("Delete Solid")
	_check(ok_del_s and doc.get_solid_count() == cnt_pre_del - 1, "delete_solid removed solid cleanly")
	var ok_undo: bool = doc.undo()
	_check(ok_undo and doc.get_solid_count() == cnt_pre_del, "Undo restored deleted solid cleanly")

	# 9. Verify Live VPK Swatch decoding across Dev Blockout + TF2 Catalog categories!
	var sw_ok := 0
	var sw_total := 0
	for cat in Tf2CatalogScript.MATERIAL_CATEGORIES.keys():
		for item in Tf2CatalogScript.MATERIAL_CATEGORIES[cat]:
			sw_total += 1
			var tex: Texture2D = assets.get_material_swatch(str(item["mat"]))
			if tex != null and tex.get_width() > 0:
				sw_ok += 1
	_check(sw_ok == sw_total and sw_total >= 20, "Live VPK material swatches decoded %d/%d (100%%!)" % [sw_ok, sw_total])

	# 9b. Verify 100% of 3D Prop Browser .mdl meshes load from TF2 VPKs!
	var pr_ok := 0
	var pr_total := 0
	for cat in Tf2CatalogScript.PROP_CATEGORIES.keys():
		for item in Tf2CatalogScript.PROP_CATEGORIES[cat]:
			pr_total += 1
			var mesh: ArrayMesh = assets.get_model_mesh(str(item["mdl"]))
			if mesh != null and mesh.get_surface_count() > 0:
				pr_ok += 1
	_check(pr_ok == pr_total and pr_total >= 20, "Live VPK 3D prop meshes loaded %d/%d (100%%!)" % [pr_ok, pr_total])

	# 10. Auto-seal & Compile clipped/rotated/tied VMF with REAL Valve vbsp.exe (0 leaks!)
	doc.add_point_entity("info_player_teamspawn", Vector3(-6, 0.5, 0), {"TeamNum": "2", "angles": "0 0 0"})
	doc.add_point_entity("info_player_teamspawn", Vector3(6, 0.5, 0), {"TeamNum": "3", "angles": "0 180 0"})
	doc.add_point_entity("light_environment", Vector3(0, 8, 0), {"_light": "255 245 220 400", "angles": "0 45 0", "pitch": "-45"})
	doc.auto_seal_skybox()
	var vmf_path := REPO_ROOT + "/godot/maps/pb_m17_test.vmf"
	var sv: Dictionary = doc.save_vmf(vmf_path)
	_check(sv.get("ok", false), "Saved edited/clipped/tied VMF to " + vmf_path)

	var tf2_dir: String = core.get_tf2_dir()
	var vbsp := tf2_dir.path_join("bin/x64/vbsp.exe")
	if not FileAccess.file_exists(vbsp):
		vbsp = tf2_dir.path_join("bin/vbsp.exe")
	var out_arr: Array = []
	var ec: int = OS.execute(vbsp, ["-game", tf2_dir.path_join("tf"), vmf_path], out_arr, true)
	var log_txt := "\n".join(out_arr)
	var has_leak := log_txt.find("**** leaked ****") != -1
	_check(ec == 0 and not has_leak, "Real Valve vbsp.exe compiled clipped+rotated+tied VMF cleanly (exit=%d, leak=%s)" % [ec, str(has_leak)])

	print("=== Milestone 17 & 18 Summary: %d failures ===" % _failed)
	quit(0 if _failed == 0 else 1)
