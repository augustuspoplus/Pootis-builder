extends SceneTree

func _init() -> void:
	var core = ClassDB.instantiate("Tf2Core")
	core.mount_tf2("C:/Users/steph/Documents/Git/pootis builder")
	var bsp_path: String = str(core.get_tf2_dir()).path_join("tf/maps/ctf_turbine.bsp")
	var d: Dictionary = core.load_bsp_data(bsp_path)
	var surfs: Array = d["surfaces"]

	var probes := [
		{"name": "Main dark floor",      "p": Vector3(-8, -8, -16)},
		{"name": "Turbine tile strip",   "p": Vector3(-6, -8, 0)},
		{"name": "Turbine grate",        "p": Vector3(0, -8, 0)},
		{"name": "Lower concrete wall",  "p": Vector3(23.5, -3, -12)},
		{"name": "Upper dark wall band", "p": Vector3(23.5, 11.5, 0)},
		{"name": "Ceiling slab",         "p": Vector3(8, 14, 0)},
		{"name": "Ceiling beam",         "p": Vector3(0, 12.5, 0)},
		{"name": "RED balcony edge",     "p": Vector3(19.5, 1.3, 10)},
		{"name": "RED vent trim",        "p": Vector3(19.0, 3.0, 0)},
		{"name": "Exterior green roof",  "p": Vector3(0, 4.0, -30)},
		{"name": "Shuttered side door",  "p": Vector3(23.5, -5.5, 14)},
	]

	for pr in probes:
		var target: Vector3 = pr["p"]
		var best_d := 1e9
		var best_m := ""
		for s in surfs:
			var verts: PackedVector3Array = s["vertices"]
			for i in range(0, verts.size(), 3):
				var dist := verts[i].distance_squared_to(target)
				if dist < best_d:
					best_d = dist
					best_m = str(s["material"])
		print("  %-22s -> %-45s (dist=%.2fm)" % [pr["name"], best_m, sqrt(best_d)])

	print("\n--- PROPS NEAR STAIRS & SHUTTER ---")
	var pgroups: Dictionary = d["prop_groups"]
	for mdl in pgroups.keys():
		var xfs: Array = pgroups[mdl]
		for xf: Transform3D in xfs:
			var p := xf.origin
			if abs(p.x) < 25.0 and abs(p.z) < 25.0 and not (mdl.find("generator") != -1 or mdl.find("container") != -1 or mdl.find("ceiling_lamp") != -1):
				print("  %-52s pos=(%.1f, %.1f, %.1f) yaw=%.0f" % [mdl, p.x, p.y, p.z, rad_to_deg(xf.basis.get_euler().y)])
	print("\n--- ALL FLOOR / TILE / GLASS / RED / METAL MATS IN ctf_turbine ---")
	for s in surfs:
		var mn: String = str(s["material"]).to_lower()
		if mn.find("floor") != -1 or mn.find("tile") != -1 or mn.find("glass") != -1 or mn.find("red") != -1 or mn.find("trim") != -1 or mn.find("wall011") != -1 or mn.find("metalwall") != -1 or mn.find("imetal") != -1:
			print("  MAT: ", s["material"], " (verts=", (s["vertices"] as PackedVector3Array).size(), ")")
	quit(0)
