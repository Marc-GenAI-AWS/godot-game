import bpy, importlib, sys, os, addon_utils
bpy.ops.wm.read_factory_settings(use_empty=True)
for m in addon_utils.modules():
    if "mpfb" in m.__name__: addon_utils.enable(m.__name__, default_set=True)
def dyn(p, k):
    for amod in list(sys.modules):
        if amod.endswith(p): return getattr(importlib.import_module(amod), k)
    raise ValueError(p)
HumanService = dyn("mpfb.services.humanservice", "HumanService")
TargetService = dyn("mpfb.services.targetservice", "TargetService")
AssetService = dyn("mpfb.services.assetservice", "AssetService")
ExportService = dyn("mpfb.services.exportservice", "ExportService")
ObjectService = dyn("mpfb.services.objectservice", "ObjectService")
LocationService = dyn("mpfb.services.locationservice", "LocationService")
HumanObjectProperties = dyn("mpfb.entities.objectproperties", "HumanObjectProperties")

h = HumanService.create_human()
macros = {"gender": 1.0, "age": 0.45, "muscle": 0.62, "weight": 0.5, "height": 0.55, "proportions": 0.7,
          "caucasian": 0.65, "african": 0.15, "asian": 0.2, "cupsize": 0.55, "firmness": 0.7}
for k, v in macros.items():
    try:
        HumanObjectProperties.set_value(k, v, entity_reference=h)
    except Exception as e:
        print("macro skip", k, e)
TargetService.reapply_macro_details(h)
troot = LocationService.get_mpfb_data("targets")
shape = [("hip", "hip-scale-horiz-incr", 0.55), ("buttocks", "buttocks-volume-incr", 0.5), ("hip", "hip-scale-depth-incr", 0.2),
         ("measure", "measure-waist-circ-decr", 0.45), ("legs", "l-upperleg-fat-incr", 0.15), ("legs", "r-upperleg-fat-incr", 0.15),
         ("torso", "torso-scale-horiz-decr", 0.1), ("pelvis", "pelvis-tone-incr", 0.3), ("stomach", "stomach-navel-in", 0.0)]
for sec, name, wgt in shape:
    p = os.path.join(troot, sec, name + ".target.gz")
    if os.path.exists(p) and wgt > 0:
        TargetService.load_target(h, p, weight=wgt); print("target", name, wgt)
    else:
        print("target missing", p)
skin = AssetService.find_asset_absolute_path("young_caucasian_female.mhmat", asset_subdir="skins")
print("skin", skin)
if skin: HumanService.set_character_skin(skin, h, skin_type="GAMEENGINE")
HumanService.add_builtin_rig(h, "game_engine")
for subdir, fname, atype in [("eyes", "low-poly.mhclo", "Eyes"), ("eyebrows", "eyebrow001.mhclo", "Eyebrows"), ("eyelashes", "eyelashes01.mhclo", "Eyelashes"), ("hair", "long01.mhclo", "Hair")]:
    p = AssetService.find_asset_absolute_path(fname, asset_subdir=subdir)
    print("asset", atype, p)
    if p: HumanService.add_mhclo_asset(p, h, asset_type=atype, material_type="GAMEENGINE")
root = ExportService.create_character_copy(h, name_suffix="_export")
bm = ObjectService.find_object_of_type_amongst_nearest_relatives(root, "Basemesh")
ExportService.bake_modifiers_remove_helpers(bm, bake_masks=True, bake_subdiv=False, remove_helpers=True, also_proxy=True)
bpy.ops.object.select_all(action="DESELECT")
root.select_set(True)
for c in ObjectService.get_list_of_children(root): c.select_set(True)
bpy.context.view_layer.objects.active = root
for img in bpy.data.images:
    if img.size[0] > 1024 and img.has_data:
        img.scale(1024, 1024)
        print("scaled", img.name)
out = "/home/marc/dev/graphics-gen/assets/mpfb_player.glb"
bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=True, export_animations=False, export_apply=True, export_image_format="AUTO")
print("EXPORTED", out, os.path.getsize(out))
