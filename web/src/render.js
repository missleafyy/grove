// Rendering on top of three.js, matching Grove's look: its ambient/fog/sky maths are injected into
// MeshStandardMaterial, plus the procedural sky, CPU particles, a pooled point-light set and Grove's
// tonemap/bloom composite.
import * as THREE from 'three';
import { EffectComposer } from 'three/examples/jsm/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/examples/jsm/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/examples/jsm/postprocessing/UnrealBloomPass.js';
import { ShaderPass } from 'three/examples/jsm/postprocessing/ShaderPass.js';
import { Col, clamp, smoothstep } from './core.js';

// Shared environment uniforms (all linear), updated by the day/night cycle.
export const U = {
  uTime: { value: 0 },
  uSkyTop: { value: new THREE.Color(0.28, 0.52, 0.86) },
  uSkyHor: { value: new THREE.Color(0.72, 0.82, 0.92) },
  uGround: { value: new THREE.Color(0.35, 0.33, 0.3) },
  uSunDir: { value: new THREE.Vector3(-0.4, -0.8, -0.35).normalize() },
  uSunColor: { value: new THREE.Color(2.5, 2.3, 2.1) },
  uMoonDir: { value: new THREE.Vector3(0.3, -0.6, 0.74).normalize() },
  uAmb: { value: 0.9 },
  uRefl: { value: 0.6 },
  uFogColor: { value: new THREE.Color(0.72, 0.82, 0.92) },
  uFogDensity: { value: 0.004 },
  uFogScatter: { value: 0.4 },
  uStars: { value: 0 },
  uClouds: { value: 0.45 },
};

// Grove treats point lights as E * (1 - x^4)^2 / (1 + 0.35 d^2); swap three's inverse-square falloff for that.
THREE.ShaderChunk.lights_pars_begin = THREE.ShaderChunk.lights_pars_begin.replace(
  /float getDistanceAttenuation\([\s\S]*?\n}/,
  `float getDistanceAttenuation( const in float lightDistance, const in float cutoffDistance, const in float decayExponent ) {
  if ( cutoffDistance <= 0.0 ) return 1.0;
  float x = lightDistance / cutoffDistance;
  float att = saturate( 1.0 - x * x * x * x );
  return att * att / ( 1.0 + lightDistance * lightDistance * 0.35 );
}`);

const COMMON_GLSL = /* glsl */`
uniform float uTime;
uniform vec3 uSkyTop, uSkyHor, uGround, uSunDir, uSunColor, uFogColor;
uniform float uAmb, uRefl, uFogDensity, uFogScatter;
float gHash12(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float gVnoise(vec2 p) {
  vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(gHash12(i), gHash12(i + vec2(1, 0)), u.x), mix(gHash12(i + vec2(0, 1)), gHash12(i + vec2(1, 1)), u.x), u.y);
}
vec3 gHemi(vec3 n) { return n.y > 0.0 ? mix(uSkyHor, uSkyTop, n.y) : mix(uSkyHor, uGround, min(-n.y * 2.0, 1.0)); }
vec3 gSkyGrad(vec3 d) {
  vec3 c = d.y >= 0.0 ? mix(uSkyHor, uSkyTop, pow(d.y, 0.55)) : mix(uSkyHor, uGround, clamp(-d.y * 6.0, 0.0, 1.0));
  vec3 L = -uSunDir; float sd = max(dot(d, L), 0.0);
  c += uSunColor * (pow(sd, 8.0) * 0.12 + pow(sd, 64.0) * 0.25) * clamp(L.y * 4.0 + 0.6, 0.0, 1.0);
  return c;
}
vec3 gFog(vec3 col, vec3 world) {
  vec3 dv = world - cameraPosition; float dist = length(dv);
  float f = 1.0 - exp(-dist * uFogDensity);
  float sun = pow(max(dot(dv / max(dist, 1e-4), -uSunDir), 0.0), 8.0);
  return mix(col, uFogColor + uSunColor * sun * uFogScatter, clamp(f, 0.0, 1.0));
}
float gWaterH(vec2 p, float t) {
  return sin(p.x * 0.35 + t * 1.1) * 0.12 + sin(p.y * 0.45 - t * 0.9) * 0.1 + sin((p.x + p.y) * 0.9 + t * 1.7) * 0.04;
}
vec3 gWaterN(vec2 p, float t) {
  float e = 0.05; float h = gWaterH(p, t);
  vec3 n = normalize(vec3(h - gWaterH(p + vec2(e, 0), t), e, h - gWaterH(p + vec2(0, e), t)));
  vec2 q = p * 1.7 + vec2(t * 0.3, t * 0.2);
  float r1 = gVnoise(q), r2 = gVnoise(q + vec2(0.13, 0.0)), r3 = gVnoise(q + vec2(0.0, 0.13));
  n.xz += vec2(r1 - r2, r1 - r3) * 1.4;
  return normalize(n);
}
`;

