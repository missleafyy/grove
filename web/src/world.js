// Builds Skylight Isle: terrain, sea, vegetation, landmarks, physics playground and collectibles (port of world.lua).
import * as THREE from 'three';
import { Col, Random, Noise, V, euler, fromY, clamp, lerp, smoothstep, TAU } from './core.js';
import { MeshData } from './mesh.js';
import * as Art from './art.js';
import * as Props from './props.js';
import { mi, node, rigid } from './props.js';
import { Particles } from './render.js';
import { Shape, addStatic } from './physics.js';
import { add, onProcess } from './game.js';

const P = Art.P;

// ------------------------------------------------------------------ terrain shape
export const zones = {
  plaza: { x: 44, z: 4, r: 15 },
  spawn: { x: 0, z: 30, r: 12 },
  ruins: { x: -34, z: -26, r: 12 },
  windmill: { x: -56, z: 22, r: 8 },
  camp: { x: 12, z: 74, r: 7 },
};
const zoneList = Object.values(zones);

function rawHeight(x, z) {
  let d = Math.sqrt(x * x + z * z) / 100;
  d += Noise.fbm2(x * 0.012 + 3.7, z * 0.012 - 1.3, 3) * 0.22;
  const mask = smoothstep(1.0, 0.6, d);
  const hills = (Noise.fbm2(x * 0.021, z * 0.021, 4) * 0.5 + 0.5) * 9;
  const mountain = Math.exp(-((x + 6) ** 2 + (z + 60) ** 2) / (2 * 19 ** 2)) * 26;
  return mask * (3 + hills + mountain) - (1 - mask) * 9;
}
for (const zn of zoneList) zn.h = rawHeight(zn.x, zn.z);
zones.plaza.h = Math.max(zones.plaza.h, 4);
zones.camp.h = 1.6;

export function height(x, z) {
  let h = rawHeight(x, z);
  for (const zn of zoneList) {
    const d = Math.sqrt((x - zn.x) ** 2 + (z - zn.z) ** 2);
    if (d < zn.r) h = lerp(h, zn.h, smoothstep(zn.r, zn.r * 0.55, d));
  }
  return h;
}

const paths = [[zones.spawn, zones.plaza], [zones.spawn, zones.ruins], [zones.spawn, zones.windmill], [zones.spawn, zones.camp]];
function pathDistance(x, z) {
  let best = 1e9;
  for (const [a, b] of paths) {
    const dx = b.x - a.x, dz = b.z - a.z;
    const t = clamp(((x - a.x) * dx + (z - a.z) * dz) / (dx * dx + dz * dz), 0, 1);
    const wx = a.x + dx * t + Math.sin(t * 9 + a.x) * 2.5 * Math.sin(t * Math.PI);
    const wz = a.z + dz * t;
    best = Math.min(best, Math.sqrt((x - wx) ** 2 + (z - wz) ** 2));
  }
  return best;
}

function slope(x, z) {
  const e = 1;
  const hx = height(x + e, z) - height(x - e, z), hz = height(x, z + e) - height(x, z - e);
  return 2 * e / Math.hypot(hx, 2 * e, hz);
}

function terrainColor(x, y, z) {
  const n = Noise.fbm2(x * 0.05, z * 0.05, 3);
  const s = slope(x, z);
  let c;
  if (y < 0.6) c = P.sand_wet.lerp(P.sand, clamp((y + 3) / 3.6, 0, 1));
  else if (y < 1.9) c = P.sand.lerp(P.grass_light, smoothstep(1.2, 1.9, y));
  else c = n > 0.08 ? P.grass.lerp(P.grass_light, clamp(n * 3, 0, 1)) : P.grass.lerp(P.grass_dark, clamp(-n * 3, 0, 1));
  if (s < 0.78 && y > 1) c = c.lerp(P.rock.lerp(P.rock_dark, clamp(n + 0.5, 0, 1)), smoothstep(0.78, 0.68, s));
  if (y > 1.5) {
    const pd = pathDistance(x, z);
    if (pd < 2.2) c = c.lerp(P.dirt, smoothstep(2.2, 1.2, pd) * 0.9);
    const zd = Math.sqrt((x - zones.ruins.x) ** 2 + (z - zones.ruins.z) ** 2);
    if (zd < 10) c = c.lerp(P.stone_dark, smoothstep(10, 8, zd) * 0.6);
  }
  return c;
}

