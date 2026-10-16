#include "Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static void configure(SKSynth*s,float left,float right,int ping){
 sk_effect(s,0,0,3,1);sk_effect_parameter(s,0,0,0,.5f);sk_effect_parameter(s,0,0,1,1);sk_effect_parameter(s,0,0,2,20000);sk_effect_parameter(s,0,0,3,1);
 sk_imported_delay(s,0,1,left,right,ping,20,20000);
}
int main(void){
 const int frames=200000;float*l=calloc(frames,sizeof(float)),*r=calloc(frames,sizeof(float));
 SKSynth*a=sk_create_effects_with_capacity(48000,16),*b=sk_create_effects_with_capacity(48000,16);assert(a&&b&&l&&r);
 configure(a,.1f,.2f,0);configure(b,.1f,.2f,0);l[0]=r[0]=1;sk_process_effects_stereo(a,b,l,r,20000);
 assert(fabsf(l[4800]-1)<.001f&&fabsf(r[9600]-1)<.001f);assert(fabsf(l[9600]-.5f)<.001f&&fabsf(r[4800])<.001f);
 sk_panic(a);sk_panic(b);configure(a,.1f,.2f,1);configure(b,.1f,.2f,1);
 for(int i=0;i<frames;i++)l[i]=r[i]=0;l[0]=r[0]=1;sk_process_effects_stereo(a,b,l,r,20000);
 assert(fabsf(l[4800]-1)<.001f&&fabsf(r[4800])<.001f);assert(fabsf(r[14400]-.5f)<.001f);
 sk_panic(a);sk_panic(b);configure(a,3,3,0);configure(b,3,3,0);
 for(int i=0;i<frames;i++)l[i]=r[i]=0;l[0]=1;sk_process_effects_stereo(a,b,l,r,frames);
 assert(fabsf(l[144000]-1)<.001f);for(int i=0;i<frames;i++){assert(isfinite(l[i])&&isfinite(r[i]));if(i<144000)assert(fabsf(l[i])<.001f);}
 sk_panic(a);sk_panic(b);for(int i=0;i<frames;i++)l[i]=r[i]=0;sk_process_effects_stereo(a,b,l,r,frames);for(int i=0;i<frames;i++)assert(l[i]==0&&r[i]==0);
 sk_panic(a);sk_panic(b);configure(a,.1f,.2f,0);configure(b,.1f,.2f,0);
 sk_imported_delay_channel(a,0,1,.2f,0,1);sk_imported_delay_channel(b,0,1,.3f,.4f,.5f);
 for(int i=0;i<frames;i++)l[i]=r[i]=0;l[0]=1;sk_process_effects_stereo(a,b,l,r,30000);
 assert(fabsf(l[4800]-1)<.001f);assert(fabsf(l[9600]-.2f)<.001f);
 assert(fabsf(r[14400]-.2f)<.001f); // left echo .4 cross * right .5 mix
 for(int i=0;i<30000;i++)assert(isfinite(l[i])&&isfinite(r[i]));
 sk_destroy(a);sk_destroy(b);free(l);free(r);puts("PASS: independent stereo delay times, linear feedback, ping-pong cross-feedback, three-second delay and panic silence");
}