// Material factory. opts mirrors Grove's Material: albedo (Col), roughness, metallic, emission (Col),
// emission_energy, wind, rim, effect ('water' | 'pulse'), transparent, map, unshaded, vertexColors.
export function material(o = {}) {
  const albedo = o.albedo || Col.WHITE;
  if (o.unshaded) {
    const e = o.emission ? o.emission.lin(o.emission_energy ?? 1) : new THREE.Color(0, 0, 0);
    return new THREE.MeshBasicMaterial({ color: albedo.lin().add(e), fog: false });
  }
  const m = new THREE.MeshStandardMaterial({
    color: albedo.lin(), roughness: o.roughness ?? 0.5, metalness: o.metallic ?? 0,
    vertexColors: o.vertexColors !== false, map: o.map || null,
    transparent: !!o.transparent, opacity: albedo.a, fog: false,
  });
  if (o.emission) { m.emissive = o.emission.lin(); m.emissiveIntensity = o.emission_energy ?? 1; }
  const rim = { value: o.rim || 0 };
  m.userData.rim = rim;
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, U, { uRim: rim, uWind: { value: o.wind || 0 } });
    const defs = (o.wind ? '#define G_WIND\n' : '') + (o.effect === 'water' ? '#define G_WATER\n' : '') +
      (o.effect === 'pulse' ? '#define G_PULSE\n' : '') + (o.rim ? '#define G_RIM\n' : '');
    sh.vertexShader = defs + 'varying vec3 vGWorld;\nuniform float uWind;\n' + sh.vertexShader
      .replace('#include <common>', '#include <common>\n' + COMMON_GLSL)
      .replace('#include <begin_vertex>', `#include <begin_vertex>
#ifdef G_WATER
  transformed.y += gWaterH((modelMatrix * vec4(transformed, 1.0)).xz, uTime);
#endif`)
      .replace('#include <project_vertex>', `
  mat4 gM = modelMatrix;
#ifdef USE_INSTANCING
  gM = modelMatrix * instanceMatrix;
#endif
  vec4 gwp = gM * vec4(transformed, 1.0);
#ifdef G_WIND
  { float h = max(position.y, 0.0);
    float ph = dot(gM[3].xz, vec2(0.37, 0.21)) + dot(gwp.xz, vec2(0.6, 0.4));
    float gust = 0.6 + 0.4 * sin(uTime * 0.4 + gM[3].x * 0.05);
    gwp.x += sin(uTime * 1.7 + ph) * uWind * h * h * 0.04 * gust;
    gwp.z += cos(uTime * 1.3 + ph * 1.3) * uWind * h * h * 0.03 * gust; }
#endif
  vGWorld = gwp.xyz;
  vec4 mvPosition = viewMatrix * gwp;
  gl_Position = projectionMatrix * mvPosition;`);
    sh.fragmentShader = defs + 'varying vec3 vGWorld;\nuniform float uRim;\n' + sh.fragmentShader
      .replace('#include <common>', '#include <common>\n' + COMMON_GLSL)
      .replace('#include <normal_fragment_maps>', `#include <normal_fragment_maps>
#ifdef G_WATER
  normal = normalize((viewMatrix * vec4(gWaterN(vGWorld.xz, uTime), 0.0)).xyz);
#endif`)
      .replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>
