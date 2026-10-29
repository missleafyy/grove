// Procedural art for Skylight Isle: palette, materials, textures and meshes built in code (port of art.lua).
import { Col, Random, Noise, V, euler, fromY, clamp, TAU } from './core.js';
import { MeshData } from './mesh.js';
import { material, genTexture } from './render.js';

const H = (s) => Col.hex(s);
export const P = {
  grass: H('#6fb253'), grass_light: H('#9ccf63'), grass_dark: H('#4b8d43'),
  sand: H('#e9d7a1'), sand_wet: H('#c9b483'),
  rock: H('#8d929b'), rock_dark: H('#666b75'), rock_light: H('#b3b7bd'),
  dirt: H('#a98b62'),
  bark: H('#7a5232'), bark_dark: H('#5c3c24'),
  leaf: H('#4e9c45'), leaf_light: H('#7cc057'), pine: H('#2f7a4f'),
  blossom: H('#f4a9c6'), blossom_light: H('#ffd0e1'), autumn: H('#e6a33c'),
  mint: H('#9fe8c4'), mint_dark: H('#4fbf8a'), mint_glow: H('#7ee0b4'),
  wood: H('#b07b47'), wood_dark: H('#7d5330'),
  stone: H('#d9d2c3'), stone_dark: H('#a69f90'),
  roof: H('#c4523f'), metal: H('#3b3f47'), lamp: H('#ffd27a'),
  white: H('#f6f4ee'), ink: H('#1f2430'),
};

function hash(x, y) { const n = Math.sin(x * 127.1 + y * 311.7) * 43758.5453; return n - Math.floor(n); }

// ------------------------------------------------------------------ textures
function crateTexture() {
  return genTexture(128, 128, (x, y, u, v) => {
    const frame = u < 0.1 || u > 0.9 || v < 0.1 || v > 0.9;
    const diag = Math.abs(u - v) < 0.06 || Math.abs(u - (1 - v)) < 0.06;
    const plank = Math.floor(v * 4);
    const grain = Noise.perlin2(u * 3 + plank * 7.3, v * 40) * 0.08;
    let base = 0.78 + grain + hash(plank, 3) * 0.08;
    if (frame || diag) base = 0.58 + grain;
    if ((v * 4) % 1 < 0.04 && !frame) base *= 0.6;
    if (frame && Math.min(u, v, 1 - u, 1 - v) < 0.015) base *= 0.7;
    return [base, base, base, 1];
  });
}
function tileTexture() {
  return genTexture(256, 256, (x, y, u, v) => {
    let cu = u * 4; const cv = v * 4, row = Math.floor(cv);
    cu += (row % 2) * 0.5;
    const fx = cu % 1, fy = cv % 1;
    const tile = hash(Math.floor(cu), row);
    const grout = Math.min(fx, fy, 1 - fx, 1 - fy) < 0.035;
    let b = 0.86 + tile * 0.1 + Noise.fbm2(u * 16, v * 16, 3) * 0.08;
    if (grout) b = 0.55;
    return [b, b * 0.98, b * 0.94, 1];
  }, 0.12);
}
function noiseTexture() {
  return genTexture(256, 256, (x, y, u, v) => { const n = 0.85 + Noise.fbm2(u * 8, v * 8, 4) * 0.25; return [n, n, n, 1]; });
}

// ------------------------------------------------------------------ materials
export function materials() {
  const M = {};
  M.terrain = material({ roughness: 0.95, map: noiseTexture() });
  M.vertex = material({ roughness: 0.85 });
  M.foliage = material({ roughness: 0.8, wind: 0.12 });
  M.grass = material({ roughness: 0.9, wind: 9 });
  M.water = material({ albedo: Col.hex('#3d9fc6', 0.72), roughness: 0.08, transparent: true, effect: 'water', vertexColors: false });
  M.crate = material({ albedo: H('#c48e57'), roughness: 0.75, map: crateTexture(), vertexColors: false });
  M.tiles = material({ roughness: 0.7, map: tileTexture(), vertexColors: false });
  M.stone = material({ albedo: P.stone, roughness: 0.85, vertexColors: false });
  M.crystal = material({ albedo: P.mint, roughness: 0.15, emission: P.mint_glow, emission_energy: 3.5, effect: 'pulse', rim: 0.6 });
  M.crystal_big = material({ albedo: H('#b8f5ff'), roughness: 0.1, emission: H('#7ad8ff'), emission_energy: 4, effect: 'pulse', rim: 0.8 });
  M.lamp_glow = material({ albedo: P.lamp, emission: P.lamp, emission_energy: 0.2 });
  M.orb = material({ albedo: H('#ffe6a6'), emission: H('#ffb84a'), emission_energy: 8, unshaded: true });
  M.pad = material({ albedo: H('#ff8fb1'), emission: H('#ff5f9a'), emission_energy: 2.5, effect: 'pulse' });
  M.player = material({ roughness: 0.7, rim: 0.3 });
  M.eye = material({ albedo: P.ink, roughness: 0.15, metallic: 0.1 });
  M.eye_shine = material({ emission: Col.WHITE, emission_energy: 1.5, unshaded: true });
  M.platform = material({ albedo: H('#d9d2c3'), roughness: 0.6 });
  M.dom = material({ albedo: H('#f2efe6'), roughness: 0.4, vertexColors: false });
  M.dom2 = material({ albedo: H('#4fbf8a'), roughness: 0.4, vertexColors: false });
  M.ball = material({ albedo: H('#ff8fb1'), roughness: 0.35, vertexColors: false });
  return M;
}

