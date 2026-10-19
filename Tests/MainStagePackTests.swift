import Foundation
import AVFoundation
@main struct MainStagePackTests {
 static func main()throws {
  guard let path=ProcessInfo.processInfo.environment["STAGEKEYS_MAINSTAGE_PACK"] else{print("SKIP: private MainStage pack unset");return}
  let source=URL(fileURLWithPath:path),pack=try LibraryBackup.read(source)
  let store=PerformanceStore();try store.audio.prepareOffline();defer{store.audio.stop()}
  store.importLibraryBackup(source)
  let deadline=Date().addingTimeInterval(120)
  while store.libraryImportBusy && Date()<deadline {RunLoop.main.run(until:Date().addingTimeInterval(0.05))}
  assert(!store.libraryImportBusy)
  var playbackErrors:[String]=[]
  let installedNames=Set(pack.sounds.compactMap {original in store.librarySounds.first{$0.id==original.id}?.sound?.fileName})
  assert(installedNames.count==Set(pack.sounds.compactMap{$0.sound?.fileName}).count,"Shared instruments must be installed once across channel variations")
  var checks=0, silentNames:[String]=[]
  for original in pack.sounds {
   guard let installed=store.librarySounds.first(where:{$0.id==original.id}),let layer=installed.layer else{fatalError("Missing installed channel: \(original.name)")}
   assert(layer.importedRack==original.layer?.importedRack && layer.midiProgram==original.layer?.midiProgram && layer.gain==original.layer?.gain && layer.pan==original.layer?.pan,"Installing a native pack must preserve authored processing/settings")
   if layer.gain==0 || layer.muted {print("Preserved silent source channel",original.name);continue}
   let audio=AudioController();try audio.prepareOffline();defer{audio.stop()}
   audio.onError={playbackErrors.append($0)}
   audio.panic();audio.configure(0,layer);audio.gain(0,layer.gain);audio.master(1);audio.space(0)
   for _ in 0..<20 {_ = try audio.offlineBlock()}
   let note=min(layer.high,max(layer.low,60))
   for velocity in [38,83,102,127] {
    audio.panic()
    audio.noteOn(key:note,pitch:note+(layer.transpose ?? 0),instrument:-1,layer:0,velocity:Float(velocity)/127)
    var peak:Float=0
    for _ in 0..<200 {let b=try audio.offlineBlock();for i in 0..<Int(b.frameLength){let v=b.floatChannelData![0][i];assert(v.isFinite);peak=max(peak,abs(v))}}
    audio.noteOff(key:note,channel:0)
    FileHandle.standardError.write(Data("Channel \(original.name), velocity \(velocity): peak \(peak), errors \(playbackErrors)\n".utf8))
    if peak<=0.0000001 {silentNames.append(original.name+" v"+String(velocity))}
    checks+=1
   }
  }
  assert(silentNames.isEmpty,"Silent channels: \(silentNames), errors: \(playbackErrors)")
  print("PASS: \(pack.sounds.count) MainStage channels preserve library settings; \(checks) velocity checks produce finite audio without opening MainStage")
 }
}
