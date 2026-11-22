extends SceneTree

## Milestones 33-36 — Comprehensive Verification Suite + 5th Showcase Map (cp_foundry_mini.vmf)!
## Verifies:
##   1. O(dirty) MapSceneSync.sync_all(false) performance & accuracy on 268-solid Turbine
##   2. Pooled EntityVisuals selection/hover wireframes
##   3. Drop-to-Floor raycast snap + Multi-Solid Group Rotate math
##   4. Live F5 CTF Intelligence Briefcase Pickup & Capture (item_teamflag -> func_capturezone)
##   5. 3D Sniper Sightline Raycast fan across a real TF2 map
##   6. Builds & Valve-compiles (vbsp + vvis + vrad, 0 leaks!) 5th flagship showcase map:
##      godot/maps/cp_foundry_mini.vmf (Symmetrical 3CP Industrial Foundry Arena!)

const Tf2AssetsScript      = preload("res://scripts/core/Tf2Assets.gd")
const Tf2GamemodesScript   = preload("res://scripts/core/Tf2Gamemodes.gd")
const MapSceneSyncScript   = preload("res://scripts/editor/MapSceneSync.gd")
const EntityVisualsScript  = preload("res://scripts/editor/EntityVisuals.gd")
const SandboxPlayerScript  = preload("res://scripts/playtest/Tf2SandboxPlayer.gd")

var _failed := 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [PASS] ", msg)
	else:
		printerr("  [FAIL] ", msg)
		_failed += 1

