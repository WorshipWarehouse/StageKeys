import Foundation
@main struct UpgradeImportedBehavior {
    static func main() throws {
        guard [4,5].contains(CommandLine.arguments.count) else{fatalError("Usage: upgrade-imported-behavior library.json sourceFolderOrALP report.json [baseline-library.json]")}
        let library=SoundLibrary(url:URL(fileURLWithPath:CommandLine.arguments[1])),input=URL(fileURLWithPath:CommandLine.arguments[2]),report=URL(fileURLWithPath:CommandLine.arguments[3])
        let extracted=input.pathExtension.lowercased()=="alp" ? try AbletonArchive.extract(input):nil
        defer{if let extracted{try? FileManager.default.removeItem(at:extracted)}}
        let baseline=CommandLine.arguments.count==5 ? try SoundLibrary(url:URL(fileURLWithPath:CommandLine.arguments[4])).read():[]
        var entries=try library.read(),rows:[[String:Any]]=[]
        for file in try SoundLibrary.samplerPresets(in:extracted ?? input) where ["adg","adv"].contains(file.pathExtension.lowercased()) {
            let id="ableton-samples-"+(try AbletonArchive.sha256(file))
            guard let index=entries.firstIndex(where:{$0.id==id}),entries[index].layer?.importedRack?.translationVersion != 4,let sound=entries[index].sound else{continue}
            let existing=entries[index].layer
            if existing != nil && existing?.importedRack != baseline.first(where:{$0.id==id})?.layer?.importedRack {
                rows.append(["id":id,"name":entries[index].name,"status":"preserved customized rack"]);continue
            }
            let temporary=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".aupreset")
            defer{try? FileManager.default.removeItem(at:temporary)}
            let conversion=try AbletonImport.convert(file,sampleRoot:extracted ?? input,to:temporary)
            guard let filename=sound.fileName else{throw AbletonImportError.invalid("Imported sound has no managed preset filename.")}
            let managed=library.url.deletingLastPathComponent().appendingPathComponent("Imported Sounds").appendingPathComponent(filename)
            func layout(_ url:URL)throws->[String] {
                guard let state=try PropertyListSerialization.propertyList(from:Data(contentsOf:url),options:[],format:nil) as? [String:Any],let instrument=state["Instrument"] as? [String:Any],let layers=instrument["Layers"] as? [[String:Any]] else{throw AbletonImportError.invalid("Invalid managed sample-layer layout.")}
                return try layers.map { layer in
                    guard let zones=layer["Zones"] as? [[String:Any]] else{throw AbletonImportError.invalid("Missing managed sample zones.")}
                    return zones.map {zone in ["waveform","min key","max key","min vel","max vel","root key","sample start","sample end"].map{String(describing:zone[$0] ?? "")}.joined(separator:":")}.joined(separator:"|")
                }
            }
            guard try layout(temporary)==layout(managed) else{throw AbletonImportError.invalid("Installed sample-layer layout differs; original library entry preserved.")}
            let behavior=AbletonImport.Behavior(rack:conversion.rack,midi:conversion.midi,warnings:conversion.warnings)
            var layer=existing ?? Layer(name:entries[index].name,instrument:-1,gain:0.5);layer.external=sound
            entries[index].previousImportedRack=existing?.importedRack
            layer.importedRack=behavior.rack
            if layer.midiProgram == baseline.first(where:{$0.id==id})?.layer?.midiProgram {layer.midiProgram=behavior.midi}
            entries[index].layer=layer
            let retained=(entries[index].conversionNotes ?? []).filter{!$0.hasPrefix("Sample-map conversion: Live rack") && !$0.hasPrefix("Not translated:") && !$0.hasPrefix("Mapped effect macros") && !$0.hasPrefix("Reverb uses") && !$0.hasPrefix("EQ3 uses") && !$0.hasPrefix("Compressor attack") && !$0.hasPrefix("Parallel outer")}
            entries[index].conversionNotes=retained+behavior.warnings
            rows.append(["id":id,"name":layer.name,"status":"upgraded","branches":behavior.rack.branches?.count ?? 0,"delays":behavior.rack.effects.filter{$0.importedDelay != nil}.count,"effects":behavior.rack.effects.count,"macros":behavior.rack.macros.count,"midi":behavior.midi != nil,"warnings":behavior.warnings])
        }
        try library.write(entries)
        try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:report,options:.atomic)
        print("Updated \(rows.count) library entries; existing samples and saved performance patches were not rewritten.")
    }
}
