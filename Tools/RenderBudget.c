// Measurement structure adapted from WorshipWarehouse/Clean-Room-SK
// RenderBudgetTests.swift at 554661c0665f082713003a45d92db468879fa92a.
// Owner authorized reuse. This measures StageKeys' actual C stereo effect path.
#include "Synth.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <mach/mach_time.h>

#define WARMUP 60
#define BLOCKS 240
#define TRIALS 3
#define MAX_FRAMES 512

static double tick_ns;
static uint64_t now_ticks(void) { return mach_absolute_time(); }
static int compare(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}
static void configure(SKSynth *s, int engaged) {
    if (!engaged) return;
    // The three slots available to a real layer: chorus -> delay -> Silver Reverb.
    sk_effect(s, 0, 0, 5, 1);
    sk_effect_parameter(s, 0, 0, 0, 0.4f);
    sk_effect(s, 0, 1, 3, 1);
    sk_effect_parameter(s, 0, 1, 0, 0.35f);
    sk_effect_parameter(s, 0, 1, 1, 0.25f);
    sk_effect(s, 0, 2, 16, 1);
    sk_effect_parameter(s, 0, 2, 0, 80);
}
static int measure(int rate, int frames, int trial, int engaged, int comma) {
    SKSynth *l = sk_create_effects(rate), *r = sk_create_effects(rate);
    if (!l || !r) { fprintf(stderr, "Cannot allocate effect states\n"); exit(1); }
    configure(l, engaged); configure(r, engaged);
    float left[MAX_FRAMES], right[MAX_FRAMES];
    double samples[BLOCKS], peak = 0, energy = 0;
    int over = 0;
    const double deadline = (double)frames / rate * 1e9;
    for (int block = 0; block < WARMUP + BLOCKS; block++) {
        // Identical generated input for both paths/trials; outside timed region.
        for (int i = 0; i < frames; i++) {
            double phase = (double)(block * frames + i) / rate;
            left[i] = (float)(0.03 * sin(phase * 6.283185307179586 * 220));
            right[i] = left[i] * 0.7f;
        }
        uint64_t start = now_ticks();
        sk_process_effects_stereo(l, r, left, right, (uint32_t)frames);
        double elapsed = (double)(now_ticks() - start) * tick_ns;
        if (!isfinite(elapsed) || elapsed < 0) { fprintf(stderr, "Invalid monotonic measurement\n"); exit(1); }
        if (block >= WARMUP) {
            samples[block - WARMUP] = elapsed;
            if (elapsed > deadline) over++;
        }
        for (int i = 0; i < frames; i++) {
            if (!isfinite(left[i]) || !isfinite(right[i])) { fprintf(stderr, "Nonfinite output\n"); exit(1); }
            peak = fmax(peak, fmax(fabs(left[i]), fabs(right[i])));
            energy += (double)left[i] * left[i] + (double)right[i] * right[i];
        }
    }
    if (!(energy > 0)) { fprintf(stderr, "Silent benchmark path\n"); exit(1); }
    qsort(samples, BLOCKS, sizeof(double), compare);
    double median = (samples[BLOCKS / 2 - 1] + samples[BLOCKS / 2]) / 2;
    double p95 = samples[(int)ceil(BLOCKS * 0.95) - 1];
    double worst = samples[BLOCKS - 1];
    printf("%s{\"rate\":%d,\"frames\":%d,\"channels\":2,\"trial\":%d,"
           "\"engaged\":%s,\"warmupBlocks\":%d,\"measuredBlocks\":%d,"
           "\"deadlineMicroseconds\":%.6f,\"medianMicroseconds\":%.6f,"
           "\"p95Microseconds\":%.6f,\"worstMicroseconds\":%.6f,"
           "\"medianDeadlineRatio\":%.9f,\"p95DeadlineRatio\":%.9f,"
           "\"worstDeadlineRatio\":%.9f,\"blocksOverDeadline\":%d,\"peak\":%.9f}",
           comma ? ",\n" : "", rate, frames, trial, engaged ? "true" : "false", WARMUP, BLOCKS,
           deadline / 1000, median / 1000, p95 / 1000, worst / 1000,
           median / deadline, p95 / deadline, worst / deadline, over, peak);
    sk_destroy(l); sk_destroy(r);
    return 1;
}
int main(void) {
    mach_timebase_info_data_t timebase;
    if (mach_timebase_info(&timebase) != KERN_SUCCESS || !timebase.denom) return 1;
    tick_ns = (double)timebase.numer / timebase.denom;
    const int rates[] = {44100, 48000, 96000}, sizes[] = {64, 257, 512};
    int comma = 0;
    printf("{\"format\":\"stagekeys-render-budget\",\"version\":1,"
           "\"path\":\"sk_process_effects_stereo\",\"effectKinds\":[5,3,16],\"rows\":[\n");
    for (int rate = 0; rate < 3; rate++) for (int size = 0; size < 3; size++)
        for (int trial = 0; trial < TRIALS; trial++) {
            // Alternate first path so every pair does not favor the same thermal/cache order.
            for (int path = 0; path < 2; path++)
                comma = measure(rates[rate], sizes[size], trial, (path + trial) % 2, comma);
        }
    puts("\n]}");
    return 0;
}