// MultiMeshInstance3D: items are [pos, rot, scale, colour?].
function multi(parent, geo, mat, items, cast = true) {
  if (!items.length) return;
  const im = new THREE.InstancedMesh(geo, mat, items.length);
  const m = new THREE.Matrix4();
  items.forEach((it, i) => {
    m.compose(it[0], it[1], V(it[2]));
    im.setMatrixAt(i, m);
    if (it[3]) im.setColorAt(i, it[3].lin());
  });
  if (items.some((it) => it[3])) for (let i = 0; i < items.length; i++) if (!items[i][3]) im.setColorAt(i, new THREE.Color(1, 1, 1));
  im.castShadow = cast;
  im.receiveShadow = true;
  im.computeBoundingSphere();
  add(parent, im);
}

// ------------------------------------------------------------------ build
export function build(root, M) {
  const r = new Random(2024);

  // Terrain: visual mesh is faceted, collision uses the smooth grid.
  const grid = MeshData.grid(300, 300, 150, 150, height, terrainColor);
  addStatic(Shape.mesh(grid), V(0, 0, 0), null, { friction: 0.9 });
  const vis = grid.copy().flat();
  for (let k = 0; k < vis.nv; k++) { vis.uv[k * 2] = vis.p[k * 3] * 0.08; vis.uv[k * 2 + 1] = vis.p[k * 3 + 2] * 0.08; }
  add(root, mi(vis.geometry(), M.terrain, { cast_shadow: true }));

  // Sea: subdivided so the vertex waves have something to move.
  const sea = mi(MeshData.grid(2600, 2600, 260, 260).geometry(), M.water, { cast_shadow: false });
  sea.renderOrder = 2;
  add(root, sea);

  // Vegetation as instanced meshes.
  function okSpot(x, z, minH = 2.2, maxH = 40, maxSlopeY = 0.82) {
    const h = height(x, z);
    if (h < minH || h > maxH) return null;
    if (slope(x, z) < maxSlopeY) return null;
    if (pathDistance(x, z) < 3) return null;
    for (const zn of zoneList) if ((x - zn.x) ** 2 + (z - zn.z) ** 2 < (zn.r + 2) ** 2) return null;
    return h;
  }

  const treeKinds = [
    { geo: Art.treeRound(1, P.leaf, P.leaf_light).geometry(), list: [] },
    { geo: Art.treeRound(2, P.leaf_light, P.grass_light).geometry(), list: [] },
    { geo: Art.treeRound(3, P.blossom, P.blossom_light).geometry(), list: [] },
    { geo: Art.treeRound(4, P.autumn, Col.hex('#f2c14e')).geometry(), list: [] },
    { geo: Art.treePine(5).geometry(), list: [] },
  ];
  let trees = 0;
  for (let i = 0; i < 4000; i++) {
    if (trees >= 230) break;
    const x = r.float(-110, 110), z = r.float(-110, 110);
    const forest = Noise.fbm2(x * 0.03 + 11, z * 0.03 - 4, 3);
    const h = okSpot(x, z);
    if (h !== null && forest > -0.02) {
      let kind;
      if (h > 14) kind = 5;
      else if (forest > 0.25) kind = r.chance(0.5) ? 5 : 1;
      else kind = r.pick([1, 1, 2, 2, 3, 4]);
      const s = r.float(0.8, 1.35);
      treeKinds[kind - 1].list.push([V(x, h - 0.15, z), fromY(r.float(0, 6.28)), s]);
      addStatic(Shape.cylinder(0.3 * s, 3 * s), V(x, h + 1.5 * s, z));
      trees++;
    }
  }
  for (const k of treeKinds) {
    for (const t of k.list) { const tint = r.float(0.88, 1.08); t[3] = new Col(tint, tint, tint); }
    multi(root, k.geo, M.foliage, k.list);
  }

  // Grass tufts (thousands, one draw call, no shadows).
  const grass = [];
  for (let i = 0; i < 30000; i++) {
    if (grass.length >= 9000) break;
    const x = r.float(-105, 105), z = r.float(-105, 105);
    const h = height(x, z);
    if (h > 2.0 && h < 22 && slope(x, z) > 0.85 && pathDistance(x, z) > 1.8) {
      const zp = zones.plaza;
      if ((x - zp.x) ** 2 + (z - zp.z) ** 2 > 15 ** 2) {
        const c = terrainColor(x, h, z);
        grass.push([V(x, h - 0.05, z), fromY(r.float(0, 6.28)), r.float(0.7, 1.4), c.lighten(0.1)]);
      }
    }
  }
  multi(root, Art.grassTuft().geometry(), M.grass, grass, false);

  for (const col of [Col.hex('#ff8fb1'), Col.hex('#fff1a8'), Col.hex('#b9a6ff'), Col.WHITE]) {
    const list = [];
    for (let i = 0; i < 3000; i++) {
      if (list.length >= 220) break;
      const x = r.float(-90, 90), z = r.float(-90, 90);
      const h = okSpot(x, z, 2.2, 16, 0.88);
      if (h !== null && Noise.perlin2(x * 0.05 + col.r * 10, z * 0.05) > 0.15) list.push([V(x, h - 0.02, z), fromY(r.float(0, 6.28)), r.float(0.8, 1.3)]);
    }
    multi(root, Art.flower(col).geometry(), M.vertex, list, false);
  }

  // Rocks, with simple sphere colliders for the big ones.
  const rockGeo = [Art.rock(1, 1).geometry(), Art.rock(2, 1).geometry(), Art.rock(3, 1).geometry()];
  const rockLists = [[], [], []];
  for (let i = 0; i < 600; i++) {
    const x = r.float(-115, 115), z = r.float(-115, 115);
    const h = height(x, z);
    if (h > -1 && h < 30 && pathDistance(x, z) > 3 && okSpot(x, z, -1, 30, 0.6) !== null) {
      const kind = r.int(1, 3);
      if (rockLists[kind - 1].length < 28) {
        const s = r.float(0.4, 2.2);
        const rot = euler(r.float(-0.2, 0.2), r.float(0, 6.28), r.float(-0.2, 0.2));
        rockLists[kind - 1].push([V(x, h - 0.2 * s, z), rot, s]);
        if (s > 0.9) addStatic(Shape.sphere(0.75 * s), V(x, h, z));
      }
    }
  }
  rockLists.forEach((l, i) => multi(root, rockGeo[i], M.vertex, l));

  buildLandmarks(root, M, r);
}

