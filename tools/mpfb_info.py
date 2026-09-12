import bpy, importlib, sys, os, json, addon_utils
bpy.ops.wm.read_factory_settings(use_empty=True)
for m in addon_utils.modules():
    if "mpfb" in m.__name__: addon_utils.enable(m.__name__, default_set=True)
def dynamic_import(p, k):
    for amod in list(sys.modules):
        if amod.endswith(p): return getattr(importlib.import_module(amod), k)
LocationService = dynamic_import("mpfb.services.locationservice", "LocationService")
print("USERDATA", LocationService.get_user_data())
print("USERCONFIG", LocationService.get_user_config())
print("MPFBDATA", LocationService.get_mpfb_data())
tj = os.path.join(LocationService.get_mpfb_data("targets"), "target.json")
meta = json.load(open(tj))
for section in sorted(meta):
    for cat in meta[section].get("categories", []):
        names = cat.get("targets", [])
        if any(k in section.lower() or k in cat["name"].lower() for k in ["hip", "waist", "buttock", "breast", "torso", "stomach", "pelvis", "legs", "upper leg", "thigh", "shoulder"]):
            print("TARGETS", section, "/", cat["name"], ":", names)
