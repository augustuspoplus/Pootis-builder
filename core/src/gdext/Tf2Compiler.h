#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include "compile/MapCompiler.h"

namespace godot {

// Native C++20 TF2 Map Compiler (vbsp / vvis / vrad / tf_win64), Leak Pointfile (.lin)
// Parser, and BSPSource Decompiler bridge for Godot 4.
class Tf2Compiler : public RefCounted {
    GDCLASS(Tf2Compiler, RefCounted)

protected:
    static void _bind_methods();

public:
    Tf2Compiler() = default;
    ~Tf2Compiler() override = default;

    Dictionary detect_paths() const;
    bool start_compile(const String& vmf_path, bool fast_profile = true,
                       bool run_vvis = true, bool run_vrad = true,
                       bool launch_tf2 = false, const String& map_name = String());
    void cancel();
    Dictionary poll();

    // Reads a vbsp leak .lin pointfile into Godot Y-up 3D polyline points for the 3D Leak Laser!
    PackedVector3Array read_leak_points(const String& lin_path) const;

    // Decompiles an official .bsp to an editable .vmf via bundled BSPSource (if installed).
    Dictionary decompile_bsp(const String& repo_root, const String& bsp_path) const;

private:
    pb::compile::MapCompiler compiler_;
};

}  // namespace godot
