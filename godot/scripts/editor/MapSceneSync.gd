class_name MapSceneSync
extends Node3D

## Milestone 4 — Live Incremental Synchronizer between Native C++20 Tf2MapDoc
## and the Godot 4 Forward+ 3D Scene + Physics Collision + Face-Pull Handles.

var doc: Object
var assets: RefCounted
var show_skybox_shell: bool = false
var show_tool_volumes: bool = true
var show_clips: bool = true
var selected_solid: int = -1
var selected_face: int = -1
var hovered_solid: int = -1

var solids_root: Node3D
var selection_box: MeshInstance3D
var hover_box: MeshInstance3D
var face_handles_root: Node3D

var _solid_nodes: Dictionary = {} # solid_idx -> Node3D
var _tool_mat_cache: Dictionary = {}
var _handle_data: Array = [] # [{pos, normal, solid_idx}]

func setup(p_doc: Object, p_assets: RefCounted) -> void:
	doc = p_doc
	assets = p_assets
	if solids_root == null:
		solids_root = Node3D.new()
		solids_root.name = "WorldSolids"
		add_child(solids_root)
	if selection_box == null:
		selection_box = MeshInstance3D.new()
		selection_box.name = "SelectionHighlight"
		selection_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(selection_box)
	if hover_box == null:
		hover_box = MeshInstance3D.new()
		hover_box.name = "HoverHighlight"
		hover_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(hover_box)
	if face_handles_root == null:
		face_handles_root = Node3D.new()
		face_handles_root.name = "FacePullHandles"
		add_child(face_handles_root)

func clear_all() -> void:
	for k in _solid_nodes.keys():
		var n: Node = _solid_nodes[k]
		if is_instance_valid(n):
			n.queue_free()
	_solid_nodes.clear()
	selected_solid = -1
	selected_face = -1
	_rebuild_selection_visuals()

func sync_all() -> void:
	if doc == null:
		return
	var count: int = doc.get_solid_count()
	# Remove nodes whose indices no longer exist
	var stale: Array = []
	for k in _solid_nodes.keys():
		if int(k) >= count:
			stale.append(k)
	for k in stale:
		var n: Node = _solid_nodes[k]
		if is_instance_valid(n):
			n.queue_free()
		_solid_nodes.erase(k)
	for i in range(count):
		sync_solid(i)
	if selected_solid >= count:
		selected_solid = -1
		selected_face = -1
	_rebuild_selection_visuals()

