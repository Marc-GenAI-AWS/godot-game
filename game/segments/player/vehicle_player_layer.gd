class_name VehiclePlayerLayer
extends PlayerLayer

# Vehicle mode: an arcade car. Up accelerates, Down brakes / reverses,
# Left / Right steer (effect scales with speed). Same interface as the
# on-foot player (forward(), right(), yaw, walking) so camera and HUD work.

var car: Node3D
var speed := 0.0
var steer := 0.0
var spin := 0.0
var kind := "hatch"
var brake_latch := false
var with_driver := false   # drive-only variant: bake a seated driver so the cabin isn't empty   # Down while rolling brakes to a stop; release and press again to reverse
var paint := Color(0.95, 0.75, 0.1)
var roof := Color(0.08, 0.08, 0.08)

const MAX_SPEED := 26.0
const ACCEL := 7.0
const BRAKE := 14.0
const DRAG := 0.6
const REVERSE_MAX := 6.0
const WHEELBASE := 2.5
const MAX_STEER := 0.5
const PROFILE := {"dist": 7.0, "height": 2.4, "look": 0.8, "fov": 66.0, "lookahead": 3.0, "clip_h": 2.6}


func build() -> void:
	car = Car.build(kind, paint, roof)
	car.name = "PlayerCar"
	if with_driver:
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		Car.add_driver(car, rng, self)
	car.position = Vector3((ctx as StreetContext).LANE_X, 0.0, 0.0)   # right-hand traffic
	add_child(car)
	ctx.player = car
	player = null
	walking = false
	ctx.camera_profile = PROFILE


func _unhandled_input(_event: InputEvent) -> void:
	pass


func tick(delta: float) -> void:
	var sc: StreetContext = ctx as StreetContext
	var throttle := 0.0
	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		throttle += 1.0
	if Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		throttle -= 1.0
	var s_in := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		s_in += 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		s_in -= 1.0
	# longitudinal
	if throttle > 0.0:
		speed = minf(speed + ACCEL * delta, MAX_SPEED)
	elif throttle < 0.0:
		if speed > 0.05:
			brake_latch = true
			speed = maxf(speed - BRAKE * delta, 0.0)
		elif brake_latch:
			speed = 0.0
		else:
			speed = maxf(speed - ACCEL * 0.6 * delta, -REVERSE_MAX)
	else:
		brake_latch = false
		speed = move_toward(speed, 0.0, (DRAG + absf(speed) * 0.12) * delta)
	# steering: ease toward input, less lock at speed
	var lock := MAX_STEER * clampf(1.0 - absf(speed) / (MAX_SPEED * 1.4), 0.35, 1.0)
	steer = lerpf(steer, s_in * lock, 1.0 - exp(-delta * 6.0))
	if absf(speed) > 0.05:
		yaw += (speed / WHEELBASE) * tan(steer) * delta
	yaw = wrapf(yaw, -PI, PI)
	# move: follow whatever is ahead (cap the step to the free distance), keep
	# on the road, and let side contacts push us out
	var fwd := forward()
	var dir := fwd if speed >= 0.0 else -fwd
	var wanted := absf(speed) * delta
	var free := ctx.free_distance(car.position, dir, 0.9, 12.0)
	var allowed := maxf(free - 0.6, 0.0)
	if wanted > allowed:
		wanted = allowed
		speed = signf(speed) * allowed / delta * 0.95   # honest speed while held up
		if absf(speed) < 0.2:
			speed = 0.0
	var p := car.position + dir * wanted
	# cars behind us never push us (they follow); drop them from this frame's list
	var keep: Array = []
	for ob in ctx.dynamic_obstacles:
		var rel: Vector3 = ob[0] - car.position
		if rel.dot(fwd) > -1.5:
			keep.append(ob)
	var saved: Array = ctx.dynamic_obstacles
	ctx.dynamic_obstacles = keep
	p = ctx.resolve_obstacles(sc.constrain_vehicle(p), 0.95)
	ctx.dynamic_obstacles = saved
	car.position = p
	car.rotation.y = yaw
	# body lean and wheel motion
	var body: Node3D = car.get_meta("body_mesh")
	body.rotation.z = lerpf(body.rotation.z, -steer * speed * 0.004, 1.0 - exp(-delta * 5.0))
	body.rotation.x = lerpf(body.rotation.x, -throttle * 0.01 * clampf(absf(speed) / 5.0, 0.0, 1.0), 1.0 - exp(-delta * 4.0))
	spin += speed * delta / float(car.get_meta("wheel_radius"))
	var wheels: Array = car.get_meta("wheels")
	for i in wheels.size():
		var hub: Node3D = wheels[i]
		hub.rotation.y = steer if i < 2 else 0.0
		(hub.get_child(0) as Node3D).rotation.x = -spin
	ctx.player_phase = 0.0
	walking = absf(speed) > 0.3
	ctx.hud_status = "%d km/h" % int(absf(speed) * 3.6)
	# endless road
	if car.position.z < -WorldContext.CHUNK:
		car.position.z += WorldContext.CHUNK
		ctx.world_wrapped.emit(WorldContext.CHUNK)
	elif car.position.z >= 0.0:
		car.position.z -= WorldContext.CHUNK
		ctx.world_wrapped.emit(-WorldContext.CHUNK)
