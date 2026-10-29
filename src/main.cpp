// Grove engine entry point: window, main loop, Lua host.
#include "core.hpp"
#include <GLFW/glfw3.h>
#include <chrono>
#include <filesystem>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <unistd.h>
#endif
#include <ctime>
#include <fstream>
#include <sstream>

extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

GLFWwindow* g_window = nullptr;
std::string g_engine_dir;
std::string g_game_dir;

static lua_State* L = nullptr;
static std::string g_error;
static bool g_quit = false, g_restart = false, g_fullscreen = false;
static double g_time = 0;
static std::vector<std::string> g_args;
static std::string g_pending_shot;
static int g_win_x = 100, g_win_y = 100, g_win_w = 1280, g_win_h = 720;

bool read_file(const std::string& path, std::string& out) {
  std::ifstream f(path, std::ios::binary);
  if (!f) return false;
  std::stringstream ss;
  ss << f.rdbuf();
  out = ss.str();
  return true;
}

// ------------------------------------------------------------- core API
extern "C" {
double gr_time(void) { return g_time; }
void gr_quit(void) { g_quit = true; }
void gr_restart(void) { g_restart = true; }
void gr_set_title(const char* t) { glfwSetWindowTitle(g_window, t); }
void gr_window_size(int* w, int* h) { glfwGetFramebufferSize(g_window, w, h); }
int gr_get_fullscreen(void) { return g_fullscreen; }
void gr_set_fullscreen(int on) {
  if (!!on == g_fullscreen) return;
  g_fullscreen = on;
  if (on) {
    glfwGetWindowPos(g_window, &g_win_x, &g_win_y);
    glfwGetWindowSize(g_window, &g_win_w, &g_win_h);
    GLFWmonitor* mon = glfwGetPrimaryMonitor();
    const GLFWvidmode* mode = glfwGetVideoMode(mon);
    glfwSetWindowMonitor(g_window, mon, 0, 0, mode->width, mode->height, mode->refreshRate);
  } else {
    glfwSetWindowMonitor(g_window, nullptr, g_win_x, g_win_y, g_win_w, g_win_h, 0);
  }
}
void gr_set_vsync(int on) { glfwSwapInterval(on ? 1 : 0); }
int gr_argc(void) { return (int)g_args.size(); }
const char* gr_argv(int i) { return (i >= 0 && i < (int)g_args.size()) ? g_args[i].c_str() : ""; }
void gr_screenshot(const char* path) { g_pending_shot = path; }
void gr_log(const char* msg) { fprintf(stdout, "%s\n", msg); fflush(stdout); }
}

// ------------------------------------------------------------- Lua host
static int traceback(lua_State* l) {
  const char* msg = lua_tostring(l, 1);
  luaL_traceback(l, l, msg ? msg : "(error object is not a string)", 1);
  return 1;
}

static void set_error(const char* what) {
  g_error = lua_tostring(L, -1) ? lua_tostring(L, -1) : "unknown error";
  fprintf(stderr, "\n[grove] %s:\n%s\n", what, g_error.c_str());
}

// Calls a global Lua function with an optional number argument.
static void lua_call_global(const char* name, bool with_arg, double arg) {
  lua_settop(L, 0);
  lua_pushcfunction(L, traceback);
  lua_getglobal(L, name);
  if (!lua_isfunction(L, -1)) { lua_settop(L, 0); return; }
  if (with_arg) lua_pushnumber(L, arg);
  if (lua_pcall(L, with_arg ? 1 : 0, 0, 1) != 0) set_error("script error");
  lua_settop(L, 0);
}

static void lua_start() {
  g_error.clear();
  L = luaL_newstate();
  luaL_openlibs(L);
  lua_pushstring(L, g_engine_dir.c_str()); lua_setglobal(L, "GROVE_ENGINE_DIR");
  lua_pushstring(L, g_game_dir.c_str()); lua_setglobal(L, "GROVE_GAME_DIR");
  lua_pushcfunction(L, traceback);
  std::string boot = g_engine_dir + "/lua/boot.lua";
  if (luaL_loadfile(L, boot.c_str()) != 0 || lua_pcall(L, 0, 0, 1) != 0) set_error("boot error");
  lua_settop(L, 0);
}

static void lua_stop() {
  if (L) { lua_close(L); L = nullptr; }
}

static void do_restart() {
  lua_stop();
  canvas_reset();
  renderer_reset();
  physics_reset();
  audio_reset();
  input_reset();
  g_time = 0;
  lua_start();
}

// ------------------------------------------------------------- main
namespace fs = std::filesystem;

// Paths are handed to Lua with forward slashes on every platform (Windows accepts them too).
static std::string slashes(std::string p) {
  for (char& c : p) if (c == '\\') c = '/';
  return p;
}

static std::string exe_dir() {
#ifdef _WIN32
  wchar_t buf[4096];
  DWORD n = GetModuleFileNameW(nullptr, buf, 4096);
  if (n == 0 || n >= 4096) return ".";
  return slashes(fs::path(buf).parent_path().u8string());
#else
  char buf[4096];
  ssize_t n = readlink("/proc/self/exe", buf, sizeof(buf) - 1);
  if (n <= 0) return ".";
  buf[n] = 0;
  std::string p(buf);
  return p.substr(0, p.find_last_of('/'));
#endif
}

static std::string abs_path(const std::string& p) {
  std::error_code ec;
  fs::path r = fs::weakly_canonical(fs::u8path(p), ec);
  return ec ? p : slashes(r.u8string());
}

