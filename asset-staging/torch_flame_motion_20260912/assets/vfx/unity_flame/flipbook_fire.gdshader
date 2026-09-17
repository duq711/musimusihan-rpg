shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;
uniform sampler2D flame_atlas : source_color, filter_linear, repeat_disable;
uniform float phase = 0.0;
uniform float strength = 0.8;
uniform float playback_fps = 24.0;
vec4 sample_frame(float index, vec2 uv) {
    vec2 tile = vec2(mod(index, 16.0), floor(index / 16.0));
    vec2 inner = mix(vec2(0.5/128.0, 0.5/256.0), vec2(1.0-0.5/128.0, 1.0-0.5/256.0), uv);
    return texture(flame_atlas, (tile + inner) / vec2(16.0, 4.0));
}
void fragment() {
    float frame = mod(TIME * playback_fps + phase, 64.0);
    vec4 fire = mix(sample_frame(floor(frame), UV), sample_frame(mod(floor(frame)+1.0,64.0), UV), fract(frame));
    ALBEDO = fire.rgb * strength;
    EMISSION = ALBEDO;
    float edge = smoothstep(0.0, 0.075, UV.x) * smoothstep(0.0, 0.075, 1.0-UV.x);
    edge *= smoothstep(0.0, 0.06, UV.y) * smoothstep(0.0, 0.10, 1.0-UV.y);
    float facing = smoothstep(0.08, 0.38, abs(dot(normalize(NORMAL), normalize(VIEW))));
    ALPHA = fire.a * edge * facing;
}
