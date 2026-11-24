class_name AppSettings
extends RefCounted

## Persistent 7-Tab Settings & Live HiDPI / UI Scale Engine for Pootis Builder 2.0.
## Combines Display/DPI Scaling + all 6 Valve Hammer Options tabs + VAC-Safe lock!

const CFG_PATH := "user://pootis_settings.cfg"

# Tab 1: Display & UI Scale
var auto_dpi: bool = true
var ui_scale: float = 1.15         # 0.75 .. 2.25 (75% .. 225%)
var window_mode: int = 1           # 0=Windowed, 1=Maximized, 2=Borderless Fullscreen
var vsync: bool = true
var icon_resolution: int = 160     # 128 / 160 / 192
var show_2d_split: bool = false

# Tab 2: Viewport & 3D Views (Hammer Dialog 199)
var msaa_level: int = 1            # 0=Off, 1=2x (snappy default), 2=4x
var shadow_quality: int = 1        # 0=Low, 1=Med (snappy default), 2=High
var ssao_enabled: bool = false     # Off by default for crisp 120+ FPS responsiveness!
var camera_fov: float = 75.0
var back_clip_m: float = 650.0
var prop_ambient_boost: float = 0.28
var show_skybox_bg: bool = true

# AI Map Co-Pilot (Hybrid: Gemini + Claude + OpenAI-Compatible + Local Ollama + Valve-DNA Offline!)
var ai_provider: String = "auto"   # auto | gemini | claude | openai | ollama | offline
var gemini_api_key: String = ""
var gemini_model: String = "gemini-2.5-flash"
var claude_api_key: String = ""
var claude_model: String = "claude-sonnet-4-20250514"
var openai_api_key: String = ""
var openai_base_url: String = "https://api.openai.com/v1"
var openai_model: String = "gpt-4o-mini"
var ollama_url: String = "http://127.0.0.1:11434"
var ollama_model: String = "llama3.2"

# Tab 3: 2D Views & Grid (Hammer Dialog 179)
var default_grid_u: int = 32
var show_grid_floor: bool = true
var grid_opacity: float = 0.22
var show_jump_callouts: bool = true
var arrow_key_nudge: bool = true
var rotate_step_deg: int = 90      # 15 / 45 / 90

# Tab 4: Controls & Keybinds
var keybind_preset: String = "Hammer++ / TrenchBroom"
var fly_speed: float = 22.0
var mouse_sens: float = 0.0035
var invert_y: bool = false

# Tab 5: TF2, FGDs & Build Programs (Hammer Dialogs 207 & 275)
var tf2_dir_override: String = ""
var compile_preset: String = "Fast" # Fast | Default | Only Entities | HDR Full | HDR Final
var compile_threads: int = 0        # 0 = Auto
var vac_safe_insecure: bool = true  # Always enforced when launching TF2!
var auto_seal_on_compile: bool = true

# Tab 6: Playtest & Audio
var default_playtest_class: int = 1 # 0=Scout, 1=Soldier, 2=Demo, 3=Sniper, 4=Engi, 5=Heavy
var playtest_fov: float = 90.0
var noclip_speed: float = 14.0
var sfx_volume_db: float = -6.0
var sfx_muted: bool = false

# Tab 7: Auto-Save & Backups (Hammer Dialog 174)
var autosave_enabled: bool = true
var autosave_minutes: int = 5
var backup_count: int = 8

