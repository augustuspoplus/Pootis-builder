#include "gdext/Tf2MapDoc.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <sstream>
#include <unordered_map>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

#include "map/BrushEdit.h"
#include "map/Raycast.h"

namespace godot {

namespace {
constexpr float kUpm = 32.0f;
constexpr float kInvUpm = 1.0f / 32.0f;

std::string toStd(const String& s) {
    CharString utf8 = s.utf8();
    return std::string(utf8.get_data(), static_cast<size_t>(utf8.length()));
}

String toGodot(const std::string& s) {
    return String::utf8(s.c_str(), static_cast<int64_t>(s.size()));
}

// Godot Y-up meters (X, Y, Z) <-> Source Z-up Hammer units (X, -Z, Y) * 32
glm::vec3 toSourcePos(const Vector3& g) {
    return glm::vec3(g.x * kUpm, -g.z * kUpm, g.y * kUpm);
}
glm::vec3 toSourceDir(const Vector3& g) {
    return glm::vec3(g.x, -g.z, g.y);
}
Vector3 toGodotPos(const glm::vec3& s) {
    return Vector3(s.x * kInvUpm, s.z * kInvUpm, -s.y * kInvUpm);
}
Vector3 toGodotDir(const glm::vec3& s) {
    return Vector3(s.x, s.z, -s.y);
}

void sourceBoxFromGodot(const Vector3& min_g, const Vector3& max_g, glm::vec3& mn, glm::vec3& mx) {
    const glm::vec3 a = toSourcePos(min_g);
    const glm::vec3 b = toSourcePos(max_g);
    mn = glm::min(a, b);
    mx = glm::max(a, b);
    // Round cleanly to integer Hammer units so vbsp never hits micro-sliver plane leaks
    mn = glm::round(mn);
    mx = glm::round(mx);
    if (mx.x - mn.x < 4.0f) mx.x = mn.x + 8.0f;
    if (mx.y - mn.y < 4.0f) mx.y = mn.y + 8.0f;
    if (mx.z - mn.z < 4.0f) mx.z = mn.z + 8.0f;
}

bool isSkyboxSolid(const pb::map::Solid& s) {
    for (const auto& f : s.faces) {
        if (f.material.find("toolsskybox") != std::string::npos) return true;
    }
    return false;
}

bool readDispRows(const pb::map::KvNode* node, int gn, int comps, std::vector<float>& out) {
    if (!node) return false;
    out.assign(static_cast<size_t>(gn) * gn * comps, 0.0f);
    for (int r = 0; r < gn; ++r) {
        char key[16];
        std::snprintf(key, sizeof(key), "row%d", r);
        const std::string val = node->get(key);
        if (val.empty()) return false;
        std::istringstream is(val);
        for (int c = 0; c < gn * comps; ++c) {
            if (!(is >> out[(static_cast<size_t>(r) * gn) * comps + c])) return false;
        }
    }
    return true;
}

void dispCornersLocal(const pb::map::BrushFace& f, const glm::vec3& start,
                      glm::vec3& A, glm::vec3& B, glm::vec3& C, glm::vec3& D) {
    int best = 0;
    float bestD = 1e30f;
    for (int i = 0; i < 4; ++i) {
        const glm::vec3 d = f.verts[i] - start;
        const float dd = glm::dot(d, d);
        if (dd < bestD) { bestD = dd; best = i; }
    }
    A = f.verts[best];
    B = f.verts[(best + 1) & 3];
    C = f.verts[(best + 2) & 3];
    D = f.verts[(best + 3) & 3];
}

void writeDispRows(pb::map::KvNode& node, int gn, int comps, const std::vector<float>& vals) {
    for (int r = 0; r < gn; ++r) {
        std::ostringstream os;
        for (int c = 0; c < gn * comps; ++c) {
            if (c) os << ' ';
            os << vals[(static_cast<size_t>(r) * gn) * comps + c];
        }
        char key[16];
        std::snprintf(key, sizeof(key), "row%d", r);
        node.set(key, os.str());
    }
}

bool meshSolidToDict(const pb::map::Solid& s, Dictionary& out) {
    out["ok"] = false;
    if (!s.valid || s.hidden) return false;

    struct Bucket {
        PackedVector3Array verts;
        PackedVector3Array norms;
        PackedVector2Array uvs;
        PackedColorArray colors;
        PackedInt32Array inds;
    };
    std::unordered_map<std::string, Bucket> buckets;
    PackedVector3Array colFaces;

    // Check if this solid is a displacement brush (in Source, only disp faces render)
    bool hasAnyDisp = false;
    for (const auto& f : s.faces)
        if (f.hasDisp) hasAnyDisp = true;

    for (const auto& f : s.faces) {
        if (f.verts.size() < 3) continue;
        if (hasAnyDisp && !f.hasDisp) continue;
        if (f.material.find("toolsskybox") != std::string::npos ||
            f.material.find("toolsnodraw") != std::string::npos)
            continue;

        Bucket& bk = buckets[f.material];

        if (f.hasDisp && f.verts.size() == 4) {
            const int power = f.dispInfo.getInt("power");
            const int gn = (power >= 2 && power <= 4) ? ((1 << power) + 1) : 0;
            std::vector<float> nrm, dst, alp;
            if (gn > 0 && readDispRows(f.dispInfo.child("normals"), gn, 3, nrm) &&
                readDispRows(f.dispInfo.child("distances"), gn, 1, dst)) {
                const bool hasAlp = readDispRows(f.dispInfo.child("alphas"), gn, 1, alp);
                glm::vec3 start(0.0f);
                std::sscanf(f.dispInfo.get("startposition").c_str(), " [ %f %f %f ]",
                            &start.x, &start.y, &start.z);
                glm::vec3 A, B, C, D;
                dispCornersLocal(f, start, A, B, C, D);

                std::vector<glm::vec3> grid(static_cast<size_t>(gn) * gn);
                for (int r = 0; r < gn; ++r) {
                    const float tb = static_cast<float>(r) / (gn - 1);
                    const glm::vec3 e0 = A + (D - A) * tb;
                    const glm::vec3 e1 = B + (C - B) * tb;
                    for (int c = 0; c < gn; ++c) {
                        const int i = r * gn + c;
                        const float ta = static_cast<float>(c) / (gn - 1);
                        const glm::vec3 base = e0 + (e1 - e0) * ta;
                        const glm::vec3 nv(nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2]);
                        grid[i] = base + nv * dst[i];
                    }
                }
                // Compute smooth normals across the displacement grid + alpha blend in COLOR.a
                const int32_t baseV = static_cast<int32_t>(bk.verts.size());
                for (int r = 0; r < gn; ++r) {
                    for (int c = 0; c < gn; ++c) {
                        const int i = r * gn + c;
                        const glm::vec3& p = grid[i];
                        const glm::vec3 du = grid[r * gn + std::min(c + 1, gn - 1)] -
                                             grid[r * gn + std::max(c - 1, 0)];
                        const glm::vec3 dv = grid[std::min(r + 1, gn - 1) * gn + c] -
                                             grid[std::max(r - 1, 0) * gn + c];
                        glm::vec3 gnrm = glm::cross(du, dv);
                        if (glm::length(gnrm) < 1e-4f) gnrm = f.planeN;
                        else gnrm = glm::normalize(gnrm);
                        if (glm::dot(gnrm, f.planeN) < 0.0f) gnrm = -gnrm;
                        bk.verts.push_back(toGodotPos(p));
                        bk.norms.push_back(toGodotDir(gnrm));
                        const glm::vec2 uv = f.texUV(p, 512.0f, 512.0f);
                        bk.uvs.push_back(Vector2(uv.x, uv.y));
                        const float aVal = hasAlp ? std::clamp(alp[i] / 255.0f, 0.0f, 1.0f) : 0.0f;
                        bk.colors.push_back(Color(1.0f, 1.0f, 1.0f, aVal));
                    }
                }
                for (int r = 0; r < gn - 1; ++r) {
                    for (int c = 0; c < gn - 1; ++c) {
                        const int32_t i00 = baseV + r * gn + c;
                        const int32_t i10 = baseV + r * gn + (c + 1);
                        const int32_t i11 = baseV + (r + 1) * gn + (c + 1);
                        const int32_t i01 = baseV + (r + 1) * gn + c;
                        // Ensure outward Godot CW winding aligned with face normal
                        const Vector3 gN = toGodotDir(f.planeN);
                        const Vector3 v00 = bk.verts[i00], v10 = bk.verts[i10],
                                      v11 = bk.verts[i11], v01 = bk.verts[i01];
                        const Vector3 triN = (v10 - v00).cross(v11 - v00);
                        // In Godot CW winding, (v2-v0).cross(v1-v0) points outward -> triN points inward
                        if (triN.dot(gN) < 0.0f) {
                            bk.inds.push_back(i00); bk.inds.push_back(i10); bk.inds.push_back(i11);
                            bk.inds.push_back(i00); bk.inds.push_back(i11); bk.inds.push_back(i01);
                            colFaces.push_back(v00); colFaces.push_back(v10); colFaces.push_back(v11);
                            colFaces.push_back(v00); colFaces.push_back(v11); colFaces.push_back(v01);
                        } else {
                            bk.inds.push_back(i00); bk.inds.push_back(i11); bk.inds.push_back(i10);
                            bk.inds.push_back(i00); bk.inds.push_back(i01); bk.inds.push_back(i11);
                            colFaces.push_back(v00); colFaces.push_back(v11); colFaces.push_back(v10);
                            colFaces.push_back(v00); colFaces.push_back(v01); colFaces.push_back(v11);
                        }
                    }
                }
                continue;
            }
        }

        // Standard planar brush face: Solid::polygonise() emits CCW around outward normal.
        // Swap fan to (0, k+1, k) for Godot CW outward front-face winding!
        const int32_t baseV = static_cast<int32_t>(bk.verts.size());
        const Vector3 gN = toGodotDir(f.planeN);
        for (const auto& vp : f.verts) {
            bk.verts.push_back(toGodotPos(vp));
            bk.norms.push_back(gN);
            const glm::vec2 uv = f.texUV(vp, 512.0f, 512.0f);
            bk.uvs.push_back(Vector2(uv.x, uv.y));
            bk.colors.push_back(Color(1.0f, 1.0f, 1.0f, 0.0f));
        }
        const int32_t n = static_cast<int32_t>(f.verts.size());
        for (int32_t k = 1; k + 1 < n; ++k) {
            const int32_t i0 = baseV;
            const int32_t i1 = baseV + k + 1;
            const int32_t i2 = baseV + k;
            bk.inds.push_back(i0);
            bk.inds.push_back(i1);
            bk.inds.push_back(i2);
            colFaces.push_back(bk.verts[i0]);
            colFaces.push_back(bk.verts[i1]);
            colFaces.push_back(bk.verts[i2]);
        }
    }

    Array surfaces;
    for (auto& [mat, bk] : buckets) {
        if (bk.inds.is_empty()) continue;
        Dictionary sd;
        sd["material"] = toGodot(mat);
        sd["vertices"] = bk.verts;
        sd["normals"] = bk.norms;
        sd["uvs"] = bk.uvs;
        sd["colors"] = bk.colors;
        sd["indices"] = bk.inds;
        surfaces.push_back(sd);
    }

    out["ok"] = !surfaces.is_empty();
    out["surfaces"] = surfaces;
    out["collision_faces"] = colFaces;
    out["is_disp"] = hasAnyDisp;
    return !surfaces.is_empty();
}

}  // namespace

