class_name EntityVisuals
extends Node3D

## Milestone 5 — Real 3D TF2 .mdl Entity Visualizer + 3D Spline Track Ribbon
## + Glowing 3D Bezier Logic Wires + Dynamic Point Lights.

var doc: Object
var assets: RefCounted
var show_logic_wires: bool = true
var show_volumes: bool = true
var selected_entity: int = -1

var ents_root: Node3D
var wires_mesh: MeshInstance3D
var track_mesh: MeshInstance3D

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

func sync_all() -> void:
	if doc == null:
		return
	for ch in ents_root.get_children():
		ch.queue_free()
	wires_mesh.mesh = null
	track_mesh.mesh = null

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
		var mesh: ArrayMesh = assets.get_model_mesh(mdl_path)
		if mesh != null:
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.rotation_degrees = Vector3(0, yaw_deg, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			holder.add_child(mi)
			ents_root.add_child(holder)
			return

	# 2. Brush Entities (func_door, trigger_*, func_respawnroom, func_capturezone, func_upgradestation)
	if is_brush:
		if not show_volumes and cls.begins_with("trigger_"):
			ents_root.add_child(holder)
			return
		var bmin: Vector3 = e["bounds_min"]
		var bmax: Vector3 = e["bounds_max"]
		var sz := (bmax - bmin).max(Vector3(0.2, 0.2, 0.2))
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = sz
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var col := Color(0.95, 0.65, 0.16, 0.22)
		if cls == "func_respawnroom":
			col = Color(0.85, 0.22, 0.18, 0.16) if str(kv.get("TeamNum", "2")) == "2" else Color(0.22, 0.52, 0.85, 0.16)
		elif cls == "func_door":
			col = Color(0.55, 0.60, 0.65, 0.82)
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
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

	# 3. Team Spawn Beacon (RED / BLU / MvM Bot Purple) + 83u Heavy Height Reference!
	if cls == "info_player_teamspawn":
		var team := int(str(kv.get("TeamNum", "2")).to_int())
		var tname := str(kv.get("targetname", "")).to_lower()
		var col := Color(0.86, 0.25, 0.20) if team == 2 else Color(0.22, 0.52, 0.84)
		if tname.find("spawnbot") != -1:
			col = Color(0.66, 0.28, 0.92) # MvM Robot spawn!
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
		return

	# 4. Real Godot OmniLight3D + glowing bulb for TF2 point lights!
	if cls == "light" or cls == "light_spot":
		var lcol := _parse_light_color(str(kv.get("_light", "255 240 210 300")))
		var omni := OmniLight3D.new()
		omni.light_color = lcol
		omni.light_energy = 1.35
		omni.omni_range = 16.0
		omni.shadow_enabled = false
		holder.add_child(omni)

		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.24
		bulb.mesh = sm
		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.albedo_color = lcol
		bulb.material_override = bmat
		holder.add_child(bulb)
		ents_root.add_child(holder)
		return

	# 5. Path Track node (yellow rail beacon)
	if cls == "path_track":
		var node_m := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.30
		node_m.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.98, 0.78, 0.18)
		node_m.material_override = mat
		holder.add_child(node_m)
		ents_root.add_child(holder)
		return

	# 6. Generic Logic Entity icon cube (light_environment, tf_gamerules, logic_relay, etc.)
	if cls != "light_environment":
		var box := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.55, 0.55, 0.55)
		box.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.74, 0.45, 0.94, 0.85) if cls.begins_with("tf_logic") else Color(0.32, 0.78, 0.88, 0.85)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		box.material_override = mat
		holder.add_child(box)
		ents_root.add_child(holder)

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
				# Double steel rails + center guide!
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
