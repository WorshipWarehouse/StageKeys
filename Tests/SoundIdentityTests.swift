import Foundation
@main struct SoundIdentityTests {
 static func main()throws {
 let store=PerformanceStore();store.setlist=Setlist();store.master=0.6;store.reverb=0
 for i in store.patch.layers.indices{store.removeSound(i)}
 try store.audio.prepareOffline();store.start()
 var captures:[[Float]]=[]
 for prefix in ["SK App Felt Piano","Touchstone Piano"] {
  guard let entry=store.librarySounds.first(where:{$0.name.hasPrefix(prefix) && $0.sound != nil}) else{fatalError("Missing fixture")}
  store.addLibrarySound(entry,index:0);store.setGain(0,0.6);store.noteOn(48,velocity:0.8)
  var samples:[Float]=[];var time=ProcessInfo.processInfo.systemUptime
  for _ in 0..<150 {time+=512.0/48000;store.midiFX.advance(to:time);store.audio.externalRack?.advanceBranches(to:time);let buffer=try store.audio.offlineBlock();samples += Array(UnsafeBufferPointer(start:buffer.floatChannelData![0],count:Int(buffer.frameLength)))}
  store.panic();captures.append(samples)
  print("SOUND IDENTITY",entry.name,"energy",samples.reduce(0){$0+Double($1*$1)},"peak",samples.map{abs($0)}.max()!)
 }
 for i in captures.indices {for j in 0..<i {let a=captures[i],b=captures[j];let aa=a.reduce(0){$0+Double($1*$1)},bb=b.reduce(0){$0+Double($1*$1)};let ab=zip(a,b).reduce(0){$0+Double($1.0*$1.1)};let correlation=abs(ab/sqrt(max(1e-20,aa*bb)));print("CORRELATION",i,j,correlation);assert(aa>0.000001 && bb>0.000001 && correlation<0.995,"Distinct presets rendered the same signal")}}
 assert(store.message==nil,store.message ?? "")
 print("PASS: distinct imported sound identity through production Store and audio graph")
 }
}
