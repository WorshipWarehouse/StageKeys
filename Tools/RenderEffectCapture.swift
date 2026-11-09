import AVFoundation
import Foundation

/// Offline matched-effect renderer. It feeds a captured dry performance through
/// the same native DSP used by StageKeys, without loading a sampler or changing
/// the running application's patch.
@main struct RenderEffectCapture {
    static func main() throws {
        guard CommandLine.arguments.count >= 7 else {
            throw NSError(domain: "RenderEffectCapture", code: 64, userInfo: [NSLocalizedDescriptionKey:
                "usage: RenderEffectCapture INPUT.wav OUTPUT.wav KIND TAIL_SECONDS PARAMETER..."])
        }
        let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw NSError(domain: "RenderEffectCapture", code: 73, userInfo: [NSLocalizedDescriptionKey: "output already exists"])
        }
        guard let kind = Int(CommandLine.arguments[3]), (0...17).contains(kind), kind <= Int(Int32.max),
              let tailSeconds = Double(CommandLine.arguments[4]), tailSeconds.isFinite,
              (0...600).contains(tailSeconds) else {
            throw NSError(domain: "RenderEffectCapture", code: 64, userInfo: [NSLocalizedDescriptionKey: "invalid kind or tail duration"])
        }
        let parameters = try CommandLine.arguments.dropFirst(5).map { value -> Float in
            guard let parsed = Float(value), parsed.isFinite else {
                throw NSError(domain: "RenderEffectCapture", code: 64, userInfo: [NSLocalizedDescriptionKey: "invalid parameter: \(value)"])
            }
            return parsed
        }

        let input = try AVAudioFile(forReading: inputURL)
        let sourceFormat = input.processingFormat
        guard sourceFormat.channelCount == 2, sourceFormat.sampleRate > 0 else {
            throw NSError(domain: "RenderEffectCapture", code: 65, userInfo: [NSLocalizedDescriptionKey: "input must be stereo PCM"])
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: sourceFormat.sampleRate, channels: 2)!
        var outputSettings = format.settings
        outputSettings[AVLinearPCMIsNonInterleaved] = false
        let output = try AVAudioFile(forWriting: outputURL, settings: outputSettings)
        guard let left = sk_create_effects(sourceFormat.sampleRate),
              let right = sk_create_effects(sourceFormat.sampleRate) else {
            throw NSError(domain: "RenderEffectCapture", code: 70, userInfo: [NSLocalizedDescriptionKey: "could not create StageKeys DSP"])
        }
        defer { sk_destroy(left); sk_destroy(right) }
        for synth in [left, right] {
            sk_effect(synth, 0, 0, Int32(kind), 1)
            for (index, value) in parameters.enumerated() {
                sk_effect_parameter(synth, 0, 0, Int32(index), value)
            }
        }

        let block: AVAudioFrameCount = 4096
        let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: block)!
        while true {
            do {
                try input.read(into: source, frameCount: block)
            } catch let error as NSError where error.domain == NSOSStatusErrorDomain && error.code == -39 {
                break // eofErr is the normal terminal read for some float WAV containers.
            }
            if source.frameLength == 0 { break }
            let frames = UInt32(source.frameLength)
            sk_process_effects_stereo(left, right, source.floatChannelData![0], source.floatChannelData![1], frames)
            try output.write(from: source)
        }

        var remaining = Int((tailSeconds * sourceFormat.sampleRate).rounded())
        while remaining > 0 {
            let count = min(remaining, Int(block))
            source.frameLength = AVAudioFrameCount(count)
            source.floatChannelData![0].initialize(repeating: 0, count: count)
            source.floatChannelData![1].initialize(repeating: 0, count: count)
            sk_process_effects_stereo(left, right, source.floatChannelData![0], source.floatChannelData![1], UInt32(count))
            try output.write(from: source)
            remaining -= count
        }
        print("Rendered kind \(kind), \(parameters.count) parameters, \(tailSeconds)s tail at \(Int(sourceFormat.sampleRate)) Hz")
    }
}
