#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static SKSynth* make(void){
 SKSynth*s=sk_create_effects(48000);assert(s);sk_effect(s,0,0,13,1);
 sk_effect_parameter(s,0,0,10,1); // source reverb core
 sk_effect_parameter(s,0,0,5,0);sk_effect_parameter(s,0,0,6,1);
 sk_effect_parameter(s,0,0,7,0);sk_effect_parameter(s,0,0,8,1);return s;
}
int main(void){
 for(int stereo=0;stereo<2;stereo++){
  SKSynth*a=make(),*b=make(),*ar=make(),*br=make();
  float*x=calloc(48000,sizeof(float)),*y=calloc(48000,sizeof(float));
  float*xr=calloc(48000,sizeof(float)),*yr=calloc(48000,sizeof(float));
  x[0]=y[0]=.1f;xr[0]=yr[0]=.05f;
  if(stereo){sk_process_effects_stereo(a,ar,x,xr,48000);sk_process_effects_stereo(b,br,y,yr,48000);}
  else {sk_process_effects(a,x,48000);sk_process_effects(b,y,48000);}
  // After silence has cleared the input chorus buffer, changing chorus must
  // not modulate a tail that is already inside the reverb tank.
  sk_effect_parameter(b,0,0,5,1);sk_effect_parameter(br,0,0,5,1);
  for(int i=0;i<48000;i++)x[i]=y[i]=xr[i]=yr[i]=0;
  if(stereo){sk_process_effects_stereo(a,ar,x,xr,48000);sk_process_effects_stereo(b,br,y,yr,48000);}
  else {sk_process_effects(a,x,48000);sk_process_effects(b,y,48000);}
  double energy=0;for(int i=0;i<48000;i++){assert(isfinite(y[i]));assert(fabsf(x[i]-y[i])<1e-8f);energy+=x[i]*x[i];if(stereo)assert(fabsf(xr[i]-yr[i])<1e-8f);}
  assert(energy>1e-12);free(x);free(y);free(xr);free(yr);sk_destroy(a);sk_destroy(b);sk_destroy(ar);sk_destroy(br);
 }
 puts("PASS PrimaVerb chorus precedes tank in mono and stereo; existing tails stay unchanged");
}
