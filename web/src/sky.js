// Day/night cycle: moves the sun and moon, blends sky/fog/light colours, drives lamps and fireflies (port of sky.lua).
import * as THREE from 'three';
import { Col, V, lerp, smoothstep, TAU } from './core.js';
import { U } from './render.js';
import { setLamps } from './props.js';
import { Input } from './input.js';

const H = Col.hex;
// Keyframes by sun elevation (-1 night .. 1 noon).
const keys = [
  { e: -0.35, top: H('#0b1230'), hor: H('#1c2a4f'), fog: H('#1a2646'), sun: H('#9fb4ff'), amb: 0.55, stars: 1 },
  { e: -0.05, top: H('#2a3570'), hor: H('#d98a6c'), fog: H('#7a6a8a'), sun: H('#ff9c5a'), amb: 0.6, stars: 0.35 },
  { e: 0.08, top: H('#4a74b8'), hor: H('#ffb27a'), fog: H('#e3b08f'), sun: H('#ffb066'), amb: 0.75, stars: 0 },
  { e: 0.3, top: H('#3f7fd0'), hor: H('#bcd8ee'), fog: H('#c3dbea'), sun: H('#fff1d8'), amb: 0.9, stars: 0 },
  { e: 1.0, top: H('#2f6fd0'), hor: H('#a9d0f0'), fog: H('#b4d4ec'), sun: H('#fffaf0'), amb: 0.95, stars: 0 },
];
function sample(e) {
  if (e <= keys[0].e) return [keys[0], keys[0], 0];
  for (let i = 0; i < keys.length - 1; i++) {
    const a = keys[i], b = keys[i + 1];
    if (e <= b.e) return [a, b, (e - a.e) / (b.e - a.e)];
  }
  return [keys[keys.length - 1], keys[keys.length - 1], 0];
}
const MOON = H('#a8bcff'), SEA = H('#2d6f8f');

export class DayNight {
  constructor(scene) {
    this.hour = 16.2;        // start in warm late afternoon
    this.dayLength = 480;    // real seconds per full day
    this.fast = false;
    this.night = 0;
    this.bloomEnabled = true;
    this.light = new THREE.DirectionalLight(0xffffff, 1);
    this.light.castShadow = true;
    const s = this.light.shadow;
    s.mapSize.set(4096, 4096);
    s.camera.left = -60; s.camera.right = 60; s.camera.top = 60; s.camera.bottom = -60;
    s.camera.near = 1; s.camera.far = 300;
    s.bias = -0.0004; s.normalBias = 0.06;
    scene.add(this.light, this.light.target);
    this.exposure = 1; this.bloomStrength = 0.08;
    this.fireflies = null;
  }
  clockText() {
    const h = Math.floor(this.hour), m = Math.floor((this.hour - h) * 60);
    return String(h).padStart(2, '0') + ':' + String(m).padStart(2, '0');
  }
  timeLapse() { return this.fast || Input.key('KeyT'); }

  update(dt, focus) {
    let speed = 24 / this.dayLength;
    if (this.timeLapse()) speed *= 30;
    this.hour = (this.hour + dt * speed) % 24;

    // Sun travels east to west, tilted so shadows stay interesting at noon.
    const ang = (this.hour - 6) / 24 * TAU;
    const sunUp = V(Math.cos(ang) * 0.9, Math.sin(ang), 0.35).normalize();
    const elev = sunUp.y;
    const [a, b, t] = sample(elev);
    const top = a.top.lerp(b.top, t), hor = a.hor.lerp(b.hor, t), fog = a.fog.lerp(b.fog, t);
    const sunc = a.sun.lerp(b.sun, t);
    const amb = lerp(a.amb, b.amb, t), stars = lerp(a.stars, b.stars, t);

    // Whichever of sun or moon is above the horizon lights the scene and casts shadows.
    const moonUp = sunUp.clone().negate();
    const night = smoothstep(0.02, -0.12, elev);
    this.night = night;
    const dirUp = night > 0.5 ? moonUp : sunUp;
    const energy = night > 0.5 ? 0.45 * smoothstep(0.0, 0.25, moonUp.y) : 2.7 * smoothstep(-0.02, 0.18, elev);
    const col = night > 0.5 ? MOON : sunc;

    // Shadow camera follows the player, snapped to texels so shadows don't shimmer.
    const texel = 120 / 4096;
    const f = V(Math.round(focus.x / texel) * texel, Math.round(focus.y / texel) * texel, Math.round(focus.z / texel) * texel);
    this.light.target.position.copy(f);
    this.light.position.copy(f).addScaledVector(dirUp, 150);
    this.light.color.copy(col.lin());
    this.light.intensity = energy * Math.PI;
    this.light.visible = energy > 0.001;

    U.uSkyTop.value.copy(top.lin());
    U.uSkyHor.value.copy(hor.lin());
    U.uFogColor.value.copy(fog.lin());
    U.uGround.value.copy(hor.lerp(SEA, 0.6).darken(0.25).lin());
    U.uAmb.value = amb;
    U.uStars.value = stars;
    U.uSunDir.value.copy(dirUp).negate();
    U.uSunColor.value.copy(col.lin(energy));
    U.uMoonDir.value.copy(moonUp).negate();
    U.uFogDensity.value = 0.0035 + night * 0.002;
    this.exposure = 1.0 + night * 0.35;
    this.bloomStrength = this.bloomEnabled ? 0.07 + night * 0.05 : 0;

    setLamps(smoothstep(0.0, 0.6, night + smoothstep(0.15, 0.0, elev) * 0.5));
    if (this.fireflies) this.fireflies.rate = night * 45;
  }
}
