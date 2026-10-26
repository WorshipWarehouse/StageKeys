#include "Synth.h"
#include "CreamCoat.h"
#include "ShimmerPitch.h"
#include <math.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <string.h>
#define VOICES 192
#define BUSES 16
#define DELAY 96000
#define QUEUE 2048
#define TAU 6.283185307179586
// All state below, except the command queue and emergency flag, belongs to the audio thread.
typedef struct { int kind,key,pitch,instrument,layer; float value,seconds,a,b,d; } Command;
typedef struct { int active,key,instrument,layer,releasing,held; double phase,phase2,step,age; float env,velocity; } Voice;
typedef struct { float b0,b1,b2,a1,a2,z1,z2; } Biquad;
// Independent StageKeys dense reverb network; no third-party DSP in this state.
// DenseReverb/dense_prepare/dense_process: MIT, see Licenses/StageKeys-Dense-Reverb-MIT.txt.
typedef struct {
 float low[8],dc[8],offset[8],feedback[8],cache[12],mix[2],damping[2],crossInput;
 double oscSin[8],oscCos[8],stepSin[8],stepCos[8];
 int ready;
} DenseReverb;
typedef struct { DenseReverb reverb; float p[32],z[12],coef[8],shiftPhase,stereo; int custom; Biquad eq[8];float clipControl[3];int clipReady; } EffectState;
struct SKSynth {
 double rate;
 int delayLength,predelayLength;
 Voice voices[VOICES];
 Command queue[QUEUE];
 _Atomic unsigned read,write;
 _Atomic int emergency;
 int sustain;
 float adsr[BUSES][4],preGain[BUSES],cutoff[BUSES];
 int customEnvelope[BUSES],voiceLimit[BUSES],compressEnabled[BUSES];
 Biquad filter[BUSES],eq[BUSES][8];
 float compressorInput[BUSES],compressorWet[BUSES];
 float threshold[BUSES],ratio[BUSES],compAttack[BUSES],compRelease[BUSES],makeup[BUSES],detector[BUSES];
 float gain[BUSES],target[BUSES],delta[BUSES],pan[BUSES];
 unsigned remaining[BUSES];
 int blockSustain[BUSES],fxKind[BUSES][3],delayPosition[BUSES][3];
 float fxAmount[BUSES][3],fxCurrent[BUSES][3],tone[BUSES][3];
 float *delay[BUSES][3],*predelay[BUSES][3];
 int predelayPosition[BUSES][3];
 _Atomic(SKCreamCoat*) cream[BUSES][3];
 _Atomic(SKShimmerPitch*) shimmer[BUSES][3];
 double fxPhase[BUSES][3],clockRemaining,clockPhase;
 float clockTempo,clockEnvelope;
 int stereoSide;
 int clockEnabled;
 EffectState effect[BUSES][3];
};
static SKSynth *create_engine(double rate,int buses,double seconds) {
 SKSynth *s=calloc(1,sizeof(*s)); if(!s) return NULL;
 for(int l=0;l<BUSES;l++)for(int k=0;k<3;k++){atomic_init(&s->cream[l][k],NULL);atomic_init(&s->shimmer[l][k],NULL);}
 s->delayLength=(int)fmax(DELAY,fmin(16,seconds)*rate);
 s->predelayLength=(int)ceil(rate*.2)+2;
 atomic_init(&s->read,0);atomic_init(&s->write,0);atomic_init(&s->emergency,0);
 for(int l=0;l<buses;l++)for(int k=0;k<3;k++){s->delay[l][k]=calloc(s->delayLength,sizeof(float));s->predelay[l][k]=calloc(s->predelayLength,sizeof(float));if(!s->delay[l][k]||!s->predelay[l][k]){sk_destroy(s);return NULL;}}
 s->rate=rate;s->clockTempo=72; for(int i=0;i<BUSES;i++){s->gain[i]=s->target[i]=0.5f;s->preGain[i]=1;s->compressorInput[i]=1;s->compressorWet[i]=1;s->voiceLimit[i]=64;s->cutoff[i]=20000;s->filter[i].b0=1;for(int k=0;k<8;k++)s->eq[i][k].b0=1;} return s;
}
SKSynth *sk_create(double rate){return create_engine(rate,BUSES,2);}
SKSynth *sk_create_effects(double rate){return create_engine(rate,1,2);}
SKSynth *sk_create_effects_with_capacity(double rate,double seconds){return create_engine(rate,1,seconds);}
void sk_destroy(SKSynth *s){if(!s)return;for(int l=0;l<BUSES;l++)for(int k=0;k<3;k++){sk_cream_destroy(atomic_load(&s->cream[l][k]));free(atomic_load(&s->shimmer[l][k]));free(s->delay[l][k]);free(s->predelay[l][k]);}free(s);}
static void clear_delay(SKSynth*s,int l,int k){SKCreamCoat*c=atomic_load_explicit(&s->cream[l][k],memory_order_acquire);if(c)sk_cream_reset(c);sk_pitch_reset(atomic_load_explicit(&s->shimmer[l][k],memory_order_acquire));if(s->predelay[l][k])memset(s->predelay[l][k],0,s->predelayLength*sizeof(float));s->predelayPosition[l][k]=0;if(s->delay[l][k])memset(s->delay[l][k],0,s->delayLength*sizeof(float));}
static void enqueue(SKSynth *s,Command c) {
 unsigned w=atomic_load_explicit(&s->write,memory_order_relaxed);
 unsigned next=(w+1)%QUEUE;
 if(next==atomic_load_explicit(&s->read,memory_order_acquire)) { atomic_store(&s->emergency,1); return; }
 s->queue[w]=c; atomic_store_explicit(&s->write,next,memory_order_release);
}
void sk_note_on(SKSynth *s,int key,int pitch,int instrument,int layer,float velocity){
 if(pitch<0||pitch>127||layer<0||layer>=BUSES||instrument<0||instrument>2)return;
 enqueue(s,(Command){.kind=1,.key=key,.pitch=pitch,.instrument=instrument,.layer=layer,.value=fminf(1,fmaxf(0,velocity))});
}
void sk_note_off_channel(SKSynth *s,int key,int layer,int forceRelease){if(layer>=0&&layer<BUSES)enqueue(s,(Command){.kind=16,.key=key,.layer=layer,.instrument=forceRelease});}
void sk_note_off(SKSynth *s,int key){enqueue(s,(Command){.kind=2,.key=key});}
void sk_gain(SKSynth *s,int layer,float gain,float seconds){if(layer>=0&&layer<BUSES)enqueue(s,(Command){.kind=3,.layer=layer,.value=fminf(4,fmaxf(0,gain)),.seconds=fminf(30,fmaxf(0,seconds))});}
void sk_effect(SKSynth *s,int layer,int slot,int kind,float amount){
 if(layer<0||layer>=BUSES||slot<0||slot>=3||kind<0||kind>17)return;
 // Allocate on the control thread, publish once, and retain through bypass/panic.
 if(kind==13&&!atomic_load_explicit(&s->cream[layer][slot],memory_order_acquire)){
  SKCreamCoat*c=sk_cream_create(s->rate),*expected=NULL;
  if(c&&!atomic_compare_exchange_strong(&s->cream[layer][slot],&expected,c))sk_cream_destroy(c);
 }
 if(kind==10&&!atomic_load_explicit(&s->shimmer[layer][slot],memory_order_acquire)){
  SKShimmerPitch*p=sk_pitch_create(),*expected=NULL;
  if(p&&!atomic_compare_exchange_strong(&s->shimmer[layer][slot],&expected,p))free(p);
 }
 enqueue(s,(Command){.kind=5,.layer=layer,.key=slot,.instrument=kind,.value=fminf(1,fmaxf(0,amount))});
}
void sk_pan(SKSynth *s,int layer,float pan){if(layer>=0&&layer<BUSES)enqueue(s,(Command){.kind=6,.layer=layer,.value=fminf(1,fmaxf(-1,pan))});}
void sk_block_sustain(SKSynth *s,int layer,int enabled){if(layer>=0&&layer<BUSES)enqueue(s,(Command){.kind=7,.layer=layer,.value=enabled?1:0});}
void sk_clock(SKSynth *s,float tempo,int enabled){enqueue(s,(Command){.kind=8,.value=fminf(300,fmaxf(20,tempo)),.key=enabled});}
void sk_sustain(SKSynth *s,int on){enqueue(s,(Command){.kind=4,.value=on?1:0});}
void sk_panic(SKSynth *s){enqueue(s,(Command){.kind=9});}
void sk_panic_channel(SKSynth *s,int layer){if(layer>=0&&layer<BUSES)enqueue(s,(Command){.kind=18,.layer=layer});}
void sk_release_voices(SKSynth*s,int layer){if(layer>=0&&layer<BUSES)enqueue(s,(Command){.kind=22,.layer=layer});}
static float bounded(float x,float lo,float hi){return isfinite(x)?fminf(hi,fmaxf(lo,x)):lo;}
void sk_envelope(SKSynth*s,int l,float a,float d,float u,float r){if(l>=0&&l<BUSES)enqueue(s,(Command){.kind=10,.layer=l,.value=bounded(a,.001,30),.seconds=bounded(d,.001,30),.a=bounded(u,0,1),.b=bounded(r,.001,30)});}
void sk_voice_limit(SKSynth*s,int l,int n){if(l>=0&&l<BUSES)enqueue(s,(Command){.kind=11,.layer=l,.key=n<1?1:n>64?64:n});}
void sk_sampler_gain(SKSynth*s,int l,float g){if(l>=0&&l<BUSES)enqueue(s,(Command){.kind=12,.layer=l,.value=bounded(g,0,4)});}
void sk_filter(SKSynth*s,int l,float f,float q){if(l>=0&&l<BUSES)enqueue(s,(Command){.kind=13,.layer=l,.value=bounded(f,20,20000),.a=bounded(q,.1,10)});}
void sk_eq(SKSynth*s,int l,int band,float f,float db,float q){if(l>=0&&l<BUSES&&band>=0&&band<8)enqueue(s,(Command){.kind=14,.layer=l,.key=band,.value=bounded(f,20,20000),.a=bounded(db,-24,24),.b=bounded(q,.1,10)});}
void sk_compressor(SKSynth*s,int l,int on,float db,float ratio,float a,float r,float makeup){if(l>=0&&l<BUSES)enqueue(s,(Command){.kind=15,.layer=l,.key=on!=0,.value=bounded(db,-60,0),.seconds=bounded(ratio,1,20),.a=bounded(a,.0001,1),.b=bounded(r,.001,5),.d=bounded(makeup,-24,24)});}
void sk_compressor_blend(SKSynth*s,int l,float input,float wet){if(l>=0&&l<BUSES)enqueue(s,(Command){.kind=20,.layer=l,.value=bounded(input,-24,24),.a=bounded(wet,0,1)});}

