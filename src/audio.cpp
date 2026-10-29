// Audio server on miniaudio: decoded sounds, fire-and-forget voices, 3D positioning.
#include "core.hpp"
#include "miniaudio.h"

struct Sound { float* data = nullptr; ma_uint64 frames = 0; int channels = 1, rate = 44100; bool owned_by_ma = false; };
struct Voice { ma_audio_buffer_ref ref; ma_sound snd; int sound = 0; bool loop = false; };

static ma_engine engine;
static bool ok = false;
static Pool<Sound> sounds;
static const int MAX_VOICES = 128;
static Voice* voices[MAX_VOICES];
static int voice_gen[MAX_VOICES];

static void free_voice(int i) {
  if (!voices[i]) return;
  ma_sound_uninit(&voices[i]->snd);
  ma_audio_buffer_ref_uninit(&voices[i]->ref);
  delete voices[i];
  voices[i] = nullptr;
  voice_gen[i]++;
}

static void collect_finished() {
  for (int i = 0; i < MAX_VOICES; i++)
    if (voices[i] && !voices[i]->loop && ma_sound_at_end(&voices[i]->snd)) free_voice(i);
}

static Voice* voice_from(int handle) {
  int i = handle & 0xFFF, g = handle >> 12;
  if (handle <= 0 || i >= MAX_VOICES || !voices[i] || voice_gen[i] != g) return nullptr;
  return voices[i];
}

bool audio_init() {
  ma_engine_config cfg = ma_engine_config_init();
  ok = ma_engine_init(&cfg, &engine) == MA_SUCCESS;
  return ok;
}

static void free_sound(Sound& s) {
  if (!s.data) return;
  if (s.owned_by_ma) ma_free(s.data, nullptr);
  else delete[] s.data;
  s.data = nullptr;
}

void audio_reset() {
  for (int i = 0; i < MAX_VOICES; i++) free_voice(i);
  sounds.each([](int, Sound& s) { free_sound(s); });
  sounds.clear();
  if (ok) ma_engine_set_volume(&engine, 1.0f);
}

void audio_shutdown() {
  audio_reset();
  if (ok) ma_engine_uninit(&engine);
  ok = false;
}

static int start_voice(int snd, float volume, float pitch, int loop, bool spatial) {
  if (!ok) return 0;
  Sound* s = sounds.get(snd);
  if (!s) return 0;
  collect_finished();
  int slot = -1;
  for (int i = 0; i < MAX_VOICES; i++) if (!voices[i]) { slot = i; break; }
  if (slot < 0) return 0;
  Voice* v = new Voice();
  v->sound = snd;
  v->loop = loop;
  ma_audio_buffer_ref_init(ma_format_f32, s->channels, s->data, s->frames, &v->ref);
  v->ref.sampleRate = s->rate;
  ma_uint32 flags = spatial ? 0 : MA_SOUND_FLAG_NO_SPATIALIZATION;
  if (ma_sound_init_from_data_source(&engine, &v->ref, flags, nullptr, &v->snd) != MA_SUCCESS) {
    ma_audio_buffer_ref_uninit(&v->ref);
    delete v;
    return 0;
  }
  ma_sound_set_volume(&v->snd, volume);
  ma_sound_set_pitch(&v->snd, pitch > 0.01f ? pitch : 0.01f);
  ma_sound_set_looping(&v->snd, loop ? MA_TRUE : MA_FALSE);
  voices[slot] = v;
  return slot | (voice_gen[slot] << 12);
}

extern "C" {

int gr_sound_load(const char* path) {
  if (!ok) return 0;
  ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 0, 0);
  ma_uint64 frames = 0;
  void* data = nullptr;
  ma_decoder dec;
  if (ma_decoder_init_file(path, &cfg, &dec) != MA_SUCCESS) { fprintf(stderr, "[grove] could not load sound %s\n", path); return 0; }
  int ch = dec.outputChannels, rate = dec.outputSampleRate;
  ma_decoder_uninit(&dec);
  if (ma_decode_file(path, &cfg, &frames, &data) != MA_SUCCESS) return 0;
  Sound s;
  s.data = (float*)data; s.frames = frames; s.channels = ch; s.rate = rate; s.owned_by_ma = true;
  return sounds.add(s);
}

int gr_sound_create(const float* samples, int frames, int channels, int rate) {
  Sound s;
  s.data = new float[(size_t)frames * channels];
  memcpy(s.data, samples, sizeof(float) * frames * channels);
  s.frames = frames; s.channels = channels; s.rate = rate;
  return sounds.add(s);
}

void gr_sound_free(int snd) {
  Sound* s = sounds.get(snd);
  if (!s) return;
  for (int i = 0; i < MAX_VOICES; i++) if (voices[i] && voices[i]->sound == snd) free_voice(i);
  free_sound(*s);
  sounds.remove(snd);
}

int gr_sound_play(int snd, float volume, float pitch, float pan, int loop) {
  int h = start_voice(snd, volume, pitch, loop, false);
  if (Voice* v = voice_from(h)) { ma_sound_set_pan(&v->snd, pan); ma_sound_start(&v->snd); }
  return h;
}

int gr_sound_play_3d(int snd, float x, float y, float z, float volume, float pitch, int loop, float min_d, float max_d) {
  int h = start_voice(snd, volume, pitch, loop, true);
  if (Voice* v = voice_from(h)) {
    ma_sound_set_position(&v->snd, x, y, z);
    ma_sound_set_attenuation_model(&v->snd, ma_attenuation_model_inverse);
    ma_sound_set_min_distance(&v->snd, min_d > 0 ? min_d : 2.0f);
    ma_sound_set_max_distance(&v->snd, max_d > 0 ? max_d : 60.0f);
    ma_sound_set_rolloff(&v->snd, 1.0f);
    ma_sound_start(&v->snd);
  }
  return h;
}

void gr_voice_stop(int h) { int i = h & 0xFFF; if (voice_from(h)) free_voice(i); }
void gr_voice_volume(int h, float vol) { if (Voice* v = voice_from(h)) ma_sound_set_volume(&v->snd, vol); }
void gr_voice_pitch(int h, float p) { if (Voice* v = voice_from(h)) ma_sound_set_pitch(&v->snd, p > 0.01f ? p : 0.01f); }
void gr_voice_position(int h, float x, float y, float z) { if (Voice* v = voice_from(h)) ma_sound_set_position(&v->snd, x, y, z); }
int gr_voice_playing(int h) { Voice* v = voice_from(h); return v && !ma_sound_at_end(&v->snd); }

void gr_listener(float px, float py, float pz, float fx, float fy, float fz) {
  if (!ok) return;
  ma_engine_listener_set_position(&engine, 0, px, py, pz);
  ma_engine_listener_set_direction(&engine, 0, fx, fy, fz);
  ma_engine_listener_set_world_up(&engine, 0, 0, 1, 0);
}

void gr_master_volume(float v) { if (ok) ma_engine_set_volume(&engine, v); }

}  // extern "C"