#ifdef G_PULSE
  { vec3 wn = inverseTransformDirection(normal, viewMatrix); vec3 wv = normalize(cameraPosition - vGWorld);
    float pulse = 0.65 + 0.35 * sin(uTime * 3.0 + vGWorld.y * 3.0);
    float fres = pow(1.0 - max(dot(wn, wv), 0.0), 2.0);
    totalEmissiveRadiance *= pulse * (0.6 + fres * 1.6); }
#endif`)
      .replace('#include <opaque_fragment>', `
  { vec3 gN = inverseTransformDirection(normal, viewMatrix);
    vec3 gV = normalize(cameraPosition - vGWorld);
    float ndv = max(dot(gN, gV), 1e-4);
    float rough = clamp(roughnessFactor, 0.04, 1.0);
    float metal = metalnessFactor;
    vec3 f0 = mix(vec3(0.04), diffuseColor.rgb, metal);
    vec3 Fr = f0 + (max(vec3(1.0 - rough), f0) - f0) * pow(1.0 - ndv, 5.0);
    vec3 hemi = gHemi(gN);
    vec3 R = reflect(-gV, gN);
    vec3 env = mix(gSkyGrad(R), gHemi(R), rough);
    outgoingLight += hemi * diffuseColor.rgb * (1.0 - metal) * (1.0 - Fr * 0.5) * uAmb;
    outgoingLight += env * Fr * (1.0 - rough * 0.7) * uRefl;
#ifdef G_RIM
    outgoingLight += (hemi + uSunColor * 0.3) * pow(1.0 - ndv, 3.0) * uRim;
#endif
#ifdef G_WATER
    diffuseColor.a = mix(diffuseColor.a, 1.0, pow(1.0 - ndv, 4.0));
#endif
    outgoingLight = gFog(outgoingLight, vGWorld); }
#include <opaque_fragment>`);
  };
  m.customProgramCacheKey = () => JSON.stringify([o.wind ? 1 : 0, o.effect || '', o.rim ? 1 : 0]);
  return m;
}

// Texture.generate(w, h, fn(x, y, u, v) -> r, g, b, a)
export function genTexture(w, h, fn, repeat = 1) {
  const data = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const c = fn(x, y, (x + 0.5) / w, (y + 0.5) / h);
    for (let j = 0; j < 4; j++) data[(y * w + x) * 4 + j] = clamp(Math.round(c[j] * 255), 0, 255);
  }
  const t = new THREE.DataTexture(data, w, h, THREE.RGBAFormat);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(repeat, repeat);
  t.magFilter = THREE.LinearFilter; t.minFilter = THREE.LinearMipmapLinearFilter; t.generateMipmaps = true;
  t.anisotropy = 8;
  t.needsUpdate = true;
  return t;
}

