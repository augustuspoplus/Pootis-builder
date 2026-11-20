extends SceneTree

var _failed: bool = false

func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
		_failed = true

func _init() -> void:
	print("=== Milestone 4: Native C++20 Tf2MapDoc CSG + Terrain + Real vbsp.exe Test ===")
	var core = ClassDB.instantiate("Tf2Core")
	_check(core != null, "Tf2Core instantiated")
	var mount: Dictionary = core.mount_tf2("C:/Users/steph/Documents/Git/pootis builder")
	_check(mount.get("ready", false), "TF2 mounted")

	var doc = ClassDB.instantiate("Tf2MapDoc")
	_check(doc != null, "Tf2MapDoc instantiated")

	doc.new_map("pb_m4_test", "sky_badlands_01")
	_check(doc.get_map_name() == "pb_m4_test", "map name matches")
	_check(doc.get_skyname() == "sky_badlands_01", "skyname matches")

	# 1. Floor + Box + Ramp + Stairs + Arch
	doc.record_undo("Add arena floor")
	var floor_id: int = doc.add_box(Vector3(-20, -1, -16), Vector3(20, 0, 16), "CONCRETE/CONCRETEFLOOR007A")
	_check(floor_id == 0, "floor box id == 0")

	doc.record_undo("Add ramp & stairs")
	var ramp_id: int = doc.add_ramp(Vector3(-6, 0, -4), Vector3(-2, 3, 0), 0, "CONCRETE/CONCRETEWALL001A")
	_check(ramp_id >= 1, "ramp created")
	var stairs_ids: PackedInt32Array = doc.add_stairs(Vector3(2, 0, -4), Vector3(6, 3, 0), 1, 6, "METAL/METALWALL001A")
	_check(stairs_ids.size() == 6, "6 stairs steps created")

	var arch_ids: PackedInt32Array = doc.add_arch(Vector3(0, 0, -10), 6.0, 1.5, 5.0, 5, "BRICK/BRICKWALL001")
	_check(arch_ids.size() == 7, "2 pillars + 5 arch segments created (got %d)" % arch_ids.size())

	# 2. Modular multi-story TF2 Building with gabled roof & carved doorway
	doc.record_undo("Add 2-story gabled building")
	var bld_ids: PackedInt32Array = doc.add_building(
		Vector3(-14, 0, -10), Vector3(-6, 0, -2),
		2, 1,
		"WOOD/WOOD_WALL002", "CONCRETE/CONCRETEFLOOR007A", "METAL/METALROOF004A", 2)
	_check(bld_ids.size() >= 6, "building created >= 6 solids, got %d" % bld_ids.size())

	# 3. Mirror building to BLU side (180-deg rotational symmetry)
	var before_mirror: int = doc.get_solid_count()
	var mir_id: int = doc.mirror_solid_x(ramp_id, true)
	_check(mir_id >= before_mirror, "mirrored ramp created")

	# 4. Push/Pull & Slope editing
	var box_id: int = doc.add_box(Vector3(-2, 0, 6), Vector3(2, 3, 10), "BRICK/BRICKWALL001")
	var pp_ok: bool = doc.push_pull_face(box_id, 0, 1.0)
	_check(pp_ok, "push_pull_face succeeded")
	var sl_ok: bool = doc.slope_solid_top(box_id, 0, 1.0)
	_check(sl_ok, "slope_solid_top succeeded")

	# 5. Auto-carve doorway through a standalone wall
	var wall_id: int = doc.add_box(Vector3(-4, 0, 11), Vector3(4, 4, 12), "BRICK/BRICKWALL001")
	var carved: int = doc.auto_carve_opening(Vector3(-1.5, 0, 10.5), Vector3(1.5, 3, 12.5), "WOOD/WOOD_WALL002")
	_check(carved >= 1, "auto_carve_opening carved wall (carved=%d)" % carved)
	_check(wall_id >= 0, "wall_id valid")

	# 6. Source Displacement Terrain + Raise/Smooth/Flatten sculpting
	var disp_id: int = doc.make_terrain_patch(Vector3(6, -1, 4), Vector3(18, 0, 14), 3, "NATURE/DIRTGROUND001")
	_check(disp_id >= 0, "displacement terrain patch created")
	var touched_raise: int = doc.sculpt_terrain(Vector3(12, 0, 9), 4.0, 2.5, 0)
	var touched_smooth: int = doc.sculpt_terrain(Vector3(12, 0, 9), 4.0, 1.0, 2)
	_check(touched_raise >= 1 and touched_smooth >= 1, "terrain sculpted (raise=%d smooth=%d)" % [touched_raise, touched_smooth])

	# Verify displacement mesh has verts & collision
	var disp_mesh: Dictionary = doc.get_solid_mesh_data(disp_id)
	_check(disp_mesh.get("ok", false), "disp mesh data ok")
	_check(disp_mesh.get("is_disp", false), "disp mesh flagged is_disp")
	_check((disp_mesh["collision_faces"] as PackedVector3Array).size() >= 300, "disp has rich collision tris")

	# 7. Entities + I/O Connection
	var red_spawn: int = doc.add_point_entity("info_player_teamspawn", Vector3(-12, 0.5, 0), {"TeamNum": "2", "angles": "0 0 0"})
	var blu_spawn: int = doc.add_point_entity("info_player_teamspawn", Vector3(12, 0.5, 0), {"TeamNum": "3", "angles": "0 180 0"})
	var sun: int = doc.add_point_entity("light_environment", Vector3(0, 10, 0), {"angles": "0 45 0", "pitch": "-45", "_light": "255 245 225 400", "_ambient": "140 165 200 180"})
	var trig: int = doc.add_brush_entity("trigger_multiple", Vector3(-1, 0, -1), Vector3(1, 3, 1), "TOOLS/TOOLSTRIGGER", {"targetname": "trig_mid"})
	var conn_ok: bool = doc.add_connection(trig, "OnStartTouch", "door_mid", "Open", "", 0.0)
	_check(red_spawn >= 0 and blu_spawn >= 0 and sun >= 0 and trig >= 0 and conn_ok, "entities & I/O connection created")

	# 8. Raycast check
	var rc: Dictionary = doc.raycast_face(Vector3(0, 10, 0), Vector3(0, -1, 0))
	_check(rc.get("hit", false), "raycast hit floor")

	# 9. Undo/Redo test (History::record snapshots state AFTER each edit)
	doc.record_undo("Before temp box")
	var cnt_before_undo: int = doc.get_solid_count()
	doc.add_box(Vector3(0, 5, 0), Vector3(2, 7, 2), "BRICK/BRICKWALL001")
	doc.record_undo("Add temp box")
	_check(doc.get_solid_count() == cnt_before_undo + 1, "temp box added")
	_check(doc.undo(), "undo succeeded")
	_check(doc.get_solid_count() == cnt_before_undo, "undo restored exact solid count")
	_check(doc.redo(), "redo succeeded")
	_check(doc.get_solid_count() == cnt_before_undo + 1, "redo restored temp box")
	_check(doc.undo(), "undo removed temp box again")

	# 10. Auto-Seal Skybox + Save VMF + Round-trip Load VMF
	_check(doc.auto_seal_skybox(), "auto_seal_skybox succeeded")
	_check(doc.is_map_sealed(), "map reports sealed")

	DirAccess.make_dir_recursive_absolute("C:/Users/steph/Documents/Git/pootis builder/godot/maps")
	var vmf_path := "C:/Users/steph/Documents/Git/pootis builder/godot/maps/pb_m4_test.vmf"
	var sv: Dictionary = doc.save_vmf(vmf_path)
	_check(sv.get("ok", false), "save_vmf ok: " + str(sv.get("error", "")))

	var doc2 = ClassDB.instantiate("Tf2MapDoc")
	var ld: Dictionary = doc2.load_vmf(vmf_path)
	_check(ld.get("ok", false), "load_vmf round-trip ok: " + str(ld.get("error", "")))
	_check(doc2.get_solid_count() == doc.get_solid_count(), "round-trip solid count matches (%d vs %d)" % [doc2.get_solid_count(), doc.get_solid_count()])
	_check(doc2.get_entity_count() == doc.get_entity_count(), "round-trip entity count matches (%d vs %d)" % [doc2.get_entity_count(), doc.get_entity_count()])

	# 11. Real Valve vbsp.exe compile test via Tf2Compiler!
	var compiler = ClassDB.instantiate("Tf2Compiler")
	var paths: Dictionary = compiler.detect_paths()
	_check(paths.get("valid", false), "Valve vbsp.exe detected: " + str(paths.get("bin_dir", "")))
	if paths.get("valid", false):
		var started: bool = compiler.start_compile(vmf_path, true, false, false, false, "pb_m4_test")
		_check(started, "Tf2Compiler.start_compile(vbsp) started")
		var t0 := Time.get_ticks_msec()
		var done := false
		var st: Dictionary = {}
		while not done and (Time.get_ticks_msec() - t0) < 30000:
			OS.delay_msec(100)
			st = compiler.poll()
			if st.get("finished", false):
				done = true
		var leak_file: String = str(st.get("leak_file", ""))
		print("  vbsp finished=%s succeeded=%s stage=%s leak_file='%s' elapsed=%.2fs" % [
			str(done), str(st.get("succeeded", false)), str(st.get("stage", "")), leak_file, float(st.get("elapsed", 0.0))
		])
		if not st.get("succeeded", false):
			var logs: PackedStringArray = st.get("log", PackedStringArray())
			for i in range(max(0, logs.size() - 12), logs.size()):
				print("    [vbsp] " + logs[i])
		_check(done and st.get("succeeded", false), "real Valve vbsp.exe compiled pb_m4_test.vmf cleanly!")
		_check(leak_file.is_empty(), "zero leaks in compiled pb_m4_test.vmf!")

	if _failed:
		print("=== MILESTONE 4 FAILED ===")
		quit(1)
	else:
		print("=== MILESTONE 4 PASSED (solids=%d, entities=%d, vbsp=OK, leaks=0) ===" % [
			doc.get_solid_count(), doc.get_entity_count()
		])
		quit(0)
