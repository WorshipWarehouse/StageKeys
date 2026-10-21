#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdlib.h>
#include <stdio.h>
static double ratio(int rate,float tone){
 int n=rate*5;float*x=calloc(n,sizeof(float));SKSynth*s=sk_create_effects(rate);assert(s&&x);
 sk_effect(s,0,0,10,1);sk_effect_parameter(s,0,0,0,0);sk_effect_parameter(s,0,0,1,.8f);sk_effect_parameter(s,0,0,2,.9f);sk_effect_parameter(s,0,0,4,0);sk_effect_parameter(s,0,0,6,tone);sk_effect_parameter(s,0,0,7,0);sk_effect_parameter(s,0,0,8,1);
 for(int i=0;i<rate/10;i++)x[i]=.1f*sinf(i*6.283185307f*4000/rate)*sinf(i*3.141592654f/(rate/10));
 sk_process_effects(s,x,n);double early=0,late=0;
 for(int i=0;i<n;i++){assert(isfinite(x[i])&&fabsf(x[i])<1);if(i>rate/2&&i<rate)early+=x[i]*x[i];if(i>rate*2&&i<rate*3)late+=x[i]*x[i];}
 assert(early>1e-15);sk_panic(s);float silence[1024]={0};sk_process_effects(s,silence,1024);for(int i=0;i<1024;i++)assert(silence[i]==0);
 sk_destroy(s);free(x);return late/early;
}
int main(void){for(int rate=44100;rate<=96000;rate=rate==44100?48000:rate*2){double dark=ratio(rate,1200),bright=ratio(rate,14000);printf("Tone decay %d: dark %.9g bright %.9g\n",rate,dark,bright);assert(dark<bright*.25);}puts("PASS: Shimmer Tone damps high-frequency recirculation, not only the output; finite tails and Panic");}
