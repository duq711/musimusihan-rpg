shader_type spatial;
render_mode depth_draw_opaque, cull_disabled;

// Opaque finish keeps mapped surface detail without whole-wall alpha layering.
uniform sampler2D source_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D ruin_scan : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D source_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D source_detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D source_roughness : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_albedo = false;
uniform bool has_normal = false;
uniform bool has_detail_normal = false;
uniform bool has_roughness = false;
uniform bool uses_vertex_color = false;
uniform bool source_triplanar = false;
uniform bool source_world_triplanar = false;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec3 source_uv_scale = vec3(1.0);
uniform vec3 source_uv_offset = vec3(0.0);
uniform vec4 source_roughness_channel = vec4(1.0, 0.0, 0.0, 0.0);
uniform float source_normal_strength = 0.9;
uniform float source_roughness_value = 0.9;
uniform float source_metallic = 0.0;
uniform float source_specular = 0.3;
uniform int surface_kind = 0;
uniform float weather_strength : hint_range(0.0, 1.5) = 1.0;
uniform float normal_offset : hint_range(0.0, 0.01) = 0.0006;
varying vec3 weather_world;
varying vec3 weather_normal;
varying vec3 authored_position;
varying vec3 authored_normal;
varying vec3 normal_axis_x;
varying vec3 normal_axis_y;
varying vec3 normal_axis_z;
varying vec4 authored_vertex_color;

