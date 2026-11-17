import Foundation
import AVFoundation

/// Conversion stays outside the audio callback. Only the tiny Apple template
/// acquisition touches AVAudioUnitSampler, on the main thread.
enum NordNative {
    final class Cancellation: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false
        func cancel() { lock.lock(); stopped = true; lock.unlock() }
        var requested: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    }
    struct Preview {
        let name, identity: String
        let index: NordPiano.Index
        let zones: [NordPiano.Zone]
        let notes: [String]
        var pcmBytes: Int {
            Set(zones.map(\.stroke)).reduce(0) { $0 + index.strokes[$1].frames * index.report.channels * 2 }
        }
    }
    struct Prepared {
        let sound: ExternalSound
        let identity: String
        let assets: [URL]
    }
    static func preview(_ data: Data) throws -> Preview {
        let index = try NordPiano.index(data)
        let gain = Int(Int8(bitPattern: data[0x2c + 0x40c]))
        let zones = try NordPiano.zones(index, libraryGain: gain)
        let banks = Dictionary(grouping:index.strokes,by: \.bank).mapValues(\.count)
        let notes = [
            "Experimental Nord attack-only conversion: \(Set(zones.map(\.stroke)).count) recordings, \(index.report.coveredKeys) keys, \(index.report.channels) channel(s), 35002 Hz PCM. Original source SHA256: \(AssetDigest.sha256(data)).",
            "Velocity layer switching uses the measured Electro 5 Touch 0 approximation (about ±2 MIDI velocities). Other Nord touch curves and continuous velocity loudness are not reproduced.",
            "Not translated: \(banks[1,default:0]) pedal-resonance recordings, \(banks[2,default:0]) release recordings, other banks \(banks.filter{$0.key > 2}.values.reduce(0,+)); Nord decay ladders, note-off fades, damper range, sympathetic resonance, effects and crossfades. Native sustain and a fixed 100 ms release replace source pedal/release behavior.",
            "Root/key mapping, stored PCM, stereo, bounded sustain loops, per-key tuning (0.7 cents/unit estimate), and version-specific trim are translated. Loop interpolation, output gain, dynamics and tone require hardware comparison; Nord sonic parity is not established.",
            "Private user input only. No factory sounds are bundled or uploaded. Content transfer rights are not established by conversion; personal pack export requires your authorization."
        ]
        return Preview(name:index.report.name,identity:"nord-"+AssetDigest.sha256(data),index:index,zones:zones,notes:notes)
    }
    static func wav(_ pcm: [Int16], channels: Int) -> Data {
        var data = Data()
        func text(_ s:String) { data.append(contentsOf:s.utf8) }
        func u16(_ x:UInt16) { data.append(UInt8(x&255));data.append(UInt8(x>>8)) }
        func u32(_ x:UInt32) { u16(UInt16(x&65535));u16(UInt16(x>>16)) }
        text("RIFF");u32(UInt32(36+pcm.count*2));text("WAVEfmt ");u32(16);u16(1);u16(UInt16(channels))
        u32(UInt32(NordPiano.sampleRate));u32(UInt32(NordPiano.sampleRate*channels*2));u16(UInt16(channels*2));u16(16)
        text("data");u32(UInt32(pcm.count*2));for sample in pcm { u16(UInt16(bitPattern:sample)) };return data
    }
    static func template() throws -> [String:Any] {
        precondition(Thread.isMainThread)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".wav")
        defer { try? FileManager.default.removeItem(at:temporary) }
        try wav([Int16](repeating:0,count:256),channels:1).write(to:temporary)
        let sampler=AVAudioUnitSampler();try sampler.loadAudioFiles(at:[temporary])
        guard let state=sampler.auAudioUnit.fullStateForDocument else { throw ExternalInstrumentError.unsupportedFormat }
        return state
    }
    /// Creates uniquely owned, unreferenced assets. Any error/cancellation rolls
    /// them back; caller commits the catalog only after the entire candidate is ready.
    static func prepare(_ data: Data, preview: Preview, library: URL, template: [String:Any],
                        cancelled: () -> Bool = { false }) throws -> Prepared {
        let manager=FileManager.default, identity=UUID().uuidString
        let samples=library.appendingPathComponent(identity+"-samples",isDirectory:true)
        let preset=library.appendingPathComponent(identity+".aupreset")
        var complete=false
        defer { if !complete {try? manager.removeItem(at:preset);try? manager.removeItem(at:samples)} }
        guard preview.identity == "nord-"+AssetDigest.sha256(data) else { throw NordPiano.DecodeFailure(reason:"Preview does not match the selected source.") }
        try manager.createDirectory(at:samples,withIntermediateDirectories:false)
        var references:[String:String]=[:]
        for i in Set(preview.zones.map(\.stroke)).sorted() {
            if cancelled() { throw CancellationError() }
            let pcm=try NordPiano.decode(data,stroke:preview.index.strokes[i],channels:preview.index.report.channels,cancelled:cancelled)
            let file=samples.appendingPathComponent("stroke-\(i).wav")
            try wav(pcm,channels:preview.index.report.channels).write(to:file,options:.atomic)
            references["Sample:\(0x10000000+i)"]=file.path
        }
        guard var instrument=template["Instrument"] as? [String:Any],var layer=(instrument["Layers"] as? [[String:Any]])?.first else { throw ExternalInstrumentError.unsupportedFormat }
        let zones:[[String:Any]]=preview.zones.enumerated().map { n,zone in
            let stroke=preview.index.strokes[zone.stroke]
            var value:[String:Any]=["ID":n,"name":"Key \(zone.key)","enabled":true,"waveform":0x10000000+zone.stroke,
                "min key":zone.key,"max key":zone.key,"root key":stroke.root,"min vel":zone.velocityLow,"max vel":zone.velocityHigh,
                "gain":zone.gainDB,"fine tune":zone.fineTuneCents,"pan":0.0,"sample start":0,"sample end":stroke.frames-1,"loop enabled":stroke.loopEnd>stroke.loopStart]
            if stroke.loopEnd>stroke.loopStart {value["loop start"]=stroke.loopStart;value["loop end"]=stroke.loopEnd-1}
            return value
        }
        layer["ID"]=0;layer["name"]=preview.name;layer["Zones"]=zones;layer["gain"]=0;layer["pan"]=0;layer["min vel"]=1;layer["max vel"]=127
        layer["Filters"]=["ID":0,"enabled":false,"cutoff":20000.0,"resonance":0.0]
        if var lfos=layer["LFOs"] as? [[String:Any]] {for i in lfos.indices {lfos[i]["enabled"]=false};layer["LFOs"]=lfos}
        let envelope=EXSNative.Envelope(attack:0.001,lowVelocityAttack:0.001,decay:0.001,sustain:1,release:0.1)
        EXSNative.applyEnvelope(envelope,group:[UInt8](repeating:0,count:120),to:&layer)
        instrument["Layers"]=[layer];instrument["voice count"]=64
        var state=template;state["Instrument"]=instrument;state["file-references"]=references;state["gain"]=0;state["name"]=preview.name
        let program=NativeSamplerProgram(groups:[.init(name:preview.name,layer:0,low:0,high:127,velocityLow:1,velocityHigh:127,controller:nil)],notes:preview.notes,compactGroups:true,conversionVersion:6,amplitudeEnvelope:envelope)
        guard program.valid else { throw ExternalInstrumentError.unsupportedFormat }
        state["StageKeys.NativeSampler"]=try JSONEncoder().encode(program)
        if cancelled() { throw CancellationError() }
        try PropertyListSerialization.data(fromPropertyList:state,format:.xml,options:0).write(to:preset,options:.atomic)
        complete=true
        return Prepared(sound:ExternalSound(kind:.samplerPreset,name:preview.name,fileName:preset.lastPathComponent,nativeSampler:program),identity:preview.identity,assets:[preset,samples])
    }
}
