shader_type spatial;

// Skin: wrap lighting with a warm scatter at the terminator, a soft sunlit
// sheen, and ambient darkening toward the ends of each lathed part.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform float normal_strength = 0.0;
uniform vec3 tint : source_color = vec3(1.0);
uniform vec3 scatter_color : source_color = vec3(0.85, 0.32, 0.22);
uniform float ao_ends = 0.28;
uniform float sheen = 0.05;

varying float v_v;

void vertex() {
	v_v = UV.y;
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * tint;
	float ends = smoothstep(0.3, 0.0, v_v) + smoothstep(0.7, 1.0, v_v);
	ALBEDO = c;
	AO = 1.0 - ao_ends * ends;
	ROUGHNESS = 0.78;
	SPECULAR = 0.15;
	if (normal_strength > 0.0) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_strength;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = clamp((ndl + 0.35) / 1.35, 0.0, 1.0);
	// warm scatter where light grazes into shadow
	float edge = smoothstep(-0.35, 0.15, ndl) * (1.0 - smoothstep(0.1, 0.55, ndl));
	vec3 diffuse = ALBEDO * wrap + scatter_color * ALBEDO * edge * 0.22;
	DIFFUSE_LIGHT += diffuse * LIGHT_COLOR * ATTENUATION;
	vec3 H = normalize(LIGHT + VIEW);
	float ndh = max(0.0, dot(NORMAL, H));
	float fres = pow(1.0 - max(0.0, dot(NORMAL, VIEW)), 3.0);
	float spec = pow(ndh, 48.0) * sheen + pow(ndh, 8.0) * sheen * 0.35 * fres;
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * spec * max(0.0, ndl);
}
