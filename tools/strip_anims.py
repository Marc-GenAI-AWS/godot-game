import bpy, sys
src = "/home/marc/dev/graphics-gen/assets/ual/pack/godot/UAL1_Standard.glb"
dst = "/home/marc/dev/graphics-gen/assets/ual_walk.glb"
keep = {"Walk_Loop", "Idle_Loop", "Walk_Formal_Loop", "Jog_Fwd_Loop", "A_TPose"}
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
for a in list(bpy.data.actions):
    if a.name not in keep:
        bpy.data.actions.remove(a)
# drop the mannequin mesh; keep only the armature so the file is tiny
for o in list(bpy.data.objects):
    if o.type == "MESH":
        bpy.data.objects.remove(o, do_unlink=True)
print("actions kept:", [a.name for a in bpy.data.actions])
bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", export_animations=True, export_animation_mode="ACTIONS", export_skins=True, export_apply=False)
