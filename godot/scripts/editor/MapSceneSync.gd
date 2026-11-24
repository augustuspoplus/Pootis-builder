class_name MapSceneSync
extends Node3D

## Live Incremental Synchronizer between Native C++20 Tf2MapDoc
## and Godot 4 Forward+ 3D Scene + Physics Collision + Face-Pull & Vertex Handles
## + Live WorldVertexTransition Dual-Texture Alpha Blending on Sculpted Cliffs/Terrain!

const WVT_EDITOR_SHADER := """
shader_type spatial;
render_mode cull_back, diffuse_lambert;

uniform sampler2D u_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D u_albedo2 : source_color, filter_linear_mipmap_anisotropic, repeat_enable;

void fragment() {
	vec3 a1 = texture(u_albedo, UV).rgb;
	vec3 a2 = texture(u_albedo2, UV).rgb;
	ALBEDO = mix(a1, a2, clamp(COLOR.a, 0.0, 1.0));
	ROUGHNESS = 0.86;
	METALLIC = 0.04;
}
"""

var doc: Object
var assets: RefCounted
var show_skybox_shell: bool = false
var show_tool_volumes: bool = true
var show_clips: bool = true
var show_vertex_handles: bool = false
var selected_solid: int = -1
var selected_solids_group: Array[int] = []
var selected_face: int = -1
var hovered_solid: int = -1

var solids_root: Node3D
var selection_box: MeshInstance3D
var multi_sel_box: MeshInstance3D
var hover_box: MeshInstance3D
var face_handles_root: Node3D
var vertex_handles_root: Node3D

var _solid_nodes: Dictionary = {} # solid_idx -> Node3D
var _solid_sigs: Dictionary = {}  # solid_idx -> String signature for O(dirty) sync_all()!
var _tool_mat_cache: Dictionary = {}
var _wvt_mat_cache: Dictionary = {}
var _wvt_shader: Shader
var _handle_data: Array = [] # [{pos, normal, solid_idx}]
var _vertex_data: Array = [] # [{pos, vert_idx, solid_idx}]
var _hover_im: ImmediateMesh = null
var _sel_im: ImmediateMesh = null
var _multi_sel_im: ImmediateMesh = null
var _wire_mat_hov: StandardMaterial3D = null
var _wire_mat_sel: StandardMaterial3D = null
var _wire_mat_multi: StandardMaterial3D = null
var _face_cone_mesh: CylinderMesh = null
var _face_stem_mesh: CylinderMesh = null
var _face_handle_mats: Dictionary = {}
var _vert_box_mesh: BoxMesh = null
var _vert_mat: StandardMaterial3D = null

func setup(p_doc: Object, p_assets: RefCounted) -> void:
	doc = p_doc
	assets = p_assets
	if _wvt_shader == null:
		_wvt_shader = Shader.new()
		_wvt_shader.code = WVT_EDITOR_SHADER
	if solids_root == null:
		solids_root = Node3D.new()
		solids_root.name = "WorldSolids"
		add_child(solids_root)
	if selection_box == null:
		selection_box = MeshInstance3D.new()
		selection_box.name = "SelectionHighlight"
		selection_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(selection_box)
	if multi_sel_box == null:
		multi_sel_box = MeshInstance3D.new()
		multi_sel_box.name = "MultiSelectionHighlight"
		multi_sel_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(multi_sel_box)
	if hover_box == null:
		hover_box = MeshInstance3D.new()
		hover_box.name = "HoverHighlight"
		hover_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(hover_box)
	if face_handles_root == null:
		face_handles_root = Node3D.new()
		face_handles_root.name = "FacePullHandles"
		add_child(face_handles_root)
	if vertex_handles_root == null:
		vertex_handles_root = Node3D.new()
		vertex_handles_root.name = "VertexHandles"
		add_child(vertex_handles_root)

