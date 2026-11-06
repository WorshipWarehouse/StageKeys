#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_CLICKS 4096
typedef struct { int count; long onset[MAX_CLICKS]; float peak[MAX_CLICKS]; } Capture;

static SKMetronomeSettings defaults(void) {
    SKMetronomeSettings s;
    memset(&s, 0, sizeof(s));
    s.level = 1; s.preset = 0; s.beatVelocity = 0.7f; s.downbeatEnabled = 1;
    s.downbeatVelocity = 1; s.beatsPerBar = 4; s.accentEvery = 0; s.subdivision = 1;
    s.countInBars = 0;
    return s;
}

// Render arbitrary block splits and record each click's first audible sample
// and its peak. Output must stay finite, bounded and identical in both channels.
static void capture(Capture *c, SKMetronome *m, const uint32_t *blocks, int blockCount, long total) {
    float left[512], right[512];
    memset(c, 0, sizeof(*c));
    long t = 0; int block = 0, quiet = 1 << 20;
    while (t < total) {
        uint32_t n = blocks[block++ % blockCount];
        if (n > 512) n = 512;
        if (t + (long)n > total) n = (uint32_t)(total - t);
        sk_metronome_render(m, left, right, n);
        for (uint32_t i = 0; i < n; i++) {
            assert(isfinite(left[i]) && isfinite(right[i]));
            assert(left[i] == right[i]);
            assert(fabsf(left[i]) <= 1);
            float a = fabsf(left[i]);
            if (a > 0.02f) {
                if (quiet > 64 && c->count < MAX_CLICKS) {
                    c->onset[c->count] = t;
                    c->peak[c->count] = a;
                    c->count++;
                }
                quiet = 0;
            } else { quiet++; }
            if (c->count > 0 && t - c->onset[c->count - 1] < 32 && a > c->peak[c->count - 1])
                c->peak[c->count - 1] = a;
            t++;
        }
    }
}

static int crossings(const float *x, int n) {
    int c = 0;
    for (int i = 1; i < n; i++) if ((x[i - 1] < 0) != (x[i] < 0)) c++;
    return c;
}

static float window_peak(const float *x, int n) {
    float p = 0;
    for (int i = 0; i < n; i++) { float a = fabsf(x[i]); if (a > p) p = a; }
    return p;
}

// 44.1/48/96 kHz, irregular block splits and a reset mid-stream.
static void test_timing(void) {
    double rates[3] = {44100, 48000, 96000};
    uint32_t blocks[9] = {1, 2, 3, 5, 7, 64, 127, 511, 256};
    for (int r = 0; r < 3; r++) {
        SKMetronome *m = sk_metronome_create(rates[r]); assert(m);
        sk_metronome_settings(m, defaults());
        sk_metronome_tempo(m, 90);
        sk_metronome_enable(m, 1);
        Capture c; capture(&c, m, blocks, 9, (long)(rates[r] * 4));
        double interval = rates[r] * 60 / 90;
        assert(c.count >= 6);
        for (int i = 0; i < c.count; i++)
            assert(fabs((double)c.onset[i] - interval * i) <= 2);
        sk_metronome_reset(m);
        sk_metronome_enable(m, 0);
        sk_metronome_enable(m, 1);
        Capture rest; capture(&rest, m, blocks, 9, (long)rates[r]);
        assert(rest.count >= 2 && rest.onset[0] <= 2);
        assert(fabs((double)(rest.onset[1] - rest.onset[0]) - interval) <= 2);
        sk_metronome_destroy(m);
    }
}

// A mid-beat tempo change keeps the phase and must not double-trigger.
static void test_tempo_change(void) {
    SKMetronome *m = sk_metronome_create(48000); assert(m);
    sk_metronome_settings(m, defaults());
    sk_metronome_tempo(m, 120);
    sk_metronome_enable(m, 1);
    uint32_t block[1] = {120};
    Capture first; capture(&first, m, block, 1, 12000);
    assert(first.count == 1);
    sk_metronome_tempo(m, 60);
    Capture after; capture(&after, m, block, 1, 48000);
    assert(after.count == 1);
    assert(fabs((double)after.onset[0] - 24000) <= 2);
    sk_metronome_destroy(m);
}

