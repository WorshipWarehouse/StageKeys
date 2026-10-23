import Foundation
import AVFoundation
import AudioToolbox
#if os(macOS)
import CoreAudio
#endif

struct AudioOutputDevice: Identifiable, Equatable {
    var id: UInt32
    var name: String
    var channels: UInt32
}
struct AudioDeviceStatus: Equatable {
    var deviceID: UInt32?
    var name: String
    var sampleRate: Double
    var bufferFrames: UInt32
    var minimumBufferFrames: UInt32
    var maximumBufferFrames: UInt32
    var canSetBuffer: Bool
    var bufferMilliseconds: Double { sampleRate > 0 ? Double(bufferFrames) * 1000 / sampleRate : 0 }
}

/// Reported, not measured: the selected device's buffer plus Core Audio's
/// presentation latency. Physical key-to-speaker latency also includes MIDI
/// delivery and the instrument's own latency, which need a hardware loopback
/// measurement; publish those separately in the device/buffer matrix.
struct AudioLatencyChain: Equatable {
    var deviceName: String
    var sampleRate: Double
    var bufferFrames: UInt32
    var bufferMilliseconds: Double
    var presentationLatencyMilliseconds: Double
    var totalMilliseconds: Double { bufferMilliseconds + presentationLatencyMilliseconds }
}
enum AudioDeviceError: LocalizedError {
    case unavailable, unsupported, offline, invalidBuffer, status(OSStatus), restartFailed(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: return "The selected audio output is unavailable."
        case .unsupported: return "This platform manages the audio output through system route controls."
        case .offline: return "Audio-device settings cannot change during offline rendering."
        case .invalidBuffer: return "This buffer size is not supported by the selected audio device."
        case .status(let code): return "Audio-device operation failed (\(code))."
        case .restartFailed(let reason): return "The audio engine could not resume: \(reason)"
        }
    }
}

