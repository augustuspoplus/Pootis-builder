class_name Tf2Assets
extends RefCounted

## Live TF2 Asset, Material, Skybox & 3D StudioModel Streaming Manager.
## Supports real VPKs + compressed BSP Pakfiles (STORED/DEFLATE/LZMA),
## WorldVertexTransition dual textures, Valve Half-Lambert prop ambient fill,
## and live VPK material swatch textures for the Material Browser!

const MAX_INFO_CACHE := 512
const MAX_MESH_CACHE := 256

var core: Object
var prop_ambient_boost: float = 0.28
var _mat_cache: Dictionary = {}    # key -> StandardMaterial3D
var _info_cache: Dictionary = {}   # key -> Dictionary {tex, tex2, ...}
var _info_lru: Array[String] = []
var _mesh_cache: Dictionary = {}   # mdl_path -> ArrayMesh
var _mesh_lru: Array[String] = []
var _sky_cache: Dictionary = {}    # skyname -> Sky

# Background WorkerThreadPool async VTF swatch streaming
var _swatch_queue: Array[String] = []
var _swatch_cbs: Dictionary = {}   # key -> Array[Callable]
var _swatch_task_id: int = -1
var _swatch_task_key: String = ""
var _swatch_task_path: String = ""
var _swatch_mutex := Mutex.new()
var _swatch_raw_res: Dictionary = {}

func _init(p_core: Object) -> void:
	core = p_core

func clear_bsp_cache() -> void:
	_mat_cache.clear()
	_info_cache.clear()
	_info_lru.clear()
	_mesh_cache.clear()
	_mesh_lru.clear()

func _touch_info_lru(key: String) -> void:
	var idx := _info_lru.find(key)
	if idx >= 0:
		_info_lru.remove_at(idx)
	_info_lru.append(key)
	while _info_lru.size() > MAX_INFO_CACHE:
		var evict: String = _info_lru.pop_front()
		if not _mat_cache.has(evict) and not _mat_cache.has(evict + "|prop"):
			_info_cache.erase(evict)

func _touch_mesh_lru(key: String) -> void:
	var idx := _mesh_lru.find(key)
	if idx >= 0:
		_mesh_lru.remove_at(idx)
	_mesh_lru.append(key)
	while _mesh_lru.size() > MAX_MESH_CACHE:
		var evict: String = _mesh_lru.pop_front()
		_mesh_cache.erase(evict)

func _build_info_from_raw(d: Dictionary) -> Dictionary:
	var res := {
		"ok": false, "tex": null, "tex2": null, "has_blend": false,
		"alpha_test": false, "translucent": false, "additive": false, "no_cull": false,
		"self_illum": false, "has_alpha": false, "color_tint": Color.WHITE,
	}
	if d != null and d.get("ok", false):
		var w := int(d["width"])
		var h := int(d["height"])
		var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, d["rgba"])
		img.generate_mipmaps()
		res["ok"] = true
		res["tex"] = ImageTexture.create_from_image(img)
		res["has_alpha"] = bool(d.get("has_alpha", false))
		res["alpha_test"] = bool(d.get("alpha_test", false))
		res["translucent"] = bool(d.get("translucent", false))
		res["additive"] = bool(d.get("additive", false))
		res["no_cull"] = bool(d.get("no_cull", false))
		res["self_illum"] = bool(d.get("self_illum", false))
		res["color_tint"] = d.get("color_tint", Color.WHITE)
		if d.get("has_blend", false):
			var w2 := int(d["width2"])
			var h2 := int(d["height2"])
			var img2 := Image.create_from_data(w2, h2, false, Image.FORMAT_RGBA8, d["rgba2"])
			img2.generate_mipmaps()
			res["has_blend"] = true
			res["tex2"] = ImageTexture.create_from_image(img2)
	return res

func get_material_info(mat_path: String) -> Dictionary:
	var key := mat_path.to_lower()
	if _info_cache.has(key):
		_touch_info_lru(key)
		return _info_cache[key]
	var res := _build_info_from_raw(core.read_material_rgba(mat_path))
	_info_cache[key] = res
	_touch_info_lru(key)
	return res

func get_material_swatch(mat_path: String) -> Texture2D:
	var info := get_material_info(mat_path)
	return info["tex"] if info.get("ok", false) else null

## Non-blocking material swatch loader using WeakRef (zero freed-lambda warnings when closing drawers!).
func request_material_swatch_async(mat_path: String, target_rect: TextureRect) -> Texture2D:
	var key := mat_path.to_lower()
	if _info_cache.has(key):
		_touch_info_lru(key)
		var inf: Dictionary = _info_cache[key]
		var t: Texture2D = inf["tex"] if inf.get("ok", false) else null
		if target_rect != null and is_instance_valid(target_rect) and t != null:
			target_rect.texture = t
		return t
	if not _swatch_cbs.has(key):
		_swatch_cbs[key] = []
		_swatch_queue.append(mat_path)
	if target_rect != null:
		(_swatch_cbs[key] as Array).append(weakref(target_rect))
	return null

