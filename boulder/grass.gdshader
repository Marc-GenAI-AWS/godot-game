shader_type spatial;
render_mode cull_disabled, world_vertex_coords, depth_draw_opaque;

// Grass blades: bent by scrolling wind noise, flattened by the boulder.

uniform sampler2D wind_noise : repeat_enable, filter_linear;
uniform vec3 boulder_pos = vec3(0.0, 1000.0, 0.0);
uniform float boulder_radius = 2.8;
uniform float wind_strength = 1.0;
uniform vec3 base_color : source_color = vec3(0.09, 0.26, 0.07);
uniform vec3 tip_color : source_color = vec3(0.36, 0.52, 0.17);
uniform vec3 dry_color : source_color = vec3(0.52, 0.5, 0.24);

varying float v_h;
varying float v_rnd;
varying float v_flat;

float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void vertex() {
	float h = UV.y;                       // 0 at root, 1 at tip
	vec3 root = MODEL_MATRIX[3].xyz;      // instance origin in world space
	float rnd = hash12(root.xz);
	v_h = h;
	v_rnd = rnd;

	// Wind: a slow gust field scrolling across the hill plus a fast flutter.
	vec2 wuv = root.xz * 0.018 + vec2(TIME * 0.05, TIME * 0.03);
	float gust = texture(wind_noise, wuv).r - 0.45;
	float flutter = sin(TIME * 2.6 + root.x * 0.7 + root.z * 0.5 + rnd * 6.2831) * 0.08;
	vec2 wind_dir = normalize(vec2(1.0, 0.45));
	float bend = h * h;                   // stiff at the root, floppy at the tip
	vec2 offset = wind_dir * (gust * 1.4 * wind_strength + flutter) * bend;

	// Boulder: blades near its footprint are shoved outward and pressed down.
	vec2 away = root.xz - boulder_pos.xz;
	float d = length(away);
	float near_ground = 1.0 - smoothstep(boulder_radius + 0.8, boulder_radius + 3.5, boulder_pos.y - root.y);
	float push = (1.0 - smoothstep(boulder_radius * 0.2, boulder_radius + 1.6, d)) * near_ground;
	offset += normalize(away + vec2(0.001)) * push * 1.5 * h;
	v_flat = push;

	VERTEX.xz += offset;
	VERTEX.y -= (length(offset) * 0.35 + push * 0.55 * h);
	NORMAL = vec3(0.0, 1.0, 0.0);         // light blades like the ground beneath them
}

void fragment() {
	vec3 col = mix(base_color, tip_color, v_h);
	col = mix(col, dry_color, v_rnd * v_rnd * 0.55);
	col *= 0.8 + 0.3 * v_rnd;
	col = mix(col, col * 0.7, v_flat * 0.6);
	ALBEDO = col;
	// Undo the back-face normal flip so both sides light like the ground.
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	ROUGHNESS = 0.95;
	SPECULAR = 0.15;
}
