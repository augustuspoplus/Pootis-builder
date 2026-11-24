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
var chat_history: Array[Dictionary] = [] # [{role: "user"|"ai", text: String, badge: String, actions_run: int}]
var _pending_prompt: String = ""
var _pending_backend: String = "offline"

func setup(p_app: Node3D) -> void:
	app = p_app
	http = HTTPRequest.new()
	http.timeout = 24.0
	add_child(http)
	http.request_completed.connect(_on_http_completed)
	if chat_history.is_empty():
		chat_history.append({
			"role": "ai",
			"text": "Hi! I'm your TF2 AI Map Architect. Tell me what you want to build (like 'add a sniper balcony with crates' or 'add warm lights'), or click 'What should I improve next?' for a live map critique!",
			"badge": get_active_backend_label(),
			"actions_run": 0,
		})

func get_effective_gemini_key() -> String:
	if app != null and app.settings != null and not app.settings.gemini_api_key.strip_edges().is_empty():
		return app.settings.gemini_api_key.strip_edges()
	var env_k := OS.get_environment("GEMINI_API_KEY").strip_edges()
	return env_k

func get_active_backend() -> String:
	if app == null or app.settings == null:
		return "offline"
	var pref: String = str(app.settings.ai_provider).to_lower()
	if pref == "offline":
		return "offline"
	if pref == "gemini":
		return "gemini" if not get_effective_gemini_key().is_empty() else "offline"
	if pref == "ollama":
		return "ollama"
	# "auto": use Gemini if key exists, else instant offline architect
	if not get_effective_gemini_key().is_empty():
		return "gemini"
	return "offline"

func get_active_backend_label() -> String:
	var b := get_active_backend()
	if b == "gemini":
		return "GEMINI API (%s)" % (app.settings.gemini_model if app != null else "gemini-2.5-flash")
	if b == "ollama":
		return "LOCAL OLLAMA (%s)" % (app.settings.ollama_model if app != null else "llama3.2")
	return "OFFLINE TF2 ARCHITECT (INSTANT)"

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
    {"op": "apply_biome", "biome": "badlands|winter|spytech|industrial|medieval|farm"},
    {"op": "set_lighting_mode", "mode": 1},
    {"op": "auto_seal"}
  ]
}
Only include actions if the user asks to build, add, fix, light, or change something. Keep action count <= 10.""" % build_map_context_summary()

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

# ==============================================================================
# AI MAP CO-PILOT STUDIO DRAWER UI
# ==============================================================================
static func build_copilot_drawer(app: Node3D, vbox: VBoxContainer) -> void:
	var fonts: Dictionary = app.fonts
	var ai: AiMapCopilot = app.ai_copilot

	# 1. Engine Status + Inline Setup Toggle
	var c1 := HudWidgets.make_section_card("AI ENGINE: " + ai.get_active_backend_label(), fonts, HudWidgets.COL_CYAN)
	vbox.add_child(c1["panel"])
	var v1: VBoxContainer = c1["vbox"]

	var top_r := HBoxContainer.new(); top_r.add_theme_constant_override("separation", 5); v1.add_child(top_r)
	var cfg_b := Button.new(); cfg_b.text = "Hide AI Setup" if ai.show_config else "Configure Gemini / Ollama"
	cfg_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	HudWidgets.style_tf2_button(cfg_b, fonts["body"], 10, ai.show_config)
	cfg_b.pressed.connect(func(): app.audio.play("click"); ai.show_config = not ai.show_config; app._open_ai_copilot_drawer())
	top_r.add_child(cfg_b)

	var undo_b := Button.new(); undo_b.text = "Undo AI"
	HudWidgets.style_tf2_button(undo_b, fonts["body"], 10)
	undo_b.pressed.connect(func(): app._do_undo())
	top_r.add_child(undo_b)

	if ai.show_config:
		var prow := HBoxContainer.new(); prow.add_theme_constant_override("separation", 4); v1.add_child(prow)
		for pid in ["auto", "gemini", "ollama", "offline"]:
			var pb := Button.new(); pb.text = str(pid).capitalize(); pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			HudWidgets.style_tf2_button(pb, fonts["heading"], 9, app.settings.ai_provider == pid)
			var mode_id: String = str(pid)
			pb.pressed.connect(func():
				app.audio.play("click"); app.settings.ai_provider = mode_id; app.settings.save_to_disk(); app._open_ai_copilot_drawer()
			)
			prow.add_child(pb)

		var g_le := LineEdit.new()
		g_le.placeholder_text = "Optional Gemini API Key (or set GEMINI_API_KEY env var)..."
		g_le.secret = true
		g_le.text = app.settings.gemini_api_key
		g_le.add_theme_font_override("font", fonts["mono"]); g_le.add_theme_font_size_override("font_size", 10)
		v1.add_child(g_le)

		var o_le := LineEdit.new()
		o_le.placeholder_text = "Local Ollama Model (e.g. llama3.2, qwen2.5)"
		o_le.text = app.settings.ollama_model
		o_le.add_theme_font_override("font", fonts["mono"]); o_le.add_theme_font_size_override("font_size", 10)
		v1.add_child(o_le)

		var sav_b := Button.new(); sav_b.text = "Save AI Settings"
		HudWidgets.style_tf2_button(sav_b, fonts["heading"], 10, true)
		sav_b.pressed.connect(func():
			app.settings.gemini_api_key = g_le.text.strip_edges()
			app.settings.ollama_model = o_le.text.strip_edges() if not o_le.text.strip_edges().is_empty() else "llama3.2"
			app.settings.save_to_disk()
			ai.show_config = false
			app.audio.play("save")
			app._toast("AI Settings saved! Active engine: " + ai.get_active_backend_label())
			app._open_ai_copilot_drawer()
		)
		v1.add_child(sav_b)

	# 2. One-Click "What Next?" Prompt Chips
	var c2 := HudWidgets.make_section_card("QUICK AI ACTIONS (1-CLICK)", fonts, HudWidgets.COL_ACC)
	vbox.add_child(c2["panel"])
	var v2: VBoxContainer = c2["vbox"]
	var chips := [
		"What should I improve next?",
		"Build a sniper balcony + cover crates",
		"Add dramatic warm & cool TF2 spotlights",
		"Build an elevated catwalk with ramps",
		"Add symmetrical health & ammo pickups",
		"Switch to winter theme & scatter pine trees",
	]
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