void Tf2MapDoc::_bind_methods() {
    ClassDB::bind_method(D_METHOD("new_map", "map_name", "skyname"),
                         &Tf2MapDoc::new_map, DEFVAL("untitled"), DEFVAL("sky_badlands_01"));
    ClassDB::bind_method(D_METHOD("load_vmf", "path"), &Tf2MapDoc::load_vmf);
    ClassDB::bind_method(D_METHOD("save_vmf", "path"), &Tf2MapDoc::save_vmf);
    ClassDB::bind_method(D_METHOD("get_map_name"), &Tf2MapDoc::get_map_name);
    ClassDB::bind_method(D_METHOD("get_skyname"), &Tf2MapDoc::get_skyname);
    ClassDB::bind_method(D_METHOD("set_skyname", "sky"), &Tf2MapDoc::set_skyname);
    ClassDB::bind_method(D_METHOD("set_grid_units", "units"), &Tf2MapDoc::set_grid_units);
    ClassDB::bind_method(D_METHOD("get_grid_units"), &Tf2MapDoc::get_grid_units);

    ClassDB::bind_method(D_METHOD("record_undo", "label"), &Tf2MapDoc::record_undo, DEFVAL("Edit"));
    ClassDB::bind_method(D_METHOD("undo"), &Tf2MapDoc::undo);
    ClassDB::bind_method(D_METHOD("redo"), &Tf2MapDoc::redo);
    ClassDB::bind_method(D_METHOD("can_undo"), &Tf2MapDoc::can_undo);
    ClassDB::bind_method(D_METHOD("can_redo"), &Tf2MapDoc::can_redo);
    ClassDB::bind_method(D_METHOD("get_undo_label"), &Tf2MapDoc::get_undo_label);
    ClassDB::bind_method(D_METHOD("get_redo_label"), &Tf2MapDoc::get_redo_label);

    ClassDB::bind_method(D_METHOD("add_box", "min_g", "max_g", "material"), &Tf2MapDoc::add_box);
    ClassDB::bind_method(D_METHOD("add_ramp", "min_g", "max_g", "dir_idx", "material"), &Tf2MapDoc::add_ramp);
    ClassDB::bind_method(D_METHOD("add_stairs", "min_g", "max_g", "dir_idx", "steps", "material"), &Tf2MapDoc::add_stairs);
    ClassDB::bind_method(D_METHOD("add_room", "min_g", "max_g", "wall_thick_m", "floor_mat", "wall_mat", "roof_mat", "open_top"),
                         &Tf2MapDoc::add_room, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("add_building", "min_g", "max_g", "floors", "roof_style", "wall_mat", "floor_mat", "roof_mat", "door_side"),
                         &Tf2MapDoc::add_building, DEFVAL(2));
    ClassDB::bind_method(D_METHOD("add_arch", "center_g", "width_m", "depth_m", "height_m", "segments", "material"), &Tf2MapDoc::add_arch);
    ClassDB::bind_method(D_METHOD("add_wall_segment", "p0_g", "p1_g", "height_m", "thick_m", "material"), &Tf2MapDoc::add_wall_segment);
    ClassDB::bind_method(D_METHOD("make_hollow", "solid_idx", "wall_thick_m"), &Tf2MapDoc::make_hollow);
    ClassDB::bind_method(D_METHOD("get_solid_vertices", "solid_idx"), &Tf2MapDoc::get_solid_vertices);
    ClassDB::bind_method(D_METHOD("move_solid_vertex", "solid_idx", "vert_idx", "delta_g"), &Tf2MapDoc::move_solid_vertex);
    ClassDB::bind_method(D_METHOD("get_face_uv", "solid_idx", "face_idx"), &Tf2MapDoc::get_face_uv);
    ClassDB::bind_method(D_METHOD("set_face_uv", "solid_idx", "face_idx", "u_scale", "v_scale", "u_shift", "v_shift", "rot_deg", "lightmap_scale"),
                         &Tf2MapDoc::set_face_uv);
    ClassDB::bind_method(D_METHOD("justify_face_uv", "solid_idx", "face_idx", "mode"), &Tf2MapDoc::justify_face_uv);
    ClassDB::bind_method(D_METHOD("align_face_uv", "solid_idx", "face_idx", "to_face"), &Tf2MapDoc::align_face_uv);
    ClassDB::bind_method(D_METHOD("replace_material", "find_mat", "replace_mat"), &Tf2MapDoc::replace_material);
    ClassDB::bind_method(D_METHOD("set_solid_hidden", "solid_idx", "hidden"), &Tf2MapDoc::set_solid_hidden);
    ClassDB::bind_method(D_METHOD("unhide_all"), &Tf2MapDoc::unhide_all);
    ClassDB::bind_method(D_METHOD("set_solid_group", "solid_idx", "group_id"), &Tf2MapDoc::set_solid_group);
    ClassDB::bind_method(D_METHOD("check_problems"), &Tf2MapDoc::check_problems);

    ClassDB::bind_method(D_METHOD("auto_carve_opening", "min_g", "max_g", "cut_material"), &Tf2MapDoc::auto_carve_opening);
    ClassDB::bind_method(D_METHOD("push_pull_face", "solid_idx", "face_idx", "delta_m"), &Tf2MapDoc::push_pull_face);
    ClassDB::bind_method(D_METHOD("resize_solid_height", "solid_idx", "delta_m"), &Tf2MapDoc::resize_solid_height);
    ClassDB::bind_method(D_METHOD("resize_solid_footprint", "solid_idx", "delta_m"), &Tf2MapDoc::resize_solid_footprint);
    ClassDB::bind_method(D_METHOD("slope_solid_top", "solid_idx", "edge_dir", "delta_y_m"), &Tf2MapDoc::slope_solid_top);
    ClassDB::bind_method(D_METHOD("translate_solid", "solid_idx", "delta_g"), &Tf2MapDoc::translate_solid);
    ClassDB::bind_method(D_METHOD("set_solid_material", "solid_idx", "material"), &Tf2MapDoc::set_solid_material);
    ClassDB::bind_method(D_METHOD("set_face_material", "solid_idx", "face_idx", "material"), &Tf2MapDoc::set_face_material);
    ClassDB::bind_method(D_METHOD("apply_theme_materials", "floor_mat", "wall_mat", "roof_mat"), &Tf2MapDoc::apply_theme_materials);
    ClassDB::bind_method(D_METHOD("delete_solid", "solid_idx"), &Tf2MapDoc::delete_solid);
    ClassDB::bind_method(D_METHOD("duplicate_solid", "solid_idx", "offset_g"), &Tf2MapDoc::duplicate_solid);
    ClassDB::bind_method(D_METHOD("mirror_solid_x", "solid_idx", "rotational_180"),
                         &Tf2MapDoc::mirror_solid_x, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("push_pull_normal", "solid_idx", "normal_g", "delta_m"), &Tf2MapDoc::push_pull_normal);
    ClassDB::bind_method(D_METHOD("rotate_solid_y", "solid_idx", "deg"), &Tf2MapDoc::rotate_solid_y);
    ClassDB::bind_method(D_METHOD("clip_solid", "solid_idx", "plane_pt_g", "plane_normal_g", "keep_mode"),
                         &Tf2MapDoc::clip_solid, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("tie_solid_to_entity", "solid_idx", "classname", "kv"), &Tf2MapDoc::tie_solid_to_entity);
    ClassDB::bind_method(D_METHOD("duplicate_entity", "ent_idx", "offset_g"), &Tf2MapDoc::duplicate_entity);
    ClassDB::bind_method(D_METHOD("raycast_entity", "ray_origin_g", "ray_dir_g"), &Tf2MapDoc::raycast_entity);

    ClassDB::bind_method(D_METHOD("make_terrain_patch", "min_g", "max_g", "power", "material"), &Tf2MapDoc::make_terrain_patch);
    ClassDB::bind_method(D_METHOD("make_cliff_wall", "p0_g", "p1_g", "height_m", "depth_m", "power", "material", "noise_amp_m"),
                         &Tf2MapDoc::make_cliff_wall, DEFVAL(0.65f));
    ClassDB::bind_method(D_METHOD("create_displacement_on_face", "solid_idx", "face_idx", "power"),
                         &Tf2MapDoc::create_displacement_on_face, DEFVAL(3));
    ClassDB::bind_method(D_METHOD("sculpt_terrain", "center_g", "radius_m", "strength_m", "mode"),
                         &Tf2MapDoc::sculpt_terrain, DEFVAL(0));
    ClassDB::bind_method(D_METHOD("sculpt_terrain_ex", "center_g", "radius_m", "strength_m", "mode", "axis_mode"),
                         &Tf2MapDoc::sculpt_terrain_ex, DEFVAL(0), DEFVAL(0));
    ClassDB::bind_method(D_METHOD("sew_displacements"), &Tf2MapDoc::sew_displacements);
    ClassDB::bind_method(D_METHOD("subdivide_displacement", "solid_idx"), &Tf2MapDoc::subdivide_displacement);

    ClassDB::bind_method(D_METHOD("auto_seal_skybox"), &Tf2MapDoc::auto_seal_skybox);
    ClassDB::bind_method(D_METHOD("is_map_sealed"), &Tf2MapDoc::is_map_sealed);

    ClassDB::bind_method(D_METHOD("add_point_entity", "classname", "pos_g", "kv"), &Tf2MapDoc::add_point_entity);
    ClassDB::bind_method(D_METHOD("add_brush_entity", "classname", "min_g", "max_g", "material", "kv"), &Tf2MapDoc::add_brush_entity);
    ClassDB::bind_method(D_METHOD("set_entity_kv", "ent_idx", "key", "val"), &Tf2MapDoc::set_entity_kv);
    ClassDB::bind_method(D_METHOD("set_entity_pos", "ent_idx", "pos_g"), &Tf2MapDoc::set_entity_pos);
    ClassDB::bind_method(D_METHOD("add_connection", "src_ent_idx", "output_name", "target_name", "input_name", "param", "delay"),
                         &Tf2MapDoc::add_connection, DEFVAL(String()), DEFVAL(0.0f));
    ClassDB::bind_method(D_METHOD("delete_entity", "ent_idx"), &Tf2MapDoc::delete_entity);
    ClassDB::bind_method(D_METHOD("get_entity_count"), &Tf2MapDoc::get_entity_count);
    ClassDB::bind_method(D_METHOD("get_entities"), &Tf2MapDoc::get_entities);

    ClassDB::bind_method(D_METHOD("get_solid_count"), &Tf2MapDoc::get_solid_count);
    ClassDB::bind_method(D_METHOD("get_solid_info", "solid_idx"), &Tf2MapDoc::get_solid_info);
    ClassDB::bind_method(D_METHOD("get_solid_mesh_data", "solid_idx"), &Tf2MapDoc::get_solid_mesh_data);
    ClassDB::bind_method(D_METHOD("raycast_face", "ray_origin_g", "ray_dir_g"), &Tf2MapDoc::raycast_face);
}

void Tf2MapDoc::new_map(const String& map_name, const String& skyname) {
    doc_.newBlank(toStd(map_name));
    doc_.worldExtra().set("skyname", toStd(skyname));
    history_.reset(doc_);
}

Dictionary Tf2MapDoc::load_vmf(const String& path) {
    Dictionary out;
    std::string err;
    const bool ok = doc_.loadVmf(toStd(path), &err);
    out["ok"] = ok;
    out["error"] = toGodot(err);
    if (ok) {
        history_.reset(doc_);
        out["solids"] = static_cast<int64_t>(doc_.worldSolids().size());
        out["entities"] = static_cast<int64_t>(doc_.entities().size());
        out["skyname"] = get_skyname();
    }
    return out;
}

Dictionary Tf2MapDoc::save_vmf(const String& path) {
    Dictionary out;
    std::string err;
    const bool ok = doc_.saveVmf(toStd(path), &err, true);
    out["ok"] = ok;
    out["error"] = toGodot(err);
    return out;
}

String Tf2MapDoc::get_map_name() const { return toGodot(doc_.name()); }