func clear_all() -> void:
	for k in _solid_nodes.keys():
		var n: Node = _solid_nodes[k]
		if is_instance_valid(n):
			n.queue_free()
	_solid_nodes.clear()
	_solid_sigs.clear()
	selected_solid = -1
	selected_solids_group.clear()
	selected_face = -1
	hovered_solid = -1
	if hover_box != null:
		hover_box.visible = false
	_rebuild_selection_visuals()

func _solid_signature(info: Dictionary) -> String:
	if not info.get("valid", false) or bool(info.get("hidden", false)):
		return "HIDDEN"
	var b0: Vector3 = info["bounds_min"]
	var b1: Vector3 = info["bounds_max"]
	return "%.3f,%.3f,%.3f|%.3f,%.3f,%.3f|%s|%d|%d|%d" % [
		b0.x, b0.y, b0.z, b1.x, b1.y, b1.z, str(info.get("material", "")),
		1 if bool(info.get("is_skybox", false)) else 0,
		1 if show_skybox_shell else 0,
		1 if show_clips else 0
	]

## Smart O(dirty) sync_all: skips untouched world brushes unless force=true!
func sync_all(force: bool = false) -> void:
	if doc == null:
		return
	var count: int = doc.get_solid_count()
	var stale: Array = []
	for k in _solid_nodes.keys():
		if int(k) >= count:
			stale.append(k)
	for k in stale:
		var n: Node = _solid_nodes[k]
		if is_instance_valid(n):
			n.queue_free()
		_solid_nodes.erase(k)
		_solid_sigs.erase(k)
	for i in range(count):
		var info: Dictionary = doc.get_solid_info(i)
		var sig := _solid_signature(info)
		var is_disp: bool = bool(info.get("is_disp", false))
		if not force and not is_disp and _solid_sigs.get(i, "") == sig:
			if sig == "HIDDEN" and not _solid_nodes.has(i):
				continue
			if _solid_nodes.has(i) and is_instance_valid(_solid_nodes[i]) and (_solid_nodes[i] as Node3D).position.is_zero_approx():
				continue
		sync_solid(i)
		_solid_sigs[i] = sig
	if selected_solid >= count:
		selected_solid = -1
		selected_face = -1
	_rebuild_selection_visuals()

## Ultra-fast O(1) visual translate during active gizmo/move drags (zero mesh/physics rebuild!).
## Caller calls sync_solid(idx, true) once on mouse release to bake exact collision & coordinates.
func offset_solid_visual(idx: int, delta: Vector3) -> void:
	if _solid_nodes.has(idx):
		var n: Node3D = _solid_nodes[idx]
		if is_instance_valid(n):
			n.position += delta

func sync_solids(indices: Array, rebuild_collision: bool = true) -> void:
	for raw_id in indices:
		sync_solid(int(raw_id), rebuild_collision)
	_rebuild_selection_visuals()

