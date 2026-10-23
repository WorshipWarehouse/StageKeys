import Foundation
import AVFoundation
final class ParameterFixtureUnit:AUAudioUnit {
 let tree:AUParameterTree
 var current:AUValue=0
 init(_ address:AUParameterAddress)throws {
  let parameter=AUParameterTree.createParameter(withIdentifier:"level",name:"Level",address:address,min:0,max:1,unit:.generic,unitName:nil,flags:[.flag_IsReadable,.flag_IsWritable],valueStrings:nil,dependentParameters:nil)
  tree=AUParameterTree.createTree(withChildren:[parameter])
  try super.init(componentDescription:AudioComponentDescription(componentType:kAudioUnitType_Effect,componentSubType:0x74657374,componentManufacturer:0x53744b79,componentFlags:0,componentFlagsMask:0))
  tree.implementorValueObserver={ [weak self] _,value in self?.current=value }
  tree.implementorValueProvider={ [weak self] _ in self?.current ?? 0 }
 }
 override var parameterTree:AUParameterTree? {get{tree}set{}}
}
@main struct PluginParameterModelTests {
 static func main()throws {
  let first=try ParameterFixtureUnit(42),second=try ParameterFixtureUnit(99),model=PluginParameterModel()
  model.attach(first);assert(model.items.count==1 && model.items[0].id==42)
  model.set(42,2);assert(first.current==1 && model.items[0].value==1)
  first.tree.parameter(withAddress:42)!.value=0.3
  func drain(){RunLoop.main.run(until:Date().addingTimeInterval(0.15))}
  drain();assert(abs(model.items[0].value-0.3)<0.00001,"Tree observer must update generic controls")
  first.tree.parameter(withAddress:42)!.value=0.8
  model.attach(second);drain();assert(model.items[0].id==99 && model.items[0].value==0,"An old unit callback must not overwrite a newly attached unit")
  model.detach();second.tree.parameter(withAddress:99)!.value=0.6;drain();assert(model.items[0].value==0,"Detached observer must not update the model")
  print("PASS: real AU parameter-tree observation, bounded writes, unit replacement and observer removal")
 }
}
