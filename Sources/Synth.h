#pragma once
#include <stdint.h>
#include <CoreMIDI/CoreMIDI.h>
typedef struct SKSynth SKSynth;
typedef struct SKOutputMeter SKOutputMeter;
SKOutputMeter *sk_output_meter_create(void);
void sk_output_meter_destroy(SKOutputMeter *meter);
// One render producer. No allocation, locks, file I/O or signal mutation.
void sk_output_meter_process(SKOutputMeter *meter,const float *left,const float *right,uint32_t frames);
void sk_output_meter_read(SKOutputMeter *meter,float *peak,float *rms,uint64_t *frames,uint64_t *invalid,uint64_t *overload);
SKSynth *sk_create(double sampleRate);
void sk_destroy(SKSynth *s);
// Lightweight three-slot effects-only engine, single producer/render consumer.
SKSynth *sk_create_effects(double sampleRate);
SKSynth *sk_create_effects_with_capacity(double rate,double seconds);
void sk_imported_delay(SKSynth *s,int slot,int enabled,float leftSeconds,float rightSeconds,int pingPong,float lowCut,float highCut);
void sk_process_effects_stereo(SKSynth *leftState,SKSynth *rightState,float *left,float *right,uint32_t frames);
void sk_process_effects(SKSynth *s,float *audio,uint32_t frames);
// Single producer (main queue), single consumer (audio render thread).
void sk_note_on(SKSynth *s, int key, int pitch, int instrument, int layer, float velocity);
void sk_note_off(SKSynth *s, int key);
void sk_note_off_channel(SKSynth *s,int key,int layer,int forceRelease);
void sk_gain(SKSynth *s, int layer, float gain, float seconds);
void sk_effect(SKSynth *s, int layer, int slot, int kind, float amount);
void sk_pan(SKSynth *s, int layer, float pan);
void sk_block_sustain(SKSynth *s, int layer, int enabled);
// Tempo for synced effects. The metronome is a separate engine; see SKMetronome.
void sk_clock(SKSynth *s, float tempo);
void sk_sustain(SKSynth *s, int enabled);
void sk_panic(SKSynth *s);
void sk_panic_channel(SKSynth *s,int layer);
// Release voices without clearing effect histories; explicit Panic still clears all.
void sk_release_voices(SKSynth *s,int layer);
void sk_render(SKSynth *s, float *left, float *right, uint32_t frames);
typedef void (*SKMIDIEvent)(void *context, uint8_t status, uint8_t data1, uint8_t data2);
void sk_read_midi(const MIDIEventList *list, SKMIDIEvent callback, void *context);

// Per-channel synthesis/DSP. Times in seconds, gain linear, filter resonance Q.
void sk_envelope(SKSynth *s,int layer,float attack,float decay,float sustain,float release);
void sk_voice_limit(SKSynth *s,int layer,int voices);
void sk_sampler_gain(SKSynth *s,int layer,float gain);
void sk_filter(SKSynth *s,int layer,float cutoff,float resonance);
void sk_eq(SKSynth *s,int layer,int band,float frequency,float gainDB,float q);
void sk_compressor(SKSynth *s,int layer,int enabled,float thresholdDB,float ratio,float attack,float release,float makeupDB);

// Physical parameter values and indices match AudioEffectCatalog descriptors.
void sk_effect_parameter(SKSynth *s,int layer,int slot,int parameterIndex,float value);

void sk_compressor_blend(SKSynth *s,int layer,float inputGainDB,float wet);

void sk_imported_delay_channel(SKSynth*s,int slot,int enabled,float feedback,float crossFeedback,float mix,int input);
void sk_imported_delay_levels(SKSynth*s,int slot,int enabled,float dry,float wet);

// Independent metronome click engine. It never enters the synth's shared
// reverb or limiter. The control thread publishes settings through a bounded
// single-producer/single-consumer queue; rendering allocates and locks nothing.
// `level` scales a click capped at 0.2 peak before the host's output headroom.
typedef struct SKMetronome SKMetronome;
typedef struct {
    float level;            // 0...1
    int preset;             // 0 click, 1 woodblock
    float beatVelocity;     // 0...1, also the accent base
    int downbeatEnabled;
    float downbeatVelocity; // 0...1
    int beatsPerBar;        // 1...16
    int accentEvery;        // 0 off, 1...16 beats
    int subdivision;        // 1...4 clicks per beat
} SKMetronomeSettings;
SKMetronome *sk_metronome_create(double sampleRate);
void sk_metronome_destroy(SKMetronome *m);
void sk_metronome_settings(SKMetronome *m, SKMetronomeSettings settings);
void sk_metronome_enable(SKMetronome *m, int enabled);
void sk_metronome_tempo(SKMetronome *m, float tempo);
// Output gain: follow the performance master, or hold the click's own level.
void sk_metronome_master(SKMetronome *m, float volume, int followsMaster);
void sk_metronome_reset(SKMetronome *m);
void sk_metronome_render(SKMetronome *m, float *left, float *right, uint32_t frames);
