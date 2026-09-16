// Adapted from Dari0us, MIT. Local-space marching for a carried torch; corrected step/jitter scope.
shader_type spatial;
render_mode unshaded, cull_front, blend_mix;
render_mode depth_draw_never, depth_test_disabled;

group_uniforms quality_and_performance;
uniform int raymarch_steps : hint_range(2, 24) = 6;
uniform bool sample_jitter = true;
///Disables Jittering and Perspective seam solutions, in favor of a faster method.
uniform bool potato_mode = false; 

group_uniforms general_parameters;
uniform sampler3D sample_noise;
uniform bool billboard = true;
uniform float billboard_z_offset = 0.675;
uniform sampler2D depth_texture : hint_depth_texture;
uniform float proximity_fade_distance = 0.375;
uniform float time_scale = 0.027;
uniform float noise_scale = 0.45;
uniform float noise_threshold = 0.43;

group_uniforms shape_composition;
uniform float oil_cloth_height = 1.48;
uniform float fire_height = 2.45;
uniform float fire_width = 2.25;
uniform vec3 box_center = vec3(0.0, 0.0, 0.0);
uniform vec3 box_rotation = vec3(0.0);
uniform float taper_factor = 0.425;

uniform float wobble_strength = 2.0;
uniform float wobble_speed = 6.0;
uniform float wobble_noise_frequency : hint_range(0.1, 10.0) = 0.125;
uniform float sharpness_cutoff : hint_range(0.0, 20.0) = 4.5;

group_uniforms visual_composition;
uniform float emission_strength = 12.5;
uniform float core_glow_multiplier : hint_range(0.0, 20.0) = 16.0;

uniform vec3 color_core = vec3(1.0, 0.9, 0.5);
uniform vec3 color_mid = vec3(1.0, 0.625, 0.0);
uniform vec3 color_outer = vec3(0.8, 0.01, 0.0);
uniform vec3 color_smoke = vec3(-0.067, -0.067, -0.067);

group_uniforms experimental;
uniform float jitter_multiplier : hint_range(0.0, 20.0) = 1.0;

varying vec3 world_position;
varying vec3 world_camera;

vec3 get_box_center(vec3 npw){
	vec3 offset = vec3(0.0,fire_height*0.5,0.0);
    return box_center + npw+offset;
}

float get_animated_time(){
    return -TIME * time_scale;
}

mat3 rotation_matrix(vec3 angles) {
    float cx = cos(angles.x), sx = sin(angles.x);
    float cy = cos(angles.y), sy = sin(angles.y);
    float cz = cos(angles.z), sz = sin(angles.z);

    vec3 row0 = vec3(cy * cz, -cy * sz, sy);
    vec3 row1 = vec3(cx * sz + sx * sy * cz, cx * cz - sx * sy * sz, -sx * cy);
    vec3 row2 = vec3(sx * sz - cx * sy * cz, sx * cz + cx * sy * sz, cx * cy);

    return mat3(row0, row1, row2);
}

float get_noise_value(vec3 p_coord, float scale_factor, float time_offset_z) {
    vec3 tex_coords = p_coord * scale_factor + vec3(0.0, time_offset_z, 0.0);
    return texture(sample_noise, fract(tex_coords)).r;
}

float sdf_box(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(vec3(0.0), q)) + min(0.0, max(q.x, max(q.y, q.z)));
}

vec3 get_per_sample_wobble(vec3 p, float strength, float noise_freq, float speed) {
    float time_val = get_animated_time();

    float wobble_time_offset_x = time_val * speed;
    float wobble_time_offset_y = time_val * speed * 1.2;
    float wobble_time_offset_z = time_val * speed * 0.8;

    float wx = get_noise_value(p + vec3(100.0, 0.0, 0.0), noise_freq, wobble_time_offset_x);
    float wy = get_noise_value(p + vec3(0.0, 200.0, 0.0), noise_freq, wobble_time_offset_y);
    float wz = get_noise_value(p + vec3(0.0, 0.0, 300.0), noise_freq, wobble_time_offset_z);

    return vec3(wx - 0.5, wy - 0.5, wz - 0.5) * strength;
}

