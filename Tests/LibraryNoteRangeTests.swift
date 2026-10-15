import Foundation
@main struct LibraryNoteRangeTests {
 static func main()throws {
  var tags=SoundTags(category:"Leads",type:"Mono Leads");tags.noteRanges=["Mid Range","Right Hand"]
  let lead=BrowserSound(id:"lead",name:"Flute",collection:"Fixture",tags:tags)
  var fullTags=SoundTags(category:"Acoustic Piano & Keys",type:"Felt Piano");fullTags.noteRanges=["Full Range"];fullTags.types=["Acoustic Piano","Felt Piano"]
  let full=BrowserSound(id:"full",name:"Felt",collection:"Fixture",tags:fullTags)
  let unknown=BrowserSound(id:"unknown",name:"Unknown",collection:"Fixture",tags:.inferred(name:"Piano"))
  for value in ["Mid Range","Right Hand"] {var query=LibraryQuery();query.filters[.noteRange]=value;assert(query.results([lead,full,unknown]).map(\.id)==["lead"])}
  var query=LibraryQuery();query.filters[.type]="Acoustic Piano";query.filters[.noteRange]="Full Range"
  assert(Set(query.results([lead,full,unknown]).map(\.id))==["full"])
  assert(query.options(.noteRange,in:[lead,full])==["All","Full Range","Left Hand","Mid Range","Right Hand"])
  query.filters[.noteRange]="Right Hand";assert(query.results([full]).isEmpty);assert(query.options(.type,in:[full]).contains("Acoustic Piano"),"Active filters must remain visible in empty results")
  query=LibraryQuery();query.filters[.noteRange]="Not Tagged";assert(query.results([lead,full,unknown]).map(\.id)==["unknown"])
  query.search="missing";assert(query.options(.noteRange,in:[full]).contains("Not Tagged"))
  assert(LibraryNoteRange.toggling(.right,in:["Mid Range"])==["Mid Range","Right Hand"])
  assert(LibraryNoteRange.toggling(.mid,in:["Mid Range","Right Hand"])==["Right Hand"])
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("range-"+UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
  let library=SoundLibrary(url:root.appendingPathComponent("library.json"))
  let native=LibrarySound(id:"native",name:"SK App Felt Piano v1_6",collection:"Sunday App · Native",sound:ExternalSound(kind:.samplerPreset,name:"Felt",fileName:"fixture.aupreset"))
  var old=SundayFactoryVoicing.feltRoom(from:native)!;old.tags!.noteRanges=nil;old.tags!.types=nil;old.layer!.low=36;old.layer!.high=84;old.layer!.gain=0.27
  try library.write([native,old]);var loaded=try library.read();let upgraded=loaded.first{$0.id==old.id}!
  assert(upgraded.tags!.noteRanges==["Full Range"] && upgraded.tags!.types==["Acoustic Piano","Felt Piano"])
  assert(upgraded.layer==old.layer,"Tag migration must not rewrite the sound or its playable range")
  old.tags!.noteRanges=[];try library.write([native,old]);loaded=try library.read();assert(loaded.first{$0.id==old.id}!.tags!.noteRanges==[],"Explicit clear must survive migration")
  var custom=LibrarySound(id:"custom",name:"Custom",collection:"My Sounds",hostPath:"/fixture.patch",tags:tags)
  custom.tags!.inferred=true;try library.write([custom]);loaded=try library.read();assert(loaded[0].tags!.noteRanges==tags.noteRanges)
  var archiveTags=tags;archiveTags.noteRanges=["Left Hand"]
  let original=LibrarySound(id:"host",name:"Original",collection:"MainStage Archive",hostPath:"/original.patch",tags:archiveTags)
  custom.tags=tags;let alias=BrowserSound.archive(original,converted:custom)
  assert(alias.ratingID==custom.id && alias.values(.noteRange)==tags.noteRanges! && alias.id==original.id)
  custom.tags!.noteRanges=[];assert(BrowserSound.archive(original,converted:custom).values(.noteRange)==["Not Tagged"])
  for invalid in [["Right Hand","Right Hand"],["Upper Keys"]] {custom.tags!.noteRanges=invalid;do{try library.write([custom]);fatalError("Invalid Note Range tags accepted")}catch{}}
  let legacy=try JSONDecoder().decode(SoundTags.self,from:Data("{\"category\":\"Keys\",\"type\":\"Piano\",\"timbres\":[],\"articulations\":[],\"sourceModel\":\"Sampler\",\"inferred\":false}".utf8));assert(legacy.noteRanges==nil && legacy.types==nil)
  print("PASS: overlapping range/type filters, fixed range choices, unknown metadata, toggle, legacy migration, explicit clear and audio-range preservation")
 }
}