static void coefficients(Biquad*b,double rate,float f,float q,float db,int peak){
 double w=TAU*fmin(f,rate*.45)/rate,cs=cos(w),sn=sin(w),alpha=sn/(2*q),A=pow(10,db/40),a0;
 if(peak){a0=1+alpha/A;b->b0=(1+alpha*A)/a0;b->b1=-2*cs/a0;b->b2=(1-alpha*A)/a0;b->a1=-2*cs/a0;b->a2=(1-alpha/A)/a0;}
 else{a0=1+alpha;b->b0=(1-cs)/2/a0;b->b1=(1-cs)/a0;b->b2=b->b0;b->a1=-2*cs/a0;b->a2=(1-alpha)/a0;}
}
static void equalizer(Biquad*b,double rate,int band,float f,float db,float q){
 if((band==0&&f<=20)||(band==7&&f>=20000)){b->b0=1;b->b1=b->b2=b->a1=b->a2=0;return;}
 if(band>=2&&band<=5){coefficients(b,rate,f,q,db,1);return;}
 if(band==7){coefficients(b,rate,f,q,0,0);return;}
 double w=TAU*fmin(f,rate*.45)/rate,c=cos(w),a=sin(w)/(2*q),A=pow(10,db/40),t=2*sqrt(A)*a,a0;
 if(band==0){a0=1+a;b->b0=(1+c)/2/a0;b->b1=-(1+c)/a0;b->b2=b->b0;b->a1=-2*c/a0;b->a2=(1-a)/a0;}
 else if(band==1){a0=(A+1)+(A-1)*c+t;b->b0=A*((A+1)-(A-1)*c+t)/a0;b->b1=2*A*((A-1)-(A+1)*c)/a0;b->b2=A*((A+1)-(A-1)*c-t)/a0;b->a1=-2*((A-1)+(A+1)*c)/a0;b->a2=((A+1)+(A-1)*c-t)/a0;}
 else{a0=(A+1)-(A-1)*c+t;b->b0=A*((A+1)+(A-1)*c+t)/a0;b->b1=-2*A*((A-1)+(A+1)*c)/a0;b->b2=A*((A+1)+(A-1)*c-t)/a0;b->a1=2*((A-1)-(A+1)*c)/a0;b->a2=((A+1)-(A-1)*c-t)/a0;}
}
static float process(Biquad*b,float x){float y=b->b0*x+b->z1;b->z1=b->b1*x-b->a1*y+b->z2;b->z2=b->b2*x-b->a2*y;return y;}
static const float effectDefault[18][32]={
{},
{20000,0.707,1},
{0.8,3,1,0},
{0.3,1,1000,0.5},
{10,5000,1},
{0.68,0.4,0.2,1,1},
{0,20,60,2,-40,0,0},
{20,0,0.707,70,0,0.707,100,0,0.707,250,0,0.707,1000,0,0.707,2500,0,0.707,7500,0,0.707,20000,0,0.707},
{0.2,0.5,0.8,0.5},
{0},
{0.75,0.66,0.9,0.75,0.5,100,10000,1,0.2,1},
{0.96,402,4877,0.4,2},
{12,0.2},
{0.5,0,0.3,100,20000,0,1,0.8,0.4,1},
{1,44,402,2.5,0,0,0.5,18,130,0.9,0.82,0.35},
{20,0.5,0.5,100,14000,0.33,0.2,1,0.8,0.4,1},
{20,.2,70,1,410,6000,.65,.51,60,.7,.3},
{15,170,-16,.45,4400,5300,0,980,0,5},
};
static const float effectMin[18][32]={
{},
{20,0.1,0},
{0,0.01,0,0},
{0,0.0625,20,0},
{2,100,0},
{0,0,0,-24,0},
{-24,0.1,1,1,-60,0,-24},
{20,-24,0.1,20,-24,0.1,20,-24,0.1,20,-24,0.1,20,-24,0.1,20,-24,0.1,20,-24,0.1,20,-24,0.1},
{0.1,0,-0.95,0},
{-96},
{0,0,0,0,0,20,200,0,0},
{0,20,600,0,-24},
{-24,0},
{0,0,0,20,200,0,0,0,0,0},
{0,1,120,0.1,0,-24,0,1,0,0,0,0},
{0,0,0,20,200,0,0,0.01,0,0},
{0,0,1,0,20,20,0,0,0,0,0},
{0,20,-100,0,20,20,-30,20,-60,-60},
};
static const float effectMax[18][32]={
{},
{20000,10,1},
{1,20,1,1},
{0.95,2,20000,1},
{24,48000,1},
{20,1,0.95,12,1},
{24,1000,3000,20,0,1,24},
{20000,24,10,20000,24,10,20000,24,10,20000,24,10,20000,24,10,20000,24,10,20000,24,10,20000,24,10},
{10,1,0.95,1},
{6},
{1,0.95,1,1,1,2000,20000,1,1,1},
{1,800,20000,1,12},
{24,1},
{1,200,0.95,2000,20000,1,10,1,1,1,2},
{2,120,600,10,1,12,1,100,200,1,1,1},
{200,1,0.95,2000,20000,1,1,10,1,1,1,1},
{200,1,1000,1,20000,20000,20,1,360,1,1},
{100,20000,100,1,20000,20000,30,20000,60,60},
};
static const int effectCount[18]={0,3,4,4,3,5,7,24,4,1,10,5,2,11,12,12,11,10};

