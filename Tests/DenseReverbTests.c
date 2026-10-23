#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static void setup(SKSynth*s,int slot,int kind,float size,float reflect,float dry,float wet){
 sk_effect(s,0,slot,kind,1);
 float acoustic[]={size,23,reflect,80,8000,.12f,.4f,dry,wet,1,2};
 float ambient[]={23,size,reflect,80,8000,.5f,.12f,.4f,dry,wet,1,1};
 for(int i=0;i<(kind==13?11:12);i++)sk_effect_parameter(s,0,slot,i,kind==13?acoustic[i]:ambient[i]);
}
static double energy(float*x,int a,int b){double sum=0;for(int i=a;i<b;i++){assert(isfinite(x[i])&&fabsf(x[i])<4);sum+=x[i]*x[i];}return sum;}
int main(void){
 for(int rate=44100;rate<=96000;rate=rate==44100?48000:rate==48000?96000:96001){
  int n=rate*12;float*l=calloc(n,sizeof(float)),*r=calloc(n,sizeof(float)),*shorter=calloc(n,sizeof(float));
  for(int kind=13;kind<=15;kind+=2){
   SKSynth*a=sk_create_effects(rate),*b=sk_create_effects(rate),*c=sk_create_effects(rate);
   setup(a,0,kind,1,.95f,0,1);setup(b,0,kind,1,.95f,0,1);setup(c,0,kind,0,.1f,0,1);
   for(int i=0;i<n;i++)l[i]=r[i]=shorter[i]=i==0?.2f:0;
   sk_process_effects_stereo(a,b,l,r,n);sk_process_effects(c,shorter,n);
   double el=energy(l,rate,rate*3),er=energy(r,rate,rate*3),late=energy(l,rate*8,rate*12),early=energy(l,0,rate),diff=0;
   fprintf(stderr,"kind%d rate%d mid%g late%g shortlate%g\n",kind,rate,el,late,energy(shorter,rate*8,rate*12));
   assert(el>1e-8&&late>1e-10&&late>energy(shorter,rate*8,rate*12)*10);
   for(int i=0;i<n;i++){if(i<rate*.023)assert(l[i]==0&&r[i]==0);diff+=(l[i]-r[i])*(l[i]-r[i]);}
   assert(diff>el*.1&&er/el>.1&&er/el<10);
   sk_release_voices(a,0);
   // Same effect configuration must preserve an already-running tail.
   setup(a,0,kind,1,.95f,0,1);for(int i=0;i<rate;i++)l[i]=0;sk_process_effects(a,l,rate);assert(energy(l,0,rate)>1e-10);
   sk_panic(a);for(int i=0;i<512;i++)l[i]=0;sk_process_effects(a,l,512);assert(energy(l,0,512)==0);
   sk_destroy(a);a=sk_create_effects(rate);setup(a,0,kind,.5f,.5f,1,0);for(int i=0;i<512;i++)l[i]=.2f*sinf(i*.3f);float original[512];for(int i=0;i<512;i++)original[i]=l[i];sk_process_effects(a,l,512);for(int i=0;i<512;i++)assert(l[i]==original[i]);
   printf("PASS Dense %d %d Hz: early=%g late=%g stereo=%g\n",kind,rate,early,late,er/el);
   // Left-only excitation must reach both wet outputs, without dry crosstalk.
   sk_destroy(a);sk_destroy(b);a=sk_create_effects(rate);b=sk_create_effects(rate);
   setup(a,0,kind,.5f,.7f,0,1);setup(b,0,kind,.5f,.7f,0,1);
   for(int i=0;i<rate;i++){l[i]=i==0?.1f:0;r[i]=0;}sk_process_effects_stereo(a,b,l,r,rate);assert(energy(r,0,rate)>1e-9);
   sk_destroy(a);sk_destroy(b);sk_destroy(c);
  }free(l);free(r);free(shorter);
 }
 // Output automation must ramp rather than jump; wet Tone must damp recirculation.
 for(int kind=13;kind<=15;kind+=2){
  SKSynth*a=sk_create_effects(48000),*b=sk_create_effects(48000);float block[512];
  setup(a,0,kind,.8f,.8f,0,0);for(int i=0;i<512;i++)block[i]=.1f;sk_process_effects(a,block,512);
  sk_effect_parameter(a,0,0,kind==13?7:8,1);for(int i=0;i<512;i++)block[i]=.1f;sk_process_effects(a,block,512);
  assert(block[0]>0&&block[0]<.001f);for(int i=1;i<512;i++)assert(fabsf(block[i]-block[i-1])<.001f);
  sk_destroy(a);a=sk_create_effects(48000);setup(a,0,kind,.8f,.9f,0,1);setup(b,0,kind,.8f,.9f,0,1);
  sk_effect_parameter(a,0,0,4,1200);sk_effect_parameter(b,0,0,4,16000);
  double dark=0,bright=0;
  for(int n=0;n<48000*5;n+=512){float x[512],y[512];for(int i=0;i<512;i++)x[i]=y[i]=n+i<4800?.05f*sinf((n+i)*6.2831853f*4000/48000):0;sk_process_effects(a,x,512);sk_process_effects(b,y,512);if(n>48000){dark+=energy(x,0,512);bright+=energy(y,0,512);}}
  assert(dark<bright*.1);sk_destroy(a);sk_destroy(b);
 }
 // Three serial engines: chord excitation, finite bounded tail, no shared state.
 SKSynth*s=sk_create_effects(48000);setup(s,0,13,.4f,.7f,1,.3f);setup(s,1,15,.8f,.95f,.6f,.4f);setup(s,2,15,1,.95f,.7f,.3f);
 float block[256];clock_t start=clock();
 for(int b=0;b<1875;b++){for(int i=0;i<256;i++){int n=b*256+i;block[i]=n<48000?.08f*(sinf(n*.0343f)+sinf(n*.0432f)+sinf(n*.0514f)):0;}sk_process_effects(s,block,256);energy(block,0,256);}
 printf("Three serial dense engines / 10 seconds audio: %.3f seconds CPU\n",(double)(clock()-start)/CLOCKS_PER_SEC);sk_destroy(s);
 puts("PASS: dense acoustic/ambient predelay, decay contrast, stereo, dry identity, reconfiguration tails, stacking and Panic");
}
