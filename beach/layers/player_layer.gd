class_name PlayerLayer
extends BeachLayer

# The walker: builds the character, handles steering, emits footsteps and
# performs the seamless chunk wrap.

const WALK_SPEED := 1.6

var player: Humanoid
var yaw := 0.0
var walking := true
var last_phase := 0.0


func build() -> void:
	player = Humanoid.new()
	player.name = "Player"
	player.build(Color(0.72, 0.5, 0.36), Color(0.92, 0.45, 0.6), Color(0.42, 0.5, 0.68), Color(0.16, 0.1, 0.06), true, 1.0)
	player.position = Vector3(-4.5, ctx.sand_height(-4.5, 0.0), 0.0)
	add_child(player)
	ctx.player = player


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		walking = not walking
	elif (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
		walking = not walking


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func right() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))


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
	player.rotation.y = yaw

	if walking:
		var p := player.position + forward() * WALK_SPEED * delta
		p.x = clampf(p.x, -50.0, 1.2)
		p.y = ctx.sand_height(p.x, p.z)
		player.position = p
		player.pose_walk(delta, WALK_SPEED)
		_emit_steps()
	else:
		player.pose_idle()
	ctx.player_phase = player.phase

	if player.position.z < -WorldContext.CHUNK:
		player.position.z += WorldContext.CHUNK
		ctx.world_wrapped.emit(WorldContext.CHUNK)


func _emit_steps() -> void:
	# Left foot plants as its swing peaks forward (phase = π/2), right at 3π/2.
	var a := fmod(last_phase, TAU)
	var b := fmod(player.phase, TAU)
	if b < a:
		b += TAU
	for side_phase in [[PI * 0.5, -1], [PI * 1.5, 1]]:
		var target: float = side_phase[0]
		var side: int = side_phase[1]
		if (a < target and b >= target) or (a < target + TAU and b >= target + TAU):
			var pos := player.position + right() * (side * 0.1) + forward() * 0.32
			ctx.player_step.emit(pos, side, yaw)
	last_phase = player.phase
