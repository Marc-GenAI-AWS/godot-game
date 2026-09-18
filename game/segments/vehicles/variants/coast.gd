class_name CoastTraffic
extends SceneLayer

# Traffic that uses the town's street grid instead of sliding along one axis.
#
# The street world's cars only ever drive up and down Z: they never turn, because there is
# nowhere to turn. The coast world has eight junctions, so its cars need three things the old
# ones did not: a route, a way through a junction, and manners.
#
#   route     - each car holds an axis and the street it is on. Reaching a junction it picks a
#               continuation (straight is twice as likely as either turn) and swings onto it.
#   junction  - a car about to enter checks whether anyone is already inside the box, and waits
#               if so. First in has priority; nobody signals, and there are no lights.
#   manners   - gap keeping uses the same free_distance() the player's car uses, so traffic
#               queues behind the player and behind itself, and lets the player out.
#
# Not chunked: these are a fixed population moving across the whole grid, and three copies of
# each car 200 m apart would drive into their own duplicates at the wrap. They wrap in Z with
# the world instead, like the gulls do.

const LANE := 1.9                  # lane centres either side of the middle, as on the avenue
const N_CARS := 26
const JUNCTION := 9.0              # half width of the box a car must find empty before entering
const TURN_RATE := 2.6             # radians per second while swinging through a junction
const CRUISE := [8.0, 13.5]
const LIVE_RADIUS := 150.0         # a car reads at a greater distance than a person

var cars: Array = []               # {node, axis, sign, street, speed, cruise, wait, wheels, wr, spin}
var _rng := RandomNumberGenerator.new()
var _frame := 0


func build() -> void:
	_rng.seed = 424242
	var y: float = CoastContext.plateau_y()
	for i in N_CARS:
		var node := Car.build(Car.random_kind(_rng), Car.PAINTS[_rng.randi() % Car.PAINTS.size()])
		Car.add_driver(node, _rng, self)
		add_child(node)
		var car := _spawn(node, y, i)
		cars.append(car)


# Half the traffic runs inland on the cross streets, half along the coast street, spread out so
# they do not all arrive at the same junction at once.
func _spawn(node: Node3D, y: float, i: int) -> Dictionary:
	var car := {"node": node, "speed": 0.0, "cruise": _rng.randf_range(CRUISE[0], CRUISE[1]),
				"wait": 0.0, "wheels": node.get_meta("wheels"), "wr": node.get_meta("wheel_radius"),
				"spin": 0.0, "lock": 0.0}
	if i % 2 == 0:
		car["axis"] = "x"
		car["sign"] = 1.0 if _rng.randf() < 0.5 else -1.0
		car["street"] = CoastContext.CROSS_Z[i % CoastContext.CROSS_Z.size()]
		node.position = Vector3(_rng.randf_range(CoastContext.AVENUE_X + 20.0, -80.0), y,
								car["street"] + _lane_offset(car))
	else:
		car["axis"] = "z"
		car["sign"] = 1.0 if _rng.randf() < 0.5 else -1.0
		car["street"] = CoastContext.MID_X
		node.position = Vector3(car["street"] + _lane_offset(car), y,
								_rng.randf_range(-WorldContext.CHUNK + 10.0, -10.0))
	node.rotation.y = _heading(car)
	return car


# Right-hand traffic: the lane is offset to the driver's right of the centre line, which is the
# same rule the avenue uses ("the -Z lane is at +x").
func _lane_offset(car: Dictionary) -> float:
	var f := _forward(car)
	var right := Vector3(-f.z, 0.0, f.x)
	return (right.z if car["axis"] == "x" else right.x) * LANE


func _forward(car: Dictionary) -> Vector3:
	return Vector3(car["sign"], 0.0, 0.0) if car["axis"] == "x" else Vector3(0.0, 0.0, car["sign"])


func _heading(car: Dictionary) -> float:
	var f := _forward(car)
	return atan2(-f.x, -f.z)


func tick(delta: float) -> void:
	_frame += 1
	var y: float = CoastContext.plateau_y()
	for i in cars.size():
		_drive(cars[i], i, delta, y)


