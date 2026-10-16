import Foundation

/// Read-only audit. Does not load plug-ins, play audio or launch MainStage.
@main struct InspectMainStage {
    static func main()throws {
        guard CommandLine.arguments.count==3 else {
            print("Usage: InspectMainStage selected-patch-or-folder report.json");return
        }
        let source=URL(fileURLWithPath:CommandLine.arguments[1])
        var patches:[URL]=[]
        if source.pathExtension.lowercased()=="patch" {patches=[source]}
        else {
            guard let iterator=FileManager.default.enumerator(at:source,includingPropertiesForKeys:[.isDirectoryKey,.isSymbolicLinkKey]) else{throw CocoaError(.fileReadUnknown)}
            for case let file as URL in iterator {
                let values=try file.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
                if values.isSymbolicLink==true {iterator.skipDescendants();continue}
                if file.pathExtension.lowercased()=="patch",values.isDirectory==true {patches.append(file);iterator.skipDescendants()}
                guard patches.count<=4096 else{throw CocoaError(.fileReadTooLarge)}
            }
        }
        struct Result:Codable {var file:String;var report:MainStagePatch.Report?;var error:String?}
        var results:[Result]=[]
        for patch in patches.sorted(by:{$0.path<$1.path}) {
            do {results.append(Result(file:patch.path,report:try MainStagePatch.inspect(patch)))}
            catch{results.append(Result(file:patch.path,error:error.localizedDescription))}
        }
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(results).write(to:URL(fileURLWithPath:CommandLine.arguments[2]),options:.atomic)
        let channels=results.compactMap(\.report).flatMap(\.channels)
        print("Audited \(results.count) patches, \(channels.count) channels; \(channels.filter{!$0.instruments.isEmpty}.count) channels reference EXS. No playback conversion or source modification occurred.")
    }
}
