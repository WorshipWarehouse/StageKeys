#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static void setup(SKSynth*s,float pitch,float chorus,float dry,float wet){
 sk_effect(s,0,0,15,1);float p[]={18,.7f,.8f,100,14000,pitch,chorus,1,dry,wet};for(int i=0;i<10;i++)sk_effect_parameter(s,0,0,i,p[i]);
}
int main(void){
 int rates[]={44100,48000,96000};for(int r=0;r<3;r++){int rate=rates[r];
  int n=rate*8;float*a=calloc(n,4),*b=calloc(n,4),*c=calloc(n,4),*d=calloc(n,4);
  SKSynth*sa=sk_create_effects(rate),*sb=sk_create_effects(rate),*sc=sk_create_effects(rate),*sd=sk_create_effects(rate);assert(a&&b&&c&&d&&sa&&sb&&sc&&sd);
  setup(sa,1,0,0,1);setup(sb,0,0,0,1);setup(sc,0,1,0,1);setup(sd,1,1,1,0);
  for(int i=0;i<rate;i++)a[i]=b[i]=c[i]=d[i]=.05f*sinf(i*6.2831853f*440/rate);
  sk_process_effects(sa,a,n);sk_process_effects(sb,b,n);sk_process_effects(sc,c,n);sk_process_effects(sd,d,n);
  double mod=0,chorus=0,tail=0;
  for(int i=0;i<n;i++){
   assert(isfinite(a[i])&&isfinite(b[i])&&isfinite(c[i])&&fabsf(a[i])<2&&fabsf(c[i])<2);
   float input=i<rate?.05f*sinf(i*6.2831853f*440/rate):0;assert(fabsf(d[i]-input)<1e-7);
   mod+=fabs(a[i]-b[i]);chorus+=fabs(c[i]-b[i]);if(i>rate*3)tail+=a[i]*a[i];
  }
  assert(mod>1&&chorus>1&&tail>1e-5);
  sk_panic(sa);for(int i=0;i<512;i++)a[i]=0;sk_process_effects(sa,a,512);for(int i=0;i<512;i++)assert(a[i]==0);
  sk_destroy(sa);sk_destroy(sb);sk_destroy(sc);sk_destroy(sd);free(a);free(b);free(c);free(d);
 }
 puts("PASS SolaVerb: independent pitch/chorus controls, dry identity, sustained finite tail, panic at 44.1/48/96kHz");
}
