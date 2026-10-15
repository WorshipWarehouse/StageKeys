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
  print("PASS: effect preset settings/core round-trip, invalid saves preserve archive, corrupt archive rejected")
 }
}