String Tf2MapDoc::get_skyname() const {
    const std::string s = const_cast<pb::map::MapDocument&>(doc_).worldExtra().get("skyname");
    return toGodot(s.empty() ? "sky_badlands_01" : s);
}

void Tf2MapDoc::set_skyname(const String& sky) {
    doc_.worldExtra().set("skyname", toStd(sky));
    doc_.markDirty();
}

void Tf2MapDoc::set_grid_units(int units) { grid_units_ = std::clamp(units, 1, 256); }
int Tf2MapDoc::get_grid_units() const { return grid_units_; }

void Tf2MapDoc::record_undo(const String& label) { history_.record(doc_, toStd(label)); }
bool Tf2MapDoc::undo() { return history_.undo(doc_); }
bool Tf2MapDoc::redo() { return history_.redo(doc_); }
bool Tf2MapDoc::can_undo() const { return history_.canUndo(); }
bool Tf2MapDoc::can_redo() const { return history_.canRedo(); }
String Tf2MapDoc::get_undo_label() const { return toGodot(history_.undoLabel()); }
String Tf2MapDoc::get_redo_label() const { return toGodot(history_.redoLabel()); }

int Tf2MapDoc::add_box(const Vector3& min_g, const Vector3& max_g, const String& material) {
    glm::vec3 mn, mx;
    sourceBoxFromGodot(min_g, max_g, mn, mx);
    pb::map::Solid s = pb::map::Solid::makeBox(mn, mx, toStd(material));
    if (!s.valid) return -1;
    s.id = doc_.nextId();
    const int idx = static_cast<int>(doc_.worldSolids().size());
    doc_.worldSolids().push_back(std::move(s));
    doc_.markDirty();
    return idx;
}

int Tf2MapDoc::add_ramp(const Vector3& min_g, const Vector3& max_g, int dir_idx, const String& material) {
    glm::vec3 mn, mx;
    sourceBoxFromGodot(min_g, max_g, mn, mx);
    const std::string mat = toStd(material);
    pb::map::Solid s = pb::map::Solid::makeBox(mn, mx, mat);
    if (!s.valid) return -1;

    // Slice with a diagonal slope plane so the ramp rises toward dir_idx (0:+X 1:-X 2:+Z(Godot=-Y Src) 3:-Z(Godot=+Y Src))
    const float dx = mx.x - mn.x;
    const float dy = mx.y - mn.y;
    const float dz = mx.z - mn.z;
    glm::vec3 n(0.0f);
    glm::vec3 pt = mn;
    switch (dir_idx & 3) {
        case 0: n = glm::normalize(glm::vec3(-dz, 0.0f, dx)); pt = glm::vec3(mn.x, mn.y, mn.z); break;
        case 1: n = glm::normalize(glm::vec3( dz, 0.0f, dx)); pt = glm::vec3(mx.x, mn.y, mn.z); break;
        case 2: n = glm::normalize(glm::vec3(0.0f,  dz, dy)); pt = glm::vec3(mn.x, mx.y, mn.z); break;
        case 3: n = glm::normalize(glm::vec3(0.0f, -dz, dy)); pt = glm::vec3(mn.x, mn.y, mn.z); break;
    }
    const float d = glm::dot(n, pt);
    s.clip(n, d, mat);
    if (!s.valid) return -1;
    s.id = doc_.nextId();
    const int idx = static_cast<int>(doc_.worldSolids().size());
    doc_.worldSolids().push_back(std::move(s));
    doc_.markDirty();
    return idx;
}

PackedInt32Array Tf2MapDoc::add_stairs(const Vector3& min_g, const Vector3& max_g, int dir_idx,
                                       int steps, const String& material) {
    PackedInt32Array out;
    steps = std::clamp(steps, 2, 24);
    const Vector3 lo(std::min(min_g.x, max_g.x), std::min(min_g.y, max_g.y), std::min(min_g.z, max_g.z));
    const Vector3 hi(std::max(min_g.x, max_g.x), std::max(min_g.y, max_g.y), std::max(min_g.z, max_g.z));
    const Vector3 sz = hi - lo;
    for (int i = 0; i < steps; ++i) {
        const float f0 = static_cast<float>(i) / steps;
        const float f1 = static_cast<float>(i + 1) / steps;
        Vector3 a = lo, b = hi;
        b.y = lo.y + sz.y * f1;
        switch (dir_idx & 3) {
            case 0: a.x = lo.x + sz.x * f0; b.x = lo.x + sz.x * f1; break;
            case 1: a.x = hi.x - sz.x * f1; b.x = hi.x - sz.x * f0; break;
            case 2: a.z = lo.z + sz.z * f0; b.z = lo.z + sz.z * f1; break;
            case 3: a.z = hi.z - sz.z * f1; b.z = hi.z - sz.z * f0; break;
        }
        const int idx = add_box(a, b, material);
        if (idx >= 0) out.push_back(idx);
    }
    return out;
}

PackedInt32Array Tf2MapDoc::add_room(const Vector3& min_g, const Vector3& max_g, float wall_thick_m,
                                     const String& floor_mat, const String& wall_mat, const String& roof_mat,
                                     bool open_top) {
    PackedInt32Array out;
    const Vector3 lo(std::min(min_g.x, max_g.x), std::min(min_g.y, max_g.y), std::min(min_g.z, max_g.z));
    const Vector3 hi(std::max(min_g.x, max_g.x), std::max(min_g.y, max_g.y), std::max(min_g.z, max_g.z));
    const float t = std::clamp(wall_thick_m, 0.25f, 2.0f);

    // Floor slab
    out.push_back(add_box(Vector3(lo.x, lo.y - t, lo.z), Vector3(hi.x, lo.y, hi.z), floor_mat));
    // 4 walls
    out.push_back(add_box(Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z + t), wall_mat));
    out.push_back(add_box(Vector3(lo.x, lo.y, hi.z - t), Vector3(hi.x, hi.y, hi.z), wall_mat));
    out.push_back(add_box(Vector3(lo.x, lo.y, lo.z + t), Vector3(lo.x + t, hi.y, hi.z - t), wall_mat));
    out.push_back(add_box(Vector3(hi.x - t, lo.y, lo.z + t), Vector3(hi.x, hi.y, hi.z - t), wall_mat));
    if (!open_top) {
        out.push_back(add_box(Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y + t, hi.z), roof_mat));
    }
    return out;
}

PackedInt32Array Tf2MapDoc::add_building(const Vector3& min_g, const Vector3& max_g, int floors, int roof_style,
                                         const String& wall_mat, const String& floor_mat, const String& roof_mat,
                                         int door_side) {
    PackedInt32Array out;
    floors = std::clamp(floors, 1, 3);
    const Vector3 lo(std::min(min_g.x, max_g.x), std::min(min_g.y, max_g.y), std::min(min_g.z, max_g.z));
    const Vector3 hi(std::max(min_g.x, max_g.x), std::max(min_g.y, max_g.y), std::max(min_g.z, max_g.z));
    const float floor_h = 4.5f;  // 144u TF2 ceiling height per story!
    const float top_y = lo.y + floors * floor_h;
    const float t = 0.5f;        // 16u wall thickness

    // Outer shell
    PackedInt32Array shell = add_room(lo, Vector3(hi.x, top_y, hi.z), t, floor_mat, wall_mat, roof_mat, true);
    for (int i = 0; i < shell.size(); ++i) out.push_back(shell[i]);

    // Upper floor decks + interior stairways
    for (int fl = 1; fl < floors; ++fl) {
        const float fy = lo.y + fl * floor_h;
        // Leave stair opening on the back-left corner
        out.push_back(add_box(Vector3(lo.x + t, fy - 0.5f, lo.z + t),
                              Vector3(hi.x - t, fy, hi.z - t - 3.0f), floor_mat));
        PackedInt32Array st = add_stairs(Vector3(lo.x + t + 0.5f, fy - floor_h, hi.z - t - 3.0f),
                                         Vector3(lo.x + t + 5.5f, fy, hi.z - t - 0.5f), 0, 8, floor_mat);
        for (int i = 0; i < st.size(); ++i) out.push_back(st[i]);
    }

    // Roof style: 0=Flat, 1=Gabled TF2 Barn Roof, 2=Slanted Battlement Roof
    const float mid_x = (lo.x + hi.x) * 0.5f;
    if (roof_style == 1) {
        const float ridge_h = 2.5f;
        out.push_back(add_ramp(Vector3(lo.x - 0.5f, top_y, lo.z - 0.5f),
                               Vector3(mid_x, top_y + ridge_h, hi.z + 0.5f), 0, roof_mat));
        out.push_back(add_ramp(Vector3(mid_x, top_y, lo.z - 0.5f),
                               Vector3(hi.x + 0.5f, top_y + ridge_h, hi.z + 0.5f), 1, roof_mat));
    } else if (roof_style == 2) {
        out.push_back(add_ramp(Vector3(lo.x - 0.5f, top_y, lo.z - 0.5f),
                               Vector3(hi.x + 0.5f, top_y + 2.0f, hi.z + 0.5f), 3, roof_mat));
    } else {
        out.push_back(add_box(Vector3(lo.x - 0.25f, top_y, lo.z - 0.25f),
                              Vector3(hi.x + 0.25f, top_y + 0.5f, hi.z + 0.25f), roof_mat));
    }

    // Auto-carve a generous 112u x 112u (3.5m) TF2 doorway on door_side (strictly above floor)!
    const float mid_z = (lo.z + hi.z) * 0.5f;
    Vector3 dmin, dmax;
    switch (door_side & 3) {
        case 0: dmin = Vector3(hi.x - 1.5f, lo.y, mid_z - 1.75f); dmax = Vector3(hi.x + 1.5f, lo.y + 3.5f, mid_z + 1.75f); break;
        case 1: dmin = Vector3(lo.x - 1.5f, lo.y, mid_z - 1.75f); dmax = Vector3(lo.x + 1.5f, lo.y + 3.5f, mid_z + 1.75f); break;
        case 2: dmin = Vector3(mid_x - 1.75f, lo.y, hi.z - 1.5f); dmax = Vector3(mid_x + 1.75f, lo.y + 3.5f, hi.z + 1.5f); break;
        default: dmin = Vector3(mid_x - 1.75f, lo.y, lo.z - 1.5f); dmax = Vector3(mid_x + 1.75f, lo.y + 3.5f, lo.z + 1.5f); break;
    }
    auto_carve_opening(dmin, dmax, wall_mat);

    // Also auto-carve a classic upper sniper window if multi-story!
    if (floors >= 2) {
        const float wy = lo.y + floor_h + 1.25f;
        auto_carve_opening(Vector3(mid_x - 2.5f, wy, hi.z - 1.5f),
                           Vector3(mid_x + 2.5f, wy + 2.0f, hi.z + 1.5f), wall_mat);
    }
    return out;
}

PackedInt32Array Tf2MapDoc::add_arch(const Vector3& center_g, float width_m, float depth_m,
                                     float height_m, int segments, const String& material) {
    PackedInt32Array out;
    segments = std::clamp(segments, 3, 12);
    const float halfW = width_m * 0.5f;
    const float halfD = depth_m * 0.5f;
    const float legW = std::max(0.5f, width_m * 0.18f);
    const float archBaseY = center_g.y + height_m * 0.55f;
    const float archR = halfW - legW;
    // Left & right pillars
    out.push_back(add_box(Vector3(center_g.x - halfW, center_g.y, center_g.z - halfD),
                          Vector3(center_g.x - halfW + legW, center_g.y + height_m, center_g.z + halfD), material));
    out.push_back(add_box(Vector3(center_g.x + halfW - legW, center_g.y, center_g.z - halfD),
                          Vector3(center_g.x + halfW, center_g.y + height_m, center_g.z + halfD), material));
    // Segmented top arch lintel blocks
    constexpr float kPi = 3.14159265358979323846f;
    for (int i = 0; i < segments; ++i) {
        const float a0 = kPi * static_cast<float>(i) / segments;
        const float a1 = kPi * static_cast<float>(i + 1) / segments;
        const float x0 = center_g.x - std::cos(a0) * archR;
        const float x1 = center_g.x - std::cos(a1) * archR;
        const float yMin = archBaseY + std::min(std::sin(a0), std::sin(a1)) * (height_m * 0.35f);
        out.push_back(add_box(Vector3(std::min(x0, x1), yMin, center_g.z - halfD),
                              Vector3(std::max(x0, x1), center_g.y + height_m, center_g.z + halfD), material));
    }
    return out;
}

