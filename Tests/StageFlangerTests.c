#include "Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define N 512
#define TAU 6.283185307179586

static void configure(SKSynth*s,int stage,float hz,float depth,float feedback,float mix){
 sk_effect(s,0,0,8,1);
 sk_effect_parameter(s,0,0,0,hz);
 sk_effect_parameter(s,0,0,1,depth);
 sk_effect_parameter(s,0,0,2,feedback);
 sk_effect_parameter(s,0,0,3,mix);
 sk_effect_parameter(s,0,0,4,(float)stage);
}
static void fill(float*x,int n,int rate,float hz,float gain){
 for(int i=0;i<n;i++)x[i]=gain*sinf((float)TAU*hz*i/rate);
}
static double energy(const float*x,int n,float bound){
 double e=0;for(int i=0;i<n;i++){assert(isfinite(x[i]));assert(fabsf(x[i])<bound);e+=(double)x[i]*x[i];}return e;
}
static void process(SKSynth*s,float*x,int n){
 for(int p=0;p<n;p+=N){int block=n-p<N?n-p:N;sk_process_effects(s,x+p,block);}
}

int main(void){
 const int rates[]={44100,48000,96000};
 for(int r=0;r<3;r++){
  int rate=rates[r],n=rate*2;
  float*dry=calloc(n,sizeof(float)),*wet=calloc(rate*10,sizeof(float)),*right=calloc(n,sizeof(float)),*legacy=calloc(n,sizeof(float));
  assert(dry&&wet&&right&&legacy);

  // A zero mix must be an exact dry identity, even with depth and feedback set.
  SKSynth*identity=sk_create_effects(rate);assert(identity);
  configure(identity,1,.25f,1,.9f,0);
  fill(dry,n,rate,311,.2f);memcpy(wet,dry,n*sizeof(float));
  process(identity,wet,n);
  for(int i=0;i<n;i++)assert(wet[i]==dry[i]);
  sk_destroy(identity);
  printf("PASS Stage Flanger %d Hz: zero mix is exact dry\n",rate);

  // A new or reset Stage core starts disengaged and fades in, so its cleared
  // delay taps cannot produce a one-sample dropout.
  SKSynth*fade=sk_create_effects(rate);assert(fade);
  configure(fade,1,.5f,.5f,.5f,1);
  fill(wet,N,rate,440,.2f);
  float first=wet[0];
  sk_process_effects(fade,wet,N);
  assert(fabsf(wet[0]-first)<1e-6f);
  sk_destroy(fade);
  printf("PASS Stage Flanger %d Hz: starts disengaged after reset\n",rate);

  // The Stage core must produce finite stereo output, a different image on the
  // two sides and a different result from the retained legacy core.
  SKSynth*left=sk_create_effects(rate),*rightState=sk_create_effects(rate),*old=sk_create_effects(rate);assert(left&&rightState&&old);
  configure(left,1,.35f,.9f,-.75f,1);configure(rightState,1,.35f,.9f,-.75f,1);configure(old,0,.35f,.9f,-.75f,1);
  fill(wet,n,rate,311,.08f);memcpy(right,wet,n*sizeof(float));memcpy(legacy,wet,n*sizeof(float));
  sk_process_effects_stereo(left,rightState,wet,right,n);sk_process_effects(old,legacy,n);
  double stereo=0,different=0;
  for(int i=0;i<n;i++){double d=wet[i]-right[i],q=wet[i]-legacy[i];stereo+=d*d;different+=q*q;}
  assert(energy(wet,n,8)>1e-6&&energy(right,n,8)>1e-6&&stereo>1e-8&&different>1e-6);
  printf("PASS Stage Flanger %d Hz: finite, stereo phase=%g, legacy difference=%g\n",rate,stereo,different);
  sk_destroy(left);sk_destroy(rightState);sk_destroy(old);

  // Either feedback polarity must remain finite over ten seconds at maximum
  // depth and feedback, then Panic must clear every history twice.
  for(int sign=-1;sign<=1;sign+=2){
   SKSynth*s=sk_create_effects(rate);assert(s);
   configure(s,1,.1f,1,.95f*sign,1);
   fill(wet,rate*10,rate,110,.15f);
   for(int p=0;p<rate*10;p+=N){int block=N;if(p+block>rate*10)block=rate*10-p;sk_process_effects(s,wet+p,block);for(int i=0;i<block;i++)assert(isfinite(wet[p+i])&&fabsf(wet[p+i])<8);}
   sk_panic(s);fill(wet,N,rate,110,0);sk_process_effects(s,wet,N);assert(energy(wet,N,1e-12)==0);
   sk_panic(s);sk_process_effects(s,wet,N);assert(energy(wet,N,1e-12)==0);
   sk_destroy(s);
  }
  printf("PASS Stage Flanger %d Hz: both feedback polarities bounded, Panic repeatable\n",rate);

  // Rapid rate/depth/mix automation must stay finite and bounded.
  SKSynth*autoState=sk_create_effects(rate);assert(autoState);
  configure(autoState,1,.2f,0,0,0);
  fill(wet,n,rate,220,.12f);
  for(int p=0;p<n;p+=64){
   float t=(float)p/rate;
   sk_effect_parameter(autoState,0,0,0,.1f+9.9f*(.5f+.5f*sinf(TAU*t*.7f)));
   sk_effect_parameter(autoState,0,0,1,.5f+.5f*sinf(TAU*t*.9f));
   sk_effect_parameter(autoState,0,0,2,.95f*sinf(TAU*t*.37f));
   sk_effect_parameter(autoState,0,0,3,.5f+.5f*sinf(TAU*t*.5f));
   sk_process_effects(autoState,wet+p,64);
  }
  assert(energy(wet,n,8)>1e-6);
  sk_destroy(autoState);
  printf("PASS Stage Flanger %d Hz: rapid automation finite\n",rate);

  // A stepped mix/depth change must be smoother on the Stage core than the
  // legacy processor, which applies the new value on the next block.
  SKSynth*stageStep=sk_create_effects(rate),*legacyStep=sk_create_effects(rate);assert(stageStep&&legacyStep);
  // Zero depth makes the legacy 0.5 ms tap and the Stage 1.5 ms tap both land
  // near 180 degrees at 1 kHz, so the unsmoothed legacy mix step is a known
  // large discontinuity while the Stage core crossfades it.
  configure(stageStep,1,.5f,0,0,0);configure(legacyStep,0,.5f,0,0,0);
  fill(wet,n,rate,1000,.2f);memcpy(right,wet,n*sizeof(float));
  int settle=rate+1234;
  sk_process_effects(stageStep,wet,settle);sk_process_effects(legacyStep,right,settle);
  float last=wet[settle-1];
  sk_effect_parameter(stageStep,0,0,3,1);sk_effect_parameter(legacyStep,0,0,3,1);
  sk_process_effects(stageStep,wet+settle,N);sk_process_effects(legacyStep,right+settle,N);
  // Compare the first sample after the step only. A full-block peak would be
  // dominated by the input waveform's own slope, not by the parameter step.
  float stageJump=fabsf(wet[settle]-last);
  float legacyJump=fabsf(right[settle]-last);
  if(!(stageJump<legacyJump*.5f))fprintf(stderr,"step failure %d Hz: stage=%g legacy=%g last=%g stage0=%g legacy0=%g\n",rate,stageJump,legacyJump,last,wet[settle],right[settle]);
  assert(stageJump<legacyJump*.5f);
  printf("PASS Stage Flanger %d Hz: smoothed mix step %g < legacy %g\n",rate,stageJump,legacyJump);
  sk_destroy(stageStep);sk_destroy(legacyStep);

  // A depth step changes the delay time. The Stage core smooths it; the legacy
  // core steps the read position on the next block.
  SKSynth*stageDepth=sk_create_effects(rate),*legacyDepth=sk_create_effects(rate);assert(stageDepth&&legacyDepth);
  configure(stageDepth,1,.5f,0,0,1);configure(legacyDepth,0,.5f,0,0,1);
  fill(wet,n,rate,1000,.2f);memcpy(right,wet,n*sizeof(float));
  sk_process_effects(stageDepth,wet,settle);sk_process_effects(legacyDepth,right,settle);
  float stageLast=wet[settle-1],legacyLast=right[settle-1];
  sk_effect_parameter(stageDepth,0,0,1,1);sk_effect_parameter(legacyDepth,0,0,1,1);
  sk_process_effects(stageDepth,wet+settle,N);sk_process_effects(legacyDepth,right+settle,N);
  float stageDepthJump=fabsf(wet[settle]-stageLast),legacyDepthJump=fabsf(right[settle]-legacyLast);
  assert(stageDepthJump<legacyDepthJump*.5f);
  printf("PASS Stage Flanger %d Hz: smoothed depth step %g < legacy %g\n",rate,stageDepthJump,legacyDepthJump);
  sk_destroy(stageDepth);sk_destroy(legacyDepth);

  // Eight simultaneous instances, ten seconds each. The reported timing is a
  // sanitizer-suite smoke figure, not release-build CPU evidence.
  SKSynth*stack[8];for(int i=0;i<8;i++){stack[i]=sk_create_effects(rate);assert(stack[i]);configure(stack[i],1,.2f+.05f*i,.8f,.6f,1);}
  fill(wet,rate*10,rate,220,.05f);
  int frames=rate*10;double worst=0,stackedEnergy=0;
  for(int p=0;p<frames;p+=N){int block=frames-p<N?frames-p:N;
   float input[N];memcpy(input,wet+p,block*sizeof(float));
   for(int i=0;i<8;i++){
    float work[N];memcpy(work,input,block*sizeof(float));
    double start=(double)clock()/CLOCKS_PER_SEC;
    sk_process_effects(stack[i],work,block);
    double elapsed=(double)clock()/CLOCKS_PER_SEC-start;if(elapsed>worst)worst=elapsed;
    stackedEnergy+=energy(work,block,8);
   }
  }
  assert(stackedEnergy>1e-8);
  long allocated=(long)(rate>48000?rate*2:96000)+(long)ceil(rate*.2)+2;
  printf("PASS Stage Flanger %d Hz: 8 instances finite, delay storage %.2f MiB, worst block %.3f ms (sanitizer smoke)\n",rate,8.0*3*allocated*sizeof(float)/(1024.0*1024.0),worst*1000);
  for(int i=0;i<8;i++)sk_destroy(stack[i]);

  free(dry);free(wet);free(right);free(legacy);
 }
 puts("PASS Stage Flanger catalog: dry identity, stereo, cores, feedback, automation, reset and stacking");
 return 0;
}