// Downbeat, accent pattern, meter and velocity relationships.
static void test_accents(void) {
    SKMetronome *m = sk_metronome_create(48000); assert(m);
    uint32_t block[1] = {512};
    SKMetronomeSettings s = defaults();
    s.beatVelocity = 0.5f; s.downbeatVelocity = 1; s.accentEvery = 2; s.beatsPerBar = 4;
    sk_metronome_settings(m, s);
    sk_metronome_tempo(m, 120);
    sk_metronome_enable(m, 1);
    Capture c; capture(&c, m, block, 1, 48000 * 2);
    assert(c.count == 4);
    assert(fabsf(c.peak[0] - 0.2f) < 0.01f);
    assert(fabsf(c.peak[1] - 0.1f) < 0.01f);
    assert(fabsf(c.peak[2] - 0.125f) < 0.01f);
    assert(fabsf(c.peak[3] - 0.1f) < 0.01f);
    assert(c.peak[0] > c.peak[2] && c.peak[2] > c.peak[1]);

    // Downbeat disabled: the first beat uses the normal velocity.
    s.downbeatEnabled = 0;
    sk_metronome_settings(m, s);
    sk_metronome_reset(m);
    sk_metronome_enable(m, 0);
    sk_metronome_enable(m, 1);
    Capture off; capture(&off, m, block, 1, 48000);
    assert(off.count == 2 && fabsf(off.peak[0] - 0.1f) < 0.01f);

    // A seven-beat bar accents only the first beat of every bar.
    s = defaults();
    s.beatVelocity = 0.5f; s.beatsPerBar = 7; s.accentEvery = 0;
    sk_metronome_settings(m, s);
    sk_metronome_reset(m);
    sk_metronome_enable(m, 0);
    sk_metronome_enable(m, 1);
    Capture bar; capture(&bar, m, block, 1, 48000 * 4);
    assert(bar.count >= 8);
    assert(fabsf(bar.peak[0] - 0.2f) < 0.01f);
    assert(fabsf(bar.peak[1] - 0.1f) < 0.01f);
    assert(fabsf(bar.peak[7] - 0.2f) < 0.01f);
    sk_metronome_destroy(m);
}

// Subdivision clicks are sample-accurate and intentionally softer than beats.
static void test_subdivision(void) {
    SKMetronome *m = sk_metronome_create(48000); assert(m);
    SKMetronomeSettings s = defaults();
    s.subdivision = 3; s.beatVelocity = 1;
    sk_metronome_settings(m, s);
    sk_metronome_tempo(m, 90);
    sk_metronome_enable(m, 1);
    uint32_t block[1] = {256};
    Capture c; capture(&c, m, block, 1, 96000);
    double step = 48000.0 * 60 / 90 / 3;
    assert(c.count >= 6);
    for (int i = 0; i < 6; i++)
        assert(fabs((double)c.onset[i] - step * i) <= 2);
    assert(c.peak[0] > c.peak[1] && c.peak[1] > 0.05f);
    sk_metronome_destroy(m);
}

// Both independently synthesized timbres are finite, bounded and distinct.
static void test_presets(void) {
    SKMetronome *m[2]; float left[2][128], right[128];
    for (int p = 0; p < 2; p++) {
        m[p] = sk_metronome_create(48000); assert(m[p]);
        SKMetronomeSettings s = defaults();
        s.preset = p; s.beatVelocity = 1;
        sk_metronome_settings(m[p], s);
        sk_metronome_tempo(m[p], 120);
        sk_metronome_enable(m[p], 1);
        sk_metronome_render(m[p], left[p], right, 128);
    }
    int different = 0;
    for (int i = 0; i < 128; i++) {
        assert(isfinite(left[0][i]) && isfinite(left[1][i]));
        assert(fabsf(left[0][i]) <= 1 && fabsf(left[1][i]) <= 1);
        if (fabsf(left[0][i] - left[1][i]) > 0.001f) different++;
    }
    assert(different > 64);
    sk_metronome_destroy(m[0]);
    sk_metronome_destroy(m[1]);
}

