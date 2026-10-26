#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
static void setup(SKSynth*s,float dry,float wet,float quality){
 sk_effect(s,0,0,10,1);float p[]={.7f,.7f,.8f,.7f,.4f,80,10000,dry,wet,quality};
 for(int i=0;i<10;i++)sk_effect_parameter(s,0,0,i,p[i]);
}
int main(void){
 const int rates[]={44100,48000,96000};
 for(int r=0;r<3;r++)for(int quality=0;quality<2;quality++){
  int rate=rates[r],position=0;float q=quality?1:.25f;
  SKSynth*a=sk_create_effects(rate),*b=sk_create_effects(rate),*c=sk_create_effects(rate);
  setup(a,1,0,q);setup(b,1,0,q);setup(c,0,1,q);
  float x[256],y[256],z[256];
  for(int block=0;block<600;block++){
   for(int i=0;i<256;i++,position++)x[i]=y[i]=z[i]=.1f+.03f*sinf(position*6.2831853f*220/rate);
   sk_process_effects(a,x,256);sk_process_effects(b,y,256);sk_process_effects(c,z,256);
  }
  sk_effect_parameter(a,0,0,7,0);sk_effect_parameter(a,0,0,8,1);
  float first=0,target=0,last=0;
  for(int block=0;block<100;block++){
   for(int i=0;i<256;i++,position++)x[i]=y[i]=z[i]=.1f+.03f*sinf(position*6.2831853f*220/rate);
   sk_process_effects(a,x,256);sk_process_effects(b,y,256);sk_process_effects(c,z,256);
   if(!block){first=fabsf(x[0]-y[0]);target=fabsf(z[0]-y[0]);}
   for(int i=0;i<256;i++){assert(isfinite(x[i]));last=fabsf(x[i]-z[i]);}
  }
  assert(target>.001f&&first/target<.01f);assert(last<.0001f);
  printf("PASS Shimmer mix slew %dHz quality%g first/target=%g settled=%g\n",rate,q,first/target,last);
  sk_destroy(a);sk_destroy(b);sk_destroy(c);
 }
}
