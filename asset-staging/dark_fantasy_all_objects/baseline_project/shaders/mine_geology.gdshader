shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Photographed relief in metres. World projection keeps every sculpt chunk
// continuous, including attached scan patches and the new fallen fragments.
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D height_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fracture_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D fracture_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 base_tint : source_color = vec4(0.68, 0.73, 0.76, 1.0);
uniform bool ground_surface = false;
uniform float metric_scale = 1.0;
uniform float normal_strength = 1.1;
uniform float dry_roughness = 0.8;
uniform float wet_roughness = 0.29;
uniform float fracture_mix = 0.28;
varying vec3 world_position;
varying vec3 world_normal;

float hash(vec3 p) { return fract(sin(dot(p,vec3(127.1,311.7,74.7)))*43758.5453); }
float noise(vec3 p) {
 vec3 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(mix(hash(i),hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
vec3 photograph(sampler2D map, vec3 p, vec3 w) {
 return texture(map,p.zy).rgb*w.x+texture(map,p.xz).rgb*w.y+texture(map,p.xy).rgb*w.z;
}
vec3 relief_normal(sampler2D map, vec3 p, vec3 w) {
 vec2 nx=texture(map,p.zy).xy*2.0-1.0;
 vec2 ny=texture(map,p.xz).xy*2.0-1.0;
 vec2 nz=texture(map,p.xy).xy*2.0-1.0;
 return vec3(ny.x*w.y+nz.x*w.z,nx.y*w.x+nz.y*w.z,nx.x*w.x+ny.y*w.y);
}
void vertex() {
 world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
void fragment() {
 vec3 n=normalize(world_normal);
 vec3 w=pow(abs(n),vec3(6.0)); w/=max(dot(w,vec3(1.0)),0.0001);
 vec3 p=world_position/metric_scale;
 // Scanned crevices provide local occlusion without distorting texture derivatives.
 float height=photograph(height_map,p,w).r;
 // Keep sampling derivatives stable at grazing angles. Geometric ledges
// carry silhouette depth; photographic normals carry the fine relief.
 float macro=noise(world_position*0.28)+0.35*noise(world_position*0.73+4.7);
 float veins=noise(world_position*vec3(0.85,0.18,0.85)+vec3(5.7,1.1,2.4));
 float fracture=fracture_mix*smoothstep(0.32,0.95,macro);
 vec3 dry=photograph(albedo_map,p,w);
 if (ground_surface) {
  // Fine alluvial mud fills the spaces between loose stones. Keep the
  // photographed gravel exposed in patches instead of glittering everywhere.
  float silt=smoothstep(0.31,0.81,noise(world_position*0.57+8.1));
  dry=mix(dry,vec3(0.105,0.085,0.062),silt*0.82);
 }
 vec3 fractured=photograph(fracture_albedo,p*0.64+3.71,w);
 dry=mix(dry,fractured,fracture);
 float luma=dot(dry,vec3(0.2126,0.7152,0.0722));
 dry=mix(vec3(luma),dry,ground_surface?0.66:0.36);
 float damp=smoothstep(0.36,0.8,veins)*(ground_surface?0.74:0.8);
 damp=max(damp,(1.0-smoothstep(0.05,1.1,world_position.y))*0.58);
 vec3 tint=base_tint.rgb;
 if (!ground_surface) { tint*=mix(vec3(0.82,0.92,1.0),vec3(1.0,0.96,0.84),smoothstep(0.62,0.94,macro)); }
 vec3 color=dry*tint*mix(0.73,1.17,smoothstep(0.2,1.0,macro));
 color*=mix(1.0,0.66,damp);
 // Sparse moss-dark mineral staining near the damp wall foot, not grass.
 float stain=(1.0-smoothstep(0.1,1.15,world_position.y))*smoothstep(0.58,0.81,veins);
 color=mix(color,color*vec3(0.57,0.79,0.68),stain*0.5);
 ALBEDO=color;
 vec3 bump=mix(relief_normal(normal_map,p,w),relief_normal(fracture_normal,p*0.64+3.71,w),fracture);
 bump-=n*dot(n,bump);
 NORMAL=normalize((VIEW_MATRIX*vec4(normalize(n+bump*normal_strength),0.0)).xyz);
 float rough=photograph(roughness_map,p,w).r;
 ROUGHNESS=clamp(mix(dry_roughness,wet_roughness,damp)+ (rough-0.5)*0.16,0.19,0.96);
 SPECULAR=ground_surface?mix(0.18,0.32,damp):mix(0.32,0.55,damp);
 METALLIC=0.0;
 AO=ground_surface?1.0:mix(0.85,1.0,smoothstep(0.16,0.6,height));
 AO_LIGHT_AFFECT=0.38;
}
