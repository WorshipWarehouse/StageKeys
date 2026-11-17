#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static double energy(const float *x,int begin,int end){
 double total=0;for(int i=begin;i<end;i++){assert(isfinite(x[i]));assert(fabsf(x[i])<4);total+=(double)x[i]*x[i];}return total;
}
static void render(float *output,int count,int rate,int selector){
 SKSynth*s=sk_create_effects(rate);assert(s);sk_effect(s,0,0,13,1);
 float p[]={.72f,18,.62f,90,11000,.32f,.55f,0,1,1,(float)selector};
 for(int i=0;i<11;i++)sk_effect_parameter(s,0,0,i,p[i]);
 output[0]=.1f;sk_process_effects(s,output,count);sk_destroy(s);
}
int main(void){
 const int rate=48000,count=rate*8;float*room=calloc(count,sizeof(float)),*hall=calloc(count,sizeof(float)),*ambient=calloc(count,sizeof(float));
 assert(room&&hall&&ambient);render(room,count,rate,3);render(hall,count,rate,4);render(ambient,count,rate,5);
 double roomLate=energy(room,rate*4,count),hallLate=energy(hall,rate*4,count),ambientLate=energy(ambient,rate*4,count);
 double roomHall=0,hallAmbient=0;for(int i=0;i<count;i++){double a=room[i]-hall[i],b=hall[i]-ambient[i];roomHall+=a*a;hallAmbient+=b*b;}
 assert(energy(room,0,count)>1e-8&&energy(hall,0,count)>1e-8&&energy(ambient,0,count)>1e-8);
 assert(roomHall>1e-8&&hallAmbient>1e-8);
 assert(roomLate<hallLate&&hallLate<ambientLate);
 printf("PASS: Stage Reverb Room/Hall/Ambient are finite, distinct, and ordered by late energy (%g < %g < %g)\n",roomLate,hallLate,ambientLate);
 free(room);free(hall);free(ambient);
}
