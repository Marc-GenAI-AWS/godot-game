class_name CoastCrowd
extends SceneLayer

# People who live in the town rather than decorate it.
#
# The street world's pedestrians walk up and down one sidewalk and turn round at the end; the
# beach's stroll along the tide line. Neither has anywhere to go. On a grid you can give them
# something better, and the interesting behaviour is all at the kerb:
#
#   walk    - along a sidewalk, on one side of one street, at their own pace
#   corner  - at a junction, carry on, turn onto the crossing street, or turn back
#   cross   - step off the kerb only when nothing is coming. They look: any car heading their way
#             inside LOOK metres of the crossing means they wait, and they keep waiting until it
#             has gone. Halfway across they look again, because a car may have turned in behind.
#
# The result is that the pace of the town is set by its traffic, which is the point: people
# bunch at a corner when a car is coming and spill across when it has passed.

const N_PEOPLE := 34
const WALK_SPEED := [1.05, 1.65]
const CROSS_SPEED := 1.9           # people step out a little faster than they stroll
const LOOK := 16.0                 # how far up the road they check before stepping off
const WALK_OFFSET := 8.6           # sidewalk centre, measured from the street's centre line
const PATIENCE := 9.0              # after this long at a kerb, give up and walk on instead
const LIVE_RADIUS := 105.0         # past this they keep walking, they just stop being posed

var people: Array = []             # {node, axis, sign, street, side, state, speed, wait, skel, body}
var _rng := RandomNumberGenerator.new()


func build() -> void:
	_rng.seed = 90210
	var y: float = CoastContext.plateau_y()
	for i in N_PEOPLE:
		var p := _spawn(i, y)
		if not p.is_empty():
			people.append(p)


func _spawn(i: int, y: float) -> Dictionary:
	var on_cross := i % 3 != 0                       # most of them on the streets to the sea
	var person := {"speed": _rng.randf_range(WALK_SPEED[0], WALK_SPEED[1]), "state": "walk",
				   "wait": 0.0, "cross_t": 0.0, "side": 1.0 if _rng.randf() < 0.5 else -1.0}
	if on_cross:
		person["axis"] = "x"
		person["street"] = CoastContext.CROSS_Z[i % CoastContext.CROSS_Z.size()]
		person["sign"] = 1.0 if _rng.randf() < 0.5 else -1.0
	else:
		person["axis"] = "z"
		person["street"] = CoastContext.MID_X
		person["sign"] = 1.0 if _rng.randf() < 0.5 else -1.0
	var along := _rng.randf_range(CoastContext.AVENUE_X + 25.0, -80.0) if on_cross \
			else _rng.randf_range(-WorldContext.CHUNK + 15.0, -15.0)
	# same CC0 bodies, hair, outfits and builds the street crowd uses
	var sex := "F" if _rng.randf() < 0.5 else "M"
	var spec: Dictionary = SkinnedPeople.BODIES[sex]
	var hairs: Array = spec["hairs"].keys()
	var casual: Array = SkinnedPeople.CASUAL_OUTFITS[sex]
	var body: String = SkinnedPeople.pick_body_type(_rng)
	var node: Node3D = SkinnedPeople.animated(
			sex, hairs[_rng.randi() % hairs.size()], casual[_rng.randi() % casual.size()],
			SkinnedPeople.SKIN_TINTS[_rng.randi() % SkinnedPeople.SKIN_TINTS.size()],
			SkinnedPeople.HAIR_TINTS[_rng.randi() % SkinnedPeople.HAIR_TINTS.size()], body)
	node.position = _place(person, along, y)
	node.rotation.y = _heading(person)
	add_child(node)
	var skel: Skeleton3D = node.get_meta("skeleton")
	SkinnedPeople.apply_bone_scales(skel, body)
	var ap: AnimationPlayer = node.get_meta("anim")
	ap.play("Walk")
	ap.seek(_rng.randf_range(0.0, 1.3), true)
	person["node"] = node
	person["skel"] = skel
	person["body"] = body
	person["anim"] = ap
	person["clip"] = "Walk"
	return person


