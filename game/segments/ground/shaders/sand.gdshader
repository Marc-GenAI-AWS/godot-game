shader_type spatial;

// Beach sand: dark warm tan, fine grain, a wet band that darkens, and a thin
// water sheet at the wave's reach that mirrors the sky at grazing angles.
// `reach_x` is the world-space x of the wet line (sea is +x).
// Knobs (defaults reproduce the shipped look): grain_scale, wet_width,
// sheet_strength, ripple_depth, tone colours.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D grain_normal : hint_normal, repeat_enable, filter_linear_mipmap;
uniform float reach_x = 3.0;
uniform vec3 dry_color : source_color = vec3(0.56, 0.41, 0.26);
uniform vec3 wet_color : source_color = vec3(0.3, 0.22, 0.15);
uniform vec3 sky_color : source_color = vec3(0.62, 0.78, 0.95);
uniform float grain_scale = 1.0;      // 0.5 = coarse, 2.0 = very fine
uniform float wet_width = 10.0;       // metres the wet band extends up the beach from the wet line
uniform float sheet_strength = 1.0;   // 0 = no mirror sheet, 2 = strong
uniform float ripple_depth = 1.0;     // scales the grain normal (0 = smooth packed sand)
uniform float mottle = 1.0;           // large-scale tone variation

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n1 = texture(noise_tex, v_world.xz * 0.12 * grain_scale).r;
	float n2 = texture(noise_tex, v_world.xz * 0.9 * grain_scale + 0.3).r;
	float n3 = texture(noise_tex, v_world.xz * 0.03 + 0.7).r;
	vec3 base = dry_color * (0.84 + (0.2 * n1 + 0.08 * n2) * mottle + 0.1 * n3 * mottle);
	// Wetness ramps up over the last metres before the wet line, ragged edge.
	float edge = reach_x + (n1 - 0.5) * 3.0;
	float wet = smoothstep(edge - wet_width, edge - 0.6, v_world.x);
	// Thin sheet of water left by the last wave: near-mirror.
	float sheet = smoothstep(edge - 3.5, edge - 0.4, v_world.x) * (0.6 + 0.4 * n3) * clamp(sheet_strength, 0.0, 2.0);
	vec3 col = mix(base, wet_color * (0.9 + 0.2 * n1), wet * 0.92);
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	col = mix(col, sky_color * 0.55, clamp(sheet * fres * 0.45, 0.0, 1.0));
	ALBEDO = col;
	NORMAL_MAP = texture(grain_normal, v_world.xz * 2.5 * grain_scale).rgb;
	NORMAL_MAP_DEPTH = mix(0.25, 0.05, clamp(sheet, 0.0, 1.0)) * ripple_depth;
	ROUGHNESS = mix(0.95, 0.12, max(wet * 0.5, clamp(sheet, 0.0, 1.0)));
	SPECULAR = mix(0.1, 0.45, clamp(sheet, 0.0, 1.0));
	METALLIC = 0.0;
}
