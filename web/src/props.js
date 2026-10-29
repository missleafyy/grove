// Reusable scene pieces ("prefabs") for Skylight Isle (port of props.lua).
import * as THREE from 'three';
import { Col, V, euler, fromY, rng, TAU, clamp, Noise } from './core.js';
import { MeshData } from './mesh.js';
import * as Art from './art.js';
import { Particles } from './render.js';
import { Shape, addStatic, addRigid, addKinematic, moveKinematic, setVelocity } from './physics.js';
import { G, add, light, label, free, onProcess, tween } from './game.js';
import { Audio } from './audio.js';
import { SFX } from './sfx.js';

const P = Art.P;
let M;
export const meshes = {};
export const areas = [];        // trigger volumes checked against the player
export const lamps = [];

export function init(materials) {
  M = materials;
  meshes.crate = MeshData.box(1, 1, 1).geometry();
  meshes.barrel = Art.barrel().geometry();
  meshes.orb = MeshData.sphere(0.28, 16, 12).geometry();
  meshes.crystal = Art.crystalMesh(1.4).geometry();
  meshes.crystal_big = Art.crystalMesh(2.6).geometry();
  meshes.pad = MeshData.cylinder(1.1, 1.25, 0.3, 24, Col.WHITE).geometry();
  meshes.pad_ring = MeshData.torus(1.15, 0.09, 32, 8, P.white).geometry();
  meshes.lamp = Art.lampPost().geometry();
  meshes.lamp_bulb = MeshData.sphere(0.2, 12, 8, Col.WHITE).geometry();
  meshes.platform = MeshData.box(4, 0.5, 4, Col.WHITE).flat().geometry();
  meshes.log = MeshData.cylinder(0.14, 0.14, 1.3, 8, P.bark).flat().geometry();
  meshes.fire_stone = Art.rock(9, 0.22).geometry();
  meshes.pillar = MeshData.cylinder(0.55, 0.62, 1, 10, P.stone).flat().geometry();
  meshes.pillar_cap = MeshData.box(1.5, 0.35, 1.5, P.stone_dark).geometry();
  meshes.sign_post = MeshData.box(0.14, 1.6, 0.14, P.wood_dark).geometry();
  meshes.sign_board = MeshData.box(1.6, 0.6, 0.1, P.wood).geometry();
}

// MeshInstance3D
export function mi(geo, mat, o = {}) {
  const m = new THREE.Mesh(geo, mat);
  if (o.position) m.position.copy(o.position);
  if (o.rotation) m.quaternion.copy(o.rotation);
  if (o.scale) m.scale.copy(typeof o.scale === 'number' ? V(o.scale) : o.scale);
  m.castShadow = o.cast_shadow !== false;
  m.receiveShadow = true;
  return m;
}
export function node(pos, rot) {
  const n = new THREE.Group();
  if (pos) n.position.copy(pos);
  if (rot) n.quaternion.copy(rot);
  return n;
}

function impactSound(rec, sound, minSpeed = 1.5, volume = 1) {
  rec.onImpact = (speed, pos, time) => {
    if (speed < minSpeed) return;
    rec.lastImpact = time;
    Audio.playAt(sound, pos, { volume: clamp(speed / 10, 0.1, 1) * volume, pitch: rng.float(0.85, 1.15) });
  };
}

function rigid(parent, o, children) {
  const g = node(o.position, o.rotation);
  children.forEach((c) => add(g, c));
  add(parent, g);
  const rec = addRigid({ ...o, obj: g });
  g.userData.body = rec;
  return { g, rec };
}

// ------------------------------------------------------------------ physics props
export function crate(parent, pos, size = 1, rot) {
  const { rec } = rigid(parent, { name: 'Crate', position: pos, rotation: rot, shape: Shape.box(size, size, size), mass: 12 * size ** 3, friction: 0.7 },
    [mi(meshes.crate, M.crate, { scale: size })]);
  impactSound(rec, SFX.thud, 2, 0.8);
}
export function barrel(parent, pos, rot) {
  const { rec } = rigid(parent, { name: 'Barrel', position: pos, rotation: rot, shape: Shape.cylinder(0.45, 1.1), mass: 20, friction: 0.5 },
    [mi(meshes.barrel, M.vertex)]);
  impactSound(rec, SFX.thud, 2, 0.6);
}
export { rigid };

