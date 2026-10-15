#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdlib.h>
#include <stdio.h>
static void impulse(float*out,int n,int kind,float ms,float dry){
 SKSynth*s=sk_create_effects(48000);assert(s);sk_effect(s,0,0,kind,1);
 sk_effect_parameter(s,0,0,kind==13?1:0,ms);
 sk_effect_parameter(s,0,0,kind==13?5:6,0); // no time-varying modulation
 if(kind==15)sk_effect_parameter(s,0,0,5,0);
 sk_effect_parameter(s,0,0,kind==13?7:8,dry);
 sk_effect_parameter(s,0,0,kind==13?8:9,1);
 out[0]=.1f;sk_process_effects(s,out,n);
 sk_panic(s);float silence[512]={0};sk_process_effects(s,silence,512);for(int i=0;i<512;i++)assert(silence[i]==0);
 sk_destroy(s);
}
int main(void){int n=24000,offset=864;for(int kind=13;kind<=15;kind+=2){
 float*a=calloc(n,sizeof(float)),*b=calloc(n,sizeof(float)),*c=calloc(n,sizeof(float));impulse(a,n,kind,0,0);impulse(b,n,kind,18,0);impulse(c,n,kind,18,1);
 double energy=0,error=0;for(int i=0;i<n;i++){float expected=i>=offset?a[i-offset]:0;energy+=expected*expected;error+=(b[i]-expected)*(b[i]-expected);if(i<offset)assert(b[i]==0);}
 assert(energy>1e-6&&error/energy<1e-8);assert(fabs(c[0]-.1f)<1e-6);for(int i=1;i<n;i++)assert(fabs(c[i]-b[i])<1e-7);
 free(a);free(b);free(c);printf("PASS reverb %d: wet delayed exactly 18ms, dry unshifted, panic clears both buffers\n",kind);
}return 0;}
