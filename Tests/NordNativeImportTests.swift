import Foundation
import AVFoundation
@main struct NordNativeImportTests {
 @MainActor static func main() async throws {
  let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
  let source=root.appendingPathComponent("Synthetic.npno"),bytes=TestFixtures.nordPiano()
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  try bytes.write(to:source)
  let preview=try NordNative.preview(bytes)
  assert(preview.index.strokes.count==2 && preview.index.report.channels==2 && preview.zones.count==6)
  for key in 59...61 {
   let zones=preview.zones.filter{$0.key==key}
   assert(zones.map(\.velocityLow)==[1,58] && zones.map(\.velocityHigh)==[57,127])
   assert(zones.map(\.stroke)==[1,0])
   assert(zones.allSatisfy{abs($0.fineTuneCents-Double(key-60)*1.4)<0.00001})
  }
  assert(NordPiano.topVelocity(34)==96 && NordPiano.topVelocity(201)==0)
  func corrupt(_ edits:[Int:UInt8])->Data {
   var b=Array(bytes);for (at,value) in edits {b[44+at]=value}
   var crc:UInt32=0xffffffff
   for byte in b.dropFirst(44) {crc ^= UInt32(byte);for _ in 0..<8 {crc=(crc&1 != 0) ? (crc>>1)^0xedb88320:crc>>1}}
   crc ^= 0xffffffff;for i in 0..<4 {b[24+i]=UInt8(truncatingIfNeeded:crc>>(i*8))}
   return Data(b)
  }
  func refuses(_ invalid:Data) {do{_ = try NordNative.preview(invalid);fatalError("Accepted invalid directory/map") }catch{}}
  refuses(corrupt([0x732:0xff])) // oversized start, with a valid container CRC
  refuses(corrupt([0x732+6:0xff,0x732+7:0xff,0x732+8:0xff,0x732+9:0xff]))
  refuses(corrupt([0x732+10:0,0x732+11:0]))
  refuses(corrupt([0x8c+60:61])) // key points to an absent root
  refuses(corrupt([0x732+0x20:0xff])) // out-of-frame loop length
  refuses(corrupt([0x732+4:1,0x732+118+4:2])) // no attack bank
  refuses(Data(bytes.dropLast()))
  var checksum=bytes;checksum[checksum.count-1] ^= 1;refuses(checksum)
  let v5=try NordNative.preview(corrupt([5:0x50,0x61d:0x50,0x732+118+5:20,0x40c:20,0x732+0x35:2,0x732+118+0x35:2]))
  for key in 59...61 {
   let zones=v5.zones.filter{$0.key==key}
   assert(zones.map(\.velocityLow)==[1,86] && zones.map(\.velocityHigh)==[85,127])
   assert(zones.allSatisfy{$0.gainDB==0},"V5 library gain is tenths dB; stroke trim is whole dB")
  }
  let template=try NordNative.template()
  let managed=root.appendingPathComponent("scratch");try FileManager.default.createDirectory(at:managed,withIntermediateDirectories:true)
  let before=try FileManager.default.contentsOfDirectory(atPath:managed.path)
  do {_ = try NordNative.prepare(bytes,preview:preview,library:managed,template:template,cancelled:{true});fatalError("Cancelled conversion published")}catch{}
  assert(try! FileManager.default.contentsOfDirectory(atPath:managed.path)==before)
  var calls=0
  do {_ = try NordNative.prepare(bytes,preview:preview,library:managed,template:template,cancelled:{calls+=1;return calls>3});fatalError("Mid-decode cancellation published")}catch{}
  assert(try! FileManager.default.contentsOfDirectory(atPath:managed.path)==before)
  let store=PerformanceStore()
  func wait() async throws {for _ in 0..<3000 where store.libraryImportBusy {try await Task.sleep(nanoseconds:10_000_000)};assert(!store.libraryImportBusy)}
  store.inspectNordSound(source);try await wait();assert(store.nordImportPreview != nil,store.libraryImportProgress ?? "")
  assert(store.librarySounds.isEmpty,"Inspection installed a catalog entry")
  store.importNordSound();try await wait()
  guard let entry=store.librarySounds.first,let sound=entry.sound,let layer=entry.layer else{fatalError(store.libraryImportProgress ?? "Missing converted instrument")}
  assert(entry.id==preview.identity && sound.nativeSampler?.valid==true && entry.conversionNotes==preview.notes)
  let map=try StageKeysSampler.map(sound,library:store.audio.externalRack!.libraryURL)
  assert(map.zones.count==6 && map.sampleCount==2 && map.zones.allSatisfy(\.looped))
  let catalog=root.appendingPathComponent("sound-library.json"),saved=try Data(contentsOf:catalog)
  store.inspectNordSound(source);try await wait();store.importNordSound();try await wait()
  assert(store.librarySounds.count==1 && (try! Data(contentsOf:catalog))==saved)
  assert(try! Data(contentsOf:source)==bytes)
  let restarted=PerformanceStore();assert(restarted.librarySounds.first?.id==entry.id)
  let pack=root.appendingPathComponent("NordTransfer")
  try LibraryBackup.write([entry],library:root,to:pack)
  let archive=root.appendingPathComponent("Nord.stagekeyspack");try PersonalSoundArchive.write(pack,to:archive)
  let target=root.appendingPathComponent("second-device");setenv("STAGEKEYS_DATA_DIR",target.path,1)
  let destination=PerformanceStore();destination.importLibraryBackup(archive)
  for _ in 0..<3000 where destination.libraryImportBusy {try await Task.sleep(nanoseconds:10_000_000)}
  guard let installed=destination.librarySounds.first,let movedLayer=installed.layer else{fatalError(destination.libraryImportProgress ?? "Pack failed")}
  assert(installed.id==entry.id && installed.conversionNotes==entry.conversionNotes)
  func render(_ layer:Layer,root:URL)throws->Double {
   setenv("STAGEKEYS_DATA_DIR",root.path,1)
   let audio=AudioController();try audio.prepareOffline();defer{audio.stop()}
   audio.configure(0,layer);audio.gain(0,layer.gain,seconds:0);audio.master(0.1);audio.space(0)
   for _ in 0..<10 {_ = try audio.offlineBlock()}
   audio.noteOn(key:60,pitch:60,instrument:-1,layer:0,velocity:0.8)
   var energy=0.0
   for _ in 0..<70 {let b=try audio.offlineBlock();for c in 0..<Int(b.format.channelCount) {for f in 0..<Int(b.frameLength) {let v=Double(b.floatChannelData![c][f]);assert(v.isFinite);energy+=v*v}}}
   return energy
  }
  let a=try render(layer,root:root),b=try render(movedLayer,root:target)
  assert(a>0.001 && abs(sqrt(b/a)-1)<0.001,"Native playback or personal transfer changed")
  setenv("STAGEKEYS_DATA_DIR",root.path,1)
  store.inspectNordSound(source);store.cancelLibraryImport();try await wait();assert(store.nordImportPreview==nil)
  assert((try! Data(contentsOf:catalog))==saved)
  print("PASS Nord import: synthetic stereo/layers/tuning/loops, preview, cancellation rollback, native render, restart, duplicates and personal pack relocation")
 }
}
