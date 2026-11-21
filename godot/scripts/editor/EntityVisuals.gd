class_name EntityVisuals
extends Node3D

## Milestone 5 + 17 — Real 3D TF2 .mdl Entity Visualizer + 3D Spline Track Ribbon
## + Glowing 3D Bezier Logic Wires + Dynamic Point Lights + VisGroups + Selection/Hover Boxes.

var doc: Object
var assets: RefCounted
var door_ctrl: Node = null
var show_logic_wires: bool = true
var show_logic_markers: bool = false # Keep mid-air tf_gamerules/tf_logic_* markers hidden unless toggled in VisGroups!
var show_volumes: bool = true
var show_triggers: bool = true
var show_props: bool = true
var show_lights: bool = true
var selected_entity: int = -1
var hovered_entity: int = -1

var ents_root: Node3D
var wires_mesh: MeshInstance3D
var track_mesh: MeshInstance3D
var selection_box: MeshInstance3D
var hover_box: MeshInstance3D

var _ent_bounds: Dictionary = {} # ent_idx -> [bmin: Vector3, bmax: Vector3]

const ENTITY_MODELS := {
	"item_healthkit_small":  "models/items/medkit_small.mdl",
	"item_healthkit_medium": "models/items/medkit_medium.mdl",
	"item_healthkit_full":   "models/items/medkit_large.mdl",
	"item_ammopack_small":   "models/items/ammopack_small.mdl",
	"item_ammopack_medium":  "models/items/ammopack_medium.mdl",
	"item_ammopack_full":    "models/items/ammopack_large.mdl",
	"item_teamflag":         "models/flag/briefcase.mdl",
}

func setup(p_doc: Object, p_assets: RefCounted) -> void:
	doc = p_doc
	assets = p_assets
	if ents_root == null:
		ents_root = Node3D.new()
		ents_root.name = "Entities"
		add_child(ents_root)
	if wires_mesh == null:
		wires_mesh = MeshInstance3D.new()
		wires_mesh.name = "LogicWires3D"
		wires_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wires_mesh)
	if track_mesh == null:
		track_mesh = MeshInstance3D.new()
		track_mesh.name = "PayloadTracks3D"
		track_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(track_mesh)
	if selection_box == null:
		selection_box = MeshInstance3D.new()
		selection_box.name = "EntitySelectionHighlight"
		selection_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(selection_box)
	if hover_box == null:
		hover_box = MeshInstance3D.new()
		hover_box.name = "EntityHoverHighlight"
		hover_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(hover_box)

func clear_all() -> void:
	if ents_root != null:
		for ch in ents_root.get_children():
			ch.queue_free()
	if wires_mesh != null:
		wires_mesh.mesh = null
	if track_mesh != null:
		track_mesh.mesh = null
	_ent_bounds.clear()
	selected_entity = -1
	hovered_entity = -1
	_rebuild_highlight_boxes()

func sync_all() -> void:
	if doc == null:
		return
	if door_ctrl != null:
		door_ctrl.clear()
	for ch in ents_root.get_children():
		ch.queue_free()
	wires_mesh.mesh = null
	track_mesh.mesh = null
	_ent_bounds.clear()

	var ents: Array = doc.get_entities()
	var target_pos := {} # targetname -> Vector3
	for i in range(ents.size()):
		var e: Dictionary = ents[i]
		var pos: Vector3 = e["pos"]
		if e.get("is_brush", false):
			pos = (e["bounds_min"] + e["bounds_max"]) * 0.5
		var kv: Dictionary = e["kv"]
		var tname: String = str(kv.get("targetname", ""))
		if not tname.is_empty():
			target_pos[tname] = pos
		_spawn_entity_node(i, e, pos)

	_rebuild_wires_and_tracks(ents, target_pos)
	if selected_entity >= ents.size():
		selected_entity = -1
	if hovered_entity >= ents.size():
		hovered_entity = -1
	_rebuild_highlight_boxes()

func set_selection(ent_idx: int) -> void:
	selected_entity = ent_idx
	_rebuild_highlight_boxes()

