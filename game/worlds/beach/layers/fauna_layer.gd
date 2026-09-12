class_name FaunaLayer
extends SceneLayer

# Seagulls: a flock circling out over the water, plus a few standing on the
# sand ahead that flush when the player gets close and resettle further on.

class Gull:
	var node: Node3D
	var wings: Array[Node3D] = []
	var state := "stand"     # stand | fly | circle
	var t := 0.0
	var origin := Vector3.ZERO
	var dir := Vector3.FORWARD
	var phase := 0.0

var gulls: Array[Gull] = []
var flock: Array[Gull] = []
var rng := RandomNumberGenerator.new()


func _make_gull(scale_f: float) -> Gull:
	var g := Gull.new()
	g.node = Node3D.new()
	g.node.scale = Vector3.ONE * scale_f
	add_child(g.node)
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.09
	cm.height = 0.5
	body.mesh = cm
	body.material_override = ctx.mat(Color(0.95, 0.95, 0.95))
	body.rotation.x = PI * 0.5
	g.node.add_child(body)
	sphere(g.node, 0.08, Color(0.95, 0.95, 0.95), Vector3(0, 0.05, -0.28))
	box(g.node, Vector3(0.03, 0.03, 0.12), Color(0.95, 0.7, 0.2), Vector3(0, 0.04, -0.4))
	box(g.node, Vector3(0.12, 0.02, 0.18), Color(0.85, 0.85, 0.85), Vector3(0, 0.02, 0.3))
	for side in [-1.0, 1.0]:
		var w := Node3D.new()
		g.node.add_child(w)
		var wing := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.75, 0.02, 0.22)
		wing.mesh = bm
		wing.material_override = ctx.mat(Color(0.8, 0.8, 0.82))
		wing.position = Vector3(side * 0.4, 0, 0)
		w.add_child(wing)
		box(w, Vector3(0.3, 0.02, 0.14), Color(0.25, 0.25, 0.28), Vector3(side * 0.88, 0, 0.02))
		g.wings.append(w)
	# two stick legs (only visible when standing)
	box(g.node, Vector3(0.02, 0.16, 0.02), Color(0.95, 0.7, 0.2), Vector3(-0.05, -0.15, 0))
	box(g.node, Vector3(0.02, 0.16, 0.02), Color(0.95, 0.7, 0.2), Vector3(0.05, -0.15, 0))
	g.phase = randf() * TAU
	return g


func build() -> void:
	rng.seed = 31
	for i in 4:
		var g := _make_gull(1.0)
		g.state = "stand"
		_place_standing(g, -20.0 - i * 18.0)
		gulls.append(g)
	for i in 7:
		var g := _make_gull(1.8)
		g.state = "circle"
		g.t = rng.randf() * TAU
		flock.append(g)


func _place_standing(g: Gull, z: float) -> void:
	var x := rng.randf_range(-9.0, -1.5)
	g.origin = Vector3(x, ctx.ground_height(x, z) + 0.24, z)
	g.node.position = g.origin
	g.node.rotation = Vector3(0, rng.randf() * TAU, 0)
	g.state = "stand"
	g.t = 0.0
	g.wings[0].rotation.z = 0.0
	g.wings[1].rotation.z = 0.0


func tick(delta: float) -> void:
	var p := ctx.player.position if ctx.player else Vector3.ZERO
	var time := ctx.time
	for g in gulls:
		match g.state:
			"stand":
				# peck / look around
				g.node.rotation.y += 0.4 * delta * sin(time * 0.7 + g.phase)
				if g.origin.distance_to(p) < 6.5:
					g.state = "fly"
					g.t = 0.0
					var away := (g.origin - p)
					away.y = 0.0
					g.dir = (away.normalized() * 0.6 + Vector3(0.8, 0, -0.4)).normalized()
					g.node.look_at(g.node.position + g.dir, Vector3.UP)
				elif g.origin.z > p.z + 12.0:
					_place_standing(g, p.z - rng.randf_range(45.0, 80.0))
			"fly":
				g.t += delta
				var u := g.t
				var pos := g.origin + g.dir * u * 7.0 + Vector3(0, minf(u * 2.6, 6.0) + 0.6 * sin(u * 2.0), 0)
				g.node.position = pos
				g.node.look_at(pos + g.dir + Vector3(0, 0.15, 0), Vector3.UP)
				var flap := sin(time * 11.0 + g.phase) * 0.6
				g.wings[0].rotation.z = flap
				g.wings[1].rotation.z = -flap
				if g.t > 8.0:
					_place_standing(g, p.z - rng.randf_range(45.0, 80.0))
	# The flock circles a slowly drifting centre out over the water.
	var cx := 22.0 + 6.0 * sin(time * 0.1)
	var cz := p.z - 35.0
	var i := 0
	for g in flock:
		g.t += delta * 0.35
		var a := g.t + i * (TAU / flock.size())
		var r := 14.0 + 3.0 * sin(time * 0.3 + i)
		var pos := Vector3(cx + cos(a) * r, 8.0 + 2.5 * sin(a * 2.0 + i) + 0.6 * i, cz + sin(a) * r * 0.7)
		var vel := Vector3(-sin(a), 0.0, cos(a) * 0.7)
		g.node.position = pos
		g.node.look_at(pos + vel, Vector3.UP)
		g.node.rotate_object_local(Vector3.FORWARD, -0.35)  # bank into the turn
		var glide := fmod(time * 0.5 + i * 1.7, 6.0) < 2.5
		var flap := 0.0 if glide else sin(time * 9.0 + g.phase) * 0.55
		g.wings[0].rotation.z = flap + 0.12
		g.wings[1].rotation.z = -flap - 0.12
		i += 1


func on_world_wrapped(dz: float) -> void:
	for g in gulls:
		g.origin.z += dz
		g.node.position.z += dz
	for g in flock:
		g.node.position.z += dz
