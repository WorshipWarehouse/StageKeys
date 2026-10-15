import Foundation
import AVFoundation
@main struct AudioUnitTests {
    static func main() throws {
        guard let component = ExternalInstrumentRack.instruments().first(where: { $0.name == "OB-Xd" }) else { print("SKIP: OB-Xd instrument is not installed"); return }
        let engine = AVAudioEngine()
        let rack = try ExternalInstrumentRack(engine: engine, libraryURL: URL(fileURLWithPath: CommandLine.arguments[1]))
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
