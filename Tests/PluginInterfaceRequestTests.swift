import Foundation
import AVFoundation
@main struct PluginInterfaceRequestTests {
 static func main() throws {
  let store=PerformanceStore()
  store.setlist.patches=[Patch(name:"Fixture A",layers:[Layer(name:"Empty",instrument:-1,gain:0)],snapshots:[]),
                         Patch(name:"Fixture B",layers:[Layer(name:"Empty",instrument:-1,gain:0)],snapshots:[])]
  let sound=ExternalSound(kind:.audioUnit,name:"Synthetic AU",component:ExternalAUIdentity(type:0x61756d75,subtype:1,manufacturer:2,name:"Synthetic AU"))
  store.setlist.patches[0].layers[0].external=sound
  store.requestPluginInterface(0);assert(store.takePluginInterfaceRequest()==0)
  assert(store.takePluginInterfaceRequest()==nil,"A dismiss callback must consume only once")
  store.requestPluginInterface(0);store.selected=1
  assert(store.takePluginInterfaceRequest()==nil,"A patch change must invalidate the handoff")
  store.selected=0;store.requestPluginInterface(0);store.setlist.patches[0].layers[0].id=UUID()
  assert(store.takePluginInterfaceRequest()==nil,"Replacing a layer must not open its old editor")
  store.requestPluginInterface(0);store.setlist.patches[0].layers[0].external?.name="Replacement"
  assert(store.takePluginInterfaceRequest()==nil,"Replacing a component/state reference must invalidate the request")
  store.requestPluginInterface(0);store.patchLock=true
  assert(store.takePluginInterfaceRequest()==nil)
  store.patchLock=false;store.requestPluginInterface(0);store.requestPluginInterface(-1)
  assert(store.takePluginInterfaceRequest()==nil,"Invalid/new requests must clear an old request")
  store.requestPluginInterface(0);store.choose(-1)
  assert(store.takePluginInterfaceRequest()==nil,"A selection attempt cancels pending presentation before routing")
  store.setlist.patches[0].layers[0].external=nil;store.requestPluginInterface(0)
  assert(store.takePluginInterfaceRequest()==nil,"Built-in and sample sounds must not request an AU editor")
  // Retry must submit a real host load, and stopped audio must stay stopped.
  assert(!store.retryPluginInterfaceLoad(0))
  store.setlist = TestFixtures.setlist()
  try store.audio.prepareOffline(); store.start()
  let rack = store.audio.externalRack!
  var callbacks: [(AVAudioUnit?, Error?) -> Void] = []
  rack.debugInstantiate = { _, completion in callbacks.append(completion) }
  store.setlist.patches[store.selected].layers[0].external = sound
  let authored = store.patch.layers[0]
  assert(store.retryPluginInterfaceLoad(0) && callbacks.count == 1)
  assert(store.patch.layers[0] == authored)
  store.stopAudio()
  assert(!store.retryPluginInterfaceLoad(0) && callbacks.count == 1)
  callbacks[0](nil, NSError(domain: "generated", code: 1))
  RunLoop.current.run(until: Date().addingTimeInterval(0.02))
  print("PASS: one-shot AU editor handoff rejects patch/layer/component replacement, invalid indices, lock and non-AU sounds")
 }
}
