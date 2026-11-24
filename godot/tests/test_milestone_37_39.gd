extends SceneTree

## Milestones 37-39 Verification Suite:
##   1. UI Responsiveness & Perf (Cached Tf2Catalog, O(dirty) EntityVisuals, Cached StyleBoxFlat)
##   2. TutorialManager Quests (4 quests, baseline snapshots, auto-completion)
##   3. AiMapCopilot Hybrid Engine (Offline TF2 Architect + Live Map Critique + Gemini/Ollama JSON Action Parser)

const Tf2CatalogScript   = preload("res://scripts/core/Tf2Catalog.gd")
const HudWidgetsScript   = preload("res://scripts/ui/Tf2HudWidgets.gd")
const TutorialScript     = preload("res://scripts/ui/TutorialManager.gd")
const AiCopilotScript    = preload("res://scripts/ai/AiMapCopilot.gd")

var _failed := 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  [PASS] ", msg)
	else:
		printerr("  [FAIL] ", msg)
		_failed += 1

func _initialize() -> void:
	print("=== Pootis Builder 2.0 — Milestones 37-39 Verification ===")
	var repo_root := ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir()
	var core = ClassDB.instantiate("Tf2Core")
	core.mount_tf2(repo_root)

	# 1. Cached StyleBoxFlat + Cached Tf2Catalog
	var sb1 := HudWidgetsScript.make_button_style(Color(0.2, 0.2, 0.2), Color(0.5, 0.5, 0.5), 7, 12, 6)
	var sb2 := HudWidgetsScript.make_button_style(Color(0.2, 0.2, 0.2), Color(0.5, 0.5, 0.5), 7, 12, 6)
	_check(sb1 == sb2, "Tf2HudWidgets.make_button_style() returns cached StyleBoxFlat (0 heap allocs on repeat)")

	Tf2CatalogScript.get_props_for_box(core, "crates", "", 45)
	var t0 := Time.get_ticks_usec()
	for _i in range(25):
		Tf2CatalogScript.get_props_for_box(core, "crates", "", 45)
	var cat_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	_check(cat_ms < 2.0, "25x Cached Tf2Catalog.get_props_for_box() ran in %.3f ms (<2ms)" % cat_ms)

	# 2. TutorialManager quest structure
	_check(TutorialScript.QUESTS.size() == 4, "TutorialManager exposes all 4 guided TF2 mapping quests")
	var total_steps := 0
	for q in TutorialScript.QUESTS:
		total_steps += (q["steps"] as Array).size()
	_check(total_steps >= 12, "Guided Tutorials contain %d hands-on auto-completing steps" % total_steps)

	# 3. AiMapCopilot JSON plan parser + Offline Architect intent coverage
	var ai = AiCopilotScript.new()
	root.add_child(ai)
	var parsed: Dictionary = ai._parse_json_plan("```json\n{\"reply\": \"Added cover!\", \"actions\": [{\"op\": \"add_box\", \"min\": [0,0,0], \"max\": [2,2,2]}]}\n```")
	_check(str(parsed.get("reply", "")) == "Added cover!" and (parsed.get("actions", []) as Array).size() == 1,
		"AiMapCopilot._parse_json_plan() cleanly strips markdown fences and parses Gemini/Ollama JSON plans")

	var plan_build: Dictionary = ai._run_offline_architect("Build an elevated catwalk with ramps and warm spotlights + cover crates")
	var acts: Array = plan_build.get("actions", [])
	_check(acts.size() >= 8, "Offline TF2 Architect generated %d structured actions for catwalk+ramps+lights+cover prompt" % acts.size())

	var plan_critique: Dictionary = ai._run_offline_architect("What should I improve next on my map?")
	_check(str(plan_critique.get("reply", "")).find("Critique") != -1, "Offline TF2 Architect generated Live TF2 Map Critique for 'What should I improve next?'")

	# 4. Milestones 40-42: Instant cold prop box (<1ms) + AI v2.0 generators (arena, door, sightlines, auto-fix)
	var tc := Time.get_ticks_usec()
	var fast_props := Tf2CatalogScript.get_props_for_box_fast(core, "spytech", 45)
	var fast_ms := float(Time.get_ticks_usec() - tc) / 1000.0
	_check(fast_props.size() >= 4 and fast_ms < 2.0, "Cold Tf2Catalog.get_props_for_box_fast('spytech') returned %d curated props in %.3f ms (<2ms, ZERO freeze!)" % [fast_props.size(), fast_ms])

	var p_arena: Dictionary = ai._run_offline_architect("Generate a complete snowy KOTH arena")
	_check((p_arena.get("actions", []) as Array).size() == 1 and str((p_arena["actions"] as Array)[0]["op"]) == "generate_arena", "AI v2.0 planned full snowy KOTH arena generation")
	var p_sight: Dictionary = ai._run_offline_architect("Break long sniper sightlines")
	_check((p_sight.get("actions", []) as Array).size() == 1 and str((p_sight["actions"] as Array)[0]["op"]) == "break_sightlines", "AI v2.0 planned automatic Sniper sightline breaker")
	var p_door: Dictionary = ai._run_offline_architect("Add a wired sliding door")
	_check((p_door.get("actions", []) as Array).size() == 1 and str((p_door["actions"] as Array)[0]["op"]) == "add_wired_door", "AI v2.0 planned wired sliding func_door + trigger")
	var p_fix: Dictionary = ai._run_offline_architect("Fix all map problems")
	_check((p_fix.get("actions", []) as Array).size() == 1 and str((p_fix["actions"] as Array)[0]["op"]) == "auto_fix_map", "AI v2.0 planned full auto-fix map repair")

	print("=== Milestones 37-42 Verification Summary: %d failures ===" % _failed)
	quit(1 if _failed > 0 else 0)