func sync_solid(idx: int, rebuild_collision: bool = true) -> void:
	if doc == null or idx < 0 or idx >= doc.get_solid_count():
		return
	var d: Dictionary = doc.get_solid_mesh_data(idx)
	var info: Dictionary = doc.get_solid_info(idx)
	_solid_sigs[idx] = _solid_signature(info)
	if not d.get("ok", false) or bool(info.get("hidden", false)):
		if _solid_nodes.has(idx):
			var old_h: Node = _solid_nodes[idx]
			if is_instance_valid(old_h):
				old_h.queue_free()
			_solid_nodes.erase(idx)
		return

	var is_sky: bool = info.get("is_skybox", false)
	var prim_mat: String = str(info.get("material", "")).to_lower()
	var is_clip: bool = prim_mat.find("toolsclip") != -1 or prim_mat.find("toolsplayerclip") != -1

	# Fast path during active face/vertex drag: update mesh in-place without rebuilding ConcavePolygonShape3D!
	var holder: Node3D = null
	if not rebuild_collision and _solid_nodes.has(idx) and is_instance_valid(_solid_nodes[idx]):
		holder = _solid_nodes[idx]
		holder.position = Vector3.ZERO
		var old_mi := holder.get_node_or_null("Mesh")
		if old_mi != null:
			old_mi.queue_free()
	else:
		if _solid_nodes.has(idx):
			var old_n: Node = _solid_nodes[idx]
			if is_instance_valid(old_n):
				old_n.queue_free()
			_solid_nodes.erase(idx)
		holder = Node3D.new()
		holder.name = "Solid_%d" % idx
		holder.set_meta("solid_idx", idx)
		holder.set_meta("is_skybox", is_sky)
		solids_root.add_child(holder)
		_solid_nodes[idx] = holder

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
				if s.has("colors") and (s["colors"] as PackedColorArray).size() == verts.size():
					arrays[Mesh.ARRAY_COLOR] = s["colors"]
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

	if rebuild_collision:
		var col_tris: PackedVector3Array = d.get("collision_faces", PackedVector3Array())
		if col_tris.size() >= 3:
			var sb := StaticBody3D.new()
			sb.name = "Col"
			sb.set_meta("solid_idx", idx)
			sb.set_meta("is_skybox", is_sky)
			sb.collision_layer = 2 if is_sky else 3
			sb.collision_mask = 0
			var cs := CollisionShape3D.new()
			var shape := ConcavePolygonShape3D.new()
			shape.backface_collision = true
			shape.set_faces(col_tris)
			cs.shape = shape
			sb.add_child(cs)
			holder.add_child(sb)

func set_selection(solid_idx: int, face_idx: int = -1) -> void:
	selected_solid = solid_idx
	selected_face = face_idx
	selected_solids_group.clear()
	if solid_idx >= 0:
		selected_solids_group.append(solid_idx)
	_rebuild_selection_visuals()

func set_multi_selection(indices: Array[int], primary_idx: int = -1, face_idx: int = -1) -> void:
	selected_solids_group = indices.duplicate()
	selected_solid = primary_idx if primary_idx >= 0 else (indices[indices.size() - 1] if not indices.is_empty() else -1)
	selected_face = face_idx
	_rebuild_selection_visuals()

func set_vertex_mode(enabled: bool) -> void:
	show_vertex_handles = enabled
	_rebuild_selection_visuals()

func set_hover(solid_idx: int) -> void:
	if hovered_solid == solid_idx:
		return
	hovered_solid = solid_idx
	_ensure_pooled_helpers()
	hover_box.visible = false
	if doc == null or hovered_solid < 0 or hovered_solid == selected_solid or hovered_solid >= doc.get_solid_count():
		return
	var d: Dictionary = doc.get_solid_info(hovered_solid)
	if not d.get("valid", false) or d.get("is_skybox", false) or d.get("hidden", false):
		return
	_update_wire_box(_hover_im, _wire_mat_hov, d["bounds_min"], d["bounds_max"], 0.03)
	hover_box.mesh = _hover_im
	hover_box.visible = true

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
		var grab_r := clampf(proj * 0.068, 0.58, 1.9)
		if dist < grab_r and proj < best_t:
			best_t = proj
			best = h
	return best

func hit_test_vertex_handle(ray_origin: Vector3, ray_dir: Vector3) -> Dictionary:
	var rd := ray_dir.normalized()
	var best_t := 1e9
	var best := {}
	for v in _vertex_data:
		var vp: Vector3 = v["pos"]
		var to_v := vp - ray_origin
		var proj := to_v.dot(rd)
		if proj < 0.1:
			continue
		var closest := ray_origin + rd * proj
		var dist := closest.distance_to(vp)
		var grab_r := clampf(proj * 0.04, 0.28, 0.95)
		if dist < grab_r and proj < best_t:
			best_t = proj
			best = v
	return best

func _update_wire_box(im: ImmediateMesh, mat: StandardMaterial3D, bmin: Vector3, bmax: Vector3, pad_val: float = 0.025) -> void:
	im.clear_surfaces()
	var pad := Vector3(pad_val, pad_val, pad_val)
	var a := bmin - pad
	var b := bmax + pad
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

