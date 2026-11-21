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

# ==============================================================================
# ALL 452 TF2 ENTITIES — GROUPED INTO 8 CLEAR, UNDERSTANDABLE CATEGORY BOXES!
# ==============================================================================
const ENTITY_FOLDER_BOXES := [
	{
		"id": "spawns",
		"name": "1. Spawns & Teams",
		"short": "Spawns",
		"color": Color(0.84, 0.30, 0.28, 1.0),
		"prefixes": ["info_player", "info_observer", "func_respawn", "filter_activator_tfteam", "tf_gamerules", "tf_player"],
		"curated": [
			{"name": "RED Spawn",       "cls": "info_player_teamspawn", "desc": "Spawns RED team players here",             "icon_type": "mdl", "icon": "spawn_red", "preset": "spawn_red"},
			{"name": "BLU Spawn",       "cls": "info_player_teamspawn", "desc": "Spawns BLU team players here",             "icon_type": "mdl", "icon": "spawn_blu", "preset": "spawn_blu"},
			{"name": "MvM Bot Spawn",   "cls": "info_player_teamspawn", "desc": "Spawns robot waves in Mann vs. Machine",   "icon_type": "mdl", "icon": "bot_spawn", "preset": "bot_spawn"},
			{"name": "Resupply Locker", "cls": "func_regenerate",       "desc": "Restores health & ammo in spawn room",     "icon_type": "mdl", "icon": "resupply",  "preset": "resupply"},
			{"name": "Spectator Cam",   "cls": "info_observer_point",   "desc": "Camera angle shown while spectating",      "icon_type": "vec", "icon": "camera",    "preset": ""},
			{"name": "Sentry Gun",      "cls": "obj_sentrygun",         "desc": "Pre-placed Engineer Sentry Gun",           "icon_type": "mdl", "icon": "sentry",    "preset": ""},
			{"name": "Dispenser",       "cls": "obj_dispenser",         "desc": "Pre-placed healing & ammo Dispenser",      "icon_type": "mdl", "icon": "dispenser", "preset": ""},
			{"name": "Team Filter",     "cls": "filter_activator_tfteam","desc": "Restricts doors/triggers to RED or BLU",  "icon_type": "vec", "icon": "relay",     "preset": ""},
			{"name": "TF2 Game Rules",  "cls": "tf_gamerules",          "desc": "Sets global TF2 match rules & HUD mode",   "icon_type": "vec", "icon": "win",       "preset": ""},
		],
	},
	{
		"id": "objectives",
		"name": "2. Objectives & Modes",
		"short": "Objectives",
		"color": Color(0.88, 0.56, 0.25, 1.0),
		"prefixes": ["team_control_point", "item_teamflag", "mapobj_cart", "path_track", "tf_logic_", "func_capturezone", "func_upgradestation", "game_round_win", "info_passtime"],
		"curated": [
			{"name": "Control Point",   "cls": "team_control_point",    "desc": "Capturable TF2 control point + hologram",  "icon_type": "mdl", "icon": "cap_point",       "preset": "cap_point"},
			{"name": "Payload Cart",    "cls": "mapobj_cart_dispenser", "desc": "BLU Payload bomb cart with dispenser",     "icon_type": "mdl", "icon": "bomb_cart",       "preset": "bomb_cart"},
			{"name": "Track Node",      "cls": "path_track",            "desc": "Waypoint node along a Payload rail path",  "icon_type": "mdl", "icon": "path_node",       "preset": "path_node"},
			{"name": "Intel Briefcase", "cls": "item_teamflag",         "desc": "Capturable CTF Intelligence briefcase",    "icon_type": "mdl", "icon": "intel",           "preset": "intel"},
			{"name": "MvM Bomb Hatch",  "cls": "func_capturezone",      "desc": "MvM robot bomb delivery pit",              "icon_type": "mdl", "icon": "mvm_hatch",       "preset": "mvm_hatch"},
			{"name": "Upgrade Station", "cls": "func_upgradestation",   "desc": "MvM weapon & class upgrade booth",         "icon_type": "mdl", "icon": "upgrade_station", "preset": "upgrade_station"},
			{"name": "Capture Zone",    "cls": "trigger_capture_area",  "desc": "Area players stand in to capture point",   "icon_type": "vec", "icon": "trigger",         "preset": ""},
			{"name": "KOTH Logic",      "cls": "tf_logic_koth",         "desc": "Enables King of the Hill 3-minute timers", "icon_type": "vec", "icon": "timer",           "preset": ""},
			{"name": "Round Winner",    "cls": "game_round_win",        "desc": "Ends the round and awards team victory",   "icon_type": "vec", "icon": "win",             "preset": ""},
		],
	},
	{
		"id": "pickups",
		"name": "3. Health & Ammo",
		"short": "Pickups",
		"color": Color(0.32, 0.78, 0.42, 1.0),
		"prefixes": ["item_healthkit", "item_ammopack", "item_powerup", "tf_spell_pickup", "item_currencypack", "item_teamflag"],
		"curated": [
			{"name": "Small Health",    "cls": "item_healthkit_small",  "desc": "Restores 20% max HP",                      "icon_type": "mdl", "icon": "health_small", "preset": "health_small"},
			{"name": "Medium Health",   "cls": "item_healthkit_medium", "desc": "Restores 50% max HP",                      "icon_type": "mdl", "icon": "health_med",   "preset": "health_med"},
			{"name": "Full Health",     "cls": "item_healthkit_full",   "desc": "Restores 100% max HP",                     "icon_type": "mdl", "icon": "health_full",  "preset": "health_full"},
			{"name": "Small Ammo",      "cls": "item_ammopack_small",   "desc": "Restores 20% ammo + 41 metal",             "icon_type": "mdl", "icon": "ammo_small",   "preset": "ammo_small"},
			{"name": "Medium Ammo",     "cls": "item_ammopack_medium",  "desc": "Restores 50% ammo + 100 metal",            "icon_type": "mdl", "icon": "ammo_med",     "preset": "ammo_med"},
			{"name": "Full Ammo",       "cls": "item_ammopack_full",    "desc": "Restores 100% ammo + 200 metal",           "icon_type": "mdl", "icon": "ammo_full",    "preset": "ammo_full"},
			{"name": "Powerup Rune",    "cls": "item_powerup_rune",     "desc": "Mannpower superpower rune pickup",         "icon_type": "vec", "icon": "particle",     "preset": ""},
			{"name": "Spellbook",       "cls": "tf_spell_pickup",       "desc": "Halloween magic spell pickup",             "icon_type": "vec", "icon": "particle",     "preset": ""},
			{"name": "MvM Credits",     "cls": "item_currencypack_medium","desc": "Bonus cash drop for MvM upgrades",       "icon_type": "vec", "icon": "counter",      "preset": ""},
		],
	},
	{
		"id": "doors",
		"name": "4. Doors & Traps",
		"short": "Doors/Traps",
		"color": Color(0.28, 0.80, 0.92, 1.0),
		"prefixes": ["func_door", "trigger_", "func_button", "func_breakable", "func_tracktrain", "info_teleport"],
		"curated": [
			{"name": "Sliding Door",    "cls": "func_door",             "desc": "Auto-sliding spawn or gate door",          "icon_type": "vec", "icon": "door",       "preset": ""},
			{"name": "Trigger Zone",    "cls": "trigger_multiple",      "desc": "Fires I/O outputs when players enter",     "icon_type": "vec", "icon": "trigger",    "preset": ""},
			{"name": "Kill / Hurt Pit", "cls": "trigger_hurt",          "desc": "Damages or kills players inside",          "icon_type": "vec", "icon": "hurt",       "preset": ""},
			{"name": "Jump / Push Pad", "cls": "trigger_push",          "desc": "Launches players upward or forward",       "icon_type": "vec", "icon": "jump_pad",   "preset": ""},
			{"name": "Teleporter",      "cls": "trigger_teleport",      "desc": "Warps players to a target destination",    "icon_type": "vec", "icon": "teleporter", "preset": ""},
			{"name": "Teleport Target", "cls": "info_teleport_destination","desc": "Exit landing point for a Teleporter",   "icon_type": "vec", "icon": "teleporter", "preset": ""},
			{"name": "Trigger Once",    "cls": "trigger_once",          "desc": "Fires one time when touched",              "icon_type": "vec", "icon": "trigger",    "preset": ""},
			{"name": "Push Button",     "cls": "func_button",           "desc": "Shootable or usable interactive switch",   "icon_type": "vec", "icon": "relay",      "preset": ""},
			{"name": "Stun Hazard",     "cls": "trigger_stun",          "desc": "Briefly stuns players on contact",         "icon_type": "vec", "icon": "hurt",       "preset": ""},
		],
	},
	{
		"id": "lights",
		"name": "5. Lights & Sky",
		"short": "Lights/Sky",
		"color": Color(0.96, 0.80, 0.32, 1.0),
		"prefixes": ["light", "sky_camera", "env_fog", "env_cubemap", "env_sun", "env_tonemap", "color_correction", "shadow_control"],
		"curated": [
			{"name": "Point Light",     "cls": "light",                 "desc": "Warm omnidirectional indoor light bulb",   "icon_type": "vec", "icon": "light",  "preset": "light"},
			{"name": "Spotlight",       "cls": "light_spot",            "desc": "Focused cone spotlight for lamps/stages",  "icon_type": "vec", "icon": "light",  "preset": ""},
			{"name": "Map Sun",         "cls": "light_environment",     "desc": "Global outdoor sunlight & sky ambient",    "icon_type": "vec", "icon": "sun",    "preset": ""},
			{"name": "3D Sky Camera",   "cls": "sky_camera",            "desc": "Projects 16x scale 3D skybox vista",       "icon_type": "vec", "icon": "camera", "preset": ""},
			{"name": "Fog Volume",      "cls": "env_fog_controller",    "desc": "Controls atmospheric distance fog",        "icon_type": "vec", "icon": "sound",  "preset": ""},
			{"name": "Env Cubemap",     "cls": "env_cubemap",           "desc": "Captures glossy water & metal reflections","icon_type": "vec", "icon": "clip",   "preset": ""},
			{"name": "Sun Flare",       "cls": "env_sun",               "desc": "Visible glowing sun sprite in the sky",    "icon_type": "vec", "icon": "sun",    "preset": ""},
			{"name": "Tonemap",         "cls": "env_tonemap_controller","desc": "Tunes HDR bloom & exposure brightness",    "icon_type": "vec", "icon": "sun",    "preset": ""},
			{"name": "Shadow Angle",    "cls": "shadow_control",        "desc": "Sets dynamic player shadow direction",     "icon_type": "vec", "icon": "light",  "preset": ""},
		],
	},
	{
		"id": "sound_fx",
		"name": "6. Sound & FX",
		"short": "Sound/FX",
		"color": Color(0.32, 0.78, 0.88, 1.0),
		"prefixes": ["ambient_generic", "env_soundscape", "info_particle", "env_explosion", "env_beam", "env_shake", "env_fire", "env_spark", "env_steam", "env_sprite"],
		"curated": [
			{"name": "Ambient Sound",   "cls": "ambient_generic",       "desc": "Plays looping SFX, alarms, or music",      "icon_type": "vec", "icon": "sound",    "preset": ""},
			{"name": "Soundscape",      "cls": "env_soundscape",        "desc": "TF2 room/outdoor ambient audio zone",      "icon_type": "vec", "icon": "sound",    "preset": ""},
			{"name": "Particle FX",     "cls": "info_particle_system",  "desc": "Spawns TF2 particles (smoke, fire, snow)", "icon_type": "vec", "icon": "particle", "preset": ""},
			{"name": "Explosion FX",    "cls": "env_explosion",         "desc": "Triggers dramatic fiery blast + damage",   "icon_type": "vec", "icon": "hurt",     "preset": ""},
			{"name": "Beam / Laser",    "cls": "env_beam",              "desc": "Glowing Spytech laser beam between points","icon_type": "vec", "icon": "light",    "preset": ""},
			{"name": "Screen Shake",    "cls": "env_shake",             "desc": "Rumbles player cameras on explosions",     "icon_type": "vec", "icon": "jump_pad", "preset": ""},
			{"name": "Glow Sprite",     "cls": "env_sprite",            "desc": "Additive light halo around lamps",         "icon_type": "vec", "icon": "light",    "preset": ""},
			{"name": "Spark Emitter",   "cls": "env_spark",             "desc": "Periodic electrical sparks on machinery",  "icon_type": "vec", "icon": "particle", "preset": ""},
			{"name": "Steam Jet",       "cls": "env_steam",             "desc": "Hissing industrial pipe steam plume",      "icon_type": "vec", "icon": "particle", "preset": ""},
		],
	},
	{
		"id": "logic",
		"name": "7. Logic & Wiring",
		"short": "Logic",
		"color": Color(0.72, 0.45, 0.90, 1.0),
		"prefixes": ["logic_", "math_", "game_text", "env_hudhint", "point_template", "team_round_timer", "tf_glow"],
		"curated": [
			{"name": "Logic Relay",     "cls": "logic_relay",           "desc": "Chains multiple I/O outputs cleanly",      "icon_type": "vec", "icon": "relay",   "preset": ""},
			{"name": "Logic Timer",     "cls": "logic_timer",           "desc": "Fires an output every X seconds",          "icon_type": "vec", "icon": "timer",   "preset": ""},
			{"name": "Round Timer",     "cls": "team_round_timer",      "desc": "Main TF2 match countdown clock on HUD",    "icon_type": "vec", "icon": "timer",   "preset": ""},
			{"name": "Math Counter",    "cls": "math_counter",          "desc": "Counts caps, kills, or puzzle switches",   "icon_type": "vec", "icon": "counter", "preset": ""},
			{"name": "Logic Auto",      "cls": "logic_auto",            "desc": "Automatically fires when the map starts",  "icon_type": "vec", "icon": "relay",   "preset": ""},
			{"name": "Case Switch",     "cls": "logic_case",            "desc": "Picks a random or matched output branch",  "icon_type": "vec", "icon": "counter", "preset": ""},
			{"name": "Logic Branch",    "cls": "logic_branch",          "desc": "True/False condition gate for I/O",        "icon_type": "vec", "icon": "relay",   "preset": ""},
			{"name": "HUD Message",     "cls": "game_text",             "desc": "Displays custom on-screen text to players","icon_type": "vec", "icon": "win",     "preset": ""},
			{"name": "Point Template",  "cls": "point_template",        "desc": "Spawns saved entity groups dynamically",   "icon_type": "vec", "icon": "relay",   "preset": ""},
		],
	},
	{
		"id": "ai_clips",
		"name": "8. AI & Clips",
		"short": "AI/Clips",
		"color": Color(0.88, 0.44, 0.76, 1.0),
		"prefixes": ["bot_", "func_nav", "func_nobuild", "info_target", "tf_bot", "ai_", "func_clip"],
		"curated": [
			{"name": "No-Build Zone",   "cls": "func_nobuild",          "desc": "Prevents Engineers from building here",    "icon_type": "vec", "icon": "clip",   "preset": ""},
			{"name": "Sentry Hint",     "cls": "bot_hint_sentrygun",    "desc": "Tells TF2 AI Engineers where to build",    "icon_type": "mdl", "icon": "sentry", "preset": ""},
			{"name": "Sniper Hint",     "cls": "bot_hint_sniper_spot",  "desc": "Tells TF2 AI Snipers good sightlines",     "icon_type": "vec", "icon": "ai",     "preset": ""},
			{"name": "Tele Exit Hint",  "cls": "bot_hint_teleporter_exit","desc": "Tells AI Engineers where to place exit", "icon_type": "vec", "icon": "teleporter","preset": ""},
			{"name": "Nav Blocker",     "cls": "func_nav_blocker",      "desc": "Blocks bot pathfinding through closed gate","icon_type": "vec", "icon": "clip",  "preset": ""},
			{"name": "Target Marker",   "cls": "info_target",           "desc": "Invisible 3D anchor point for beams/cams", "icon_type": "vec", "icon": "ai",     "preset": ""},
			{"name": "Bot Action Pt",   "cls": "bot_action_point",      "desc": "Commands bots to move or attack here",     "icon_type": "vec", "icon": "ai",     "preset": ""},
			{"name": "MvM Bomb Path",   "cls": "func_nav_prefer",       "desc": "Guides MvM robots down preferred flank",   "icon_type": "vec", "icon": "ai",     "preset": ""},
			{"name": "VPhysics Clip",   "cls": "func_clip_vphysics",    "desc": "Blocks physics props & stickies only",     "icon_type": "vec", "icon": "clip",   "preset": ""},
		],
	},
]

