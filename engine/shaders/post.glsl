// Post-processing: bloom down/up sampling and the final tonemap composite.
uniform sampler2D u_src;
uniform vec2 u_src_texel;
uniform float u_threshold;
uniform int u_first;

#ifdef VERTEX
out vec2 v_uv;
void main() {
  vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
  v_uv = p;
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
#endif

#ifdef FRAGMENT
in vec2 v_uv;
out vec4 frag;

#ifdef DOWNSAMPLE
vec3 tap(vec2 o) { return texture(u_src, v_uv + o * u_src_texel).rgb; }
float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3 karis(vec3 a, vec3 b, vec3 c, vec3 d) {
  float wa = 1.0 / (1.0 + luma(a)), wb = 1.0 / (1.0 + luma(b)), wc = 1.0 / (1.0 + luma(c)), wd = 1.0 / (1.0 + luma(d));
  return (a * wa + b * wb + c * wc + d * wd) / (wa + wb + wc + wd);
}
void main() {
  vec3 a = tap(vec2(-2, 2)), b = tap(vec2(0, 2)), c = tap(vec2(2, 2));
  vec3 d = tap(vec2(-2, 0)), e = tap(vec2(0, 0)), f = tap(vec2(2, 0));
  vec3 g = tap(vec2(-2, -2)), h = tap(vec2(0, -2)), i = tap(vec2(2, -2));
  vec3 j = tap(vec2(-1, 1)), k = tap(vec2(1, 1)), l = tap(vec2(-1, -1)), m = tap(vec2(1, -1));
  vec3 col;
  if (u_first != 0) {
    col = karis(j, k, l, m) * 0.5 + karis(a, b, d, e) * 0.125 + karis(b, c, e, f) * 0.125
        + karis(d, e, g, h) * 0.125 + karis(e, f, h, i) * 0.125;
    float br = max(col.r, max(col.g, col.b));
    float soft = clamp(br - u_threshold + 0.5, 0.0, 1.0);
    soft = soft * soft * 0.5;
    float contrib = max(soft, br - u_threshold) / max(br, 1e-4);
    col *= max(contrib, 0.0);
  } else {
    col = e * 0.125 + (a + c + g + i) * 0.03125 + (b + d + f + h) * 0.0625 + (j + k + l + m) * 0.125;
  }
  frag = vec4(max(col, vec3(0.0)), 1.0);
}
#endif

#ifdef UPSAMPLE
void main() {
  vec3 s = vec3(0.0);
  vec2 t = u_src_texel;
  s += texture(u_src, v_uv + vec2(-t.x, t.y)).rgb;
  s += texture(u_src, v_uv + vec2(0, t.y)).rgb * 2.0;
  s += texture(u_src, v_uv + vec2(t.x, t.y)).rgb;
  s += texture(u_src, v_uv + vec2(-t.x, 0)).rgb * 2.0;
  s += texture(u_src, v_uv).rgb * 4.0;
  s += texture(u_src, v_uv + vec2(t.x, 0)).rgb * 2.0;
  s += texture(u_src, v_uv + vec2(-t.x, -t.y)).rgb;
  s += texture(u_src, v_uv + vec2(0, -t.y)).rgb * 2.0;
  s += texture(u_src, v_uv + vec2(t.x, -t.y)).rgb;
  frag = vec4(s / 16.0, 1.0);
}
#endif

#ifdef COMPOSITE
uniform sampler2D u_bloom;
uniform float u_exposure;
uniform float u_bloom_strength;
uniform float u_saturation;
uniform float u_contrast;
uniform float u_vignette;
uniform float u_time;

vec3 aces(vec3 x) {
  const mat3 m1 = mat3(0.59719, 0.07600, 0.02840, 0.35458, 0.90834, 0.13383, 0.04823, 0.01566, 0.83777);
  const mat3 m2 = mat3(1.60475, -0.10208, -0.00327, -0.53108, 1.10813, -0.07276, -0.07367, -0.00605, 1.07602);
  vec3 v = m1 * x;
  vec3 a = v * (v + 0.0245786) - 0.000090537;
  vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
  return clamp(m2 * (a / b), 0.0, 1.0);
}

void main() {
  vec3 hdr = texture(u_src, v_uv).rgb;
  vec3 bloom = texture(u_bloom, v_uv).rgb;
  vec3 c = (hdr + bloom * u_bloom_strength) * u_exposure;
  c = aces(c);
  float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
  c = mix(vec3(l), c, u_saturation);
  c = pow(c, vec3(1.0 / 2.2));
  c = (c - 0.5) * u_contrast + 0.5;
  vec2 q = v_uv - 0.5;
  c *= 1.0 - dot(q, q) * u_vignette * 1.6;
  float n = fract(sin(dot(gl_FragCoord.xy + fract(u_time) * 61.0, vec2(12.9898, 78.233))) * 43758.5453);
  c += (n - 0.5) / 255.0;
  frag = vec4(clamp(c, 0.0, 1.0), 1.0);
}
#endif
#endif
