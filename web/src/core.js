// Core helpers ported from Grove's math3d.lua: seeded Random, Perlin noise, math extras, colours.
// Random and Noise match the engine bit-for-bit so the island generates identically.
import * as THREE from 'three';

export const TAU = Math.PI * 2;
export const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
export const lerp = (a, b, t) => a + (b - a) * t;
export const smoothstep = (a, b, v) => { const t = clamp((v - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
export const damp = (a, b, speed, dt) => a + (b - a) * (1 - Math.exp(-speed * dt));
export const wrapAngle = (a) => { a = (a + Math.PI) % TAU; if (a < 0) a += TAU; return a - Math.PI; };
export const lerpAngle = (a, b, t) => a + wrapAngle(b - a) * t;
const lmod = (a, n) => ((a % n) + n) % n;   // Lua-style modulo

// ------------------------------------------------------------------ random (xorshift32)
export class Random {
  constructor(seed) { this.state = (lmod(Math.floor(seed), 2147483646) + 1) | 0; }
  next() {
    let x = this.state;
    x ^= x << 13; x ^= x >>> 17; x ^= x << 5;
    this.state = x | 0;
    return (x >>> 0) / 4294967296;
  }
  float(a, b) {
    const r = this.next();
    if (a === undefined) return r;
    if (b === undefined) return r * a;
    return a + (b - a) * r;
  }
  int(a, b) { return Math.floor(this.float(a, b + 1)); }
  pick(t) { return t[this.int(1, t.length) - 1]; }
  chance(p) { return this.float() < p; }
}
export const rng = new Random(1337);

// ------------------------------------------------------------------ noise
const perm = new Int32Array(512);
(function seed(s) {
  const r = new Random(s);
  const p = [];
  for (let i = 0; i <= 255; i++) p[i] = i;
  for (let i = 255; i >= 1; i--) { const j = r.int(0, i); const t = p[i]; p[i] = p[j]; p[j] = t; }
  for (let i = 0; i < 512; i++) perm[i] = p[i % 256];
})(0);
const fade = (t) => t * t * t * (t * (t * 6 - 15) + 10);
function grad2(h, x, y) {
  h = h % 8;
  const u = h < 4 ? x : y, v = h < 4 ? y : x;
  return ((h % 2) === 0 ? u : -u) + ((Math.floor(h / 2) % 2) === 0 ? v : -v);
}
function grad3(h, x, y, z) {
  h = h % 16;
  const u = h < 8 ? x : y;
  const v = h < 4 ? y : ((h === 12 || h === 14) ? x : z);
  return ((h % 2) === 0 ? u : -u) + ((Math.floor(h / 2) % 2) === 0 ? v : -v);
}
export const Noise = {
  perlin2(x, y) {
    let xi = Math.floor(x), yi = Math.floor(y);
    const xf = x - xi, yf = y - yi;
    xi = lmod(xi, 256); yi = lmod(yi, 256);
    const u = fade(xf), v = fade(yf);
    const aa = perm[perm[xi] + yi], ab = perm[perm[xi] + yi + 1];
    const ba = perm[perm[xi + 1] + yi], bb = perm[perm[xi + 1] + yi + 1];
    const x1 = grad2(aa, xf, yf) + (grad2(ba, xf - 1, yf) - grad2(aa, xf, yf)) * u;
    const x2 = grad2(ab, xf, yf - 1) + (grad2(bb, xf - 1, yf - 1) - grad2(ab, xf, yf - 1)) * u;
    return (x1 + (x2 - x1) * v) * 0.7;
  },
  perlin3(x, y, z) {
    let xi = Math.floor(x), yi = Math.floor(y), zi = Math.floor(z);
    const xf = x - xi, yf = y - yi, zf = z - zi;
    xi = lmod(xi, 256); yi = lmod(yi, 256); zi = lmod(zi, 256);
    const u = fade(xf), v = fade(yf), w = fade(zf);
    const A = perm[xi] + yi, B = perm[xi + 1] + yi;
    const AA = perm[A] + zi, AB = perm[A + 1] + zi, BA = perm[B] + zi, BB = perm[B + 1] + zi;
    const l = lerp;
    return l(l(l(grad3(perm[AA], xf, yf, zf), grad3(perm[BA], xf - 1, yf, zf), u),
               l(grad3(perm[AB], xf, yf - 1, zf), grad3(perm[BB], xf - 1, yf - 1, zf), u), v),
             l(l(grad3(perm[AA + 1], xf, yf, zf - 1), grad3(perm[BA + 1], xf - 1, yf, zf - 1), u),
               l(grad3(perm[AB + 1], xf, yf - 1, zf - 1), grad3(perm[BB + 1], xf - 1, yf - 1, zf - 1), u), v), w);
  },
  fbm2(x, y, octaves = 4) {
    let s = 0, a = 1, f = 1, norm = 0;
    for (let i = 0; i < octaves; i++) { s += Noise.perlin2(x * f, y * f) * a; norm += a; a *= 0.5; f *= 2; }
    return s / norm;
  },
};

// ------------------------------------------------------------------ colours (sRGB floats, like Grove's Color)
export class Col {
  constructor(r, g, b, a = 1) { this.r = r; this.g = g; this.b = b; this.a = a; }
  static hex(s, a = 1) {
    const n = parseInt(s.replace('#', ''), 16);
    return new Col(((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255, a);
  }
  static hsv(h, s, v) {
    const i = Math.floor(h * 6), f = h * 6 - i, p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
    const m = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][lmod(i, 6)];
    return new Col(m[0], m[1], m[2]);
  }
  lerp(o, t) { return new Col(lerp(this.r, o.r, t), lerp(this.g, o.g, t), lerp(this.b, o.b, t), lerp(this.a, o.a, t)); }
  lighten(t) { return this.lerp(new Col(1, 1, 1, this.a), t); }
  darken(t) { return this.lerp(new Col(0, 0, 0, this.a), t); }
  withAlpha(a) { return new Col(this.r, this.g, this.b, a); }
  // Linear THREE.Color using Grove's pow-2.2 conversion.
  lin(scale = 1) { return new THREE.Color(Math.pow(this.r, 2.2) * scale, Math.pow(this.g, 2.2) * scale, Math.pow(this.b, 2.2) * scale); }
  css(a = this.a) { return `rgba(${Math.round(this.r * 255)},${Math.round(this.g * 255)},${Math.round(this.b * 255)},${a})`; }
}
Col.WHITE = new Col(1, 1, 1);

// ------------------------------------------------------------------ vectors / quats
export const V = (x = 0, y = x, z = x) => new THREE.Vector3(x, y, z);
// Grove's Quat.euler(x, y, z) is yaw * pitch * roll, i.e. three's 'YXZ' order.
export const euler = (x = 0, y = 0, z = 0) => new THREE.Quaternion().setFromEuler(new THREE.Euler(x, y, z, 'YXZ'));
export const fromY = (a) => euler(0, a, 0);
// Rotation whose -Z axis points along fwd.
export function lookRotation(fwd, up = V(0, 1, 0)) {
  const m = new THREE.Matrix4().lookAt(V(0, 0, 0), fwd.clone().normalize(), up);
  return new THREE.Quaternion().setFromRotationMatrix(m);
}

// ------------------------------------------------------------------ easing
export const Ease = {
  linear: (t) => t,
  out_quad: (t) => 1 - (1 - t) * (1 - t),
  out_cubic: (t) => 1 - Math.pow(1 - t, 3),
  in_out_cubic: (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
  in_back: (t) => 2.70158 * t * t * t - 1.70158 * t * t,
  out_back: (t) => 1 + 2.70158 * Math.pow(t - 1, 3) + 1.70158 * Math.pow(t - 1, 2),
  out_elastic: (t) => (t === 0 ? 0 : t === 1 ? 1 : Math.pow(2, -10 * t) * Math.sin((t * 10 - 0.75) * (TAU / 3)) + 1),
};
