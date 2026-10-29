-- Audio: Sound resources (files or synthesized), a retro SFX synth, a music builder,
-- the Audio helper and the AudioPlayer3D node.
local ffi = require("ffi")
local sin, floor, pi, exp, abs, min, max = math.sin, math.floor, math.pi, math.exp, math.abs, math.min, math.max
local RATE = 44100

------------------------------------------------------------------ Sound
Sound = class("Sound")
function Sound:_init(id) self.id = id end
function Sound.load(path)
  local id = C.gr_sound_load(res_path(path))
  if id == 0 then error("could not load sound " .. path, 2) end
  return Sound(id)
end
function Sound.from_samples(buf, frames, channels, rate)
  return Sound(C.gr_sound_create(buf, frames, channels or 1, rate or RATE))
end
function Sound:free() C.gr_sound_free(self.id) end

------------------------------------------------------------------ synth
-- Sound.synth{ wave, freq, freq_end, duration, attack, decay, sustain, release, volume,
--              duty, vibrato, vibrato_rate, arp = {semitones...}, arp_speed, lowpass, noise, echo }
local function osc(wave, phase, duty, rnd)
  local p = phase % 1
  if wave == "square" then return p < duty and 0.6 or -0.6
  elseif wave == "saw" then return (p * 2 - 1) * 0.6
  elseif wave == "triangle" then return (p < 0.5 and (p * 4 - 1) or (3 - p * 4)) * 0.8
  elseif wave == "noise" then return rnd
  else return sin(p * 2 * pi) end
end

