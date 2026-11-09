#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static const float TAU_F = 6.28318530718f;

static void setup(SKSynth *s, int stage, float semitones, float amount) {
    sk_effect(s, 0, 0, 12, 1);
    sk_effect_parameter(s, 0, 0, 0, semitones);
    sk_effect_parameter(s, 0, 0, 1, amount);
    sk_effect_parameter(s, 0, 0, 2, (float)stage);
}

static void sine(float *x, int n, int rate, float hz, float amplitude) {
    for (int i = 0; i < n; i++) x[i] = amplitude * sinf(TAU_F * hz * i / rate);
}

static void bounded(const float *x, int n) {
    for (int i = 0; i < n; i++) {
        assert(isfinite(x[i]));
        assert(fabsf(x[i]) < 20);
    }
}

static double powerAt(const float *x, int n, double hz, int rate) {
    double real = 0, imaginary = 0;
    for (int i = 0; i < n; i++) {
        double phase = TAU_F * hz * i / rate;
        real += x[i] * cos(phase);
        imaginary += x[i] * sin(phase);
    }
    return real * real + imaginary * imaginary;
}

int main(void) {
    const int rates[] = {44100, 48000, 96000};
    for (int r = 0; r < 3; r++) {
        int rate = rates[r], n = rate * 2;
        float *stage = calloc((size_t)n, sizeof(float));
        float *legacy = calloc((size_t)n, sizeof(float));
        float *input = calloc((size_t)n, sizeof(float));
        assert(stage && legacy && input);
        SKSynth *a = sk_create_effects(rate), *old = sk_create_effects(rate);
        assert(a && old);

        // Pitch 0 and Amount 0 must be exact dry, not a delayed or attenuated copy.
        setup(a, 1, 0, 1);
        setup(old, 0, 0, 1);
        sine(input, n, rate, 220, .16f);
        for (int i = 0; i < n; i++) stage[i] = legacy[i] = input[i];
        sk_process_effects(a, stage, n);
        sk_process_effects(old, legacy, n);
        for (int i = 0; i < n; i++) {
            assert(stage[i] == input[i]);
            assert(legacy[i] == input[i]);
        }

        // Amount 0 is likewise exact dry even when Pitch is non-zero.
        sk_panic(a);
        setup(a, 1, 12, 0);
        sine(input, n, rate, 330, .16f);
        for (int i = 0; i < n; i++) stage[i] = input[i];
        sk_process_effects(a, stage, n);
        for (int i = 0; i < n; i++) assert(stage[i] == input[i]);

        // Upward and downward shifts must produce the expected fundamental.
        sk_panic(a);
        setup(a, 1, 12, 1);
        sine(input, n, rate, 220, .16f);
        for (int i = 0; i < n; i++) stage[i] = input[i];
        sk_process_effects(a, stage, n);
        bounded(stage, n);
        double up = powerAt(stage + rate / 2, rate / 2, 440, rate);
        double fundamental = powerAt(stage + rate / 2, rate / 2, 220, rate);
        assert(up > fundamental * 4);

        sk_panic(a);
        setup(a, 1, -12, 1);
        sine(input, n, rate, 440, .16f);
        for (int i = 0; i < n; i++) stage[i] = input[i];
        sk_process_effects(a, stage, n);
        bounded(stage, n);
        double down = powerAt(stage + rate / 2, rate / 2, 220, rate);
        fundamental = powerAt(stage + rate / 2, rate / 2, 440, rate);
        assert(down > fundamental * 4);

        // A wet/dry step must ramp rather than replacing the direct signal at once.
        sk_panic(a);
        setup(a, 1, 12, 0);
        sine(input, rate / 2, rate, 220, .16f);
        for (int i = 0; i < rate / 2; i++) stage[i] = input[i];
        sk_process_effects(a, stage, rate / 2);
        sk_effect_parameter(a, 0, 0, 1, 1);
        sine(input, 256, rate, 220, .16f);
        for (int i = 0; i < 256; i++) stage[i] = input[i];
        sk_process_effects(a, stage, 256);
        for (int i = 0; i < 4; i++) assert(fabsf(stage[i] - input[i]) < .02f);

        // Rapid pitch/amount automation remains finite and bounded.
        for (int block = 0; block < 96; block++) {
            float semitones = (float)((block % 13) - 6);
            float amount = (float)(block % 17) / 16;
            sk_effect_parameter(a, 0, 0, 0, semitones);
            sk_effect_parameter(a, 0, 0, 1, amount);
            sine(stage, 128, rate, 330, .12f);
            sk_process_effects(a, stage, 128);
            bounded(stage, 128);
        }

        // Panic clears the delay line and both heads.
        sk_panic(a);
        for (int i = 0; i < 512; i++) stage[i] = 0;
        sk_process_effects(a, stage, 512);
        for (int i = 0; i < 512; i++) assert(stage[i] == 0);

        sk_destroy(a);
        sk_destroy(old);

        // Eight independent instances remain finite and bounded.
        SKSynth *instances[8];
        for (int i = 0; i < 8; i++) {
            instances[i] = sk_create_effects(rate);
            assert(instances[i]);
            setup(instances[i], 1, 7, .5f);
        }
        for (int block = 0; block < 8; block++) {
            for (int i = 0; i < 8; i++) {
                for (int j = 0; j < 256; j++) {
                    stage[j] = .10f * sinf(TAU_F * (180 + 20 * i) * (block * 256 + j) / rate);
                }
                sk_process_effects(instances[i], stage, 256);
                bounded(stage, 256);
            }
        }
        for (int i = 0; i < 8; i++) sk_destroy(instances[i]);

        free(stage);
        free(legacy);
        free(input);
        printf("PASS Stage Pitch %d Hz: exact dry, pitch content, smoothing, automation, Panic, eight instances\n", rate);
    }
    puts("PASS all Stage Pitch tests");
    return 0;
}
