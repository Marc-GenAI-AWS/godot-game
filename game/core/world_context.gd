class_name WorldContext
extends Node

# Shared state every layer reads from. Layers never talk to each other
# directly; they read the context or listen to its signals. Worlds subclass
# this to add their terrain queries and constants (see worlds/beach).

signal world_wrapped(dz: float)                # player jumped back a chunk
signal player_step(pos: Vector3, side: int, yaw: float)

const CHUNK := 200.0          # scenery period along Z (player walks toward -Z)

var time := 0.0
var wind := Vector2(1.0, 0.45)
var player: Node3D
var player_vehicle: Node3D   # the player's car when a world has one (driven or parked)
var player_phase := 0.0       # walk-cycle phase, for camera bob etc.
var camera: Camera3D
# Camera framing the current player mode wants (the camera layer reads it).
var camera_profile := {"dist": 3.3, "height": 1.55, "look": 0.88, "fov": 60.0, "lookahead": 3.0}
var hud_hint := "Up: faster   Down: slower   Left / Right: steer   Space: jump   Drag: look around"
var hud_status := ""
var world_title := "Scene Studio"
var inspect := false        # orbit the player up close (URL #inspect)
var inspect_offset := Vector3.ZERO   # #inspect-crowd orbits the lounger rows instead
var lite := false           # skip optional detail for A/B timing (URL #lite)
var variant := "quaternius"  # which player body to use (URL #mpfb)
# Segment overrides for the verifier: segment name -> script path. A world
# asks ctx.layer("sky", SkyLayer) so a candidate layer can be swapped in
# without editing the world (--swap=sky=res://segments/sky/candidates/x.gd).
var overrides := {}

# Chosen from the right-click menu; empty means the layer's own default.
var player_sex := ""
var player_outfit := ""
var player_hair := ""
var player_pos := Vector3.ZERO      # carried across a rebuild so a swap does not teleport you
var player_heading := 0.0
var menu_available := false         # the right-click menu is present (not during captures)
var menu_used := false              # stop advertising it once they have found it


# segment -> the hand-built script the world asked for, so the right-click menu can
# put a layer back to "Original" without knowing how the world was assembled.
var defaults := {}
# instance id -> segment, so main can label each layer by identity. A world creates its
# layers in one order and may return them in another (the beach makes the player before
# the fauna but lists them the other way round), so position is not a safe label.
var built_of := {}


func layer(segment: String, default_script: GDScript) -> SceneLayer:
	defaults[segment] = default_script
	var inst: SceneLayer = null
	if overrides.has(segment):
		var s = load(str(overrides[segment]))
		if s is GDScript:
			var candidate = s.new()
			if candidate is SceneLayer:
				inst = candidate
		if inst == null:
			push_error("override for '%s' is not a SceneLayer script: %s" % [segment, overrides[segment]])
	if inst == null:
		inst = default_script.new()
	built_of[inst.get_instance_id()] = segment
	return inst

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


func obstacle_count() -> int:
	var n := 0
	for b in _obstacles:
		n += (_obstacles[b] as Array).size()
	return n


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


# Free distance along `dir` (xz) from `pos` before a circle (expanded by
# `radius`) is hit, up to `max_d`. Used by vehicles to follow instead of push.
func free_distance(pos: Vector3, dir: Vector3, radius: float, max_d: float) -> float:
	var best := max_d
	var p2 := Vector2(pos.x, pos.z)
	var d2 := Vector2(dir.x, dir.z).normalized()
	var checks: Array = []
	var b0 := int(floor(pos.z / OB_BUCKET))
	var span := int(ceil(max_d / OB_BUCKET)) + 1
	for b in range(b0 - span, b0 + span + 1):
		if _obstacles.has(b):
			for ob in _obstacles[b]:
				checks.append(ob)
	for ob in dynamic_obstacles:
		checks.append(ob)
	for ob in checks:
		var c := Vector2(ob[0].x, ob[0].z) - p2
		var r: float = ob[1] + radius
		var along := c.dot(d2)
		if along < -r or along > best + r:
			continue
		var perp := absf(c.cross(d2))
		if perp >= r:
			continue
		var hit := along - sqrt(r * r - perp * perp)
		if hit < best:
			best = maxf(hit, 0.0)
	return best


