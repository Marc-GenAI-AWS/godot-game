class_name SkinnedPlayerLayer
extends PlayerLayer

# Route-1 player: a CC0 rigged body (Quaternius Universal Base Characters)
# driven by the CC0 Universal Animation Library walk, wearing our painted
# crop top / denim texture. Same interface as PlayerLayer so the camera,
# tracks and HUD layers don't care which one is active.

const ANIM_SCENE := "res://characters/assets/ual_walk.glb"
const ANIM_WALK_SPEED := 0.975      # m/s the Walk clip covers at speed 1 (measured)
const STEP_L := 0.25                # foot-contact times inside the Walk clip (s)
const STEP_R := 0.667

# Configuration (a subclass can change these in _init before build runs).
var body_scene := "res://characters/assets/Superhero_Female_FullBody.gltf"
var hair_scene := "res://characters/assets/Hair_Long.gltf"   # "" = none
var body_mesh_name := "Superhero_Female"
var hair_mesh_names: Array[String] = ["Hair_Long", "Eyebrows"]
var painted_texture := "res://characters/assets/T_Player_BaseColor.png"
var normal_texture := "res://characters/assets/T_Superhero_Female_Normal.png"   # "" = none
var facing_flip := true             # model faces +Z; our world walks toward -Z
var extend_hair := true             # add ribbon strands under the stock hair
var hair_tint := Color(0.55, 0.36, 0.22)

var body: Node3D
var skel: Skeleton3D
var anim: AnimationPlayer
var last_anim_t := -1.0
# Locomotion: 0 = stopped, 1 = walk, 2 = jog. Space jumps.
var pace := 1
var jog_speed := 4.0
const JOG_CLIP_SPEED := 5.26      # m/s the Jog_Fwd clip covers at speed 1 (measured)
const JOG_STEP_L := 0.04
const JOG_STEP_R := 0.5
var vy := 0.0
var airborne := false
var landing_t := 0.0
var jump_t := 0.0
var _press_pos := Vector2.ZERO
var foot_l := -1
var foot_r := -1
var hair_pivot: Node3D
var hair_pivot2: Node3D


func build() -> void:
	body = (load(body_scene) as PackedScene).instantiate()
	body.name = "Player"
	skel = body.find_child("*Skeleton*", true, false) as Skeleton3D
	if skel == null:
		skel = body.find_child("GeneralSkeleton", true, false) as Skeleton3D
	if facing_flip:
		(skel.get_parent() as Node3D).rotation.y = PI

	# Long hair: a mesh skinned to the same rig, just re-parented to our skeleton.
	if hair_scene != "":
		var hs: Node3D = (load(hair_scene) as PackedScene).instantiate()
		var hair_mesh: MeshInstance3D = hs.find_child(hair_mesh_names[0], true, false)
		hair_mesh.owner = null
		hair_mesh.get_parent().remove_child(hair_mesh)
		skel.add_child(hair_mesh)
		hair_mesh.skeleton = NodePath("..")
		hs.free()

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
	if extend_hair:
		_extend_hair()

	body.position = Vector3(-4.5, ctx.sand_height(-4.5, 0.0), 0.0)
	add_child(body)
	ctx.player = body
	player = null
	foot_l = skel.find_bone("LeftFoot") if skel.find_bone("LeftFoot") >= 0 else skel.find_bone("foot_l")
	foot_r = skel.find_bone("RightFoot") if skel.find_bone("RightFoot") >= 0 else skel.find_bone("foot_r")
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
	var mesh: MeshInstance3D = skel.get_node(body_mesh_name)
	var skin := ShaderMaterial.new()
	skin.shader = load("res://shaders/skin.gdshader")
	skin.set_shader_parameter("albedo_tex", load(painted_texture))
	if normal_texture != "":
		skin.set_shader_parameter("normal_tex", load(normal_texture))
		skin.set_shader_parameter("normal_strength", 1.0)
	skin.set_shader_parameter("ao_ends", 0.0)
	skin.set_shader_parameter("sheen", 0.025)
	mesh.set_surface_override_material(0, skin)

	for n in hair_mesh_names:
		var mi: MeshInstance3D = skel.get_node_or_null(n)
		if mi == null:
			continue
		# keep the imported textures, tint and make it double sided / alpha-cut
		var src := mi.mesh.surface_get_material(0)
		var hair_mat: StandardMaterial3D = src.duplicate() if src is StandardMaterial3D else StandardMaterial3D.new()
		hair_mat.albedo_color = hair_tint
		hair_mat.roughness = 0.55
		hair_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if hair_mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			hair_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			hair_mat.alpha_scissor_threshold = 0.5
		mi.set_surface_override_material(0, hair_mat)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_UP, KEY_W:
				pace = mini(pace + 1, 2)
			KEY_DOWN, KEY_S:
				pace = maxi(pace - 1, 0)
			KEY_SPACE:
				_jump()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_pos = event.position
		elif event.position.distance_to(_press_pos) < 8.0:
			pace = 1 if pace == 0 else 0
	elif event is InputEventScreenTouch:
		if event.pressed:
			_press_pos = event.position
		elif event.position.distance_to(_press_pos) < 12.0:
			pace = 1 if pace == 0 else 0
	walking = pace > 0


