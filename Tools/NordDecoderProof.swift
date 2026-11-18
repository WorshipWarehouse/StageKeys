// Local-only authorized decoder evidence. Output includes private derived PCM.
// Never commit/upload its output, source pianos, or recordings.
@testable import StageKeysVerificationCore
import Foundation
import CryptoKit

@main struct NordDecoderProof {
    static func main() throws {
        guard CommandLine.arguments.count>=4 else{fatalError("Usage: NordDecoderProof NEW-PRIVATE-DIRECTORY piano1.npno piano2.npno")}
        let manager=FileManager.default,root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        guard !manager.fileExists(atPath:root.path) else{fatalError("Refusing an existing output directory")}
        try manager.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var reports:[[String:Any]]=[]
        for (number,path) in CommandLine.arguments.dropFirst(2).enumerated() {
            let source=URL(fileURLWithPath:path)
            let bytes=try NordPiano.read(source),before=AssetDigest.sha256(bytes)
            let preview=try NordNative.preview(bytes),index=preview.index
            let key=60,rootNote=index.keyMap[key]
            guard rootNote != 255 else{fatalError("The declared key is uncovered")}
            var records:[[String:Any]]=[]
            for (i,stroke) in index.strokes.enumerated() where stroke.root==rootNote && stroke.bank==0 {
                let a=try NordPiano.decode(bytes,stroke:stroke,channels:index.report.channels)
                let b=try NordPiano.decode(bytes,stroke:stroke,channels:index.report.channels)
                guard a==b,a.count==stroke.frames*index.report.channels else{fatalError("PCM count or repeatability mismatch")}
                let raw=a.withUnsafeBytes{Data($0)}
                let file="piano-\(number)-stroke-\(i).wav"
                try NordNative.wav(a,channels:index.report.channels).write(to:root.appendingPathComponent(file),options:.atomic)
                let selections=preview.zones.filter{$0.key==key && $0.stroke==i}.map{["low":$0.velocityLow,"high":$0.velocityHigh]}
                records.append(["stroke":i,"root":stroke.root,"layer":stroke.layer,"threshold":stroke.threshold,
                                "frames":stroke.frames,"channels":index.report.channels,"sampleRate":NordPiano.sampleRate,
                                "pcmSHA256":AssetDigest.sha256(raw),"file":file,"velocityRanges":selections])
            }
            var velocityChecks:[[String:Any]]=[]
            for velocity in [20,64,110] {
                let selected=preview.zones.filter{$0.key==key && ($0.velocityLow...$0.velocityHigh).contains(velocity)}
                guard selected.count==1 else{fatalError("Missing or ambiguous declared velocity selection")}
                velocityChecks.append(["velocity":velocity,"stroke":selected[0].stroke,"low":selected[0].velocityLow,"high":selected[0].velocityHigh])
            }
            guard try AssetDigest.sha256(NordPiano.read(source))==before,!records.isEmpty else{fatalError("Source changed or no declared attacks")}
            reports.append(["source":source.lastPathComponent,"sourceSHA256":before,"requestedKey":key,"storedRoot":rootNote,
                            "fineTuneUnits":index.fineTune[key],"storedAttackLayers":records,"velocityChecks":velocityChecks,
                            "scope":"attack PCM decoder proof only; native mapping and hardware equivalence are separate"])
        }
        try JSONSerialization.data(withJSONObject:["reports":reports],options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("decoder-proof.json"),options:.atomic)
        print("PASS: repeated declared-note PCM, frame counts, stereo and soft/medium/hard selection; private output retained locally")
    }
}
