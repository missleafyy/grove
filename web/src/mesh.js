// MeshData: procedural mesh builder ported from Grove (resources.lua). Builds THREE.BufferGeometry.
import * as THREE from 'three';
import { Col } from './core.js';

const _p = new THREE.Vector3(), _n = new THREE.Vector3();

export class MeshData {
  constructor() {
    this.p = []; this.n = []; this.uv = []; this.c = []; this.i = [];
    this.cur = [1, 1, 1, 1];
  }
  get nv() { return this.p.length / 3; }
  color(c) { this.cur = [c.r, c.g, c.b, c.a]; return this; }
  vertex(px, py, pz, nx = 0, ny = 1, nz = 0, u = 0, v = 0) {
    this.p.push(px, py, pz); this.n.push(nx, ny, nz); this.uv.push(u, v); this.c.push(...this.cur);
    return this.nv - 1;
  }
  tri(a, b, c) { this.i.push(a, b, c); return this; }
  quad(a, b, c, d) { this.tri(a, b, c); this.tri(a, c, d); }

  append(o, pos, rot, scale) {
    const base = this.nv;
    for (let k = 0; k < o.nv; k++) {
      _p.set(o.p[k * 3], o.p[k * 3 + 1], o.p[k * 3 + 2]);
      _n.set(o.n[k * 3], o.n[k * 3 + 1], o.n[k * 3 + 2]);
      if (scale) { _p.multiply(scale); _n.divide(scale).normalize(); }
      if (rot) { _p.applyQuaternion(rot); _n.applyQuaternion(rot); }
      if (pos) _p.add(pos);
      this.p.push(_p.x, _p.y, _p.z); this.n.push(_n.x, _n.y, _n.z);
      this.uv.push(o.uv[k * 2], o.uv[k * 2 + 1]);
      this.c.push(o.c[k * 4], o.c[k * 4 + 1], o.c[k * 4 + 2], o.c[k * 4 + 3]);
    }
    for (const idx of o.i) this.i.push(idx + base);
    return this;
  }
  transform(pos, rot, scale) {
    if (typeof scale === 'number') scale = new THREE.Vector3(scale, scale, scale);
    for (let k = 0; k < this.nv; k++) {
      _p.set(this.p[k * 3], this.p[k * 3 + 1], this.p[k * 3 + 2]);
      _n.set(this.n[k * 3], this.n[k * 3 + 1], this.n[k * 3 + 2]);
      if (scale) { _p.multiply(scale); _n.divide(scale).normalize(); }
      if (rot) { _p.applyQuaternion(rot); _n.applyQuaternion(rot); }
      if (pos) _p.add(pos);
      this.p[k * 3] = _p.x; this.p[k * 3 + 1] = _p.y; this.p[k * 3 + 2] = _p.z;
      this.n[k * 3] = _n.x; this.n[k * 3 + 1] = _n.y; this.n[k * 3 + 2] = _n.z;
    }
    return this;
  }
  paintFn(fn) {
    for (let k = 0; k < this.nv; k++) {
      const r = fn(this.p[k * 3], this.p[k * 3 + 1], this.p[k * 3 + 2], this.c[k * 4], this.c[k * 4 + 1], this.c[k * 4 + 2]);
      this.c[k * 4] = r[0]; this.c[k * 4 + 1] = r[1]; this.c[k * 4 + 2] = r[2];
    }
    return this;
  }
  displace(fn) {
    for (let k = 0; k < this.nv; k++) {
      const d = fn(this.p[k * 3], this.p[k * 3 + 1], this.p[k * 3 + 2]);
      this.p[k * 3] += d[0] || 0; this.p[k * 3 + 1] += d[1] || 0; this.p[k * 3 + 2] += d[2] || 0;
    }
    return this;
  }
  // Unshare vertices and give each triangle its face normal (faceted low-poly look).
  flat() {
    const P = [], N = [], UV = [], C = [], I = [];
    for (let k = 0; k < this.i.length; k += 3) {
      const ids = [this.i[k], this.i[k + 1], this.i[k + 2]];
      const a = ids.map((id) => [this.p[id * 3], this.p[id * 3 + 1], this.p[id * 3 + 2]]);
      const e1 = [a[1][0] - a[0][0], a[1][1] - a[0][1], a[1][2] - a[0][2]];
      const e2 = [a[2][0] - a[0][0], a[2][1] - a[0][1], a[2][2] - a[0][2]];
      let nx = e1[1] * e2[2] - e1[2] * e2[1], ny = e1[2] * e2[0] - e1[0] * e2[2], nz = e1[0] * e2[1] - e1[1] * e2[0];
      const l = Math.hypot(nx, ny, nz) || 1; nx /= l; ny /= l; nz /= l;
      const base = P.length / 3;
      ids.forEach((id, j) => {
        P.push(...a[j]); N.push(nx, ny, nz); UV.push(this.uv[id * 2], this.uv[id * 2 + 1]);
        C.push(this.c[id * 4], this.c[id * 4 + 1], this.c[id * 4 + 2], this.c[id * 4 + 3]);
      });
      I.push(base, base + 1, base + 2);
    }
    this.p = P; this.n = N; this.uv = UV; this.c = C; this.i = I;
    return this;
  }
  smoothNormals() {
    const acc = new Map();
    const key = (k) => Math.floor(this.p[k * 3] * 1000 + 0.5) + ':' + Math.floor(this.p[k * 3 + 1] * 1000 + 0.5) + ':' + Math.floor(this.p[k * 3 + 2] * 1000 + 0.5);
    for (let k = 0; k < this.i.length; k += 3) {
      const [ia, ib, ic] = [this.i[k], this.i[k + 1], this.i[k + 2]];
      const e1 = [this.p[ib * 3] - this.p[ia * 3], this.p[ib * 3 + 1] - this.p[ia * 3 + 1], this.p[ib * 3 + 2] - this.p[ia * 3 + 2]];
      const e2 = [this.p[ic * 3] - this.p[ia * 3], this.p[ic * 3 + 1] - this.p[ia * 3 + 1], this.p[ic * 3 + 2] - this.p[ia * 3 + 2]];
      const n = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]];
      for (const id of [ia, ib, ic]) {
        const kk = key(id);
        const s = acc.get(kk);
        if (s) { s[0] += n[0]; s[1] += n[1]; s[2] += n[2]; } else acc.set(kk, n.slice());
      }
    }
    for (let k = 0; k < this.nv; k++) {
      const n = acc.get(key(k));
      if (n) { const l = Math.hypot(n[0], n[1], n[2]) || 1; this.n[k * 3] = n[0] / l; this.n[k * 3 + 1] = n[1] / l; this.n[k * 3 + 2] = n[2] / l; }
    }
    return this;
  }
  copy() {
    const m = new MeshData();
    m.p = this.p.slice(); m.n = this.n.slice(); m.uv = this.uv.slice(); m.c = this.c.slice(); m.i = this.i.slice();
    return m;
  }
  // Vertex colours are sRGB in Grove and linearised in the shader with pow 2.2; do that here.
  geometry() {
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.Float32BufferAttribute(this.p, 3));
    g.setAttribute('normal', new THREE.Float32BufferAttribute(this.n, 3));
    g.setAttribute('uv', new THREE.Float32BufferAttribute(this.uv, 2));
    const c = new Float32Array(this.nv * 3);
    for (let k = 0; k < this.nv; k++) for (let j = 0; j < 3; j++) c[k * 3 + j] = Math.pow(Math.max(this.c[k * 4 + j], 0), 2.2);
    g.setAttribute('color', new THREE.BufferAttribute(c, 3));
    g.setIndex(this.nv > 65535 ? new THREE.Uint32BufferAttribute(this.i, 1) : new THREE.Uint16BufferAttribute(this.i, 1));
    g.computeBoundingSphere();
    return g;
  }

  // ---------------------------------------------------------------- primitives
  static box(sx, sy, sz, col) {
    sy = sy ?? sx; sz = sz ?? sx;
    const m = new MeshData();
    if (col) m.color(col);
    const hx = sx / 2, hy = sy / 2, hz = sz / 2;
    const faces = [
      [1, 0, 0, [hx, -hy, hz], [hx, -hy, -hz], [hx, hy, -hz], [hx, hy, hz], sz, sy],
      [-1, 0, 0, [-hx, -hy, -hz], [-hx, -hy, hz], [-hx, hy, hz], [-hx, hy, -hz], sz, sy],
      [0, 1, 0, [-hx, hy, hz], [hx, hy, hz], [hx, hy, -hz], [-hx, hy, -hz], sx, sz],
      [0, -1, 0, [-hx, -hy, -hz], [hx, -hy, -hz], [hx, -hy, hz], [-hx, -hy, hz], sx, sz],
      [0, 0, 1, [-hx, -hy, hz], [hx, -hy, hz], [hx, hy, hz], [-hx, hy, hz], sx, sy],
      [0, 0, -1, [hx, -hy, -hz], [-hx, -hy, -hz], [-hx, hy, -hz], [hx, hy, -hz], sx, sy],
    ];
    for (const f of faces) {
      const [nx, ny, nz] = f, u = f[7], v = f[8];
      const a = m.vertex(...f[3], nx, ny, nz, 0, v);
      const b = m.vertex(...f[4], nx, ny, nz, u, v);
      const c = m.vertex(...f[5], nx, ny, nz, u, 0);
      const d = m.vertex(...f[6], nx, ny, nz, 0, 0);
      m.quad(a, b, c, d);
    }
    return m;
  }
  static sphere(r, segments = 24, rings = 16, col) {
    const m = new MeshData();
    if (col) m.color(col);
    for (let y = 0; y <= rings; y++) {
      const v = y / rings, phi = v * Math.PI;
      for (let x = 0; x <= segments; x++) {
        const u = x / segments, th = u * 2 * Math.PI;
        const nx = Math.sin(phi) * Math.cos(th), ny = Math.cos(phi), nz = Math.sin(phi) * Math.sin(th);
        m.vertex(nx * r, ny * r, nz * r, nx, ny, nz, u, v);
      }
    }
    for (let y = 0; y < rings; y++) for (let x = 0; x < segments; x++) {
      const a = y * (segments + 1) + x, b = a + segments + 1;
      m.tri(a, a + 1, b + 1); m.tri(a, b + 1, b);
    }
    return m;
  }
  static icosphere(r, subdiv = 1, col) {
    const t = (1 + Math.sqrt(5)) / 2;
    let verts = [[-1, t, 0], [1, t, 0], [-1, -t, 0], [1, -t, 0], [0, -1, t], [0, 1, t], [0, -1, -t], [0, 1, -t], [t, 0, -1], [t, 0, 1], [-t, 0, -1], [-t, 0, 1]];
    let faces = [[1, 12, 6], [1, 6, 2], [1, 2, 8], [1, 8, 11], [1, 11, 12], [2, 6, 10], [6, 12, 5], [12, 11, 3], [11, 8, 7],
      [8, 2, 9], [4, 10, 5], [4, 5, 3], [4, 3, 7], [4, 7, 9], [4, 9, 10], [5, 10, 6], [3, 5, 12], [7, 3, 11], [9, 7, 8], [10, 9, 2]];
    verts = verts.map((v) => { const l = Math.hypot(...v); return [v[0] / l, v[1] / l, v[2] / l]; });
    for (let s = 0; s < subdiv; s++) {
      const cache = new Map(), nf = [];
      const mid = (a, b) => {
        const k = a < b ? a + '_' + b : b + '_' + a;
        if (cache.has(k)) return cache.get(k);
        const va = verts[a - 1], vb = verts[b - 1];
        const x = (va[0] + vb[0]) / 2, y = (va[1] + vb[1]) / 2, z = (va[2] + vb[2]) / 2, l = Math.hypot(x, y, z);
        verts.push([x / l, y / l, z / l]);
        cache.set(k, verts.length);
        return verts.length;
      };
      for (const f of faces) {
        const a = mid(f[0], f[1]), b = mid(f[1], f[2]), c = mid(f[2], f[0]);
        nf.push([f[0], a, c], [f[1], b, a], [f[2], c, b], [a, b, c]);
      }
      faces = nf;
    }
    const m = new MeshData();
    if (col) m.color(col);
    for (const v of verts) m.vertex(v[0] * r, v[1] * r, v[2] * r, v[0], v[1], v[2], 0.5 + Math.atan2(v[2], v[0]) / (2 * Math.PI), 0.5 - Math.asin(v[1]) / Math.PI);
    for (const f of faces) {
      const a = verts[f[0] - 1], b = verts[f[1] - 1], c = verts[f[2] - 1];
      const e1 = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], e2 = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
      const n = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]];
      const s = [a[0] + b[0] + c[0], a[1] + b[1] + c[1], a[2] + b[2] + c[2]];
      if (n[0] * s[0] + n[1] * s[1] + n[2] * s[2] >= 0) m.tri(f[0] - 1, f[1] - 1, f[2] - 1);
      else m.tri(f[0] - 1, f[2] - 1, f[1] - 1);
    }
    return m;
  }
  static cylinder(rTop, rBottom, h, segments = 16, col, caps = true) {
    const m = new MeshData();
    if (col) m.color(col);
    const hh = h / 2, slope = (rBottom - rTop) / h;
    for (let i = 0; i <= segments; i++) {
      const u = i / segments, a = u * 2 * Math.PI, c = Math.cos(a), s = Math.sin(a);
      const l = Math.hypot(c, slope, s);
      m.vertex(c * rBottom, -hh, s * rBottom, c / l, slope / l, s / l, u, 1);
      m.vertex(c * rTop, hh, s * rTop, c / l, slope / l, s / l, u, 0);
    }
    for (let i = 0; i < segments; i++) { const a = i * 2; m.tri(a, a + 1, a + 3); m.tri(a, a + 3, a + 2); }
    if (caps) {
      for (let side = 0; side <= 1; side++) {
        const y = side === 0 ? hh : -hh, r = side === 0 ? rTop : rBottom;
        if (r > 0) {
          const ny = side === 0 ? 1 : -1;
          const center = m.vertex(0, y, 0, 0, ny, 0, 0.5, 0.5);
          const first = m.nv;
          for (let i = 0; i <= segments; i++) {
            const a = i / segments * 2 * Math.PI;
            m.vertex(Math.cos(a) * r, y, Math.sin(a) * r, 0, ny, 0, 0.5 + Math.cos(a) * 0.5, 0.5 + Math.sin(a) * 0.5);
          }
          for (let i = 0; i < segments; i++) {
            if (side === 0) m.tri(center, first + i + 1, first + i); else m.tri(center, first + i, first + i + 1);
          }
        }
      }
    }
    return m;
  }
  static cone(r, h, segments, col) { return MeshData.cylinder(0, r, h, segments, col); }
  static torus(R, r, segments = 32, sides = 12, col) {
    const m = new MeshData();
    if (col) m.color(col);
    for (let i = 0; i <= segments; i++) {
      const u = i / segments * 2 * Math.PI;
      for (let j = 0; j <= sides; j++) {
        const v = j / sides * 2 * Math.PI;
        m.vertex(Math.cos(u) * (R + r * Math.cos(v)), r * Math.sin(v), Math.sin(u) * (R + r * Math.cos(v)),
          Math.cos(u) * Math.cos(v), Math.sin(v), Math.sin(u) * Math.cos(v), i / segments, j / sides);
      }
    }
    for (let i = 0; i < segments; i++) for (let j = 0; j < sides; j++) {
      const a = i * (sides + 1) + j, b = a + sides + 1;
      m.tri(a, a + 1, b + 1); m.tri(a, b + 1, b);
    }
    return m;
  }
  static grid(w, d, resX, resZ, heightFn, colorFn) {
    const m = new MeshData();
    const hw = w / 2, hd = d / 2;
    for (let z = 0; z <= resZ; z++) for (let x = 0; x <= resX; x++) {
      const px = -hw + w * x / resX, pz = -hd + d * z / resZ;
      const py = heightFn ? heightFn(px, pz) : 0;
      if (colorFn) m.color(colorFn(px, py, pz));
      m.vertex(px, py, pz, 0, 1, 0, x / resX, z / resZ);
    }
    for (let z = 0; z < resZ; z++) for (let x = 0; x < resX; x++) {
      const a = z * (resX + 1) + x, b = a + resX + 1;
      m.tri(a, b, a + 1); m.tri(a + 1, b, b + 1);
    }
    if (heightFn) m.smoothNormals();
    return m;
  }
}
export { Col };
