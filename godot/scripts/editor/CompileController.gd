class_name CompileController
extends Node3D

## Milestone 7 — Async TF2 Map Compiler Controller (vbsp / vvis / vrad / TF2 launch),
## 3D Glowing Red Leak Laser Renderer, 1-Click Auto-Seal Recovery, and BSPSource Remix.

signal status_changed(state: Dictionary)
signal compile_finished(state: Dictionary)

var compiler: Object
var is_running: bool = false
var last_state: Dictionary = {}
var leak_laser: MeshInstance3D

func _ready() -> void:
	compiler = ClassDB.instantiate("Tf2Compiler")
	leak_laser = MeshInstance3D.new()
	leak_laser.name = "LeakPointfileLaser"
	leak_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(leak_laser)

func detect_paths() -> Dictionary:
	if compiler == null:
		compiler = ClassDB.instantiate("Tf2Compiler")
	return compiler.detect_paths()

func start_compile(vmf_path: String, fast_profile: bool = true,
				   run_vvis: bool = true, run_vrad: bool = true,
				   launch_tf2: bool = false, map_name: String = "") -> bool:
	if compiler == null:
		compiler = ClassDB.instantiate("Tf2Compiler")
	clear_leak_laser()
	var ok: bool = compiler.start_compile(vmf_path, fast_profile, run_vvis, run_vrad, launch_tf2, map_name)
	is_running = ok
	return ok

func cancel_compile() -> void:
	if compiler != null:
		compiler.cancel()
	is_running = false

func clear_leak_laser() -> void:
	if leak_laser != null:
		leak_laser.mesh = null
		for ch in leak_laser.get_children():
			ch.queue_free()

func show_leak_points(pts: PackedVector3Array) -> void:
	clear_leak_laser()
	if pts.size() < 2:
		return
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.12, 0.10, 1.0)
	mat.no_depth_test = true
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
	for p in pts:
		im.surface_add_vertex(p)
	im.surface_end()
	leak_laser.mesh = im

	# Add bright red warning beacons at leak start & void breach point
	for idx in [0, pts.size() - 1]:
		var sphere := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.45
		sphere.mesh = sm
		sphere.material_override = mat
		sphere.position = pts[idx]
		leak_laser.add_child(sphere)

func poll_once() -> Dictionary:
	if compiler == null:
		return {}
	var st: Dictionary = compiler.poll()
	last_state = st
	if is_running:
		status_changed.emit(st)
		if st.get("finished", false):
			is_running = false
			var lin: String = str(st.get("leak_file", ""))
			if not lin.is_empty():
				var pts: PackedVector3Array = compiler.read_leak_points(lin)
				show_leak_points(pts)
				st["leak_points"] = pts
			compile_finished.emit(st)
	return st

func _process(_delta: float) -> void:
	if is_running:
		poll_once()

func decompile_bsp(repo_root: String, bsp_path: String) -> Dictionary:
	if compiler == null:
		compiler = ClassDB.instantiate("Tf2Compiler")
	return compiler.decompile_bsp(repo_root, bsp_path)