func _ensure_pooled_helpers() -> void:
	if _hover_im == null:
		_hover_im = ImmediateMesh.new()
		_wire_mat_hov = StandardMaterial3D.new()
		_wire_mat_hov.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wire_mat_hov.albedo_color = Color(0.20, 0.90, 1.0, 0.92)
		_wire_mat_hov.no_depth_test = true
	if _sel_im == null:
		_sel_im = ImmediateMesh.new()
		_wire_mat_sel = StandardMaterial3D.new()
		_wire_mat_sel.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wire_mat_sel.albedo_color = Color(0.98, 0.68, 0.16, 1.0)
		_wire_mat_sel.no_depth_test = true
	if _multi_sel_im == null:
		_multi_sel_im = ImmediateMesh.new()
		_wire_mat_multi = StandardMaterial3D.new()
		_wire_mat_multi.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wire_mat_multi.albedo_color = Color(0.16, 0.88, 1.0, 0.96)
		_wire_mat_multi.no_depth_test = true
	if _face_cone_mesh == null:
		_face_cone_mesh = CylinderMesh.new()
		_face_cone_mesh.top_radius = 0.0
		_face_cone_mesh.bottom_radius = 0.44
		_face_cone_mesh.height = 0.96
	if _face_stem_mesh == null:
		_face_stem_mesh = CylinderMesh.new()
		_face_stem_mesh.top_radius = 0.14
		_face_stem_mesh.bottom_radius = 0.14
		_face_stem_mesh.height = 0.72
	if _vert_box_mesh == null:
		_vert_box_mesh = BoxMesh.new()
		_vert_box_mesh.size = Vector3(0.42, 0.42, 0.42)
		_vert_mat = StandardMaterial3D.new()
		_vert_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_vert_mat.albedo_color = Color(1.0, 0.92, 0.18)
		_vert_mat.no_depth_test = true

func _get_face_mat(col: Color) -> StandardMaterial3D:
	var key := col.to_html(false)
	if not _face_handle_mats.has(key):
		var hm := StandardMaterial3D.new()
		hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hm.albedo_color = col
		hm.no_depth_test = true
		_face_handle_mats[key] = hm
	return _face_handle_mats[key]

