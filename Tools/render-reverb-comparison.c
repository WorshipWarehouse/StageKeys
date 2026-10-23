// Standalone original test excitation; generated audio contains no library samples.
#include "../Sources/Synth.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static float voice(int type,int n,int note){
 float time=n/48000.f,hz=440*powf(2,(note-69)/12.f),phase=6.283185307f*hz*time,out=0;
 if(type==0){for(int h=1;h<=8;h++)out+=sinf(phase*h*(1+h*.00008f))*expf(-time*(1+h*.12f))/h;}
 if(type==1){for(int h=1;h<=6;h++)out+=sinf(phase*h)/(h%2?1.7f:4);out*=fminf(1,time*100);}
 if(type==2){out=(sinf(phase)+sinf(phase*1.002f))*.5f*(1-expf(-time*2));}
 if(type==3){for(int h=1;h<=12;h++)out+=sinf(phase*h)/h;out*=expf(-time*2);}
 if(type==4)return voice(0,n,note)*.6f+voice(2,n,note)*.4f;
 return out*.035f;
}
int main(int argc,char**argv){
 if(argc!=2)return 1;const int rate=48000,n=rate*12;const char*names[]={"piano","organ","pad","synth","layered"};
 for(int type=0;type<5;type++)for(int kind=13;kind<=15;kind+=2)for(int dense=0;dense<=1;dense++){
  SKSynth*l=sk_create_effects(rate),*r=sk_create_effects(rate);float*a=calloc(n,4),*b=calloc(n,4);
  float acoustic[]={.8f,23,.7f,100,7000,.1f,.4f,.7f,.4f,1,dense?2:1};
  float ambient[]={23,.8f,.8f,100,7000,.6f,.2f,.4f,.4f,.6f,1,dense};
  for(int side=0;side<2;side++){SKSynth*s=side?r:l;sk_effect(s,0,0,kind,1);for(int j=0;j<(kind==13?11:12);j++)sk_effect_parameter(s,0,0,j,kind==13?acoustic[j]:ambient[j]);}
  for(int i=0;i<rate*8;i++){
   int onset=(i/(rate*2))*rate*2,root=i<rate*4?48:53;float env=i% (rate*2)>rate*1.7f?fmaxf(0,1-(i%(rate*2)-rate*1.7f)/(rate*.3f)):1;
   a[i]=(voice(type,i-onset,root)+voice(type,i-onset,root+4)+voice(type,i-onset,root+7))*env;b[i]=a[i];
  }
  clock_t start=clock();sk_process_effects_stereo(l,r,a,b,n);double cpu=(double)(clock()-start)/CLOCKS_PER_SEC,peak=0,energy=0;
  char path[2048];snprintf(path,sizeof(path),"%s/%s-%s-%s.f32",argv[1],names[type],kind==13?"acoustic":"ambient",dense?"dense":"legacy");FILE*f=fopen(path,"wb");if(!f)return 2;
  for(int i=0;i<n;i++){if(!isfinite(a[i])||!isfinite(b[i]))return 3;peak=fmax(peak,fmax(fabs(a[i]),fabs(b[i])));energy+=a[i]*a[i]+b[i]*b[i];fwrite(a+i,4,1,f);fwrite(b+i,4,1,f);}fclose(f);
  printf("%s,%d,%d,%.6f,%.6f,%.6f\n",names[type],kind,dense,cpu,peak,sqrt(energy/(n*2)));
  sk_destroy(l);sk_destroy(r);free(a);free(b);
 }
}
