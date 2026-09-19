shader_type spatial;
render_mode cull_disabled;

// Solid wood coordinates follow the shield, not the camera or Boolean UVs.
// The planks run along local Y; their exposed ends reveal X/Z growth rings.
uniform float ring_spacing = 0.0048;
uniform float relief_metres = 0.00032;
varying vec3 wood_position;

float wood_hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float wood_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(wood_hash(i), wood_hash(i + vec3(1,0,0)), f.x),
		mix(wood_hash(i + vec3(0,1,0)), wood_hash(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(wood_hash(i + vec3(0,0,1)), wood_hash(i + vec3(1,0,1)), f.x),
		mix(wood_hash(i + vec3(0,1,1)), wood_hash(i + vec3(1,1,1)), f.x), f.y), f.z);
}

void vertex() {
	wood_position = VERTEX;
}

void fragment() {
	vec3 p = wood_position;
	float board = floor((p.x + 0.0525) / 0.105);
	float seed = wood_hash(vec3(board, 7.0, 3.0));
	// Each board comes from a different off-centre section of the log. Ring
	// arcs continue through angled breaks instead of repeating on each face.
	float drift = (wood_noise(vec3(p.y * 3.0, seed * 9.0, 0.0)) - 0.5) * 0.006;
	vec2 section = vec2(p.x - board * 0.105 + (seed - 0.5) * 0.055 + drift,
		p.z + 0.025 + seed * 0.035);
	float radius = length(section * vec2(0.86, 1.0));
	float irregular = wood_noise(vec3(p.x * 75.0, p.y * 2.0, p.z * 75.0)) - 0.5;
	float phase = radius / ring_spacing + irregular * 0.72 + seed * 11.0;
	phase += sin(phase * 0.87 + seed * 5.0) * 0.27;
	phase += (wood_noise(vec3(p.x * 370.0, p.y * 7.0, p.z * 370.0)) - 0.5) * 0.16;
	float width = max(fwidth(phase), 0.015);
	float wave = 0.5 + 0.5 * sin(phase * 6.2831853);
	float latewood = smoothstep(0.76 - width, 0.97 + width, wave);
	latewood = mix(latewood, 0.22, smoothstep(0.30, 0.90, width));
	float fibres = wood_noise(vec3(p.x * 1050.0, p.y * 24.0, p.z * 1050.0));
	float coarse = wood_noise(vec3(p.x * 180.0, p.y * 18.0, p.z * 180.0));
	float pores = smoothstep(0.64, 0.86, fibres) * (0.3 + latewood * 0.7);
	float fibre_visibility = 1.0 - smoothstep(0.4, 1.8, length(fwidth(p) * vec3(1050.0, 24.0, 1050.0)));
	pores *= fibre_visibility;
	vec3 early_color = vec3(0.33, 0.218, 0.122);
	vec3 late_color = vec3(0.12, 0.061, 0.029);
	vec3 wood = mix(early_color, late_color, latewood * (0.51 + fibres * 0.35));
	wood *= mix(0.63, 1.16, coarse);
	wood *= 1.0 - pores * 0.65;
	wood += (fibres - 0.5) * 0.095 * fibre_visibility;
	ALBEDO = max(wood, vec3(0.01));
	ROUGHNESS = clamp(0.88 + latewood * 0.08 + pores * 0.04, 0.0, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.18;
	// Surface-gradient relief needs no tangent/UV coordinates on cut walls.
	float height = relief_metres * (coarse * 0.5 - latewood * 0.3 - pores + fibres * 0.25 * fibre_visibility);
	vec3 n = normalize(NORMAL);
	vec3 dx = dFdx(VERTEX);
	vec3 dy = dFdy(VERTEX);
	vec3 rx = cross(dy, n);
	vec3 ry = cross(n, dx);
	float determinant = dot(dx, rx);
	vec3 gradient = sign(determinant) * (dFdx(height) * rx + dFdy(height) * ry);
	NORMAL = normalize(max(abs(determinant), 0.00000001) * n - gradient);
}
