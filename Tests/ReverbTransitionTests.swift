import Foundation
@main struct ReverbTransitionTests {
 @MainActor static func main()throws {
  let store=PerformanceStore();try store.audio.prepareOffline();defer{store.audio.stop()}
  var layer=Layer(name:"Tail test",instrument:0,gain:0.2);var fx=AudioEffect.factoryDefault(kind:15);var p=fx.values;p[8]=0;p[9]=1;p[2]=0.9;fx.parameters=p;layer.effects[0]=fx
  let first=Patch(name:"A",layers:[layer]+(0..<14).map{_ in Layer.empty()},snapshots:[])
  var second=first.duplicate();second.name="B"
  store.setlist.patches=[first,second];store.selected=0;store.audio.master(1);store.audio.space(0);store.start()
  store.noteOn(60);for _ in 0..<100{_ = try store.audio.offlineBlock()};store.noteOff(60)
  for _ in 0..<100{_ = try store.audio.offlineBlock()}
  func energy()throws->Double {var sum=0.0;for _ in 0..<40{let b=try store.audio.offlineBlock();for i in 0..<Int(b.frameLength){let x=Double(b.floatChannelData![0][i]);sum+=x*x}};return sum}
  let before=try energy();store.choose(1);let after=try energy();assert(before>1e-10 && after>1e-10,"Unchanged retained effect graph must retain its tail across patch selection")
  store.panic();for _ in 0..<8{_ = try store.audio.offlineBlock()};let cleared=try energy();FileHandle.standardError.write(Data("Tail energy before/after/Panic: \(before) / \(after) / \(cleared)\n".utf8));assert(sqrt(cleared/Double(40*512))<3.2e-6 && cleared<before*0.0001,"Explicit Panic must suppress the retained tail below -110 dBFS after buffered output drains")
  print("PASS: patch transition retains compatible reverb tail, explicit Panic clears it",before,after)
 }
}
