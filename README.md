# Grove

A small Godot-style 3D engine for PC games. C++ core (OpenGL 4.5, Jolt Physics, miniaudio),
games written in Lua (LuaJIT). Games live in `games/<name>/main.lua`.

```
./play.sh                 # run the showcase (games/demo)
./play.sh games/smoke     # run another game
./build.sh                # rebuild the engine (only needed after C++/CMake changes)
```

Dev keys (always available): **F5** hot-restart (reloads Lua and shaders), **F3** stats overlay,
**F11** fullscreen, **F12** screenshot to `<game>/screenshots/`. Script errors show on screen; fix and press F5.

Automated runs: `bin/grove games/x --frames N --hidden --shot out.png` steps N frames at a fixed 1/60 s and
saves the last frame. `--restart-loop` hot-restarts repeatedly as a teardown self-test.

## Layout

| Path | What |
|---|---|
| `src/` | C++ engine: `renderer.cpp`, `canvas.cpp` (2D/UI), `physics.cpp` (Jolt), `audio.cpp`, `input.cpp`, `meshload.cpp` (glTF/OBJ), `main.cpp` (loop + Lua host) |
| `engine/api.h` | The C API. Read by C++ and by LuaJIT FFI (`C.gr_*`), so it stays plain C. |
| `engine/shaders/` | GLSL. `main.glsl` is the PBR surface shader; edit and press F5. |
| `engine/lua/grove/` | The Lua side: node tree, math, resources, physics/UI nodes, game loop. |
| `games/demo/` | Showcase game "Skylight Isle". `shots.lua` is its screenshot tour (`--shots <dir>`). |

## Scripting model (like Godot)

```lua
local Spinner = MeshInstance3D:extend("Spinner")
function Spinner:_ready() self.speed = 2 end
function Spinner:_process(dt) self:rotate_y(dt * self.speed) end

Game.start(Node3D {                       -- array entries become children
  DirectionalLight3D {},
  Camera3D { position = Vec3(0, 3, 8) },
  Spinner { mesh = MeshData.box(1):upload(), material = Material { albedo = Color("#e8a33c") } },
  StaticBody3D { shape = Shape.box(20, 1, 20), position = Vec3(0, -1, 0) },
})
```

Callbacks: `_ready`, `_process(dt)`, `_physics_process(dt)`, `_enter_tree`, `_exit_tree`, `_draw_ui(rect)`.
Constructor keys are assigned as fields; `groups = {...}`, `on = { signal = fn }`.
Node API: `add_child, remove_child, queue_free, get("A/B"), find(name|Class), find_all, connect(sig, fn), emit(sig, ...), add_to_group, spawn(fn)`.
`process_mode = "always"` keeps a subtree running while `Game.paused`.

**Node3D**: `position` (Vec3), `rotation` (Quat; Vec3 euler accepted in constructors, or `rotation_degrees`), `scale`, `visible`, `top_level`.
`global_position(), set_global_position(v), global_rotation(), forward(), right(), up(), look_at(p), rotate_y(a), translate_local(v), to_global(p), to_local(p)`.

**Visual nodes**: `MeshInstance3D {mesh, material, cast_shadow, tint}`, `MultiMeshInstance3D {mesh, material}` + `:set_instance(i, pos, rot, scale, color)` (world space, one draw call),
`Camera3D {fov, near, far, current}` + `:shake(a)`, `:world_to_screen(p)`, `:screen_ray(x, y)`,
`DirectionalLight3D {color, energy, shadows}` (one sun; -Z is light direction), `OmniLight3D {color, energy, range}`, `SpotLight3D {+angle, softness}` (up to 32 lights),
`Particles3D {rate, amount, lifetime, speed, spread, direction, gravity, damping, color, color_end, size, size_end, additive, turbulence, stretch, emit_box, emit_radius, one_shot, auto_free}` + `:burst(n)`,
`Label3D {text, size, color}` (world-anchored text), `AudioPlayer3D {sound, volume, pitch, loop, autoplay, positional}`.

**Environment** (global): `sky_top, sky_horizon, ground, sun_dir, sun_color, sun_energy, ambient_energy, reflection_energy, fog_color, fog_density, fog_height, fog_height_density, clouds, cloud_speed, stars, moon_dir, exposure, bloom_strength, bloom_threshold, saturation, contrast, vignette, sun_shadows, shadow_distance, sky_enabled`. `Environment:set{...}`.

