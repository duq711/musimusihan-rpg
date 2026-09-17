shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 surface_tint : source_color = vec4(1.0);
uniform vec4 roughness_channel = vec4(1.0,0.0,0.0,0.0);
uniform bool has_albedo = false;
uniform bool has_normal = false;
uniform bool has_roughness = false;
uniform float saturation : hint_range(0.0,1.0) = 0.25;
uniform float normal_strength : hint_range(0.0,2.0) = 0.8;
uniform float roughness_value : hint_range(0.0,1.0) = 0.85;
uniform float metallic_value : hint_range(0.0,1.0) = 0.0;
uniform float dust_amount : hint_range(0.0,1.0) = 0.12;
varying vec3 local_position;
varying vec3 local_normal;
float hash(vec3 p) { return fract(sin(dot(p, vec3(127.1,311.7,74.7))) * 43758.5453); }
float noise(vec3 p) {
 vec3 i=floor(p), f=fract(p);f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { local_position=VERTEX;local_normal=NORMAL; }
void fragment() {
 vec3 source=base_color.rgb;
 if(has_albedo) source*=texture(albedo_map,UV).rgb;
 float luma=dot(source,vec3(0.2126,0.7152,0.0722));
 vec3 aged=mix(vec3(luma),source,saturation)*surface_tint.rgb;
 float stains=noise(local_position*2.4)*0.6+noise(local_position*16.0)*0.4;
 aged*=mix(0.72,1.08,stains);
 float dust=max(local_normal.y,0.0)*dust_amount*smoothstep(0.28,0.80,stains);
 ALBEDO=mix(aged,vec3(0.22,0.215,0.19),dust);
 ROUGHNESS=roughness_value;
 if(has_roughness) ROUGHNESS*=mix(0.78,1.0,dot(texture(roughness_map,UV),roughness_channel));
 METALLIC=metallic_value;
 SPECULAR=0.35;
 if(has_normal) { NORMAL_MAP=texture(normal_map,UV).rgb; NORMAL_MAP_DEPTH=normal_strength; }
}