// Glowing ball the player throws. Lights up the world and knocks things over.
const orbs = [];
export function sparkOrb(parent, pos, vel) {
  const mesh = mi(meshes.orb, M.orb, { cast_shadow: false });
  const trail = new Particles({ rate: 40, lifetime: 0.5, speed: 0.3, spread: 180, size: 0.16, size_end: 0,
    color: new Col(1, 0.75, 0.35, 0.9), color_end: new Col(1, 0.4, 0.1, 0), amount: 64 });
  const { g, rec } = rigid(parent, { name: 'Orb', position: pos, shape: Shape.sphere(0.28), mass: 6, bounce: 0.55, friction: 0.4,
    ccd: true, linear_damp: 0.1, angular_damp: 0.3 }, [mesh, trail]);
  const l = light(g, { color: Col.hex('#ffbe5c'), energy: 3, range: 7 });
  setVelocity(rec, vel);
  impactSound(rec, SFX.bounce, 1.5, 0.7);
  const orb = { g, born: G.time };
  onProcess(g, () => {
    const age = G.time - orb.born;
    if (age > 7) {
      const t = clamp(age - 7, 0, 1);
      mesh.scale.setScalar(Math.max(1 - t, 0.001));
      l.energy = 3 * (1 - t);
      trail.emitting = t < 0.5;
      if (t >= 1) { free(g); const i = orbs.indexOf(orb); if (i >= 0) orbs.splice(i, 1); }
    }
  });
  orbs.push(orb);
  // Keep the number of live orbs bounded.
  while (orbs.length > 24) { const old = orbs.shift(); old.born = Math.min(old.born, G.time - 7); }
  return g;
}

// ------------------------------------------------------------------ effects
export function burst(parent, pos, col = new Col(1, 1, 1, 1), count = 40, speed = 5) {
  return add(parent, new Particles({ position: pos, one_shot: true, auto_free: true, amount: count, lifetime: 0.9, lifetime_random: 0.4,
    speed, speed_random: 0.5, spread: 180, gravity: [0, -6, 0], damping: 1.5, size: 0.14, size_end: 0, color: col, color_end: col.withAlpha(0) }));
}
export function dust(parent, pos) {
  return add(parent, new Particles({ position: pos, one_shot: true, auto_free: true, amount: 14, lifetime: 0.6, speed: 1.6, spread: 80,
    gravity: [0, -1, 0], damping: 3, additive: false, size: 0.22, size_end: 0.45,
    color: new Col(0.95, 0.92, 0.85, 0.55), color_end: new Col(0.95, 0.92, 0.85, 0), emit_radius: 0.3 }));
}
export function splash(parent, pos) {
  return add(parent, new Particles({ position: pos, one_shot: true, auto_free: true, amount: 60, lifetime: 1.0, speed: 6, speed_random: 0.4, spread: 35,
    gravity: [0, -14, 0], additive: false, size: 0.16, size_end: 0.05,
    color: new Col(0.85, 0.95, 1, 0.9), color_end: new Col(0.85, 0.95, 1, 0), emit_radius: 0.4 }));
}

