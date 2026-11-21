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

# Organized Visual Category Boxes for ALL 16,697+ TF2 VPK Props!
const PROP_FOLDER_BOXES := [
	{
		"id": "winter",
		"name": "Winter & Snow",
		"subtitle": "Snowy pines, ice, Smissmas",
		"icon": "pine",
		"color": Color(0.45, 0.78, 0.96, 1.0),
		"keywords": ["_snow", "snow", "winter", "icicle", "frost", "coldfront", "barnblitz", "smissmas", "xmas", "christmas", "snowman"],
		"curated": [
			{"name": "Snowy Pine Huge",   "mdl": "models/props_foliage/tree_pine_huge_snow.mdl"},
			{"name": "Winter Wood Fence", "mdl": "models/props_coalmines/wood_fence_short_128.mdl"},
		],
	},
	{
		"id": "trees",
		"name": "Trees & Foliage",
		"subtitle": "Pines, shrubs, cacti, logs",
		"icon": "pine",
		"color": Color(0.36, 0.76, 0.44, 1.0),
		"keywords": ["tree", "pine", "foliage", "bush", "shrub", "cactus", "plant", "grass", "stump", "log", "ivy", "vine", "fern", "palm"],
		"curated": [
			{"name": "Alpine Pine",       "mdl": "models/props_foliage/tree_pine01.mdl"},
			{"name": "Tall Pine Tree",    "mdl": "models/props_foliage/tree_pine_huge.mdl"},
			{"name": "Desert Cactus",     "mdl": "models/props_foliage/cactus01.mdl"},
			{"name": "Shrub Bush",        "mdl": "models/props_foliage/shrub_03a.mdl"},
			{"name": "Fallen Log",        "mdl": "models/props_forest/wood_pile.mdl"},
		],
	},
	{
		"id": "crates",
		"name": "Crates & Barrels",
		"subtitle": "Cover crates, drums, hay",
		"icon": "crate",
		"color": Color(0.88, 0.56, 0.25, 1.0),
		"keywords": ["crate", "barrel", "drum", "hay", "pallet", "box", "sack", "tire", "bucket"],
		"curated": [
			{"name": "Mining Crate",      "mdl": "models/props_2fort/miningcrate001.mdl"},
			{"name": "Wooden Barrel",     "mdl": "models/props_farm/wooden_barrel.mdl"},
			{"name": "Oil Drum",          "mdl": "models/props_badlands/barrel01.mdl"},
			{"name": "Shipping Crate",    "mdl": "models/props_2fort/miningcrate002.mdl"},
			{"name": "Hay Bale",          "mdl": "models/props_farm/haypile001.mdl"},
			{"name": "Steel Bucket",      "mdl": "models/props_2fort/metalbucket001.mdl"},
		],
	},
	{
		"id": "rocks",
		"name": "Rocks & Cliffs",
		"subtitle": "Canyon boulders & ledges",
		"icon": "rock",
		"color": Color(0.76, 0.54, 0.40, 1.0),
		"keywords": ["rock", "boulder", "cliff", "stone", "canyon", "spire", "rubble", "props_nature", "props_mining/rock"],
		"curated": [
			{"name": "Canyon Boulder",    "mdl": "models/props_nature/rock_worn001.mdl"},
			{"name": "Mining Rock 01",    "mdl": "models/props_mining/rock001.mdl"},
			{"name": "Mining Rock 02",    "mdl": "models/props_mining/rock002.mdl"},
			{"name": "Badlands Spire",    "mdl": "models/props_badlands/rock_spire01.mdl"},
		],
	},
	{
		"id": "industrial",
		"name": "Industrial & Mining",
		"subtitle": "Pipes, trains, silos, cranes",
		"icon": "oil_drum",
		"color": Color(0.78, 0.64, 0.34, 1.0),
		"keywords": ["mine", "mining", "train", "track", "pipe", "tank", "silo", "crane", "beam", "girder", "factory", "granary", "hydro", "foundry", "coal"],
		"curated": [
			{"name": "Grain Machinery",   "mdl": "models/props_granary/grain_machinery_set1.mdl"},
			{"name": "Track Curve 90°",   "mdl": "models/props_mining/track_arc_90degree_128.mdl"},
			{"name": "Support I-Beam",    "mdl": "models/props_mining/support_wall001a.mdl"},
			{"name": "Oil Drum",          "mdl": "models/props_badlands/barrel01.mdl"},
		],
	},
	{
		"id": "spytech",
		"name": "Spytech & Lab",
		"subtitle": "Consoles, servers, radar",
		"icon": "console",
		"color": Color(0.32, 0.72, 0.88, 1.0),
		"keywords": ["spytech", "computer", "console", "server", "terminal", "monitor", "radar", "dish", "laser", "rocket", "doomsday", "lab", "vent"],
		"curated": [
			{"name": "Control Console",   "mdl": "models/props_spytech/control_room_console01.mdl"},
			{"name": "Computer Wall",     "mdl": "models/props_spytech/computer_wall02.mdl"},
			{"name": "Turbine Chair",     "mdl": "models/props_spytech/terminal_chair.mdl"},
			{"name": "Spytech Vent",      "mdl": "models/props_spytech/vent_system_vent01.mdl"},
		],
	},
	{
		"id": "lights",
		"name": "Lights & Signs",
		"subtitle": "Lamps, signs, fences, doors",
		"icon": "light",
		"color": Color(0.96, 0.80, 0.36, 1.0),
		"keywords": ["light", "lamp", "lantern", "sign", "poster", "fence", "door", "window", "bridge", "roof", "props_lights", "props_gameplay/sign"],
		"curated": [
			{"name": "Industrial Lamp",   "mdl": "models/props_lights/lamp001.mdl"},
			{"name": "Cage Light",        "mdl": "models/props_lights/light_cage001a.mdl"},
			{"name": "Spotlight",         "mdl": "models/props_lights/spotlight001a.mdl"},
			{"name": "Farm Fence",        "mdl": "models/props_farm/fence_wooden01a.mdl"},
		],
	},
	{
		"id": "medieval",
		"name": "Medieval & Spooky",
		"subtitle": "Castles, torches, Halloween",
		"icon": "barrel",
		"color": Color(0.76, 0.44, 0.86, 1.0),
		"keywords": ["medieval", "degroot", "castle", "torch", "halloween", "pumpkin", "skull", "tomb", "grave", "spooky", "ghost", "coffin", "cauldron", "manor"],
		"curated": [
			{"name": "Wooden Barrel",     "mdl": "models/props_farm/wooden_barrel.mdl"},
			{"name": "Castle Torch",      "mdl": "models/props_medieval/wall_torch.mdl"},
			{"name": "Halloween Pumpkin", "mdl": "models/props_halloween/pumpkin_01.mdl"},
			{"name": "Stone Gravestone",  "mdl": "models/props_halloween/tombstone_01.mdl"},
		],
	},
	{
		"id": "gameplay",
		"name": "Gameplay & Vehicles",
		"subtitle": "Carts, lockers, trucks, MvM",
		"icon": "bomb_cart",
		"color": Color(0.86, 0.34, 0.34, 1.0),
		"keywords": ["props_gameplay", "props_mvm", "props_vehicles", "truck", "pickup", "van", "car", "forklift", "helicopter", "bomb_cart", "resupply", "cap_point", "briefcase"],
		"curated": [
			{"name": "Payload Cart",      "mdl": "models/props_trainyard/bomb_cart.mdl"},
			{"name": "Resupply Locker",   "mdl": "models/props_gameplay/resupply_locker.mdl"},
			{"name": "Cap Point Base",    "mdl": "models/props_gameplay/cap_point_base.mdl"},
			{"name": "MvM Bomb Hatch",    "mdl": "models/props_mvm/mann_hatch.mdl"},
			{"name": "MvM Upgrade Stn",   "mdl": "models/props_mvm/mvm_upgrade_center.mdl"},
			{"name": "Intel Briefcase",   "mdl": "models/flag/briefcase.mdl"},
		],
	},
]

