#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static const float TAU_F = 6.28318530718f;

static void configure(SKSynth *s, int stage, float amount, float feedback,
                      float diffusion, float dry, float wet, float quality) {
    sk_effect(s, 0, 0, 10, 1);
    float p[11] = {amount, feedback, .55f, diffusion, .2f, 80, 14000,
                   dry, wet, quality, (float)stage};
    for (int i = 0; i < 11; i++) sk_effect_parameter(s, 0, 0, i, p[i]);
}

static void sine(float *x, int n, int rate, float hz, float amplitude) {
    for (int i = 0; i < n; i++) x[i] = amplitude * sinf(TAU_F * hz * i / rate);
}

static double energy(const float *x, int start, int end) {
    double sum = 0;
    for (int i = start; i < end; i++) {
        assert(isfinite(x[i]));
        sum += x[i] * x[i];
    }
    return sum;
}

static double powerAt(const float *x, int start, int n, double hz, int rate) {
    double real = 0, imaginary = 0;
    for (int i = 0; i < n; i++) {
        double phase = TAU_F * hz * i / rate;
        real += x[start + i] * cos(phase);
        imaginary += x[start + i] * sin(phase);
    }
    return real * real + imaginary * imaginary;
}

static void bounded(const float *x, int n) {
    for (int i = 0; i < n; i++) {
        assert(isfinite(x[i]));
        assert(fabsf(x[i]) < 20);
    }
}

static double dampingRatio(int rate, float tone) {
    int n = rate * 4;
    float *x = calloc((size_t)n, sizeof(float));
    SKSynth *s = sk_create_effects(rate);
    assert(x && s);
    sk_effect(s, 0, 0, 10, 1);
    float p[11] = {0, .8f, .9f, .5f, 0, 80, tone, 0, 1, 1, 1};
    for (int i = 0; i < 11; i++) sk_effect_parameter(s, 0, 0, i, p[i]);
    for (int i = 0; i < rate / 10; i++) {
        x[i] = .1f * sinf(TAU_F * 4000 * i / rate) * sinf(3.141592654f * i / (rate / 10));
    }
    sk_process_effects(s, x, n);
    double early = energy(x, rate / 2, rate);
    double late = energy(x, rate * 2, rate * 3);
    assert(early > 1e-15);
    sk_panic(s);
    for (int i = 0; i < 512; i++) x[i] = 0;
    sk_process_effects(s, x, 512);
    for (int i = 0; i < 512; i++) assert(x[i] == 0);
    sk_destroy(s);
    free(x);
    return late / early;
}

