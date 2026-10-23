#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static void run(float*out,float q,float dry,float wet,int n){
 SKSynth*s=sk_create_effects(48000);assert(s);sk_effect(s,0,0,15,1);
 sk_effect_parameter(s,0,0,8,dry);sk_effect_parameter(s,0,0,9,wet);sk_effect_parameter(s,0,0,10,q);
 for(int i=0;i<n;i++)out[i]=i<24000?.1f*sinf(i*6.2831853f*1700/48000):0;
 sk_process_effects(s,out,n);sk_panic(s);float silence[512]={0};sk_process_effects(s,silence,512);for(int i=0;i<512;i++)assert(silence[i]==0);sk_destroy(s);
}
int main(void){int n=144000;float*a=calloc(n,4),*b=calloc(n,4),*dry=calloc(n,4),*sum=calloc(n,4);
 run(a,1,0,1,n);run(b,0,0,1,n);run(dry,0,1,0,n);run(sum,0,1,1,n);
 double difference=0,energy=0;
 for(int i=0;i<n;i++){float input=i<24000?.1f*sinf(i*6.2831853f*1700/48000):0;assert(isfinite(a[i])&&isfinite(b[i]));assert(fabsf(dry[i]-input)<1e-7);assert(fabsf(sum[i]-input-b[i])<1e-6);difference+=fabs(a[i]-b[i]);energy+=b[i]*b[i];}
 assert(difference>1&&energy>1e-7);free(a);free(b);free(dry);free(sum);puts("PASS SolaVerb quality: stepped wet clock changes sound, dry identity, independent mix, finite tail and panic");}
