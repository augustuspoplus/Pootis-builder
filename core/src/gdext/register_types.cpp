#include "gdext/register_types.h"

#include <gdextension_interface.h>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "gdext/Tf2Compiler.h"
#include "gdext/Tf2Core.h"
#include "gdext/Tf2MapDoc.h"

using namespace godot;

void initialize_pootis_core_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
    ClassDB::register_class<Tf2Core>();
    ClassDB::register_class<Tf2MapDoc>();
    ClassDB::register_class<Tf2Compiler>();
}

void uninitialize_pootis_core_module(ModuleInitializationLevel p_level) {
    if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) {
        return;
    }
}

extern "C" {
GDExtensionBool GDE_EXPORT pootis_core_library_init(
    GDExtensionInterfaceGetProcAddress p_get_proc_address,
    const GDExtensionClassLibraryPtr p_library,
    GDExtensionInitialization* r_initialization) {
    godot::GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
    init_obj.register_initializer(initialize_pootis_core_module);
    init_obj.register_terminator(uninitialize_pootis_core_module);
    init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init_obj.init();
}
}