// ------------------------------------------------------------------ gameplay pieces
export const crystals = [];
export function crystal(parent, pos, big) {
  const glow = big ? Col.hex('#bff1ff') : P.mint_glow;
  const root = node(pos);
  const visual = node();
  add(visual, mi(big ? meshes.crystal_big : meshes.crystal, big ? M.crystal_big : M.crystal, { position: V(0, big ? -0.6 : -0.3, 0) }));
  light(visual, { color: big ? Col.hex('#8fe3ff') : P.mint_glow, energy: big ? 5 : 2.5, range: big ? 9 : 6, position: V(0, 0.3, 0) });
  add(visual, new Particles({ rate: 6, lifetime: 2, speed: 0.4, spread: 60, size: 0.06, size_end: 0, emit_radius: 0.6,
    color: glow.withAlpha(0.9), color_end: new Col(1, 1, 1, 0), turbulence: 2 }));
  add(root, visual);
  if (big) label(root, 'Sky Crystal', { position: V(0, 2.6, 0), size: 26, color: Col.hex('#bff1ff') });
  add(parent, root);
  const c = { root, visual, big, phase: rng.float(0, 6.28), taken: false, radius: big ? 1.6 : 1.0 };
  onProcess(root, (dt) => {
    if (c.taken) return;
    visual.rotateY(dt * 1.2);
    visual.position.y = Math.sin(G.time * 2 + c.phase) * 0.18 + 0.2;
  });
  crystals.push(c);
  return c;
}
export function collectCrystal(c, onCollected) {
  c.taken = true;
  const p = c.root.position.clone();
  Audio.play(SFX.chime, { volume: 0.7 });
  Audio.play(SFX.collect, { volume: 0.5 });
  burst(c.root.parent, p.clone().add(V(0, 0.4, 0)), c.big ? Col.hex('#bff1ff') : P.mint_glow, 70, 7);
  tween(c.visual, { scale: V(1.6), position: V(0, 1.5, 0) }, 0.18, { ease: 'out_quad',
    onDone: () => tween(c.visual, { scale: V(0.01) }, 0.25, { ease: 'in_back', onDone: () => free(c.root) }) });
  onCollected(c);
}

export function jumpPad(parent, pos, strength = 22) {
  const g = node(pos);
  add(g, mi(meshes.pad, M.pad, { position: V(0, -0.05, 0) }));
  const ring = add(g, mi(meshes.pad_ring, M.stone, { position: V(0, 0.16, 0) }));
  light(g, { color: Col.hex('#ff6fa5'), energy: 2, range: 5, position: V(0, 0.8, 0) });
  add(g, new Particles({ rate: 14, lifetime: 1.2, speed: 3, spread: 8, emit_radius: 0.8, size: 0.08, size_end: 0,
    color: Col.hex('#ffb3cf'), color_end: new Col(1, 0.5, 0.7, 0) }));
  add(parent, g);
  addStatic(Shape.cylinder(1.25, 0.3), pos.clone().add(V(0, -0.05, 0)));
  areas.push({ kind: 'pad', pos, radius: 1.1, height: 0.8, inside: false, onEnter(player) {
    player.launch(strength);
    Audio.playAt(SFX.bounce_pad, pos, { volume: 0.9 });
    ring.scale.set(1.3, 3, 1.3);
    tween(ring, { scale: V(1) }, 0.5, { ease: 'out_elastic' });
  } });
}

// Platform that drifts between two points; carries the player and pushes crates.
export const platforms = [];
export function movingPlatform(parent, a, b, period, phase = 0) {
  const g = node(a);
  add(g, mi(meshes.platform, M.platform));
  add(g, mi(meshes.crystal, M.crystal, { position: V(0, -0.55, 0), rotation: euler(Math.PI, 0, 0), scale: 0.7, cast_shadow: false }));
  add(parent, g);
  const rec = addKinematic({ name: 'Platform', position: a, shape: Shape.box(4, 0.5, 4), obj: g });
  g.userData.body = rec;
  const p = V();
  platforms.push(() => {
    let t = (Math.sin((G.time / period + phase) * TAU) + 1) / 2;
    t = t * t * (3 - 2 * t);
    moveKinematic(rec, p.copy(a).lerp(b, t));
  });
}

