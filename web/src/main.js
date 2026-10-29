// Grove showcase: Skylight Isle, web edition. A small third-person exploration game: find all
// 12 crystals, climb the sky islands, knock things over. Ported from games/demo/main.lua.
import * as THREE from 'three';
import { Col, V, rng, lookRotation } from './core.js';
import { U, createRenderer, setupPost, makeSky, initLightPool, updateLightPool, updateParticles, particleCount, setParticleScale } from './render.js';
import { initPhysics, stepPhysics, bodies } from './physics.js';
import { G, add, after, run, tween, tickTimers, updateLabels } from './game.js';
import { Input, initInput } from './input.js';
import { Audio, unlockAudio, setListener } from './audio.js';
import { SFX, initSfx } from './sfx.js';
import { buildMusic } from './music.js';
import * as Art from './art.js';
import * as Props from './props.js';
import * as World from './world.js';
import { Player, CameraRig } from './player.js';
import { DayNight } from './sky.js';
import { createHud } from './hud.js';

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const SHOT = params.get('shot');   // automated screenshot scenes, see shotScene()

function fail(e) {
  console.error(e);
  const el = $('error');
  el.style.display = 'flex';
  el.textContent = 'Skylight Isle could not start: ' + (e && e.message ? e.message : e) +
    '. It needs a browser with WebGL 2 and WebAssembly (recent Chrome, Edge, Firefox or Safari).';
}
const progress = async (f) => { $('loading').querySelector('i').style.width = Math.round(f * 100) + '%'; await new Promise((r) => setTimeout(r, 0)); };