# Debug: nearest obstacle (static or dynamic) to a point: [distance, centre, radius, kind]
func nearest_obstacle(pos: Vector3) -> Array:
	var best := [INF, Vector3.ZERO, 0.0, "none"]
	var b0 := int(floor(pos.z / OB_BUCKET))
	for b in [b0 - 1, b0, b0 + 1]:
		if _obstacles.has(b):
			for ob in _obstacles[b]:
				var d: float = Vector2(pos.x - ob[0].x, pos.z - ob[0].z).length() - ob[1]
				if d < best[0]:
					best = [d, ob[0], ob[1], "static"]
	for ob in dynamic_obstacles:
		var d: float = Vector2(pos.x - ob[0].x, pos.z - ob[0].z).length() - ob[1]
		if d < best[0]:
			best = [d, ob[0], ob[1], "dynamic"]
	return best


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
var cloud_cover_tex: ImageTexture   # equirectangular cloud sheet with alpha, for ProceduralSkyMaterial.sky_cover
var window_tex: ImageTexture
var frond_tex: ImageTexture
var soft_disc_tex: ImageTexture


# ---- terrain / walkability interface (worlds override) ----

# Height of the terrain surface at (x, z).
func ground_height(_x: float, _z: float) -> float:
	return 0.0


# Height characters stand at (may include decks, kerbs, floors). Defaults to terrain.
func walk_height(x: float, z: float) -> float:
	return ground_height(x, z)


# Clamp a character position to the walkable area (before obstacle push-out).
func constrain(p: Vector3) -> Vector3:
	return p


# 0..1 how wet the ground is at a point (footprints darken / linger).
func wetness_at(_p: Vector3) -> float:
	return 0.0


func mat(c: Color, rough := 0.85) -> StandardMaterial3D:
	return Humanoid._mat(c, rough)


func tick(delta: float) -> void:
	time += delta
	dynamic_obstacles.clear()   # layers re-register moving obstacles each frame


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
	# Cloud-cover panorama: soft cloud masses with gaps, denser toward the
	# horizon rows, tileable across the seam; the sky material multiplies its
	# alpha by sky_cover_modulate.a so one texture serves broken to overcast.
	var pw := 512
	var ph := 256
	var pn := FastNoiseLite.new()
	pn.seed = 21
	pn.frequency = 0.9
	pn.fractal_octaves = 5
	pn.fractal_lacunarity = 2.1
	var pimg := Image.create(pw, ph, false, Image.FORMAT_RGBA8)
	for y in ph:
		var lat := 1.0 - float(y) / (ph - 1)          # 1 at the zenith row, 0.5 at the horizon, 0 at the nadir
		var above := clampf((lat - 0.53) / 0.1, 0.0, 1.0)   # nothing at or below the horizon; fade in just above it
		above = above * above * (3.0 - 2.0 * above)
		# isotropic in angle: the cylinder's circumference (2*pi*r) covers 360
		# degrees and one lat unit covers 180, so r = lat_scale / pi
		for x in pw:
			var ang := TAU * float(x) / pw
			var m := pn.get_noise_3d(cos(ang) * 2.55, lat * 8.0 + 3.0, sin(ang) * 2.55) * 0.5 + 0.5
			var d := pn.get_noise_3d(cos(ang) * 6.4 + 40.0, lat * 20.0, sin(ang) * 6.4) * 0.5 + 0.5
			var a := clampf((m - 0.4) * 3.2, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a) * above
			var shade := clampf(0.8 + (d - 0.5) * 0.3 + (m - 0.5) * 0.15, 0.6, 1.0)
			pimg.set_pixel(x, y, Color(shade, shade, shade, a))
	cloud_cover_tex = ImageTexture.create_from_image(pimg)

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
