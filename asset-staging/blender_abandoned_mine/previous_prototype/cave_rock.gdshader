shader_type spatial;
render_mode cull_disabled;

uniform vec4 rock_dark : source_color = vec4(0.095, 0.075, 0.055, 1.0);
uniform vec4 rock_light : source_color = vec4(0.43, 0.35, 0.255, 1.0);
uniform float wetness = 0.0;
varying vec3 rock_position;

float hash31(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}
float noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash31(i), hash31(i+vec3(1,0,0)), f.x),
                   mix(hash31(i+vec3(0,1,0)), hash31(i+vec3(1,1,0)), f.x), f.y),
               mix(mix(hash31(i+vec3(0,0,1)), hash31(i+vec3(1,0,1)), f.x),
                   mix(hash31(i+vec3(0,1,1)), hash31(i+vec3(1,1,1)), f.x), f.y), f.z);
}
void vertex() { rock_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    vec3 p = rock_position;
    float large = noise3(p * 0.55);
    float grain = noise3(p * 3.8) * 0.5 + noise3(p * 13.0) * 0.3 + noise3(p * 37.0) * 0.2;
    float strata = abs(sin(p.y * 8.5 + noise3(p * vec3(0.7, 1.1, 0.7)) * 11.0));
    float fissure = smoothstep(0.04, 0.22, strata);
    ALBEDO = mix(rock_dark.rgb, rock_light.rgb, large * 0.4 + grain * 0.6) * mix(0.47, 1.0, fissure);
    ROUGHNESS = mix(0.91, 0.28, wetness * (0.4 + 0.6 * large));
    SPECULAR = mix(0.25, 0.6, wetness);
    // Derivative bump follows the actual cave surface rather than UV seams.
    float bump = grain * 0.095 + strata * 0.018;
    vec3 q0 = dFdx(VERTEX);
    vec3 q1 = dFdy(VERTEX);
    vec3 s = cross(q1, NORMAL);
    vec3 t = cross(NORMAL, q0);
    float det = dot(q0, s);
    vec3 gradient = sign(det) * (dFdx(bump) * s + dFdy(bump) * t);
    NORMAL = normalize(abs(det) * NORMAL - gradient);
}