func _drive(car: Dictionary, index: int, delta: float, y: float) -> void:
	var node: Node3D = car["node"]
	var f := _forward(car)
	var seen: bool = ctx.player == null or WorldContext.pose_if_near(node, null, ctx.player.global_position, LIVE_RADIUS)
	# How much room is there ahead. This asks the other cars directly rather than going through
	# the obstacle field: every car registers itself there, so a car would find its own circle
	# a metre in front of its nose and brake for itself.
	#
	# It is also O(cars) per car, and so is the junction check - the two of them are most of what
	# this layer costs. Skipping them entirely out of sight was four times cheaper and wrong: cars
	# drove through each other and were still interpenetrating when the player arrived (4,540
	# overlapping frames a minute, against 28). So an unseen car re-checks every fourth frame and
	# reuses the last answer between, which keeps the queueing and drops three quarters of the work.
	var due: bool = seen or (_frame + index) % 4 == 0
	var free: float = _gap_ahead(car, index) if due else float(car.get("free", 99.0))
	car["free"] = free
	var target: float = car["cruise"]
	if free < 12.0:
		target = clampf((free - 3.5) * 1.6, 0.0, car["cruise"])
	if car["wait"] > 0.0:
		car["wait"] -= delta
		target = 0.0
	elif due and _junction_ahead(car, node.position) and not _junction_clear(car, index, node.position):
		target = 0.0
		car["held"] = float(car.get("held", 0.0)) + delta
		if float(car["held"]) > 4.0:                 # nobody went: somebody has to, or it is a jam
			target = car["cruise"] * 0.4
	else:
		car["held"] = 0.0
	car["speed"] = move_toward(car["speed"], target, (7.0 if target > car["speed"] else 12.0) * delta)
	node.position += f * car["speed"] * delta
	node.position.y = y

	# swing the nose round after a turn rather than snapping it
	var want := _heading(car)
	if absf(wrapf(want - node.rotation.y, -PI, PI)) > 0.01:
		node.rotation.y = rotate_toward(node.rotation.y, want, TURN_RATE * delta)

	car["lock"] = maxf(float(car["lock"]) - delta, 0.0)
	_maybe_turn(car, node)
	_keep_lane(car, node, delta)
	_wrap(car, node)

	# wheels, and the car as an obstacle for everyone else including the player
	car["spin"] += car["speed"] * delta / float(car["wr"])
	if seen:                                        # spinning wheels nobody can see is free to skip
		for w in car["wheels"]:
			((w as Node3D).get_child(0) as Node3D).rotation.x = -car["spin"]
	if seen:
		for dz: float in [-1.2, 1.2]:
			ctx.dynamic_obstacles.append([node.position + f * dz, 1.0])


# Junction geometry: a car on a cross street meets the coast street and the avenue; a car on the
# coast street meets each cross street.
func _junction_ahead(car: Dictionary, pos: Vector3) -> bool:
	var d := _distance_to_junction(car, pos)
	return d > 0.0 and d < 7.0


func _distance_to_junction(car: Dictionary, pos: Vector3) -> float:
	var best := -1.0
	for j: Vector3 in CoastContext.junctions():
		var along: float = (j.x - pos.x) * car["sign"] if car["axis"] == "x" else (j.z - pos.z) * car["sign"]
		var across: float = absf(j.z - pos.z) if car["axis"] == "x" else absf(j.x - pos.x)
		if along > 0.0 and across < JUNCTION and (best < 0.0 or along < best):
			best = along
	return best


# Distance to whatever is in front of us in this lane: another car, or the player.
func _gap_ahead(car: Dictionary, index: int) -> float:
	var pos: Vector3 = (car["node"] as Node3D).position
	var f := _forward(car)
	var best := 16.0
	for i in cars.size():
		if i == index:
			continue
		var rel: Vector3 = (cars[i]["node"] as Node3D).position - pos
		var along := rel.dot(f)
		if along <= 0.0:
			continue
		var across := (rel - f * along).length()
		if across < 2.4:
			best = minf(best, along - 4.2)          # nose to tail, not centre to centre
	if ctx.player != null:
		var rel2: Vector3 = ctx.player.position - pos
		var along2 := rel2.dot(f)
		var across2 := (rel2 - f * along2).length()
		if along2 > 0.0 and across2 < 2.4:
			best = minf(best, along2 - 4.2)
	return maxf(best, 0.0)


# You may enter a junction if nobody is in it and nobody approaching it will arrive before you.
# "Before you" has to be decided the same way by both cars or they both wait for ever - which is
# exactly what the first version did, and why two cars sat still for a minute. Distance decides,
# and the index breaks an exact tie.
func _junction_clear(car: Dictionary, index: int, pos: Vector3) -> bool:
	var d := _distance_to_junction(car, pos)
	if d < 0.0:
		return true
	var j: Vector3 = pos + _forward(car) * d
	for i in cars.size():
		if i == index:
			continue
		var other: Dictionary = cars[i]
		var opos: Vector3 = (other["node"] as Node3D).position
		var od := opos.distance_to(j)
		if od < 5.0:
			return false                            # somebody is in the box
		if od > JUNCTION or float(other["speed"]) < 0.3:
			continue                                # too far away, or stopped and not claiming it
		if (j - opos).normalized().dot(_forward(other)) < 0.5:
			continue                                # not heading into it
		# Only yield to somebody who will actually be there before us. Yielding to anyone merely
		# closer queued the whole grid solid once there were 26 cars: A waits for B, B is stuck
		# behind C, C waits for A.
		var their_eta: float = od / maxf(float(other["speed"]), 0.1)
		var my_eta: float = d / maxf(float(car["speed"]), 0.1)
		if their_eta < my_eta - 0.15 or (absf(their_eta - my_eta) <= 0.15 and i < index):
			return false                            # they have the better claim
	# the player always has right of way: they are not reading this code
	if ctx.player != null and ctx.player.position.distance_to(j) < JUNCTION * 0.7:
		return false
	return true


