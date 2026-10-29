// Main surface shader. Variants: INSTANCED, DEPTH (shadow pass).

uniform mat4 u_model;
uniform mat3 u_normal_mat;
uniform float u_wind;
uniform int u_effect;
uniform int u_vertex_color;

float water_height(vec2 p, float t) {
  return sin(p.x * 0.35 + t * 1.1) * 0.12 + sin(p.y * 0.45 - t * 0.9) * 0.1
       + sin((p.x + p.y) * 0.9 + t * 1.7) * 0.04;
}

#ifdef VERTEX
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_normal;
layout(location = 2) in vec2 a_uv;
layout(location = 3) in vec4 a_color;
#ifdef INSTANCED
layout(location = 4) in vec4 i_m0;
layout(location = 5) in vec4 i_m1;
layout(location = 6) in vec4 i_m2;
layout(location = 7) in vec4 i_m3;
layout(location = 8) in vec4 i_color;
#endif

out vec3 v_world;
out vec3 v_normal;
out vec2 v_uv;
out vec4 v_color;
out float v_view_depth;

void main() {
  mat4 M = u_model;
  mat3 N = u_normal_mat;
  vec4 icol = vec4(1.0);
#ifdef INSTANCED
  M = mat4(i_m0, i_m1, i_m2, i_m3);
  N = mat3(M);
  icol = i_color;
#endif
  vec4 wp = M * vec4(a_pos, 1.0);
  if (u_wind > 0.0) {
    float h = max(a_pos.y, 0.0);
    float ph = dot(M[3].xz, vec2(0.37, 0.21)) + dot(wp.xz, vec2(0.6, 0.4));
    float gust = 0.6 + 0.4 * sin(u_time * 0.4 + M[3].x * 0.05);
    wp.x += sin(u_time * 1.7 + ph) * u_wind * h * h * 0.04 * gust;
    wp.z += cos(u_time * 1.3 + ph * 1.3) * u_wind * h * h * 0.03 * gust;
  }
  if (u_effect == 1) wp.y += water_height(wp.xz, u_time);
  v_world = wp.xyz;
  v_normal = N * a_normal;
  v_uv = a_uv;
  vec4 vc = u_vertex_color != 0 ? vec4(srgb_to_linear(a_color.rgb), a_color.a) : vec4(1.0);
  v_color = vc * vec4(srgb_to_linear(icol.rgb), icol.a);
  vec4 vp = u_view * wp;
  v_view_depth = -vp.z;
  gl_Position = u_viewproj * wp;
}
#endif

#ifdef FRAGMENT
in vec3 v_world;
in vec3 v_normal;
in vec2 v_uv;
in vec4 v_color;
in float v_view_depth;

uniform vec4 u_albedo;
uniform vec3 u_emission;
uniform float u_roughness;
uniform float u_metallic;
uniform float u_rim;
uniform vec2 u_uv_scale;
uniform float u_alpha_cutoff;
uniform sampler2D u_albedo_tex;
uniform int u_has_tex;
uniform int u_unshaded;
uniform int u_triplanar;
uniform int u_no_fog;
uniform vec4 u_tint;

uniform int u_num_lights;
uniform vec4 u_lpos[32];   // xyz position, w range
uniform vec4 u_lcol[32];   // rgb colour*energy, w type (0 omni, 1 spot)
uniform vec4 u_ldir[32];   // xyz direction, w cos(outer angle)
uniform float u_lsoft[32];

uniform int u_shadows_on;
uniform sampler2DArrayShadow u_shadow;
uniform mat4 u_shadow_mat[3];
uniform vec3 u_shadow_splits;
uniform vec3 u_shadow_texel;

out vec4 frag;

vec4 sample_albedo() {
  if (u_has_tex == 0) return vec4(1.0);
  if (u_triplanar != 0) {
    vec3 n = abs(normalize(v_normal));
    n = pow(n, vec3(4.0));
    n /= (n.x + n.y + n.z);
    vec3 p = v_world * u_uv_scale.x;
    return texture(u_albedo_tex, p.zy) * n.x + texture(u_albedo_tex, p.xz) * n.y + texture(u_albedo_tex, p.xy) * n.z;
  }
  return texture(u_albedo_tex, v_uv * u_uv_scale);
}

#ifdef DEPTH
void main() {
  if (u_alpha_cutoff > 0.0 && sample_albedo().a * u_albedo.a < u_alpha_cutoff) discard;
}
#else

float shadow_cascade(int c, vec3 world, vec3 n, float ndl) {
  float bias_world = u_shadow_texel[c] * (1.5 + 2.0 * (1.0 - ndl));
  vec4 sp = u_shadow_mat[c] * vec4(world + n * bias_world, 1.0);
  vec3 p = sp.xyz / sp.w;
  if (p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0 || p.z > 1.0) return 1.0;
  float ts = 1.0 / float(textureSize(u_shadow, 0).x);
  float s = 0.0;
  for (int y = -2; y <= 2; y++)
    for (int x = -2; x <= 2; x++)
      s += texture(u_shadow, vec4(p.xy + vec2(x, y) * ts, float(c), p.z - 0.0005));
  return s / 25.0;
}

float sun_shadow(vec3 world, vec3 n, float ndl) {
  if (u_shadows_on == 0) return 1.0;
  float d = v_view_depth;
  if (d > u_shadow_splits.z) return 1.0;
  int c = d < u_shadow_splits.x ? 0 : (d < u_shadow_splits.y ? 1 : 2);
  float s = shadow_cascade(c, world, n, ndl);
  // Blend into the next cascade near the boundary to hide the seam.
  float edge = c == 0 ? u_shadow_splits.x : (c == 1 ? u_shadow_splits.y : u_shadow_splits.z);
  float band = edge * 0.12;
  float t = clamp((d - (edge - band)) / band, 0.0, 1.0);
  if (t > 0.0) s = mix(s, c < 2 ? shadow_cascade(c + 1, world, n, ndl) : 1.0, t);
  return s;
}

