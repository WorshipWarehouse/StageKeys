import AVFoundation
import Foundation
import Darwin
@main struct LivePianoFidelityTests {
 static func main()throws {
  setbuf(stdout,nil)
  guard let data=ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"],!data.contains("Application Support/StageKeys") else{fatalError("Use an isolated copy of the personal library")}
  var files=rlimit();getrlimit(RLIMIT_NOFILE,&files);let required=min(files.rlim_max,rlim_t(16384))
  let store=PerformanceStore();getrlimit(RLIMIT_NOFILE,&files);assert(files.rlim_cur>=required,"GUI streaming file budget was not established");store.setlist=Setlist();store.master=0.2;store.reverb=0;store.modWheel=0
  for i in store.patch.layers.indices{store.removeSound(i)}
  store.start()
  let names=["SK Felt Piano | Room","Touchstone Piano"]
  for (i,name) in names.enumerated(){guard let entry=store.librarySounds.first(where:{$0.name.hasPrefix(name) && $0.sound != nil}) else{fatalError("Missing personal fixture: \(name)")};store.addLibrarySound(entry,index:i)}
  func checkReferences(){for (i,count) in [222,9].enumerated(){let refs=store.audio.externalRack?.state(channel:i)?["file-references"] as? [String:String];assert(refs?.count==count,"Piano lost its sample mapping after graph reinitialization")}}
  checkReferences()
  // Rebuild processing while both sampler instruments are installed.
  var layer=store.patch.layers[1];layer.effects[0]=AudioEffect(kind:3,amount:0.2);store.commitLayer(1,layer);checkReferences()
  let lock=NSLock();var capture:[Float]=[];var takes:[[Float]]=[]
  store.audio.installPlaybackProbe{b in lock.lock();capture += Array(UnsafeBufferPointer(start:b.floatChannelData![0],count:Int(b.frameLength)));lock.unlock()}
  defer{store.audio.removePlaybackProbe();store.audio.stop()}
  for i in 0..<2 {
   store.panic();for channel in 0..<2{store.setGain(channel,channel==i ? 0.6:0)}
   lock.lock();capture=[];lock.unlock();store.noteOn(48,velocity:0.8)
   RunLoop.current.run(until:Date().addingTimeInterval(0.8));store.noteOff(48)
   lock.lock();let samples=Array(capture.prefix(24000));lock.unlock();let energy=samples.reduce(0.0){$0+Double($1*$1)}
   assert(energy>0.00001&&samples.allSatisfy(\.isFinite));takes.append(samples);checkReferences();print("LIVE PIANO",names[i],"energy",energy)
  }
  let a=takes[0],b=takes[1],aa=a.reduce(0.0){$0+Double($1*$1)},bb=b.reduce(0.0){$0+Double($1*$1)},ab=zip(a,b).reduce(0.0){$0+Double($1.0*$1.1)}
  let correlation=abs(ab/sqrt(aa*bb));assert(correlation<0.99,"Both piano layers became the same fallback tone")
  assert(store.message==nil,store.message ?? "");print("PASS: live Felt Room and Touchstone retain 222/9 sample mappings across effect graph rebuilds; distinct waveforms",correlation)
 }
}