int Tf2MapDoc::auto_carve_opening(const Vector3& min_g, const Vector3& max_g, const String& cut_material) {
    glm::vec3 mn, mx;
    sourceBoxFromGodot(min_g, max_g, mn, mx);
    const pb::map::Solid cutter = pb::map::Solid::makeBox(mn, mx, toStd(cut_material));
    if (!cutter.valid) return 0;

    int carved = 0;
    std::vector<pb::map::Solid> nextWorld;
    nextWorld.reserve(doc_.worldSolids().size() + 4);
    for (auto& ws : doc_.worldSolids()) {
        if (!ws.valid || ws.hidden || isSkyboxSolid(ws)) {
            nextWorld.push_back(std::move(ws));
            continue;
        }
        const bool overlaps =
            ws.boundsMax.x > mn.x + 1.0f && ws.boundsMin.x < mx.x - 1.0f &&
            ws.boundsMax.y > mn.y + 1.0f && ws.boundsMin.y < mx.y - 1.0f &&
            ws.boundsMax.z > mn.z + 1.0f && ws.boundsMin.z < mx.z - 1.0f;
        if (!overlaps) {
            nextWorld.push_back(std::move(ws));
            continue;
        }
        std::vector<pb::map::Solid> pieces = pb::map::carve(ws, cutter);
        for (auto& pc : pieces) {
            if (!pc.valid) continue;
            pc.id = doc_.nextId();
            nextWorld.push_back(std::move(pc));
        }
        ++carved;
    }
    if (carved > 0) {
        doc_.worldSolids() = std::move(nextWorld);
        doc_.markDirty();
    }
    return carved;
}

bool Tf2MapDoc::push_pull_face(int solid_idx, int face_idx, float delta_m) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    pb::map::Solid& s = doc_.worldSolids()[solid_idx];
    if (face_idx < 0 || face_idx >= static_cast<int>(s.faces.size())) return false;
    const float deltaU = std::round(delta_m * kUpm);
    if (std::fabs(deltaU) < 0.5f) return false;

    pb::map::Solid backup = s;
    auto& f = s.faces[face_idx];
    f.planeD += deltaU;
    f.planeFromPoints = false;
    s.polygonise();
    if (!s.valid) {
        s = std::move(backup);
        return false;
    }
    doc_.markDirty();
    return true;
}

bool Tf2MapDoc::resize_solid_height(int solid_idx, float delta_m) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    const auto& s = doc_.worldSolids()[solid_idx];
    for (int fi = 0; fi < static_cast<int>(s.faces.size()); ++fi) {
        if (s.faces[fi].planeN.z > 0.7f) return push_pull_face(solid_idx, fi, delta_m);
    }
    return false;
}

bool Tf2MapDoc::resize_solid_footprint(int solid_idx, float delta_m) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    bool changed = false;
    const int n = static_cast<int>(doc_.worldSolids()[solid_idx].faces.size());
    for (int fi = 0; fi < n; ++fi) {
        if (std::fabs(doc_.worldSolids()[solid_idx].faces[fi].planeN.z) < 0.3f) {
            if (push_pull_face(solid_idx, fi, delta_m)) changed = true;
        }
    }
    return changed;
}

bool Tf2MapDoc::slope_solid_top(int solid_idx, int edge_dir, float delta_y_m) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    pb::map::Solid& s = doc_.worldSolids()[solid_idx];
    const pb::map::BrushHandles h = pb::map::extractHandles(s);
    const glm::vec3 ctr = s.center();
    std::vector<int> picked;
    for (int i = 0; i < static_cast<int>(h.verts.size()); ++i) {
        const glm::vec3& p = h.verts[i].pos;
        if (p.z < ctr.z) continue;  // top corners only
        const bool match = (edge_dir == 0 && p.x > ctr.x) ||
                           (edge_dir == 1 && p.x < ctr.x) ||
                           (edge_dir == 2 && p.y < ctr.y) ||
                           (edge_dir == 3 && p.y > ctr.y);
        if (match) picked.push_back(i);
    }
    if (picked.empty()) return false;
    pb::map::Solid backup = s;
    if (!pb::map::moveVertexHandles(s, h, picked, glm::vec3(0.0f, 0.0f, delta_y_m * kUpm))) {
        s = std::move(backup);
        return false;
    }
    doc_.markDirty();
    return true;
}

bool Tf2MapDoc::translate_solid(int solid_idx, const Vector3& delta_g) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    doc_.worldSolids()[solid_idx].translate(glm::round(toSourcePos(delta_g)));
    doc_.markDirty();
    return true;
}

bool Tf2MapDoc::set_solid_material(int solid_idx, const String& material) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    const std::string mat = toStd(material);
    for (auto& f : doc_.worldSolids()[solid_idx].faces) f.material = mat;
    doc_.markDirty();
    return true;
}

bool Tf2MapDoc::set_face_material(int solid_idx, int face_idx, const String& material) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    auto& s = doc_.worldSolids()[solid_idx];
    if (face_idx < 0 || face_idx >= static_cast<int>(s.faces.size())) return false;
    s.faces[face_idx].material = toStd(material);
    doc_.markDirty();
    return true;
}

bool Tf2MapDoc::apply_theme_materials(const String& floor_mat, const String& wall_mat, const String& roof_mat) {
    const std::string fm = toStd(floor_mat);
    const std::string wm = toStd(wall_mat);
    const std::string rm = toStd(roof_mat);
    for (auto& s : doc_.worldSolids()) {
        if (!s.valid || isSkyboxSolid(s)) continue;
        const glm::vec3 sz = s.boundsMax - s.boundsMin;
        const bool isFloor = (sz.z <= 40.0f && s.boundsMax.z <= 16.0f);
        for (auto& f : s.faces) {
            if (f.material.rfind("tools/", 0) == 0) continue;
            if (f.planeN.z > 0.7f) f.material = isFloor ? fm : rm;
            else if (f.planeN.z < -0.7f) f.material = fm;
            else f.material = wm;
        }
    }
    doc_.markDirty();
    return true;
}

bool Tf2MapDoc::delete_solid(int solid_idx) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    doc_.worldSolids().erase(doc_.worldSolids().begin() + solid_idx);
    doc_.markDirty();
    return true;
}

int Tf2MapDoc::duplicate_solid(int solid_idx, const Vector3& offset_g) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return -1;
    pb::map::Solid copy = doc_.worldSolids()[solid_idx];
    copy.id = doc_.nextId();
    copy.translate(glm::round(toSourcePos(offset_g)));
    const int idx = static_cast<int>(doc_.worldSolids().size());
    doc_.worldSolids().push_back(std::move(copy));
    doc_.markDirty();
    return idx;
}

int Tf2MapDoc::mirror_solid_x(int solid_idx, bool rotational_180) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return -1;
    const pb::map::Solid& src = doc_.worldSolids()[solid_idx];
    // Transform every plane cleanly (Mirror across X=0 or Rotate 180 deg around Z!)
    std::vector<std::pair<glm::vec3, float>> planes;
    planes.reserve(src.faces.size());
    for (const auto& f : src.faces) {
        glm::vec3 n = f.planeN;
        if (rotational_180) { n.x = -n.x; n.y = -n.y; }
        else { n.x = -n.x; }
        planes.push_back({n, f.planeD});
    }
    const std::string mat = src.faces.empty() ? "concrete/concretefloor002" : src.faces[0].material;
    pb::map::Solid dst = pb::map::Solid::fromPlanes(planes, mat);
    if (!dst.valid) return -1;
    for (size_t i = 0; i < dst.faces.size() && i < src.faces.size(); ++i) {
        dst.faces[i].material = src.faces[i].material;
    }
    dst.id = doc_.nextId();
    const int idx = static_cast<int>(doc_.worldSolids().size());
    doc_.worldSolids().push_back(std::move(dst));
    doc_.markDirty();
    return idx;
}

int Tf2MapDoc::make_terrain_patch(const Vector3& min_g, const Vector3& max_g, int power, const String& material) {
    const int idx = add_box(min_g, max_g, material);
    if (idx < 0) return -1;
    auto& s = doc_.worldSolids()[idx];
    power = std::clamp(power, 2, 4);
    for (auto& f : s.faces) {
        if (f.planeN.z > 0.7f && f.verts.size() == 4) {
            pb::map::faceMakeDisplacement(f, power);
            break;
        }
    }
    doc_.markDirty();
    return idx;
}

int Tf2MapDoc::sculpt_terrain(const Vector3& center_g, float radius_m, float strength_m, int mode) {
    const glm::vec3 centerU = toSourcePos(center_g);
    const float radU = std::max(16.0f, radius_m * kUpm);
    const float amtU = strength_m * kUpm;
    int touched = 0;

    for (auto& s : doc_.worldSolids()) {
        for (auto& f : s.faces) {
            if (!f.hasDisp || f.verts.size() != 4) continue;
            if (mode == 0) {
                if (pb::map::faceSculptDisplacement(f, centerU, radU, std::fabs(amtU))) ++touched;
            } else if (mode == 1) {
                if (pb::map::faceSculptDisplacement(f, centerU, radU, -std::fabs(amtU))) ++touched;
            } else {
                // Smooth (mode 2) or Flatten toward target height (mode 3)
                const int power = f.dispInfo.getInt("power");
                if (power < 2 || power > 4) continue;
                const int gn = (1 << power) + 1;
                std::vector<float> nrm, dst;
                if (!readDispRows(f.dispInfo.child("normals"), gn, 3, nrm) ||
                    !readDispRows(f.dispInfo.child("distances"), gn, 1, dst))
                    continue;
                glm::vec3 start(0.0f);
                std::sscanf(f.dispInfo.get("startposition").c_str(), " [ %f %f %f ]",
                            &start.x, &start.y, &start.z);
                glm::vec3 A, B, C, D;
                dispCornersLocal(f, start, A, B, C, D);
                std::vector<float> nextDst = dst;
                bool any = false;
                const float r2 = radU * radU;
                for (int r = 0; r < gn; ++r) {
                    const float tb = static_cast<float>(r) / (gn - 1);
                    const glm::vec3 e0 = A + (D - A) * tb;
                    const glm::vec3 e1 = B + (C - B) * tb;
                    for (int c = 0; c < gn; ++c) {
                        const int i = r * gn + c;
                        const float ta = static_cast<float>(c) / (gn - 1);
                        const glm::vec3 base = e0 + (e1 - e0) * ta;
                        const glm::vec3 nv(nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2]);
                        const glm::vec3 cur = base + nv * dst[i];
                        const float d2 = glm::dot(cur - centerU, cur - centerU);
                        if (d2 > r2) continue;
                        const float fall = 1.0f - std::sqrt(d2) / radU;
                        if (mode == 2) {
                            float sum = 0.0f; int cnt = 0;
                            for (int dr = -1; dr <= 1; ++dr)
                                for (int dc = -1; dc <= 1; ++dc) {
                                    int rr = r + dr, cc = c + dc;
                                    if (rr >= 0 && rr < gn && cc >= 0 && cc < gn) {
                                        sum += dst[rr * gn + cc]; ++cnt;
                                    }
                                }
                            nextDst[i] = dst[i] + ((sum / cnt) - dst[i]) * fall * 0.65f;
                        } else {
                            const float targetD = centerU.z - base.z;
                            nextDst[i] = dst[i] + (targetD - dst[i]) * fall * 0.75f;
                        }
                        any = true;
                    }
                }
                if (any) {
                    for (auto& ch : f.dispInfo.children) {
                        if (ch.name == "distances") {
                            writeDispRows(ch, gn, 1, nextDst);
                            ++touched;
                            break;
                        }
                    }
                }
            }
        }
    }
    if (touched > 0) doc_.markDirty();
    return touched;
}

