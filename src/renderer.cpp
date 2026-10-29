// 3D renderer: meshes, materials, instances, lights, cascaded shadows, sky, particles, HDR + bloom.
#include "core.hpp"
#include "stb_image.h"
#include "stb_image_write.h"
#include <algorithm>
#include <random>

// ------------------------------------------------------------ resources
struct Mesh { GLuint vao = 0, vbo = 0, ebo = 0; int count = 0; V3 mn, mx; };
struct Texture { GLuint id = 0; int w = 0, h = 0; };
struct Instance {
  int mesh = 0, material = 0;
  bool visible = true, shadow = true;
  M4 model = M4::identity();
  float normal[9] = {1, 0, 0, 0, 1, 0, 0, 0, 1};
  float tint[4] = {1, 1, 1, 1};
  V3 wmn, wmx;
};
struct MultiMesh {
  int mesh = 0, material = 0, count = 0, visible_count = 0;
  bool visible = true, shadow = true;
  std::vector<float> data;  // 20 floats per instance: mat4 + rgba
  GLuint vao = 0, ibo = 0;
  bool dirty = true;
  V3 wmn, wmx;
};
struct Particle { V3 p, v; float age, life, rot, spin; };
struct ParticleSys {
  GrParticleConfig* cfg = nullptr;
  std::vector<Particle> ps;
  int max = 0;
  float accum = 0;
  int burst = 0;
};

static Pool<Mesh> meshes;
static Pool<Texture> textures;
static Pool<GrMaterial*> materials;
static Pool<Instance> instances;
static Pool<MultiMesh> multimeshes;
static Pool<GrLight*> lights;
static Pool<ParticleSys> particles;

static GrEnvironment env;
static GrStats stats;
static std::mt19937 rng(1234);

// Camera state.
static V3 cam_pos;
static Q4 cam_rot;
static float cam_fov = 70, cam_near = 0.1f, cam_far = 1000;
static M4 view, proj, viewproj, inv_viewproj;
static int vp_w = 1, vp_h = 1;

// GL objects.
static GLuint prog_main, prog_main_inst, prog_depth, prog_depth_inst, prog_sky, prog_particles, prog_lines;
static GLuint prog_down, prog_up, prog_composite;
static GLuint empty_vao, white_tex, dot_tex;
static GLuint shadow_tex, shadow_fbo;
static const int SHADOW_RES = 2048, CASCADES = 3;
static M4 shadow_mats[CASCADES];
static float shadow_splits[CASCADES], shadow_texel[CASCADES];
static GLuint msaa_fbo, msaa_color, msaa_depth, resolve_fbo, resolve_tex;
static int fb_w = 0, fb_h = 0;
static const int BLOOM_MIPS = 6;
static GLuint bloom_tex[BLOOM_MIPS], bloom_fbo[BLOOM_MIPS];
static int bloom_w[BLOOM_MIPS], bloom_h[BLOOM_MIPS];
static GLuint particle_vao, particle_vbo;
static GLuint line_vao, line_vbo;
static std::vector<float> line_data;
static std::vector<float> particle_data;
static float g_rtime = 0;

M4 m4_inverse(const M4& mm) {
  const float* m = mm.m;
  float inv[16];
  inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
  inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
  inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
  inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
  inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
  inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
  inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
  inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
  inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
  inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
  inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
  inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
  inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
  inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
  inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
  inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];
  float det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
  M4 r{};
  if (std::fabs(det) < 1e-12f) return M4::identity();
  det = 1.0f / det;
  for (int i = 0; i < 16; i++) r.m[i] = inv[i] * det;
  return r;
}

// ------------------------------------------------------------ shaders
static GLuint compile_stage(GLenum type, const std::string& src, const std::string& name) {
  GLuint s = glCreateShader(type);
  const char* c = src.c_str();
  glShaderSource(s, 1, &c, nullptr);
  glCompileShader(s);
  GLint ok;
  glGetShaderiv(s, GL_COMPILE_STATUS, &ok);
  if (!ok) {
    char log[8192];
    glGetShaderInfoLog(s, sizeof(log), nullptr, log);
    fprintf(stderr, "[grove] shader %s (%s) failed:\n%s\n", name.c_str(), type == GL_VERTEX_SHADER ? "vertex" : "fragment", log);
  }
  return s;
}

GLuint compile_program(const std::string& file, const std::string& defines) {
  std::string body, common;
  if (!read_file(g_engine_dir + "/shaders/" + file, body)) { fprintf(stderr, "[grove] missing shader %s\n", file.c_str()); return 0; }
  bool want_common = file != "canvas.glsl" && file != "post.glsl";
  if (want_common) read_file(g_engine_dir + "/shaders/common.glsl", common);
  std::string head = "#version 450 core\n" + defines;
  GLuint vs = compile_stage(GL_VERTEX_SHADER, head + "#define VERTEX\n" + common + body, file);
  GLuint fs = compile_stage(GL_FRAGMENT_SHADER, head + "#define FRAGMENT\n" + common + body, file);
  GLuint p = glCreateProgram();
  glAttachShader(p, vs);
  glAttachShader(p, fs);
  glLinkProgram(p);
  GLint ok;
  glGetProgramiv(p, GL_LINK_STATUS, &ok);
  if (!ok) {
    char log[8192];
    glGetProgramInfoLog(p, sizeof(log), nullptr, log);
    fprintf(stderr, "[grove] link %s failed:\n%s\n", file.c_str(), log);
  }
  glDeleteShader(vs);
  glDeleteShader(fs);
  return p;
}

// Uniform helpers (location lookups are cached by the driver well enough for our draw counts).
static inline GLint U(GLuint p, const char* n) { return glGetUniformLocation(p, n); }
static inline void set1i(GLuint p, const char* n, int v) { glUniform1i(U(p, n), v); }
static inline void set1f(GLuint p, const char* n, float v) { glUniform1f(U(p, n), v); }
static inline void set2f(GLuint p, const char* n, float a, float b) { glUniform2f(U(p, n), a, b); }
static inline void set3f(GLuint p, const char* n, const float* v) { glUniform3fv(U(p, n), 1, v); }
static inline void set4f(GLuint p, const char* n, const float* v) { glUniform4fv(U(p, n), 1, v); }
static inline void setm4(GLuint p, const char* n, const M4& m) { glUniformMatrix4fv(U(p, n), 1, GL_FALSE, m.m); }

static inline float lin(float c) { return std::pow(std::max(c, 0.0f), 2.2f); }
static void lin3(const float* in, float* out, float mul = 1) { for (int i = 0; i < 3; i++) out[i] = lin(in[i]) * mul; }

// ------------------------------------------------------------ setup
static GLuint make_tex2d(int w, int h, GLenum fmt, GLenum filter, GLenum wrap) {
  GLuint t;
  glCreateTextures(GL_TEXTURE_2D, 1, &t);
  glTextureStorage2D(t, 1, fmt, w, h);
  glTextureParameteri(t, GL_TEXTURE_MIN_FILTER, filter);
  glTextureParameteri(t, GL_TEXTURE_MAG_FILTER, filter);
  glTextureParameteri(t, GL_TEXTURE_WRAP_S, wrap);
  glTextureParameteri(t, GL_TEXTURE_WRAP_T, wrap);
  return t;
}

