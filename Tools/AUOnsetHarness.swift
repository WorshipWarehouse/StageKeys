import Foundation
import AVFoundation
import AudioToolbox

/// macOS-only onset harness for `AUEventSampleTime` delivery.
///
/// Run on macOS with:
///   xcrun swiftc -DDEBUG Tools/AUOnsetHarness.swift -o /tmp/au-onset && /tmp/au-onset
///
/// It renders a generated tone through the Apple sampler twice: once with the
/// note scheduled at sample 0 and once at sample 1024, then compares the first
/// audible frame. A sampler that ignores future sample times reports the same
/// onset for both runs, which is the failure this harness is looking for.
@main struct AUOnsetHarness {
    static func main() throws {
        let rate = 48_000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stagekeys-au-onset.wav")
        try writeTone(to: url, format: format)
        defer { try? FileManager.default.removeItem(at: url) }

        guard let first = try measure(offset: 0, file: url, format: format) else {
            print("SKIP: no scheduleMIDIEventBlock or no rendered onset")
            return
        }
        guard let second = try measure(offset: 1024, file: url, format: format) else {
            print("SKIP: second render produced no onset")
            return
        }
        let delta = second - first
        print("onset at 0: frame \(first); at 1024: frame \(second); delta \(delta)")
        assert(abs(delta - 1024) <= 2, "Scheduled AU events did not land at the requested sample offset")
        print("PASS: AUEventSampleTime onset")
    }

    static func measure(offset: AUEventSampleTime, file: URL, format: AVAudioFormat) throws -> Int? {
        let engine = AVAudioEngine()
        let sampler = AVAudioUnitSampler()
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try sampler.loadAudioFiles(at: [file])
        try engine.start()
        defer { engine.stop() }
        guard let block = sampler.auAudioUnit.scheduleMIDIEventBlock else { return nil }
        var bytes: [UInt8] = [0x90, 60, 127]
        bytes.withUnsafeMutableBufferPointer { block(offset, 0, 3, $0.baseAddress!) }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        let status = try engine.renderOffline(4096, to: buffer)
        guard status == .success, let channels = buffer.floatChannelData else { return nil }
        for frame in 0..<Int(buffer.frameLength) where abs(channels[0][frame]) > 1e-5 { return frame }
        return nil
    }

    static func writeTone(to url: URL, format: AVAudioFormat) throws {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let frames: AVAudioFrameCount = 2048
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let channels = buffer.floatChannelData!
        for channel in 0..<2 {
            for frame in 0..<Int(frames) {
                let phase = 2 * Double.pi * 880 * Double(frame) / format.sampleRate
                channels[channel][frame] = Float(0.5 * sin(phase) * exp(-Double(frame) / 512))
            }
        }
        try file.write(from: buffer)
    }
}
