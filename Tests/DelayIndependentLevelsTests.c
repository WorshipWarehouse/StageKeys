#include "Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static void configure(SKSynth*s,float dry,float wet){sk_effect(s,0,0,3,1);sk_effect_parameter(s,0,0,0,0);sk_effect_parameter(s,0,0,1,1);sk_effect_parameter(s,0,0,2,20000);sk_effect_parameter(s,0,0,3,1);sk_imported_delay(s,0,1,.01f,.01f,0,20,20000);sk_imported_delay_levels(s,0,1,dry,wet);}
int main(void){
 const int rates[]={44100,48000,96000};
 for(int k=0;k<3;k++){
  int rate=rates[k],n=rate/5,delay=rate/100;float*a=calloc(n,sizeof(float)),*b=calloc(n,sizeof(float));
  SKSynth*l=sk_create_effects(rate),*r=sk_create_effects(rate);configure(l,.7f,.4f);configure(r,.7f,.4f);a[0]=.25f;b[0]=.1f;
  sk_process_effects_stereo(l,r,a,b,n);
  assert(fabsf(a[0]-.175f)<.000001f && fabsf(b[0]-.07f)<.000001f);
  assert(fabsf(a[delay]-.1f)<.00001f && fabsf(b[delay]-.04f)<.00001f);
  sk_destroy(l);sk_destroy(r);l=sk_create_effects(rate);r=sk_create_effects(rate);configure(l,0,0);configure(r,0,0);
  for(int i=0;i<n;i++)a[i]=b[i]=.2f;sk_process_effects_stereo(l,r,a,b,n);for(int i=0;i<n;i++)assert(a[i]==0&&b[i]==0);
  sk_destroy(l);sk_destroy(r);l=sk_create_effects(rate);r=sk_create_effects(rate);configure(l,1,0);configure(r,1,0);
  for(int i=0;i<n;i++)a[i]=b[i]=.2f;sk_process_effects_stereo(l,r,a,b,n);
  sk_imported_delay_levels(l,0,1,0,0);sk_imported_delay_levels(r,0,1,0,0);
  for(int i=0;i<n;i++)a[i]=b[i]=.2f;sk_process_effects_stereo(l,r,a,b,n);
  assert(a[0]>.199f && a[n-1]<.00002f);
  for(int i=1;i<n;i++){assert(isfinite(a[i])&&isfinite(b[i]));assert(fabsf(a[i]-a[i-1])<.001f);}
  sk_destroy(l);sk_destroy(r);free(a);free(b);
 }
 puts("PASS: independent delay dry/wet stereo impulse timing, exact silence and smooth automation at 44.1/48/96 kHz");
}
