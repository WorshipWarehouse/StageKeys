import Foundation
@main struct EXSAmplitudeUpgradeTests {
 static func main()throws {
  guard let path=ProcessInfo.processInfo.environment["STAGEKEYS_PIANO_PRESET"],let source=ProcessInfo.processInfo.environment["STAGEKEYS_EXS_FIXTURE"] else{print("SKIP: private sampler/source unset");return}
  let input=URL(fileURLWithPath:path),bytes=try Data(contentsOf:input),state=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as! [String:Any]
  let program=try JSONDecoder().decode(NativeSamplerProgram.self,from:state["StageKeys.NativeSampler"] as! Data)
  assert(program.conversionVersion==5 && program.voiceControls?.amplitudeVelocity==nil)
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),folder=root.appendingPathComponent("Imported Sounds")
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
  let file=folder.appendingPathComponent(input.lastPathComponent);try bytes.write(to:file)
  let original=try StageKeysSampler.retainOriginal(URL(fileURLWithPath:source),library:root)
  let sound=ExternalSound(kind:.samplerPreset,name:"Custom name",fileName:input.lastPathComponent,nativeSampler:program)
  let updated=try StageKeysSampler.updatePlayback(sound,original:original,library:root)
  assert(updated.nativeSampler?.voiceControls?.amplitudeVelocity?.sensitivity == -52 && updated.name==sound.name)
  let after=try PropertyListSerialization.propertyList(from:Data(contentsOf:file),options:[],format:nil) as! [String:Any]
  assert(NSDictionary(dictionary:state["file-references"] as! [String:Any])==NSDictionary(dictionary:after["file-references"] as! [String:Any]))
  let priorLayers=(state["Instrument"] as! [String:Any])["Layers"] as! [[String:Any]],layers=(after["Instrument"] as! [String:Any])["Layers"] as! [[String:Any]]
  for i in layers.indices {
   assert(NSArray(array:priorLayers[i]["Zones"] as! [Any])==NSArray(array:layers[i]["Zones"] as! [Any]))
   assert(NSArray(array:priorLayers[i]["Envelopes"] as! [Any])==NSArray(array:layers[i]["Envelopes"] as! [Any]))
  }
  let stable=try Data(contentsOf:file);_ = try StageKeysSampler.updatePlayback(updated,original:original,library:root);let stableAgain=try Data(contentsOf:file);assert(stableAgain==stable)
  var edited=state,inst=state["Instrument"] as! [String:Any],editedLayers=priorLayers,connections=priorLayers[0]["Connections"] as! [[String:Any]]
  for i in connections.indices where connections[i]["source"] as? Int==301 && ((connections[i]["destination"] as? Int ?? 0)&0xffff00ff)==0x50100000 {connections[i]["scale"] = -64.0}
  editedLayers[0]["Connections"]=connections;inst["Layers"]=editedLayers;edited["Instrument"]=inst
  let editedBytes=try PropertyListSerialization.data(fromPropertyList:edited,format:.xml,options:0);try editedBytes.write(to:file)
  do{_ = try StageKeysSampler.updatePlayback(sound,original:original,library:root);fatalError("Edited amplitude route must not be overwritten")}catch{}
  let retained=try Data(contentsOf:file);assert(retained==editedBytes)
  print("PASS: native velocity upgrade retains sample maps/envelopes, is idempotent and rolls back edited amplitude routes")
 }
}
