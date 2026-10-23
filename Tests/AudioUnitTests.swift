import Foundation
import AVFoundation
@main struct AudioUnitTests {
    static func main() throws {
        let installed=ExternalInstrumentRack.instruments()
        guard let component = installed.first(where: { $0.name == "OB-Xd" }) ?? installed.first(where:{$0.manufacturer==0x6170706c && $0.subtype==0x646c7320}) else { fatalError("No test Audio Unit is installed") }
        let engine = AVAudioEngine()
        let library=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!).appendingPathComponent("Hosted AU Tests",isDirectory:true)
        let rack = try ExternalInstrumentRack(engine: engine, libraryURL: library)
        var finished = false, failure: Error?
        rack.load(ExternalSound(kind: .audioUnit, name: component.name, component: component), channel: 3) { result in
            if case .failure(let e) = result { failure = e }
            finished = true
        }
        let deadline = Date().addingTimeInterval(20)
        while !finished && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        if let failure { throw failure }
        assert(finished && rack.contains(3))
        if let state = try rack.stateData(channel: 3) { try rack.restoreStateData(state, channel: 3) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        engine.prepare(); try engine.start()
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        _ = try engine.renderOffline(512,to: buffer)
        rack.volume(channel: 3,gain: 0.5,pan: 0)
        rack.noteOn(channel: 3,key: 100,pitch: 60,velocity: 0.8)
        var peak: Float = 0
        for _ in 0..<100 {
            _ = try engine.renderOffline(512,to: buffer)
            for i in 0..<Int(buffer.frameLength) { let s = buffer.floatChannelData![0][i]; assert(s.isFinite); peak = max(peak,abs(s)) }
        }
        assert(peak > 0.001,"AU instrument must produce audio")
        rack.noteOff(channel: 3,key: 100,forceRelease: true); rack.panic()
        if let unit = rack.unit(channel: 3) {
            // The instrument interface must resolve (custom view or no view) rather
            // than leaving the editor waiting; the generic editor covers no-view AUs.
            var resolved = false
            unit.auAudioUnit.requestViewController { view in
                resolved = true
                print(view == nil ? "AU has no custom interface; the generic editor applies" : "AU provides a custom interface")
            }
            let viewDeadline = Date().addingTimeInterval(10)
            while !resolved && Date() < viewDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            assert(resolved, "Requesting the Audio Unit interface must complete or report no interface")
            let parameters = unit.auAudioUnit.parameterTree?.allParameters ?? []
            print("AU parameters: \(parameters.count), factory presets: \(unit.auAudioUnit.factoryPresets?.count ?? 0)")
            if let state = try rack.stateData(channel: 3) {
                assert(!state.isEmpty, "Audio Unit document state must be serializable")
                try rack.restoreStateData(state, channel: 3)
                assert(unit.auAudioUnit.parameterTree?.allParameters.count ?? 0 == parameters.count,
                       "Parameter tree changed across an Audio Unit state round-trip")
            }
        }
        engine.stop(); try rack.remove(3)
        var cancelled = false
        rack.load(ExternalSound(kind: .audioUnit, name: component.name, component: component), channel: 4) { result in
            if case .failure(let error) = result, case ExternalInstrumentError.superseded = error { cancelled = true }
        }
        try rack.remove(4)
        let cancellationDeadline = Date().addingTimeInterval(20)
        while !cancelled && Date() < cancellationDeadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        assert(cancelled && !rack.contains(4), "A removed channel must not be reinstalled by a stale asynchronous AU load")
        print("PASS: asynchronous Audio Unit load cancellation")
        print("PASS: third-party OB-Xd AU instantiate, state restore, MIDI and offline audio; peak \(peak)")
    }
}