static func get_entity_box(cat_id: String) -> Dictionary:
	for box in ENTITY_FOLDER_BOXES:
		if str(box["id"]) == cat_id:
			return box
	return ENTITY_FOLDER_BOXES[0]

static func get_entity_icon_spec(cls: String) -> Dictionary:
	var c := cls.to_lower()
	if c == "info_player_teamspawn": return {"type": "mdl", "key": "spawn_red"}
	if c == "item_healthkit_small":  return {"type": "mdl", "key": "health_small"}
	if c == "item_healthkit_medium": return {"type": "mdl", "key": "health_med"}
	if c == "item_healthkit_full":   return {"type": "mdl", "key": "health_full"}
	if c == "item_ammopack_small":   return {"type": "mdl", "key": "ammo_small"}
	if c == "item_ammopack_medium":  return {"type": "mdl", "key": "ammo_med"}
	if c == "item_ammopack_full":    return {"type": "mdl", "key": "ammo_full"}
	if c.find("control_point") != -1:return {"type": "mdl", "key": "cap_point"}
	if c.find("teamflag") != -1:     return {"type": "mdl", "key": "intel"}
	if c.find("cart") != -1:         return {"type": "mdl", "key": "bomb_cart"}
	if c.find("path_track") != -1:   return {"type": "mdl", "key": "path_node"}
	if c.find("regenerate") != -1:   return {"type": "mdl", "key": "resupply"}
	if c.find("upgrade") != -1:      return {"type": "mdl", "key": "upgrade_station"}
	if c.find("sentry") != -1:       return {"type": "mdl", "key": "sentry"}
	if c.find("dispenser") != -1:    return {"type": "mdl", "key": "dispenser"}
	if c.find("door") != -1:         return {"type": "vec", "key": "door"}
	if c.find("teleport") != -1:     return {"type": "vec", "key": "teleporter"}
	if c.find("hurt") != -1 or c.find("explosion") != -1 or c.find("stun") != -1: return {"type": "vec", "key": "hurt"}
	if c.find("push") != -1 or c.find("shake") != -1: return {"type": "vec", "key": "jump_pad"}
	if c.begins_with("trigger_"):    return {"type": "vec", "key": "trigger"}
	if c.find("light_environment") != -1 or c.find("env_sun") != -1 or c.find("tonemap") != -1: return {"type": "vec", "key": "sun"}
	if c.begins_with("light") or c.find("beam") != -1 or c.find("sprite") != -1: return {"type": "vec", "key": "light"}
	if c.find("sound") != -1 or c.find("ambient") != -1 or c.find("fog") != -1: return {"type": "vec", "key": "sound"}
	if c.find("particle") != -1 or c.find("fire") != -1 or c.find("spark") != -1 or c.find("steam") != -1 or c.find("spell") != -1 or c.find("powerup") != -1: return {"type": "vec", "key": "particle"}
	if c.find("timer") != -1 or c.find("koth") != -1: return {"type": "vec", "key": "timer"}
	if c.find("math_") != -1 or c.find("counter") != -1 or c.find("case") != -1 or c.find("currency") != -1: return {"type": "vec", "key": "counter"}
	if c.find("win") != -1 or c.find("gamerules") != -1 or c.find("game_text") != -1: return {"type": "vec", "key": "win"}
	if c.find("camera") != -1 or c.find("observer") != -1: return {"type": "vec", "key": "camera"}
	if c.find("clip") != -1 or c.find("nobuild") != -1 or c.find("cubemap") != -1 or c.find("nav_blocker") != -1: return {"type": "vec", "key": "clip"}
	if c.find("bot_") != -1 or c.find("ai_") != -1 or c.find("nav_") != -1 or c.find("target") != -1: return {"type": "vec", "key": "ai"}
	return {"type": "vec", "key": "relay"}

static func get_entities_for_box(core: Object, cat_id: String, limit: int = 36) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var seen: Dictionary = {}
	var box := get_entity_box(cat_id)
	for item in box.get("curated", []):
		results.append(item)
		seen[str(item["cls"]) + ":" + str(item.get("preset", ""))] = true
		seen[str(item["cls"])] = true
	if core != null and core.has_method("list_fgd_point_classes"):
		var prefixes: Array = box.get("prefixes", [])
		var all_cls: PackedStringArray = core.list_fgd_point_classes("")
		for raw_c in all_cls:
			if results.size() >= limit:
				break
			var cs := str(raw_c)
			if seen.has(cs):
				continue
			var matched := false
			for pf in prefixes:
				if cs.begins_with(str(pf)):
					matched = true; break
			if not matched:
				continue
			seen[cs] = true
			var ic := get_entity_icon_spec(cs)
			var pretty := cs.replace("info_", "").replace("env_", "").replace("logic_", "").replace("tf_", "").replace("_", " ").capitalize()
			results.append({
				"name": pretty,
				"cls": cs,
				"desc": "Valve TF2 FGD entity (" + cs + ")",
				"icon_type": ic["type"],
				"icon": ic["key"],
				"preset": "",
			})
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
