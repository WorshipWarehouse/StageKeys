import Foundation

/// Rebuild source sampler controls while retaining installed sample maps and filenames.
@main struct RepairSamplerVoicing {
 static func main()throws {
  guard CommandLine.arguments.count==6 else{fatalError("Usage: RepairSamplerVoicing managed.aupreset source.adg sampleRoot backup.aupreset report.json")}
  let managed=URL(fileURLWithPath:CommandLine.arguments[1]),source=URL(fileURLWithPath:CommandLine.arguments[2]),root=URL(fileURLWithPath:CommandLine.arguments[3]),backup=URL(fileURLWithPath:CommandLine.arguments[4]),report=URL(fileURLWithPath:CommandLine.arguments[5])
  guard !FileManager.default.fileExists(atPath:backup.path) else{throw SamplerInterchangeError.destinationExists}
  let temporary=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".aupreset");defer{try? FileManager.default.removeItem(at:temporary)}
  let conversion=try AbletonImport.convert(source,sampleRoot:root,to:temporary)
  func read(_ url:URL)throws->[String:Any]{guard let state=try PropertyListSerialization.propertyList(from:Data(contentsOf:url),options:[],format:nil) as? [String:Any] else{throw SamplerInterchangeError.invalidPreset};return state}
  var state=try read(managed);let rebuilt=try read(temporary)
  guard var instrument=state["Instrument"] as? [String:Any],var layers=instrument["Layers"] as? [[String:Any]],let updated=(rebuilt["Instrument"] as? [String:Any])?["Layers"] as? [[String:Any]],layers.count==updated.count,let refs=state["file-references"] as? [String:String],let sourceRefs=rebuilt["file-references"] as? [String:String],Set(refs.keys)==Set(sourceRefs.keys) else{throw SamplerInterchangeError.invalidPreset}
  for (key,path) in refs {guard let sourcePath=sourceRefs[key],try AbletonArchive.sha256(URL(fileURLWithPath:path)) == AbletonArchive.sha256(URL(fileURLWithPath:sourcePath)) else{throw AbletonImportError.invalid("Source sample differs; installed preset preserved.")}}
  for i in layers.indices {
   guard let old=layers[i]["Zones"] as? NSArray,let new=updated[i]["Zones"] as? NSArray,old.isEqual(new) else{throw AbletonImportError.invalid("Source sample map differs; installed preset preserved.")}
   for key in ["Filters","Connections","Envelopes","LFOs"] {layers[i][key]=updated[i][key]}
  }
  instrument["Layers"]=layers;state["Instrument"]=instrument
  try FileManager.default.copyItem(at:managed,to:backup)
  try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:managed,options:.atomic)
  try JSONSerialization.data(withJSONObject:["name":conversion.name,"layers":layers.count,"samples":refs.count,"audioBytesUnchanged":true,"warnings":conversion.warnings],options:[.prettyPrinted,.sortedKeys]).write(to:report,options:.atomic)
  print("Restored source sampler filter, velocity and envelope controls; sample maps and audio bytes unchanged.")
 }
}
