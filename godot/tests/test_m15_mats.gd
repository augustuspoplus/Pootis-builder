extends SceneTree

func _init() -> void:
	var core = ClassDB.instantiate("Tf2Core")
	core.mount_tf2("C:/Users/steph/Documents/Git/pootis builder")
	for m in ["cp_degrootkeep_rats", "cp_ambush_event", "pl_upward", "ctf_turbine", "sd_doomsday"]:
		var d: Dictionary = core.load_bsp_data(m)
		var surfs: Array = d["surfaces"]
		var miss := []
		var blend_ok := 0
		for s in surfs:
			var mp: String = str(s["material"])
			var r: Dictionary = core.read_material_rgba(mp)
			if not r.get("ok", false):
				miss.append(mp)
			elif r.get("has_blend", false):
				blend_ok += 1
		print("%-22s | pak=%4d | surfs=%3d | missing_mats=%2d | WVT_blends=%2d" % [
			m, int(d["pak_entries"]), surfs.size(), miss.size(), blend_ok
		])
		for mm in miss.slice(0, 10):
			print("    MISSING: ", mm)
	quit(0)
