import Foundation
import AVFoundation
import CoreMIDI
import AudioToolbox
#if os(macOS)
import Darwin
#endif

/// Numeric, operation-scoped evidence only. Never retain an NSError description,
/// source path, patch name or plug-in state in a support report.
struct AudioChangeDiagnostic: Codable, Equatable {
    enum Phase: String, Codable {
        case prepareSound, loadInstrument, restorePluginState, importedProcessing, effectControls, finishGraph, audioDevice
        var action: String {
            switch self {
            case .prepareSound: return "preparing the sound"
            case .loadInstrument: return "loading the instrument"
            case .restorePluginState: return "restoring instrument settings"
            case .importedProcessing: return "updating imported effects"
            case .effectControls: return "updating effect controls"
            case .finishGraph: return "applying the audio change"
            case .audioDevice: return "changing the audio device"
            }
        }
    }
    let requestID: UUID
    let phase: Phase
    let soundSlot: Int?
    let graphGeneration: UInt64
    let engineRunning: Bool
    let sampleRate: Double?
    /// Current device buffer when captured. nil means unmeasured, not zero.
    let bufferFrames: UInt32?
    let errorDomain: String
    let errorCode: Int
    /// True only when the controller retained its previous instrument/cache
    /// without a graph edit. Document transaction ownership belongs to Store;
    /// this flag alone never proves document rollback or uninterrupted audio.
    let previousSoundRetained: Bool?
    let lastGraphFailure: AudioGraphFailure?

    init(error: Error, phase: Phase, slot: Int?, generation: UInt64, running: Bool,
         sampleRate: Double?, bufferFrames: UInt32? = nil, previousSoundRetained: Bool? = nil,
         lastGraphFailure: AudioGraphFailure? = nil) {
        requestID = UUID(); self.phase = phase
        soundSlot = slot.flatMap { (0..<16).contains($0) ? $0 + 1 : nil }
        graphGeneration = generation; engineRunning = running
        self.sampleRate = sampleRate.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.bufferFrames = bufferFrames.flatMap { $0 > 0 ? $0 : nil }
        let ns = error as NSError
        errorCode = ns.code
        errorDomain = [NSOSStatusErrorDomain, "com.apple.coreaudio.avfaudio", NSPOSIXErrorDomain,
                       NSCocoaErrorDomain, ExternalInstrumentRack.loadCapacityErrorDomain].contains(ns.domain) ? ns.domain : "other"
        self.previousSoundRetained = previousSoundRetained
        self.lastGraphFailure = lastGraphFailure
    }
}

struct AudioChangeFailure: LocalizedError {
    let diagnostic: AudioChangeDiagnostic
    var errorDescription: String? {
        let slot = diagnostic.soundSlot.map { " for sound \($0)" } ?? ""
        if diagnostic.errorDomain == ExternalInstrumentRack.loadCapacityErrorDomain {
            let retained = diagnostic.previousSoundRetained == true ? " The previous sound remains available." : ""
            return "Could not begin another Audio Unit load\(slot). Earlier loads are still finishing. Wait before retrying. If they never finish, save your work and restart StageKeys.\(retained)"
        }
        if diagnostic.phase == .audioDevice {
            let code = diagnostic.errorCode == 0 ? "" : " (error \(diagnostic.errorCode))"
            let state = diagnostic.engineRunning
                ? "The previous audio output is still active. Choose another output in Audio Settings, then retry."
                : "Audio is stopped. Choose another output in Audio Settings, then start audio."
            return "Could not change the audio device setting\(code). \(state) Copy Support Diagnostics before reporting the problem."
        }
        if diagnostic.previousSoundRetained == true {
            return "Could not apply the sound change\(slot) while \(diagnostic.phase.action) (error \(diagnostic.errorCode)). The previous sound remains available. Check for missing sounds or samples, reconnect their storage, then try again."
        }
        if diagnostic.phase == .prepareSound {
            return "Could not prepare the sound\(slot) (error \(diagnostic.errorCode)). Check for missing sounds or samples and reconnect their storage. For an Audio Unit, review instrument availability in Audio Settings, then retry."
        }
        return "Could not complete the audio change\(slot) while \(diagnostic.phase.action) (error \(diagnostic.errorCode)). Check Audio Settings and retry. If audio has stopped, restart audio. Copy Support Diagnostics before reporting the problem."
    }
}

/// Why an audio-engine start failed, in terms the performer can act on.
struct AudioStartupFailure: Equatable {
    enum Kind: Equatable {
        case outputUnavailable
        case outputBusy
        case formatMismatch
        case interrupted
        case permissionDenied
        case unknown
        case graphRecoveryRequired
    }

    let kind: Kind
    let routeName: String?
    let code: Int

    /// Only states that can plausibly clear without the user changing a device
    /// setting are retried automatically. A format or permission failure needs
    /// an explicit user change; an unexpected failure is not retried blindly.
    var recoverable: Bool {
        switch kind {
        case .outputUnavailable, .outputBusy, .interrupted: return true
        case .formatMismatch, .permissionDenied, .unknown, .graphRecoveryRequired: return false
        }
    }

    var message: String {
        let route = routeName.map { "“\($0)”" } ?? "The selected audio output"
        switch kind {
        case .outputUnavailable:
            return "Audio could not start. \(route) is unavailable. Connect it or choose another output, then retry."
        case .outputBusy:
            return "Audio could not start. \(route) could not be opened. Another app may be using it or its sample rate changed. Close the other app, refresh the output, then retry."
        case .formatMismatch:
            return "Audio could not start. \(route) rejected the requested sample rate or buffer size. Choose a supported device setting, then retry."
        case .interrupted:
            return "Audio could not start. The system interrupted audio. Retry when the device is available."
        case .permissionDenied:
            return "Audio could not start. StageKeys is not allowed to use audio output. Check the system privacy or audio settings, then retry."
        case .unknown:
            return "Audio could not start (error \(code)). Refresh the output or choose another device, then retry."
        case .graphRecoveryRequired:
            return "Audio stopped during a sound change (error \(code)). Retry audio or open Audio Settings. Your session is still available."
        }
    }
}