// ------------------------------------------------------------------ meshes
export function treeRound(seed, leafA, leafB) {
  const r = new Random(seed);
  const m = new MeshData();
  m.append(MeshData.cylinder(0.16, 0.28, 2.6, 7, P.bark), V(0, 1.3, 0));
  const blobs = [[0, 3.4, 0, 1.55], [0.75, 2.9, 0.3, 1.1], [-0.6, 3.05, -0.45, 1.15], [0.1, 4.25, -0.2, 1.0]];
  blobs.forEach((b, idx) => {
    const i = idx + 1;
    const c = leafA.lerp(leafB, r.float());
    const blob = MeshData.icosphere(b[3], 1, c);
    blob.displace((x, y, z) => { const n = Noise.perlin3(x * 1.3 + seed, y * 1.3, z * 1.3 + i) * 0.28; return [x * n, y * n * 0.6, z * n]; });
    blob.paintFn((x, y, z, cr, cg, cb) => { const t = clamp(0.75 + y / b[3] * 0.35, 0.55, 1.1); return [cr * t, cg * t, cb * t]; });
    m.append(blob, V(b[0], b[1], b[2]));
  });
  return m.flat();
}

export function treePine(seed) {
  const r = new Random(seed);
  const m = new MeshData();
  m.append(MeshData.cylinder(0.12, 0.22, 1.6, 6, P.bark_dark), V(0, 0.8, 0));
  let y = 1.2, w = 1.7;
  for (let i = 1; i <= 4; i++) {
    const c = P.pine.lerp(P.leaf, r.float(0, 0.35)).darken(0.05 * (4 - i));
    const cone = MeshData.cylinder(0.05, w, 1.7, 8, c, true);
    cone.displace((x, yy, z) => [x * r.float(-0.06, 0.06), 0, z * r.float(-0.06, 0.06)]);
    m.append(cone, V(0, y + 0.85, 0), fromY(r.float(0, 6.28)));
    y += 1.05; w *= 0.76;
  }
  return m.flat();
}

export function grassTuft() {
  const m = new MeshData();
  const r = new Random(4);
  for (let i = 1; i <= 5; i++) {
    const ang = i / 5 * Math.PI + r.float(0, 0.4);
    const h = r.float(0.35, 0.65), lean = r.float(-0.15, 0.15);
    const dx = Math.cos(ang) * 0.06, dz = Math.sin(ang) * 0.06;
    const ox = r.float(-0.12, 0.12), oz = r.float(-0.12, 0.12);
    m.color(P.grass_dark.darken(0.25));
    const a = m.vertex(ox - dx, 0, oz - dz, 0, 1, 0);
    const b = m.vertex(ox + dx, 0, oz + dz, 0, 1, 0);
    m.color(P.grass_light.lighten(0.15));
    const c = m.vertex(ox + lean, h, oz + lean * 0.5, 0, 1, 0);
    m.tri(a, b, c); m.tri(a, c, b);
  }
  return m;
}

export function flower(col) {
  const m = new MeshData();
  m.append(MeshData.cylinder(0.015, 0.02, 0.35, 4, P.grass_dark, false), V(0, 0.175, 0));
  for (let i = 0; i <= 4; i++) {
    const a = i / 5 * TAU;
    m.append(MeshData.icosphere(0.055, 0, col), V(Math.cos(a) * 0.06, 0.37, Math.sin(a) * 0.06), null, V(1, 0.4, 1));
  }
  m.append(MeshData.icosphere(0.04, 0, H('#ffd34d')), V(0, 0.39, 0));
  return m.flat();
}

export function rock(seed, size) {
  const m = MeshData.icosphere(size, 1, P.rock);
  m.displace((x, y, z) => { const n = Noise.perlin3(x * 0.9 + seed * 3.1, y * 0.9, z * 0.9 - seed) * 0.45 * size; return [x / size * n, y / size * n * 0.7, z / size * n]; });
  m.transform(null, null, V(1, 0.7, 1));
  m.paintFn((x, y, z, cr, cg, cb) => {
    const t = 0.8 + hash(x * 3, z * 3) * 0.25 + y / size * 0.15;
    if (y > size * 0.35) return [P.grass.r * t, P.grass.g * t, P.grass.b * t];
    return [cr * t, cg * t, cb * t];
  });
  return m.flat();
}

