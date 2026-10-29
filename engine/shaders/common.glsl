// Shared uniforms and helpers, prepended to every 3D shader.
// All colours arriving here are already linear (the renderer converts them).

uniform mat4 u_view;
uniform mat4 u_proj;
uniform mat4 u_viewproj;
uniform vec3 u_cam_pos;
uniform float u_time;

uniform vec3 u_sky_top;
uniform vec3 u_sky_horizon;
uniform vec3 u_ground;
uniform vec3 u_sun_dir;       // direction light travels
uniform vec3 u_sun_color;     // colour * energy
uniform float u_sun_size;
uniform vec3 u_moon_dir;
uniform float u_ambient_energy;
uniform float u_reflection_energy;
uniform vec3 u_fog_color;
uniform float u_fog_density;
uniform float u_fog_height;
uniform float u_fog_height_density;
uniform float u_fog_sun_scatter;
uniform float u_clouds;
uniform float u_cloud_speed;
uniform float u_stars;
uniform float u_toon;        // cel shading bands, 0 = off

const float PI = 3.14159265;

float hash12(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float hash13(vec3 p3) {
  p3 = fract(p3 * 0.1031);
  p3 += dot(p3, p3.zyx + 31.32);
  return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash12(i), hash12(i + vec2(1, 0)), u.x),
             mix(hash12(i + vec2(0, 1)), hash12(i + vec2(1, 1)), u.x), u.y);
}

float fbm(vec2 p) {
  float s = 0.0, a = 0.5;
  for (int i = 0; i < 5; i++) { s += a * vnoise(p); p = p * 2.03 + vec2(17.1, 9.2); a *= 0.5; }
  return s;
}

// Quantise a 0..1 light amount into u_toon bands with an anti-aliased step between them.
float toon_ramp(float x) {
  float y = clamp(x, 0.0, 1.0) * u_toon;
  float w = max(fwidth(y), 1e-3) * 0.75;
  float i = floor(y);
  return (i + smoothstep(0.5 - w, 0.5 + w, y - i)) / u_toon;
}

vec3 srgb_to_linear(vec3 c) { return pow(max(c, vec3(0.0)), vec3(2.2)); }

// Hemisphere ambient light for a normal.
vec3 hemi_light(vec3 n) {
  return n.y > 0.0 ? mix(u_sky_horizon, u_sky_top, n.y) : mix(u_sky_horizon, u_ground, min(-n.y * 2.0, 1.0));
}

// Background sky colour in a direction, without the sun disk (used for reflections too).
vec3 sky_gradient(vec3 d) {
  float y = d.y;
  vec3 c;
  if (y >= 0.0) c = mix(u_sky_horizon, u_sky_top, pow(y, 0.55));
  else c = mix(u_sky_horizon, u_ground, clamp(-y * 6.0, 0.0, 1.0));
  vec3 L = -u_sun_dir;
  float sd = max(dot(d, L), 0.0);
  c += u_sun_color * (pow(sd, 8.0) * 0.12 + pow(sd, 64.0) * 0.25) * clamp(L.y * 4.0 + 0.6, 0.0, 1.0);
  return c;
}

float fog_amount(vec3 world, float dist) {
  float h = u_fog_height_density * exp(-max(world.y - u_fog_height, 0.0) * 0.12);
  return 1.0 - exp(-dist * (u_fog_density + h));
}

vec3 apply_fog(vec3 col, vec3 world) {
  vec3 dv = world - u_cam_pos;
  float dist = length(dv);
  float f = fog_amount(world, dist);
  float sun = pow(max(dot(dv / max(dist, 1e-4), -u_sun_dir), 0.0), 8.0);
  vec3 fc = u_fog_color + u_sun_color * sun * u_fog_sun_scatter;
  return mix(col, fc, clamp(f, 0.0, 1.0));
}
