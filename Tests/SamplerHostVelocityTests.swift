import Foundation
import AVFoundation
@main struct SamplerHostVelocityTests {
 static func main()throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
  let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!,wave=root.appendingPathComponent("original.wav"),pcm=AVAudioPCMBuffer(pcmFormat:AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!,frameCapacity:48000)!
  pcm.frameLength=48000;for i in 0..<48000 {pcm.floatChannelData![0][i]=0.02*sin(Float(i)*2 * .pi*500/48000)}
  do{let file=try AVAudioFile(forWriting:wave,settings:format.settings);try file.write(from:pcm)}
  let bytes=try Data(contentsOf:wave),seed=AVAudioUnitSampler();try seed.loadAudioFiles(at:[wave])
  var original=seed.auAudioUnit.fullStateForDocument!,instrument=original["Instrument"] as! [String:Any],layer=(instrument["Layers"] as! [[String:Any]])[0]
  let amp=EXSNative.VoiceControls.AmplitudeVelocity(sensitivity:-52,high:0);EXSNative.applyAmplitudeVelocity(amp,to:&layer)
  var zones=layer["Zones"] as! [[String:Any]]
  for i in zones.indices {zones[i]["gain"]=0.0;zones[i]["min vel"]=0;zones[i]["max vel"]=127;zones[i]["root key"]=60}
  layer["Zones"]=zones;instrument["Layers"]=[layer];original["Instrument"]=instrument
  let model=EXSNative.VoiceControls(amplitudeVelocity:amp,gain:0,tuning:0),program=NativeSamplerProgram(groups:[.init(name:"Fixture",layer:0,low:0,high:127,velocityLow:0,velocityHigh:127)],notes:[],voiceControls:model)
  original["StageKeys.NativeSampler"]=try JSONEncoder().encode(program)
  let old=NSDictionary(dictionary:original)
  func render(_ curve:Int,_ velocity:UInt8)throws->Double {
   let state=try SamplerHostVelocity.prepare(original,curve:curve),engine=AVAudioEngine(),sampler=AVAudioUnitSampler()
   engine.attach(sampler);engine.connect(sampler,to:engine.mainMixerNode,format:format);try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:512);try SamplerRendering.configure(sampler,offline:true)
   let file=root.appendingPathComponent("\(curve).aupreset");try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:file);try sampler.loadInstrument(at:file);try engine.start();defer{engine.stop()}
   sampler.startNote(60,withVelocity:velocity,onChannel:0)
   let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:512)!;var energy=0.0
   for block in 0..<20 {_ = try engine.renderOffline(512,to:buffer);if block>4 {for i in 0..<Int(buffer.frameLength){let x=Double(buffer.floatChannelData![0][i]);assert(x.isFinite);energy+=x*x}}};return sqrt(energy)
  }
  // Independent measured MainStage ratios, never calculated from the implementation.
  let expected=[-20:[6.821458,6.474113,5.103445,3.154371],-10:[4.196234,4.321726,3.560263,2.279690],10:[-3.205452,-4.344464,-4.372236,-3.434513]]
  for (i,v) in [38,64,83,102].enumerated(){let dry=try render(0,UInt8(v));for curve in [-20,-10,10] {let wet=try render(curve,UInt8(v)),db=20*log10(wet/dry);assert(abs(db-expected[curve]![i])<0.005,"Host gain mismatch: \(curve), \(v), \(db)")}}
  let prepared=try SamplerHostVelocity.prepare(original,curve:-10),newLayer=((prepared["Instrument"] as! [String:Any])["Layers"] as! [[String:Any]])[0]
  assert(NSArray(array:newLayer["Connections"] as! [[String:Any]])==NSArray(array:layer["Connections"] as! [[String:Any]]))
  assert(NSDictionary(dictionary:prepared["file-references"] as! [String:String])==NSDictionary(dictionary:original["file-references"] as! [String:String]))
  let expanded=newLayer["Zones"] as! [[String:Any]];assert(expanded.count==zones.count*128)
  for zone in expanded {assert(zone["waveform"] as? Int == zones[0]["waveform"] as? Int);assert(zone["root key"] as? Int==60)}
  let repeated=try SamplerHostVelocity.prepare(prepared,curve:-10);assert(NSDictionary(dictionary:repeated)==NSDictionary(dictionary:prepared));assert(NSDictionary(dictionary:original)==old)
  let retained=try Data(contentsOf:wave);assert(retained==bytes)
  print("PASS: rendered measured host gains, untouched velocity/filter routes, sample bytes, references and idempotence")
 }
}
