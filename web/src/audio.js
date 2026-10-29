// Audio: Grove's retro synth, SoundBuilder music and presets, played through WebAudio.
import { Random } from './core.js';

const RATE = 44100;
let ctx = null, master = null;
const pending = [];

// Browsers only allow audio after a user gesture; sounds are rendered up front and played once unlocked.
export function unlockAudio() {
  if (ctx) { if (ctx.state === 'suspended') ctx.resume(); return; }
  const AC = window.AudioContext || window.webkitAudioContext;
  if (!AC) return;
  ctx = new AC();
  master = ctx.createGain();
  master.gain.value = 0.9;
  master.connect(ctx.destination);
  for (const f of pending.splice(0)) f();
}

class Sound {
  constructor(samples) { this.samples = samples; this.buf = null; }
  buffer() {
    if (!this.buf) {
      this.buf = ctx.createBuffer(1, this.samples.length, RATE);
      this.buf.getChannelData(0).set(this.samples);
    }
    return this.buf;
  }
}

function osc(wave, phase, duty, rnd) {
  const p = phase - Math.floor(phase);
  if (wave === 'square') return p < duty ? 0.6 : -0.6;
  if (wave === 'saw') return (p * 2 - 1) * 0.6;
  if (wave === 'triangle') return (p < 0.5 ? (p * 4 - 1) : (3 - p * 4)) * 0.8;
  if (wave === 'noise') return rnd;
  return Math.sin(p * 2 * Math.PI);
}

function renderSynth(p, buf, offset, total) {
  const wave = p.wave || 'square';
  const freq = p.freq || 440, freqEnd = p.freq_end ?? freq;
  const dur = p.duration || 0.3;
  const attack = p.attack ?? 0.005, release = p.release ?? dur * 0.6;
  const sustain = p.sustain ?? 1, vol = p.volume ?? 0.5, duty = p.duty ?? 0.5;
  const vib = p.vibrato || 0, vibRate = p.vibrato_rate || 6;
  const arp = p.arp, arpSpeed = p.arp_speed || 0.07;
  const lp = p.lowpass ?? 1, lpEnd = p.lowpass_end ?? lp;
  const noiseAmt = p.noise || 0, curve = p.curve || 1;
  const n = Math.floor(dur * RATE);
  let phase = 0, filt = 0, nval = 0, nphase = 0;
  const r = new Random(p.seed || 7);
  for (let i = 0; i < n; i++) {
    const t = i / RATE, k = i / n;
    let f = freq + (freqEnd - freq) * Math.pow(k, curve);
    if (arp) {
      let step = Math.floor(t / arpSpeed) % arp.length;
      if (p.arp_once) step = Math.min(Math.floor(t / arpSpeed), arp.length - 1);
      f *= Math.pow(2, arp[step] / 12);
    }
    if (vib > 0) f *= 1 + Math.sin(t * vibRate * 2 * Math.PI) * vib;
    phase += f / RATE;
    nphase += Math.max(f, 50) * 8 / RATE;
    if (nphase >= 1) { nphase -= Math.floor(nphase); nval = r.float(-1, 1); }
    let s = osc(wave, phase, duty, nval);
    if (noiseAmt > 0) s = s * (1 - noiseAmt) + nval * noiseAmt;
    let env;
    if (t < attack) env = t / attack;
    else if (t > dur - release) env = Math.max(0, (dur - t) / release) * sustain;
    else env = sustain + (1 - sustain) * Math.exp(-(t - attack) * 12);
    const cut = lp + (lpEnd - lp) * k;
    filt += (s - filt) * cut;
    const idx = offset + i;
    if (idx < total) buf[idx] += filt * env * vol;
  }
  return n;
}

export function synth(p) {
  const tail = p.echo ? (p.echo_delay || 0.12) * 4 : 0;
  const total = Math.floor(((p.duration || 0.3) + tail) * RATE) + 1;
  const buf = new Float32Array(total);
  renderSynth(p, buf, 0, total);
  for (const l of p.layers || []) renderSynth(l, buf, Math.floor((l.delay || 0) * RATE), total);
  if (p.echo) {
    const d = Math.floor((p.echo_delay || 0.12) * RATE);
    for (let i = d; i < total; i++) buf[i] += buf[i - d] * p.echo;
  }
  return new Sound(buf);
}

const presets = {
  jump: { wave: 'square', freq: 240, freq_end: 620, curve: 0.6, duration: 0.22, duty: 0.25, release: 0.12, volume: 0.3 },
  land: { wave: 'noise', freq: 300, freq_end: 80, duration: 0.12, lowpass: 0.25, release: 0.1, volume: 0.45 },
  powerup: { wave: 'square', freq: 440, duration: 0.6, arp: [0, 4, 7, 12, 16, 19, 24], arp_speed: 0.06, arp_once: true, release: 0.3, volume: 0.3, vibrato: 0.01, vibrato_rate: 12 },
  blip: { wave: 'sine', freq: 880, duration: 0.07, release: 0.05, volume: 0.35 },
  select: { wave: 'triangle', freq: 660, freq_end: 990, duration: 0.09, release: 0.06, volume: 0.4 },
  thud: { wave: 'sine', freq: 140, freq_end: 45, duration: 0.25, release: 0.2, volume: 0.7, layers: [{ wave: 'noise', freq: 400, freq_end: 80, duration: 0.08, lowpass: 0.3, volume: 0.4 }] },
  whoosh: { wave: 'noise', freq: 200, freq_end: 900, duration: 0.35, attack: 0.12, lowpass: 0.05, lowpass_end: 0.3, release: 0.2, volume: 0.4 },
  step: { wave: 'noise', freq: 500, freq_end: 200, duration: 0.05, lowpass: 0.2, release: 0.04, volume: 0.25 },
  chime: { wave: 'sine', freq: 1320, duration: 1.2, release: 1.1, volume: 0.3, echo: 0.35, echo_delay: 0.11, layers: [{ wave: 'sine', freq: 1980, duration: 1.0, release: 0.9, volume: 0.15 }] },
  bounce: { wave: 'sine', freq: 300, freq_end: 520, duration: 0.12, release: 0.08, volume: 0.4 },
};
export const preset = (name) => synth({ ...presets[name] });

