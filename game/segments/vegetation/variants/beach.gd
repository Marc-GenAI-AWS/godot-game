class_name BeachVegetation
extends ChunkedLayer

# Palms and hedges. Palms come from the shared species generator
# (segments/vegetation/species/palm.gd): tall thin fan palms along the
# promenade, fuller coconut palms on the sand; crowns sway in tick().

var crowns: Array[Node3D] = []


func _init() -> void:
	seed_v = 4321


func build_chunk(chunk: Node3D, rng: RandomNumberGenerator) -> void:
	var L := WorldContext.CHUNK
	# Tall, thin fan palms in a line along the promenade (as in the reference)
	var z := -L + rng.randf_range(0.0, 6.0)
	while z < 0.0:
		var x := BeachContext.BOARDWALK_X - 2.5 + rng.randf_range(-0.6, 0.6)
		crowns.append(Palm.build(chunk, Vector3(x, ctx.ground_height(x, z) - 0.2, z), rng, ctx, true))
		z += rng.randf_range(5.5, 8.5)
	# a few fuller coconut palms on the sand
	for i in 3:
		var x := rng.randf_range(-48.0, -38.0)
		var zz := rng.randf_range(-L, 0.0)
		crowns.append(Palm.build(chunk, Vector3(x, ctx.ground_height(x, zz) - 0.2, zz), rng, ctx, false))
	# Hedges along the boardwalk's landward side.
	var hedges := MeshBatch.new()
	var hz := -L
	while hz < 0.0:
		var len := rng.randf_range(6.0, 14.0)
		var hx := BeachContext.BOARDWALK_X - 8.6
		hedges.add_box_at(Vector3(1.2, 1.0, len), Color(0.15, 0.4, 0.17), Vector3(hx, ctx.ground_height(hx, hz) + 0.9, hz + len * 0.5))
		hz += len + rng.randf_range(3.0, 10.0)
	hedges.instance(chunk, "Hedges", 0.95)




func tick(_delta: float) -> void:
	var t := ctx.time
	for i in crowns.size():
		var c := crowns[i]
		c.rotation.x = 0.045 * sin(t * 0.9 + i * 1.3)
		c.rotation.z = 0.055 * sin(t * 0.7 + i * 0.7) + 0.03
