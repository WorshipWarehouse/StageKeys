#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#define N 24000
static void setup(SKSynth*s,float quality,float dry,float wet){sk_effect(s,0,0,13,1);float p[]={0,18,.33f,776,2884,0,0,dry,wet,quality};for(int i=0;i<10;i++)sk_effect_parameter(s,0,0,i,p[i]);}
int main(void){float*l=calloc(N,sizeof(float)),*r=calloc(N,sizeof(float)),*low=calloc(N,sizeof(float));SKSynth*a=sk_create_effects(48000),*b=sk_create_effects(48000),*c=sk_create_effects(48000);setup(a,1,0,1);setup(b,1,0,1);setup(c,0,0,1);l[0]=r[0]=low[0]=.1f;sk_process_effects_stereo(a,b,l,r,N);sk_process_effects(c,low,N);double el=0,er=0,diff=0,quality=0;for(int i=0;i<N;i++){assert(isfinite(l[i])&&isfinite(r[i]));el+=l[i]*l[i];er+=r[i]*r[i];diff+=(l[i]-r[i])*(l[i]-r[i]);quality+=(l[i]-low[i])*(l[i]-low[i]);if(i<864)assert(l[i]==0&&r[i]==0);}assert(el>1e-6&&er>1e-6&&diff>el*.1&&er/el>.2&&er/el<5&&quality>el*.1);sk_panic(a);sk_panic(b);for(int i=0;i<512;i++)l[i]=r[i]=0;sk_process_effects_stereo(a,b,l,r,512);for(int i=0;i<512;i++)assert(l[i]==0&&r[i]==0);setup(a,1,1,0);setup(b,1,1,0);for(int i=0;i<512;i++)l[i]=r[i]=(i==0?.1f:0);sk_process_effects_stereo(a,b,l,r,512);assert(l[0]==.1f&&r[0]==.1f);for(int i=1;i<512;i++)assert(l[i]==0&&r[i]==0);sk_destroy(a);sk_destroy(b);sk_destroy(c);free(l);free(r);free(low);puts("PASS: PrimaVerb decorrelates mono wet tails, quality changes diffusion, dry stays unchanged, zero chorus rate is accepted, and panic clears stereo tails");}
