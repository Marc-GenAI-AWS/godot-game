class_name ChunkedLayer
extends BeachLayer

# Scenery that repeats every WorldContext.CHUNK metres. build_chunk() is
# called three times with an identical RNG so the copies match exactly and
# the player can be teleported back a chunk without a visible seam.

var seed_v := 1
var chunks: Array[Node3D] = []


func build() -> void:
	for i in 3:
		var chunk := Node3D.new()
		chunk.name = "Chunk%d" % i
		chunk.position.z = (i - 1) * WorldContext.CHUNK
		add_child(chunk)
		chunks.append(chunk)
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_v
		build_chunk(chunk, rng)


func build_chunk(_chunk: Node3D, _rng: RandomNumberGenerator) -> void:
	pass


# Local-Z helpers: chunk content lives in z ∈ [-CHUNK, 0).
func wrap_local_z(z: float) -> float:
	if z < -WorldContext.CHUNK:
		return z + WorldContext.CHUNK
	if z >= 0.0:
		return z - WorldContext.CHUNK
	return z
