import Foundation

@main struct SupportDiagnosticsTests {
    static func main() throws {
        let secret = "PRIVATE-DEVICE-AND-PATH"
        let status = AudioDeviceStatus(deviceID: 123, name: secret, sampleRate: 48000, bufferFrames: 128,
            minimumBufferFrames: 32, maximumBufferFrames: 1024, canSetBuffer: true)
        let latency = AudioLatencyChain(deviceName: secret, sampleRate: 48000, bufferFrames: 128,
            bufferMilliseconds: 128.0 / 48, presentationLatencyMilliseconds: 2)
        let report = SupportDiagnostics(version: "0.53.0", build: "57", running: true, status: status,
            latency: latency, midiSources: 2, loadedSlots: 3, limiterBypassed: false, recording: false)
        let json = try report.json()
        assert(!json.contains(secret) && !json.contains("deviceID"))
        let decoded = try JSONDecoder().decode(SupportDiagnostics.self, from: Data(json.utf8))
        assert(decoded.underrunCount == nil && decoded.connectedMIDISources == 2 && decoded.loadedSoundSlots == 3)
        assert(abs(decoded.reportedOutputLatencyMilliseconds! - 4.6666666667) < 1e-6)
        let invalid = SupportDiagnostics(version: "test", build: "test", running: false,
            status: AudioDeviceStatus(deviceID: nil, name: secret, sampleRate: .nan, bufferFrames: 0,
                minimumBufferFrames: 0, maximumBufferFrames: 0, canSetBuffer: false), latency: nil,
            midiSources: -1, loadedSlots: 1000, limiterBypassed: true, recording: false)
        assert(invalid.sampleRate == nil && invalid.connectedMIDISources == 0 && invalid.loadedSoundSlots == 15)
        _ = try invalid.json()
        print("PASS: diagnostics omit names/IDs/paths, distinguish unknown metrics and bound numeric data")
    }
}
