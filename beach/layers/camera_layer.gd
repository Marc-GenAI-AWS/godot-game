class_name CameraLayer
extends BeachLayer

# Chase camera directly behind the walker, centred, stabilised (no step bob).

var camera: Camera3D
var player_layer: PlayerLayer


func build() -> void:
	camera = Camera3D.new()
	camera.name = "ChaseCamera"
	camera.fov = 60.0
	camera.near = 0.1
	camera.far = 1500.0
	add_child(camera)
	camera.current = true
	ctx.camera = camera
	if ctx.player:
		camera.global_position = ctx.player.position + Vector3(0.6, 1.8, 3.8)


func tick(delta: float) -> void:
	if not player_layer:
		return
	var p := ctx.player.position
	if ctx.inspect:
		# Slow orbit at close range, eye level, for checking the character.
		var a := ctx.time * 0.35
		var centre := p + ctx.inspect_offset
		var r := 2.6 if ctx.inspect_offset == Vector3.ZERO else 5.5
		var eye := centre + Vector3(sin(a) * r, 1.25 if ctx.inspect_offset == Vector3.ZERO else 2.2, cos(a) * r)
		eye.y = maxf(eye.y, ctx.sand_height(eye.x, eye.z) + 0.6)
		camera.global_position = eye
		camera.look_at(centre + Vector3(0, 0.95 if ctx.inspect_offset == Vector3.ZERO else 0.5, 0), Vector3.UP)
		return
	var fwd := player_layer.forward()
	var right := player_layer.right()
	var target := p + Vector3(0, 1.55, 0) - fwd * 3.3
	target.y = maxf(target.y, ctx.sand_height(target.x, target.z) + 0.8)
	# Stabilised: follow the root smoothly with no step bob, sway or roll.
	var k := 1.0 - exp(-delta * 3.0)
	camera.global_position = camera.global_position.lerp(target, k)
	camera.look_at(p + Vector3(0, 0.88, 0) + fwd * 3.0, Vector3.UP)


func on_world_wrapped(dz: float) -> void:
	camera.global_position.z += dz
