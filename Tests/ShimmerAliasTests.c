#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdlib.h>
#include <stdio.h>
static double energy(double rate,double hz){SKSynth*s=sk_create_effects(rate);assert(s);sk_effect(s,0,0,10,1);sk_effect_parameter(s,0,0,0,1);sk_effect_parameter(s,0,0,1,0);sk_effect_parameter(s,0,0,4,0);sk_effect_parameter(s,0,0,6,20000);sk_effect_parameter(s,0,0,7,0);sk_effect_parameter(s,0,0,8,1);int n=(int)(rate*2);float*a=calloc(n,sizeof(float));assert(a);for(int i=0;i<rate;i++)a[i]=.1f*sinf(6.283185307*hz*i/rate);sk_process_effects(s,a,n);double e=0;for(int i=(int)(rate*.3);i<n;i++){assert(isfinite(a[i]));e+=a[i]*a[i];}free(a);sk_destroy(s);return e;}
int main(void){double rates[]={44100,48000,96000};for(int i=0;i<3;i++){double sr=rates[i],low=energy(sr,sr*.02),high=energy(sr,sr*.3);assert(low>1e-6&&high/low<.1);printf("PASS shimmer antialias %.0f Hz: high/low wet energy %.6f\n",sr,high/low);}return 0;}
