// Keyboard, mouse and gamepad state, with per-frame pressed/released edges.
#include "core.hpp"
#include <GLFW/glfw3.h>

static const int NKEYS = GLFW_KEY_LAST + 1;
static unsigned char key_cur[NKEYS], key_prev[NKEYS], key_sim[NKEYS];
static unsigned char mb_cur[8], mb_prev[8], mb_sim[8];
static double mx, my, last_mx, last_my;
static float dmx, dmy, wheel;
static bool have_last = false, captured = false;
static std::vector<unsigned> text_buf;
static GLFWgamepadstate pad_cur[4], pad_prev[4];
static bool pad_ok[4];

static void key_cb(GLFWwindow*, int key, int, int action, int) {
  if (key < 0 || key >= NKEYS) return;
  if (action == GLFW_PRESS) key_cur[key] = 1;
  else if (action == GLFW_RELEASE) key_cur[key] = 0;
}
static void mb_cb(GLFWwindow*, int b, int action, int) {
  if (b < 0 || b >= 8) return;
  mb_cur[b] = action == GLFW_PRESS;
}
static void cursor_cb(GLFWwindow*, double x, double y) {
  if (have_last) { dmx += (float)(x - last_mx); dmy += (float)(y - last_my); }
  last_mx = x; last_my = y; have_last = true;
  mx = x; my = y;
}
static void scroll_cb(GLFWwindow*, double, double y) { wheel += (float)y; }
static void char_cb(GLFWwindow*, unsigned c) { text_buf.push_back(c); }
static void focus_cb(GLFWwindow*, int focused) {
  if (!focused) memset(key_cur, 0, sizeof(key_cur));
}

static void poll_pads() {
  for (int i = 0; i < 4; i++) {
    pad_prev[i] = pad_cur[i];
    pad_ok[i] = glfwJoystickIsGamepad(GLFW_JOYSTICK_1 + i) && glfwGetGamepadState(GLFW_JOYSTICK_1 + i, &pad_cur[i]);
    if (!pad_ok[i]) memset(&pad_cur[i], 0, sizeof(pad_cur[i]));
  }
}

void input_init(GLFWwindow* w) {
  glfwSetKeyCallback(w, key_cb);
  glfwSetMouseButtonCallback(w, mb_cb);
  glfwSetCursorPosCallback(w, cursor_cb);
  glfwSetScrollCallback(w, scroll_cb);
  glfwSetCharCallback(w, char_cb);
  glfwSetWindowFocusCallback(w, focus_cb);
  if (glfwRawMouseMotionSupported()) glfwSetInputMode(w, GLFW_RAW_MOUSE_MOTION, GLFW_TRUE);
  input_reset();
}

void input_begin_frame() {
  memcpy(key_prev, key_cur, sizeof(key_cur));
  memcpy(mb_prev, mb_cur, sizeof(mb_cur));
  for (int i = 0; i < NKEYS; i++) key_sim[i] &= 1;  // drop the "new this frame" bit
  for (int i = 0; i < 8; i++) mb_sim[i] &= 1;
  dmx = dmy = wheel = 0;
  text_buf.clear();
  poll_pads();
}

void input_reset() {
  memset(key_sim, 0, sizeof(key_sim));
  memset(mb_sim, 0, sizeof(mb_sim));
  gr_set_mouse_captured(0);
  poll_pads();
}

// Simulated input keeps bit0 = held, bit1 = went down this frame.
static int sim_down(unsigned char s) { return s & 1; }
static int sim_edge(unsigned char s) { return (s & 3) == 3; }

extern "C" {
int gr_key_down(int k) { return k >= 0 && k < NKEYS && (key_cur[k] || sim_down(key_sim[k])); }
int gr_key_pressed(int k) { return k >= 0 && k < NKEYS && ((key_cur[k] && !key_prev[k]) || sim_edge(key_sim[k])); }
int gr_key_released(int k) { return k >= 0 && k < NKEYS && !key_cur[k] && key_prev[k]; }
int gr_mouse_down(int b) { return b >= 0 && b < 8 && (mb_cur[b] || sim_down(mb_sim[b])); }
int gr_mouse_pressed(int b) { return b >= 0 && b < 8 && ((mb_cur[b] && !mb_prev[b]) || sim_edge(mb_sim[b])); }
int gr_mouse_released(int b) { return b >= 0 && b < 8 && !mb_cur[b] && mb_prev[b]; }
void gr_mouse_pos(float* x, float* y) {
  // Report in framebuffer pixels so UI coordinates match rendering on HiDPI.
  int ww, wh, fw, fh;
  glfwGetWindowSize(g_window, &ww, &wh);
  glfwGetFramebufferSize(g_window, &fw, &fh);
  float sx = ww ? (float)fw / ww : 1, sy = wh ? (float)fh / wh : 1;
  *x = (float)mx * sx; *y = (float)my * sy;
}
void gr_mouse_delta(float* x, float* y) { *x = dmx; *y = dmy; }
float gr_mouse_wheel(void) { return wheel; }
void gr_set_mouse_captured(int on) {
  captured = on;
  glfwSetInputMode(g_window, GLFW_CURSOR, on ? GLFW_CURSOR_DISABLED : GLFW_CURSOR_NORMAL);
  have_last = false;
}
int gr_get_mouse_captured(void) { return captured; }
int gr_gamepad_connected(int p) { return p >= 0 && p < 4 && pad_ok[p]; }
float gr_gamepad_axis(int p, int a) { return (p >= 0 && p < 4 && a >= 0 && a <= GLFW_GAMEPAD_AXIS_LAST) ? pad_cur[p].axes[a] : 0; }
int gr_gamepad_button(int p, int b) { return (p >= 0 && p < 4 && b >= 0 && b <= GLFW_GAMEPAD_BUTTON_LAST) ? pad_cur[p].buttons[b] : 0; }
int gr_gamepad_pressed(int p, int b) {
  return (p >= 0 && p < 4 && b >= 0 && b <= GLFW_GAMEPAD_BUTTON_LAST) ? (pad_cur[p].buttons[b] && !pad_prev[p].buttons[b]) : 0;
}
int gr_text_input(unsigned* out, int max) {
  int n = 0;
  for (unsigned c : text_buf) { if (n >= max) break; out[n++] = c; }
  return n;
}
void gr_sim_key(int k, int down) {
  if (k < 0 || k >= NKEYS) return;
  key_sim[k] = down ? (sim_down(key_sim[k]) ? 1 : 3) : 0;
}
void gr_sim_mouse_button(int b, int down) {
  if (b < 0 || b >= 8) return;
  mb_sim[b] = down ? (sim_down(mb_sim[b]) ? 1 : 3) : 0;
}
}
