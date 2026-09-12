class_name SkinnedPlayerLayer
extends PlayerLayer

# Route-1 player: a CC0 rigged body (Quaternius Universal Base Characters)
# driven by the CC0 Universal Animation Library walk, wearing our painted
# crop top / denim texture. Same interface as PlayerLayer so the camera,
# tracks and HUD layers don't care which one is active.

const BODY_SCENE := "res://characters/assets/Superhero_Female_FullBody.gltf"
const HAIR_SCENE := "res://characters/assets/Hair_Long.gltf"
const ANIM_SCENE := "res://characters/assets/ual_walk.glb"
const ANIM_WALK_SPEED := 0.975      # m/s the Walk clip covers at speed 1 (measured)
const STEP_L := 0.25                # foot-contact times inside the Walk clip (s)
const STEP_R := 0.667
const FACING_FLIP := true           # model faces +Z; our world walks toward -Z

var body: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var last_anim_t := -1.0
var foot_l := -1
var foot_r := -1
var hair_pivot: Node3D
var hair_pivot2: Node3D


func build() -> void:
	body = (load(BODY_SCENE) as PackedScene).instantiate()
	body.name = "Player"
	skel = body.get_node("Armature/Skeleton3D")
	if FACING_FLIP:
		body.get_node("Armature").rotation.y = PI

	# Long hair: a mesh skinned to the same rig, just re-parented to our skeleton.
	var hair_scene: Node3D = (load(HAIR_SCENE) as PackedScene).instantiate()
	var hair_mesh: MeshInstance3D = hair_scene.get_node("Armature/Skeleton3D/Hair_Long")
	hair_mesh.owner = null
	hair_mesh.get_parent().remove_child(hair_mesh)
	skel.add_child(hair_mesh)
	hair_mesh.skeleton = NodePath("..")
	hair_scene.free()

	# Animation library from the trimmed UAL file (same skeleton, same paths).
	var ual: Node = (load(ANIM_SCENE) as PackedScene).instantiate()
	var src_ap: AnimationPlayer = ual.get_node("AnimationPlayer")
	anim = AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	body.add_child(anim)
	anim.add_animation_library("", src_ap.get_animation_library("").duplicate(true))
	ual.free()
	for a in ["Walk", "Idle", "Walk_Formal", "Jog_Fwd"]:
		if anim.has_animation(a):
			anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR

	_apply_materials()
	_extend_hair()

	body.position = Vector3(-4.5, ctx.sand_height(-4.5, 0.0), 0.0)
	add_child(body)
	ctx.player = body
	player = null
	foot_l = skel.find_bone("foot_l")
	foot_r = skel.find_bone("foot_r")
	anim.play("Walk")
	anim.speed_scale = WALK_SPEED / ANIM_WALK_SPEED


func _extend_hair() -> void:
	# The stock hairstyle stops at the shoulders; hang our ribbon strands from
	# the head bone so the hair reaches mid-back and swings with the walk.
	var att := BoneAttachment3D.new()
	att.bone_name = "Head"
	skel.add_child(att)
	if ctx.lite:
		return
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 0.02, 0.0)
	pivot.rotation.y = PI          # model's back is -Z locally; ribbons expect +Z
	att.add_child(pivot)
	hair_pivot = pivot
	hair_pivot2 = Node3D.new()
	hair_pivot2.position = Vector3(0, -0.2, 0.06)
	pivot.add_child(hair_pivot2)
	var mat := HairRibbons.strand_material(Color(0.3, 0.18, 0.1))
	# rear half only, rooted low at the nape so they emerge from under the stock hair
	HairRibbons.build(pivot, hair_pivot2, mat, 18, 6, 0.055, 0.075, -0.06, 5, 0.45, PI - 0.45, false)


func _apply_materials() -> void:
	var mesh: MeshInstance3D = skel.get_node("Superhero_Female")
	var skin := ShaderMaterial.new()
	skin.shader = load("res://shaders/skin.gdshader")
	skin.set_shader_parameter("albedo_tex", load("res://characters/assets/T_Player_BaseColor.png"))
	skin.set_shader_parameter("normal_tex", load("res://characters/assets/T_Superhero_Female_Normal.png"))
	skin.set_shader_parameter("normal_strength", 1.0)
	skin.set_shader_parameter("ao_ends", 0.0)
	skin.set_shader_parameter("sheen", 0.025)
	mesh.set_surface_override_material(0, skin)

	var hair_mat := StandardMaterial3D.new()
	hair_mat.albedo_texture = load("res://characters/assets/T_Hair_2_BaseColor.png")
	hair_mat.albedo_color = Color(0.55, 0.36, 0.22)
	hair_mat.normal_enabled = true
	hair_mat.normal_texture = load("res://characters/assets/T_Hair_2_Normal.png")
	hair_mat.roughness = 0.55
	hair_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for n in ["Hair_Long", "Eyebrows"]:
		var mi: MeshInstance3D = skel.get_node(n)
		mi.set_surface_override_material(0, hair_mat)


func tick(delta: float) -> void:
	var steer := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		steer += 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		steer -= 1.0
	yaw += steer * delta * 1.4
	if steer == 0.0:
		yaw = lerpf(yaw, 0.0, 1.0 - exp(-delta * 0.8))
	yaw = clampf(yaw, -0.9, 0.9)
	body.rotation.y = yaw

	var want := "Walk" if walking else "Idle"
	if anim.current_animation != want:
		anim.play(want, 0.35)
	if walking and not ctx.inspect:
		var p := body.position + forward() * WALK_SPEED * delta
		p.x = clampf(p.x, -50.0, 1.2)
		p.y = ctx.sand_height(p.x, p.z)
		body.position = p
	if walking:
		_emit_steps_from_clip()
		ctx.player_phase = anim.current_animation_position / anim.current_animation_length * TAU
	if hair_pivot:
		var p := ctx.player_phase
		hair_pivot.rotation.x = -0.04 + 0.05 * cos(2.0 * p - 0.9)
		hair_pivot.rotation.z = 0.08 * sin(p - 0.7)
		hair_pivot2.rotation.x = 0.06 * cos(2.0 * p - 1.7)
		hair_pivot2.rotation.z = 0.11 * sin(p - 1.5)

	if body.position.z < -WorldContext.CHUNK:
		body.position.z += WorldContext.CHUNK
		ctx.world_wrapped.emit(WorldContext.CHUNK)


func _emit_steps_from_clip() -> void:
	if anim.current_animation != "Walk":
		last_anim_t = -1.0
		return
	var t := anim.current_animation_position
	if last_anim_t >= 0.0:
		for pair in [[STEP_L, foot_l, -1], [STEP_R, foot_r, 1]]:
			var st: float = pair[0]
			var crossed := (last_anim_t < st and t >= st) or (t < last_anim_t and (last_anim_t < st or t >= st))
			if crossed and pair[1] >= 0:
				var world := skel.global_transform * skel.get_bone_global_pose(pair[1]).origin
				ctx.player_step.emit(world, pair[2], yaw)
	last_anim_t = t
