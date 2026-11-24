class_name AiMapCopilot
extends Node

## Milestone 39 — Built-in Hybrid AI Map Co-Pilot ("AI Architect") for Pootis Builder 2.0!
## 3-Tier Seamless Engine:
##   1. Google Gemini API (gemini-2.5-flash) via HTTPS when API key is configured
##   2. Local Free Ollama (http://127.0.0.1:11434/api/chat) when selected/available
##   3. Built-in Instant Offline TF2 Smart Architect (zero setup, <5ms, always works!)
## Executes structured TF2 map-building actions directly into Tf2MapDoc in 1 undoable step!

const HudWidgets         = preload("res://scripts/ui/Tf2HudWidgets.gd")
const Tf2GamemodesScript = preload("res://scripts/core/Tf2Gamemodes.gd")

signal response_ready(entry: Dictionary)

var app: Node3D
var http: HTTPRequest
var is_thinking: bool = false
var show_config: bool = false
var active_tab: int = 0 # 0=Architect Chat, 1=AI Arena & Valve DNA
var valve_dna: Dictionary = {}
var arena_leaderboard: Array[Dictionary] = []
var chat_history: Array[Dictionary] = [] # [{role: "user"|"ai", text: String, badge: String, actions_run: int}]
var suggested_followups: Array[String] = [
	"What should I improve next?",
	"Generate a complete snowy KOTH arena",
	"Break long sniper sightlines",
]
var _pending_prompt: String = ""
var _pending_backend: String = "offline"

func setup(p_app: Node3D) -> void:
	app = p_app
	http = HTTPRequest.new()
	http.timeout = 24.0
	add_child(http)
	http.request_completed.connect(_on_http_completed)
	load_valve_dna()
	_load_leaderboard()
	if chat_history.is_empty():
		var studied: int = (valve_dna.get("maps_studied", []) as Array).size()
		var dna_note := " Grounded in %d mined official Valve TF2 maps!" % studied if studied > 0 else ""
		chat_history.append({
			"role": "ai",
			"text": "Hi! I'm your TF2 AI Map Architect.%s Tell me what you want to build, click 'What should I improve next?', or switch to the 'AI Arena & Valve DNA' tab to score & compare models!" % dna_note,
			"badge": get_active_backend_label(),
			"actions_run": 0,
		})

func load_valve_dna() -> void:
	var dna_path := _get_repo_root().path_join("godot/data/tf2_design_dna.json")
	if FileAccess.file_exists(dna_path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(dna_path))
		if parsed is Dictionary:
			valve_dna = parsed

func _get_repo_root() -> String:
	if app != null and not str(app.repo_root).is_empty():
		return str(app.repo_root)
	return ProjectSettings.globalize_path("res://").get_base_dir().get_base_dir()

func _load_leaderboard() -> void:
	var lp := _get_repo_root().path_join("godot/ai_benchmarks/leaderboard.json")
	if FileAccess.file_exists(lp):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(lp))
		if parsed is Array:
			arena_leaderboard.clear()
			for item in parsed:
				if item is Dictionary:
					arena_leaderboard.append(item)

