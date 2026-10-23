import Foundation
@main struct PrimaVerbModelTests {
 static func main()throws {
  var legacy=AudioEffect();legacy.kind=13;legacy.parameters=[0,18,0.33,776,2884,0,0.01,1,0.23]
  assert(legacy.validate()&&legacy.values.count==10&&legacy.values[9]==1)
  assert(legacy.usesCreamCoat && legacy.renderValues.last==1)
  var other=legacy;other.parameters![1]=42;assert(!other.usesCreamCoat && other.renderValues.last==0)
  other.reverbCore="creamcoat";assert(other.usesCreamCoat && other.validate())
  other.reverbCore="invalid";assert(!other.validate())
  let bytes=try JSONEncoder().encode(legacy);let decoded=try JSONDecoder().decode(AudioEffect.self,from:bytes)
  assert(decoded==legacy&&decoded.parameters?.count==9&&decoded.values[9]==1,"Opening an old patch must not rewrite its stored settings")
  var current=legacy;var values=current.values;values[6]=0;values[9]=0.4;current.parameters=values;assert(current.validate())
  current.parameters![9]=1.01;assert(!current.validate());current.parameters=Array(repeating:0,count:8);assert(!current.validate())
  let source=LibrarySound(id:"fixture",name:"SK App Felt Piano v1_6",collection:"Private",sound:ExternalSound(kind:.samplerPreset,name:"Felt",fileName:"fixture.aupreset"))
  let room=SundayFactoryVoicing.feltRoom(from:source)!.layer!;assert(room.effects[1].validate()&&room.effects[1].values[6]==0&&room.effects[1].values[9]==1)
  for kind in [13,15] {
   let effect=AudioEffect.factoryDefault(kind:kind);assert(effect.reverbCore=="dense-v1" && effect.validate())
   let decoded=try JSONDecoder().decode(AudioEffect.self,from:JSONEncoder().encode(effect));assert(decoded==effect && decoded.renderValues.last==(kind==13 ? 2:1))
   var old=effect;old.reverbCore=nil;assert(old.validate() && old.renderValues.last==0)
  }
  print("PASS: legacy PrimaVerb keeps stored values, missing Quality defaults to 100%, zero chorus rate validates, and Felt Room retains observed controls")
 }
}
