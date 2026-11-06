#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

#define MAX_CLICKS 4096
typedef struct { int count; long onset[MAX_CLICKS]; float peak[MAX_CLICKS]; } Capture;

static SKMetronomeSettings defaults(void) {
    SKMetronomeSettings s;
    memset(&s, 0, sizeof(s));
    s.level = 1; s.preset = 0; s.beatVelocity = 0.7f; s.downbeatEnabled = 1;
    s.downbeatVelocity = 1; s.beatsPerBar = 4; s.accentEvery = 0; s.subdivision = 1;
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

// Count-in must work at every supported rate and across irregular block splits.
static void test_count_in_matrix(void) {
    double rates[3] = {44100, 48000, 96000};
    uint32_t blocks[3] = {1, 127, 511};
    for (int i = 0; i < 3; i++) {
        SKMetronome *m = sk_metronome_create(rates[i]); assert(m);
        SKMetronomeSettings s = defaults();
        s.beatVelocity = 0.5f; s.downbeatVelocity = 1;
        sk_metronome_settings(m, s);
        sk_metronome_tempo(m, 120);
        sk_metronome_count_in(m, 1);
        Capture c; capture(&c, m, &blocks[i], 1, (long)(rates[i] * 3));
        assert(c.count == 4);
        assert(c.peak[0] > c.peak[1]); // count-in begins on the downbeat
        sk_metronome_destroy(m);
    }
}

// A one-shot count-in starts on a downbeat, stops after the requested bars when
// the click was off, and leaves an already-running click untouched.
static void test_count_in(void) {
    SKMetronome *m = sk_metronome_create(48000); assert(m);
    uint32_t block[1] = {512};
    SKMetronomeSettings s = defaults();
    s.beatVelocity = 0.5f; s.downbeatVelocity = 1;
    sk_metronome_settings(m, s);
    sk_metronome_tempo(m, 120);
    sk_metronome_count_in(m, 1);
    Capture c; capture(&c, m, block, 1, 48000 * 3);
    assert(c.count == 4);
    assert(c.peak[0] > c.peak[1]); // count-in begins on the downbeat

    // Pressing Count In while the normal click is already running must not
    // insert an early downbeat; the next click stays on its original boundary.
    sk_metronome_reset(m);
    sk_metronome_enable(m, 0);
    sk_metronome_enable(m, 1);
    sk_metronome_render(m, NULL, NULL, 12000);
    sk_metronome_count_in(m, 1);
    Capture phase; capture(&phase, m, block, 1, 13000);
    assert(phase.count == 1 && phase.onset[0] >= 11998 && phase.onset[0] <= 12002);

    // A second one-shot request before the first finishes stays temporary and
    // still stops when the click setting is off.
    sk_metronome_enable(m, 0);
    sk_metronome_count_in(m, 1);
    sk_metronome_render(m, NULL, NULL, 1000);
    sk_metronome_count_in(m, 1);
    Capture repeated; capture(&repeated, m, block, 1, 48000 * 3);
    assert(repeated.count == 4);

    // Turning on the normal click during Count In keeps the running phase
    // and continues beyond the end of the former one-shot bar.
    sk_metronome_enable(m, 0);
    sk_metronome_count_in(m, 1);
    sk_metronome_render(m, NULL, NULL, 12000);
    sk_metronome_enable(m, 1);
    Capture promoted; capture(&promoted, m, block, 1, 48000 * 3);
    assert(promoted.count == 6 && promoted.onset[0] >= 11998 && promoted.onset[0] <= 12002);

    // A normal click is unaffected by Count In and keeps running.
    sk_metronome_enable(m, 0);
    sk_metronome_enable(m, 1);
    sk_metronome_count_in(m, 1);
    Capture on; capture(&on, m, block, 1, 48000 * 3);
    assert(on.count == 6);
    Capture continued; capture(&continued, m, block, 1, 48000);
    assert(continued.count == 2);
    sk_metronome_destroy(m);
}

// Switching clock mode must cancel a pending one-shot count-in so a later
// normal click cannot inherit its remaining bars and stop early.
static void test_count_in_clock_mode_change(void) {
    SKMetronome *m = sk_metronome_create(48000); assert(m);
    uint32_t block[1] = {512};
    SKMetronomeSettings s = defaults();
    s.beatVelocity = 1; s.downbeatVelocity = 1;
    sk_metronome_settings(m, s);
    sk_metronome_tempo(m, 120);
    sk_metronome_count_in(m, 1);
    sk_metronome_render(m, NULL, NULL, 1000); // begin the count-in
    sk_metronome_clock_enabled(m, 1);
    sk_metronome_render(m, NULL, NULL, 0);
    sk_metronome_clock_enabled(m, 0);
    sk_metronome_enable(m, 1);
    Capture c; capture(&c, m, block, 1, 48000 * 4);
    assert(c.count == 8);
    sk_metronome_destroy(m);
}

// External clock tempo must be sample-rate independent and tolerant of the
// same irregular block splits as the internal scheduler.
static void test_external_clock_matrix(void) {
    double rates[3] = {44100, 48000, 96000};
    uint32_t blocks[3] = {1, 127, 511};
    for (int i = 0; i < 3; i++) {
        SKMetronome *m = sk_metronome_create(rates[i]); assert(m);
        SKMetronomeSettings s = defaults();
        s.beatVelocity = 1; s.downbeatVelocity = 1;
        sk_metronome_settings(m, s);
        sk_metronome_tempo(m, 120);
        sk_metronome_clock_enabled(m, 1);
        sk_metronome_enable(m, 1);
        sk_metronome_clock_event(m, 1, 0);
        for (int tick = 1; tick <= 24; tick++) sk_metronome_clock_event(m, 0, (double)tick / 36.0);
        sk_metronome_render(m, NULL, NULL, 0);
        Capture c; capture(&c, m, &blocks[i], 1, (long)(rates[i] * 2));
        assert(c.count >= 3);
        double interval = rates[i] * 60 / 90;
        for (int click = 0; click < c.count; click++)
            assert(fabs((double)c.onset[click] - interval * click) <= 2);
        sk_metronome_clock_event(m, 3, 0);
        sk_metronome_render(m, NULL, NULL, 0);
        Capture stopped; capture(&stopped, m, &blocks[i], 1, (long)rates[i]);
        assert(stopped.count == 0);
        sk_metronome_destroy(m);
    }
}

// A burst of clock ticks must not consume the slots reserved for transport, so
// a Stop that arrives while the render thread is delayed is still delivered.
static void test_clock_transport_reserve(void) {
    SKMetronome *m = sk_metronome_create(48000); assert(m);
    SKMetronomeSettings s = defaults();
    s.beatVelocity = 1; s.downbeatVelocity = 1;
    sk_metronome_settings(m, s);
    sk_metronome_clock_enabled(m, 1);
    sk_metronome_enable(m, 1);
    sk_metronome_clock_event(m, 1, 0);
    for (int tick = 1; tick <= 2000; tick++) sk_metronome_clock_event(m, 0, (double)tick / 36.0);
    sk_metronome_clock_event(m, 3, 0);
    sk_metronome_render(m, NULL, NULL, 0);
    uint32_t block[1] = {512};
    Capture stopped; capture(&stopped, m, block, 1, 48000);
    assert(stopped.count == 0);
    sk_metronome_destroy(m);
}

// External MIDI Clock waits for Start, derives 90 BPM from 24 PPQN, stops on
// Stop and resumes without restarting the phase on Continue.
static void test_external_clock(void) {
    SKMetronome *m = sk_metronome_create(48000); assert(m);
    uint32_t block[1] = {512};
    SKMetronomeSettings s = defaults();
    s.beatVelocity = 1; s.downbeatVelocity = 1;
    sk_metronome_settings(m, s);
    sk_metronome_tempo(m, 120);
    sk_metronome_clock_enabled(m, 1);
    sk_metronome_enable(m, 1);
    Capture idle; capture(&idle, m, block, 1, 48000);
    assert(idle.count == 0);

    sk_metronome_clock_event(m, 1, 0);
    for (int i = 1; i <= 24; i++) sk_metronome_clock_event(m, 0, (double)i / 36.0);
    sk_metronome_render(m, NULL, NULL, 0);
    // Reapplying settings while a clock is running must not stop the click or
    // reset its clock phase.
    sk_metronome_settings(m, s);
    sk_metronome_render(m, NULL, NULL, 0);
    Capture c; capture(&c, m, block, 1, 48000 * 2);
    assert(c.count >= 3);
    double interval = 48000.0 * 60 / 90;
    for (int i = 0; i < c.count; i++) assert(fabs((double)c.onset[i] - interval * i) <= 2);

    sk_metronome_clock_event(m, 3, 0);
    sk_metronome_render(m, NULL, NULL, 0);
    Capture stopped; capture(&stopped, m, block, 1, 48000);
    assert(stopped.count == 0);

    sk_metronome_clock_event(m, 2, 10);
    sk_metronome_render(m, NULL, NULL, 0);
    Capture resumed; capture(&resumed, m, block, 1, 48000);
    assert(resumed.count >= 2 && resumed.onset[0] <= 2);

    sk_metronome_clock_enabled(m, 0);
    sk_metronome_render(m, NULL, NULL, 0);
    Capture internal; capture(&internal, m, block, 1, 48000 * 2);
    assert(internal.count >= 2 && fabs((double)(internal.onset[1] - internal.onset[0]) - interval) <= 2);
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
    test_count_in_matrix();
    test_count_in();
    test_count_in_clock_mode_change();
    test_external_clock_matrix();
    test_clock_transport_reserve();
    test_external_clock();
    test_reset();
    puts("PASS: metronome timing at 44.1/48/96 kHz, block splits, tempo phase, accents, subdivision, presets, levels, master follow, count-in phase/repeat/promotion/clock-mode cancel, MIDI clock sync/reserve, long-run drift and reset");
}