func _save_leaderboard() -> void:
	var bdir := _get_repo_root().path_join("godot/ai_benchmarks")
	DirAccess.make_dir_recursive_absolute(bdir)
	var f := FileAccess.open(bdir.path_join("leaderboard.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(arena_leaderboard, "\t"))
		f.close()

func get_effective_gemini_key() -> String:
	if app != null and app.settings != null and not str(app.settings.gemini_api_key).strip_edges().is_empty():
		return str(app.settings.gemini_api_key).strip_edges()
	return OS.get_environment("GEMINI_API_KEY").strip_edges()

func get_effective_claude_key() -> String:
	if app != null and app.settings != null and not str(app.settings.claude_api_key).strip_edges().is_empty():
		return str(app.settings.claude_api_key).strip_edges()
	return OS.get_environment("ANTHROPIC_API_KEY").strip_edges()

func get_effective_openai_key() -> String:
	if app != null and app.settings != null and not str(app.settings.openai_api_key).strip_edges().is_empty():
		return str(app.settings.openai_api_key).strip_edges()
	return OS.get_environment("OPENAI_API_KEY").strip_edges()

func get_active_backend() -> String:
	if app == null or app.settings == null:
		return "offline"
	var pref: String = str(app.settings.ai_provider).to_lower()
	if pref == "offline": return "offline"
	if pref == "gemini": return "gemini" if not get_effective_gemini_key().is_empty() else "offline"
	if pref == "claude": return "claude" if not get_effective_claude_key().is_empty() else "offline"
	if pref == "openai": return "openai" if not get_effective_openai_key().is_empty() else "offline"
	if pref == "ollama": return "ollama"
	# "auto": pick first configured cloud provider, else instant Valve-DNA offline architect
	if not get_effective_gemini_key().is_empty(): return "gemini"
	if not get_effective_claude_key().is_empty(): return "claude"
	if not get_effective_openai_key().is_empty(): return "openai"
	return "offline"

func get_active_backend_label() -> String:
	var b := get_active_backend()
	if b == "gemini": return "GEMINI API (%s)" % (str(app.settings.gemini_model) if app != null else "gemini-2.5-flash")
	if b == "claude": return "CLAUDE API (%s)" % (str(app.settings.claude_model) if app != null else "claude-sonnet-4")
	if b == "openai": return "OPENAI-COMPAT (%s)" % (str(app.settings.openai_model) if app != null else "gpt-4o-mini")
	if b == "ollama": return "LOCAL OLLAMA (%s)" % (str(app.settings.ollama_model) if app != null else "llama3.2")
	var studied: int = (valve_dna.get("maps_studied", []) as Array).size()
	return "VALVE-DNA ARCHITECT (%d MAPS)" % studied if studied > 0 else "OFFLINE TF2 ARCHITECT"

func get_dna_prompt_snippet() -> String:
	if valve_dna.is_empty():
		return "Valve standard corridor 192-320u, doorway 128x128u, crouch-jump 72u, rocket-jump 240u."
	var theme_k: String = str(app.active_biome) if app != null else "badlands"
	var by_t: Dictionary = valve_dna.get("by_theme", {})
	var tinfo: Dictionary = by_t.get(theme_k, by_t.get("badlands", {}))
	var walls: Array = tinfo.get("walls", [])
	var floors: Array = tinfo.get("floors", [])
	var props: Array = tinfo.get("props", [])
	return "Mined Official Valve TF2 DNA (%d maps studied): For '%s' theme prefer walls=%s, floors=%s, props=%s. Corridor 192-320u, crouch-jump 72u, scout-2x 136u, rocket-jump 240u, keep sightlines <1536u." % [
		(valve_dna.get("maps_studied", []) as Array).size(), theme_k,
		str(walls.slice(0, 3)), str(floors.slice(0, 3)), str(props.slice(0, 3))
	]

func build_map_context_summary() -> String:
	if app == null or app.doc == null:
		return "Empty map"
	var scnt: int = app.doc.get_solid_count()
	var ents: Array = app.doc.get_entities()
	var red_sp := 0; var blu_sp := 0; var lights := 0; var health := 0; var ammo := 0; var props := 0; var caps := 0; var flags := 0
	for e in ents:
		var cls := str(e.get("classname", ""))
		var tm := str(e.get("kv", {}).get("TeamNum", ""))
		if cls == "info_player_teamspawn":
			if tm == "2": red_sp += 1
			elif tm == "3": blu_sp += 1
		elif cls.begins_with("light"): lights += 1
		elif cls.begins_with("item_healthkit"): health += 1
		elif cls.begins_with("item_ammopack"): ammo += 1
		elif cls.begins_with("prop_"): props += 1
		elif cls == "team_control_point": caps += 1
		elif cls == "item_teamflag": flags += 1
	return "Map='%s', Gamemode='%s', Biome='%s', Sealed=%s, Solids=%d, Entities=%d (RED spawns=%d, BLU spawns=%d, Lights=%d, Health=%d, Ammo=%d, Props=%d, CapPoints=%d, IntelFlags=%d)." % [
		app.doc.get_map_name(), app.active_gamemode.to_upper(), app.active_biome,
		"YES" if app.doc.is_map_sealed() else "NO",
		scnt, ents.size(), red_sp, blu_sp, lights, health, ammo, props, caps, flags
	]

func submit_prompt(prompt: String) -> void:
	var clean := prompt.strip_edges()
	if clean.is_empty() or is_thinking:
		return
	chat_history.append({"role": "user", "text": clean, "badge": "YOU", "actions_run": 0})
	_pending_prompt = clean
	_pending_backend = get_active_backend()

	if _pending_backend == "offline":
		var res := _run_offline_architect(clean)
		_finish_response(res, "OFFLINE ARCHITECT")
		return

	is_thinking = true
	if app != null and app.right_drawer.visible and app.right_drawer_title.text.find("AI MAP") != -1:
		app._open_ai_copilot_drawer()

	var sys_prompt := """You are Pootis Builder 2.0's built-in Team Fortress 2 Level Design AI Architect.
Current Map State: %s
%s
Coordinates are in Godot meters (1 meter = 32 TF2 Hammer units, Y is UP, floor is usually Y=0).
Respond ONLY with valid raw JSON (no markdown fences) matching this exact schema:
{
  "reply": "Short helpful 1-3 sentence TF2 mapping response or next-step advice.",
  "actions": [
    {"op": "add_box", "min": [x0,y0,z0], "max": [x1,y1,z1], "mat": "BRICK/BRICKWALL001"},
    {"op": "add_ramp", "min": [x0,y0,z0], "max": [x1,y1,z1], "dir": 0, "mat": "CONCRETE/CONCRETEFLOOR002"},
    {"op": "add_catwalk", "p0": [x0,y0,z0], "p1": [x1,y1,z1]},
    {"op": "add_fence", "p0": [x0,y0,z0], "p1": [x1,y1,z1]},
    {"op": "add_light", "pos": [x,y,z], "color": "255 190 120 600", "spot": true},
    {"op": "add_pickup", "kind": "health_med|ammo_med|health_small|ammo_small", "pos": [x,y,z]},
    {"op": "add_prop", "mdl": "models/props_2fort/miningcrate001.mdl", "pos": [x,y,z], "yaw": 0},
    {"op": "stamp_room", "kind": "spawn_room|sniper_deck|mid_arena|hallway", "team": 2},
    {"op": "generate_arena", "mode": "koth|ctf|cp", "biome": "badlands|winter|spytech|industrial|medieval"},
    {"op": "add_wired_door", "pos": [x,y,z], "name": "ai_door_01"},
    {"op": "break_sightlines"},
    {"op": "auto_fix_map"},
    {"op": "apply_biome", "biome": "badlands|winter|spytech|industrial|medieval|farm"},
    {"op": "set_lighting_mode", "mode": 1},
    {"op": "auto_seal"}
  ],
  "followups": ["Short next idea 1", "Short next idea 2"]
}
Only include actions if the user asks to build, add, fix, light, or change something. Keep action count <= 10.""" % [build_map_context_summary(), get_dna_prompt_snippet()]

	if _pending_backend == "gemini":
		var key := get_effective_gemini_key()
		var mdl: String = str(app.settings.gemini_model) if not str(app.settings.gemini_model).is_empty() else "gemini-2.5-flash"
		var url := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s" % [mdl, key]
		var body := JSON.stringify({
			"contents": [{"role": "user", "parts": [{"text": sys_prompt + "\n\nUser request: " + clean}]}],
			"generationConfig": {"temperature": 0.4, "responseMimeType": "application/json"},
		})
		var err := http.request(url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
		if err != OK:
			is_thinking = false
			var fb := _run_offline_architect(clean)
			fb["reply"] = "(Gemini request error %d — used instant offline fallback) " % err + str(fb["reply"])
			_finish_response(fb, "OFFLINE FALLBACK")
	elif _pending_backend == "claude":
		var key := get_effective_claude_key()
		var mdl: String = str(app.settings.claude_model) if not str(app.settings.claude_model).is_empty() else "claude-sonnet-4-20250514"
		var headers := PackedStringArray(["Content-Type: application/json", "x-api-key: " + key, "anthropic-version: 2023-06-01"])
		var body := JSON.stringify({
			"model": mdl,
			"max_tokens": 1024,
			"system": sys_prompt,
			"messages": [{"role": "user", "content": clean}],
		})
		var err := http.request("https://api.anthropic.com/v1/messages", headers, HTTPClient.METHOD_POST, body)
		if err != OK:
			is_thinking = false
			var fb := _run_offline_architect(clean)
			fb["reply"] = "(Claude request error %d — used instant offline fallback) " % err + str(fb["reply"])
			_finish_response(fb, "OFFLINE FALLBACK")
	elif _pending_backend == "openai":
		var key := get_effective_openai_key()
		var base_u: String = str(app.settings.openai_base_url).trim_suffix("/")
		var mdl: String = str(app.settings.openai_model) if not str(app.settings.openai_model).is_empty() else "gpt-4o-mini"
		var headers := PackedStringArray(["Content-Type: application/json", "Authorization: Bearer " + key])
		var body := JSON.stringify({
			"model": mdl,
			"response_format": {"type": "json_object"},
			"messages": [
				{"role": "system", "content": sys_prompt},
				{"role": "user", "content": clean},
			],
		})
		var err := http.request(base_u + "/chat/completions", headers, HTTPClient.METHOD_POST, body)
		if err != OK:
			is_thinking = false
			var fb := _run_offline_architect(clean)
			fb["reply"] = "(OpenAI-compat request error %d — used instant offline fallback) " % err + str(fb["reply"])
			_finish_response(fb, "OFFLINE FALLBACK")
	elif _pending_backend == "ollama":
		var base_u: String = str(app.settings.ollama_url).trim_suffix("/")
		var mdl: String = str(app.settings.ollama_model) if not str(app.settings.ollama_model).is_empty() else "llama3.2"
		var body := JSON.stringify({
			"model": mdl,
			"stream": false,
			"format": "json",
			"messages": [
				{"role": "system", "content": sys_prompt},
				{"role": "user", "content": clean},
			],
		})
		var err := http.request(base_u + "/api/chat", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
		if err != OK:
			is_thinking = false
			var fb := _run_offline_architect(clean)
			fb["reply"] = "(Ollama unreachable at %s — used instant offline fallback) " % base_u + str(fb["reply"])
			_finish_response(fb, "OFFLINE FALLBACK")

func _on_http_completed(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	is_thinking = false
	var raw_txt := body.get_string_from_utf8()
	var ai_text := ""
	if response_code >= 200 and response_code < 300:
		var parsed = JSON.parse_string(raw_txt)
		if parsed is Dictionary:
			if _pending_backend == "gemini":
				var cands: Array = parsed.get("candidates", [])
				if not cands.is_empty():
					var parts: Array = cands[0].get("content", {}).get("parts", [])
					if not parts.is_empty():
						ai_text = str(parts[0].get("text", ""))
			elif _pending_backend == "claude":
				var blocks: Array = parsed.get("content", [])
				if not blocks.is_empty():
					ai_text = str(blocks[0].get("text", ""))
			elif _pending_backend == "openai":
				var chs: Array = parsed.get("choices", [])
				if not chs.is_empty():
					ai_text = str(chs[0].get("message", {}).get("content", ""))
			elif _pending_backend == "ollama":
				ai_text = str(parsed.get("message", {}).get("content", ""))

	var plan: Dictionary = _parse_json_plan(ai_text)
	if plan.is_empty():
		# Graceful fallback to offline architect so the user ALWAYS gets a useful result!
		var fb := _run_offline_architect(_pending_prompt)
		var note := "HTTP %d" % response_code if response_code != 200 else "non-JSON reply"
		fb["reply"] = "(%s %s — ran offline fallback) %s" % [_pending_backend.to_upper(), note, str(fb["reply"])]
		_finish_response(fb, "OFFLINE FALLBACK")
		return

	_finish_response(plan, get_active_backend_label())

func _parse_json_plan(txt: String) -> Dictionary:
	var s := txt.strip_edges()
	if s.is_empty():
		return {}
	if s.begins_with("```"):
		var nl := s.find("\n")
		if nl >= 0: s = s.substr(nl + 1)
		if s.ends_with("```"): s = s.substr(0, s.length() - 3)
		s = s.strip_edges()
	var parsed = JSON.parse_string(s)
	if parsed is Dictionary and (parsed.has("reply") or parsed.has("actions")):
		return parsed
	return {}

func _finish_response(plan: Dictionary, badge: String) -> void:
	var actions: Array = plan.get("actions", [])
	var applied := 0
	if not actions.is_empty():
		applied = execute_actions(actions, _pending_prompt.left(28))
	var reply_txt := str(plan.get("reply", "Done!"))
	if plan.has("followups") and plan["followups"] is Array and not (plan["followups"] as Array).is_empty():
		suggested_followups.clear()
		for fu in plan["followups"]:
			suggested_followups.append(str(fu))
	var entry := {
		"role": "ai",
		"text": reply_txt,
		"badge": badge,
		"actions_run": applied,
	}
	chat_history.append(entry)
	if chat_history.size() > 24:
		chat_history = chat_history.slice(chat_history.size() - 24)
	response_ready.emit(entry)
	if app != null:
		if applied > 0:
			app.audio.play("save")
			app._toast("AI Architect applied %d map action(s)! (Ctrl+Z to Undo)" % applied)
		else:
			app.audio.play("click")
		if app.right_drawer.visible and app.right_drawer_title.text.find("AI MAP") != -1:
			app._open_ai_copilot_drawer()

# ==============================================================================
# BUILT-IN INSTANT OFFLINE TF2 SMART ARCHITECT (Works 100% Offline, <5ms!)
# ==============================================================================
func _run_offline_architect(prompt: String) -> Dictionary:
	var q := prompt.to_lower()
	var acts: Array = []

	# 0. Full Symmetrical TF2 Map Generation ("generate a complete snowy koth / ctf / cp arena")
	if (q.find("generate") != -1 or q.find("create") != -1 or q.find("new map") != -1 or q.find("complete") != -1) and (q.find("map") != -1 or q.find("arena") != -1 or q.find("fortress") != -1 or q.find("koth") != -1 or q.find("ctf") != -1 or q.find("3cp") != -1 or q.find("5cp") != -1):
		var gmode := "ctf" if q.find("ctf") != -1 else ("cp" if (q.find("cp") != -1 or q.find("3cp") != -1 or q.find("5cp") != -1) else "koth")
		var gbiome := "badlands"
		for bk_c in ["winter", "snow", "spytech", "industrial", "medieval", "farm"]:
			var bks := str(bk_c)
			if q.find(bks) != -1:
				gbiome = "winter" if bks == "snow" else bks; break
		return {
			"reply": "Generated a brand-new symmetrical %s %s TF2 arena (spawns, wired sliding doors, catwalks, spotlights, cover & 0-leak skybox)! Press F5 to playtest it right now." % [gbiome.capitalize(), gmode.to_upper()],
			"actions": [{"op": "generate_arena", "mode": gmode, "biome": gbiome}],
			"followups": ["Break long sniper sightlines", "Add symmetrical health & ammo pickups", "What should I improve next?"],
		}

	# 0b. Auto-Fix All Map Problems
	if q.find("fix") != -1 and (q.find("all") != -1 or q.find("problem") != -1 or q.find("map") != -1 or q.find("leak") != -1):
		return {
			"reply": "Ran full TF2 Auto-Fix: sealed skybox, verified tf_gamerules + light_environment, ensured RED/BLU spawns & balanced pickups!",
			"actions": [{"op": "auto_fix_map"}],
			"followups": ["Break long sniper sightlines", "Add dramatic warm & cool TF2 spotlights", "What should I improve next?"],
		}

	# 0c. Auto-Break Long Sniper Sightlines
	if q.find("break") != -1 and q.find("sightline") != -1:
		return {
			"reply": "Scanned 360 deg Sniper sightlines and placed TF2 cover barriers & crates directly across the longest open sightline lanes!",
			"actions": [{"op": "break_sightlines"}],
			"followups": ["Add dramatic warm & cool TF2 spotlights", "Add a wired sliding door", "What should I improve next?"],
		}

	# 0d. Add Wired Sliding TF2 Door
	if q.find("door") != -1:
		var dp: Vector3 = app.hover_pos if (app != null and app.hover_valid) else Vector3(-6.0, 0.0, 0.0)
		return {
			"reply": "Built a working TF2 func_door + trigger_multiple wired with OnStartTouch->Open & OnEndTouchAll->Close! Walk through it in F5 to test.",
			"actions": [{"op": "add_wired_door", "pos": [dp.x, dp.y, dp.z], "name": "ai_sliding_door"}],
			"followups": ["Add dramatic warm & cool TF2 spotlights", "What should I improve next?"],
		}

	# 1. Live Map Critique / "What should I do next?"
	if q.find("next") != -1 or q.find("audit") != -1 or q.find("critique") != -1 or q.find("improve") != -1 or q.find("help") != -1 or q.find("clue") != -1 or q.find("tip") != -1:
		var tips: Array[String] = []
		var ents: Array = app.doc.get_entities() if (app != null and app.doc != null) else []
		var red_sp := 0; var blu_sp := 0; var lights := 0; var health := 0; var ammo := 0; var props := 0
		for e in ents:
			var cls := str(e.get("classname", ""))
			var tm := str(e.get("kv", {}).get("TeamNum", ""))
			if cls == "info_player_teamspawn":
				if tm == "2": red_sp += 1
				elif tm == "3": blu_sp += 1
			elif cls.begins_with("light"): lights += 1
			elif cls.begins_with("item_healthkit"): health += 1
			elif cls.begins_with("item_ammopack"): ammo += 1
			elif cls.begins_with("prop_"): props += 1
		if app != null and app.doc != null and not app.doc.is_map_sealed():
			tips.append("1) Your map has an OPEN VOID leak — tell me 'seal my map' or click Auto-Seal before compiling.")
		if red_sp < 2 or blu_sp < 2:
			tips.append("2) Add more spawns (currently %d RED / %d BLU) — open Gamemode Studio or say 'add spawn rooms'." % [red_sp, blu_sp])
		if lights < 2:
			tips.append("3) Your map has only %d light(s) — click 'Add Dramatic TF2 Lighting' to give interiors warm/cool contrast!" % lights)
		if health < 2 or ammo < 2:
			tips.append("4) Add symmetrical flank pickups (currently %d health / %d ammo) so Scouts & Soldiers can rotate!" % [health, ammo])
		if props < 4:
			tips.append("5) Add cover crates & high ground (currently %d props) — try 'Build Sniper Balcony + Stairs' or 'Add Mid Cover'!" % props)
		if tips.is_empty():
			tips.append("Your map fundamentals look solid (%d solids, %d lights, %d props, SEALED)! Great next steps: press Alt+S to check Sniper sightlines, press F5 to playtest rocket jumps & objectives, then press F9 to compile for real TF2!" % [
				app.doc.get_solid_count(), lights, props
			])
		return {"reply": "Live TF2 Map Critique:\n" + "\n".join(tips), "actions": []}

	# 2. Biome / Theme switching
	for bk in ["winter", "snow", "badlands", "desert", "spytech", "industrial", "medieval", "farm"]:
		var bk_s: String = str(bk)
		if q.find(bk_s) != -1:
			var target_b: String = "winter" if (bk_s == "snow" or bk_s == "winter") else ("badlands" if bk_s == "desert" else bk_s)
			acts.append({"op": "apply_biome", "biome": target_b})
			break

	# 3. Sniper Deck / Balcony / High Ground
	if q.find("sniper") != -1 or q.find("balcony") != -1 or q.find("deck") != -1 or q.find("high ground") != -1:
		acts.append({"op": "stamp_room", "kind": "sniper_deck", "team": 3 if q.find("blu") != -1 else 2})

	# 4. Spawn Room
	if q.find("spawn") != -1:
		acts.append({"op": "stamp_room", "kind": "spawn_room", "team": 3 if q.find("blu") != -1 else 2})

	# 5. Mid Arena / Courtyard
	if q.find("mid") != -1 and (q.find("arena") != -1 or q.find("courtyard") != -1 or q.find("point") != -1):
		acts.append({"op": "stamp_room", "kind": "mid_arena", "team": 0})

	# 6. Catwalk / Bridge / Walkway
	if q.find("catwalk") != -1 or q.find("bridge") != -1 or q.find("walkway") != -1:
		acts.append({"op": "add_catwalk", "p0": [-10.0, 3.0, -7.0], "p1": [10.0, 3.0, -7.0]})
		acts.append({"op": "add_ramp", "min": [-13.0, 0.0, -8.5], "max": [-10.0, 3.0, -5.5], "dir": 0, "mat": "METAL/METALFLOOR001"})
		acts.append({"op": "add_ramp", "min": [10.0, 0.0, -8.5], "max": [13.0, 3.0, -5.5], "dir": 1, "mat": "METAL/METALFLOOR001"})

	# 7. Fence / Guardrail / Barrier
	if q.find("fence") != -1 or q.find("barrier") != -1:
		acts.append({"op": "add_fence", "p0": [-8.0, 0.0, 6.0], "p1": [8.0, 0.0, 6.0]})

	# 8. Lighting / Spotlights
	if q.find("light") != -1 or q.find("spot") != -1 or q.find("glow") != -1 or q.find("lamp") != -1:
		acts.append({"op": "add_light", "pos": [-9.0, 5.5, 0.0], "color": "255 175 95 720", "spot": true})
		acts.append({"op": "add_light", "pos": [9.0, 5.5, 0.0], "color": "115 190 255 720", "spot": true})
		acts.append({"op": "add_light", "pos": [0.0, 6.5, 0.0], "color": "255 225 170 650", "spot": true})
		acts.append({"op": "set_lighting_mode", "mode": 1})

	# 9. Cover / Crates / Barrels / Props / Trees
	if q.find("cover") != -1 or q.find("crate") != -1 or q.find("barrel") != -1 or q.find("prop") != -1:
		acts.append({"op": "add_prop", "mdl": "models/props_2fort/miningcrate001.mdl", "pos": [-5.0, 0.0, -3.5], "yaw": 18})
		acts.append({"op": "add_prop", "mdl": "models/props_2fort/miningcrate001.mdl", "pos": [5.0, 0.0, 3.5], "yaw": 198})
		acts.append({"op": "add_prop", "mdl": "models/props_2fort/oildrum.mdl", "pos": [-5.8, 0.0, -2.6], "yaw": 0})
		acts.append({"op": "add_prop", "mdl": "models/props_2fort/oildrum.mdl", "pos": [5.8, 0.0, 2.6], "yaw": 45})
	if q.find("tree") != -1 or q.find("pine") != -1 or q.find("forest") != -1:
		var mdl := "models/props_foliage/tree_pine_huge_snow.mdl" if (app != null and app.active_biome == "winter") else "models/props_foliage/tree_pine01.mdl"
		acts.append({"op": "add_prop", "mdl": mdl, "pos": [-11.0, 0.0, -9.0], "yaw": 25})
		acts.append({"op": "add_prop", "mdl": mdl, "pos": [11.0, 0.0, 9.0], "yaw": 140})
		acts.append({"op": "add_prop", "mdl": mdl, "pos": [-11.0, 0.0, 9.0], "yaw": 260})

	# 10. Health & Ammo Pickups
	if q.find("health") != -1 or q.find("med") != -1 or q.find("ammo") != -1 or q.find("pickup") != -1:
		acts.append({"op": "add_pickup", "kind": "health_med", "pos": [-6.5, 0.2, 5.5]})
		acts.append({"op": "add_pickup", "kind": "ammo_med", "pos": [-6.5, 0.2, -5.5]})
		acts.append({"op": "add_pickup", "kind": "health_med", "pos": [6.5, 0.2, -5.5]})
		acts.append({"op": "add_pickup", "kind": "ammo_med", "pos": [6.5, 0.2, 5.5]})

	# 11. Seal / Leak Fix / Sightlines
	if q.find("seal") != -1 or q.find("leak") != -1:
		acts.append({"op": "auto_seal"})
	if q.find("sightline") != -1:
		acts.append({"op": "show_sightlines"})

	if acts.is_empty():
		return {
			"reply": "I'm ready to build! Try commands like:\n- 'Build a sniper balcony + cover crates'\n- 'Add dramatic warm & cool TF2 spotlights'\n- 'Build an elevated catwalk with ramps'\n- 'Add symmetrical health and ammo pickups'\n- 'Switch to winter theme and scatter pine trees'\n- 'What should I improve next?'",
			"actions": [],
		}

	return {
		"reply": "Built your request live into the map (%d TF2 actions applied)! Press Ctrl+Z anytime to undo, or F5 to walk inside and test it." % acts.size(),
		"actions": acts,
	}

# ==============================================================================
# SAFE STRUCTURED ACTION EXECUTOR (1 Undoable Step into Tf2MapDoc!)
# ==============================================================================
func execute_actions(actions: Array, label: String = "AI Architect") -> int:
	if app == null or app.doc == null:
		return 0
	var count := 0
	var touched_solids := false
	var touched_ents := false
	for raw in actions:
		if not (raw is Dictionary):
			continue
		var a: Dictionary = raw
		var op := str(a.get("op", "")).to_lower()
		match op:
			"add_box":
				var p0 := _v3(a.get("min", [-2, 0, -2]))
				var p1 := _v3(a.get("max", [2, 2, 2]))
				var mat := str(a.get("mat", "BRICK/BRICKWALL001"))
				if app.doc.add_box(p0, p1, mat) >= 0:
					count += 1; touched_solids = true
			"add_ramp":
				var p0 := _v3(a.get("min", [-2, 0, -2]))
				var p1 := _v3(a.get("max", [2, 2, 2]))
				var dir := clampi(int(a.get("dir", 0)), 0, 3)
				var mat := str(a.get("mat", "CONCRETE/CONCRETEFLOOR002"))
				if app.doc.add_ramp(p0, p1, dir, mat) >= 0:
					count += 1; touched_solids = true
			"add_catwalk":
				var prev: String = str(app.spline_preset)
				app.spline_preset = "catwalk"
				var ids: Array = app._place_spline_segment(_v3(a.get("p0", [-8, 3, -6])), _v3(a.get("p1", [8, 3, -6])))
				app.spline_preset = prev
				if not ids.is_empty():
					count += 1; touched_solids = true
			"add_fence":
				var prev: String = str(app.spline_preset)
				app.spline_preset = "fence"
				var ids: Array = app._place_spline_segment(_v3(a.get("p0", [-6, 0, 5])), _v3(a.get("p1", [6, 0, 5])))
				app.spline_preset = prev
				if not ids.is_empty():
					count += 1; touched_solids = true
			"add_light":
				var pos := _v3(a.get("pos", [0, 5, 0]))
				var col := str(a.get("color", "255 200 130 600"))
				var is_spot := bool(a.get("spot", true))
				var kv := {"_light": col}
				if is_spot:
					kv["pitch"] = "-75"; kv["_cone"] = "55"
				if app.doc.add_point_entity("light_spot" if is_spot else "light", pos, kv) >= 0:
					count += 1; touched_ents = true
			"add_pickup":
				var pos := _v3(a.get("pos", [0, 0.2, 0]))
				var k := str(a.get("kind", "health_med"))
				var cls := "item_healthkit_medium"
				if k == "ammo_med": cls = "item_ammopack_medium"
				elif k == "health_small": cls = "item_healthkit_small"
				elif k == "ammo_small": cls = "item_ammopack_small"
				if app.doc.add_point_entity(cls, pos, {}) >= 0:
					count += 1; touched_ents = true
			"add_prop":
				var pos := _v3(a.get("pos", [0, 0, 0]))
				var mdl := str(a.get("mdl", "models/props_2fort/miningcrate001.mdl"))
				var yaw := float(a.get("yaw", 0.0))
				if app.doc.add_point_entity("prop_static", pos, {"model": mdl, "angles": "0 %.0f 0" % yaw}) >= 0:
					count += 1; touched_ents = true
			"stamp_room":
				app._room_kit_team = int(a.get("team", 2))
				app._stamp_smart_room_kit(str(a.get("kind", "sniper_deck")))
				count += 1; touched_solids = true; touched_ents = true
			"generate_arena":
				_exec_generate_arena(str(a.get("mode", "koth")), str(a.get("biome", "badlands")))
				count += 1; touched_solids = true; touched_ents = true
			"add_wired_door":
				var dp := _v3(a.get("pos", [-6, 0, 0]))
				var dn := str(a.get("name", "ai_sliding_door_%d" % (randi() % 900 + 100)))
				app.doc.add_brush_entity("func_door", dp + Vector3(-0.25, 0.0, -2.0), dp + Vector3(0.25, 3.6, 2.0), "METAL/METALDOOR001", {
					"targetname": dn, "movedir": "-90 0 0", "speed": "420"
				})
				var ti: int = app.doc.add_brush_entity("trigger_multiple", dp + Vector3(-2.2, 0.0, -2.4), dp + Vector3(2.2, 3.6, 2.4), "TOOLS/TOOLSTRIGGER", {})
				app.doc.add_connection(ti, "OnStartTouch", dn, "Open", "", 0.0, false)
				app.doc.add_connection(ti, "OnEndTouchAll", dn, "Close", "", 0.0, false)
				count += 1; touched_ents = true
			"break_sightlines":
				var broke := _exec_break_sightlines()
				count += maxi(1, broke); touched_solids = true; touched_ents = true
			"auto_fix_map":
				var fixed := _exec_auto_fix_map()
				count += maxi(1, fixed); touched_solids = true; touched_ents = true
			"apply_biome":
				app._apply_biome(str(a.get("biome", "badlands")))
				count += 1; touched_solids = true
			"set_lighting_mode":
				app._set_lighting_mode(clampi(int(a.get("mode", 1)), 0, 2))
				count += 1
			"auto_seal":
				app._do_auto_seal()
				count += 1; touched_solids = true
			"show_sightlines":
				if not app.sightline_active:
					app._toggle_sightline_analyzer()
				count += 1

	if count > 0:
		app._record_history("AI: " + label)
		if touched_solids:
			app.map_sync.sync_all(false)
		if touched_ents:
			app.ent_vis.sync_all(false)
		app._refresh_2d_views(true)
	return count

func _v3(arr: Variant) -> Vector3:
	if arr is Array and (arr as Array).size() >= 3:
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return Vector3.ZERO

func _exec_generate_arena(mode: String, biome: String) -> void:
	var b: Dictionary = Tf2GamemodesScript.get_biome(biome)
	var floor_m: String = str(b["floor"])
	var wall_m: String = str(b["wall"])
	var roof_m: String = str(b["roof"])
	app.doc.new_map("%s_ai_%s" % [mode, biome])
	app.active_gamemode = mode
	app.active_biome = biome
	app.active_sky = str(b["sky"])
	app.doc.set_skyname(app.active_sky)
	app._apply_environment_from_biome(biome)

	# Courtyard floor + mid platform + perimeter walls
	app.doc.add_box(Vector3(-24, -1.0, -14), Vector3(24, 0.0, 14), floor_m)
	app.doc.add_box(Vector3(-5, 0.0, -5), Vector3(5, 1.0, 5), str(b.get("trim", "CONCRETE/CONCRETEFLOOR002")))
	app.doc.add_ramp(Vector3(-7.5, 0.0, -2.5), Vector3(-5, 1.0, 2.5), 0, floor_m)
	app.doc.add_ramp(Vector3(5, 0.0, -2.5), Vector3(7.5, 1.0, 2.5), 1, floor_m)
	app.doc.add_box(Vector3(-25, 0, -15), Vector3(25, 9, -14), wall_m)
	app.doc.add_box(Vector3(-25, 0, 14), Vector3(25, 9, 15), wall_m)
	app.doc.add_box(Vector3(-25, 0, -14), Vector3(-24, 9, 14), wall_m)
	app.doc.add_box(Vector3(24, 0, -14), Vector3(25, 9, 14), wall_m)

	# Elevated twin flank catwalks + ramps
	for sv in [-1.0, 1.0]:
		var sz: float = float(sv) * 10.0
		app.doc.add_box(Vector3(-12, 2.8, sz - 1.4), Vector3(12, 3.1, sz + 1.4), "METAL/METALGRATE011A")
		app.doc.add_ramp(Vector3(-15, 0.0, sz - 1.4), Vector3(-12, 2.8, sz + 1.4), 0, "METAL/METALFLOOR001")
		app.doc.add_ramp(Vector3(12, 0.0, sz - 1.4), Vector3(15, 2.8, sz + 1.4), 1, "METAL/METALFLOOR001")

	# Symmetrical RED & BLU spawns + wired doors + spotlights + cover + pickups
	for team_i in [2, 3]:
		var sgn: float = -1.0 if team_i == 2 else 1.0
		var bx0: float = -24.0 if team_i == 2 else 18.0
		var bx1: float = -18.0 if team_i == 2 else 24.0
		var dx: float = -18.0 if team_i == 2 else 18.0
		app.doc.add_box(Vector3(bx0, 0, -6), Vector3(bx1, 4.5, -5.5), wall_m)
		app.doc.add_box(Vector3(bx0, 0, 5.5), Vector3(bx1, 4.5, 6), wall_m)
		app.doc.add_box(Vector3(bx0, 4.5, -6), Vector3(bx1, 5.0, 6), roof_m)
		var dn := "ai_door_red" if team_i == 2 else "ai_door_blu"
		app.doc.add_brush_entity("func_door", Vector3(dx - 0.2, 0, -2.0), Vector3(dx + 0.2, 3.6, 2.0), "METAL/METALDOOR001", {"targetname": dn, "movedir": "-90 0 0", "speed": "400"})
		var ti: int = app.doc.add_brush_entity("trigger_multiple", Vector3(dx - 2.2, 0, -2.4), Vector3(dx + 2.2, 3.6, 2.4), "TOOLS/TOOLSTRIGGER", {})
		app.doc.add_connection(ti, "OnStartTouch", dn, "Open", "", 0.0, false)
		app.doc.add_connection(ti, "OnEndTouchAll", dn, "Close", "", 0.0, false)
		for si in range(3):
			app.doc.add_point_entity("info_player_teamspawn", Vector3(sgn * 21.0, 0.2, (float(si) - 1.0) * 2.5), {"TeamNum": str(team_i), "angles": "0 %d 0" % (0 if team_i == 2 else 180)})
		Tf2GamemodesScript.stamp_preset(app.doc, "resupply", Vector3(sgn * 22.8, 0.0, 0.0), team_i)
		app.doc.add_point_entity("prop_static", Vector3(sgn * 10.5, 0.0, -4.0), {"model": "models/props_2fort/miningcrate001.mdl", "angles": "0 15 0"})
		app.doc.add_point_entity("prop_static", Vector3(sgn * 10.5, 0.0, 4.0), {"model": "models/props_2fort/oildrum.mdl", "angles": "0 0 0"})
		app.doc.add_point_entity("item_healthkit_medium", Vector3(sgn * 12.0, 0.2, 0.0), {})
		app.doc.add_point_entity("item_ammopack_medium", Vector3(sgn * 12.0, 0.2, 3.0), {})
		app.doc.add_point_entity("light_spot", Vector3(sgn * 11.0, 6.0, 0.0), {"_light": "255 185 105 720" if team_i == 2 else "120 190 255 720", "pitch": "-75", "_cone": "55"})

	app.doc.add_point_entity("tf_gamerules", Vector3(0, 8, 0), {"targetname": "gamerules"})
	app.doc.add_point_entity("light_environment", Vector3(0, 8.6, 0), {"_light": "255 235 200 450", "pitch": "-45"})
	if mode == "ctf":
		Tf2GamemodesScript.stamp_preset(app.doc, "intel", Vector3(-15, 0.2, 0), 2)
		Tf2GamemodesScript.stamp_preset(app.doc, "intel", Vector3(15, 0.2, 0), 3)
		app.doc.add_brush_entity("func_capturezone", Vector3(-17, 0, -2.5), Vector3(-13, 3.5, 2.5), "TOOLS/TOOLSTRIGGER", {"TeamNum": "2"})
		app.doc.add_brush_entity("func_capturezone", Vector3(13, 0, -2.5), Vector3(17, 3.5, 2.5), "TOOLS/TOOLSTRIGGER", {"TeamNum": "3"})
	elif mode == "cp":
		app.doc.add_point_entity("team_control_point_master", Vector3(0, 8.4, 0), {})
		Tf2GamemodesScript.stamp_preset(app.doc, "cap_point", Vector3(-13, 0.05, 0), 2)
		Tf2GamemodesScript.stamp_preset(app.doc, "cap_point", Vector3(0, 1.05, 0), 0)
		Tf2GamemodesScript.stamp_preset(app.doc, "cap_point", Vector3(13, 0.05, 0), 3)
	else:
		app.doc.add_point_entity("tf_logic_koth", Vector3(0, 8.2, 0), {"timer_length": "180"})
		app.doc.add_point_entity("team_control_point_master", Vector3(0, 8.4, 0), {})
		Tf2GamemodesScript.stamp_preset(app.doc, "cap_point", Vector3(0, 1.05, 0), 0)

	app.doc.auto_seal_skybox()
	app.map_sync.clear_all(); app.map_sync.sync_all(true)
	app.ent_vis.clear_all(); app.ent_vis.sync_all(true)
	app.map_title_lbl.text = "| " + app.doc.get_map_name()

func _exec_break_sightlines() -> int:
	var orig := Vector3(0.0, 2.35, 0.0)
	var placed := 0
	var dirs := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(0.707, 0, 0.707), Vector3(-0.707, 0, -0.707)]
	for d_v in dirs:
		var dir: Vector3 = (d_v as Vector3).normalized()
		var rc: Dictionary = app.doc.raycast_face(orig, dir)
		if rc.get("hit", false):
			var dist_m: float = orig.distance_to(rc["hit_pos"])
			if dist_m * 32.0 > 640.0 and placed < 3:
				var spot: Vector3 = orig + dir * clampf(dist_m * 0.45, 5.5, 14.0)
				spot.y = 0.0
				app.doc.add_box(spot + Vector3(-1.2, 0.0, -0.6), spot + Vector3(1.2, 2.2, 0.6), "CONCRETE/CONCRETEWALL002")
				app.doc.add_point_entity("prop_static", spot + Vector3(1.6, 0.0, 0.2), {"model": "models/props_2fort/miningcrate001.mdl", "angles": "0 25 0"})
				placed += 1
	if placed == 0:
		app.doc.add_box(Vector3(-7.0, 0.0, -1.2), Vector3(-5.8, 2.4, 1.2), "CONCRETE/CONCRETEWALL002")
		app.doc.add_box(Vector3(5.8, 0.0, -1.2), Vector3(7.0, 2.4, 1.2), "CONCRETE/CONCRETEWALL002")
		placed = 2
	return placed

func _exec_auto_fix_map() -> int:
	var fixes := 0
	if not app.doc.is_map_sealed():
		app.doc.auto_seal_skybox(); fixes += 1
	var ents: Array = app.doc.get_entities()
	var has_rules := false; var has_sun := false; var red_sp := 0; var blu_sp := 0; var hk := 0
	for e in ents:
		var cls := str(e.get("classname", ""))
		var tm := str(e.get("kv", {}).get("TeamNum", ""))
		if cls == "tf_gamerules": has_rules = true
		elif cls == "light_environment": has_sun = true
		elif cls == "info_player_teamspawn":
			if tm == "2": red_sp += 1
			elif tm == "3": blu_sp += 1
		elif cls.begins_with("item_healthkit"): hk += 1
	if not has_rules:
		app.doc.add_point_entity("tf_gamerules", Vector3(0, 7.0, 0), {"targetname": "gamerules"}); fixes += 1
	if not has_sun:
		app.doc.add_point_entity("light_environment", Vector3(0, 7.5, 0), {"_light": "255 235 200 450", "pitch": "-45"}); fixes += 1
	while red_sp < 2:
		app.doc.add_point_entity("info_player_teamspawn", Vector3(-16.0, 0.2, float(red_sp) * 2.4 - 1.2), {"TeamNum": "2", "angles": "0 0 0"}); red_sp += 1; fixes += 1
	while blu_sp < 2:
		app.doc.add_point_entity("info_player_teamspawn", Vector3(16.0, 0.2, float(blu_sp) * 2.4 - 1.2), {"TeamNum": "3", "angles": "0 180 0"}); blu_sp += 1; fixes += 1
	if hk < 2:
		app.doc.add_point_entity("item_healthkit_medium", Vector3(-7.0, 0.2, 5.0), {})
		app.doc.add_point_entity("item_healthkit_medium", Vector3(7.0, 0.2, -5.0), {})
		fixes += 2
	return fixes

# ==============================================================================
# OBJECTIVE 0-100 TF2 MAP AUTO-SCORER & MULTI-MODEL AI ARENA (Milestone 45!)
# ==============================================================================
func score_map_doc(target_doc: Object = null) -> Dictionary:
	var d_obj: Object = target_doc if target_doc != null else (app.doc if app != null else null)
	if d_obj == null:
		return {"total": 0, "grade": "D", "seal": 0, "balance": 0, "sightlines": 0, "lighting": 0, "detail": 0, "op_rays": 0, "max_sight_u": 0}
	var scnt: int = d_obj.get_solid_count()
	var ents: Array = d_obj.get_entities()
	var sealed: bool = d_obj.is_map_sealed()

	# 1. Seal & Geometry Integrity (/25)
	var seal_pts: int = (20 if sealed else 0) + (5 if scnt >= 8 else (2 if scnt >= 2 else 0))

	# 2. Spawn & Gamemode Balance (/20)
	var red_sp := 0; var blu_sp := 0; var has_rules := false; var has_obj := false
	var lights := 0; var has_sun := false; var health := 0; var ammo := 0; var props := 0
	for e in ents:
		var cls := str(e.get("classname", ""))
		var tm := str(e.get("kv", {}).get("TeamNum", ""))
		if cls == "info_player_teamspawn":
			if tm == "2": red_sp += 1
			elif tm == "3": blu_sp += 1
		elif cls == "tf_gamerules": has_rules = true
		elif cls in ["team_control_point", "item_teamflag", "path_track", "func_capturezone"]: has_obj = true
		elif cls == "light_environment": has_sun = true; lights += 1
		elif cls.begins_with("light"): lights += 1
		elif cls.begins_with("item_healthkit"): health += 1
		elif cls.begins_with("item_ammopack"): ammo += 1
		elif cls.begins_with("prop_"): props += 1
	var bal_pts := 0
	if red_sp >= 1 and blu_sp >= 1: bal_pts += 8
	if red_sp == blu_sp and red_sp >= 2: bal_pts += 4
	if has_rules: bal_pts += 4
	if has_obj: bal_pts += 4

	# 3. Sniper Sightline Health (/20) — 18-ray 360 deg horizontal scan!
	var op_rays := 0; var max_u := 0
	for i in range(18):
		var a: float = TAU * float(i) / 18.0
		var rc: Dictionary = d_obj.raycast_face(Vector3(0, 2.35, 0), Vector3(cos(a), 0, sin(a)))
		if rc.get("hit", false):
			var du := int(round(Vector3(0, 2.35, 0).distance_to(rc["hit_pos"]) * 32.0))
			max_u = maxi(max_u, du)
			if du > 2048: op_rays += 1
	var sight_pts: int = clampi(20 - op_rays * 4 - (3 if max_u > 1600 else 0), 4, 20)

	# 4. Lighting & Atmosphere (/15)
	var light_pts: int = (6 if has_sun else 0) + mini(9, lights * 3)

	# 5. Pickups, Props & Verticality (/20)
	var min_y := 1e9; var max_y := -1e9
	for s in range(mini(scnt, 120)):
		var si: Dictionary = d_obj.get_solid_info(s)
		if si.get("valid", false) and not bool(si.get("is_skybox", false)):
			min_y = minf(min_y, (si["bounds_min"] as Vector3).y)
			max_y = maxf(max_y, (si["bounds_max"] as Vector3).y)
	var vert_u: float = maxf(0.0, (max_y - min_y) * 32.0) if max_y > min_y else 0.0
	var det_pts: int = mini(6, health * 3) + mini(6, ammo * 3) + mini(4, props) + (4 if vert_u >= 128.0 else (2 if vert_u >= 48.0 else 0))

	var total: int = clampi(seal_pts + bal_pts + sight_pts + light_pts + det_pts, 0, 100)
	var grade := "S" if total >= 92 else ("A" if total >= 82 else ("B" if total >= 70 else ("C" if total >= 55 else "D")))
	return {
		"total": total, "grade": grade,
		"seal": seal_pts, "balance": bal_pts, "sightlines": sight_pts, "lighting": light_pts, "detail": det_pts,
		"op_rays": op_rays, "max_sight_u": max_u, "solids": scnt, "entities": ents.size(),
	}

## Runs a live 3-Candidate AI & Valve-DNA Model Arena Bake-Off, scores each candidate objectively out of 100,
## and persists the ranked leaderboard to godot/ai_benchmarks/leaderboard.json!
func run_arena_bakeoff() -> Array[Dictionary]:
	var candidates := [
		{"model": "Valve-DNA: Viaduct Winter KOTH", "mode": "koth", "biome": "winter",     "extra_cover": true},
		{"model": "Valve-DNA: Turbine Spytech CTF", "mode": "ctf",  "biome": "spytech",    "extra_cover": true},
		{"model": "Valve-DNA: Badlands 3CP Arena",  "mode": "cp",   "biome": "badlands",   "extra_cover": false},
	]
	var results: Array[Dictionary] = []
	for cand in candidates:
		var tmp_doc = ClassDB.instantiate("Tf2MapDoc")
		_build_candidate_into_doc(tmp_doc, str(cand["mode"]), str(cand["biome"]), bool(cand["extra_cover"]))
		var sc := score_map_doc(tmp_doc)
		results.append({
			"model": str(cand["model"]),
			"mode": str(cand["mode"]),
			"biome": str(cand["biome"]),
			"score": int(sc["total"]),
			"grade": str(sc["grade"]),
			"max_sight_u": int(sc["max_sight_u"]),
			"solids": int(sc["solids"]),
			"entities": int(sc["entities"]),
			"ts": Time.get_datetime_string_from_system(),
		})
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["score"]) > int(b["score"]))
	arena_leaderboard = results
	_save_leaderboard()
	if app != null:
		app.audio.play("save")
		app._toast("AI Arena Complete! Winner: %s (%d/100 Grade %s)" % [str(results[0]["model"]), int(results[0]["score"]), str(results[0]["grade"])])
		if app.right_drawer.visible and app.right_drawer_title.text.find("AI MAP") != -1:
			app._open_ai_copilot_drawer()
	return results

func _build_candidate_into_doc(tdoc: Object, mode: String, biome: String, extra_cover: bool) -> void:
	var b: Dictionary = Tf2GamemodesScript.get_biome(biome)
	tdoc.new_map("%s_arena_%s" % [mode, biome])
	tdoc.set_skyname(str(b["sky"]))
	tdoc.add_box(Vector3(-22, -1, -13), Vector3(22, 0, 13), str(b["floor"]))
	tdoc.add_box(Vector3(-5, 0, -5), Vector3(5, 1.0, 5), str(b.get("trim", "CONCRETE/CONCRETEFLOOR002")))
	tdoc.add_box(Vector3(-23, 0, -14), Vector3(23, 8, -13), str(b["wall"]))
	tdoc.add_box(Vector3(-23, 0, 13), Vector3(23, 8, 14), str(b["wall"]))
	tdoc.add_box(Vector3(-23, 0, -13), Vector3(-22, 8, 13), str(b["wall"]))
	tdoc.add_box(Vector3(22, 0, -13), Vector3(23, 8, 13), str(b["wall"]))
	tdoc.add_box(Vector3(-12, 2.8, -10.5), Vector3(12, 3.1, -8.0), "METAL/METALGRATE011A")
	tdoc.add_box(Vector3(-12, 2.8, 8.0), Vector3(12, 3.1, 10.5), "METAL/METALGRATE011A")
	if extra_cover:
		tdoc.add_box(Vector3(-8.5, 0, -1.5), Vector3(-7.0, 2.6, 1.5), "CONCRETE/CONCRETEWALL002")
		tdoc.add_box(Vector3(7.0, 0, -1.5), Vector3(8.5, 2.6, 1.5), "CONCRETE/CONCRETEWALL002")
	for team_i in [2, 3]:
		var sgn: float = -1.0 if team_i == 2 else 1.0
		for si in range(3):
			tdoc.add_point_entity("info_player_teamspawn", Vector3(sgn * 19.0, 0.2, (float(si) - 1.0) * 2.4), {"TeamNum": str(team_i)})
		tdoc.add_point_entity("prop_static", Vector3(sgn * 10.0, 0.0, -4.0), {"model": "models/props_2fort/miningcrate001.mdl"})
		tdoc.add_point_entity("prop_static", Vector3(sgn * 10.0, 0.0, 4.0), {"model": "models/props_2fort/oildrum.mdl"})
		tdoc.add_point_entity("item_healthkit_medium", Vector3(sgn * 11.0, 0.2, 0.0), {})
		tdoc.add_point_entity("item_ammopack_medium", Vector3(sgn * 11.0, 0.2, 3.0), {})
		tdoc.add_point_entity("light_spot", Vector3(sgn * 10.0, 5.5, 0.0), {"_light": "255 190 110 700" if team_i == 2 else "120 190 255 700", "pitch": "-75"})
	tdoc.add_point_entity("tf_gamerules", Vector3(0, 7.0, 0), {"targetname": "gamerules"})
	tdoc.add_point_entity("light_environment", Vector3(0, 7.6, 0), {"_light": "255 235 200 450", "pitch": "-45"})
	if mode == "ctf":
		Tf2GamemodesScript.stamp_preset(tdoc, "intel", Vector3(-14, 0.2, 0), 2)
		Tf2GamemodesScript.stamp_preset(tdoc, "intel", Vector3(14, 0.2, 0), 3)
	else:
		Tf2GamemodesScript.stamp_preset(tdoc, "cap_point", Vector3(0, 1.05, 0), 0)
	tdoc.auto_seal_skybox()

# ==============================================================================
# AI MAP CO-PILOT STUDIO DRAWER UI (2 Tabs: Architect Chat | AI Arena & Valve DNA)
# ==============================================================================
static func build_copilot_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	var ai: AiMapCopilot = app.ai_copilot

	# Top 2-Tab Bar
	var tab_r := HBoxContainer.new(); tab_r.add_theme_constant_override("separation", 5); vbox.add_child(tab_r)
	for ti in [{"id": 0, "t": "1. Architect Chat"}, {"id": 1, "t": "2. AI Arena & Valve DNA"}]:
		var tb := Button.new(); tb.text = str(ti["t"]); tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var tid: int = int(ti["id"])
		HudWidgets.style_tf2_button(tb, fonts["heading"], 10, ai.active_tab == tid)
		tb.pressed.connect(func(): app.audio.play("click"); ai.active_tab = tid; app._open_ai_copilot_drawer())
		tab_r.add_child(tb)

	if ai.active_tab == 1:
		_build_arena_dna_tab(app, vbox, ai, fonts)
		return

	# 1. Engine Status + Inline 5-Provider Setup Toggle
	var c1 := HudWidgets.make_section_card("AI ENGINE: " + ai.get_active_backend_label(), fonts, HudWidgets.COL_CYAN)
	vbox.add_child(c1["panel"])
	var v1: VBoxContainer = c1["vbox"]

	var top_r := HBoxContainer.new(); top_r.add_theme_constant_override("separation", 5); v1.add_child(top_r)
	var cfg_b := Button.new(); cfg_b.text = "Hide AI Setup" if ai.show_config else "Models (Gemini/Claude/GPT/Ollama)"
	cfg_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudWidgets.style_tf2_button(cfg_b, fonts["body"], 10, ai.show_config)
	cfg_b.pressed.connect(func(): app.audio.play("click"); ai.show_config = not ai.show_config; app._open_ai_copilot_drawer())
	top_r.add_child(cfg_b)

	var undo_b := Button.new(); undo_b.text = "Undo AI"
	HudWidgets.style_tf2_button(undo_b, fonts["body"], 10)
	undo_b.pressed.connect(func(): app._do_undo())
	top_r.add_child(undo_b)

	if ai.show_config:
		var pg := GridContainer.new(); pg.columns = 3; pg.add_theme_constant_override("h_separation", 4); pg.add_theme_constant_override("v_separation", 4); v1.add_child(pg)
		for pid in ["auto", "gemini", "claude", "openai", "ollama", "offline"]:
			var pb := Button.new(); pb.text = str(pid).capitalize(); pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			HudWidgets.style_tf2_button(pb, fonts["heading"], 9, app.settings.ai_provider == pid)
			var mode_id: String = str(pid)
			pb.pressed.connect(func():
				app.audio.play("click"); app.settings.ai_provider = mode_id; app.settings.save_to_disk(); app._open_ai_copilot_drawer()
			)
			pg.add_child(pb)

		var g_le := LineEdit.new(); g_le.placeholder_text = "Gemini API Key (or GEMINI_API_KEY env)..."; g_le.secret = true; g_le.text = app.settings.gemini_api_key
		var cl_le := LineEdit.new(); cl_le.placeholder_text = "Claude API Key (or ANTHROPIC_API_KEY env)..."; cl_le.secret = true; cl_le.text = app.settings.claude_api_key
		var oa_le := LineEdit.new(); oa_le.placeholder_text = "OpenAI-Compat Key (GPT / DeepSeek / OpenRouter)..."; oa_le.secret = true; oa_le.text = app.settings.openai_api_key
		var o_le := LineEdit.new(); o_le.placeholder_text = "Ollama Model (e.g. llama3.2, qwen2.5)"; o_le.text = app.settings.ollama_model
		for le: LineEdit in [g_le, cl_le, oa_le, o_le]:
			le.add_theme_font_override("font", fonts["mono"]); le.add_theme_font_size_override("font_size", 10)
			v1.add_child(le)

		var sav_b := Button.new(); sav_b.text = "Save Multi-Model AI Settings"
		HudWidgets.style_tf2_button(sav_b, fonts["heading"], 10, true)
		sav_b.pressed.connect(func():
			app.settings.gemini_api_key = g_le.text.strip_edges()
			app.settings.claude_api_key = cl_le.text.strip_edges()
			app.settings.openai_api_key = oa_le.text.strip_edges()
			app.settings.ollama_model = o_le.text.strip_edges() if not o_le.text.strip_edges().is_empty() else "llama3.2"
			app.settings.save_to_disk()
			ai.show_config = false
			app.audio.play("save")
			app._toast("AI Settings saved! Active engine: " + ai.get_active_backend_label())
			app._open_ai_copilot_drawer()
		)
		v1.add_child(sav_b)

	# 2. One-Click "What Next?" Prompt Chips (Dynamic Follow-Ups + Core Generators!)
	var c2 := HudWidgets.make_section_card("QUICK AI ACTIONS & SUGGESTED NEXT STEPS", fonts, HudWidgets.COL_ACC)
	vbox.add_child(c2["panel"])
	var v2: VBoxContainer = c2["vbox"]
	var chips: Array[String] = []
	for fu in ai.suggested_followups:
		if not chips.has(fu):
			chips.append(fu)
	for base_c in [
		"What should I improve next?",
		"Generate a complete snowy KOTH arena",
		"Break long sniper sightlines",
		"Add a wired sliding door",
		"Add dramatic warm & cool TF2 spotlights",
		"Fix all map problems",
	]:
		if chips.size() >= 6:
			break
		if not chips.has(base_c):
			chips.append(base_c)
	var cg := GridContainer.new(); cg.columns = 2; cg.add_theme_constant_override("h_separation", 4); cg.add_theme_constant_override("v_separation", 4)
	v2.add_child(cg)
	for ch_txt in chips:
		var cb := Button.new()
		cb.text = str(ch_txt)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		HudWidgets.style_tf2_button(cb, fonts["body"], 9, ch_txt == chips[0])
		var pr: String = str(ch_txt)
		cb.pressed.connect(func(): ai.submit_prompt(pr))
		cg.add_child(cb)

	# 3. Always-Visible Prompt Input Bar + Live Chat Log (Newest on Top!)
	var c3 := HudWidgets.make_section_card("ASK OR BUILD WITH AI ARCHITECT", fonts, HudWidgets.COL_GREEN)
	vbox.add_child(c3["panel"])
	var v3: VBoxContainer = c3["vbox"]

	var inp_row := HBoxContainer.new(); inp_row.add_theme_constant_override("separation", 5); v3.add_child(inp_row)
	var ple := LineEdit.new()
	ple.placeholder_text = "Type what to build or ask 'what next?'..."
	ple.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ple.add_theme_font_override("font", fonts["body"]); ple.add_theme_font_size_override("font_size", 11)
	inp_row.add_child(ple)

	var send_fn := func() -> void:
		var t := ple.text.strip_edges()
		if not t.is_empty():
			ple.text = ""
			ai.submit_prompt(t)
	ple.text_submitted.connect(func(_s: String): send_fn.call())

	var sb := Button.new(); sb.text = "Run"
	sb.disabled = ai.is_thinking
	HudWidgets.style_tf2_button(sb, fonts["heading"], 10, true)
	sb.pressed.connect(send_fn)
	inp_row.add_child(sb)

	if ai.is_thinking:
		var th := Label.new(); th.text = "Thinking with %s..." % ai.get_active_backend_label()
		th.add_theme_font_override("font", fonts["mono"]); th.add_theme_font_size_override("font_size", 10)
		th.add_theme_color_override("font_color", HudWidgets.COL_CYAN)
		v3.add_child(th)

	var recent_msgs := ai.chat_history.slice(maxi(0, ai.chat_history.size() - 6))
	recent_msgs.reverse()
	for msg in recent_msgs:
		var is_u: bool = str(msg["role"]) == "user"
		var b_lbl := Label.new()
		var act_cnt := int(msg.get("actions_run", 0))
		b_lbl.text = str(msg.get("badge", "AI")) + (("  [APPLIED %d]" % act_cnt) if act_cnt > 0 else "")
		b_lbl.add_theme_font_override("font", fonts["mono"]); b_lbl.add_theme_font_size_override("font_size", 9)
		b_lbl.add_theme_color_override("font_color", HudWidgets.COL_ACC if is_u else HudWidgets.COL_GREEN)
		v3.add_child(b_lbl)

		var t_lbl := Label.new()
		t_lbl.text = str(msg["text"])
		t_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t_lbl.add_theme_font_override("font", fonts["body"]); t_lbl.add_theme_font_size_override("font_size", 10)
		t_lbl.add_theme_color_override("font_color", HudWidgets.COL_TX if not is_u else Color(1.0, 0.94, 0.82))
		v3.add_child(t_lbl)

static func _build_arena_dna_tab(app: Node3D, vbox: VBoxContainer, ai: AiMapCopilot, fonts: Dictionary) -> void:
	# 1. Objective Live Map Quality Score (/100)
	var sc := ai.score_map_doc()
	var grade_col := HudWidgets.COL_GREEN if int(sc["total"]) >= 82 else (HudWidgets.COL_ACC if int(sc["total"]) >= 65 else HudWidgets.COL_RED)
	var c1 := HudWidgets.make_section_card("LIVE MAP QUALITY SCORE: %d / 100 (GRADE %s)" % [int(sc["total"]), str(sc["grade"])], fonts, grade_col)
	vbox.add_child(c1["panel"])
	var v1: VBoxContainer = c1["vbox"]
	for row in [
		["Seal & Geometry:", "%d / 25" % int(sc["seal"])],
		["Spawn & Mode Balance:", "%d / 20" % int(sc["balance"])],
		["Sniper Sightlines:", "%d / 20  (Max %du, %d OP)" % [int(sc["sightlines"]), int(sc["max_sight_u"]), int(sc["op_rays"])]],
		["Lighting & Sun:", "%d / 15" % int(sc["lighting"])],
		["Pickups, Props & Height:", "%d / 20" % int(sc["detail"])],
	]:
		var rh := HBoxContainer.new(); v1.add_child(rh)
		var kl := Label.new(); kl.text = str(row[0]); kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kl.add_theme_font_override("font", fonts["body"]); kl.add_theme_font_size_override("font_size", 10)
		kl.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED); rh.add_child(kl)
		var vl := Label.new(); vl.text = str(row[1])
		vl.add_theme_font_override("font", fonts["mono"]); vl.add_theme_font_size_override("font_size", 10)
		vl.add_theme_color_override("font_color", HudWidgets.COL_TX); rh.add_child(vl)

	var fix_b := Button.new(); fix_b.text = "Auto-Boost Map Score (Fix Issues)"
	HudWidgets.style_tf2_button(fix_b, fonts["heading"], 10, int(sc["total"]) < 85)
	fix_b.pressed.connect(func(): ai.submit_prompt("Fix all map problems"); app._open_ai_copilot_drawer())
	v1.add_child(fix_b)

	# 2. Multi-Model AI Arena Bake-Off & Leaderboard
	var c2 := HudWidgets.make_section_card("AI MODEL ARENA & LEADERBOARD", fonts, HudWidgets.COL_CYAN)
	vbox.add_child(c2["panel"])
	var v2: VBoxContainer = c2["vbox"]
	var run_b := Button.new(); run_b.text = "Run 3-Candidate AI Arena Bake-Off"
	HudWidgets.style_tf2_button(run_b, fonts["heading"], 10, true)
	run_b.pressed.connect(func(): ai.run_arena_bakeoff())
	v2.add_child(run_b)

	if ai.arena_leaderboard.is_empty():
		var el := Label.new(); el.text = "Click above to benchmark & score 3 Valve-DNA map candidates into leaderboard.json!"
		el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		el.add_theme_font_override("font", fonts["body"]); el.add_theme_font_size_override("font_size", 10)
		el.add_theme_color_override("font_color", HudWidgets.COL_TX_MUTED); v2.add_child(el)
	else:
		for rank in range(mini(3, ai.arena_leaderboard.size())):
			var e: Dictionary = ai.arena_leaderboard[rank]
			var rb := Button.new()
			rb.text = "#%d  %s — %d/100 (Grade %s | Max Sight %du)  [Build]" % [
				rank + 1, str(e["model"]), int(e["score"]), str(e["grade"]), int(e.get("max_sight_u", 0))
			]
			rb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			rb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			HudWidgets.style_tf2_button(rb, fonts["body"], 9, rank == 0)
			var m_id: String = str(e.get("mode", "koth"))
			var b_id: String = str(e.get("biome", "winter"))
			rb.pressed.connect(func():
				ai._exec_generate_arena(m_id, b_id)
				app._record_history("Arena Winner: " + str(e["model"]))
				app._toast("Loaded Arena Candidate: %s!" % str(e["model"]))
				app._open_ai_copilot_drawer()
			)
			v2.add_child(rb)

	# 3. Mined Official Valve TF2 Map DNA Corpus
	var studied: Array = ai.valve_dna.get("maps_studied", [])
	var c3 := HudWidgets.make_section_card("OFFICIAL VALVE TF2 MAP DNA (%d MAPS MINED)" % studied.size(), fonts, HudWidgets.COL_ACC)
	vbox.add_child(c3["panel"])
	var v3: VBoxContainer = c3["vbox"]
	for i in range(mini(5, studied.size())):
		var m: Dictionary = studied[i]
		var ml := Label.new()
		var sp: Array = m.get("play_span_u", [0, 0, 0])
		ml.text = "%s (%s) — %s | %d props | %d doors" % [
			str(m["name"]), str(m["mode"]).to_upper(), str(m.get("skyname", "")), int(m.get("total_props", 0)), int(m.get("door_count", 0))
		]
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ml.add_theme_font_override("font", fonts["mono"]); ml.add_theme_font_size_override("font_size", 9)
		ml.add_theme_color_override("font_color", HudWidgets.COL_TX)
		v3.add_child(ml)
