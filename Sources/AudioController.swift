import Foundation
import AVFoundation
import CoreMIDI
import AudioToolbox
#if os(macOS)
import Darwin
#endif

/// Why an audio-engine start failed, in terms the performer can act on.
struct AudioStartupFailure: Equatable {
    enum Kind: Equatable {
        case outputUnavailable
        case outputBusy
        case formatMismatch
        case interrupted
        case permissionDenied
        case unknown
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
        case .formatMismatch, .permissionDenied, .unknown: return false
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
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setPreferredIOBufferDuration(0.0053)
        try session.setActive(true)
        #endif
        if !engine.isRunning { engine.prepare(); try engine.start() }
    }
    func stop() { stopAudioCheck();sk_panic(synth); engine.stop() }
    func noteOn(key: Int, pitch: Int, instrument: Int, layer: Int, velocity: Float,sourceID:Int32? = nil) {
        if externalSounds[layer] != nil { externalRack?.noteOn(channel: layer, key: key, pitch: pitch, velocity: velocity,sourceID:sourceID) }
        // Synth.c remains the effect/clock core; product notes require user content.
    }
    func noteOff(key: Int, channel: Int, force: Bool = false) {
        sk_note_off_channel(synth, Int32(key), Int32(channel), force ? 1 : 0)
        externalRack?.noteOff(channel: channel, key: key, forceRelease: force)
    }
    func noteOff(_ key: Int) { sk_note_off(synth, Int32(key)); externalRack?.noteOff(key: key) }
    private var patchGain: Float = 1
    private var outputTrims:[Int:Float]=[:]
    private func scaledGain(_ index:Int,_ gain:Float)->Float { gain * (outputTrims[index] ?? 1) * (index<15 ? patchGain : 1) }
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
    func withGraphChanges(_ operation: () throws -> Void) throws {
        if let rack = externalRack { try rack.withGraphChanges(operation) }
        else { try operation() }
    }
    func configure(_ index: Int, _ layer: Layer) {
        outputTrims[index]=pow(10,(layer.channelSettings.outputTrimDB ?? 0)/20)
        pans[index] = layer.pan
        let hostCurve=layer.importedRack?.mainStageAmplitudeVelocityCurve ?? layer.external?.nativeSampler?.rack.mainStageAmplitudeVelocityCurve
        if samplerHostCurves[index] != hostCurve || externalSounds[index] != layer.external || externalStates[index] != layer.pluginState || samplerAttacks[index] != layer.samplerAttackMinimum {
            samplerAttacks[index]=layer.samplerAttackMinimum
            samplerHostCurves[index]=hostCurve
            externalStates[index] = layer.pluginState
            if let sound = layer.external {
                do { try externalRack?.remove(index) } catch { onError?(error.localizedDescription) }
                externalSounds[index] = sound
                externalRack?.load(sound, channel: index,attackMinimum:layer.samplerAttackMinimum,hostVelocityCurve:hostCurve) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success:
                        if let state = layer.pluginState { do { try self.externalRack?.restoreStateData(state, channel: index) } catch { self.onError?(error.localizedDescription) } }
                        self.externalRack?.volume(channel: index, gain: self.scaledGain(index,self.levels[index] ?? 0), pan: layer.pan)
                        self.filter(index, layer, mod: self.modulationValues[index] ?? 1)
                        self.modulation(index, value: self.modulationValues[index] ?? 1)
                        self.configureEffects(index, layer.effects, force: true)
                        self.configureImported(index,layer.importedRack ?? layer.external?.nativeSampler?.rack)
                    case .failure(let error):
                        if let e = error as? ExternalInstrumentError, case .superseded = e { return }
                        try? self.externalRack?.remove(index)
                        self.onError?(error.localizedDescription)
                    }
                }
            } else { externalSounds[index] = nil; do { try externalRack?.remove(index) } catch { onError?(error.localizedDescription) } }
        }
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
        configureEffects(index, layer.effects)
        configureImported(index,layer.importedRack ?? layer.external?.nativeSampler?.rack)
    }
    private func configureImported(_ index:Int,_ rack:ImportedRack?) {
        if let rack { importedRacks[index]=rack } else {importedRacks[index]=nil}
        do {try externalRack?.configureParallel(channel:index,branches:rack?.branches ?? externalSounds[index]?.nativeSampler?.rack.branches,tempo:tempo);try externalRack?.configureImported(channel:index,rack:rack,tempo:tempo)}
        catch {onError?(error.localizedDescription)}
        if rack?.mainStageUnityControllers==true {externalRack?.initializeMainStageControllers(channel:index)}
    }
    func audition(_ index: Int, _ layer: Layer) {
        var live = layer
        if live.external?.kind == .audioUnit { live.pluginState = externalStates[index] }
        configure(index,live)
    }
    func restoreAuditionState(_ index: Int, _ state: Data) throws {
        try externalRack?.restoreStateData(state,channel:index)
        externalStates[index] = state
    }
    /// Restore a saved Audio Unit document state in place. Snapshot recall uses
    /// this instead of `restoreStateData` so the transition is not interrupted by
    /// an engine stop and graph rebuild.
    func restorePluginState(_ index: Int, _ state: Data) {
        guard let map = try? PropertyListSerialization.propertyList(from: state, options: [], format: nil) as? [String: Any] else { return }
        externalRack?.restoreState(map, channel: index)
        externalStates[index] = state
    }
    func configureSnapshot(_ index: Int, effects: [AudioEffect], pan: Float, importedRack:ImportedRack? = nil) {
        pans[index] = pan
        sk_pan(synth, Int32(index), pan)
        externalRack?.volume(channel: index, gain: scaledGain(index,levels[index] ?? 0), pan: pan)
        configureEffects(index, effects)
        configureImported(index,importedRack)
    }
    private func configureEffects(_ index: Int, _ chain: [AudioEffect], force: Bool = false) {
        for (slot, fx) in chain.enumerated() {
            let old = effects[index].flatMap { $0.indices.contains(slot) ? $0[slot] : nil }
            guard force || old != fx else { continue }
            sk_effect(synth,Int32(index),Int32(slot),fx.enabled ? Int32(fx.kind) : 0,fx.amount)
            if fx.enabled && (fx.parameters != nil || fx.kind > 3) {
                var values = fx.renderValues
                if fx.kind == 2, let beats = fx.syncBeats { values[1] = min(20,max(0.01,tempo/(60*beats))) }
                for (p,value) in values.enumerated() { sk_effect_parameter(synth,Int32(index),Int32(slot),Int32(p),value) }
            }
            if externalSounds[index] != nil {
                do { var values=fx.renderValues;if fx.kind==2,let beats=fx.syncBeats {values[1]=min(20,max(0.01,tempo/(60*beats)))};try externalRack?.configureEffect(channel:index,slot:slot,kind:fx.kind,enabled:fx.enabled,parameters:values,tempo:tempo,delay:fx.playbackDelay) }
                catch { onError?(error.localizedDescription) }
            }
        }
        effects[index] = chain
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
        sk_metronome_settings(metronomeEngine, SKMetronomeSettings(level: settings.level, preset: Int32(settings.preset), beatVelocity: settings.beatVelocity, downbeatEnabled: settings.downbeatEnabled ? 1 : 0, downbeatVelocity: settings.downbeatVelocity, beatsPerBar: Int32(settings.beatsPerBar), accentEvery: Int32(settings.accentEvery), subdivision: Int32(settings.subdivision)))
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
