-- Procedural music: a dusty spaghetti-western loop for the desert and a faster one for HU-MAN.
local Music = {}

local function down(n) return (n:gsub("%d", function(d) return tostring(tonumber(d) - 1) end)) end

function Music.desert()
  local bpm = 92
  local beat = 60 / bpm
  local bars = 8
  local m = SoundBuilder(bars * 4 * beat)
  -- A minor, with the classic western bVII and V turns.
  local chords = { { "A2", "C3", "E3" }, { "G2", "B2", "D3" }, { "F2", "A2", "C3" }, { "E2", "G#2", "B2" } }
  local melody = {
    { "E5", 0, 1.5 }, { "D5", 1.5, 0.5 }, { "C5", 2, 1 }, { "A4", 3, 1 },
    { "B4", 4, 1.5 }, { "G4", 5.5, 0.5 }, { "D5", 6, 2 },
    { "C5", 8, 1 }, { "A4", 9, 1 }, { "F4", 10, 1 }, { "A4", 11, 1 },
    { "G#4", 12, 2 }, { "B4", 14, 1 }, { "E5", 15, 1 },
  }
  for bar = 0, bars - 1 do
    local ch = chords[bar % 4 + 1]
    local t0 = bar * 4 * beat
    -- Galloping bass: root on 1 and 3, fifth on the "and".
    for i = 0, 3 do
      local n = (i % 2 == 0) and down(ch[1]) or down(ch[3])
      m:note(t0 + i * beat, n, beat * 0.6, { wave = "triangle", volume = 0.26, release = 0.15 })
      m:note(t0 + i * beat + beat * 0.75, down(ch[1]), beat * 0.2, { wave = "triangle", volume = 0.14, release = 0.08 })
    end
    -- Twangy strummed chord (saw, low-passed) with tremolo.
    for k, n in ipairs(ch) do
      m:note(t0 + (k - 1) * 0.02, n:gsub("%d", function(d) return tostring(tonumber(d) + 1) end), beat * 1.8,
        { wave = "saw", volume = 0.045, lowpass = 0.08, release = 0.6, sustain = 0.4, vibrato = 0.004, vibrato_rate = 6 })
      m:note(t0 + 2 * beat + (k - 1) * 0.02, n:gsub("%d", function(d) return tostring(tonumber(d) + 1) end), beat * 1.8,
        { wave = "saw", volume = 0.035, lowpass = 0.08, release = 0.6, sustain = 0.4 })
    end
    -- Whistled melody in the second half.
    if bar >= 4 then
      local off = (bar - 4) * 4
      for _, nt in ipairs(melody) do
        if nt[2] >= off and nt[2] < off + 4 then
          m:note(t0 + (nt[2] - off) * beat, nt[1], nt[3] * beat, { wave = "sine", volume = 0.1, attack = 0.04, release = 0.3, sustain = 0.6, vibrato = 0.012, vibrato_rate = 5.5 })
        end
      end
    end
    -- Brushy percussion and a woodblock "clip-clop".
    for i = 0, 3 do
      m:drum(t0 + i * beat, i % 2 == 0 and "kick" or "snare", i % 2 == 0 and 0.3 or 0.18)
      m:note(t0 + i * beat + beat * 0.5, 1800, 0.04, { wave = "square", volume = 0.04, release = 0.03, lowpass = 0.3 })
    end
  end
  return m:build({ reverb = 0.45 })
end

function Music.boss()
  local bpm = 148
  local beat = 60 / bpm
  local bars = 8
  local m = SoundBuilder(bars * 4 * beat)
  local roots = { "E2", "E2", "C2", "D2", "E2", "E2", "G2", "D2" }
  local riff = { 0, 0, 12, 0, 10, 0, 7, 5 }
  for bar = 0, bars - 1 do
    local t0 = bar * 4 * beat
    local root = note_freq(roots[bar + 1])
    for i = 0, 7 do
      local f = root * 2 ^ (riff[i + 1] / 12)
      m:note(t0 + i * beat / 2, f, beat * 0.45, { wave = "saw", volume = 0.12, lowpass = 0.12, release = 0.08, sustain = 0.8 })
      m:note(t0 + i * beat / 2, f * 2, beat * 0.45, { wave = "square", duty = 0.3, volume = 0.04, lowpass = 0.2, release = 0.06 })
    end
    for i = 0, 3 do
      m:drum(t0 + i * beat, "kick", 0.45)
      if i % 2 == 1 then m:drum(t0 + i * beat, "snare", 0.4) end
      m:drum(t0 + i * beat + beat / 2, "hat", 0.3)
    end
    if bar % 2 == 1 then
      m:note(t0, root * 4, beat * 3, { wave = "square", duty = 0.2, volume = 0.05, vibrato = 0.02, vibrato_rate = 7, release = 0.5 })
    end
  end
  return m:build({ reverb = 0.25 })
end

return Music