# At the centre of a junction, pick where to go next. Straight twice as likely as a turn, and a
# turn that would leave the grid is not offered.
# One decision per junction. Without the lock a car inside the box decides again on every frame -
# sixty times a second, each one possibly a turn - which reads as cars spinning on the spot and
# showed up as 3,132 turns a minute instead of about forty.
func _maybe_turn(car: Dictionary, node: Node3D) -> void:
	if car["speed"] < 0.5 or car["lock"] > 0.0:
		return
	var d := _distance_to_junction(car, node.position)
	if d < 0.0 or d > 1.2:
		return
	car["lock"] = 2.2
	var options: Array = [["straight", 2.0]]
	for turn: String in ["left", "right"]:
		var next := _after_turn(car, turn)
		if next.is_empty():
			continue
		options.append([turn, 1.0])
	var total := 0.0
	for o in options:
		total += o[1]
	var roll := _rng.randf() * total
	for o in options:
		roll -= o[1]
		if roll <= 0.0:
			if o[0] != "straight":
				var next := _after_turn(car, o[0])
				# Only the heading changes here. An earlier version also snapped the car onto the
				# new lane's centre line - a jump of up to 4 m sideways, which landed cars on top
				# of each other in the junction. _keep_lane eases it across instead.
				car["axis"] = next["axis"]
				car["sign"] = next["sign"]
				car["street"] = next["street"]
			break


# Ease back to the middle of the lane every frame: after a turn the car starts out across it.
func _keep_lane(car: Dictionary, node: Node3D, delta: float) -> void:
	var want: float = car["street"] + _lane_offset(car)
	var k := 1.0 - exp(-delta * 3.0)
	if car["axis"] == "x":
		node.position.z = lerpf(node.position.z, want, k)
	else:
		node.position.x = lerpf(node.position.x, want, k)


# What street a left or right turn from here would put us on, or {} if there is none.
func _after_turn(car: Dictionary, turn: String) -> Dictionary:
	var f := _forward(car)
	var right := Vector3(-f.z, 0.0, f.x)
	var dir := right if turn == "right" else -right
	if car["axis"] == "x":
		# turning onto a street that runs along Z: only the coast street does
		var cx: float = CoastContext.MID_X
		if absf(cx - _pos_of(car).x) > JUNCTION:
			return {}
		return {"axis": "z", "sign": signf(dir.z), "street": cx}
	# turning onto a cross street
	var cz: float = CoastContext.cross_near(_pos_of(car).z, JUNCTION)
	if is_nan(cz):
		return {}
	return {"axis": "x", "sign": signf(dir.x), "street": cz}


func _pos_of(car: Dictionary) -> Vector3:
	return (car["node"] as Node3D).position


# The world is a 200 m loop in Z and bounded in X by the promenade and the avenue; a car that
# reaches either end turns round rather than driving into the sea.
func _wrap(car: Dictionary, node: Node3D) -> void:
	if node.position.z < -WorldContext.CHUNK:
		node.position.z += WorldContext.CHUNK
	elif node.position.z >= 0.0:
		node.position.z -= WorldContext.CHUNK
	if car["axis"] == "x":
		# Turn round at the promenade and at the avenue. Only if we are actually heading that way,
		# and step back inside afterwards: the first version flipped the sign again on the very
		# next frame, which is where 4,000 "turns" a minute came from.
		var out_sea: bool = node.position.x > CoastTown.SEAWARD_X - 6.0 and car["sign"] > 0.0
		var out_inland: bool = node.position.x < CoastContext.AVENUE_X + 4.0 and car["sign"] < 0.0
		if out_sea or out_inland:
			car["sign"] = -car["sign"]
			node.position.x = clampf(node.position.x, CoastContext.AVENUE_X + 5.0, CoastTown.SEAWARD_X - 7.0)
			node.position.z = car["street"] + _lane_offset(car)
			car["wait"] = 0.6


func on_world_wrapped(dz: float) -> void:
	for car in cars:
		(car["node"] as Node3D).position.z += dz
