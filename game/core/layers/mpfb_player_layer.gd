class_name MpfbPlayerLayer
extends SkinnedPlayerLayer

# Route-2 player: a parametric body generated headlessly in Blender with the
# open-source MPFB2 human generator (CC0 MakeHuman system assets), retargeted
# onto the same animation library by Godot's humanoid bone map.

func _init() -> void:
	body_scene = "res://core/characters/mpfb/mpfb_player.glb"
	hair_scene = ""
	body_mesh_name = "Human_export"
	hair_mesh_names = ["Human_long01_export", "Human_eyebrow001_export", "Human_eyelashes01_export"]
	painted_texture = "res://core/characters/mpfb/T_MPFB_BaseColor.png"
	normal_texture = ""
	extend_hair = false
	hair_tint = Color(0.95, 0.72, 0.5)
