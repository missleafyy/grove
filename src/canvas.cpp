#include <cmath>
// 2D canvas: batched rounded rects, images and SDF text drawn over the 3D frame.
#include "core.hpp"
#include "stb_truetype.h"
#include <unordered_map>

struct Glyph { float u0, v0, u1, v1, xoff, yoff, w, h, advance; };
struct Font {
  GLuint tex = 0;
  std::unordered_map<unsigned, Glyph> glyphs;
  float ascent = 0, line_h = 0;
  std::string data;
  stbtt_fontinfo info;
};

static const float BASE = 48.0f;   // SDF bake size in pixels
static const int PAD = 6, ATLAS = 1024;
static std::vector<Font*> fonts(1, nullptr);
static int builtin_fonts = 0;
static GLuint prog, vao, vbo, white;
static std::vector<float> verts;
static GLuint cur_tex = 0;
static int scr_w = 1, scr_h = 1;

static Font* load_font(const char* path) {
  Font* f = new Font();
  if (!read_file(path, f->data) || !stbtt_InitFont(&f->info, (const unsigned char*)f->data.data(), 0)) {
    fprintf(stderr, "[grove] could not load font %s\n", path);
    delete f;
    return nullptr;
  }
  float scale = stbtt_ScaleForPixelHeight(&f->info, BASE);
  int asc, desc, gap;
  stbtt_GetFontVMetrics(&f->info, &asc, &desc, &gap);
  f->ascent = asc * scale;
  f->line_h = (asc - desc + gap) * scale;

  std::vector<unsigned> cps;
  for (unsigned c = 32; c < 127; c++) cps.push_back(c);
  for (unsigned c = 160; c < 256; c++) cps.push_back(c);
  unsigned extra[] = {0x2022, 0x2026, 0x2013, 0x2014, 0x2190, 0x2191, 0x2192, 0x2193, 0x2018, 0x2019, 0x201C, 0x201D, 0x2665, 0x2605, 0x2606};
  for (unsigned c : extra) cps.push_back(c);

  std::vector<unsigned char> atlas(ATLAS * ATLAS, 0);
  int x = 1, y = 1, row_h = 0;
  float pixel_dist = 128.0f / PAD;
  for (unsigned cp : cps) {
    int gi = stbtt_FindGlyphIndex(&f->info, cp);
    if (cp != 32 && gi == 0) continue;
    int adv, lsb;
    stbtt_GetGlyphHMetrics(&f->info, gi, &adv, &lsb);
    int w = 0, h = 0, xo = 0, yo = 0;
    unsigned char* sdf = stbtt_GetGlyphSDF(&f->info, scale, gi, PAD, 128, pixel_dist, &w, &h, &xo, &yo);
    Glyph g{};
    g.advance = adv * scale;
    if (sdf) {
      if (x + w + 1 >= ATLAS) { x = 1; y += row_h + 1; row_h = 0; }
      if (y + h + 1 < ATLAS) {
        for (int r = 0; r < h; r++) memcpy(&atlas[(y + r) * ATLAS + x], &sdf[r * w], w);
        g.u0 = (float)x / ATLAS; g.v0 = (float)y / ATLAS;
        g.u1 = (float)(x + w) / ATLAS; g.v1 = (float)(y + h) / ATLAS;
        g.xoff = (float)xo; g.yoff = (float)yo; g.w = (float)w; g.h = (float)h;
        x += w + 1;
        row_h = std::max(row_h, h);
      }
      stbtt_FreeSDF(sdf, nullptr);
    }
    f->glyphs[cp] = g;
  }
  glCreateTextures(GL_TEXTURE_2D, 1, &f->tex);
  glTextureStorage2D(f->tex, 1, GL_R8, ATLAS, ATLAS);
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
  glTextureSubImage2D(f->tex, 0, 0, 0, ATLAS, ATLAS, GL_RED, GL_UNSIGNED_BYTE, atlas.data());
  glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
  glTextureParameteri(f->tex, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTextureParameteri(f->tex, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTextureParameteri(f->tex, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTextureParameteri(f->tex, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  return f;
}

bool canvas_init() {
  prog = compile_program("canvas.glsl", "");
  glCreateVertexArrays(1, &vao);
  glCreateBuffers(1, &vbo);
  glVertexArrayVertexBuffer(vao, 0, vbo, 0, 24 * sizeof(float));
  int sizes[6] = {2, 2, 4, 4, 4, 4}, off = 0;
  for (int i = 0; i < 6; i++) {
    glEnableVertexArrayAttrib(vao, i);
    glVertexArrayAttribFormat(vao, i, sizes[i], GL_FLOAT, GL_FALSE, off * sizeof(float));
    glVertexArrayAttribBinding(vao, i, 0);
    off += sizes[i];
  }
  unsigned char px[4] = {255, 255, 255, 255};
  glCreateTextures(GL_TEXTURE_2D, 1, &white);
  glTextureStorage2D(white, 1, GL_RGBA8, 1, 1);
  glTextureSubImage2D(white, 0, 0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
  gr_font_load((g_engine_dir + "/fonts/NotoSans-Regular.ttf").c_str());
  gr_font_load((g_engine_dir + "/fonts/NotoSans-Bold.ttf").c_str());
  builtin_fonts = (int)fonts.size();
  return prog != 0;
}

void canvas_reset() {
  for (size_t i = builtin_fonts; i < fonts.size(); i++)
    if (fonts[i]) { glDeleteTextures(1, &fonts[i]->tex); delete fonts[i]; }
  fonts.resize(builtin_fonts);
  verts.clear();
}

static void flush_batch() {
  if (verts.empty()) return;
  glNamedBufferData(vbo, verts.size() * sizeof(float), verts.data(), GL_STREAM_DRAW);
  glBindTextureUnit(0, cur_tex ? cur_tex : white);
  glDrawArrays(GL_TRIANGLES, 0, (GLsizei)(verts.size() / 24));
  verts.clear();
}

// Batches are flushed lazily at the end of the frame; texture switches split them.
struct Cmd { GLuint tex; size_t start, end; };
static std::vector<Cmd> cmds;

static void use_tex(GLuint t) {
  if (cmds.empty() || cmds.back().tex != t) {
    if (!cmds.empty()) cmds.back().end = verts.size();
    cmds.push_back({t, verts.size(), verts.size()});
  }
}

static void vtx(float x, float y, float u, float v, const float* c, const float* rect, const float* params, const float* c2) {
  float d[24] = {x, y, u, v, c[0], c[1], c[2], c[3], rect[0], rect[1], rect[2], rect[3],
                 params[0], params[1], params[2], params[3], c2[0], c2[1], c2[2], c2[3], 0, 0, 0, 0};
  verts.insert(verts.end(), d, d + 24);
}

// Emits a quad. Corner colours: top pair c_top, bottom pair c_bot.
static void quad(float x, float y, float w, float h, float u0, float v0, float u1, float v1,
                 const float* c_top, const float* c_bot, float mode, float radius, float p2, float p3,
                 const float* c2, float hw, float hh, float pad) {
  static const float zero[4] = {0, 0, 0, 0};
  if (!c2) c2 = zero;
  float params[4] = {mode, radius, p2, p3};
  float x0 = x - pad, y0 = y - pad, x1 = x + w + pad, y1 = y + h + pad;
  float cx = x + w * 0.5f, cy = y + h * 0.5f;
  float r00[4] = {x0 - cx, y0 - cy, hw, hh}, r10[4] = {x1 - cx, y0 - cy, hw, hh};
  float r01[4] = {x0 - cx, y1 - cy, hw, hh}, r11[4] = {x1 - cx, y1 - cy, hw, hh};
  vtx(x0, y0, u0, v0, c_top, r00, params, c2);
  vtx(x1, y0, u1, v0, c_top, r10, params, c2);
  vtx(x1, y1, u1, v1, c_bot, r11, params, c2);
  vtx(x0, y0, u0, v0, c_top, r00, params, c2);
  vtx(x1, y1, u1, v1, c_bot, r11, params, c2);
  vtx(x0, y1, u0, v1, c_bot, r01, params, c2);
}

static unsigned next_cp(const char*& s) {
  unsigned char c = (unsigned char)*s++;
  if (c < 0x80) return c;
  int n = (c >= 0xF0) ? 3 : (c >= 0xE0) ? 2 : (c >= 0xC0) ? 1 : 0;
  unsigned cp = c & (0x3F >> n);
  for (int i = 0; i < n && *s; i++) cp = (cp << 6) | ((unsigned char)*s++ & 0x3F);
  return cp;
}

extern "C" {

int gr_font_load(const char* path) {
  Font* f = load_font(path);
  if (!f) return 0;
  fonts.push_back(f);
  return (int)fonts.size() - 1;
}

static Font* font_get(int id) {
  if (id <= 0 || id >= (int)fonts.size() || !fonts[id]) id = 1;
  return id < (int)fonts.size() ? fonts[id] : nullptr;
}

float gr_text_width(int font, const char* text, float size) {
  Font* f = font_get(font);
  if (!f) return 0;
  float s = size / BASE, w = 0, best = 0;
  while (*text) {
    unsigned cp = next_cp(text);
    if (cp == '\n') { best = std::max(best, w); w = 0; continue; }
    auto it = f->glyphs.find(cp);
    if (it == f->glyphs.end()) it = f->glyphs.find('?');
    if (it != f->glyphs.end()) w += it->second.advance * s;
  }
  return std::max(best, w);
}

void gr_draw_rect(float x, float y, float w, float h, float r, float g, float b, float a, float radius) {
  use_tex(white);
  float c[4] = {r, g, b, a};
  radius = std::min(radius, std::min(w, h) * 0.5f);
  quad(x, y, w, h, 0, 0, 1, 1, c, c, 0, radius, 0, 0, nullptr, w * 0.5f, h * 0.5f, 1);
}

void gr_draw_rect_border(float x, float y, float w, float h, float r, float g, float b, float a, float radius, float t) {
  use_tex(white);
  float c[4] = {r, g, b, a};
  radius = std::min(radius, std::min(w, h) * 0.5f);
  quad(x, y, w, h, 0, 0, 1, 1, c, c, 1, radius, t, 0, nullptr, w * 0.5f, h * 0.5f, 1);
}

void gr_draw_rect_gradient(float x, float y, float w, float h, float r1, float g1, float b1, float a1,
                           float r2, float g2, float b2, float a2, float radius) {
  use_tex(white);
  float c1[4] = {r1, g1, b1, a1}, c2[4] = {r2, g2, b2, a2};
  radius = std::min(radius, std::min(w, h) * 0.5f);
  quad(x, y, w, h, 0, 0, 1, 1, c1, c2, 0, radius, 0, 0, nullptr, w * 0.5f, h * 0.5f, 0);
}

void gr_draw_shadow(float x, float y, float w, float h, float radius, float blur, float a) {
  use_tex(white);
  float c[4] = {0, 0, 0, a};
  quad(x, y, w, h, 0, 0, 1, 1, c, c, 4, radius, 0, blur, nullptr, w * 0.5f, h * 0.5f, blur * 2);
}

GLuint renderer_texture_gl(int id);

void gr_draw_image(int tex, float x, float y, float w, float h, float u0, float v0, float u1, float v1,
                   float r, float g, float b, float a) {
  use_tex(renderer_texture_gl(tex));
  float c[4] = {r, g, b, a};
  quad(x, y, w, h, u0, v0, u1, v1, c, c, 2, 0, 0, 0, nullptr, w * 0.5f, h * 0.5f, 0);
}

void gr_draw_text(int font, const char* text, float x, float y, float size, float r, float g, float b, float a,
                  float outline, float orr, float og, float ob, float oa) {
  Font* f = font_get(font);
  if (!f) return;
  use_tex(f->tex);
  float s = size / BASE;
  float c[4] = {r, g, b, a}, c2[4] = {orr, og, ob, oa};
  // outline is given in pixels at the drawn size; convert to SDF units (0.5 = edge).
  float ow = outline > 0 ? std::min(0.45f, outline / s / (PAD * 2.0f)) : 0;
  float pen_x = x, pen_y = y + f->ascent * s;
  unsigned prev = 0;
  while (*text) {
    unsigned cp = next_cp(text);
    if (cp == '\n') { pen_x = x; pen_y += f->line_h * s; prev = 0; continue; }
    auto it = f->glyphs.find(cp);
    if (it == f->glyphs.end()) it = f->glyphs.find('?');
    if (it == f->glyphs.end()) continue;
    if (prev) pen_x += stbtt_GetCodepointKernAdvance(&f->info, prev, cp) * stbtt_ScaleForPixelHeight(&f->info, BASE) * s;
    const Glyph& gl = it->second;
    if (gl.w > 0) {
      quad(pen_x + gl.xoff * s, pen_y + gl.yoff * s, gl.w * s, gl.h * s, gl.u0, gl.v0, gl.u1, gl.v1,
           c, c, 3, 0, ow, 0, c2, 0, 0, 0);
    }
    pen_x += gl.advance * s;
    prev = cp;
  }
}

// Convex polygon (screen-space points, either winding) with a feathered ~1px anti-aliased edge.
void gr_draw_poly(const float* pts, int n, float r, float g, float b, float a) {
  if (n < 3) return;
  use_tex(white);
  static const float zero[4] = {0, 0, 0, 0};
  float c[4] = {r, g, b, a}, c0[4] = {r, g, b, 0};
  float params[4] = {2, 0, 0, 0};
  float area = 0;
  for (int i = 0; i < n; i++) {
    int j = (i + 1) % n;
    area += pts[i * 2] * pts[j * 2 + 1] - pts[j * 2] * pts[i * 2 + 1];
  }
  float wind = area > 0 ? 1.0f : -1.0f;
  // Offset each vertex half a pixel in and out along the averaged edge normals.
  std::vector<float> in(n * 2), out(n * 2);
  for (int i = 0; i < n; i++) {
    int ip = (i + n - 1) % n, in_ = (i + 1) % n;
    float ex0 = pts[i * 2] - pts[ip * 2], ey0 = pts[i * 2 + 1] - pts[ip * 2 + 1];
    float ex1 = pts[in_ * 2] - pts[i * 2], ey1 = pts[in_ * 2 + 1] - pts[i * 2 + 1];
    float l0 = std::sqrt(ex0 * ex0 + ey0 * ey0) + 1e-6f, l1 = std::sqrt(ex1 * ex1 + ey1 * ey1) + 1e-6f;
    // outward normal for CCW in y-down screen space
    float nx0 = ey0 / l0 * wind, ny0 = -ex0 / l0 * wind, nx1 = ey1 / l1 * wind, ny1 = -ex1 / l1 * wind;
    float nx = nx0 + nx1, ny = ny0 + ny1;
    float nl = std::sqrt(nx * nx + ny * ny) + 1e-6f;
    nx /= nl; ny /= nl;
    float k = 0.5f / std::max(0.3f, nx * nx0 + ny * ny0);   // keep the feather 1px wide at corners
    nx *= k; ny *= k;
    in[i * 2] = pts[i * 2] - nx; in[i * 2 + 1] = pts[i * 2 + 1] - ny;
    out[i * 2] = pts[i * 2] + nx; out[i * 2 + 1] = pts[i * 2 + 1] + ny;
  }
  for (int i = 1; i + 1 < n; i++) {
    vtx(in[0], in[1], 0.5f, 0.5f, c, zero, params, zero);
    vtx(in[i * 2], in[i * 2 + 1], 0.5f, 0.5f, c, zero, params, zero);
    vtx(in[(i + 1) * 2], in[(i + 1) * 2 + 1], 0.5f, 0.5f, c, zero, params, zero);
  }
  for (int i = 0; i < n; i++) {
    int j = (i + 1) % n;
    vtx(in[i * 2], in[i * 2 + 1], 0.5f, 0.5f, c, zero, params, zero);
    vtx(out[i * 2], out[i * 2 + 1], 0.5f, 0.5f, c0, zero, params, zero);
    vtx(out[j * 2], out[j * 2 + 1], 0.5f, 0.5f, c0, zero, params, zero);
    vtx(in[i * 2], in[i * 2 + 1], 0.5f, 0.5f, c, zero, params, zero);
    vtx(out[j * 2], out[j * 2 + 1], 0.5f, 0.5f, c0, zero, params, zero);
    vtx(in[j * 2], in[j * 2 + 1], 0.5f, 0.5f, c, zero, params, zero);
  }
}

}  // extern "C"

void canvas_draw_error(const std::string& msg, int w, int h) {
  gr_draw_rect(0, 0, (float)w, (float)h, 0.05f, 0.03f, 0.04f, 0.88f, 0);
  gr_draw_rect(0, 0, (float)w, 54, 0.75f, 0.16f, 0.22f, 1, 0);
  gr_draw_text(2, "Script error  -  fix the code and press F5 to restart", 20, 12, 24, 1, 1, 1, 1, 0, 0, 0, 0, 0);
  std::string m = msg;
  // Keep it to what fits on screen.
  float y = 74;
  size_t pos = 0;
  while (pos < m.size() && y < h - 20) {
    size_t nl = m.find('\n', pos);
    std::string line = m.substr(pos, nl == std::string::npos ? std::string::npos : nl - pos);
    for (auto& ch : line) if (ch == '\t') ch = ' ';
    gr_draw_text(1, line.c_str(), 20, y, 17, 1, 0.85f, 0.85f, 1, 0, 0, 0, 0, 0);
    y += 23;
    if (nl == std::string::npos) break;
    pos = nl + 1;
  }
}

void canvas_flush(int w, int h) {
  scr_w = w; scr_h = h;
  if (!cmds.empty()) cmds.back().end = verts.size();
  if (verts.empty()) { cmds.clear(); return; }
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  glViewport(0, 0, w, h);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);
  glEnable(GL_BLEND);
  glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
  glUseProgram(prog);
  glUniform2f(glGetUniformLocation(prog, "u_screen"), (float)w, (float)h);
  glUniform1i(glGetUniformLocation(prog, "u_tex"), 0);
  glBindVertexArray(vao);
  glNamedBufferData(vbo, verts.size() * sizeof(float), verts.data(), GL_STREAM_DRAW);
  for (auto& c : cmds) {
    if (c.end <= c.start) continue;
    glBindTextureUnit(0, c.tex);
    glDrawArrays(GL_TRIANGLES, (GLint)(c.start / 24), (GLsizei)((c.end - c.start) / 24));
    gr_stats()->draw_calls++;
  }
  verts.clear();
  cmds.clear();
  glDisable(GL_BLEND);
  glEnable(GL_DEPTH_TEST);
}
