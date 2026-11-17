// Native channel compressor response regressions (related to #10).
//
// These measurements describe the StageKeys native channel compressor only.
// They do not compare against a MainStage capture, a hosted Audio Unit or a
// physical output. Docs/COMPRESSOR-RESPONSE.md records the measured values and
// the behavior each case protects.
#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

#define BLOCK 512
static float wetL[BLOCK], wetR[BLOCK], dryL[BLOCK], dryR[BLOCK];

// A deterministic, sample-free voice: the sustained native instrument through a
// short custom envelope and a fixed performance fader. The low fader keeps every
// measured output well inside the soft limiter's linear region.
static SKSynth *source(double rate) {
    SKSynth *s = sk_create(rate);
    assert(s);
    sk_envelope(s, 0, .005f, .005f, 1, .05f);
    sk_gain(s, 0, .2f, 0);
    sk_note_on(s, 60, 84, 1, 0, .8f);
    return s;
}
static void chain(SKSynth *s, int enabled, float threshold, float ratio,
                  float attack, float release, float makeup, float inputGain,
                  float mix) {
    sk_compressor(s, 0, enabled, threshold, ratio, attack, release, makeup);
    sk_compressor_blend(s, 0, inputGain, mix);
}
static void render(SKSynth *s, float *l, float *r, int n) {
    assert(n > 0 && n <= BLOCK);
    sk_render(s, l, r, (uint32_t)n);
    for (int i = 0; i < n; i++) {
        assert(isfinite(l[i]));
        assert(isfinite(r[i]));
        assert(l[i] == r[i]);
    }
}
static double energy(const float *l, int n) {
    double e = 0;
    for (int i = 0; i < n; i++) e += (double)l[i] * l[i];
    return e;
}
static void render_both(SKSynth *a, SKSynth *b, int block, int blocks) {
    for (int i = 0; i < blocks; i++) {
        render(a, wetL, wetR, block);
        render(b, dryL, dryR, block);
    }
}
// Energy ratio of the compressor channel to an identical uncompressed channel
// over whole blocks. Both engines render the same voice and command sequence, so
// the ratio isolates the compressor's gain.
static double gain_db(SKSynth *wet, SKSynth *dry, int block, int blocks) {
    double we = 0, de = 0;
    for (int i = 0; i < blocks; i++) {
        render(wet, wetL, wetR, block);
        render(dry, dryL, dryR, block);
        we += energy(wetL, block);
        de += energy(dryL, block);
    }
    assert(we > 0 && de > 0);
    return 10 * log10(we / de);
}
// Settle for 0.75 s, then measure 0.5 s of steady-state gain.
static double settled_db(double rate, float threshold, float ratio, float attack,
                         float release, float makeup, float inputGain, float mix) {
    SKSynth *wet = source(rate), *dry = source(rate);
    chain(wet, 1, threshold, ratio, attack, release, makeup, inputGain, mix);
    chain(dry, 0, threshold, ratio, attack, release, 0, 0, 1);
    gain_db(wet, dry, 256, (int)(rate * .75) / 256);
    double db = gain_db(wet, dry, 256, (int)(rate * .5) / 256);
    sk_destroy(wet);
    sk_destroy(dry);
    return db;
}
// Step the source gain from silence to unity and report the first 5 ms block
// whose reduction reaches 63% of its settled value. Because the detector is a
// one-pole on linear amplitude and the threshold is crossed part-way into the
// attack, this dB-domain point arrives earlier than the configured constant;
// the regression therefore checks the setting's proportional effect separately.
static double attack_time(double rate, float attack, float release, double *settled) {
    SKSynth *wet = source(rate), *dry = source(rate);
    chain(wet, 1, -60, 20, attack, release, 0, 12, 1);
    chain(dry, 0, -60, 20, attack, release, 0, 0, 1);
    sk_sampler_gain(wet, 0, 0);
    sk_sampler_gain(dry, 0, 0);
    render_both(wet, dry, 512, 8);            // settle with no signal
    sk_sampler_gain(wet, 0, 1);
    sk_sampler_gain(dry, 0, 1);
    int frames = (int)lround(rate * .005), count = 0;
    double observed[224];                    // 1 s at 5 ms blocks
    long limit = (long)rate;                  // 1 s of step response
    long elapsed = 0;
    while (elapsed < limit) {
        assert(count < 224);
        render(wet, wetL, wetR, frames);
        render(dry, dryL, dryR, frames);
        observed[count++] = 10 * log10(energy(wetL, frames) / energy(dryL, frames));
        elapsed += frames;
    }
    *settled = gain_db(wet, dry, frames, (int)(rate * .5) / frames);
    sk_destroy(wet);
    sk_destroy(dry);
    for (int i = 0; i < count; i++)
        if (fabs(observed[i]) >= .632 * fabs(*settled))
            return (i + 1) * frames / rate;
    assert(!"attack never reached 63% of its settled reduction");
    return -1;
}
// Step the source down 12 dB and report the first 5 ms block whose reduction has
// moved 63% of the way from the old value to the new settled value.
static double release_time(double rate, float attack, float release, double *settled) {
    SKSynth *wet = source(rate), *dry = source(rate);
    chain(wet, 1, -60, 20, attack, release, 0, 12, 1);
    chain(dry, 0, -60, 20, attack, release, 0, 0, 1);
    render_both(wet, dry, 512, (int)(rate * 1.0) / 512);
    int frames = (int)lround(rate * .005);
    double start = gain_db(wet, dry, frames, (int)(rate * .2) / frames);
    sk_sampler_gain(wet, 0, .25f);
    sk_sampler_gain(dry, 0, .25f);
    double observed[320];                    // 1.5 s at 5 ms blocks
    int count = 0;
    long limit = (long)(rate * 1.5), elapsed = 0;
    while (elapsed < limit) {
        assert(count < 320);
        render(wet, wetL, wetR, frames);
        render(dry, dryL, dryR, frames);
        observed[count++] = 10 * log10(energy(wetL, frames) / energy(dryL, frames));
        elapsed += frames;
    }
    *settled = gain_db(wet, dry, frames, (int)(rate * .5) / frames);
    sk_destroy(wet);
    sk_destroy(dry);
    assert(fabs(*settled) < fabs(start));
    double target = fabs(*settled) + .368 * (fabs(start) - fabs(*settled));
    for (int i = 0; i < count; i++)
        if (fabs(observed[i]) <= target)
            return (i + 1) * frames / rate;
    assert(!"release never reached 63% of its settled reduction");
    return -1;
}
// Re-enabling the compressor after a silent bypass must not replay gain
// reduction captured before it was switched off.
static double bypass_state_db(double rate) {
    SKSynth *a = source(rate), *b = source(rate);
    chain(a, 1, -60, 20, .02f, .15f, 0, 12, 1);
    chain(b, 1, -60, 20, .02f, .15f, 0, 12, 1);
    render_both(a, b, 512, (int)(rate * .75) / 512);   // capture reduction
    chain(a, 0, -60, 20, .02f, .15f, 0, 12, 1);        // bypass A only
    sk_sampler_gain(a, 0, 0);
    sk_sampler_gain(b, 0, 0);
    render_both(a, b, 512, (int)(rate * .75) / 512);   // silence; B releases
    chain(a, 1, -60, 20, .02f, .15f, 0, 12, 1);
    sk_sampler_gain(a, 0, 1);
    sk_sampler_gain(b, 0, 1);
    // Skip the first 20 ms: residual sub-threshold detector state changes the
    // steepest part of the dB curve without being audible reduction. Stale
    // reduction from before the bypass persists for the release time, so the
    // comparison window still distinguishes it from a cleared detector.
    int settleBlocks = (int)(rate * .02) / 256;
    (void)gain_db(a, b, 256, settleBlocks);
    double db = gain_db(a, b, 256, (int)(rate * .1) / 256);
    sk_destroy(a);
    sk_destroy(b);
    return db;
}
// Identical per-sample arithmetic must not depend on how the host splits blocks.
static double patterned_energy(double rate, int patterned) {
    static const int pattern[] = {1, 7, 64, 255, 511};
    SKSynth *wet = source(rate);
    chain(wet, 1, -60, 20, .02f, .15f, 0, 12, 1);
    long limit = (long)(rate * .5), done = 0;
    int step = 0;
    double total = 0;
    while (done < limit) {
        int n = patterned ? pattern[step++ % 5] : 256;
        if (done + n > limit) n = (int)(limit - done);
        render(wet, wetL, wetR, n);
        total += energy(wetL, n);
        done += n;
    }
    sk_destroy(wet);
    return total;
}

