class_name OceanLayer
extends BeachLayer

# The sea: one big grid with the water shader doing swells, depth colour,
# edge foam and breaker lines.

var material: ShaderMaterial


func build() -> void:
	var flat := func(_x: float, _z: float) -> float: return 0.0
	var mesh := grid_mesh(-12.0, 520.0, -WorldContext.CHUNK * 2.4, WorldContext.CHUNK * 1.4, 3.0, flat)
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/water.gdshader")
	material.set_shader_parameter("noise_tex", ctx.noise_tex)
	material.set_shader_parameter("sand_slope", WorldContext.SAND_SLOPE)
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