func _jump() -> void:
	if airborne or landing_t > 0.0:
		return
	airborne = true
	vy = 3.4
	jump_t = 0.0
	anim.play("Jump_Start", 0.1)
	anim.speed_scale = 2.2


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

	walking = pace > 0
	var speed := 0.0 if pace == 0 else (WALK_SPEED if pace == 1 else jog_speed)
	var ground := ctx.sand_height(body.position.x, body.position.z)
	if airborne:
		# ballistic arc; keep forward momentum
		jump_t += delta
		vy -= 9.8 * delta
		var p := body.position + forward() * (0.0 if ctx.inspect else speed) * delta
		p.x = clampf(p.x, -50.0, 1.2)
		p.y += vy * delta
		var g := ctx.sand_height(p.x, p.z)
		if jump_t > 0.35 and anim.current_animation != "Jump":
			anim.play("Jump", 0.15)
			anim.speed_scale = 1.0
		if vy < 0.0 and p.y <= g:
			p.y = g
			airborne = false
			landing_t = 0.32
			anim.play("Jump_Land", 0.08)
			anim.speed_scale = 2.4
		body.position = p
	else:
		if landing_t > 0.0:
			landing_t -= delta
		else:
			var want := "Idle" if pace == 0 else ("Walk" if pace == 1 else "Jog_Fwd")
			if anim.current_animation != want:
				anim.play(want, 0.3)
			anim.speed_scale = 1.0 if pace == 0 else (WALK_SPEED / ANIM_WALK_SPEED if pace == 1 else jog_speed / JOG_CLIP_SPEED)
		if speed > 0.0 and not ctx.inspect:
			var p := body.position + forward() * speed * (0.5 if landing_t > 0.0 else 1.0) * delta
			p.x = clampf(p.x, -50.0, 1.2)
			p.y = ctx.sand_height(p.x, p.z)
			body.position = p
		else:
			body.position.y = ground
	if walking and not airborne:
		_emit_steps_from_clip()
		ctx.player_phase = anim.current_animation_position / maxf(anim.current_animation_length, 0.01) * TAU
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
	var clip := anim.current_animation
	if clip != "Walk" and clip != "Jog_Fwd":
		last_anim_t = -1.0
		return
	var sl := STEP_L if clip == "Walk" else JOG_STEP_L
	var sr := STEP_R if clip == "Walk" else JOG_STEP_R
	var t := anim.current_animation_position
	if last_anim_t >= 0.0:
		for pair in [[sl, foot_l, -1], [sr, foot_r, 1]]:
			var st: float = pair[0]
			var crossed := (last_anim_t < st and t >= st) or (t < last_anim_t and (last_anim_t < st or t >= st))
			if crossed and pair[1] >= 0:
				var world := skel.global_transform * skel.get_bone_global_pose(pair[1]).origin
				ctx.player_step.emit(world, pair[2], yaw)
	last_anim_t = t
