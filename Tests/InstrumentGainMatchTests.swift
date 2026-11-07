import Foundation
import AVFoundation
@main struct InstrumentGainMatchTests {
 @MainActor static func main()async throws {
  assert(abs(try! InstrumentGainMatch.repeatability([0.1,0.2])-6.0206)<0.001)
  let boundaryWarning=try InstrumentGainMatch.repeatabilityWarning(spreadDB:1)
  let aboveBoundaryWarning=try InstrumentGainMatch.repeatabilityWarning(spreadDB:1.01)
  assert(boundaryWarning==nil && aboveBoundaryWarning?.contains("listening comparison")==true)
  for invalidSpread in [Double.nan,-1.0,Double.infinity] {
   var rejected=false
   do{_ = try InstrumentGainMatch.repeatabilityWarning(spreadDB:invalidSpread)}catch{rejected=true}
   assert(rejected,"Invalid confidence spread must be rejected")
  }
  for levels in [[0.0,0.1],[Double.nan,0.1],[0.1]] {do{_ = try InstrumentGainMatch.repeatability(levels);fatalError("Invalid repeatability accepted")}catch{}}
  var trimDraft=InstrumentGainMatch.TrimDraft();var draftTrim:Float? = -3
  draftTrim=trimDraft.toggleComparison(current:draftTrim,proposed:2)
  assert(trimDraft.isComparing && trimDraft.comparisonTrim == -3 && draftTrim == 2 && trimDraft.committedValue(current:draftTrim) == -3)
  draftTrim=trimDraft.toggleComparison(current:draftTrim,proposed:2)
  assert(!trimDraft.isComparing && draftTrim == -3)
  draftTrim=trimDraft.apply(current:draftTrim,proposed:4)
  assert(trimDraft.canUndo && draftTrim == 4)
  draftTrim=trimDraft.undo()
  assert(!trimDraft.canUndo && draftTrim == -3)
  draftTrim=trimDraft.reset(current:draftTrim)
  assert(trimDraft.canUndo && draftTrim == nil)
  draftTrim=trimDraft.undo()
  assert(draftTrim == -3 && !trimDraft.canUndo)
  var unityTrim:Float?;unityTrim=trimDraft.reset(current:unityTrim);assert(trimDraft.canUndo && unityTrim == nil)
  unityTrim=trimDraft.undo();assert(unityTrim == nil && !trimDraft.canUndo)
  var readinessChecks=0
  do {
   try await InstrumentGainMatch.waitForInstrumentReady(maxAttempts:2,pollNanoseconds:1_000_000,isReady:{readinessChecks+=1;return false},loadError:{nil})
   fatalError("A never-ready instrument was accepted")
  }catch{assert(error.localizedDescription.contains("did not finish loading"))}
  assert(readinessChecks==3,"Readiness wait must be bounded and perform a final state check")
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
  let base=TestFixtures.layer(gain:0.2,name:"Probe")
  let dataRoot=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
  let splitSeed=AVAudioUnitSampler()
  try splitSeed.loadAudioFiles(at:[dataRoot.appendingPathComponent("Generated Fixture 0.wav")])
  var splitState=splitSeed.auAudioUnit.fullStateForDocument!
  var splitInstrument=splitState["Instrument"] as! [String:Any]
  var splitLayers=splitInstrument["Layers"] as! [[String:Any]]
  var splitLayerState=splitLayers[0]
  let originalZones=splitLayerState["Zones"] as! [[String:Any]]
  var splitZones=[[String:Any]]()
  for (index,range) in [(0,59,0,83),(0,59,84,127),(60,127,0,83),(60,127,84,127)].enumerated() {
   var zone=originalZones[0]
   zone["ID"]=index;zone["min key"]=range.0;zone["max key"]=range.1
   zone["min vel"]=range.2;zone["max vel"]=range.3
   zone["min velocity"]=range.2;zone["max velocity"]=range.3
   splitZones.append(zone)
  }
  splitLayerState["Zones"]=splitZones;splitLayers[0]=splitLayerState;splitInstrument["Layers"]=splitLayers
  splitState["Instrument"]=splitInstrument
  let splitProgram=NativeSamplerProgram(groups:[.init(name:"Generated key/velocity split",layer:0,low:0,high:127,velocityLow:0,velocityHigh:127)],notes:[],conversionVersion:6)
  splitState["StageKeys.NativeSampler"]=try JSONEncoder().encode(splitProgram)
  let splitURL=dataRoot.appendingPathComponent("Generated Key Velocity Split.aupreset")
  try PropertyListSerialization.data(fromPropertyList:splitState,format:.xml,options:0).write(to:splitURL)
  let splitController=AudioController()
  let splitSound=try splitController.externalRack!.importPreset(splitURL,sampleRoot:dataRoot)
  let splitMap=try StageKeysSampler.map(splitSound,library:splitController.externalRack!.libraryURL)
  assert(splitMap.zones.count==4 && splitMap.zones.contains{$0.low==0 && $0.high==59 && $0.velocityLow==0 && $0.velocityHigh==83} &&
         splitMap.zones.contains{$0.low==60 && $0.high==127 && $0.velocityLow==84 && $0.velocityHigh==127},
         "Generated zones must straddle the probe and peak-stress key/velocity boundaries")
  var splitProbe=base;splitProbe.external=splitSound;splitProbe.importedRack=splitSound.nativeSampler?.rack
  let splitMeasurement=try await InstrumentGainMatch.measure(splitProbe,modulation:0.5)
  assert(splitMeasurement.probeNotes==[48,60,72] && splitMeasurement.measuredVelocity==83 && splitMeasurement.peakStressVelocity==127)
  var trimOnly=base;trimOnly.channelSettings.outputTrimDB = -6
  assert(InstrumentGainMatch.sameMeasurementInputs(base,trimOnly))
  trimOnly.gain=0.4;assert(!InstrumentGainMatch.sameMeasurementInputs(base,trimOnly))
  trimOnly=base;trimOnly.pluginState=Data([1,2,3]);assert(!InstrumentGainMatch.sameMeasurementInputs(base,trimOnly))
  let a=try await InstrumentGainMatch.measure(base,modulation:0.5);var changed=base;changed.gain=0.8;changed.channelSettings.outputTrimDB = -12
  assert(a.probeNotes == [48,60,72] && a.measuredVelocity == 83 && a.peakStressVelocity == 127 && a.probeTempo == 72 && a.repeatabilityDB != nil)
  let preserved=try InstrumentGainMatch.retarget(a,to:-30);assert(preserved.probeNotes==a.probeNotes && preserved.measuredVelocity==a.measuredVelocity && preserved.peakStressVelocity==a.peakStressVelocity && preserved.probeTempo==a.probeTempo && preserved.repeatabilityDB==a.repeatabilityDB)
  let b=try await InstrumentGainMatch.measure(changed,modulation:0.5,tempo:137)
  assert(b.probeTempo == 137)
  assert(abs(a.rmsDB-b.rmsDB)<0.001 && abs(a.trimDB-b.trimDB)<0.001,"Probe must be independent of fader and existing trim")
  func outputEnergy(_ trim:Float)throws->Double {
   let audio=AudioController();try audio.prepareOffline();audio.bypassMasterLimiter(true);defer{audio.stop()};var l=base;l.gain=0.01;l.channelSettings.outputTrimDB=trim;l.effects[0]=AudioEffect.factoryDefault(kind:11)
   audio.configure(0,l);audio.gain(0,0.01,seconds:0);audio.master(1);audio.space(0)
   for _ in 0..<10{_ = try audio.offlineBlock()};audio.noteOn(key:60,pitch:60,instrument:0,layer:0,velocity:0.7)
   var energy=0.0;for _ in 0..<40 {let b=try audio.offlineBlock();for i in 0..<Int(b.frameLength){energy+=Double(b.floatChannelData![0][i]*b.floatChannelData![0][i])}};return energy
  }
  let dry=try outputEnergy(0),trimmed=try outputEnergy(-6);print("TRIM RATIO",sqrt(trimmed/dry));assert(abs(sqrt(trimmed/dry)-pow(10,-6.0/20))<0.001,"Trim must follow nonlinear effects without changing their drive")
  let store=PerformanceStore()
  var savedSetlist=TestFixtures.setlist()
  var persisted=savedSetlist.patches[0].layers[0]
  persisted.gain=0.37;persisted.low=44;persisted.high=91;persisted.muted=true
  persisted.channelSettings.outputTrimDB = -3
  persisted.channelSettings.eqEnabled=false
  persisted.channelSettings.equalizer[2].gain=2.5
  persisted.channelSettings.compressorEnabled=true
  persisted.channelSettings.threshold = -22
  persisted.effects[0]=AudioEffect.factoryDefault(kind:11)
  savedSetlist.patches[0].layers[0]=persisted
  let auIdentity=ExternalAUIdentity(type:0x61756d75,subtype:0x6761696e,manufacturer:0x54657374,name:"Generated Gain State AU")
  var pluginLayer=Layer(name:auIdentity.name,instrument:-1,gain:0.31)
  pluginLayer.id=savedSetlist.patches[0].layers[1].id
  pluginLayer.external=ExternalSound(kind:.audioUnit,name:auIdentity.name,component:auIdentity)
  let authoredPluginState=try PropertyListSerialization.data(fromPropertyList:["GeneratedGainState":"preserve"],format:.binary,options:0)
  pluginLayer.pluginState=authoredPluginState
  pluginLayer.channelSettings.outputTrimDB = 1.25
  savedSetlist.patches[0].layers[1]=pluginLayer
  store.setlist=savedSetlist;store.save()
  let setlistURL=dataRoot.appendingPathComponent("setlist.json")
  let beforePreview=try Data(contentsOf:setlistURL)
  let audition=store.beginAudition(0)!
  var preview=persisted;preview.channelSettings.outputTrimDB=2
  store.previewLayer(0,preview,token:audition)
  assert(store.playbackLayer(0)==preview && store.patch.layers[0]==persisted)
  assert(try! Data(contentsOf:setlistURL)==beforePreview,"A/B preview must not persist the temporary trim")
  store.previewLayer(0,persisted,token:audition)
  assert(store.playbackLayer(0)==persisted && (try! Data(contentsOf:setlistURL))==beforePreview)
  var committed=persisted;committed.channelSettings.outputTrimDB=4
  store.confirmAudition(audition,index:0,layer:committed)
  assert(store.patch.layers[0]==committed,"Apply plus Confirm must commit only the separate trim")
  let restarted=PerformanceStore()
  assert(restarted.patch.layers[0]==committed,"The confirmed trim and authored channel settings must survive save/reload")
  assert(restarted.patch.layers[1].pluginState==authoredPluginState && restarted.patch.layers[1].channelSettings.outputTrimDB==1.25,
         "Saving a trim must preserve another layer's Audio Unit state and trim")
  assert(restarted.patch.layers[0].gain==persisted.gain && restarted.patch.layers[0].low==persisted.low && restarted.patch.layers[0].high==persisted.high &&
         restarted.patch.layers[0].muted==persisted.muted && restarted.patch.layers[0].channelSettings.equalizer==persisted.channelSettings.equalizer &&
         restarted.patch.layers[0].channelSettings.compressorEnabled==persisted.channelSettings.compressorEnabled &&
         restarted.patch.layers[0].channelSettings.threshold==persisted.channelSettings.threshold && restarted.patch.layers[0].effects==persisted.effects,
         "Source level, note/velocity settings, dynamics and effects must remain authored")
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
