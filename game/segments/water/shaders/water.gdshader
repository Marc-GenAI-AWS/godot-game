shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

// Shoreline ocean: sine swells, turquoise-to-navy depth colour, fake
// transparency onto sand in the shallows, animated foam at the water's edge
// and along breaking wave lines further out. The sand under the water is
// assumed to be y = -sand_slope * x (sea is +x).
// Knobs (defaults reproduce the shipped look): swell_amp, chop, foam_amount,
// breaker_strength, breaker_spacing, clarity_depth, colours. Away from their
// defaults the knobs change what the chase camera sees: chop below 1 glasses
// the surface over and above 1 flecks the open water with whitecaps;
// foam_amount widens or narrows the edge zones while the band stays lacy;
// breaker_strength sets how wide the breaker lines are.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform float sand_slope = 0.06;
uniform float tide_amp = 0.14;
uniform vec3 deep_color : source_color = vec3(0.0, 0.16, 0.42);
uniform vec3 shallow_color : source_color = vec3(0.02, 0.34, 0.46);
uniform vec3 sand_color : source_color = vec3(0.38, 0.31, 0.23);
uniform float swell_amp = 1.0;          // 0.3 calm .. 2.0 big swell
uniform float chop = 1.0;               // small high-frequency waves (0 = glassy)
uniform float foam_amount = 1.0;        // edge foam density (0 = none, 2 = heavy)
uniform float breaker_strength = 1.0;   // foam lines further out (0 = none)
uniform float breaker_spacing = 1.0;    // 0.5 = tight lines, 2.0 = wide
uniform float clarity_depth = 1.0;      // how far the sand shows through (0.3 murky .. 3.0 very clear)
uniform float sparkle = 1.0;            // ripple normal strength

varying vec3 v_world;
varying float v_depth;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float tide = tide_amp * sin(t * 0.55) + 0.05 * sin(t * 1.7);
	float shore = clamp(w.x / 18.0, 0.0, 1.0);
	float swell = (0.10 * sin(w.x * 0.35 - t * 1.1) + 0.05 * sin(w.z * 0.4 + w.x * 0.2 + t * 0.8)) * swell_amp
		+ 0.03 * sin((w.x + w.z) * 1.6 - t * 2.3) * chop;
	float y = tide + swell * shore;
	VERTEX.y += y;
	v_world = vec3(w.x, y, w.z);
	v_depth = y + sand_slope * w.x;
	// Approximate normal from the same swell field for lighting.
	float dx = 0.10 * 0.35 * cos(w.x * 0.35 - t * 1.1) * shore * swell_amp;
	NORMAL = normalize(vec3(-dx, 1.0, 0.0));
}