enum AudioStartupClassifier {
    /// Translate AVFAudio/Core Audio/AVAudioSession failures without exposing
    /// the raw description, which can contain paths or device identifiers.
    static func classify(_ error: Error, routeName: String?) -> AudioStartupFailure {
        let ns = error as NSError
        let code = ns.code
        let domain = ns.domain.lowercased()
        let detail = ns.localizedDescription.lowercased()
        let trimmed = routeName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let route = (trimmed?.isEmpty == false) ? trimmed : nil
        let audioDomain = domain == NSOSStatusErrorDomain.lowercased()
            || domain.contains("coreaudio") || domain.contains("avfaudio")

        let kind: AudioStartupFailure.Kind
        if audioDomain {
            switch code {
            case 2003329396: kind = .outputBusy // kAudioHardwareUnspecifiedError ('what')
            case Int(kAudioUnitErr_NoConnection): kind = .outputUnavailable
            case Int(kAudioUnitErr_FormatNotSupported): kind = .formatMismatch
            case Int(kAudioUnitErr_CannotDoInCurrentContext): kind = .outputBusy
            default: kind = from(detail: detail)
            }
        } else if domain == NSPOSIXErrorDomain.lowercased() {
            switch code {
            case 16: kind = .outputBusy // EBUSY
            case 6, 19: kind = .outputUnavailable // ENXIO, ENODEV
            default: kind = from(detail: detail)
            }
        } else {
            kind = from(detail: detail)
        }
        return AudioStartupFailure(kind: kind, routeName: route, code: code)
    }

    private static func from(detail: String) -> AudioStartupFailure.Kind {
        if detail.contains("permission") || detail.contains("not permitted") || detail.contains("denied") { return .permissionDenied }
        if detail.contains("interrupt") { return .interrupted }
        if detail.contains("format") || detail.contains("sample rate") || detail.contains("sample-rate") { return .formatMismatch }
        if detail.contains("in use") || detail.contains("busy") || detail.contains("exclusive") { return .outputBusy }
        if detail.contains("device") || detail.contains("output") || detail.contains("route")
            || detail.contains("disconnect") || detail.contains("unavailable") { return .outputUnavailable }
        return .unknown
    }
}

/// Bounded automatic retries. The first two failures wait 0.25 s and 0.75 s;
/// the third failure leaves the engine stopped and the failure visible for a
/// manual retry. These are delays, not a claim about recovery probability.
struct AudioStartupRetryPolicy: Equatable {
    let maximumAttempts: Int
    let delays: [TimeInterval]

    init(maximumAttempts: Int = 3, delays: [TimeInterval] = [0.25, 0.75]) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.delays = delays.map { max(0, $0) }
    }

    func delay(afterFailedAttempt attempt: Int) -> TimeInterval? {
        guard attempt >= 1, attempt < maximumAttempts else { return nil }
        let index = attempt - 1
        guard index < delays.count else { return nil }
        return delays[index]
    }
}

enum AudioStartupRecovery {
    /// Unplug/replug, sleep/wake and route changes all arrive as engine
    /// configuration changes. Only restart audio that was running; a stopped or
    /// failed engine waits for an explicit start so an implicit retry loop cannot
    /// start it while the device is still settling.
    static func shouldRestartAfterConfigurationChange(started: Bool, engineRunning: Bool) -> Bool {
        started && !engineRunning
    }
}

enum AudioStartupState: Equatable {
    case stopped
    case starting(attempt: Int)
    case retrying(attempt: Int, delay: TimeInterval, failure: AudioStartupFailure)
    case running
    case failed(AudioStartupFailure)

