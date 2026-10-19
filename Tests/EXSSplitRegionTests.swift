import Foundation
import AVFoundation
@main struct EXSSplitRegionTests {
 static func main()throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
  let format=AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:48000,channels:1,interleaved:true)!
  let pcm=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:105600)!;pcm.frameLength=105600
  let samples=pcm.int16ChannelData![0]
  for i in 0..<105600 {let amplitude:Double=i<48000 ? 4000:(i<96000 ? 26000:2000);samples[i]=Int16(amplitude*sin(Double(i)*2 * .pi*400/48000))}
  let source=root.appendingPathComponent("consolidated.caf")
  do{let file=try AVAudioFile(forWriting:source,settings:format.settings,commonFormat:.pcmFormatInt16,interleaved:true);try file.write(from:pcm)}
  let original=try Data(contentsOf:source)
  let assembled=try SamplerSplitRegions.assemble(source,attack:0..<48000,loop:96000..<105600)
  let file=try AVAudioFile(forReading:assembled,commonFormat:.pcmFormatInt16,interleaved:true)
  assert(file.length==57600 && file.fileFormat.sampleRate==48000)
  let assembledBytes=try Data(contentsOf:assembled)
  func payload(_ bytes:Data)->Data {
   var pos=8
   while pos+12<=bytes.count {
    let count=bytes[pos+4..<pos+12].reduce(0){($0<<8)|Int($1)}
    if String(data:bytes[pos..<pos+4],encoding:.ascii)=="data" {return bytes.subdata(in:pos+16..<pos+12+count)}
    pos+=12+count
   }
   fatalError("Missing CAF audio")
  }
  let stored=payload(original),expected=stored.subdata(in:0..<96000)+stored.subdata(in:192000..<211200)
  assert(payload(assembledBytes)==expected,"Every PCM byte must remain bit-identical, including attack and loop")
  let after=try Data(contentsOf:source);assert(after==original,"Original sample file must not change")
  let sampler=AVAudioUnitSampler();try sampler.loadAudioFiles(at:[source])
  var state=sampler.auAudioUnit.fullStateForDocument!,instrument=state["Instrument"] as! [String:Any]
  var layer=(instrument["Layers"] as! [[String:Any]])[0],zones=layer["Zones"] as! [[String:Any]]
  zones[0]["min key"]=0;zones[0]["max key"]=127;zones[0]["root key"]=60;zones[0]["sample start"]=0;zones[0]["sample end"]=57600
  zones[0]["loop enabled"]=true;zones[0]["loop start"]=48001;zones[0]["loop end"]=57600
  zones[0]["StageKeys EXS attack end"]=48000;zones[0]["StageKeys EXS tail start"]=96000;zones[0]["StageKeys EXS tail end"]=105600;layer["Zones"]=zones
  EXSNative.applyEnvelope(.init(attack:0,lowVelocityAttack:0,decay:10,sustain:1,release:0.1),group:Array(repeating:0,count:120),to:&layer)
  var second=zones[0];second["ID"]=1;second["min key"]=61;second["max key"]=61;second["root key"]=61
  layer["Zones"]=[zones[0],second]
  instrument["Layers"]=[layer];state["Instrument"]=instrument
  let prepared=try SamplerSplitRegions.prepare(state),unchanged=state["file-references"] as! [String:String]
  assert(unchanged.values.contains(source.path))
  let preparedZones=(((prepared["Instrument"] as! [String:Any])["Layers"] as! [[String:Any]])[0]["Zones"] as! [[String:Any]])
  assert((prepared["file-references"] as! [String:String]).count==1,"Split zones must share one PCM file per source")
  assert(preparedZones[0]["waveform"] as? Int==preparedZones[1]["waveform"] as? Int && preparedZones[1]["sample start"] as? Int==57600,"Compacted zone offsets must remain distinct")
  assert(preparedZones[0]["sample end"] as? Int==57599 && preparedZones[0]["loop start"] as? Int==48001)
  let preset=root.appendingPathComponent("prepared.aupreset");try PropertyListSerialization.data(fromPropertyList:prepared,format:.xml,options:0).write(to:preset)
  let engine=AVAudioEngine(),out=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
  engine.attach(sampler);engine.connect(sampler,to:engine.mainMixerNode,format:out)
  try engine.enableManualRenderingMode(.offline,format:out,maximumFrameCount:480)
  try SamplerRendering.configure(sampler,offline:true);try sampler.loadInstrument(at:preset);try engine.start();defer{engine.stop()}
  sampler.startNote(60,withVelocity:100,onChannel:0)
  let buffer=AVAudioPCMBuffer(pcmFormat:out,frameCapacity:480)!
  var attackPeak:Float=0,heldPeak:Float=0
  for block in 0..<350 {_ = try engine.renderOffline(480,to:buffer);for i in 0..<Int(buffer.frameLength){let value=abs(buffer.floatChannelData![0][i]);assert(value.isFinite);if block<90 {attackPeak=max(attackPeak,value)};if block>110 {heldPeak=max(heldPeak,value)}}}
  assert(attackPeak>0.001 && heldPeak>0.001 && heldPeak<attackPeak*0.65,"Held audio must loop the quiet tail, never replay the loud gap")
  do{_ = try SamplerSplitRegions.assemble(source,attack:0..<48000,loop:96000..<999999);assertionFailure("Out-of-bounds region accepted")}catch{}
  print("PASS: exact PCM frame preservation, original file unchanged, bounded split maps, held-note gap exclusion; peaks \(attackPeak) / \(heldPeak)")
 }
}
