extends SceneTree

func _init() -> void:
	var core = ClassDB.instantiate("Tf2Core")
	core.mount_tf2("C:/Users/steph/Documents/Git/pootis builder")
	var bsp_path: String = str(core.get_tf2_dir()).path_join("tf/maps/ctf_turbine.bsp")
	var d: Dictionary = core.load_bsp_data(bsp_path)
	print("=== REAL VALVE ctf_turbine.bsp MEASUREMENTS ===")
	print("skyname: ", d["skyname"])
	print("play_bounds: ", d["play_bounds_min"], " -> ", d["play_bounds_max"])

	print("\n--- TOP MATERIALS (sorted by vert count) ---")
	var surfs: Array = d["surfaces"]
	var mats := []
	for s in surfs:
		mats.append({"mat": s["material"], "verts": (s["vertices"] as PackedVector3Array).size()})
	mats.sort_custom(func(a, b): return a["verts"] > b["verts"])
	for i in range(min(30, mats.size())):
		print("  [%2d] %-55s (%d verts)" % [i, mats[i]["mat"], mats[i]["verts"]])

	print("\n--- STATIC PROPS IN MID HALL (|x|<22, |z|<18) ---")
	var pgroups: Dictionary = d["prop_groups"]
	for mdl in pgroups.keys():
		var xfs: Array = pgroups[mdl]
		var mid_hits := []
		for xf: Transform3D in xfs:
			var p := xf.origin
			if abs(p.x) < 22.0 and abs(p.z) < 18.0:
				var eul := xf.basis.get_euler()
				mid_hits.append("pos=(%.2f, %.2f, %.2f) yaw=%.0f" % [p.x, p.y, p.z, rad_to_deg(eul.y)])
		if not mid_hits.is_empty():
			print("  MODEL: %s (total=%d, mid=%d)" % [mdl, xfs.size(), mid_hits.size()])
			for h in mid_hits.slice(0, 6):
				print("    ", h)

	print("\n--- KEY GAMEPLAY ENTITIES ---")
	for e in d["entities"]:
		var cls: String = str(e["classname"])
		if cls in ["item_teamflag", "info_player_teamspawn", "item_healthkit_medium", "item_healthkit_small", "item_ammopack_medium", "item_ammopack_full"]:
			print("  %-24s pos=%s" % [cls, str(e["pos"])])

	quit(0)