    var isStarting: Bool {
        switch self {
        case .starting, .retrying: return true
        case .stopped, .running, .failed: return false
        }
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var failure: AudioStartupFailure? {
        switch self {
        case .retrying(_, _, let failure), .failed(let failure): return failure
        case .stopped, .starting, .running: return nil
        }
    }
}

final class AudioController {
    private let engine = AVAudioEngine()
    private let synth: OpaquePointer
    private let metronomeEngine: OpaquePointer
    private var metronomeNode: AVAudioSourceNode!
    private var metronomeFollowsMaster = true
    private var masterVolume: Float = 0.7
    private let reverb = AVAudioUnitReverb()
    private let outputLimiter=AVAudioUnitEffect(audioComponentDescription:AudioComponentDescription(componentType:kAudioUnitType_Effect,componentSubType:kAudioUnitSubType_PeakLimiter,componentManufacturer:kAudioUnitManufacturer_Apple,componentFlags:0,componentFlagsMask:0))
    private let protectedOutput=AVAudioMixerNode()
    private var source: AVAudioSourceNode!
    lazy var deviceController = AudioDeviceController(engine: engine)
    lazy var externalRack: ExternalInstrumentRack? = try? ExternalInstrumentRack(engine: engine)
    private var externalSounds: [Int: ExternalSound] = [:]
    private var externalStates: [Int: Data] = [:]
    private var samplerAttacks:[Int:Float]=[:]
    private var samplerHostCurves:[Int:Int]=[:]
    private var levels: [Int: Float] = [:]
    private var diagnosticRecorder:AudioDiagnosticRecorder?
    private let outputMeter=OutputMeter()
    private var outputTapInstalled=false
    var outputMetrics:OutputMeter.Reading {outputMeter.read()}
    private func installOutputTap(recorder:AudioDiagnosticRecorder?=nil) {
        if outputTapInstalled {protectedOutput.removeTap(onBus:0)}
        let meter=outputMeter
        protectedOutput.installTap(onBus:0,bufferSize:512,format:protectedOutput.outputFormat(forBus:0)) { [weak recorder] buffer,_ in
            meter.append(buffer);recorder?.append(buffer)
        }
        outputTapInstalled=true
    }
    func startAudioCheck(at url:URL,completion:@escaping(Result<AudioDiagnosticRecorder.Summary,Error>)->Void)throws {
        guard engine.isRunning,diagnosticRecorder==nil else{throw NSError(domain:"StageKeysAudioCheck",code:2,userInfo:[NSLocalizedDescriptionKey:"Start audio playback and stop any existing audio check first."])}
        let format=protectedOutput.outputFormat(forBus:0)
        let recorder=try AudioDiagnosticRecorder(url:url,format:format) { [weak self] result in
            self?.diagnosticRecorder=nil;self?.installOutputTap()
            completion(result)
        }
        diagnosticRecorder=recorder
        installOutputTap(recorder:recorder)
    }
    func stopAudioCheck(){diagnosticRecorder?.finish()}
    // Session-only diagnostic switch. Keep the graph and 1 dB output headroom
    // unchanged so the limiter is the only processor toggled for comparison.
    func bypassMasterLimiter(_ bypassed:Bool){outputLimiter.bypass=bypassed}
    var onError: ((String) -> Void)?
    var onGraphUnavailable: ((AudioChangeDiagnostic) -> Void)?
    private(set) var lastChangeFailure: AudioChangeDiagnostic?
    private var handledGraphFailure: UUID?
    private var rebuildRackOnStart = false
    #if DEBUG
    /// Deterministic preparation failure; no target application or user content.
    var debugSoundPreparationFailure: Error?
    var debugStartFailure: (() -> Error?)?
    /// Reports a failure after the engine itself started, so tests can exercise
    /// cleanup from a partially initialized start without a real device.
    var debugFailureAfterEngineStart: (() -> Error?)?
    #endif
    @discardableResult
    private func changeFailure(_ error: Error, phase: AudioChangeDiagnostic.Phase,
                               slot: Int? = nil, retained: Bool? = nil, forceUnavailable: Bool = false,
                               includeGraphFailure: Bool = true, bufferFrames: UInt32? = nil) -> AudioChangeFailure {
        let rate = engine.isInManualRenderingMode ? engine.manualRenderingFormat.sampleRate : engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        let graphFailure = includeGraphFailure ? externalRack?.lastGraphFailure : nil
        let diagnostic = AudioChangeDiagnostic(error: error, phase: phase, slot: slot,
            generation: externalRack?.graphGeneration ?? 0, running: engine.isRunning,
            sampleRate: rate, bufferFrames: bufferFrames, previousSoundRetained: retained, lastGraphFailure: graphFailure)
        lastChangeFailure = diagnostic
        let graphUnavailable = includeGraphFailure && (diagnostic.lastGraphFailure.map { $0.edited && $0.wasRunning && !engine.isRunning && handledGraphFailure != $0.id } ?? false)
        if forceUnavailable || graphUnavailable {
            rebuildRackOnStart = true
            handledGraphFailure = diagnostic.lastGraphFailure?.id
            // A candidate may already be attached despite a finish failure.
            // Do not let identity caches suppress the saved patch's reload on
            // manual retry, or expose state from an unqualified live unit.
            invalidateInstrumentCaches()
            onGraphUnavailable?(diagnostic)
        }
        return AudioChangeFailure(diagnostic: diagnostic)
    }
    /// Direct rack clients (the transactional Tonic picker) use the same graph
    /// completion reporting and stopped-engine recovery as channel loads.
    func recordInstrumentLoadFailure(_ error: Error, channel: Int) -> AudioChangeFailure {
        changeFailure(error, phase: .loadInstrument, slot: channel)
    }
    /// Device/route operations are not rack graph edits. Record the underlying
    /// numeric Core Audio/AVFAudio cause for support without attaching a stale
    /// graph failure or entering graph-recovery ownership by mistake.
    @discardableResult
    func recordAudioDeviceFailure(_ error: Error) -> AudioChangeFailure {
        let cause: Error
        if let device = error as? AudioDeviceError, case .resumeFailed(let underlying) = device { cause = underlying }
        else { cause = error }
        let frames = (try? deviceController.status())?.bufferFrames
        return changeFailure(cause, phase: .audioDevice, includeGraphFailure: false, bufferFrames: frames)
    }
    /// Check known unavailable resources before the store changes snapshots,
    /// panics held notes, or persists the proposed sound. Does not load an AU or
    /// edit the graph; successful preflight is not proof a later install succeeds.
    func prepareSoundChange(_ index: Int, _ layer: Layer, revalidateResources: Bool = false, checkInstallation: Bool = true) throws {
        let hostCurve = layer.importedRack?.mainStageAmplitudeVelocityCurve ?? layer.external?.nativeSampler?.rack.mainStageAmplitudeVelocityCurve
        guard let sound = layer.external,
              (revalidateResources && sound.kind != .audioUnit) || externalSounds[index] != sound || externalStates[index] != layer.pluginState ||
              samplerAttacks[index] != layer.samplerAttackMinimum || samplerHostCurves[index] != hostCurve else { return }
        do {
            #if DEBUG
            if let failure = debugSoundPreparationFailure { throw failure }
            #endif
            guard let rack = externalRack else { throw ExternalInstrumentError.invalidComponent }
            try rack.validateSound(sound, checkInstallation: checkInstallation)
        } catch {
            throw changeFailure(error, phase: .prepareSound, slot: index,
                                retained: externalRack?.unit(channel: index) != nil && engine.isRunning ? true : nil)
        }
    }
    func withInstrumentCatalog<T>(_ operation: () throws -> T) rethrows -> T {
        if let rack = externalRack { return try rack.withInstrumentCatalog(operation) }
        return try operation()
    }
    func preparePatchResources(_ layers: [Layer]) throws {
        try withInstrumentCatalog {
            for (index, layer) in layers.enumerated() { try prepareSoundChange(index, layer, revalidateResources: true) }
        }
    }
    var offline: Bool { engine.isInManualRenderingMode }
    #if DEBUG
    func installPlaybackProbe(_ callback:@escaping (AVAudioPCMBuffer)->Void) {
        engine.mainMixerNode.installTap(onBus:0,bufferSize:512,format:nil){buffer,_ in callback(buffer)}
    }
    func removePlaybackProbe(){engine.mainMixerNode.removeTap(onBus:0)}
    #endif
    func panic(channel:Int,preserveEffectTails:Bool=false) { if preserveEffectTails {sk_release_voices(synth,Int32(channel))} else {sk_panic_channel(synth,Int32(channel))}; externalRack?.panic(channel,preserveEffectTails:preserveEffectTails) }
    /// Mark a sampler already installed directly by a transactional pad load so
    /// the following control/effect configuration does not detach and reload it.
    func adoptExternalSound(_ sound:ExternalSound?,channel:Int) {
        unavailableConfigurations.remove(channel)
        externalSounds[channel]=sound
        externalStates[channel]=nil
        samplerAttacks[channel]=0
        samplerHostCurves[channel]=sound?.nativeSampler?.rack.mainStageAmplitudeVelocityCurve
    }
    var running: Bool { engine.isRunning }
    init() {
        #if os(macOS)
        // LaunchServices can give GUI apps a 256-file soft limit, unlike a shell.
        // Streamed multi-sample pianos and graph reloads can exceed that budget.
        // Raise only this process's soft limit, within its existing hard limit.
        var files=rlimit()
        if getrlimit(RLIMIT_NOFILE,&files)==0 {
            let desired=min(files.rlim_max,rlim_t(16384))
            if files.rlim_cur<desired {files.rlim_cur=desired;_ = setrlimit(RLIMIT_NOFILE,&files)}
        }
        #endif
        synth = sk_create(48_000)!
        metronomeEngine = sk_metronome_create(48_000)!
        let pointer = synth
        let metronomePointer = metronomeEngine
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        source = AVAudioSourceNode(format: format) { _, _, frames, list in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard buffers.count >= 2, let l = buffers[0].mData, let r = buffers[1].mData else { return -1 }
            sk_render(pointer, l.assumingMemoryBound(to: Float.self), r.assumingMemoryBound(to: Float.self), frames)
            return noErr
        }
        // The click bypasses the shared hall reverb and is mixed into the
        // protected output, so its level and accents stay predictable.
        metronomeNode = AVAudioSourceNode(format: format) { _, _, frames, list in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard buffers.count >= 2, let l = buffers[0].mData, let r = buffers[1].mData else { return -1 }
            sk_metronome_render(metronomePointer, l.assumingMemoryBound(to: Float.self), r.assumingMemoryBound(to: Float.self), frames)
            return noErr
        }
        engine.attach(source); engine.attach(reverb); engine.attach(metronomeNode)
        reverb.loadFactoryPreset(.largeHall); reverb.wetDryMix = 22
        engine.connect(source, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.attach(outputLimiter);engine.attach(protectedOutput)
        AudioUnitSetParameter(outputLimiter.audioUnit,kLimiterParam_AttackTime,kAudioUnitScope_Global,0,0.001,0)
        AudioUnitSetParameter(outputLimiter.audioUnit,kLimiterParam_DecayTime,kAudioUnitScope_Global,0,0.06,0)
        AudioUnitSetParameter(outputLimiter.audioUnit,kLimiterParam_PreGain,kAudioUnitScope_Global,0,0,0)
        engine.connect(engine.mainMixerNode,to:outputLimiter,format:format)
        engine.connect(outputLimiter,to:protectedOutput,format:format)
        engine.connect(protectedOutput,to:engine.outputNode,format:format)
        engine.connect(metronomeNode,to:protectedOutput,format:format)
        // Leave 1 dB after limiting for reconstructed output peaks.
        protectedOutput.outputVolume=pow(Float(10),Float(-1)/20)
        engine.mainMixerNode.outputVolume = 0.7
        installOutputTap()
    }
    func start() throws {
        #if DEBUG
        if let failure = debugStartFailure?() { throw failure }
        #endif
        if rebuildRackOnStart {
            engine.stop()
            invalidateInstrumentCaches()
            externalRack?.resetForRecovery()
            rebuildRackOnStart = false
        }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setPreferredIOBufferDuration(0.0053)
        try session.setActive(true)
        #endif
        if !engine.isRunning { engine.prepare(); try engine.start() }
        #if DEBUG
        if let failure = debugFailureAfterEngineStart?() { throw failure }
        #endif
    }
    func stop() { stopAudioCheck();sk_panic(synth); engine.stop() }
    private var deliveryPolicy = MIDIDeliveryPolicy()
    /// Reports a channel whose hosted AU can no longer take sample-timed events
    /// after a rejected install or a retirement, so the scheduler drops its mark.
    var onLookaheadEligibilityLost: ((Int) -> Void)?
    /// Convert a musical deadline into an AU event sample time from the last
    /// render timestamp. Returns nil when the event cannot still be scheduled
    /// ahead of the render position, in which case the caller delivers now.
    private func auDelivery(for deadline: TimeInterval?, canSchedule: Bool) -> MIDIEventDelivery {
        guard deadline != nil, canSchedule else { return .immediate }
        guard let render = engine.outputNode.lastRenderTime,
              render.isSampleTimeValid, render.isHostTimeValid else { return .immediate }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = AVAudioTime.seconds(forHostTime: mach_absolute_time() &- render.hostTime)
        let current = render.sampleTime + AVAudioFramePosition((elapsed * render.sampleRate).rounded())
        let timeline = MIDIAudioTimeline(sampleRate: render.sampleRate,
                                         anchorSample: Int64(current), anchorTime: now)
        return deliveryPolicy.delivery(deadline: deadline, now: now, timeline: timeline,
                                       currentSample: Int64(current), canSchedule: canSchedule)
    }
    /// True when this slot is a hosted AU whose events can be delivered at a
    /// future sample time. Parallel imported branches stay immediate.
    func canScheduleMIDI(channel: Int) -> Bool {
        // A channel whose replacement is still loading or failed to install must
        // not be treated as schedulable on its outgoing unit.
        !unavailableConfigurations.contains(channel) && externalSounds[channel] != nil &&
            (externalRack?.canSchedule(channel: channel) ?? false)
    }
    func noteOn(key: Int, pitch: Int, instrument: Int, layer: Int, velocity: Float,sourceID:Int32? = nil,at deadline: TimeInterval? = nil) {
        if externalSounds[layer] != nil {
            let sampleTime = auDelivery(for: deadline, canSchedule: true).sampleTime
            externalRack?.noteOn(channel: layer, key: key, pitch: pitch, velocity: velocity,sourceID:sourceID,sampleTime:sampleTime)
        }
        // Synth.c remains the effect/clock core; product notes require user content.
    }
    func noteOff(key: Int, channel: Int, force: Bool = false, at deadline: TimeInterval? = nil) {
        sk_note_off_channel(synth, Int32(key), Int32(channel), force ? 1 : 0)
        let sampleTime = auDelivery(for: deadline, canSchedule: true).sampleTime
        externalRack?.noteOff(channel: channel, key: key, forceRelease: force, sampleTime: sampleTime)
    }
    func noteOff(_ key: Int) { sk_note_off(synth, Int32(key)); externalRack?.noteOff(key: key) }
    private var patchGain: Float = 1
    private var patchLoading = false
    func setPatchLoading(_ loading: Bool) {
        patchLoading = loading
        for (index, level) in levels where index < 15 { gain(index, level, seconds: 0) }
    }
    private var outputTrims:[Int:Float]=[:]
    private func scaledGain(_ index:Int,_ gain:Float)->Float { gain * (outputTrims[index] ?? 1) * (index < 15 ? (patchLoading ? 0 : patchGain) : 1) }
    func setPatchVolume(_ db:Float) { patchGain=pow(10,max(-24,min(12,db))/20);for (index,gain) in levels where index<15 { self.gain(index,gain) } }
    func gain(_ index: Int, _ gain: Float, seconds: Float = 0.025) {
        levels[index] = gain
        sk_gain(synth, Int32(index), scaledGain(index,gain), seconds)
        externalRack?.unit(channel: index).map { _ in externalRack?.volume(channel: index, gain: scaledGain(index,gain), pan: pans[index] ?? 0) }
    }
    private var effects: [Int: [AudioEffect]] = [:]
    private var tempo: Float = 72
    private var importedRacks: [Int: ImportedRack] = [:]
    private var pans: [Int: Float] = [:]
    private var modulationValues: [Int: Float] = [:]
    func modulation(_ index: Int, value: Float) {
        let bounded = value.isFinite ? max(0, min(1, value)) : 0
        modulationValues[index] = bounded
        externalRack?.control(channel: index, controller: 1, value: UInt8((bounded * 127).rounded()))
    }
    func filter(_ index: Int, _ layer: Layer, mod: Float) {
        let c = layer.channelSettings
        let cutoff = c.cutoff(modulation: mod)
        sk_filter(synth, Int32(index), cutoff, c.resonance)
        externalRack?.processing(channel: index, gain: c.samplerGain, cutoff: cutoff, resonance: c.resonance,
            eqEnabled: c.eqEnabled, bands: c.equalizer.map { ($0.frequency, $0.gain, $0.q) },
            compressorEnabled: c.compressorEnabled, threshold: c.threshold, attack: c.compressorAttack, release: c.compressorRelease, makeup: c.makeup,ratio:c.ratio,inputGain:c.compressorInputGain ?? 0,mix:c.compressorMix ?? 1)
    }
    private var hostGraphBatchDepth = 0
    private var pendingPatchFailure: Error?
    func withGraphChanges(_ operation: () throws -> Void) throws {
        let outer = hostGraphBatchDepth == 0
        if outer { pendingPatchFailure = nil }
        hostGraphBatchDepth += 1
        defer { hostGraphBatchDepth -= 1; if outer { pendingPatchFailure = nil } }
        let initialRequests = configurationRequests
        do {
            if let rack = externalRack {
                try rack.withGraphChanges {
                    try operation()
                    if outer, let failure = pendingPatchFailure { throw failure }
                }
            } else {
                try operation()
                if outer, let failure = pendingPatchFailure { throw failure }
            }
        } catch {
            // Whole-patch callers may already have changed selection, MIDI or
            // control caches inside the batch. A rack rollback alone cannot
            // publish that batch as Running; explicit retry rebuilds the saved
            // selected patch and invalidates those speculative caches.
            if let failure = pendingPatchFailure { publishPatchFailure(failure) }
            else {
                if externalRack?.lastGraphFailure?.edited == true && initialRequests != configurationRequests { engine.stop() }
                changeFailure(error, phase: .finishGraph)
            }
            throw error // Preserve the caller's typed-error handling contract.
        }
    }
    func rejectPatchChange(_ error: Error) {
        if hostGraphBatchDepth > 0 { pendingPatchFailure = pendingPatchFailure ?? error; return }
        publishPatchFailure(error)
    }
    private func publishPatchFailure(_ error: Error) {
        engine.stop()
        if let failure = error as? AudioChangeFailure {
            let d = failure.diagnostic
            changeFailure(NSError(domain: d.errorDomain, code: d.errorCode), phase: d.phase,
                          slot: d.soundSlot.map { $0 - 1 }, forceUnavailable: true)
        } else { changeFailure(error, phase: .finishGraph, forceUnavailable: true) }
    }
    private func invalidateInstrumentCaches() {
        cancelPendingConfigurations()
        externalSounds.removeAll(); externalStates.removeAll()
        samplerAttacks.removeAll(); samplerHostCurves.removeAll()
        effects.removeAll(); importedRacks.removeAll()
    }
    /// Offline document edits must not instantiate instruments or capture old
    /// live AU state over the newly authored settings. Rebuild at next Start.
    func prepareOfflineEditing() {
        precondition(!engine.isRunning)
        invalidateInstrumentCaches()
        rebuildRackOnStart = true
    }
    func cancelPendingConfigurations() {
        configurationRequests.removeAll(); unavailableConfigurations.removeAll()
        for channel in 0..<16 { externalRack?.cancelPendingLoad(channel) }
    }
    private var configurationRequests: [Int: UUID] = [:]
    private var unavailableConfigurations: Set<Int> = []
    /// The rack may still be playing the previous instrument during a pending
    /// replacement. Editors and state capture must match the document's sound,
    /// not merely find any live unit in that channel.
    func loadedUnit(channel: Int, sound: ExternalSound?) -> AVAudioUnit? {
        guard !unavailableConfigurations.contains(channel), let sound, externalSounds[channel] == sound else { return nil }
        return externalRack?.unit(channel: channel)
    }
    func pluginStateData(channel: Int, sound: ExternalSound?) throws -> Data? {
        guard sound?.kind == .audioUnit, loadedUnit(channel: channel, sound: sound) != nil else { return nil }
        return try externalRack?.stateData(channel: channel)
    }
    /// Capture only the draft's installed AU. A pending/rejected replacement
    /// must retain its authored state instead of borrowing the old unit's state.
    func calibrationSource(_ layer: Layer, channel: Int) throws -> Layer {
        var source = layer
        if source.external?.kind == .audioUnit {
            source.pluginState = try pluginStateData(channel: channel, sound: source.external) ?? source.pluginState
        }
        return source
    }
    /// False reports a synchronous preparation/loading rejection. True means
    /// accepted, including pending asynchronous AU loads. Later state/effect or
    /// graph-finalization failures are not covered by this acceptance result.
    @discardableResult
    func configure(_ index: Int, _ layer: Layer, shouldInstall: (() -> Bool)? = nil, completion: ((Bool) -> Void)? = nil) -> Bool {
        withInstrumentCatalog { configurePrepared(index, layer, shouldInstall: shouldInstall, completion: completion) }
    }
    private func configurePrepared(_ index: Int, _ layer: Layer, shouldInstall: (() -> Bool)?, completion: ((Bool) -> Void)?) -> Bool {
        do { try prepareSoundChange(index, layer) }
        catch { onError?(error.localizedDescription); completion?(false); return false }
        let request = UUID()
        configurationRequests[index] = request
        externalRack?.cancelPendingLoad(index)
        let hostCurve = layer.importedRack?.mainStageAmplitudeVelocityCurve ?? layer.external?.nativeSampler?.rack.mainStageAmplitudeVelocityCurve
        let changed = samplerHostCurves[index] != hostCurve || externalSounds[index] != layer.external ||
            externalStates[index] != layer.pluginState || samplerAttacks[index] != layer.samplerAttackMinimum
        if changed, let sound = layer.external {
            guard let rack = externalRack else {
                onError?(changeFailure(ExternalInstrumentError.invalidComponent, phase: .loadInstrument, slot: index).localizedDescription)
                completion?(false)
                return false
            }
            let previousUnit = rack.unit(channel: index)
            let previousGeneration = rack.graphGeneration
            unavailableConfigurations.insert(index)
            var rejected = false
            // Rack installation retires the old voice only after candidate
            // preparation succeeds. Do not remove it or change active caches,
            // gain/pan/effects before the loader has accepted the replacement.
            rack.load(sound, channel: index, attackMinimum: layer.samplerAttackMinimum, hostVelocityCurve: hostCurve, configureCandidate: {
                // AU state belongs to the staged candidate. A rejected document
                // must roll back before the loader reports installation success.
                guard shouldInstall?() ?? true else { throw ExternalInstrumentError.superseded }
                if self.patchLoading { rack.volume(channel: index, gain: 0, pan: layer.pan) }
                if let state = layer.pluginState { try rack.restoreStateData(state, channel: index) }
            }) { [weak self] result in
                guard let self, self.configurationRequests[index] == request else { completion?(false); return }
                switch result {
                case .success:
                    self.externalSounds[index] = sound
                    self.externalStates[index] = layer.pluginState
                    self.samplerAttacks[index] = layer.samplerAttackMinimum
                    self.samplerHostCurves[index] = hostCurve
                    self.unavailableConfigurations.remove(index)
                    guard self.applyLayerConfiguration(index, layer, forceEffects: true) else {
                        rejected = true
                        self.rejectPatchChange(self.lastChangeFailure.map { AudioChangeFailure(diagnostic: $0) } ?? ExternalInstrumentError.unsupportedEffect)
                        completion?(false); return
                    }
                    completion?(true)
                case .failure(let error):
                    rejected = true
                    if let e = error as? ExternalInstrumentError, case .superseded = e {
                        self.unavailableConfigurations.remove(index)
                        completion?(false)
                        return
                    }
                    let unchanged = rack.unit(channel: index) === previousUnit && (rack.graphGeneration == previousGeneration || rack.lastGraphFailure?.rollbackSucceeded == true)
                    if unchanged && self.externalSounds[index] != sound {
                        self.unavailableConfigurations.remove(index)
                    } else {
                        self.onLookaheadEligibilityLost?(index)
                    }
                    self.onError?(self.changeFailure(error, phase: .loadInstrument, slot: index, retained: unchanged ? true : nil).localizedDescription)
                    completion?(false)
                }
            }
            return !rejected
        }
        if changed {
            do { try externalRack?.remove(index) }
            catch {
                onError?(changeFailure(error, phase: .loadInstrument, slot: index).localizedDescription)
                completion?(false)
                return false
            }
            externalSounds[index] = nil
            onLookaheadEligibilityLost?(index)
            externalStates[index] = layer.pluginState
            samplerAttacks[index] = layer.samplerAttackMinimum
            samplerHostCurves[index] = hostCurve
        }
        unavailableConfigurations.remove(index)
        guard applyLayerConfiguration(index, layer) else {
            rejectPatchChange(lastChangeFailure.map { AudioChangeFailure(diagnostic: $0) } ?? ExternalInstrumentError.unsupportedEffect)
            completion?(false); return false
        }
        completion?(true)
        return true
    }
    private func applyLayerConfiguration(_ index: Int, _ layer: Layer, forceEffects: Bool = false) -> Bool {
        outputTrims[index] = pow(10, (layer.channelSettings.outputTrimDB ?? 0) / 20)
        pans[index] = layer.pan
        externalRack?.volume(channel: index, gain: scaledGain(index,levels[index] ?? layer.gain), pan: layer.pan)
        let c = layer.channelSettings
        sk_envelope(synth, Int32(index), c.attack, c.decay, c.sustain, c.release)
        sk_voice_limit(synth, Int32(index), Int32(c.voiceCount))
        sk_sampler_gain(synth, Int32(index), c.samplerGain)
        for (band, eq) in c.equalizer.enumerated() { sk_eq(synth, Int32(index), Int32(band), c.eqEnabled ? eq.frequency : (band == 0 ? 20 : band == 7 ? 20000 : eq.frequency), c.eqEnabled ? eq.gain : 0, eq.q) }
        sk_compressor(synth, Int32(index), c.compressorEnabled ? 1 : 0, c.threshold, c.ratio, c.compressorAttack, c.compressorRelease, c.makeup)
        sk_compressor_blend(synth,Int32(index),c.compressorInputGain ?? 0,c.compressorMix ?? 1)
        filter(index, layer, mod: modulationValues[index] ?? 1)
        sk_pan(synth, Int32(index), layer.pan)
        sk_block_sustain(synth, Int32(index), layer.blockSustain ? 1 : 0)
        guard configureEffects(index, layer.effects, force: forceEffects) else { return false }
        return configureImported(index,layer.importedRack ?? layer.external?.nativeSampler?.rack)
    }
    @discardableResult
    private func configureImported(_ index:Int,_ rack:ImportedRack?) -> Bool {
        if let rack { importedRacks[index]=rack } else {importedRacks[index]=nil}
        do {try externalRack?.configureParallel(channel:index,branches:rack?.branches ?? externalSounds[index]?.nativeSampler?.rack.branches,tempo:tempo);try externalRack?.configureImported(channel:index,rack:rack,tempo:tempo)}
        catch {onError?(changeFailure(error, phase: .importedProcessing, slot: index).localizedDescription); return false}
        if rack?.mainStageUnityControllers==true {externalRack?.initializeMainStageControllers(channel:index)}
        return true
    }
    func audition(_ index: Int, _ layer: Layer) {
        var live = layer
        if live.external?.kind == .audioUnit { live.pluginState = externalStates[index] }
        configure(index,live)
    }
    func restoreAuditionState(_ index: Int, _ state: Data) throws {
        do { try externalRack?.restoreStateData(state,channel:index) }
        catch {
            changeFailure(error, phase: .restorePluginState, slot: index)
            throw error
        }
        externalStates[index] = state
    }
    /// Commit processing caches and C controls only after every rack edit has
    /// completed. This does not instantiate or change the selected instrument.
    @discardableResult
    func applySnapshotStates(_ states: [Int: SnapshotSoundState], restorePluginStates: Bool = false) -> Bool {
        guard !states.isEmpty else { return true }
        var pluginStates: [Int: Data] = [:]
        do {
            for (index, state) in states {
                guard (0..<15).contains(index), state.effects.count == 3,
                      state.effects.allSatisfy({ $0.validate() }), state.pan.isFinite, (-1...1).contains(state.pan),
                      state.importedRack?.validate() ?? true else { throw ExternalInstrumentError.unsupportedFormat }
                if restorePluginStates, let data = state.pluginState, externalSounds[index]?.kind == .audioUnit,
                   externalStates[index] != data {
                    guard loadedUnit(channel: index, sound: externalSounds[index]) != nil, data.count <= 2_000_000,
                          (try PropertyListSerialization.propertyList(from: data, options: [], format: nil)) is [String: Any] else {
                        throw ExternalInstrumentError.unsupportedFormat
                    }
                    pluginStates[index] = data
                }
            }
            if let rack = externalRack {
                try rack.withGraphChanges(capturingControls: true) {
                    for index in states.keys.sorted() {
                        let state = states[index]!
                        if let data = pluginStates[index] { try rack.restoreStateData(data, channel: index) }
                        let imported = state.importedRack ?? externalSounds[index]?.nativeSampler?.rack
                        try rack.configureParallel(channel: index, branches: imported?.branches, tempo: tempo)
                        try rack.configureImported(channel: index, rack: imported, tempo: tempo)
                        for (slot, fx) in state.effects.enumerated() {
                            var values = fx.renderValues
                            if fx.kind == 2, let beats = fx.syncBeats { values[1] = min(20, max(0.01, tempo / (60 * beats))) }
                            try rack.configureEffect(channel: index, slot: slot, kind: fx.kind, enabled: fx.enabled, parameters: values, tempo: tempo, delay: fx.playbackDelay)
                        }
                        rack.volume(channel: index, gain: scaledGain(index, levels[index] ?? 0), pan: state.pan)
                    }
                }
            }
        } catch {
            onError?(changeFailure(error, phase: .importedProcessing).localizedDescription)
            return false
        }
        for (index, state) in states {
            pans[index] = state.pan
            externalRack?.volume(channel: index, gain: scaledGain(index, levels[index] ?? 0), pan: state.pan)
            sk_pan(synth, Int32(index), state.pan)
            configureEffects(index, state.effects, configureRack: false)
            let imported = state.importedRack ?? externalSounds[index]?.nativeSampler?.rack
            importedRacks[index] = imported
            if imported?.mainStageUnityControllers == true { externalRack?.initializeMainStageControllers(channel: index) }
            if let data = pluginStates[index] { externalStates[index] = data }
        }
        return true
    }
    @discardableResult
    func configureSnapshot(_ index: Int, effects: [AudioEffect], pan: Float, importedRack: ImportedRack? = nil) -> Bool {
        var layer = Layer.empty(); layer.effects = effects; layer.pan = pan; layer.importedRack = importedRack
        return applySnapshotStates([index: SnapshotSoundState(layer)])
    }
    @discardableResult
    private func configureEffects(_ index: Int, _ chain: [AudioEffect], force: Bool = false, configureRack: Bool = true) -> Bool {
        for (slot, fx) in chain.enumerated() {
            let old = effects[index].flatMap { $0.indices.contains(slot) ? $0[slot] : nil }
            guard force || old != fx else { continue }
            sk_effect(synth,Int32(index),Int32(slot),fx.enabled ? Int32(fx.kind) : 0,fx.amount)
            if fx.enabled && (fx.parameters != nil || fx.kind > 3) {
                var values = fx.renderValues
                if fx.kind == 2, let beats = fx.syncBeats { values[1] = min(20,max(0.01,tempo/(60*beats))) }
                for (p,value) in values.enumerated() { sk_effect_parameter(synth,Int32(index),Int32(slot),Int32(p),value) }
            }
            if configureRack && externalSounds[index] != nil {
                do { var values=fx.renderValues;if fx.kind==2,let beats=fx.syncBeats {values[1]=min(20,max(0.01,tempo/(60*beats)))};try externalRack?.configureEffect(channel:index,slot:slot,kind:fx.kind,enabled:fx.enabled,parameters:values,tempo:tempo,delay:fx.playbackDelay) }
                catch { onError?(changeFailure(error, phase: .effectControls, slot: index).localizedDescription); return false }
            }
        }
        effects[index] = chain
        return true
    }
    func effect(_ index: Int, _ slot: Int, _ kind: Int, _ amount: Float) { sk_effect(synth, Int32(index), Int32(slot), Int32(kind), amount) }
    func clock(_ tempo: Double, _ enabled: Bool) {
        let changed = self.tempo != Float(tempo); self.tempo = Float(tempo)
        sk_clock(synth,Float(tempo))
        sk_metronome_tempo(metronomeEngine, Float(tempo))
        sk_metronome_enable(metronomeEngine, enabled ? 1 : 0)
        if changed { for (index,chain) in effects { configureEffects(index,chain,force:true) }; for (index,rack) in importedRacks {configureImported(index,rack)} }
    }
    func releaseSource(_ source:Int32){externalRack?.releaseSource(source)}
    func sustain(_ on: Bool, layers: [Layer]) { sk_sustain(synth, on ? 1 : 0); for (i,l) in layers.enumerated() { externalRack?.sustain(channel: i, on: on && !l.blockSustain) } }
    func panic() { sk_panic(synth); sk_metronome_reset(metronomeEngine); externalRack?.panic(); reverb.auAudioUnit.reset(); outputLimiter.auAudioUnit.reset() }
    /// Reported output latency for the published device/buffer matrix. Never
    /// called from the render callback.
    func latencyChain() throws -> AudioLatencyChain { try deviceController.latency() }
    func master(_ volume: Float) { masterVolume = volume; engine.mainMixerNode.outputVolume = volume; sk_metronome_master(metronomeEngine, volume, metronomeFollowsMaster ? 1 : 0) }
    /// Applies persisted click controls. The engine keeps its own sample-accurate
    /// clock; no audio-thread allocation or locking is involved.
    func metronome(_ enabled: Bool, settings: MetronomeSettings) {
        metronomeFollowsMaster = settings.followsMaster
        sk_metronome_settings(metronomeEngine, SKMetronomeSettings(level: settings.level, preset: Int32(settings.preset), beatVelocity: settings.beatVelocity, downbeatEnabled: settings.downbeatEnabled ? 1 : 0, downbeatVelocity: settings.downbeatVelocity, beatsPerBar: Int32(settings.beatsPerBar), accentEvery: Int32(settings.accentEvery), subdivision: Int32(settings.subdivision), countInBars: Int32(settings.countInBars)))
        sk_metronome_master(metronomeEngine, masterVolume, metronomeFollowsMaster ? 1 : 0)
        sk_metronome_enable(metronomeEngine, enabled ? 1 : 0)
    }
    func space(_ amount: Float) { reverb.wetDryMix = amount }
    // Runs an isolated production graph without sending sound to the device.
    func prepareOffline() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        try externalRack?.prepareOfflineSamples()
        try engine.start()
    }
    func offlineBlock() throws -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 512)!
        let status = try engine.renderOffline(512, to: buffer)
        guard status == .success else { throw NSError(domain: "StageKeysOffline", code: Int(status.rawValue)) }
        return buffer
    }
    deinit { engine.stop(); sk_destroy(synth); sk_metronome_destroy(metronomeEngine) }
}
