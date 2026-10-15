import Foundation
/// Apply the observed Room voicing only to pristine native Felt Piano modules in a named patch.
@main struct ApplyFactoryVoicing {
 static func main()throws {
  guard CommandLine.arguments.count==5 else{fatalError("Usage: ApplyFactoryVoicing StageKeysDataDirectory patchName NEW-backup.json report.json")}
  let base=URL(fileURLWithPath:CommandLine.arguments[1]),name=CommandLine.arguments[2],backup=URL(fileURLWithPath:CommandLine.arguments[3]),report=URL(fileURLWithPath:CommandLine.arguments[4]),file=base.appendingPathComponent("setlist.json")
  guard !FileManager.default.fileExists(atPath:backup.path) else{throw SamplerInterchangeError.destinationExists}
  let data=try Data(contentsOf:file);var setlist=try JSONDecoder().decode(Setlist.self,from:data);try setlist.validate()
  let library=try SoundLibrary(url:base.appendingPathComponent("sound-library.json")).read()
  var changed:[String]=[]
  for p in setlist.patches.indices where setlist.patches[p].name==name {
   for i in setlist.patches[p].layers.indices {
    let original=setlist.patches[p].layers[i],pristine=Layer(name:original.name,instrument:-1,gain:0.5)
    guard original.channelSettings==pristine.channelSettings,original.effects.allSatisfy({$0.kind==0}),original.importedRack==nil,original.midiProgram==nil,
          let entry=library.first(where:{$0.name.hasPrefix("SK App Felt Piano") && $0.sound?.fileName==original.external?.fileName}),let voiced=SundayFactoryVoicing.feltRoom(from:entry)?.layer else{continue}
    setlist.patches[p].layers[i].channelSettings=voiced.channelSettings;setlist.patches[p].layers[i].effects=voiced.effects
    if original.name==entry.name {setlist.patches[p].layers[i].name=voiced.name}
    for scene in setlist.patches[p].snapshots.indices {
      if let states=setlist.patches[p].snapshots[scene].sounds,states.indices.contains(i),states[i].effects.allSatisfy({$0.kind==0}) {setlist.patches[p].snapshots[scene].sounds![i].effects=voiced.effects}
    }
    changed.append("\(name) · Module \(i+1)")
   }
  }
  try setlist.validate();try data.write(to:backup,options:.atomic)
  if !changed.isEmpty {let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];try encoder.encode(setlist).write(to:file,options:.atomic)}
  try JSONSerialization.data(withJSONObject:["updated":changed,"gainsAndRoutingPreserved":true],options:[.prettyPrinted,.sortedKeys]).write(to:report,options:.atomic)
  print("Applied Room voicing to \(changed.count) pristine modules; custom controls, levels and routing preserved.")
 }
}
