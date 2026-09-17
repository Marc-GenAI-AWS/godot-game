class_name StreetWalkerLayer
extends SkinnedPlayerLayer

# On-foot street player: the male CC0 base in a blue shirt and dark jeans
# (car-entry reference), starting on the right-hand sidewalk. Same controls
# as the beach walker.


func _init() -> void:
	body_scene = "res://segments/characters/assets/Superhero_Male_FullBody.gltf"
	hair_scene = "res://segments/characters/assets/Hair_SimpleParted.gltf"
	body_mesh_name = "SuperHero_Male"
	hair_mesh_names = ["Hair_SimpleParted", "Eyebrows"]
	painted_texture = "res://segments/characters/assets/T_M_shirt_blue_jeans.png"
	normal_texture = "res://segments/characters/assets/T_Superhero_Male_Normal.png"
	extend_hair = false
	hair_tint = Color(0.16, 0.11, 0.08)


func build() -> void:
	super()
	# The base class already honours ctx.player_pos; only the street knows where its sidewalk is,
	# and in a world that is not the street (the coast) there is none to stand on.
	var sc: StreetContext = ctx as StreetContext
	if sc != null and ctx.player_pos == Vector3.ZERO:
		body.position = Vector3(sc.WALK_OUT - 1.4, sc.KERB_H, -3.0)
	pace = 0
	walking = false
	anim.play("Idle")
	anim.speed_scale = 1.0
