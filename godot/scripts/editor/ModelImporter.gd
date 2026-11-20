class_name ModelImporter
extends RefCounted

## Milestone 8 — Easy 3D Model Importer (.obj / .glb / .gltf from Blender, Blockbench, Maya, etc.)
## Turns any external 3D model into a live textured 3D prop in Pootis Builder with auto-scale,
## physics collision, and 1-click Valve Source .smd + .qc export bundle for studiomdl.exe!

const UPM := 32.0

## Imports a .glb, .gltf, or .obj file into a Godot MeshInstance3D + ArrayMesh + AABB metadata.
static func import_model(file_path: String, fit_target_m: float = 0.0, uniform_scale: float = 1.0) -> Dictionary:
	var ext := file_path.get_extension().to_lower()
	if not FileAccess.file_exists(file_path):
		return {"ok": false, "error": "File not found: " + file_path}

	var mesh: ArrayMesh = null
	var scene_node: Node3D = null

	if ext == "glb" or ext == "gltf":
		var gltf := GLTFDocument.new()
		var state := GLTFState.new()
		var err := gltf.append_from_file(file_path, state)
		if err != OK:
			return {"ok": false, "error": "GLTFDocument failed (err=%d)" % err}
		var gen := gltf.generate_scene(state)
		if gen == null or not (gen is Node3D):
			return {"ok": false, "error": "GLTF scene empty"}
		scene_node = gen
		mesh = _extract_first_array_mesh(scene_node)
	elif ext == "obj":
		var res := _parse_obj(file_path)
		if not res.get("ok", false):
			return res
		mesh = res["mesh"]
		var mi := MeshInstance3D.new()
		mi.name = file_path.get_file().get_basename()
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		scene_node = mi
	else:
		return {"ok": false, "error": "Unsupported 3D format '.%s' (use .obj, .glb, or .gltf)" % ext}

	var aabb := _compute_node_aabb(scene_node)
	var final_scale := uniform_scale
	if fit_target_m > 0.01:
		var max_dim: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
		if max_dim > 0.0001:
			final_scale = fit_target_m / max_dim

	# Wrap in a cleanly bottom-centered holder so placing on floors never sinks or floats!
	var holder := Node3D.new()
	holder.name = "Imported_" + file_path.get_file().get_basename()
	scene_node.scale = Vector3.ONE * final_scale
	var offset := Vector3(
		-(aabb.position.x + aabb.size.x * 0.5) * final_scale,
		-aabb.position.y * final_scale,
		-(aabb.position.z + aabb.size.z * 0.5) * final_scale
	)
	scene_node.position = offset
	holder.add_child(scene_node)

	# Auto-attach a clean BoxShape3D StaticBody3D so players collide with imported props in F5!
	var col_sz := (aabb.size * final_scale).max(Vector3(0.25, 0.25, 0.25))
	var sb := StaticBody3D.new()
	sb.collision_layer = 1
	sb.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = col_sz
	cs.shape = bs
	cs.position = Vector3(0, col_sz.y * 0.5, 0)
	sb.add_child(cs)
	holder.add_child(sb)

	return {
		"ok": true,
		"node": holder,
		"mesh": mesh,
		"scale": final_scale,
		"size_m": col_sz,
		"size_u": col_sz * UPM,
		"source_path": file_path,
		"name": file_path.get_file().get_basename(),
	}