float fire_sdf(vec3 p, vec3 npw) {
    vec3 local_p = p - get_box_center(npw);
    local_p = transpose(rotation_matrix(box_rotation)) * local_p;
    vec3 box_size = vec3(fire_width, fire_height, fire_width);
    float normalized_height = (local_p.y + box_size.y * 0.5) / box_size.y;
    float current_taper = 1.0 - normalized_height * taper_factor;
    current_taper = max(0.01, current_taper);

    vec3 tapered_local_p = local_p;
    tapered_local_p.xz /= current_taper;

    vec3 per_sample_wobble_offset = get_per_sample_wobble(local_p, wobble_strength, wobble_noise_frequency, wobble_speed);

    float dist = sdf_box(tapered_local_p, box_size * 0.5);

    float sdf_noise_time_offset = get_animated_time() * 20.0;
    float distortion = get_noise_value(local_p + per_sample_wobble_offset, noise_scale * 0.5, sdf_noise_time_offset) * 0.3;
    dist += distortion;

    return dist;
}

// Continuous oil combustion around the full wrapped cloth, in local metres / scale.
float oil_surface_density(vec3 p) {
    float h = p.y / oil_cloth_height;
    float mask = smoothstep(0.0, 0.10, h) * (1.0 - smoothstep(0.94, 1.22, h));
    // Vertically stretched turbulence breaks the burning skin into rising tongues.
    vec3 flow = vec3(p.x * 3.2, p.y * 0.65, p.z * 3.2);
    float n = get_noise_value(flow, noise_scale, get_animated_time() * 32.0);
    float n2 = get_noise_value(flow * 1.8 + vec3(0.0, 2.0, 0.0), noise_scale, get_animated_time() * 23.0);
    float radius = 0.54 + 0.10 * sin(clamp(h, 0.0, 1.0) * 3.14159);
    float r = length(p.xz);
    float shell = smoothstep(radius - 0.25, radius - 0.08, r)
        * (1.0 - smoothstep(radius + n * 0.13, radius + 0.12 + n * 0.20, r));
    float flame = smoothstep(0.28, 0.66, n * 0.75 + n2 * 0.25);
    return mask * shell * (0.018 + 0.17 * flame);
}

