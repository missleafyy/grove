// Sound bank, all synthesized at startup (same recipes as the native demo).
import { synth, preset, noteFreq } from './audio.js';

export const SFX = {};
export function initSfx() {
  Object.assign(SFX, {
    jump: preset('jump'),
    double_jump: preset('whoosh'),
    land: preset('land'),
    step: preset('step'),
    thud: preset('thud'),
    bounce: preset('bounce'),
    bounce_pad: synth({ wave: 'sine', freq: 180, freq_end: 900, curve: 0.5, duration: 0.45, release: 0.3, volume: 0.5, vibrato: 0.04, vibrato_rate: 18 }),
    shoot: synth({ wave: 'sine', freq: 900, freq_end: 300, duration: 0.16, release: 0.12, volume: 0.4, layers: [{ wave: 'noise', freq: 3000, duration: 0.05, lowpass: 0.4, volume: 0.15 }] }),
    chime: preset('chime'),
    collect: preset('powerup'),
    splash: synth({ wave: 'noise', freq: 1200, freq_end: 200, duration: 0.7, lowpass: 0.5, lowpass_end: 0.05, release: 0.6, volume: 0.6 }),
    fanfare: synth({ wave: 'square', duty: 0.3, freq: noteFreq('C5'), duration: 1.4, arp: [0, 4, 7, 12, 7, 12, 16, 19, 24], arp_speed: 0.11, arp_once: true, release: 0.6, volume: 0.25, echo: 0.3, echo_delay: 0.14 }),
    hover: preset('blip'),
    click: preset('select'),
  });
}
