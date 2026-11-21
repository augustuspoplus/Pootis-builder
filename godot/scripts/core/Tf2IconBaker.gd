class_name Tf2IconBaker
extends RefCounted

## Studio 3D TF2 Game-Asset Icon Baker.
## Renders REAL transparent 3D studio thumbnails directly from Valve's .mdl files
## in TF2 VPKs using a clean offscreen SubViewport with 3-point TF2 lighting!

const GAMEPLAY_ICONS := {
	"bomb_cart":       "models/props_trainyard/bomb_cart.mdl",
	"health_med":      "models/items/medkit_medium.mdl",
	"health_small":    "models/items/medkit_small.mdl",
	"health_full":     "models/items/medkit_large.mdl",
	"ammo_med":        "models/items/ammopack_medium.mdl",
	"ammo_small":      "models/items/ammopack_small.mdl",
	"ammo_full":       "models/items/ammopack_large.mdl",
	"resupply":        "models/props_gameplay/resupply_locker.mdl",
	"cap_point":       "models/props_gameplay/cap_point_base.mdl",
	"intel":           "models/flag/briefcase.mdl",
	"mvm_hatch":       "models/props_mvm/mann_hatch.mdl",
	"upgrade_station": "models/props_mvm/mvm_upgrade_center.mdl",
	"light":           "models/props_lights/lamp001.mdl",
	"crate":           "models/props_2fort/miningcrate001.mdl",
	"barrel":          "models/props_farm/wooden_barrel.mdl",
	"console":         "models/props_spytech/control_room_console01.mdl",
	"computer":        "models/props_spytech/computer_wall02.mdl",
	"pine":            "models/props_foliage/tree_pine01.mdl",
	"rock":            "models/props_nature/rock_worn001.mdl",
	"hay":             "models/props_farm/haypile001.mdl",
	"oil_drum":        "models/props_badlands/barrel01.mdl",
	"vent":            "models/props_spytech/vent_system_vent01.mdl",
}

static func create_studio_viewport(size_px: int = 160) -> Dictionary:
	var svp := SubViewport.new()
	svp.size = Vector2i(size_px, size_px)
	svp.own_world_3d = true
	svp.transparent_bg = true
	svp.msaa_3d = Viewport.MSAA_4X
	svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.92, 0.90, 0.86)
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	we.environment = env
	svp.add_child(we)

	# Key light (warm TF2 sunlight)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-34, 38, 0)
	key.light_color = Color(1.0, 0.95, 0.86)
	key.light_energy = 1.65
	svp.add_child(key)

	# Cool BLU rim light for Valve SIGGRAPH 2007 silhouette pop!
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-18, -140, 0)
	rim.light_color = Color(0.68, 0.84, 1.0)
	rim.light_energy = 0.95
	svp.add_child(rim)

	var cam := Camera3D.new()
	cam.fov = 34.0
	cam.near = 0.05
	cam.far = 200.0
	svp.add_child(cam)

	var holder := MeshInstance3D.new()
	svp.add_child(holder)

	return {"viewport": svp, "camera": cam, "mesh_node": holder}

static func frame_mesh(studio: Dictionary, mesh: ArrayMesh, yaw_deg: float = -35.0, pitch_deg: float = 24.0) -> void:
	var holder: MeshInstance3D = studio["mesh_node"]
	var cam: Camera3D = studio["camera"]
	holder.mesh = mesh
	if mesh == null:
		return
	var aabb := mesh.get_aabb()
	var center := aabb.position + aabb.size * 0.5
	holder.position = -center
	holder.rotation_degrees = Vector3(0, yaw_deg, 0)

	var max_dim := maxf(maxf(aabb.size.x, aabb.size.y), aabb.size.z)
	var radius := maxf(aabb.size.length() * 0.5, max_dim * 0.52)
	var dist := maxf(radius / sin(deg_to_rad(cam.fov * 0.5)) * 1.08, 0.6)
	var pr := deg_to_rad(pitch_deg)
	var eye := Vector3(0.0, sin(pr) * dist, cos(pr) * dist)
	cam.look_at_from_position(eye, Vector3.ZERO, Vector3.UP)
