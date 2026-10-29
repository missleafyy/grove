// 2D canvas: rounded rects (SDF), gradients, images and SDF text in one batched shader.
uniform vec2 u_screen;
uniform sampler2D u_tex;

#ifdef VERTEX
layout(location = 0) in vec2 a_pos;
layout(location = 1) in vec2 a_uv;
layout(location = 2) in vec4 a_color;
layout(location = 3) in vec4 a_rect;     // local x, y, half w, half h
layout(location = 4) in vec4 a_params;   // mode, radius, border/outline, blur
layout(location = 5) in vec4 a_color2;   // border / outline colour
out vec2 v_uv;
out vec4 v_color;
out vec4 v_rect;
flat out vec4 v_params;
out vec4 v_color2;
void main() {
  v_uv = a_uv; v_color = a_color; v_rect = a_rect; v_params = a_params; v_color2 = a_color2;
  gl_Position = vec4(a_pos / u_screen * vec2(2.0, -2.0) + vec2(-1.0, 1.0), 0.0, 1.0);
}
#endif

#ifdef FRAGMENT
in vec2 v_uv;
in vec4 v_color;
in vec4 v_rect;
flat in vec4 v_params;
in vec4 v_color2;
out vec4 frag;

float sd_round_box(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
  int mode = int(v_params.x + 0.5);
  if (mode == 0) {          // filled rounded rect
    float d = sd_round_box(v_rect.xy, v_rect.zw, v_params.y);
    float aa = fwidth(d);
    frag = v_color * vec4(1, 1, 1, clamp(0.5 - d / aa, 0.0, 1.0));
  } else if (mode == 1) {   // border
    float d = sd_round_box(v_rect.xy, v_rect.zw, v_params.y);
    float aa = fwidth(d);
    float outer = clamp(0.5 - d / aa, 0.0, 1.0);
    float inner = clamp(0.5 - (d + v_params.z) / aa, 0.0, 1.0);
    frag = v_color * vec4(1, 1, 1, outer - inner);
  } else if (mode == 2) {   // image
    frag = texture(u_tex, v_uv) * v_color;
  } else if (mode == 3) {   // SDF text with optional outline
    float dist = texture(u_tex, v_uv).r;
    float w = fwidth(dist) * 0.7;
    float fill = smoothstep(0.5 - w, 0.5 + w, dist);
    float ow = v_params.z;
    if (ow > 0.0) {
      float o = smoothstep(0.5 - ow - w, 0.5 - ow + w, dist);
      vec4 oc = v_color2 * o;
      frag = mix(oc, v_color, fill);
      frag.a = max(o * v_color2.a, fill * v_color.a);
    } else {
      frag = vec4(v_color.rgb, v_color.a * fill);
    }
  } else {                  // soft drop shadow
    float d = sd_round_box(v_rect.xy, v_rect.zw, v_params.y);
    float a = 1.0 - smoothstep(-v_params.w, v_params.w, d);
    frag = vec4(0, 0, 0, v_color.a * a);
  }
}
#endif
