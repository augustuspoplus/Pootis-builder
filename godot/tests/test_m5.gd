extends SceneTree

const Tf2GamemodesScript = preload("res://scripts/core/Tf2Gamemodes.gd")

var _failed: bool = false

func _check(cond: bool, msg: String) -> void:
	if not cond:
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)
		_failed = true

func _init() -> void:
	print("=== Milestone 5: ALL 12 TF2 Gamemodes VMF + Real Valve vbsp.exe Verification ===")
	var doc = ClassDB.instantiate("Tf2MapDoc")
	var compiler = ClassDB.instantiate("Tf2Compiler")
	var paths: Dictionary = compiler.detect_paths()
	_check(paths.get("valid", false), "Valve vbsp.exe ready")

	DirAccess.make_dir_recursive_absolute("C:/Users/steph/Documents/Git/pootis builder/godot/maps/gamemodes")
	var passed_modes: int = 0

	for gm in Tf2GamemodesScript.GAMEMODES:
		var mid: String = gm["id"]
		var meta: Dictionary = Tf2GamemodesScript.build_gamemode_template(doc, mid)
		var mname: String = meta["map_name"]
		var vmf_path := "C:/Users/steph/Documents/Git/pootis builder/godot/maps/gamemodes/%s.vmf" % mname
		var sv: Dictionary = doc.save_vmf(vmf_path)
		_check(sv.get("ok", false), "%s save_vmf ok" % mid)

		var started: bool = compiler.start_compile(vmf_path, true, false, false, false, mname)
		_check(started, "%s vbsp started" % mid)
		var t0 := Time.get_ticks_msec()
		var st: Dictionary = {}
		while (Time.get_ticks_msec() - t0) < 25000:
			OS.delay_msec(60)
			st = compiler.poll()
			if st.get("finished", false):
				break

		var ok: bool = st.get("succeeded", false)
		var leak: String = str(st.get("leak_file", ""))
		print("  [%2d/12] %-10s -> %-18s | solids=%3d ents=%2d | vbsp=%s leaks=%s (%.2fs)" % [
			passed_modes + 1, mid, mname, doc.get_solid_count(), doc.get_entity_count(),
			"OK" if ok else "FAIL", "0" if leak.is_empty() else leak, float(st.get("elapsed", 0.0))
		])
		if not ok:
			var logs: PackedStringArray = st.get("log", PackedStringArray())
			for i in range(max(0, logs.size() - 8), logs.size()):
				print("      [vbsp] " + logs[i])
		_check(ok and leak.is_empty(), "%s compiled cleanly with 0 leaks" % mid)
		if ok and leak.is_empty():
			passed_modes += 1

	if _failed:
		print("=== MILESTONE 5 FAILED (%d/12 gamemodes passed) ===" % passed_modes)
		quit(1)
	else:
		print("=== MILESTONE 5 PASSED (%d/12 TF2 GAMEMODES COMPILED CLEANLY WITH REAL VBSP.EXE!) ===" % passed_modes)
		quit(0)
