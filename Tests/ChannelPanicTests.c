#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
int main(void){
 SKSynth*s=sk_create(48000);float l[512],r[512];
 for(int i=0;i<16;i++)sk_gain(s,i,i<2?1:0,0);
 sk_pan(s,0,-1);sk_pan(s,1,1);sk_sustain(s,1);
 sk_note_on(s,10,60,0,0,1);sk_note_on(s,11,64,0,1,1);
 for(int b=0;b<20;b++)sk_render(s,l,r,512);
 sk_note_off_channel(s,10,0,0);sk_note_off_channel(s,11,1,0);
 sk_panic_channel(s,0);double left=0,right=0;
 for(int b=0;b<20;b++){sk_render(s,l,r,512);for(int n=0;n<512;n++){left+=l[n]*l[n];right+=r[n]*r[n];}}
 assert(left<1e-12&&right>.001);
 sk_sustain(s,0);for(int b=0;b<500;b++)sk_render(s,l,r,512);
 double tail=0;for(int n=0;n<512;n++)tail+=fabs(r[n]);assert(tail<.001);
 sk_destroy(s);puts("PASS: channel panic clears sustained voices without silencing another channel or changing global pedal state");
}
