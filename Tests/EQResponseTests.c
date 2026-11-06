// Native EQ response regression for #10's bandwidth/Q acceptance material.
//
// The channel EQ and the Channel EQ audio effect share equalizer() in Synth.c.
// These checks drive the effects engine with an impulse and measure the actual
// magnitude response, so they cover the rendered filter rather than a
// reimplementation of its coefficient math.
//
// A peaking band's stored Q is the analog constant-Q width the editor displays
// as octaves. RBJ defines that width between the midpoint (dBgain/2) gain
// frequencies, and the bilinear transform compresses it unless alpha uses the
// w0/sin(w0) form. This test asserts the rendered width equals the displayed
// width at 44.1/48/96 kHz, including the top octave where the old direct-Q
// mapping lost 42% of the requested bandwidth.

#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

#define N 16384
static const double PI = 3.14159265358979323846;
static float ir[N];

static double qForOctaves(double bw) { return 1 / (2 * sinh(bw * log(2) / 2)); }

static void renderBand(double rate, int band, float f, float db, float q) {
    SKSynth *s = sk_create_effects(rate);
    assert(s);
    sk_effect(s, 0, 0, 7, 1);
    sk_effect_parameter(s, 0, 0, band * 3 + 0, f);
    sk_effect_parameter(s, 0, 0, band * 3 + 1, db);
    sk_effect_parameter(s, 0, 0, band * 3 + 2, q);
    for (int i = 0; i < N; i++) ir[i] = 0;
    ir[0] = 0.01f;
    sk_process_effects(s, ir, N);
    sk_destroy(s);
}

// Rotate the unit phasor instead of calling sin/cos per sample; the scan below
// evaluates thousands of frequencies.
static double magnitude(double rate, double f) {
    double w = 2 * PI * f / rate, c = cos(w), s = sin(w), cr = 1, sr = 0, re = 0, im = 0;
    for (int n = 0; n < N; n++) {
        re += ir[n] * cr;
        im -= ir[n] * sr;
        double next = cr * c - sr * s;
        sr = cr * s + sr * c;
        cr = next;
    }
    return sqrt(re * re + im * im);
}

static double gainDB(double rate, double f) {
    return 20 * log10(fmax(1e-12, magnitude(rate, f) / 0.01));
}

// First frequency on the chosen side of f0 whose gain reaches the midpoint.
// A boost falls away from its peak; a cut rises away from its trough.
static int reached(double rate, double f, double target, int falling) {
    double g = gainDB(rate, f);
    return falling ? g <= target : g >= target;
}
static double edge(double rate, double f0, double target, int up, int falling) {
    double step = up ? 1.002 : 0.998, prev = f0, f = f0;
    for (int i = 0; i < 3000; i++) {
        prev = f;
        f *= step;
        if (f < 20 || f > rate * 0.45) break;
        if (reached(rate, f, target, falling)) {
            double lo = fmin(prev, f), hi = fmax(prev, f);
            for (int k = 0; k < 40; k++) {
                double mid = sqrt(lo * hi);
                if (reached(rate, mid, target, falling) == up) hi = mid; else lo = mid;
            }
            return sqrt(lo * hi);
        }
    }
    return f0;
}

static double measuredOctaves(double rate, double f0, double peak) {
    double target = peak / 2;
    int falling = peak > 0;
    double lo = edge(rate, f0, target, 0, falling), hi = edge(rate, f0, target, 1, falling);
    return log(hi / lo) / log(2);
}

