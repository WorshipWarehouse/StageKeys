#include "../Sources/CreamCoat.h"
#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
// Golden measurements generated with the pinned upstream double processor,
// using float inputs/outputs and deterministic seeds from the adaptation.
static void upstream_golden(float predelay,int onset,double energyL,double energyR){
 SKCreamCoat*s=sk_cream_create(48000);assert(s);sk_cream_configure(s,0,.33f,1,predelay);
 double el=0,er=0;int first=-1;
 for(int n=0;n<48000;n++){float l=n==0?.1f:0,r=l;sk_cream_frame(s,&l,&r);assert(isfinite(l)&&isfinite(r));if(first<0&&(fabsf(l)>1e-6f||fabsf(r)>1e-6f))first=n;el+=(double)l*l;er+=(double)r*r;}
 assert(first==onset&&fabs(el-energyL)<1e-9&&fabs(er-energyR)<1e-9);
 sk_cream_reset(s);sk_cream_configure(s,0,.33f,1,predelay);float a=.1f,b=a;sk_cream_frame(s,&a,&b);assert(fabs(a)<1e-6&&fabs(b)<1e-6);sk_cream_destroy(s);
}
static void setup(SKSynth*s,float dry,float wet){
 sk_effect(s,0,0,13,1);float p[]={0,18,.33f,776,2884,0,0,dry,wet,1,1};for(int i=0;i<11;i++)sk_effect_parameter(s,0,0,i,p[i]);
}
int main(void){
 upstream_golden(0,517,.000755401658619,.000730494898449);
 upstream_golden(.09f,3215,.00253216444507,.00243210267639);
 // Host wiring: stereo core, independent dry signal, and reset/bypass lifecycle.
 const int n=48000;float*l=calloc(n,sizeof(float)),*r=calloc(n,sizeof(float));
 SKSynth*a=sk_create_effects(48000),*b=sk_create_effects(48000);assert(a&&b);setup(a,0,1);setup(b,0,1);l[0]=r[0]=.1f;
 sk_process_effects_stereo(a,b,l,r,n);double el=0,er=0,diff=0;int first=-1;
 for(int i=0;i<n;i++){assert(isfinite(l[i])&&isfinite(r[i]));el+=l[i]*l[i];er+=r[i]*r[i];diff+=(l[i]-r[i])*(l[i]-r[i]);if(first<0&&(fabs(l[i])>1e-6||fabs(r[i])>1e-6))first=i;}
 assert(first==3215&&el>1e-5&&er>1e-5&&diff>el*.1);
 sk_panic(a);sk_panic(b);for(int i=0;i<n;i++)l[i]=r[i]=0;sk_process_effects_stereo(a,b,l,r,n);for(int i=0;i<n;i++)assert(fabs(l[i])<1e-6&&fabs(r[i])<1e-6);
 setup(a,1,0);setup(b,1,0);for(int i=0;i<n;i++){l[i]=.07f*sinf(i*.1f);r[i]=.04f*cosf(i*.2f);}sk_process_effects_stereo(a,b,l,r,n);for(int i=0;i<n;i++){assert(l[i]==.07f*sinf(i*.1f));assert(r[i]==.04f*cosf(i*.2f));}
 sk_effect(a,0,0,0,0);sk_effect(b,0,0,0,0);sk_process_effects_stereo(a,b,l,r,128);setup(a,0,1);setup(b,0,1);for(int i=0;i<n;i++)l[i]=r[i]=0;sk_process_effects_stereo(a,b,l,r,n);for(int i=0;i<n;i++)assert(fabs(l[i])<1e-6&&fabs(r[i])<1e-6);
 sk_destroy(a);sk_destroy(b);free(l);free(r);puts("PASS: upstream impulse goldens, normalized predelay onset, live stereo wiring, dry identity, panic and bypass reset");
}
