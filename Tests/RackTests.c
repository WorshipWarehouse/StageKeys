#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#define N 512
static float l[N],r[N];
static double energy(SKSynth *s,int blocks,int channel){double e=0;for(int b=0;b<blocks;b++){sk_render(s,l,r,N);for(int i=0;i<N;i++){assert(isfinite(l[i])&&isfinite(r[i]));assert(fabsf(l[i])<=1&&fabsf(r[i])<=1);float x=channel?r[i]:l[i];e+=x*x;}}return e;}
int main(void){
 SKSynth *s=sk_create(48000);assert(s);
 // The last sound bus and tonic bus are independent and both render.
 sk_gain(s,14,0.8,0);sk_note_on(s,60,60,1,14,0.7);assert(energy(s,50,0)>0.1);
 sk_pan(s,14,-1);assert(energy(s,30,1)<1e-10);assert(energy(s,20,0)>0.1);
 sk_gain(s,14,0,0);sk_gain(s,15,0.6,0);sk_note_on(s,256,48,1,15,0.7);assert(energy(s,50,1)>0.1);sk_panic(s);assert(energy(s,1,0)==0);
 // All fifteen sound modules can create voices together, with bounds maintained.
 for(int i=0;i<15;i++){sk_gain(s,i,0.4,0);sk_pan(s,i,0);for(int n=0;n<4;n++)sk_note_on(s,60+n,60+n*4,i%3,i,0.7);}
 assert(energy(s,50,0)>0.1);sk_panic(s);assert(energy(s,1,0)==0);
 // Block sustain releases only the opted-out module.
 sk_block_sustain(s,14,1);sk_sustain(s,1);sk_note_on(s,60,60,1,14,0.8);energy(s,50,0);sk_note_off(s,60);energy(s,1500,0);assert(energy(s,1,0)<1e-8);sk_panic(s);energy(s,1,0);
 // Each real effect changes output, and Panic clears delay/filter history.
 for(int kind=1;kind<=3;kind++){
  SKSynth *dry=sk_create(48000),*fx=sk_create(48000);assert(dry&&fx);
  sk_effect(fx,14,0,kind,0.8);sk_note_on(dry,60,72,0,14,0.8);sk_note_on(fx,60,72,0,14,0.8);
  double a=energy(dry,100,0),b=energy(fx,100,0);assert(fabs(a-b)>0.01);
  sk_panic(fx);assert(energy(fx,1,0)==0);sk_destroy(dry);sk_destroy(fx);
 }
 // The synth clock now publishes tempo for synced effects only; the metronome
 // renders on its own path (MetronomeTests). Reintroducing a synth click here
 // would double-trigger the app's metronome.
 sk_clock(s,120);assert(energy(s,50,0)==0);sk_panic(s);assert(energy(s,1,0)==0);
 // Ordered panic must not drop a new note queued immediately afterwards.
 sk_panic(s);sk_gain(s,14,0.7,0);sk_note_on(s,60,60,0,14,0.8);assert(energy(s,20,0)>0.01);sk_panic(s);assert(energy(s,1,0)==0);
 sk_destroy(s);puts("PASS: 15-layer rack, separate tonic, stereo pan, block sustain, three DSP effects, clock tempo only, panic cleanup");
}
