// Debug lines.
#ifdef VERTEX
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec3 a_color;
out vec3 v_color;
void main() { v_color = a_color; gl_Position = u_viewproj * vec4(a_pos, 1.0); }
#endif
#ifdef FRAGMENT
in vec3 v_color;
out vec4 frag;
void main() { frag = vec4(v_color * 2.0, 1.0); }
#endif