float D_GGX(float ndh, float a) {
  float a2 = a * a;
  float d = ndh * ndh * (a2 - 1.0) + 1.0;
  return a2 / (PI * d * d);
}
float G_Smith(float ndv, float ndl, float r) {
  float k = (r + 1.0) * (r + 1.0) / 8.0;
  return (ndv / (ndv * (1.0 - k) + k)) * (ndl / (ndl * (1.0 - k) + k));
}
vec3 F_Schlick(float c, vec3 f0) { return f0 + (1.0 - f0) * pow(1.0 - c, 5.0); }

vec3 brdf(vec3 N, vec3 V, vec3 L, vec3 base, float rough, float metal, vec3 f0) {
  vec3 H = normalize(V + L);
  float ndl = max(dot(N, L), 0.0);
  float ndv = max(dot(N, V), 1e-4);
  float ndh = max(dot(N, H), 0.0);
  vec3 F = F_Schlick(max(dot(H, V), 0.0), f0);
  vec3 spec = D_GGX(ndh, rough * rough) * G_Smith(ndv, ndl, rough) * F / (4.0 * ndv * max(ndl, 1e-4));
  vec3 kd = (1.0 - F) * (1.0 - metal);
  return (kd * base + spec * PI) * ndl;
}

vec3 water_normal(vec2 p, float t) {
  float e = 0.05;
  float h = water_height(p, t);
  vec3 n = normalize(vec3(h - water_height(p + vec2(e, 0), t), e, h - water_height(p + vec2(0, e), t)));
  // Small ripples on top of the big swell.
  vec2 q = p * 1.7 + vec2(t * 0.3, t * 0.2);
  float r1 = vnoise(q), r2 = vnoise(q + vec2(0.13, 0.0)), r3 = vnoise(q + vec2(0.0, 0.13));
  n.xz += vec2(r1 - r2, r1 - r3) * 1.4;
  return normalize(n);
}

void main() {
  vec4 tex = sample_albedo();
  vec4 base4 = vec4(u_albedo.rgb, u_albedo.a) * tex * v_color * u_tint;
  if (u_alpha_cutoff > 0.0 && base4.a < u_alpha_cutoff) discard;
  vec3 base = base4.rgb;
  float alpha = base4.a;

  vec3 N = normalize(v_normal);
  if (!gl_FrontFacing) N = -N;
  vec3 V = normalize(u_cam_pos - v_world);
  float rough = clamp(u_roughness, 0.04, 1.0);
  float metal = u_metallic;
  vec3 emission = u_emission;

  if (u_effect == 1) {
    N = water_normal(v_world.xz, u_time);
    float fres = pow(1.0 - max(dot(N, V), 0.0), 4.0);
    alpha = mix(alpha, 1.0, fres);
  } else if (u_effect == 2) {
    float pulse = 0.65 + 0.35 * sin(u_time * 3.0 + v_world.y * 3.0);
    float fres = pow(1.0 - max(dot(N, V), 0.0), 2.0);
    emission *= pulse * (0.6 + fres * 1.6);
  }

  vec3 col;
  if (u_unshaded != 0) {
    col = base + emission;
  } else {
    vec3 f0 = mix(vec3(0.04), base, metal);
    vec3 L = -u_sun_dir;
    float ndl = max(dot(N, L), 0.0);
    float sh = ndl > 0.0 ? sun_shadow(v_world, normalize(v_normal) * (gl_FrontFacing ? 1.0 : -1.0), ndl) : 0.0;
    col = brdf(N, V, L, base, rough, metal, f0) * u_sun_color * sh;

    for (int i = 0; i < u_num_lights; i++) {
      vec3 dl = u_lpos[i].xyz - v_world;
      float d = length(dl);
      float range = u_lpos[i].w;
      if (d > range) continue;
      vec3 Ld = dl / d;
      float x = d / range;
      float att = clamp(1.0 - x * x * x * x, 0.0, 1.0);
      att = att * att / (1.0 + d * d * 0.35);
      if (u_lcol[i].w > 0.5) {
        float cd = dot(-Ld, normalize(u_ldir[i].xyz));
        float outer = u_ldir[i].w;
        float inner = mix(1.0, outer, 1.0 - u_lsoft[i]);
        att *= clamp((cd - outer) / max(inner - outer, 1e-3), 0.0, 1.0);
      }
      col += brdf(N, V, Ld, base, rough, metal, f0) * u_lcol[i].rgb * att;
    }

    // Ambient: hemisphere diffuse plus a sky reflection approximation.
    float ndv = max(dot(N, V), 1e-4);
    vec3 hemi = hemi_light(N);
    vec3 Fr = f0 + (max(vec3(1.0 - rough), f0) - f0) * pow(1.0 - ndv, 5.0);
    vec3 R = reflect(-V, N);
    vec3 env = mix(sky_gradient(R), hemi_light(R), rough);
    col += hemi * base * (1.0 - metal) * (1.0 - Fr * 0.5) * u_ambient_energy;
    col += env * Fr * (1.0 - rough * 0.7) * u_reflection_energy;
    if (u_rim > 0.0) col += (hemi + u_sun_color * 0.3) * pow(1.0 - ndv, 3.0) * u_rim;
    col += emission;
  }
  if (u_no_fog == 0) col = apply_fog(col, v_world);
  frag = vec4(col, alpha);
}
#endif
#endif
