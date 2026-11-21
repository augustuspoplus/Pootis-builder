#pragma once

#include <string>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include "map/History.h"
#include "map/MapDocument.h"

namespace godot {

// Native C++20 CSG Brush, Displacement Terrain, Entity & VMF Document Engine for Godot 4.
// All Godot-facing positions/dimensions are in Godot Y-up meters (1.0m = 32 Hammer units)
// and mapped cleanly to integer-snapped Source Z-up Hammer planes internally so every
// saved .vmf compiles cleanly with Valve's vbsp.exe!
class Tf2MapDoc : public RefCounted {
    GDCLASS(Tf2MapDoc, RefCounted)

protected:
    static void _bind_methods();

public:
    Tf2MapDoc() = default;
    ~Tf2MapDoc() override = default;

    // Document lifecycle
    void new_map(const String& map_name = "untitled", const String& skyname = "sky_badlands_01");
    Dictionary load_vmf(const String& path);
    Dictionary save_vmf(const String& path);
    String get_map_name() const;
    String get_skyname() const;
    void set_skyname(const String& sky);
    bool is_dirty() const;
    void clear_dirty();
    void set_grid_units(int units);
    int get_grid_units() const;

    // Undo / Redo
    void record_undo(const String& label = "Edit");
    bool undo();
    bool redo();
    bool can_undo() const;
    bool can_redo() const;
    String get_undo_label() const;
    String get_redo_label() const;

    // CSG Solid creation (Godot Y-up meters, 1m = 32u)
    int add_box(const Vector3& min_g, const Vector3& max_g, const String& material);
    int add_ramp(const Vector3& min_g, const Vector3& max_g, int dir_idx, const String& material);
    PackedInt32Array add_stairs(const Vector3& min_g, const Vector3& max_g, int dir_idx, int steps, const String& material);
    PackedInt32Array add_room(const Vector3& min_g, const Vector3& max_g, float wall_thick_m,
                              const String& floor_mat, const String& wall_mat, const String& roof_mat,
                              bool open_top = false);
    PackedInt32Array add_building(const Vector3& min_g, const Vector3& max_g, int floors, int roof_style,
                                  const String& wall_mat, const String& floor_mat, const String& roof_mat,
                                  int door_side = 2);
    PackedInt32Array add_arch(const Vector3& center_g, float width_m, float depth_m, float height_m,
                              int segments, const String& material);
    int add_wall_segment(const Vector3& p0_g, const Vector3& p1_g, float height_m, float thick_m,
                         const String& material);
    PackedInt32Array make_hollow(int solid_idx, float wall_thick_m);
    PackedVector3Array get_solid_vertices(int solid_idx) const;
    bool move_solid_vertex(int solid_idx, int vert_idx, const Vector3& delta_g);
    bool move_solid_vertex_at(int solid_idx, const Vector3& old_pos_g, const Vector3& delta_g);

    // Hammer Face Edit UV & Material Tools (Shift+A)
    Dictionary get_face_uv(int solid_idx, int face_idx) const;
    bool set_face_uv(int solid_idx, int face_idx, float u_scale, float v_scale,
                     float u_shift, float v_shift, float rot_deg, float lightmap_scale);
    bool justify_face_uv(int solid_idx, int face_idx, int mode);
    bool align_face_uv(int solid_idx, int face_idx, bool to_face);
    int replace_material(const String& find_mat, const String& replace_mat);

    // QuickHide, Groups & Check Map for Problems (Alt+P)
    bool set_solid_hidden(int solid_idx, bool hidden);
    int unhide_all();
    bool set_solid_group(int solid_idx, int group_id);
    Array check_problems() const;

    // CSG Editing
    int auto_carve_opening(const Vector3& min_g, const Vector3& max_g, const String& cut_material);
    bool push_pull_face(int solid_idx, int face_idx, float delta_m);
    bool resize_solid_height(int solid_idx, float delta_m);
    bool resize_solid_footprint(int solid_idx, float delta_m);
    bool slope_solid_top(int solid_idx, int edge_dir, float delta_y_m);
    bool translate_solid(int solid_idx, const Vector3& delta_g);
    bool set_solid_material(int solid_idx, const String& material);
    bool set_face_material(int solid_idx, int face_idx, const String& material);
    bool apply_theme_materials(const String& floor_mat, const String& wall_mat, const String& roof_mat);
    bool delete_solid(int solid_idx);
    int duplicate_solid(int solid_idx, const Vector3& offset_g);
    int mirror_solid_x(int solid_idx, bool rotational_180 = false);
    bool push_pull_normal(int solid_idx, const Vector3& normal_g, float delta_m);
    bool rotate_solid_y(int solid_idx, float deg);
    int clip_solid(int solid_idx, const Vector3& plane_pt_g, const Vector3& plane_normal_g, int keep_mode = 0);
    int tie_solid_to_entity(int solid_idx, const String& classname, const Dictionary& kv);
    PackedInt32Array untie_brush_entity(int ent_idx);
    Dictionary get_entity_mesh_data(int ent_idx) const;
    int duplicate_entity(int ent_idx, const Vector3& offset_g);
    Dictionary raycast_entity(const Vector3& ray_origin_g, const Vector3& ray_dir_g) const;

    // Source Displacement Terrain & Vertical Cliff Walls
    int make_terrain_patch(const Vector3& min_g, const Vector3& max_g, int power, const String& material);
    int make_cliff_wall(const Vector3& p0_g, const Vector3& p1_g, float height_m, float depth_m,
                        int power, const String& material, float noise_amp_m = 0.65f);
    bool create_displacement_on_face(int solid_idx, int face_idx, int power = 3);
    int sculpt_terrain(const Vector3& center_g, float radius_m, float strength_m, int mode = 0);
    int sculpt_terrain_ex(const Vector3& center_g, float radius_m, float strength_m,
                          int mode = 0, int axis_mode = 0);
    int sew_displacements();
    bool subdivide_displacement(int solid_idx);

    // Skybox Seal
    bool auto_seal_skybox();
    bool is_map_sealed() const;

    // Entities & I/O Connections
    int add_point_entity(const String& classname, const Vector3& pos_g, const Dictionary& kv);
    int add_brush_entity(const String& classname, const Vector3& min_g, const Vector3& max_g,
                         const String& material, const Dictionary& kv);
    bool set_entity_kv(int ent_idx, const String& key, const String& val);
    bool set_entity_pos(int ent_idx, const Vector3& pos_g);
    bool add_connection(int src_ent_idx, const String& output_name, const String& target_name,
                        const String& input_name, const String& param = String(), float delay = 0.0f,
                        bool once_only = false);
    bool remove_connection(int src_ent_idx, int conn_idx);
    bool delete_entity(int ent_idx);
    int get_entity_count() const;
    Array get_entities() const;

    // Meshing & Raycasting
    int get_solid_count() const;
    Dictionary get_solid_info(int solid_idx) const;
    Dictionary get_solid_mesh_data(int solid_idx) const;
    Dictionary raycast_face(const Vector3& ray_origin_g, const Vector3& ray_dir_g) const;

    const pb::map::MapDocument& doc() const { return doc_; }

private:
    pb::map::MapDocument doc_;
    pb::map::History history_;
    int grid_units_ = 32;
};

}  // namespace godot
