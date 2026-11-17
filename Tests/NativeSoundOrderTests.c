#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static double energy(SKSynth *s, int blocks) {
    float l[512], r[512];
    double e = 0;
    for (int b = 0; b < blocks; b++) {
        sk_render(s, l, r, 512);
        for (int i = 0; i < 512; i++) { assert(isfinite(l[i])); assert(isfinite(r[i])); e += l[i] * l[i]; }
    }
    return e;
}
static SKSynth *tone(void) {
    SKSynth *s = sk_create(48000);
    assert(s);
    sk_envelope(s, 0, .001, .001, 1, .01);
    sk_note_on(s, 60, 84, 1, 0, 1);
    return s;
}

int main(void) {
    // Native order is source gain -> compressor -> Mod Filter -> 8-band EQ ->
    // three audio-effect slots -> pan -> performance fader. An EQ boost placed
    // after the compressor must therefore reach the output instead of being
    // caught by the detector.
    SKSynth *s = tone();
    sk_compressor(s, 0, 1, -60, 20, .0001, .1, 0);
    double compressed = energy(s, 60);
    sk_destroy(s);
    s = tone();
    sk_compressor(s, 0, 1, -60, 20, .0001, .1, 0);
    // Band 4 sits at ~1 kHz, near the pitch-84 fundamental the fixture plays.
    sk_eq(s, 0, 4, 1000, 24, .707);
    double boosted = energy(s, 60);
    sk_destroy(s);
    assert(compressed > 0);
    assert(boosted > compressed * 50);

    // The Mod Filter sits inside the same native path: a closed cutoff removes
    // the signal and an open cutoff does not.
    s = tone();
    double open = energy(s, 30);
    sk_destroy(s);
    s = tone();
    sk_filter(s, 0, 40, .707);
    double closed = energy(s, 30);
    sk_destroy(s);
    assert(closed < open * .02);

    // Resonance at its legal maximum stays finite inside the same path.
    s = tone();
    sk_filter(s, 0, 2000, 10);
    energy(s, 30);
    sk_destroy(s);

    // Envelope timing: a long attack must not be at full level immediately, and
    // a held note must reach it.
    s = sk_create(48000);
    sk_envelope(s, 0, .5, 1, 1, .5);
    sk_note_on(s, 60, 100, 1, 0, 1);
    double early = energy(s, 5);
    double late = energy(s, 25);
    assert(late > early * 5);
    sk_destroy(s);

    // Source/sampler gain precedes processing, so zero gain is silent even with
    // the EQ and compressor enabled.
    s = tone();
    sk_eq(s, 0, 4, 1000, 24, .707);
    sk_compressor(s, 0, 1, -60, 20, .0001, .1, 0);
    sk_sampler_gain(s, 0, 0);
    assert(energy(s, 3) < 1e-10);
    sk_destroy(s);

    // Pan is applied before the performance fader and preserves the stereo law.
    s = tone();
    sk_pan(s, 0, -1);
    sk_gain(s, 0, 1, .001);
    float l[512], r[512];
    sk_render(s, l, r, 512);
    double left = 0, right = 0;
    for (int i = 0; i < 512; i++) { assert(isfinite(l[i]) && isfinite(r[i])); left += l[i] * l[i]; right += r[i] * r[i]; }
    assert(left > right * 100);
    sk_destroy(s);

    puts("native sound order tests passed");
}
