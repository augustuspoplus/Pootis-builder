#include "gdext/Tf2Compiler.h"

#include <cstdio>
#include <fstream>
#include <string>

#include <godot_cpp/core/class_db.hpp>

#include "decompile/BspSource.h"

namespace godot {

namespace {
std::string toStd(const String& s) {
    CharString utf8 = s.utf8();
    return std::string(utf8.get_data(), static_cast<size_t>(utf8.length()));
}
String toGodot(const std::string& s) {
    return String::utf8(s.c_str(), static_cast<int64_t>(s.size()));
}
}  // namespace

void Tf2Compiler::_bind_methods() {
    ClassDB::bind_method(D_METHOD("detect_paths"), &Tf2Compiler::detect_paths);
    ClassDB::bind_method(D_METHOD("start_compile", "vmf_path", "fast_profile", "run_vvis",
                                  "run_vrad", "launch_tf2", "map_name"),
                         &Tf2Compiler::start_compile,
                         DEFVAL(true), DEFVAL(true), DEFVAL(true), DEFVAL(false), DEFVAL(String()));
    ClassDB::bind_method(D_METHOD("cancel"), &Tf2Compiler::cancel);
    ClassDB::bind_method(D_METHOD("poll"), &Tf2Compiler::poll);
    ClassDB::bind_method(D_METHOD("read_leak_points", "lin_path"), &Tf2Compiler::read_leak_points);
    ClassDB::bind_method(D_METHOD("decompile_bsp", "repo_root", "bsp_path"), &Tf2Compiler::decompile_bsp);
}

Dictionary Tf2Compiler::detect_paths() const {
    const auto p = pb::compile::GamePaths::detect();
    Dictionary out;
    out["valid"] = p.valid();
    out["bin_dir"] = toGodot(p.binDir);
    out["game_dir"] = toGodot(p.gameDir);
    out["exe"] = toGodot(p.exe);
    return out;
}

bool Tf2Compiler::start_compile(const String& vmf_path, bool fast_profile,
                                bool run_vvis, bool run_vrad,
                                bool launch_tf2, const String& map_name) {
    const auto paths = pb::compile::GamePaths::detect();
    if (!paths.valid()) return false;
    pb::compile::CompileOptions opts;
    opts.profile = fast_profile ? pb::compile::Profile::Fast : pb::compile::Profile::Final;
    opts.runVvis = run_vvis;
    opts.runVrad = run_vrad;
    opts.launchGame = launch_tf2;
    opts.mapName = toStd(map_name);
    compiler_.start(toStd(vmf_path), opts, paths);
    return true;
}

void Tf2Compiler::cancel() { compiler_.cancel(); }

Dictionary Tf2Compiler::poll() {
    compiler_.poll();
    Dictionary out;
    out["running"] = compiler_.running();
    out["finished"] = compiler_.finished();
    out["succeeded"] = compiler_.succeeded();
    out["launched"] = compiler_.launched();
    out["stage"] = toGodot(compiler_.stage());
    out["map_name"] = toGodot(compiler_.mapName());
    out["elapsed"] = compiler_.elapsedSeconds();
    out["leak_file"] = toGodot(compiler_.leakFile());

    PackedStringArray lines;
    for (const auto& l : compiler_.log()) lines.push_back(toGodot(l));
    out["log"] = lines;
    return out;
}

PackedVector3Array Tf2Compiler::read_leak_points(const String& lin_path) const {
    PackedVector3Array pts;
    std::ifstream is(toStd(lin_path));
    if (!is) return pts;
    std::string line;
    constexpr float kInvUpm = 1.0f / 32.0f;
    while (std::getline(is, line)) {
        float x = 0, y = 0, z = 0;
        if (std::sscanf(line.c_str(), "%f %f %f", &x, &y, &z) == 3) {
            pts.push_back(Vector3(x * kInvUpm, z * kInvUpm, -y * kInvUpm));
        }
    }
    return pts;
}

Dictionary Tf2Compiler::decompile_bsp(const String& repo_root, const String& bsp_path) const {
    Dictionary out;
    std::string err, log;
    const std::string vmf = pb::decompile::bspToVmf(toStd(repo_root), toStd(bsp_path), &err, &log);
    out["ok"] = !vmf.empty();
    out["vmf_path"] = toGodot(vmf);
    out["error"] = toGodot(err);
    out["log"] = toGodot(log);
    return out;
}

}  // namespace godot
