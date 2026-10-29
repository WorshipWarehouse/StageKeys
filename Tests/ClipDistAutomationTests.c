#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
static void setup(SKSynth*s){
 sk_effect(s,0,0,17,1);float p[]={15,170,-16,0,4400,20000,0,980,0,0};
 for(int i=0;i<10;i++)sk_effect_parameter(s,0,0,i,p[i]);
}
int main(void){
 const int rates[]={44100,48000,96000};
 for(int r=0;r<3;r++){
  int rate=rates[r];SKSynth*a=sk_create_effects(rate),*b=sk_create_effects(rate);setup(a);setup(b);
  float x[256],y[256];
  for(int block=0;block<20;block++){
   for(int i=0;i<256;i++)x[i]=y[i]=.1f;
   sk_process_effects(a,x,256);sk_process_effects(b,y,256);
  }
  sk_effect_parameter(a,0,0,9,-12);
  float first=0,settled=0;
  for(int block=0;block<200;block++){
   for(int i=0;i<256;i++)x[i]=y[i]=.1f;
   sk_process_effects(a,x,256);sk_process_effects(b,y,256);
   if(!block)first=x[0]/y[0];settled=x[255]/y[255];
   for(int i=0;i<256;i++)assert(isfinite(x[i]));
  }
  assert(first>.99f&&first<1);assert(fabsf(settled-powf(10,-12.f/20))<.000001f);
  printf("PASS ClipDist %dHz output automation first ratio=%g settled=%g\n",rate,first,settled);
  sk_destroy(a);sk_destroy(b);
 }
}
