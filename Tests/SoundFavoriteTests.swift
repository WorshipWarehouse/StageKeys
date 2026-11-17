import Foundation
@main struct SoundFavoriteTests {
 static func main()throws {
  var tags=SoundTags(category:"Leads",type:"Mono Leads");tags.noteRanges=["Mid Range"]
  let lead=BrowserSound(id:"lead",name:"Flute",collection:"Fixture",tags:tags)
  var favorited=lead;favorited.favorite=true
  let felt=BrowserSound(id:"felt",name:"Felt",collection:"Fixture",tags:tags)

  // Favorites are a personal filter, not a tag: an untagged sound can be one,
  // and the filter composes with search without inventing a facet value.
  var query=LibraryQuery();query.favoritesOnly=true
  assert(query.results([favorited,felt]).map(\.id)==["lead"])
  query.search="felt";assert(query.results([favorited,felt]).isEmpty)
  query.search="";assert(query.results([favorited]).map(\.id)==["lead"])
  query.favoritesOnly=false;assert(query.results([favorited,felt]).count==2)
  assert(query.matches(favorited) && query.matches(felt))

  assert(SoundFavoriteArchive.toggling("lead",in:[:])==["lead":true])
  assert(SoundFavoriteArchive.toggling("lead",in:["lead":true])?.isEmpty==true)
  assert(SoundFavoriteArchive.toggling("",in:[:])==nil,"An empty identity is not a favorite")
  assert(SoundFavoriteArchive.toggling(String(repeating:"a",count:513),in:[:])==nil,"Oversized identities are refused")
  assert(SoundFavoriteArchive.valid([:]) && !SoundFavoriteArchive.valid(["lead":false]),"Only stored favorites are valid")
  assert(!SoundFavoriteArchive.valid(["":true]))

  let root=FileManager.default.temporaryDirectory.appendingPathComponent("favorites-"+UUID().uuidString,isDirectory:true)
  defer{try? FileManager.default.removeItem(at:root)}
  let url=root.appendingPathComponent("sound-favorites.json")
  assert((try? SoundFavoriteArchive.read(url))?.isEmpty==true,"A missing file reads as no favorites")
  try SoundFavoriteArchive.save(["lead":true],to:url)
  let saved=try SoundFavoriteArchive.read(url);assert(saved==["lead":true])
  try SoundFavoriteArchive.save(["lead":true,"felt":true],to:url)
  let both=try SoundFavoriteArchive.read(url);assert(both.count==2)
  let refused=(try? SoundFavoriteArchive.save(["lead":false],to:url))==nil
  assert(refused,"A false entry must be refused before writing")
  let intact=try SoundFavoriteArchive.read(url);assert(intact.count==2,"A refused write must leave the saved favorites intact")

  // A damaged primary keeps its bytes and the previous validated copy restores.
  try Data("{".utf8).write(to:url)
  assert(SoundFavoriteArchive.load(url).isEmpty,"A damaged file must not load as favorites")
  let recovered=try SoundFavoriteArchive.recover(url)
  assert(recovered==["lead":true],"Recovery restores the previous validated copy")
  let restored=try SoundFavoriteArchive.read(url);assert(restored==["lead":true])

  // Toggling through the store writes a file the next launch can read.
  let data=root.appendingPathComponent("data",isDirectory:true)
  try FileManager.default.createDirectory(at:data,withIntermediateDirectories:true)
  setenv("STAGEKEYS_DATA_DIR",data.path,1)
  let store=PerformanceStore()
  assert(store.soundFavorites.isEmpty && !store.favoritesRecoveryRequired)
  store.toggleFavorite("native-felt")
  assert(store.soundFavorites["native-felt"]==true)
  let relaunched=PerformanceStore()
  assert(relaunched.soundFavorites["native-felt"]==true,"Favorites must survive a relaunch")
  assert(!relaunched.favoritesRecoveryRequired)
  relaunched.toggleFavorite("native-felt")
  assert(relaunched.soundFavorites.isEmpty)
  let afterRemoval=PerformanceStore()
  assert(afterRemoval.soundFavorites.isEmpty,"Removing a favorite must persist too")

  print("PASS: favorites filter, toggle archive, bounded validation, previous-copy recovery and relaunch persistence")
 }
}