bool Tf2MapDoc::auto_seal_skybox() {
    // Remove any existing skybox shell brushes first so re-sealing stays clean & tight
    auto& ws = doc_.worldSolids();
    ws.erase(std::remove_if(ws.begin(), ws.end(),
                            [](const pb::map::Solid& s) { return isSkyboxSolid(s); }),
             ws.end());

    glm::vec3 mn(1e30f), mx(-1e30f);
    for (const auto& s : ws) {
        if (!s.valid) continue;
        mn = glm::min(mn, s.boundsMin);
        mx = glm::max(mx, s.boundsMax);
    }
    for (const auto& e : doc_.entities()) {
        mn = glm::min(mn, e.origin - glm::vec3(64.0f));
        mx = glm::max(mx, e.origin + glm::vec3(64.0f, 64.0f, 128.0f));
    }
    if (mn.x > mx.x) {
        mn = glm::vec3(-1024, -1024, -64);
        mx = glm::vec3(1024, 1024, 512);
    }
    const glm::vec3 smin = glm::floor(mn - glm::vec3(128.0f, 128.0f, 96.0f));
    const glm::vec3 smax = glm::ceil(mx + glm::vec3(128.0f, 128.0f, 384.0f));
    const float th = 32.0f;
    const std::string sky = "tools/toolsskybox";

    auto pushSky = [&](glm::vec3 a, glm::vec3 b) {
        pb::map::Solid s = pb::map::Solid::makeBox(a, b, sky);
        if (s.valid) {
            s.id = doc_.nextId();
            ws.push_back(std::move(s));
        }
    };
    pushSky({smin.x, smin.y, smin.z - th}, {smax.x, smax.y, smin.z});
    pushSky({smin.x, smin.y, smax.z},      {smax.x, smax.y, smax.z + th});
    pushSky({smin.x - th, smin.y, smin.z}, {smin.x, smax.y, smax.z});
    pushSky({smax.x, smin.y, smin.z},      {smax.x + th, smax.y, smax.z});
    pushSky({smin.x, smin.y - th, smin.z}, {smax.x, smin.y, smax.z});
    pushSky({smin.x, smax.y, smin.z},      {smax.x, smax.y + th, smax.z});
    doc_.markDirty();
    return true;
}

bool Tf2MapDoc::is_map_sealed() const {
    int skyCount = 0;
    for (const auto& s : doc_.worldSolids()) {
        if (s.valid && isSkyboxSolid(s)) ++skyCount;
    }
    return skyCount >= 6;
}

int Tf2MapDoc::add_point_entity(const String& classname, const Vector3& pos_g, const Dictionary& kv) {
    pb::map::MapEntity e;
    e.id = doc_.nextId();
    e.classname = toStd(classname);
    e.origin = glm::round(toSourcePos(pos_g));
    e.kv.name = "entity";
    e.kv.set("id", std::to_string(e.id));
    e.kv.set("classname", e.classname);
    char obuf[64];
    std::snprintf(obuf, sizeof(obuf), "%.0f %.0f %.0f", e.origin.x, e.origin.y, e.origin.z);
    e.kv.set("origin", obuf);

    Array keys = kv.keys();
    for (int i = 0; i < keys.size(); ++i) {
        const String k = keys[i];
        const String v = kv[k];
        e.kv.set(toStd(k), toStd(v));
    }
    const int idx = static_cast<int>(doc_.entities().size());
    doc_.entities().push_back(std::move(e));
    doc_.markDirty();
    return idx;
}

int Tf2MapDoc::add_brush_entity(const String& classname, const Vector3& min_g, const Vector3& max_g,
                                const String& material, const Dictionary& kv) {
    glm::vec3 mn, mx;
    sourceBoxFromGodot(min_g, max_g, mn, mx);
    pb::map::Solid s = pb::map::Solid::makeBox(mn, mx, toStd(material));
    if (!s.valid) return -1;
    s.id = doc_.nextId();

    pb::map::MapEntity e;
    e.id = doc_.nextId();
    e.classname = toStd(classname);
    e.origin = 0.5f * (mn + mx);
    e.kv.name = "entity";
    e.kv.set("id", std::to_string(e.id));
    e.kv.set("classname", e.classname);
    Array keys = kv.keys();
    for (int i = 0; i < keys.size(); ++i) {
        const String k = keys[i];
        const String v = kv[k];
        e.kv.set(toStd(k), toStd(v));
    }
    e.solids.push_back(std::move(s));
    const int idx = static_cast<int>(doc_.entities().size());
    doc_.entities().push_back(std::move(e));
    doc_.markDirty();
    return idx;
}

bool Tf2MapDoc::set_entity_kv(int ent_idx, const String& key, const String& val) {
    if (ent_idx < 0 || ent_idx >= static_cast<int>(doc_.entities().size())) return false;
    doc_.entities()[ent_idx].kv.set(toStd(key), toStd(val));
    doc_.markDirty();
    return true;
}

bool Tf2MapDoc::set_entity_pos(int ent_idx, const Vector3& pos_g) {
    if (ent_idx < 0 || ent_idx >= static_cast<int>(doc_.entities().size())) return false;
    auto& e = doc_.entities()[ent_idx];
    const glm::vec3 newOrg = glm::round(toSourcePos(pos_g));
    const glm::vec3 delta = newOrg - e.origin;
    e.origin = newOrg;
    char obuf[64];
    std::snprintf(obuf, sizeof(obuf), "%.0f %.0f %.0f", e.origin.x, e.origin.y, e.origin.z);
    e.kv.set("origin", obuf);
    for (auto& s : e.solids) s.translate(delta);
    doc_.markDirty();
    return true;
}

bool Tf2MapDoc::add_connection(int src_ent_idx, const String& output_name, const String& target_name,
                               const String& input_name, const String& param, float delay) {
    if (src_ent_idx < 0 || src_ent_idx >= static_cast<int>(doc_.entities().size())) return false;
    char arg[256];
    std::snprintf(arg, sizeof(arg), "%s,%s,%s,%g,-1",
                  toStd(target_name).c_str(), toStd(input_name).c_str(),
                  toStd(param).c_str(), delay);
    doc_.entities()[src_ent_idx].connections.push_back({toStd(output_name), arg});
    doc_.markDirty();
    return true;
}

bool Tf2MapDoc::delete_entity(int ent_idx) {
    if (ent_idx < 0 || ent_idx >= static_cast<int>(doc_.entities().size())) return false;
    doc_.entities().erase(doc_.entities().begin() + ent_idx);
    doc_.markDirty();
    return true;
}

int Tf2MapDoc::get_entity_count() const { return static_cast<int>(doc_.entities().size()); }

Array Tf2MapDoc::get_entities() const {
    Array out;
    for (size_t i = 0; i < doc_.entities().size(); ++i) {
        const auto& e = doc_.entities()[i];
        Dictionary ed;
        ed["index"] = static_cast<int64_t>(i);
        ed["id"] = e.id;
        ed["classname"] = toGodot(e.classname);
        ed["targetname"] = toGodot(e.targetname());
        ed["pos"] = toGodotPos(e.origin);
        ed["is_brush"] = e.isBrush();
        if (e.isBrush()) {
            glm::vec3 mn(1e30f), mx(-1e30f);
            for (const auto& s : e.solids) {
                mn = glm::min(mn, s.boundsMin);
                mx = glm::max(mx, s.boundsMax);
            }
            const Vector3 a = toGodotPos(mn), b = toGodotPos(mx);
            ed["bounds_min"] = Vector3(std::min(a.x, b.x), std::min(a.y, b.y), std::min(a.z, b.z));
            ed["bounds_max"] = Vector3(std::max(a.x, b.x), std::max(a.y, b.y), std::max(a.z, b.z));
        }
        Dictionary kvd;
        for (const auto& p : e.kv.pairs) kvd[toGodot(p.first)] = toGodot(p.second);
        ed["kv"] = kvd;
        Array conns;
        for (const auto& c : e.connections) {
            Dictionary cd;
            cd["output"] = toGodot(c.first);
            cd["args"] = toGodot(c.second);
            conns.push_back(cd);
        }
        ed["connections"] = conns;
        out.push_back(ed);
    }
    return out;
}

int Tf2MapDoc::get_solid_count() const { return static_cast<int>(doc_.worldSolids().size()); }

Dictionary Tf2MapDoc::get_solid_info(int solid_idx) const {
    Dictionary out;
    out["valid"] = false;
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return out;
    const auto& s = doc_.worldSolids()[solid_idx];
    const Vector3 a = toGodotPos(s.boundsMin);
    const Vector3 b = toGodotPos(s.boundsMax);
    const Vector3 mn(std::min(a.x, b.x), std::min(a.y, b.y), std::min(a.z, b.z));
    const Vector3 mx(std::max(a.x, b.x), std::max(a.y, b.y), std::max(a.z, b.z));
    bool hasDisp = false;
    for (const auto& f : s.faces) if (f.hasDisp) hasDisp = true;

    out["valid"] = s.valid;
    out["id"] = s.id;
    out["hidden"] = s.hidden;
    out["group"] = s.group;
    out["bounds_min"] = mn;
    out["bounds_max"] = mx;
    out["center"] = (mn + mx) * 0.5f;
    out["size"] = mx - mn;
    out["face_count"] = static_cast<int64_t>(s.faces.size());
    out["is_skybox"] = isSkyboxSolid(s);
    out["is_disp"] = hasDisp;
    const String pm = toGodot(s.faces.empty() ? "" : s.faces[0].material);
    out["material"] = pm;
    out["primary_material"] = pm;
    return out;
}

Dictionary Tf2MapDoc::get_solid_mesh_data(int solid_idx) const {
    Dictionary out;
    out["ok"] = false;
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return out;
    meshSolidToDict(doc_.worldSolids()[solid_idx], out);
    return out;
}

Dictionary Tf2MapDoc::raycast_face(const Vector3& ray_origin_g, const Vector3& ray_dir_g) const {
    Dictionary out;
    out["hit"] = false;
    const glm::vec3 ro = toSourcePos(ray_origin_g);
    const glm::vec3 rd = glm::normalize(toSourceDir(ray_dir_g));
    float bestT = 1e30f;
    int bestSolid = -1, bestFace = -1;

    for (int i = 0; i < static_cast<int>(doc_.worldSolids().size()); ++i) {
        const auto& s = doc_.worldSolids()[i];
        if (!s.valid || s.hidden || isSkyboxSolid(s)) continue;
        float t = 0.0f;
        int fi = -1;
        if (pb::map::raySolidFace(ro, rd, s, t, fi) && t > 0.01f && t < bestT) {
            bestT = t;
            bestSolid = i;
            bestFace = fi;
        }
    }
    if (bestSolid < 0) return out;
    const auto& f = doc_.worldSolids()[bestSolid].faces[bestFace];
    glm::vec3 fc(0.0f);
    for (const auto& v : f.verts) fc += v;
    if (!f.verts.empty()) fc /= static_cast<float>(f.verts.size());

    out["hit"] = true;
    out["solid_idx"] = bestSolid;
    out["face_idx"] = bestFace;
    out["t"] = bestT * kInvUpm;
    out["hit_pos"] = toGodotPos(ro + rd * bestT);
    const Vector3 gn = toGodotDir(f.planeN);
    out["normal"] = gn;
    out["face_normal"] = gn;
    out["face_center"] = toGodotPos(fc);
    out["material"] = toGodot(f.material);
    return out;
}

