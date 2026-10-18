import Foundation
@main struct EXSVoiceUpgradeTests {
 static func main()throws {
  guard let path=ProcessInfo.processInfo.environment["STAGEKEYS_PIANO_PRESET"],let source=ProcessInfo.processInfo.environment["STAGEKEYS_EXS_FIXTURE"] else {print("SKIP: private v2 sampler/source fixture unset");return}
  let input=URL(fileURLWithPath:path),bytes=try Data(contentsOf:input),before=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as! [String:Any]
  let program=try JSONDecoder().decode(NativeSamplerProgram.self,from:before["StageKeys.NativeSampler"] as! Data)
  assert(program.conversionVersion==2)
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString,isDirectory:true),library=root.appendingPathComponent("Imported Sounds",isDirectory:true)
  try FileManager.default.createDirectory(at:library,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
  let preset=library.appendingPathComponent(input.lastPathComponent);try bytes.write(to:preset)
  let original=try StageKeysSampler.retainOriginal(URL(fileURLWithPath:source),library:root)
  let sound=ExternalSound(kind:.samplerPreset,name:"My Name",fileName:input.lastPathComponent,nativeSampler:program)
  let refs=before["file-references"] as! [String:String],hashes=try refs.mapValues{try AbletonArchive.sha256(URL(fileURLWithPath:$0))}
  let updated=try StageKeysSampler.updateVoiceControls(sound,original:original,library:root)
  if let sampleRoot=ProcessInfo.processInfo.environment["STAGEKEYS_EXS_ROOT"] {
   let fresh=try EXSNative.convert(URL(fileURLWithPath:source),sampleRoot:URL(fileURLWithPath:sampleRoot),to:root.appendingPathComponent("fresh.aupreset"))
   assert(fresh.conversionVersion==3 && fresh.voiceControls==updated.nativeSampler?.voiceControls,"Fresh imports must receive the same source controls as the existing-library upgrade")
   print("PASS: newly imported MainStage EXS receives the same synthesis controls without patch-name matching")
  }
  assert(updated.name==sound.name && updated.nativeSampler?.conversionVersion==3 && updated.nativeSampler?.voiceControls?.filter != nil)
  if let output=ProcessInfo.processInfo.environment["STAGEKEYS_UPGRADE_OUTPUT"] {try Data(contentsOf:preset).write(to:URL(fileURLWithPath:output))}
  let after=try PropertyListSerialization.propertyList(from:Data(contentsOf:preset),options:[],format:nil) as! [String:Any]
  let a=(before["Instrument"] as! [String:Any])["Layers"] as! [[String:Any]],b=(after["Instrument"] as! [String:Any])["Layers"] as! [[String:Any]]
  for i in a.indices {
   let za=a[i]["Zones"] as! [[String:Any]],zb=b[i]["Zones"] as! [[String:Any]]
   for j in za.indices {
    var old=za[j],new=zb[j]
    for key in ["gain","fine tune"] {old.removeValue(forKey:key);new.removeValue(forKey:key)}
    assert(NSDictionary(dictionary:old)==NSDictionary(dictionary:new),"Zone/sample mapping changed")
   }
   assert((b[i]["Filters"] as! [String:Any])["enabled"] as! Bool)
  }
  assert(NSDictionary(dictionary:refs)==NSDictionary(dictionary:after["file-references"] as! [String:String]))
  let backup=try Data(contentsOf:root.appendingPathComponent("Sampler Backups/"+MainStagePatch.digest(bytes)+".aupreset"));assert(backup==bytes)
  for (key,value) in refs {let hash=try AbletonArchive.sha256(URL(fileURLWithPath:value));assert(hash==hashes[key])}
  let retained=try Data(contentsOf:input);assert(retained==bytes)
  // An existing edited filter must not be overwritten.
  var edited=before,inst=edited["Instrument"] as! [String:Any],layers=inst["Layers"] as! [[String:Any]],filter=layers[0]["Filters"] as! [String:Any]
  filter["enabled"]=true;filter["cutoff"]=2345;layers[0]["Filters"]=filter;inst["Layers"]=layers;edited["Instrument"]=inst
  let editBytes=try PropertyListSerialization.data(fromPropertyList:edited,format:.xml,options:0);try editBytes.write(to:preset)
  do{_ = try StageKeysSampler.updateVoiceControls(sound,original:original,library:root);assertionFailure("Edited filter overwritten")}catch{}
  let kept=try Data(contentsOf:preset);assert(kept==editBytes)
  // V2 maps did not retain source group IDs. Never guess if source names are ambiguous.
  let sourceBytes=try Data(contentsOf:URL(fileURLWithPath:source));var offset=0,duplicate=Data()
  while offset+84<=sourceBytes.count {
   let b=[UInt8](sourceBytes[offset..<offset+8]),signature=Int(b[0])|Int(b[1])<<8|Int(b[2])<<16|Int(b[3])<<24,size=Int(b[4])|Int(b[5])<<8|Int(b[6])<<16|Int(b[7])<<24
   if (signature>>24)&63==2 {duplicate=sourceBytes[offset..<offset+84+size];break};offset+=84+size
  }
  assert(!duplicate.isEmpty)
  let ambiguous=root.appendingPathComponent("ambiguous.exs");try (sourceBytes+duplicate).write(to:ambiguous)
  let ambiguousOriginal=try StageKeysSampler.retainOriginal(ambiguous,library:root)
  try bytes.write(to:preset)
  do{_ = try StageKeysSampler.updateVoiceControls(sound,original:ambiguousOriginal,library:root);assertionFailure("Ambiguous source group matched by name")}catch{}
  let untouched=try Data(contentsOf:preset);assert(untouched==bytes)
  if let sampleRoot=ProcessInfo.processInfo.environment["STAGEKEYS_EXS_ROOT"] {
   do{_ = try EXSNative.convert(ambiguous,sampleRoot:URL(fileURLWithPath:sampleRoot),to:root.appendingPathComponent("duplicate.aupreset"));assertionFailure("Duplicate group ID stacked its sample zones")}catch{}
  }
  print("PASS: ambiguous legacy group names and duplicate source group IDs are rejected")
  print("PASS: source-backed v2→v3 playback update, preset backup, edited-filter protection, exact sample/loop/key/velocity map and original hashes")
 }
}