// Street lamp that switches on at dusk.
export function lamp(parent, pos) {
  const g = node(pos);
  add(g, mi(meshes.lamp, M.vertex));
  add(g, mi(meshes.lamp_bulb, M.lamp_glow, { position: V(0, 3.0, 0), cast_shadow: false }));
  const l = light(g, { color: Col.hex('#ffc874'), energy: 0, range: 11, position: V(0, 3.0, 0) });
  add(parent, g);
  addStatic(Shape.offset(Shape.cylinder(0.12, 3), V(0, 1.5, 0)), pos);
  lamps.push((t) => { l.energy = 3.5 * t; });
}
export function setLamps(t) {
  for (const f of lamps) f(t);
  M.lamp_glow.emissiveIntensity = 0.2 + 5 * t;
}

export function campfire(parent, pos) {
  const fire = node(pos);
  const l = light(fire, { color: Col.hex('#ff9a3c'), energy: 4, range: 12, position: V(0, 1, 0) });
  add(fire, new Particles({ position: V(0, 0.15, 0), rate: 70, lifetime: 0.9, lifetime_random: 0.4, speed: 1.6, spread: 12, emit_radius: 0.25,
    size: 0.38, size_end: 0.05, color: new Col(1, 0.7, 0.25, 0.9), color_end: new Col(1, 0.2, 0.05, 0), turbulence: 3, amount: 120 }));
  add(fire, new Particles({ position: V(0, 0.3, 0), rate: 10, lifetime: 1.6, speed: 3, spread: 25, size: 0.04, size_end: 0,
    color: new Col(1, 0.8, 0.4, 1), color_end: new Col(1, 0.3, 0, 0), turbulence: 6 }));
  add(fire, new Particles({ position: V(0, 1.0, 0), rate: 8, lifetime: 3.5, speed: 1.2, spread: 10, additive: false,
    size: 0.4, size_end: 1.6, color: new Col(0.35, 0.35, 0.38, 0.35), color_end: new Col(0.5, 0.5, 0.52, 0), turbulence: 1.5 }));
  for (let i = 0; i <= 4; i++) {
    const a = i / 5 * TAU;
    add(fire, mi(meshes.log, M.vertex, { position: V(Math.cos(a) * 0.3, 0.2, Math.sin(a) * 0.3), rotation: fromY(-a).multiply(euler(0, 0, 1.1)) }));
  }
  for (let i = 0; i <= 9; i++) {
    const a = i / 10 * TAU;
    add(fire, mi(meshes.fire_stone, M.vertex, { position: V(Math.cos(a) * 0.85, 0.05, Math.sin(a) * 0.85) }));
  }
  add(parent, fire);
  addStatic(Shape.cylinder(0.9, 0.4), pos.clone().add(V(0, 0.2, 0)));
  onProcess(fire, () => {
    const t = G.time;
    l.energy = 3.5 + Math.sin(t * 13) * 0.4 + Math.sin(t * 7.3) * 0.5 + Noise.perlin2(t * 4, 0) * 0.8;
  });
}

export function pillar(parent, pos, height, broken) {
  const g = node(pos);
  add(g, mi(meshes.pillar, M.vertex, { position: V(0, height / 2, 0), scale: V(1, height, 1) }));
  if (!broken) add(g, mi(meshes.pillar_cap, M.vertex, { position: V(0, height + 0.17, 0) }));
  add(parent, g);
  addStatic(Shape.offset(Shape.cylinder(0.6, height), V(0, height / 2, 0)), pos);
}

export function sign(parent, pos, yaw, text) {
  const rot = fromY(yaw);
  const g = node(pos, rot);
  add(g, mi(meshes.sign_post, M.vertex, { position: V(0, 0.8, 0) }));
  add(g, mi(meshes.sign_board, M.vertex, { position: V(0, 1.4, 0.08) }));
  label(g, text, { position: V(0, 2.15, 0), size: 24, max_distance: 28, color: Col.hex('#fff4d6') });
  add(parent, g);
  addStatic(Shape.offset(Shape.box(0.2, 1.6, 0.2), V(0, 0.8, 0)), pos, rot);
}