float weather_hash(vec2 p) {
 return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float weather_noise(vec2 p) {
 vec2 i = floor(p), f = fract(p);
 f = f * f * (3.0 - 2.0 * f);
 return mix(mix(weather_hash(i), weather_hash(i + vec2(1.0, 0.0)), f.x),
  mix(weather_hash(i + vec2(0.0, 1.0)), weather_hash(i + vec2(1.0)), f.x), f.y);
}
float weather_fbm(vec2 p) {
 return weather_noise(p) * 0.55 + weather_noise(p * 2.07 + 4.9) * 0.29
  + weather_noise(p * 4.13 + 12.1) * 0.16;
}
vec4 mapped_texture(sampler2D map, vec3 position, vec3 weights, vec2 authored_uv) {
 if (!source_triplanar) { return texture(map, authored_uv); }
 return texture(map, position.zy) * weights.x + texture(map, position.xz) * weights.y
  + texture(map, position.xy) * weights.z;
}
vec3 mapped_normal(sampler2D map, vec3 position, vec3 weights, vec3 reference, float strength) {
 vec3 nx = texture(map, position.zy).rgb * 2.0 - 1.0;
 vec3 ny = texture(map, position.xz).rgb * 2.0 - 1.0;
 vec3 nz = texture(map, position.xy).rgb * 2.0 - 1.0;
 nx.xy *= strength; ny.xy *= strength; nz.xy *= strength;
 vec3 sx = vec3(nx.z * (reference.x < 0.0 ? -1.0 : 1.0), nx.y, nx.x);
 vec3 sy = vec3(ny.x, ny.z * (reference.y < 0.0 ? -1.0 : 1.0), ny.y);
 vec3 sz = vec3(nz.x, nz.y, nz.z * (reference.z < 0.0 ? -1.0 : 1.0));
 return normalize(sx * weights.x + sy * weights.y + sz * weights.z + reference * 0.001);
}
void vertex() {
 weather_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
 weather_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
 authored_position = VERTEX; authored_normal = NORMAL;
 normal_axis_x = MODEL_NORMAL_MATRIX * vec3(1.0, 0.0, 0.0);
 normal_axis_y = MODEL_NORMAL_MATRIX * vec3(0.0, 1.0, 0.0);
 normal_axis_z = MODEL_NORMAL_MATRIX * vec3(0.0, 0.0, 1.0);
 authored_vertex_color = COLOR;
 VERTEX += NORMAL * normal_offset;
}
void fragment() {
 // Preserve two-sided lighting when a thin fractured surface or an authored
 // sculpture exposes its reverse face. Custom world normals must follow the
 // same face orientation as the engine's default fragment normal.
 float face_sign = FRONT_FACING ? 1.0 : -1.0;
 vec3 wn = normalize(weather_normal) * face_sign;
 vec3 texture_normal = source_world_triplanar ? wn : normalize(authored_normal) * face_sign;
 vec3 weights = pow(abs(texture_normal), vec3(4.0));
 weights /= max(weights.x + weights.y + weights.z, 0.0001);
 vec3 position = (source_world_triplanar ? weather_world : authored_position)
  * source_uv_scale + source_uv_offset;
 vec2 authored_uv = UV * source_uv_scale.xy + source_uv_offset.xy;
 vec3 mineral_color = mix(vec3(dot(authored_vertex_color.rgb, vec3(0.299, 0.587, 0.114))), authored_vertex_color.rgb, 0.22);
 vec3 base = base_color.rgb;
 if (has_albedo) { base *= mapped_texture(source_albedo, position, weights, authored_uv).rgb; }
 if (uses_vertex_color) { base *= mineral_color; }
 // Generated diffuse material scan carries the fine fracture/mold structure
 // in the room goals. Geometry, source maps and lighting remain actual 3D.
 vec3 scan = mapped_texture(ruin_scan, weather_world * 0.57, pow(abs(wn), vec3(4.0)) / max(dot(pow(abs(wn), vec3(4.0)), vec3(1.0)), 0.001), UV).rgb;
 vec3 scanned_stone = scan * (vec3(0.77) + base_color.rgb * 0.30);
 if (uses_vertex_color) { scanned_stone *= mineral_color; }
 base = mix(base, scanned_stone, 0.88);
 float upward = smoothstep(0.45, 0.91, wn.y);
 vec2 wall_p = vec2(weather_world.x + weather_world.z * 0.79, weather_world.y);
 vec2 p = mix(wall_p, weather_world.xz, upward);
 float broad = weather_fbm(p * 0.81 + 8.6);
 float grain = weather_fbm(p * 27.4);
 float chips = weather_fbm(p * 8.3 + 14.2);
 float lower_band = 1.0 - smoothstep(0.12, 2.05 + broad * 0.55, weather_world.y);
 if (surface_kind == 1) { lower_band = 0.76; }
 float damp = smoothstep(0.26, 0.69, broad) * (0.18 + lower_band * 0.58);
 float moss = smoothstep(0.33, 0.60, weather_fbm(p * 9.4 + broad * 1.7))
  * lower_band * (0.63 + grain * 0.29);
 float trails = smoothstep(0.54, 0.84, weather_noise(vec2(wall_p.x * 19.0, wall_p.y * 0.24)))
  * (1.0 - upward) * lower_band * 0.27;
 float mold = smoothstep(0.41, 0.65, chips) * lower_band * 0.57 + trails;
 if (surface_kind == 2) { moss *= 0.24; mold *= 0.72; damp *= 0.65; }
 // Fine mottling modifies the authored texture; no bright salt paint flecks.
 base *= mix(0.70, 1.23, grain) * mix(0.84, 1.12, chips);
 base = mix(base, base * vec3(0.49, 0.60, 0.52), damp * weather_strength);
 base = mix(base, vec3(0.043, 0.076, 0.018) * mix(0.64, 1.24, grain), clamp(moss * weather_strength, 0.0, 0.68));
 base = mix(base, base * vec3(0.19, 0.30, 0.23), clamp(mold * weather_strength, 0.0, 0.50));
 ALBEDO = base;
 float roughness = source_roughness_value;
 if (has_roughness) { roughness *= dot(mapped_texture(source_roughness, position, weights, authored_uv), source_roughness_channel); }
 float wet_response = smoothstep(0.16, 0.63, damp) * (0.68 + grain * 0.28);
 ROUGHNESS = clamp(mix(roughness, 0.25 + grain * 0.19, wet_response) + moss * 0.07, 0.22, 0.97);
 METALLIC = source_metallic;
 SPECULAR = mix(min(source_specular, 0.35), 0.51, wet_response);
 if (source_triplanar && has_normal) {
  vec3 normal_value = mapped_normal(source_normal, position, weights, texture_normal, min(source_normal_strength, 1.2));
  if (has_detail_normal) {
   vec3 detail = mapped_normal(source_detail_normal, position, weights, texture_normal, 0.56);
   normal_value = normalize(normal_value + (detail - texture_normal) * 0.42);
  }
  if (!source_world_triplanar) {
   normal_value = normalize(normal_axis_x * normal_value.x + normal_axis_y * normal_value.y + normal_axis_z * normal_value.z);
  }
 NORMAL = normalize((VIEW_MATRIX * vec4(normal_value, 0.0)).xyz);
 } else if (has_normal) {
  vec3 normal_value = texture(source_normal, authored_uv).rgb * 2.0 - 1.0;
  normal_value.xy *= min(source_normal_strength, 1.2);
  NORMAL = normalize(TANGENT * normal_value.x + BINORMAL * normal_value.y + NORMAL * max(normal_value.z, 0.01));
 }
 vec2 scan_uv = p * 0.57;
 float scan_u = dot(texture(ruin_scan, scan_uv + vec2(0.004, 0.0)).rgb - texture(ruin_scan, scan_uv - vec2(0.004, 0.0)).rgb, vec3(0.333));
 float scan_v = dot(texture(ruin_scan, scan_uv + vec2(0.0, 0.004)).rgb - texture(ruin_scan, scan_uv - vec2(0.0, 0.004)).rgb, vec3(0.333));
 vec3 tangent_u = abs(wn.y) > 0.82 ? vec3(1.0, 0.0, 0.0) : normalize(vec3(wn.z, 0.0, -wn.x));
 vec3 tangent_v = normalize(cross(wn, tangent_u));
 NORMAL = normalize(NORMAL - (VIEW_MATRIX * vec4(tangent_u * scan_u + tangent_v * scan_v, 0.0)).xyz * 1.8);
}