func set_hover(ent_idx: int) -> void:
	if hovered_entity == ent_idx:
		return
	hovered_entity = ent_idx
	_rebuild_highlight_boxes()

func _rebuild_highlight_boxes() -> void:
	if selection_box != null:
		selection_box.mesh = null
		if selected_entity >= 0 and _ent_bounds.has(selected_entity):
			var bb: Array = _ent_bounds[selected_entity]
			selection_box.mesh = _make_wire_box(bb[0], bb[1], Color(0.98, 0.68, 0.16, 1.0), 0.06)
	if hover_box != null:
		hover_box.mesh = null
		if hovered_entity >= 0 and hovered_entity != selected_entity and _ent_bounds.has(hovered_entity):
			var bb: Array = _ent_bounds[hovered_entity]
			hover_box.mesh = _make_wire_box(bb[0], bb[1], Color(0.20, 0.90, 1.0, 0.92), 0.05)

func _make_wire_box(bmin: Vector3, bmax: Vector3, col: Color, pad_val: float = 0.04) -> ImmediateMesh:
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

func _spawn_entity_node(idx: int, e: Dictionary, pos: Vector3) -> void:
	var cls: String = str(e["classname"])
	var kv: Dictionary = e["kv"]
	var is_brush: bool = e.get("is_brush", false)
	var holder := Node3D.new()
	holder.name = "Ent_%d_%s" % [idx, cls]
	holder.position = pos
	holder.set_meta("entity_idx", idx)
	holder.set_meta("classname", cls)

	var yaw_deg := _parse_yaw(str(kv.get("angles", "0 0 0")))

	# 1. Explicit prop model (prop_static / prop_dynamic / prop_physics) or known gameplay .mdl!
	var mdl_path: String = str(kv.get("model", ""))
	if mdl_path.is_empty() and ENTITY_MODELS.has(cls):
		mdl_path = ENTITY_MODELS[cls]

	if not mdl_path.is_empty() and mdl_path.to_lower().ends_with(".mdl") and assets != null:
		if not show_props and cls.begins_with("prop_"):
			return
		var mesh: ArrayMesh = assets.get_model_mesh(mdl_path)
		if mesh != null:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.rotation_degrees = Vector3(0, yaw_deg, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			holder.add_child(mi)
			ents_root.add_child(holder)
			var aabb := mesh.get_aabb()
			var bmin := pos + aabb.position
			var bmax := pos + aabb.position + aabb.size
			_ent_bounds[idx] = [bmin, bmax]
			return

	# 2. Brush Entities (func_door, trigger_*, func_respawnroom, func_capturezone, func_upgradestation, func_detail)
	if is_brush:
		var is_trig := cls.begins_with("trigger_") or cls == "func_respawnroom" or cls == "func_capturezone" or cls == "func_nobuild"
		if (not show_volumes or not show_triggers) and is_trig:
			ents_root.add_child(holder)
			return
		var bmin: Vector3 = e["bounds_min"]
		var bmax: Vector3 = e["bounds_max"]
		_ent_bounds[idx] = [bmin, bmax]
		var sz := (bmax - bmin).max(Vector3(0.2, 0.2, 0.2))

		# Build ACTUAL textured 3D brush mesh from doc.get_entity_mesh_data(idx) for solid brush entities
		# (func_detail, func_door, func_wall, etc.) so Ctrl+T never turns ramps/arches into untextured boxes!
		var built_real_mesh: ArrayMesh = null
		var built_col: PackedVector3Array = PackedVector3Array()
		if not is_trig and cls != "func_water" and cls != "func_upgradestation" and doc.has_method("get_entity_mesh_data"):
			var md: Dictionary = doc.get_entity_mesh_data(idx)
			if md.get("ok", false):
				built_real_mesh = ArrayMesh.new()
				for s in md["surfaces"]:
					var arr := []
					arr.resize(Mesh.ARRAY_MAX)
					var verts: PackedVector3Array = s["vertices"]
					var local_v := PackedVector3Array()
					local_v.resize(verts.size())
					for vi in range(verts.size()):
						local_v[vi] = verts[vi] - pos
					arr[Mesh.ARRAY_VERTEX] = local_v
					arr[Mesh.ARRAY_NORMAL] = s["normals"]
					arr[Mesh.ARRAY_TEX_UV] = s["uvs"]
					arr[Mesh.ARRAY_INDEX] = s["indices"]
					built_real_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
					var si := built_real_mesh.get_surface_count() - 1
					built_real_mesh.surface_set_material(si, assets.get_material(str(s["material"]), false))
				var raw_col: PackedVector3Array = md.get("collision_faces", PackedVector3Array())
				built_col.resize(raw_col.size())
				for ci in range(raw_col.size()):
					built_col[ci] = raw_col[ci] - pos

		var mi := MeshInstance3D.new()
		if built_real_mesh != null:
			mi.mesh = built_real_mesh
		else:
			var bm := BoxMesh.new()
			bm.size = sz
			mi.mesh = bm

		if cls == "func_door":
			# Make custom func_door solid & interactive so F5 playtest slides it open smoothly!
			var ab := AnimatableBody3D.new()
			ab.sync_to_physics = false
			ab.collision_layer = 1
			ab.collision_mask = 0
			ab.position = pos
			if built_real_mesh == null:
				var dmat := StandardMaterial3D.new()
				dmat.albedo_color = Color(0.55, 0.60, 0.65, 1.0)
				mi.material_override = dmat
			ab.add_child(mi)
			var cs := CollisionShape3D.new()
			if built_col.size() >= 3:
				var poly := ConcavePolygonShape3D.new()
				poly.backface_collision = true
				poly.set_faces(built_col)
				cs.shape = poly
			else:
				var bs := BoxShape3D.new()
				bs.size = sz
				cs.shape = bs
			ab.add_child(cs)
			ents_root.add_child(ab)
			if door_ctrl != null:
				var mdir := Vector3.UP
				var mparts := str(kv.get("movedir", "-90 0 0")).split(" ", false)
				if mparts.size() >= 2:
					var pr := deg_to_rad(float(mparts[0]))
					var yr := deg_to_rad(float(mparts[1]))
					mdir = Vector3(cos(pr) * cos(yr), -sin(pr), -cos(pr) * sin(yr)).normalized()
				var spd := maxf(4.0, float(str(kv.get("speed", "320"))) / 32.0)
				var trav := maxf(2.4, absf(mdir.x) * sz.x + absf(mdir.y) * sz.y + absf(mdir.z) * sz.z - 0.15)
				door_ctrl.register_door(ab, pos, mdir, trav, spd, maxf(4.5, sz.length() * 0.8 + 2.0), str(kv.get("targetname", "")))
			return

		if built_real_mesh != null:
			# Solid world-textured brush entity (func_detail, func_wall, etc.) — also add static collision for F5!
			var sb := StaticBody3D.new()
			sb.collision_layer = 1
			sb.collision_mask = 0
			sb.add_child(mi)
			if built_col.size() >= 3:
				var cs := CollisionShape3D.new()
				var poly := ConcavePolygonShape3D.new()
				poly.backface_collision = true
				poly.set_faces(built_col)
				cs.shape = poly
				sb.add_child(cs)
			holder.add_child(sb)
			ents_root.add_child(holder)
			return

		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var col := Color(0.95, 0.65, 0.16, 0.22)
		if cls == "func_respawnroom":
			col = Color(0.85, 0.22, 0.18, 0.16) if str(kv.get("TeamNum", "2")) == "2" else Color(0.22, 0.52, 0.85, 0.16)
		elif cls == "func_water":
			col = Color(0.18, 0.55, 0.78, 0.52)
		elif cls == "trigger_hurt":
			col = Color(0.96, 0.16, 0.16, 0.34)
		elif cls == "trigger_push":
			col = Color(0.20, 0.86, 0.72, 0.32)
		elif cls == "func_capturezone" or cls == "trigger_capture_area":
			col = Color(0.98, 0.78, 0.18, 0.22)
		elif cls == "func_upgradestation":
			col = Color(0.68, 0.36, 0.95, 0.28)
		mat.albedo_color = col
		mi.material_override = mat
		holder.add_child(mi)
		ents_root.add_child(holder)
		return

	# 3. Team Spawn Beacon (Real ABS 3D Engineer Model when available, else 83u Heavy Reference!)
	if cls == "info_player_teamspawn":
		var team := int(str(kv.get("TeamNum", "2")).to_int())
		var tname := str(kv.get("targetname", "")).to_lower()
		var col := Color(0.86, 0.25, 0.20) if team == 2 else Color(0.22, 0.52, 0.84)
		if tname.find("spawnbot") != -1:
			col = Color(0.66, 0.28, 0.92) # MvM Robot spawn!
		var engy_mesh: ArrayMesh = assets.get_model_mesh("models/editor-abs/dev_engy.mdl") if assets != null else null
		if engy_mesh != null:
			var emi := MeshInstance3D.new()
			emi.mesh = engy_mesh
			emi.rotation_degrees = Vector3(0, yaw_deg, 0)
			# Subtle team tint pedestal ring underneath so RED/BLU/Bot is instant at a glance!
			var ring := MeshInstance3D.new()
			var rmesh := CylinderMesh.new()
			rmesh.top_radius = 0.72; rmesh.bottom_radius = 0.76; rmesh.height = 0.10
			ring.mesh = rmesh
			ring.position = Vector3(0, 0.05, 0)
			var rmat := StandardMaterial3D.new()
			rmat.albedo_color = col
			rmat.emission_enabled = true; rmat.emission = col; rmat.emission_energy_multiplier = 0.55
			ring.material_override = rmat
			holder.add_child(emi)
			holder.add_child(ring)
			ents_root.add_child(holder)
			_ent_bounds[idx] = [pos + Vector3(-0.75, 0.0, -0.75), pos + Vector3(0.75, 2.55, 0.75)]
			return
		var cyl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.62
		cm.bottom_radius = 0.72
		cm.height = 2.55 # ~82u TF2 Heavy player height!
		cyl.mesh = cm
		cyl.position = Vector3(0, 1.28, 0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(col.r, col.g, col.b, 0.65)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 0.45
		cyl.material_override = mat
		holder.add_child(cyl)
		ents_root.add_child(holder)
		_ent_bounds[idx] = [pos + Vector3(-0.75, 0.0, -0.75), pos + Vector3(0.75, 2.6, 0.75)]
		return

	# 4. Real Godot OmniLight3D + glowing bulb for TF2 point lights!
	if cls == "light" or cls == "light_spot":
		if not show_lights:
			return
		var lcol := _parse_light_color(str(kv.get("_light", "255 240 210 300")))
		var omni := OmniLight3D.new()
		omni.light_color = lcol
		omni.light_energy = 1.35
		omni.omni_range = 16.0
		omni.shadow_enabled = false
		holder.add_child(omni)

		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.28
		bulb.mesh = sm
		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.albedo_color = lcol
		bulb.material_override = bmat
		holder.add_child(bulb)
		ents_root.add_child(holder)
		_ent_bounds[idx] = [pos - Vector3(0.35, 0.35, 0.35), pos + Vector3(0.35, 0.35, 0.35)]
		return

	# 5. Path Track node (yellow rail beacon)
	if cls == "path_track":
		var node_m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.32
		node_m.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.98, 0.78, 0.18)
		node_m.material_override = mat
		holder.add_child(node_m)
		ents_root.add_child(holder)
		_ent_bounds[idx] = [pos - Vector3(0.4, 0.4, 0.4), pos + Vector3(0.4, 0.4, 0.4)]
		return

	# 6. Generic Logic Entity icon badge (hidden by default unless toggled in VisGroups so sky stays clean!)
	if cls != "light_environment" and show_logic_markers:
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.32, 0.32, 0.32)
		box.mesh = bm
		box.rotation_degrees = Vector3(45, 45, 0)
		var mat := StandardMaterial3D.new()
		var base_c := Color(0.86, 0.56, 0.24, 0.55) if cls.begins_with("tf_logic") else Color(0.36, 0.68, 0.82, 0.50)
		mat.albedo_color = base_c
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		box.material_override = mat
		holder.add_child(box)
		ents_root.add_child(holder)
		_ent_bounds[idx] = [pos - Vector3(0.28, 0.28, 0.28), pos + Vector3(0.28, 0.28, 0.28)]

