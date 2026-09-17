shader_type spatial;
render_mode cull_disabled, depth_draw_never;
uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D scene_color : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float water_clock = 0.0;
uniform vec4 ripple_events[24];
uniform float detail_normal_strength = 1.8;
uniform float reflection_roughness = 0.20;
varying vec3 water_world;

vec4 waves(vec2 p) {
    float t = water_clock;
    float a = p.x * 2.7 + p.y * 1.8 + t * 0.52;
    float b = p.x * -1.3 + p.y * 3.9 - t * 0.39;
    vec4 wave = vec4(sin(a) * 0.0023 + sin(b) * 0.0017,
        cos(a) * 0.0062 - cos(b) * 0.0022, cos(a) * 0.0041 + cos(b) * 0.0066, 0.0);
    // Millimetre-scale crossing ripples break up reflected lamp light while
    // preserving the low, slow silhouette of sheltered cave water.
    vec2 small_p = p + vec2(sin(p.y * 0.37), sin(p.x * 0.29)) * 0.17;
    float fine_a = (small_p.x * 14.3 + small_p.y * 9.7) * 1.8 + t * 0.83;
    float fine_b = (small_p.x * -19.1 + small_p.y * 13.2) * 1.8 - t * 1.14;
    float fine_c = (small_p.x * 31.7 + small_p.y * 4.1) * 1.8 + t * 0.65;
    wave.yz += (vec2(0.0172, 0.0116) * cos(fine_a)
        + vec2(-0.0153, 0.0106) * cos(fine_b)
        + vec2(0.0127, 0.0016) * cos(fine_c)) * detail_normal_strength;
    for (int i = 0; i < 24; i++) {
        float age = t - ripple_events[i].z;
        if (age >= 0.0 && age < 4.2 && ripple_events[i].w > 0.0) {
            vec2 offset = p - ripple_events[i].xy;
            float radius = max(length(offset), 0.001);
            float front = radius - age * 1.25;
            // A broader packet carries several small crests after each step.
            // Only foot contacts receive this amplitude; ambient waves stay calm.
            float envelope = exp(-front * front * 4.2) * exp(-age * 0.78) * smoothstep(0.0, 0.12, age);
            float strength = ripple_events[i].w * envelope;
            float phase = front * 17.0 + sin(p.x * 1.1 + p.y * 0.8) * 0.14;
            wave.x += sin(phase) * strength * 0.014;
            wave.yz += offset / radius * cos(phase) * strength * 0.27;
            // Sparse crest scattering is lit by the scene, never emissive white
            // rings. The grain breaks the crest into small disturbed patches.
            float crest_grain = 0.55 + 0.45 * sin(p.x * 13.7 + p.y * 9.3 + cos(p.y * 4.6));
            wave.w += pow(max(sin(phase), 0.0), 6.0) * strength * crest_grain * 0.38;
        }
    }
    return wave;
}

vec3 scene_position(vec2 screen_uv, mat4 inverse_projection) {
    float depth = texture(scene_depth, screen_uv).r;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
    vec3 ndc = vec3(screen_uv, depth) * 2.0 - 1.0;
    #else
    vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth);
    #endif
    vec4 position = inverse_projection * vec4(ndc, 1.0);
    return position.xyz / position.w;
}

void vertex() {
    water_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    VERTEX.y += waves(water_world.xz).x * smoothstep(0.0, 0.65, UV2.x);
}

