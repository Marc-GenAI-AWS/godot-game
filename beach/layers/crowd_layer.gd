class_name CrowdLayer
extends ChunkedLayer

# Everyone who isn't the player: sunbathers on the furniture layer's spots,
# strollers on the waterline, waders and bobbing swimmers.

var furniture: FurnitureLayer
var walkers: Array = []     # [Humanoid, speed, dir]
var swimmers: Array = []    # [Humanoid, base_y, phase]

var skins := [Color(0.9, 0.72, 0.58), Color(0.76, 0.55, 0.4), Color(0.55, 0.36, 0.25), Color(0.95, 0.8, 0.68)]
var suits := [Color(0.9, 0.2, 0.3), Color(0.1, 0.3, 0.7), Color(0.95, 0.85, 0.2), Color(0.1, 0.1, 0.12), Color(0.2, 0.7, 0.6)]
var tops := [Color(1, 1, 1), Color(0.9, 0.3, 0.3), Color(0.2, 0.4, 0.8), Color(0.95, 0.85, 0.3), Color(0.3, 0.7, 0.5)]
var bottoms := [Color(0.3, 0.4, 0.6), Color(0.1, 0.1, 0.12), Color(0.9, 0.9, 0.85), Color(0.8, 0.3, 0.2)]
var hairs := [Color(0.12, 0.08, 0.05), Color(0.35, 0.22, 0.1), Color(0.75, 0.6, 0.35), Color(0.05, 0.05, 0.05)]


func _init() -> void:
	seed_v = 9876


func _pick(arr: Array, rng: RandomNumberGenerator) -> Color:
	return arr[rng.randi() % arr.size()]


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	var ci := chunks.size() - 1
	# Sunbathers / sitters on furniture spots
	if furniture and ci < furniture.spots.size():
		for spot in furniture.spots[ci]:
			if rng.randf() > 0.7:
				continue
			var h := Humanoid.new()
			var skin := _pick(skins, rng)
			var suit := _pick(suits, rng)
			h.build(skin, suit if rng.randf() < 0.8 else skin, suit, _pick(hairs, rng), rng.randf() < 0.6, 0.95)
			var node: Node3D = spot["node"]
			if spot["kind"] == "lounger":
				h.pose_lying()
				h.position = Vector3(0.0, 0.42, 0.85)
			else:
				if rng.randf() < 0.5:
					h.pose_lying()
					h.position = Vector3(0.0, 0.05, 0.85)
				else:
					h.pose_sit()
					h.position = Vector3(0.0, 0.03, 0.3)
			node.add_child(h)
			h.bake_static()
	# Waders standing in the shallows
	for i in 5:
		var h := Humanoid.new()
		h.build(_pick(skins, rng), skins[0], _pick(bottoms, rng), Color(0.1, 0.07, 0.05), rng.randf() < 0.5, rng.randf_range(0.9, 1.05))
		var wx := rng.randf_range(4.0, 9.0)
		var wz := rng.randf_range(-L, 0.0)
		h.position = Vector3(wx, ctx.sand_height(wx, wz), wz)
		h.rotation.y = rng.randf_range(-0.6, 0.6) + PI * 0.5
		h.pose_idle()
		chunk.add_child(h)
		h.bake_static()
	# Swimmers bobbing further out
	for i in 6:
		var h := Humanoid.new()
		h.build(_pick(skins, rng), skins[0], _pick(suits, rng), Color(0.1, 0.07, 0.05), false, 1.0)
		var wx := rng.randf_range(14.0, 26.0)
		var wz := rng.randf_range(-L, 0.0)
		h.position = Vector3(wx, -1.05, wz)
		h.rotation.y = rng.randf() * TAU
		h.pose_idle()
		chunk.add_child(h)
		h.bake_static()
		swimmers.append([h, -1.05, rng.randf() * TAU])
	# Strollers along the waterline, some in pairs
	for i in 9:
		var pair := rng.randf() < 0.35
		var x := rng.randf_range(-12.0, -1.0)
		var z := rng.randf_range(-L, 0.0)
		var dir := 1.0 if rng.randf() < 0.5 else -1.0
		var speed := rng.randf_range(1.1, 1.6)
		for k in (2 if pair else 1):
			var h := Humanoid.new()
			h.build(_pick(skins, rng), _pick(tops, rng), _pick(bottoms, rng), _pick(hairs, rng), rng.randf() < 0.5, rng.randf_range(0.9, 1.05))
			var xx := x + k * 0.8
			h.position = Vector3(xx, ctx.sand_height(xx, z), z)
			h.rotation.y = 0.0 if dir < 0 else PI
			chunk.add_child(h)
			walkers.append([h, speed, dir])


func tick(delta: float) -> void:
	for w in walkers:
		var h: Humanoid = w[0]
		h.position.z = wrap_local_z(h.position.z + w[2] * w[1] * delta)
		h.position.y = ctx.sand_height(h.position.x, h.position.z)
		h.pose_walk(delta, w[1])
	for s in swimmers:
		var h: Humanoid = s[0]
		h.position.y = s[1] + ctx.sea_level() + 0.12 * sin(ctx.time * 1.3 + s[2])
