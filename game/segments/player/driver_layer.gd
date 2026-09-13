class_name DriverLayer
extends PlayerLayer

# The street player as a whole: on foot, then into the car and driving, then
# out again - the loop in the car-entry reference clip. Composes the on-foot
# walker and the vehicle mode and hands control between them with a short
# scripted transition (walk to the door, door swings, slide into the seat,
# door shuts). Exposes yaw / walking / forward() like any player layer so the
# camera, HUD and crowd don't care which mode is active.

const ENTER_KEYS := [KEY_E, KEY_ENTER, KEY_KP_ENTER]
const FOOT_PROFILE := {"dist": 3.6, "height": 1.7, "look": 0.95, "fov": 60.0, "lookahead": 3.0, "clip_h": 2.8}
const FOOT_HINT := "Up / Down: pace   Left / Right: turn   Space: jump   E: get in (beside the car)   Drag: look around"
const CAR_HINT := "Up: accelerate   Down: brake / reverse   Left / Right: steer   E: get out (when stopped)   Drag: look around"
const DOOR_ANGLE := -1.15        # radians the door swings (front hinge, outward)
const DOOR_T := 0.45             # door swing time
const SLIDE_T := 0.75            # seat <-> door slide time
const NEAR := 2.6                # how close to the door "E" works

var walker: StreetWalkerLayer
var vehicle: VehiclePlayerLayer
var car: Node3D
var body: Node3D
var mode := "foot"               # foot | entering | car | exiting
var phase := 0
var t := 0.0
var from_pos := Vector3.ZERO
var from_yaw := 0.0
var door_open := 0.0
var sit_root_y := 0.0            # body root height (car local) that seats the driver under the roof


func build() -> void:
	var sc: StreetContext = ctx as StreetContext
	vehicle = VehiclePlayerLayer.new()
	vehicle.name = "Vehicle"
	add_child(vehicle)
	vehicle.setup(ctx)
	car = vehicle.car
	car.position = Vector3(sc.PARK_X, 0.0, -10.0)      # parked at the right kerb, nose down the street
	ctx.player_vehicle = car
	walker = StreetWalkerLayer.new()
	walker.name = "Walker"
	add_child(walker)
	walker.setup(ctx)
	body = walker.body
	_measure_sitting()
	_set_mode("foot")


# Play the seated clip once to learn where the hips and head end up, then
# place the root so the hips rest on the cushion, sinking a little further if
# the head would otherwise touch the roof (legs vanish into the body shell).
func _measure_sitting() -> void:
	var skel: Skeleton3D = walker.skel
	var head := skel.find_bone("Head")
	var hips := skel.find_bone("Hips")
	walker.anim.play("Sitting_Idle")
	walker.anim.seek(0.2, true)
	skel.force_update_all_bone_transforms()
	var head_h := skel.get_bone_global_pose(head).origin.y if head >= 0 else 0.0
	var hip_h := skel.get_bone_global_pose(hips).origin.y if hips >= 0 else 0.0
	if head_h < 0.5 or head_h > 1.3:
		head_h = 0.95   # pose not applied yet (or odd rig): typical seated head height
	if hip_h < 0.2 or hip_h > 0.7:
		hip_h = 0.45
	var seat: Vector3 = car.get_meta("seat")
	var roof_y: float = car.get_meta("roof_y")
	sit_root_y = minf(seat.y + 0.06 - hip_h, roof_y - 0.22 - head_h)
	walker.anim.play("Idle")


func _set_mode(m: String) -> void:
	mode = m
	phase = 0
	t = 0.0
	ctx.hud_status = ""
	walker.set_process_unhandled_input(m == "foot")
	if m == "foot":
		ctx.player = body
		ctx.camera_profile = FOOT_PROFILE
		ctx.hud_hint = FOOT_HINT
		walker.pace = 0
		walker.walking = false
	elif m == "car":
		ctx.player = car
		ctx.camera_profile = VehiclePlayerLayer.PROFILE
		ctx.hud_hint = CAR_HINT


func _door_world() -> Vector3:
	var p: Vector3 = car.global_transform * (car.get_meta("door_point") as Vector3)
	p.y = ctx.walk_height(p.x, p.z)
	return p


func _seat_world() -> Vector3:
	var s: Vector3 = car.get_meta("seat")
	return car.global_transform * Vector3(s.x, sit_root_y, s.z)


func _near_door() -> bool:
	return body.position.distance_to(_door_world()) < NEAR


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in ENTER_KEYS:
		if mode == "foot" and _near_door():
			_set_mode("entering")
			walker.pace = 0
		elif mode == "car" and absf(vehicle.speed) < 0.3:
			vehicle.speed = 0.0
			ctx.player = body
			_set_mode("exiting")


