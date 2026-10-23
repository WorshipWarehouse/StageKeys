import Foundation
@main struct MainStageAutoConversionTests {
 @MainActor static func main()async throws {
  let env=ProcessInfo.processInfo.environment
  guard let reference=env["STAGEKEYS_MAINSTAGE_REFERENCE"],let exs=env["STAGEKEYS_EXS_FIXTURE"],let sample=env["STAGEKEYS_SAMPLE_FIXTURE"] else{print("SKIP: private bundled MainStage fixture unset");return}
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),patch=root.appendingPathComponent("Bundled.patch"),dataRoot=root.appendingPathComponent("data")
  try FileManager.default.createDirectory(at:patch,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
  let ref=URL(fileURLWithPath:reference)
  var document=try PropertyListSerialization.propertyList(from:Data(contentsOf:ref.appendingPathComponent("data.plist")),options:[],format:nil) as! [String:Any]
  let channels=document["channels"] as! [[String:Any]],channel=channels.first{($0["Filename"] as? String)=="Grand Piano.cst"}!
  document["channels"]=[channel]
  let strip=try Data(contentsOf:ref.appendingPathComponent("Grand Piano.cst")),names=MainStagePatch.instrumentReferences(strip);assert(names.count==1)
  try strip.write(to:patch.appendingPathComponent("Grand Piano.cst"));try PropertyListSerialization.data(fromPropertyList:document,format:.binary,options:0).write(to:patch.appendingPathComponent("data.plist"))
  let source=URL(fileURLWithPath:exs),audio=URL(fileURLWithPath:sample),hash=try AssetDigest.sha256(audio),exsHash=try AssetDigest.sha256(source)
  try FileManager.default.copyItem(at:source,to:patch.appendingPathComponent(names[0]))
  try FileManager.default.copyItem(at:audio,to:patch.appendingPathComponent("Steinway Piano_consolidated.caf"))
  setenv("STAGEKEYS_DATA_DIR",dataRoot.path,1);let store=PerformanceStore();store.importMainStagePatch(patch)
  for _ in 0..<1500 where store.libraryImportBusy {try await Task.sleep(nanoseconds:20_000_000)}
  assert(!store.libraryImportBusy,"Native import did not finish")
  guard let entry=store.librarySounds.first(where:{$0.id.hasPrefix("mainstage-channel-")}),let sound=entry.sound else{fatalError(store.libraryImportProgress ?? "Native conversion added no sound")}
  assert(sound.nativeSampler?.conversionVersion==6 && entry.layer?.importedRack != nil && entry.originalInstrument?.sha256==exsHash)
  let file=dataRoot.appendingPathComponent("Imported Sounds/"+sound.fileName!),state=try PropertyListSerialization.propertyList(from:Data(contentsOf:file),options:[],format:nil) as! [String:Any],refs=state["file-references"] as! [String:String]
  assert(refs.count==1);let managedHash=try AssetDigest.sha256(URL(fileURLWithPath:refs.values.first!));assert(managedHash==hash)
  let count=store.librarySounds.count;store.importMainStagePatch(patch)
  for _ in 0..<1500 where store.libraryImportBusy {try await Task.sleep(nanoseconds:20_000_000)}
  assert(store.librarySounds.count==count,"Reimport duplicated the native instrument")
  print("PASS: app-native bundled MainStage conversion v6, >16 MB sample retention, original hashes, rack processing and duplicate-aware reimport",store.libraryImportProgress ?? "")
 }
}