func sync_solid(idx: int) -> void:
	if doc == null or idx < 0 or idx >= doc.get_solid_count():
		return
	if _solid_nodes.has(idx):
		var old_n: Node = _solid_nodes[idx]
		if is_instance_valid(old_n):
			old_n.queue_free()
		_solid_nodes.erase(idx)

	var d: Dictionary = doc.get_solid_mesh_data(idx)
	var info: Dictionary = doc.get_solid_info(idx)
	if not d.get("ok", false):
		return

	var is_sky: bool = info.get("is_skybox", false)
	var prim_mat: String = str(info.get("material", "")).to_lower()
	var is_clip: bool = prim_mat.find("toolsclip") != -1 or prim_mat.find("toolsplayerclip") != -1
	var holder := Node3D.new()
	holder.name = "Solid_%d" % idx
	holder.set_meta("solid_idx", idx)
	holder.set_meta("is_skybox", is_sky)

	# Visual mesh (skip skybox sealing shell unless show_skybox_shell is enabled; hide clips when show_clips is false)
	if (not is_sky or show_skybox_shell) and (not is_clip or show_clips):
		var surfaces: Array = d["surfaces"]
		if surfaces.size() > 0:
			var mesh := ArrayMesh.new()
			for s in surfaces:
				var mpath: String = String(s["material"])
				if is_sky and not show_skybox_shell:
					continue
				var verts: PackedVector3Array = s["vertices"]
				var norms: PackedVector3Array = s["normals"]
				var uvs: PackedVector2Array = s["uvs"]
				var idxs: PackedInt32Array = s["indices"]
				if verts.is_empty() or idxs.is_empty():
					continue
				var arrays := []
				arrays.resize(Mesh.ARRAY_MAX)
				arrays[Mesh.ARRAY_VERTEX] = verts
				arrays[Mesh.ARRAY_NORMAL] = norms
				arrays[Mesh.ARRAY_TEX_UV] = uvs
				arrays[Mesh.ARRAY_INDEX] = idxs
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				var sidx := mesh.get_surface_count() - 1
				mesh.surface_set_material(sidx, _resolve_material(mpath, is_sky))

			if mesh.get_surface_count() > 0:
				var mi := MeshInstance3D.new()
				mi.name = "Mesh"
				mi.mesh = mesh
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if is_sky else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				holder.add_child(mi)

	# Physics collision (always active for walkable geometry & skybox boundaries in F5 playtest)
	var col_tris: PackedVector3Array = d.get("collision_faces", PackedVector3Array())
	if col_tris.size() >= 3:
		var sb := StaticBody3D.new()
		sb.name = "Col"
		sb.set_meta("solid_idx", idx)
		sb.set_meta("is_skybox", is_sky)
		# Skybox stays on layer 2 (blocks player, ignored by editor raycasts on layer 1)
		sb.collision_layer = 2 if is_sky else 3
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(col_tris)
		cs.shape = shape
		sb.add_child(cs)
		holder.add_child(sb)

	solids_root.add_child(holder)
	_solid_nodes[idx] = holder

func set_selection(solid_idx: int, face_idx: int = -1) -> void:
	selected_solid = solid_idx
	selected_face = face_idx
	_rebuild_selection_visuals()

func set_hover(solid_idx: int) -> void:
	if hovered_solid == solid_idx:
		return
	hovered_solid = solid_idx
	hover_box.mesh = null
	if doc == null or hovered_solid < 0 or hovered_solid == selected_solid or hovered_solid >= doc.get_solid_count():
		return
	var d: Dictionary = doc.get_solid_info(hovered_solid)
	if not d.get("valid", false) or d.get("is_skybox", false):
		return
	hover_box.mesh = _make_wire_box(d["bounds_min"], d["bounds_max"], Color(0.20, 0.90, 1.0, 0.92), 0.03)

func hit_test_face_handle(ray_origin: Vector3, ray_dir: Vector3) -> Dictionary:
	var rd := ray_dir.normalized()
	var best_t := 1e9
	var best := {}
	for h in _handle_data:
		var hp: Vector3 = h["pos"]
		var to_h := hp - ray_origin
		var proj := to_h.dot(rd)
		if proj < 0.1:
			continue
		var closest := ray_origin + rd * proj
		var dist := closest.distance_to(hp)
		var grab_r := clampf(proj * 0.045, 0.32, 1.15)
		if dist < grab_r and proj < best_t:
			best_t = proj
			best = h
	return best

func _make_wire_box(bmin: Vector3, bmax: Vector3, col: Color, pad_val: float = 0.025) -> ImmediateMesh:
	var pad := Vector3(pad_val, pad_val, pad_val)
	var a := bmin - pad
	var b := bmax + pad
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.no_depth_test = true
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	var corners := [
		Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z),
		Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z),
		Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z),
		Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z),
	]
	var edges := [
		[0,1],[1,2],[2,3],[3,0],
		[4,5],[5,6],[6,7],[7,4],
		[0,4],[1,5],[2,6],[3,7],
	]
	for e in edges:
		im.surface_add_vertex(corners[e[0]])
		im.surface_add_vertex(corners[e[1]])
	im.surface_end()
	return im

