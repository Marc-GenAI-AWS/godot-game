shader_type spatial;

// Beach sand: dry and mottled up the beach, dark and glossy where the last
// wave reached. `reach_x` is the world-space x of the wet line (sea is +x).

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float reach_x = 3.0;
uniform vec3 dry_color : source_color = vec3(0.66, 0.52, 0.34);
uniform vec3 wet_color : source_color = vec3(0.42, 0.34, 0.25);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n1 = texture(noise_tex, v_world.xz * 0.12).r;
	float n2 = texture(noise_tex, v_world.xz * 0.9 + 0.3).r;
	vec3 base = dry_color * (0.86 + 0.2 * n1 + 0.08 * n2);
	// Wetness ramps up over the last few metres before the wet line, with a
	// ragged edge from the noise so it is not a straight band.
	float edge = reach_x + (n1 - 0.5) * 3.0;
	float wet = smoothstep(edge - 9.0, edge - 0.5, v_world.x);
	vec3 col = mix(base, wet_color * (0.9 + 0.2 * n1), wet * 0.9);
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.18, wet);
	SPECULAR = mix(0.1, 0.5, wet);
	METALLIC = 0.0;
}