const FAVORITES_PATH := "user://prop_favorites.json"

static func load_prop_favorites() -> Array[String]:
	var out: Array[String] = []
	if not FileAccess.file_exists(FAVORITES_PATH):
		return out
	var f := FileAccess.open(FAVORITES_PATH, FileAccess.READ)
	if f == null:
		return out
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Array:
		for item in parsed:
			var s := str(item)
			if not s.is_empty() and not out.has(s):
				out.append(s)
	return out

static func save_prop_favorites(favs: Array[String]) -> void:
	var f := FileAccess.open(FAVORITES_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(favs, "\t"))

static func get_prop_box(cat_id: String) -> Dictionary:
	for box in PROP_FOLDER_BOXES:
		if str(box["id"]) == cat_id:
			return box
	return {}

static func get_props_for_box(core: Object, cat_id: String, search_filter: String = "", limit: int = 48) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var seen: Dictionary = {}
	var fl := search_filter.to_lower().strip_edges()
	var box := get_prop_box(cat_id)
	if box.is_empty():
		return results

	# 1) Curated iconic Valve TF2 props for this category first!
	for item in box.get("curated", []):
		var mp: String = str(item["mdl"])
		var nm: String = str(item["name"])
		if not fl.is_empty() and nm.to_lower().find(fl) == -1 and mp.to_lower().find(fl) == -1:
			continue
		if not seen.has(mp):
			seen[mp] = true
			results.append({"name": nm, "mdl": mp})

	# 2) Live VPK search across ALL 16,697+ mounted TF2 models matching this category's keywords!
	if core != null and core.has_method("search_models"):
		var kws: Array = box.get("keywords", [])
		for kw in kws:
			if results.size() >= limit:
				break
			var found: PackedStringArray = core.search_models(str(kw), 24)
			for m in found:
				if results.size() >= limit:
					break
				var mp := str(m)
				if seen.has(mp):
					continue
				if mp.find("/player/") != -1 or mp.find("/weapons/") != -1 or mp.find("/bots/") != -1 or mp.find("skybox") != -1 or mp.find("_animations") != -1 or mp.find("_ss.") != -1 or mp.find("police") != -1 or mp.find("gib") != -1:
					continue
				if not fl.is_empty() and mp.to_lower().find(fl) == -1:
					continue
				seen[mp] = true
				var pretty := mp.get_file().get_basename().replace("_", " ").capitalize()
				results.append({"name": pretty, "mdl": mp})
	return results

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
