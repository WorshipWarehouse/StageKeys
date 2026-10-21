import Foundation
@main struct EXSResponseUpgradeTests {
 static func main()throws {
  guard let path=ProcessInfo.processInfo.environment["STAGEKEYS_PIANO_PRESET"],let source=ProcessInfo.processInfo.environment["STAGEKEYS_EXS_FIXTURE"] else{print("SKIP: private response fixture unset");return}
  let input=URL(fileURLWithPath:path),bytes=try Data(contentsOf:input),state=try PropertyListSerialization.propertyList(from:bytes,options:[],format:nil) as! [String:Any]
  let program=try JSONDecoder().decode(NativeSamplerProgram.self,from:state["StageKeys.NativeSampler"] as! Data);assert(program.conversionVersion==5)
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),folder=root.appendingPathComponent("Imported Sounds")
  try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
  let file=folder.appendingPathComponent(input.lastPathComponent);try bytes.write(to:file)
  let original=try StageKeysSampler.retainOriginal(URL(fileURLWithPath:source),library:root)
  let sourceBytes=try Data(contentsOf:root.appendingPathComponent(original.file))
  let sound=ExternalSound(kind:.samplerPreset,name:"Custom name",fileName:input.lastPathComponent,nativeSampler:program)
  let updated=try StageKeysSampler.updatePlayback(sound,original:original,library:root);assert(updated.nativeSampler?.conversionVersion==6 && updated.name==sound.name)
  let after=try PropertyListSerialization.propertyList(from:Data(contentsOf:file),options:[],format:nil) as! [String:Any]
  assert(NSDictionary(dictionary:state["file-references"] as! [String:Any])==NSDictionary(dictionary:after["file-references"] as! [String:Any]))
  let prior=(state["Instrument"] as! [String:Any])["Layers"] as! [[String:Any]],layers=(after["Instrument"] as! [String:Any])["Layers"] as! [[String:Any]]
  for i in layers.indices {
   assert(NSArray(array:prior[i]["Envelopes"] as! [Any])==NSArray(array:layers[i]["Envelopes"] as! [Any]))
   let a=prior[i]["Zones"] as! [[String:Any]],b=layers[i]["Zones"] as! [[String:Any]]
   for j in a.indices {var old=a[j],new=b[j];let g=(old.removeValue(forKey:"gain") as! NSNumber).doubleValue,h=(new.removeValue(forKey:"gain") as! NSNumber).doubleValue
    let centered=(prior[i]["pan"] as? NSNumber)?.doubleValue==0 && (a[j]["pan"] as? NSNumber)?.doubleValue==0
    assert(abs(h-g-(centered ? EXSNative.centerGainDB:0))<1e-8);assert(NSDictionary(dictionary:old)==NSDictionary(dictionary:new))}
  }
  let stable=try Data(contentsOf:file);_ = try StageKeysSampler.updatePlayback(updated,original:original,library:root);let stableRead=try Data(contentsOf:file);assert(stableRead==stable)
  let sourceRead=try Data(contentsOf:root.appendingPathComponent(original.file));assert(sourceRead==sourceBytes)
  let backup=root.appendingPathComponent("Sampler Backups/"+MainStagePatch.digest(bytes)+".aupreset");let backupRead=try Data(contentsOf:backup);assert(backupRead==bytes)
  var edited=state,inst=state["Instrument"] as! [String:Any],ls=prior,z=prior[0]["Zones"] as! [[String:Any]];z[0]["gain"] = 13.0;ls[0]["Zones"]=z;inst["Layers"]=ls;edited["Instrument"]=inst
  let edit=try PropertyListSerialization.data(fromPropertyList:edited,format:.xml,options:0);try edit.write(to:file)
  do{_ = try StageKeysSampler.updatePlayback(sound,original:original,library:root);fatalError("Edited gain overwritten")}catch{}
  let editRead=try Data(contentsOf:file);assert(editRead==edit)
  print("PASS: v6 response upgrade, unchanged samples/maps/envelope times, centered gain, backup, idempotence and edited-gain rollback")
 }
}