bool Tf2MapDoc::push_pull_normal(int solid_idx, const Vector3& normal_g, float delta_m) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    const glm::vec3 targetN = glm::normalize(toSourceDir(normal_g));
    const auto& s = doc_.worldSolids()[solid_idx];
    int bestFace = -1;
    float bestDot = 0.55f;
    for (int fi = 0; fi < static_cast<int>(s.faces.size()); ++fi) {
        const float d = glm::dot(s.faces[fi].planeN, targetN);
        if (d > bestDot) {
            bestDot = d;
            bestFace = fi;
        }
    }
    if (bestFace < 0) return false;
    return push_pull_face(solid_idx, bestFace, delta_m);
}

bool Tf2MapDoc::rotate_solid_y(int solid_idx, float deg) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    pb::map::Solid& s = doc_.worldSolids()[solid_idx];
    const glm::vec3 ctr = s.center();
    const float rad = deg * 3.14159265358979323846f / 180.0f;
    const float cs = std::cos(rad), sn = std::sin(rad);
    auto rotPt = [&](const glm::vec3& p) {
        const glm::vec3 d = p - ctr;
        return glm::vec3(ctr.x + d.x * cs - d.y * sn, ctr.y + d.x * sn + d.y * cs, p.z);
    };
    auto rotDir = [&](const glm::vec3& v) {
        return glm::vec3(v.x * cs - v.y * sn, v.x * sn + v.y * cs, v.z);
    };
    pb::map::Solid backup = s;
    for (auto& f : s.faces) {
        const glm::vec3 nn = glm::normalize(rotDir(f.planeN));
        glm::vec3 pt = f.verts.empty() ? (f.planeN * f.planeD) : f.verts[0];
        pt = rotPt(pt);
        f.planeN = nn;
        f.planeD = glm::dot(nn, pt);
        f.planeFromPoints = false;
        const glm::vec3 u = rotDir(glm::vec3(f.uAxis));
        const glm::vec3 v = rotDir(glm::vec3(f.vAxis));
        f.uAxis = glm::vec4(u, f.uAxis.w);
        f.vAxis = glm::vec4(v, f.vAxis.w);
    }
    s.polygonise();
    if (!s.valid) {
        s = std::move(backup);
        return false;
    }
    doc_.markDirty();
    return true;
}

int Tf2MapDoc::clip_solid(int solid_idx, const Vector3& plane_pt_g, const Vector3& plane_normal_g, int keep_mode) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return -1;
    const glm::vec3 pt = toSourcePos(plane_pt_g);
    const glm::vec3 n = glm::normalize(toSourceDir(plane_normal_g));
    const float d = glm::dot(n, pt);
    const pb::map::Solid orig = doc_.worldSolids()[solid_idx];
    const std::string mat = orig.faces.empty() ? "CONCRETE/CONCRETEWALL001A" : orig.faces[0].material;

    pb::map::Solid backPart = orig;
    pb::map::Solid frontPart = orig;
    const bool backOk = backPart.clip(n, d, mat);
    const bool frontOk = frontPart.clip(-n, -d, mat);

    if (keep_mode == 1) {
        if (!frontOk) return -1;
        frontPart.id = orig.id;
        doc_.worldSolids()[solid_idx] = std::move(frontPart);
        doc_.markDirty();
        return solid_idx;
    } else if (keep_mode == 2) {
        if (!backOk) return -1;
        backPart.id = orig.id;
        doc_.worldSolids()[solid_idx] = std::move(backPart);
        doc_.markDirty();
        return solid_idx;
    } else {
        if (!backOk || !frontOk) return -1;
        backPart.id = orig.id;
        frontPart.id = doc_.nextId();
        doc_.worldSolids()[solid_idx] = std::move(backPart);
        const int newIdx = static_cast<int>(doc_.worldSolids().size());
        doc_.worldSolids().push_back(std::move(frontPart));
        doc_.markDirty();
        return newIdx;
    }
}

int Tf2MapDoc::tie_solid_to_entity(int solid_idx, const String& classname, const Dictionary& kv) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return -1;
    pb::map::Solid s = std::move(doc_.worldSolids()[solid_idx]);
    doc_.worldSolids().erase(doc_.worldSolids().begin() + solid_idx);

    pb::map::MapEntity e;
    e.id = doc_.nextId();
    e.classname = toStd(classname);
    e.origin = s.center();
    e.kv.set("classname", e.classname);
    Array keys = kv.keys();
    for (int i = 0; i < keys.size(); ++i) {
        e.kv.set(toStd(String(keys[i])), toStd(String(kv[keys[i]])));
    }
    e.solids.push_back(std::move(s));
    const int idx = static_cast<int>(doc_.entities().size());
    doc_.entities().push_back(std::move(e));
    doc_.markDirty();
    return idx;
}

int Tf2MapDoc::duplicate_entity(int ent_idx, const Vector3& offset_g) {
    if (ent_idx < 0 || ent_idx >= static_cast<int>(doc_.entities().size())) return -1;
    pb::map::MapEntity copy = doc_.entities()[ent_idx];
    copy.id = doc_.nextId();
    const glm::vec3 dU = glm::round(toSourcePos(offset_g));
    copy.origin += dU;
    char buf[96];
    std::snprintf(buf, sizeof(buf), "%g %g %g", copy.origin.x, copy.origin.y, copy.origin.z);
    copy.kv.set("origin", buf);
    for (auto& s : copy.solids) {
        s.id = doc_.nextId();
        s.translate(dU);
    }
    const int idx = static_cast<int>(doc_.entities().size());
    doc_.entities().push_back(std::move(copy));
    doc_.markDirty();
    return idx;
}

Dictionary Tf2MapDoc::raycast_entity(const Vector3& ray_origin_g, const Vector3& ray_dir_g) const {
    Dictionary out;
    out["hit"] = false;
    const Vector3 rd = ray_dir_g.normalized();
    float bestT = 1e30f;
    int bestIdx = -1;

    for (int i = 0; i < static_cast<int>(doc_.entities().size()); ++i) {
        const auto& e = doc_.entities()[i];
        if (e.hidden || e.classname == "light_environment" || e.classname == "tf_gamerules" ||
            e.classname == "team_control_point_master" || e.classname.rfind("tf_logic_", 0) == 0)
            continue;
        Vector3 bmin, bmax;
        if (e.isBrush()) {
            glm::vec3 mn(1e30f), mx(-1e30f);
            for (const auto& s : e.solids) {
                mn = glm::min(mn, s.boundsMin);
                mx = glm::max(mx, s.boundsMax);
            }
            const Vector3 a = toGodotPos(mn), b = toGodotPos(mx);
            bmin = Vector3(std::min(a.x, b.x), std::min(a.y, b.y), std::min(a.z, b.z));
            bmax = Vector3(std::max(a.x, b.x), std::max(a.y, b.y), std::max(a.z, b.z));
        } else {
            const Vector3 p = toGodotPos(e.origin);
            const Vector3 ext(0.95f, 1.35f, 0.95f);
            bmin = p - Vector3(ext.x, 0.1f, ext.z);
            bmax = p + Vector3(ext.x, ext.y * 2.0f, ext.z);
        }
        // Slab ray-AABB intersection
        float tmin = 0.05f, tmax = 400.0f;
        for (int a = 0; a < 3; ++a) {
            const float inv = (std::fabs(rd[a]) > 1e-6f) ? (1.0f / rd[a]) : 1e6f;
            float t0 = (bmin[a] - ray_origin_g[a]) * inv;
            float t1 = (bmax[a] - ray_origin_g[a]) * inv;
            if (t0 > t1) std::swap(t0, t1);
            tmin = std::max(tmin, t0);
            tmax = std::min(tmax, t1);
        }
        if (tmax >= tmin && tmin < bestT) {
            bestT = tmin;
            bestIdx = i;
        }
    }

    if (bestIdx < 0) return out;
    const auto& e = doc_.entities()[bestIdx];
    out["hit"] = true;
    out["entity_idx"] = bestIdx;
    out["classname"] = toGodot(e.classname);
    out["pos"] = toGodotPos(e.origin);
    out["hit_pos"] = ray_origin_g + rd * bestT;
    out["t"] = bestT;
    return out;
}

int Tf2MapDoc::add_wall_segment(const Vector3& p0_g, const Vector3& p1_g, float height_m, float thick_m,
                                const String& material) {
    const glm::vec3 a = toSourcePos(p0_g);
    const glm::vec3 b = toSourcePos(p1_g);
    glm::vec2 dir2(b.x - a.x, b.y - a.y);
    const float len = glm::length(dir2);
    if (len < 8.0f) return -1;
    dir2 /= len;
    const glm::vec3 fwd(dir2.x, dir2.y, 0.0f);
    const glm::vec3 right(dir2.y, -dir2.x, 0.0f);
    const float halfT = std::max(4.0f, thick_m * kUpm * 0.5f);
    const float hU = std::max(16.0f, height_m * kUpm);
    const float z0 = std::min(a.z, b.z);
    const float z1 = z0 + hU;

    const glm::vec3 mid = 0.5f * (a + b);
    std::vector<std::pair<glm::vec3, float>> planes = {
        { right,  glm::dot(right,  mid + right * halfT) },
        {-right,  glm::dot(-right, mid - right * halfT) },
        { fwd,    glm::dot(fwd,    b) },
        {-fwd,    glm::dot(-fwd,   a) },
        { glm::vec3(0, 0,  1),  z1 },
        { glm::vec3(0, 0, -1), -z0 },
    };
    pb::map::Solid s = pb::map::Solid::fromPlanes(planes, toStd(material));
    if (!s.valid) return -1;
    s.id = doc_.nextId();
    const int idx = static_cast<int>(doc_.worldSolids().size());
    doc_.worldSolids().push_back(std::move(s));
    doc_.markDirty();
    return idx;
}

PackedInt32Array Tf2MapDoc::make_hollow(int solid_idx, float wall_thick_m) {
    PackedInt32Array out;
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return out;
    const pb::map::Solid orig = doc_.worldSolids()[solid_idx];
    const float rawU = (std::fabs(wall_thick_m) < 0.05f) ? -16.0f : (wall_thick_m * kUpm);
    const float t = std::max(4.0f, std::fabs(rawU));
    pb::map::Solid shellSrc = orig;
    if (rawU < 0.0f) {
        // Hammer convention: negative thickness hollows OUTWARD so the interior stays the original size!
        const std::string mat = orig.faces.empty() ? "tools/toolsnodraw" : orig.faces.front().material;
        shellSrc = pb::map::Solid::makeBox(orig.boundsMin - glm::vec3(t), orig.boundsMax + glm::vec3(t), mat);
    }
    auto pieces = pb::map::hollow(shellSrc, t);
    std::vector<pb::map::Solid> validPieces;
    for (auto& p : pieces) {
        if (p.valid && p.faces.size() >= 4) validPieces.push_back(std::move(p));
    }
    if (validPieces.empty()) return out;
    doc_.worldSolids().erase(doc_.worldSolids().begin() + solid_idx);
    for (auto& p : validPieces) {
        p.id = doc_.nextId();
        const int idx = static_cast<int>(doc_.worldSolids().size());
        doc_.worldSolids().push_back(std::move(p));
        out.push_back(idx);
    }
    doc_.markDirty();
    return out;
}

PackedVector3Array Tf2MapDoc::get_solid_vertices(int solid_idx) const {
    PackedVector3Array out;
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return out;
    const pb::map::BrushHandles h = pb::map::extractHandles(doc_.worldSolids()[solid_idx]);
    for (const auto& v : h.verts) out.push_back(toGodotPos(v.pos));
    return out;
}

