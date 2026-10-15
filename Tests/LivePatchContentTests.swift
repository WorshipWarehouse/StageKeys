import AVFoundation
import Foundation
import Darwin
/// This deliberately runs with live streaming, through Store MIDI and all channel
/// nodes. Offline direct-sampler checks alone cannot catch a playback-path fallback.
@main struct LivePatchContentTests {
 static func main()throws {
  setbuf(stdout,nil)
  guard let data=ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"], !data.contains("Application Support/StageKeys") else {fatalError("Use an isolated test data directory")}
  let root=URL(fileURLWithPath:data).appendingPathComponent("Imported Sounds");try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
  let store=PerformanceStore();store.setlist=Setlist();store.reverb=0;store.master=0.2;store.modWheel=0
  for i in store.patch.layers.indices{store.removeSound(i)}
  store.start()
  let lock=NSLock();var captured:[Float]=[]
  store.audio.installPlaybackProbe{b in lock.lock();captured += Array(UnsafeBufferPointer(start:b.floatChannelData![0],count:Int(b.frameLength)));lock.unlock()}
  defer{store.audio.removePlaybackProbe();store.audio.stop()}
  for (hz,kind):(Int,ExternalSound.Kind) in [(220,.samplerPreset),(880,.samplerPreset),(220,.sample),(880,.sample),(220,.samplerPreset)] {
   let file=root.appendingPathComponent("source-\(hz).wav"),buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!;buffer.frameLength=48000
   for c in 0..<2{for n in 0..<48000{let phase=Float(n)*2*Float.pi*Float(hz)/48000;buffer.floatChannelData![c][n]=0.12*(sin(phase)+0.4*sin(3*phase))}}
   try AVAudioFile(forWriting:file,settings:format.settings).write(from:buffer)
   let sampler=AVAudioUnitSampler();try sampler.loadAudioFiles(at:[file]);let preset=root.appendingPathComponent("source-\(hz).aupreset");try PropertyListSerialization.data(fromPropertyList:sampler.auAudioUnit.fullStateForDocument!,format:.xml,options:0).write(to:preset)
   let entry=LibrarySound(id:"live-\(hz)",name:"Source \(hz)",collection:"Test",sound:ExternalSound(kind:kind,name:"Source \(hz)",fileName:kind == .sample ? file.lastPathComponent:preset.lastPathComponent))
   store.addLibrarySound(entry,index:0);store.setGain(0,0.6)
   assert((store.audio.externalRack?.state(channel:0)?["file-references"] as? [String:String])?.values.contains(file.path)==true,"Graph rebuild discarded the sample references")
   store.panic();lock.lock();captured=[];lock.unlock()
   store.noteOn(60,velocity:0.8)
   RunLoop.current.run(until:Date().addingTimeInterval(0.8));store.noteOff(60)
   lock.lock();let samples=Array(captured.dropFirst(4096).prefix(24000));lock.unlock()
   func power(_ f:Double)->Double {var r=0.0,i=0.0;for (n,v) in samples.enumerated(){let p=2*Double.pi*f*Double(n)/48000;r+=Double(v)*cos(p);i+=Double(v)*sin(p)};return r*r+i*i}
   let source=power(Double(hz)),partial=power(Double(hz*3)),fallback=power(261.625565)
   print("LIVE SOURCE",hz,"fundamental",source,"partial",partial,"fallback",fallback,"message",store.message ?? "none")
   assert(samples.count>12000 && source>0.01 && source>fallback*100 && partial>source*0.05,"Live patch lost its referenced waveform or became a generic sine")
   assert(store.message==nil,store.message ?? "")
  }
  print("PASS: live patch hot-swaps preserve referenced pitch and upper harmonics through Store MIDI and the production effect graph")
 }
}
