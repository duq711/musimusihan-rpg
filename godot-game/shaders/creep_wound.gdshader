shader_type spatial;
render_mode cull_disabled;

// The cap's vertex colours describe tissue, dark recesses and bone. Detail
// stays in cap UV space when the skin deforms or the severed part tumbles.
float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}
void fragment() {
	float coarse = noise2(UV * 28.0);
	float grain = noise2(UV * vec2(185.0, 48.0));
	float fibres = smoothstep(0.57, 0.82, grain);
	bool bone = COLOR.g > COLOR.r * 0.58;
	vec3 tissue = COLOR.rgb * mix(0.50, 1.08, coarse) * (1.0 - fibres * 0.24);
	// The recessed centre receives less light than the exposed torn rim.
	tissue *= mix(0.42, 0.82, smoothstep(0.06, 0.48, length(UV - vec2(0.5))));
	ALBEDO = bone ? COLOR.rgb * mix(0.66, 1.0, coarse) : tissue;
	ROUGHNESS = bone ? 0.66 : mix(0.50, 0.68, grain);
	SPECULAR = bone ? 0.20 : 0.16;
	AO = mix(0.68, 1.0, coarse);
}
