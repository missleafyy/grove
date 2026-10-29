// Procedural sky: gradient, sun, moon, clouds and stars. Drawn as a fullscreen triangle at the far plane.
uniform mat4 u_inv_viewproj;

#ifdef VERTEX
out vec2 v_ndc;
void main() {
  vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2) * 2.0 - 1.0;
  v_ndc = p;
  gl_Position = vec4(p, 1.0, 1.0);
}
#endif

#ifdef FRAGMENT
in vec2 v_ndc;
out vec4 frag;

void main() {
  vec4 a = u_inv_viewproj * vec4(v_ndc, -1.0, 1.0);
  vec4 b = u_inv_viewproj * vec4(v_ndc, 1.0, 1.0);
  vec3 d = normalize(b.xyz / b.w - a.xyz / a.w);

  vec3 col = sky_gradient(d);
  vec3 L = -u_sun_dir;
  float above = smoothstep(-0.02, 0.05, d.y);

  // Stars, fading in at night.
  if (u_stars > 0.0 && d.y > 0.0) {
    vec3 sp = d * 300.0;
    vec3 cell = floor(sp);
    float h = hash13(cell);
    if (h > 0.997) {
      vec3 c = cell + 0.5 + (vec3(hash13(cell + 1.3), hash13(cell + 2.7), hash13(cell + 4.1)) - 0.5) * 0.6;
      float dist = length(sp - c);
      float tw = 0.6 + 0.4 * sin(u_time * (2.0 + h * 40.0) + h * 100.0);
      col += vec3(0.9, 0.95, 1.0) * smoothstep(0.35, 0.0, dist) * u_stars * tw * 3.0 * above;
    }
  }

  // Moon.
  float md = dot(d, -u_moon_dir);
  if (md > 0.0) {
    col += vec3(0.85, 0.9, 1.0) * smoothstep(0.9993, 0.9996, md) * 2.0 * u_stars;
    col += vec3(0.3, 0.35, 0.5) * pow(md, 200.0) * 0.4 * u_stars;
  }

  // Sun disk.
  float sd = dot(d, L);
  float disk = smoothstep(1.0 - u_sun_size * 0.0012, 1.0 - u_sun_size * 0.0009, sd);
  col += u_sun_color * disk * 12.0 * above;

  // Clouds on a virtual plane.
  if (u_clouds > 0.0 && d.y > 0.0) {
    vec2 uv = d.xz / (d.y + 0.12) * 1.6 + vec2(u_time * u_cloud_speed * 0.02, u_time * u_cloud_speed * 0.007);
    float n = fbm(uv);
    float cover = smoothstep(1.0 - u_clouds, 1.0 - u_clouds + 0.35, n);
    float light = clamp(fbm(uv + L.xz * 0.08) - n + 0.55, 0.0, 1.0);
    vec3 lit = mix(u_sky_horizon * 0.9, vec3(1.0), 0.5) * (u_sun_color * 0.35 + hemi_light(vec3(0, 1, 0)) * 0.9);
    vec3 cc = mix(lit * 0.55, lit * 1.15, light);
    cc += u_sun_color * pow(max(sd, 0.0), 12.0) * 0.6;
    col = mix(col, cc, cover * smoothstep(0.0, 0.25, d.y) * 0.95);
  }

  // Let fog swallow the horizon so terrain blends into the sky.
  float hz = pow(1.0 - abs(d.y), 10.0);
  col = mix(col, u_fog_color, clamp(hz * min((u_fog_density + u_fog_height_density * 0.2) * 120.0, 1.0), 0.0, 1.0));
  frag = vec4(col, 1.0);
}
#endif