// Levels and explicit stops, including a fresh bar on re-enable.
static void test_level_and_stop(void) {
    SKMetronome *m = sk_metronome_create(48000); assert(m);
    uint32_t block[1] = {512};
    SKMetronomeSettings s = defaults();
    s.level = 0;
    sk_metronome_settings(m, s);
    sk_metronome_tempo(m, 120);
    sk_metronome_enable(m, 1);
    Capture silent; capture(&silent, m, block, 1, 48000);
    assert(silent.count == 0);
    s.level = 1;
    sk_metronome_settings(m, s);
    sk_metronome_reset(m);
    sk_metronome_enable(m, 0);
    sk_metronome_enable(m, 1);
    Capture loud; capture(&loud, m, block, 1, 48000);
    assert(loud.count == 2);
    sk_metronome_enable(m, 0);
    Capture stopped; capture(&stopped, m, block, 1, 48000);
    assert(stopped.count == 0);
    sk_metronome_enable(m, 1);
    Capture again; capture(&again, m, block, 1, 48000);
    assert(again.count == 2 && again.onset[0] <= 2);
    sk_metronome_destroy(m);
}

// Master-follow is a real output gain, and off must hold the click's own level.
static void test_master(void) {
    SKMetronome *m = sk_metronome_create(48000); assert(m);
    uint32_t block[1] = {512};
    SKMetronomeSettings s = defaults();
    s.beatVelocity = 1;
    sk_metronome_settings(m, s);
    sk_metronome_tempo(m, 120);
    sk_metronome_master(m, 0.5f, 1);
    sk_metronome_enable(m, 1);
    Capture half; capture(&half, m, block, 1, 24000);
    assert(half.count == 1 && fabsf(half.peak[0] - 0.1f) < 0.01f);
    sk_metronome_reset(m);
    sk_metronome_enable(m, 0);
    sk_metronome_enable(m, 1);
    sk_metronome_master(m, 0.5f, 0);
    Capture own; capture(&own, m, block, 1, 24000);
    assert(own.count == 1 && fabsf(own.peak[0] - 0.2f) < 0.01f);
    sk_metronome_reset(m);
    sk_metronome_enable(m, 0);
    sk_metronome_enable(m, 1);
    sk_metronome_master(m, 0, 1);
    Capture muted; capture(&muted, m, block, 1, 24000);
    assert(muted.count == 0);
    sk_metronome_destroy(m);
}