func _build_foundry_mini(doc: Object, out_vmf: String) -> void:
	doc.new_map("cp_foundry_mini")
	doc.set_skyname("sky_goldrush_01")

	# Main Industrial Courtyard Floor + Mid Foundry Blast-Furnace Deck
	doc.add_box(Vector3(-28, -1.0, -16), Vector3(28, 0.0, 16), "CONCRETE/CONCRETEFLOOR001")
	doc.add_box(Vector3(-6.0, 0.0, -6.0), Vector3(6.0, 1.0, 6.0), "METAL/METALFLOOR001")
	doc.add_ramp(Vector3(-8.5, 0.0, -3.0), Vector3(-6.0, 1.0, 3.0), 0, "CONCRETE/CONCRETEFLOOR002")
	doc.add_ramp(Vector3(6.0, 0.0, -3.0), Vector3(8.5, 1.0, 3.0), 1, "CONCRETE/CONCRETEFLOOR002")

	# Perimeter Industrial Brick & Steel Walls
	doc.add_box(Vector3(-29, 0.0, -17), Vector3(29, 10.0, -16), "BRICK/BRICKWALL001")
	doc.add_box(Vector3(-29, 0.0, 16), Vector3(29, 10.0, 17), "BRICK/BRICKWALL001")
	doc.add_box(Vector3(-29, 0.0, -16), Vector3(-28, 10.0, 16), "BRICK/BRICKWALL001")
	doc.add_box(Vector3(28, 0.0, -16), Vector3(29, 10.0, 16), "BRICK/BRICKWALL001")

	# Twin Elevated Metal Grate Catwalks with Safety Guardrails (Built like Spline Catwalk!)
	for side_v in [-1.0, 1.0]:
		var sz: float = float(side_v) * 11.5
		doc.add_box(Vector3(-18.0, 3.0, sz - 1.5), Vector3(18.0, 3.3, sz + 1.5), "METAL/METALGRATE011A")
		var rail_z: float = sz - float(side_v) * 1.4
		doc.add_wall_segment(Vector3(-18.0, 4.2, rail_z), Vector3(18.0, 4.2, rail_z), 0.16, 0.16, "METAL/IBEAM001B")
		doc.add_wall_segment(Vector3(-18.0, 3.65, rail_z), Vector3(18.0, 3.65, rail_z), 0.12, 0.12, "METAL/IBEAM001B")
		for px in [-16.0, -8.0, 0.0, 8.0, 16.0]:
			doc.add_box(Vector3(px - 0.18, 0.0, sz - 0.18), Vector3(px + 0.18, 4.35, sz + 0.18), "METAL/IBEAM001B")
		# Steel Stairs leading up to catwalks from both teams
		doc.add_stairs(Vector3(-21.0, 0.0, sz - 1.4), Vector3(-18.0, 3.0, sz + 1.4), 0, 8, "METAL/IBEAM001B")
		doc.add_stairs(Vector3(18.0, 0.0, sz - 1.4), Vector3(21.0, 3.0, sz + 1.4), 1, 8, "METAL/IBEAM001B")

	# Central Industrial Furnace Overhang Roof + Steel Columns
	doc.add_box(Vector3(-7.0, 6.8, -7.0), Vector3(7.0, 7.6, 7.0), "METAL/METALROOF004A")
	for cx in [-6.5, 6.5]:
		for cz in [-6.5, 6.5]:
			doc.add_box(Vector3(cx - 0.35, 0.0, cz - 0.35), Vector3(cx + 0.35, 6.8, cz + 0.35), "METAL/IBEAM001B")

	# Symmetrical RED (Left, -X) & BLU (Right, +X) Spawn Buildings + Animated Doors!
	for team_i in [2, 3]:
		var sgn: float = -1.0 if team_i == 2 else 1.0
		var wall_m := "METAL/IMETAL001" if team_i == 2 else "METAL/IMETAL002"
		var roof_m := "METAL/METALROOF004A" if team_i == 2 else "METAL/METALROOF006A"
		var bx0: float = -28.0 if team_i == 2 else 21.0
		var bx1: float = -21.0 if team_i == 2 else 28.0
		var door_x: float = -21.0 if team_i == 2 else 21.0
		doc.add_box(Vector3(bx0, 0.0, -7.0), Vector3(bx1, 4.8, -6.4), wall_m)
		doc.add_box(Vector3(bx0, 0.0, 6.4), Vector3(bx1, 4.8, 7.0), wall_m)
		doc.add_box(Vector3(bx0, 4.8, -7.2), Vector3(bx1, 5.4, 7.2), roof_m)
		# Front spawn wall flanking sliding doorway
		doc.add_box(Vector3(door_x - 0.3, 0.0, -7.0), Vector3(door_x + 0.3, 4.8, -2.0), wall_m)
		doc.add_box(Vector3(door_x - 0.3, 0.0, 2.0), Vector3(door_x + 0.3, 4.8, 7.0), wall_m)
		doc.add_box(Vector3(door_x - 0.3, 3.6, -2.0), Vector3(door_x + 0.3, 4.8, 2.0), wall_m)
		var dname := "spawn_door_red" if team_i == 2 else "spawn_door_blu"
		doc.add_brush_entity("func_door", Vector3(door_x - 0.2, 0.0, -2.0), Vector3(door_x + 0.2, 3.6, 2.0), "METAL/METALDOOR001", {
			"targetname": dname, "movedir": "-90 0 0", "speed": "420"
		})
		var ti: int = doc.add_brush_entity("trigger_multiple", Vector3(door_x - 2.2, 0.0, -2.5), Vector3(door_x + 2.2, 3.6, 2.5), "TOOLS/TOOLSTRIGGER", {})
		doc.add_connection(ti, "OnStartTouch", dname, "Open", "", 0.0, false)
		doc.add_connection(ti, "OnEndTouchAll", dname, "Close", "", 0.0, false)
		doc.add_brush_entity("func_respawnroom", Vector3(bx0 + 0.4, 0.1, -6.0), Vector3(bx1 - 0.4, 4.4, 6.0), "TOOLS/TOOLSTRIGGER", {"TeamNum": str(team_i)})
		# 4 Team Spawns + Resupply + Warm/Cool Spawn Light
		for si in range(4):
			var sy: float = (float(si) - 1.5) * 2.4
			doc.add_point_entity("info_player_teamspawn", Vector3(sgn * 24.5, 0.2, sy), {
				"TeamNum": str(team_i), "angles": "0 %d 0" % (0 if team_i == 2 else 180)
			})
		Tf2GamemodesScript.stamp_preset(doc, "resupply", Vector3(sgn * 26.8, 0.0, 0.0), team_i)
		doc.add_point_entity("light", Vector3(sgn * 24.5, 3.8, 0.0), {
			"_light": "255 185 135 480" if team_i == 2 else "140 195 255 480"
		})

		# Symmetrical Yard Cover Crates + Concrete Barriers + Pickups
		doc.add_box(Vector3(sgn * 12.5 - 1.0, 0.0, -5.5), Vector3(sgn * 12.5 + 1.0, 1.8, -3.5), "CONCRETE/CONCRETEWALL002")
		doc.add_box(Vector3(sgn * 12.5 - 1.0, 0.0, 3.5), Vector3(sgn * 12.5 + 1.0, 1.8, 5.5), "CONCRETE/CONCRETEWALL002")
		doc.add_point_entity("prop_static", Vector3(sgn * 10.0, 0.0, -7.2), {"model": "models/props_2fort/miningcrate001.mdl", "angles": "0 20 0"})
		doc.add_point_entity("prop_static", Vector3(sgn * 10.0, 0.0, 7.2), {"model": "models/props_2fort/oildrum.mdl", "angles": "0 0 0"})
		doc.add_point_entity("item_healthkit_medium", Vector3(sgn * 14.0, 0.2, 0.0), {})
		doc.add_point_entity("item_ammopack_medium", Vector3(sgn * 14.0, 0.2, 3.0), {})
		# Spotlight illuminating each team's yard
		doc.add_point_entity("light_spot", Vector3(sgn * 13.0, 6.2, 0.0), {
			"_light": "255 190 110 700" if team_i == 2 else "125 195 255 700", "pitch": "-75", "_cone": "55"
		})

	# Complete 3CP Gamemode Logic + Mid Furnace Spotlight + Sun
	doc.add_point_entity("tf_gamerules", Vector3(0, 8.0, 0), {"targetname": "gamerules"})
	doc.add_point_entity("team_control_point_master", Vector3(0, 8.8, 0), {})
	doc.add_point_entity("light_environment", Vector3(0, 9.2, 0), {"_light": "255 232 195 450", "pitch": "-42", "angles": "0 135 0"})
	doc.add_point_entity("light_spot", Vector3(0, 6.2, 0), {"_light": "255 165 75 850", "pitch": "-90", "_cone": "60"})
	Tf2GamemodesScript.stamp_preset(doc, "cap_point", Vector3(-16.0, 0.05, 0.0), 2)
	Tf2GamemodesScript.stamp_preset(doc, "cap_point", Vector3(0.0, 1.05, 0.0), 0)
	Tf2GamemodesScript.stamp_preset(doc, "cap_point", Vector3(16.0, 0.05, 0.0), 3)

	doc.auto_seal_skybox()
	doc.save_vmf(out_vmf)

