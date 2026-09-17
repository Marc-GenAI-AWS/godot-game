extends SceneLayer

# The beach itself plus small scatter (shells, pebbles).
# Dark warm tan sand, fine grain, a wide wet band with a strong mirror sheet,
# shells and pebbles scattered along the tide line.

var material: ShaderMaterial


func build() -> void:
	var mesh := grid_mesh(-130.0, 70.0, -WorldContext.CHUNK * 2.2, WorldContext.CHUNK * 1.2, 2.0, ctx.ground_height)
	material = ShaderMaterial.new()
	material.shader = load("res://segments/ground/shaders/sand.gdshader")
	material.set_shader_parameter("noise_tex", ctx.noise_tex)
	material.set_shader_parameter("grain_normal", ctx.sand_normal_tex)
	material.set_shader_parameter("sky_color", ctx.sky_horizon)
	material.set_shader_parameter("dry_color", Color(0.56, 0.41, 0.26))
	material.set_shader_parameter("wet_color", Color(0.3, 0.22, 0.15))
	material.set_shader_parameter("grain_scale", 2.0)
	material.set_shader_parameter("wet_width", 14.0)
	material.set_shader_parameter("sheet_strength", 1.7)
	material.set_shader_parameter("ripple_depth", 0.6)
	material.set_shader_parameter("mottle", 1.1)
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = "Sand"
	mi.mesh = mesh
	add_child(mi)

	# Shells and pebbles along the tide line, as one MultiMesh.
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var count := 900
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sm := SphereMesh.new()
	sm.radius = 0.028
	sm.height = 0.028
	sm.radial_segments = 6
	sm.rings = 3
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.7
	sm.material = m
	mm.mesh = sm
	mm.instance_count = count
	for i in count:
		var x := rng.randf_range(-8.0, 3.0) + (rng.randf_range(-30.0, 0.0) if rng.randf() < 0.25 else 0.0)
		var z := rng.randf_range(-WorldContext.CHUNK * 2.1, WorldContext.CHUNK * 1.1)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(0.8, 2.2), 0.6, rng.randf_range(0.8, 1.6))), Vector3(x, ctx.ground_height(x, z) + 0.01, z))
		mm.set_instance_transform(i, t)
		var shade := rng.randf_range(0.55, 0.85)
		mm.set_instance_color(i, Color(shade, shade * 0.95, shade * 0.85) if rng.randf() < 0.7 else Color(0.35, 0.33, 0.3))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Shells"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func tick(_delta: float) -> void:
	material.set_shader_parameter("reach_x", ctx.tide_reach)
