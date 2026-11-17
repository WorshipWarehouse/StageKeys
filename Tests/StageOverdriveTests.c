#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static const float TAU_F = 6.28318530718f;

static void setup(SKSynth *s, int stage, float drive, float low, float tone, float mix, float boost) {
    sk_effect(s, 0, 0, 11, 1);
    float p[] = {drive, low, tone, mix, boost, (float)stage};
    for (int i = 0; i < 6; i++) sk_effect_parameter(s, 0, 0, i, p[i]);
}

static void sine(float *x, int n, int rate, float hz, float amplitude) {
    for (int i = 0; i < n; i++) x[i] = amplitude * sinf(TAU_F * hz * i / rate);
}

static void bounded(const float *x, int n) {
    for (int i = 0; i < n; i++) {
        assert(isfinite(x[i]));
        assert(fabsf(x[i]) < 4);
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

static double powerAt(const float *x, int n, int rate, double hz) {
    double re = 0, im = 0;
    for (int i = 0; i < n; i++) {
        double window = .5 - .5 * cos(2 * 3.14159265358979323846 * i / (n - 1));
        double angle = 2 * 3.14159265358979323846 * hz * i / rate;
        re += window * x[i] * cos(angle);
        im -= window * x[i] * sin(angle);
    }
    return re * re + im * im;
}

static double bandPower(const float *x, int n, int rate, double hz) {
    double power = 0;
    for (int offset = -2; offset <= 2; offset++) power += powerAt(x, n, rate, hz + offset);
    return power;
}

int main(void) {
    const int rates[] = {44100, 48000, 96000};
    for (int r = 0; r < 3; r++) {
        int rate = rates[r], n = rate * 2;
        float *dry = calloc((size_t)n, sizeof(float));
        float *stage = calloc((size_t)n, sizeof(float));
        float *legacy = calloc((size_t)n, sizeof(float));
        float *out = calloc((size_t)n, sizeof(float));
        assert(dry && stage && legacy && out);
        sine(dry, n, rate, 220, .16f);
        for (int i = 0; i < n; i++) stage[i] = legacy[i] = dry[i];

        SKSynth *a = sk_create_effects(rate), *old = sk_create_effects(rate);
        assert(a && old);
        setup(a, 1, .96f, 20, 20000, 0, 0);
        sk_process_effects(a, stage, n);
        // Mix 0 with unity boost is an exact, state-free direct path.
        for (int i = 0; i < n; i++) assert(stage[i] == dry[i]);

        setup(old, 0, .96f, 20, 20000, 0, 0);
        sk_process_effects(old, legacy, n);
        setup(a, 1, .96f, 402, 4877, .4f, 2);
        setup(old, 0, .96f, 402, 4877, .4f, 2);
        for (int i = 0; i < n; i++) stage[i] = legacy[i] = dry[i];
        sk_process_effects(a, stage, n);
        sk_process_effects(old, legacy, n);
        double different = 0;
        for (int i = 0; i < n; i++) {
            double d = (double)stage[i] - legacy[i];
            different += d * d;
        }
        assert(different > 1e-5);
        bounded(stage, n);
        bounded(legacy, n);

        // A mix step must not hard-switch to the saturated path.
        setup(a, 1, 1, 20, 20000, 0, 0);
        setup(old, 0, 1, 20, 20000, 0, 0);
        sine(out, n, rate, 440, .30f);
        for (int i = 0; i < n; i++) stage[i] = legacy[i] = out[i];
        sk_process_effects(a, out, n);
        float before = out[n - 1];
        for (int i = 0; i < n; i++) out[i] = 0;
        sk_effect_parameter(a, 0, 0, 3, 1);
        sk_effect_parameter(old, 0, 0, 3, 1);
        for (int i = 0; i < 128; i++) out[i] = .30f * sinf(TAU_F * 440 * (n + i) / rate);
        for (int i = 0; i < 128; i++) stage[i] = legacy[i] = out[i];
        sk_process_effects(a, stage, 128);
        sk_process_effects(old, legacy, 128);
        float stageJump = maxJumper(stage, 128, before), legacyJump = maxJumper(legacy, 128, before);
        assert(stageJump > 0 && legacyJump > stageJump * 2);

        // Fast automation stays finite and bounded at every sample.
        for (int block = 0; block < 96; block++) {
            float value = (float)(block % 17) / 16;
            sk_effect_parameter(a, 0, 0, 0, value);
            sk_effect_parameter(a, 0, 0, 1, 20 + 780 * value);
            sk_effect_parameter(a, 0, 0, 2, 600 + 19400 * value);
            sk_effect_parameter(a, 0, 0, 3, value);
            sk_effect_parameter(a, 0, 0, 4, -24 + 36 * value);
            sine(stage, 128, rate, 330, .12f);
            sk_process_effects(a, stage, 128);
            bounded(stage, 128);
        }

        // Panic clears both the Stage state and the direct path.
        sk_panic(a);
        for (int i = 0; i < 512; i++) stage[i] = 0;
        sk_process_effects(a, stage, 512);
        for (int i = 0; i < 512; i++) assert(stage[i] == 0);

        // A fixed 8.64 kHz probe at 48 kHz places the third through eighth
        // harmonics at measurable non-harmonic alias bins. This is an alias
        // diagnostic, not a listening or oversampling claim.
        if (rate == 48000) {
            setup(a, 1, 1, 20, 20000, 1, 0);
            setup(old, 0, 1, 20, 20000, 1, 0);
            for (int i = 0; i < n; i++) stage[i] = legacy[i] = .12f * sinf(TAU_F * 8640 * i / rate);
            sk_process_effects(a, stage, n);
            sk_process_effects(old, legacy, n);
            const double aliases[] = {22080, 13440, 4800, 3840, 12480, 21120};
            double stageAlias = 0, legacyAlias = 0;
            for (int i = 0; i < 6; i++) {
                stageAlias += bandPower(stage + rate, rate, rate, aliases[i]);
                legacyAlias += bandPower(legacy + rate, rate, rate, aliases[i]);
            }
            double stageFundamental = bandPower(stage + rate, rate, rate, 8640);
            double legacyFundamental = bandPower(legacy + rate, rate, rate, 8640);
            assert(stageAlias / stageFundamental < .5 * legacyAlias / legacyFundamental);
            printf("INFO 48 kHz alias/fundamental: stage=%.6g legacy=%.6g\n", stageAlias / stageFundamental, legacyAlias / legacyFundamental);
        }

        sk_destroy(a);
        sk_destroy(old);

        // Eight independent live instances remain finite and bounded.
        SKSynth *instances[8];
        for (int i = 0; i < 8; i++) {
            instances[i] = sk_create_effects(rate);
            assert(instances[i]);
            setup(instances[i], 1, .85f, 60, 8000, .5f, 0);
        }
        for (int block = 0; block < 8; block++) {
            for (int i = 0; i < 8; i++) {
                for (int j = 0; j < 256; j++) out[j] = .10f * sinf(TAU_F * (180 + 20 * i) * (block * 256 + j) / rate);
                sk_process_effects(instances[i], out, 256);
                bounded(out, 256);
            }
        }
        for (int i = 0; i < 8; i++) sk_destroy(instances[i]);
        free(dry);
        free(stage);
        free(legacy);
        free(out);

        printf("PASS Stage Overdrive %d Hz: exact dry, smoothed mix, automation, Panic, eight instances\n", rate);
    }
    puts("PASS all Stage Overdrive tests");
    return 0;
}