static void set_env_defaults() {
  GrEnvironment e{};
  float top[3] = {0.28f, 0.52f, 0.86f}, hor[3] = {0.72f, 0.82f, 0.92f}, gnd[3] = {0.35f, 0.33f, 0.3f};
  memcpy(e.sky_top, top, 12); memcpy(e.sky_horizon, hor, 12); memcpy(e.ground, gnd, 12);
  V3 sd = normalize(V3(-0.4f, -0.8f, -0.35f));
  e.sun_dir[0] = sd.x; e.sun_dir[1] = sd.y; e.sun_dir[2] = sd.z;
  e.sun_color[0] = 1; e.sun_color[1] = 0.95f; e.sun_color[2] = 0.88f;
  e.sun_energy = 2.5f; e.sun_size = 1; e.sun_shadows = 1; e.shadow_distance = 90;
  e.ambient_energy = 0.9f; e.reflection_energy = 0.6f;
  memcpy(e.fog_color, hor, 12);
  e.fog_density = 0.004f; e.fog_height = 0; e.fog_height_density = 0; e.fog_sun_scatter = 0.4f;
  e.clouds = 0.45f; e.cloud_speed = 1; e.stars = 0;
  e.moon_dir[0] = 0.3f; e.moon_dir[1] = -0.6f; e.moon_dir[2] = 0.74f;
  e.exposure = 1; e.bloom_strength = 0.08f; e.bloom_threshold = 1.0f; e.saturation = 1.05f; e.contrast = 1.03f; e.vignette = 0.25f;
  e.sky_enabled = 1;
  env = e;
}

static void build_programs() {
  prog_main = compile_program("main.glsl", "");
  prog_main_inst = compile_program("main.glsl", "#define INSTANCED\n");
  prog_depth = compile_program("main.glsl", "#define DEPTH\n");
  prog_depth_inst = compile_program("main.glsl", "#define DEPTH\n#define INSTANCED\n");
  prog_sky = compile_program("sky.glsl", "");
  prog_particles = compile_program("particles.glsl", "");
  prog_lines = compile_program("lines.glsl", "");
  prog_down = compile_program("post.glsl", "#define DOWNSAMPLE\n");
  prog_up = compile_program("post.glsl", "#define UPSAMPLE\n");
  prog_composite = compile_program("post.glsl", "#define COMPOSITE\n");
}

