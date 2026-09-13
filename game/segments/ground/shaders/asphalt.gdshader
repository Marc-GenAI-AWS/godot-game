shader_type spatial;

// Asphalt: grey-brown aggregate grain, darker wheel tracks in each lane,
// oil stains and repair patches, all from world-space noise.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec3 base_color : source_color = vec3(0.34, 0.33, 0.31);
uniform float lane_x = 1.9;      // lane centres at ±lane_x
uniform float track_offset = 0.8; // wheel tracks at lane ± offset

varying vec3 v_world;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float g1 = texture(noise_tex, v_world.xz * 0.9).r;
	float g2 = texture(noise_tex, v_world.xz * 4.0 + 0.3).r;
	float big = texture(noise_tex, v_world.xz * 0.05 + 0.6).r;
	vec3 col = base_color * (0.8 + 0.22 * g1 + 0.12 * g2) * (0.9 + 0.2 * big);
	// wheel tracks: darker, smoother bands
	float t = 0.0;
	for (int i = 0; i < 4; i++) {
		float cx = (i < 2 ? lane_x : -lane_x) + ((i % 2 == 0) ? track_offset : -track_offset);
		t += exp(-pow((v_world.x - cx) / 0.35, 2.0));
	}
	col *= 1.0 - 0.18 * clamp(t, 0.0, 1.0);
	// oil stains near lane centres and occasional patches
	float stain = smoothstep(0.62, 0.8, texture(noise_tex, v_world.xz * vec2(0.3, 0.08) + 0.2).r);
	col *= 1.0 - 0.25 * stain * exp(-pow(abs(abs(v_world.x) - lane_x) / 0.5, 2.0));
	float patch = smoothstep(0.72, 0.78, texture(noise_tex, v_world.xz * 0.02 + 0.9).r);
	col = mix(col, col * 0.85 + 0.02, patch);
	ALBEDO = col;
	ROUGHNESS = 0.95 - 0.1 * t;
	SPECULAR = 0.15;
}
