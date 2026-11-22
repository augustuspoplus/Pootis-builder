class_name EntityVisuals
extends Node3D

## Milestone 5 + 17 — Real 3D TF2 .mdl Entity Visualizer + 3D Spline Track Ribbon
## + Glowing 3D Bezier Logic Wires + Dynamic Point Lights + VisGroups + Selection/Hover Boxes.

const Tf2CatalogScript = preload("res://scripts/core/Tf2Catalog.gd")

var doc: Object
var assets: RefCounted
var door_ctrl: Node = null
var show_logic_wires: bool = true
var show_logic_markers: bool = true # Show crisp 3D billboard icons on ALL placed entities so none are invisible!
var show_volumes: bool = true
var show_triggers: bool = true
var show_props: bool = true
var show_lights: bool = true
var playtest_mode: bool = false
var selected_entity: int = -1
var hovered_entity: int = -1

var ents_root: Node3D
var wires_mesh: MeshInstance3D
var track_mesh: MeshInstance3D
var selection_box: MeshInstance3D
var hover_box: MeshInstance3D

var _ent_bounds: Dictionary = {} # ent_idx -> [bmin: Vector3, bmax: Vector3]
var _ent_nodes: Dictionary = {}  # ent_idx -> Node3D (for O(1) incremental sync without rebuilding entire scene!)
var _badge_tex_cache: Dictionary = {} # kind -> ImageTexture
var _editor_only_nodes: Array[Node3D] = []
var _light_nodes: Array[Light3D] = []
var lighting_preview_mode: int = 0 # 0=Daylight, 1=Lit Interior, 2=Fullbright
var cart_visual_node: Node3D = null
var _cart_orig_pos: Vector3 = Vector3.ZERO
var _cart_orig_rot: Vector3 = Vector3.ZERO
var _sel_im: ImmediateMesh = null
var _hov_im: ImmediateMesh = null
var _wire_mat_sel: StandardMaterial3D = null
var _wire_mat_hov: StandardMaterial3D = null

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
	_ent_nodes.clear()
	_editor_only_nodes.clear()
	_light_nodes.clear()
	cart_visual_node = null
	_light_nodes.clear()
	cart_visual_node = null
	selected_entity = -1
	hovered_entity = -1
	_rebuild_highlight_boxes()

func set_lighting_preview_mode(mode: int) -> void:
	lighting_preview_mode = clampi(mode, 0, 2)
	for ln in _light_nodes:
		if not is_instance_valid(ln):
			continue
		var base_e: float = float(ln.get_meta("base_energy", 1.35))
		if lighting_preview_mode == 1: # Lit Interior Preview (boost interior lights + enable shadow on key spots!)
			ln.visible = show_lights
			ln.light_energy = base_e * 1.65
			if ln is SpotLight3D:
				ln.shadow_enabled = true
		elif lighting_preview_mode == 2: # Fullbright Blockout
			ln.visible = false
		else: # Daylight
			ln.visible = show_lights
			ln.light_energy = base_e
			ln.shadow_enabled = false

func move_cart_visual(world_pos: Vector3, yaw_rad: float) -> void:
	if cart_visual_node != null and is_instance_valid(cart_visual_node):
		cart_visual_node.position = world_pos
		cart_visual_node.rotation = Vector3(0.0, yaw_rad, 0.0)

func reset_cart_visual() -> void:
	if cart_visual_node != null and is_instance_valid(cart_visual_node):
		cart_visual_node.position = _cart_orig_pos
		cart_visual_node.rotation = _cart_orig_rot

func set_playtest_mode(on: bool) -> void:
	playtest_mode = on
	for n in _editor_only_nodes:
		if is_instance_valid(n):
			n.visible = not on
	if wires_mesh != null:
		wires_mesh.visible = (not on) and show_logic_wires
	if selection_box != null:
		selection_box.visible = not on
	if hover_box != null:
		hover_box.visible = not on

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
	_ent_nodes.clear()
	_editor_only_nodes.clear()
	_light_nodes.clear()
	cart_visual_node = null

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
		var spawned := _spawn_entity_node(i, e, pos)
		if spawned != null:
			_ent_nodes[i] = spawned

	_rebuild_wires_and_tracks(ents, target_pos)
	if selected_entity >= ents.size():
		selected_entity = -1
	if hovered_entity >= ents.size():
		hovered_entity = -1
	_rebuild_highlight_boxes()

