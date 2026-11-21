extends SceneTree

func _init() -> void:
	var core = ClassDB.instantiate("Tf2Core")
	core.mount_tf2("C:/Users/steph/Documents/Git/pootis builder")
	var bsp_path: String = str(core.get_tf2_dir()).path_join("tf/maps/ctf_turbine.bsp")
	var d: Dictionary = core.load_bsp_data(bsp_path)
	# Raycast / inspect exact mid hall wall planes from collision_faces near center (0, 0, 0)
	var tris: PackedVector3Array = d["collision_faces"]
	var min_x := -999.0; var max_x := 999.0
	var min_z := -999.0; var max_z := 999.0
	var floor_y := -999.0; var ceil_y := 999.0
	# Sample axis-aligned faces near mid hall (|x|<35, |z|<35)
	var x_walls := {}
	var z_walls := {}
	var y_planes := {}
	for i in range(0, tris.size(), 3):
		var a := tris[i]; var b := tris[i+1]; var c := tris[i+2]
		var ctr := (a + b + c) / 3.0
		if abs(ctr.x) > 35.0 or abs(ctr.z) > 35.0 or ctr.y < -12.0 or ctr.y > 18.0:
			continue
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-6:
			continue
		n = n.normalized()
		if abs(n.x) > 0.95:
			var k := int(round(ctr.x * 2.0))
			x_walls[k] = x_walls.get(k, 0) + 1
		elif abs(n.z) > 0.95:
			var k := int(round(ctr.z * 2.0))
			z_walls[k] = z_walls.get(k, 0) + 1
		elif abs(n.y) > 0.95:
			var k := int(round(ctr.y * 2.0))
			y_planes[k] = y_planes.get(k, 0) + 1

	var print_top := func(label: String, dict: Dictionary):
		var arr := []
		for k in dict.keys(): arr.append([dict[k], float(k) * 0.5])
		arr.sort_custom(func(p, q): return p[0] > q[0])
		print(label)
		for j in range(min(12, arr.size())):
			print("  %.1fm (%du) — %d tris" % [arr[j][1], int(arr[j][1] * 32), arr[j][0]])

	print_top.call("TOP X WALL PLANES:", x_walls)
	print_top.call("TOP Z WALL PLANES:", z_walls)
	print_top.call("TOP Y HORIZONTAL PLANES:", y_planes)
	quit(0)