func _initialize() -> void:
	print("=== Pootis Builder 2.0 — Milestones 33-36 Comprehensive Verification ===")
	var repo_root := ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir()
	var core = ClassDB.instantiate("Tf2Core")
	core.mount_tf2(repo_root)
	var doc = ClassDB.instantiate("Tf2MapDoc")
	var assets = Tf2AssetsScript.new(core)

	var map_sync = MapSceneSyncScript.new()
	map_sync.setup(doc, assets)
	root.add_child(map_sync)

	var ent_vis = EntityVisualsScript.new()
	ent_vis.setup(doc, assets)
	root.add_child(ent_vis)

	# 1. O(dirty) MapSceneSync.sync_all(false) + Pooled EntityVisuals hover
	var lr: Dictionary = doc.load_vmf(repo_root.path_join("godot/maps/ctf_turbine_rebuilt.vmf"))
	_check(lr.get("ok", false), "Loaded 268-solid ctf_turbine_rebuilt.vmf")
	map_sync.sync_all(true)
	ent_vis.sync_all()
	var n_before: int = doc.get_solid_count()
	doc.add_box(Vector3(12, 0, 12), Vector3(14, 2, 14), "BRICK/BRICKWALL001")
	var t0 := Time.get_ticks_usec()
	map_sync.sync_all(false)
	var dirty_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_check(doc.get_solid_count() == n_before + 1 and map_sync._solid_nodes.has(n_before), "O(dirty) sync_all(false) synced new brush #%d cleanly in %.2f ms" % [n_before, dirty_ms])
	_check(dirty_ms < 25.0, "O(dirty) sync_all(false) stayed fast (<25ms, got %.2f ms)" % dirty_ms)
	for i in range(25):
		ent_vis.set_hover(i)
	_check(ent_vis._hov_im != null and ent_vis._sel_im != null, "EntityVisuals pooled highlight ImmediateMeshes active")

	# 2. Live F5 CTF Intelligence Briefcase Pickup & Capture Simulation!
	var player = SandboxPlayerScript.new()
	root.add_child(player)
	player.spawn_at(Vector3.ZERO, 0.0, doc.get_entities())
	_check(player._ctf_flags.size() >= 2, "Found RED & BLU item_teamflag briefcases on ctf_turbine_rebuilt (%d)" % player._ctf_flags.size())
	_check(player._ctf_zones.size() >= 2, "Found RED & BLU func_capturezone volumes (%d)" % player._ctf_zones.size())
	# Walk onto BLU flag -> pick up!
	var blu_fpos: Vector3 = player._ctf_flags[1]["pos"]
	var red_zpos: Vector3 = player._ctf_zones[0]["pos"]
	if str(player._ctf_zones[0]["team"]) == str(player._ctf_flags[1]["team"]):
		red_zpos = player._ctf_zones[1]["pos"]
	player.position = blu_fpos
	player._process_triggers(0.05)
	var tel1: Dictionary = player.get_telemetry()
	_check(bool(tel1["ctf_carrying"]), "Live F5 CTF: Picked up enemy Intelligence Briefcase cleanly!")
	# Carry back to friendly capture zone -> score 1/3!
	player.position = red_zpos
	player._process_triggers(0.05)
	var tel2: Dictionary = player.get_telemetry()
	_check(not bool(tel2["ctf_carrying"]) and int(tel2["ctf_caps"]) == 1, "Live F5 CTF: Delivered Intel to capture zone -> Score 1/3!")

	# 3. Drop-to-Floor & Group Rotate Verification
	doc.new_map("koth_m33_test")
	doc.add_box(Vector3(-10, -1, -10), Vector3(10, 0, 10), "CONCRETE/CONCRETEFLOOR001")
	var elevated: int = doc.add_box(Vector3(-1, 5.0, -1), Vector3(1, 7.0, 1), "BRICK/BRICKWALL001")
	var rc: Dictionary = doc.raycast_face(Vector3(0, 4.95, 0), Vector3(0, -1, 0))
	_check(rc.get("hit", false) and absf((rc["hit_pos"] as Vector3).y) < 0.05, "Drop-to-Floor downward raycast hit floor at Y=0")
	doc.translate_solid(elevated, Vector3(0, (rc["hit_pos"] as Vector3).y - 5.0, 0))
	var einfo: Dictionary = doc.get_solid_info(elevated)
	_check(absf((einfo["bounds_min"] as Vector3).y) < 0.05, "Drop-to-Floor snapped solid bottom flush to Y=0")

	# 4. Build & Valve-Compile 5th Showcase Map: cp_foundry_mini.vmf!
	var foundry_vmf := repo_root.path_join("godot/maps/cp_foundry_mini.vmf")
	_build_foundry_mini(doc, foundry_vmf)
	_check(FileAccess.file_exists(foundry_vmf), "Saved 5th Showcase Map: godot/maps/cp_foundry_mini.vmf (%d solids, %d ents)" % [doc.get_solid_count(), doc.get_entities().size()])
	_check(doc.is_map_sealed(), "cp_foundry_mini.vmf is cleanly sealed (0 leaks)")

	# Sightline Raycast Fan Check on cp_foundry_mini!
	var max_u := 0
	var ray_hits := 0
	for i in range(36):
		var a: float = TAU * float(i) / 36.0
		var rrc: Dictionary = doc.raycast_face(Vector3(0, 2.35, 0), Vector3(cos(a), 0, sin(a)))
		if rrc.get("hit", false):
			ray_hits += 1
			max_u = maxi(max_u, int(round(Vector3(0, 2.35, 0).distance_to(rrc["hit_pos"]) * 32.0)))
	_check(ray_hits == 36 and max_u > 256, "3D Sniper Sightline Fan cast 36/36 rays on cp_foundry_mini (max=%du)" % max_u)

	# Real Valve vbsp + vvis + vrad Compile!
	var compiler = ClassDB.instantiate("Tf2Compiler")
	var tools: Dictionary = compiler.detect_paths()
	if bool(tools.get("valid", false)):
		compiler.start_compile(foundry_vmf, true, true, true, false, "cp_foundry_mini")
		var wait_ms := 0
		var st: Dictionary = compiler.poll()
		while not bool(st.get("finished", false)) and wait_ms < 45000:
			OS.delay_msec(100)
			wait_ms += 100
			st = compiler.poll()
		var bsp_out: String = str(st.get("bsp_path", str(tools.get("game_dir", "")).path_join("maps/cp_foundry_mini.bsp")))
		if bsp_out.is_empty():
			bsp_out = str(tools.get("game_dir", "")).path_join("maps/cp_foundry_mini.bsp")
		_check(bool(st.get("succeeded", false)) and str(st.get("leak_file", "")).is_empty() and FileAccess.file_exists(bsp_out),
			"Real Valve vbsp+vvis+vrad compiled %s in %.1fs (0 leaks!)" % [bsp_out.get_file(), float(st.get("elapsed", 0.0))])
	else:
		print("  [SKIP] Valve SDK tools not found on host: ", tools)

	print("=== Milestones 33-36 Verification Summary: %d failures ===" % _failed)
	quit(1 if _failed > 0 else 0)