// Delay taps interpolate bounded preallocated memory. All state is render-owned.
static float tap_capacity(const float *buffer,int pos,float offset,int capacity){
 offset=fminf(capacity-2,fmaxf(1,offset));double at=(double)pos-(double)offset;while(at<0)at+=capacity;
 int i=((int)at)%capacity;float f=(float)(at-floor(at));return buffer[i]*(1-f)+buffer[(i+1)%capacity]*f;
}
#define tap(buffer,pos,offset) tap_capacity(buffer,pos,offset,s->delayLength)
static void effectReset(EffectState *e){
 memset(e,0,sizeof(*e));for(int i=0;i<8;i++)e->eq[i].b0=1;
}
static void effectCoefficients(EffectState*e,int kind,double rate){
 float *p=e->p;
 if(kind==10||kind==15||(kind==13&&p[10]>1.5f))rate/=(1 << (int)roundf((1-p[kind==10||kind==13?9:10])*5));
 if(kind==10){
  // An octave-up read doubles input frequencies. Band-limit the wet pitch
  // history first so high harmonics do not fold back as dissonant aliases.
  float cutoff=fminf(p[6]*.5f,rate*.2f);
  coefficients(&e->eq[0],rate,cutoff,.7071068f,0,0);
  coefficients(&e->eq[1],rate,cutoff,.7071068f,0,0);
 }
 if(kind==1)coefficients(&e->eq[0],rate,p[0],p[1],0,0);
 if(kind==7)for(int b=0;b<8;b++)equalizer(&e->eq[b],rate,b,p[b*3],p[b*3+1],p[b*3+2]);
 if(kind==6){e->coef[0]=exp(-1000/(rate*p[1]));e->coef[1]=exp(-1000/(rate*p[2]));e->coef[2]=pow(10,p[0]/20);e->coef[3]=pow(10,p[6]/20);}
 if(kind==9)e->coef[0]=p[0]<=-96?0:pow(10,p[0]/20);
 if(kind==5)e->coef[0]=pow(10,p[3]/20);
 if(kind==11){e->coef[0]=1-exp(-TAU*p[1]/rate);e->coef[1]=1-exp(-TAU*p[2]/rate);e->coef[2]=pow(10,p[4]/20);}
 if(kind==3)e->coef[0]=1-exp(-TAU*p[2]/rate);
 if(kind==16){e->coef[0]=1-exp(-TAU*p[4]/rate);e->coef[1]=1-exp(-TAU*p[5]/rate);}
 if(kind==17){
  e->coef[6]=1-exp(-1/(rate*.02));
  e->coef[0]=pow(10,p[0]/20);e->coef[5]=pow(10,p[8]/20);e->coef[4]=pow(10,p[9]/20);
  for(int i=1;i<=3;i++){float f=p[i==1?1:i==2?4:5],g=tanf(TAU*.5f*fminf(f,rate*.45f)/rate);e->coef[i]=g/(1+g);}
  equalizer(&e->eq[0],rate,6,p[7],p[6],.707f);
 }
 if(kind==12)e->coef[0]=pow(2,p[0]/12);
 if(kind==13||kind==15){e->coef[6]=1-exp(-TAU*5/rate);e->coef[7]=1-exp(-1/(rate*.02));}
 if(kind==10||kind==13||kind==15){int low=kind==10?5:3,tone=kind==10?6:4;e->coef[0]=1-exp(-TAU*p[low]/rate);e->coef[1]=1-exp(-TAU*p[tone]/rate);}
 if(kind==14){e->coef[0]=pow(10,p[5]/20);e->coef[1]=1-exp(-1/(rate*p[3]));}
}
static float shifted(SKSynth*s,EffectState*e,float *buffer,int pos,float ratio,double rate){
 float window=fminf(s->delayLength/4,rate*.06),phase=e->shiftPhase;
 phase+=(1-ratio)/window;phase-=floorf(phase);e->shiftPhase=phase;
 float phase2=phase+.5f;phase2-=floorf(phase2);
 float a=.5f-.5f*cosf(TAU*phase),b=1-a;
 return a*tap(buffer,pos,16+phase*window)+b*tap(buffer,pos,16+phase2*window);
}
// Chorus belongs before the reverb tank; keep the direct signal untouched.
static float cream_input(SKSynth*s,int l,int k,float input){
 EffectState*e=&s->effect[l][k];float*p=e->p;
 int pos=s->delayPosition[l][k];s->delay[l][k][pos]=input;
 if(p[5]>0&&p[6]>0){float offset=s->rate*(.015f+.010f*(.5f+.5f*sinf(s->fxPhase[l][k])));float mod=tap(s->delay[l][k],pos,offset);input=input*(1-p[5])+mod*p[5];}
 s->fxPhase[l][k]=fmod(s->fxPhase[l][k]+TAU*p[6]/s->rate,TAU);s->delayPosition[l][k]=(pos+1)%s->delayLength;
 return input;
}
// Wet-only source core; the host retains independent additive Dry/Wet controls.
static float cream_output(SKSynth*s,int l,int k,float dry,float wet){
 EffectState*e=&s->effect[l][k];float*p=e->p;
 e->z[0]+=e->coef[0]*(wet-e->z[0]);wet-=e->z[0];e->z[1]+=e->coef[1]*(wet-e->z[1]);wet=e->z[1];
 return dry*p[7]+wet*p[8];
}
// Eight-line Householder FDN with four input allpasses. Mixing is orthogonal;
// damped per-line gains stay below unity. All histories are preallocated.
static void dense_prepare(EffectState*e,int kind,double rate){
 DenseReverb*r=&e->reverb;float*p=e->p;
 if(r->ready && !memcmp(r->cache,p,12*sizeof(float)))return;
 int ambient=kind==15;float size=p[ambient?1:0],reflect=p[2]/.95f;
 double wetRate=rate/(1 << (int)roundf((1-p[ambient?10:9])*5));
 float scale=.40f+size*.77f;
 // Acoustic room classes alter geometry as well as time. Ambient size is continuous.
 int room=(int)roundf(size*6);float shape=ambient?0:(room%3-1)*.065f;
 const float times[8]={.0191f,.0263f,.0347f,.0433f,.0569f,.0683f,.0839f,.1073f};
 float decay=(ambient?1.2f:.15f)+(ambient?4:1)*reflect/(.03f+(1-reflect)*(1-reflect));
 for(int i=0;i<8;i++){
  float seconds=times[i]*scale*(1+shape*((i%3)-1));
  r->offset[i]=seconds*wetRate;r->feedback[i]=fminf(.9999f,powf(.001f,seconds/decay));
  double step=TAU*(.071+i*.037)*(ambient?.35+p[7]*.35:1)/wetRate;
  r->stepSin[i]=sin(step);r->stepCos[i]=cos(step);
  if(!r->ready){r->oscSin[i]=sin(i*1.71);r->oscCos[i]=cos(i*1.71);}
 }
 if(!r->ready){r->damping[0]=e->coef[0];r->damping[1]=e->coef[1];r->mix[0]=p[ambient?8:7];r->mix[1]=p[ambient?9:8];}
 memcpy(r->cache,p,12*sizeof(float));r->ready=1;
}
static float dense_process(SKSynth*s,int l,int k,float x,float dry,double rate){
 EffectState*e=&s->effect[l][k];DenseReverb*r=&e->reverb;float*p=e->p;
 int ambient=s->fxKind[l][k]==15,capacity=s->delayLength/14,pos=s->delayPosition[l][k]%capacity;
 float*buffer=s->delay[l][k];
 for(int i=0;i<2;i++)r->damping[i]+=e->coef[7]*(e->coef[i]-r->damping[i]);
 x+=r->crossInput;
 int prepos=s->predelayPosition[l][k];float pre=p[ambient?0:1];
 float input=pre>0?tap_capacity(s->predelay[l][k],prepos,rate*pre*.001f,s->predelayLength):x;
 s->predelay[l][k][prepos]=x;s->predelayPosition[l][k]=(prepos+1)%s->predelayLength;
 // Low cut removes excitation mud; a separate gentle DC blocker acts in feedback.
 e->z[6]+=r->damping[0]*(input-e->z[6]);input-=e->z[6];
 float*chorus=buffer+12*capacity;chorus[pos]=input;
 float amount=p[ambient?6:5],hz=p[ambient?7:6],phase=s->fxPhase[l][k];
 if(amount>0 && hz>0)input=input*(1-amount)+amount*tap_capacity(chorus,pos,rate*(.016f+.006f*sinf(phase+s->stereoSide*.73f)),capacity);
 float early=0;float*earlyHistory=buffer+13*capacity;earlyHistory[pos]=input;
 for(int i=0;i<4;i++)early+=tap_capacity(earlyHistory,pos,rate*(.0037f+i*.0041f)*(.6f+p[ambient?1:0])*(1+s->stereoSide*.071f),capacity)*(i%2?-.18f:.23f);
 for(int i=0;i<4;i++){
  float*h=buffer+(8+i)*capacity,delayed=tap_capacity(h,pos,rate*(.0031f+i*.0023f)*(1+s->stereoSide*.031f),capacity);
  float out=delayed-.62f*input;h[pos]=input+.62f*out;input=out;
 }
 float v[8],sum=0,wet=0;
 for(int i=0;i<8;i++){
  double old=r->oscSin[i];r->oscSin[i]=old*r->stepCos[i]+r->oscCos[i]*r->stepSin[i];r->oscCos[i]=r->oscCos[i]*r->stepCos[i]-old*r->stepSin[i];
  float modulation=ambient?p[5]*rate*.00065f*r->oscSin[i]:0;
  float delayed=tap_capacity(buffer+i*capacity,pos,r->offset[i]*(1+s->stereoSide*.013f)+modulation,capacity);
  r->low[i]+=r->damping[1]*(delayed-r->low[i]);
  r->dc[i]+=e->coef[6]*(r->low[i]-r->dc[i]);
  v[i]=(r->low[i]-r->dc[i])*r->feedback[i];sum+=v[i];
  wet+=delayed*(i%2?-.35355339f:.35355339f);
 }
 for(int i=0;i<8;i++){
  float value=input*(i%3==0?-.25f:.25f)+sum*.25f-v[i];
  buffer[i*capacity+pos]=fabsf(value)>8 ? 8*tanhf(value/8):value;
 }
 wet=wet*.7f+early*(ambient?.08f:.5f);
 e->z[1]+=r->damping[1]*(wet-e->z[1]);wet=e->z[1];
 float slew=e->coef[7];r->mix[0]+=slew*(p[ambient?8:7]-r->mix[0]);r->mix[1]+=slew*(p[ambient?9:8]-r->mix[1]);
 e->z[5]=wet;s->fxPhase[l][k]=fmod(phase+TAU*hz/rate,TAU);s->delayPosition[l][k]=(pos+1)%capacity;
 return dry*r->mix[0]+wet*r->mix[1];
}
static float effectProcess(SKSynth*s,int l,int k,float x){
 int kind=s->fxKind[l][k];EffectState*e=&s->effect[l][k];float *p=e->p,*buffer=s->delay[l][k],dry=x,y=x;
 int pos=s->delayPosition[l][k];double rate=s->rate;float phase=s->fxPhase[l][k];
 e->stereo=0;
 if(kind==10||kind==15||(kind==13&&p[10]>1.5f)){
  int divider=1 << (int)roundf((1-p[kind==10||kind==13?9:10])*5);
  e->z[3]+=x;e->z[4]+=1;
  if(e->z[4]<divider)return (kind==13&&p[10]>1.5f)||(kind==15&&p[11]>0) ? dry*e->reverb.mix[0]+e->z[5]*e->reverb.mix[1] : kind==10?dry*p[7]+e->z[5]*p[8]:dry*p[8]+e->z[5]*p[9];
  x=e->z[3]/e->z[4];e->z[3]=e->z[4]=0;rate/=divider;
 }
 if((kind==13&&p[10]>1.5f)||(kind==15&&p[11]>0))return dense_process(s,l,k,x,dry,rate);
 if(kind==13&&p[10]>0){float a=cream_input(s,l,k,x),b=a;SKCreamCoat*c=atomic_load_explicit(&s->cream[l][k],memory_order_acquire);if(!c)return x;sk_cream_frame(c,&a,&b);return cream_output(s,l,k,x,(a+b)*.5f);}
 if(!e->custom&&kind<=3){
  s->fxCurrent[l][k]+=(s->fxAmount[l][k]-s->fxCurrent[l][k])*.002f;float a=s->fxCurrent[l][k];
  if(kind==1){float c=.004f+a*a*.8f;s->tone[l][k]+=c*(x-s->tone[l][k]);return s->tone[l][k];}
  if(kind==2){s->fxPhase[l][k]=fmod(phase+TAU*3/rate,TAU);return x*(1-a*(.5f+.5f*sinf(phase)));}
  if(kind==3){int length=(int)fmin(s->delayLength,rate*.25);float t=buffer[pos];buffer[pos]=x+t*.3f;s->delayPosition[l][k]=(pos+1)%length;return x*(1-a*.5f)+t*a;}
 }
 switch(kind){
 case 1:y=p[0]>=20000?x:process(&e->eq[0],x);y=dry+(y-dry)*p[2];break;
 case 2:{float mod=.5f+.5f*sinf(phase);y=x*(1-p[0]*mod);y=dry+(y-dry)*p[2];e->stereo=p[3]*p[0]*sinf(phase)*.5f;s->fxPhase[l][k]=fmod(phase+TAU*p[1]/rate,TAU);break;}
 case 3:{float duration=fminf(s->delayLength-2,rate*60/s->clockTempo*p[1]);float t=tap(buffer,pos,duration);e->z[0]+=e->coef[0]*(t-e->z[0]);buffer[pos]=tanhf(x+e->z[0]*p[0]);y=x*(1-p[3])+e->z[0]*p[3];break;}
 case 4:{e->z[1]+=p[1]/rate;if(e->z[1]>=1){e->z[1]-=floorf(e->z[1]);float levels=powf(2,roundf(p[0])-1);e->z[0]=roundf(x*levels)/levels;}y=x+(e->z[0]-x)*p[2];break;}
 case 5:case 8:{float hz=p[0],depth=p[1],feedback=p[2],mix=kind==5?p[4]:p[3];float delay=kind==5?rate*(.015f+.01f*depth*(.5f+.5f*sinf(phase))):rate*(.0005f+.004f*depth*(.5f+.5f*sinf(phase)));float t=tap(buffer,pos,delay);buffer[pos]=tanhf(x+t*feedback);y=(x*(1-mix)+t*mix)*(kind==5?e->coef[0]:1);s->fxPhase[l][k]=fmod(phase+TAU*hz/rate,TAU);break;}
 case 6:{float v=x*e->coef[2],level=fabsf(v),a=level>e->z[0]?e->coef[0]:e->coef[1];e->z[0]=a*e->z[0]+(1-a)*level;float db=20*log10f(fmaxf(1e-9,e->z[0]));float reduction=fmaxf(0,db-p[4])*(1-1/p[3]);y=(dry*(1-p[5])+v*powf(10,-reduction/20)*p[5])*e->coef[3];break;}
 case 7:for(int b=0;b<8;b++)y=process(&e->eq[b],y);break;
 case 9:y=x*e->coef[0];break;
 case 10:{
  // Diffuse the room before octave shifting. The pitch history contains only
  // the wet return, never the dry attack. All buffers are allocated off-thread.
  int capacity=s->delayLength/6,index=pos%capacity;
  float room=.035f+p[2]*.13f,decay=.4f+p[2]*7,wet=0;
  const float spacing[4]={1,1.271f,1.617f,1.953f};
  float pitch=e->z[6],recirculate=p[0]*p[1]*.65f;
  for(int line=0;line<4;line++){
   float seconds=room*spacing[line]*(s->stereoSide?1.031f:1);
   float mod=sinf(phase+line*1.73f+s->stereoSide*.9f)*rate*.0007f*p[4];
   float*history=buffer+line*capacity;
   float delayed=tap_capacity(history,index,rate*seconds+mod,capacity);
   float feedback=powf(.001f,seconds/decay);
   // Tone must absorb high-frequency energy on every trip through the
   // tank; filtering only the output leaves a bright ringing tail inside.
   e->z[8+line]+=e->coef[1]*(delayed-e->z[8+line]);
   history[index]=x+feedback*(e->z[8+line]*(1-recirculate)+pitch*recirculate);
   wet+=delayed*.25f;
  }
  for(int line=0;line<2;line++){
   float*history=buffer+(4+line)*capacity;
   float delayed=tap_capacity(history,index,rate*(line==0?.0071f:.0113f)*(s->stereoSide?1.07f:1),capacity);
   float a=p[3]*.7f,out=delayed-a*wet;history[index]=wet+a*out;wet=out;
  }
  // Frequency-tracked overlap/add avoids the periodic detuning of short
  // crossfaded grains. Its frame latency belongs only to the wet octave path.
  SKShimmerPitch*shifter=atomic_load_explicit(&s->shimmer[l][k],memory_order_acquire);
  pitch=sk_pitch_process(shifter,process(&e->eq[1],process(&e->eq[0],wet)),1 << (int)roundf((1-p[9])*5));e->z[6]=pitch;
  wet=wet*(1-p[0])+pitch*p[0];
  e->z[0]+=e->coef[0]*(wet-e->z[0]);wet-=e->z[0];e->z[1]+=e->coef[1]*(wet-e->z[1]);wet=e->z[1];
  e->z[5]=wet;y=dry*p[7]+wet*p[8];s->fxPhase[l][k]=fmod(phase+TAU*.3f/rate,TAU);break;}
 case 15:{
  // Independent modulated delay lines, with a separate pre-tank chorus.
  // Partitioned histories are allocated off-thread; the direct path is intact.
  int capacity=s->delayLength/7,index=pos%capacity;
  int prepos=s->predelayPosition[l][k];
  float input=p[0]>0?tap_capacity(s->predelay[l][k],prepos,rate*p[0]*.001f,s->predelayLength):x;
  s->predelay[l][k][prepos]=x;s->predelayPosition[l][k]=(prepos+1)%s->predelayLength;
  float*chorus=buffer+6*capacity;chorus[index]=input;
  if(p[6]>0&&p[7]>0){float seconds=.015f+.010f*(.5f+.5f*sinf(phase));input=input*(1-p[6])+tap_capacity(chorus,index,seconds*rate,capacity)*p[6];}
  const float spacing[4]={1,1.271f,1.617f,1.953f};
  float room=.025f+p[1]*.10f,decay=.5f+30*p[2]*p[2],wet=0;
  for(int line=0;line<4;line++){
   float seconds=room*spacing[line]*(s->stereoSide?1.019f:1);
   float modulation=sinf(phase*(.37f+line*.173f)+line*1.73f+s->stereoSide*.91f)*p[5]*rate*.002f;
   float*history=buffer+line*capacity;
   float delayed=tap_capacity(history,index,seconds*rate+modulation,capacity);
   float feedback=fminf(.9995f,powf(.001f,seconds/decay));
   history[index]=input+delayed*feedback;wet+=delayed*.25f;
  }
  for(int line=0;line<2;line++){
   float*history=buffer+(4+line)*capacity;
   float delayed=tap_capacity(history,index,rate*(line==0?.0071f:.0113f)*(s->stereoSide?1.07f:1),capacity);
   float a=.65f,out=delayed-a*wet;history[index]=wet+a*out;wet=out;
  }
  e->z[0]+=e->coef[0]*(wet-e->z[0]);wet-=e->z[0];e->z[1]+=e->coef[1]*(wet-e->z[1]);wet=e->z[1];
  e->z[5]=wet;y=dry*p[8]+wet*p[9];s->fxPhase[l][k]=fmod(phase+TAU*p[7]/rate,TAU);break;}
 case 13:{
  float size=kind==10?p[2]:kind==13?p[0]:p[1],feedback=kind==10?p[1]:p[2];float predelay=kind==13?p[1]:kind==15?p[0]:0;
  float modulation=kind==10?p[4]:kind==13?p[5]:p[6];float hz=kind==10?.3f:kind==13?p[6]:p[7];
  float base=rate*(.027f+size*.13f)*(kind==13 && s->stereoSide ? 1.037f:1),mod=sinf(phase)*rate*.001f*modulation;
  float first=tap(buffer,pos,base+mod);
  float wet;
  if(kind==13) {
   float dense=(first+tap(buffer,pos,base*1.31f-mod)+tap(buffer,pos,base*1.73f+mod)+tap(buffer,pos,base*2.17f-mod))*.25f;
   wet=first+(dense-first)*p[9];
  } else {wet=(first+tap(buffer,pos,base*1.31f-mod)+tap(buffer,pos,base*1.73f+mod)+tap(buffer,pos,base*2.17f-mod))*.25f;}
  if(kind==10){float pitch=shifted(s,e,buffer,pos,2,rate);wet=wet*(1-p[0]) + pitch*p[0];}
  if(kind==15){float pitch=shifted(s,e,buffer,pos,1+.015f*p[5]*sinf(phase*.37f),rate);wet=wet*(1-p[5]*.25f)+pitch*p[5]*.25f;}
  e->z[0]+=e->coef[0]*(wet-e->z[0]);wet-=e->z[0];e->z[1]+=e->coef[1]*(wet-e->z[1]);wet=e->z[1];
  if(kind==10){float a=p[3]*.65f,ap=-a*wet+e->z[2];e->z[2]=wet+a*ap;wet=ap;}
  int prepos=s->predelayPosition[l][k];
  float input=predelay>0?tap_capacity(s->predelay[l][k],prepos,rate*predelay*.001f,s->predelayLength):x;
  s->predelay[l][k][prepos]=x;s->predelayPosition[l][k]=(prepos+1)%s->predelayLength;
  // A single bounded feedback tank with four decorrelated taps. Independent algorithm.
  buffer[pos]=input+wet*feedback*.94f;
  int di=kind==10?7:kind==13?7:8,wi=di+1;if(kind==10)e->z[5]=wet;y=dry*p[di]+wet*p[wi];s->fxPhase[l][k]=fmod(phase+TAU*hz/rate,TAU);break;}
 case 11:{e->z[0]+=e->coef[0]*(x-e->z[0]);float v=x-e->z[0],drive=1+p[0]*30;v=tanhf(v*drive)/tanhf(drive);e->z[1]+=e->coef[1]*(v-e->z[1]);y=(x*(1-p[3])+e->z[1]*p[3])*e->coef[2];break;}
 case 12:buffer[pos]=x;y=p[0]==0?x:x*(1-p[1])+shifted(s,e,buffer,pos,e->coef[0],rate)*p[1];break;
 case 16:{
  int prepos=s->predelayPosition[l][k];
  float input=p[0]>0?tap_capacity(s->predelay[l][k],prepos,rate*p[0]*.001f,s->predelayLength):x;
  s->predelay[l][k][prepos]=x;s->predelayPosition[l][k]=(prepos+1)%s->predelayLength;
  int capacity=s->delayLength/8,index=pos%capacity;float wet=0;
  const float spacing[4]={.73f,.89f,1.07f,1.19f};
  float room=.025f+p[2]*.0003f,decay=(.2f+p[3]*8+p[1]*4)*1.04f;
  float angle=phase+s->stereoSide*p[8]*TAU/360;
  for(int line=0;line<4;line++){
   float seconds=room*spacing[line]*(s->stereoSide?1.013f:1),offset=seconds*rate;
   offset+=sinf(angle+line)*p[7]*rate*.0015f;
   float tail=tap_capacity(buffer+line*capacity,index,offset,capacity);
   float feedback=fminf(.985f,powf(.001f,seconds/decay));
   // Absorb high frequencies on successive late-tank trips; an output
   // filter alone cannot reproduce the source's frequency-dependent decay.
   e->z[8+line]+=e->coef[1]*(tail-e->z[8+line]);
   buffer[line*capacity+index]=input*.35f+(tail*.8f+e->z[8+line]*.2f)*feedback;wet+=tail*.25f;
  }
  // Short reflection paths build the room response before the late tank fills.
  // Separate delay partitions keep their decay independent of the long tail.
  float early=0,earlyDecay=decay*(.5f+.2f*p[3]+.1f*p[1]);
  for(int line=0;line<2;line++){
   float seconds=room*(line==0?.47f:.61f)*(s->stereoSide?1.017f:1);
   float*reflection=buffer+(6+line)*capacity;
   float delayed=tap_capacity(reflection,index,seconds*rate,capacity);
   reflection[index]=input+delayed*powf(.001f,seconds/earlyDecay);
   early+=delayed*.5f;
  }
  wet+=early*p[1]*.8f;
  float diffusion=.15f+.55f*p[3];
  for(int stage=0;stage<2;stage++){
   float*line=buffer+(4+stage)*capacity;
   float delayed=tap_capacity(line,index,rate*(stage==0?.0053f:.0017f),capacity);
   float ap=delayed-diffusion*wet;line[index]=wet+diffusion*ap;wet=ap;
  }
  e->z[0]+=e->coef[0]*(wet-e->z[0]);wet-=e->z[0];e->z[1]+=e->coef[1]*(wet-e->z[1]);wet=e->z[1];
  y=x*p[9]+wet*p[10];s->fxPhase[l][k]=fmod(phase+TAU*p[6]/rate,TAU);break;
 }
 case 17:{
  if(!e->clipReady){e->clipControl[0]=e->coef[5];e->clipControl[1]=e->coef[4];e->clipControl[2]=p[3];e->clipReady=1;}
  e->clipControl[0]+=e->coef[6]*(e->coef[5]-e->clipControl[0]);
  e->clipControl[1]+=e->coef[6]*(e->coef[4]-e->clipControl[1]);
  e->clipControl[2]+=e->coef[6]*(p[3]-e->clipControl[2]);
  float input=x*e->clipControl[0],amplified=input*e->coef[0];
  float v=(amplified-e->z[0])*e->coef[1],low=v+e->z[0];e->z[0]=low+v;
  float bias=p[2]*.01f,signal=amplified-low;
  // Antiderivative antialiasing of the independent soft clipper. The divided
  // difference integrates the transfer curve between samples without resampling.
  float previous=e->z[3],difference=signal-previous,clipped;
  if(fabsf(difference)<.0001f)clipped=tanhf((signal+previous)*.5f+bias)-tanhf(bias);
  else {float a=signal+bias,b=previous+bias;
   double fa=fabs((double)a)+log1p(exp(-2*fabs((double)a))),fb=fabs((double)b)+log1p(exp(-2*fabs((double)b)));
   clipped=(fa-fb)/difference-tanhf(bias);
  }
  e->z[3]=signal;
  v=(clipped-e->z[1])*e->coef[2];low=v+e->z[1];e->z[1]=low+v;
  float mixed=input*(1-e->clipControl[2])+low*e->clipControl[2];
  v=(mixed-e->z[2])*e->coef[3];low=v+e->z[2];e->z[2]=low+v;
  y=process(&e->eq[0],low)*e->clipControl[1];break;
 }
 case 14:{float target=p[0]<.5f?0:p[0]<1.5f?p[1]/60:p[2]/60;e->z[0]+=(target-e->z[0])*e->coef[1];s->fxPhase[l][k]=fmod(phase+TAU*e->z[0]/rate,TAU);float doppler=rate*(.002f+.0015f*(p[7]/100)*sinf(phase));buffer[pos]=x;float body=tap(buffer,pos,doppler);float driven=tanhf(body*(1+p[4]*12));float ambience=tap(buffer,pos,rate*(.02f+.15f*p[9]));float amp=.72f+.28f*cosf(phase)*(1-p[6]*.5f);y=(driven*amp+ambience*p[11]*.4f)*e->coef[0];e->stereo=sinf(phase)*fminf(1,p[8]/200)*p[10];break;}
 default:break;
 }
 s->delayPosition[l][k]=(pos+1)%s->delayLength;
 if(!isfinite(y)){y=0;memset(e->z,0,sizeof(e->z));memset(&e->reverb,0,sizeof(e->reverb));}
 return y;
}

