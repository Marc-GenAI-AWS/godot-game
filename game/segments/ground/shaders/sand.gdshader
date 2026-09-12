shader_type spatial;

// Beach sand: dark warm tan, fine grain, a wet band that darkens, and a thin
// water sheet at the wave's reach that mirrors the sky at grazing angles.
// `reach_x` is the world-space x of the wet line (sea is +x).

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D grain_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float reach_x = 3.0;
uniform vec3 dry_color : source_color = vec3(0.56, 0.41, 0.26);
uniform vec3 wet_color : source_color = vec3(0.3, 0.22, 0.15);
uniform vec3 sky_color : source_color = vec3(0.62, 0.78, 0.95);

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n1 = texture(noise_tex, v_world.xz * 0.12).r;
	float n2 = texture(noise_tex, v_world.xz * 0.9 + 0.3).r;
	float n3 = texture(noise_tex, v_world.xz * 0.03 + 0.7).r;
	vec3 base = dry_color * (0.84 + 0.2 * n1 + 0.08 * n2 + 0.1 * n3);
	// Wetness ramps up over the last metres before the wet line, ragged edge.
	float edge = reach_x + (n1 - 0.5) * 3.0;
	float wet = smoothstep(edge - 10.0, edge - 0.6, v_world.x);
	// Thin sheet of water left by the last wave: near-mirror.
	float sheet = smoothstep(edge - 3.5, edge - 0.4, v_world.x) * (0.6 + 0.4 * n3);
	vec3 col = mix(base, wet_color * (0.9 + 0.2 * n1), wet * 0.92);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	col = mix(col, sky_color * 0.55, sheet * fres * 0.45);
	ALBEDO = col;
	NORMAL_MAP = texture(grain_normal, v_world.xz * 2.5).rgb;
	NORMAL_MAP_DEPTH = mix(0.25, 0.05, sheet);
	ROUGHNESS = mix(0.95, 0.12, max(wet * 0.5, sheet));
	SPECULAR = mix(0.1, 0.45, sheet);
	METALLIC = 0.0;
}
