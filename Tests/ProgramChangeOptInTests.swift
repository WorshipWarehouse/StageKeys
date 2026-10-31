import Foundation
import CoreMIDI
@main struct ProgramChangeOptInTests {
 static func main() throws {
  let store=PerformanceStore();store.setlist=TestFixtures.setlist();store.primarySourceID = -1;store.midiChannel = -1;store.secondarySourceID = -2
  try store.audio.prepareOffline();store.start();defer{store.audio.stop()}
  var client=MIDIClientRef(),source=MIDIEndpointRef()
  assert(MIDIClientCreateWithBlock("StageKeys Program Change Contract" as CFString,&client,nil)==noErr)
  defer{if source != 0{MIDIEndpointDispose(source)};MIDIClientDispose(client)}
  assert(MIDISourceCreate(client,"Power-on Sequence Fixture" as CFString,&source)==noErr)
  func wait(_ predicate:()->Bool){let end=Date().addingTimeInterval(3);while !predicate() && Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};assert(predicate())}
  wait{store.midiSources.contains{$0.endpoint==source}}
  store.primarySourceID=store.midiSources.first{$0.endpoint==source}!.id
  func send(_ status:UInt8,_ a:UInt8,_ b:UInt8=0){
   store.midiLog=[]
   var list=MIDIPacketList()
   withUnsafeMutablePointer(to:&list){p in
    let packet=MIDIPacketListInit(p);let bytes:[UInt8]=status&0xf0==0xc0 ? [status,a]:[status,a,b]
    bytes.withUnsafeBufferPointer{_ = MIDIPacketListAdd(p,MemoryLayout<MIDIPacketList>.size,packet,0,bytes.count,$0.baseAddress!)}
    assert(MIDIReceived(source,p)==noErr)
   }
   wait{!store.midiLog.isEmpty}
  }
  // Legacy absent flags survive decoding; runtime semantics are explicitly off.
  let legacy=try JSONDecoder().decode(Setlist.self,from:JSONEncoder().encode(store.setlist))
  assert(legacy.patches.allSatisfy{$0.programChangeEnabled == nil})
  store.setlist=legacy;store.choose(1);store.captureSnapshot(0)
  let id=store.patch.id,snapshot=store.activeSnapshot,tempo=store.patch.tempo,layers=store.patch.layers.map(\.id)
  send(0xc0,0);send(0xc0,2)
  assert(store.patch.id==id && store.activeSnapshot==snapshot && store.patch.tempo==tempo && store.patch.layers.map(\.id)==layers)
  send(0x90,72,100);assert(store.isNoteHeld(72))
  send(0xb0,64,127);assert(store.sustain);send(0x80,72);send(0xb0,64,0);assert(!store.sustain && store.held.isEmpty)
  store.setlist.patches[0].programChangeEnabled=true;store.setlist.patches[0].programChangeNumber=99
  store.patchLock=true;send(0xc0,99);assert(store.patch.id==id && store.activeSnapshot==snapshot)
  store.patchLock=false;send(0xc0,99);assert(store.selected==0)
  store.choose(1);store.setlist.patches[0].programChangeEnabled=false;send(0xc0,99);assert(store.selected==1)
  store.setlist.patches[0].programChangeEnabled=true
  store.midiChannel=1;send(0xc0,99);assert(store.selected==1);send(0xc1,99);assert(store.selected==0)
  let roundTrip=try JSONDecoder().decode(Setlist.self,from:JSONEncoder().encode(store.setlist))
  assert(roundTrip.patches[0].programChangeEnabled==true && roundTrip.patches[0].programChangeNumber==99 && roundTrip.patches[1].programChangeEnabled==nil)
  // Patch Settings display/mapping policy: raw MIDI 0...127 stored, 1...128 labelled.
  assert(ProgramChangeMapping.isValid(0) && ProgramChangeMapping.isValid(127))
  assert(!ProgramChangeMapping.isValid(nil) && !ProgramChangeMapping.isValid(-1) && !ProgramChangeMapping.isValid(128))
  assert(ProgramChangeMapping.label(0)==1 && ProgramChangeMapping.label(127)==128 && ProgramChangeMapping.value(fromLabel:1)==0 && ProgramChangeMapping.value(fromLabel:128)==127)
  let policy=ProgramChangeMapping.explanation(41)
  assert(policy.contains("41") && policy.contains("42"),"The off-by-one explanation must name both numbering schemes")
  store.setlist=TestFixtures.setlist();store.choose(0);store.midiChannel = -1
  store.setProgramChangeEnabled(true)
  assert(store.setlist.patches[0].programChangeNumber == 0)
  store.choose(1);store.setProgramChangeEnabled(true);assert(store.setlist.patches[1].programChangeNumber == 1)
  store.setProgramChangeNumber(42);assert(store.setlist.patches[1].programChangeNumber == 42)
  store.setlist.patches[0].programChangeNumber=1
  store.setlist.patches[1].programChangeNumber=nil;store.setProgramChangeEnabled(false);store.setProgramChangeEnabled(true)
  assert(store.setlist.patches[1].programChangeNumber == 0)

  // Patch key direction, octave shift and tempo lock through the same live path.
  store.midiChannel = -1
  store.panic()
  store.setlist.patches[0].tempoLocked=false;store.setlist.patches[0].tempo=96;store.liveTempo=132
  store.choose(1);store.choose(0)
  assert(store.performedTempo==132,"An unlocked patch keeps the live tempo across a patch change")
  store.updateTempo(108);assert(store.liveTempo==108 && store.patch.tempo==108)
  store.setTempoLocked(true);store.setlist.patches[1].tempo=64;store.choose(1)
  assert(store.performedTempo==64,"A locked patch recalls its own tempo")
  store.setPlayKey(2);store.setHearKey(0);store.setKeyDirection(.nearest);store.setOctaveShift(0)
  assert(store.patch.transpose == -2 && store.patch.octaveShiftResolved == 0)
  store.setOctaveShift(1);assert(store.patch.transpose == 10,"The octave shift moves the sounding key by 12 semitones")
  send(0x90,74,100);assert(store.isNoteHeld(74))
  send(0xb0,64,127);assert(store.sustain);send(0x80,74);send(0xb0,64,0);assert(!store.sustain && store.held.isEmpty)
  store.setOctaveShift(0);assert(store.patch.transpose == -2,"Returning the octave restores the original transposition")
  print("PASS: legacy/unconfigured Program Change ignored; explicit mapping and numbering policy verified")
  print("PASS: live MIDI path keeps the shared live tempo, recalls a locked patch tempo, and applies Play In/Hear In direction and octave shift with sustain")
 }
}