# Where a person stands: `along` down their street, offset to their side of it.
func _place(person: Dictionary, along: float, y: float) -> Vector3:
	var off: float = person["side"] * WALK_OFFSET
	if person["axis"] == "x":
		return Vector3(along, y + 0.15, person["street"] + off)
	return Vector3(person["street"] + off, y + 0.15, along)


func _forward(person: Dictionary) -> Vector3:
	return Vector3(person["sign"], 0.0, 0.0) if person["axis"] == "x" else Vector3(0.0, 0.0, person["sign"])


func _heading(person: Dictionary) -> float:
	var f := _forward(person)
	return atan2(-f.x, -f.z)


func tick(delta: float) -> void:
	var y: float = CoastContext.plateau_y()
	for person in people:
		match person["state"]:
			"walk":
				_walk(person, delta, y)
			"wait":
				_wait(person, delta)
			"cross":
				_cross(person, delta, y)


func _walk(person: Dictionary, delta: float, y: float) -> void:
	var node: Node3D = person["node"]
	var f := _forward(person)
	node.position += f * float(person["speed"]) * delta
	node.position.y = y + 0.15
	node.rotation.y = lerp_angle(node.rotation.y, _heading(person), 1.0 - exp(-delta * 8.0))
	_animate(person, float(person["speed"]))
	_wrap(person, node)
	# at a corner, decide: carry on, turn, or cross
	var d := _distance_to_junction(person, node.position)
	if d >= 0.0 and d < 1.0 and person["wait"] <= 0.0:
		person["wait"] = 4.0                          # one decision per corner
		var roll := _rng.randf()
		if roll < 0.32:
			_begin_cross(person)
		elif roll < 0.62:
			_turn(person)
	person["wait"] = maxf(float(person["wait"]) - delta, 0.0)
	ctx.dynamic_obstacles.append([node.position, 0.4])


# Step into the road only when nothing is coming, and keep looking while you wait.
func _begin_cross(person: Dictionary) -> void:
	person["state"] = "wait"
	person["wait"] = 0.0


func _wait(person: Dictionary, delta: float) -> void:
	var node: Node3D = person["node"]
	person["wait"] = float(person["wait"]) + delta
	_animate(person, 0.0)
	ctx.dynamic_obstacles.append([node.position, 0.4])
	if _road_clear(person):
		person["state"] = "cross"
		person["cross_t"] = 0.0
		person["side"] = -float(person["side"])       # the far sidewalk is the destination
	elif float(person["wait"]) > PATIENCE:
		person["state"] = "walk"                      # gave up; carry on down this side
		person["wait"] = 4.0


# Anything coming? A car counts if it is on this street, within LOOK, and heading this way.
func _road_clear(person: Dictionary) -> bool:
	var node: Node3D = person["node"]
	var on_x: bool = person["axis"] == "x"
	var street: float = person["street"]
	for group in [_traffic_nodes(), [ctx.player_vehicle]]:
		for n in group:
			var car := n as Node3D
			if car == null or not is_instance_valid(car):
				continue
			# Only traffic on the roadway being crossed counts. Checking every car within LOOK in
			# any direction - which the first version did - means a car two streets away on its
			# own business holds somebody at a kerb, and with 26 cars about, nobody ever crossed.
			var lateral: float = absf(car.position.z - street) if on_x else absf(car.position.x - street)
			if lateral > CoastContext.CROSS_HALF + 1.0:
				continue
			var along: float = (car.position.x - node.position.x) if on_x else (car.position.z - node.position.z)
			if absf(along) > LOOK:
				continue
			var car_f := Vector3(-sin(car.rotation.y), 0.0, -cos(car.rotation.y))
			var toward: float = -car_f.x * along if on_x else -car_f.z * along
			if toward > 0.0:                          # it is coming this way
				return false
	return true


func _traffic_nodes() -> Array:
	var out: Array = []
	for l in get_parent().get_children():
		if l is CoastTraffic:
			for car in (l as CoastTraffic).cars:
				out.append(car["node"])
	return out


