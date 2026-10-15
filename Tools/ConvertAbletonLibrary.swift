import Foundation
import AVFoundation
import CryptoKit

/// Imports original sample maps, not rendered captures or complete Live racks.
@main struct ConvertAbletonLibrary {
    struct Item:Codable {
        var name:String
        var status:String
        var detail:String
        var zones:Int=0
        var layers:Int=0
        var warnings:[String]=[]
        var originalSampleHashes:[String:String]=[:]
        var checks:Int=0
    }
    static func main()throws {
        guard [4,5].contains(CommandLine.arguments.count) else{print("Usage: ConvertAbletonLibrary sourceFolderOrALP StageKeysDataDirectory report.json [collection]");return}
        let input=URL(fileURLWithPath:CommandLine.arguments[1]),base=URL(fileURLWithPath:CommandLine.arguments[2]),report=URL(fileURLWithPath:CommandLine.arguments[3])
        let collection=CommandLine.arguments.count==5 ? CommandLine.arguments[4] : "Imported Sounds"
        let extracted:URL?=input.pathExtension.lowercased()=="alp" ? try AbletonArchive.extract(input) : nil
        defer{if let extracted{try? FileManager.default.removeItem(at:extracted)}}
        let root=extracted ?? input,library=SoundLibrary(url:base.appendingPathComponent("sound-library.json")),engine=AVAudioEngine()
        let rack=try ExternalInstrumentRack(engine:engine,libraryURL:base.appendingPathComponent("Imported Sounds"))
        var entries=try library.read(),items:[Item]=[]
        let files=try SoundLibrary.samplerPresets(in:root).filter{["adg","adv"].contains($0.pathExtension.lowercased())}
        guard !files.isEmpty else{throw AbletonImportError.invalid("No Ableton presets found.")}
        for file in files {
            var item=Item(name:file.deletingPathExtension().lastPathComponent,status:"failed",detail:"")
            let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".aupreset")
            defer{try? FileManager.default.removeItem(at:temp)}
            do {
                let conversion=try AbletonImport.convert(file,sampleRoot:root,to:temp)
                item.zones=conversion.zones;item.layers=conversion.layers;item.warnings=conversion.warnings;item.originalSampleHashes=conversion.sampleHashes
                let hash=try AbletonArchive.sha256(file),id="ableton-samples-"+hash
                if entries.contains(where:{$0.id==id}){item.status="already imported";items.append(item);continue}
                var sound=try rack.importPreset(temp,sampleRoot:root);sound.name=conversion.name
                let managed=rack.libraryURL.appendingPathComponent(sound.fileName!)
                var published=false
                defer{if !published{try? FileManager.default.removeItem(at:managed);try? FileManager.default.removeItem(at:rack.libraryURL.appendingPathComponent(managed.deletingPathExtension().lastPathComponent+"-samples"))}}
                let state=try PropertyListSerialization.propertyList(from:Data(contentsOf:managed),options:[],format:nil) as! [String:Any]
                item.checks=try AbletonImport.validatePlayback(managed)
                let references=state["file-references"] as! [String:String]
                let copiedHashes=try Set(references.values.map{try AbletonArchive.sha256(URL(fileURLWithPath:$0))})
                guard copiedHashes == Set(conversion.sampleHashes.values) else{throw AbletonImportError.invalid("Original sample bytes changed during import.")}
                var layer=Layer(name:sound.name,instrument:-1,gain:0.5);layer.external=sound;layer.importedRack=conversion.rack;layer.midiProgram=conversion.midi
                let proposed=entries+[LibrarySound(id:id,name:sound.name,collection:collection,sound:sound,layer:layer,conversionNotes:conversion.warnings)]
                try library.write(proposed);entries=proposed;published=true
                item.status="imported";item.detail="Original audio bytes preserved; mapped notes rendered. This is a sample-map import; consult warnings for untranslated rack behavior."
            } catch{item.detail=error.localizedDescription}
            items.append(item)
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];try encoder.encode(items).write(to:report,options:.atomic)
            print("\(item.status): \(item.name) (\(item.zones) zones, \(item.checks) checks) \(item.status == "failed" ? item.detail : "")")
        }
        if items.contains(where:{$0.status=="failed"}){exit(1)}
    }
}
