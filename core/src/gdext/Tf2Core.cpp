#include "gdext/Tf2Core.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <filesystem>
#include <unordered_map>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/basis.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <glm/gtc/matrix_transform.hpp>

#include "bsp/BspFile.h"
#include "bsp/BspMesh.h"
#include "core/File.h"
#include "model/StudioModel.h"

namespace fs = std::filesystem;

namespace godot {

namespace {
std::string toStd(const String& s) {
    CharString utf8 = s.utf8();
    return std::string(utf8.get_data(), static_cast<size_t>(utf8.length()));
}

String toGodot(const std::string& s) {
    return String::utf8(s.c_str(), static_cast<int64_t>(s.size()));
}

std::string detectTf2Dir() {
    const char* kCandidates[] = {
        "C:/Program Files (x86)/Steam/steamapps/common/Team Fortress 2",
        "C:/Program Files/Steam/steamapps/common/Team Fortress 2",
        "D:/SteamLibrary/steamapps/common/Team Fortress 2",
        "E:/SteamLibrary/steamapps/common/Team Fortress 2",
        "F:/SteamLibrary/steamapps/common/Team Fortress 2",
    };
    for (const char* c : kCandidates) {
        std::error_code ec;
        if (fs::exists(fs::path(c) / "tf" / "tf2_textures_dir.vpk", ec)) {
            return c;
        }
    }
    return {};
}
}  // namespace

void Tf2Core::_bind_methods() {
    ClassDB::bind_method(D_METHOD("mount_tf2", "repo_root"), &Tf2Core::mount_tf2, DEFVAL(String()));
    ClassDB::bind_method(D_METHOD("is_ready"), &Tf2Core::is_ready);
    ClassDB::bind_method(D_METHOD("get_tf2_dir"), &Tf2Core::get_tf2_dir);
    ClassDB::bind_method(D_METHOD("get_fgd_class_count"), &Tf2Core::get_fgd_class_count);
    ClassDB::bind_method(D_METHOD("list_maps"), &Tf2Core::list_maps);
    ClassDB::bind_method(D_METHOD("list_materials", "prefix", "limit"),
                         &Tf2Core::list_materials, DEFVAL(String()), DEFVAL(256));
    ClassDB::bind_method(D_METHOD("list_models", "prefix", "limit"),
                         &Tf2Core::list_models, DEFVAL(String()), DEFVAL(256));
    ClassDB::bind_method(D_METHOD("get_fgd_class_info", "classname"), &Tf2Core::get_fgd_class_info);
    ClassDB::bind_method(D_METHOD("read_material_rgba", "material_path"), &Tf2Core::read_material_rgba);
    ClassDB::bind_method(D_METHOD("read_model_data", "mdl_path"), &Tf2Core::read_model_data);
    ClassDB::bind_method(D_METHOD("list_skyboxes"), &Tf2Core::list_skyboxes);
    ClassDB::bind_method(D_METHOD("read_skybox_panorama", "skyname", "pano_width", "pano_height"),
                         &Tf2Core::read_skybox_panorama, DEFVAL(1024), DEFVAL(512));
    ClassDB::bind_method(D_METHOD("load_bsp_data", "bsp_path"), &Tf2Core::load_bsp_data);
}

Dictionary Tf2Core::mount_tf2(const String& repo_root) {
    fs_ = pb::source::SourceFs();
    fgd_ = pb::fgd::Fgd();
    tf2_dir_ = detectTf2Dir();

    std::string root = toStd(repo_root);
    if (root.empty()) root = ".";

    fs_.mountDefaults(root);
    mounted_ = fs_.ready();

    // Load TF2 FGD (prefer TF2's full bin/tf.fgd which resolves @include base.fgd/halflife2.fgd -> 446 classes!)
    std::vector<std::string> fgdCandidates;
    if (!tf2_dir_.empty()) {
        fgdCandidates.push_back(tf2_dir_ + "/bin/tf.fgd");
        fgdCandidates.push_back(tf2_dir_ + "/bin/x64/tf.fgd");
    }
    fgdCandidates.push_back(root + "/assets/mapping_resource_pack/tf-abs.fgd");
    fgdCandidates.push_back(root + "/../assets/mapping_resource_pack/tf-abs.fgd");
    std::string loadedFgd;
    for (const auto& p : fgdCandidates) {
        if (pb::fileExists(p) && fgd_.load(p)) {
            loadedFgd = p;
            break;
        }
    }

    const PackedStringArray maps = list_maps();
    const auto allMats = fs_.listFiles("materials/", ".vmt");
    const auto allMdls = fs_.listFiles("models/", ".mdl");

    Dictionary out;
    out["ready"] = mounted_;
    out["tf2_dir"] = toGodot(tf2_dir_);
    out["fgd_path"] = toGodot(loadedFgd);
    out["fgd_classes"] = static_cast<int64_t>(fgd_.size());
    out["fgd_point_classes"] = static_cast<int64_t>(fgd_.pointClasses().size());
    out["fgd_solid_classes"] = static_cast<int64_t>(fgd_.solidClasses().size());
    out["map_count"] = maps.size();
    out["material_count"] = static_cast<int64_t>(allMats.size());
    out["model_count"] = static_cast<int64_t>(allMdls.size());
    return out;
}

bool Tf2Core::is_ready() const { return mounted_; }

String Tf2Core::get_tf2_dir() const { return toGodot(tf2_dir_); }

int Tf2Core::get_fgd_class_count() const { return static_cast<int>(fgd_.size()); }

PackedStringArray Tf2Core::list_maps() const {
    PackedStringArray out;
    if (tf2_dir_.empty()) return out;
    const fs::path mapsDir = fs::path(tf2_dir_) / "tf" / "maps";
    std::error_code ec;
    if (!fs::exists(mapsDir, ec)) return out;

    std::vector<std::string> names;
    for (const auto& entry : fs::directory_iterator(mapsDir, ec)) {
        if (!entry.is_regular_file(ec)) continue;
        std::string ext = entry.path().extension().string();
        std::transform(ext.begin(), ext.end(), ext.begin(),
                       [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        if (ext == ".bsp") names.push_back(entry.path().filename().string());
    }
    std::sort(names.begin(), names.end());
    for (const auto& n : names) out.push_back(toGodot(n));
    return out;
}

PackedStringArray Tf2Core::list_materials(const String& prefix, int limit) const {
    PackedStringArray out;
    if (!mounted_) return out;
    std::string pfx = "materials/" + toStd(prefix);
    const auto files = fs_.listFiles(pfx, ".vmt");
    const int cap = (limit > 0) ? std::min<int>(limit, static_cast<int>(files.size()))
                                : static_cast<int>(files.size());
    for (int i = 0; i < cap; ++i) {
        std::string s = files[i];
        if (s.rfind("materials/", 0) == 0) s = s.substr(10);
        if (s.size() > 4 && s.substr(s.size() - 4) == ".vmt") s.resize(s.size() - 4);
        out.push_back(toGodot(s));
    }
    return out;
}

PackedStringArray Tf2Core::list_models(const String& prefix, int limit) const {
    PackedStringArray out;
    if (!mounted_) return out;
    std::string pfx = "models/" + toStd(prefix);
    const auto files = fs_.listFiles(pfx, ".mdl");
    const int cap = (limit > 0) ? std::min<int>(limit, static_cast<int>(files.size()))
                                : static_cast<int>(files.size());
    for (int i = 0; i < cap; ++i) out.push_back(toGodot(files[i]));
    return out;
}

Dictionary Tf2Core::get_fgd_class_info(const String& classname) const {
    Dictionary out;
    const pb::fgd::EntityClass* ec = fgd_.flattened(toStd(classname));
    if (!ec) {
        out["found"] = false;
        return out;
    }
    out["found"] = true;
    out["name"] = toGodot(ec->name);
    out["description"] = toGodot(ec->description.empty() ? ec->help : ec->description);
    out["is_point"] = ec->isPoint();
    out["is_solid"] = ec->isSolid();
    out["studio_model"] = toGodot(ec->studioModel);
    out["has_color"] = ec->hasColor;
    out["color"] = Color(ec->color.r, ec->color.g, ec->color.b, 1.0f);
    out["has_size"] = ec->hasSize;
    out["size_min"] = Vector3(ec->sizeMin.x, ec->sizeMin.y, ec->sizeMin.z);
    out["size_max"] = Vector3(ec->sizeMax.x, ec->sizeMax.y, ec->sizeMax.z);
    out["var_count"] = static_cast<int64_t>(ec->vars.size());
    out["input_count"] = static_cast<int64_t>(ec->inputs.size());
    out["output_count"] = static_cast<int64_t>(ec->outputs.size());
    return out;
}

Dictionary Tf2Core::read_material_rgba(const String& material_path) const {
    Dictionary out;
    out["ok"] = false;
    if (!mounted_) return out;

    const std::string mat = toStd(material_path);
    const pb::source::ResolvedMaterial rm = fs_.resolveMaterial(mat);
    const std::string tex = !rm.baseTexture.empty() ? rm.baseTexture : mat;
    const pb::source::VtfImage img = fs_.loadTexture(tex);
    if (!img.ok()) return out;

    PackedByteArray bytes;
    bytes.resize(static_cast<int64_t>(img.rgba.size()));
    std::memcpy(bytes.ptrw(), img.rgba.data(), img.rgba.size());

    out["ok"] = true;
    out["width"] = img.width;
    out["height"] = img.height;
    out["has_alpha"] = img.hasAlpha;
    out["alpha_test"] = rm.alphaTest;
    out["translucent"] = rm.translucent;
    out["no_cull"] = rm.noCull;
    out["self_illum"] = rm.selfIllum;
    out["base_texture"] = toGodot(tex);
    out["rgba"] = bytes;
    return out;
}

Dictionary Tf2Core::read_model_data(const String& mdl_path) {
    Dictionary out;
    out["ok"] = false;
    if (!mounted_) return out;

    const std::string path = toStd(mdl_path);
    const pb::model::StudioModel& mdl = pb::model::loadStudioModel(fs_, path);
    if (!mdl.ok || mdl.verts.empty() || mdl.indices.empty()) return out;

    constexpr float kInvUpm = 1.0f / 32.0f;  // 32 Hammer units = 1 Godot meter
    auto toGodotPos = [](const glm::vec3& p) {
        return Vector3(p.x * kInvUpm, p.z * kInvUpm, -p.y * kInvUpm);
    };
    auto toGodotNrm = [](const glm::vec3& n) {
        return Vector3(n.x, n.z, -n.y);
    };

    Array surfaces;
    for (const auto& sm : mdl.meshes) {
        if (sm.indexCount < 3) continue;
        if (sm.firstIndex + sm.indexCount > mdl.indices.size()) continue;

        PackedVector3Array verts;
        PackedVector3Array norms;
        PackedVector2Array uvs;
        PackedInt32Array inds;
        std::unordered_map<uint32_t, int32_t> remap;
        remap.reserve(sm.indexCount);

        auto addVert = [&](uint32_t srcIdx) -> int32_t {
            auto it = remap.find(srcIdx);
            if (it != remap.end()) return it->second;
            const int32_t dstIdx = static_cast<int32_t>(verts.size());
            const auto& v = mdl.verts[srcIdx];
            verts.push_back(toGodotPos(v.pos));
            norms.push_back(toGodotNrm(v.normal));
            uvs.push_back(Vector2(v.uv.x, v.uv.y));
            remap.emplace(srcIdx, dstIdx);
            return dstIdx;
        };

        // Source StudioMDL .vtx indices are already CW outward-facing for Godot ArrayMesh
        for (uint32_t k = 0; k + 2 < sm.indexCount; k += 3) {
            const uint32_t a = mdl.indices[sm.firstIndex + k + 0];
            const uint32_t b = mdl.indices[sm.firstIndex + k + 1];
            const uint32_t c = mdl.indices[sm.firstIndex + k + 2];
            if (a >= mdl.verts.size() || b >= mdl.verts.size() || c >= mdl.verts.size()) continue;
            const int32_t ia = addVert(a);
            const int32_t ib = addVert(b);
            const int32_t ic = addVert(c);
            inds.push_back(ia);
            inds.push_back(ib);
            inds.push_back(ic);
        }

        if (inds.is_empty()) continue;
        Dictionary surf;
        surf["material"] = toGodot(sm.material);
        surf["vertices"] = verts;
        surf["normals"] = norms;
        surf["uvs"] = uvs;
        surf["indices"] = inds;
        surfaces.push_back(surf);
    }

    if (surfaces.is_empty()) return out;

    const Vector3 b0 = toGodotPos(mdl.boundsMin);
    const Vector3 b1 = toGodotPos(mdl.boundsMax);
    out["ok"] = true;
    out["path"] = mdl_path;
    out["vertex_count"] = static_cast<int64_t>(mdl.verts.size());
    out["triangle_count"] = static_cast<int64_t>(mdl.indices.size() / 3);
    out["bounds_min"] = Vector3(std::min(b0.x, b1.x), std::min(b0.y, b1.y), std::min(b0.z, b1.z));
    out["bounds_max"] = Vector3(std::max(b0.x, b1.x), std::max(b0.y, b1.y), std::max(b0.z, b1.z));
    out["surfaces"] = surfaces;
    return out;
}

PackedStringArray Tf2Core::list_skyboxes() const {
    PackedStringArray out;
    if (!mounted_) return out;
    const auto files = fs_.listFiles("materials/skybox/", ".vmt");
    std::vector<std::string> names;
    for (const auto& f : files) {
        // Strip "materials/skybox/" prefix and ".vmt" suffix
        if (f.rfind("materials/skybox/", 0) != 0 || f.size() <= 23) continue;
        std::string stem = f.substr(17, f.size() - 21);
        // Match "*up" (skip "*up_hdr" duplicates if base exists, or strip suffix cleanly)
        if (stem.size() > 2 && stem.substr(stem.size() - 2) == "up") {
            std::string sky = stem.substr(0, stem.size() - 2);
            if (sky.size() > 4 && sky.substr(sky.size() - 4) == "_hdr")
                sky.resize(sky.size() - 4);
            names.push_back(sky);
        }
    }
    std::sort(names.begin(), names.end());
    names.erase(std::unique(names.begin(), names.end()), names.end());
    for (const auto& n : names) out.push_back(toGodot(n));
    return out;
}

Dictionary Tf2Core::read_skybox_panorama(const String& skyname, int pano_width, int pano_height) const {
    Dictionary out;
    out["ok"] = false;
    if (!mounted_) return out;

    const std::string sky = toStd(skyname);
    // 0:ft(+Y) 1:bk(-Y) 2:lf(+X) 3:rt(-X) 4:up(+Z) 5:dn(-Z)
    static const char* kSuffix[6] = {"ft", "bk", "lf", "rt", "up", "dn"};
    pb::source::VtfImage faces[6];
    int loadedFaces = 0;

    for (int i = 0; i < 6; ++i) {
        const std::string matPath = "skybox/" + sky + kSuffix[i];
        pb::source::ResolvedMaterial rm = fs_.resolveMaterial(matPath);
        std::string tex = !rm.baseTexture.empty() ? rm.baseTexture : matPath;
        faces[i] = fs_.loadTexture(tex);
        if (!faces[i].ok()) {
            // Fallback to HDR variant if base face wasn't found
            const std::string hdrPath = "skybox/" + sky + "_hdr" + kSuffix[i];
            rm = fs_.resolveMaterial(hdrPath);
            tex = !rm.baseTexture.empty() ? rm.baseTexture : hdrPath;
            faces[i] = fs_.loadTexture(tex);
        }
        if (faces[i].ok()) ++loadedFaces;
    }
    if (loadedFaces < 4) return out;

    const int W = std::clamp(pano_width, 256, 4096);
    const int H = std::clamp(pano_height, 128, 2048);
    PackedByteArray rgba;
    rgba.resize(static_cast<int64_t>(W) * H * 4);
    uint8_t* dst = rgba.ptrw();

    auto sampleFace = [](const pb::source::VtfImage& img, float u, float v, uint8_t outPx[4]) {
        if (!img.ok()) {
            outPx[0] = 90; outPx[1] = 105; outPx[2] = 125; outPx[3] = 255;
            return;
        }
        u = std::clamp(u, 0.0f, 1.0f);
        v = std::clamp(v, 0.0f, 1.0f);
        const float fx = u * static_cast<float>(img.width - 1);
        const float fy = v * static_cast<float>(img.height - 1);
        const int x0 = static_cast<int>(fx);
        const int y0 = static_cast<int>(fy);
        const int x1 = std::min(x0 + 1, img.width - 1);
        const int y1 = std::min(y0 + 1, img.height - 1);
        const float tx = fx - x0;
        const float ty = fy - y0;
        const uint8_t* p00 = &img.rgba[(static_cast<size_t>(y0) * img.width + x0) * 4];
        const uint8_t* p10 = &img.rgba[(static_cast<size_t>(y0) * img.width + x1) * 4];
        const uint8_t* p01 = &img.rgba[(static_cast<size_t>(y1) * img.width + x0) * 4];
        const uint8_t* p11 = &img.rgba[(static_cast<size_t>(y1) * img.width + x1) * 4];
        for (int c = 0; c < 3; ++c) {
            const float a = p00[c] * (1.0f - tx) + p10[c] * tx;
            const float b = p01[c] * (1.0f - tx) + p11[c] * tx;
            outPx[c] = static_cast<uint8_t>(std::clamp(a * (1.0f - ty) + b * ty, 0.0f, 255.0f));
        }
        outPx[3] = 255;
    };

    constexpr float kPi = 3.14159265358979323846f;
    for (int y = 0; y < H; ++y) {
        const float theta = (static_cast<float>(y) + 0.5f) / static_cast<float>(H) * kPi;  // 0=zenith, pi=nadir
        const float sinT = std::sin(theta);
        const float cosT = std::cos(theta);
        for (int x = 0; x < W; ++x) {
            const float phi = ((static_cast<float>(x) + 0.5f) / static_cast<float>(W) - 0.5f) * 2.0f * kPi;
            // Godot PanoramaSky direction: Y up, -Z forward at phi=0
            const float gx = sinT * std::sin(phi);
            const float gy = cosT;
            const float gz = -sinT * std::cos(phi);

            // Convert Godot Y-up -> Source Z-up (sx = gx, sy = -gz, sz = gy)
            const float sx = gx;
            const float sy = -gz;
            const float sz = gy;
            const float ax = std::fabs(sx);
            const float ay = std::fabs(sy);
            const float az = std::fabs(sz);

            // Exact Quake/Source Engine skybox cubemap convention (ft -> lf -> bk -> rt clockwise):
            // 0:ft(+Y) 1:bk(-Y) 2:lf(+X) 3:rt(-X) 4:up(+Z) 5:dn(-Z)
            int faceIdx = 0;
            float u = 0.5f, v = 0.5f;
            if (ay >= ax && ay >= az) {
                if (sy > 0.0f) {  // ft (+Y): right = +X (connects to lf)
                    faceIdx = 0;
                    u = 0.5f * (sx / ay + 1.0f);
                    v = 0.5f * (-sz / ay + 1.0f);
                } else {          // bk (-Y): right = -X (connects to rt)
                    faceIdx = 1;
                    u = 0.5f * (-sx / ay + 1.0f);
                    v = 0.5f * (-sz / ay + 1.0f);
                }
            } else if (ax >= ay && ax >= az) {
                if (sx > 0.0f) {  // lf (+X): right = -Y (connects to bk)
                    faceIdx = 2;
                    u = 0.5f * (-sy / ax + 1.0f);
                    v = 0.5f * (-sz / ax + 1.0f);
                } else {          // rt (-X): right = +Y (connects to ft)
                    faceIdx = 3;
                    u = 0.5f * (sy / ax + 1.0f);
                    v = 0.5f * (-sz / ax + 1.0f);
                }
            } else {
                if (sz > 0.0f) {  // up (+Z)
                    faceIdx = 4;
                    u = 0.5f * (sx / az + 1.0f);
                    v = 0.5f * (sy / az + 1.0f);
                } else {          // dn (-Z)
                    faceIdx = 5;
                    u = 0.5f * (sx / az + 1.0f);
                    v = 0.5f * (-sy / az + 1.0f);
                }
            }

            uint8_t px[4];
            sampleFace(faces[faceIdx], u, v, px);
            uint8_t* o = dst + (static_cast<size_t>(y) * W + x) * 4;
            o[0] = px[0]; o[1] = px[1]; o[2] = px[2]; o[3] = 255;
        }
    }

    out["ok"] = true;
    out["skyname"] = skyname;
    out["faces_loaded"] = loadedFaces;
    out["width"] = W;
    out["height"] = H;
    out["rgba"] = rgba;
    return out;
}

Dictionary Tf2Core::load_bsp_data(const String& bsp_path) {
    Dictionary out;
    out["ok"] = false;
    if (!mounted_) return out;

    std::string path = toStd(bsp_path);
    // Allow shorthand map names like "koth_sawmill" or "koth_sawmill.bsp"
    if (!pb::fileExists(path) && !tf2_dir_.empty()) {
        std::string cand = tf2_dir_ + "/tf/maps/" + path;
        if (cand.size() < 4 || cand.substr(cand.size() - 4) != ".bsp") cand += ".bsp";
        if (pb::fileExists(cand)) path = cand;
    }

    pb::bsp::BspFile bsp;
    std::string err;
    if (!bsp.load(path, &err)) {
        out["error"] = toGodot(err.empty() ? ("Failed to open BSP: " + path) : err);
        return out;
    }

    // Mount embedded BSP Pakfile ZIP (Lump 40) so map-packed textures & _wvt_patch resolve!
    fs_.clearBspPak();
    size_t pakEntries = 0;
    const uint8_t* pakPtr = nullptr;
    size_t pakSize = 0;
    if (bsp.lumpBytes(pb::bsp::LUMP_PAKFILE, pakPtr, pakSize) && pakPtr && pakSize > 0) {
        pakEntries = fs_.mountBspPak(pakPtr, pakSize);
    }

    pb::bsp::MeshBuildOptions mopts;
    mopts.bakeProps = false;  // Godot instances static props via MultiMeshInstance3D!
    mopts.includeSky = false;
    mopts.includeTriggers = false;
    const pb::bsp::WorldMesh mesh = pb::bsp::buildWorldMesh(bsp, mopts);

    constexpr float kInvUpm = 1.0f / 32.0f;
    auto toGodotPos = [](const glm::vec3& p) {
        return Vector3(p.x * kInvUpm, p.z * kInvUpm, -p.y * kInvUpm);
    };
    auto toGodotNrm = [](const glm::vec3& n) {
        return Vector3(n.x, n.z, -n.y);
    };

    // Build per-material Godot ArrayMesh surface buffers + solid world collision triangle soup
    Array surfaces;
    PackedVector3Array colFaces;
    colFaces.resize(0);

    for (const auto& b : mesh.batches) {
        if (b.indexCount < 3 || b.firstIndex + b.indexCount > mesh.indices.size()) continue;
        if (b.material.rfind("tools/", 0) == 0) continue;

        PackedVector3Array verts;
        PackedVector3Array norms;
        PackedVector2Array uvs;
        PackedVector2Array uv2s;
        PackedColorArray colors;
        PackedInt32Array inds;
        std::unordered_map<uint32_t, int32_t> remap;
        remap.reserve(b.indexCount);

        auto addVert = [&](uint32_t srcIdx) -> int32_t {
            auto it = remap.find(srcIdx);
            if (it != remap.end()) return it->second;
            const int32_t dstIdx = static_cast<int32_t>(verts.size());
            const auto& v = mesh.vertices[srcIdx];
            verts.push_back(toGodotPos(v.pos));
            norms.push_back(toGodotNrm(v.normal));
            uvs.push_back(Vector2(v.texUv.x, v.texUv.y));
            uv2s.push_back(Vector2(v.uv.x, v.uv.y));
            colors.push_back(Color(v.tint.r, v.tint.g, v.tint.b, 1.0f));
            remap.emplace(srcIdx, dstIdx);
            return dstIdx;
        };

        const bool addCollision = !b.translucent && b.material.find("water") == std::string::npos;
        for (uint32_t k = 0; k + 2 < b.indexCount; k += 3) {
            const uint32_t a = mesh.indices[b.firstIndex + k + 0];
            const uint32_t bb = mesh.indices[b.firstIndex + k + 1];
            const uint32_t c = mesh.indices[b.firstIndex + k + 2];
            if (a >= mesh.vertices.size() || bb >= mesh.vertices.size() || c >= mesh.vertices.size())
                continue;
            const int32_t ia = addVert(a);
            const int32_t ib = addVert(bb);
            const int32_t ic = addVert(c);
            // BspMesh emits OpenGL CCW faces; swap to Godot CW outward winding (ia, ic, ib)
            inds.push_back(ia);
            inds.push_back(ic);
            inds.push_back(ib);
            if (addCollision) {
                colFaces.push_back(verts[ia]);
                colFaces.push_back(verts[ic]);
                colFaces.push_back(verts[ib]);
            }
        }
        if (inds.is_empty()) continue;

        Dictionary surf;
        surf["material"] = toGodot(b.material);
        surf["translucent"] = b.translucent;
        surf["vertices"] = verts;
        surf["normals"] = norms;
        surf["uvs"] = uvs;
        surf["uv2s"] = uv2s;
        surf["colors"] = colors;
        surf["indices"] = inds;
        surfaces.push_back(surf);
    }

    // Group LZMA static props by .mdl path with exact Source->Godot Transform3D for MultiMeshInstance3D!
    std::unordered_map<std::string, Array> propMap;
    for (const auto& pr : mesh.props) {
        if (pr.model.empty()) continue;
        const float yaw = glm::radians(pr.anglesPYR.y);
        const float pit = glm::radians(pr.anglesPYR.x);
        const float rol = glm::radians(pr.anglesPYR.z);
        const glm::mat3 R =
            glm::mat3(glm::rotate(glm::mat4(1.0f), yaw, glm::vec3(0, 0, 1))) *
            glm::mat3(glm::rotate(glm::mat4(1.0f), pit, glm::vec3(0, 1, 0))) *
            glm::mat3(glm::rotate(glm::mat4(1.0f), rol, glm::vec3(1, 0, 0)));
        const float sc = (pr.scale > 0.01f) ? pr.scale : 1.0f;

        // Exact similarity transform G = P * R * P^-1 into Godot Y-up basis
        const Vector3 bx = toGodotNrm(R * glm::vec3(1, 0, 0)) * sc;
        const Vector3 by = toGodotNrm(R * glm::vec3(0, 0, 1)) * sc;
        const Vector3 bz = toGodotNrm(R * glm::vec3(0, -1, 0)) * sc;
        const Basis basis(bx, by, bz);
        const Transform3D xf(basis, toGodotPos(pr.pos));
        propMap[pr.model].push_back(xf);
    }
    Dictionary propGroups;
    for (auto& [mdlPath, arr] : propMap) {
        propGroups[toGodot(mdlPath)] = arr;
    }

    // Extract skyname from worldspawn + point entities
    std::string skyname = "sky_tf2_04";
    if (const auto* ws = bsp.worldspawn()) {
        auto it = ws->find("skyname");
        if (it != ws->end() && !it->second.empty()) skyname = it->second;
    }

    Array entities;
    for (const auto& kv : bsp.entities()) {
        auto ci = kv.find("classname");
        if (ci == kv.end()) continue;
        Dictionary ed;
        ed["classname"] = toGodot(ci->second);
        auto ti = kv.find("targetname");
        if (ti != kv.end()) ed["targetname"] = toGodot(ti->second);
        auto tm = kv.find("TeamNum");
        if (tm != kv.end()) ed["team"] = toGodot(tm->second);
        auto oi = kv.find("origin");
        if (oi != kv.end()) {
            glm::vec3 org(0.0f);
            if (std::sscanf(oi->second.c_str(), "%f %f %f", &org.x, &org.y, &org.z) == 3) {
                ed["pos"] = toGodotPos(org);
            }
        }
        entities.push_back(ed);
    }

    PackedByteArray lmBytes;
    if (!mesh.lightmapAtlas.empty()) {
        lmBytes.resize(static_cast<int64_t>(mesh.lightmapAtlas.size()));
        std::memcpy(lmBytes.ptrw(), mesh.lightmapAtlas.data(), mesh.lightmapAtlas.size());
    }

    const Vector3 b0 = toGodotPos(mesh.boundsMin);
    const Vector3 b1 = toGodotPos(mesh.boundsMax);
    const Vector3 p0 = toGodotPos(mesh.playBoundsMin);
    const Vector3 p1 = toGodotPos(mesh.playBoundsMax);

    out["ok"] = true;
    out["name"] = toGodot(bsp.name());
    out["path"] = toGodot(path);
    out["version"] = bsp.version();
    out["skyname"] = toGodot(skyname);
    out["pak_entries"] = static_cast<int64_t>(pakEntries);
    out["drawn_faces"] = static_cast<int64_t>(mesh.drawnFaces);
    out["surface_count"] = surfaces.size();
    out["prop_count"] = static_cast<int64_t>(mesh.props.size());
    out["unique_prop_models"] = propGroups.size();
    out["entity_count"] = entities.size();
    out["bounds_min"] = Vector3(std::min(b0.x, b1.x), std::min(b0.y, b1.y), std::min(b0.z, b1.z));
    out["bounds_max"] = Vector3(std::max(b0.x, b1.x), std::max(b0.y, b1.y), std::max(b0.z, b1.z));
    out["play_bounds_min"] = Vector3(std::min(p0.x, p1.x), std::min(p0.y, p1.y), std::min(p0.z, p1.z));
    out["play_bounds_max"] = Vector3(std::max(p0.x, p1.x), std::max(p0.y, p1.y), std::max(p0.z, p1.z));
    out["has_spawn"] = mesh.hasSpawn;
    out["spawn_pos"] = toGodotPos(mesh.spawnPos);
    out["spawn_yaw"] = mesh.spawnYaw;
    out["lightmap_width"] = mesh.lightmapWidth;
    out["lightmap_height"] = mesh.lightmapHeight;
    out["lightmap_rgb"] = lmBytes;
    out["surfaces"] = surfaces;
    out["collision_faces"] = colFaces;
    out["prop_groups"] = propGroups;
    out["entities"] = entities;
    return out;
}

}  // namespace godot