## Fast O(1) incremental single-entity update + optional spring pop-in animation!
func sync_entity(idx: int, animate_pop: bool = false) -> void:
	if doc == null or idx < 0:
		return
	var ents: Array = doc.get_entities()
	if idx >= ents.size():
		sync_all()
		return
	if _ent_nodes.has(idx):
		var old_n: Node3D = _ent_nodes[idx]
		if is_instance_valid(old_n):
			old_n.queue_free()
		_ent_nodes.erase(idx)
	_ent_bounds.erase(idx)
	var e: Dictionary = ents[idx]
	var pos: Vector3 = e["pos"]
	if e.get("is_brush", false):
		pos = (e["bounds_min"] + e["bounds_max"]) * 0.5
	var spawned := _spawn_entity_node(idx, e, pos)
	if spawned != null:
		_ent_nodes[idx] = spawned
		if animate_pop and is_inside_tree():
			spawned.scale = Vector3(0.05, 0.05, 0.05)
			var tw := create_tween()
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tw.tween_property(spawned, "scale", Vector3.ONE, 0.22)
	if str(e["classname"]) == "path_track" or not (e.get("connections", []) as Array).is_empty():
		var target_pos := {}
		for i in range(ents.size()):
			var oe: Dictionary = ents[i]
			var tn: String = str(oe["kv"].get("targetname", ""))
			if not tn.is_empty():
				target_pos[tn] = (oe["bounds_min"] + oe["bounds_max"]) * 0.5 if oe.get("is_brush", false) else oe["pos"]
		_rebuild_wires_and_tracks(ents, target_pos)
	_rebuild_highlight_boxes()

func set_selection(ent_idx: int) -> void:
	selected_entity = ent_idx
	_rebuild_highlight_boxes()

func set_hover(ent_idx: int) -> void:
	if hovered_entity == ent_idx:
		return
	hovered_entity = ent_idx
	_rebuild_highlight_boxes()

func _ensure_wire_pool() -> void:
	if _sel_im == null:
		_sel_im = ImmediateMesh.new()
		_wire_mat_sel = StandardMaterial3D.new()
		_wire_mat_sel.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wire_mat_sel.albedo_color = Color(0.98, 0.68, 0.16, 1.0)
		_wire_mat_sel.no_depth_test = true
	if _hov_im == null:
		_hov_im = ImmediateMesh.new()
		_wire_mat_hov = StandardMaterial3D.new()
		_wire_mat_hov.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_wire_mat_hov.albedo_color = Color(0.20, 0.90, 1.0, 0.92)
		_wire_mat_hov.no_depth_test = true

func _fill_wire_box(im: ImmediateMesh, mat: StandardMaterial3D, bmin: Vector3, bmax: Vector3, pad_val: float = 0.04) -> void:
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
	var edges := [[0,1],[1,2],[2,3],[3,0],[4,5],[5,6],[6,7],[7,4],[0,4],[1,5],[2,6],[3,7]]
	for e in edges:
		im.surface_add_vertex(corners[e[0]])
		im.surface_add_vertex(corners[e[1]])
	im.surface_end()

func _rebuild_highlight_boxes() -> void:
	_ensure_wire_pool()
	if selection_box != null:
		selection_box.visible = false
		if selected_entity >= 0 and _ent_bounds.has(selected_entity):
			var bb: Array = _ent_bounds[selected_entity]
			_fill_wire_box(_sel_im, _wire_mat_sel, bb[0], bb[1], 0.06)
			selection_box.mesh = _sel_im
			selection_box.visible = not playtest_mode
	if hover_box != null:
		hover_box.visible = false
		if hovered_entity >= 0 and hovered_entity != selected_entity and _ent_bounds.has(hovered_entity):
			var bb: Array = _ent_bounds[hovered_entity]
			_fill_wire_box(_hov_im, _wire_mat_hov, bb[0], bb[1], 0.05)
			hover_box.mesh = _hov_im
			hover_box.visible = not playtest_mode