func load_from_disk() -> void:
	var cf := ConfigFile.new()
	if cf.load(CFG_PATH) != OK:
		return
	auto_dpi = bool(cf.get_value("display", "auto_dpi", auto_dpi))
	ui_scale = clampf(float(cf.get_value("display", "ui_scale", ui_scale)), 0.75, 2.25)
	window_mode = clampi(int(cf.get_value("display", "window_mode", window_mode)), 0, 2)
	vsync = bool(cf.get_value("display", "vsync", vsync))
	icon_resolution = int(cf.get_value("display", "icon_resolution", icon_resolution))
	show_2d_split = bool(cf.get_value("display", "show_2d_split", show_2d_split))

	msaa_level = clampi(int(cf.get_value("viewport", "msaa_level", msaa_level)), 0, 2)
	shadow_quality = clampi(int(cf.get_value("viewport", "shadow_quality", shadow_quality)), 0, 2)
	ssao_enabled = bool(cf.get_value("viewport", "ssao_enabled", ssao_enabled))
	camera_fov = clampf(float(cf.get_value("viewport", "camera_fov", camera_fov)), 50.0, 105.0)
	back_clip_m = clampf(float(cf.get_value("viewport", "back_clip_m", back_clip_m)), 150.0, 2000.0)
	prop_ambient_boost = clampf(float(cf.get_value("viewport", "prop_ambient_boost", prop_ambient_boost)), 0.0, 0.7)
	show_skybox_bg = bool(cf.get_value("viewport", "show_skybox_bg", show_skybox_bg))

	default_grid_u = int(cf.get_value("grid", "default_grid_u", default_grid_u))
	show_grid_floor = bool(cf.get_value("grid", "show_grid_floor", show_grid_floor))
	grid_opacity = clampf(float(cf.get_value("grid", "grid_opacity", grid_opacity)), 0.04, 0.8)
	show_jump_callouts = bool(cf.get_value("grid", "show_jump_callouts", show_jump_callouts))
	arrow_key_nudge = bool(cf.get_value("grid", "arrow_key_nudge", arrow_key_nudge))
	rotate_step_deg = int(cf.get_value("grid", "rotate_step_deg", rotate_step_deg))

	keybind_preset = str(cf.get_value("controls", "keybind_preset", keybind_preset))
	fly_speed = clampf(float(cf.get_value("controls", "fly_speed", fly_speed)), 6.0, 60.0)
	mouse_sens = clampf(float(cf.get_value("controls", "mouse_sens", mouse_sens)), 0.001, 0.012)
	invert_y = bool(cf.get_value("controls", "invert_y", invert_y))

	tf2_dir_override = str(cf.get_value("tf2", "tf2_dir_override", tf2_dir_override))
	compile_preset = str(cf.get_value("tf2", "compile_preset", compile_preset))
	compile_threads = int(cf.get_value("tf2", "compile_threads", compile_threads))
	vac_safe_insecure = true # Always enforce VAC safety!
	auto_seal_on_compile = bool(cf.get_value("tf2", "auto_seal_on_compile", auto_seal_on_compile))

	default_playtest_class = clampi(int(cf.get_value("playtest", "default_playtest_class", default_playtest_class)), 0, 5)
	playtest_fov = clampf(float(cf.get_value("playtest", "playtest_fov", playtest_fov)), 70.0, 110.0)
	noclip_speed = clampf(float(cf.get_value("playtest", "noclip_speed", noclip_speed)), 5.0, 40.0)
	sfx_volume_db = clampf(float(cf.get_value("playtest", "sfx_volume_db", sfx_volume_db)), -36.0, 0.0)
	sfx_muted = bool(cf.get_value("playtest", "sfx_muted", sfx_muted))

	autosave_enabled = bool(cf.get_value("autosave", "autosave_enabled", autosave_enabled))
	autosave_minutes = clampi(int(cf.get_value("autosave", "autosave_minutes", autosave_minutes)), 1, 30)
	backup_count = clampi(int(cf.get_value("autosave", "backup_count", backup_count)), 1, 30)

	ai_provider = str(cf.get_value("ai", "ai_provider", ai_provider))
	gemini_api_key = str(cf.get_value("ai", "gemini_api_key", gemini_api_key))
	gemini_model = str(cf.get_value("ai", "gemini_model", gemini_model))
	claude_api_key = str(cf.get_value("ai", "claude_api_key", claude_api_key))
	claude_model = str(cf.get_value("ai", "claude_model", claude_model))
	openai_api_key = str(cf.get_value("ai", "openai_api_key", openai_api_key))
	openai_base_url = str(cf.get_value("ai", "openai_base_url", openai_base_url))
	openai_model = str(cf.get_value("ai", "openai_model", openai_model))
	ollama_url = str(cf.get_value("ai", "ollama_url", ollama_url))
	ollama_model = str(cf.get_value("ai", "ollama_model", ollama_model))