void fragment() {
    vec2 p = water_world.xz;
    float bank_detail = sin(p.x * 9.7 + sin(p.y * 4.3)) * sin(p.y * 8.1 - p.x * 2.0) * 0.028;
    float shore = smoothstep(0.0, 0.24, UV2.x + bank_detail);
    if (shore < 0.005) { discard; }
    vec4 wave = waves(p);
    vec3 world_normal = normalize(vec3(-wave.y, 1.0, -wave.z));
    NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
    vec3 floor_view = scene_position(SCREEN_UV, INV_PROJECTION_MATRIX);
    vec3 floor_world = (INV_VIEW_MATRIX * vec4(floor_view, 1.0)).xyz;
    float real_depth = max(water_world.y - floor_world.y, 0.0);
    float contact_fade = smoothstep(0.005, 0.09, real_depth);
    float depth = min(real_depth, max(UV2.y, 0.035));
    float fresnel = 0.025 + 0.78 * pow(1.0 - max(dot(normalize(VIEW), NORMAL), 0.0), 5.0);
    vec2 distortion = wave.yz * min(depth, 0.4) * 0.10;
    vec2 refracted_uv = clamp(SCREEN_UV + distortion, vec2(0.002), vec2(0.998));
    vec3 bed_color = textureLod(scene_color, refracted_uv, 0.25).rgb;
    // Mineral-rich water absorbs warm bed colour fastest; the visible shallow
    // margin still comes from the real floor rather than a painted blue layer.
    vec3 absorption = exp(-vec3(6.6, 2.65, 1.55) * depth);
    vec3 transmitted = bed_color * absorption;
    float incoming_light = clamp(dot(bed_color, vec3(0.2126, 0.7152, 0.0722)) * 2.5, 0.0, 1.0);
    transmitted += vec3(0.012, 0.033, 0.040) * (vec3(1.0) - absorption) * incoming_light;
    transmitted *= mix(1.0, 0.80, smoothstep(0.06, 0.22, depth));
    vec3 deep_tint = mix(vec3(0.022, 0.049, 0.051), vec3(0.006, 0.025, 0.031), smoothstep(0.02, 0.32, depth));
    // Bounded screen-space reflection of the real illuminated rock and timber.
    vec3 reflected = vec3(0.006, 0.012, 0.016);
    vec3 reflect_direction = reflect(-normalize(VIEW), NORMAL);
    float previous_distance = 0.0;
    for (int step_index = 1; step_index <= 16; step_index++) {
        float step_number = float(step_index);
        float distance = step_number * 0.18 + step_number * step_number * 0.032;
        vec3 ray = VERTEX + NORMAL * 0.035 + reflect_direction * distance;
        vec4 clip = PROJECTION_MATRIX * vec4(ray, 1.0);
        vec2 reflection_uv = clip.xy / clip.w * 0.5 + 0.5;
        if (ray.z >= -0.05 || any(lessThan(reflection_uv, vec2(0.01))) || any(greaterThan(reflection_uv, vec2(0.99)))) { break; }
        vec3 hit = scene_position(reflection_uv, INV_PROJECTION_MATRIX);
        float separation = hit.z - ray.z;
        if (separation > 0.0 && separation < 1.35) {
            // Refine the actual depth crossing instead of showing a long
            // uniformly bright ray-march band across the water.
            float low = previous_distance;
            float high = distance;
            for (int refinement = 0; refinement < 3; refinement++) {
                float middle = (low + high) * 0.5;
                vec3 probe = VERTEX + NORMAL * 0.035 + reflect_direction * middle;
                vec4 probe_clip = PROJECTION_MATRIX * vec4(probe, 1.0);
                vec2 probe_uv = probe_clip.xy / probe_clip.w * 0.5 + 0.5;
                if (scene_position(probe_uv, INV_PROJECTION_MATRIX).z - probe.z > 0.0) {
                    high = middle;
                    reflection_uv = probe_uv;
                } else {
                    low = middle;
                }
            }
            float fade = smoothstep(0.0, 0.12, min(min(reflection_uv.x, 1.0 - reflection_uv.x), min(reflection_uv.y, 1.0 - reflection_uv.y)));
            fade *= 1.0 - smoothstep(8.0, 12.0, distance);
            reflected = mix(reflected, textureLod(scene_color, reflection_uv, 0.8 + reflection_roughness * 4.0).rgb, fade);
            break;
        }
        previous_distance = distance;
    }
    float crest = clamp(wave.w, 0.0, 0.6);
    ALBEDO = deep_tint * (1.0 - fresnel) + vec3(0.12, 0.15, 0.13) * crest;
    EMISSION = transmitted * (1.0 - fresnel) * (1.0 - crest * 0.14) + reflected * fresnel;
    ROUGHNESS = reflection_roughness + (1.0 - shore) * 0.13 + crest * 0.08;
    METALLIC = 0.0;
    SPECULAR = 0.42;
    ALPHA = shore * contact_fade * 0.92;
}
