// Explicit local-only qualification. Never commit reports or vendor assets.
@testable import StageKeysVerificationCore
import Foundation
import AVFoundation

@main struct AuditNordBundle {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count==3 else {fatalError("Usage: AuditNordBundle source.ns4pbundle NEW-private-output-directory")}
        let source=URL(fileURLWithPath:CommandLine.arguments[1]),root=URL(fileURLWithPath:CommandLine.arguments[2]),fm=FileManager.default
        guard !fm.fileExists(atPath:root.path) else {fatalError("Output must be new")}
        try fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        setenv("STAGEKEYS_DATA_DIR",root.path,1)
        let preview=try NordBundle.inspect(source),store=PerformanceStore()
        func wait() async throws {
            let deadline=Date().addingTimeInterval(300)
            while store.libraryImportBusy && Date()<deadline {try await Task.sleep(nanoseconds:10_000_000)}
            guard !store.libraryImportBusy else {throw NordBundle.Failure(reason:"Import exceeded five-minute qualification bound")}
        }
        store.inspectNordBundle(source);try await wait()
        guard store.nordBundlePreview != nil else {throw NordBundle.Failure(reason:store.libraryImportProgress ?? "Bundle inspection failed")}
        var results:[[String:Any]]=[]
        for piano in preview.pianos {
            do {
                store.inspectNordBundlePiano(piano.name);try await wait()
                guard let selected=store.nordImportPreview else {throw NordBundle.Failure(reason:store.libraryImportProgress ?? "Piano inspection failed")}
                store.importNordSound();try await wait()
                guard let entry=store.librarySounds.first(where:{$0.id==selected.identity}),let layer=entry.layer else {throw NordBundle.Failure(reason:store.libraryImportProgress ?? "Piano was not installed")}
                let audio=AudioController();try audio.prepareOffline();defer{audio.stop()}
                audio.configure(0,layer);audio.gain(0,layer.gain,seconds:0);audio.master(0.1);audio.space(0)
                for _ in 0..<10 {_ = try audio.offlineBlock()}
                var renders:[[String:Any]]=[]
                for key in [36,60,84] {
                    for velocity in [20,57,58,100,127] {
                        audio.noteOn(key:key,pitch:key,instrument:-1,layer:0,velocity:Float(velocity)/127)
                        var energy=0.0,peak=0.0
                        for _ in 0..<20 {
                            let b=try audio.offlineBlock()
                            for c in 0..<Int(b.format.channelCount) {for f in 0..<Int(b.frameLength) {
                                let v=Double(b.floatChannelData![c][f]);guard v.isFinite else {throw NordBundle.Failure(reason:"Non-finite native output")}
                                energy+=v*v;peak=max(peak,abs(v))
                            }}
                        }
                        audio.noteOff(key:key,channel:0)
                        for _ in 0..<40 {_ = try audio.offlineBlock()}
                        renders.append(["key":key,"velocity":velocity,"energy":energy,"peak":peak])
                    }
                }
                guard renders.allSatisfy({($0["energy"] as? Double ?? 0)>0}) else {throw NordBundle.Failure(reason:"Silent sampled key/velocity")}
                results.append(["path":piano.name,"identity":selected.identity,"zones":selected.zones.count,"pcmBytes":selected.pcmBytes,"state":"installed and finite nonzero offline render","renders":renders])
            } catch {results.append(["path":piano.name,"state":"failed","error":error.localizedDescription])}
            let report:[String:Any]=["directoryFingerprint":preview.identity,"results":results,"limitation":"Standalone attack-only pianos. No listening comparison, hardware timing, full programs, sample instruments, organ, synth or effects qualification."]
            try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("report.json"),options:.atomic)
            print("\(results.count)/\(preview.pianos.count): \(results.last!["state"]!)",terminator:"\n");fflush(stdout)
        }
        let restarted=PerformanceStore()
        guard restarted.librarySounds.count==results.filter({$0["state"] as? String != "failed"}).count else {throw NordBundle.Failure(reason:"Restart catalog mismatch")}
    }
}