bool renderer_init() {
  build_programs();
  if (!prog_main || !prog_composite) return false;
  glCreateVertexArrays(1, &empty_vao);

  unsigned char white[4] = {255, 255, 255, 255};
  white_tex = make_tex2d(1, 1, GL_RGBA8, GL_LINEAR, GL_REPEAT);
  glTextureSubImage2D(white_tex, 0, 0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, white);

  // Soft round particle sprite.
  const int D = 64;
  std::vector<unsigned char> dot(D * D * 4);
  for (int y = 0; y < D; y++)
    for (int x = 0; x < D; x++) {
      float dx = (x + 0.5f) / D * 2 - 1, dy = (y + 0.5f) / D * 2 - 1;
      float r = std::sqrt(dx * dx + dy * dy);
      float a = std::max(0.0f, 1 - r);
      a = a * a * (3 - 2 * a);
      unsigned char* p = &dot[(y * D + x) * 4];
      p[0] = p[1] = p[2] = 255; p[3] = (unsigned char)(a * 255);
    }
  dot_tex = make_tex2d(D, D, GL_RGBA8, GL_LINEAR, GL_CLAMP_TO_EDGE);
  glTextureSubImage2D(dot_tex, 0, 0, 0, D, D, GL_RGBA, GL_UNSIGNED_BYTE, dot.data());

  // Cascaded shadow map array with hardware depth comparison.
  glCreateTextures(GL_TEXTURE_2D_ARRAY, 1, &shadow_tex);
  glTextureStorage3D(shadow_tex, 1, GL_DEPTH_COMPONENT32F, SHADOW_RES, SHADOW_RES, CASCADES);
  glTextureParameteri(shadow_tex, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTextureParameteri(shadow_tex, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTextureParameteri(shadow_tex, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTextureParameteri(shadow_tex, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTextureParameteri(shadow_tex, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE);
  glTextureParameteri(shadow_tex, GL_TEXTURE_COMPARE_FUNC, GL_LEQUAL);
  glCreateFramebuffers(1, &shadow_fbo);
  glNamedFramebufferDrawBuffer(shadow_fbo, GL_NONE);
  glNamedFramebufferReadBuffer(shadow_fbo, GL_NONE);

  // Particle instance stream.
  glCreateVertexArrays(1, &particle_vao);
  glCreateBuffers(1, &particle_vbo);
  glVertexArrayVertexBuffer(particle_vao, 0, particle_vbo, 0, 12 * sizeof(float));
  glVertexArrayBindingDivisor(particle_vao, 0, 1);
  for (int i = 0; i < 3; i++) {
    glEnableVertexArrayAttrib(particle_vao, i);
    glVertexArrayAttribFormat(particle_vao, i, 4, GL_FLOAT, GL_FALSE, i * 4 * sizeof(float));
    glVertexArrayAttribBinding(particle_vao, i, 0);
  }

  glCreateVertexArrays(1, &line_vao);
  glCreateBuffers(1, &line_vbo);
  glVertexArrayVertexBuffer(line_vao, 0, line_vbo, 0, 6 * sizeof(float));
  for (int i = 0; i < 2; i++) {
    glEnableVertexArrayAttrib(line_vao, i);
    glVertexArrayAttribFormat(line_vao, i, 3, GL_FLOAT, GL_FALSE, i * 3 * sizeof(float));
    glVertexArrayAttribBinding(line_vao, i, 0);
  }

  set_env_defaults();
  return true;
}

static void destroy_targets() {
  if (!fb_w) return;
  glDeleteFramebuffers(1, &msaa_fbo); glDeleteRenderbuffers(1, &msaa_color); glDeleteRenderbuffers(1, &msaa_depth);
  glDeleteFramebuffers(1, &resolve_fbo); glDeleteTextures(1, &resolve_tex);
  glDeleteFramebuffers(BLOOM_MIPS, bloom_fbo); glDeleteTextures(BLOOM_MIPS, bloom_tex);
  fb_w = fb_h = 0;
}

static void ensure_targets(int w, int h) {
  if (w == fb_w && h == fb_h) return;
  destroy_targets();
  fb_w = w; fb_h = h;
  glCreateRenderbuffers(1, &msaa_color);
  glNamedRenderbufferStorageMultisample(msaa_color, 4, GL_RGBA16F, w, h);
  glCreateRenderbuffers(1, &msaa_depth);
  glNamedRenderbufferStorageMultisample(msaa_depth, 4, GL_DEPTH_COMPONENT32F, w, h);
  glCreateFramebuffers(1, &msaa_fbo);
  glNamedFramebufferRenderbuffer(msaa_fbo, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, msaa_color);
  glNamedFramebufferRenderbuffer(msaa_fbo, GL_DEPTH_ATTACHMENT, GL_RENDERBUFFER, msaa_depth);

  resolve_tex = make_tex2d(w, h, GL_RGBA16F, GL_LINEAR, GL_CLAMP_TO_EDGE);
  glCreateFramebuffers(1, &resolve_fbo);
  glNamedFramebufferTexture(resolve_fbo, GL_COLOR_ATTACHMENT0, resolve_tex, 0);

  int bw = w, bh = h;
  for (int i = 0; i < BLOOM_MIPS; i++) {
    bw = std::max(1, bw / 2); bh = std::max(1, bh / 2);
    bloom_w[i] = bw; bloom_h[i] = bh;
    bloom_tex[i] = make_tex2d(bw, bh, GL_R11F_G11F_B10F, GL_LINEAR, GL_CLAMP_TO_EDGE);
    glCreateFramebuffers(1, &bloom_fbo[i]);
    glNamedFramebufferTexture(bloom_fbo[i], GL_COLOR_ATTACHMENT0, bloom_tex[i], 0);
  }
}

void renderer_reset() {
  meshes.each([](int, Mesh& m) { glDeleteVertexArrays(1, &m.vao); glDeleteBuffers(1, &m.vbo); glDeleteBuffers(1, &m.ebo); });
  textures.each([](int, Texture& t) { glDeleteTextures(1, &t.id); });
  materials.each([](int, GrMaterial*& m) { delete m; });
  multimeshes.each([](int, MultiMesh& m) { glDeleteVertexArrays(1, &m.vao); glDeleteBuffers(1, &m.ibo); });
  lights.each([](int, GrLight*& l) { delete l; });
  particles.each([](int, ParticleSys& p) { delete p.cfg; });
  meshes.clear(); textures.clear(); materials.clear(); instances.clear();
  multimeshes.clear(); lights.clear(); particles.clear();
  line_data.clear();
  set_env_defaults();
  // Reload shaders so edits apply on F5.
  GLuint progs[] = {prog_main, prog_main_inst, prog_depth, prog_depth_inst, prog_sky, prog_particles, prog_lines, prog_down, prog_up, prog_composite};
  for (GLuint p : progs) glDeleteProgram(p);
  build_programs();
}

void renderer_shutdown() {
  renderer_reset();
  destroy_targets();
}

// ------------------------------------------------------------ mesh / texture / material API
static void transform_aabb(const M4& m, V3 mn, V3 mx, V3& omn, V3& omx) {
  omn = V3(1e30f, 1e30f, 1e30f); omx = V3(-1e30f, -1e30f, -1e30f);
  for (int i = 0; i < 8; i++) {
    V3 p = m.point(V3(i & 1 ? mx.x : mn.x, i & 2 ? mx.y : mn.y, i & 4 ? mx.z : mn.z));
    omn = V3(std::min(omn.x, p.x), std::min(omn.y, p.y), std::min(omn.z, p.z));
    omx = V3(std::max(omx.x, p.x), std::max(omx.y, p.y), std::max(omx.z, p.z));
  }
}

static void setup_mesh_attribs(GLuint vao) {
  glEnableVertexArrayAttrib(vao, 0); glVertexArrayAttribFormat(vao, 0, 3, GL_FLOAT, GL_FALSE, 0);
  glEnableVertexArrayAttrib(vao, 1); glVertexArrayAttribFormat(vao, 1, 3, GL_FLOAT, GL_FALSE, 12);
  glEnableVertexArrayAttrib(vao, 2); glVertexArrayAttribFormat(vao, 2, 2, GL_FLOAT, GL_FALSE, 24);
  glEnableVertexArrayAttrib(vao, 3); glVertexArrayAttribFormat(vao, 3, 4, GL_FLOAT, GL_FALSE, 32);
  for (int i = 0; i < 4; i++) glVertexArrayAttribBinding(vao, i, 0);
}

extern "C" {

int gr_mesh_create(const GrVertex* v, int nv, const unsigned* idx, int ni) {
  if (nv <= 0) return 0;
  Mesh m;
  glCreateVertexArrays(1, &m.vao);
  glCreateBuffers(1, &m.vbo);
  glNamedBufferStorage(m.vbo, nv * sizeof(GrVertex), v, 0);
  glVertexArrayVertexBuffer(m.vao, 0, m.vbo, 0, sizeof(GrVertex));
  setup_mesh_attribs(m.vao);
  std::vector<unsigned> seq;
  if (!idx || ni <= 0) { seq.resize(nv); for (int i = 0; i < nv; i++) seq[i] = i; idx = seq.data(); ni = nv; }
  glCreateBuffers(1, &m.ebo);
  glNamedBufferStorage(m.ebo, ni * sizeof(unsigned), idx, 0);
  glVertexArrayElementBuffer(m.vao, m.ebo);
  m.count = ni;
  m.mn = V3(1e30f, 1e30f, 1e30f); m.mx = V3(-1e30f, -1e30f, -1e30f);
  for (int i = 0; i < nv; i++) {
    m.mn = V3(std::min(m.mn.x, v[i].px), std::min(m.mn.y, v[i].py), std::min(m.mn.z, v[i].pz));
    m.mx = V3(std::max(m.mx.x, v[i].px), std::max(m.mx.y, v[i].py), std::max(m.mx.z, v[i].pz));
  }
  return meshes.add(m);
}

void gr_mesh_free(int id) {
  if (Mesh* m = meshes.get(id)) {
    glDeleteVertexArrays(1, &m->vao); glDeleteBuffers(1, &m->vbo); glDeleteBuffers(1, &m->ebo);
    meshes.remove(id);
  }
}

void gr_mesh_aabb(int id, float* mn, float* mx) {
  Mesh* m = meshes.get(id);
  if (!m) { mn[0] = mn[1] = mn[2] = mx[0] = mx[1] = mx[2] = 0; return; }
  mn[0] = m->mn.x; mn[1] = m->mn.y; mn[2] = m->mn.z;
  mx[0] = m->mx.x; mx[1] = m->mx.y; mx[2] = m->mx.z;
}

static int upload_texture(int w, int h, const unsigned char* rgba, int nearest, int repeat, bool srgb) {
  Texture t;
  t.w = w; t.h = h;
  int levels = nearest ? 1 : 1 + (int)std::floor(std::log2((float)std::max(w, h)));
  glCreateTextures(GL_TEXTURE_2D, 1, &t.id);
  glTextureStorage2D(t.id, levels, srgb ? GL_SRGB8_ALPHA8 : GL_RGBA8, w, h);
  glTextureSubImage2D(t.id, 0, 0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, rgba);
  if (levels > 1) glGenerateTextureMipmap(t.id);
  glTextureParameteri(t.id, GL_TEXTURE_MIN_FILTER, nearest ? GL_NEAREST : GL_LINEAR_MIPMAP_LINEAR);
  glTextureParameteri(t.id, GL_TEXTURE_MAG_FILTER, nearest ? GL_NEAREST : GL_LINEAR);
  glTextureParameterf(t.id, GL_TEXTURE_MAX_ANISOTROPY, 8.0f);
  GLenum wrap = repeat ? GL_REPEAT : GL_CLAMP_TO_EDGE;
  glTextureParameteri(t.id, GL_TEXTURE_WRAP_S, wrap);
  glTextureParameteri(t.id, GL_TEXTURE_WRAP_T, wrap);
  return textures.add(t);
}

int gr_texture_load(const char* path, int nearest) {
  int w, h, n;
  unsigned char* px = stbi_load(path, &w, &h, &n, 4);
  if (!px) { fprintf(stderr, "[grove] could not load texture %s\n", path); return 0; }
  int id = upload_texture(w, h, px, nearest, 1, true);
  stbi_image_free(px);
  return id;
}

int gr_texture_create(int w, int h, const unsigned char* rgba, int nearest, int repeat) {
  return upload_texture(w, h, rgba, nearest, repeat, true);
}

void gr_texture_size(int id, int* w, int* h) {
  Texture* t = textures.get(id);
  *w = t ? t->w : 0; *h = t ? t->h : 0;
}

void gr_texture_free(int id) {
  if (Texture* t = textures.get(id)) { glDeleteTextures(1, &t->id); textures.remove(id); }
}

GLuint renderer_texture_gl(int id) {
  Texture* t = textures.get(id);
  return t ? t->id : white_tex;
}

int gr_material_create(void) {
  GrMaterial* m = new GrMaterial{};
  m->albedo[0] = m->albedo[1] = m->albedo[2] = m->albedo[3] = 1;
  m->roughness = 0.8f;
  m->uv_scale[0] = m->uv_scale[1] = 1;
  m->vertex_color = 1;
  return materials.add(m);
}
GrMaterial* gr_material_get(int id) { GrMaterial** m = materials.get(id); return m ? *m : nullptr; }
void gr_material_free(int id) { if (GrMaterial** m = materials.get(id)) { delete *m; materials.remove(id); } }

int gr_model_load(const char* path, int* out_meshes, int* out_mats, int max_parts) {
  std::vector<std::vector<GrVertex>> pv;
  std::vector<std::vector<unsigned>> pi;
  std::vector<GrMaterial> mats;
  std::vector<std::string> texs;
  if (!meshload(path, pv, pi, mats, texs)) return 0;
  int n = std::min((int)pv.size(), max_parts);
  for (int i = 0; i < n; i++) {
    out_meshes[i] = gr_mesh_create(pv[i].data(), (int)pv[i].size(), pi[i].data(), (int)pi[i].size());
    int mid = gr_material_create();
    *gr_material_get(mid) = mats[i];
    if (!texs[i].empty()) gr_material_get(mid)->albedo_tex = gr_texture_load(texs[i].c_str(), 0);
    out_mats[i] = mid;
  }
  return n;
}

// ------------------------------------------------------------ instances
int gr_instance_create(int mesh, int material) {
  Instance in;
  in.mesh = mesh; in.material = material;
  if (Mesh* m = meshes.get(mesh)) { in.wmn = m->mn; in.wmx = m->mx; }
  return instances.add(in);
}
void gr_instance_free(int id) { instances.remove(id); }
void gr_instance_set(int id, int mesh, int material, int visible, int shadow) {
  Instance* in = instances.get(id);
  if (!in) return;
  if (in->mesh != mesh) {
    in->mesh = mesh;
    if (Mesh* m = meshes.get(mesh)) transform_aabb(in->model, m->mn, m->mx, in->wmn, in->wmx);
  }
  in->material = material; in->visible = visible; in->shadow = shadow;
}
void gr_instance_xform(int id, float px, float py, float pz, float qx, float qy, float qz, float qw, float sx, float sy, float sz) {
  Instance* in = instances.get(id);
  if (!in) return;
  Q4 q{qx, qy, qz, qw};
  in->model = m4_trs(V3(px, py, pz), q, V3(sx, sy, sz));
  // Normal matrix = inverse-transpose of the upper 3x3 = R * S^-1.
  M4 nm = m4_trs(V3(), q, V3(1 / (sx ? sx : 1), 1 / (sy ? sy : 1), 1 / (sz ? sz : 1)));
  for (int c = 0; c < 3; c++) for (int r = 0; r < 3; r++) in->normal[c * 3 + r] = nm.m[c * 4 + r];
  if (Mesh* m = meshes.get(in->mesh)) transform_aabb(in->model, m->mn, m->mx, in->wmn, in->wmx);
}
void gr_instance_tint(int id, float r, float g, float b, float a) {
  if (Instance* in = instances.get(id)) { in->tint[0] = r; in->tint[1] = g; in->tint[2] = b; in->tint[3] = a; }
}

// ------------------------------------------------------------ multimesh
int gr_multimesh_create(int mesh, int material, int count) {
  MultiMesh mm;
  mm.mesh = mesh; mm.material = material; mm.count = count; mm.visible_count = count;
  mm.data.assign(count * 20, 0.0f);
  for (int i = 0; i < count; i++) { float* d = &mm.data[i * 20]; d[0] = d[5] = d[10] = d[15] = 1; d[16] = d[17] = d[18] = d[19] = 1; }
  glCreateVertexArrays(1, &mm.vao);
  glCreateBuffers(1, &mm.ibo);
  glNamedBufferData(mm.ibo, std::max(1, count) * 20 * sizeof(float), nullptr, GL_DYNAMIC_DRAW);
  if (Mesh* m = meshes.get(mesh)) {
    glVertexArrayVertexBuffer(mm.vao, 0, m->vbo, 0, sizeof(GrVertex));
    glVertexArrayElementBuffer(mm.vao, m->ebo);
  }
  setup_mesh_attribs(mm.vao);
  glVertexArrayVertexBuffer(mm.vao, 1, mm.ibo, 0, 20 * sizeof(float));
  glVertexArrayBindingDivisor(mm.vao, 1, 1);
  for (int i = 0; i < 5; i++) {
    glEnableVertexArrayAttrib(mm.vao, 4 + i);
    glVertexArrayAttribFormat(mm.vao, 4 + i, 4, GL_FLOAT, GL_FALSE, i * 16);
    glVertexArrayAttribBinding(mm.vao, 4 + i, 1);
  }
  return multimeshes.add(mm);
}
void gr_multimesh_set(int id, int i, float px, float py, float pz, float qx, float qy, float qz, float qw, float sx, float sy, float sz, float r, float g, float b, float a) {
  MultiMesh* mm = multimeshes.get(id);
  if (!mm || i < 0 || i >= mm->count) return;
  M4 m = m4_trs(V3(px, py, pz), Q4{qx, qy, qz, qw}, V3(sx, sy, sz));
  float* d = &mm->data[i * 20];
  memcpy(d, m.m, 64);
  d[16] = r; d[17] = g; d[18] = b; d[19] = a;
  mm->dirty = true;
}
void gr_multimesh_commit(int id, int visible_count) {
  MultiMesh* mm = multimeshes.get(id);
  if (!mm) return;
  mm->visible_count = std::max(0, std::min(visible_count < 0 ? mm->count : visible_count, mm->count));
  glNamedBufferSubData(mm->ibo, 0, mm->visible_count * 20 * sizeof(float), mm->data.data());
  mm->dirty = false;
  Mesh* m = meshes.get(mm->mesh);
  mm->wmn = V3(1e30f, 1e30f, 1e30f); mm->wmx = V3(-1e30f, -1e30f, -1e30f);
  if (!m) return;
  for (int i = 0; i < mm->visible_count; i++) {
    M4 t; memcpy(t.m, &mm->data[i * 20], 64);
    V3 a, b;
    transform_aabb(t, m->mn, m->mx, a, b);
    mm->wmn = V3(std::min(mm->wmn.x, a.x), std::min(mm->wmn.y, a.y), std::min(mm->wmn.z, a.z));
    mm->wmx = V3(std::max(mm->wmx.x, b.x), std::max(mm->wmx.y, b.y), std::max(mm->wmx.z, b.z));
  }
}
void gr_multimesh_options(int id, int visible, int shadow) {
  if (MultiMesh* mm = multimeshes.get(id)) { mm->visible = visible; mm->shadow = shadow; }
}
void gr_multimesh_free(int id) {
  if (MultiMesh* mm = multimeshes.get(id)) { glDeleteVertexArrays(1, &mm->vao); glDeleteBuffers(1, &mm->ibo); multimeshes.remove(id); }
}

// ------------------------------------------------------------ lights / env / camera
int gr_light_create(void) {
  GrLight* l = new GrLight{};
  l->enabled = 1; l->color[0] = l->color[1] = l->color[2] = 1; l->energy = 1; l->range = 10;
  l->dir[1] = -1; l->spot_angle = 30; l->spot_softness = 0.3f;
  return lights.add(l);
}
GrLight* gr_light_get(int id) { GrLight** l = lights.get(id); return l ? *l : nullptr; }
void gr_light_free(int id) { if (GrLight** l = lights.get(id)) { delete *l; lights.remove(id); } }

GrEnvironment* gr_environment(void) { return &env; }
GrStats* gr_stats(void) { return &stats; }

void gr_camera(float px, float py, float pz, float qx, float qy, float qz, float qw, float fov, float zn, float zf) {
  cam_pos = V3(px, py, pz); cam_rot = Q4{qx, qy, qz, qw};
  cam_fov = fov; cam_near = zn; cam_far = zf;
}

int gr_world_to_screen(float x, float y, float z, float* sx, float* sy) {
  float v[4] = {x, y, z, 1}, o[4] = {0, 0, 0, 0};
  for (int r = 0; r < 4; r++) for (int c = 0; c < 4; c++) o[r] += viewproj(r, c) * v[c];
  if (o[3] <= 1e-4f) { *sx = *sy = -10000; return 0; }
  float nx = o[0] / o[3], ny = o[1] / o[3];
  *sx = (nx * 0.5f + 0.5f) * vp_w;
  *sy = (1 - (ny * 0.5f + 0.5f)) * vp_h;
  return nx >= -1 && nx <= 1 && ny >= -1 && ny <= 1;
}

void gr_screen_ray(float sx, float sy, float* origin, float* dir) {
  float nx = sx / vp_w * 2 - 1, ny = 1 - sy / vp_h * 2;
  auto unproj = [](float x, float y, float z) {
    float v[4] = {x, y, z, 1}, o[4] = {0, 0, 0, 0};
    for (int r = 0; r < 4; r++) for (int c = 0; c < 4; c++) o[r] += inv_viewproj(r, c) * v[c];
    return V3(o[0] / o[3], o[1] / o[3], o[2] / o[3]);
  };
  V3 a = unproj(nx, ny, -1), b = unproj(nx, ny, 1);
  V3 d = normalize(b - a);
  origin[0] = a.x; origin[1] = a.y; origin[2] = a.z;
  dir[0] = d.x; dir[1] = d.y; dir[2] = d.z;
}

// ------------------------------------------------------------ particles
int gr_particles_create(int max_particles) {
  ParticleSys ps;
  ps.cfg = new GrParticleConfig{};
  GrParticleConfig& c = *ps.cfg;
  c.emitting = 1; c.rate = 20; c.lifetime = 1.5f; c.world_space = 1;
  c.dir[1] = 1; c.spread = 25; c.speed = 2;
  c.color_start[0] = c.color_start[1] = c.color_start[2] = c.color_start[3] = 1;
  c.color_end[0] = c.color_end[1] = c.color_end[2] = 1;
  c.size_start = 0.2f; c.size_end = 0.05f;
  ps.max = std::max(1, max_particles);
  ps.ps.reserve(ps.max);
  return particles.add(ps);
}
GrParticleConfig* gr_particles_config(int id) { ParticleSys* p = particles.get(id); return p ? p->cfg : nullptr; }
void gr_particles_burst(int id, int count) { if (ParticleSys* p = particles.get(id)) p->burst += count; }
int gr_particles_alive(int id) { ParticleSys* p = particles.get(id); return p ? (int)p->ps.size() : 0; }
void gr_particles_free(int id) { if (ParticleSys* p = particles.get(id)) { delete p->cfg; particles.remove(id); } }

void gr_debug_line(float ax, float ay, float az, float bx, float by, float bz, float r, float g, float b) {
  float d[12] = {ax, ay, az, r, g, b, bx, by, bz, r, g, b};
  line_data.insert(line_data.end(), d, d + 12);
}

}  // extern "C"

static float frand() { return std::uniform_real_distribution<float>(0, 1)(rng); }

static void spawn_particle(ParticleSys& s) {
  if ((int)s.ps.size() >= s.max) return;
  GrParticleConfig& c = *s.cfg;
  Particle p;
  p.p = V3(c.pos[0] + (frand() * 2 - 1) * c.emit_box[0], c.pos[1] + (frand() * 2 - 1) * c.emit_box[1], c.pos[2] + (frand() * 2 - 1) * c.emit_box[2]);
  if (c.emit_radius > 0) {
    V3 r;
    do r = V3(frand() * 2 - 1, frand() * 2 - 1, frand() * 2 - 1); while (dot(r, r) > 1);
    p.p = p.p + r * c.emit_radius;
  }
  // Random direction inside a cone around dir.
  V3 d = normalize(V3(c.dir[0], c.dir[1], c.dir[2]));
  float spread = c.spread * 3.14159265f / 180.0f;
  float cz = 1 - frand() * (1 - std::cos(spread));
  float phi = frand() * 6.2831853f;
  float sz = std::sqrt(std::max(0.0f, 1 - cz * cz));
  V3 t = std::fabs(d.y) < 0.99f ? normalize(cross(d, V3(0, 1, 0))) : V3(1, 0, 0);
  V3 b = cross(d, t);
  V3 dir = d * cz + t * (sz * std::cos(phi)) + b * (sz * std::sin(phi));
  float sp = c.speed * (1 + (frand() * 2 - 1) * c.speed_random);
  p.v = dir * sp;
  p.age = 0;
  p.life = std::max(0.01f, c.lifetime * (1 + (frand() * 2 - 1) * c.lifetime_random));
  p.rot = frand() * 6.28f;
  p.spin = (frand() * 2 - 1) * 2;
  s.ps.push_back(p);
}

static void update_particles(float dt) {
  particles.each([dt](int, ParticleSys& s) {
    GrParticleConfig& c = *s.cfg;
    if (c.emitting) {
      s.accum += c.rate * dt;
      while (s.accum >= 1) { spawn_particle(s); s.accum -= 1; }
    } else s.accum = 0;
    while (s.burst > 0) { spawn_particle(s); s.burst--; }
    V3 g(c.gravity[0], c.gravity[1], c.gravity[2]);
    float damp = std::exp(-c.damping * dt);
    for (size_t i = 0; i < s.ps.size();) {
      Particle& p = s.ps[i];
      p.age += dt;
      if (p.age >= p.life) { p = s.ps.back(); s.ps.pop_back(); continue; }
      p.v = (p.v + g * dt) * damp;
      if (c.turbulence > 0) {
        float tt = g_rtime * 1.3f;
        p.v = p.v + V3(std::sin(p.p.y * 1.7f + tt + i), std::sin(p.p.z * 1.3f + tt * 1.1f), std::sin(p.p.x * 1.5f + tt * 0.9f)) * (c.turbulence * dt);
      }
      p.p = p.p + p.v * dt;
      p.rot += p.spin * dt;
      i++;
    }
  });
}

// ------------------------------------------------------------ frame
struct Frustum { float pl[6][4]; };
static Frustum frustum_from(const M4& m) {
  Frustum f;
  for (int i = 0; i < 6; i++) {
    int row = i / 2;
    float s = (i % 2) ? -1.0f : 1.0f;
    for (int c = 0; c < 4; c++) f.pl[i][c] = m(3, c) + s * m(row, c);
  }
  return f;
}
static bool aabb_visible(const Frustum& f, V3 mn, V3 mx) {
  for (int i = 0; i < 6; i++) {
    const float* p = f.pl[i];
    V3 v(p[0] > 0 ? mx.x : mn.x, p[1] > 0 ? mx.y : mn.y, p[2] > 0 ? mx.z : mn.z);
    if (p[0] * v.x + p[1] * v.y + p[2] * v.z + p[3] < 0) return false;
  }
  return true;
}

static void bind_material(GLuint p, const GrMaterial* m, bool depth_only) {
  static GrMaterial def = [] { GrMaterial d{}; d.albedo[0] = d.albedo[1] = d.albedo[2] = d.albedo[3] = 1; d.roughness = 0.8f; d.uv_scale[0] = d.uv_scale[1] = 1; d.vertex_color = 1; return d; }();
  if (!m) m = &def;
  set1f(p, "u_wind", m->wind);
  set1i(p, "u_effect", m->effect);
  set1i(p, "u_vertex_color", m->vertex_color);
  set1f(p, "u_alpha_cutoff", m->alpha_cutoff);
  set2f(p, "u_uv_scale", m->uv_scale[0], m->uv_scale[1]);
  set1i(p, "u_has_tex", m->albedo_tex != 0);
  set1i(p, "u_triplanar", m->triplanar);
  glBindTextureUnit(0, renderer_texture_gl(m->albedo_tex));
  float a4[4] = {lin(m->albedo[0]), lin(m->albedo[1]), lin(m->albedo[2]), m->albedo[3]};
  set4f(p, "u_albedo", a4);
  if (depth_only) return;
  float e[3];
  lin3(m->emission, e, m->emission_energy);
  set3f(p, "u_emission", e);
  set1f(p, "u_roughness", m->roughness);
  set1f(p, "u_metallic", m->metallic);
  set1f(p, "u_rim", m->rim);
  set1i(p, "u_unshaded", m->unshaded);
  set1i(p, "u_no_fog", m->no_fog);
  if (m->double_sided) glDisable(GL_CULL_FACE); else glEnable(GL_CULL_FACE);
}

static void set_frame_uniforms(GLuint p, const M4& vp) {
  glUseProgram(p);
  setm4(p, "u_view", view);
  setm4(p, "u_proj", proj);
  setm4(p, "u_viewproj", vp);
  float cp[3] = {cam_pos.x, cam_pos.y, cam_pos.z};
  set3f(p, "u_cam_pos", cp);
  set1f(p, "u_time", g_rtime);
  float c[3];
  lin3(env.sky_top, c); set3f(p, "u_sky_top", c);
  lin3(env.sky_horizon, c); set3f(p, "u_sky_horizon", c);
  lin3(env.ground, c); set3f(p, "u_ground", c);
  V3 sd = normalize(V3(env.sun_dir[0], env.sun_dir[1], env.sun_dir[2]));
  float sdv[3] = {sd.x, sd.y, sd.z};
  set3f(p, "u_sun_dir", sdv);
  lin3(env.sun_color, c, env.sun_energy); set3f(p, "u_sun_color", c);
  set1f(p, "u_sun_size", env.sun_size);
  V3 md = normalize(V3(env.moon_dir[0], env.moon_dir[1], env.moon_dir[2]));
  float mdv[3] = {md.x, md.y, md.z};
  set3f(p, "u_moon_dir", mdv);
  set1f(p, "u_ambient_energy", env.ambient_energy);
  set1f(p, "u_reflection_energy", env.reflection_energy);
  lin3(env.fog_color, c); set3f(p, "u_fog_color", c);
  set1f(p, "u_fog_density", env.fog_density);
  set1f(p, "u_fog_height", env.fog_height);
  set1f(p, "u_fog_height_density", env.fog_height_density);
  set1f(p, "u_fog_sun_scatter", env.fog_sun_scatter);
  set1f(p, "u_clouds", env.clouds);
  set1f(p, "u_cloud_speed", env.cloud_speed);
  set1f(p, "u_stars", env.stars);
}

struct DrawItem { int kind; int id; float dist; };  // kind 0 instance, 1 multimesh

static void draw_instance(GLuint p, Instance& in, bool depth) {
  Mesh* m = meshes.get(in.mesh);
  if (!m) return;
  setm4(p, "u_model", in.model);
  glUniformMatrix3fv(U(p, "u_normal_mat"), 1, GL_FALSE, in.normal);
  if (!depth) set4f(p, "u_tint", in.tint);
  glBindVertexArray(m->vao);
  glDrawElements(GL_TRIANGLES, m->count, GL_UNSIGNED_INT, nullptr);
  stats.draw_calls++;
  stats.triangles += m->count / 3;
}

static void draw_multimesh(GLuint p, MultiMesh& mm, bool depth) {
  Mesh* m = meshes.get(mm.mesh);
  if (!m || mm.visible_count == 0) return;
  if (!depth) { float t[4] = {1, 1, 1, 1}; set4f(p, "u_tint", t); }
  glBindVertexArray(mm.vao);
  glDrawElementsInstanced(GL_TRIANGLES, m->count, GL_UNSIGNED_INT, nullptr, mm.visible_count);
  stats.draw_calls++;
  stats.triangles += m->count / 3 * mm.visible_count;
}

static void render_shadows() {
  V3 L = normalize(V3(env.sun_dir[0], env.sun_dir[1], env.sun_dir[2]));
  float aspect = (float)vp_w / vp_h;
  float fovy = cam_fov * 3.14159265f / 180.0f;
  float th = std::tan(fovy * 0.5f), tw = th * aspect;
  float nearp = cam_near, farp = std::min(env.shadow_distance, cam_far);
  V3 fwd = qrot(cam_rot, V3(0, 0, -1)), right = qrot(cam_rot, V3(1, 0, 0)), up = qrot(cam_rot, V3(0, 1, 0));

  glBindFramebuffer(GL_FRAMEBUFFER, shadow_fbo);
  glViewport(0, 0, SHADOW_RES, SHADOW_RES);
  glEnable(GL_DEPTH_TEST);
  glDepthMask(GL_TRUE);
  glEnable(GL_POLYGON_OFFSET_FILL);
  glPolygonOffset(1.5f, 2.0f);
  glDisable(GL_BLEND);

  float prev = nearp;
  for (int c = 0; c < CASCADES; c++) {
    float t = (c + 1) / (float)CASCADES;
    float split = 0.7f * (nearp * std::pow(farp / nearp, t)) + 0.3f * (nearp + (farp - nearp) * t);
    shadow_splits[c] = split;
    // Bounding sphere of this frustum slice: stable under camera rotation.
    float n = prev, f = split;
    V3 center(0, 0, 0);
    V3 corners[8];
    for (int i = 0; i < 8; i++) {
      float d = (i & 4) ? f : n;
      corners[i] = cam_pos + fwd * d + right * (((i & 1) ? 1 : -1) * tw * d) + up * (((i & 2) ? 1 : -1) * th * d);
      center = center + corners[i];
    }
    center = center * (1.0f / 8);
    float radius = 0;
    for (auto& cc : corners) radius = std::max(radius, length(cc - center));
    radius = std::ceil(radius * 16) / 16;
    prev = split;

    V3 upv = std::fabs(L.y) > 0.99f ? V3(0, 0, 1) : V3(0, 1, 0);
    float back = radius + 120.0f;
    M4 lview = m4_look_at(center - L * back, center, upv);
    M4 lproj = m4_ortho(-radius, radius, -radius, radius, 0.0f, back + radius);
    // Snap to texel grid to stop shimmering.
    M4 lvp = lproj * lview;
    V3 o = lvp.point(V3(0, 0, 0));
    float texel_ndc = 2.0f / SHADOW_RES;
    float ox = std::round(o.x / texel_ndc) * texel_ndc - o.x;
    float oy = std::round(o.y / texel_ndc) * texel_ndc - o.y;
    lproj.m[12] += ox; lproj.m[13] += oy;
    lvp = lproj * lview;
    shadow_texel[c] = 2 * radius / SHADOW_RES;

    M4 bias = M4::identity();
    bias.m[0] = bias.m[5] = bias.m[10] = 0.5f;
    bias.m[12] = bias.m[13] = bias.m[14] = 0.5f;
    shadow_mats[c] = bias * lvp;

    glNamedFramebufferTextureLayer(shadow_fbo, GL_DEPTH_ATTACHMENT, shadow_tex, 0, c);
    glClear(GL_DEPTH_BUFFER_BIT);
    Frustum fr = frustum_from(lvp);

    set_frame_uniforms(prog_depth, lvp);
    instances.each([&](int, Instance& in) {
      if (!in.visible || !in.shadow) return;
      GrMaterial* m = gr_material_get(in.material);
      if (m && (m->transparent || m->unshaded)) return;
      if (!aabb_visible(fr, in.wmn, in.wmx)) return;
      bind_material(prog_depth, m, true);
      glDisable(GL_CULL_FACE);
      draw_instance(prog_depth, in, true);
    });
    set_frame_uniforms(prog_depth_inst, lvp);
    multimeshes.each([&](int, MultiMesh& mm) {
      if (!mm.visible || !mm.shadow) return;
      GrMaterial* m = gr_material_get(mm.material);
      if (m && (m->transparent || m->unshaded)) return;
      if (!aabb_visible(fr, mm.wmn, mm.wmx)) return;
      bind_material(prog_depth_inst, m, true);
      glDisable(GL_CULL_FACE);
      draw_multimesh(prog_depth_inst, mm, true);
    });
  }
  glDisable(GL_POLYGON_OFFSET_FILL);
}

static void set_light_uniforms(GLuint p) {
  struct L { float d; GrLight* l; };
  std::vector<L> ls;
  lights.each([&](int, GrLight*& l) {
    if (!l->enabled || l->energy <= 0) return;
    V3 lp(l->pos[0], l->pos[1], l->pos[2]);
    ls.push_back({length(lp - cam_pos) - l->range, l});
  });
  std::sort(ls.begin(), ls.end(), [](const L& a, const L& b) { return a.d < b.d; });
  int n = std::min((int)ls.size(), 32);
  float pos[32 * 4], col[32 * 4], dir[32 * 4], soft[32];
  for (int i = 0; i < n; i++) {
    GrLight* l = ls[i].l;
    pos[i * 4] = l->pos[0]; pos[i * 4 + 1] = l->pos[1]; pos[i * 4 + 2] = l->pos[2]; pos[i * 4 + 3] = l->range;
    lin3(l->color, &col[i * 4], l->energy);
    col[i * 4 + 3] = (float)l->type;
    dir[i * 4] = l->dir[0]; dir[i * 4 + 1] = l->dir[1]; dir[i * 4 + 2] = l->dir[2];
    dir[i * 4 + 3] = std::cos(l->spot_angle * 3.14159265f / 180.0f);
    soft[i] = l->spot_softness;
  }
  set1i(p, "u_num_lights", n);
  if (n) {
    glUniform4fv(U(p, "u_lpos"), n, pos);
    glUniform4fv(U(p, "u_lcol"), n, col);
    glUniform4fv(U(p, "u_ldir"), n, dir);
    glUniform1fv(U(p, "u_lsoft"), n, soft);
  }
  stats.lights = n;
}

static void set_shadow_uniforms(GLuint p) {
  set1i(p, "u_shadows_on", env.sun_shadows && env.sun_energy > 0);
  glUniformMatrix4fv(U(p, "u_shadow_mat"), CASCADES, GL_FALSE, shadow_mats[0].m);
  glUniform3fv(U(p, "u_shadow_splits"), 1, shadow_splits);
  glUniform3fv(U(p, "u_shadow_texel"), 1, shadow_texel);
  set1i(p, "u_shadow", 1);
  set1i(p, "u_albedo_tex", 0);
}

static void render_particles() {
  glUseProgram(prog_particles);
  set_frame_uniforms(prog_particles, viewproj);
  set1i(prog_particles, "u_tex", 0);
  glBindVertexArray(particle_vao);
  glEnable(GL_BLEND);
  glDepthMask(GL_FALSE);
  glDisable(GL_CULL_FACE);
  stats.particles = 0;
  particles.each([&](int, ParticleSys& s) {
    if (s.ps.empty()) return;
    GrParticleConfig& c = *s.cfg;
    particle_data.resize(s.ps.size() * 12);
    float* d = particle_data.data();
    for (auto& p : s.ps) {
      float t = p.age / p.life;
      float size = c.size_start + (c.size_end - c.size_start) * t;
      d[0] = p.p.x; d[1] = p.p.y; d[2] = p.p.z; d[3] = size;
      for (int k = 0; k < 4; k++) d[4 + k] = c.color_start[k] + (c.color_end[k] - c.color_start[k]) * t;
      // Fade in briefly to avoid popping.
      d[7] *= std::min(1.0f, p.age * 12.0f);
      d[8] = p.v.x; d[9] = p.v.y; d[10] = p.v.z; d[11] = p.rot;
      d += 12;
    }
    glNamedBufferData(particle_vbo, particle_data.size() * sizeof(float), particle_data.data(), GL_STREAM_DRAW);
    if (c.additive) glBlendFunc(GL_SRC_ALPHA, GL_ONE);
    else glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    set1f(prog_particles, "u_stretch", c.stretch);
    glBindTextureUnit(0, c.texture ? renderer_texture_gl(c.texture) : dot_tex);
    glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 4, (GLsizei)s.ps.size());
    stats.draw_calls++;
    stats.particles += (int)s.ps.size();
  });
  glDepthMask(GL_TRUE);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
}

static void render_bloom() {
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_BLEND);
  glBindVertexArray(empty_vao);
  glUseProgram(prog_down);
  set1i(prog_down, "u_src", 0);
  set1f(prog_down, "u_threshold", env.bloom_threshold);
  GLuint src = resolve_tex;
  int sw = fb_w, sh = fb_h;
  for (int i = 0; i < BLOOM_MIPS; i++) {
    glBindFramebuffer(GL_FRAMEBUFFER, bloom_fbo[i]);
    glViewport(0, 0, bloom_w[i], bloom_h[i]);
    set2f(prog_down, "u_src_texel", 1.0f / sw, 1.0f / sh);
    set1i(prog_down, "u_first", i == 0);
    glBindTextureUnit(0, src);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    src = bloom_tex[i]; sw = bloom_w[i]; sh = bloom_h[i];
  }
  glUseProgram(prog_up);
  set1i(prog_up, "u_src", 0);
  glEnable(GL_BLEND);
  glBlendFunc(GL_ONE, GL_ONE);
  for (int i = BLOOM_MIPS - 1; i > 0; i--) {
    glBindFramebuffer(GL_FRAMEBUFFER, bloom_fbo[i - 1]);
    glViewport(0, 0, bloom_w[i - 1], bloom_h[i - 1]);
    set2f(prog_up, "u_src_texel", 1.0f / bloom_w[i], 1.0f / bloom_h[i]);
    glBindTextureUnit(0, bloom_tex[i]);
    glDrawArrays(GL_TRIANGLES, 0, 3);
  }
  glDisable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
}

void renderer_render(int w, int h, float dt) {
  g_rtime += dt;
  vp_w = w; vp_h = h;
  ensure_targets(w, h);
  stats.draw_calls = stats.triangles = stats.instances = 0;

  view = m4_inverse(m4_trs(cam_pos, cam_rot, V3(1, 1, 1)));
  proj = m4_perspective(cam_fov * 3.14159265f / 180.0f, (float)w / h, cam_near, cam_far);
  viewproj = proj * view;
  inv_viewproj = m4_inverse(viewproj);
  Frustum fr = frustum_from(viewproj);

  update_particles(dt);
  multimeshes.each([](int id, MultiMesh& mm) { if (mm.dirty) gr_multimesh_commit(id, mm.visible_count); });
  if (env.sun_shadows && env.sun_energy > 0) render_shadows();

  // ---- main HDR pass
  glBindFramebuffer(GL_FRAMEBUFFER, msaa_fbo);
  glViewport(0, 0, w, h);
  float cc[4] = {lin(env.clear_color[0]), lin(env.clear_color[1]), lin(env.clear_color[2]), 1};
  glClearBufferfv(GL_COLOR, 0, cc);
  glClear(GL_DEPTH_BUFFER_BIT);
  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_LEQUAL);
  glDepthMask(GL_TRUE);
  glDisable(GL_BLEND);
  glEnable(GL_CULL_FACE);
  glCullFace(GL_BACK);
  glBindTextureUnit(1, shadow_tex);

  std::vector<DrawItem> opaque, transparent;
  instances.each([&](int id, Instance& in) {
    if (!in.visible || !meshes.get(in.mesh)) return;
    if (!aabb_visible(fr, in.wmn, in.wmx)) return;
    GrMaterial* m = gr_material_get(in.material);
    stats.instances++;
    if ((m && m->transparent) || in.tint[3] < 0.999f) {
      V3 c = (in.wmn + in.wmx) * 0.5f;
      transparent.push_back({0, id, length(c - cam_pos)});
    } else opaque.push_back({0, id, (float)in.material * 100000.0f + in.mesh});
  });
  multimeshes.each([&](int id, MultiMesh& mm) {
    if (!mm.visible || mm.visible_count == 0) return;
    if (!aabb_visible(fr, mm.wmn, mm.wmx)) return;
    GrMaterial* m = gr_material_get(mm.material);
    stats.instances += mm.visible_count;
    if (m && m->transparent) transparent.push_back({1, id, length((mm.wmn + mm.wmx) * 0.5f - cam_pos)});
    else opaque.push_back({1, id, 0});
  });
  std::sort(opaque.begin(), opaque.end(), [](const DrawItem& a, const DrawItem& b) { return a.dist < b.dist; });
  std::sort(transparent.begin(), transparent.end(), [](const DrawItem& a, const DrawItem& b) { return a.dist > b.dist; });

  auto draw_list = [&](std::vector<DrawItem>& list) {
    for (int pass = 0; pass < 2; pass++) {
      GLuint p = pass == 0 ? prog_main : prog_main_inst;
      set_frame_uniforms(p, viewproj);
      set_light_uniforms(p);
      set_shadow_uniforms(p);
      int last_mat = -1;
      for (auto& it : list) {
        if (it.kind != pass) continue;
        if (pass == 0) {
          Instance* in = instances.get(it.id);
          if (in->material != last_mat) { bind_material(p, gr_material_get(in->material), false); last_mat = in->material; }
          draw_instance(p, *in, false);
        } else {
          MultiMesh* mm = multimeshes.get(it.id);
          bind_material(p, gr_material_get(mm->material), false);
          draw_multimesh(p, *mm, false);
        }
      }
    }
  };
  draw_list(opaque);

  // Sky fills whatever the geometry did not cover.
  if (env.sky_enabled) {
    glUseProgram(prog_sky);
    set_frame_uniforms(prog_sky, viewproj);
    setm4(prog_sky, "u_inv_viewproj", inv_viewproj);
    glDepthMask(GL_FALSE);
    glDisable(GL_CULL_FACE);
    glBindVertexArray(empty_vao);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glDepthMask(GL_TRUE);
    stats.draw_calls++;
  }

  // Debug lines.
  if (!line_data.empty()) {
    glUseProgram(prog_lines);
    set_frame_uniforms(prog_lines, viewproj);
    glNamedBufferData(line_vbo, line_data.size() * sizeof(float), line_data.data(), GL_STREAM_DRAW);
    glBindVertexArray(line_vao);
    glDrawArrays(GL_LINES, 0, (GLsizei)(line_data.size() / 6));
    line_data.clear();
  }

  // Transparent geometry, back to front.
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
  glDepthMask(GL_FALSE);
  draw_list(transparent);
  glDepthMask(GL_TRUE);
  render_particles();
  glDisable(GL_BLEND);

  // Resolve MSAA, bloom, tonemap to the window.
  glBlitNamedFramebuffer(msaa_fbo, resolve_fbo, 0, 0, w, h, 0, 0, w, h, GL_COLOR_BUFFER_BIT, GL_NEAREST);
  render_bloom();

  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glViewport(0, 0, w, h);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_BLEND);
  glUseProgram(prog_composite);
  set1i(prog_composite, "u_src", 0);
  set1i(prog_composite, "u_bloom", 1);
  set1f(prog_composite, "u_exposure", env.exposure);
  set1f(prog_composite, "u_bloom_strength", env.bloom_strength);
  set1f(prog_composite, "u_saturation", env.saturation);
  set1f(prog_composite, "u_contrast", env.contrast);
  set1f(prog_composite, "u_vignette", env.vignette);
  set1f(prog_composite, "u_time", g_rtime);
  glBindTextureUnit(0, resolve_tex);
  glBindTextureUnit(1, bloom_tex[0]);
  glBindVertexArray(empty_vao);
  glDrawArrays(GL_TRIANGLES, 0, 3);
  glEnable(GL_DEPTH_TEST);
}

void renderer_capture(const char* path, int w, int h) {
  std::vector<unsigned char> px(w * h * 4), flipped(w * h * 4);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, 0);
  glReadBuffer(GL_BACK);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
  for (int y = 0; y < h; y++) memcpy(&flipped[y * w * 4], &px[(h - 1 - y) * w * 4], w * 4);
  for (int i = 0; i < w * h; i++) flipped[i * 4 + 3] = 255;
  stbi_write_png(path, w, h, 4, flipped.data(), w * 4);
}
