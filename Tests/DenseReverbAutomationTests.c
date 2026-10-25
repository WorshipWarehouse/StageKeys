#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static void setup(SKSynth *s, int kind) {
    sk_effect(s, 0, 0, kind, 1);
    float acoustic[] = {.8f, 0, .8f, 20, 20000, 0, 1, 0, 1, 1, 2};
    float ambient[] = {0, .8f, .8f, 20, 20000, 0, 0, 1, 0, 1, 1, 1};
    for (int i = 0; i < (kind == 13 ? 11 : 12); i++)
        sk_effect_parameter(s, 0, 0, i, kind == 13 ? acoustic[i] : ambient[i]);
}

static void excite(float *x, float *y, int *position, int rate) {
    for (int i = 0; i < 256; i++, (*position)++)
        x[i] = y[i] = .1f * sinf(*position * 6.2831853f * 4000 / rate)
                    + .1f * sinf(*position * 6.2831853f * 70 / rate);
}

int main(void) {
    const int rates[] = {44100, 48000, 96000};
    for (int r = 0; r < 3; r++) for (int kind = 13; kind <= 15; kind += 2)
    for (int control = 3; control <= 4; control++) {
        int rate = rates[r], position = 0;
        SKSynth *a = sk_create_effects(rate), *b = sk_create_effects(rate);
        setup(a, kind); setup(b, kind);
        float x[256], y[256];
        // Identical established tails isolate control-induced changes from the source waveform.
        for (int block = 0; block < 600; block++) {
            excite(x, y, &position, rate);
            sk_process_effects(a, x, 256); sk_process_effects(b, y, 256);
            for (int i = 0; i < 256; i++) assert(x[i] == y[i]);
        }
        sk_effect_parameter(a, 0, 0, control, control == 4 ? 200 : 2000);
        float first = 0, maximum = 0;
        for (int block = 0; block < 20; block++) {
            excite(x, y, &position, rate);
            sk_process_effects(a, x, 256); sk_process_effects(b, y, 256);
            if (block == 0) first = fabsf(x[0] - y[0]);
            for (int i = 0; i < 256; i++) {
                assert(isfinite(x[i]) && isfinite(y[i]));
                maximum = fmaxf(maximum, fabsf(x[i] - y[i]));
            }
        }
        // Require an effective control change without an abrupt first-frame jump.
        assert(maximum > 1e-5f);
        assert(first / maximum < .01f);
        printf("PASS automation kind%d rate%d control%d first=%g max=%g ratio=%g\n",
               kind, rate, control, first, maximum, first / maximum);
        sk_destroy(a); sk_destroy(b);
    }
}
