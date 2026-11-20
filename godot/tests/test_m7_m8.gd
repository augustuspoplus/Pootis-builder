extends SceneTree

const ModelImporterScript = preload("res://scripts/editor/ModelImporter.gd")

var _failed: bool = false

func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
		_failed = true

func _run_vbsp(compiler: Object, vmf_path: String, map_name: String) -> Dictionary:
	compiler.start_compile(vmf_path, true, false, false, false, map_name)
	var t0 := Time.get_ticks_msec()
	var st: Dictionary = {}
	while (Time.get_ticks_msec() - t0) < 25000:
		OS.delay_msec(60)
		st = compiler.poll()
		if st.get("finished", false):
			break
	return st

func _init() -> void:
	print("=== Milestones 7 & 8: Leak Laser + Auto-Seal Recovery & 3D Model Importer (.OBJ + .QC/.SMD) ===")
	var doc = ClassDB.instantiate("Tf2MapDoc")
	var compiler = ClassDB.instantiate("Tf2Compiler")

	# --- MILESTONE 7: Intentional Leak -> .lin 3D Laser -> Auto-Seal -> Clean Compile ---
	doc.new_map("pb_m7_leak_test", "sky_badlands_01")
	doc.add_box(Vector3(-8, -1, -8), Vector3(8, 0, 8), "CONCRETE/CONCRETEFLOOR007A")
	doc.add_point_entity("info_player_teamspawn", Vector3(0, 1, 0), {"TeamNum": "2"})
	var leak_vmf := "C:/Users/steph/Documents/Git/pootis builder/godot/maps/pb_m7_leak_test.vmf"
	doc.save_vmf(leak_vmf)

	var st_leak := _run_vbsp(compiler, leak_vmf, "pb_m7_leak_test")
	var lin_path: String = str(st_leak.get("leak_file", ""))
	print("  Step 1 (Unsealed): succeeded=%s leak_file='%s'" % [str(st_leak.get("succeeded", false)), lin_path])
	_check(not lin_path.is_empty(), "vbsp detected leak and produced .lin file")

	var pts: PackedVector3Array = compiler.read_leak_points(lin_path)
	print("  Step 2 (3D Red Leak Laser): parsed %d 3D polyline points" % pts.size())
	_check(pts.size() >= 2, "3D leak laser parsed >= 2 points from .lin")

	# Now 1-click Auto-Seal Skybox and recompile!
	doc.auto_seal_skybox()
	doc.save_vmf(leak_vmf)
	var st_fixed := _run_vbsp(compiler, leak_vmf, "pb_m7_leak_test")
	var lin_after: String = str(st_fixed.get("leak_file", ""))
	print("  Step 3 (After Auto-Seal): succeeded=%s leak_file='%s'" % [str(st_fixed.get("succeeded", false)), lin_after])
	_check(st_fixed.get("succeeded", false) and lin_after.is_empty(), "Auto-Seal fixed leak completely (0 leaks)!")

	# --- MILESTONE 8: 3D Model Importer (.OBJ + .MTL -> Godot Prop + Valve .QC/.SMD) ---
	var sample_dir := "C:/Users/steph/Documents/Git/pootis builder/godot/maps/imported_models"
	DirAccess.make_dir_recursive_absolute(sample_dir)
	var mtl_path := sample_dir + "/custom_pylon.mtl"
	var obj_path := sample_dir + "/custom_pylon.obj"

	var mf := FileAccess.open(mtl_path, FileAccess.WRITE)
	mf.store_string("newmtl team_red\nKd 0.85 0.24 0.18\n")
	mf.close()

	# Simple Blender-exported 3D pyramid/pylon .obj
	var of := FileAccess.open(obj_path, FileAccess.WRITE)
	of.store_string("""# Blender-style custom TF2 prop
mtllib custom_pylon.mtl
usemtl team_red
v -1.0 0.0 -1.0
v  1.0 0.0 -1.0
v  1.0 0.0  1.0
v -1.0 0.0  1.0
v  0.0 2.5  0.0
f 1 2 3 4
f 1 5 2
f 2 5 3
f 3 5 4
f 4 5 1
""")
	of.close()

	var imp: Dictionary = ModelImporterScript.import_model(obj_path, 2.0, 1.0)
	_check(imp.get("ok", false), "ModelImporter imported .obj cleanly: " + str(imp.get("error", "")))
	if imp.get("ok", false):
		var sz_u: Vector3 = imp["size_u"]
		print("  Step 4 (.OBJ Import): name=%s scale=%.2f size_u=(%.0f, %.0f, %.0f)" % [
			imp["name"], float(imp["scale"]), sz_u.x, sz_u.y, sz_u.z
		])
		_check(abs(sz_u.y - 64.0) < 2.0, "Fit 64u scaled pylon height to 64u (got %.1f)" % sz_u.y)

		var exp_res: Dictionary = ModelImporterScript.export_tf2_qc_smd(sample_dir + "/qc_out", "custom_pylon", imp["mesh"], float(imp["scale"]))
		_check(exp_res.get("ok", false), "Exported Valve .QC + .SMD bundle cleanly")
		print("  Step 5 (TF2 .QC/.SMD Export): tris=%d qc=%s" % [int(exp_res.get("triangles", 0)), str(exp_res.get("qc_path", ""))])
		_check(int(exp_res.get("triangles", 0)) == 6, "Exported exact 6 triangles to .smd")
		_check(FileAccess.file_exists(str(exp_res.get("qc_path", ""))), ".qc file exists on disk")
		(imp["node"] as Node).free()

	if _failed:
		print("=== MILESTONES 7 & 8 FAILED ===")
		quit(1)
	else:
		print("=== MILESTONES 7 & 8 PASSED (Leak Laser + Auto-Seal + .OBJ/.GLB Importer + .QC/.SMD Export!) ===")
		quit(0)