async function boot() {
  const canvas = $('view');
  const { renderer, composer } = createRenderer(canvas);
  const scene = new THREE.Scene();
  const camera = new THREE.PerspectiveCamera(68, innerWidth / innerHeight, 0.1, 2500);
  G.scene = scene; G.camera = camera;
  const post = setupPost(composer, scene, camera);
  const resize = () => {
    renderer.setSize(innerWidth, innerHeight, false);
    composer.setSize(innerWidth, innerHeight);
    camera.aspect = innerWidth / innerHeight;
    camera.updateProjectionMatrix();
  };
  resize();
  addEventListener('resize', resize);
  initInput(canvas);

  await progress(0.05);
  await initPhysics();
  await progress(0.15);
  initSfx();
  const music = Audio.loop(buildMusic(), 0);
  await progress(0.3);

  const M = Art.materials();
  Props.init(M);
  initLightPool(scene);
  const sky = makeSky();
  scene.add(sky);
  const root = new THREE.Group();
  scene.add(root);
  await progress(0.4);
  World.build(root, M);
  await progress(0.85);

  // ---------------------------------------------------------------- game state
  const ctl = { collected: 0, total: Props.crystals.length, state: 'title', shadows: true, victoryOpen: false };
  const daynight = new DayNight(scene);
  daynight.fireflies = World.fireflies;
  ctl.daynight = daynight;
  const spawn = V(0, World.height(0, 30) + 0.5, 30);
  const player = new Player(root, spawn, M);
  const rig = new CameraRig(scene, player, camera);
  player.rig = rig;
  const hud = createHud(ctl);
  const musicVol = { v: 0 };
  tween(musicVol, { v: 0.55 }, 4, { ease: 'linear', real: true });

  ctl.startPlay = () => {
    if (ctl.state !== 'title') return;
    unlockAudio();
    ctl.state = 'play';
    ctl.startedAt = G.time;
    ctl.hintTime = G.realTime;
    hud.hideTitle();
    // Fly the camera from the orbit view down behind the player.
    const fromPos = rig.position.clone(), fromRot = rig.rotation.clone();
    rig.mode = 'follow'; rig.yaw = 0; rig.focus = null;
    rig.process(0.016);
    const toPos = rig.position.clone(), toRot = rig.rotation.clone();
    rig.mode = 'fly';
    Input.captureMouse(true);
    run(1.6, (t) => {
      rig.position.copy(fromPos).lerp(toPos, t);
      rig.rotation.copy(fromRot).slerp(toRot, t);
      camera.position.set(0, 0, rig.distance * t);
    }, { ease: 'in_out_cubic', onDone: () => {
      rig.mode = 'follow';
      player.locked = false;
      hud.show(true);
      hud.toast('Find all ' + ctl.total + ' crystals', 'Glowing mint crystals are hidden around the island and up in the sky');
    } });
  };
  let pausedAt = -1;
  ctl.pause = () => {
    if (ctl.state !== 'play') return;
    ctl.state = 'paused';
    G.paused = true;
    pausedAt = G.realTime;
    hud.showPause(true);
    Input.captureMouse(false);
    Audio.setVolume(music, 0.25);
  };
  ctl.resume = () => {
    if (ctl.state !== 'paused') return;
    ctl.state = 'play';
    G.paused = false;
    hud.showPause(false);
    Input.captureMouse(true);
    Audio.setVolume(music, 0.55);
  };
  ctl.closeVictory = () => {
    ctl.victoryOpen = false;
    hud.showVictory(false);
    Input.captureMouse(true);
    player.locked = false;
  };
  document.addEventListener('pointerlockchange', () => {
    // Browsers swallow Esc to release the mouse, so losing the lock mid-play means "pause".
    if (!document.pointerLockElement && ctl.state === 'play' && !ctl.victoryOpen && rig.mode === 'follow' && !SHOT) ctl.pause();
  });

  function onCollected(c) {
    ctl.collected++;
    hud.popCounter();
    rig.shake(0.25);
    if (ctl.collected >= ctl.total) {
      Audio.play(SFX.fanfare, { volume: 0.6 });
      const secs = G.time - (ctl.startedAt || 0);
      ctl.victoryOpen = true;
      hud.showVictory(true, `Time: ${Math.floor(secs / 60)}:${String(Math.floor(secs % 60)).padStart(2, '0')}`);
      Input.captureMouse(false);
      player.locked = true;
      // Fireworks over the island.
      for (let i = 0; i < 14; i++) {
        after(i * 0.35, () => {
          const p = player.position.clone().add(V(rng.float(-18, 18), rng.float(12, 20), rng.float(-18, 18)));
          Props.burst(root, p, Col.hsv(rng.float(), 0.6, 1), 90, 9);
          Audio.playAt(SFX.thud, p, { volume: 0.6, pitch: 0.6 });
        });
      }
    } else if (c.big) hud.toast('Sky Crystal!', ctl.collected + ' of ' + ctl.total + ' found');
    else hud.toast('Crystal ' + ctl.collected + ' / ' + ctl.total);
  }

  // Unlock audio on the first interaction anywhere (title music starts then).
  const unlock = () => unlockAudio();
  addEventListener('pointerdown', unlock);
  addEventListener('keydown', unlock);
  canvas.addEventListener('mousedown', () => {
    if (ctl.state === 'play' && !Input.isMouseCaptured() && !ctl.victoryOpen && rig.mode === 'follow') Input.captureMouse(true);
  });

  // ---------------------------------------------------------------- triggers
  const center = V();
  function checkTriggers() {
    const p = player.position;
    center.copy(p).add(V(0, 0.62, 0));
    for (const c of Props.crystals) {
      if (c.taken) continue;
      const cp = c.root.getWorldPosition(V());
      if (cp.distanceTo(center) < c.radius + player.radius) Props.collectCrystal(c, onCollected);
    }
    for (const a of Props.areas) {
      const dx = p.x - a.pos.x, dz = p.z - a.pos.z;
      const inside = Math.hypot(dx, dz) < a.radius + player.radius && p.y > a.pos.y - a.height / 2 - 0.2 && p.y < a.pos.y + a.height / 2;
      if (inside && !a.inside) a.onEnter(player);
      a.inside = inside;
    }
  }

  await progress(1);
  $('loading').style.opacity = 0;
  setTimeout(() => $('loading').remove(), 700);

  // ---------------------------------------------------------------- loop
  const info = { calls: 0, tris: 0, bodies: 0, particles: 0 };
  // Step quality down on slower machines: lower resolution first, then a smaller shadow map.
  let quality = 0, qAcc = 0, qFrames = 0;
  function adaptQuality(dt) {
    qAcc += dt; qFrames++;
    if (qAcc < 3) return;
    const slow = qAcc / qFrames > 1 / 42;
    qAcc = 0; qFrames = 0;
    if (!slow || quality >= 3) return;
    quality++;
    const pr = [1.5, 1, 0.8, 0.65][quality];
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, pr));
    composer.setPixelRatio(renderer.getPixelRatio());
    resize();
    if (quality === 2) {
      const sh = daynight.light.shadow;
      sh.mapSize.set(2048, 2048);
      if (sh.map) { sh.map.dispose(); sh.map = null; }
    }
  }
  const camPos = V(), camRight = V();
  let last = performance.now();
  let frame = 0;
  const shot = SHOT ? shotScene(SHOT, { ctl, player, rig, daynight, root }) : null;

  function tick(now) {
    const dtReal = shot ? 1 / 60 : Math.min((now - last) / 1000, 0.1);
    last = now;
    Input.poll();
    G.realTime += dtReal;
    U.uTime.value = G.realTime;

    // Keys that must work while paused.
    if (Input.pressed('pause') && G.realTime - pausedAt > 0.3) {
      if (ctl.state === 'play' && !ctl.victoryOpen) ctl.pause(); else if (ctl.state === 'paused') ctl.resume();
    }
    if (ctl.state === 'title' && Input.pressed('ui_accept')) ctl.startPlay();
    if (shot) shot.tick(frame);

    if (!G.paused) {
      const dt = dtReal;
      G.time += dt;
      for (const f of Props.platforms) f();
      player.physics(dt);
      stepPhysics(dt, G.time);
      checkTriggers();
      player.process(dt);
      for (const f of [...G.process]) f(dt);
      rig.process(dt);
      daynight.update(dt, player.position);
      tickTimers(dt, dtReal);
      updateParticles(dt, G.realTime);
    } else tickTimers(0, dtReal);
    Audio.setVolume(music, ctl.state === 'paused' ? 0.25 : musicVol.v);

    camera.getWorldPosition(camPos);
    sky.position.copy(camPos);
    updateLightPool(camPos);
    camRight.set(1, 0, 0).applyQuaternion(camera.getWorldQuaternion(new THREE.Quaternion()));
    setListener(camPos, camRight);
    post.bloom.strength = daynight.bloomStrength * 3.5;
    post.comp.uniforms.uExposure.value = daynight.exposure;
    post.comp.uniforms.uTime.value = G.realTime;
    setParticleScale(renderer.domElement.height, camera.fov);

    renderer.info.autoReset = false;
    renderer.info.reset();
    composer.render();
    info.calls = renderer.info.render.calls; info.tris = renderer.info.render.triangles;
    if (!shot) adaptQuality(dtReal);
    info.bodies = bodies.length;
    info.particles = particleCount();
    updateLabels(camera, innerWidth, innerHeight);
    hud.update(dtReal, info);
    Input.endFrame();
    frame++;
    if (shot && shot.done(frame)) { document.title = 'SHOT_READY'; return; }
    requestAnimationFrame(tick);
  }
  requestAnimationFrame(tick);
}

