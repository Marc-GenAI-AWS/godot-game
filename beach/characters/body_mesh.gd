class_name BodyMesh
extends RefCounted

# Mesh + texture generators for the character rig. Everything is built from
# profiles (surface of revolution with elliptical cross-sections) and tubes
# swept along curves, so body parts are smooth instead of boxy.


# profile: Array of Vector3(y, radius_x, radius_z), bottom to top.
# Returns an indexed mesh with smooth normals and (u around, v along) UVs.
static func lathe(profile: Array, segs: int, y_offset := 0.0, a0 := 0.0, a1 := TAU) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := profile.size()
	for r in rows:
		var p: Vector3 = profile[r]
		for s in segs + 1:
			var a := lerpf(a0, a1, float(s) / segs)
			st.set_uv(Vector2(float(s) / segs, float(r) / (rows - 1)))
			st.add_vertex(Vector3(cos(a) * p.y, p.x + y_offset, sin(a) * p.z))
	_ring_indices(st, rows, segs)
	st.generate_normals()
	return st.commit()


# Sweep an elliptical ring along a polyline. radii: Array of Vector2 per point.
static func tube(points: Array, radii: Array, segs: int, wide_axis := Vector3.ZERO) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := points.size()
	for r in rows:
		var p: Vector3 = points[r]
		var t: Vector3
		if r == 0:
			t = (points[1] - points[0]).normalized()
		elif r == rows - 1:
			t = (points[r] - points[r - 1]).normalized()
		else:
			t = (points[r + 1] - points[r - 1]).normalized()
		var n: Vector3
		if wide_axis != Vector3.ZERO:
			# keep the ring's wide axis along the requested direction
			n = (wide_axis - t * t.dot(wide_axis)).normalized()
		else:
			var ref := Vector3.RIGHT if absf(t.dot(Vector3.RIGHT)) < 0.9 else Vector3.UP
			n = ref.cross(t).normalized()
		var b := t.cross(n).normalized()
		var rad: Vector2 = radii[r]
		for s in segs + 1:
			var a := TAU * s / segs
			st.set_uv(Vector2(float(s) / segs, float(r) / (rows - 1)))
			st.add_vertex(p + n * cos(a) * rad.x + b * sin(a) * rad.y)
	_ring_indices(st, rows, segs)
	st.generate_normals()
	return st.commit()


static func _ring_indices(st: SurfaceTool, rows: int, segs: int) -> void:
	for r in rows - 1:
		for s in segs:
			var i0 := r * (segs + 1) + s
			var i1 := i0 + 1
			var i2 := i0 + segs + 1
			var i3 := i2 + 1
			st.add_index(i0); st.add_index(i1); st.add_index(i2)
			st.add_index(i1); st.add_index(i3); st.add_index(i2)


# Smooth interpolation helper for building profiles from a few key points.
static func profile_from_keys(keys: Array, steps_per_key := 3) -> Array:
	# keys: Array of Vector3(y, rx, rz). Catmull-Rom between them.
	var out := []
	var n := keys.size()
	for i in n - 1:
		var p0: Vector3 = keys[maxi(i - 1, 0)]
		var p1: Vector3 = keys[i]
		var p2: Vector3 = keys[i + 1]
		var p3: Vector3 = keys[mini(i + 2, n - 1)]
		for k in steps_per_key:
			var t := float(k) / steps_per_key
			out.append(_catmull(p0, p1, p2, p3, t))
	out.append(keys[n - 1])
	return out


static func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


# ---------------------------------------------------------------- textures

static func floral_top_texture(base: Color) -> ImageTexture:
	var w := 128
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = 17
	n.frequency = 0.09
	n.fractal_octaves = 2
	var petal := Color(0.78, 0.18, 0.32)
	var leaf := Color(0.55, 0.62, 0.45)
	var cream := Color(0.98, 0.9, 0.9)
	for y in h:
		for x in w:
			var v := n.get_noise_2d(x, y)
			var v2 := n.get_noise_2d(x * 2.3 + 50.0, y * 2.3)
			var c := base
			if v > 0.22:
				c = petal.lerp(base, clampf((0.4 - v) * 4.0, 0.0, 0.6))
			elif v < -0.28:
				c = leaf
			if v2 > 0.42:
				c = cream
			# lace-like lighter band at the top and bottom edges
			if y < 6 or y > h - 7:
				c = c.lerp(cream, 0.5)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func denim_texture(base: Color) -> ImageTexture:
	# u wraps around the shorts (0 = right side, 0.25 = back centre,
	# 0.5 = left side, 0.75 = front centre). v: 0 = hem, 1 = waistband.
	var w := 256
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = 23
	n.frequency = 0.9
	var dark := base.darkened(0.35)
	var thread := Color(0.85, 0.72, 0.45)
	var label := Color(0.92, 0.88, 0.78)
	for y in h:
		for x in w:
			var u := float(x) / w
			var v := float(y) / h
			var grain := n.get_noise_2d(x * 3.0, y * 0.6) * 0.5 + 0.5
			var c := base.lerp(base.lightened(0.18), grain * 0.6)
			# vertical whisker fade lighter toward the seat / front
			c = c.lightened(0.08 * (1.0 - absf(sin(u * TAU))))
			# side seams and centre seams
			for seam in [0.0, 0.25, 0.5, 0.75]:
				if absf(u - seam) < 0.006 or absf(u - seam - 1.0) < 0.006:
					c = dark
				if absf(u - seam) < 0.012 and absf(u - seam) >= 0.006:
					c = thread if int(y / 3) % 2 == 0 else c
			# waistband
			if v > 0.9:
				c = c.darkened(0.12)
				if v > 0.895 and v < 0.915:
					c = thread
			# frayed hem
			if v < 0.05:
				c = c.lerp(Color(0.9, 0.9, 0.88), 0.55)
				if int(x / 2) % 3 == 0 and v < 0.03:
					c = Color(0.93, 0.93, 0.9)
			# back pockets (either side of the back centre seam)
			for pc in [0.17, 0.33]:
				var du := absf(u - pc)
				if du < 0.055 and v > 0.45 and v < 0.82:
					var edge := du > 0.048 or v < 0.47 or v > 0.80
					c = thread if edge else c.darkened(0.06)
			# white leather label on the back-right waistband
			if u > 0.31 and u < 0.36 and v > 0.905 and v < 0.985:
				c = label
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func skin_texture(base: Color, tattoo: bool) -> ImageTexture:
	var w := 64
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = 29
	n.frequency = 0.15
	for y in h:
		for x in w:
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var c := base.lerp(base.darkened(0.08), v)
			if tattoo:
				# small dark motif on the back of the thigh (u around: back ≈ 0.25)
				var u := float(x) / w
				var vv := float(y) / h
				var d := Vector2((u - 0.28) * 3.0, (vv - 0.62) * 2.2).length()
				if d < 0.12 or (d < 0.2 and sin(atan2(vv - 0.62, u - 0.28) * 5.0) > 0.6):
					c = Color(0.15, 0.12, 0.14)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


static func hair_texture(base: Color) -> ImageTexture:
	# thin vertical streaks so strands read as many hairs
	var w := 32
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var n := FastNoiseLite.new()
	n.seed = 41
	n.frequency = 0.5
	for y in h:
		for x in w:
			var v := n.get_noise_2d(x * 4.0, y * 0.15) * 0.5 + 0.5
			img.set_pixel(x, y, base.lerp(base.lightened(0.3), v * 0.6))
	return ImageTexture.create_from_image(img)
