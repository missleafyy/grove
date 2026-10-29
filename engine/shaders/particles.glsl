// Camera-facing (optionally velocity-stretched) particle quads.
uniform float u_stretch;
uniform sampler2D u_tex;

#ifdef VERTEX
layout(location = 0) in vec4 i_pos_size;
layout(location = 1) in vec4 i_color;
layout(location = 2) in vec4 i_vel_rot;
out vec2 v_uv;
out vec4 v_color;
out vec3 v_world;
void main() {
  vec2 c = vec2(gl_VertexID & 1, (gl_VertexID >> 1) & 1) * 2.0 - 1.0;
  v_uv = c * 0.5 + 0.5;
  vec3 right = vec3(u_view[0][0], u_view[1][0], u_view[2][0]);
  vec3 up = vec3(u_view[0][1], u_view[1][1], u_view[2][1]);
  float size = i_pos_size.w;
  vec3 p = i_pos_size.xyz;
  vec3 vel = i_vel_rot.xyz;
  float sp = length(vel);
  if (u_stretch > 0.0 && sp > 0.01) {
    vec3 axis = vel / sp;
    vec3 side = normalize(cross(axis, normalize(u_cam_pos - p)));
    p += side * c.x * size + axis * c.y * (size + sp * u_stretch);
  } else {
    float r = i_vel_rot.w;
    vec2 rc = vec2(c.x * cos(r) - c.y * sin(r), c.x * sin(r) + c.y * cos(r));
    p += (right * rc.x + up * rc.y) * size;
  }
  v_world = p;
  v_color = vec4(srgb_to_linear(i_color.rgb), i_color.a);
  gl_Position = u_viewproj * vec4(p, 1.0);
}
#endif

#ifdef FRAGMENT
in vec2 v_uv;
in vec4 v_color;
in vec3 v_world;
out vec4 frag;
void main() {
  vec4 t = texture(u_tex, v_uv);
  vec4 c = v_color * t;
  float f = fog_amount(v_world, length(v_world - u_cam_pos));
  c.a *= 1.0 - clamp(f, 0.0, 1.0) * 0.8;
  frag = c;
}
#endif
