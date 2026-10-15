import Foundation
@main struct UpgradeImportedBehavior {
    static func main() throws {
        guard [4,5,6].contains(CommandLine.arguments.count) else{fatalError("Usage: upgrade-imported-behavior library.json sourceFolderOrALP report.json [baseline-library.json] [native-preset-backup-directory]")}
        let library=SoundLibrary(url:URL(fileURLWithPath:CommandLine.arguments[1])),input=URL(fileURLWithPath:CommandLine.arguments[2]),report=URL(fileURLWithPath:CommandLine.arguments[3])
        let extracted=input.pathExtension.lowercased()=="alp" ? try AbletonArchive.extract(input):nil
        defer{if let extracted{try? FileManager.default.removeItem(at:extracted)}}
        let baseline=CommandLine.arguments.count>=5 ? try SoundLibrary(url:URL(fileURLWithPath:CommandLine.arguments[4])).read():[]
        var entries=try library.read(),rows:[[String:Any]]=[]
        for file in try SoundLibrary.samplerPresets(in:extracted ?? input) where ["adg","adv"].contains(file.pathExtension.lowercased()) {
            let id="ableton-samples-"+(try AbletonArchive.sha256(file))
            guard let index=entries.firstIndex(where:{$0.id==id}),entries[index].layer?.importedRack?.translationVersion != 6,let sound=entries[index].sound else{continue}
            let existing=entries[index].layer
            if existing != nil && existing?.importedRack != baseline.first(where:{$0.id==id})?.layer?.importedRack {
                rows.append(["id":id,"name":entries[index].name,"status":"preserved customized rack"]);continue
            }
            let temporary=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".aupreset")
            defer{try? FileManager.default.removeItem(at:temporary)}
            let conversion=try AbletonImport.convert(file,sampleRoot:extracted ?? input,to:temporary)
            guard let filename=sound.fileName,filename==URL(fileURLWithPath:filename).lastPathComponent else{throw AbletonImportError.invalid("Imported sound has no managed preset filename.")}
            let managed=library.url.deletingLastPathComponent().appendingPathComponent("Imported Sounds").appendingPathComponent(filename)
            func layout(_ url:URL)throws->[String] {
                guard let state=try PropertyListSerialization.propertyList(from:Data(contentsOf:url),options:[],format:nil) as? [String:Any],let instrument=state["Instrument"] as? [String:Any],let layers=instrument["Layers"] as? [[String:Any]] else{throw AbletonImportError.invalid("Invalid managed sample-layer layout.")}
                return try layers.map { layer in
                    guard let zones=layer["Zones"] as? [[String:Any]] else{throw AbletonImportError.invalid("Missing managed sample zones.")}
                    return zones.map {zone in ["waveform","min key","max key","min vel","max vel","root key","sample start","sample end"].map{String(describing:zone[$0] ?? "")}.joined(separator:":")}.joined(separator:"|")
                }
            }
            guard try layout(temporary)==layout(managed) else{throw AbletonImportError.invalid("Installed sample-layer layout differs; original library entry preserved.")}
            var samplerRebuilt=false
            if CommandLine.arguments.count==6 {
                func state(_ url:URL)throws->[String:Any] {guard let result=try PropertyListSerialization.propertyList(from:Data(contentsOf:url),options:[],format:nil) as? [String:Any] else{throw SamplerInterchangeError.invalidPreset};return result}
                var original=try state(managed);let rebuilt=try state(temporary)
                guard var instrument=original["Instrument"] as? [String:Any],var layers=instrument["Layers"] as? [[String:Any]],let incoming=(rebuilt["Instrument"] as? [String:Any])?["Layers"] as? [[String:Any]],layers.count==incoming.count,let refs=original["file-references"] as? [String:String],let incomingRefs=rebuilt["file-references"] as? [String:String],Set(refs.keys)==Set(incomingRefs.keys) else{throw SamplerInterchangeError.invalidPreset}
                let sampleRoot=managed.deletingLastPathComponent().resolvingSymlinksInPath().path+"/"
                for (key,path) in refs {let sample=URL(fileURLWithPath:path).resolvingSymlinksInPath();guard sample.path.hasPrefix(sampleRoot),let sourcePath=incomingRefs[key],try AbletonArchive.sha256(sample)==AbletonArchive.sha256(URL(fileURLWithPath:sourcePath)) else{throw AbletonImportError.invalid("Source sample differs; installed preset preserved.")}}
                for i in layers.indices {guard let old=layers[i]["Zones"] as? NSArray,let new=incoming[i]["Zones"] as? NSArray,old.isEqual(new) else{throw AbletonImportError.invalid("Source sample zones differ; installed preset preserved.")};for key in ["Filters","Connections","Envelopes","LFOs"] {layers[i][key]=incoming[i][key]}}
                let backupRoot=URL(fileURLWithPath:CommandLine.arguments[5]);try FileManager.default.createDirectory(at:backupRoot,withIntermediateDirectories:true)
                let backup=backupRoot.appendingPathComponent(filename);if !FileManager.default.fileExists(atPath:backup.path) {try FileManager.default.copyItem(at:managed,to:backup)}
                instrument["Layers"]=layers;original["Instrument"]=instrument
                try PropertyListSerialization.data(fromPropertyList:original,format:.xml,options:0).write(to:managed,options:.atomic);samplerRebuilt=true
            }
            var warnings=conversion.warnings
            if !samplerRebuilt {warnings.removeAll{$0.hasPrefix("Amplitude velocity depth is retained") || $0.hasPrefix("Saved clean low-pass cutoff")};warnings.append("Only rack metadata was upgraded; run with a native preset backup directory to restore source sampler filter/velocity controls.")}
            let behavior=AbletonImport.Behavior(rack:conversion.rack,midi:conversion.midi,warnings:warnings)
            var layer=existing ?? Layer(name:entries[index].name,instrument:-1,gain:0.5);layer.external=sound
            entries[index].previousImportedRack=existing?.importedRack
            layer.importedRack=behavior.rack
            if layer.midiProgram == baseline.first(where:{$0.id==id})?.layer?.midiProgram {layer.midiProgram=behavior.midi}
            entries[index].layer=layer
            let retained=(entries[index].conversionNotes ?? []).filter{!$0.hasPrefix("Sample-map conversion: Live rack") && !$0.hasPrefix("Not translated") && !$0.hasPrefix("Mapped effect macros") && !$0.hasPrefix("Reverb uses") && !$0.hasPrefix("EQ3 uses") && !$0.hasPrefix("Compressor attack") && !$0.hasPrefix("Parallel outer")}
            entries[index].conversionNotes=retained+behavior.warnings
            rows.append(["id":id,"name":layer.name,"status":"upgraded","samplerControlsRebuilt":samplerRebuilt,"branches":behavior.rack.branches?.count ?? 0,"delays":behavior.rack.effects.filter{$0.importedDelay != nil}.count,"effects":behavior.rack.effects.count,"macros":behavior.rack.macros.count,"midi":behavior.midi != nil,"warnings":behavior.warnings])
        }
        try library.write(entries)
        try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:report,options:.atomic)
        print("Updated \(rows.count) library entries; existing samples and saved performance patches were not rewritten.")
    }
}
