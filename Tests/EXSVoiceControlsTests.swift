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
  let endpoints:[(UInt8,Int16)]=[(0x5a,-52),(0x59,0)]
  var endpointData=Data([2,0,0,0]);endpointData.append(contentsOf:endpoints.map(\.0))
  for (_,value) in endpoints {var v=value.littleEndian;withUnsafeBytes(of:&v){endpointData.append(contentsOf:$0)}}
  var endpointNotes=Set<String>();let endpointModel=try EXSNative.voiceControls([.init(kind:4,modern:true,index:0,name:"Source endpoints",body:[UInt8](endpointData))],notes:&endpointNotes)
  assert(endpointModel?.amplitudeVelocity?.sensitivity == -52 && endpointModel?.amplitudeVelocity?.high==0)
  var amplitude=clean;amplitude.amplitudeVelocity = .init(sensitivity:-52,high:0)
  let defaultSoft=try render(clean,38),sourceSoft=try render(amplitude,38),defaultHard=try render(clean,127),sourceHard=try render(amplitude,127)
  let softGain=magnitude(sourceSoft,500)/magnitude(defaultSoft,500),hardGain=magnitude(sourceHard,500)/magnitude(defaultHard,500)
  assert(abs(softGain-1.3926)<0.03 && abs(hardGain-1)<0.03,"Source velocity sensitivity must raise soft notes without boosting the maximum: \(softGain), \(hardGain)")
  let savedAmplitude=try JSONDecoder().decode(EXSNative.VoiceControls.self,from:JSONEncoder().encode(amplitude));assert(savedAmplitude==amplitude)
  print("PASS: source amplitude velocity endpoints, rendered soft/hard level response and persistence",softGain,hardGain)
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
  let sourceRoot=root.appendingPathComponent("mainstage-source",isDirectory:true)
  let outputRoot=root.appendingPathComponent("converted",isDirectory:true)
  try FileManager.default.createDirectory(at:outputRoot,withIntermediateDirectories:true)
  let source=try TestFixtures.exs(in:sourceRoot)
  let shaping:[(UInt8,Int16)]=[(0x52,64),(0x53,0),(0x54,32),(0x51,80),(0x55,64),(0x6b,2),
                               (0x2c,1),(0xf3,2),(0x1e,600),(0x1d,300)]
  func parameterChunk(_ values:[(UInt8,Int16)])->Data {
   var body:[UInt8]=[UInt8(values.count),0,0,0]
   body.append(contentsOf:values.map(\.0))
   for (_,value) in values {var v=value.littleEndian;withUnsafeBytes(of:&v){body.append(contentsOf:$0)}}
   var header=[UInt8](repeating:0,count:84),signature=UInt32(4<<24)|0x101,size=UInt32(body.count)
   var signatureLE=signature.littleEndian,sizeLE=size.littleEndian
   withUnsafeBytes(of:&signatureLE){header.replaceSubrange(0..<4,with:$0)}
   withUnsafeBytes(of:&sizeLE){header.replaceSubrange(4..<8,with:$0)}
   header.replaceSubrange(16..<20,with:Array("JBOS".utf8))
   header.replaceSubrange(20..<30,with:Array("Parameters".utf8))
   return Data(header+body)
  }
  var sourceBytes=try Data(contentsOf:source);sourceBytes.append(parameterChunk(shaping));try sourceBytes.write(to:source)
  let converted=outputRoot.appendingPathComponent("Supported.aupreset")
  let convertedProgram=try EXSNative.convert(source,sampleRoot:sourceRoot,to:converted)
  let preset=try PropertyListSerialization.propertyList(from:Data(contentsOf:converted),options:[],format:nil) as! [String:Any]
  let program=try JSONDecoder().decode(NativeSamplerProgram.self,from:preset["StageKeys.NativeSampler"] as! Data)
  assert(program.amplitudeEnvelope?.attack==EXSNative.Envelope.seconds(64) && program.amplitudeEnvelope?.sustain==Double(80)/127)
  assert(program.voiceControls?.filter?.cutoff==0.6 && program.voiceControls?.filter?.resonance==0.3)
  assert(convertedProgram.notes.contains{$0.contains("amplitude attack, decay, sustain and release are translated")})
  assert(convertedProgram.notes.contains{$0.contains("low-pass cutoff, resonance")})
  var instrument=preset["Instrument"] as! [String:Any],layers=instrument["Layers"] as! [[String:Any]]
  let convertedLayer=layers[0],filter=convertedLayer["Filters"] as! [String:Any]
  assert(filter["enabled"] as? Bool==true && filter["resonance"] as? Double==3)
  let stages=((convertedLayer["Envelopes"] as! [[String:Any]])[0]["Stages"] as! [[String:Any]])
  assert(stages.first{$0["stage"] as? Int==1}?["time"] as? Double==EXSNative.Envelope.seconds(64))
  assert(stages.first{$0["stage"] as? Int==3}?["time"] as? Double==EXSNative.Envelope.seconds(32))
  let unsupportedRoot=root.appendingPathComponent("unsupported-source",isDirectory:true)
  let unsupportedSource=try TestFixtures.exs(in:unsupportedRoot)
  var unsupportedBytes=try Data(contentsOf:unsupportedSource),unsupported=shaping
  unsupported[unsupported.firstIndex{$0.0==0xf3}!] = (0xf3,1)
  unsupportedBytes.append(parameterChunk(unsupported));try unsupportedBytes.write(to:unsupportedSource)
  let unsupportedNotes=try EXSNative.convert(unsupportedSource,sampleRoot:unsupportedRoot,to:outputRoot.appendingPathComponent("Unsupported.aupreset"))
  assert(unsupportedNotes.notes.contains{$0.contains("filter circuit") && $0.contains("not translated")},
         "An unsupported source filter circuit must be named instead of using the default filter silently")
  func renderPreset(_ url:URL,key:UInt8)throws->[Float] {
   let sampler=AVAudioUnitSampler(),engine=AVAudioEngine();engine.attach(sampler);engine.connect(sampler,to:engine.mainMixerNode,format:format)
   try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:512);try SamplerRendering.configure(sampler,offline:true)
   try sampler.loadInstrument(at:url);engine.prepare();try engine.start();defer{engine.stop()}
   let b=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:512)!
   for _ in 0..<8{_ = try engine.renderOffline(512,to:b)}
   sampler.startNote(key,withVelocity:100,onChannel:0);var x:[Float]=[]
   for _ in 0..<40{_ = try engine.renderOffline(512,to:b);x+=Array(UnsafeBufferPointer(start:b.floatChannelData![0],count:Int(b.frameLength)))}
   sampler.stopNote(key,onChannel:0)
   assert(x.allSatisfy(\.isFinite));return Array(x[4096..<16384])
  }
  func peakFrequency(_ x:[Float])->Double {(200...900).map{Double($0)}.max{magnitude(x,$0)<magnitude(x,$1)}!}
  // EXS Transpose moves the zones as well as the pitch. Translating it as a
  // cents offset would keep the authored zone answering a boundary key.
  let plainRoot=root.appendingPathComponent("plain-source",isDirectory:true)
  let plainSource=try TestFixtures.exs(in:plainRoot),plain=outputRoot.appendingPathComponent("Plain.aupreset")
  let plainProgram=try EXSNative.convert(plainSource,sampleRoot:plainRoot,to:plain)
  assert(plainProgram.voiceControls?.transpose==nil && plainProgram.groups[0].low==0 && plainProgram.groups[0].high==127)
  let plainPeak=peakFrequency(try renderPreset(plain,key:60))
  assert(abs(plainPeak-261.63)<2,"Untransposed playback must stay at the authored pitch: \(plainPeak)")
  // A parameters chunk must carry a supported amplitude envelope, otherwise the
  // converter correctly refuses the whole layout before any transpose applies.
  let envelopeParameters:[(UInt8,Int16)]=[(0x52,0),(0x53,0),(0x54,0),(0x51,127),(0x55,0),(0x6b,2)]
  let upRoot=root.appendingPathComponent("transpose-up-source",isDirectory:true)
  let upSource=try TestFixtures.exs(in:upRoot)
  var upBytes=try Data(contentsOf:upSource);upBytes.append(parameterChunk(envelopeParameters+[(0x2d,12)]));try upBytes.write(to:upSource)
  let up=outputRoot.appendingPathComponent("Transposed.aupreset")
  let upProgram=try EXSNative.convert(upSource,sampleRoot:upRoot,to:up)
  assert(upProgram.voiceControls?.transpose==12 && upProgram.voiceControls?.tuning==0,
         "Instrument transpose must not be translated as a cents offset")
  assert(upProgram.groups[0].low==0 && upProgram.groups[0].high==115)
  let upState=try PropertyListSerialization.propertyList(from:Data(contentsOf:up),options:[],format:nil) as! [String:Any]
  let upZones=(((upState["Instrument"] as! [String:Any])["Layers"] as! [[String:Any]])[0]["Zones"] as! [[String:Any]])
  assert(upZones.count==1 && upZones[0]["min key"] as? Int==0 && upZones[0]["max key"] as? Int==115 &&
         upZones[0]["root key"] as? Int==48 && (upZones[0]["fine tune"] as? NSNumber)?.doubleValue==0,
         "Transpose must move the zone range and root key without adding a cents offset")
  let upPeak=peakFrequency(try renderPreset(up,key:60))
  assert(abs(upPeak-523.25)<4,"Source transpose must move the pitch with the zone map: \(upPeak)")
  let flatRoot=root.appendingPathComponent("transpose-flat-source",isDirectory:true)
  let flatSource=try TestFixtures.exs(in:flatRoot)
  var flatBytes=try Data(contentsOf:flatSource);flatBytes.append(parameterChunk(envelopeParameters+[(0x2d,-7)]));try flatBytes.write(to:flatSource)
  let flat=outputRoot.appendingPathComponent("Flat.aupreset")
  let flatProgram=try EXSNative.convert(flatSource,sampleRoot:flatRoot,to:flat)
  assert(flatProgram.voiceControls?.transpose==(-7) && flatProgram.groups[0].low==7 && flatProgram.groups[0].high==127)
  let flatPeak=peakFrequency(try renderPreset(flat,key:60))
  assert(abs(flatPeak-261.63*pow(2,-7.0/1200))<2,"Negative transpose must lower the played key: \(flatPeak)")
  var overNotes=Set<String>()
  do{_ = try EXSNative.voiceControls([.init(kind:4,modern:true,index:0,name:"Out of range",body:Array(parameterChunk([(0x2d,100)])[84...]))],notes:&overNotes);fatalError("Out-of-range transpose accepted")}catch{}
  print("PASS: generic EXS parameter decoding, active gain/tuning and velocity-sensitive filter; soft/hard HF balance",softBalance,hardBalance)
  print("PASS: instrument transpose moves zone selection and pitch",plainPeak,upPeak,flatPeak)
 }
}
