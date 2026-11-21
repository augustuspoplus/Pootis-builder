extends SceneTree

## Comprehensive 5-Phase Engine + BSP + FGD + Cliff/Wall/Door Automated Verification Suite!

const Tf2AssetsScript    = preload("res://scripts/core/Tf2Assets.gd")
const Tf2BspLoaderScript = preload("res://scripts/core/Tf2BspLoader.gd")
const Tf2DoorCtrlScript  = preload("res://scripts/core/Tf2DoorController.gd")
const REPO_ROOT          := "C:/Users/steph/Documents/Git/pootis builder"

var _failed := 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [PASS] ", msg)
	else:
		printerr("  [FAIL] ", msg)
		_failed += 1

func _initialize() -> void:
	print("=== Pootis Builder 2.0 — 5-Phase Engine Overhaul Verification ===")
	var core: Object = ClassDB.instantiate("Tf2Core")
	var mount: Dictionary = core.mount_tf2(REPO_ROOT)
	_check(mount.get("ready", false), "TF2 VPKs + ABS Resource Packs mounted")
	_check(int(mount.get("material_count", 0)) > 15000, "All TF2 materials indexed (%d)" % int(mount.get("material_count", 0)))
	_check(int(mount.get("model_count", 0)) > 4000, "All TF2 models indexed (%d)" % int(mount.get("model_count", 0)))

	# 1. Verify ABS_MRP_Improved_FGD.vpk + tf-abs.fgd merged SmartEdit metadata!
	var engy_mdl: Dictionary = core.read_model_data("models/editor-abs/dev_engy.mdl")
	_check(engy_mdl.get("ok", false), "ABS_MRP_Improved_FGD.vpk mounted -> dev_engy.mdl loaded cleanly!")

	var pts: PackedStringArray = core.list_fgd_point_classes("")
	var slds: PackedStringArray = core.list_fgd_solid_classes("")
	_check(pts.size() >= 250 and slds.size() >= 90, "All FGD classes exposed (%d point, %d solid)" % [pts.size(), slds.size()])

	var cp_fgd: Dictionary = core.get_fgd_class_info("team_control_point")
	_check(cp_fgd.get("found", false) and (cp_fgd.get("vars", []) as Array).size() >= 5 and (cp_fgd.get("outputs", []) as Array).size() >= 2,
		"SmartEdit FGD metadata returned for team_control_point (vars=%d, outputs=%d)" % [
			(cp_fgd.get("vars", []) as Array).size(), (cp_fgd.get("outputs", []) as Array).size()
		])

	var mod_search: PackedStringArray = core.search_models("barrel", 30)
	var mat_search: PackedStringArray = core.search_materials("blend", 30)
	_check(mod_search.size() >= 10 and mat_search.size() >= 10,
		"Full VPK Search working (barrel models=%d, blend materials=%d)" % [mod_search.size(), mat_search.size()])

	# 2. Verify Phase 4: pl_upward.bsp dynamic props (Payload Cart + Cap Points) & interactive func_door!
	var assets := Tf2AssetsScript.new(core)
	var loader := Tf2BspLoaderScript.new(core, assets)
	var dctrl := Tf2DoorCtrlScript.new()
	var bsp_parent := Node3D.new()
	root.add_child(dctrl)
	root.add_child(bsp_parent)

	var upward_data: Dictionary = core.load_bsp_data("pl_upward.bsp")
	_check(upward_data.get("ok", false), "Loaded pl_upward.bsp cleanly")
	var prop_groups: Dictionary = upward_data.get("prop_groups", {})
	var has_cap_or_cart := false
	for k in prop_groups.keys():
		var ks := str(k).to_lower()
		if ks.find("bomb_cart") != -1 or ks.find("cap_point") != -1 or ks.find("cappoint") != -1 or ks.find("resupply") != -1:
			has_cap_or_cart = true
			print("    [pl_upward dynamic/gameplay prop found]: ", ks, " x", (prop_groups[k] as Array).size())
	_check(has_cap_or_cart, "pl_upward.bsp includes dynamic Payload Cart / Capture Point / Resupply props!")

	var up_res: Dictionary = loader.load_bsp_into("pl_upward.bsp", bsp_parent, dctrl)
	var door_cnt: int = dctrl.get_door_count()
	_check(up_res.get("ok", false) and door_cnt >= 4, "pl_upward.bsp separated %d interactive sliding func_door(s)!" % door_cnt)

	# Simulate player walking right up to Door #0 and verify it slides open!
	if door_cnt > 0:
		var d0: Dictionary = dctrl._doors[0]
		var closed_p: Vector3 = d0["closed_pos"]
		var door_node: Node3D = d0["node"]
		for _step in range(30):
			dctrl.tick(closed_p + Vector3(0.5, 0, 0.5), 0.05)
		var moved_dist := door_node.position.distance_to(closed_p)
		_check(moved_dist > 1.0, "F5 Interactive Door #0 slid open smoothly by %.2fm (%.0fu)!" % [moved_dist, moved_dist * 32.0])

	# 3. Verify Phase 3: Angled Wall Chain, Make Hollow, Vertex Edit, Vertical Cliff Wall, Alpha Paint, Sew, Subdivide, UV, Alt+P!
	var doc: Object = ClassDB.instantiate("Tf2MapDoc")
	doc.new_map("pb_overhaul_test", "sky_badlands_01")
	doc.add_box(Vector3(-16, -1, -16), Vector3(16, 0, 16), "NATURE/DIRTGROUND001")

	var w45: int = doc.add_wall_segment(Vector3(-6, 0, -4), Vector3(2, 0, 4), 4.5, 0.75, "WOOD/WOOD_WALL007")
	_check(w45 >= 0, "add_wall_segment created 45-degree angled wall brush #%d" % w45)

	var room_box: int = doc.add_box(Vector3(4, 0, -6), Vector3(10, 4.5, 0), "BRICK/BRICKWALL001")
	var hol: PackedInt32Array = doc.make_hollow(room_box, -0.5)
	_check(hol.size() == 6, "make_hollow converted solid into %d sealed room walls!" % hol.size())

	var vtest: int = doc.add_box(Vector3(-10, 0, 4), Vector3(-6, 3, 8), "CONCRETE/CONCRETEWALL001A")
	var verts: PackedVector3Array = doc.get_solid_vertices(vtest)
	var v_ok: bool = verts.size() == 8 and doc.move_solid_vertex(vtest, 0, Vector3(0.5, 0, 0))
	_check(v_ok, "Vertex Manipulation (Shift+V) extracted %d corners & moved vertex cleanly!" % verts.size())

	var cliff_id: int = doc.make_cliff_wall(Vector3(-14, 0, -14), Vector3(14, 0, -14), 8.0, 2.0, 3, "NATURE/ROCKGROUND004", 0.85)
	_check(cliff_id >= 0 and doc.get_solid_info(cliff_id).get("is_disp", false),
		"make_cliff_wall created stratified vertical Power-3 displacement cliff #%d!" % cliff_id)

	var sc_n: int = doc.sculpt_terrain_ex(Vector3(0, 4, -13), 5.0, 0.6, 0, 0) # Face Normal raise on cliff!
	var al_n: int = doc.sculpt_terrain_ex(Vector3(0, 4, -13), 5.0, 1.0, 4, 0) # Paint Alpha+!
	_check(sc_n > 0 and al_n > 0, "sculpt_terrain_ex sculpted vertical cliff along Face Normal & painted Alpha blend!")

	var p1: int = doc.make_terrain_patch(Vector3(-12, -1, 8), Vector3(0, 0, 14), 3, "NATURE/DIRTGROUND001")
	var p2: int = doc.make_terrain_patch(Vector3(0, -1, 8), Vector3(12, 0, 14), 3, "NATURE/DIRTGROUND001")
	doc.sculpt_terrain_ex(Vector3(0, 0, 11), 4.0, 1.5, 0, 1)
	var sewn: int = doc.sew_displacements()
	var sub_ok: bool = doc.subdivide_displacement(p1)
	_check(p1 >= 0 and p2 >= 0 and sewn >= 5 and sub_ok,
		"Hammer Sew welded %d boundary vertices + Subdivide smoothed terrain!" % sewn)

	var uv_ok: bool = doc.set_face_uv(w45, 0, 0.5, 0.5, 16.0, 8.0, 15.0, 8.0) and doc.justify_face_uv(w45, 0, 0)
	_check(uv_ok, "Face Edit UV Scale/Shift/Rot/Lightmap + Fit Justify applied cleanly!")

	var probs_before: Array = doc.check_problems()
	_check(probs_before.size() >= 3, "Alt+P Check Map for Problems detected %d issues on unsealed spawnless map!" % probs_before.size())

	doc.add_point_entity("info_player_teamspawn", Vector3(-6, 0.5, 0), {"TeamNum": "2", "angles": "0 0 0"})
	doc.add_point_entity("info_player_teamspawn", Vector3(6, 0.5, 2), {"TeamNum": "3", "angles": "0 180 0"})
	doc.add_point_entity("light_environment", Vector3(0, 10, 0), {"_light": "255 245 220 400", "pitch": "-45"})
	doc.auto_seal_skybox()
	var probs_after: Array = doc.check_problems()
	_check(probs_after.is_empty(), "Alt+P Check Map for Problems returned 0 issues after sealing + spawns + light!")

	# Real Valve vbsp.exe compile of angled wall + hollow room + vertex-edited brush + vertical cliff + sewn displacements!
	var vmf_path := REPO_ROOT + "/godot/maps/pb_overhaul_test.vmf"
	var sv: Dictionary = doc.save_vmf(vmf_path)
	var tf2_dir: String = core.get_tf2_dir()
	var vbsp := tf2_dir.path_join("bin/x64/vbsp.exe")
	if not FileAccess.file_exists(vbsp): vbsp = tf2_dir.path_join("bin/vbsp.exe")
	var out_arr: Array = []
	var ec: int = OS.execute(vbsp, ["-game", tf2_dir.path_join("tf"), vmf_path], out_arr, true)
	var has_leak := "\n".join(out_arr).find("**** leaked ****") != -1
	_check(sv.get("ok", false) and ec == 0 and not has_leak,
		"Real Valve vbsp.exe compiled angled walls + hollow room + vertical cliff + sewn terrain (exit=%d, leak=%s)!" % [ec, str(has_leak)])

	print("=== 5-Phase Overhaul Test Summary: %d failures ===" % _failed)
	quit(0 if _failed == 0 else 1)
