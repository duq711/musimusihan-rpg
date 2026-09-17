shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;
varying vec3 water_position;
void vertex() { water_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec2 p = water_position.xz;
    float a = sin(p.x * 5.0 + p.y * 2.8 + TIME * 0.65);
    float b = cos(p.y * 7.3 - p.x * 1.8 + TIME * 0.48);
    ALBEDO = vec3(0.025, 0.063, 0.061) + (a * b * 0.009);
    ROUGHNESS = 0.18;
    METALLIC = 0.32;
    SPECULAR = 0.7;
    NORMAL = normalize((VIEW_MATRIX * vec4(a * 0.065, 1.0, b * 0.065, 0.0)).xyz);
    ALPHA = 0.72;
}
