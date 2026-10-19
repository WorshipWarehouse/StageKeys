#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
static void render(float *out,int n,int rate,float pre,float dry,float size,float reflect,float density){
 SKSynth*s=sk_create_effects(rate);assert(s);sk_effect(s,0,0,16,1);
 float p[]={pre,reflect,size,density,760,6800,0,0,0,dry,1};
 for(int i=0;i<11;i++)sk_effect_parameter(s,0,0,i,p[i]);
 out[0]=.1f;sk_process_effects(s,out,n);
 sk_panic(s);float silence[1024]={0};sk_process_effects(s,silence,1024);
 for(int i=0;i<1024;i++)assert(silence[i]==0);
 sk_destroy(s);
}
int main(void){for(int rate=44100;rate<=96000;rate=rate==44100?48000:rate*2){
 int n=rate*12,shift=rate/100;float*a=calloc(n,sizeof(float)),*b=calloc(n,sizeof(float)),*c=calloc(n,sizeof(float));
 render(a,n,rate,0,0,160,.71,.81);render(b,n,rate,10,0,160,.71,.81);render(c,n,rate,10,1,160,.71,.81);
 double energy=0,error=0,early=0,late=0;
 for(int i=0;i<n;i++){
  assert(isfinite(a[i])&&isfinite(b[i])&&fabsf(a[i])<1);
  float expected=i>=shift?a[i-shift]:0;energy+=expected*expected;error+=(b[i]-expected)*(b[i]-expected);
  if(i<shift)assert(b[i]==0);
  if(i>0)assert(fabsf(c[i]-b[i])<1e-7);
  if(i<rate/20)early+=a[i]*a[i];if(i>rate*9)late+=a[i]*a[i];
 }
 assert(early>1e-9&&energy>1e-7&&error/energy<1e-7&&late<energy*.001);
 assert(fabsf(c[0]-.1f)<1e-6);
 free(a);free(b);free(c);
 // Small/large rooms, minimum/maximum reflectivity and density must remain finite.
 for(int j=0;j<8;j++){
  float*out=calloc(n,sizeof(float));render(out,n,rate,100,0,j&1?200:0,j&2?1:0,j&4?1:0);
  for(int i=0;i<n;i++)assert(isfinite(out[i])&&fabsf(out[i])<1);free(out);
 }
 printf("PASS Silver reflections %d Hz: early energy, predelay, dry identity, bounded tails and panic\n",rate);
}return 0;}