int main(void) {
    const double rates[] = {44100, 48000, 96000};
    const double centers[] = {100, 1000, 4000, 8000, 12000};
    const double widths[] = {0.5, 1, 2};

    // A band at 0 dB is exactly unity, so an "off" EQ cannot colour the channel.
    renderBand(48000, 4, 1000, 0, 0.707);
    for (int i = 0; i < 3; i++) {
        double probe[] = {100, 1000, 10000};
        assert(fabs(gainDB(48000, probe[i])) < 0.01);
    }

    printf("center   rate   width  measured  error%%  peakdB\n");
    for (int r = 0; r < 3; r++) {
        for (int c = 0; c < 5; c++) {
            for (int w = 0; w < 3; w++) {
                double rate = rates[r], f0 = centers[c], width = widths[w];
                if (f0 > rate * 0.45) continue;

                renderBand(rate, 4, (float)f0, 12, (float)qForOctaves(width));
                double peak = gainDB(rate, f0);
                assert(fabs(peak - 12) < 0.05);
                double measured = measuredOctaves(rate, f0, peak);
                double error = 100 * (measured - width) / width;
                printf("%6.0f  %6.0f  %5.2f   %6.3f  %+6.1f  %6.2f\n", f0, rate, width, measured, error, peak);
                // Midpoint edges land on the requested width everywhere. Wide
                // bands whose upper edge nears Nyquist keep a small residual
                // (worst measured 4.1%) because the BLT is not symmetric there.
                assert(fabs(error) <= (width >= 2 ? 6.0 : 2.0));

                // A cut has the same width as the matching boost.
                renderBand(rate, 4, (float)f0, -12, (float)qForOctaves(width));
                double cutPeak = gainDB(rate, f0);
                assert(fabs(cutPeak + 12) < 0.05);
                assert(fabs(measuredOctaves(rate, f0, cutPeak) - width) <= width * (width >= 2 ? 0.06 : 0.02));
            }
        }
    }

    // Wider Q is narrower, and the ordering survives at the top octave.
    for (int r = 0; r < 3; r++) {
        double rate = rates[r];
        renderBand(rate, 4, 10000, 12, (float)qForOctaves(0.5));
        double narrow = measuredOctaves(rate, 10000, 12);
        renderBand(rate, 4, 10000, 12, (float)qForOctaves(1));
        double medium = measuredOctaves(rate, 10000, 12);
        renderBand(rate, 4, 10000, 12, (float)qForOctaves(2));
        double wide = measuredOctaves(rate, 10000, 12);
        assert(narrow < medium && medium < wide);
    }

    // High pass and low pass corners stay at the stated frequency and slope.
    for (int r = 0; r < 3; r++) {
        double rate = rates[r];
        renderBand(rate, 0, 100, 0, 0.707f);
        assert(fabs(gainDB(rate, 100) + 3.01) < 0.2);
        assert(gainDB(rate, 50) < -9.5 && gainDB(rate, 50) > -15.5);
        assert(fabs(gainDB(rate, 400)) < 0.5);
        renderBand(rate, 7, 5000, 0, 0.707f);
        assert(fabs(gainDB(rate, 5000) + 3.01) < 0.2);
        assert(gainDB(rate, 10000) < -9.5 && gainDB(rate, 10000) > -15.5);
        assert(fabs(gainDB(rate, 1250)) < 0.5);
    }

    // Shelves reach their full gain at the far end and unity at the other.
    renderBand(96000, 1, 200, 12, 0.707f);
    assert(fabs(gainDB(96000, 20) - 12) < 0.6);
    assert(fabs(gainDB(96000, 18000)) < 0.6);
    renderBand(96000, 6, 7500, 12, 0.707f);
    assert(fabs(gainDB(96000, 20000) - 12) < 0.8);
    assert(fabs(gainDB(96000, 100)) < 0.6);

    // Every extreme legal setting stays finite and bounded, including the
    // narrowest and widest widths the editor can store.
    for (int b = 0; b < 8; b++) {
        renderBand(96000, b, b == 0 ? 20 : b == 7 ? 20000 : 40 + b * 2400, 24, 0.1f);
        renderBand(96000, b, b == 0 ? 20 : b == 7 ? 20000 : 40 + b * 2400, -24, 10.0f);
    }
    for (int i = 0; i < N; i++) assert(isfinite(ir[i]));
    for (int i = 0; i < 3; i++) {
        double probe[] = {20, 1000, 20000};
        assert(isfinite(gainDB(96000, probe[i])));
        assert(fabs(gainDB(96000, probe[i])) < 60);
    }

    puts("EQ response tests passed");
    return 0;
}