func _rebuild_selection_visuals() -> void:
	selection_box.mesh = null
	_handle_data.clear()
	for ch in face_handles_root.get_children():
		ch.queue_free()

	if doc == null or selected_solid < 0 or selected_solid >= doc.get_solid_count():
		return

	var d: Dictionary = doc.get_solid_info(selected_solid)
	if not d.get("valid", false):
		return

	var bmin: Vector3 = d["bounds_min"]
	var bmax: Vector3 = d["bounds_max"]
	selection_box.mesh = _make_wire_box(bmin, bmax, Color(0.98, 0.68, 0.16, 1.0), 0.03)

	# 6 interactive 3D Push/Pull Face Handles (+X,-X,+Y,-Y,+Z,-Z) — bigger & easier to grab!
	var mid := (bmin + bmax) * 0.5
	var dirs := [
		{"n": Vector3(1, 0, 0),  "pos": Vector3(bmax.x + 0.55, mid.y, mid.z), "col": Color(0.95, 0.30, 0.22)},
		{"n": Vector3(-1, 0, 0), "pos": Vector3(bmin.x - 0.55, mid.y, mid.z), "col": Color(0.95, 0.30, 0.22)},
		{"n": Vector3(0, 1, 0),  "pos": Vector3(mid.x, bmax.y + 0.55, mid.z), "col": Color(0.98, 0.76, 0.18)},
		{"n": Vector3(0, -1, 0), "pos": Vector3(mid.x, bmin.y - 0.55, mid.z), "col": Color(0.98, 0.76, 0.18)},
		{"n": Vector3(0, 0, 1),  "pos": Vector3(mid.x, mid.y, bmax.z + 0.55), "col": Color(0.24, 0.66, 0.96)},
		{"n": Vector3(0, 0, -1), "pos": Vector3(mid.x, mid.y, bmin.z - 0.55), "col": Color(0.24, 0.66, 0.96)},
	]
	for item in dirs:
		var handle := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.22
		cone.height = 0.52
		handle.mesh = cone
		var hmat := StandardMaterial3D.new()
		hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hmat.albedo_color = item["col"]
		hmat.no_depth_test = true
		handle.material_override = hmat
		handle.position = item["pos"]
		var n: Vector3 = item["n"]
		if n == Vector3(1, 0, 0):
			handle.rotation_degrees = Vector3(0, 0, -90)
		elif n == Vector3(-1, 0, 0):
			handle.rotation_degrees = Vector3(0, 0, 90)
		elif n == Vector3(0, -1, 0):
			handle.rotation_degrees = Vector3(180, 0, 0)
		elif n == Vector3(0, 0, 1):
			handle.rotation_degrees = Vector3(90, 0, 0)
		elif n == Vector3(0, 0, -1):
			handle.rotation_degrees = Vector3(-90, 0, 0)
		face_handles_root.add_child(handle)
		_handle_data.append({"pos": item["pos"], "normal": n, "solid_idx": selected_solid})

func _resolve_material(mpath: String, is_sky: bool) -> Material:
	var low := mpath.to_lower()
	if is_sky or low.find("toolsskybox") != -1:
		return _get_tool_mat("skybox", Color(0.38, 0.72, 0.98, 0.14))
	if low.find("toolsplayerclip") != -1 or low.find("toolsclip") != -1:
		return _get_tool_mat("clip", Color(0.92, 0.25, 0.55, 0.28))
	if low.find("toolstrigger") != -1:
		return _get_tool_mat("trigger", Color(0.95, 0.62, 0.14, 0.32))
	if low.find("toolsnodraw") != -1:
		return _get_tool_mat("nodraw", Color(0.88, 0.78, 0.18, 0.95))
	if assets != null:
		return assets.get_material(mpath, false)
	return _get_tool_mat("default", Color(0.6, 0.56, 0.52, 1.0))

func _get_tool_mat(key: String, col: Color) -> StandardMaterial3D:
	if _tool_mat_cache.has(key):
		return _tool_mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	if col.a < 0.99:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tool_mat_cache[key] = m
	return m