# Walk straight across the road to the far sidewalk, then resume.
func _cross(person: Dictionary, delta: float, y: float) -> void:
	var node: Node3D = person["node"]
	var to: float = person["street"] + float(person["side"]) * WALK_OFFSET
	var here: float = node.position.z if person["axis"] == "x" else node.position.x
	var step: float = signf(to - here) * CROSS_SPEED * delta
	if absf(to - here) <= absf(step):
		if person["axis"] == "x":
			node.position.z = to
		else:
			node.position.x = to
		person["state"] = "walk"
		person["wait"] = 3.0
	else:
		if person["axis"] == "x":
			node.position.z += step
		else:
			node.position.x += step
	node.position.y = y + 0.15
	var facing := Vector3(0.0, 0.0, signf(to - here)) if person["axis"] == "x" \
			else Vector3(signf(to - here), 0.0, 0.0)
	node.rotation.y = lerp_angle(node.rotation.y, atan2(-facing.x, -facing.z), 1.0 - exp(-delta * 9.0))
	_animate(person, CROSS_SPEED)
	ctx.dynamic_obstacles.append([node.position, 0.4])


func _turn(person: Dictionary) -> void:
	var f := _forward(person)
	var right := Vector3(-f.z, 0.0, f.x)
	var dir := right if _rng.randf() < 0.5 else -right
	if person["axis"] == "x":
		var cx: float = CoastContext.MID_X
		if absf((person["node"] as Node3D).position.x - cx) > 12.0:
			return
		person["axis"] = "z"
		person["sign"] = signf(dir.z)
		person["street"] = cx
	else:
		var cz: float = CoastContext.cross_near((person["node"] as Node3D).position.z, 12.0)
		if is_nan(cz):
			return
		person["axis"] = "x"
		person["sign"] = signf(dir.x)
		person["street"] = cz


func _distance_to_junction(person: Dictionary, pos: Vector3) -> float:
	var best := -1.0
	for j: Vector3 in CoastContext.junctions():
		var along: float = (j.x - pos.x) * person["sign"] if person["axis"] == "x" else (j.z - pos.z) * person["sign"]
		var across: float = absf(j.z - pos.z) if person["axis"] == "x" else absf(j.x - pos.x)
		if along > 0.0 and across < 14.0 and (best < 0.0 or along < best):
			best = along
	return best


func _wrap(person: Dictionary, node: Node3D) -> void:
	if node.position.z < -WorldContext.CHUNK:
		node.position.z += WorldContext.CHUNK
	elif node.position.z >= 0.0:
		node.position.z -= WorldContext.CHUNK
	if person["axis"] == "x":
		var far_sea: bool = node.position.x > CoastTown.SEAWARD_X - 4.0 and person["sign"] > 0.0
		var far_inland: bool = node.position.x < CoastContext.AVENUE_X + 6.0 and person["sign"] < 0.0
		if far_sea or far_inland:
			person["sign"] = -float(person["sign"])
			node.position.x = clampf(node.position.x, CoastContext.AVENUE_X + 7.0, CoastTown.SEAWARD_X - 5.0)


# The walk clip covers 0.975 m per second at speed_scale 1, so the cadence follows the speed and
# feet do not skate. Standing at a kerb is the idle clip, not a walk played very slowly.
func _animate(person: Dictionary, speed: float) -> void:
	var ap: AnimationPlayer = person["anim"]
	# Nothing to pose if nobody can see them. apply_bone_scales() walks the skeleton every frame,
	# which is the single most expensive thing this layer does.
	if ctx.player != null and not WorldContext.pose_if_near(person["node"], ap, ctx.player.global_position, LIVE_RADIUS):
		return
	var want: String = "Walk" if speed > 0.05 else "Idle"
	if person["clip"] != want:
		person["clip"] = want
		ap.play(want, 0.2)
	ap.speed_scale = clampf(speed / 0.975, 0.35, 1.8) if want == "Walk" else 1.0
	SkinnedPeople.apply_bone_scales(person["skel"], person["body"])


func on_world_wrapped(dz: float) -> void:
	for person in people:
		(person["node"] as Node3D).position.z += dz
