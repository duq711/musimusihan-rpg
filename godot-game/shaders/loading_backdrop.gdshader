shader_type canvas_item;
render_mode unshaded;

// Static grading keeps the scene still; only the small loading ring moves.
void fragment() {
	vec3 scene = texture(TEXTURE, UV).rgb;
	float grey = dot(scene, vec3(0.299, 0.587, 0.114));
	scene = mix(scene, vec3(grey), 0.28);
	float edge = smoothstep(0.30, 0.73, length((UV - 0.5) * vec2(1.05, 1.0)));
	float lower_fade = smoothstep(0.64, 0.96, UV.y);
	float grain = fract(sin(dot(floor(UV * vec2(1920.0, 1080.0)), vec2(12.9898, 78.233))) * 43758.5453);
	scene *= (1.0 - edge * 0.76) * (1.0 - lower_fade * 0.91);
	scene += (grain - 0.5) * 0.009 * (1.0 - lower_fade);
	COLOR = vec4(max(scene, vec3(0.0)), 1.0);
}