int main(void) {
    const int rates[] = {44100, 48000, 96000};
    for (int r = 0; r < 3; r++) {
        int rate = rates[r], n = rate * 2;
        float *a = calloc((size_t)n, sizeof(float));
        float *b = calloc((size_t)n, sizeof(float));
        float *input = calloc((size_t)n, sizeof(float));
        assert(a && b && input);
        SKSynth *stage = sk_create_effects(rate), *other = sk_create_effects(rate);
        assert(stage && other);

        // Wet 0 leaves the direct path exact.
        configure(stage, 1, .75f, .66f, .75f, 1, 0, 1);
        sine(input, n, rate, 330, .16f);
        for (int i = 0; i < n; i++) a[i] = input[i];
        sk_process_effects(stage, a, n);
        for (int i = 0; i < n; i++) assert(fabsf(a[i] - input[i]) < 1e-7f);

        // Stage Shimmer pitches before the tank; feedback off still yields octave content.
        sk_panic(stage);
        configure(stage, 1, 1, 0, 0, 0, 1, 1);
        sine(input, n, rate, 220, .16f);
        for (int i = 0; i < n; i++) a[i] = input[i];
        sk_process_effects(stage, a, n);
        bounded(a, n);
        double octave = powerAt(a, rate / 2, rate / 2, 440, rate);
        double fundamental = powerAt(a, rate / 2, rate / 2, 220, rate);
        assert(octave > fundamental * 4);

        // Quality now affects the pitch shifter alone, not the reverb clock.
        sk_panic(stage);
        configure(stage, 1, 1, .5f, .5f, 0, 1, 0);
        sine(input, n, rate, 220, .16f);
        for (int i = 0; i < n; i++) a[i] = input[i];
        sk_process_effects(stage, a, n);
        sk_panic(other);
        configure(other, 1, 1, .5f, .5f, 0, 1, 1);
        for (int i = 0; i < n; i++) b[i] = input[i];
        sk_process_effects(other, b, n);
        double difference = 0;
        for (int i = 0; i < n; i++) {
            assert(isfinite(a[i]) && isfinite(b[i]));
            difference += fabsf(a[i] - b[i]);
        }
        assert(difference > .01);

        // No near-direct pitched attack, but a feedback tail remains.
        sk_panic(stage);
        configure(stage, 1, 1, .66f, .75f, 0, 1, 1);
        for (int i = 0; i < n; i++) a[i] = i < rate / 2 ? .1f * sinf(TAU_F * 220 * i / rate) : 0;
        sk_process_effects(stage, a, n);
        for (int i = 0; i < 1000; i++) assert(a[i] == 0);
        assert(energy(a, rate, n) > 1e-10);

        // Room, feedback, diffusion and amount automation stay bounded.
        for (int block = 0; block < 64; block++) {
            sk_effect_parameter(stage, 0, 0, 0, (float)(block % 7) / 6);
            sk_effect_parameter(stage, 0, 0, 1, .2f + .7f * (float)(block % 5) / 4);
            sk_effect_parameter(stage, 0, 0, 2, .2f + .8f * (float)(block % 3) / 2);
            sk_effect_parameter(stage, 0, 0, 3, (float)(block % 9) / 8);
            sk_effect_parameter(stage, 0, 0, 4, (float)(block % 11) / 10);
            sine(a, 128, rate, 330, .12f);
            sk_process_effects(stage, a, 128);
            bounded(a, 128);
        }

        sk_panic(stage);
        for (int i = 0; i < 512; i++) a[i] = 0;
        sk_process_effects(stage, a, 512);
        for (int i = 0; i < 512; i++) assert(a[i] == 0);

        // Stereo rendering keeps the two room sides distinct and finite.
        sk_destroy(stage);
        sk_destroy(other);
        stage = sk_create_effects(rate);
        other = sk_create_effects(rate);
        assert(stage && other);
        configure(stage, 1, 1, .66f, .75f, 0, 1, 1);
        configure(other, 1, 1, .66f, .75f, 0, 1, 1);
        for (int i = 0; i < rate; i++) a[i] = b[i] = i == 0 ? .2f : 0;
        sk_process_effects_stereo(stage, other, a, b, rate);
        double stereo = 0;
        for (int i = 0; i < rate; i++) {
            assert(isfinite(a[i]) && isfinite(b[i]));
            stereo += (a[i] - b[i]) * (a[i] - b[i]);
        }
        assert(stereo > 1e-8);
        sk_panic(stage);
        sk_panic(other);
        for (int i = 0; i < 512; i++) a[i] = b[i] = 0;
        sk_process_effects_stereo(stage, other, a, b, 512);
        for (int i = 0; i < 512; i++) assert(a[i] == 0 && b[i] == 0);

        // Eight independent instances remain finite and bounded.
        SKSynth *instances[8];
        for (int i = 0; i < 8; i++) {
            instances[i] = sk_create_effects(rate);
            assert(instances[i]);
            configure(instances[i], 1, .75f, .66f, .75f, 0, 1, 1);
        }
        for (int block = 0; block < 8; block++) {
            for (int i = 0; i < 8; i++) {
                sine(a, 256, rate, 180 + 20 * i, .10f);
                sk_process_effects(instances[i], a, 256);
                bounded(a, 256);
            }
        }
        for (int i = 0; i < 8; i++) sk_destroy(instances[i]);

        double dark = dampingRatio(rate, 1200), bright = dampingRatio(rate, 14000);
        assert(dark < bright * .25);
        printf("PASS Stage Shimmer %d Hz: dry, octave/free feedback, quality, tail, damping, automation, stereo, Panic, eight instances\n", rate);

        sk_destroy(stage);
        sk_destroy(other);
        free(a);
        free(b);
        free(input);
    }
    puts("PASS all Stage Shimmer tests");
    return 0;
}