func save_to_disk() -> void:
	var cf := ConfigFile.new()
	cf.set_value("display", "auto_dpi", auto_dpi)
	cf.set_value("display", "ui_scale", ui_scale)
	cf.set_value("display", "window_mode", window_mode)
	cf.set_value("display", "vsync", vsync)
	cf.set_value("display", "icon_resolution", icon_resolution)
	cf.set_value("display", "show_2d_split", show_2d_split)

	cf.set_value("viewport", "msaa_level", msaa_level)
	cf.set_value("viewport", "shadow_quality", shadow_quality)
	cf.set_value("viewport", "ssao_enabled", ssao_enabled)
	cf.set_value("viewport", "camera_fov", camera_fov)
	cf.set_value("viewport", "back_clip_m", back_clip_m)
	cf.set_value("viewport", "prop_ambient_boost", prop_ambient_boost)
	cf.set_value("viewport", "show_skybox_bg", show_skybox_bg)

	cf.set_value("grid", "default_grid_u", default_grid_u)
	cf.set_value("grid", "show_grid_floor", show_grid_floor)
	cf.set_value("grid", "grid_opacity", grid_opacity)
	cf.set_value("grid", "show_jump_callouts", show_jump_callouts)
	cf.set_value("grid", "arrow_key_nudge", arrow_key_nudge)
	cf.set_value("grid", "rotate_step_deg", rotate_step_deg)

	cf.set_value("controls", "keybind_preset", keybind_preset)
	cf.set_value("controls", "fly_speed", fly_speed)
	cf.set_value("controls", "mouse_sens", mouse_sens)
	cf.set_value("controls", "invert_y", invert_y)

	cf.set_value("tf2", "tf2_dir_override", tf2_dir_override)
	cf.set_value("tf2", "compile_preset", compile_preset)
	cf.set_value("tf2", "compile_threads", compile_threads)
	cf.set_value("tf2", "vac_safe_insecure", true)
	cf.set_value("tf2", "auto_seal_on_compile", auto_seal_on_compile)

	cf.set_value("playtest", "default_playtest_class", default_playtest_class)
	cf.set_value("playtest", "playtest_fov", playtest_fov)
	cf.set_value("playtest", "noclip_speed", noclip_speed)
	cf.set_value("playtest", "sfx_volume_db", sfx_volume_db)
	cf.set_value("playtest", "sfx_muted", sfx_muted)

	cf.set_value("autosave", "autosave_enabled", autosave_enabled)
	cf.set_value("autosave", "autosave_minutes", autosave_minutes)
	cf.set_value("autosave", "backup_count", backup_count)

	cf.set_value("ai", "ai_provider", ai_provider)
	cf.set_value("ai", "gemini_api_key", gemini_api_key)
	cf.set_value("ai", "gemini_model", gemini_model)
	cf.set_value("ai", "claude_api_key", claude_api_key)
	cf.set_value("ai", "claude_model", claude_model)
	cf.set_value("ai", "openai_api_key", openai_api_key)
	cf.set_value("ai", "openai_base_url", openai_base_url)
	cf.set_value("ai", "openai_model", openai_model)
	cf.set_value("ai", "ollama_url", ollama_url)
	cf.set_value("ai", "ollama_model", ollama_model)
	cf.save(CFG_PATH)

func reset_defaults() -> void:
	auto_dpi = true; ui_scale = 1.15; window_mode = 1; vsync = true
	icon_resolution = 160; show_2d_split = false
	msaa_level = 2; shadow_quality = 2; ssao_enabled = true
	camera_fov = 75.0; back_clip_m = 650.0; prop_ambient_boost = 0.28; show_skybox_bg = true
	default_grid_u = 32; show_grid_floor = true; grid_opacity = 0.22
	show_jump_callouts = true; arrow_key_nudge = true; rotate_step_deg = 90
	keybind_preset = "Hammer++ / TrenchBroom"; fly_speed = 22.0; mouse_sens = 0.0035; invert_y = false
	compile_preset = "Fast"; compile_threads = 0; vac_safe_insecure = true; auto_seal_on_compile = true
	default_playtest_class = 1; playtest_fov = 90.0; noclip_speed = 14.0; sfx_volume_db = -6.0; sfx_muted = false
	autosave_enabled = true; autosave_minutes = 5; backup_count = 8

func to_dict() -> Dictionary:
	return {
		"auto_dpi": auto_dpi, "ui_scale": ui_scale, "window_mode": window_mode,
		"vsync": vsync, "icon_resolution": icon_resolution, "show_2d_split": show_2d_split,
		"msaa_level": msaa_level, "shadow_quality": shadow_quality, "ssao_enabled": ssao_enabled,
		"camera_fov": camera_fov, "back_clip_m": back_clip_m, "prop_ambient_boost": prop_ambient_boost,
		"show_skybox_bg": show_skybox_bg, "default_grid_u": default_grid_u, "show_grid_floor": show_grid_floor,
		"grid_opacity": grid_opacity, "show_jump_callouts": show_jump_callouts, "arrow_key_nudge": arrow_key_nudge,
		"rotate_step_deg": rotate_step_deg, "keybind_preset": keybind_preset, "fly_speed": fly_speed,
		"mouse_sens": mouse_sens, "invert_y": invert_y, "tf2_dir_override": tf2_dir_override,
		"compile_preset": compile_preset, "compile_threads": compile_threads, "auto_seal_on_compile": auto_seal_on_compile,
		"default_playtest_class": default_playtest_class, "playtest_fov": playtest_fov, "noclip_speed": noclip_speed,
		"sfx_volume_db": sfx_volume_db, "sfx_muted": sfx_muted, "autosave_enabled": autosave_enabled,
		"autosave_minutes": autosave_minutes, "backup_count": backup_count,
	}

