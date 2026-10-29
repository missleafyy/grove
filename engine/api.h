/* Grove engine C API.
   This file is read by both the C++ engine and LuaJIT's ffi.cdef, so it must
   stay plain C declarations: no #include, #define, or other preprocessor lines. */

/* ---------------------------------------------------------------- core */
double gr_time(void);
void   gr_quit(void);
void   gr_restart(void);
void   gr_set_title(const char* title);
void   gr_window_size(int* w, int* h);
void   gr_set_fullscreen(int on);
int    gr_get_fullscreen(void);
void   gr_set_vsync(int on);
int    gr_argc(void);
const char* gr_argv(int i);
void   gr_screenshot(const char* path);
void   gr_log(const char* msg);

/* --------------------------------------------------------------- input */
int    gr_key_down(int key);
int    gr_key_pressed(int key);
int    gr_key_released(int key);
int    gr_mouse_down(int button);
int    gr_mouse_pressed(int button);
int    gr_mouse_released(int button);
void   gr_mouse_pos(float* x, float* y);
void   gr_mouse_delta(float* x, float* y);
float  gr_mouse_wheel(void);
void   gr_set_mouse_captured(int on);
int    gr_get_mouse_captured(void);
int    gr_gamepad_connected(int pad);
float  gr_gamepad_axis(int pad, int axis);
int    gr_gamepad_button(int pad, int button);
int    gr_gamepad_pressed(int pad, int button);
int    gr_text_input(unsigned int* out, int max);
void   gr_sim_key(int key, int down);
void   gr_sim_mouse_button(int button, int down);

/* ------------------------------------------------------------ renderer */
typedef struct GrVertex {
  float px, py, pz;
  float nx, ny, nz;
  float u, v;
  float r, g, b, a;
} GrVertex;

typedef struct GrMaterial {
  float albedo[4];
  float emission[3];
  float emission_energy;
  float roughness;
  float metallic;
  float rim;              /* fresnel rim light strength */
  float uv_scale[2];
  float alpha_cutoff;     /* > 0 enables alpha-tested cutout */
  float wind;             /* vertex sway strength (foliage) */
  int   albedo_tex;       /* 0 = none */
  int   unshaded;
  int   transparent;
  int   double_sided;
  int   vertex_color;     /* multiply albedo by vertex colour */
  int   effect;           /* 0 standard, 1 water, 2 hologram/pulse */
  int   triplanar;        /* world-space triplanar mapping of albedo_tex */
  int   no_fog;
} GrMaterial;

typedef struct GrLight {
  int   type;             /* 0 omni, 1 spot */
  int   enabled;
  float color[3];
  float energy;
  float pos[3];
  float dir[3];
  float range;
  float spot_angle;       /* degrees, half-angle */
  float spot_softness;
} GrLight;

typedef struct GrEnvironment {
  float sky_top[3];
  float sky_horizon[3];
  float ground[3];
  float sun_dir[3];       /* direction light travels (points away from sun) */
  float sun_color[3];
  float sun_energy;
  float sun_size;
  int   sun_shadows;
  float shadow_distance;
  float ambient_energy;
  float reflection_energy;
  float fog_color[3];
  float fog_density;
  float fog_height;
  float fog_height_density;
  float fog_sun_scatter;
  float clouds;           /* 0..1 coverage */
  float cloud_speed;
  float stars;            /* 0..1 visibility */
  float moon_dir[3];
  float exposure;
  float bloom_strength;
  float bloom_threshold;
  float saturation;
  float contrast;
  float vignette;
  float clear_color[3];
  int   sky_enabled;
} GrEnvironment;

typedef struct GrParticleConfig {
  int   emitting;
  int   additive;
  int   texture;          /* 0 = built-in soft dot */
  int   world_space;
  float rate;             /* particles per second */
  float lifetime;
  float lifetime_random;
  float pos[3];
  float emit_box[3];      /* half extents */
  float emit_radius;
  float dir[3];
  float spread;           /* degrees */
  float speed;
  float speed_random;
  float gravity[3];
  float damping;
  float color_start[4];
  float color_end[4];
  float size_start;
  float size_end;
  float turbulence;
  float stretch;          /* velocity stretching */
} GrParticleConfig;

typedef struct GrStats {
  int draw_calls;
  int triangles;
  int instances;
  int lights;
  int particles;
  float frame_ms;
  float gpu_ms;
} GrStats;

int    gr_mesh_create(const GrVertex* verts, int nverts, const unsigned int* idx, int nidx);
void   gr_mesh_free(int mesh);
void   gr_mesh_aabb(int mesh, float* mn, float* mx);

int    gr_model_load(const char* path, int* meshes, int* materials, int max_parts);

int    gr_texture_load(const char* path, int nearest);
int    gr_texture_create(int w, int h, const unsigned char* rgba, int nearest, int repeat);
void   gr_texture_size(int tex, int* w, int* h);
void   gr_texture_free(int tex);

int    gr_material_create(void);
GrMaterial* gr_material_get(int mat);
void   gr_material_free(int mat);

int    gr_instance_create(int mesh, int material);
void   gr_instance_free(int inst);
void   gr_instance_set(int inst, int mesh, int material, int visible, int cast_shadow);
void   gr_instance_xform(int inst, float px, float py, float pz, float qx, float qy, float qz, float qw, float sx, float sy, float sz);
void   gr_instance_tint(int inst, float r, float g, float b, float a);

int    gr_multimesh_create(int mesh, int material, int count);
void   gr_multimesh_set(int mm, int i, float px, float py, float pz, float qx, float qy, float qz, float qw, float sx, float sy, float sz, float r, float g, float b, float a);
void   gr_multimesh_commit(int mm, int visible_count);
void   gr_multimesh_options(int mm, int visible, int cast_shadow);
void   gr_multimesh_free(int mm);