func _spawn_entity_node(idx: int, e: Dictionary, pos: Vector3) -> Node3D:
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
			return null
		var mesh: ArrayMesh = assets.get_model_mesh(mdl_path)
		if mesh != null:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.rotation_degrees = Vector3(0, yaw_deg, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			holder.add_child(mi)
			ents_root.add_child(holder)
			if mdl_path.to_lower().find("bomb_cart") != -1 or cls == "mapobj_cart_dispenser":
				cart_visual_node = holder
				_cart_orig_pos = pos
				_cart_orig_rot = holder.rotation
			var aabb := mesh.get_aabb()
			var bmin := pos + aabb.position
			var bmax := pos + aabb.position + aabb.size
			_ent_bounds[idx] = [bmin, bmax]
			return holder

	# 2. Brush Entities (func_door, trigger_*, func_respawnroom, func_capturezone, func_upgradestation, func_detail)
	if is_brush:
		var is_trig := cls.begins_with("trigger_") or cls == "func_respawnroom" or cls == "func_capturezone" or cls == "func_nobuild"
		if (not show_volumes or not show_triggers) and is_trig:
			ents_root.add_child(holder)
			return holder
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
			return ab

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
			return holder

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
		_attach_entity_billboard_icon(holder, cls, kv, Vector3(0, sz.y * 0.5 + 0.55, 0))
		_editor_only_nodes.append(mi)
		mi.visible = not playtest_mode
		ents_root.add_child(holder)
		return holder

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
			return holder
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
		return holder

	# 4. Real Godot OmniLight3D / SpotLight3D matching Valve's _light (R G B Brightness) + angles/pitch/_cone!
	if cls == "light" or cls == "light_spot":
		if not show_lights:
			return null
		var linfo := _parse_light_info(str(kv.get("_light", "255 240 210 300")))
		var lcol: Color = linfo["color"]
		var bright: float = float(linfo["brightness"])
		var base_energy := clampf(bright / 180.0, 0.35, 6.0)
		var rng := clampf(sqrt(maxf(bright, 40.0)) * 0.90, 6.0, 38.0)

		var light_node: Light3D
		if cls == "light_spot":
			var spot := SpotLight3D.new()
			spot.light_color = lcol
			spot.light_energy = base_energy * (1.65 if lighting_preview_mode == 1 else 1.0)
			spot.spot_range = rng * 1.25
			var cone_deg := clampf(float(str(kv.get("_cone", "45"))), 12.0, 82.0)
			spot.spot_angle = cone_deg
			spot.spot_attenuation = 1.25
			spot.shadow_enabled = (lighting_preview_mode == 1)
			var pitch_deg := float(str(kv.get("pitch", "-90")))
			spot.rotation_degrees = Vector3(pitch_deg, yaw_deg, 0.0)
			light_node = spot

			# Subtle wireframe spotlight cone preview in edit mode so mappers see exact aim!
			var cone_vis := MeshInstance3D.new()
			var cim := ImmediateMesh.new()
			var cmat := StandardMaterial3D.new()
			cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			cmat.albedo_color = Color(lcol.r, lcol.g, lcol.b, 0.55)
			cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			cim.surface_begin(Mesh.PRIMITIVE_LINES, cmat)
			var clen := 3.2
			var crad := clen * tan(deg_to_rad(cone_deg))
			for ci in range(8):
				var a0 := float(ci) * TAU / 8.0
				var a1 := float(ci + 1) * TAU / 8.0
				var p0 := Vector3(cos(a0) * crad, sin(a0) * crad, -clen)
				var p1 := Vector3(cos(a1) * crad, sin(a1) * crad, -clen)
				cim.surface_add_vertex(Vector3.ZERO); cim.surface_add_vertex(p0)
				cim.surface_add_vertex(p0); cim.surface_add_vertex(p1)
			cim.surface_end()
			cone_vis.mesh = cim
			cone_vis.rotation_degrees = Vector3(pitch_deg, yaw_deg, 0.0)
			holder.add_child(cone_vis)
			_editor_only_nodes.append(cone_vis)
			cone_vis.visible = not playtest_mode
		else:
			var omni := OmniLight3D.new()
			omni.light_color = lcol
			omni.light_energy = base_energy * (1.65 if lighting_preview_mode == 1 else 1.0)
			omni.omni_range = rng
			omni.omni_attenuation = 1.35
			omni.shadow_enabled = false
			light_node = omni

		light_node.set_meta("base_energy", base_energy)
		light_node.visible = (lighting_preview_mode != 2) and show_lights
		holder.add_child(light_node)
		_light_nodes.append(light_node)

		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.28
		bulb.mesh = sm
		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.albedo_color = lcol
		bulb.material_override = bmat
		holder.add_child(bulb)
		_attach_entity_billboard_icon(holder, cls, kv, Vector3(0, 0.72, 0))
		_editor_only_nodes.append(bulb)
		bulb.visible = not playtest_mode
		ents_root.add_child(holder)
		_ent_bounds[idx] = [pos - Vector3(0.45, 0.45, 0.45), pos + Vector3(0.45, 1.15, 0.45)]
		return holder

	# 5. Path Track node (yellow rail beacon + billboard icon)
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
		_attach_entity_billboard_icon(holder, cls, kv, Vector3(0, 0.75, 0))
		_editor_only_nodes.append(node_m)
		node_m.visible = not playtest_mode
		ents_root.add_child(holder)
		_ent_bounds[idx] = [pos - Vector3(0.45, 0.45, 0.45), pos + Vector3(0.45, 1.15, 0.45)]
		return holder

	# 6. EVERY OTHER ENTITY gets a crisp, color-coded 3D Billboard Icon + Label so NO entity is ever invisible!
	if show_logic_markers:
		_attach_entity_billboard_icon(holder, cls, kv, Vector3(0, 0.78, 0))
		ents_root.add_child(holder)
		_ent_bounds[idx] = [pos + Vector3(-0.55, 0.0, -0.55), pos + Vector3(0.55, 1.45, 0.55)]
		return holder
	return null

func _attach_entity_billboard_icon(holder: Node3D, cls: String, kv: Dictionary, offset: Vector3) -> void:
	var ic: Dictionary = Tf2CatalogScript.get_entity_icon_spec(cls)
	var kind: String = str(ic.get("key", "relay"))
	var spr := Sprite3D.new()
	spr.texture = _get_badge_texture(kind)
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.pixel_size = 0.0155
	spr.position = offset
	spr.visible = not playtest_mode
	holder.add_child(spr)
	_editor_only_nodes.append(spr)

	var tname: String = str(kv.get("targetname", ""))
	var pretty: String = cls.replace("info_", "").replace("env_", "").replace("logic_", "").replace("tf_", "").replace("trigger_", "").replace("_", " ").capitalize()
	var lbl := Label3D.new()
	lbl.text = "%s\n(%s)" % [pretty, tname] if not tname.is_empty() else pretty
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font_size = 24
	lbl.outline_size = 6
	lbl.pixel_size = 0.0055
	lbl.modulate = Color(0.96, 0.92, 0.85, 0.95)
	lbl.position = offset + Vector3(0, -0.62, 0)
	lbl.visible = not playtest_mode
	holder.add_child(lbl)
	_editor_only_nodes.append(lbl)

func _get_badge_texture(kind: String) -> ImageTexture:
	if _badge_tex_cache.has(kind):
		return _badge_tex_cache[kind]
	var sz := 64
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var bg := Color(0.22, 0.14, 0.29, 0.96)
	var bd := Color(0.76, 0.48, 0.94, 1.0)
	var fg := Color(0.98, 0.95, 0.88, 1.0)
	match kind:
		"door":       bg = Color(0.14, 0.24, 0.32, 0.96); bd = Color(0.24, 0.88, 0.98, 1.0)
		"trigger":    bg = Color(0.30, 0.22, 0.08, 0.96); bd = Color(0.98, 0.82, 0.28, 1.0)
		"hurt":       bg = Color(0.36, 0.10, 0.10, 0.96); bd = Color(0.96, 0.28, 0.26, 1.0)
		"jump_pad":   bg = Color(0.10, 0.28, 0.16, 0.96); bd = Color(0.30, 0.88, 0.46, 1.0)
		"teleporter": bg = Color(0.12, 0.20, 0.34, 0.96); bd = Color(0.24, 0.86, 0.98, 1.0)
		"light":      bg = Color(0.32, 0.25, 0.08, 0.96); bd = Color(0.98, 0.86, 0.34, 1.0)
		"sun":        bg = Color(0.34, 0.22, 0.08, 0.96); bd = Color(0.98, 0.68, 0.24, 1.0)
		"sound":      bg = Color(0.10, 0.26, 0.30, 0.96); bd = Color(0.28, 0.88, 0.96, 1.0)
		"particle":   bg = Color(0.32, 0.15, 0.08, 0.96); bd = Color(0.98, 0.62, 0.24, 1.0)
		"clip":       bg = Color(0.28, 0.14, 0.26, 0.96); bd = Color(0.92, 0.46, 0.80, 1.0)
		"win":        bg = Color(0.12, 0.28, 0.14, 0.96); bd = Color(0.34, 0.88, 0.44, 1.0)
		"camera":     bg = Color(0.14, 0.22, 0.32, 0.96); bd = Color(0.36, 0.68, 0.96, 1.0)
		"ai":         bg = Color(0.28, 0.14, 0.26, 0.96); bd = Color(0.92, 0.50, 0.84, 1.0)
		"cap_point":  bg = Color(0.30, 0.20, 0.10, 0.96); bd = Color(0.96, 0.64, 0.24, 1.0)
		"path_node":  bg = Color(0.30, 0.24, 0.08, 0.96); bd = Color(0.98, 0.80, 0.20, 1.0)

	# Rounded square badge with crisp 3px colored frame
	for y in range(4, sz - 4):
		for x in range(4, sz - 4):
			var dx := maxf(0.0, maxf(12.0 - float(x), float(x) - float(sz - 13)))
			var dy := maxf(0.0, maxf(12.0 - float(y), float(y) - float(sz - 13)))
			var d := Vector2(dx, dy).length()
			if d <= 8.0:
				img.set_pixel(x, y, bd if d >= 5.0 else bg)

	# Crisp centered geometric glyph per entity category!
	var cx := 32.0; var cy := 32.0
	for y in range(14, 50):
		for x in range(14, 50):
			var px := float(x) - cx; var py := float(y) - cy
			var r := Vector2(px, py).length()
			var draw_fg := false
			match kind:
				"light", "sun":
					draw_fg = (r <= 9.0) or (kind == "sun" and r >= 12.0 and r <= 16.0 and (absf(px) < 2.0 or absf(py) < 2.0 or absf(absf(px) - absf(py)) < 2.2))
				"door":
					draw_fg = (absf(px) <= 1.8 and absf(py) <= 15.0) or (px < -4.0 and absf(py) <= (-px - 4.0) * 0.7 and px > -14.0) or (px > 4.0 and absf(py) <= (px - 4.0) * 0.7 and px < 14.0)
				"trigger":
					draw_fg = (r <= 6.5) or (absf(absf(px) - absf(py)) <= 2.2 and r <= 15.0)
				"hurt":
					draw_fg = (Vector2(px, py + 3.0).length() <= 10.5 and not (Vector2(absf(px) - 4.0, py + 3.0).length() <= 2.4)) or (absf(px) <= 5.5 and py >= 6.0 and py <= 13.0)
				"jump_pad":
					draw_fg = (absf(px) <= 4.0 and py >= -2.0 and py <= 14.0) or (py <= 0.0 and py >= -14.0 and absf(px) <= (py + 14.0) * 0.9)
				"teleporter":
					draw_fg = (r >= 10.0 and r <= 13.5) or (r >= 5.0 and r <= 7.5 and py > -4.0) or (r <= 2.5)
				"timer":
					draw_fg = (r >= 11.0 and r <= 14.0) or (absf(px) <= 1.8 and py <= 1.0 and py >= -9.0) or (absf(py) <= 1.8 and px >= 0.0 and px <= 8.0)
				"sound":
					draw_fg = (px >= -13.0 and px <= -4.0 and absf(py) <= 5.0) or (px > -4.0 and px <= 3.0 and absf(py) <= 5.0 + (px + 4.0) * 1.1) or (px > 5.0 and r >= 8.0 and r <= 11.0 and absf(py) < px * 0.9)
				"clip":
					draw_fg = (absf(px) >= 11.0 and absf(px) <= 14.0 and absf(py) <= 14.0) or (absf(py) >= 11.0 and absf(py) <= 14.0 and absf(px) <= 14.0) or (absf(px - py) <= 2.0 and absf(px) <= 13.0)
				"win":
					draw_fg = (px >= -10.0 and px <= -6.5 and absf(py) <= 14.0) or (px >= -6.5 and px <= 12.0 and py >= -13.0 and py <= 2.0 and (py + 5.5) * 0.0 + absf(py + 5.5) <= (12.0 - px) * 0.45)
				"ai", "cap_point":
					draw_fg = (r >= 9.0 and r <= 12.0) or (r <= 3.5) or (absf(px) <= 1.5 and r <= 15.0) or (absf(py) <= 1.5 and r <= 15.0)
				_: # relay / counter / particle / camera diamond+bolt
					draw_fg = (absf(px + py * 0.45) <= 3.5 and py <= 1.0 and py >= -14.0) or (absf(px + py * 0.45 - 2.0) <= 3.5 and py >= -1.0 and py <= 14.0)
			if draw_fg:
				img.set_pixel(x, y, fg if kind not in ["light", "sun", "trigger"] else bd)

	var tex := ImageTexture.create_from_image(img)
	_badge_tex_cache[kind] = tex
	return tex

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

func _parse_light_info(light_str: String) -> Dictionary:
	var parts := light_str.split(" ", false)
	var col := Color(1.0, 0.94, 0.82)
	var bright := 300.0
	if parts.size() >= 3:
		col = Color(
			clampf(float(parts[0]) / 255.0, 0.0, 1.0),
			clampf(float(parts[1]) / 255.0, 0.0, 1.0),
			clampf(float(parts[2]) / 255.0, 0.0, 1.0)
		)
	if parts.size() >= 4:
		bright = clampf(float(parts[3]), 25.0, 2500.0)
	return {"color": col, "brightness": bright}

func _parse_light_color(light_str: String) -> Color:
	return _parse_light_info(light_str)["color"]
