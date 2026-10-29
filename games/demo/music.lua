-- A gentle procedural music loop, generated at startup with SoundBuilder.
local Music = {}

function Music.build()
  local bpm = 84
  local beat = 60 / bpm
  local bars = 8
  local m = SoundBuilder(bars * 4 * beat)
  -- I - vi - IV - V in C major, twice.
  local chords = {
    { "C3", "E3", "G3", "B3" }, { "A2", "C3", "E3", "G3" }, { "F2", "A2", "C3", "E3" }, { "G2", "B2", "D3", "F3" },
  }
  local melody_scale = { "C5", "D5", "E5", "G5", "A5", "C6" }
  local r = Random(9)
  for bar = 0, bars - 1 do
    local chord = chords[bar % 4 + 1]
    local t0 = bar * 4 * beat
    -- Soft pad.
    for _, n in ipairs(chord) do
      m:note(t0, n, 4 * beat, { wave = "triangle", volume = 0.07, attack = 0.6, release = 1.2, sustain = 0.8, lowpass = 0.12, vibrato = 0.003, vibrato_rate = 4 })
    end
    -- Bass.
    m:note(t0, chord[1]:gsub("%d", function(d) return tostring(tonumber(d) - 1) end), 2 * beat, { wave = "sine", volume = 0.22, release = 0.6 })
    m:note(t0 + 2 * beat, chord[1]:gsub("%d", function(d) return tostring(tonumber(d) - 1) end), 2 * beat, { wave = "sine", volume = 0.18, release = 0.6 })
    -- Plucked arpeggio in eighths.
    for i = 0, 7 do
      local n = chord[(i % 4) + 1]:gsub("%d", function(d) return tostring(tonumber(d) + 1) end)
      m:note(t0 + i * beat / 2, n, beat * 0.9, { wave = "square", duty = 0.3, volume = 0.035, attack = 0.003, release = 0.35, sustain = 0.3, lowpass = 0.18 })
    end
    -- A sparse melody in the second half.
    if bar >= 4 then
      for i = 0, 3 do
        if r:chance(0.7) then
          m:note(t0 + i * beat + (r:chance(0.3) and beat / 2 or 0), r:pick(melody_scale), beat * 1.2,
            { wave = "sine", volume = 0.09, attack = 0.01, release = 0.5, sustain = 0.5, vibrato = 0.006, vibrato_rate = 5 })
        end
      end
    end
    -- Light percussion.
    for i = 0, 3 do
      if i % 2 == 0 then m:drum(t0 + i * beat, "kick", 0.35) end
      m:drum(t0 + i * beat + beat / 2, "hat", 0.25)
    end
  end
  return m:build({ reverb = 0.35 })
end

return Music
