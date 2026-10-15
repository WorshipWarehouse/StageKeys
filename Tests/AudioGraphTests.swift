import AVFoundation
import Foundation

@main
struct AudioGraphTests {
    static func main() throws {
        let audio = AudioController()
        try audio.prepareOffline()
        audio.gain(0, 0.7, seconds: 0)
        audio.gain(1, 0.4, seconds: 0)
        audio.noteOn(key: 60, pitch: 60, instrument: 0, layer: 0, velocity: 0.8)
        audio.noteOn(key: 60, pitch: 60, instrument: 1, layer: 1, velocity: 0.8)
        let file = try AVAudioFile(forWriting: URL(fileURLWithPath: CommandLine.arguments[1]), settings: [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
        var peak: Float = 0
        for block in 0..<750 {
            if block == 120 { audio.noteOff(60) }
            if block == 190 { for n in [60, 64, 67] { audio.noteOn(key: n, pitch: n, instrument: 0, layer: 0, velocity: 0.8); audio.noteOn(key: n, pitch: n, instrument: 1, layer: 1, velocity: 0.6) } }
            if block == 360 { for n in [60, 64, 67] { audio.noteOff(n) } }
            let buffer = try audio.offlineBlock()
            for i in 0..<Int(buffer.frameLength) { let sample = buffer.floatChannelData![0][i]; assert(sample.isFinite); peak = max(peak, abs(sample)) }
            try file.write(from: buffer)
        }
        assert(peak > 0.01 && peak < 1)
        print("PASS: actual AVAudioEngine source → reverb → mixer graph; stereo WAV rendered, peak \(peak)")
    }
}