## Exports an ArrayMesh to a Valve Source Engine .smd + .qc bundle ready for studiomdl.exe!
static func export_tf2_qc_smd(out_dir: String, model_name: String, mesh: Mesh, scale_m: float = 1.0) -> Dictionary:
	if mesh == null:
		return {"ok": false, "error": "No mesh available to export"}
	DirAccess.make_dir_recursive_absolute(out_dir)
	var safe_name := model_name.to_lower().replace(" ", "_")
	var smd_path := out_dir.path_join(safe_name + "_ref.smd")
	var qc_path := out_dir.path_join(safe_name + ".qc")

	var smd := PackedStringArray()
	smd.append("version 1")
	smd.append("nodes")
	smd.append("0 \"root\" -1")
	smd.append("end")
	smd.append("skeleton")
	smd.append("time 0")
	smd.append("0 0.000000 0.000000 0.000000 0.000000 0.000000 0.000000")
	smd.append("end")
	smd.append("triangles")

	var tri_count := 0
	for s in range(mesh.get_surface_count()):
		var arrays := mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var idxs: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var mat_name := safe_name + "_mat_%d" % s

		var count := idxs.size() if idxs.size() > 0 else verts.size()
		var k := 0
		while k + 2 < count:
			var i0 := idxs[k] if idxs.size() > 0 else k
			var i1 := idxs[k + 1] if idxs.size() > 0 else k + 1
			var i2 := idxs[k + 2] if idxs.size() > 0 else k + 2
			smd.append(mat_name)
			for vi in [i0, i2, i1]: # Convert Godot CW -> Source CCW Z-up Hammer units!
				var v := verts[vi] * scale_m * UPM
				var sx := v.x
				var sy := -v.z
				var sz := v.y
				var n := norms[vi] if vi < norms.size() else Vector3.UP
				var uv := uvs[vi] if vi < uvs.size() else Vector2.ZERO
				smd.append("0 %.4f %.4f %.4f %.4f %.4f %.4f %.4f %.4f" % [
					sx, sy, sz, n.x, -n.z, n.y, uv.x, 1.0 - uv.y
				])
			tri_count += 1
			k += 3

	smd.append("end")
	var sf := FileAccess.open(smd_path, FileAccess.WRITE)
	if sf == null:
		return {"ok": false, "error": "Cannot write SMD: " + smd_path}
	sf.store_string("\n".join(smd) + "\n")
	sf.close()

	var qc_text := """$modelname "props_pootis/%s.mdl"
$body "Body" "%s_ref.smd"
$staticprop
$surfaceprop "metal"
$cdmaterials "models/props_pootis/"
$sequence "idle" "%s_ref.smd"
$collisionmodel "%s_ref.smd" {
	$concave
	$automass
}
""" % [safe_name, safe_name, safe_name, safe_name]

	var qf := FileAccess.open(qc_path, FileAccess.WRITE)
	if qf == null:
		return {"ok": false, "error": "Cannot write QC: " + qc_path}
	qf.store_string(qc_text)
	qf.close()

	return {"ok": true, "smd_path": smd_path, "qc_path": qc_path, "triangles": tri_count}

