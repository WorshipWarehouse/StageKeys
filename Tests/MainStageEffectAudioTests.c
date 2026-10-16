#include "Synth.h"
#include <assert.h>
#include <math.h>
#include <stdlib.h>
#include <stdio.h>
static void silver(SKSynth*s,float pre,float density){sk_effect(s,0,0,16,1);sk_effect_parameter(s,0,0,0,pre);sk_effect_parameter(s,0,0,3,density);sk_effect_parameter(s,0,0,7,0);sk_effect_parameter(s,0,0,9,0);sk_effect_parameter(s,0,0,10,1);}
int main(void){
 int n=144000,shift=2400;float*a=calloc(n,sizeof(float)),*b=calloc(n,sizeof(float)),*r=calloc(n,sizeof(float));
 SKSynth*x=sk_create_effects(48000),*y=sk_create_effects(48000);silver(x,0,1);silver(y,50,1);a[0]=b[0]=1;
 sk_process_effects(x,a,n);sk_process_effects(y,b,n);
 double error=0,energy=0;for(int i=shift;i<n;i++){assert(isfinite(a[i])&&isfinite(b[i]));error+=fabs(a[i-shift]-b[i]);energy+=fabs(a[i-shift]);}assert(energy>0.01 && error<energy*.00001);
 sk_panic(x);sk_panic(y);silver(x,0,0);silver(y,0,1);for(int i=0;i<n;i++)a[i]=b[i]=0;a[0]=b[0]=1;sk_process_effects(x,a,n);sk_process_effects(y,b,n);
 double shortTail=0,longTail=0;for(int i=48000;i<n;i++){shortTail+=a[i]*a[i];longTail+=b[i]*b[i];}assert(longTail>shortTail*3);
 // Reverb must preserve proportional transients instead of soft-clipping its tank.
 sk_panic(x);sk_panic(y);silver(x,0,.8f);silver(y,0,.8f);
 for(int i=0;i<n;i++)a[i]=b[i]=0;a[0]=.25f;b[0]=1;
 sk_process_effects(x,a,n);sk_process_effects(y,b,n);double proportional=0;
 for(int i=0;i<n;i++)proportional+=fabs(b[i]-4*a[i]);assert(proportional<.0001);
 sk_panic(x);sk_panic(y);sk_effect(x,0,0,17,1);sk_effect(y,0,0,17,1);sk_effect_parameter(x,0,0,2,0);sk_effect_parameter(y,0,0,2,75);for(int i=0;i<n;i++)a[i]=b[i]=.1f*sinf(i*2*3.14159265f*220/48000);sk_process_effects(x,a,n);sk_process_effects(y,b,n);
 double difference=0;for(int i=0;i<n;i++){assert(isfinite(a[i])&&isfinite(b[i]));difference+=fabs(a[i]-b[i]);}assert(difference>1);
 // Input gain must also affect the dry branch before sum filtering.
 sk_panic(x);sk_panic(y);sk_effect_parameter(x,0,0,3,0);sk_effect_parameter(y,0,0,3,0);
 sk_effect_parameter(x,0,0,8,0);sk_effect_parameter(y,0,0,8,-6);
 for(int i=0;i<n;i++)a[i]=b[i]=.1f*sinf(i*2*3.14159265f*220/48000);
 sk_process_effects(x,a,n);sk_process_effects(y,b,n);
 double gainError=0;for(int i=0;i<n;i++)gainError+=fabs(b[i]-a[i]*powf(10,-6.0f/20));assert(gainError<.01);
 sk_panic(x);sk_panic(y);for(int i=0;i<n;i++)a[i]=b[i]=0;sk_process_effects_stereo(x,y,a,b,n);for(int i=0;i<n;i++)assert(a[i]==0&&b[i]==0);
 sk_destroy(x);sk_destroy(y);free(a);free(b);free(r);puts("PASS: Silver native predelay alignment/density tail, Clip symmetry response, finite output and panic silence");
}
