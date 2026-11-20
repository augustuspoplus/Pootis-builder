#pragma once

#include <string>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include "fgd/Fgd.h"
#include "source/SourceFs.h"

namespace godot {

// Native C++20 TF2 Core bridge exposed to Godot 4 GDScript.
// Wraps pb::source::SourceFs (VPKs, BSP pakfiles, VMT/VTF) and pb::fgd::Fgd
// with zero OpenGL/ImGui/GLFW dependencies.
class Tf2Core : public RefCounted {
    GDCLASS(Tf2Core, RefCounted)

protected:
    static void _bind_methods();

public:
    Tf2Core() = default;
    ~Tf2Core() override = default;

    // Mounts installed Steam TF2 VPKs + optional repo root for ABS Mapping Resource Pack & FGD.
    Dictionary mount_tf2(const String& repo_root = String());

    bool is_ready() const;
    String get_tf2_dir() const;
    int get_fgd_class_count() const;

    PackedStringArray list_maps() const;
    PackedStringArray list_materials(const String& prefix = String(), int limit = 256) const;
    PackedStringArray list_models(const String& prefix = String(), int limit = 256) const;

    // Returns FGD metadata (description, kind, studio_model, color, size, vars) for a TF2 entity class.
    Dictionary get_fgd_class_info(const String& classname) const;

    // Resolves a Source material (.vmt -> $basetexture .vtf) and decodes RGBA8 pixels directly to Godot.
    Dictionary read_material_rgba(const String& material_path) const;

    // Streams a TF2 StudioModel (.mdl/.vvd/.vtx) directly from VPKs into Godot Y-up surface arrays (1m = 32u).
    Dictionary read_model_data(const String& mdl_path);

    // Lists installed Valve TF2 skyboxes found under materials/skybox/.
    PackedStringArray list_skyboxes() const;

    // Decodes all 6 Valve TF2 skybox VTF faces (ft/bk/lf/rt/up/dn) and stitches a crisp
    // equirectangular RGBA8 panorama ready for Godot PanoramaSkyMaterial + real sky IBL lighting!
    Dictionary read_skybox_panorama(const String& skyname, int pano_width = 1024, int pano_height = 512) const;

    // Loads any Valve Source TF2 .bsp map (including Pakfile ZIP textures, displacements,
    // baked VRAD lightmap atlas, LZMA static props pre-grouped for MultiMeshInstance3D,
    // and world collision triangles for instant F5 walk playtesting!).
    Dictionary load_bsp_data(const String& bsp_path);

    // Reads raw WAV/MP3 sound bytes directly from Steam TF2 VPKs (e.g. "sound/ui/buttonclick.wav").
    PackedByteArray read_sound_bytes(const String& vpk_path) const;

private:
    pb::source::SourceFs fs_;
    pb::fgd::Fgd fgd_;
    std::string tf2_dir_;
    bool mounted_ = false;
};

}  // namespace godot
