class_name Tf2Catalog
extends RefCounted

## Milestone 10 — Curated TF2 VPK Material Browser, Curated 3D Prop Browser,
## Jump-Height Reference Table, and TF2 Map Coach Analyzer.

const MATERIAL_CATEGORIES := {
	"Dev Blockout": [
		{"name": "Dev Orange Grid", "mat": "DEV/DEV_MEASUREGENERIC01"},
		{"name": "Dev Grey Grid",   "mat": "DEV/DEV_MEASUREGENERIC01B"},
		{"name": "Dev Blend Orange","mat": "DEV/DEV_BLENDMEASURE"},
		{"name": "Dev Blend Grey",  "mat": "DEV/DEV_BLENDMEASURE2"},
		{"name": "Dev Wall Grid",   "mat": "DEV/DEV_MEASUREWALL01A"},
		{"name": "Dev Crate Grid",  "mat": "DEV/DEV_MEASURECRATE01"},
	],
	"Floors": [
		{"name": "Concrete Slab",   "mat": "CONCRETE/CONCRETEFLOOR007A"},
		{"name": "Concrete Light",  "mat": "CONCRETE/CONCRETEFLOOR001A"},
		{"name": "Steel Grate",     "mat": "METAL/METALGRATE011A"},
		{"name": "Cobblestone",     "mat": "MEDIEVAL/COBBLESTONE001"},
		{"name": "Wood Planks",     "mat": "WOOD/WOOD_FLOOR002"},
		{"name": "Badlands Dirt",   "mat": "NATURE/DIRTGROUND001"},
		{"name": "Alpine Rock",     "mat": "NATURE/ROCKGROUND004"},
		{"name": "Winter Snow",     "mat": "NATURE/SNOW_FULL001"},
	],
	"Walls": [
		{"name": "Barn Wood",       "mat": "WOOD/WOOD_WALL002"},
		{"name": "RED Wood",        "mat": "WOOD/WOOD_WALL007"},
		{"name": "BLU Wood",        "mat": "WOOD/WOOD_WALL005A"},
		{"name": "Red Brick",       "mat": "BRICK/BRICKWALL001"},
		{"name": "Concrete Wall",   "mat": "CONCRETE/CONCRETEWALL001A"},
		{"name": "RED Concrete",    "mat": "CONCRETE/CONCRETEWALL002A"},
		{"name": "BLU Concrete",    "mat": "CONCRETE/CONCRETEWALL001D"},
		{"name": "Castle Stone",    "mat": "MEDIEVAL/STONEWALL001A"},
	],
	"Roofs & Metal": [
		{"name": "RED Barn Roof",   "mat": "METAL/METALROOF004A"},
		{"name": "BLU Metal Roof",  "mat": "METAL/METALROOF006A"},
		{"name": "Corrugated Steel","mat": "METAL/METALWALL001A"},
		{"name": "Dark Steel",      "mat": "METAL/METALWALL001B"},
		{"name": "I-Beam Steel",    "mat": "METAL/IBEAM001B"},
		{"name": "Vent Duct Metal", "mat": "METAL/METALWALL002A"},
	],
	"Glass & Tools": [
		{"name": "Spytech Glass",   "mat": "GLASS/GLASSWINDOW001A"},
		{"name": "Player Clip",     "mat": "TOOLS/TOOLSPLAYERCLIP"},
		{"name": "Trigger Volume",  "mat": "TOOLS/TOOLSTRIGGER"},
		{"name": "Skybox Seal",     "mat": "TOOLS/TOOLSSKYBOX"},
		{"name": "NoDraw",          "mat": "TOOLS/TOOLSNODRAW"},
	],
}

