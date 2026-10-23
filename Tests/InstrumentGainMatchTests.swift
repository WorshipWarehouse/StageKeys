import Foundation
@main struct InstrumentGainMatchTests {
 @MainActor static func main()async throws {
  let result=try InstrumentGainMatch.recommendation(rms:0.1,peak:0.2)
  assert(abs(result.trimDB+4)<0.001 && !result.peakLimited)
  let quieter=try InstrumentGainMatch.retarget(result,to:-30);assert(abs(quieter.trimDB+10)<0.001)
  for target in [Double.nan,-100,0] {do{_ = try InstrumentGainMatch.retarget(result,to:target);fatalError("Invalid target accepted")}catch{}}
  let capped=try InstrumentGainMatch.recommendation(rms:0.001,peak:0.002,targetDB:-24)
  assert(capped.trimLimited && !capped.peakLimited && abs(capped.outputRMSDB+48)<0.001)
  let cut=try InstrumentGainMatch.recommendation(rms:0.1,peak:0.2,targetDB:-60)
  assert(cut.trimLimited && cut.trimDB == -24)
  assert(!result.trimLimited && abs(result.outputRMSDB+24)<0.001)
  let protected=try InstrumentGainMatch.recommendation(rms:0.01,peak:0.5)
  assert(protected.peakLimited && abs(protected.trimDB-(-9+6.0206))<0.001)
  for invalid in [0.0,Double.nan,Double.infinity] {do{_ = try InstrumentGainMatch.recommendation(rms:invalid,peak:1);fatalError("Invalid/quiet result accepted")}catch{}}
  let legacy=ChannelSettings();let bytes=try JSONEncoder().encode(legacy);var json=try JSONSerialization.jsonObject(with:bytes) as! [String:Any];json.removeValue(forKey:"outputTrimDB")
  let decoded=try JSONDecoder().decode(ChannelSettings.self,from:JSONSerialization.data(withJSONObject:json));assert(decoded.outputTrimDB==nil && decoded.validate())
  var invalid=legacy;invalid.outputTrimDB = .nan;assert(!invalid.validate());invalid.outputTrimDB=13;assert(!invalid.validate())
  let base=Layer(name:"Probe",instrument:0,gain:0.2)
  let a=try await InstrumentGainMatch.measure(base,modulation:0.5);var changed=base;changed.gain=0.8;changed.channelSettings.outputTrimDB = -12
  let b=try await InstrumentGainMatch.measure(changed,modulation:0.5)
  assert(abs(a.rmsDB-b.rmsDB)<0.001 && abs(a.trimDB-b.trimDB)<0.001,"Probe must be independent of fader and existing trim")
  func outputEnergy(_ trim:Float)throws->Double {
   let audio=AudioController();try audio.prepareOffline();audio.bypassMasterLimiter(true);defer{audio.stop()};var l=base;l.gain=0.01;l.channelSettings.outputTrimDB=trim;l.effects[0]=AudioEffect.factoryDefault(kind:11)
   audio.configure(0,l);audio.gain(0,0.01,seconds:0);audio.master(1);audio.space(0)
   for _ in 0..<10{_ = try audio.offlineBlock()};audio.noteOn(key:60,pitch:60,instrument:0,layer:0,velocity:0.7)
   var energy=0.0;for _ in 0..<40 {let b=try audio.offlineBlock();for i in 0..<Int(b.frameLength){energy+=Double(b.floatChannelData![0][i]*b.floatChannelData![0][i])}};return energy
  }
  let dry=try outputEnergy(0),trimmed=try outputEnergy(-6);print("TRIM RATIO",sqrt(trimmed/dry));assert(abs(sqrt(trimmed/dry)-pow(10,-6.0/20))<0.001,"Trim must follow nonlinear effects without changing their drive")
  if let component=ExternalInstrumentRack.instruments().first(where:{$0.manufacturer==0x6170706c && $0.subtype==0x646c7320}) {
   var au=base;au.instrument = -1;au.external=ExternalSound(kind:.audioUnit,name:component.name,component:component)
   let measured=try await InstrumentGainMatch.measure(au,modulation:0.5);assert(measured.trimDB.isFinite);print("PASS: actual asynchronous Audio Unit calibration",component.name,measured)
  }else {print("SKIP: Apple DLS AU unavailable on this host")}
  if let path=ProcessInfo.processInfo.environment["STAGEKEYS_PIANO_PRESET"] {
   let source=URL(fileURLWithPath:path),data=try Data(contentsOf:source),state=try PropertyListSerialization.propertyList(from:data,options:[],format:nil) as! [String:Any]
   let program=try JSONDecoder().decode(NativeSamplerProgram.self,from:state["StageKeys.NativeSampler"] as! Data)
   let folder=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!).appendingPathComponent("Imported Sounds");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);try data.write(to:folder.appendingPathComponent(source.lastPathComponent))
   var piano=base;piano.instrument = -1;piano.external=ExternalSound(kind:.samplerPreset,name:"Private Steinway",fileName:source.lastPathComponent,nativeSampler:program)
   let result=try await InstrumentGainMatch.measure(piano,modulation:0.5);assert(result.trimDB.isFinite);let unchanged=try Data(contentsOf:source);assert(unchanged==data)
   print("PASS: converted native Steinway calibration with original preset unchanged",result)
  }
  print("PASS: bounded peak-limited fixed gain matching, silence rejection, legacy persistence and isolated production rendering",a)
 }
}
