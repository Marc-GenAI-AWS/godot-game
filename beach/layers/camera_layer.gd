class_name CameraLayer
extends BeachLayer

# Over-the-shoulder chase camera with a subtle step-synced bob.

var camera: Camera3D
var player_layer: PlayerLayer


func build() -> void:
	camera = Camera3D.new()
	camera.name = "ChaseCamera"
	camera.fov = 55.0
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
		var eye := p + Vector3(sin(a) * 2.6, 1.25, cos(a) * 2.6)
		camera.global_position = eye
		camera.look_at(p + Vector3(0, 0.95, 0), Vector3.UP)
		return
	var fwd := player_layer.forward()
	var right := player_layer.right()
	var target := p + right * 0.45 + Vector3(0, 1.55, 0) - fwd * 2.9
	target.y = maxf(target.y, ctx.sand_height(target.x, target.z) + 0.8)
	var k := 1.0 - exp(-delta * 4.0)
	camera.global_position = camera.global_position.lerp(target, k)
	var bob := 0.018 * sin(ctx.player_phase * 2.0)
	var sway := 0.012 * sin(ctx.player_phase)
	camera.global_position += Vector3(0, bob, 0) + right * sway
	camera.look_at(p + Vector3(0, 1.05, 0) + fwd * 2.2 + right * 0.25, Vector3.UP)
	camera.rotate_object_local(Vector3.FORWARD, 0.004 * sin(ctx.player_phase))


func on_world_wrapped(dz: float) -> void:
	camera.global_position.z += dz