const PROP_CATEGORIES := {
	"Cover & Crates": [
		{"name": "Mining Crate",     "mdl": "models/props_2fort/miningcrate001.mdl"},
		{"name": "Barrel 01",        "mdl": "models/props_farm/wooden_barrel.mdl"},
		{"name": "Shipping Crate",   "mdl": "models/props_2fort/miningcrate002.mdl"},
		{"name": "Hay Bale",         "mdl": "models/props_farm/haypile001.mdl"},
		{"name": "Control Console",  "mdl": "models/props_spytech/control_room_console01.mdl"},
		{"name": "Computer Wall",    "mdl": "models/props_spytech/computer_wall02.mdl"},
	],
	"Industrial & Turbine": [
		{"name": "Turbine Chair",    "mdl": "models/props_spytech/terminal_chair.mdl"},
		{"name": "Grain Machinery",  "mdl": "models/props_granary/grain_machinery_set1.mdl"},
		{"name": "Steel Bucket",     "mdl": "models/props_2fort/metalbucket001.mdl"},
		{"name": "Work Light",       "mdl": "models/props_lights/lamp001.mdl"},
		{"name": "Oil Drum",         "mdl": "models/props_badlands/barrel01.mdl"},
		{"name": "Spytech Vent",     "mdl": "models/props_spytech/vent_system_vent01.mdl"},
	],
	"Nature & Outdoor": [
		{"name": "Alpine Pine Tree", "mdl": "models/props_foliage/tree_pine01.mdl"},
		{"name": "Pine Tree Tall",   "mdl": "models/props_foliage/tree_pine_huge.mdl"},
		{"name": "Boulder Rock",     "mdl": "models/props_nature/rock_worn001.mdl"},
		{"name": "Desert Cactus",    "mdl": "models/props_foliage/cactus01.mdl"},
		{"name": "Shrub Bush",       "mdl": "models/props_foliage/shrub_03a.mdl"},
	],
	"Gameplay & MvM": [
		{"name": "Resupply Locker",  "mdl": "models/props_gameplay/resupply_locker.mdl"},
		{"name": "Payload Cart",     "mdl": "models/props_trainyard/bomb_cart.mdl"},
		{"name": "Cap Point Base",   "mdl": "models/props_gameplay/cap_point_base.mdl"},
		{"name": "MvM Bomb Hatch",   "mdl": "models/props_mvm/mann_hatch.mdl"},
		{"name": "MvM Upgrade Stn",  "mdl": "models/props_mvm/mvm_upgrade_center.mdl"},
		{"name": "Intel Briefcase",  "mdl": "models/flag/briefcase.mdl"},
	],
}

## Computes human-friendly TF2 Map Coach health & gameplay balance diagnostics!
static func analyze_map(doc: Object) -> Dictionary:
	var report := {
		"sealed": doc.is_map_sealed(),
		"solids": doc.get_solid_count(),
		"entities": doc.get_entity_count(),
		"red_spawns": 0,
		"blu_spawns": 0,
		"health_kits": 0,
		"ammo_packs": 0,
		"objectives": 0,
		"walk_time_heavy_s": 0.0,
		"walk_time_scout_s": 0.0,
		"longest_span_u": 0,
		"warnings": [],
		"grade": "A",
	}
	var ents: Array = doc.get_entities()
	var red_pos: Array[Vector3] = []
	var blu_pos: Array[Vector3] = []
	var obj_pos: Array[Vector3] = []

	for e in ents:
		var cls: String = str(e["classname"])
		var pos: Vector3 = e["pos"]
		var kv: Dictionary = e["kv"]
		if cls == "info_player_teamspawn":
			if str(kv.get("TeamNum", "2")) == "2":
				report["red_spawns"] += 1
				red_pos.append(pos)
			else:
				report["blu_spawns"] += 1
				blu_pos.append(pos)
		elif cls.begins_with("item_healthkit"):
			report["health_kits"] += 1
		elif cls.begins_with("item_ammopack"):
			report["ammo_packs"] += 1
		elif cls in ["team_control_point", "item_teamflag", "func_capturezone", "info_passtime_ball_spawn"]:
			report["objectives"] += 1
			obj_pos.append(pos)

	# Estimate Spawn-to-Mid walk time!
	if not red_pos.is_empty():
		var mid := Vector3.ZERO
		if not obj_pos.is_empty():
			mid = obj_pos[0]
		elif not blu_pos.is_empty():
			mid = (red_pos[0] + blu_pos[0]) * 0.5
		var dist_u := red_pos[0].distance_to(mid) * 32.0
		report["walk_time_heavy_s"] = snappedf(dist_u / 230.0, 0.1)
		report["walk_time_scout_s"] = snappedf(dist_u / 400.0, 0.1)
		report["longest_span_u"] = int(round(dist_u * 2.0))

	var warns: Array = report["warnings"]
	if not report["sealed"]:
		warns.append("Map is not sealed — click Auto-Seal Skybox before compiling.")
	if report["red_spawns"] == 0 or report["blu_spawns"] == 0:
		warns.append("Add spawns for both RED (%d) and BLU (%d)." % [report["red_spawns"], report["blu_spawns"]])
	if report["health_kits"] == 0:
		warns.append("No Health Kits placed yet — players will starve in mid!")
	if report["longest_span_u"] > 2400:
		warns.append("Long open sightline (~%du) — add cover or corners vs Snipers!" % report["longest_span_u"])

	if warns.is_empty():
		report["grade"] = "A+"
	elif warns.size() == 1:
		report["grade"] = "B+"
	else:
		report["grade"] = "C"
	return report