static bool dir_exists(const std::string& p) {
  std::error_code ec;
  return fs::is_directory(fs::u8path(p), ec);
}

// With no game argument, run games/demo, or else the first game folder next to the engine
// (so a packaged build can be started by double-clicking the executable).
static std::string default_game() {
  std::string games = g_engine_dir + "/../games";
  if (dir_exists(games + "/demo")) return games + "/demo";
  std::error_code ec;
  for (auto& e : fs::directory_iterator(fs::u8path(games), ec))
    if (e.is_directory() && fs::exists(e.path() / "main.lua")) return slashes(e.path().u8string());
  return games + "/demo";
}

static std::string timestamp_shot_path() {
  std::error_code ec;
  fs::create_directories(fs::u8path(g_game_dir + "/screenshots"), ec);
  char name[256];
  time_t t = time(nullptr);
  strftime(name, sizeof(name), "/screenshots/shot_%Y%m%d_%H%M%S.png", localtime(&t));
  return g_game_dir + name;
}

int main(int argc, char** argv) {
  g_engine_dir = abs_path(exe_dir() + "/../engine");
  std::string game;
  int max_frames = 0, width = 1280, height = 720;
  bool hidden = false;
  std::string final_shot;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    g_args.push_back(a);
    if (a == "--frames" && i + 1 < argc) max_frames = atoi(argv[i + 1]);
    else if (a == "--shot" && i + 1 < argc) final_shot = argv[i + 1];
    else if (a == "--hidden") hidden = true;
    else if (a == "--size" && i + 1 < argc) sscanf(argv[i + 1], "%dx%d", &width, &height);
    else if (a[0] != '-' && game.empty() && dir_exists(a)) game = a;
  }
  if (game.empty()) game = default_game();
  g_game_dir = abs_path(game);
  printf("[grove] engine: %s\n[grove] game:   %s\n", g_engine_dir.c_str(), g_game_dir.c_str());

  if (!glfwInit()) { fprintf(stderr, "glfwInit failed\n"); return 1; }
  glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
  glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 5);
  glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
  glfwWindowHint(GLFW_OPENGL_FORWARD_COMPAT, GLFW_TRUE);
  if (hidden) glfwWindowHint(GLFW_VISIBLE, GLFW_FALSE);
  g_window = glfwCreateWindow(width, height, "Grove", nullptr, nullptr);
  if (!g_window) { fprintf(stderr, "Could not create an OpenGL 4.5 window\n"); return 1; }
  glfwMakeContextCurrent(g_window);
  if (!gladLoadGL((GLADloadfunc)glfwGetProcAddress)) { fprintf(stderr, "GL load failed\n"); return 1; }
  printf("[grove] GL: %s / %s\n", glGetString(GL_RENDERER), glGetString(GL_VERSION));
  glfwSwapInterval(max_frames ? 0 : 1);

  input_init(g_window);
  if (!renderer_init() || !canvas_init()) return 1;
  if (!physics_init()) return 1;
  if (!audio_init()) fprintf(stderr, "[grove] audio unavailable, continuing silently\n");

  lua_start();

  double last = glfwGetTime();
  int frame = 0;
  while (!glfwWindowShouldClose(g_window) && !g_quit) {
    glfwPollEvents();
    double now = glfwGetTime();
    float dt = (float)(now - last);
    last = now;
    if (max_frames) dt = 1.0f / 60.0f;  // deterministic stepping for automated runs
    if (dt > 0.1f) dt = 0.1f;
    g_time += dt;

    // Built-in developer keys.
    if (gr_key_pressed(GLFW_KEY_F5)) g_restart = true;
    if (gr_key_pressed(GLFW_KEY_F11)) gr_set_fullscreen(!g_fullscreen);
    if (gr_key_pressed(GLFW_KEY_F12)) g_pending_shot = timestamp_shot_path();

    int w, h;
    glfwGetFramebufferSize(g_window, &w, &h);
    if (w > 0 && h > 0) {
      auto t0 = std::chrono::high_resolution_clock::now();
      if (L && g_error.empty()) lua_call_global("grove_frame", true, dt);
      renderer_render(w, h, dt);
      if (L && g_error.empty()) lua_call_global("grove_draw_ui", false, 0);
      if (!g_error.empty()) canvas_draw_error(g_error, w, h);
      canvas_flush(w, h);
      auto t1 = std::chrono::high_resolution_clock::now();
      gr_stats()->frame_ms = std::chrono::duration<float, std::milli>(t1 - t0).count();

      frame++;
      if (!g_pending_shot.empty()) {
        renderer_capture(g_pending_shot.c_str(), w, h);
        printf("[grove] screenshot: %s\n", g_pending_shot.c_str());
        g_pending_shot.clear();
      }
      if (max_frames && frame >= max_frames) {
        if (!final_shot.empty()) {
          renderer_capture(final_shot.c_str(), w, h);
          printf("[grove] screenshot: %s\n", final_shot.c_str());
        }
        g_quit = true;
      }
    }
    glfwSwapBuffers(g_window);
    input_begin_frame();

    if (g_restart) { g_restart = false; do_restart(); }
  }
  int code = g_error.empty() ? 0 : 2;
  lua_stop();
  audio_shutdown();
  physics_shutdown();
  renderer_shutdown();
  glfwTerminate();
  return code;
}