void sk_imported_delay(SKSynth*s,int slot,int enabled,float leftSeconds,float rightSeconds,int pingPong,float lowCut,float highCut){
 if(slot>=0&&slot<3&&isfinite(leftSeconds)&&isfinite(rightSeconds)&&isfinite(lowCut)&&isfinite(highCut))enqueue(s,(Command){.kind=19,.key=slot,.instrument=enabled,.value=leftSeconds,.a=rightSeconds,.b=pingPong?1:0,.d=lowCut,.seconds=highCut});
}
void sk_imported_delay_channel(SKSynth*s,int slot,int enabled,float feedback,float crossFeedback,float mix,int input){
 if(slot>=0&&slot<3&&isfinite(feedback)&&isfinite(crossFeedback)&&isfinite(mix))enqueue(s,(Command){.kind=21,.key=slot,.instrument=enabled,.value=feedback,.a=crossFeedback,.b=mix,.d=input});
}
void sk_effect_parameter(SKSynth*s,int l,int slot,int index,float value){if(l>=0&&l<BUSES&&slot>=0&&slot<3&&index>=0&&index<32&&isfinite(value))enqueue(s,(Command){.kind=17,.layer=l,.key=slot,.pitch=index,.value=value});}
static void commands(SKSynth *s) {
 unsigned r=atomic_load_explicit(&s->read,memory_order_relaxed);
 unsigned w=atomic_load_explicit(&s->write,memory_order_acquire);
 if(atomic_exchange(&s->emergency,0)){
  memset(s->voices,0,sizeof(s->voices));for(int dl=0;dl<BUSES;dl++)for(int dk=0;dk<3;dk++)clear_delay(s,dl,dk);memset(s->tone,0,sizeof(s->tone));for(int el=0;el<BUSES;el++)for(int ek=0;ek<3;ek++){EffectState*e=&s->effect[el][ek];memset(e->z,0,sizeof(e->z));memset(&e->reverb,0,sizeof(e->reverb));e->shiftPhase=e->stereo=0;s->delayPosition[el][ek]=0;s->fxPhase[el][ek]=0;for(int eb=0;eb<8;eb++)e->eq[eb].z1=e->eq[eb].z2=0;}for(int l=0;l<BUSES;l++){s->filter[l].z1=s->filter[l].z2=0;s->detector[l]=0;for(int k=0;k<8;k++)s->eq[l][k].z1=s->eq[l][k].z2=0;}s->sustain=0;s->clockEnabled=0;s->clockEnvelope=0;
  atomic_store_explicit(&s->read,w,memory_order_release);return;
 }
 while(r!=w){Command c=s->queue[r];
  if(c.kind==1){
   int selected=-1,count=0,oldest=-1;double age=-1;float quietest=2;
   for(int i=0;i<VOICES;i++)if(s->voices[i].active&&s->voices[i].layer==c.layer){count++;if(s->voices[i].age>age){age=s->voices[i].age;oldest=i;}}
   if(count>=s->voiceLimit[c.layer])selected=oldest;
   if(selected<0)for(int i=0;i<VOICES;i++){if(!s->voices[i].active){selected=i;break;} if(s->voices[i].env<quietest){quietest=s->voices[i].env;selected=i;}}
   s->voices[selected]=(Voice){.active=1,.key=c.key,.instrument=c.instrument,.layer=c.layer,.held=1,.step=TAU*440*pow(2,(c.pitch-69)/12.0)/s->rate,.velocity=c.value};
  }else if(c.kind==2){for(int i=0;i<VOICES;i++)if(s->voices[i].active&&s->voices[i].key==c.key){s->voices[i].held=0;if(!s->sustain||c.key>=256||s->blockSustain[s->voices[i].layer])s->voices[i].releasing=1;}}
  else if(c.kind==3){int l=c.layer;s->target[l]=c.value;s->remaining[l]=(unsigned)(s->rate*c.seconds);if(!s->remaining[l])s->gain[l]=c.value;else s->delta[l]=(c.value-s->gain[l])/s->remaining[l];}
  else if(c.kind==4){s->sustain=c.value>0;if(!s->sustain)for(int i=0;i<VOICES;i++)if(!s->voices[i].held)s->voices[i].releasing=1;}
  else if(c.kind==5){int l=c.layer,k=c.key;if(s->fxKind[l][k]!=c.instrument){s->tone[l][k]=0;clear_delay(s,l,k);s->delayPosition[l][k]=0;s->fxPhase[l][k]=0;effectReset(&s->effect[l][k]);memcpy(s->effect[l][k].p,effectDefault[c.instrument],sizeof(s->effect[l][k].p));effectCoefficients(&s->effect[l][k],c.instrument,s->rate);}s->fxKind[l][k]=c.instrument;s->fxAmount[l][k]=c.value;}
  else if(c.kind==6)s->pan[c.layer]=c.value;
  else if(c.kind==7){s->blockSustain[c.layer]=c.value>0;if(c.value>0)for(int i=0;i<VOICES;i++)if(s->voices[i].layer==c.layer&&!s->voices[i].held)s->voices[i].releasing=1;}
  else if(c.kind==8){s->clockTempo=c.value;if(c.key&&!s->clockEnabled)s->clockRemaining=0;s->clockEnabled=c.key;}
  else if(c.kind==9){memset(s->voices,0,sizeof(s->voices));for(int dl=0;dl<BUSES;dl++)for(int dk=0;dk<3;dk++)clear_delay(s,dl,dk);memset(s->tone,0,sizeof(s->tone));for(int el=0;el<BUSES;el++)for(int ek=0;ek<3;ek++){EffectState*e=&s->effect[el][ek];memset(e->z,0,sizeof(e->z));memset(&e->reverb,0,sizeof(e->reverb));e->shiftPhase=e->stereo=0;s->delayPosition[el][ek]=0;s->fxPhase[el][ek]=0;for(int eb=0;eb<8;eb++)e->eq[eb].z1=e->eq[eb].z2=0;}for(int l=0;l<BUSES;l++){s->filter[l].z1=s->filter[l].z2=0;s->detector[l]=0;for(int k=0;k<8;k++)s->eq[l][k].z1=s->eq[l][k].z2=0;}s->sustain=0;s->clockEnabled=0;s->clockEnvelope=0;}
  else if(c.kind==10){s->customEnvelope[c.layer]=1;s->adsr[c.layer][0]=c.value;s->adsr[c.layer][1]=c.seconds;s->adsr[c.layer][2]=c.a;s->adsr[c.layer][3]=c.b;}
  else if(c.kind==11){s->voiceLimit[c.layer]=c.key;int count=0;for(int i=0;i<VOICES;i++)if(s->voices[i].active&&s->voices[i].layer==c.layer&&++count>c.key)s->voices[i].active=0;}
  else if(c.kind==12)s->preGain[c.layer]=c.value;
  else if(c.kind==13){s->cutoff[c.layer]=c.value;coefficients(&s->filter[c.layer],s->rate,c.value,c.a,0,0);}
  else if(c.kind==14)equalizer(&s->eq[c.layer][c.key],s->rate,c.key,c.value,c.a,c.b);
  else if(c.kind==15){int l=c.layer;s->compressEnabled[l]=c.key;s->threshold[l]=c.value;s->ratio[l]=c.seconds;s->compAttack[l]=exp(-1/(s->rate*c.a));s->compRelease[l]=exp(-1/(s->rate*c.b));s->makeup[l]=c.d;}
  else if(c.kind==22){for(int i=0;i<VOICES;i++)if(s->voices[i].layer==c.layer){s->voices[i].held=0;s->voices[i].releasing=1;}}
  else if(c.kind==18){int l=c.layer;for(int i=0;i<VOICES;i++)if(s->voices[i].layer==l)s->voices[i].active=0;for(int dk=0;dk<3;dk++)clear_delay(s,l,dk);memset(s->tone[l],0,sizeof(s->tone[l]));s->filter[l].z1=s->filter[l].z2=s->detector[l]=0;for(int k=0;k<3;k++){EffectState*e=&s->effect[l][k];memset(e->z,0,sizeof(e->z));memset(&e->reverb,0,sizeof(e->reverb));e->shiftPhase=e->stereo=0;s->delayPosition[l][k]=0;s->fxPhase[l][k]=0;for(int b=0;b<8;b++)e->eq[b].z1=e->eq[b].z2=0;}for(int b=0;b<8;b++)s->eq[l][b].z1=s->eq[l][b].z2=0;}
  else if(c.kind==16){for(int i=0;i<VOICES;i++)if(s->voices[i].active&&s->voices[i].layer==c.layer&&s->voices[i].key==c.key){s->voices[i].held=0;if(c.instrument||!s->sustain||s->blockSustain[c.layer])s->voices[i].releasing=1;}}
  else if(c.kind==20){s->compressorInput[c.layer]=powf(10,c.value/20);s->compressorWet[c.layer]=c.a;}
  else if(c.kind==21){EffectState*e=&s->effect[0][c.key];e->p[30]=c.instrument?1:0;e->p[4]=bounded(c.value,-.95f,.95f);e->p[5]=bounded(c.a,-(.95f-fabsf(e->p[4])),.95f-fabsf(e->p[4]));e->p[6]=bounded(c.b,0,1);e->p[7]=bounded(c.d,0,4);}
  else if(c.kind==19){EffectState*e=&s->effect[0][c.key];e->p[24]=c.instrument?1:0;e->p[25]=bounded(c.value,.001f,16);e->p[26]=bounded(c.a,.001f,16);e->p[27]=c.b;e->p[28]=bounded(c.d,20,20000);e->p[29]=bounded(c.seconds,e->p[28],20000);e->coef[4]=1-exp(-TAU*e->p[28]/s->rate);e->coef[5]=1-exp(-TAU*e->p[29]/s->rate);}
  else if(c.kind==17){int kind=s->fxKind[c.layer][c.key];if(c.pitch<effectCount[kind]){EffectState*e=&s->effect[c.layer][c.key];e->custom=1;
   if(((kind==13&&c.pitch==10)||(kind==15&&c.pitch==11))&&e->p[c.pitch]!=c.value){clear_delay(s,c.layer,c.key);memset(e->z,0,sizeof(e->z));memset(&e->reverb,0,sizeof(e->reverb));s->delayPosition[c.layer][c.key]=0;s->fxPhase[c.layer][c.key]=0;}
   e->p[c.pitch]=bounded(c.value,effectMin[kind][c.pitch],effectMax[kind][c.pitch]);effectCoefficients(e,kind,s->rate);}}
  r=(r+1)%QUEUE;
 }
 // Cache coefficients once per block, never allocate from the render callback.
 for(int l=0;l<BUSES;l++)for(int k=0;k<3;k++)if(s->fxKind[l][k]==13&&s->effect[l][k].p[10]>0&&s->effect[l][k].p[10]<1.5f){SKCreamCoat*c=atomic_load_explicit(&s->cream[l][k],memory_order_acquire);float*p=s->effect[l][k].p;if(c)sk_cream_configure(c,p[0],p[2],p[9],p[1]/200);}
 for(int l=0;l<BUSES;l++)for(int k=0;k<3;k++){int kind=s->fxKind[l][k];EffectState*e=&s->effect[l][k];if((kind==13&&e->p[10]>1.5f)||(kind==15&&e->p[11]>0))dense_prepare(e,kind,s->rate);}
 atomic_store_explicit(&s->read,r,memory_order_release);
}
void sk_process_effects(SKSynth*s,float*audio,uint32_t frames){
 commands(s);
 for(uint32_t n=0;n<frames;n++){
  float x=isfinite(audio[n])?audio[n]:0;
  for(int k=0;k<3;k++)if(s->fxKind[0][k])x=effectProcess(s,0,k,x);
  audio[n]=isfinite(x)?fminf(16,fmaxf(-16,x)):0;
 }
}
// Imported stereo delays share feedback between the two render-owned states.
// No allocation or Swift calls occur inside the render loop.
void sk_process_effects_stereo(SKSynth*l,SKSynth*r,float*left,float*right,uint32_t frames){
 commands(l);commands(r);
 l->stereoSide=0;r->stereoSide=1;
 for(uint32_t n=0;n<frames;n++){
  float x=isfinite(left[n])?left[n]:0,y=isfinite(right[n])?right[n]:0;
  for(int k=0;k<3;k++){
   EffectState*a=&l->effect[0][k],*b=&r->effect[0][k];
   if(l->fxKind[0][k]==13&&a->p[10]>0&&a->p[10]<1.5f){
    SKCreamCoat*c=atomic_load_explicit(&l->cream[0][k],memory_order_acquire);
    if(c){float wl=cream_input(l,0,k,x),wr=cream_input(r,0,k,y);sk_cream_frame(c,&wl,&wr);x=cream_output(l,0,k,x,wl);y=cream_output(r,0,k,y,wr);}
   }else if((l->fxKind[0][k]==13&&a->p[10]>1.5f&&r->fxKind[0][k]==13&&b->p[10]>1.5f)||(l->fxKind[0][k]==15&&a->p[11]>0&&r->fxKind[0][k]==15&&b->p[11]>0)){
    a->reverb.crossInput=(y-x)*.15f;b->reverb.crossInput=(x-y)*.15f;
    x=effectProcess(l,0,k,x);y=effectProcess(r,0,k,y);
    a->reverb.crossInput=b->reverb.crossInput=0;
   }else if(l->fxKind[0][k]==3&&a->p[24]>0){
    int lp=l->delayPosition[0][k],rp=r->delayPosition[0][k];
    float dl=tap_capacity(l->delay[0][k],lp,a->p[25]*l->rate,l->delayLength),dr=tap_capacity(r->delay[0][k],rp,a->p[26]*r->rate,r->delayLength);
    if(a->p[28]>20){a->z[2]+=a->coef[4]*(dl-a->z[2]);dl-=a->z[2];}
    if(b->p[28]>20){b->z[2]+=b->coef[4]*(dr-b->z[2]);dr-=b->z[2];}
    if(a->p[29]<20000){a->z[3]+=a->coef[5]*(dl-a->z[3]);dl=a->z[3];}
    if(b->p[29]<20000){b->z[3]+=b->coef[5]*(dr-b->z[3]);dr=b->z[3];}
    float feedback=a->p[0],mix=a->p[3];
    float il=a->p[27]>0?(x+y)*.5f:x,ir=a->p[27]>0?0:y;
    if(a->p[30]>0 && b->p[30]>0){
     int li=(int)a->p[7],ri=(int)b->p[7];
     float lin=li==0?0:li==1?x:li==2?y:li==3?(x+y)*.5f:(x-y)*.5f;
     float rin=ri==0?0:ri==1?x:ri==2?y:ri==3?(x+y)*.5f:(x-y)*.5f;
     l->delay[0][k][lp]=fminf(16,fmaxf(-16,lin+dl*a->p[4]+dr*a->p[5]));
     r->delay[0][k][rp]=fminf(16,fmaxf(-16,rin+dr*b->p[4]+dl*b->p[5]));
     x=x*(1-a->p[6])+dl*a->p[6];y=y*(1-b->p[6])+dr*b->p[6];
    }else{
     l->delay[0][k][lp]=fminf(16,fmaxf(-16,il+(a->p[27]>0?dr:dl)*feedback));
     r->delay[0][k][rp]=fminf(16,fmaxf(-16,ir+(a->p[27]>0?dl:dr)*feedback));
     x=x*(1-mix)+dl*mix;y=y*(1-mix)+dr*mix;
    }
    l->delayPosition[0][k]=(lp+1)%l->delayLength;r->delayPosition[0][k]=(rp+1)%r->delayLength;
   }else{
    if(l->fxKind[0][k])x=effectProcess(l,0,k,x);
    if(r->fxKind[0][k])y=effectProcess(r,0,k,y);
   }
  }
  left[n]=isfinite(x)?fminf(16,fmaxf(-16,x)):0;right[n]=isfinite(y)?fminf(16,fmaxf(-16,y)):0;
 }
}
void sk_render(SKSynth *s,float *left,float *right,uint32_t frames){
 commands(s);
 for(uint32_t n=0;n<frames;n++){
  float bus[BUSES]={0};float sumL=0,sumR=0;
  for(int l=0;l<BUSES;l++)if(s->remaining[l]){s->gain[l]+=s->delta[l];if(!--s->remaining[l])s->gain[l]=s->target[l];}
  for(int i=0;i<VOICES;i++){
   Voice *v=&s->voices[i];if(!v->active)continue;
   if(s->customEnvelope[v->layer]){float *e=s->adsr[v->layer];
    if(v->releasing)v->env*=exp(-9.210340372/(s->rate*e[3]));
    else if(v->age<e[0])v->env=fminf(1,v->env+1/(s->rate*e[0]));
    else v->env=fmaxf(e[2],v->env-(1-e[2])/(s->rate*e[1]));
   }else{
   double attack=v->instrument==1?0.35:0.006;
   if(v->releasing)v->env*=exp(-1.0/(s->rate*(v->instrument==1?1.2:0.3)));
   else v->env=fminf(1,v->env+1.0/(s->rate*attack));
   }
   if(v->releasing&&v->env<0.0001){v->active=0;continue;}
   double p=v->phase;float sample;
   if(v->instrument==0)sample=(sin(p)+0.35*sin(2*p)*exp(-v->age*1.7)+0.13*sin(3*p)*exp(-v->age*3))*exp(-v->age*0.45);
   else if(v->instrument==1)sample=0.6*sin(p)+0.25*sin(v->phase2)+0.15*sin(p*2);
   else sample=(sin(p)+0.45*sin(p*3)+0.2*sin(p*7))*exp(-v->age*1.5);
   bus[v->layer]+=sample*v->env*v->velocity*0.14;
   v->phase=fmod(p+v->step,TAU);v->phase2=fmod(v->phase2+v->step*1.003,TAU);v->age+=1/s->rate;
  }
  // Soft output limiting; bounded for large chords and sustained layers.
  for(int l=0;l<BUSES;l++){
   float x=bus[l]*s->preGain[l];
   if(s->cutoff[l]<20000)x=process(&s->filter[l],x);
   for(int band=0;band<8;band++)x=process(&s->eq[l][band],x);
   if(s->compressEnabled[l]){float dry=x;x*=s->compressorInput[l];float level=fabsf(x),c=level>s->detector[l]?s->compAttack[l]:s->compRelease[l];s->detector[l]=c*s->detector[l]+(1-c)*level;float db=20*log10f(fmaxf(1e-9,s->detector[l]));float reduction=fmaxf(0,db-s->threshold[l])*(1-1/s->ratio[l]);x*=powf(10,-reduction/20);x=(dry*(1-s->compressorWet[l])+x*s->compressorWet[l])*powf(10,s->makeup[l]/20);}

   float spread=0;
   for(int k=0;k<3;k++)if(s->fxKind[l][k]){x=effectProcess(s,l,k,x);spread+=s->effect[l][k].stereo;}
   x*=s->gain[l];float pan=s->pan[l];sumL+=x*(pan>0?1-pan:1)*(1-fminf(1,fmaxf(0,spread)));sumR+=x*(pan<0?1+pan:1)*(1-fminf(1,fmaxf(0,-spread)));
  }
  if(s->clockEnabled){if(s->clockRemaining<=0){s->clockRemaining+=s->rate*60/s->clockTempo;s->clockEnvelope=0.1f;s->clockPhase=0;}s->clockRemaining--;float click=sin(s->clockPhase)*s->clockEnvelope;s->clockPhase+=TAU*1600/s->rate;s->clockEnvelope*=0.995f;sumL+=click;sumR+=click;}
  left[n]=tanhf(sumL);if(right)right[n]=tanhf(sumR);
 }
}
// Decode MIDI 1 UMP and MIDI 2 channel-voice note/CC messages. Packet traversal is C-native.
void sk_read_midi(const MIDIEventList *list,SKMIDIEvent callback,void *context){
 const MIDIEventPacket *p=&list->packet[0];
 for(uint32_t i=0;i<list->numPackets;i++,p=MIDIEventPacketNext(p)){
  for(uint32_t j=0;j<p->wordCount;){uint32_t w=p->words[j];unsigned type=w>>28;
   unsigned size=(type<=2||type==6||type==7)?1:(type==3||type==4||type==8||type==9||type==10)?2:4;
   if(j+size>p->wordCount)break;
   uint8_t status=(w>>16)&255,d1=(w>>8)&127,d2=w&127;
   if(type==2)callback(context,status,d1,d2);
   else if(type==4){unsigned kind=status&0xf0;uint32_t data=p->words[j+1];if(kind==0x90||kind==0x80)d2=(data>>25)&127;else if(kind==0xb0)d2=data>>25;else if(kind==0xc0){d1=(data>>24)&127;d2=0;}if(kind==0x90||kind==0x80||kind==0xb0||kind==0xc0)callback(context,status,d1,d2);}
   j+=size;
  }
 }
}
