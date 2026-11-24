class_name VmfExporter
extends RefCounted

## Exports Pootis Builder Godot 4 blocks & TF2 gameplay stamps into a 100% valid,
## pre-sealed Valve Source .vmf file (1 Godot meter = 32 Hammer units).

const UNITS_PER_METER := 32.0

static func export_vmf(path: String, map_name: String, sky_name: String,
		blocks: Array, stamps: Array) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false

	var next_id := 1
	var lines: PackedStringArray = []
	lines.append("versioninfo\n{\n\t\"editorversion\" \"400\"\n\t\"editorbuild\" \"8864\"\n\t\"mapversion\" \"1\"\n\t\"formatversion\" \"100\"\n\t\"prefab\" \"0\"\n}")
	lines.append("world\n{\n\t\"id\" \"1\"\n\t\"mapversion\" \"1\"\n\t\"classname\" \"worldspawn\"\n\t\"skyname\" \"%s\"\n\t\"maxpropscreenwidth\" \"-1\"\n\t\"detailvbsp\" \"detail.vbsp\"\n\t\"detailmaterial\" \"detail/detailsprites\"" % sky_name)
	next_id = 2

	# Track map bounds so we auto-seal with a leak-free skybox shell
	var bmin := Vector3(-1024, -1024, -64)
	var bmax := Vector3(1024, 1024, 512)

	for b in blocks:
		var pos: Vector3 = b["pos"] * UNITS_PER_METER
		var sz: Vector3 = b["size"] * UNITS_PER_METER
		# Godot (X, Y-up, Z-back) -> Source Hammer (X, -Z, Y-up)
		var hmin := Vector3(pos.x - sz.x * 0.5, -pos.z - sz.z * 0.5, pos.y - sz.y * 0.5)
		var hmax := Vector3(pos.x + sz.x * 0.5, -pos.z + sz.z * 0.5, pos.y + sz.y * 0.5)
		bmin = bmin.min(hmin)
		bmax = bmax.max(hmax)
		var mat: String = b.get("vmf_mat", "concrete/concretefloor002")
		var res := _make_solid(next_id, hmin, hmax, mat)
		lines.append(res["text"])
		next_id = res["next_id"]

	# Auto-seal hollow skybox (6 slabs outside map bounds -> 0 leaks in vbsp!)
	var pad := 128.0
	var th := 32.0
	var smin := bmin - Vector3(pad, pad, pad)
	var smax := bmax + Vector3(pad, pad, pad + 384.0)
	var sky_boxes := [
		[Vector3(smin.x, smin.y, smin.z - th), Vector3(smax.x, smax.y, smin.z)],
		[Vector3(smin.x, smin.y, smax.z),      Vector3(smax.x, smax.y, smax.z + th)],
		[Vector3(smin.x - th, smin.y, smin.z), Vector3(smin.x, smax.y, smax.z)],
		[Vector3(smax.x, smin.y, smin.z),      Vector3(smax.x + th, smax.y, smax.z)],
		[Vector3(smin.x, smin.y - th, smin.z), Vector3(smax.x, smin.y, smax.z)],
		[Vector3(smin.x, smax.y, smin.z),      Vector3(smax.x, smax.y + th, smax.z)],
	]
	for sb in sky_boxes:
		var res := _make_solid(next_id, sb[0], sb[1], "tools/toolsskybox")
		lines.append(res["text"])
		next_id = res["next_id"]

	lines.append("}")

	# Sun light_environment
	lines.append("entity\n{\n\t\"id\" \"%d\"\n\t\"classname\" \"light_environment\"\n\t\"_light\" \"255 242 214 550\"\n\t\"_ambient\" \"165 185 215 220\"\n\t\"angles\" \"0 225 0\"\n\t\"pitch\" \"-45\"\n\t\"origin\" \"0 0 384\"\n}" % next_id)
	next_id += 1

	# Gameplay stamps -> real TF2 entities
	var cp_idx := 0
	for st in stamps:
		var p: Vector3 = st["pos"] * UNITS_PER_METER
		var org := "%.0f %.0f %.0f" % [p.x, -p.z, p.y + 8.0]
		var kind: String = st["kind"]
		match kind:
			"RED":
				lines.append("entity\n{\n\t\"id\" \"%d\"\n\t\"classname\" \"info_player_teamspawn\"\n\t\"TeamNum\" \"2\"\n\t\"angles\" \"0 0 0\"\n\t\"origin\" \"%s\"\n}" % [next_id, org])
				next_id += 1
			"BLU":
				lines.append("entity\n{\n\t\"id\" \"%d\"\n\t\"classname\" \"info_player_teamspawn\"\n\t\"TeamNum\" \"3\"\n\t\"angles\" \"0 180 0\"\n\t\"origin\" \"%s\"\n}" % [next_id, org])
				next_id += 1
			"Health":
				lines.append("entity\n{\n\t\"id\" \"%d\"\n\t\"classname\" \"item_healthkit_medium\"\n\t\"origin\" \"%s\"\n}" % [next_id, org])
				next_id += 1
			"Ammo":
				lines.append("entity\n{\n\t\"id\" \"%d\"\n\t\"classname\" \"item_ammopack_medium\"\n\t\"origin\" \"%s\"\n}" % [next_id, org])
				next_id += 1
			"Locker":
				var hmin := Vector3(p.x - 32, -p.z - 16, p.y)
				var hmax := Vector3(p.x + 32, -p.z + 16, p.y + 96)
				var sres := _make_solid(next_id + 1, hmin, hmax, "tools/toolstrigger")
				lines.append("entity\n{\n\t\"id\" \"%d\"\n\t\"classname\" \"func_regenerate\"\n%s\n}" % [next_id, sres["text"]])
				next_id = sres["next_id"]
			"Point":
				cp_idx += 1
				var cp_name := "control_point_%d" % cp_idx
				lines.append("entity\n{\n\t\"id\" \"%d\"\n\t\"classname\" \"team_control_point\"\n\t\"targetname\" \"%s\"\n\t\"point_printname\" \"Point %d\"\n\t\"point_index\" \"%d\"\n\t\"origin\" \"%s\"\n}" % [next_id, cp_name, cp_idx, cp_idx - 1, org])
				next_id += 1
			"Intel":
				lines.append("entity\n{\n\t\"id\" \"%d\"\n\t\"classname\" \"item_teamflag\"\n\t\"TeamNum\" \"2\"\n\t\"origin\" \"%s\"\n}" % [next_id, org])
				next_id += 1
			"Cart":
				lines.append("entity\n{\n\t\"id\" \"%d\"\n\t\"classname\" \"prop_dynamic\"\n\t\"model\" \"models/props_trainyard/bomb_cart.mdl\"\n\t\"origin\" \"%s\"\n}" % [next_id, org])
				next_id += 1

	f.store_string("\n".join(lines) + "\n")
	f.close()
	return true

