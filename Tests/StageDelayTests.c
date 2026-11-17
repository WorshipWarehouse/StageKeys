#include "Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static void configure(SKSynth*s,int stage,int rate){
 sk_effect(s,0,0,3,1);sk_clock(s,123);sk_effect_parameter(s,0,0,0,.35f);sk_effect_parameter(s,0,0,1,.125f);
 sk_effect_parameter(s,0,0,2,20000);sk_effect_parameter(s,0,0,3,1);sk_effect_parameter(s,0,0,4,(float)stage);(void)rate;
}
static double energy(const float*x,int n){double e=0;for(int i=0;i<n;i++){assert(isfinite(x[i]));assert(fabsf(x[i])<16);e+=(double)x[i]*x[i];}return e;}
int main(void){
 const int rates[]={44100,48000,96000};
 for(int r=0;r<3;r++){
  int rate=rates[r],n=rate*2;float*stage=calloc(n,sizeof(float)),*legacy=calloc(n,sizeof(float));assert(stage&&legacy);
  SKSynth*a=sk_create_effects(rate),*b=sk_create_effects(rate);assert(a&&b);configure(a,1,rate);configure(b,0,rate);
  for(int i=0;i<n;i++)stage[i]=legacy[i]=.2f*sinf(6.28318530718f*997*i/rate);
  sk_process_effects(a,stage,n);sk_process_effects(b,legacy,n);
  double difference=0;for(int i=0;i<n;i++){double d=stage[i]-legacy[i];difference+=d*d;}
  assert(energy(stage,n)>1e-4&&difference>1e-6);
  sk_panic(a);for(int i=0;i<512;i++)stage[i]=0;sk_process_effects(a,stage,512);assert(energy(stage,512)==0);
  printf("PASS Stage Delay %d Hz: finite cubic/linear difference=%g\n",rate,difference);
  sk_destroy(a);sk_destroy(b);free(stage);free(legacy);
 }
}