func _rebuild_wires_and_tracks(ents: Array, target_pos: Dictionary) -> void:
	# 1. Payload / Tank 3D Spline Track Lines
	var tim := ImmediateMesh.new()
	var tmat := StandardMaterial3D.new()
	tmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tmat.albedo_color = Color(0.98, 0.78, 0.16)
	var has_track := false
	for e in ents:
		if str(e["classname"]) == "path_track":
			var nxt: String = str(e["kv"].get("target", ""))
			if not nxt.is_empty() and target_pos.has(nxt):
				if not has_track:
					tim.surface_begin(Mesh.PRIMITIVE_LINES, tmat)
					has_track = true
				var p0: Vector3 = e["pos"]
				var p1: Vector3 = target_pos[nxt]
				var side := (p1 - p0).cross(Vector3.UP).normalized() * 0.42
				tim.surface_add_vertex(p0 + side)
				tim.surface_add_vertex(p1 + side)
				tim.surface_add_vertex(p0 - side)
				tim.surface_add_vertex(p1 - side)
				tim.surface_add_vertex(p0 + Vector3(0, 0.12, 0))
				tim.surface_add_vertex(p1 + Vector3(0, 0.12, 0))
	if has_track:
		tim.surface_end()
		track_mesh.mesh = tim

	if not show_logic_wires:
		return

	# 2. Glowing 3D Bezier Logic Wires for all Entity I/O Connections!
	var wim := ImmediateMesh.new()
	var wmat := StandardMaterial3D.new()
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wmat.albedo_color = Color(0.24, 0.92, 0.98)
	wmat.no_depth_test = true
	var has_wires := false
	for e in ents:
		var src_pos: Vector3 = e["pos"]
		if e.get("is_brush", false):
			src_pos = (e["bounds_min"] + e["bounds_max"]) * 0.5
		var conns: Array = e.get("connections", [])
		for c in conns:
			var args: String = str(c.get("args", ""))
			var parts := args.split(",")
			if parts.size() >= 1:
				var tgt := parts[0].strip_edges()
				if target_pos.has(tgt):
					if not has_wires:
						wim.surface_begin(Mesh.PRIMITIVE_LINES, wmat)
						has_wires = true
					var p0 := src_pos
					var p2: Vector3 = target_pos[tgt]
					var ctrl := (p0 + p2) * 0.5 + Vector3(0, max(2.0, p0.distance_to(p2) * 0.25), 0)
					var prev := p0
					for s in range(1, 13):
						var t := float(s) / 12.0
						var cur := (1.0 - t) * (1.0 - t) * p0 + 2.0 * (1.0 - t) * t * ctrl + t * t * p2
						wim.surface_add_vertex(prev)
						wim.surface_add_vertex(cur)
						prev = cur
	if has_wires:
		wim.surface_end()
		wires_mesh.mesh = wim

func _parse_yaw(angles_str: String) -> float:
	var parts := angles_str.split(" ", false)
	if parts.size() >= 2:
		return float(parts[1])
	return 0.0

func _parse_light_color(light_str: String) -> Color:
	var parts := light_str.split(" ", false)
	if parts.size() >= 3:
		return Color(
			clamp(float(parts[0]) / 255.0, 0.0, 1.0),
			clamp(float(parts[1]) / 255.0, 0.0, 1.0),
			clamp(float(parts[2]) / 255.0, 0.0, 1.0)
		)
	return Color(1.0, 0.94, 0.82)