static func _make_solid(start_id: int, mn: Vector3, mx: Vector3, mat: String) -> Dictionary:
	var sid := start_id
	var fid := start_id + 1
	var faces := [
		# Top (+Z)
		[Vector3(mn.x, mx.y, mx.z), Vector3(mx.x, mx.y, mx.z), Vector3(mx.x, mn.y, mx.z), "[1 0 0 0] 0.25", "[0 -1 0 0] 0.25"],
		# Bottom (-Z)
		[Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mx.y, mn.z), "[1 0 0 0] 0.25", "[0 -1 0 0] 0.25"],
		# West (-X)
		[Vector3(mn.x, mx.y, mx.z), Vector3(mn.x, mn.y, mx.z), Vector3(mn.x, mn.y, mn.z), "[0 1 0 0] 0.25", "[0 0 -1 0] 0.25"],
		# East (+X)
		[Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), "[0 1 0 0] 0.25", "[0 0 -1 0] 0.25"],
		# North (+Y)
		[Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z), Vector3(mn.x, mx.y, mn.z), "[1 0 0 0] 0.25", "[0 0 -1 0] 0.25"],
		# South (-Y)
		[Vector3(mx.x, mn.y, mn.z), Vector3(mn.x, mn.y, mn.z), Vector3(mn.x, mn.y, mx.z), "[1 0 0 0] 0.25", "[0 0 -1 0] 0.25"],
	]
	var out := "\tsolid\n\t{\n\t\t\"id\" \"%d\"\n" % sid
	for fc in faces:
		var p1: Vector3 = fc[0]
		var p2: Vector3 = fc[1]
		var p3: Vector3 = fc[2]
		out += "\t\tside\n\t\t{\n\t\t\t\"id\" \"%d\"\n\t\t\t\"plane\" \"(%.0f %.0f %.0f) (%.0f %.0f %.0f) (%.0f %.0f %.0f)\"\n\t\t\t\"material\" \"%s\"\n\t\t\t\"uaxis\" \"%s\"\n\t\t\t\"vaxis\" \"%s\"\n\t\t\t\"rotation\" \"0\"\n\t\t\t\"lightmapscale\" \"16\"\n\t\t\t\"smoothing_groups\" \"0\"\n\t\t}\n" % [
			fid, p1.x, p1.y, p1.z, p2.x, p2.y, p2.z, p3.x, p3.y, p3.z, mat, fc[3], fc[4]
		]
		fid += 1
	out += "\t}"
	return {"text": out, "next_id": fid}
