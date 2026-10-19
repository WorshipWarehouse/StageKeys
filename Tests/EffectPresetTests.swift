import Foundation
@main struct EffectPresetTests {
 static func main()throws {
  let dir=FileManager.default.temporaryDirectory.appendingPathComponent("effect-presets-"+UUID().uuidString)
  defer{try? FileManager.default.removeItem(at:dir)}
  let url=dir.appendingPathComponent("effect-presets.json")
  var fx=AudioEffect();fx.kind=13;fx.parameters=[0,18,0.33,776,2884,0,0,1,0.23,1];fx.reverbCore="creamcoat"
  let preset=EffectPreset(name:"Piano Room",effect:fx)
  try EffectPresetArchive.save([preset],to:url);assert(EffectPresetArchive.load(url)==[preset])
  var bad=preset;bad.name=" ";do{try EffectPresetArchive.save([bad],to:url);fatalError("Invalid preset saved")}catch{}
  assert(EffectPresetArchive.load(url)==[preset],"Invalid save must preserve previous presets")
  try Data("corrupt".utf8).write(to:url);assert(EffectPresetArchive.load(url).isEmpty)
  var legacy=AudioEffect();legacy.kind=10;legacy.parameters=[0.75,0.66,0.9,0.75,0.5,100,10000,1,0.2]
  assert(legacy.validate() && legacy.values.count==10 && legacy.values[9]==1,"Legacy shimmer must keep full quality")
  var modern=legacy;modern.parameters=legacy.values;modern.parameters![9]=0.4
  let migrated=EffectPreset(name:"Soft Shimmer",effect:modern);try EffectPresetArchive.save([migrated],to:url)
  assert(EffectPresetArchive.load(url)==[migrated],"Shimmer quality must survive preset persistence")
  let delay=AudioEffect.factoryDefault(kind:3);assert(delay.values[1]==0.75 && delay.values[0]==0.3 && delay.values[2]==1000 && delay.values[3]==0.5)
  assert(delay.validate() && delay.playbackDelay?.pingPong==true && delay.playbackDelay?.leftSynced==true)
  let dp=EffectPreset(name:"Stereo eighth",effect:delay);try EffectPresetArchive.save([dp],to:url);assert(EffectPresetArchive.load(url)==[dp])
  var wrong=delay;wrong.kind=10;assert(!wrong.validate())
  print("PASS: effect preset settings/core round-trip, invalid saves preserve archive, corrupt archive rejected")
 }
}