func poll_async_loads() -> void:
	if core == null:
		return
	if _swatch_task_id != -1:
		if not WorkerThreadPool.is_task_completed(_swatch_task_id):
			return
		WorkerThreadPool.wait_for_task_completion(_swatch_task_id)
		_swatch_task_id = -1
		_swatch_mutex.lock()
		var raw := _swatch_raw_res
		_swatch_raw_res = {}
		_swatch_mutex.unlock()
		var key := _swatch_task_key
		var res := _build_info_from_raw(raw)
		_info_cache[key] = res
		_touch_info_lru(key)
		var tex: Texture2D = res["tex"] if res.get("ok", false) else null
		if _swatch_cbs.has(key):
			for wr in _swatch_cbs[key]:
				var tr = (wr as WeakRef).get_ref() if wr is WeakRef else null
				if tr != null and is_instance_valid(tr) and tex != null:
					(tr as TextureRect).texture = tex
			_swatch_cbs.erase(key)
	if _swatch_task_id == -1 and not _swatch_queue.is_empty():
		var next_path: String = _swatch_queue.pop_front()
		var nkey := next_path.to_lower()
		if _info_cache.has(nkey):
			var inf: Dictionary = _info_cache[nkey]
			var tex: Texture2D = inf["tex"] if inf.get("ok", false) else null
			if _swatch_cbs.has(nkey):
				for wr in _swatch_cbs[nkey]:
					var tr = (wr as WeakRef).get_ref() if wr is WeakRef else null
					if tr != null and is_instance_valid(tr) and tex != null:
						(tr as TextureRect).texture = tex
				_swatch_cbs.erase(nkey)
			return
		_swatch_task_key = nkey
		_swatch_task_path = next_path
		var core_ref: Object = core
		_swatch_task_id = WorkerThreadPool.add_task(func():
			var d: Dictionary = core_ref.read_material_rgba(next_path)
			_swatch_mutex.lock()
			_swatch_raw_res = d
			_swatch_mutex.unlock()
		)

func get_material(mat_path: String, triplanar := false, is_prop := false) -> StandardMaterial3D:
	var key := mat_path.to_lower() + ("|tri" if triplanar else "") + ("|prop" if is_prop else "")
	if _mat_cache.has(key):
		return _mat_cache[key]

	var mat := StandardMaterial3D.new()
	mat.roughness = 0.84
	mat.metallic = 0.04

	var info := get_material_info(mat_path)
	if info.get("ok", false):
		var tex: ImageTexture = info["tex"]
		mat.albedo_texture = tex
		var tint: Color = info.get("color_tint", Color.WHITE)
		mat.albedo_color = tint
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if info["additive"]:
			# Authentic Valve $additive hologram / glow / light-beam material (e.g. cappoint_hologram.mdl!)
			mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		elif info["alpha_test"]:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			mat.alpha_scissor_threshold = 0.42
		elif info["translucent"]:
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if info["no_cull"]:
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Valve TF2 Half-Lambert ambient fill on props so shadowed / night-map props NEVER turn pitch-black!
		if info["self_illum"]:
			mat.emission_enabled = true
			mat.emission_texture = tex
			mat.emission_energy_multiplier = 0.72
		elif is_prop and not info["additive"]:
			mat.emission_enabled = true
			mat.emission_texture = tex
			mat.emission_energy_multiplier = prop_ambient_boost
		if triplanar:
			mat.uv1_triplanar = true
			mat.uv1_world_triplanar = true
			mat.uv1_scale = Vector3(0.25, 0.25, 0.25)
	else:
		mat.albedo_color = Color(0.56, 0.52, 0.48)
		if is_prop:
			mat.emission_enabled = true
			mat.emission = Color(0.18, 0.17, 0.16)

	_mat_cache[key] = mat
	return mat

func has_cached_model(mdl_path: String) -> bool:
	return _mesh_cache.has(mdl_path.to_lower())

func get_model_mesh(mdl_path: String) -> ArrayMesh:
	var key := mdl_path.to_lower()
	if _mesh_cache.has(key):
		return _mesh_cache[key]

	var d: Dictionary = core.read_model_data(mdl_path)
	return build_model_from_raw(mdl_path, d)

func build_model_from_raw(mdl_path: String, d: Dictionary) -> ArrayMesh:
	var key := mdl_path.to_lower()
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	if d == null or not d.get("ok", false):
		_mesh_cache[key] = null
		return null

	var mesh := ArrayMesh.new()
	var surfaces: Array = d["surfaces"]
	for s in surfaces:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s["vertices"]
		arrays[Mesh.ARRAY_NORMAL] = s["normals"]
		arrays[Mesh.ARRAY_TEX_UV] = s["uvs"]
		arrays[Mesh.ARRAY_INDEX]  = s["indices"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var surf_idx := mesh.get_surface_count() - 1
		var mpath: String = s["material"]
		var mat := get_material(mpath, false, true)
		mesh.surface_set_material(surf_idx, mat)

	_mesh_cache[key] = mesh
	_touch_mesh_lru(key)
	return mesh

func spawn_prop(mdl_path: String, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := get_model_mesh(mdl_path)
	var mi := MeshInstance3D.new()
	mi.name = mdl_path.get_file().get_basename()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi

func get_sky(skyname: String, pano_w := 1024, pano_h := 512) -> Sky:
	var key := skyname.to_lower()
	if _sky_cache.has(key):
		return _sky_cache[key]

	var d: Dictionary = core.read_skybox_panorama(skyname, pano_w, pano_h)
	var sky := Sky.new()
	if d.get("ok", false):
		var w := int(d["width"])
		var h := int(d["height"])
		var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, d["rgba"])
		var tex := ImageTexture.create_from_image(img)
		var pmat := PanoramaSkyMaterial.new()
		pmat.panorama = tex
		pmat.filter = true
		sky.sky_material = pmat
	else:
		var fallback := ProceduralSkyMaterial.new()
		sky.sky_material = fallback

	_sky_cache[key] = sky
	return sky
