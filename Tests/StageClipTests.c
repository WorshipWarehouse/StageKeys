#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static const float TAU_F = 6.28318530718f;

static void setup(SKSynth *s, int stage, float drive, float tone, float symmetry, float mix,
                  float clipFilter, float sumLowPass, float shelfGain, float shelfFrequency,
                  float inputGain, float outputGain) {
    sk_effect(s, 0, 0, 17, 1);
    float p[] = {drive, tone, symmetry, mix, clipFilter, sumLowPass, shelfGain, shelfFrequency,
                 inputGain, outputGain, (float)stage};
    for (int i = 0; i < 11; i++) sk_effect_parameter(s, 0, 0, i, p[i]);
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

static float maxJumper(const float *x, int n, float before) {
    float jump = 0;
    for (int i = 0; i < n; i++) {
        float d = fabsf(x[i] - before);
        if (d > jump) jump = d;
    }
    return jump;
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

        // Both cores retain the same static signal path up to ADAA branch rounding;
        // Stage Clip changes how controls move.
        setup(a, 1, 15, 170, -16, .45f, 4400, 5300, 0, 980, 0, 5);
        setup(old, 0, 15, 170, -16, .45f, 4400, 5300, 0, 980, 0, 5);
        sine(input, n, rate, 220, .16f);
        for (int i = 0; i < n; i++) stage[i] = legacy[i] = input[i];
        sk_process_effects(a, stage, n);
        sk_process_effects(old, legacy, n);
        bounded(stage, n);
        bounded(legacy, n);
        double staticDifference = 0;
        for (int i = 0; i < n; i++) {
            double d = (double)stage[i] - legacy[i];
            staticDifference += d * d;
        }
        assert(staticDifference < 1e-4);

        // A large drive step must ramp instead of switching to the new curve.
        setup(a, 1, 0, 170, -16, .45f, 4400, 5300, 0, 980, 0, 5);
        setup(old, 0, 0, 170, -16, .45f, 4400, 5300, 0, 980, 0, 5);
        for (int i = 0; i < n; i++) stage[i] = legacy[i] = input[i];
        sk_process_effects(a, stage, n);
        sk_process_effects(old, legacy, n);
        float before = stage[n - 1];
        for (int i = 0; i < 128; i++) {
            stage[i] = legacy[i] = .16f * sinf(TAU_F * 220 * (n + i) / rate);
        }
        sk_effect_parameter(a, 0, 0, 0, 60);
        sk_effect_parameter(old, 0, 0, 0, 60);
        sk_process_effects(a, stage, 128);
        sk_process_effects(old, legacy, 128);
        float stageJump = maxJumper(stage, 4, before), legacyJump = maxJumper(legacy, 4, before);
        assert(stageJump > 0 && legacyJump > stageJump * 2);

        // Symmetry and filter automation also stay finite and bounded.
        for (int block = 0; block < 96; block++) {
            float value = (float)(block % 17) / 16;
            sk_effect_parameter(a, 0, 0, 1, 20 + 19980 * value);
            sk_effect_parameter(a, 0, 0, 2, -100 + 200 * value);
            sk_effect_parameter(a, 0, 0, 3, value);
            sk_effect_parameter(a, 0, 0, 4, 20 + 19980 * value);
            sk_effect_parameter(a, 0, 0, 5, 20 + 19980 * value);
            sk_effect_parameter(a, 0, 0, 6, -30 + 60 * value);
            sk_effect_parameter(a, 0, 0, 7, 20 + 19980 * value);
            sk_effect_parameter(a, 0, 0, 8, -60 + 120 * value);
            sk_effect_parameter(a, 0, 0, 9, -60 + 120 * value);
            sine(stage, 128, rate, 330, .12f);
            sk_process_effects(a, stage, 128);
            bounded(stage, 128);
        }

        // Panic clears the stage and the legacy paths.
        sk_panic(a);
        for (int i = 0; i < 512; i++) stage[i] = 0;
        sk_process_effects(a, stage, 512);
        for (int i = 0; i < 512; i++) assert(stage[i] == 0);

        sk_destroy(a);
        sk_destroy(old);

        // Eight independent live instances remain finite and bounded.
        SKSynth *instances[8];
        for (int i = 0; i < 8; i++) {
            instances[i] = sk_create_effects(rate);
            assert(instances[i]);
            setup(instances[i], 1, 20, 9000, -30, .5f, 7000, 8000, 3, 1200, 0, 0);
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
        printf("PASS Stage Clip %d Hz: static path, smoothed drive, automation, Panic, eight instances\n", rate);
    }
    puts("PASS all Stage Clip tests");
    return 0;
}