export function barrel() {
  const m = MeshData.cylinder(0.42, 0.42, 1.1, 14, P.wood);
  m.paintFn((x, y, z, r, g, b) => {
    if ((Math.abs(y) > 0.38 && Math.abs(y) < 0.46) || Math.abs(y) < 0.04) return [P.metal.r, P.metal.g, P.metal.b];
    const plank = Math.floor((Math.atan2(z, x) + Math.PI) / TAU * 14);
    const t = 0.9 + hash(plank, 1) * 0.2;
    return [r * t, g * t, b * t];
  });
  m.displace((x, y, z) => { const k = (1 - (y / 0.55) ** 2) * 0.08; return [x * k, 0, z * k]; });
  return m.smoothNormals();
}

export function crystalMesh(h = 1) {
  const m = new MeshData();
  m.append(MeshData.cylinder(0, 0.32, 0.55 * h, 6, Col.WHITE, false), V(0, 0.45 * h, 0));
  m.append(MeshData.cylinder(0.32, 0.18, 0.35 * h, 6, Col.WHITE, false), V(0, 0, 0));
  return m.flat();
}

export function lampPost() {
  const m = new MeshData();
  m.append(MeshData.cylinder(0.07, 0.1, 2.6, 8, P.metal), V(0, 1.3, 0));
  m.append(MeshData.cylinder(0.18, 0.22, 0.12, 8, P.metal), V(0, 0.06, 0));
  m.append(MeshData.cylinder(0.24, 0.12, 0.14, 8, P.metal), V(0, 2.95, 0));
  m.append(MeshData.cylinder(0.02, 0.3, 0.25, 8, P.metal), V(0, 3.25, 0));
  return m.flat();
}

export function skyIsland(seed, radius) {
  const m = new MeshData();
  const top = MeshData.cylinder(radius, radius * 0.95, 0.6, 14, P.grass);
  top.displace((x, y, z) => (y > 0 ? [0, Noise.perlin2(x * 0.4 + seed, z * 0.4) * 0.15, 0] : [0, 0, 0]));
  top.paintFn((x, y, z, cr, cg, cb) => {
    if (y < 0.2) return [P.dirt.r, P.dirt.g, P.dirt.b];
    const t = 0.9 + hash(x, z) * 0.2;
    return [cr * t, cg * t, cb * t];
  });
  m.append(top, V(0, -0.3, 0));
  const under = MeshData.cylinder(radius * 0.95, 0.3, radius * 1.6, 12, P.rock);
  under.displace((x, y, z) => { const n = Noise.perlin3(x * 0.5 + seed, y * 0.5, z * 0.5) * 0.35; return [x * n, 0, z * n]; });
  under.paintFn((x, y, z, cr, cg, cb) => { const t = 0.75 + hash(x * 2, y * 2) * 0.3; return [cr * t, cg * t, cb * t]; });
  m.append(under, V(0, -0.6 - radius * 0.8, 0));
  return m.flat();
}

export function playerParts() {
  const parts = {};
  const body = MeshData.sphere(0.5, 28, 20, P.mint);
  body.transform(null, null, V(1, 0.92, 1));
  body.paintFn((x, y, z, r, g, b) => (y < -0.15 ? [r * 0.92, g * 0.92, b * 0.92] : [r, g, b]));
  parts.body = body.geometry();
  parts.eye = MeshData.sphere(0.075, 12, 10, Col.WHITE).transform(null, null, V(0.8, 1.25, 0.5)).geometry();
  parts.shine = MeshData.sphere(0.025, 8, 6, Col.WHITE).geometry();
  parts.cheek = MeshData.sphere(0.06, 10, 8, H('#ff9db5')).transform(null, null, V(1, 0.6, 0.35)).geometry();
  parts.foot = MeshData.sphere(0.16, 14, 10, P.mint_dark).transform(null, null, V(1, 0.6, 1.3)).geometry();
  const sprout = new MeshData();
  sprout.append(MeshData.cylinder(0.025, 0.035, 0.28, 6, P.mint_dark), V(0, 0.14, 0));
  sprout.append(MeshData.sphere(0.16, 12, 8, H('#5fd18f')).transform(null, null, V(1, 0.22, 0.55)), V(0.14, 0.3, 0), euler(0, 0, 0.5));
  sprout.append(MeshData.sphere(0.12, 12, 8, H('#7fe0a6')).transform(null, null, V(1, 0.22, 0.55)), V(-0.11, 0.26, 0), euler(0, 0, -0.6));
  parts.sprout = sprout.geometry();
  return parts;
}
