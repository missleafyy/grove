// A gentle procedural music loop, generated at startup with SoundBuilder (port of music.lua).
import { SoundBuilder } from './audio.js';
import { Random } from './core.js';

const shift = (n, d) => n.replace(/-?\d/, (o) => String(parseInt(o, 10) + d));

export function buildMusic() {
  const bpm = 84, beat = 60 / bpm, bars = 8;
  const m = new SoundBuilder(bars * 4 * beat);
  // I - vi - IV - V in C major, twice.
  const chords = [['C3', 'E3', 'G3', 'B3'], ['A2', 'C3', 'E3', 'G3'], ['F2', 'A2', 'C3', 'E3'], ['G2', 'B2', 'D3', 'F3']];
  const melody = ['C5', 'D5', 'E5', 'G5', 'A5', 'C6'];
  const r = new Random(9);
  for (let bar = 0; bar < bars; bar++) {
    const chord = chords[bar % 4];
    const t0 = bar * 4 * beat;
    // Soft pad.
    for (const n of chord) m.note(t0, n, 4 * beat, { wave: 'triangle', volume: 0.07, attack: 0.6, release: 1.2, sustain: 0.8, lowpass: 0.12, vibrato: 0.003, vibrato_rate: 4 });
    // Bass.
    m.note(t0, shift(chord[0], -1), 2 * beat, { wave: 'sine', volume: 0.22, release: 0.6 });
    m.note(t0 + 2 * beat, shift(chord[0], -1), 2 * beat, { wave: 'sine', volume: 0.18, release: 0.6 });
    // Plucked arpeggio in eighths.
    for (let i = 0; i < 8; i++) {
      m.note(t0 + i * beat / 2, shift(chord[i % 4], 1), beat * 0.9, { wave: 'square', duty: 0.3, volume: 0.035, attack: 0.003, release: 0.35, sustain: 0.3, lowpass: 0.18 });
    }
    // A sparse melody in the second half.
    if (bar >= 4) {
      for (let i = 0; i < 4; i++) {
        if (r.chance(0.7)) {
          const t = t0 + i * beat + (r.chance(0.3) ? beat / 2 : 0);
          m.note(t, r.pick(melody), beat * 1.2, { wave: 'sine', volume: 0.09, attack: 0.01, release: 0.5, sustain: 0.5, vibrato: 0.006, vibrato_rate: 5 });
        }
      }
    }
    // Light percussion.
    for (let i = 0; i < 4; i++) {
      if (i % 2 === 0) m.drum(t0 + i * beat, 'kick', 0.35);
      m.drum(t0 + i * beat + beat / 2, 'hat', 0.25);
    }
  }
  return m.build({ reverb: 0.35 });
}