bool Tf2MapDoc::move_solid_vertex(int solid_idx, int vert_idx, const Vector3& delta_g) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    pb::map::Solid& s = doc_.worldSolids()[solid_idx];
    const pb::map::BrushHandles h = pb::map::extractHandles(s);
    if (vert_idx < 0 || vert_idx >= static_cast<int>(h.verts.size())) return false;
    pb::map::Solid backup = s;
    const glm::vec3 dU = glm::round(toSourcePos(delta_g));
    if (!pb::map::moveVertexHandles(s, h, {vert_idx}, dU)) {
        s = std::move(backup);
        return false;
    }
    doc_.markDirty();
    return true;
}

bool Tf2MapDoc::create_displacement_on_face(int solid_idx, int face_idx, int power) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    auto& s = doc_.worldSolids()[solid_idx];
    if (face_idx < 0 || face_idx >= static_cast<int>(s.faces.size())) return false;
    auto& f = s.faces[face_idx];
    if (f.verts.size() != 4) return false;
    pb::map::faceMakeDisplacement(f, std::clamp(power, 2, 4));
    doc_.markDirty();
    return true;
}

int Tf2MapDoc::make_cliff_wall(const Vector3& p0_g, const Vector3& p1_g, float height_m, float depth_m,
                               int power, const String& material, float noise_amp_m) {
    const int idx = add_wall_segment(p0_g, p1_g, height_m, std::max(1.5f, depth_m), material);
    if (idx < 0) return -1;
    auto& s = doc_.worldSolids()[idx];
    power = std::clamp(power, 2, 4);
    // Pick the front vertical face (largest area side face facing outward along right normal)
    const glm::vec3 a = toSourcePos(p0_g);
    const glm::vec3 b = toSourcePos(p1_g);
    glm::vec2 dir2 = glm::normalize(glm::vec2(b.x - a.x, b.y - a.y));
    const glm::vec3 frontN(dir2.y, -dir2.x, 0.0f);
    int bestFace = -1;
    float bestDot = 0.5f;
    for (int fi = 0; fi < static_cast<int>(s.faces.size()); ++fi) {
        if (s.faces[fi].verts.size() != 4) continue;
        float d = glm::dot(s.faces[fi].planeN, frontN);
        if (d > bestDot) { bestDot = d; bestFace = fi; }
    }
    if (bestFace < 0) return idx;
    auto& f = s.faces[bestFace];
    pb::map::faceMakeDisplacement(f, power);

    // Pre-sculpt dramatic stratified TF2 Badlands/Upward canyon cliff rock face + base alpha blend!
    const int gn = (1 << power) + 1;
    std::vector<float> dst(static_cast<size_t>(gn) * gn, 0.0f);
    std::vector<float> alp(static_cast<size_t>(gn) * gn, 0.0f);
    glm::vec3 start(0.0f);
    std::sscanf(f.dispInfo.get("startposition").c_str(), " [ %f %f %f ]",
                &start.x, &start.y, &start.z);
    glm::vec3 A, B, C, D;
    dispCornersLocal(f, start, A, B, C, D);
    const float zMin = std::min({A.z, B.z, C.z, D.z});
    const float zMax = std::max({A.z, B.z, C.z, D.z});
    const float zSpan = std::max(32.0f, zMax - zMin);
    const float ampU = std::max(28.0f, noise_amp_m * kUpm * 2.1f);
    for (int r = 0; r < gn; ++r) {
        const float tb = static_cast<float>(r) / (gn - 1);
        const glm::vec3 e0 = A + (D - A) * tb;
        const glm::vec3 e1 = B + (C - B) * tb;
        for (int c = 0; c < gn; ++c) {
            const float ta = static_cast<float>(c) / (gn - 1);
            const glm::vec3 base = e0 + (e1 - e0) * ta;
            const float h01 = std::clamp((base.z - zMin) / zSpan, 0.0f, 1.0f);
            // Stratified horizontal TF2 rock shelves + bold angular crag ridges
            const float ridge = std::sin(base.x * 0.017f + base.y * 0.015f) * 0.55f +
                                std::cos(base.x * 0.039f - base.z * 0.022f) * 0.45f;
            const float shelf = std::sin(h01 * 12.566f + ridge * 1.1f) * 0.38f;
            // Base flares forward naturally like real canyon rock talus!
            const float talus = (1.0f - h01) * (1.0f - h01) * ampU * 1.15f;
            const float crag = (0.35f + 0.65f * (1.0f - h01 * 0.45f)) * (ridge + shelf) * ampU * 0.72f;
            dst[r * gn + c] = std::max(-ampU * 0.35f, talus + crag);
            // Pre-paint dusty dirt-to-rock alpha transition along the bottom 35% of the cliff!
            const float dirtBlend = std::clamp((0.42f - h01) / 0.42f + ridge * 0.12f, 0.0f, 1.0f);
            alp[r * gn + c] = dirtBlend * 255.0f;
        }
    }
    for (auto& ch : f.dispInfo.children) {
        if (ch.name == "distances") writeDispRows(ch, gn, 1, dst);
        if (ch.name == "alphas") writeDispRows(ch, gn, 1, alp);
    }
    doc_.markDirty();
    return idx;
}

int Tf2MapDoc::sculpt_terrain_ex(const Vector3& center_g, float radius_m, float strength_m,
                                 int mode, int axis_mode) {
    // mode: 0=Raise, 1=Lower, 2=Smooth, 3=Flatten, 4=PaintAlpha+, 5=PaintAlpha-, 6=OrganicNoise
    // axis_mode: 0=FaceNormal (works on cliffs & floors!), 1=WorldY, 2=WorldX, 3=WorldZ
    const glm::vec3 centerU = toSourcePos(center_g);
    const float radU = std::max(16.0f, radius_m * kUpm);
    const float amtU = strength_m * kUpm;
    int touched = 0;

    for (auto& s : doc_.worldSolids()) {
        for (auto& f : s.faces) {
            if (!f.hasDisp || f.verts.size() != 4) continue;
            const int power = f.dispInfo.getInt("power");
            if (power < 2 || power > 4) continue;
            const int gn = (1 << power) + 1;
            std::vector<float> nrm, dst, alp;
            if (!readDispRows(f.dispInfo.child("normals"), gn, 3, nrm) ||
                !readDispRows(f.dispInfo.child("distances"), gn, 1, dst))
                continue;
            const bool hasAlp = readDispRows(f.dispInfo.child("alphas"), gn, 1, alp);
            if (!hasAlp) alp.assign(static_cast<size_t>(gn) * gn, 0.0f);

            glm::vec3 start(0.0f);
            std::sscanf(f.dispInfo.get("startposition").c_str(), " [ %f %f %f ]",
                        &start.x, &start.y, &start.z);
            glm::vec3 A, B, C, D;
            dispCornersLocal(f, start, A, B, C, D);

            std::vector<float> nextDst = dst;
            std::vector<float> nextAlp = alp;
            std::vector<float> nextNrm = nrm;
            bool anyDst = false, anyAlp = false, anyNrm = false;
            const float r2 = radU * radU;

            for (int r = 0; r < gn; ++r) {
                const float tb = static_cast<float>(r) / (gn - 1);
                const glm::vec3 e0 = A + (D - A) * tb;
                const glm::vec3 e1 = B + (C - B) * tb;
                for (int c = 0; c < gn; ++c) {
                    const int i = r * gn + c;
                    const float ta = static_cast<float>(c) / (gn - 1);
                    const glm::vec3 base = e0 + (e1 - e0) * ta;
                    const glm::vec3 nv(nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2]);
                    const glm::vec3 cur = base + nv * dst[i];
                    const float d2 = glm::dot(cur - centerU, cur - centerU);
                    if (d2 > r2) continue;
                    const float t = 1.0f - std::sqrt(d2) / radU;
                    const float fall = t * t * (3.0f - 2.0f * t); // smoothstep

                    if (mode == 4 || mode == 5) {
                        const float deltaA = (mode == 4 ? 1.0f : -1.0f) * std::fabs(strength_m) * 90.0f * fall;
                        nextAlp[i] = std::clamp(alp[i] + deltaA, 0.0f, 255.0f);
                        anyAlp = true;
                    } else if (mode == 0 || mode == 1 || mode == 6) {
                        glm::vec3 pushDir = f.planeN;
                        if (axis_mode == 1) pushDir = glm::vec3(0, 0, 1);
                        else if (axis_mode == 2) pushDir = glm::vec3(1, 0, 0);
                        else if (axis_mode == 3) pushDir = glm::vec3(0, -1, 0);
                        float signedAmt = (mode == 1 ? -std::fabs(amtU) : std::fabs(amtU)) * fall;
                        if (mode == 6) {
                            const float h = std::sin(cur.x * 0.047f + cur.z * 0.061f) * std::cos(cur.y * 0.053f);
                            signedAmt = h * std::fabs(amtU) * fall;
                        }
                        const glm::vec3 target = cur + pushDir * signedAmt;
                        const glm::vec3 off = target - base;
                        const float dlen = glm::length(off);
                        if (dlen > 0.001f) {
                            const glm::vec3 dn = off / dlen;
                            nextNrm[i * 3 + 0] = dn.x;
                            nextNrm[i * 3 + 1] = dn.y;
                            nextNrm[i * 3 + 2] = dn.z;
                            nextDst[i] = dlen;
                            anyNrm = true;
                        } else {
                            nextDst[i] = 0.0f;
                        }
                        anyDst = true;
                    } else if (mode == 2) {
                        // Smooth neighbor positions
                        float sum = 0.0f; int cnt = 0;
                        for (int dr = -1; dr <= 1; ++dr)
                            for (int dc = -1; dc <= 1; ++dc) {
                                int rr = r + dr, cc = c + dc;
                                if (rr >= 0 && rr < gn && cc >= 0 && cc < gn) {
                                    sum += dst[rr * gn + cc]; ++cnt;
                                }
                            }
                        nextDst[i] = dst[i] + ((sum / cnt) - dst[i]) * fall * 0.72f;
                        anyDst = true;
                    } else if (mode == 3) {
                        const float targetD = glm::dot(centerU - base, nv);
                        nextDst[i] = dst[i] + (targetD - dst[i]) * fall * 0.78f;
                        anyDst = true;
                    }
                }
            }
            if (anyDst || anyNrm) {
                for (auto& ch : f.dispInfo.children) {
                    if (anyDst && ch.name == "distances") writeDispRows(ch, gn, 1, nextDst);
                    if (anyNrm && ch.name == "normals") writeDispRows(ch, gn, 3, nextNrm);
                }
                ++touched;
            }
            if (anyAlp) {
                bool wrote = false;
                for (auto& ch : f.dispInfo.children) {
                    if (ch.name == "alphas") { writeDispRows(ch, gn, 1, nextAlp); wrote = true; break; }
                }
                if (!wrote) {
                    pb::map::KvNode an; an.name = "alphas";
                    writeDispRows(an, gn, 1, nextAlp);
                    f.dispInfo.children.push_back(std::move(an));
                }
                ++touched;
            }
        }
    }
    if (touched > 0) doc_.markDirty();
    return touched;
}

