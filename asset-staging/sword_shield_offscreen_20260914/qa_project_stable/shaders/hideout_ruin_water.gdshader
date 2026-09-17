shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform bool ripple_only = false;
uniform float opacity : hint_range(0.0, 1.0) = 0.76;
uniform float wave_strength : hint_range(0.0, 2.0) = 1.0;
uniform float ripple_speed : hint_range(0.1, 2.0) = 0.52;
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
varying vec3 seep_world;

float water_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float water_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(water_hash(i), water_hash(i + vec2(1.0, 0.0)), f.x),
		mix(water_hash(i + vec2(0.0, 1.0)), water_hash(i + vec2(1.0)), f.x), f.y);
}

void vertex() {
	seep_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Trace the current opaque room, so wet surfaces reflect the actual masonry,
// roof openings and workstations. Offscreen rays fall back to the room probe.
// The fixed bound keeps the cost predictable and avoids another world render.
vec4 wet_reflection(vec3 origin, vec3 direction, mat4 projection, mat4 inverse_projection) {
	vec3 ray = origin;
	vec3 previous = ray;
	for (int step = 0; step < 28; step++) {
		previous = ray;
		ray += direction * (0.16 + float(step) * 0.032);
		vec4 clip = projection * vec4(ray, 1.0);
		if (clip.w <= 0.0) { break; }
		vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
		if (any(lessThan(uv, vec2(0.015))) || any(greaterThan(uv, vec2(0.985)))) { break; }
		float depth = textureLod(scene_depth, uv, 0.0).r;
		vec4 hit = inverse_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
		float gap = hit.z / hit.w - ray.z;
		if (depth > 0.00001 && gap > 0.0 && gap < 0.65) {
			for (int refine = 0; refine < 4; refine++) {
				vec3 middle = (previous + ray) * 0.5;
				vec4 middle_clip = projection * vec4(middle, 1.0);
				vec2 middle_uv = middle_clip.xy / middle_clip.w * 0.5 + 0.5;
				vec4 middle_hit = inverse_projection * vec4(middle_uv * 2.0 - 1.0, textureLod(scene_depth, middle_uv, 0.0).r, 1.0);
				if (middle_hit.z / middle_hit.w > middle.z) { ray = middle; uv = middle_uv; }
				else { previous = middle; }
			}
			float edge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
			float confidence = smoothstep(0.015, 0.13, edge) * (1.0 - float(step) / 42.0);
			return vec4(textureLod(scene_color, uv, 0.65).rgb, confidence);
		}
	}
	return vec4(0.0);
}

void fragment() {
	vec2 p = seep_world.xz;
	vec2 local_p = (UV - vec2(0.5)) * 2.0;
	float radius = length(local_p);
	float bank = water_noise(p * 3.6 + UV * 4.0);
	float shore = 1.0 - smoothstep(0.69, 0.99, radius + (bank - 0.5) * 0.25);
	float border = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	shore *= smoothstep(0.012, 0.11, border);
	float a = p.x * 16.7 + p.y * 10.3 + TIME * 0.73;
	float b = p.y * 28.1 - p.x * 14.9 - TIME * 0.56;
	float phase = fract(TIME * ripple_speed + water_hash(floor(seep_world.xz * 0.1)) * 0.7);
	float front = radius - phase * 0.85;
	float envelope = exp(-front * front * 21.0) * (1.0 - phase * 0.64);
	float ring = cos(front * 62.0) * envelope;
	vec2 direction = local_p / max(radius, 0.015);
	vec2 slope = vec2(cos(a) * 0.009 + cos(b) * 0.006,
		cos(a) * 0.007 - cos(b) * 0.009) * wave_strength;
	if (ripple_only) { slope += direction * ring * 0.10; }
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(-slope.x, 1.0, -slope.y)), 0.0)).xyz);
	float crest = pow(max(ring, 0.0), 3.0);
	ALBEDO = mix(vec3(0.007, 0.014, 0.012), vec3(0.019, 0.029, 0.020), bank)
		+ (ripple_only ? vec3(0.19, 0.23, 0.22) * crest : vec3(0.0));
	ROUGHNESS = ripple_only ? 0.065 : mix(0.08, 0.19, 1.0 - shore);
	METALLIC = 0.24;
	SPECULAR = 0.90;
	vec3 reflection_direction = reflect(normalize(VERTEX), NORMAL);
	vec4 reflection = wet_reflection(VERTEX + NORMAL * 0.045, reflection_direction, PROJECTION_MATRIX, INV_PROJECTION_MATRIX);
	float fresnel = 0.08 + 0.82 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = reflection.rgb * reflection.a * fresnel * 1.45
		+ (ripple_only ? vec3(0.28, 0.31, 0.29) * crest : vec3(0.0));
	ALPHA = shore * opacity * (ripple_only ? envelope * 0.92 : 1.0);
}