// ------------------------------------------------------------------ landmarks
function staticMesh(root, pos, rot, shape, meshes) {
  const g = node(pos, rot);
  meshes.forEach((m) => add(g, m));
  add(root, g);
  addStatic(shape, pos, rot);
  return g;
}

export let fireflies = null;

function buildLandmarks(root, M, r) {
  const zp = zones.plaza, ph = zp.h;

  // Physics playground: tiled plaza, crate wall, barrels, dominoes.
  staticMesh(root, V(zp.x, ph - 0.5, zp.z), null, Shape.box(26, 1.2, 26), [mi(MeshData.box(26, 1.2, 26).geometry(), M.tiles)]);
  const top = ph + 0.1;
  for (let row = 0; row <= 4; row++) for (let col = 0; col <= 4 - row; col++) {
    const x = zp.x + 6 + (col - (4 - row) / 2) * 1.02;
    Props.crate(root, V(x, top + 0.5 + row * 1.0, zp.z - 6));
  }
  for (let i = 0; i <= 5; i++) {
    const a = i / 6 * TAU;
    Props.barrel(root, V(zp.x - 7 + Math.cos(a) * 1.0, top + 0.55, zp.z - 5 + Math.sin(a) * 1.0));
  }
  Props.barrel(root, V(zp.x - 7, top + 1.65, zp.z - 5));
  // Domino spiral. The meshes overlap their neighbours slightly; the colliders are narrower so the
  // solver doesn't shove them apart (and topple the lot) on the first frame.
  const domGeo = MeshData.box(0.25, 1.6, 0.8).geometry();
  for (let i = 0; i <= 26; i++) {
    const t = i / 26, a = t * Math.PI * 1.4, rad = 4.8 - t * 1.6;
    const x = zp.x - 2 + Math.cos(a) * rad, z = zp.z + 4 + Math.sin(a) * rad;
    rigid(root, { name: 'Domino', position: V(x, top + 0.8, z), rotation: fromY(-a), shape: Shape.box(0.25, 1.6, 0.5), mass: 3, friction: 0.4 },
      [mi(domGeo, i % 3 === 0 ? M.dom2 : M.dom)]);
  }
  // Big ball to roll around.
  rigid(root, { name: 'BigBall', position: V(zp.x + 4, top + 1.2, zp.z + 6), shape: Shape.sphere(1.2), mass: 30, bounce: 0.3, friction: 0.8 },
    [mi(MeshData.sphere(1, 32, 24).geometry(), M.ball, { scale: 1.2 })]);

  Props.sign(root, V(zp.x - 14, height(zp.x - 14, zp.z + 1), zp.z + 1), Math.PI / 2, 'Physics Playground');
  Props.jumpPad(root, V(zp.x + 8, top, zp.z + 8), 26);

  // Sky islands above the playground, linked by moving platforms.
  const base = V(zp.x + 8, top, zp.z + 8);
  const i1 = base.clone().add(V(-2, 12.5, -12));
  const i2 = base.clone().add(V(-22, 15, -26));
  const i3 = base.clone().add(V(-30, 24, -46));
  for (const [pos, rad, seed] of [[i1, 5, 11], [i2, 4.5, 12], [i3, 6, 13]]) {
    const md = Art.skyIsland(seed, rad);
    staticMesh(root, pos, null, Shape.convex(md), [mi(md.geometry(), M.vertex)]);
  }
  Props.movingPlatform(root, i1.clone().add(V(-5, 0, -4)), i2.clone().add(V(5, -1, 5)), 7, 0);
  Props.movingPlatform(root, i2.clone().add(V(-2, 0, -6)), i3.clone().add(V(3, -1.5, 7)), 8, 0.25);
  Props.crystal(root, i1.clone().add(V(1, 1.2, 1)));
  Props.crystal(root, i2.clone().add(V(0, 1.2, 0)));
  Props.crystal(root, i3.clone().add(V(0, 1.8, 0)), true);
  add(root, mi(Art.treePine(77).geometry(), M.foliage, { position: i3.clone().add(V(-2.5, -0.2, -2)), scale: 1.1 }));
  add(root, mi(Art.treeRound(78, P.blossom, P.blossom_light).geometry(), M.foliage, { position: i2.clone().add(V(1.8, -0.1, -1.5)), scale: 0.8 }));

  // Ancient ruins: a ring of pillars around an altar.
  const zr = zones.ruins;
  for (let i = 0; i <= 9; i++) {
    const a = i / 10 * TAU;
    const x = zr.x + Math.cos(a) * 8, z = zr.z + Math.sin(a) * 8;
    const broken = i === 3 || i === 7;
    if (i !== 5) Props.pillar(root, V(x, height(x, z) - 0.2, z), broken ? r.float(1.2, 2.2) : 4.4, broken);
  }
  // One pillar has fallen over and can be pushed.
  rigid(root, { name: 'FallenPillar', position: V(zr.x + 3, zr.h + 0.65, zr.z + 9), rotation: euler(0, 0.4, Math.PI / 2), shape: Shape.cylinder(0.6, 3.2), mass: 80 },
    [mi(Props.meshes.pillar, M.vertex, { scale: V(1, 3.2, 1) })]);
  staticMesh(root, V(zr.x, zr.h + 0.4, zr.z), null, Shape.box(3, 1, 3), [mi(MeshData.box(3, 1, 3, P.stone_dark).flat().geometry(), M.vertex)]);
  Props.crystal(root, V(zr.x, zr.h + 1.6, zr.z));
  Props.sign(root, V(zr.x + 9, height(zr.x + 9, zr.z + 9), zr.z + 9), -0.6, 'Ancient Ruins');

  // Windmill on the west hill.
  const zw = zones.windmill;
  const wpos = V(zw.x, zw.h - 0.2, zw.z);
  const wm = staticMesh(root, wpos, null, Shape.offset(Shape.cylinder(2.0, 9), V(0, 4.5, 0)), [
    mi(MeshData.cylinder(1.4, 2.3, 9, 12, P.white).flat().geometry(), M.vertex, { position: V(0, 4.5, 0) }),
    mi(MeshData.cone(2.0, 3, 12, P.roof).flat().geometry(), M.vertex, { position: V(0, 10.5, 0) }),
    mi(MeshData.box(1.0, 1.8, 0.2, P.wood_dark).geometry(), M.vertex, { position: V(0, 0.9, -2.25) }),
  ]);
  const blades = new MeshData();
  for (let i = 0; i <= 3; i++) {
    const q = euler(0, 0, i * Math.PI / 2);
    blades.append(MeshData.box(0.35, 6, 0.08, P.wood), V(0, 3.2, 0).applyQuaternion(q), q);
    blades.append(MeshData.box(1.3, 4.8, 0.04, P.white), V(0.75, 3.6, 0.02).applyQuaternion(q), q);
  }
  blades.append(MeshData.cylinder(0.35, 0.35, 0.6, 10, P.wood_dark), null, euler(Math.PI / 2, 0, 0));
  const bladeMesh = add(wm, mi(blades.flat().geometry(), M.vertex, { position: V(0, 8.4, -2.0) }));
  onProcess(bladeMesh, (dt) => bladeMesh.rotateZ(dt * 0.8));
  Props.crystal(wm, V(0, 12.6, 0));
  Props.sign(root, V(zw.x + 6, height(zw.x + 6, zw.z + 6), zw.z + 6), 0.8, 'Windmill Hill');
  // Steps up to the windmill crystal: a spiral of floating stones.
  const stoneGeo = MeshData.box(1.6, 0.4, 1.6, P.stone).flat().geometry();
  for (let i = 0; i <= 8; i++) {
    const a = i / 9 * TAU * 1.1 + 0.6;
    staticMesh(root, V(zw.x + Math.cos(a) * 3.6, zw.h + 1.0 + i * 1.25, zw.z + Math.sin(a) * 3.6), null, Shape.box(1.6, 0.4, 1.6), [mi(stoneGeo, M.vertex)]);
  }

  // Beach campfire.
  const zc = zones.camp;
  Props.campfire(root, V(zc.x, zc.h, zc.z));
  const logGeo = MeshData.box(1.8, 0.5, 0.5, P.bark).flat().geometry();
  for (let i = 0; i <= 2; i++) {
    const a = i / 3 * TAU + 0.4;
    staticMesh(root, V(zc.x + Math.cos(a) * 2.6, zc.h + 0.25, zc.z + Math.sin(a) * 2.6), fromY(-a + Math.PI / 2), Shape.box(1.8, 0.5, 0.5), [mi(logGeo, M.vertex)]);
  }
  Props.crystal(root, V(zc.x - 3, zc.h + 1, zc.z + 3));

  // Lamp posts along the paths.
  for (const [a, b] of paths) {
    for (let t = 0.2; t <= 0.9 + 1e-9; t += 0.23) {
      const x = a.x + (b.x - a.x) * t + 2.6, z = a.z + (b.z - a.z) * t;
      const h = height(x, z);
      if (h > 1.5) Props.lamp(root, V(x, h - 0.1, z));
    }
  }

  // Remaining crystals scattered around the island.
  for (const s of [V(-6, 0, 18), V(26, 0, 36), V(-60, 0, -12), V(-6, 0, -60), V(64, 0, -30), V(-30, 0, 58)]) {
    Props.crystal(root, V(s.x, height(s.x, s.z) + 1.0, s.z));
  }

  // Fireflies drift over the meadow at night.
  fireflies = add(root, new Particles({ position: V(0, zones.spawn.h + 1.5, 20), emit_box: [40, 1.5, 40],
    rate: 0, lifetime: 6, speed: 0.3, spread: 180, size: 0.07, size_end: 0.07, amount: 400,
    color: new Col(0.85, 1, 0.5, 1), color_end: new Col(0.8, 1, 0.4, 0), turbulence: 2.5 }));

  Props.sign(root, V(6, height(6, 20), 20), 0.3, 'Welcome to Skylight Isle');
}
