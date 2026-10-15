import Foundation
import AVFoundation
#if os(macOS)
import CoreAudio
#endif

@main struct AudioDeviceTests {
    static func main() throws {
        let engine = AVAudioEngine()
        let controller = AudioDeviceController(engine: engine)
        let devices = try AudioDeviceController.availableOutputs()
        assert(devices.allSatisfy { $0.channels > 0 && !$0.name.isEmpty })
        assert(Set(devices.map(\.id)).count == devices.count)
        let before = try controller.status()
        assert(before.sampleRate > 0 && before.bufferFrames > 0)
        assert(before.bufferMilliseconds.isFinite)
        assert(!engine.isRunning, "Read-only status must not start the engine")
        #if os(macOS)
        if let id = before.deviceID { assert(devices.contains { $0.id == id }) }
        // Invalid selection fails before touching CurrentDevice or hardware.
        do { try controller.select(deviceID: UInt32.max); assertionFailure("Unavailable device accepted") }
        catch AudioDeviceError.unavailable {}
        do { try controller.buffer(frameCount: 0); assertionFailure("Invalid buffer accepted") }
        catch AudioDeviceError.invalidBuffer {}
        let after = try controller.status()
        assert(after == before)
        #endif
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        do { try controller.select(deviceID: before.deviceID ?? 0); assertionFailure("Offline selection accepted") }
        catch AudioDeviceError.offline {}
        do { try controller.buffer(frameCount: 128); assertionFailure("Offline buffer mutation accepted") }
        catch AudioDeviceError.offline {}
        do { _ = try controller.status(); assertionFailure("Hardware status exposed as offline status") }
        catch AudioDeviceError.offline {}
        engine.disableManualRenderingMode()
        print("PASS read-only output inventory/status, invalid settings, offline mutation guards; \(devices.count) output devices; \(before.name), \(before.sampleRate) Hz, \(before.bufferFrames) frames")
    }
}
