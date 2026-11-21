class_name Tf2Assets
extends RefCounted

## Live TF2 Asset, Material, Skybox & 3D StudioModel Streaming Manager.
## Supports real VPKs + compressed BSP Pakfiles (STORED/DEFLATE/LZMA),
## WorldVertexTransition dual textures, Valve Half-Lambert prop ambient fill,
## and live VPK material swatch textures for the Material Browser!

var core: Object
var prop_ambient_boost: float = 0.28
var _mat_cache: Dictionary = {}    # key -> StandardMaterial3D
var _info_cache: Dictionary = {}   # key -> Dictionary {tex, tex2, has_blend, alpha_test, translucent, no_cull, self_illum, has_alpha}
var _mesh_cache: Dictionary = {}   # mdl_path -> ArrayMesh
var _sky_cache: Dictionary = {}    # skyname -> Sky

func _init(p_core: Object) -> void:
	core = p_core

func clear_bsp_cache() -> void:
	_mat_cache.clear()
	_info_cache.clear()
	_mesh_cache.clear()

func get_material_info(mat_path: String) -> Dictionary:
	var key := mat_path.to_lower()
	if _info_cache.has(key):
		return _info_cache[key]

	var res := {
		"ok": false, "tex": null, "tex2": null, "has_blend": false,
		"alpha_test": false, "translucent": false, "additive": false, "no_cull": false,
		"self_illum": false, "has_alpha": false, "color_tint": Color.WHITE,
	}
	var d: Dictionary = core.read_material_rgba(mat_path)
	if d.get("ok", false):
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

	_info_cache[key] = res
	return res

func get_material_swatch(mat_path: String) -> Texture2D:
	var info := get_material_info(mat_path)
	return info["tex"] if info.get("ok", false) else null

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

func get_model_mesh(mdl_path: String) -> ArrayMesh:
	var key := mdl_path.to_lower()
	if _mesh_cache.has(key):
		return _mesh_cache[key]

	var d: Dictionary = core.read_model_data(mdl_path)
	if not d.get("ok", false):
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