// A count-in plays whole beats of a higher-pitched click before the bar, then
// hands off to the bar's own downbeat one beat later. It ignores the
// subdivision, restarts on each fresh enable and is cancelled by reset.
static void test_count_in(void) {
    enum { CHUNK = 12000 };  // 120 BPM at 48 kHz: a beat is two chunks.
    float *left = calloc(CHUNK, sizeof(float)), *right = calloc(CHUNK, sizeof(float));
    assert(left && right);
    SKMetronome *m = sk_metronome_create(48000); assert(m);
    SKMetronomeSettings s = defaults();
    s.beatVelocity = 1; s.downbeatVelocity = 1; s.subdivision = 2; s.beatsPerBar = 4; s.countInBars = 1;
    sk_metronome_settings(m, s);
    sk_metronome_tempo(m, 120);
    sk_metronome_enable(m, 1);
    int zc[12]; float peak[12];
    for (int i = 0; i < 12; i++) {
        sk_metronome_render(m, left, right, CHUNK);
        zc[i] = crossings(left, 512); peak[i] = window_peak(left, 512);
        for (int j = 0; j < 512; j++) assert(isfinite(left[j]) && left[j] == right[j]);
    }
    // Four beat-spaced count-in clicks; no subdivision click between them.
    for (int i = 0; i < 4; i++) {
        assert(peak[i * 2] > 0.05f && peak[i * 2 + 1] < 0.01f);
        assert(zc[i * 2] > zc[8] * 3 / 2);
    }
    // The bar starts exactly one beat after the last count-in click, with its
    // own downbeat accent and the eighth-note subdivision restored.
    assert(peak[8] > 0.15f && zc[8] > 5 && zc[8] < zc[0] * 2 / 3);
    assert(peak[9] > 0.05f && peak[9] < 0.15f);
    assert(peak[10] > 0.15f);

    // Off: the bar starts immediately at the normal pitch.
    s.countInBars = 0;
    sk_metronome_settings(m, s);
    sk_metronome_reset(m);
    sk_metronome_enable(m, 0);
    sk_metronome_enable(m, 1);
    sk_metronome_render(m, left, right, CHUNK);
    assert(window_peak(left, 512) > 0.15f && crossings(left, 512) < zc[0] * 2 / 3);

    // Two bars of count-in, then the bar.
    s.countInBars = 2;
    sk_metronome_settings(m, s);
    sk_metronome_reset(m);
    sk_metronome_enable(m, 0);
    sk_metronome_enable(m, 1);
    int high = 0, low = 0;
    for (int i = 0; i < 20; i++) {
        sk_metronome_render(m, left, right, CHUNK);
        if (i % 2) continue;
        int c = crossings(left, 512);
        if (i < 16) { assert(c > zc[8] * 3 / 2); high++; }
        else { assert(c < zc[8] * 3 / 2); low++; }
    }
    assert(high == 8 && low == 2);

    // A tempo change during the count-in keeps beat phase: the next count-in
    // click lands half a beat from the change, at the higher pitch.
    s.countInBars = 1;
    sk_metronome_settings(m, s);
    sk_metronome_reset(m);
    sk_metronome_enable(m, 0);
    sk_metronome_enable(m, 1);
    sk_metronome_render(m, left, right, CHUNK);
    assert(crossings(left, 512) > zc[8] * 3 / 2);
    sk_metronome_tempo(m, 60);
    for (int i = 1; i < 4; i++) {
        sk_metronome_render(m, left, right, CHUNK);
        if (i < 3) assert(crossings(left, 512) == 0);
        else assert(crossings(left, 512) > zc[8] * 3 / 2);
    }

    // Re-enabling restarts the count-in; reset cancels it without a click and
    // the bar starts at its normal pitch afterwards.
    sk_metronome_enable(m, 0);
    sk_metronome_enable(m, 1);
    sk_metronome_render(m, left, right, CHUNK);
    assert(crossings(left, 512) > zc[8] * 3 / 2);
    sk_metronome_tempo(m, 120);
    sk_metronome_reset(m);
    sk_metronome_render(m, left, right, CHUNK);
    assert(window_peak(left, CHUNK) == 0);
    sk_metronome_render(m, left, right, CHUNK);
    assert(window_peak(left, 512) > 0.15f && crossings(left, 512) < zc[8] * 3 / 2);

    sk_metronome_destroy(m);
    free(left); free(right);
}

// Long runs must not drift or accumulate scheduling error.
static void test_long_run(void) {
    SKMetronome *m = sk_metronome_create(48000); assert(m);
    SKMetronomeSettings s = defaults();
    s.beatVelocity = 1;
    sk_metronome_settings(m, s);
    sk_metronome_tempo(m, 300);
    sk_metronome_enable(m, 1);
    uint32_t blocks[5] = {512, 128, 256, 64, 511};
    Capture c; capture(&c, m, blocks, 5, 48000 * 60);
    assert(c.count == 300);
    assert(fabs((double)c.onset[c.count - 1] - 9600.0 * (c.count - 1)) <= 2);
    sk_metronome_destroy(m);
}

// Reset truncates the tail immediately and the next enable starts a new bar.
static void test_reset(void) {
    SKMetronome *m = sk_metronome_create(48000); assert(m);
    sk_metronome_settings(m, defaults());
    sk_metronome_tempo(m, 120);
    sk_metronome_enable(m, 1);
    float left[32], right[32];
    sk_metronome_render(m, left, right, 32);
    sk_metronome_reset(m);
    sk_metronome_render(m, left, right, 32);
    for (int i = 0; i < 32; i++) assert(left[i] == 0 && right[i] == 0);
    sk_metronome_enable(m, 0);
    sk_metronome_enable(m, 1);
    sk_metronome_render(m, left, right, 32);
    assert(fabsf(left[1]) > 0.01f);
    sk_metronome_destroy(m);
}

int main(void) {
    test_timing();
    test_tempo_change();
    test_accents();
    test_subdivision();
    test_presets();
    test_level_and_stop();
    test_master();
    test_long_run();
    test_reset();
    test_count_in();
    puts("PASS: metronome timing at 44.1/48/96 kHz, block splits, tempo phase, accents, subdivision, presets, levels, master follow, long-run drift, reset and count-in");
}
