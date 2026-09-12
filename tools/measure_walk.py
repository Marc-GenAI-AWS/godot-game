import bpy, json
from mathutils import Vector
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath="/home/marc/dev/graphics-gen/assets/ual/pack/godot/UAL1_Standard_RM.glb")
arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
out = {}
for name in ["Walk_Loop", "Walk_Formal_Loop", "Idle_Loop", "Jog_Fwd_Loop"]:
    act = bpy.data.actions[name]
    arm.animation_data.action = act
    try:
        arm.animation_data.action_slot = act.slots[0]
    except Exception:
        pass
    f0, f1 = act.frame_range
    fps = bpy.context.scene.render.fps
    root_start = None; root_end = None
    lows = {"foot_l": [], "foot_r": []}
    for f in range(int(f0), int(f1) + 1):
        bpy.context.scene.frame_set(f)
        root = arm.matrix_world @ arm.pose.bones["root"].head
        if root_start is None: root_start = root.copy()
        root_end = root.copy()
        for b in lows:
            p = arm.matrix_world @ arm.pose.bones[b].head
            lows[b].append((f, p.z, p.y))
    dur = (f1 - f0) / fps
    dist = (root_end - root_start).length
    contacts = {}
    for b, arr in lows.items():
        zs = [z for _, z, _ in arr]
        fmin = min(arr, key=lambda t: t[1])[0]
        contacts[b] = {"min_frame": fmin, "min_t": (fmin - f0) / fps, "z_min": min(zs), "z_max": max(zs)}
    out[name] = {"frames": [f0, f1], "fps": fps, "duration": dur, "root_dist": dist, "speed": dist / dur if dur else 0, "contacts": contacts}
print("MEASURE " + json.dumps(out))