func from_dict(d: Dictionary) -> void:
	for k in d.keys():
		if k in self:
			set(k, d[k])
	vac_safe_insecure = true

func compute_effective_scale(win: Window) -> float:
	# Native 1:1 HiDPI scaling (window/stretch/mode="disabled") for razor-sharp text & 1px borders!
	var user_mult := clampf(ui_scale, 0.75, 2.25)
	var eff := user_mult
	if auto_dpi and DisplayServer.get_name() != "headless":
		var scr := DisplayServer.window_get_current_screen(win.get_window_id())
		var dpi: int = DisplayServer.screen_get_dpi(scr)
		var os_scale: float = DisplayServer.screen_get_scale(scr)
		if os_scale <= 0.01:
			os_scale = clampf(float(dpi) / 96.0, 1.0, 2.0)
		var snapped_os := snappedf(clampf(os_scale, 1.0, 2.0), 0.25)
		# Only boost by OS scale when user is near 100%-135%; at explicit high zoom (150%+) honor exact user scale
		eff = maxf(snapped_os * user_mult if user_mult <= 1.35 else user_mult, user_mult)
	# Safety cap: always keep at least ~760 logical px width & ~420 logical px height so UI NEVER overflows!
	var win_sz: Vector2i = win.size
	if win_sz.x > 400 and win_sz.y > 300:
		var max_safe := minf(float(win_sz.x) / 760.0, float(win_sz.y) / 420.0)
		eff = minf(eff, clampf(max_safe, 1.0, 2.25))
	return clampf(snappedf(eff, 0.05), 0.75, 2.25)

func apply_runtime(main_app: Node3D) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var win := main_app.get_window()
	if win == null:
		return
	var eff := compute_effective_scale(win)
	win.content_scale_factor = eff

	if main_app.get("_auto_shots") is Array and (main_app._auto_shots as Array).is_empty():
		var want_mode := DisplayServer.WINDOW_MODE_WINDOWED
		if window_mode == 1: want_mode = DisplayServer.WINDOW_MODE_MAXIMIZED
		elif window_mode == 2: want_mode = DisplayServer.WINDOW_MODE_FULLSCREEN
		if DisplayServer.window_get_mode() != want_mode:
			DisplayServer.window_set_mode(want_mode)

	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)

	var vp := main_app.get_viewport()
	if vp != null:
		var mvals := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X]
		vp.msaa_3d = mvals[clampi(msaa_level, 0, 2)]
	if main_app.get("editor_cam") != null:
		var cam: Camera3D = main_app.editor_cam
		cam.fov = camera_fov
		cam.far = back_clip_m
	if main_app.get("we") != null and main_app.we.environment != null:
		var env: Environment = main_app.we.environment
		env.ssao_enabled = ssao_enabled
		env.background_mode = Environment.BG_SKY if show_skybox_bg else Environment.BG_COLOR
		if not show_skybox_bg:
			env.background_color = Color(0.11, 0.10, 0.09)
	if main_app.get("sun") != null:
		main_app.sun.shadow_enabled = (shadow_quality > 0)
	if main_app.get("grid_floor") != null:
		main_app.grid_floor.visible = show_grid_floor and not bool(main_app.get("viewing_bsp"))
		var gmat: Material = main_app.grid_floor.material_override
		if gmat is StandardMaterial3D:
			(gmat as StandardMaterial3D).albedo_color.a = clampf(grid_opacity, 0.05, 0.85)
	if main_app.get("assets") != null:
		main_app.assets.prop_ambient_boost = prop_ambient_boost
	if main_app.get("player") != null:
		main_app.player.base_fov = playtest_fov
		main_app.player.noclip_speed_u = noclip_speed * 32.0
		if main_app.player.cam != null and not main_app.player.scoped:
			main_app.player.cam.fov = playtest_fov
	if main_app.get("audio") != null:
		main_app.audio.set_volume(sfx_volume_db, sfx_muted)
