import Foundation
@main struct NoFactorySoundsTests {
 static func main() throws {
  let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
  let store=PerformanceStore()
  assert(store.librarySounds.isEmpty && store.setlist.patches.count==1)
  assert(store.patch.name=="New Patch" && store.patch.layers.count==15)
  assert(store.patch.layers.allSatisfy{!$0.loaded && $0.name=="Add Sound" && $0.gain==0 && $0.instrument == -1})
  assert(store.patch.snapshots.count==5 && store.patch.snapshots.allSatisfy(\.isEmptySlot))
  assert(store.setlist.assignments.isEmpty && store.setlist.controlAssignments==nil && store.tonicSound==nil)
  try store.audio.prepareOffline();store.start();defer{store.audio.stop()}
  for note in [36,48,60,72,84]{store.noteOn(note,velocity:1);store.noteOn(note,velocity:1,hardware:true)}
  store.setSustain(true);store.modWheel=0.5
  store.toggleTonic(0);assert(store.tonic==nil && store.message?.contains("Choose or import") == true)
  // Even an obsolete serialized index cannot start a product factory generator.
  for instrument in 0..<3 {store.audio.noteOn(key:500+instrument,pitch:72,instrument:instrument,layer:instrument,velocity:1)}
  for _ in 0..<120 {let block=try store.audio.offlineBlock();for channel in 0..<Int(block.format.channelCount){for frame in 0..<Int(block.frameLength){assert(block.floatChannelData![channel][frame]==0,"Fresh profile or legacy index produced sound")}}}
  store.panic();store.message=nil;store.save();store.audio.stop()
  let restored=PerformanceStore();assert(restored.librarySounds.isEmpty && restored.patch.layers.allSatisfy{!$0.loaded} && restored.patch.snapshots.allSatisfy(\.isEmptySlot))
  // Existing user content and obsolete metadata are retained, not deleted or replaced.
  var legacy=Setlist();var old=Layer(name:"Retained Legacy Metadata",instrument:1,gain:0.7)
  old.pan = -0.3;old.effects[0]=AudioEffect.factoryDefault(kind:13)
  legacy.patches[0].layers[0]=old
  legacy.patches[0].layers[1]=TestFixtures.layer(gain:0.4,name:"Owned Synthetic Sample")
  let entry=LibrarySound(id:"owned-fixture",name:"Owned Synthetic Sample",collection:"My Sounds",sound:legacy.patches[0].layers[1].external,layer:legacy.patches[0].layers[1])
  let oldEntry=LibrarySound(id:"legacy-metadata",name:old.name,collection:"My Sounds",layer:old)
  try SoundLibrary(url:root.appendingPathComponent("sound-library.json")).write([entry,oldEntry])
  let sample=root.appendingPathComponent("Imported Sounds").appendingPathComponent(entry.sound!.fileName!)
  let hash=try AssetDigest.sha256(sample),encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
  let source=try encoder.encode(legacy);try source.write(to:root.appendingPathComponent("setlist.json"))
  let loaded=PerformanceStore()
  assert(loaded.librarySounds.count==2 && loaded.hasUnavailableLegacyVoices)
  let retained=try encoder.encode(loaded.setlist);assert(retained==source,"Existing metadata was silently rewritten")
  assert(!loaded.patch.layers[0].loaded && loaded.patch.layers[1].loaded)
  let unavailable=BrowserSound.library(loaded.librarySounds.first{$0.id==oldEntry.id}!)
  assert(!unavailable.playable && unavailable.unavailableReason != nil)
  try loaded.audio.prepareOffline();loaded.start();defer{loaded.audio.stop()}
  var separate=oldEntry;separate.id="legacy-owned-reference";separate.sound=entry.sound
  assert(BrowserSound.library(separate).playable,"An explicitly stored user sample reference must remain addable")
  loaded.addLibrarySound(separate,index:2)
  assert(loaded.patch.layers[2].external==entry.sound && loaded.patch.layers[2].effects==old.effects,"Adding an older catalog entry must keep its explicit sample and edits")
  loaded.noteOn(60,velocity:1)
  var energy=0.0
  for _ in 0..<40 {let block=try loaded.audio.offlineBlock();for frame in 0..<Int(block.frameLength){let value=Double(block.floatChannelData![0][frame]);energy+=value*value}}
  assert(energy>0.0001,"Owned imported content stopped working")
  let afterHash=try AssetDigest.sha256(sample);assert(afterHash==hash,"Original sample bytes changed")
  print("PASS: clean profile has no sounds, fifteen empty modules/five empty snapshots, no mappings and silent input/legacy indices; owned imports and legacy metadata preserved")
 }
}