// ------------------------------------------------------------------ sky
export function makeSky() {
  const mat = new THREE.ShaderMaterial({
    uniforms: { ...U, uMoonDir: U.uMoonDir, uStars: U.uStars, uClouds: U.uClouds },
    depthWrite: false, side: THREE.BackSide,
    vertexShader: `varying vec3 vDir; void main() { vDir = position; vec4 p = projectionMatrix * modelViewMatrix * vec4(position, 1.0); gl_Position = p.xyww; }`,
    fragmentShader: COMMON_GLSL + `
uniform vec3 uMoonDir; uniform float uStars, uClouds;
varying vec3 vDir;
float hash13(vec3 p3) { p3 = fract(p3 * 0.1031); p3 += dot(p3, p3.zyx + 31.32); return fract((p3.x + p3.y) * p3.z); }
float fbm(vec2 p) { float s = 0.0, a = 0.5; for (int i = 0; i < 5; i++) { s += a * gVnoise(p); p = p * 2.03 + vec2(17.1, 9.2); a *= 0.5; } return s; }
void main() {
  vec3 d = normalize(vDir);
  vec3 col = gSkyGrad(d);
  vec3 L = -uSunDir;
  float above = smoothstep(-0.02, 0.05, d.y);
  if (uStars > 0.0 && d.y > 0.0) {
    vec3 sp = d * 300.0; vec3 cell = floor(sp); float h = hash13(cell);
    if (h > 0.997) {
      vec3 c = cell + 0.5 + (vec3(hash13(cell + 1.3), hash13(cell + 2.7), hash13(cell + 4.1)) - 0.5) * 0.6;
      float tw = 0.6 + 0.4 * sin(uTime * (2.0 + h * 40.0) + h * 100.0);
      col += vec3(0.9, 0.95, 1.0) * smoothstep(0.35, 0.0, length(sp - c)) * uStars * tw * 3.0 * above;
    }
  }
  float md = dot(d, -uMoonDir);
  if (md > 0.0) {
    col += vec3(0.85, 0.9, 1.0) * smoothstep(0.9993, 0.9996, md) * 2.0 * uStars;
    col += vec3(0.3, 0.35, 0.5) * pow(md, 200.0) * 0.4 * uStars;
  }
  float sd = dot(d, L);
  col += uSunColor * smoothstep(1.0 - 0.0012, 1.0 - 0.0009, sd) * 12.0 * above;
  if (uClouds > 0.0 && d.y > 0.0) {
    vec2 uv = d.xz / (d.y + 0.12) * 1.6 + vec2(uTime * 0.02, uTime * 0.007);
    float n = fbm(uv);
    float cover = smoothstep(1.0 - uClouds, 1.0 - uClouds + 0.35, n);
    float light = clamp(fbm(uv + L.xz * 0.08) - n + 0.55, 0.0, 1.0);
    vec3 lit = mix(uSkyHor * 0.9, vec3(1.0), 0.5) * (uSunColor * 0.35 + gHemi(vec3(0, 1, 0)) * 0.9);
    vec3 cc = mix(lit * 0.55, lit * 1.15, light);
    cc += uSunColor * pow(max(sd, 0.0), 12.0) * 0.6;
    col = mix(col, cc, cover * smoothstep(0.0, 0.25, d.y) * 0.95);
  }
  float hz = pow(1.0 - abs(d.y), 10.0);
  col = mix(col, uFogColor, clamp(hz * min(uFogDensity * 120.0, 1.0), 0.0, 1.0));
  gl_FragColor = vec4(col, 1.0);
}`,
  });
  const sky = new THREE.Mesh(new THREE.SphereGeometry(1000, 48, 24), mat);
  sky.frustumCulled = false;
  sky.renderOrder = -10;
  return sky;
}

// ------------------------------------------------------------------ particles
// Grove's CPU particle system: world-space billboards with cone emission, gravity, damping, turbulence.
const particleSystems = new Set();
let particleScale = { value: 500 };
const PARTICLE_VS = `
attribute vec4 aColor; attribute float aSize;
uniform float uScale;
varying vec4 vColor; varying vec3 vW;
void main() {
  vColor = vec4(pow(max(aColor.rgb, vec3(0.0)), vec3(2.2)), aColor.a);
  vW = position;
  vec4 mv = viewMatrix * vec4(position, 1.0);
  gl_Position = projectionMatrix * mv;
  gl_PointSize = aSize * 2.0 * uScale / max(-mv.z, 0.05);
}`;
const PARTICLE_FS = `
uniform float uFogDensity;
varying vec4 vColor; varying vec3 vW;
void main() {
  vec2 c = gl_PointCoord * 2.0 - 1.0;
  float r = dot(c, c);
  if (r > 1.0) discard;
  float a = pow(1.0 - r, 1.6);
  vec4 col = vColor * vec4(1.0, 1.0, 1.0, a);
  float f = 1.0 - exp(-length(vW - cameraPosition) * uFogDensity);
  col.a *= 1.0 - clamp(f, 0.0, 1.0) * 0.8;
  gl_FragColor = vec4(col.rgb * col.a, col.a);
}`;

