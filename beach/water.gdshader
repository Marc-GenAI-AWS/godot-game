shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Shoreline ocean: sine swells, turquoise-to-navy depth colour, fake
// transparency onto sand in the shallows, animated foam at the water's edge
// and along breaking wave lines further out. The sand under the water is
// assumed to be y = -sand_slope * x (sea is +x).

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float sand_slope = 0.06;
uniform float tide_amp = 0.14;
uniform vec3 deep_color : source_color = vec3(0.01, 0.12, 0.32);
uniform vec3 shallow_color : source_color = vec3(0.06, 0.45, 0.5);
uniform vec3 sand_color : source_color = vec3(0.42, 0.36, 0.27);

varying vec3 v_world;
varying float v_depth;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float tide = tide_amp * sin(t * 0.55) + 0.05 * sin(t * 1.7);
	float shore = clamp(w.x / 18.0, 0.0, 1.0);
	float swell = 0.10 * sin(w.x * 0.35 - t * 1.1) + 0.05 * sin(w.z * 0.4 + w.x * 0.2 + t * 0.8)
		+ 0.03 * sin((w.x + w.z) * 1.6 - t * 2.3);
	float y = tide + swell * shore;
	VERTEX.y += y;
	v_world = vec3(w.x, y, w.z);
	v_depth = y + sand_slope * w.x;
	// Approximate normal from the same swell field for lighting.
	float dx = 0.10 * 0.35 * cos(w.x * 0.35 - t * 1.1) * shore;
	NORMAL = normalize(vec3(-dx, 1.0, 0.0));
}

void fragment() {
	float t = TIME;
	float d = v_depth;
	vec3 col = mix(shallow_color, deep_color, smoothstep(0.0, 7.0, d));
	// Shallows: let the sand show through.
	col = mix(sand_color, col, smoothstep(0.0, 0.7, d));

	// Foam at the water's edge, streaked and moving up the beach with the tide.
	float n1 = texture(noise_tex, v_world.xz * vec2(0.25, 0.08) + vec2(-t * 0.08, t * 0.02)).r;
	float n2 = texture(noise_tex, v_world.xz * vec2(0.9, 0.5) + vec2(t * 0.05, -t * 0.07)).r;
	float edge_foam = smoothstep(0.9, 0.0, d) * smoothstep(0.35, 0.7, n1 * 0.6 + n2 * 0.5);
	// Breaking lines: bands of foam rolling toward shore.
	float band = sin(v_world.x * 0.5 - t * 1.1 + n1 * 2.0);
	float breakers = smoothstep(0.75, 0.95, band) * smoothstep(3.0, 9.0, v_world.x) * smoothstep(40.0, 15.0, v_world.x);
	breakers *= smoothstep(0.3, 0.6, n2);
	float foam = clamp(edge_foam + breakers * 0.9, 0.0, 1.0);
	col = mix(col, vec3(0.85, 0.88, 0.9), foam);

	// Small ripple normals for sparkle.
	float r1 = texture(noise_tex, v_world.xz * 0.6 + vec2(t * 0.06, t * 0.04)).r;
	float r2 = texture(noise_tex, v_world.xz * 0.6 + vec2(0.013, 0.0) + vec2(t * 0.06, t * 0.04)).r;
	float r3 = texture(noise_tex, v_world.xz * 0.6 + vec2(0.0, 0.013) + vec2(t * 0.06, t * 0.04)).r;
	vec3 ripple = normalize(vec3((r1 - r2) * 6.0, 1.0, (r1 - r3) * 6.0));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(ripple, 0.0)).xyz, 0.18));

	ALBEDO = col;
	ROUGHNESS = mix(0.22, 0.7, foam);
	SPECULAR = 0.5;
	METALLIC = 0.0;
}
