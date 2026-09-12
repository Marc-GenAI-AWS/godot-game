class_name WorldContext
extends Node

# Shared state every layer reads from. Layers never talk to each other
# directly; they read the context or listen to its signals.

signal world_wrapped(dz: float)                # player jumped back a chunk
signal player_step(pos: Vector3, side: int, yaw: float)

const CHUNK := 200.0          # scenery period along Z (player walks toward -Z)
const SAND_SLOPE := 0.06      # sand drops this much per metre into the sea (+X)
const LAND_SLOPE := 0.03      # and rises this much per metre up the beach (-X)
const BOARDWALK_X := -56.0

var time := 0.0
var tide_reach := 3.0         # world X the last wave reached (wet line)
var wind := Vector2(1.0, 0.45)
var player: Node3D
var player_phase := 0.0       # walk-cycle phase, for camera bob etc.
var camera: Camera3D
var inspect := false        # orbit the player up close (URL #inspect)
var inspect_offset := Vector3.ZERO   # #inspect-crowd orbits the lounger rows instead
var lite := false           # skip optional detail for A/B timing (URL #lite)
var variant := "quaternius"  # which player body to use (URL #mpfb)

# Palette published by the sky layer at build time; other layers read it.
var sky_zenith := Color(0.1, 0.32, 0.82)
var sky_horizon := Color(0.62, 0.78, 0.95)
var sun_dir := Vector3(-0.35, -0.8, -0.35)
var sun_color := Color(1.0, 0.96, 0.88)
var fog_color := Color(0.72, 0.82, 0.94)

# Soft collisions: static obstacle circles in a z-bucket hash, plus a
# per-frame list of moving ones (strollers). resolve() pushes a point out.
var _obstacles := {}          # bucket (int) -> Array of [Vector3, radius]
var dynamic_obstacles: Array = []   # [Vector3, radius], rebuilt each frame
const OB_BUCKET := 8.0


func add_obstacle(pos: Vector3, radius: float) -> void:
	var b := int(floor(pos.z / OB_BUCKET))
	if not _obstacles.has(b):
		_obstacles[b] = []
	_obstacles[b].append([pos, radius])


func resolve_obstacles(pos: Vector3, radius: float) -> Vector3:
	var b0 := int(floor(pos.z / OB_BUCKET))
	for b in [b0 - 1, b0, b0 + 1]:
		if _obstacles.has(b):
			for ob in _obstacles[b]:
				pos = _push_out(pos, ob[0], ob[1] + radius)
	for ob in dynamic_obstacles:
		pos = _push_out(pos, ob[0], ob[1] + radius)
	return pos


static func _push_out(pos: Vector3, centre: Vector3, r: float) -> Vector3:
	var d := Vector2(pos.x - centre.x, pos.z - centre.z)
	var len := d.length()
	if len < r and len > 0.0001:
		d = d / len * r
		return Vector3(centre.x + d.x, pos.y, centre.z + d.y)
	return pos


var noise_tex: ImageTexture
var sand_normal_tex: ImageTexture
var cloud_tex: ImageTexture
var window_tex: ImageTexture
var frond_tex: ImageTexture
var soft_disc_tex: ImageTexture


func sand_height(x: float, z: float) -> float:
	var h := -SAND_SLOPE * x if x > 0.0 else -LAND_SLOPE * x
	h += 0.06 * sin(z * 0.21 + x * 0.1) + 0.04 * sin(z * 0.7 - x * 0.3)
	return h


func sea_level() -> float:
	return 0.14 * sin(time * 0.55) + 0.05 * sin(time * 1.7)


func mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	return Humanoid._mat(c, rough)


func tick(delta: float) -> void:
	time += delta
	tide_reach = 3.2 + 1.6 * sin(time * 0.55) + 0.5 * sin(time * 1.7)


func make_textures() -> void:
	var n := FastNoiseLite.new()
	n.seed = 3
	n.frequency = 0.02
	n.fractal_octaves = 4
	noise_tex = ImageTexture.create_from_image(n.get_seamless_image(256, 256))
	# fine grain normal map for sand
	var gn := FastNoiseLite.new()
	gn.seed = 8
	gn.frequency = 0.25
	gn.fractal_octaves = 3
	var gimg := gn.get_seamless_image(256, 256)
	gimg.bump_map_to_normal_map(1.2)
	sand_normal_tex = ImageTexture.create_from_image(gimg)

	# Window tile: pale wall, darker window, a ledge line at the bottom.
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(Color(1, 1, 1))
	for y in range(18, 46):
		for x in range(20, 44):
			img.set_pixel(x, y, Color(0.42, 0.5, 0.6))
	for y in range(50, 54):
		for x in 64:
			img.set_pixel(x, y, Color(0.9, 0.9, 0.9))
	window_tex = ImageTexture.create_from_image(img)

	# Cloud sprite: soft blobby fbm mask.
	var cn := FastNoiseLite.new()
	cn.seed = 9
	cn.frequency = 0.012
	cn.fractal_octaves = 5
	var w := 384
	var h := 192
	var cimg := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var u := (x - w * 0.5) / (w * 0.5)
			var v := (y - h * 0.5) / (h * 0.5)
			var r := sqrt(u * u + v * v * 2.2)
			var m := cn.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((m - 0.3) * 3.2 - r * r * 2.6 + 0.55, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a) * clampf((0.98 - r) * 12.0, 0.0, 1.0)
			# bright tops, grey-blue undersides
			var shade := clampf(1.02 - maxf(v + 0.15, 0.0) * 0.45 - (0.5 - m) * 0.2, 0.62, 1.0)
			cimg.set_pixel(x, y, Color(shade, shade, shade + 0.03, a))
	cloud_tex = ImageTexture.create_from_image(cimg)

	# Palm frond: serrated leaflets either side of a rib, alpha-cut.
	var fw := 256
	var fh := 64
	var fimg := Image.create(fw, fh, false, Image.FORMAT_RGBA8)
	for y in fh:
		for x in fw:
			var u := float(x) / fw
			var v := (float(y) / fh) * 2.0 - 1.0
			var half := 0.2 + 0.8 * sqrt(1.0 - u) * (0.55 + 0.45 * absf(sin(u * 70.0)))
			var rib := absf(v) < 0.08 * (1.0 - u) + 0.02
			var a := 1.0 if (absf(v) < half or rib) else 0.0
			var g := 0.36 + 0.22 * absf(sin(u * 70.0)) - 0.1 * absf(v)
			fimg.set_pixel(x, y, Color(0.12, g, 0.12, a))
	frond_tex = ImageTexture.create_from_image(fimg)

	# Soft disc for footprints / dust.
	var d := GradientTexture2D.new()
	d.fill = GradientTexture2D.FILL_RADIAL
	d.fill_from = Vector2(0.5, 0.5)
	d.fill_to = Vector2(0.5, 0.0)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	d.gradient = g
	d.width = 64
	d.height = 64
	soft_disc_tex = ImageTexture.create_from_image(d.get_image())
