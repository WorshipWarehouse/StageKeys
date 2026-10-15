import Foundation
import AVFoundation
import CoreMIDI
import AudioToolbox
#if os(macOS)
import Darwin
#endif

final class AudioController {
    private let engine = AVAudioEngine()
    private let synth: OpaquePointer
    private let reverb = AVAudioUnitReverb()
    private let outputLimiter=AVAudioUnitEffect(audioComponentDescription:AudioComponentDescription(componentType:kAudioUnitType_Effect,componentSubType:kAudioUnitSubType_PeakLimiter,componentManufacturer:kAudioUnitManufacturer_Apple,componentFlags:0,componentFlagsMask:0))
    private let protectedOutput=AVAudioMixerNode()
    private var source: AVAudioSourceNode!
    lazy var deviceController = AudioDeviceController(engine: engine)
    lazy var externalRack: ExternalInstrumentRack? = try? ExternalInstrumentRack(engine: engine)
    private var externalSounds: [Int: ExternalSound] = [:]
    private var externalStates: [Int: Data] = [:]
    private var levels: [Int: Float] = [:]
    var onError: ((String) -> Void)?
    var offline: Bool { engine.isInManualRenderingMode }
    #if DEBUG
    func installPlaybackProbe(_ callback:@escaping (AVAudioPCMBuffer)->Void) {
        engine.mainMixerNode.installTap(onBus:0,bufferSize:512,format:nil){buffer,_ in callback(buffer)}
    }
    func removePlaybackProbe(){engine.mainMixerNode.removeTap(onBus:0)}
    #endif
    func panic(channel:Int) { sk_panic_channel(synth,Int32(channel)); externalRack?.panic(channel) }
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
        let pointer = synth
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        source = AVAudioSourceNode(format: format) { _, _, frames, list in
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            guard buffers.count >= 2, let l = buffers[0].mData, let r = buffers[1].mData else { return -1 }
            sk_render(pointer, l.assumingMemoryBound(to: Float.self), r.assumingMemoryBound(to: Float.self), frames)
            return noErr
        }
        engine.attach(source); engine.attach(reverb)
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
        // Leave 1 dB after limiting for reconstructed output peaks.
        protectedOutput.outputVolume=pow(Float(10),Float(-1)/20)
        engine.mainMixerNode.outputVolume = 0.7
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
    func stop() { sk_panic(synth); engine.stop() }
    func noteOn(key: Int, pitch: Int, instrument: Int, layer: Int, velocity: Float,sourceID:Int32? = nil) {
        if externalSounds[layer] != nil { externalRack?.noteOn(channel: layer, key: key, pitch: pitch, velocity: velocity,sourceID:sourceID) }
        else if instrument >= 0 { sk_note_on(synth, Int32(key), Int32(pitch), Int32(instrument), Int32(layer), velocity) }
    }
    func noteOff(key: Int, channel: Int, force: Bool = false) {
        sk_note_off_channel(synth, Int32(key), Int32(channel), force ? 1 : 0)
        externalRack?.noteOff(channel: channel, key: key, forceRelease: force)
    }
    func noteOff(_ key: Int) { sk_note_off(synth, Int32(key)); externalRack?.noteOff(key: key) }
    private var patchGain: Float = 1
    private func scaledGain(_ index:Int,_ gain:Float)->Float { gain * (index<15 ? patchGain : 1) }
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
        let cutoff = exp(log(c.filterMin) + (log(c.filterMax) - log(c.filterMin)) * mod)
        sk_filter(synth, Int32(index), cutoff, c.resonance)
        externalRack?.processing(channel: index, gain: c.samplerGain, cutoff: cutoff, resonance: c.resonance,
            eqEnabled: c.eqEnabled, bands: c.equalizer.map { ($0.frequency, $0.gain, $0.q) },
            compressorEnabled: c.compressorEnabled, threshold: c.threshold, attack: c.compressorAttack, release: c.compressorRelease, makeup: c.makeup,ratio:c.ratio,inputGain:c.compressorInputGain ?? 0,mix:c.compressorMix ?? 1)
    }
    func configure(_ index: Int, _ layer: Layer) {
        pans[index] = layer.pan
        if externalSounds[index] != layer.external || externalStates[index] != layer.pluginState {
            externalStates[index] = layer.pluginState
            if let sound = layer.external {
                do { try externalRack?.remove(index) } catch { onError?(error.localizedDescription) }
                externalSounds[index] = sound
                externalRack?.load(sound, channel: index) { [weak self] result in
                    guard let self else { return }
                    switch result {
                    case .success:
                        if let state = layer.pluginState { do { try self.externalRack?.restoreStateData(state, channel: index) } catch { self.onError?(error.localizedDescription) } }
                        self.externalRack?.volume(channel: index, gain: self.scaledGain(index,self.levels[index] ?? 0), pan: layer.pan)
                        self.filter(index, layer, mod: self.modulationValues[index] ?? 1)
                        self.modulation(index, value: self.modulationValues[index] ?? 1)
                        self.configureEffects(index, layer.effects, force: true)
                        self.configureImported(index,layer.importedRack)
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
        configureImported(index,layer.importedRack)
    }
    private func configureImported(_ index:Int,_ rack:ImportedRack?) {
        if let rack { importedRacks[index]=rack } else {importedRacks[index]=nil}
        do {try externalRack?.configureParallel(channel:index,branches:rack?.branches,tempo:tempo);try externalRack?.configureImported(channel:index,rack:rack,tempo:tempo)}
        catch {onError?(error.localizedDescription)}
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
                var values = fx.values
                if fx.kind == 2, let beats = fx.syncBeats { values[1] = min(20,max(0.01,tempo/(60*beats))) }
                for (p,value) in values.enumerated() { sk_effect_parameter(synth,Int32(index),Int32(slot),Int32(p),value) }
            }
            if externalSounds[index] != nil {
                do { var values=fx.values;if fx.kind==2,let beats=fx.syncBeats {values[1]=min(20,max(0.01,tempo/(60*beats)))};try externalRack?.configureEffect(channel:index,slot:slot,kind:fx.kind,enabled:fx.enabled,parameters:values,tempo:tempo) }
                catch { onError?(error.localizedDescription) }
            }
        }
        effects[index] = chain
    }
    func effect(_ index: Int, _ slot: Int, _ kind: Int, _ amount: Float) { sk_effect(synth, Int32(index), Int32(slot), Int32(kind), amount) }
    func clock(_ tempo: Double, _ enabled: Bool) {
        let changed = self.tempo != Float(tempo); self.tempo = Float(tempo)
        sk_clock(synth,Float(tempo),enabled ? 1 : 0)
        if changed { for (index,chain) in effects { configureEffects(index,chain,force:true) }; for (index,rack) in importedRacks {configureImported(index,rack)} }
    }
    func releaseSource(_ source:Int32){externalRack?.releaseSource(source)}
    func sustain(_ on: Bool, layers: [Layer]) { sk_sustain(synth, on ? 1 : 0); for (i,l) in layers.enumerated() { externalRack?.sustain(channel: i, on: on && !l.blockSustain) } }
    func panic() { sk_panic(synth); externalRack?.panic() }
    func master(_ volume: Float) { engine.mainMixerNode.outputVolume = volume }
    func space(_ amount: Float) { reverb.wetDryMix = amount }
    #if DEBUG
    // Runs the actual production graph without sending sound to the device.
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
    #endif
    deinit { engine.stop(); sk_destroy(synth) }
}