void fragment() {
	float t = TIME;
	float d = v_depth;
	vec3 col = mix(shallow_color, deep_color, smoothstep(0.0, 7.0, d));
	// Shallows: let the sand show through.
	col = mix(sand_color, col, smoothstep(0.0, 0.28 * clarity_depth, d));

	// Water's edge in three zones (d = water depth over the sand):
	//  wash  d < ~0.05  thin dark film that mirrors the sky
	//  band  0.04-0.2   dense foam broken by lace holes
	//  outer 0.2-0.5    sparse lace streaks
	float n1 = texture(noise_tex, v_world.xz * vec2(0.25, 0.08) + vec2(-t * 0.08, t * 0.02)).r;
	float n2 = texture(noise_tex, v_world.xz * vec2(0.9, 0.5) + vec2(t * 0.05, -t * 0.07)).r;
	float n4 = texture(noise_tex, v_world.xz * vec2(1.8, 1.1) + vec2(-t * 0.11, t * 0.04)).r;
	// weighted noise sum normalised to 0..1 (mean ~0.5): the thresholds below
	// are coverage fractions, so the band keeps holes and the streaks stay sparse
	float lace = (n1 * 0.45 + n2 * 0.5 + n4 * 0.35) / 1.3;
	// foam_amount scales the width of the band and the streaks; above 1 the
	// lace holes close only a little further, so heavy foam is a wider lacy
	// band rather than a solid white sheet
	float fw = 0.45 + 0.55 * foam_amount;
	float fa = min(foam_amount, 1.4);
	float wash = smoothstep(0.07, 0.015, d);
	// band ~0.3-2.7 m out from the water line, streaks ~2-6.7 m (sand slope 0.06)
	float foam_band = smoothstep(0.02, 0.05, d) * smoothstep(0.16 * fw, 0.09 * fw, d);
	float outer = smoothstep(0.12 * fw, 0.18 * fw, d) * smoothstep(0.4 * fw, 0.24 * fw, d);
	// The band is lace with holes (sand shows through between the patches)
	// rather than a solid white strip; foam_amount closes the holes.
	float edge_foam = foam_band * smoothstep(0.42, 0.58, lace + 0.08 * (fa - 1.0))
		+ outer * smoothstep(0.58, 0.7, lace + 0.1 * (fa - 1.0));
	edge_foam = max(edge_foam, wash * smoothstep(0.55, 0.7, lace) * 0.5);
	edge_foam *= clamp(foam_amount, 0.0, 1.0);
	vec3 wet_film = mix(sand_color * 0.6, vec3(0.32, 0.46, 0.64), 0.3);
	col = mix(col, wet_film, wash);
	// Breaking lines: bands of foam rolling toward shore. Strength widens the
	// lines (and fades them below 1) instead of brightening past white.
	float bs = breaker_strength;
	float band = sin(v_world.x * 0.5 / breaker_spacing - t * 1.1 + n1 * 2.0);
	float lo = 0.95 - 0.2 * min(bs, 1.5);
	float breakers = smoothstep(lo, lo + 0.2, band) * smoothstep(3.0, 9.0, v_world.x) * smoothstep(40.0, 15.0, v_world.x);
	breakers *= smoothstep(0.3, 0.6, n2) * min(bs, 1.0);
	// Whitecaps: a choppy sea flecks the open water with small foam patches
	// (none at chop <= 1).
	float nc1 = texture(noise_tex, v_world.xz * vec2(0.07, 0.11) + vec2(-t * 0.03, t * 0.02)).r;
	float nc2 = texture(noise_tex, v_world.xz * 0.45 + vec2(t * 0.09, -t * 0.05)).r;
	float caps = smoothstep(0.62, 0.8, nc1 * 0.6 + nc2 * 0.55) * smoothstep(1.0, 1.6, chop) * smoothstep(12.0, 30.0, v_world.x);
	float foam = clamp(edge_foam + breakers * 0.9 + caps * 0.85, 0.0, 1.0);
	col = mix(col, vec3(0.88, 0.91, 0.94) * (0.82 + 0.18 * n2), foam);

	// Small ripple normals for sparkle; a calm sea (chop < 1) glasses over,
	// a choppy one roughens.
	float r1 = texture(noise_tex, v_world.xz * 0.6 + vec2(t * 0.06, t * 0.04)).r;
	float r2 = texture(noise_tex, v_world.xz * 0.6 + vec2(0.013, 0.0) + vec2(t * 0.06, t * 0.04)).r;
	float r3 = texture(noise_tex, v_world.xz * 0.6 + vec2(0.0, 0.013) + vec2(t * 0.06, t * 0.04)).r;
	vec3 ripple = normalize(vec3((r1 - r2) * 6.0, 1.0, (r1 - r3) * 6.0));
	float calm = clamp(chop, 0.0, 1.0);
	float rough_sea = max(chop - 1.0, 0.0);
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(ripple, 0.0)).xyz, 0.12 * sparkle * mix(0.35, 1.0, calm) * (1.0 + 0.6 * rough_sea)));

	ALBEDO = col;
	// Ragged water's edge: fade the sheet out over the last centimetres of
	// depth with noise so the plane/sand intersection is not a straight line.
	ALPHA = smoothstep(-0.01, 0.035, d + (n4 - 0.5) * 0.06);
	float base_rough = mix(0.12, 0.3, calm) + 0.1 * rough_sea;
	ROUGHNESS = mix(mix(base_rough, 0.15, wash), 0.85, foam);
	SPECULAR = mix(mix(0.3, 0.4, wash), 0.15, foam);
	METALLIC = 0.0;
}