const pdefaults = {
  emitting: true, additive: true, amount: 200, rate: 30, lifetime: 1.5, lifetime_random: 0.3,
  emit_box: [0, 0, 0], emit_radius: 0, direction: [0, 1, 0], spread: 30, speed: 2, speed_random: 0.3,
  gravity: [0, 0, 0], damping: 0, color: new Col(1, 1, 1, 1), color_end: new Col(1, 1, 1, 0),
  size: 0.15, size_end: 0.05, turbulence: 0, one_shot: false, auto_free: false,
};

export class Particles extends THREE.Object3D {
  constructor(opts) {
    super();
    const { position, ...rest } = opts;
    Object.assign(this, pdefaults, rest);
    if (position) this.position.copy(position);
    this.max = this.amount;
    this.ps = [];
    this.accum = 0;
    this.burst = 0;
    if (this.one_shot) { this.burst = this.amount; this.emitting = false; this.bornAt = null; }
    const g = new THREE.BufferGeometry();
    this.aPos = new Float32Array(this.max * 3);
    this.aCol = new Float32Array(this.max * 4);
    this.aSize = new Float32Array(this.max);
    g.setAttribute('position', new THREE.BufferAttribute(this.aPos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('aColor', new THREE.BufferAttribute(this.aCol, 4).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('aSize', new THREE.BufferAttribute(this.aSize, 1).setUsage(THREE.DynamicDrawUsage));
    const mat = new THREE.ShaderMaterial({
      uniforms: { uScale: particleScale, uFogDensity: U.uFogDensity }, vertexShader: PARTICLE_VS, fragmentShader: PARTICLE_FS,
      transparent: true, depthWrite: false,
      blending: THREE.CustomBlending,
    });
    // The shader outputs premultiplied colour.
    mat.blendSrc = THREE.OneFactor;
    mat.blendDst = this.additive ? THREE.OneFactor : THREE.OneMinusSrcAlphaFactor;
    this.points = new THREE.Points(g, mat);
    this.points.frustumCulled = false;
    this.points.renderOrder = 5;
    this.wp = new THREE.Vector3();
  }
  onAdded(scene) { scene.add(this.points); particleSystems.add(this); }
  dispose() {
    particleSystems.delete(this);
    this.points.removeFromParent();
    this.points.geometry.dispose(); this.points.material.dispose();
    this.removeFromParent();
  }
  spawn() {
    if (this.ps.length >= this.max) return;
    const c = this.wp, eb = this.emit_box;
    const p = [c.x + (Math.random() * 2 - 1) * eb[0], c.y + (Math.random() * 2 - 1) * eb[1], c.z + (Math.random() * 2 - 1) * eb[2]];
    if (this.emit_radius > 0) {
      let r; do { r = [Math.random() * 2 - 1, Math.random() * 2 - 1, Math.random() * 2 - 1]; } while (r[0] * r[0] + r[1] * r[1] + r[2] * r[2] > 1);
      for (let j = 0; j < 3; j++) p[j] += r[j] * this.emit_radius;
    }
    const d = new THREE.Vector3(...this.direction).normalize();
    const spread = this.spread * Math.PI / 180;
    const cz = 1 - Math.random() * (1 - Math.cos(spread));
    const phi = Math.random() * Math.PI * 2;
    const sz = Math.sqrt(Math.max(0, 1 - cz * cz));
    const t = Math.abs(d.y) < 0.99 ? new THREE.Vector3().crossVectors(d, new THREE.Vector3(0, 1, 0)).normalize() : new THREE.Vector3(1, 0, 0);
    const b = new THREE.Vector3().crossVectors(d, t);
    const dir = d.multiplyScalar(cz).addScaledVector(t, sz * Math.cos(phi)).addScaledVector(b, sz * Math.sin(phi));
    const sp = this.speed * (1 + (Math.random() * 2 - 1) * this.speed_random);
    this.ps.push({ p, v: [dir.x * sp, dir.y * sp, dir.z * sp], age: 0, life: Math.max(0.01, this.lifetime * (1 + (Math.random() * 2 - 1) * this.lifetime_random)) });
  }
  update(dt, rtime) {
    this.getWorldPosition(this.wp);
    const vis = this.parent && isVisible(this);
    if (this.emitting && vis) {
      this.accum += this.rate * dt;
      while (this.accum >= 1) { this.spawn(); this.accum -= 1; }
    } else this.accum = 0;
    if (this.burst > 0) { while (this.burst > 0) { this.spawn(); this.burst--; } this.bornAt = rtime; }
    const g = this.gravity, damp = Math.exp(-this.damping * dt), tt = rtime * 1.3;
    const ps = this.ps;
    for (let i = 0; i < ps.length;) {
      const p = ps[i];
      p.age += dt;
      if (p.age >= p.life) { ps[i] = ps[ps.length - 1]; ps.pop(); continue; }
      for (let j = 0; j < 3; j++) p.v[j] = (p.v[j] + g[j] * dt) * damp;
      if (this.turbulence > 0) {
        p.v[0] += Math.sin(p.p[1] * 1.7 + tt + i) * this.turbulence * dt;
        p.v[1] += Math.sin(p.p[2] * 1.3 + tt * 1.1) * this.turbulence * dt;
        p.v[2] += Math.sin(p.p[0] * 1.5 + tt * 0.9) * this.turbulence * dt;
      }
      for (let j = 0; j < 3; j++) p.p[j] += p.v[j] * dt;
      i++;
    }
    const a = this.color, e = this.color_end;
    for (let i = 0; i < ps.length; i++) {
      const p = ps[i], k = p.age / p.life;
      this.aPos[i * 3] = p.p[0]; this.aPos[i * 3 + 1] = p.p[1]; this.aPos[i * 3 + 2] = p.p[2];
      this.aCol[i * 4] = a.r + (e.r - a.r) * k; this.aCol[i * 4 + 1] = a.g + (e.g - a.g) * k;
      this.aCol[i * 4 + 2] = a.b + (e.b - a.b) * k; this.aCol[i * 4 + 3] = a.a + (e.a - a.a) * k;
      this.aSize[i] = this.size + (this.size_end - this.size) * k;
    }
    const geo = this.points.geometry;
    geo.setDrawRange(0, ps.length);
    for (const n of ['position', 'aColor', 'aSize']) { geo.attributes[n].needsUpdate = true; geo.attributes[n].addUpdateRange(0, ps.length * (n === 'position' ? 3 : n === 'aColor' ? 4 : 1)); }
    if (this.auto_free && this.bornAt !== null && rtime - this.bornAt > 0.2 && ps.length === 0) this.dispose();
  }
}
function isVisible(o) { for (let n = o; n; n = n.parent) if (!n.visible) return false; return true; }
export function updateParticles(dt, rtime) { for (const p of [...particleSystems]) p.update(dt, rtime); }
export function particleCount() { let n = 0; for (const p of particleSystems) n += p.ps.length; return n; }

// ------------------------------------------------------------------ point light pool
// Grove has dozens of lights (lamps, crystals, orbs, campfire). Three recompiles shaders when the
// light count changes, so keep a fixed pool and hand it to the lights nearest the camera each frame.
export const virtualLights = new Set();
export class VLight {
  constructor(obj, color, energy, range) { this.obj = obj; this.color = color; this.energy = energy; this.range = range; this.wp = new THREE.Vector3(); }
}
const POOL = 10;
const pool = [];
export function initLightPool(scene) {
  for (let i = 0; i < POOL; i++) {
    const l = new THREE.PointLight(0xffffff, 0, 1, 2);
    scene.add(l);
    pool.push(l);
  }
}
export function updateLightPool(camPos) {
  const cand = [];
  for (const v of virtualLights) {
    if (v.energy <= 0.01 || !isVisible(v.obj) || !v.obj.parent) continue;
    v.obj.getWorldPosition(v.wp);
    const d = v.wp.distanceTo(camPos);
    if (d > 70 + v.range) continue;
    v.score = v.energy * v.range / (1 + d * d * 0.02);
    cand.push(v);
  }
  cand.sort((a, b) => b.score - a.score);
  for (let i = 0; i < POOL; i++) {
    const l = pool[i], v = cand[i];
    if (!v) { l.intensity = 0; continue; }
    l.position.copy(v.wp);
    l.distance = v.range;
    l.color.copy(v.color);
    // E * PI cancels three's Lambert 1/PI so the result matches Grove; fade the weakest slot to hide swaps.
    const fade = i === POOL - 1 ? 0.5 : 1;
    l.intensity = v.energy * Math.PI * fade;
  }
}

// ------------------------------------------------------------------ renderer + post
const COMPOSITE = {
  uniforms: { tDiffuse: { value: null }, uExposure: { value: 1 }, uTime: U.uTime },
  vertexShader: `varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
  fragmentShader: `
uniform sampler2D tDiffuse; uniform float uExposure; uniform float uTime; varying vec2 vUv;
vec3 aces(vec3 x) {
  const mat3 m1 = mat3(0.59719, 0.07600, 0.02840, 0.35458, 0.90834, 0.13383, 0.04823, 0.01566, 0.83777);
  const mat3 m2 = mat3(1.60475, -0.10208, -0.00327, -0.53108, 1.10813, -0.07276, -0.07367, -0.00605, 1.07602);
  vec3 v = m1 * x; vec3 a = v * (v + 0.0245786) - 0.000090537; vec3 b = v * (0.983729 * v + 0.4329510) + 0.238081;
  return clamp(m2 * (a / b), 0.0, 1.0);
}
void main() {
  vec3 c = aces(texture2D(tDiffuse, vUv).rgb * uExposure);
  float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
  c = mix(vec3(l), c, 1.05);
  c = pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
  c = (c - 0.5) * 1.03 + 0.5;
  vec2 q = vUv - 0.5;
  c *= 1.0 - dot(q, q) * 0.25 * 1.6;
  float n = fract(sin(dot(gl_FragCoord.xy + fract(uTime) * 61.0, vec2(12.9898, 78.233))) * 43758.5453);
  gl_FragColor = vec4(c + (n - 0.5) / 255.0, 1.0);
}`,
};

export function createRenderer(canvas) {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance', preserveDrawingBuffer: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.toneMapping = THREE.NoToneMapping;
  const size = new THREE.Vector2();
  renderer.getDrawingBufferSize(size);
  const rt = new THREE.WebGLRenderTarget(size.x, size.y, { type: THREE.HalfFloatType, samples: 4 });
  const composer = new EffectComposer(renderer, rt);
  return { renderer, composer };
}

export function setupPost(composer, scene, camera) {
  composer.addPass(new RenderPass(scene, camera));
  const bloom = new UnrealBloomPass(new THREE.Vector2(256, 256), 0.3, 0.55, 1.0);
  composer.addPass(bloom);
  const comp = new ShaderPass(COMPOSITE);
  composer.addPass(comp);
  return { bloom, comp };
}

export function setParticleScale(heightPx, fovDeg) {
  particleScale.value = heightPx / (2 * Math.tan(fovDeg * Math.PI / 360));
}
export { smoothstep };
