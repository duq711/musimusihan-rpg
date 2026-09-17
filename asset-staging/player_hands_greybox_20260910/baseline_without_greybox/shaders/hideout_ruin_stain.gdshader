shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform int stain_kind = 0;
uniform float opacity : hint_range(0.0, 1.0) = 0.82;
varying vec3 stain_world;

float stain_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float stain_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(stain_hash(i), stain_hash(i + vec2(1.0, 0.0)), f.x),
		mix(stain_hash(i + vec2(0.0, 1.0)), stain_hash(i + vec2(1.0)), f.x), f.y);
}

float stain_fbm(vec2 p) {
	return stain_noise(p) * 0.54 + stain_noise(p * 2.13 + 7.7) * 0.29
		+ stain_noise(p * 4.39 + 19.3) * 0.17;
}

void vertex() {
	stain_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 world_p = vec2(stain_world.x + stain_world.z * 0.713, stain_world.y + stain_world.z * 0.31);
	vec2 q = (UV - vec2(0.5)) * 2.0;
	float broad = stain_fbm(world_p * 1.7 + UV * 3.1);
	float grain = stain_fbm(world_p * 23.0 + UV * 31.0);
	float edge_warp = (broad - 0.5) * 0.55 + (grain - 0.5) * 0.10;
	float edge = 1.0 - smoothstep(0.66, 0.96, length(q) + edge_warp);
	// Guaranteed transparent perimeter prevents rectangular seams on large quads.
	float border = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	edge *= smoothstep(0.015, 0.13, border);
	float coverage = edge * mix(0.26, 0.70, smoothstep(0.25, 0.76, broad));
	coverage *= mix(0.46, 1.0, smoothstep(0.27, 0.70, grain));
	vec3 color = mix(vec3(0.016, 0.033, 0.008), vec3(0.047, 0.071, 0.021), grain);
	float roughness = 0.97;
	if (stain_kind == 1) {
		color = mix(vec3(0.007, 0.014, 0.010), vec3(0.041, 0.051, 0.028), grain);
		coverage *= mix(0.37, 1.0, smoothstep(0.32, 0.70, grain));
	} else if (stain_kind == 2) {
		float trails = stain_noise(vec2(world_p.x * 18.0, stain_world.y * 0.16 + 7.4));
		float fine_trails = stain_noise(vec2(world_p.x * 43.0, stain_world.y * 0.31 + 11.7));
		coverage *= 0.26 + smoothstep(0.43, 0.76, trails) * 0.54 + fine_trails * 0.20;
		color = mix(vec3(0.012, 0.025, 0.017), vec3(0.065, 0.078, 0.039), grain);
		roughness = 0.36;
	} else if (stain_kind == 3) {
		color = mix(vec3(0.005, 0.007, 0.005), vec3(0.026, 0.023, 0.017), grain);
		coverage *= 0.72;
	} else if (stain_kind == 4) {
		color = mix(vec3(0.12, 0.15, 0.11), vec3(0.24, 0.27, 0.20), grain);
		coverage *= smoothstep(0.59, 0.78, grain) * 0.27;
	}
	ALBEDO = color;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = stain_kind == 2 ? 0.52 : 0.17;
	ALPHA = clamp(coverage * opacity, 0.0, 0.94);
}
