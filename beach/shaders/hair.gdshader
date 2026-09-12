shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Hair ribbons: alpha-cut strand texture, per-strand sway (seed in vertex
// colour), and a Kajiya-Kay style anisotropic highlight along the strand.

uniform sampler2D strand_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.24, 0.14, 0.08);
uniform vec3 tip_color : source_color = vec3(0.4, 0.25, 0.13);
uniform float sway_amp = 0.02;
uniform float shine = 0.14;

varying vec3 v_strand;   // strand direction in view space
varying float v_v;
varying float v_seed;

void vertex() {
	float v = UV.y;                      // 0 = root, 1 = tip
	float seed = COLOR.r;
	float t = TIME;
	float sway = sin(t * 2.1 + seed * 6.2831) * 0.55 + sin(t * 3.7 + seed * 12.0) * 0.3 + sin(t * 0.7 + seed * 3.0) * 0.4;
	float lift = sin(t * 1.6 + seed * 9.0) * 0.3;
	VERTEX += vec3(sway, lift * 0.3, lift) * sway_amp * v * v;
	v_v = v;
	v_seed = seed;
	v_strand = normalize((MODELVIEW_MATRIX * vec4(BINORMAL, 0.0)).xyz);
}

void fragment() {
	vec4 tex = texture(strand_tex, vec2(UV.x * 2.0 + v_seed, UV.y * 3.0));
	ALPHA = tex.a * (1.0 - smoothstep(0.85, 1.0, v_v) * 0.6);
	ALPHA_SCISSOR_THRESHOLD = 0.3;
	vec3 col = mix(base_color, tip_color, v_v * 0.7);
	ALBEDO = col * (0.8 + 0.5 * tex.r);
	ROUGHNESS = 0.55;
	SPECULAR = 0.2;
	AO = 0.75 + 0.25 * v_v;
}

void light() {
	vec3 T = normalize(v_strand);
	vec3 H = normalize(LIGHT + VIEW);
	float dotTH = dot(T, H);
	float sinTH = sqrt(max(0.0, 1.0 - dotTH * dotTH));
	float spec1 = pow(sinTH, 80.0) * shine;
	float spec2 = pow(sinTH, 18.0) * shine * 0.25;
	float dotTL = dot(T, LIGHT);
	float diff = sqrt(max(0.0, 1.0 - dotTL * dotTL));   // strands lit from any side
	float ndl = max(0.0, dot(NORMAL, LIGHT)) * 0.5 + 0.5;
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * (0.35 + 0.65 * diff * ndl);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * (spec1 + spec2) * (0.6 + 0.4 * diff) * mix(vec3(1.0), ALBEDO * 3.0, 0.6);
}