/// Main-thread output-only controls. Never accesses the input node, requests
/// microphone access, or changes the system default output. macOS buffer frame
/// size belongs to the selected hardware device and can affect other clients.
final class AudioDeviceController {
    private let engine: AVAudioEngine
    init(engine: AVAudioEngine) { self.engine = engine }
    private func assertOnline() throws {
        precondition(Thread.isMainThread)
        guard !engine.isInManualRenderingMode else { throw AudioDeviceError.offline }
    }
    #if os(macOS)
    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    private static func scalar<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                  default initial: T) throws -> T {
        var property = address(selector)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let code = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0)
        }
        guard code == noErr else { throw AudioDeviceError.status(code) }
        return value
    }
    private static func name(_ device: AudioDeviceID) throws -> String {
        var property = address(kAudioObjectPropertyName)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let code = AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value)
        guard code == noErr else { throw AudioDeviceError.status(code) }
        return value?.takeRetainedValue() as String? ?? "Audio Output"
    }
    private static func outputChannels(_ device: AudioDeviceID) throws -> UInt32 {
        var property = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        var code = AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size)
        guard code == noErr else { throw AudioDeviceError.status(code) }
        guard size >= MemoryLayout<AudioBufferList>.size else { return 0 }
        let allocation = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { allocation.deallocate() }
        code = AudioObjectGetPropertyData(device, &property, 0, nil, &size, allocation)
        guard code == noErr else { throw AudioDeviceError.status(code) }
        let list = UnsafeMutableAudioBufferListPointer(allocation.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + $1.mNumberChannels }
    }
    static func availableOutputs() throws -> [AudioOutputDevice] {
        var property = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        var code = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size)
        guard code == noErr else { throw AudioDeviceError.status(code) }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard !devices.isEmpty else { return [] }
        code = devices.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, $0.baseAddress!)
        }
        guard code == noErr else { throw AudioDeviceError.status(code) }
        return devices.compactMap { device in
            // Hotplug races can remove a single endpoint during enumeration.
            guard let channels = try? outputChannels(device), channels > 0,
                  let title = try? name(device) else { return nil }
            return AudioOutputDevice(id: device, name: title, channels: channels)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private func currentDevice() throws -> AudioDeviceID {
        guard let unit = engine.outputNode.audioUnit else { throw AudioDeviceError.unavailable }
        var device = AudioDeviceID()
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let code = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, &size)
        guard code == noErr, device != kAudioObjectUnknown else { throw AudioDeviceError.status(code) }
        return device
    }
    func status() throws -> AudioDeviceStatus {
        try assertOnline()
        let device = try currentDevice()
        let rate = try Self.scalar(device, kAudioDevicePropertyNominalSampleRate, default: Double(0))
        let frames = try Self.scalar(device, kAudioDevicePropertyBufferFrameSize, default: UInt32(0))
        let range = try Self.scalar(device, kAudioDevicePropertyBufferFrameSizeRange, default: AudioValueRange())
        var property = Self.address(kAudioDevicePropertyBufferFrameSize)
        var settable = DarwinBoolean(false)
        let code = AudioObjectIsPropertySettable(device, &property, &settable)
        return AudioDeviceStatus(deviceID: device, name: try Self.name(device), sampleRate: rate, bufferFrames: frames,
                                 minimumBufferFrames: UInt32(max(0, range.mMinimum)), maximumBufferFrames: UInt32(max(0, range.mMaximum)),
                                 canSetBuffer: code == noErr && settable.boolValue)
    }
    static func uid(_ device: UInt32) throws -> String {
        var property = address(kAudioDevicePropertyDeviceUID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let code = AudioObjectGetPropertyData(device, &property, 0, nil, &size, &value)
        guard code == noErr, let value else { throw AudioDeviceError.status(code) }
        return value.takeRetainedValue() as String
    }
    func outputUID() throws -> String? { try Self.uid(currentDevice()) }
    func select(uid: String) throws {
        guard let device = try Self.availableOutputs().first(where: { (try? Self.uid($0.id)) == uid }) else { throw AudioDeviceError.unavailable }
        try select(deviceID: device.id)
    }
    func select(deviceID: UInt32) throws {
        try assertOnline()
        guard try Self.availableOutputs().contains(where: { $0.id == deviceID }) else { throw AudioDeviceError.unavailable }
        guard let unit = engine.outputNode.audioUnit else { throw AudioDeviceError.unavailable }
        let previous = try currentDevice()
        if previous == deviceID { return }
        try transaction(change: {
            var device = deviceID
            let code = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                            &device, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard code == noErr else { throw AudioDeviceError.status(code) }
        }, rollback: {
            var device = previous
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &device, UInt32(MemoryLayout<AudioDeviceID>.size))
        })
    }
    func buffer(frameCount: UInt32) throws {
        try assertOnline()
        let current = try status()
        guard current.canSetBuffer, frameCount >= current.minimumBufferFrames,
              frameCount <= current.maximumBufferFrames, frameCount > 0,
              let device = current.deviceID else { throw AudioDeviceError.invalidBuffer }
        if current.bufferFrames == frameCount { return }
        try transaction(change: {
            var property = Self.address(kAudioDevicePropertyBufferFrameSize)
            var value = frameCount
            let code = AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
            guard code == noErr else { throw AudioDeviceError.status(code) }
        }, rollback: {
            var property = Self.address(kAudioDevicePropertyBufferFrameSize)
            var value = current.bufferFrames
            AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        })
    }
    #else
    static func availableOutputs() throws -> [AudioOutputDevice] {
        let session = AVAudioSession.sharedInstance()
        return session.currentRoute.outputs.enumerated().map {
            AudioOutputDevice(id: UInt32($0.offset), name: $0.element.portName, channels: UInt32($0.element.channels?.count ?? 2))
        }
    }
    func status() throws -> AudioDeviceStatus {
        try assertOnline()
        let session = AVAudioSession.sharedInstance()
        let rate = session.sampleRate
        return AudioDeviceStatus(deviceID: nil, name: session.currentRoute.outputs.map(\.portName).joined(separator: ", "),
                                 sampleRate: rate, bufferFrames: UInt32(max(0, (session.ioBufferDuration * rate).rounded())),
                                 minimumBufferFrames: 32, maximumBufferFrames: 4096, canSetBuffer: rate > 0)
    }
    func outputUID() throws -> String? { nil }
    func select(uid: String) throws { throw AudioDeviceError.unsupported }
    func select(deviceID: UInt32) throws { try assertOnline(); throw AudioDeviceError.unsupported }
    /// iOS grants a preference rather than a guarantee; refresh status afterward.
    func buffer(frameCount: UInt32) throws {
        try assertOnline()
        let session = AVAudioSession.sharedInstance()
        guard session.sampleRate > 0, (32...4096).contains(frameCount) else { throw AudioDeviceError.invalidBuffer }
        let previous = session.preferredIOBufferDuration
        try transaction(change: {
            try session.setPreferredIOBufferDuration(Double(frameCount) / session.sampleRate)
        }, rollback: { try? session.setPreferredIOBufferDuration(previous) })
    }
    #endif
    /// Reported output chain for the published latency matrix. Available on both
    /// platforms so diagnostics can compare requested and granted buffers.
    func latency() throws -> AudioLatencyChain {
        try assertOnline()
        let status = try status()
        let reported = engine.outputNode.presentationLatency
        return AudioLatencyChain(deviceName: status.name, sampleRate: status.sampleRate,
                                 bufferFrames: status.bufferFrames, bufferMilliseconds: status.bufferMilliseconds,
                                 presentationLatencyMilliseconds: reported.isFinite ? max(0, reported) * 1000 : 0)
    }
    private func transaction(change: () throws -> Void, rollback: () -> Void) throws {
        let wasRunning = engine.isRunning
        let volume = engine.mainMixerNode.outputVolume
        if wasRunning { engine.stop() }
        do {
            try change()
            if wasRunning { engine.prepare(); try engine.start() }
            engine.mainMixerNode.outputVolume = volume
        } catch {
            let originalError = error
            rollback()
            if wasRunning && !engine.isRunning {
                do { engine.prepare(); try engine.start() }
                catch { throw AudioDeviceError.restartFailed(error.localizedDescription) }
            }
            engine.mainMixerNode.outputVolume = volume
            throw originalError
        }
    }
}