// Automated scenes for screenshot checks: ?shot=title|run|playground|sky|ruins|camp|meadow|morning
function shotScene(name, { ctl, player, rig, daynight }) {
  const z = World.zones;
  const scenes = {
    title: { frames: 90 },
    run: { frames: 220, setup() {} },
    playground: { frames: 200, setup() { player.teleport(V(z.plaza.x - 4, z.plaza.h + 1, z.plaza.z + 2)); rig.yaw = Math.atan2(-10, 8); rig.pitch = -0.2; }, fire: [60, 140] },
    dominoes: { frames: 240, setup() { player.teleport(V(z.plaza.x - 2, z.plaza.h + 0.3, z.plaza.z + 11)); rig.yaw = 0; rig.pitch = -0.6; } },
    sky: { frames: 120, setup() { player.teleport(V(z.plaza.x + 8, z.plaza.h + 1, z.plaza.z + 8)); rig.yaw = 0.6; rig.pitch = 0.35; } },
    ruins: { frames: 120, setup() { player.teleport(V(z.ruins.x + 6, z.ruins.h + 1, z.ruins.z + 12)); rig.yaw = 0.3; rig.pitch = -0.25; daynight.hour = 18.4; } },
    camp: { frames: 150, setup() { player.teleport(V(z.camp.x + 4, z.camp.h + 1, z.camp.z - 5)); rig.yaw = -2.4; rig.pitch = -0.2; daynight.hour = 22.5; } },
    meadow: { frames: 150, setup() { daynight.hour = 22.5; rig.pitch = -0.15; } },
    morning: { frames: 120, setup() { daynight.hour = 9; rig.pitch = -0.3; } },
    // Gameplay checks (results go to the console).
    jump: { frames: 120, each(f) {
      const realPressed = jumpProbe.pressed || (jumpProbe.pressed = Input.pressed);
      Input.pressed = (a) => (a === 'jump' && f === 30) || (a !== 'jump' && realPressed(a));
      Input.down = (a) => a === 'jump' && f >= 30 && f < 70;
      if (f === 29) jumpProbe.y0 = player.position.y;
      if (f > 30) jumpProbe.max = Math.max(jumpProbe.max || 0, player.position.y - jumpProbe.y0);
      if (f === 119) console.log('jump apex', jumpProbe.max.toFixed(2), 'grounded', player.isOnFloor());
    } },
    pad: { frames: 200, setup() { player.teleport(V(z.plaza.x + 8, z.plaza.h + 0.4, z.plaza.z + 8)); }, each(f) {
      jumpProbe.max = Math.max(jumpProbe.max || 0, player.position.y);
      if (f === 199) console.log('pad apex y', jumpProbe.max.toFixed(1), 'plaza y', z.plaza.h.toFixed(1), 'now y', player.position.y.toFixed(1));
    } },
    platform: { frames: 400, setup() { rig.pitch = -0.5; }, each(f) {
      const plat = bodies.find((b) => b.name === 'Platform');
      if (f === 3) player.teleport(plat.pos.clone().add(V(0, 0.3, 0)));
      if (f % 10 === 0 && f < 200) console.log('platform', f, 'dy', (player.position.y - plat.pos.y).toFixed(2), 'dxz', Math.hypot(player.position.x - plat.pos.x, player.position.z - plat.pos.z).toFixed(2), 'grounded', player.isOnFloor());
    } },
    collect: { frames: 420, each(f) {
      if (f >= 5 && f % 15 === 0) {
        const c = Props.crystals.find((k) => !k.taken);
        if (c) player.teleport(c.root.getWorldPosition(V()).sub(V(0, 0.8, 0)));
      }
      if (f === 419) console.log('collected', ctl.collected, '/', ctl.total, 'victory', ctl.victoryOpen);
    } },
  };
  scenes.perf = { frames: 300, setup() { rig.pitch = -0.2; }, each(f) {
    if (f === 100) jumpProbe.t0 = performance.now();
    if (f === 299) {
      const gl = document.getElementById('view').getContext('webgl2');
      const ext = gl.getExtension('WEBGL_debug_renderer_info');
      console.log('frame ms', ((performance.now() - jumpProbe.t0) / 199).toFixed(1), ext ? gl.getParameter(ext.UNMASKED_RENDERER_WEBGL) : '');
    }
  } };
  const jumpProbe = {};
  const s = scenes[name] || scenes.title;
  return {
    tick(frame) {
      if (s.each && frame > 2) s.each(frame);
      if (name === 'title' || frame !== 2) {
        if (s.fire && frame >= s.fire[0] && frame < s.fire[1]) Input.down = (a) => a === 'fire';
        if (s.fire && frame === s.fire[1]) Input.down = () => false;
        return;
      }
      ctl.startPlay();
      rig.mode = 'follow';
      player.locked = false;
      document.getElementById('hud').style.opacity = 1;
      s.setup && s.setup();
    },
    done: (frame) => frame >= s.frames,
  };
}

boot().catch(fail);
