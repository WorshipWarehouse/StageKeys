import Foundation
import AVFoundation
import Darwin
@main struct SamplerContentTests {
 static func main()throws {
  setbuf(stdout,nil)
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
  let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
  for frequency in [220,880] {
   let name="Tone\(frequency).wav",buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!;buffer.frameLength=48000
   for c in 0..<2 {for f in 0..<48000{buffer.floatChannelData![c][f]=0.15*sin(Float(f)*2*Float.pi*Float(frequency)/48000)}}
   try AVAudioFile(forWriting:root.appendingPathComponent(name),settings:format.settings).write(from:buffer)
   let xml="<Ableton><AbletonDevicePreset><Device><OriginalSimpler><Player><MultiSampleMap><SampleParts><MultiSamplePart><RootKey Value=\"60\"/><SampleStart Value=\"0\"/><SampleEnd Value=\"47999\"/><SampleRef><FileRef><Name Value=\"\(name)\"/></FileRef></SampleRef></MultiSamplePart></SampleParts></MultiSampleMap></Player><VolumeAndPan><VolumeVelScale><Manual Value=\"0.25\"/></VolumeVelScale></VolumeAndPan><Filter><IsOn><Manual Value=\"true\"/></IsOn><Slot><Value><SimplerFilter><Type><Manual Value=\"0\"/></Type><Freq><Manual Value=\"2754\"/></Freq><Res><Manual Value=\"0\"/></Res></SimplerFilter></Value></Slot></Filter></OriginalSimpler></Device></AbletonDevicePreset></Ableton>"
   let preset=root.appendingPathComponent("\(frequency).aupreset"),source=root.appendingPathComponent("\(frequency).adg");try Data(xml.utf8).write(to:source);_ = try AbletonImport.convert(source,sampleRoot:root,to:preset)
   let state=try PropertyListSerialization.propertyList(from:Data(contentsOf:preset),options:[],format:nil) as! [String:Any],layer=(state["Instrument"] as! [String:Any])["Layers"] as! [[String:Any]]
   assert((layer[0]["LFOs"] as! [[String:Any]]).allSatisfy{($0["enabled"] as? Bool)==false})
   assert((layer[0]["Filters"] as! [String:Any])["cutoff"] as! Double == 2754)
   let velocity=(layer[0]["Connections"] as! [[String:Any]]).first{($0["source"] as? Int)==301 && ($0["destination"] as? Int)==1343225856}!
   assert(velocity["scale"] as! Double == -24)

   let engine=AVAudioEngine(),sampler=AVAudioUnitSampler();engine.attach(sampler);engine.connect(sampler,to:engine.mainMixerNode,format:format);try SamplerRendering.configure(sampler,offline:true);try sampler.loadInstrument(at:preset)
   try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:512);try engine.start();sampler.startNote(60,withVelocity:100,onChannel:0)
   let output=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:512)!;var last:Float=0,crossings=0,frames=0
   for block in 0..<80 {try engine.renderOffline(512,to:output);if block>5 {for f in 0..<Int(output.frameLength){let value=output.floatChannelData![0][f];if value*last<0{crossings+=1};last=value;frames+=1}}}
   let measured=Double(crossings)*48000/Double(frames)/2;print("SOURCE FREQUENCY",frequency,"RENDERED",measured);assert(abs(measured-Double(frequency))<3,"Sampler rendered a fallback tone instead of the referenced waveform")
   engine.stop()
  }
  print("PASS: imported sampler output follows the referenced source waveform")
 }
}