func _rebuild_selection_visuals() -> void:
	_ensure_pooled_helpers()
	selection_box.visible = false
	if multi_sel_box != null:
		multi_sel_box.visible = false
	_handle_data.clear()
	_vertex_data.clear()
	for ch in face_handles_root.get_children():
		ch.queue_free()
	for ch in vertex_handles_root.get_children():
		ch.queue_free()

	if doc == null or selected_solid < 0 or selected_solid >= doc.get_solid_count():
		return

	# Draw cyan wireframes around all additional multi-selected solids!
	if multi_sel_box != null and selected_solids_group.size() > 1:
		_multi_sel_im.clear_surfaces()
		var drew_any := false
		var edges := [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]
		for sid in selected_solids_group:
			if sid == selected_solid or sid < 0 or sid >= doc.get_solid_count():
				continue
			var si: Dictionary = doc.get_solid_info(sid)
			if not si.get("valid", false):
				continue
			if not drew_any:
				_multi_sel_im.surface_begin(Mesh.PRIMITIVE_LINES, _wire_mat_multi)
				drew_any = true
			var a: Vector3 = si["bounds_min"] - Vector3(0.03, 0.03, 0.03)
			var b: Vector3 = si["bounds_max"] + Vector3(0.03, 0.03, 0.03)
			var c := [
				Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z),
				Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z),
			]
			for e in edges:
				_multi_sel_im.surface_add_vertex(c[e[0]])
				_multi_sel_im.surface_add_vertex(c[e[1]])
		if drew_any:
			_multi_sel_im.surface_end()
			multi_sel_box.mesh = _multi_sel_im
			multi_sel_box.visible = true

	var d: Dictionary = doc.get_solid_info(selected_solid)
	if not d.get("valid", false):
		return

	var bmin: Vector3 = d["bounds_min"]
	var bmax: Vector3 = d["bounds_max"]
	_update_wire_box(_sel_im, _wire_mat_sel, bmin, bmax, 0.03)
	selection_box.mesh = _sel_im
	selection_box.visible = true

	if show_vertex_handles:
		# Hammer Shift+V Vertex Manipulation Handles (glowing yellow corner cubes!)
		var verts: PackedVector3Array = doc.get_solid_vertices(selected_solid)
		for vi in range(verts.size()):
			var vm := MeshInstance3D.new()
			vm.mesh = _vert_box_mesh
			vm.material_override = _vert_mat
			vm.position = verts[vi]
			vertex_handles_root.add_child(vm)
			_vertex_data.append({"pos": verts[vi], "vert_idx": vi, "solid_idx": selected_solid})
		return

	# 6 interactive BIG 3D Push/Pull Face Arrows (+X,-X,+Y,-Y,+Z,-Z) with bold cone + stem!
	var mid := (bmin + bmax) * 0.5
	var dirs := [
		{"n": Vector3(1, 0, 0),  "pos": Vector3(bmax.x + 1.05, mid.y, mid.z), "col": Color(0.98, 0.30, 0.22)},
		{"n": Vector3(-1, 0, 0), "pos": Vector3(bmin.x - 1.05, mid.y, mid.z), "col": Color(0.98, 0.30, 0.22)},
		{"n": Vector3(0, 1, 0),  "pos": Vector3(mid.x, bmax.y + 1.05, mid.z), "col": Color(1.0, 0.80, 0.16)},
		{"n": Vector3(0, -1, 0), "pos": Vector3(mid.x, bmin.y - 1.05, mid.z), "col": Color(1.0, 0.80, 0.16)},
		{"n": Vector3(0, 0, 1),  "pos": Vector3(mid.x, mid.y, bmax.z + 1.05), "col": Color(0.22, 0.68, 1.0)},
		{"n": Vector3(0, 0, -1), "pos": Vector3(mid.x, mid.y, bmin.z - 1.05), "col": Color(0.22, 0.68, 1.0)},
	]
	for item in dirs:
		var holder := Node3D.new()
		holder.position = item["pos"]
		var n: Vector3 = item["n"]
		if n == Vector3(1, 0, 0):
			holder.rotation_degrees = Vector3(0, 0, -90)
		elif n == Vector3(-1, 0, 0):
			holder.rotation_degrees = Vector3(0, 0, 90)
		elif n == Vector3(0, -1, 0):
			holder.rotation_degrees = Vector3(180, 0, 0)
		elif n == Vector3(0, 0, 1):
			holder.rotation_degrees = Vector3(90, 0, 0)
		elif n == Vector3(0, 0, -1):
			holder.rotation_degrees = Vector3(-90, 0, 0)
		var fmat := _get_face_mat(item["col"])
		var cone := MeshInstance3D.new()
		cone.mesh = _face_cone_mesh
		cone.material_override = fmat
		cone.position = Vector3(0, 0.28, 0)
		holder.add_child(cone)
		var stem := MeshInstance3D.new()
		stem.mesh = _face_stem_mesh
		stem.material_override = fmat
		stem.position = Vector3(0, -0.45, 0)
		holder.add_child(stem)
		face_handles_root.add_child(holder)
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
		var info: Dictionary = assets.get_material_info(mpath)
		if info.get("has_blend", false) and info["tex"] != null and info["tex2"] != null:
			if _wvt_mat_cache.has(low):
				return _wvt_mat_cache[low]
			var sm := ShaderMaterial.new()
			sm.shader = _wvt_shader
			sm.set_shader_parameter("u_albedo", info["tex"])
			sm.set_shader_parameter("u_albedo2", info["tex2"])
			_wvt_mat_cache[low] = sm
			return sm
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