const noteIndex = { C: 0, 'C#': 1, Db: 1, D: 2, 'D#': 3, Eb: 3, E: 4, F: 5, 'F#': 6, Gb: 6, G: 7, 'G#': 8, Ab: 8, A: 9, 'A#': 10, Bb: 10, B: 11 };
export function noteFreq(n) {
  if (typeof n === 'number') return 440 * Math.pow(2, (n - 69) / 12);
  const m = n.match(/^([A-G][#b]?)(-?\d)$/);
  const midi = (parseInt(m[2], 10) + 1) * 12 + noteIndex[m[1]];
  return 440 * Math.pow(2, (midi - 69) / 12);
}

export class SoundBuilder {
  constructor(seconds) { this.frames = Math.floor(seconds * RATE); this.buf = new Float32Array(this.frames); }
  note(t, note, dur, opts = {}) {
    const p = { ...opts };
    p.freq = (typeof note === 'number' && note > 127) ? note : noteFreq(note);
    p.duration = dur;
    p.wave = p.wave || 'triangle';
    p.attack = p.attack ?? 0.01;
    p.release = p.release ?? Math.min(dur * 0.5, 0.3);
    p.sustain = p.sustain ?? 0.7;
    const start = Math.floor(t * RATE);
    const len = Math.floor(dur * RATE) + 1;
    const tmp = new Float32Array(len);
    const n = renderSynth(p, tmp, 0, len);
    for (let i = 0; i < n; i++) this.buf[(start + i) % this.frames] += tmp[i];
  }
  drum(t, kind, v = 0.5) {
    if (kind === 'kick') this.note(t, 150, 0.22, { wave: 'sine', freq_end: 40, volume: v, sustain: 1, release: 0.2, attack: 0.002 });
    else if (kind === 'hat') this.note(t, 4000, 0.05, { wave: 'noise', volume: v * 0.3, lowpass: 0.9, release: 0.04, attack: 0.001 });
  }
  build(opts = {}) {
    let buf = this.buf;
    const n = this.frames;
    if (opts.reverb) {
      const out = Float32Array.from(buf);
      for (const d of [0.0297, 0.0371, 0.0411, 0.0437]) {
        const dl = Math.floor(d * RATE * 3);
        const comb = new Float32Array(n);
        for (let pass = 0; pass < 2; pass++) for (let i = 0; i < n; i++) {
          let j = i - dl; if (j < 0) j += n;
          comb[i] = buf[i] + comb[j] * 0.72;
        }
        for (let i = 0; i < n; i++) out[i] += comb[i] * opts.reverb * 0.25;
      }
      buf = out;
    }
    let peak = 0;
    for (let i = 0; i < n; i++) peak = Math.max(peak, Math.abs(buf[i]));
    if (peak > 0.95) { const g = 0.95 / peak; for (let i = 0; i < n; i++) buf[i] *= g; }
    return new Sound(buf);
  }
}

// ------------------------------------------------------------------ playback
let listener = null;   // { pos: Vector3, right: Vector3 }
export function setListener(pos, right) { listener = { pos, right }; }

function start(sound, volume, pitch, pan, loop) {
  const src = ctx.createBufferSource();
  src.buffer = sound.buffer();
  src.playbackRate.value = pitch;
  src.loop = !!loop;
  const g = ctx.createGain();
  g.gain.value = volume;
  let node = src;
  if (ctx.createStereoPanner) {
    const p = ctx.createStereoPanner();
    p.pan.value = pan;
    src.connect(p); p.connect(g);
  } else src.connect(g);
  g.connect(master);
  src.start();
  return { src, gain: g };
}

export const Audio = {
  play(sound, o = {}) {
    if (!ctx || ctx.state !== 'running') return null;
    return start(sound, o.volume ?? 1, o.pitch ?? 1, o.pan ?? 0, o.loop);
  },
  playAt(sound, pos, o = {}) {
    if (!ctx || ctx.state !== 'running' || !listener) return null;
    const minD = o.min_distance ?? 3, maxD = o.max_distance ?? 80;
    const d = pos.distanceTo(listener.pos);
    if (d > maxD) return null;
    const att = d <= minD ? 1 : minD / d;
    const pan = d > 0.01 ? Math.max(-1, Math.min(1, pos.clone().sub(listener.pos).normalize().dot(listener.right))) * 0.8 : 0;
    return start(sound, (o.volume ?? 1) * att, o.pitch ?? 1, pan, o.loop);
  },
  // A looping, non-positional voice whose volume can be changed later (music).
  loop(sound, volume) {
    const v = { volume, node: null };
    const go = () => { v.node = start(sound, volume, 1, 0, true); };
    if (ctx) go(); else pending.push(go);
    return v;
  },
  setVolume(v, vol) { v.volume = vol; if (v.node) v.node.gain.gain.value = vol; },
};
