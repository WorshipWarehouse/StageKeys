#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static double energy(const float*x,int n){double e=0;for(int i=0;i<n;i++){assert(isfinite(x[i]));assert(fabsf(x[i])<4);e+=(double)x[i]*x[i];}return e;}
static void setup(SKSynth*s,int stage){sk_effect(s,0,0,5,1);float p[]={.65f,.4f,.2f,1,1,(float)stage};for(int i=0;i<6;i++)sk_effect_parameter(s,0,0,i,p[i]);}
int main(void){
 const int rates[]={44100,48000,96000};
 for(int r=0;r<3;r++){
  int rate=rates[r],n=rate*2;float*l=calloc(n,sizeof(float)),*right=calloc(n,sizeof(float)),*legacy=calloc(n,sizeof(float));assert(l&&right&&legacy);
  SKSynth*a=sk_create_effects(rate),*b=sk_create_effects(rate),*old=sk_create_effects(rate);setup(a,1);setup(b,1);setup(old,0);
  for(int i=0;i<n;i++)l[i]=right[i]=legacy[i]=i<rate ? .08f*sinf(i*6.28318530718f*311/rate):0;
  sk_process_effects_stereo(a,b,l,right,n);sk_process_effects(old,legacy,n);
  double stereo=0,different=0;for(int i=0;i<n;i++){double d=l[i]-right[i],q=l[i]-legacy[i];stereo+=d*d;different+=q*q;}
  assert(energy(l,n)>1e-5&&energy(right,n)>1e-5&&stereo>1e-5&&different>1e-5);
  sk_panic(a);sk_panic(b);for(int i=0;i<512;i++)l[i]=right[i]=0;sk_process_effects_stereo(a,b,l,right,512);assert(energy(l,512)==0&&energy(right,512)==0);
  printf("PASS Stage Chorus %d Hz: finite stereo=%g legacy difference=%g\n",rate,stereo,different);
  sk_destroy(a);sk_destroy(b);sk_destroy(old);free(l);free(right);free(legacy);
 }
}