func _yaw_toward(dir: Vector3) -> float:
	return atan2(-dir.x, -dir.z)   # forward() = (-sin yaw, 0, -cos yaw)


func _car_right() -> Vector3:
	return car.global_transform.basis.x


func _apply_door() -> void:
	(car.get_meta("door_l") as Node3D).rotation.y = DOOR_ANGLE * door_open
	(car.get_meta("door_gap") as Node3D).visible = door_open > 0.03


func tick(delta: float) -> void:
	match mode:
		"foot":
			walker.tick(delta)
			# the parked car is a soft obstacle for the walker and the crowd
			var f := car.global_transform.basis.z
			for dz: float in [-1.1, 1.1]:
				ctx.dynamic_obstacles.append([car.global_position + f * dz, 1.0])
			ctx.hud_status = "E: get in" if _near_door() else ""
			yaw = walker.yaw
			walking = walker.walking
		"car":
			vehicle.tick(delta)
			_seat_body()
			if absf(vehicle.speed) < 0.3:
				ctx.hud_status += "   E: get out"
			yaw = vehicle.yaw
			walking = vehicle.walking
		"entering":
			_tick_enter(delta)
		"exiting":
			_tick_exit(delta)
	_apply_door()


func _seat_body() -> void:
	body.global_position = _seat_world()
	body.rotation.y = car.rotation.y


func _tick_enter(delta: float) -> void:
	t += delta
	var dp := _door_world()
	match phase:
		0:   # walk to the door
			var to := dp - body.position
			to.y = 0.0
			var d := to.length()
			if d < 0.1:
				phase = 1
				t = 0.0
				walker.anim.play("Idle", 0.25)
				walker.anim.speed_scale = 1.0
			else:
				walker.yaw = lerp_angle(walker.yaw, _yaw_toward(to / d), 1.0 - exp(-delta * 8.0))
				body.rotation.y = walker.yaw
				body.position += to / d * minf(PlayerLayer.WALK_SPEED * delta, d)
				body.position.y = dp.y
				if walker.anim.current_animation != "Walk":
					walker.anim.play("Walk", 0.2)
					walker.anim.speed_scale = PlayerLayer.WALK_SPEED / SkinnedPlayerLayer.ANIM_WALK_SPEED
			yaw = walker.yaw
			walking = true
		1:   # face the car while the door swings open
			walker.yaw = lerp_angle(walker.yaw, _yaw_toward(_car_right()), 1.0 - exp(-delta * 7.0))
			body.rotation.y = walker.yaw
			door_open = minf(t / DOOR_T, 1.0)
			yaw = walker.yaw
			walking = false
			if t > DOOR_T + 0.1:
				phase = 2
				t = 0.0
				from_pos = body.position
				from_yaw = walker.yaw
				walker.anim.play("Sitting_Idle", 0.35)
				ctx.player = car
				ctx.camera_profile = VehiclePlayerLayer.PROFILE
		2:   # slide into the seat
			var u := smoothstep(0.0, 1.0, minf(t / SLIDE_T, 1.0))
			body.position = from_pos.lerp(_seat_world(), u)
			body.rotation.y = lerp_angle(from_yaw, car.rotation.y, u)
			yaw = vehicle.yaw
			if t > SLIDE_T:
				phase = 3
				t = 0.0
		3:   # door shuts
			_seat_body()
			door_open = 1.0 - minf(t / DOOR_T, 1.0)
			yaw = vehicle.yaw
			if t > DOOR_T + 0.05:
				_set_mode("car")


func _tick_exit(delta: float) -> void:
	t += delta
	match phase:
		0:   # door swings open
			_seat_body()
			door_open = minf(t / DOOR_T, 1.0)
			yaw = vehicle.yaw
			walking = false
			if t > DOOR_T + 0.05:
				phase = 1
				t = 0.0
				from_pos = body.position
				from_yaw = body.rotation.y
				walker.anim.play("Idle", 0.35)
				ctx.camera_profile = FOOT_PROFILE
		1:   # slide out to the kerb side of the door
			var u := smoothstep(0.0, 1.0, minf(t / SLIDE_T, 1.0))
			body.position = from_pos.lerp(_door_world(), u)
			body.rotation.y = lerp_angle(from_yaw, car.rotation.y, u)   # step out facing down the street
			walker.yaw = body.rotation.y
			yaw = walker.yaw
			if t > SLIDE_T:
				phase = 2
				t = 0.0
		2:   # door shuts, back on foot
			door_open = 1.0 - minf(t / DOOR_T, 1.0)
			yaw = walker.yaw
			if t > DOOR_T + 0.05:
				_set_mode("foot")


func on_world_wrapped(dz: float) -> void:
	# the active mode wrapped itself; carry the other one along
	if mode == "foot":
		car.position.z += dz
	else:
		body.position.z += dz
