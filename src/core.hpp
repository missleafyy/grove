// Shared engine internals: math, handle pools, module entry points.
#pragma once
#include <glad/gl.h>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

extern "C" {
#include "../engine/api.h"
}

struct GLFWwindow;
extern GLFWwindow* g_window;
extern std::string g_engine_dir;
extern std::string g_game_dir;

bool read_file(const std::string& path, std::string& out);

// ---------------------------------------------------------------- math
struct V3 {
  float x = 0, y = 0, z = 0;
  V3() {}
  V3(float x, float y, float z) : x(x), y(y), z(z) {}
  V3 operator+(V3 o) const { return {x + o.x, y + o.y, z + o.z}; }
  V3 operator-(V3 o) const { return {x - o.x, y - o.y, z - o.z}; }
  V3 operator*(float s) const { return {x * s, y * s, z * s}; }
  V3 operator-() const { return {-x, -y, -z}; }
};
inline float dot(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline V3 cross(V3 a, V3 b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
inline float length(V3 a) { return std::sqrt(dot(a, a)); }
inline V3 normalize(V3 a) { float l = length(a); return l > 1e-8f ? a * (1.0f / l) : V3(0, 1, 0); }

struct Q4 { float x = 0, y = 0, z = 0, w = 1; };
inline V3 qrot(Q4 q, V3 v) {
  V3 u(q.x, q.y, q.z);
  V3 t = cross(u, v) * 2.0f;
  return v + t * q.w + cross(u, t);
}

// Column-major 4x4 matrix, OpenGL convention.
struct M4 {
  float m[16];
  static M4 identity() { M4 r{}; r.m[0] = r.m[5] = r.m[10] = r.m[15] = 1; return r; }
  float& operator()(int row, int col) { return m[col * 4 + row]; }
  float operator()(int row, int col) const { return m[col * 4 + row]; }
  M4 operator*(const M4& b) const {
    M4 r{};
    for (int c = 0; c < 4; c++)
      for (int rr = 0; rr < 4; rr++) {
        float s = 0;
        for (int k = 0; k < 4; k++) s += (*this)(rr, k) * b(k, c);
        r(rr, c) = s;
      }
    return r;
  }
  V3 point(V3 p) const {
    return {m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12], m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13],
            m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14]};
  }
};

inline M4 m4_trs(V3 p, Q4 q, V3 s) {
  float xx = q.x * q.x, yy = q.y * q.y, zz = q.z * q.z;
  float xy = q.x * q.y, xz = q.x * q.z, yz = q.y * q.z;
  float wx = q.w * q.x, wy = q.w * q.y, wz = q.w * q.z;
  M4 r{};
  r.m[0] = (1 - 2 * (yy + zz)) * s.x; r.m[1] = 2 * (xy + wz) * s.x;       r.m[2] = 2 * (xz - wy) * s.x;
  r.m[4] = 2 * (xy - wz) * s.y;       r.m[5] = (1 - 2 * (xx + zz)) * s.y; r.m[6] = 2 * (yz + wx) * s.y;
  r.m[8] = 2 * (xz + wy) * s.z;       r.m[9] = 2 * (yz - wx) * s.z;       r.m[10] = (1 - 2 * (xx + yy)) * s.z;
  r.m[12] = p.x; r.m[13] = p.y; r.m[14] = p.z; r.m[15] = 1;
  return r;
}

inline M4 m4_perspective(float fovy_rad, float aspect, float n, float f) {
  float t = 1.0f / std::tan(fovy_rad * 0.5f);
  M4 r{};
  r.m[0] = t / aspect; r.m[5] = t;
  r.m[10] = (f + n) / (n - f); r.m[11] = -1;
  r.m[14] = 2 * f * n / (n - f);
  return r;
}

inline M4 m4_ortho(float l, float r_, float b, float t, float n, float f) {
  M4 r = M4::identity();
  r.m[0] = 2 / (r_ - l); r.m[5] = 2 / (t - b); r.m[10] = -2 / (f - n);
  r.m[12] = -(r_ + l) / (r_ - l); r.m[13] = -(t + b) / (t - b); r.m[14] = -(f + n) / (f - n);
  return r;
}

inline M4 m4_look_at(V3 eye, V3 target, V3 up) {
  V3 f = normalize(target - eye);
  V3 s = normalize(cross(f, up));
  V3 u = cross(s, f);
  M4 r = M4::identity();
  r.m[0] = s.x; r.m[4] = s.y; r.m[8] = s.z;
  r.m[1] = u.x; r.m[5] = u.y; r.m[9] = u.z;
  r.m[2] = -f.x; r.m[6] = -f.y; r.m[10] = -f.z;
  r.m[12] = -dot(s, eye); r.m[13] = -dot(u, eye); r.m[14] = dot(f, eye);
  return r;
}

M4 m4_inverse(const M4& m);

// ---------------------------------------------------------------- pools
// Stable integer handles starting at 1; 0 always means "none".
template <class T>
struct Pool {
  std::vector<T> items;
  std::vector<char> alive;
  std::vector<int> free_ids;
  int add(const T& v) {
    int id;
    if (!free_ids.empty()) { id = free_ids.back(); free_ids.pop_back(); items[id] = v; alive[id] = 1; }
    else { if (items.empty()) { items.emplace_back(); alive.push_back(0); }
           id = (int)items.size(); items.push_back(v); alive.push_back(1); }
    return id;
  }
  T* get(int id) { return (id > 0 && id < (int)items.size() && alive[id]) ? &items[id] : nullptr; }
  void remove(int id) { if (get(id)) { alive[id] = 0; items[id] = T(); free_ids.push_back(id); } }
  template <class F> void each(F f) { for (int i = 1; i < (int)items.size(); i++) if (alive[i]) f(i, items[i]); }
  void clear() { items.clear(); alive.clear(); free_ids.clear(); }
};

// ---------------------------------------------------------------- modules
GLuint compile_program(const std::string& file, const std::string& defines);

bool renderer_init();
void renderer_render(int w, int h, float dt);
void renderer_reset();
void renderer_shutdown();
void renderer_capture(const char* path, int w, int h);

bool canvas_init();
void canvas_flush(int w, int h);
void canvas_reset();
void canvas_draw_error(const std::string& msg, int w, int h);

bool physics_init();
void physics_reset();
void physics_shutdown();

bool audio_init();
void audio_reset();
void audio_shutdown();

void input_init(GLFWwindow* w);
void input_begin_frame();
void input_reset();

bool meshload(const char* path, std::vector<std::vector<GrVertex>>& parts_v, std::vector<std::vector<unsigned>>& parts_i,
              std::vector<GrMaterial>& mats, std::vector<std::string>& tex_paths);
