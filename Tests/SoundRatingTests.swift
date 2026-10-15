import Foundation
@main struct SoundRatingTests {
 static func main()throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("ratings-"+UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
  let url=root.appendingPathComponent("ratings.json")
  let rated=SoundRatingArchive.setting(4,for:"piano",in:[:])!
  try SoundRatingArchive.save(rated,to:url);assert(SoundRatingArchive.load(url)==rated)
  assert(SoundRatingArchive.setting(0,for:"piano",in:rated)!.isEmpty)
  assert(SoundRatingArchive.setting(6,for:"piano",in:rated)==nil)
  do{try SoundRatingArchive.save(["piano":6],to:url);fatalError("Bad rating accepted")}catch{}
  assert(SoundRatingArchive.load(url)==rated)
  let oversized=Dictionary(uniqueKeysWithValues:(0..<8192).map{("\($0)"+String(repeating:"x",count:505),1)})
  do{try SoundRatingArchive.save(oversized,to:url);fatalError("Unreadably large archive saved")}catch{}
  assert(SoundRatingArchive.load(url)==rated)
  var a=BrowserSound(id:"a",name:"Alpha",collection:"Test",tags:.inferred(name:"Piano"));a.rating=1;a.addedOrder=2
  var b=BrowserSound(id:"b",name:"Beta",collection:"Test",tags:.inferred(name:"Pad"));b.rating=5;b.addedOrder=1
  var query=LibraryQuery();query.order(by:.rating);assert(query.results([a,b]).map(\.id)==["b","a"])
  query.ascending=true;assert(query.results([a,b]).map(\.id)==["a","b"])
  query.order(by:.recent);assert(query.results([a,b]).first?.id=="a")
  query.order(by:.random);let first=query.results([a,b]).map(\.id);assert(query.results([b,a]).map(\.id)==first,"Random must stay stable across view updates and input order")
  var tags=a.tags;tags.complexity="Simple";a=BrowserSound(id:"a",name:"Alpha",collection:"Test",tags:tags);query=LibraryQuery();query.filters[.complexity]="Simple";assert(query.results([a,b]).map(\.id)==["a"])
  let library=SoundLibrary(url:root.appendingPathComponent("library.json"))
  let sound=LibrarySound(id:"a",name:"Piano",collection:"My Sounds",hostPath:"/fixture.patch",tags:a.tags)
  try library.write([sound]);let read=try library.read();assert(read.first?.tags?.complexity=="Simple")
  print("PASS: rating persistence, clear, validation, numeric sort, recent insertion order, stable random order and complexity metadata")
 }
}
