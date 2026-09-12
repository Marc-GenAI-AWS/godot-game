class_name WorldContext
extends Node

# Shared state every layer reads from. Layers never talk to each other
# directly; they read the context or listen to its signals.

signal world_wrapped(dz: float)                # player jumped back a chunk
signal player_step(pos: Vector3, side: int, yaw: float)

const CHUNK := 200.0          # scenery period along Z (player walks toward -Z)
const SAND_SLOPE := 0.06      # sand drops this much per metre into the sea (+X)
const LAND_SLOPE := 0.03      # and rises this much per metre up the beach (-X)
const BOARDWALK_X := -66.0

var time := 0.0
var tide_reach := 3.0         # world X the last wave reached (wet line)
var wind := Vector2(1.0, 0.45)
var player: Node3D
var player_phase := 0.0       # walk-cycle phase, for camera bob etc.
var camera: Camera3D
var inspect := false        # orbit the player up close (URL #inspect)
var lite := false           # skip optional detail for A/B timing (URL #lite)
var variant := "quaternius"  # which player body to use (URL #mpfb)

var noise_tex: ImageTexture
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
			var a := clampf((m - 0.35) * 3.0 - r * 1.3 + 0.55, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			var shade := clampf(1.0 - (v + 0.4) * 0.25, 0.7, 1.0)
			cimg.set_pixel(x, y, Color(shade, shade, shade + 0.02, a))
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
