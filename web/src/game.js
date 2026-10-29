// Tiny runtime standing in for Grove's node tree: per-frame callbacks, timers, tweens, 3D labels,
// and helpers for adding/freeing objects that own particles, lights or physics bodies.
import * as THREE from 'three';
import { Ease, clamp, smoothstep } from './core.js';
import { Particles, virtualLights, VLight } from './render.js';
import { removeBody } from './physics.js';

export const G = {
  scene: null, camera: null,
  time: 0, realTime: 0, paused: false,
  process: new Set(),       // fn(dt) — game time, stops when paused
  always: new Set(),        // fn(dtReal) — runs while paused too
};

export function add(parent, obj) {
  parent.add(obj);
  obj.traverse((o) => { if (o instanceof Particles) o.onAdded(G.scene); });
  return obj;
}

export function light(parent, opts) {
  const o = new THREE.Object3D();
  if (opts.position) o.position.copy(opts.position);
  parent.add(o);
  const l = new VLight(o, opts.color.lin(), opts.energy, opts.range);
  virtualLights.add(l);
  o.userData.vlight = l;
  return l;
}

// Remove an object and everything it owns.
export function free(obj) {
  obj.traverse((o) => {
    if (o.userData.vlight) virtualLights.delete(o.userData.vlight);
    if (o.userData.body) removeBody(o.userData.body);
    if (o.userData.process) G.process.delete(o.userData.process);
    if (o.userData.label) { o.userData.label.el.remove(); labels.delete(o.userData.label); }
  });
  const ps = [];
  obj.traverse((o) => { if (o instanceof Particles) ps.push(o); });
  ps.forEach((p) => p.dispose());
  obj.removeFromParent();
}

export function onProcess(obj, fn) {
  obj.userData.process = fn;
  G.process.add(fn);
}

// ------------------------------------------------------------------ timers & tweens
const timers = [];
export function after(sec, fn) { timers.push({ at: G.time + sec, fn }); }

const tweens = new Set();
// Tween numeric or Vector3 properties of target. opts: ease, onDone, real (use real time).
export function tween(target, props, dur, opts = {}) {
  const from = {};
  for (const k in props) from[k] = props[k].clone ? target[k].clone() : target[k];
  const tw = { t: 0, dur, opts, fn: (k) => {
    for (const key in props) {
      if (props[key].clone) target[key].copy(from[key]).lerp(props[key], k);
      else target[key] = from[key] + (props[key] - from[key]) * k;
    }
  } };
  tweens.add(tw);
  return tw;
}
export function run(dur, fn, opts = {}) {
  const tw = { t: 0, dur, opts, fn };
  tweens.add(tw);
  return tw;
}
export function tickTimers(dt, dtReal) {
  for (let i = timers.length - 1; i >= 0; i--) if (G.time >= timers[i].at) { const t = timers[i]; timers.splice(i, 1); t.fn(); }
  for (const tw of [...tweens]) {
    const d = tw.opts.real ? dtReal : dt;
    tw.t = Math.min(tw.dur, tw.t + d);
    const k = (Ease[tw.opts.ease || 'out_quad'])(tw.dur > 0 ? tw.t / tw.dur : 1);
    tw.fn(k);
    if (tw.t >= tw.dur) { tweens.delete(tw); if (tw.opts.onDone) tw.opts.onDone(); }
  }
}

// ------------------------------------------------------------------ Label3D (HTML)
const labels = new Set();
let labelLayer = null;
export function label(parent, text, opts = {}) {
  if (!labelLayer) labelLayer = document.getElementById('labels');
  const o = new THREE.Object3D();
  if (opts.position) o.position.copy(opts.position);
  parent.add(o);
  const el = document.createElement('div');
  el.className = 'label3d';
  el.textContent = text;
  el.style.color = opts.color ? opts.color.css() : '#fff';
  labelLayer.appendChild(el);
  const l = { obj: o, el, size: opts.size || 28, maxDistance: opts.max_distance || 40 };
  labels.add(l);
  o.userData.label = l;
  return l;
}
const _p = new THREE.Vector3(), _c = new THREE.Vector3();
export function updateLabels(cam, w, h) {
  cam.getWorldPosition(_c);
  for (const l of labels) {
    let vis = true;
    for (let n = l.obj; n; n = n.parent) if (!n.visible) vis = false;
    l.obj.getWorldPosition(_p);
    const dist = _p.distanceTo(_c);
    if (!vis || dist > l.maxDistance || !l.obj.parent) { l.el.style.display = 'none'; continue; }
    _p.project(cam);
    if (_p.z > 1 || _p.z < -1 || Math.abs(_p.x) > 1.1 || Math.abs(_p.y) > 1.1) { l.el.style.display = 'none'; continue; }
    const size = clamp(l.size * 10 / Math.max(dist, 0.1), 8, l.size * 3) * (h / 720);
    const fade = 1 - smoothstep(l.maxDistance * 0.75, l.maxDistance, dist);
    l.el.style.display = 'block';
    l.el.style.fontSize = size.toFixed(1) + 'px';
    l.el.style.opacity = fade.toFixed(3);
    l.el.style.transform = `translate(${((_p.x * 0.5 + 0.5) * w).toFixed(1)}px, ${((-_p.y * 0.5 + 0.5) * h).toFixed(1)}px) translate(-50%, -50%)`;
  }
}
