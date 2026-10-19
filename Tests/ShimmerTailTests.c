#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static void configure(SKSynth*s,float amount,float feedback){sk_effect(s,0,0,10,1);sk_effect_parameter(s,0,0,0,amount);sk_effect_parameter(s,0,0,1,feedback);sk_effect_parameter(s,0,0,7,0);sk_effect_parameter(s,0,0,8,1);}
static double power(float*x,int begin,int end,double hz){double a=0,b=0;for(int i=begin;i<end;i++){double w=.5-.5*cos(6.283185307*(i-begin)/(end-begin-1));a+=x[i]*w*cos(i*6.283185307*hz/48000);b+=x[i]*w*sin(i*6.283185307*hz/48000);}return a*a+b*b;}
// Crossfaded grains and room modulation produce sidebands; compare bands,
// not one FFT bin whose energy can cancel for a particular delay length.
static double band(float*x,int low,int high){double total=0;for(int hz=low;hz<=high;hz+=2)total+=power(x,12000,36000,hz);return total;}
int main(void){int n=48000*8;float*a=calloc(n,sizeof(float)),*b=calloc(n,sizeof(float));assert(a&&b);SKSynth*l=sk_create_effects(48000),*r=sk_create_effects(48000);assert(l&&r);configure(l,1,.66);configure(r,0,.66);
 for(int i=0;i<48000;i++)a[i]=b[i]=.1f*sinf(i*6.283185307f*220/48000);
 sk_process_effects(l,a,n);sk_process_effects(r,b,n);
 for(int i=0;i<1000;i++)assert(a[i]==0); // no near-direct pitched attack
 assert(band(a,400,480)>band(a,190,250)*4);
 assert(band(b,190,250)>band(b,400,480)*4);
 for(int block=12;block<30;block++){double e=0;for(int i=block*4800;i<(block+1)*4800;i++)e+=a[i]*a[i];assert(e>1e-12);}
 sk_panic(l);sk_panic(r);configure(l,1,.95);configure(r,1,.95);
 for(int i=0;i<n;i++)a[i]=b[i]=i==0?.5f:0;sk_process_effects_stereo(l,r,a,b,n);double difference=0;
 for(int i=0;i<n;i++){assert(isfinite(a[i])&&isfinite(b[i])&&fabsf(a[i])<2&&fabsf(b[i])<2);difference+=fabs(a[i]-b[i]);}assert(difference>.001);
 sk_panic(l);sk_panic(r);for(int i=0;i<n;i++)a[i]=b[i]=0;sk_process_effects_stereo(l,r,a,b,n);for(int i=0;i<n;i++)assert(a[i]==0&&b[i]==0);
 sk_destroy(l);sk_destroy(r);free(a);free(b);puts("PASS shimmer: wet-only onset, octave shift, dense tail, stereo decorrelation, bounded feedback and panic");}
