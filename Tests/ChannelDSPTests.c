#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
static double energy(SKSynth*s,int blocks){float l[512],r[512];double e=0;for(int b=0;b<blocks;b++){sk_render(s,l,r,512);for(int i=0;i<512;i++){assert(isfinite(l[i]));assert(isfinite(r[i]));e+=l[i]*l[i];}}return e;}
static SKSynth* tone(void){SKSynth*s=sk_create(48000);assert(s);sk_envelope(s,0,.001,.001,1,.01);sk_note_on(s,60,84,1,0,1);return s;}
int main(void){
 SKSynth*s=tone();double dry=energy(s,30);assert(dry>.01);sk_sampler_gain(s,0,0);assert(energy(s,3)<1e-10);sk_destroy(s);
 s=tone();sk_filter(s,0,40,.707);assert(energy(s,30)<dry*.02);sk_destroy(s);
 s=tone();sk_eq(s,0,7,40,0,.707);assert(energy(s,30)<dry*.02);sk_destroy(s);
 s=tone();sk_eq(s,0,0,10000,0,.707);assert(energy(s,30)<dry*.02);sk_destroy(s);
 s=tone();sk_compressor(s,0,1,-50,20,.0001,.1,0);assert(energy(s,30)<dry*.05);sk_destroy(s);
 s=tone();energy(s,10);sk_note_off(s,60);energy(s,10);assert(energy(s,3)<1e-10);sk_destroy(s);
 // Limiting a channel steals its own oldest voice; key-off for the stolen note cannot release the new one.
 s=tone();sk_voice_limit(s,0,1);sk_note_on(s,61,72,1,0,1);sk_note_off(s,60);assert(energy(s,30)>.01);sk_note_off(s,61);energy(s,10);assert(energy(s,3)<1e-10);sk_destroy(s);
 // Every EQ band and extreme legal parameter remains finite; panic clears filter tails.
 s=tone();for(int b=0;b<8;b++)sk_eq(s,0,b,100+b*1000,24,10);sk_filter(s,0,18000,10);energy(s,100);sk_panic(s);assert(energy(s,3)==0);sk_destroy(s);
 puts("channel DSP tests passed");
}