void vertex() {
    if (billboard){
        mat3 cam_rotation = mat3(
            MAIN_CAM_INV_VIEW_MATRIX[0].xyz,
            MAIN_CAM_INV_VIEW_MATRIX[1].xyz,
            MAIN_CAM_INV_VIEW_MATRIX[2].xyz
        );
        VERTEX = cam_rotation * VERTEX;
        NORMAL = cam_rotation * NORMAL;

        // Apply the Z offset after billboard rotation to move the plane along the camera's Z axis.
		
		float post_offset = CAMERA_DIRECTION_WORLD.y+billboard_z_offset;
		
		
        VERTEX += MAIN_CAM_INV_VIEW_MATRIX[2].xyz * post_offset;
    }
    world_position = VERTEX;
    world_camera = (inverse(MODEL_MATRIX) * INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
}

float hash(vec3 p) {
    p = fract(p * 0.3183099 + vec3(0.1, 0.3, 0.7));
    p = p * dot(p, p.yzx + 19.19);
    return fract((p.x + p.y) * p.z);
}


void fragment() {
    if (noise_threshold <= 0.001){
        discard;
    }

    vec3 ray_origin = world_camera;
    vec3 ray_direction = normalize(world_position - world_camera);

    vec3 fire_world_center = get_box_center(vec3(0.0));
    vec3 box_size = vec3(fire_width, fire_height, fire_width);
    float max_dim = max(box_size.x, max(box_size.y, box_size.z));
    vec3 rotated_box_half_extents = vec3(max_dim);

    vec3 box_min_world = fire_world_center - rotated_box_half_extents * 0.5;
    vec3 box_max_world = fire_world_center + rotated_box_half_extents * 0.5;

    float t_enter = 0.0;
    float t_exit = length(fire_world_center - ray_origin) + length(rotated_box_half_extents);

    vec3 inv_ray_direction = 1.0 / ray_direction;

    vec3 t0 = (box_min_world - ray_origin) * inv_ray_direction;
    vec3 t1 = (box_max_world - ray_origin) * inv_ray_direction;

    vec3 t_smaller = min(t0, t1);
    vec3 t_larger = max(t0, t1);

    t_enter = max(t_enter, max(t_smaller.x, max(t_smaller.y, t_smaller.z)));
    t_exit = min(t_exit, min(t_larger.x, min(t_larger.y, t_larger.z)));

    if (t_enter >= t_exit) {
        discard;
    }

    // Stop at the first opaque surface, rather than depth-testing the rear proxy box.
    // This exposes fire in FRONT of the cloth while occluding fire behind it.
    float scene_depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
    vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
    scene_view /= scene_view.w;
    vec3 scene_local = (inverse(MODEL_MATRIX) * INV_VIEW_MATRIX * vec4(scene_view.xyz, 1.0)).xyz;
    t_exit = min(t_exit, dot(scene_local - ray_origin, ray_direction));
    t_enter = max(0.0, t_enter);
	
    float total_distance = t_enter;
    float march_range = t_exit - t_enter;
    if (march_range <= 0.0001) {
        discard;
    }

    // --- ANGLE-BASED STEP COUNT FIX ---
    float angle_factor = dot(ray_direction, vec3(0.0, 1.0, 0.0));
    angle_factor = clamp(1.0 - abs(angle_factor), 0.0, 1.0);
    float step_multiplier = mix(1.0, 2.5, angle_factor);
    int adjusted_steps = int(float(raymarch_steps) * step_multiplier);
    adjusted_steps = clamp(adjusted_steps, raymarch_steps, 24);
	float step_size = march_range / float(raymarch_steps); // Distribute steps evenly over the intersection range
	
	bool potato_conditions = raymarch_steps<4 && !sample_jitter || potato_mode;
	
	
	
	if (!potato_conditions){
    	step_size = march_range / float(adjusted_steps);
	}
    vec3 final_color = vec3(0.0);
    float current_alpha = 0.0;


if (potato_conditions){
	    for (int i = 0; i < raymarch_steps; i++) {
        vec3 current_position = ray_origin + ray_direction * total_distance;

        // Exit loop if current_position is outside the actual march_range or goes beyond t_exit
        if (total_distance >= t_exit) {
            break;
        }

        float sdf_dist = fire_sdf(current_position,vec3(0.0));

        float density_noise_time_offset = get_animated_time() * 30.0;
        vec3 per_sample_wobble_offset_density = get_per_sample_wobble(current_position, wobble_strength * 0.7, wobble_noise_frequency * 1.1, wobble_speed * 0.9);

        float density_noise_value = get_noise_value(current_position + per_sample_wobble_offset_density, noise_scale * 0.7, density_noise_time_offset);

        float density = 0.0;
        if (sdf_dist < 0.0) {
            float noise_shaping = 1.0 - smoothstep(noise_threshold * 0.8, noise_threshold * 1.2, density_noise_value);
            density = smoothstep(0.0, sharpness_cutoff, -sdf_dist * 0.5 + noise_shaping);
            density = clamp(density, 0.0, 1.0);

            vec3 local_fire_pos = current_position - get_box_center(vec3(0.0));
            local_fire_pos = transpose(rotation_matrix(box_rotation)) * local_fire_pos;
	        float height_alpha = smoothstep(0.5, 1.0, (local_fire_pos.y + box_size.y * 0.5) / box_size.y);
	        height_alpha = pow(height_alpha, 0.33);
	        density *= (1.0 - height_alpha);

            float dist_to_center = length(local_fire_pos.xz);
            density *= smoothstep(0.7, 0.0, dist_to_center / (box_size.x * 0.5));
        }

        density *= smoothstep(oil_cloth_height * 0.75, oil_cloth_height + 0.4, current_position.y);
        density = max(density, oil_surface_density(current_position));
        float alpha_step = 1.0 - exp(-density * step_size * 25.0);

        vec3 current_color_rgb = mix(color_outer, color_mid, density_noise_value);

        current_color_rgb = mix(current_color_rgb, color_core, smoothstep(0.7, 1.0, density * core_glow_multiplier));

        vec3 local_fire_pos_for_color = current_position - get_box_center(vec3(0.0));
        local_fire_pos_for_color = transpose(rotation_matrix(box_rotation)) * local_fire_pos_for_color;
        float height_factor = (local_fire_pos_for_color.y + box_size.y * 0.5) / box_size.y;
        current_color_rgb = mix(current_color_rgb, color_smoke, smoothstep(0.6, 1.0, height_factor * (1.0 - density)));

        final_color += current_color_rgb * alpha_step * (1.0 - current_alpha);
        current_alpha += alpha_step * (1.0 - current_alpha);

        if (current_alpha > 0.99) {
            break;
        }

        total_distance += step_size;
    }
}else{
for (int i = 0; i < 48; i++) {
    if (i >= adjusted_steps) break;

    // Calculate the base position for this step.
    vec3 current_position = ray_origin + ray_direction * total_distance;
    if (total_distance >= t_exit) break;

    // Generate a truly random jitter offset.
    // The input to the hash function is now a more chaotic combination of
    // the current position, ray direction, and time.
    vec3 jitter_position = current_position;
	if (sample_jitter){
		vec3 hash_input = current_position * 1.25 + ray_direction * 33.333 + vec3(TIME*33.333);
    	float jitter = (hash(hash_input) - 0.5) * step_size;
		float jitter_power = pow(float(raymarch_steps),0.125);
		float jitter_scale = clamp(jitter_power,0.75,1.5);
		jitter_position = current_position + ray_direction * (jitter/jitter_scale*jitter_multiplier);
    }

    // --- All density and color calculations now use jitter_position ---
    float sdf_dist = fire_sdf(jitter_position, vec3(0.0));

    float density_noise_time_offset = get_animated_time() * 30.0;
    vec3 wobble = get_per_sample_wobble(jitter_position, wobble_strength * 0.7, wobble_noise_frequency * 1.1, wobble_speed * 0.9);

    float noise_val_density = get_noise_value(jitter_position + wobble, noise_scale * 0.7, density_noise_time_offset);

    float density = 0.0;
    if (sdf_dist < 0.0) {
        float noise_shaping = 1.0 - smoothstep(noise_threshold * 0.8, noise_threshold * 1.2, noise_val_density);
        density = smoothstep(0.0, sharpness_cutoff, -sdf_dist * 0.5 + noise_shaping);
        density = clamp(density, 0.0, 1.0);

        vec3 local_fire_pos = jitter_position - get_box_center(vec3(0.0));
        local_fire_pos = transpose(rotation_matrix(box_rotation)) * local_fire_pos;
        float height_alpha = smoothstep(0.5, 1.0, (local_fire_pos.y + box_size.y * 0.5) / box_size.y);
        height_alpha = pow(height_alpha, 0.333);
        density *= (1.0 - height_alpha);

        float dist_to_center = length(local_fire_pos.xz);
        density *= smoothstep(0.7, 0.0, dist_to_center / (box_size.x * 0.5));
    }

    density *= smoothstep(oil_cloth_height * 0.75, oil_cloth_height + 0.4, jitter_position.y);
    density = max(density, oil_surface_density(jitter_position));
    float alpha_step = 1.0 - exp(-density * step_size * 25.0);

    vec3 current_color_rgb = mix(color_outer, color_mid, noise_val_density);
    current_color_rgb = mix(current_color_rgb, color_core, smoothstep(0.7, 1.0, density * core_glow_multiplier));

    vec3 local_fire_pos_for_color = jitter_position - get_box_center(vec3(0.0));
    local_fire_pos_for_color = transpose(rotation_matrix(box_rotation)) * local_fire_pos_for_color;
    float height_factor = (local_fire_pos_for_color.y + box_size.y * 0.5) / box_size.y;
    current_color_rgb = mix(current_color_rgb, color_smoke, smoothstep(0.6, 1.0, height_factor * (1.0 - density)));

    final_color += current_color_rgb * alpha_step * (1.0 - current_alpha);
    current_alpha += alpha_step * (1.0 - current_alpha);

    if (current_alpha > 0.99) break;

    total_distance += step_size;
}
}
    ALPHA = clamp(current_alpha, 0.0, 1.0);

    ALBEDO = final_color / max(current_alpha, 0.001) * emission_strength;
    EMISSION = ALBEDO;
}
