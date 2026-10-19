import Foundation
import AVFoundation
@main struct SamplerAttackTests {
 static func main() throws {
  let envelope:[[String:Any]]=[["ID":0,"enabled":true,"Stages":[["stage":1,"time":0.001],["stage":3,"time":3.0],["stage":4,"level":0.7],["stage":5,"time":0.5]]],["ID":1,"enabled":true,"Stages":[["stage":1,"time":0.0001]]]]
  let layer:[String:Any]=["ID":2,"Envelopes":envelope,"Connections":[["source":0x20000200,"destination":0x50100200,"enabled":true],["source":0x20000201,"destination":0x40100200,"enabled":true]],"Zones":[["waveform":10,"sample start":400,"sample end":20000,"loop start":18000,"loop end":19999]]]
  let original:[String:Any]=["Instrument":["Layers":[layer]],"file-references":["Sample:10":"/unchanged/original.caf"]]
  let prepared=SamplerAttack.prepare(original,minimum:0.04),inst=prepared["Instrument"] as! [String:Any],updated=(inst["Layers"] as! [[String:Any]])[0],env=updated["Envelopes"] as! [[String:Any]]
  let stages=env[0]["Stages"] as! [[String:Any]]
  assert(abs((stages[0]["time"] as! Double)-0.04)<0.000001)
  assert(NSDictionary(dictionary:env[1]).isEqual(to:envelope[1]),"Filter envelope must remain unchanged")
  assert(NSArray(array:updated["Zones"] as! [[String:Any]])==NSArray(array:layer["Zones"] as! [[String:Any]]),"Sample/loop boundaries must remain unchanged")
  assert(stages[1]["time"] as! Double==3 && stages[2]["level"] as! Double==0.7 && stages[3]["time"] as! Double==0.5)
  assert(NSDictionary(dictionary:SamplerAttack.prepare(original,minimum:0)).isEqual(to:original))
  assert(NSDictionary(dictionary:SamplerAttack.prepare(prepared,minimum:0.01)).isEqual(to:prepared),"Longer authored attacks must never be shortened")
  assert(NSDictionary(dictionary:prepared["file-references"] as! [String:Any]).isEqual(to:original["file-references"] as! [String:Any]))
  var settings=ChannelSettings();settings.samplerAttackMinimum=0.04;assert(settings.validate());let copy=try JSONDecoder().decode(ChannelSettings.self,from:JSONEncoder().encode(settings));assert(copy==settings)
  settings.samplerAttackMinimum = -.infinity;assert(!settings.validate())
  if let fixture=ProcessInfo.processInfo.environment["STAGEKEYS_PIANO_PRESET"] {
   let file=URL(fileURLWithPath:fixture),bytes=try Data(contentsOf:file),state=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as! [String:Any]
   let program=try JSONDecoder().decode(NativeSamplerProgram.self,from:state["StageKeys.NativeSampler"] as! Data)
   let refs=state["file-references"] as! [String:String],hashes=try refs.mapValues{try AssetDigest.sha256(URL(fileURLWithPath:$0))}
   func render(_ minimum:Float,_ note:Int)throws->[Float] {
    let destination=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!).appendingPathComponent(UUID().uuidString,isDirectory:true)
    try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
    try bytes.write(to:destination.appendingPathComponent(file.lastPathComponent))
    let engine=AVAudioEngine(),rack=try ExternalInstrumentRack(engine:engine,libraryURL:destination),format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
    try engine.enableManualRenderingMode(.offline,format:format,maximumFrameCount:512)
    var failure:Error?
    rack.load(ExternalSound(kind:.samplerPreset,name:"Steinway",fileName:file.lastPathComponent,nativeSampler:program),channel:0,attackMinimum:minimum){if case .failure(let e)=$0{failure=e}}
    if let failure{throw failure}
    try rack.configureParallel(channel:0,branches:program.rack.branches,tempo:120);rack.volume(channel:0,gain:0.5,pan:0)
    try rack.prepareOfflineSamples();try engine.start();defer{engine.stop()}
    let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:512)!
    for _ in 0..<10 {_ = try engine.renderOffline(512,to:buffer)}
    rack.noteOn(channel:0,key:note,pitch:note,velocity:1)
    var result:[Float]=[]
    for _ in 0..<40 {_ = try engine.renderOffline(512,to:buffer);result+=Array(UnsafeBufferPointer(start:buffer.floatChannelData![0],count:Int(buffer.frameLength)))}
    return result
   }
   for note in [60,84,96] {
    let raw=try render(0,note),smooth=try render(0.04,note)
    func start(_ x:[Float])->Int{x.firstIndex(where:{abs($0)>1e-12})!}
    let a=start(raw),b=start(smooth),span=96
    let stepA=(1..<span).map{abs(raw[a+$0]-raw[a+$0-1])}.max()!,stepB=(1..<span).map{abs(smooth[b+$0]-smooth[b+$0-1])}.max()!
    assert(stepB<stepA*0.85,"Early attack step was not reduced at note \(note): \(stepA) → \(stepB)")
    let tailA=raw.suffix(5000).reduce(0.0){$0+Double($1*$1)},tailB=smooth.suffix(5000).reduce(0.0){$0+Double($1*$1)}
    assert((0.85...1.15).contains(tailB/tailA),"Sustained piano must retain its body")
    print("PASS Steinway note",note,"early step",stepA,"→",stepB,"body ratio",tailB/tailA)
   }
   let retained=try Data(contentsOf:file);assert(retained==bytes)
   for (key,path) in refs {let digest=try AssetDigest.sha256(URL(fileURLWithPath:path));assert(digest==hashes[key])}
   print("PASS: original Steinway preset and CAF sample hashes unchanged")
  }
  print("PASS: attack-only playback state, bypass, long attacks, non-amplitude envelopes, boundaries and settings roundtrip")
 }
}
