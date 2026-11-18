// Local-only read-only evidence. Keep reports and all vendor payloads private.
@testable import StageKeysVerificationCore
import Foundation
import CryptoKit

@main struct InspectNordBundle {
    static func main() throws {
        guard CommandLine.arguments.count==3 || CommandLine.arguments.count==4 else {
            fatalError("Usage: InspectNordBundle selected.ns4pbundle NEW-private-report.json [--pianos]")
        }
        let source=URL(fileURLWithPath:CommandLine.arguments[1]),output=URL(fileURLWithPath:CommandLine.arguments[2])
        guard !FileManager.default.fileExists(atPath:output.path) else{fatalError("Choose a new report path")}
        let properties=try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard properties.isRegularFile==true,properties.isSymbolicLink != true,let expectedBytes=properties.fileSize,expectedBytes>=22,expectedBytes<=NordBundle.fileLimit else {throw NordBundle.Failure(reason:"Choose a bounded regular bundle.")}
        func boundedHash() throws -> String {
            let handle=try FileHandle(forReadingFrom:source);defer{try? handle.close()}
            var digest=SHA256(),count=0
            while let chunk=try handle.read(upToCount:1<<20),!chunk.isEmpty {
                count+=chunk.count;guard count<=NordBundle.fileLimit else{throw NordBundle.Failure(reason:"Source grew beyond its admission limit.")};digest.update(data:chunk)
            }
            guard count==expectedBytes else{throw NordBundle.Failure(reason:"Source changed size during inspection.")}
            return digest.finalize().map{String(format:"%02x",$0)}.joined()
        }
        let before=try boundedHash()
        let preview=try NordBundle.inspect(source)
        var pianos:[[String:Any]]=[]
        if CommandLine.arguments.count==4 {
            guard CommandLine.arguments[3]=="--pianos" else{fatalError("Unknown option")}
            for entry in preview.pianos {
                do {
                    let bytes=try NordBundle.piano(entry.name,from:source,preview:preview)
                    let piano=try NordNative.preview(bytes)
                    pianos.append(["path":entry.name,"sourceSHA256":AssetDigest.sha256(bytes),"name":piano.name,"contentVersion":piano.index.report.contentVersion,"zones":piano.zones.count,"pcmBytes":piano.pcmBytes,"state":"index validated only; no PCM/native playback qualification","notes":piano.notes])
                }catch{pianos.append(["path":entry.name,"state":"unsupported/invalid","error":error.localizedDescription])}
            }
        }
        guard try boundedHash()==before else{throw NordBundle.Failure(reason:"Source changed during inspection.")}
        let report:[String:Any]=["sourceName":preview.sourceName,"sourceBytes":preview.sourceBytes,"archiveSHA256":before,"directoryFingerprint":preview.identity,
            "pianos":preview.pianos.count,"samples":preview.samples.count,"programs":preview.programs.map{["name":$0.name,"dependencies":$0.dependencies,"state":"untranslated"]},
            "pianoInspection":pianos,"limitation":preview.limitation]
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output,options:.atomic)
        print("Inspected \(preview.programs.count) untranslated programs, \(preview.pianos.count) piano files and \(preview.samples.count) sample instruments. No program playback or source modification claimed.")
    }
}
