extends SceneTree

# Writes BoneMap resources that map UE-mannequin style bone names (used by
# the Quaternius animation library and MPFB's game_engine rig) onto Godot's
# SkeletonProfileHumanoid, so the importer can retarget between them.

func _init() -> void:
	var pairs := {
		"Root": "root", "Hips": "pelvis", "Spine": "spine_01", "Chest": "spine_02", "UpperChest": "spine_03",
		"Neck": "neck_01", "Head": "Head",
	}
	for side in [["Left", "l"], ["Right", "r"]]:
		var S: String = side[0]
		var s: String = side[1]
		pairs[S + "Shoulder"] = "clavicle_" + s
		pairs[S + "UpperArm"] = "upperarm_" + s
		pairs[S + "LowerArm"] = "lowerarm_" + s
		pairs[S + "Hand"] = "hand_" + s
		pairs[S + "ThumbMetacarpal"] = "thumb_01_" + s
		pairs[S + "ThumbProximal"] = "thumb_02_" + s
		pairs[S + "ThumbDistal"] = "thumb_03_" + s
		for f in [["Index", "index"], ["Middle", "middle"], ["Ring", "ring"], ["Little", "pinky"]]:
			pairs[S + f[0] + "Proximal"] = f[1] + "_01_" + s
			pairs[S + f[0] + "Intermediate"] = f[1] + "_02_" + s
			pairs[S + f[0] + "Distal"] = f[1] + "_03_" + s
		pairs[S + "UpperLeg"] = "thigh_" + s
		pairs[S + "LowerLeg"] = "calf_" + s
		pairs[S + "Foot"] = "foot_" + s
		pairs[S + "Toes"] = "ball_" + s
	for variant in [["ue", {}], ["mpfb", {"Head": "head", "Root": "Root"}]]:
		var bm := BoneMap.new()
		bm.profile = SkeletonProfileHumanoid.new()
		for k in pairs:
			var v: String = variant[1].get(k, pairs[k])
			bm.set_skeleton_bone_name(k, v)
		var path := "res://segments/characters/assets/bonemap_%s.tres" % variant[0]
		var err := ResourceSaver.save(bm, path)
		print("saved ", path, " err=", err, " Hips->", bm.get_skeleton_bone_name("Hips"), " Head->", bm.get_skeleton_bone_name("Head"))
	quit()
