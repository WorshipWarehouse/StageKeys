#include "Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

// The native tempo-synced delay recomputes its tap from the clock every sample.
// A tempo or subdivision change used to move the read position by thousands of
// samples in one step, which is a click. Both changes below retime between two
// taps that already carry the tone, so the measurement is not just a fade to
// silence. This checks the largest sample-to-sample step in steady state and
// across each change, then confirms the new delay time is actually reached.

static const double pi = 3.14159265358979323846;

static void configure(SKSynth *s, float subdivision) {
    sk_effect(s, 0, 0, 3, 1);
    sk_effect_parameter(s, 0, 0, 0, 0.0f);   /* feedback */
    sk_effect_parameter(s, 0, 0, 1, subdivision);
    sk_effect_parameter(s, 0, 0, 2, 20000);  /* filter */
    sk_effect_parameter(s, 0, 0, 3, 1.0f);   /* mix: wet only */
    sk_clock(s, 120);
}

int main(void) {
    const int rates[3] = {44100, 48000, 96000};
    const int block = 64;
    for (int r = 0; r < 3; r++) {
        const double rate = rates[r];
        SKSynth *left = sk_create_effects(rate);
        SKSynth *right = sk_create_effects(rate);
        configure(left, 1.0f);
        configure(right, 1.0f);

        // 120 BPM at one beat is a 0.5 s delay. Doubling the tempo at 1 s halves
        // it to 0.25 s; doubling the subdivision at 1.3 s restores 0.5 s. Both
        // old and new taps already contain tone at each change.
        const int tempoBlock = (int)(rate * 1.0 / block);
        const int subdivisionBlock = (int)(rate * 1.3 / block);
        const int total = (int)(rate * 1.8 / block) * block;
        float l[64], rr[64];
        double phase = 0, previous = 0;
        double steady = 0, tempoStep = 0, subdivisionStep = 0, settled = 0, peak = 0;

        for (int n = 0; n < total; n += block) {
            for (int i = 0; i < block; i++) {
                l[i] = rr[i] = (float)(0.5 * sin(phase));
                phase += 2 * pi * 997 / rate;
                if (phase > 2 * pi) phase -= 2 * pi;
            }
            if (n / block == tempoBlock) { sk_clock(left, 240); sk_clock(right, 240); }
            if (n / block == subdivisionBlock) {
                sk_effect_parameter(left, 0, 0, 1, 2.0f);
                sk_effect_parameter(right, 0, 0, 1, 2.0f);
            }
            sk_process_effects_stereo(left, right, l, rr, block);
            for (int i = 0; i < block; i++) {
                const int m = n + i;
                assert(isfinite(l[i]) && fabsf(l[i]) <= 16);
                const double step = fabs((double)l[i] - previous);
                previous = l[i];
                if (m >= rate * 0.60 && m < rate * 0.98) steady = fmax(steady, step);
                else if (m >= tempoBlock * block && m < rate * 1.04) tempoStep = fmax(tempoStep, step);
                else if (m >= subdivisionBlock * block && m < rate * 1.34) subdivisionStep = fmax(subdivisionStep, step);
                else if (m >= rate * 1.50 && m < rate * 1.70) settled = fmax(settled, step);
                peak = fmax(peak, fabs((double)l[i]));
            }
        }

        assert(steady > 0.02 && steady < 0.2);
        assert(peak > 0.2 && settled > 0.02);
        // Before the crossfade this was 5.3x the steady slope at 48 kHz.
        assert(tempoStep < steady * 2.0 + 0.01);
        assert(subdivisionStep < steady * 2.0 + 0.01);

        // The new time must be reached: at 240 BPM and one beat the impulse is
        // one quarter second behind, at every rate.
        sk_effect_parameter(left, 0, 0, 1, 1.0f);
        sk_effect_parameter(right, 0, 0, 1, 1.0f);
        sk_panic(left);
        sk_panic(right);
        for (int n = 0; n < (int)(rate * 0.1); n += block) {
            memset(l, 0, sizeof(l));
            memset(rr, 0, sizeof(rr));
            sk_process_effects_stereo(left, right, l, rr, block);
        }
        int impulse = -1;
        double loudest = 0;
        const int blocks = (int)(rate * 1.2 / block);
        for (int b = 0; b < blocks; b++) {
            for (int i = 0; i < block; i++) l[i] = rr[i] = (b == 0 && i == 0) ? 1.0f : 0.0f;
            sk_process_effects_stereo(left, right, l, rr, block);
            for (int i = 0; i < block; i++) {
                const int m = b * block + i;
                if (fabsf(l[i]) > loudest) { loudest = fabsf(l[i]); impulse = m; }
            }
        }
        const int expected = (int)llround(rate / 4);
        const int error = impulse > expected ? impulse - expected : expected - impulse;
        assert(loudest > 0.01);
        assert(error <= 4);

        printf("PASS %.0f Hz: steady %.4f, tempo %.4f, subdivision %.4f, settled %.4f, impulse %d/%d\n",
               rate, steady, tempoStep, subdivisionStep, settled, impulse, expected);
        sk_destroy(left);
        sk_destroy(right);
    }
    puts("PASS tempo-synced delay changes overlap taps instead of stepping the read position");
    return 0;
}
