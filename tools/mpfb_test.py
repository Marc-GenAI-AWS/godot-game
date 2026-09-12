import bpy, importlib, sys, os
bpy.ops.wm.read_factory_settings(use_empty=True)
def dynamic_import(absolute_package_str, key):
    for amod in list(sys.modules):
        if amod.endswith(absolute_package_str):
            m = importlib.import_module(amod)
            return getattr(m, key)
    raise ValueError("No module " + absolute_package_str)
# make sure the extension is enabled in this session
import addon_utils
for m in addon_utils.modules():
    if "mpfb" in m.__name__:
        print("found addon module", m.__name__)
        addon_utils.enable(m.__name__, default_set=True)
HumanService = dynamic_import("mpfb.services.humanservice", "HumanService")
TargetService = dynamic_import("mpfb.services.targetservice", "TargetService")
HumanObjectProperties = dynamic_import("mpfb.entities.objectproperties", "HumanObjectProperties")
h = HumanService.create_human()
HumanObjectProperties.set_value("gender", 1.0, entity_reference=h)
TargetService.reapply_macro_details(h)
rig = HumanService.add_builtin_rig(h, "game_engine")
print("rig bones:", len(rig.data.bones), [b.name for b in rig.data.bones][:12])
print("mesh verts:", len(h.data.vertices))
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath="/home/marc/dev/graphics-gen/assets/mpfb_test.glb", export_format="GLB", use_selection=True, export_animations=False)
print("EXPORTED")
