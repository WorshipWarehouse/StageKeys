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
        let failure = AudioChangeDiagnostic(error: NSError(domain: "/Users/SECRET/VENDOR", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "PRIVATE-DEVICE-AND-PATH"]), phase: .prepareSound,
            slot: 2, generation: 7, running: true, sampleRate: .nan, previousSoundRetained: true)
        let failedReport = SupportDiagnostics(version: "test", build: "test", running: true, status: status,
            latency: latency, midiSources: 1, loadedSlots: 2, limiterBypassed: false, recording: false,
            lastAudioChangeFailure: failure)
        let failureJSON = try failedReport.json()
        assert(!failureJSON.contains("SECRET") && !failureJSON.contains("PRIVATE-DEVICE") && !failureJSON.contains("/Users/"))
        let restored = try JSONDecoder().decode(SupportDiagnostics.self, from: Data(failureJSON.utf8))
        assert(restored.lastAudioChangeFailure == failure)
        assert(failure.errorDomain == "other" && failure.sampleRate == nil && failure.soundSlot == 3)
        let legacy = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        let legacyReport = try JSONDecoder().decode(SupportDiagnostics.self, from: JSONSerialization.data(withJSONObject: legacy))
        assert(legacyReport.lastAudioChangeFailure == nil)

        // A device/route failure is operation-scoped, numeric and actionable.
        // The raw AVFAudio description must never reach the performer or report.
        let deviceCause = NSError(domain: "com.apple.coreaudio.avfaudio", code: -1, userInfo:
            [NSLocalizedDescriptionKey: "The operation couldn’t be completed. PRIVATE-DEVICE-AND-PATH"])
        let stoppedDevice = AudioChangeDiagnostic(error: deviceCause, phase: .audioDevice,
            slot: nil, generation: 11, running: false, sampleRate: 48000, bufferFrames: 256)
        assert(stoppedDevice.bufferFrames == 256)
        let unmeasuredDevice = AudioChangeDiagnostic(error: deviceCause, phase: .audioDevice,
            slot: nil, generation: 11, running: false, sampleRate: 48000, bufferFrames: 0)
        assert(unmeasuredDevice.bufferFrames == nil, "An unmeasured buffer must not be reported as zero")
        let stoppedMessage = AudioChangeFailure(diagnostic: stoppedDevice).localizedDescription
        assert(stoppedMessage.contains("-1") && stoppedMessage.contains("Audio Settings") && stoppedMessage.contains("start audio"))
        assert(!stoppedMessage.contains("PRIVATE") && !stoppedMessage.contains("com.apple") && !stoppedMessage.contains("couldn’t"))
        let runningDevice = AudioChangeDiagnostic(error: deviceCause, phase: .audioDevice,
            slot: nil, generation: 11, running: true, sampleRate: 48000)
        let runningMessage = AudioChangeFailure(diagnostic: runningDevice).localizedDescription
        assert(runningMessage.contains("previous audio output") && !runningMessage.contains("PRIVATE"))
        let resume = AudioDeviceError.resumeFailed(deviceCause).localizedDescription
        assert(resume.contains("-1") && resume.contains("Audio Settings"))
        assert(!resume.contains("PRIVATE") && !resume.contains("couldn’t"))
        let deviceReport = SupportDiagnostics(version: "test", build: "test", running: false, status: nil,
            latency: nil, midiSources: 0, loadedSlots: 1, limiterBypassed: false, recording: false,
            lastAudioChangeFailure: stoppedDevice)
        let deviceJSON = try deviceReport.json()
        assert(deviceJSON.contains("audioDevice") && deviceJSON.contains("-1"))
        assert(!deviceJSON.contains("PRIVATE") && !deviceJSON.contains("couldn’t"))
        let decodedDevice = try JSONDecoder().decode(SupportDiagnostics.self, from: Data(deviceJSON.utf8)).lastAudioChangeFailure
        assert(decodedDevice == stoppedDevice && decodedDevice?.bufferFrames == 256)
        print("PASS: diagnostics omit names/IDs/paths, distinguish unknown metrics and bound numeric data")
    }
}
