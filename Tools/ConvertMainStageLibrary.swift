import Foundation
import AVFoundation

/// Stage original EXS instruments plus supported channel processing. Does not
/// launch MainStage, render replacement samples, or mutate an installed library.
@main struct ConvertMainStageLibrary {
 struct Item:Codable {var patch:String;var channel:String;var status:String;var detail:String;var notes:[String]=[]}
 static func main()throws {
  guard CommandLine.arguments.count==5 else{print("Usage: ConvertMainStageLibrary patchFolder sampleRoot NEW-outputFolder report.json");return}
  let source=URL(fileURLWithPath:CommandLine.arguments[1]),samples=URL(fileURLWithPath:CommandLine.arguments[2]),output=URL(fileURLWithPath:CommandLine.arguments[3]),reportFile=URL(fileURLWithPath:CommandLine.arguments[4])
  guard !FileManager.default.fileExists(atPath:output.path) else{throw MainStagePatch.Failure.invalid("Choose a new staging folder; installed libraries are never overwritten.")}
  try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
  let engine=AVAudioEngine(),rack=try ExternalInstrumentRack(engine:engine,libraryURL:output.appendingPathComponent("Imported Sounds"))
  var patches:[URL]=[]
  if source.pathExtension=="patch" {patches=[source]}
  else if let files=FileManager.default.enumerator(at:source,includingPropertiesForKeys:[.isSymbolicLinkKey]) {
   for case let file as URL in files {
    if (try file.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink==true{files.skipDescendants();continue}
    if file.pathExtension=="patch" {patches.append(file);files.skipDescendants()}
    guard patches.count<=4096 else{throw CocoaError(.fileReadTooLarge)}
   }
  }
  var reports:[(URL,MainStagePatch.Report)]=[],unreadable:[Item]=[]
  for patch in patches.sorted(by:{$0.path<$1.path}) {
   do{reports.append((patch,try MainStagePatch.inspect(patch)))}
   catch{unreadable.append(Item(patch:patch.lastPathComponent,channel:"",status:"blocked",detail:error.localizedDescription))}
  }
  let names=Set(reports.flatMap{$0.1.channels.flatMap(\.instruments)})
  let instruments=try MainStagePatch.findSamplerInstruments(names,in:samples)
  var cache:[String:ExternalSound]=[:],entries:[LibrarySound]=[],items:[Item]=unreadable
  let library=SoundLibrary(url:output.appendingPathComponent("sound-library.json"))
  func save()throws {
   try library.write(entries)
   let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
   try encoder.encode(items).write(to:reportFile,options:.atomic)
  }
  for (patch,report) in reports {
   let document=try PropertyListSerialization.propertyList(from:MainStagePatch.read(patch.appendingPathComponent("data.plist"),in:patch),options:[],format:nil) as! [String:Any]
   let channels=document["channels"] as? [[String:Any]] ?? []
   var retainedID:String?
   for channel in report.channels {
    var item=Item(patch:report.name,channel:channel.name,status:"unsupported",detail:"")
    do {
     guard channel.instruments.count==1,let name=channel.instruments.first else{item.detail="Requires native instrument engine: "+channel.devices.map(\.name).joined(separator:", ");items.append(item);continue}
     let matches=instruments.filter{$0.lastPathComponent==name}
     guard matches.count==1 else{throw MainStagePatch.Failure.invalid(matches.isEmpty ? "Original EXS not installed: "+name:"Ambiguous EXS: "+name)}
     let instrument=matches[0],hash=try AssetDigest.sha256(instrument)
     let sound:ExternalSound
     if let cached=cache[hash] {sound=cached}
     else {sound=try rack.importEXS(instrument,sampleRoot:samples);cache[hash]=sound}
     let original=try StageKeysSampler.retainOriginal(instrument,library:output)
     let channelData=channels.first{$0["Filename"] as? String==channel.file} ?? [:]
     var processing=try MainStageProcessing.translate(MainStagePatch.read(patch.appendingPathComponent(channel.file),in:patch),channelID:channelData["Channel_instID"] as? Int)
     MainStageProcessing.channelSettings(channelData,to:&processing)
     let display=SoundLibrary.cleanImportedName(report.name)+(report.channels.count==1 ? "":" · "+SoundLibrary.cleanImportedName(channel.name))
     var layer=Layer(name:display,instrument:-1,gain:1);layer.external=sound;layer.importedRack=sound.nativeSampler?.rack
     layer=try processing.applying(to:layer)
     if retainedID==nil {
      let target=output.appendingPathComponent("MainStage Sources/"+UUID().uuidString)
      _ = try MainStagePatch.retain(patch,to:target);retainedID=target.lastPathComponent
     }
     let notes=(sound.nativeSampler?.notes ?? [])+processing.issues
     let id="mainstage-channel-"+channel.sha256+"-"+hash
     if !entries.contains(where:{$0.id==id}) {entries.append(LibrarySound(id:id,name:display,collection:"MainStage Patches",sound:sound,layer:layer,sourceArchiveID:retainedID,conversionNotes:notes,originalInstrument:original))}
     item.status="staged";item.detail="Original samples and source retained; supported channel processing attached. Audio fidelity requires verification.";item.notes=notes
    } catch {item.status="blocked";item.detail=error.localizedDescription}
    items.append(item);try save();print("\(item.status): \(item.patch) / \(item.channel): \(item.detail)")
   }
  }
  try save();print("Staged \(entries.count) native channels; \(items.filter{$0.status != "staged"}.count) unsupported or blocked channels. No installed sounds changed.")
 }
}
