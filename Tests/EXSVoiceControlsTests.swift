import Foundation
import AVFoundation
@main struct EXSVoiceControlsTests {
 static func main()throws {
  let values:[(UInt8,Int16)]=[(7,-6),(15,-7),(0x2c,1),(0xf3,0),(0x1e,0),(0x1d,0),(0x2e,100),(0xad,8),(0xae,-3),(0xaf,-1),(0xb0,1000),(0xb1,1000)]
  var data=Data([UInt8(values.count),0,0,0]);data.append(contentsOf:values.map(\.0));for (_,value) in values {var v=value.littleEndian;withUnsafeBytes(of:&v){data.append(contentsOf:$0)}}
  var notes=Set<String>();let controls=try EXSNative.voiceControls([.init(kind:4,modern:true,index:0,name:"Parameters",body:[UInt8](data))],notes:&notes)!
  assert(controls.gain == -6 && controls.tuning == -7 && controls.filter?.routes.count==2 && controls.valid)
  var invalid=controls;invalid.filter?.routes[0].amount = .nan;assert(!invalid.valid)
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
  let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!,wave=root.appendingPathComponent("two-tones.wav")
  let pcm=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!;pcm.frameLength=48000
  for i in 0..<48000 {pcm.floatChannelData![0][i]=0.05*(sin(Float(i)*2 * .pi*500/48000)+sin(Float(i)*2 * .pi*8000/48000))}
  do{let f=try AVAudioFile(forWriting:wave,settings:format.settings);try f.write(from:pcm)}
  let originalBytes=try Data(contentsOf:wave)
  let seed=AVAudioUnitSampler();try seed.loadAudioFiles(at:[wave]);let template=seed.auAudioUnit.fullStateForDocument!
  var group=[UInt8](repeating:0,count:120);group[41]=20
  func render(_ model:EXSNative.VoiceControls,_ velocity:UInt8,envelope:EXSNative.Envelope?=nil,smoothing:Float=0,onset:Bool=false)throws->[Float] {
   let sampler=AVAudioUnitSampler(),engine=AVAudioEngine();engine.attach(sampler);engine.connect(sampler,to:engine.mainMixerNode,format:format)
   try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:512);try SamplerRendering.configure(sampler,offline:true)
   var state=template,inst=state["Instrument"] as! [String:Any],layer=(inst["Layers"] as! [[String:Any]])[0],zones=layer["Zones"] as! [[String:Any]]
   zones[0]["root key"]=60;zones[0]["min key"]=0;zones[0]["max key"]=127;layer["Zones"]=zones
   if let envelope {EXSNative.applyEnvelope(envelope,group:group,to:&layer)}
   EXSNative.applyVoiceControls(model,envelope:envelope,group:group,to:&layer)
   inst["Layers"]=[layer];state["Instrument"]=inst
   let file=root.appendingPathComponent("render.aupreset");try PropertyListSerialization.data(fromPropertyList:SamplerAttack.prepare(state,minimum:smoothing),format:.xml,options:0).write(to:file);try sampler.loadInstrument(at:file)
   engine.prepare();try engine.start();defer{engine.stop()};let b=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:512)!
   for _ in 0..<8{_ = try engine.renderOffline(512,to:b)}
   sampler.startNote(60,withVelocity:velocity,onChannel:0);var x:[Float]=[]
   for _ in 0..<40{_ = try engine.renderOffline(512,to:b);x+=Array(UnsafeBufferPointer(start:b.floatChannelData![0],count:Int(b.frameLength)))}
   assert(x.allSatisfy(\.isFinite));return onset ? Array(x.prefix(2048)):Array(x[4096..<16384])
  }
  func magnitude(_ x:[Float],_ hz:Double)->Double {
   var re=0.0,im=0.0
   for (i,v) in x.enumerated(){let angle=2*Double.pi*hz*Double(i)/48000;re+=Double(v)*cos(angle);im+=Double(v)*sin(angle)}
   return hypot(re,im)/Double(x.count)
  }
  var clean=controls;clean.gain=0;clean.tuning=0;clean.filter=nil
  let dry=try render(clean,83);var quiet=clean;quiet.gain = -6;let attenuated=try render(quiet,83)
  let ratio=magnitude(attenuated,500)/magnitude(dry,500);assert(abs(ratio-pow(10,-6.0/20))<0.005,"Source level is not active: \(ratio)")
  var tuned=clean;tuned.tuning = -7;let pitched=try render(tuned,83)
  let peak=(480...510).map{Double($0)}.max{magnitude(pitched,$0)<magnitude(pitched,$1)}!
  assert(abs(peak-500*pow(2,-7.0/1200))<1.1,"Source tuning is not active: \(peak)")
  var filtered=controls;filtered.gain=0;filtered.tuning=0
  let soft=try render(filtered,50),hard=try render(filtered,110)
  let softBalance=magnitude(soft,8000)/magnitude(soft,500),hardBalance=magnitude(hard,8000)/magnitude(hard,500)
  assert(softBalance<hardBalance*0.4 && hardBalance>0.005,"Velocity must open the per-voice filter: \(softBalance) / \(hardBalance)")
  let envelope=EXSNative.Envelope(attack:0,lowVelocityAttack:0.005,decay:10,sustain:1,release:0.2)
  func onsetRatio(_ x:[Float])->Double {
   let early=x.prefix(96).reduce(0.0){$0+Double($1*$1)}/96
   let body=x.suffix(512).reduce(0.0){$0+Double($1*$1)}/512
   return early/max(body,1e-20)
  }
  let slow=onsetRatio(try render(clean,20,envelope:envelope,onset:true)),fast=onsetRatio(try render(clean,120,envelope:envelope,onset:true))
  assert(fast>slow*2 && fast>0.05,"Original velocity-dependent attack must be active without a fixed delay: \(slow) / \(fast)")
  let smoothed=onsetRatio(try render(clean,120,envelope:envelope,smoothing:0.04,onset:true))
  assert(smoothed<fast*0.1,"Explicit attack smoothing must override the velocity factor")
  print("PASS: velocity attack endpoint processing and explicit smoothing override",slow,fast,smoothed)
  var layer:[String:Any]=["ID":3,"Zones":[["gain":-2,"fine tune":4]],"Connections":[]]
  EXSNative.applyVoiceControls(controls,envelope:nil,group:group,to:&layer)
  let routes=layer["Connections"] as! [[String:Any]]
  assert(routes.allSatisfy{($0["destination"] as! Int)==EXSNative.cutoffDestination+3*256})
  assert((routes[0]["min value"] as! Double)>0,"Signed group cutoff offset must be retained")
  let zones=layer["Zones"] as! [[String:Any]];assert(zones[0]["gain"] as! Double == -8 && zones[0]["fine tune"] as! Double == -3)
  let retained=try Data(contentsOf:wave);assert(retained==originalBytes)
  print("PASS: generic EXS parameter decoding, active gain/tuning and velocity-sensitive filter; soft/hard HF balance",softBalance,hardBalance)
 }
}