int Tf2MapDoc::sew_displacements() {
    struct DispRef {
        pb::map::BrushFace* face = nullptr;
        int gn = 0;
        std::vector<glm::vec3> base;
        std::vector<glm::vec3> cur;
        bool dirty = false;
    };
    std::vector<DispRef> list;
    for (auto& s : doc_.worldSolids()) {
        for (auto& f : s.faces) {
            if (!f.hasDisp || f.verts.size() != 4) continue;
            const int power = f.dispInfo.getInt("power");
            if (power < 2 || power > 4) continue;
            const int gn = (1 << power) + 1;
            std::vector<float> nrm, dst;
            if (!readDispRows(f.dispInfo.child("normals"), gn, 3, nrm) ||
                !readDispRows(f.dispInfo.child("distances"), gn, 1, dst))
                continue;
            glm::vec3 start(0.0f);
            std::sscanf(f.dispInfo.get("startposition").c_str(), " [ %f %f %f ]",
                        &start.x, &start.y, &start.z);
            glm::vec3 A, B, C, D;
            dispCornersLocal(f, start, A, B, C, D);
            DispRef dr;
            dr.face = &f;
            dr.gn = gn;
            dr.base.resize(static_cast<size_t>(gn) * gn);
            dr.cur.resize(static_cast<size_t>(gn) * gn);
            for (int r = 0; r < gn; ++r) {
                const float tb = static_cast<float>(r) / (gn - 1);
                const glm::vec3 e0 = A + (D - A) * tb;
                const glm::vec3 e1 = B + (C - B) * tb;
                for (int c = 0; c < gn; ++c) {
                    const int i = r * gn + c;
                    const float ta = static_cast<float>(c) / (gn - 1);
                    dr.base[i] = e0 + (e1 - e0) * ta;
                    const glm::vec3 nv(nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2]);
                    dr.cur[i] = dr.base[i] + nv * dst[i];
                }
            }
            list.push_back(std::move(dr));
        }
    }
    int sewn = 0;
    for (size_t a = 0; a < list.size(); ++a) {
        for (size_t b = a + 1; b < list.size(); ++b) {
            auto& da = list[a];
            auto& db = list[b];
            for (int ra = 0; ra < da.gn; ++ra) {
                for (int ca = 0; ca < da.gn; ++ca) {
                    if (ra != 0 && ra != da.gn - 1 && ca != 0 && ca != da.gn - 1) continue;
                    const int ia = ra * da.gn + ca;
                    for (int rb = 0; rb < db.gn; ++rb) {
                        for (int cb = 0; cb < db.gn; ++cb) {
                            if (rb != 0 && rb != db.gn - 1 && cb != 0 && cb != db.gn - 1) continue;
                            const int ib = rb * db.gn + cb;
                            if (glm::distance(da.base[ia], db.base[ib]) < 6.0f) {
                                const glm::vec3 mid = 0.5f * (da.cur[ia] + db.cur[ib]);
                                da.cur[ia] = mid;
                                db.cur[ib] = mid;
                                da.dirty = db.dirty = true;
                                ++sewn;
                            }
                        }
                    }
                }
            }
        }
    }
    for (auto& dr : list) {
        if (!dr.dirty) continue;
        const int total = dr.gn * dr.gn;
        std::vector<float> nrm(total * 3), dst(total);
        for (int i = 0; i < total; ++i) {
            const glm::vec3 off = dr.cur[i] - dr.base[i];
            const float len = glm::length(off);
            const glm::vec3 nv = (len > 1e-4f) ? (off / len) : dr.face->planeN;
            nrm[i * 3 + 0] = nv.x; nrm[i * 3 + 1] = nv.y; nrm[i * 3 + 2] = nv.z;
            dst[i] = len;
        }
        for (auto& ch : dr.face->dispInfo.children) {
            if (ch.name == "normals") writeDispRows(ch, dr.gn, 3, nrm);
            if (ch.name == "distances") writeDispRows(ch, dr.gn, 1, dst);
        }
    }
    if (sewn > 0) doc_.markDirty();
    return sewn;
}

bool Tf2MapDoc::subdivide_displacement(int solid_idx) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    bool any = false;
    for (auto& f : doc_.worldSolids()[solid_idx].faces) {
        if (!f.hasDisp) continue;
        const int power = f.dispInfo.getInt("power");
        if (power < 2 || power > 4) continue;
        const int gn = (1 << power) + 1;
        std::vector<float> dst;
        if (!readDispRows(f.dispInfo.child("distances"), gn, 1, dst)) continue;
        std::vector<float> out = dst;
        for (int r = 1; r < gn - 1; ++r)
            for (int c = 1; c < gn - 1; ++c) {
                out[r * gn + c] = (dst[(r - 1) * gn + c] + dst[(r + 1) * gn + c] +
                                   dst[r * gn + (c - 1)] + dst[r * gn + (c + 1)] +
                                   dst[r * gn + c] * 2.0f) / 6.0f;
            }
        for (auto& ch : f.dispInfo.children) {
            if (ch.name == "distances") { writeDispRows(ch, gn, 1, out); any = true; break; }
        }
    }
    if (any) doc_.markDirty();
    return any;
}

Dictionary Tf2MapDoc::get_face_uv(int solid_idx, int face_idx) const {
    Dictionary d;
    d["ok"] = false;
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return d;
    const auto& s = doc_.worldSolids()[solid_idx];
    if (face_idx < 0 || face_idx >= static_cast<int>(s.faces.size())) return d;
    const auto& f = s.faces[face_idx];
    d["ok"] = true;
    d["material"] = toGodot(f.material);
    d["u_scale"] = f.uScale;
    d["v_scale"] = f.vScale;
    d["u_shift"] = f.uAxis.w;
    d["v_shift"] = f.vAxis.w;
    d["rotation"] = f.rotation;
    d["lightmap_scale"] = f.lightmapScale;
    d["has_disp"] = f.hasDisp;
    return d;
}

bool Tf2MapDoc::set_face_uv(int solid_idx, int face_idx, float u_scale, float v_scale,
                            float u_shift, float v_shift, float rot_deg, float lightmap_scale) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    auto& s = doc_.worldSolids()[solid_idx];
    if (face_idx < 0 || face_idx >= static_cast<int>(s.faces.size())) return false;
    auto& f = s.faces[face_idx];
    f.uScale = std::clamp(u_scale, 0.02f, 16.0f);
    f.vScale = std::clamp(v_scale, 0.02f, 16.0f);
    f.uAxis.w = u_shift;
    f.vAxis.w = v_shift;
    if (std::fabs(rot_deg - f.rotation) > 0.01f) {
        pb::map::faceRotateUV(f, rot_deg - f.rotation);
    }
    f.lightmapScale = std::clamp(lightmap_scale, 2.0f, 128.0f);
    doc_.markDirty();
    return true;
}

bool Tf2MapDoc::justify_face_uv(int solid_idx, int face_idx, int mode) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    auto& s = doc_.worldSolids()[solid_idx];
    if (face_idx < 0 || face_idx >= static_cast<int>(s.faces.size())) return false;
    pb::map::faceJustifyUV(s.faces[face_idx], 512, 512, mode);
    doc_.markDirty();
    return true;
}

bool Tf2MapDoc::align_face_uv(int solid_idx, int face_idx, bool to_face) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    auto& s = doc_.worldSolids()[solid_idx];
    if (face_idx < 0 || face_idx >= static_cast<int>(s.faces.size())) return false;
    if (to_face) pb::map::faceAlignToFace(s.faces[face_idx]);
    else pb::map::faceAlignWorld(s.faces[face_idx]);
    doc_.markDirty();
    return true;
}

int Tf2MapDoc::replace_material(const String& find_mat, const String& replace_mat) {
    std::string fm = toStd(find_mat);
    std::string rm = toStd(replace_mat);
    std::string fmLow = fm;
    std::transform(fmLow.begin(), fmLow.end(), fmLow.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    int count = 0;
    for (auto& s : doc_.worldSolids()) {
        for (auto& f : s.faces) {
            std::string cur = f.material;
            std::transform(cur.begin(), cur.end(), cur.begin(),
                           [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
            if (cur == fmLow) {
                f.material = rm;
                ++count;
            }
        }
    }
    if (count > 0) doc_.markDirty();
    return count;
}

bool Tf2MapDoc::set_solid_hidden(int solid_idx, bool hidden) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    doc_.worldSolids()[solid_idx].hidden = hidden;
    return true;
}

int Tf2MapDoc::unhide_all() {
    int n = 0;
    for (auto& s : doc_.worldSolids()) { if (s.hidden) { s.hidden = false; ++n; } }
    for (auto& e : doc_.entities()) { if (e.hidden) { e.hidden = false; ++n; } }
    return n;
}

bool Tf2MapDoc::set_solid_group(int solid_idx, int group_id) {
    if (solid_idx < 0 || solid_idx >= static_cast<int>(doc_.worldSolids().size())) return false;
    doc_.worldSolids()[solid_idx].group = group_id;
    doc_.markDirty();
    return true;
}

Array Tf2MapDoc::check_problems() const {
    Array out;
    auto pushProb = [&](const char* sev, const char* code, const std::string& msg,
                        const Vector3& pos, int sidx, int eidx, const char* fix) {
        Dictionary d;
        d["severity"] = String(sev);
        d["code"] = String(code);
        d["message"] = toGodot(msg);
        d["pos"] = pos;
        d["solid_idx"] = sidx;
        d["ent_idx"] = eidx;
        d["fix_kind"] = String(fix);
        out.push_back(d);
    };

    if (!is_map_sealed()) {
        pushProb("ERROR", "UNSEALED", "Map has no sealing TOOLSSKYBOX shell (will leak in vbsp!)",
                 Vector3(0, 4, 0), -1, -1, "auto_seal");
    }

    int redSpawns = 0, bluSpawns = 0, lights = 0;
    std::unordered_map<std::string, int> targetCounts;
    for (int i = 0; i < static_cast<int>(doc_.entities().size()); ++i) {
        const auto& e = doc_.entities()[i];
        if (e.classname == "info_player_teamspawn") {
            if (e.kv.get("TeamNum") == "3") ++bluSpawns;
            else ++redSpawns;
        }
        if (e.classname == "light" || e.classname == "light_environment" || e.classname == "light_spot")
            ++lights;
        const std::string tn = e.targetname();
        if (!tn.empty()) targetCounts[tn]++;
    }
    if (redSpawns == 0) {
        pushProb("ERROR", "NO_RED_SPAWN", "Missing RED info_player_teamspawn!",
                 Vector3(-12, 1, 0), -1, -1, "add_red_spawn");
    }
    if (bluSpawns == 0) {
        pushProb("ERROR", "NO_BLU_SPAWN", "Missing BLU info_player_teamspawn!",
                 Vector3(12, 1, 0), -1, -1, "add_blu_spawn");
    }
    if (lights == 0) {
        pushProb("WARN", "NO_LIGHT", "No light_environment or light entity (map will compile fullbright!)",
                 Vector3(0, 8, 0), -1, -1, "add_sun");
    }

    // Check broken I/O targets & invalid solids
    for (int i = 0; i < static_cast<int>(doc_.entities().size()); ++i) {
        const auto& e = doc_.entities()[i];
        for (const auto& c : e.connections) {
            auto comma = c.second.find(',');
            std::string tgt = (comma == std::string::npos) ? c.second : c.second.substr(0, comma);
            if (!tgt.empty() && tgt[0] != '!' && targetCounts.find(tgt) == targetCounts.end()) {
                pushProb("WARN", "BROKEN_IO",
                         "Entity #" + std::to_string(i) + " (" + e.classname + ") output '" + c.first +
                             "' targets missing entity '" + tgt + "'",
                         toGodotPos(e.origin), -1, i, "");
            }
        }
    }
    for (int i = 0; i < static_cast<int>(doc_.worldSolids().size()); ++i) {
        const auto& s = doc_.worldSolids()[i];
        if (!s.valid || s.faces.size() < 4) {
            pushProb("ERROR", "INVALID_SOLID",
                     "Solid #" + std::to_string(i) + " has degenerate geometry (<4 valid faces)",
                     toGodotPos(s.center()), i, -1, "delete_solid");
        }
    }
    return out;
}

}  // namespace godot
