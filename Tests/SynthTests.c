#include "../Sources/Synth.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#define N 512
static float left[N],right[N];
static double render(SKSynth *s,int blocks) {
 double energy=0;
 for(int b=0;b<blocks;b++){sk_render(s,left,right,N);for(int i=0;i<N;i++){assert(isfinite(left[i]));assert(fabsf(left[i])<=1);assert(left[i]==right[i]);energy+=left[i]*left[i];}}
 return energy;
}
static void event(void *ctx,uint8_t status,uint8_t a,uint8_t b){int *count=ctx;assert(status==0x90);assert(a==60);assert(b==100);(*count)++;}
int main(void){
 SKSynth *s=sk_create(48000);assert(s);
 assert(render(s,1)==0);
 for(int instrument=0;instrument<3;instrument++){
  sk_note_on(s,60,60,instrument,0,0.8);assert(render(s,100)>0.1);
  sk_note_off(s,60);render(s,1500);assert(render(s,1)<1e-8);
 }
 sk_sustain(s,1);sk_note_on(s,60,60,1,0,0.8);render(s,100);sk_note_off(s,60);assert(render(s,100)>0.1);
 sk_sustain(s,0);render(s,1500);assert(render(s,1)<1e-8);
 // A held key uses the original identity even when its pitch was transposed.
 sk_note_on(s,188,72,1,0,0.8);render(s,80);sk_note_off(s,188);render(s,1500);assert(render(s,1)<1e-8);
 sk_note_on(s,60,60,1,0,0.8);render(s,100);sk_gain(s,0,0,0.1);render(s,20);assert(render(s,1)<1e-8);sk_panic(s);render(s,1);
 sk_gain(s,0,0.5,0);sk_note_on(s,60,60,1,0,0.8);render(s,100);sk_panic(s);assert(render(s,1)==0);
 // Overflow must recover silently rather than lose a note-off and hang a voice.
 for(int i=0;i<3000;i++)sk_note_on(s,i,60,1,0,1);assert(render(s,1)==0);
 // Stress the fixed voice pool with more than 96 simultaneous notes.
 for(int i=0;i<150;i++)sk_note_on(s,i,60+i%24,i%3,0,1);assert(render(s,30)>0.1);sk_panic(s);assert(render(s,1)==0);
 MIDIEventList list;MIDIEventPacket *packet=MIDIEventListInit(&list,kMIDIProtocol_1_0);UInt32 word=0x20903c64;assert(MIDIEventListAdd(&list,sizeof(list),packet,0,1,&word));int count=0;sk_read_midi(&list,event,&count);assert(count==1);
 sk_destroy(s);puts("PASS: instruments, release, sustain, transpose identity, fades, panic, overflow, voice bounds, MIDI UMP");
}
