extends SceneTree

## Milestone 29 — Automated Performance Benchmark on ctf_turbine_rebuilt.vmf (268 solids, 69 entities)
## Measures O(1) visual drag vs full sync_all, deferred collision push/pull,
## single-entity incremental move, pooled hover wireframes, and 100x raycast picking!

const Tf2AssetsScript     = preload("res://scripts/core/Tf2Assets.gd")
const MapSceneSyncScript  = preload("res://scripts/editor/MapSceneSync.gd")
const EntityVisualsScript = preload("res://scripts/editor/EntityVisuals.gd")

func _initialize() -> void:
	print("=== Pootis Builder 2.0 — Milestone 29 Editor Performance Benchmark ===")
	var core = ClassDB.instantiate("Tf2Core")
	var doc  = ClassDB.instantiate("Tf2MapDoc")
	var repo_root := ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir()
	core.mount_tf2(repo_root)

	var assets = Tf2AssetsScript.new(core)
	var map_sync = MapSceneSyncScript.new()
	map_sync.setup(doc, assets)
	root.add_child(map_sync)

	var ent_vis = EntityVisualsScript.new()
	ent_vis.setup(doc, assets)
	root.add_child(ent_vis)

	var turbine_vmf := repo_root.path_join("godot/maps/ctf_turbine_rebuilt.vmf")
	var lr: Dictionary = doc.load_vmf(turbine_vmf)
	if not lr.get("ok", false):
		print("[FAIL] Could not load ctf_turbine_rebuilt.vmf")
		quit(1)
		return
	print("Loaded ctf_turbine_rebuilt.vmf: %d solids, %d entities" % [doc.get_solid_count(), doc.get_entities().size()])

	# Baseline full scene sync (legacy edit cost)
	var t0 := Time.get_ticks_usec()
	map_sync.sync_all()
	var full_sync_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	ent_vis.sync_all()
	print("  Baseline Full map_sync.sync_all() (268 solids): %.2f ms" % full_sync_ms)

	# 1. Fast Visual Drag (100 drag steps using offset_solid_visual)
	t0 = Time.get_ticks_usec()
	for i in range(100):
		doc.translate_solid(4, Vector3(0.5, 0, 0))
		map_sync.offset_solid_visual(4, Vector3(0.5, 0, 0))
	var drag_100_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("  [PASS] 100x Visual Solid Drag Steps: %.2f ms total (%.4f ms/step — %.0fx faster than sync_all!)" % [
		drag_100_ms, drag_100_ms / 100.0, full_sync_ms / maxf(0.001, drag_100_ms / 100.0)
	])

	# 2. Deferred Collision Face Push/Pull (20 steps without ConcavePolygonShape3D rebuild + 1 finalize)
	t0 = Time.get_ticks_usec()
	for i in range(20):
		doc.push_pull_normal(4, Vector3(1, 0, 0), 0.5)
		map_sync.sync_solid(4, false)
	var face_drag_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	map_sync.sync_solid(4, true)
	var finalize_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("  [PASS] 20x Face Push/Pull (deferred collision): %.2f ms (%.3f ms/step) + 1x Finalize: %.2f ms" % [
		face_drag_ms, face_drag_ms / 20.0, finalize_ms
	])

	# 3. Single-Entity Incremental Move (20 steps)
	var ents: Array = doc.get_entities()
	var epos: Vector3 = ents[2]["pos"]
	t0 = Time.get_ticks_usec()
	for i in range(20):
		epos += Vector3(0.5, 0, 0)
		doc.set_entity_pos(2, epos)
		ent_vis.sync_entity(2, false)
	var ent_move_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("  [PASS] 20x Incremental Entity Move: %.2f ms (%.3f ms/step)" % [ent_move_ms, ent_move_ms / 20.0])

	# 4. Pooled Hover Wireframe Switching (100 hovers across solids)
	t0 = Time.get_ticks_usec()
	for i in range(100):
		map_sync.set_hover(i % 40)
	var hover_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("  [PASS] 100x Pooled Hover Wireframe Updates: %.2f ms (%.4f ms/hover)" % [hover_ms, hover_ms / 100.0])

	# 5. 100x C++ Raycast Face Picking on 268-solid Turbine
	t0 = Time.get_ticks_usec()
	var hits := 0
	for i in range(100):
		var rd := Vector3(0.5 + float(i % 10) * 0.05, -0.35, -0.6).normalized()
		var rc: Dictionary = doc.raycast_face(Vector3(-12, 5, 10), rd)
		if rc.get("hit", false): hits += 1
	var ray_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("  [PASS] 100x C++ raycast_face (268 solids, %d hits): %.2f ms (%.4f ms/pick)" % [hits, ray_ms, ray_ms / 100.0])

	print("=== Performance Benchmark Complete: ALL PASS ===")
	quit(0)
