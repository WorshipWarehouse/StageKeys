import Foundation
@main struct LibraryOrderPersistenceTests {
 static func main()throws {
  // A fixed library: the only thing that may decide a Random order is the stored seed.
  let sounds=(0..<30).map{i -> BrowserSound in
      var sound=BrowserSound(id:"s\(i)",name:"Sound \(i)",collection:"Test",tags:.inferred(name:"Piano"))
      sound.rating=i%6;sound.addedOrder=i
      return sound
  }
  let identifiers=sounds.map(\.id)
  let defaultOrder=LibraryQuery().results(sounds).map(\.id)
  assert(LibraryQuery().ordering == .name,"A library with no stored preference still opens in Name order")
  assert(LibraryQuery(storedOrder:"Name",storedSeed:42).results(sounds).map(\.id) == defaultOrder,"A restored Name order ignores a stored seed")

  // Choosing Random draws a non-zero seed, and a relaunch reuses it verbatim, so the
  // list the performer was reading comes back instead of reshuffling.
  var chosen=LibraryQuery();chosen.order(by:.random)
  let chosenSeed=chosen.shuffleSeed
  assert(chosenSeed != 0,"Choosing Random stores a non-zero seed")
  chosen.ascending.toggle()
  let shown=chosen.results(sounds).map(\.id)
  let relaunched=LibraryQuery(storedOrder:"Random",storedSeed:chosenSeed,storedAscending:chosen.ascending)
  assert(relaunched.shuffleSeed == chosenSeed,"A stored Random seed is reused instead of redrawn")
  assert(relaunched.results(Array(sounds.reversed())).map(\.id) == shown,"The same Random order and the same seed reproduce the list after a relaunch")
  assert(Set(shown) == Set(identifiers),"A restored Random order keeps every sound")

  assert(relaunched.ascending==chosen.ascending,"A reversed Random direction must survive relaunch")
  let reversedRating=LibraryQuery(storedOrder:"Rating",storedSeed:nil,storedAscending:true)
  assert(reversedRating.results(sounds).first?.rating==0,"An explicitly reversed Rating order must override its default")

  // The seed is what decides the order: a known seed pins the list, and a different
  // seed produces a different one.
  let pinned=LibraryQuery(storedOrder:"Random",storedSeed:42).results(sounds).map(\.id)
  assert(pinned.first == "s4","The stored seed decides the Random order")
  let other=LibraryQuery(storedOrder:"Random",storedSeed:43).results(sounds).map(\.id)
  assert(other != pinned,"A different stored seed produces a different order")

  // Navigating out of the browser clears the search and filters; that must not
  // disturb the saved order or draw a new Random seed.
  var navigating=LibraryQuery(storedOrder:"Random",storedSeed:42)
  navigating.search="pad";navigating.filters[.type]="Synth Pads"
  assert(navigating.results(sounds).isEmpty,"The fixture search filters every row out")
  navigating.search="";navigating.filters=[:]
  assert(navigating.results(sounds).map(\.id) == pinned,"Clearing the search and filters keeps the saved Random order")
  assert(navigating.shuffleSeed == 42,"Clearing transient state does not draw a new seed")

  // An absent seed is drawn rather than stored as the 0 sentinel, and an unknown or
  // missing order falls back to Name without inventing a shuffle.
  assert(LibraryQuery(storedOrder:"Random",storedSeed:0).shuffleSeed != 0,"A missing Random seed is drawn, never kept as zero")
  let unknown=LibraryQuery(storedOrder:"Bogus",storedSeed:42)
  assert(unknown.ordering == .name && unknown.shuffleSeed == 0,"An unknown stored order falls back to Name")
  assert(unknown.results(sounds).map(\.id) == defaultOrder,"An unknown stored order is not applied to the list")
  assert(LibraryQuery(storedOrder:nil,storedSeed:nil).results(sounds).map(\.id) == defaultOrder,"A first launch with no stored preference keeps Name order")

  // Every other order restores its own direction, not Name's ascending one.
  var rating=LibraryQuery();rating.order(by:.rating)
  let ratingOrder=rating.results(sounds).map(\.id)
  let restoredRating=LibraryQuery(storedOrder:"Rating",storedSeed:42)
  assert(restoredRating.ordering == .rating && restoredRating.shuffleSeed == 0,"Rating restores without a shuffle seed")
  assert(restoredRating.results(sounds).map(\.id) == ratingOrder,"Rating restores its descending direction")
  assert(restoredRating.results(sounds).first?.rating == 5,"Rating still lists the highest rating first")
  assert(LibraryQuery(storedOrder:"Recently Added",storedSeed:42).results(sounds).first?.addedOrder == 29,"Recently Added still lists the newest sound first")
  assert(LibraryQuery(storedOrder:"Recommended",storedSeed:42).ascending == true,"Recommended keeps its ascending order")

  // Re-selecting Random still draws a fresh seed, so the command keeps working.
  var again=LibraryQuery();again.order(by:.random);let firstSeed=again.shuffleSeed
  again.order(by:.name);again.order(by:.random)
  assert(again.shuffleSeed != firstSeed,"Re-selecting Random draws a new seed")
  print("PASS: the library order and its Random seed are restored so the same list survives a relaunch")
 }
}
