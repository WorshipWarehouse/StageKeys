#include "../Sources/ShimmerPitch.h"
#include <assert.h>
#include <stdio.h>
static double power(const float*x,int start,int n,double rate,double hz){double re=0,im=0;for(int i=0;i<n;i++){double w=.5-.5*cos(2*SK_PITCH_PI*i/(n-1));re+=w*x[start+i]*cos(2*SK_PITCH_PI*hz*i/rate);im+=w*x[start+i]*sin(2*SK_PITCH_PI*hz*i/rate);}return re*re+im*im;}
int main(void){double rates[]={44100,48000,96000},notes[]={220,261.625565,329.627557};
 for(int r=0;r<3;r++){
  double rate=rates[r];int n=(int)(rate*3);float*out=calloc(n,sizeof(float));SKShimmerPitch*p=sk_pitch_create();assert(out&&p);
  for(int i=0;i<n;i++){float x=0;for(int k=0;k<3;k++)x+=.03*sin(2*SK_PITCH_PI*notes[k]*i/rate);out[i]=sk_pitch_process(p,x,1);assert(isfinite(out[i])&&fabs(out[i])<.5);}
  for(int k=0;k<3;k++){
   double target=notes[k]*2,best=0,frequency=0;for(int step=-24;step<=24;step++){double hz=target+step*.25,e=power(out,(int)rate,(int)rate,rate,hz);if(e>best){best=e;frequency=hz;}}
   assert(fabs(frequency-target)<=.5);assert(best>1&&best>power(out,(int)rate,(int)rate,rate,notes[k])*100);
   printf("PASS shimmer octave %.0f Hz: %.3f -> %.3f Hz\n",rate,notes[k],frequency);
  }
  sk_pitch_reset(p);for(int i=0;i<SK_PITCH_N*3;i++)assert(sk_pitch_process(p,0,1)==0);
  free(p);free(out);
 }
 puts("PASS: chord octave tuning within 0.5 Hz at three rates; bounded output and clean reset");
}