**Physics** (Jolt): `StaticBody3D`, `RigidBody3D {mass, friction, bounce, linear_damp, angular_damp, gravity_scale, ccd}` (+ `apply_impulse, set_velocity, get_velocity, teleport`; signal `body_entered(other, {point, normal, speed})`),
`AnimatableBody3D` (move it in code; carries characters), `CharacterBody3D {radius, height, max_slope, step_height}` (origin at feet; set `velocity`, call `move_and_slide()`, `is_on_floor()`),
`Area3D` (signals `body_entered/body_exited`). Shapes: `Shape.box(sx,sy,sz) sphere(r) capsule(r,h) cylinder(r,h) convex(meshdata) mesh(meshdata) offset(shape, v)`.
Queries: `Physics.raycast(from, to, exclude) -> {node, position, normal, distance}`, `Physics.overlap_sphere(c, r)`, `Physics.set_gravity(v)`.

**Resources**: `MeshData` builder (`box sphere icosphere cylinder cone capsule torus grid plane`, `:append(md, pos, rot, scale) :transform :paint :paint_fn :displace :flat :smooth_normals :copy :upload()`; vertex colours are first-class),
`Material {albedo, roughness, metallic, emission, emission_energy, texture, uv_scale, triplanar, transparent, double_sided, unshaded, alpha_cutoff, wind, rim, effect = "water"|"pulse", no_fog}`,
`Texture.load(path) / generate(w, h, fn) / checker`, `Model.load(path)` / `Model.instance(path)` (glTF/OBJ), `Font.load(path)`. Paths are relative to the game folder.

**Audio**: `Sound.load(path)` (wav/mp3/flac/ogg), `Sound.preset("coin"|"jump"|"land"|"laser"|"explosion"|"hit"|"powerup"|"blip"|"select"|"thud"|"whoosh"|"step"|"chime"|"bounce", variation)`,
`Sound.synth{wave, freq, freq_end, duration, arp, ...}`, `SoundBuilder(seconds):note(t, "C4", dur, opts) :drum(t, "kick") :build{reverb}` for music.
`Audio.play(snd, {volume, pitch, pan, loop})`, `Audio.play_at(snd, pos, opts)`.

**Input**: actions `move_left/right/forward/back, jump, sprint, interact, fire, aim, pause, ui_*`; `Input.bind(name, {"SPACE", "mouse1", "pad_a", "pad_lx-"})`.
`Input.pressed/down/released/strength(a)`, `Input.vector(l, r, f, b)`, `Input.mouse_delta()`, `Input.capture_mouse(on)`, `Input.look_stick()`, `Input.simulate(a, down)`.

**UI**: Control nodes `Panel, Label, Button (signal "pressed" / on_pressed), ProgressBar, TextureRect, VBox, HBox` with `anchor` (`top_left`…`bottom_right`, `center`, `full`) + `x, y, w, h`.
Coordinates are virtual 720p-height pixels (scaled to the window). Immediate drawing in any `_draw_ui`: `Draw.rect/rect_border/gradient/shadow/circle/ring/image/text/text_width`. Keyboard/gamepad navigate buttons automatically.

**Flow**: `Game.start(node|fn)`, `Game.change_scene`, `Game.paused`, `Game.time_scale`, `Game.time/delta`, `Game.group(name)`,
`Game.after(s, fn)`, `Game.every(s, fn)`, coroutines `Game.spawn(fn)` / `node:spawn(fn)` with `wait(s)`, `wait_frames(n)`, `wait_until(fn)`, `wait_signal(node, sig)`.
`Tween.to(target, {field = value}, dur, {ease, delay, loop, yoyo, on_done, always})`, `Tween.run(dur, fn)`, `Ease.*`.
`Save.write(name, table)`, `Save.read(name)`. Math: `Vec3, Quat, Color, Random(seed), Noise.perlin2/3, fbm2/3, math.clamp/lerp/damp/smoothstep`. Debug: `Debug.line/box/cross`.

## Building from scratch

Needs gcc, cmake, glfw3 dev headers. Third-party sources are vendored in `third_party/`
(LuaJIT is built with `make -C third_party/luajit BUILDMODE=static`; Jolt builds through CMake).
