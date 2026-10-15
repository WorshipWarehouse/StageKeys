import Foundation
import AVFoundation
import CryptoKit

/// Converts user-created MainStage Auto Sampler captures. Never executes a
/// .patch/.cst or represents a sampled instrument as an editable synth preset.
@main struct ConvertMainStageCapture {
    struct Job: Codable {
        var preset: String
        var sampleRoot: String
        var name: String
        var collection: String
        var notes: [UInt8]
        var velocities: [UInt8]
        var seconds: Double?
        var exportFolder: String?
        var requireSustain: Bool?
        var extendKeyRange: [Int]?
        var sourceArchiveID: String?
        var tags: SoundTags?
    }
    struct Manifest: Codable { var jobs: [Job] }
    struct Result: Codable {
        var name: String
        var sourceSHA256: String
        var status: String
        var detail: String
        var sampleCount: Int
        var loopedZoneCount: Int
        var extrapolatedRange: [Int]?
        var peaks: [String: Float]
        var latePeaks: [String: Float]
    }
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            print("Usage: ConvertMainStageCapture manifest.json StageKeysDataDirectory report.json")
            return
        }
        let manifest=try JSONDecoder().decode(Manifest.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        guard !manifest.jobs.isEmpty, manifest.jobs.count <= 256 else { throw CocoaError(.fileReadCorruptFile) }
        let base=URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true)
        let library=SoundLibrary(url:base.appendingPathComponent("sound-library.json"))
        var entries=try library.read(), results:[Result]=[]
        let engine=AVAudioEngine(), managed=base.appendingPathComponent("Imported Sounds",isDirectory:true)
        let rack=try ExternalInstrumentRack(engine:engine,libraryURL:managed)
        for job in manifest.jobs {
            var result=Result(name:job.name,sourceSHA256:"",status:"failed",detail:"",sampleCount:0,loopedZoneCount:0,extrapolatedRange:nil,peaks:[:],latePeaks:[:])
            do {
                guard !job.notes.isEmpty,job.notes.count<=128,job.notes.allSatisfy({$0<128}),!job.velocities.isEmpty,job.velocities.count<=16,job.velocities.allSatisfy({$0>0 && $0<128}) else { throw CocoaError(.fileReadCorruptFile) }
                let seconds=job.seconds ?? 2
                guard seconds>=2,seconds<=30,seconds.isFinite else { throw CocoaError(.fileReadCorruptFile) }
                let preset=URL(fileURLWithPath:job.preset), samples=URL(fileURLWithPath:job.sampleRoot,isDirectory:true)
                let bytes=try Data(contentsOf:preset)
                guard bytes.count<=16_000_000 else { throw CocoaError(.fileReadTooLarge) }
                result.sourceSHA256=SHA256.hash(data:bytes).map{String(format:"%02x",$0)}.joined()
                let identityBytes=bytes+(try JSONEncoder().encode(job.extendKeyRange))
                let id="mainstage-capture-"+SHA256.hash(data:identityBytes).map{String(format:"%02x",$0)}.joined()
                if entries.contains(where:{$0.id==id}) { result.status="already imported";results.append(result);continue }
                var sound=try preset.pathExtension.lowercased() == "aupreset" ? rack.importPreset(preset,sampleRoot:samples) : rack.importEXS(preset,sampleRoot:samples);sound.name=job.name
                let imported=managed.appendingPathComponent(sound.fileName!)
                var published=false
                defer {
                    if !published {
                        let assets=managed.appendingPathComponent(imported.deletingPathExtension().lastPathComponent+"-samples")
                        try? FileManager.default.removeItem(at:imported)
                        try? FileManager.default.removeItem(at:assets)
                    }
                }
                var state=try PropertyListSerialization.propertyList(from:Data(contentsOf:imported),options:[],format:nil) as! [String:Any]
                if let range=job.extendKeyRange {
                    guard range.count==2,range[0]>=0,range[1]<=127,range[0]<=range[1],var instrument=state["Instrument"] as? [String:Any],var layers=instrument["Layers"] as? [[String:Any]] else { throw CocoaError(.fileReadCorruptFile) }
                    for index in layers.indices {
                        guard var zones=layers[index]["Zones"] as? [[String:Any]],!zones.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                        let low=zones.map{$0["min key"] as? Int ?? 0}.min()!, high=zones.map{$0["max key"] as? Int ?? 127}.max()!
                        guard range[0]<=low,range[1]>=high else { throw CocoaError(.fileReadCorruptFile) }
                        for zone in zones.indices {
                            if (zones[zone]["min key"] as? Int ?? 0)==low { zones[zone]["min key"]=range[0] }
                            if (zones[zone]["max key"] as? Int ?? 127)==high { zones[zone]["max key"]=range[1] }
                        }
                        layers[index]["Zones"]=zones
                    }
                    instrument["Layers"]=layers;state["Instrument"]=instrument
                    try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:imported,options:.atomic)
                    result.extrapolatedRange=range
                }
                result.sampleCount=(state["file-references"] as? [String:String])?.count ?? 0
                let instrument=state["Instrument"] as? [String:Any]
                let layers=instrument?["Layers"] as? [[String:Any]] ?? []
                result.loopedZoneCount=layers.flatMap{$0["Zones"] as? [[String:Any]] ?? []}.filter{($0["loop enabled"] as? Bool)==true}.count
                let playback=AVAudioEngine(),sampler=AVAudioUnitSampler()
                playback.attach(sampler);playback.connect(sampler,to:playback.mainMixerNode,format:nil)
                try sampler.loadInstrument(at:imported)
                let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
                try playback.enableManualRenderingMode(.offline,format:format,maximumFrameCount:512)
                playback.prepare();try playback.start()
                defer { playback.stop() }
                let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:512)!
                for velocity in job.velocities { for note in job.notes {
                    sampler.sendController(120,withValue:0,onChannel:0)
                    sampler.startNote(note,withVelocity:velocity,onChannel:0)
                    var peak:Float=0,latePeak:Float=0
                    let blocks=Int(ceil(seconds*48000/512))
                    for block in 0..<blocks {
                        let status=try playback.renderOffline(512,to:buffer)
                        guard status == .success else { throw CocoaError(.fileReadUnknown) }
                        for channel in 0..<2 { for frame in 0..<Int(buffer.frameLength) {
                            let value=buffer.floatChannelData![channel][frame]
                            guard value.isFinite else { throw CocoaError(.fileReadCorruptFile) }
                            peak=max(peak,abs(value));if block>=blocks-94 { latePeak=max(latePeak,abs(value)) }
                        } }
                    }
                    sampler.stopNote(note,onChannel:0)
                    result.peaks["\(note):\(velocity)"]=peak
                    result.latePeaks["\(note):\(velocity)"]=latePeak
                    if job.requireSustain == true && latePeak<=0.0001 { throw NSError(domain:"CaptureValidation",code:2,userInfo:[NSLocalizedDescriptionKey:"Silent sustain at note \(note), velocity \(velocity)"]) }
                    guard peak>0.0001 else { throw NSError(domain:"CaptureValidation",code:1,userInfo:[NSLocalizedDescriptionKey:"Silent note \(note), velocity \(velocity)"] ) }
                } }
                if let exportFolder=job.exportFolder { _ = try SamplerInterchange.exportPreset(sound,libraryURL:managed,to:URL(fileURLWithPath:exportFolder,isDirectory:true)) }
                let proposed=entries+[LibrarySound(id:id,name:job.name,collection:job.collection,sound:sound,tags:job.tags,sourceArchiveID:job.sourceArchiveID)]
                try library.write(proposed);entries=proposed;published=true
                result.status="imported";result.detail="Managed Apple sampler preset; finite audible playback verified. Sampled timbre, not full synth/effect parameter conversion."+(result.extrapolatedRange == nil ? "" : " Outer keyboard pitches extrapolate the nearest recorded zone.")
            } catch { result.detail=error.localizedDescription }
            results.append(result)
        }
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(results).write(to:URL(fileURLWithPath:CommandLine.arguments[3]),options:.atomic)
        for result in results { print("\(result.status): \(result.name) — \(result.detail)") }
        if results.contains(where:{$0.status=="failed"}) { exit(1) }
    }
}
