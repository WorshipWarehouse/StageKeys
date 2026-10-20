#ifndef STAGEKEYS_SHIMMER_PITCH_H
#define STAGEKEYS_SHIMMER_PITCH_H
#include <math.h>
#include <stdlib.h>
#include <string.h>
// Fixed-size, wet-only octave phase vocoder. Storage and tables are prepared
// on the control thread. No allocation, locks or system calls in process().
#define SK_PITCH_N 2048
#define SK_PITCH_PI 3.14159265358979323846
struct SKShimmerPitch {
 float input[SK_PITCH_N],output[SK_PITCH_N],window[SK_PITCH_N];
 float re[SK_PITCH_N],im[SK_PITCH_N],twRe[SK_PITCH_N/2],twIm[SK_PITCH_N/2];
 double previous[SK_PITCH_N/2+1],phase[SK_PITCH_N/2+1];
 int cursor,hop,n;
};
typedef struct SKShimmerPitch SKShimmerPitch;
static void sk_pitch_reset(SKShimmerPitch*p){
 if(!p)return;memset(p->input,0,sizeof(p->input));memset(p->output,0,sizeof(p->output));
 memset(p->previous,0,sizeof(p->previous));memset(p->phase,0,sizeof(p->phase));p->cursor=p->hop=0;
}
static SKShimmerPitch*sk_pitch_create(void){
 SKShimmerPitch*p=calloc(1,sizeof(*p));if(!p)return NULL;p->n=SK_PITCH_N;
 for(int i=0;i<SK_PITCH_N;i++)p->window[i]=.5-.5*cos(2*SK_PITCH_PI*i/SK_PITCH_N);
 for(int i=0;i<SK_PITCH_N/2;i++){p->twRe[i]=cos(2*SK_PITCH_PI*i/SK_PITCH_N);p->twIm[i]=-sin(2*SK_PITCH_PI*i/SK_PITCH_N);}return p;
}
static void sk_pitch_fft(SKShimmerPitch*p,int inverse){
 for(int i=1,j=0;i<p->n;i++){int bit=p->n>>1;for(;j&bit;bit>>=1)j^=bit;j^=bit;if(i<j){float a=p->re[i],b=p->im[i];p->re[i]=p->re[j];p->im[i]=p->im[j];p->re[j]=a;p->im[j]=b;}}
 for(int size=2;size<=p->n;size<<=1)for(int at=0;at<p->n;at+=size)for(int j=0;j<size/2;j++){
  int k=j*SK_PITCH_N/size,b=at+j+size/2,a=at+j;float wr=p->twRe[k],wi=inverse?-p->twIm[k]:p->twIm[k];
  float r=wr*p->re[b]-wi*p->im[b],i=wr*p->im[b]+wi*p->re[b];p->re[b]=p->re[a]-r;p->im[b]=p->im[a]-i;p->re[a]+=r;p->im[a]+=i;
 }
 if(inverse)for(int i=0;i<p->n;i++){p->re[i]/=p->n;p->im[i]/=p->n;}
}
static float sk_pitch_process(SKShimmerPitch*p,float x,int divider){
 if(!p)return 0;if(divider<1)divider=1;int n=SK_PITCH_N/divider;if(n<128)n=128;
 if(p->n!=n){sk_pitch_reset(p);p->n=n;}
 int hop=n/8,stride=SK_PITCH_N/n,cursor=p->cursor;float result=p->output[cursor];p->output[cursor]=0;p->input[cursor]=x;
 p->cursor=(cursor+1)%n;if(++p->hop<hop)return result;p->hop=0;
 for(int i=0;i<n;i++){p->re[i]=p->input[(p->cursor+i)%n]*p->window[i*stride];p->im[i]=0;}
 sk_pitch_fft(p,0);
 // Move bins downward in memory order so each source bin is consumed before
 // an octave-up destination overwrites it. Track the true frequency between
 // frames rather than periodically resetting a short delay grain.
 for(int i=n/2;i>=0;i--){
  double angle=atan2(p->im[i],p->re[i]),expected=2*SK_PITCH_PI*i*hop/n;
  double deviation=remainder(angle-p->previous[i]-expected,2*SK_PITCH_PI);p->previous[i]=angle;
  float magnitude=hypotf(p->re[i],p->im[i]);p->re[i]=p->im[i]=0;
  if(i<=n/4){int destination=i*2;p->phase[destination]=remainder(p->phase[destination]+2*(expected+deviation),2*SK_PITCH_PI);p->re[destination]=magnitude*cos(p->phase[destination]);p->im[destination]=magnitude*sin(p->phase[destination]);}
 }
 p->im[0]=p->im[n/2]=0;
 for(int i=1;i<n/2;i++){p->re[n-i]=p->re[i];p->im[n-i]=-p->im[i];}
 sk_pitch_fft(p,1);
 for(int i=0;i<n;i++)p->output[(p->cursor+i)%n]+=p->re[i]*p->window[i*stride]/3;
 return result;
}
#endif
