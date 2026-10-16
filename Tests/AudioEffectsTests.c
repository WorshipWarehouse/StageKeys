#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#define N 512
static void setup(SKSynth*s){sk_envelope(s,0,.001,.001,1,.01);sk_gain(s,0,.5,0);sk_note_on(s,69,69,1,0,.8);}
static void render(SKSynth*s,float*l,int frames){float r[N];for(int p=0;p<frames;p+=N){int n=frames-p<N?frames-p:N;sk_render(s,l+p,r,n);for(int i=0;i<n;i++){assert(isfinite(l[p+i])&&isfinite(r[i]));assert(fabsf(l[p+i])<=1&&fabsf(r[i])<=1);}}}
static double difference(float*a,float*b,int n){double e=0;for(int i=0;i<n;i++)e+=(a[i]-b[i])*(a[i]-b[i]);return e;}
static double powerAt(float*x,int n,double hz){double r=0,i=0;for(int k=0;k<n;k++){r+=x[k]*cos(6.28318530718*hz*k/48000);i+=x[k]*sin(6.28318530718*hz*k/48000);}return r*r+i*i;}
int main(void){
 int frames=48000;float *dry=calloc(frames,sizeof(float)),*wet=calloc(frames,sizeof(float));assert(dry&&wet);
 SKSynth*base=sk_create(48000);setup(base);render(base,dry,frames);sk_destroy(base);
 for(int kind=1;kind<=17;kind++){
  SKSynth*s=sk_create(48000);setup(s);sk_effect(s,0,0,kind,.7);
  // Trigger parameter mode for each effect; choose an audible setting for unity-default processors.
  switch(kind){
   case 1:sk_effect_parameter(s,0,0,0,600);break;
   case 2:sk_effect_parameter(s,0,0,0,.8);break;
   case 3:sk_effect_parameter(s,0,0,1,.25);break;
   case 4:sk_effect_parameter(s,0,0,0,4);break;
   case 5:sk_effect_parameter(s,0,0,0,.68);break;
   case 6:sk_effect_parameter(s,0,0,5,1);break;
   case 7:sk_effect_parameter(s,0,0,7,12);break;
   case 8:sk_effect_parameter(s,0,0,0,.2);break;
   case 9:sk_effect_parameter(s,0,0,0,-12);break;
   case 10:sk_effect_parameter(s,0,0,8,.6);break;
   case 11:sk_effect_parameter(s,0,0,0,.96);break;
   case 12:sk_effect_parameter(s,0,0,1,1);break;
   case 13:sk_effect_parameter(s,0,0,0,.5);break;
   case 14:sk_effect_parameter(s,0,0,0,2);break;
   case 15:sk_effect_parameter(s,0,0,0,20);break;
  }
  render(s,wet,frames);double d=difference(dry,wet,frames);assert(d>.001);
  if(kind==12){double fundamental=powerAt(wet+24000,24000,440),octave=powerAt(wet+24000,24000,880);assert(octave>fundamental*2);}
  // Bypass must restore dry note generation without retaining processor tail.
  sk_panic(s);sk_effect(s,0,0,0,0);setup(s);render(s,wet,frames);assert(difference(dry,wet,frames)<1e-10);
  sk_panic(s);render(s,wet,N);for(int j=0;j<N;j++)assert(wet[j]==0);
  // Invalid values cannot corrupt audio state or write beyond parameter storage.
  sk_effect_parameter(s,0,0,31,NAN);sk_effect_parameter(s,15,2,100,INFINITY);render(s,wet,N);
  sk_destroy(s);printf("PASS effect %d audible, bounded, bypass and panic\n",kind);
 }
 // Independent slots and reconfiguration use bounded state, all15 channels are legal.
 SKSynth*s=sk_create(44100);for(int l=0;l<15;l++){sk_effect(s,l,0,10,1);sk_effect_parameter(s,l,0,1,.95);sk_effect(s,l,1,8,1);sk_effect_parameter(s,l,1,2,-.95);sk_note_on(s,l,36+l,1,l,1);}render(s,wet,frames);sk_panic(s);render(s,wet,N);for(int i=0;i<N;i++)assert(wet[i]==0);sk_destroy(s);
 free(dry);free(wet);puts("PASS all audio effect catalog tests");
}