int    gr_light_create(void);
GrLight* gr_light_get(int light);
void   gr_light_free(int light);

GrEnvironment* gr_environment(void);
void   gr_camera(float px, float py, float pz, float qx, float qy, float qz, float qw, float fov, float znear, float zfar);
int    gr_world_to_screen(float x, float y, float z, float* sx, float* sy);
void   gr_screen_ray(float sx, float sy, float* origin, float* dir);

int    gr_particles_create(int max_particles);
GrParticleConfig* gr_particles_config(int ps);
void   gr_particles_burst(int ps, int count);
int    gr_particles_alive(int ps);
void   gr_particles_free(int ps);

void   gr_debug_line(float ax, float ay, float az, float bx, float by, float bz, float r, float g, float b);
GrStats* gr_stats(void);

/* --------------------------------------------------------- 2D canvas */
int    gr_font_load(const char* path);
float  gr_text_width(int font, const char* text, float size);
void   gr_draw_rect(float x, float y, float w, float h, float r, float g, float b, float a, float radius);
void   gr_draw_rect_border(float x, float y, float w, float h, float r, float g, float b, float a, float radius, float thickness);
void   gr_draw_rect_gradient(float x, float y, float w, float h, float r1, float g1, float b1, float a1, float r2, float g2, float b2, float a2, float radius);
void   gr_draw_image(int tex, float x, float y, float w, float h, float u0, float v0, float u1, float v1, float r, float g, float b, float a);
void   gr_draw_text(int font, const char* text, float x, float y, float size, float r, float g, float b, float a, float outline, float or_, float og, float ob, float oa);
void   gr_draw_shadow(float x, float y, float w, float h, float radius, float blur, float a);

/* ------------------------------------------------------------- physics */
typedef struct GrBodyDesc {
  int   shape;
  int   motion;           /* 0 static, 1 kinematic, 2 dynamic */
  int   sensor;
  float pos[3];
  float rot[4];
  float friction;
  float restitution;
  float mass;             /* 0 = from shape density */
  float linear_damping;
  float angular_damping;
  float gravity_factor;
  int   ccd;
} GrBodyDesc;

typedef struct GrRayHit {
  int   body;
  float pos[3];
  float normal[3];
  float fraction;
} GrRayHit;

typedef struct GrContact {
  int   a;
  int   b;
  float point[3];
  float normal[3];
  float speed;            /* approach speed along the normal */
} GrContact;

typedef struct GrCharState {
  float pos[3];
  float vel[3];
  int   on_floor;
  int   on_wall;
  int   on_ceiling;
  float floor_normal[3];
  int   floor_body;
} GrCharState;

int    gr_shape_box(float hx, float hy, float hz);
int    gr_shape_sphere(float radius);
int    gr_shape_capsule(float half_height, float radius);
int    gr_shape_cylinder(float half_height, float radius);
int    gr_shape_convex(const float* pts, int npts);
int    gr_shape_mesh(const float* verts, int nverts, const unsigned int* idx, int nidx);
int    gr_shape_offset(int shape, float x, float y, float z);

int    gr_body_create(const GrBodyDesc* desc);
void   gr_body_destroy(int body);
void   gr_body_get(int body, float* pos, float* rot);
void   gr_body_set(int body, float px, float py, float pz, float qx, float qy, float qz, float qw);
void   gr_body_move_kinematic(int body, float px, float py, float pz, float qx, float qy, float qz, float qw, float dt);
void   gr_body_get_velocity(int body, float* lin, float* ang);
void   gr_body_set_velocity(int body, float lx, float ly, float lz, float ax, float ay, float az);
void   gr_body_impulse(int body, float x, float y, float z, float px, float py, float pz, int at_point);
void   gr_body_force(int body, float x, float y, float z);
int    gr_body_sleeping(int body);
void   gr_body_wake(int body);
int    gr_body_overlaps(int body, int* out, int max);

void   gr_physics_step(float dt);
void   gr_physics_gravity(float x, float y, float z);
int    gr_physics_active(int* ids, float* xforms, int max);
int    gr_physics_raycast(float ox, float oy, float oz, float dx, float dy, float dz, int ignore_body, GrRayHit* hit);
int    gr_physics_sphere_overlap(float x, float y, float z, float radius, int* out, int max);
int    gr_physics_poll_contact(GrContact* out);
int    gr_physics_body_count(void);

int    gr_character_create(float radius, float height, float px, float py, float pz, float max_slope_deg, float step_height);
void   gr_character_destroy(int ch);
void   gr_character_move(int ch, float vx, float vy, float vz, float dt, GrCharState* out);
void   gr_character_teleport(int ch, float x, float y, float z);
int    gr_character_body(int ch);

/* --------------------------------------------------------------- audio */
int    gr_sound_load(const char* path);
int    gr_sound_create(const float* samples, int frames, int channels, int rate);
void   gr_sound_free(int snd);
int    gr_sound_play(int snd, float volume, float pitch, float pan, int loop);
int    gr_sound_play_3d(int snd, float x, float y, float z, float volume, float pitch, int loop, float min_dist, float max_dist);
void   gr_voice_stop(int voice);
void   gr_voice_volume(int voice, float volume);
void   gr_voice_pitch(int voice, float pitch);
void   gr_voice_position(int voice, float x, float y, float z);
int    gr_voice_playing(int voice);
void   gr_listener(float px, float py, float pz, float fx, float fy, float fz);
void   gr_master_volume(float v);
