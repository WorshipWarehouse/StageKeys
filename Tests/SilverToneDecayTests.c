#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdlib.h>
#include <stdio.h>
static double ratio(int rate,float tone){
 int n=rate*5;float*x=calloc(n,sizeof(float));SKSynth*s=sk_create_effects(rate);assert(s&&x);
 sk_effect(s,0,0,16,1);float p[]={0,0,160,.81,100,tone,0,0,0,0,1};for(int i=0;i<11;i++)sk_effect_parameter(s,0,0,i,p[i]);
 for(int i=0;i<rate/10;i++)x[i]=.1f*sinf(i*6.283185307f*4000/rate)*sinf(i*3.141592654f/(rate/10));
 sk_process_effects(s,x,n);double early=0,late=0;
 for(int i=0;i<n;i++){assert(isfinite(x[i])&&fabsf(x[i])<1);if(i>rate/2&&i<rate)early+=x[i]*x[i];if(i>rate*2&&i<rate*3)late+=x[i]*x[i];}
 assert(early>1e-15);sk_panic(s);float silence[1024]={0};sk_process_effects(s,silence,1024);for(int i=0;i<1024;i++)assert(silence[i]==0);
 sk_destroy(s);free(x);return late/early;
}
int main(void){for(int rate=44100;rate<=96000;rate=rate==44100?48000:rate*2){double dark=ratio(rate,1200),bright=ratio(rate,14000);printf("Tone decay %d: dark %.9g bright %.9g\n",rate,dark,bright);assert(dark<bright*.8);}puts("PASS: SilverVerb Tone damps high-frequency recirculation, not only the output; finite tails and Panic");}
