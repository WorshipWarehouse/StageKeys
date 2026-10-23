import Foundation
import CoreMIDI
@main struct ManualMIDIDestinationRefreshTests {
 static func main()throws {
  let store=PerformanceStore(),name="StageKeys Refresh Test "+UUID().uuidString
  var client=MIDIClientRef(),destination=MIDIEndpointRef()
  assert(MIDIClientCreateWithBlock(name as CFString,&client,nil)==noErr)
  defer{if destination != 0{MIDIEndpointDispose(destination)};MIDIClientDispose(client);store.midi.stop()}
  assert(!store.midiDestinations.contains{$0.name.contains(name)})
  assert(MIDIDestinationCreateWithBlock(client,name as CFString,&destination,{_,_ in})==noErr)
  var id:Int32=0;assert(MIDIObjectGetIntegerProperty(destination,kMIDIPropertyUniqueID,&id)==noErr)
  // No run-loop turn: the queued setup notification has not invalidated cache.
  store.refreshMIDIDestinations()
  assert(store.midiDestinations.contains{$0.id==id},"Explicit Refresh must enumerate a newly added destination even when cache is populated")
  MIDIEndpointDispose(destination);destination=0;store.refreshMIDIDestinations()
  assert(!store.midiDestinations.contains{$0.id==id},"Explicit Refresh must remove a disposed destination")
  print("PASS: production-store manual refresh bypasses stale CoreMIDI destination cache")
 }
}