local function render_synth(p, buf, offset, total)
  local wave = p.wave or "square"
  local freq = p.freq or 440
  local freq_end = p.freq_end or freq
  local dur = p.duration or 0.3
  local attack, release = p.attack or 0.005, p.release or (dur * 0.6)
  local sustain = p.sustain or 1
  local vol = p.volume or 0.5
  local duty = p.duty or 0.5
  local vib, vib_rate = p.vibrato or 0, p.vibrato_rate or 6
  local arp, arp_speed = p.arp, p.arp_speed or 0.07
  local lp = p.lowpass or 1
  local lp_end = p.lowpass_end or lp
  local noise_amt = p.noise or 0
  local curve = p.curve or 1
  local n = floor(dur * RATE)
  local phase, filt = 0, 0
  local r = Random(p.seed or 7)
  local nval, nphase = 0, 0
  for i = 0, n - 1 do
    local t = i / RATE
    local k = i / n
    local f = freq + (freq_end - freq) * (k ^ curve)
    if arp then
      local step = floor(t / arp_speed) % #arp + 1
      if p.arp_once then step = min(floor(t / arp_speed) + 1, #arp) end
      f = f * 2 ^ (arp[step] / 12)
    end
    if vib > 0 then f = f * (1 + sin(t * vib_rate * 2 * pi) * vib) end
    phase = phase + f / RATE
    -- Noise is sample-and-hold at the oscillator frequency so pitch shapes it.
    nphase = nphase + max(f, 50) * 8 / RATE
    if nphase >= 1 then nphase = nphase - floor(nphase); nval = r:float(-1, 1) end
    local s = osc(wave, phase, duty, nval)
    if noise_amt > 0 then s = s * (1 - noise_amt) + nval * noise_amt end
    local env
    if t < attack then env = t / attack
    elseif t > dur - release then env = max(0, (dur - t) / release) * sustain
    else env = sustain + (1 - sustain) * exp(-(t - attack) * 12) end
    local cut = lp + (lp_end - lp) * k
    filt = filt + (s - filt) * cut
    local idx = offset + i
    if idx < total then buf[idx] = buf[idx] + filt * env * vol end
  end
  return n
end

local function apply_echo(buf, total, delay, feedback)
  local d = floor(delay * RATE)
  for i = d, total - 1 do buf[i] = buf[i] + buf[i - d] * feedback end
end

function Sound.synth(p)
  local tail = p.echo and (p.echo_delay or 0.12) * 4 or 0
  local total = floor(((p.duration or 0.3) + tail) * RATE) + 1
  local buf = ffi.new("float[?]", total)
  render_synth(p, buf, 0, total)
  if p.layers then
    for _, l in ipairs(p.layers) do render_synth(l, buf, floor((l.delay or 0) * RATE), total) end
  end
  if p.echo then apply_echo(buf, total, p.echo_delay or 0.12, p.echo) end
  return Sound.from_samples(buf, total, 1, RATE)
end

-- Ready-made retro effects. variation (number) gives a slightly different take.
local presets = {
  coin = { wave = "square", freq = 988, duration = 0.32, arp = { 0, 7, 12 }, arp_speed = 0.055, arp_once = true, release = 0.22, volume = 0.35, duty = 0.5 },
  jump = { wave = "square", freq = 240, freq_end = 620, curve = 0.6, duration = 0.22, duty = 0.25, release = 0.12, volume = 0.3 },
  land = { wave = "noise", freq = 300, freq_end = 80, duration = 0.12, lowpass = 0.25, release = 0.1, volume = 0.45 },
  laser = { wave = "saw", freq = 1400, freq_end = 180, curve = 0.5, duration = 0.2, release = 0.15, volume = 0.3 },
  explosion = { wave = "noise", freq = 900, freq_end = 60, duration = 0.9, lowpass = 0.6, lowpass_end = 0.03, release = 0.8, volume = 0.8 },
  hit = { wave = "square", freq = 320, freq_end = 90, duration = 0.14, noise = 0.5, release = 0.1, volume = 0.45 },
  powerup = { wave = "square", freq = 440, duration = 0.6, arp = { 0, 4, 7, 12, 16, 19, 24 }, arp_speed = 0.06, arp_once = true, release = 0.3, volume = 0.3, vibrato = 0.01, vibrato_rate = 12 },
  blip = { wave = "sine", freq = 880, duration = 0.07, release = 0.05, volume = 0.35 },
  select = { wave = "triangle", freq = 660, freq_end = 990, duration = 0.09, release = 0.06, volume = 0.4 },
  thud = { wave = "sine", freq = 140, freq_end = 45, duration = 0.25, release = 0.2, volume = 0.7, layers = { { wave = "noise", freq = 400, freq_end = 80, duration = 0.08, lowpass = 0.3, volume = 0.4 } } },
  whoosh = { wave = "noise", freq = 200, freq_end = 900, duration = 0.35, attack = 0.12, lowpass = 0.05, lowpass_end = 0.3, release = 0.2, volume = 0.4 },
  step = { wave = "noise", freq = 500, freq_end = 200, duration = 0.05, lowpass = 0.2, release = 0.04, volume = 0.25 },
  chime = { wave = "sine", freq = 1320, duration = 1.2, release = 1.1, volume = 0.3, echo = 0.35, echo_delay = 0.11, layers = { { wave = "sine", freq = 1980, duration = 1.0, release = 0.9, volume = 0.15 } } },
  bounce = { wave = "sine", freq = 300, freq_end = 520, duration = 0.12, release = 0.08, volume = 0.4 },
}

function Sound.preset(name, variation)
  local p = presets[name]
  assert(p, "unknown sound preset '" .. tostring(name) .. "'")
  local q = {}
  for k, v in pairs(p) do q[k] = v end
  if variation then
    local r = Random(variation)
    q.freq = q.freq * r:float(0.85, 1.15)
    if q.freq_end then q.freq_end = q.freq_end * r:float(0.85, 1.15) end
    q.seed = variation
  end
  return Sound.synth(q)
end
Sound.presets = presets

------------------------------------------------------------------ music builder
-- local m = SoundBuilder(16)              -- 16 seconds
-- m:note(0.0, "C4", 0.5, { wave = "triangle", volume = 0.2 })
-- m:build({ loop = true, reverb = 0.3 })  -> Sound
local note_index = { C = 0, ["C#"] = 1, Db = 1, D = 2, ["D#"] = 3, Eb = 3, E = 4, F = 5, ["F#"] = 6, Gb = 6, G = 7, ["G#"] = 8, Ab = 8, A = 9, ["A#"] = 10, Bb = 10, B = 11 }
function note_freq(n)
  if type(n) == "number" then return 440 * 2 ^ ((n - 69) / 12) end
  local name, oct = n:match("^([A-G][#b]?)(%-?%d)$")
  assert(name, "bad note name " .. n)
  local midi = (tonumber(oct) + 1) * 12 + note_index[name]
  return 440 * 2 ^ ((midi - 69) / 12)
end

SoundBuilder = class("SoundBuilder")
function SoundBuilder:_init(seconds)
  self.seconds = seconds
  self.frames = floor(seconds * RATE)
  self.buf = ffi.new("float[?]", self.frames)
end
function SoundBuilder:note(t, note, dur, opts)
  opts = opts or {}
  local p = {}
  for k, v in pairs(opts) do p[k] = v end
  -- note: name ("C4"), MIDI number (<= 127) or frequency in Hz (> 127)
  p.freq = (type(note) == "number" and note > 127) and note or note_freq(note)
  p.duration = dur
  p.wave = p.wave or "triangle"
  p.attack = p.attack or 0.01
  p.release = p.release or min(dur * 0.5, 0.3)
  p.sustain = p.sustain or 0.7
  local start = floor(t * RATE)
  -- Wrap long notes around the end so loops are seamless.
  local tmp = ffi.new("float[?]", floor(dur * RATE) + 1)
  local n = render_synth(p, tmp, 0, floor(dur * RATE) + 1)
  for i = 0, n - 1 do
    local idx = (start + i) % self.frames
    self.buf[idx] = self.buf[idx] + tmp[i]
  end
end
function SoundBuilder:drum(t, kind, volume)
  local v = volume or 0.5
  if kind == "kick" then self:note(t, 150, 0.22, { wave = "sine", freq_end = 40, volume = v, sustain = 1, release = 0.2, attack = 0.002 })
  elseif kind == "snare" then self:note(t, 900, 0.16, { wave = "noise", volume = v * 0.6, lowpass = 0.5, release = 0.14, attack = 0.001 })
  elseif kind == "hat" then self:note(t, 4000, 0.05, { wave = "noise", volume = v * 0.3, lowpass = 0.9, release = 0.04, attack = 0.001 })
  end
end
function SoundBuilder:build(opts)
  opts = opts or {}
  local buf, n = self.buf, self.frames
  if opts.reverb then
    -- A few feedback combs make a cheap, pleasant room.
    local out = ffi.new("float[?]", n)
    for i = 0, n - 1 do out[i] = buf[i] end
    for _, d in ipairs({ 0.0297, 0.0371, 0.0411, 0.0437 }) do
      local dl = floor(d * RATE * 3)
      local comb = ffi.new("float[?]", n)
      for pass = 1, 2 do  -- second pass wraps the tail into the loop start
        for i = 0, n - 1 do
          local j = i - dl
          if j < 0 then j = j + n end
          comb[i] = buf[i] + comb[j] * 0.72
        end
      end
      for i = 0, n - 1 do out[i] = out[i] + comb[i] * opts.reverb * 0.25 end
    end
    buf = out
  end
  local peak = 0
  for i = 0, n - 1 do peak = max(peak, abs(buf[i])) end
  local gain = peak > 0.95 and 0.95 / peak or 1
  if gain ~= 1 then for i = 0, n - 1 do buf[i] = buf[i] * gain end end
  return Sound.from_samples(buf, n, 1, RATE)
end

------------------------------------------------------------------ Audio helper
Audio = {}
-- opts: volume, pitch, pan, loop
function Audio.play(sound, opts)
  opts = opts or {}
  return C.gr_sound_play(sound.id, opts.volume or 1, opts.pitch or 1, opts.pan or 0, opts.loop and 1 or 0)
end
-- Positional one-shot at a world position.
function Audio.play_at(sound, pos, opts)
  opts = opts or {}
  return C.gr_sound_play_3d(sound.id, pos.x, pos.y, pos.z, opts.volume or 1, opts.pitch or 1, opts.loop and 1 or 0, opts.min_distance or 3, opts.max_distance or 80)
end
function Audio.stop(voice) C.gr_voice_stop(voice) end
function Audio.set_voice_volume(voice, v) C.gr_voice_volume(voice, v) end
function Audio.set_voice_pitch(voice, p) C.gr_voice_pitch(voice, p) end
function Audio.is_playing(voice) return C.gr_voice_playing(voice) == 1 end
function Audio.set_master_volume(v) C.gr_master_volume(v) end

------------------------------------------------------------------ AudioPlayer3D
AudioPlayer3D = Node3D:extend("AudioPlayer3D")
function AudioPlayer3D:_setup()
  Node3D._setup(self)
  self.volume = 1
  self.pitch = 1
  self.loop = false
  self.autoplay = false
  self.positional = true
  self.min_distance = 3
  self.max_distance = 60
end
function AudioPlayer3D:__enter() if self.autoplay then self:play() end end
function AudioPlayer3D:__exit() self:stop() end
function AudioPlayer3D:play()
  self:stop()
  if not self.sound then return end
  if self.positional then
    local p = self:global_position()
    self._voice = C.gr_sound_play_3d(self.sound.id, p.x, p.y, p.z, self.volume, self.pitch, self.loop and 1 or 0, self.min_distance, self.max_distance)
  else
    self._voice = C.gr_sound_play(self.sound.id, self.volume, self.pitch, 0, self.loop and 1 or 0)
  end
end
function AudioPlayer3D:stop()
  if self._voice then C.gr_voice_stop(self._voice); self._voice = nil end
end
function AudioPlayer3D:is_playing() return self._voice ~= nil and C.gr_voice_playing(self._voice) == 1 end
function AudioPlayer3D:__sync(vis, gp)
  if self._voice then
    if self.positional then C.gr_voice_position(self._voice, gp.x, gp.y, gp.z) end
    C.gr_voice_volume(self._voice, self.volume)
    C.gr_voice_pitch(self._voice, self.pitch)
  end
end