# --- Fast Built-in Wavefront .OBJ + .MTL Parser ---
static func _parse_obj(file_path: String) -> Dictionary:
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		return {"ok": false, "error": "Cannot open OBJ: " + file_path}

	var raw_v: Array[Vector3] = []
	var raw_vn: Array[Vector3] = []
	var raw_vt: Array[Vector2] = []
	var mtl_colors := {} # mtl_name -> Color
	var cur_mtl := "default"
	var buckets := {} # mtl -> {v, n, uv}

	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var p := line.split(" ", false)
		if p.is_empty():
			continue
		match p[0]:
			"mtllib":
				if p.size() >= 2:
					_parse_mtl(file_path.get_base_dir().path_join(p[1]), mtl_colors)
			"usemtl":
				if p.size() >= 2:
					cur_mtl = p[1]
			"v":
				if p.size() >= 4:
					raw_v.append(Vector3(float(p[1]), float(p[2]), float(p[3])))
			"vn":
				if p.size() >= 4:
					raw_vn.append(Vector3(float(p[1]), float(p[2]), float(p[3])).normalized())
			"vt":
				if p.size() >= 3:
					raw_vt.append(Vector2(float(p[1]), 1.0 - float(p[2])))
			"f":
				if p.size() < 4:
					continue
				if not buckets.has(cur_mtl):
					buckets[cur_mtl] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array()}
				var bk: Dictionary = buckets[cur_mtl]
				var fv: Array[Vector3] = []
				var fn: Array[Vector3] = []
				var fuv: Array[Vector2] = []
				for i in range(1, p.size()):
					var parts := p[i].split("/")
					var vi := _obj_idx(int(parts[0]), raw_v.size())
					fv.append(raw_v[vi] if vi >= 0 else Vector3.ZERO)
					if parts.size() >= 2 and not parts[1].is_empty():
						var ti := _obj_idx(int(parts[1]), raw_vt.size())
						fuv.append(raw_vt[ti] if ti >= 0 else Vector2.ZERO)
					else:
						fuv.append(Vector2.ZERO)
					if parts.size() >= 3 and not parts[2].is_empty():
						var ni := _obj_idx(int(parts[2]), raw_vn.size())
						fn.append(raw_vn[ni] if ni >= 0 else Vector3.ZERO)
					else:
						fn.append(Vector3.ZERO)
				# Fan-triangulate polygon (swap to Godot CW outward winding)
				for k in range(1, fv.size() - 1):
					var p0 := fv[0]
					var p1 := fv[k + 1]
					var p2 := fv[k]
					var flat_n := (p2 - p0).cross(p1 - p0)
					flat_n = flat_n.normalized() if flat_n.length_squared() > 1e-10 else Vector3.UP
					bk["v"].append(p0); bk["v"].append(p1); bk["v"].append(p2)
					bk["n"].append(fn[0] if fn[0].length_squared() > 0.1 else flat_n)
					bk["n"].append(fn[k + 1] if fn[k + 1].length_squared() > 0.1 else flat_n)
					bk["n"].append(fn[k] if fn[k].length_squared() > 0.1 else flat_n)
					bk["uv"].append(fuv[0]); bk["uv"].append(fuv[k + 1]); bk["uv"].append(fuv[k])
	f.close()

	var mesh := ArrayMesh.new()
	for mname in buckets.keys():
		var bk: Dictionary = buckets[mname]
		if (bk["v"] as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = bk["v"]
		arr[Mesh.ARRAY_NORMAL] = bk["n"]
		arr[Mesh.ARRAY_TEX_UV] = bk["uv"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = mtl_colors.get(mname, Color(0.76, 0.72, 0.66))
		mat.roughness = 0.78
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)

	if mesh.get_surface_count() == 0:
		return {"ok": false, "error": "OBJ contained zero triangles"}
	return {"ok": true, "mesh": mesh}

static func _parse_mtl(mtl_path: String, out_colors: Dictionary) -> void:
	if not FileAccess.file_exists(mtl_path):
		return
	var f := FileAccess.open(mtl_path, FileAccess.READ)
	if f == null:
		return
	var cur := ""
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		var p := line.split(" ", false)
		if p.size() >= 2 and p[0] == "newmtl":
			cur = p[1]
		elif p.size() >= 4 and p[0] == "Kd" and not cur.is_empty():
			out_colors[cur] = Color(float(p[1]), float(p[2]), float(p[3]))
	f.close()

static func _obj_idx(raw: int, sz: int) -> int:
	if raw > 0 and raw <= sz:
		return raw - 1
	if raw < 0 and sz + raw >= 0:
		return sz + raw
	return -1

static func _extract_first_array_mesh(node: Node) -> ArrayMesh:
	if node is MeshInstance3D and node.mesh != null:
		if node.mesh is ArrayMesh:
			return node.mesh
	for ch in node.get_children():
		var m := _extract_first_array_mesh(ch)
		if m != null:
			return m
	return null

static func _compute_node_aabb(node: Node) -> AABB:
	var found := false
	var acc := AABB()
	var stack: Array = [node]
	while not stack.is_empty():
		var cur: Node = stack.pop_back()
		if cur is MeshInstance3D and cur.mesh != null:
			var a: AABB = cur.mesh.get_aabb()
			acc = a if not found else acc.merge(a)
			found = true
		for ch in cur.get_children():
			stack.append(ch)
	return acc if found else AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))
