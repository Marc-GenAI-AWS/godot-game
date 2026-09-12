class_name StreetTraffic
extends ChunkedLayer

# Parked cars along both kerbs (static, batched by nothing: they are few) and
# moving traffic in the two lanes, wrapping within the chunk. Moving cars are
# dynamic obstacles; parked ones are static obstacles.

var traffic: Array = []   # [node, lane_x, dir, speed, wheels, wr]


func _init() -> void:
	seed_v = 777


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var sc: StreetContext = ctx as StreetContext
	# parked cars, nose along the road, in the parking strips
	for side: float in [-1.0, 1.0]:
		var z := -L + rng.randf_range(2.0, 10.0)
		while z < -6.0:
			if rng.randf() < 0.55:
				var car := Car.build(Car.random_kind(rng), Car.PAINTS[rng.randi() % Car.PAINTS.size()])
				var len: float = car.get_meta("length")
				car.position = Vector3(side * sc.PARK_X, 0.0, z + len * 0.5)
				car.rotation.y = 0.0 if side > 0.0 else PI
				chunk.add_child(car)
				# two circles along the car's length so they don't spill into the lane
				for dz in [-len * 0.28, len * 0.28]:
					ctx.add_obstacle(car.global_position + Vector3(0, 0, dz), 1.0)
				z += len + rng.randf_range(1.0, 5.0)
			else:
				z += rng.randf_range(6.0, 14.0)
	# moving traffic: a few per lane, spaced out
	# right-hand traffic: the -Z lane is at +x, the +Z lane at -x
	for lane in [[sc.LANE_X, -1.0], [-sc.LANE_X, 1.0]]:
		var n := 3
		for i in n:
			var car := Car.build(Car.random_kind(rng), Car.PAINTS[rng.randi() % Car.PAINTS.size()])
			var z := -L + (i + rng.randf_range(0.2, 0.8)) * (L / n)
			if z > -30.0:
				z -= 40.0   # keep the start clear
			car.position = Vector3(lane[0], 0.0, z)
			car.rotation.y = 0.0 if lane[1] < 0.0 else PI
			chunk.add_child(car)
			traffic.append({"node": car, "dir": lane[1], "cruise": rng.randf_range(11.0, 15.5), "speed": 0.0, "lane": lane[0], "wheels": car.get_meta("wheels"), "wr": car.get_meta("wheel_radius"), "spin": 0.0})


# Distance (m) to the nearest car ahead in this lane, or INF.
func _gap_ahead(t: Dictionary) -> float:
	var car: Node3D = t["node"]
	var gp := car.global_position
	var best := INF
	var candidates: Array = []
	for o in traffic:
		if o != t and absf(o["lane"] - t["lane"]) < 0.5:
			candidates.append((o["node"] as Node3D).global_position)
	if ctx.player and absf(ctx.player.global_position.x - t["lane"]) < 1.6:
		candidates.append(ctx.player.global_position)
	for c in candidates:
		var d: float = (c.z - gp.z) * t["dir"]
		if d > 0.0 and d < best:
			best = d
	return best


func tick(delta: float) -> void:
	for t in traffic:
		var car: Node3D = t["node"]
		# car-following: keep a gap to whatever is ahead in the lane
		var gap := _gap_ahead(t)
		var target: float = t["cruise"]
		if gap < 7.0:
			target = 0.0
		elif gap < 16.0:
			target = minf(target, (gap - 7.0) / 9.0 * t["cruise"])
		t["speed"] = move_toward(t["speed"], target, (5.0 if target < t["speed"] else 3.0) * delta)
		car.position.z = wrap_local_z(car.position.z + t["dir"] * t["speed"] * delta)
		t["spin"] += t["speed"] * delta / t["wr"]
		for w in t["wheels"]:
			(w.get_child(0) as Node3D).rotation.x = -t["spin"]
		var f := car.global_transform.basis.z   # car length axis
		for dz in [-1.1, 1.1]:
			ctx.dynamic_obstacles.append([car.global_position + f * dz, 1.0])