int main(void) {
    const double rates[] = {44100, 48000, 96000};
    double heavy[3];

    for (int i = 0; i < 3; i++) {
        double rate = rates[i];
        // Below threshold with no makeup is unity, and ratio 1 can never reduce.
        double unity = settled_db(rate, 0, 20, .02f, .15f, 0, 0, 1);
        double noRatio = settled_db(rate, -60, 1, .02f, .15f, 0, 0, 1);
        // Above threshold the compressor reduces, and a higher ratio reduces more.
        heavy[i] = settled_db(rate, -60, 20, .02f, .15f, 0, 0, 1);
        double gentle = settled_db(rate, -60, 2, .02f, .15f, 0, 0, 1);
        // Input gain drives the detector, so above threshold the extra 12 dB at
        // the input is almost entirely cancelled: the net change is 12/ratio dB.
        double gained = settled_db(rate, -60, 20, .02f, .15f, 0, 12, 1);
        // Makeup gain is applied to the compressed path only.
        double made = settled_db(rate, 0, 20, .02f, .15f, 6, 0, 1);
        // Mix 0 is a true bypass: neither input gain nor makeup may reach the dry
        // signal, and it must match the compressor switched off.
        double dryMix = settled_db(rate, -60, 20, .02f, .15f, 6, 12, 0);
        double negativeMakeup = settled_db(rate, -60, 20, .02f, .15f, -24, 0, 0);
        // At 50% the result sits between the dry and the compressed-plus-makeup path.
        double half = settled_db(rate, -60, 20, .02f, .15f, 6, 0, .5f);
        double full = settled_db(rate, -60, 20, .02f, .15f, 6, 0, 1);
        printf("rate %.0f Hz: unity %+.3f, ratio-1 %+.3f, heavy %+.2f, gentle %+.2f, "
               "input %+.2f, makeup6 %+.2f, mix0 %+.2f, mix0/-24 %+.2f, "
               "half %+.2f, full %+.2f dB\n",
               rate, unity, noRatio, heavy[i], gentle, gained, made, dryMix,
               negativeMakeup, half, full);
        assert(fabs(unity) < .01);
        assert(fabs(noRatio) < .01);
        assert(heavy[i] < -12 && heavy[i] > -40);
        assert(gentle > heavy[i] + 6);
        assert(fabs((gained - heavy[i]) - 12.0 / 20.0) < .3);
        assert(fabs(made - 6) < .05);
        assert(fabs(dryMix) < 1e-4);
        assert(fabs(negativeMakeup) < 1e-4);
        assert(half < -3 && half > full + 1);
        // Block boundaries do not change the render.
        double uniform = patterned_energy(rate, 0), split = patterned_energy(rate, 1);
        assert(uniform > 0);
        assert(fabs(uniform - split) <= uniform * 1e-6);
    }
    // The same settings produce the same steady-state gain at every supported rate.
    double low = heavy[0], high = heavy[0];
    for (int i = 1; i < 3; i++) {
        if (heavy[i] < low) low = heavy[i];
        if (heavy[i] > high) high = heavy[i];
    }
    assert(high - low < .5);

    double fastAttack[3];
    for (int i = 0; i < 3; i++) {
        double settledFast = 0, settledSlow = 0;
        double attack = attack_time(rates[i], .05f, .15f, &settledFast);
        double attackLong = attack_time(rates[i], .1f, .15f, &settledSlow);
        double released = 0;
        double release = release_time(rates[i], .02f, .2f, &released);
        double stale = bypass_state_db(rates[i]);
        fastAttack[i] = attack;
        printf("rate %.0f Hz: attack63 %.4f s (%+.2f dB), attack100ms %.4f s, "
               "release63 %.4f s (%+.2f dB), re-enabled bypass %+.3f dB\n",
               rates[i], attack, settledFast, attackLong, release, released, stale);
        assert(fabs(settledFast) > 8 && fabs(settledSlow) > 8);
        // The attack setting controls the response: doubling it approximately
        // doubles the measured dB-domain point, and that point is reached before
        // the configured linear time constant. The band allows for the 5 ms
        // measurement blocks and the threshold-crossing part of the attack.
        assert(attack > .005 && attack < .05);
        assert(attackLong / attack > 1.4 && attackLong / attack < 2.6);
        assert(fabs(released) > 8);
        assert(release > .2 * .5 && release < .2 * 1.5);
        assert(fabs(stale) < .1);
    }
    double attackLow = fastAttack[0], attackHigh = fastAttack[0];
    for (int i = 1; i < 3; i++) {
        if (fastAttack[i] < attackLow) attackLow = fastAttack[i];
        if (fastAttack[i] > attackHigh) attackHigh = fastAttack[i];
    }
    assert(attackHigh - attackLow < .01);
    // Extreme legal values stay finite and never leave the limiter's bounds.
    for (int i = 0; i < 3; i++) {
        SKSynth *s = source(rates[i]);
        chain(s, 1, -60, 20, .001f, .01f, 24, 24, 0);
        render(s, wetL, wetR, 256);
        chain(s, 1, 0, 1, 1, 3, -24, -24, 1);
        render(s, wetL, wetR, 256);
        chain(s, 0, -60, 20, .001f, .01f, 24, 24, 1);
        render(s, wetL, wetR, 256);
        sk_destroy(s);
    }
    printf("PASS: compressor gain transfer, makeup/mix, bypass state, attack/release "
           "and block invariance at 44.1/48/96 kHz (heavy gain %.2f/%.2f/%.2f dB)\n",
           heavy[0], heavy[1], heavy[2]);
}
