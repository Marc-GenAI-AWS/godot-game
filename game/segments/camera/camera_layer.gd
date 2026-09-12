class_name CameraLayer
extends SceneLayer

# Chase camera directly behind the walker, centred, stabilised (no step bob).

var camera: Camera3D
var player_layer: PlayerLayer
# Drag-orbit: hold the mouse / a finger and drag to look around the walker.
var orbit_yaw := 0.0
var orbit_pitch := 0.16
const PITCH_DEFAULT := 0.16
var dragging := false


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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
	elif event is InputEventScreenTouch:
		dragging = event.pressed
	elif dragging and (event is InputEventMouseMotion or event is InputEventScreenDrag):
		orbit_yaw -= event.relative.x * 0.006
		orbit_pitch = clampf(orbit_pitch + event.relative.y * 0.004, -0.15, 1.1)


func tick(delta: float) -> void:
	if not player_layer:
		return
	var p := ctx.player.position
	if ctx.inspect:
		# Slow orbit at close range, eye level, for checking the character.
		var a := ctx.time * 0.35
		var centre := p + ctx.inspect_offset
		var r := 2.6 if ctx.inspect_offset == Vector3.ZERO else 3.4
		var eye := centre + Vector3(sin(a) * r, 1.25 if ctx.inspect_offset == Vector3.ZERO else 1.5, cos(a) * r)
		eye.y = maxf(eye.y, ctx.ground_height(eye.x, eye.z) + 0.6)
		camera.global_position = eye
		camera.look_at(centre + Vector3(0, 0.95 if ctx.inspect_offset == Vector3.ZERO else 0.5, 0), Vector3.UP)
		return
	var fwd := player_layer.forward()
	# Ease back behind her while she moves; hold the angle while she stands.
	if not dragging and player_layer.walking:
		var e := 1.0 - exp(-delta * 1.2)
		orbit_yaw = lerp_angle(orbit_yaw, 0.0, e)
		orbit_pitch = lerpf(orbit_pitch, PITCH_DEFAULT, e)
	var prof: Dictionary = ctx.camera_profile
	if camera.fov != float(prof["fov"]):
		camera.fov = prof["fov"]
	var a := player_layer.yaw + orbit_yaw
	var dist: float = prof["dist"]
	var pitch := orbit_pitch + (float(prof["height"]) / dist - PITCH_DEFAULT)
	var dir := Vector3(sin(a) * cos(pitch), sin(pitch), cos(a) * cos(pitch))
	var focus := p + Vector3(0, float(prof["look"]), 0)
	var target := focus + dir * dist
	target.y = maxf(target.y, ctx.ground_height(target.x, target.z) + 0.5)
	# Stabilised: follow the root smoothly with no step bob, sway or roll.
	var k := 1.0 - exp(-delta * (9.0 if dragging else 4.5))
	camera.global_position = camera.global_position.lerp(target, k)
	var ahead := fwd * float(prof["lookahead"]) * 0.47 * maxf(cos(orbit_yaw), 0.0)
	camera.look_at(focus + Vector3(0, -0.1, 0) + ahead, Vector3.UP)


func on_world_wrapped(dz: float) -> void:
	camera.global_position.z += dz
