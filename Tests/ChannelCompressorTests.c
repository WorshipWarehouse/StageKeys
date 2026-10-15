#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
static double energy(int enabled,float input,float mix,float ratio){
 SKSynth*s=sk_create(48000);sk_gain(s,0,0.1f,0);sk_compressor(s,0,enabled,-40,ratio,.02f,.2f,0);sk_compressor_blend(s,0,input,mix);sk_note_on(s,60,60,0,0,.8f);
 float l[512],r[512];double e=0;for(int b=0;b<100;b++){sk_render(s,l,r,512);if(b>10)for(int i=0;i<512;i++){assert(isfinite(l[i]));e+=l[i]*l[i];}}sk_destroy(s);return e;
}
int main(void){double dry=energy(0,0,1,1),bypass=energy(1,12,0,10),loud=energy(1,12,1,1),mixed=energy(1,12,.5f,1),compressed=energy(1,0,1,10);assert(fabs(bypass/dry-1)<.001);assert(loud>dry*15 && mixed>dry*5 && mixed<loud);assert(compressed<dry*.6);printf("PASS: channel compressor input gain, ratio, blend and bypass affect rendered audio\n");}
