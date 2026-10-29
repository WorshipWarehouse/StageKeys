import SwiftUI
import UniformTypeIdentifiers
import AVFoundation
import CryptoKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class PerformanceStore: ObservableObject {
    @Published var setlist = Setlist()
    @Published var selected = 0
    @Published private(set) var effectPresets:[EffectPreset]=[]
    @Published var started = false
    @Published var audioOutputs: [AudioOutputDevice] = []
    @Published var audioStatus: AudioDeviceStatus?
    @Published var message: String?
    @Published private(set) var audioCheckRecording=false
    @Published var masterLimiterBypassed=false {didSet{audio.bypassMasterLimiter(masterLimiterBypassed)}}
    func startAudioCheck() {
        do {
            let folder=saveURL.deletingLastPathComponent().appendingPathComponent("Audio Checks",isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            let url=folder.appendingPathComponent("StageKeys-"+UUID().uuidString+".wav")
            try audio.startAudioCheck(at:url) { [weak self] result in
                self?.audioCheckRecording=false
                switch result {
                case .success(let summary):self?.message=String(format:"Audio check saved (%.1f seconds):\n%@",Double(summary.frames)/summary.sampleRate,summary.url.path)
                case .failure(let error):self?.message="Audio check failed: "+error.localizedDescription
                }
            }
            audioCheckRecording=true
        }catch{message=error.localizedDescription}
    }
    func stopAudioCheck(){audio.stopAudioCheck()}
    func copySupportDiagnostics() {
        do {
            let report = SupportDiagnostics(version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
                build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development",
                running: audio.running, status: audioStatus, latency: try? audio.latencyChain(),
                midiSources: midiSources.filter(\.connected).count, loadedSlots: patch.layers.filter(\.loaded).count,
                limiterBypassed: masterLimiterBypassed, recording: audioCheckRecording)
            let text = try report.json()
            #if os(macOS)
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
            #else
            UIPasteboard.general.string = text
            #endif
            message = "Diagnostics copied locally. Review before sharing. No device names, file paths, samples, setlists or plug-in state are included. Underruns and physical keyboard latency are not measured."
        } catch { message = "Could not create diagnostics: \(error.localizedDescription)" }
    }
    @Published var deviceCount = 0
    @Published var midiSources: [MIDIInputSource] = []
    @Published var midiDevices: [MIDIKnownDevice] = []
    @Published var midiStatus = "Looking for MIDI keyboards…"
    private struct HardwareNote: Hashable { var source: Int32; var channel: Int; var note: Int }
    private struct PedalSource: Hashable { var source: Int32; var channel: Int }
    private var hardwareNotes: [HardwareNote: Int] = [:]
    private var nextHardwareKey = 1024
    private var pedalSources: Set<PedalSource> = []
    private struct CCKey: Hashable { var source:Int32; var channel:Int; var cc:Int }
    private var mappedPedals: Set<CCKey> = []
    private var pressedCCs: [CCKey:Bool] = [:]
    private var screenSustain = false
    @Published var held: Set<Int> = []
    @Published var sustain = false
    @Published var tonic: Int?
    @Published var tonicLastRoot=0
    @Published var tonicTimbre=0 {didSet{if oldValue != tonicTimbre {restartTonic()}}}
    @Published var tonicSound:ExternalSound? {didSet{if oldValue != tonicSound {restartTonic()}}}
    @Published var tonicVelocitySelector=false
    private var tonicLoadGeneration=UUID()
    var tonicLocked:Bool {patch.tonicState != nil}
    func toggleTonicPatchLock() {
        if tonicLocked {setlist.patches[selected].tonicState=nil}
        else {setlist.patches[selected].tonicState=TonicPatchState(enabled:tonic != nil,root:tonicLastRoot,timbre:tonicTimbre,sound:tonicSound,velocitySelector:tonicVelocitySelector,gain:tonicGain,brightness:tonicBrightness,shimmer:tonicShimmer)}
        save()
    }
    private func recallTonicPatch() {
        guard let state=patch.tonicState,state.valid else{return}
        tonicVelocitySelector=state.velocitySelector;tonicTimbre=state.timbre;tonicSound=state.sound
        tonicGain=state.gain;tonicBrightness=state.brightness;tonicShimmer=state.shimmer
        tonicLastRoot=state.root
        if state.enabled && tonicSound != nil {if let previous=tonic,previous != state.root {stopTonicNotes(previous)};if tonic != state.root {tonic=state.root;playTonicNotes(state.root)}}
        else if let previous=tonic {stopTonicNotes(previous);tonic=nil}
    }
    var tonicNames:[String] {tonicVelocitySelector ? ["Warm","Bright","Dark","Choir","Organ","Guitar","Strings","Pure","Evolving","Rev Piano","Simple","Classic"]:[tonicSound?.name ?? "Choose Sound"]}
    var tonicLabel:String {tonicSound == nil ? "Choose Sound":"\(tonicTimbre+1). \(tonicNames[min(max(0,tonicTimbre),tonicNames.count-1)])"}

    @Published var tonicGain: Float = 0.32 { didSet { audio.gain(15, tonicGain) } }
    @Published var master: Float = 0.7 { didSet { audio.master(master) } }
    @Published var reverb: Float = 22 { didSet { audio.space(reverb) } }
    @Published var transition: Float = 1.5
    @Published var activeSnapshot: UUID?
    @Published var learning: Int?
    @Published var learningTarget: MIDIControlTarget?
    @Published var midiActivity = false
    @Published var notesMode = false
    @Published var patchLock = false
    @Published var editRanges = false
    @Published var showRanges = true
    @Published var keyboardBase = 48
    @Published var metronome = false { didSet { audio.clock(patch.tempo, metronome) } }
    @Published var midiChannel = -1 { didSet { if oldValue != midiChannel { panic() } } }
    @Published var primarySourceID: Int32 = -1 { didSet { if oldValue != primarySourceID { panic() } } }
    @Published var secondarySourceID: Int32 = -2 { didSet { if oldValue != secondarySourceID { panic() } } }
    @Published var secondaryChannel = -1 { didSet { if oldValue != secondaryChannel { panic() } } }
    @Published var velocityMinimum = 0
    @Published var velocityMaximum = 127
    @Published var midiSourceNames: [Int32:String] = [:]
    @Published var midiLog: [String] = []
    /// Current MIDI outputs, refreshed when Core MIDI reports a setup change.
    @Published var midiDestinations: [ExternalMIDIDestination] = []
    @Published var disableSilent = false
    @Published var tonicBrightness: Float = 0.7 { didSet { configureTonic() } }
    @Published var tonicShimmer: Float = 0 { didSet { updateShimmer() } }
    @Published var modWheel: Float = 1 { didSet { updateToneFilters() } }
    private func updateToneFilters() {
        for i in patch.layers.indices {
            let l = playbackLayer(i); guard l.loaded else { continue }
            audio.filter(i, l, mod: modWheel)
            audio.modulation(i, value: modWheel)
            if let destination = l.midiDestinationID { sendMIDI(destination, 0xb0 | UInt8(l.midiOutputChannel), 1, UInt8((max(0, min(1, modWheel)) * 127).rounded())) }
            for (slot, fx) in l.effects.enumerated() where fx.kind == 1 && fx.enabled && fx.parameters == nil { audio.effect(i, slot, 1, fx.amount * (0.2 + 0.8 * modWheel)) }
        }
    }
    private func updateShimmer() {configureTonic()}
    private func configureTonic() {
        var layer=Layer(name:"Tonic Pad",instrument:-1,gain:tonicGain)
        layer.external=tonicSound
        var tone=AudioEffect();tone.kind=1;tone.parameters=[200*pow(100,max(0,min(1,tonicBrightness))),0.707,1]
        var shimmer=AudioEffect();shimmer.kind=10
        var values=AudioEffectCatalog.defaults(for:10);values[0]=1;values[7]=1;values[8]=max(0,min(1,tonicShimmer))*0.5;shimmer.parameters=values;shimmer.enabled=tonicShimmer>0
        layer.effects=[tone,shimmer,AudioEffect()]
        audio.configure(15,layer);audio.gain(15,tonicGain)
    }
    private func stopTonicNotes(_ root:Int) {
        audio.noteOff(key:9000+root,channel:15)
        for interval in [0,7,12] {audio.noteOff(key:9100+root+interval,channel:15)}
    }
    private func playTonicNotes(_ root:Int) {
        configureTonic()
        if tonicSound != nil {audio.noteOn(key:9000+root,pitch:36+root,instrument:-1,layer:15,velocity:tonicVelocitySelector ? Float(tonicTimbre+1)/127:0.65)}

    }
    private func restartTonic() {
        guard started else{return}
        let root=tonic
        audio.panic(channel:15);configureTonic()
        if let root {playTonicNotes(root)}
    }
    func selectTonicRoot(_ root:Int) {
        guard (0..<12).contains(root),started else{return}
        tonicLastRoot=root
        guard tonic != nil,tonic != root else{return}
        if let previous=tonic {stopTonicNotes(previous)}
        tonic=root;playTonicNotes(root)
    }
    /// Validate a library preset before selection without copying its assets.
    /// Only the already-supported looped-note map and twelve-timbre selector are
    /// safe on the Tonic Pad; Audio Units are intentionally excluded.
    private func tonicEligibility(_ sound:ExternalSound)throws->Bool {
        guard sound.kind == .samplerPreset,let root=audio.externalRack?.libraryURL else {throw ExternalInstrumentError.unsupportedFormat}
        let map=try StageKeysSampler.map(sound,library:root)
        guard let velocitySelector=StageKeysSampler.tonicVelocitySelector(map) else {
            throw MainStagePatch.Failure.invalid("This pad has an unsupported key/velocity selector. Choose a looped instrument covering MIDI 36–47 at normal velocity, or the supported twelve-timbre sampler.")
        }
        return velocitySelector
    }
    private func loadTonicSound(_ sound:ExternalSound, completion:@escaping(Result<Void,Error>)->Void) {
        guard let rack=audio.externalRack else {completion(.failure(ExternalInstrumentError.missingFile));return}
        let channel=15,previous=tonicSound,wasEnabled=tonic != nil,oldRoot=tonic,previousVelocitySelector=tonicVelocitySelector,previousTimbre=tonicTimbre
        let generation=UUID();tonicLoadGeneration=generation
        do {
            let velocitySelector=try tonicEligibility(sound)
            rack.load(sound,channel:channel){ [weak self] result in
                guard let self,self.tonicLoadGeneration==generation else{return}
                switch result {
                case .success:
                    self.audio.adoptExternalSound(sound,channel:channel)
                    self.tonicVelocitySelector=velocitySelector;self.tonicTimbre=0;self.tonicSound=sound
                    if wasEnabled,let oldRoot {self.tonic=oldRoot;self.playTonicNotes(oldRoot)}
                    self.save();completion(.success(()))
                case .failure(let error):
                    if let previous {
                        rack.load(previous,channel:channel){ [weak self] restore in
                            guard let self,self.tonicLoadGeneration==generation else{return}
                            switch restore {
                            case .success:
                                self.audio.adoptExternalSound(previous,channel:channel)
                                self.tonicVelocitySelector=previousVelocitySelector;self.tonicTimbre=previousTimbre
                                if wasEnabled,let oldRoot {self.tonic=oldRoot;self.playTonicNotes(oldRoot)}
                                self.message=error.localizedDescription
                            case .failure(let restoreError):
                                self.audio.adoptExternalSound(nil,channel:channel)
                                self.tonicVelocitySelector=previousVelocitySelector;self.tonicTimbre=previousTimbre
                                self.tonicSound=nil;self.tonic=nil
                                self.message="Could not restore the previous Tonic Pad sound: "+restoreError.localizedDescription
                            }
                            completion(.failure(error))
                        }
                    } else {self.audio.adoptExternalSound(nil,channel:channel);self.tonicSound=nil;self.tonic=nil;self.tonicVelocitySelector=false;self.tonicTimbre=0;self.message=error.localizedDescription;completion(.failure(error))}
                }
            }
        }catch {message=error.localizedDescription;completion(.failure(error))}
    }
    func setTonicInstrument(_ sound:ExternalSound) {
        loadTonicSound(sound){_ in}
    }
    func tonicSoundEligibility(_ sound:ExternalSound)->String? {
        do {_ = try tonicEligibility(sound);return nil}
        catch {return error.localizedDescription}
    }
    func importTonicInstrument(_ url:URL,samples:URL) {
        guard ["exs","aupreset"].contains(url.pathExtension.lowercased()) else{message="Choose a sampler instrument (.aupreset or .exs).";return}
        guard let sound=importLibrarySound(url,sampleRoot:samples) else{return}
        guard let eligibility=tonicSoundEligibility(sound) else { setTonicInstrument(sound);return }
        message=eligibility
    }
    func clearTonicSound(){if let root=tonic{stopTonicNotes(root)};tonic=nil;audio.panic(channel:15);tonicVelocitySelector=false;tonicTimbre=0;tonicSound=nil;save()}
    let midiFX = MIDIFXProcessor()
    private var midiOutput: ExternalMIDIOutput?
    private var outputNotes: [Int: [Int: Int]] = [:]
    private var lastTaps: [Date] = []
    private struct Audition {
        let token: UUID
        let patchID: UUID
        let layerID: UUID
        let index: Int
        /// Updated when the instrument interface closes so its edits survive the
        /// audition teardown instead of reverting to the state captured on open.
        var pluginState: Data?
        var draft: Layer
        var isolatedLibrary = false
    }
    private var audition: Audition?
    func saveEffectPreset(_ effect:AudioEffect,name:String) {
        var saved=effect
        if effect.usesCreamCoat {saved.reverbCore="creamcoat"}
        let preset=EffectPreset(name:name.trimmingCharacters(in:.whitespacesAndNewlines),effect:saved)
        guard preset.validate(),effectPresets.count<128 else{message="Enter a preset name of 1–80 characters. Up to 128 presets can be saved.";return}
        let updated=effectPresets+[preset]
        do {try EffectPresetArchive.save(updated,to:saveURL.deletingLastPathComponent().appendingPathComponent("effect-presets.json"));effectPresets=updated}
        catch {message="Could not save effect preset: \(error.localizedDescription)"}
    }
    func playbackLayer(_ index: Int) -> Layer {
        if let audition, audition.patchID == patch.id, audition.index == index, patch.layers[index].id == audition.layerID { return audition.draft }
        return patch.layers[index]
    }
    @discardableResult
    func beginAudition(_ index: Int) -> UUID? {
        cancelAudition()
        guard patch.layers.indices.contains(index) else { return nil }
        cancelTransition()
        let layer = patch.layers[index], token = UUID()
        let state = layer.external?.kind == .audioUnit ? (try? audio.externalRack?.stateData(channel:index)) : nil
        audition = Audition(token:token,patchID:patch.id,layerID:layer.id,index:index,pluginState:state ?? nil,draft:layer)
        return token
    }
    func previewLayer(_ index: Int, _ proposed: Layer, token: UUID) {
        guard let session = audition, session.token == token, session.patchID == patch.id, session.index == index,
              patch.layers.indices.contains(index), patch.layers[index].id == session.layerID else { return }
        var layer = proposed; layer.gain = session.isolatedLibrary ? 0.6:patch.layers[index].gain; layer.muted = session.isolatedLibrary ? false:patch.layers[index].muted
        var validation = Setlist(); validation.patches = [Patch(name:"Audition",layers:[layer],snapshots:[])]
        guard (try? validation.validate()) != nil else { return }
        let previous = session.draft
        if previous.effectiveTranspose != layer.effectiveTranspose || previous.low != layer.low || previous.high != layer.high || previous.midiOutputChannel != layer.midiOutputChannel {
            midiFX.panic(channel:index); audio.panic(channel:index)
        }
        audition?.draft = layer
        configureMIDI(index,layer); audio.audition(index,layer)
        audio.gain(index,layer.loaded && !layer.muted ? layer.gain : 0)
        updateToneFilters(); applySustain()
    }
    func endAudition(_ token: UUID?) {
        guard let session = audition, token == session.token else { return }
        guard session.patchID == patch.id, patch.layers.indices.contains(session.index), patch.layers[session.index].id == session.layerID else { audition=nil; return }
        midiFX.panic(channel:session.index); audio.panic(channel:session.index)
        audition=nil
        if let state=session.pluginState {
            do { try audio.restoreAuditionState(session.index,state); setlist.patches[selected].layers[session.index].pluginState=state }
            catch { message=error.localizedDescription }
        }
        let original=patch.layers[session.index]
        configureMIDI(session.index,original); audio.configure(session.index,original)
        audio.gain(session.index,original.loaded && !original.muted ? original.gain : 0)
        if session.isolatedLibrary {for (i,layer) in patch.layers.enumerated() where i != session.index {audio.gain(i,layer.loaded && !layer.muted ? layer.gain:0)};audio.gain(15,tonicGain)}
        updateToneFilters(); applySustain()
    }
    @discardableResult func auditionLibrarySound(_ index:Int,_ layer:Layer)->UUID? {
        guard let token=beginAudition(index) else{return nil}
        panic();audition?.isolatedLibrary=true
        for i in patch.layers.indices where i != index {audio.gain(i,0)}
        audio.gain(15,0);previewLayer(index,layer,token:token)
        return token
    }
    func cancelAudition() { endAudition(audition?.token) }
    func confirmAudition(_ token: UUID?, index: Int, layer: Layer) {
        guard let session=audition, session.token == token, session.patchID == patch.id, session.index == index, patch.layers.indices.contains(index), patch.layers[index].id == session.layerID else { return }
        var final=layer; final.gain=patch.layers[index].gain; final.muted=patch.layers[index].muted
        if layer.external?.kind == .audioUnit { do { final.pluginState=try audio.externalRack?.stateData(channel:index) } catch { message=error.localizedDescription; return } }
        endAudition(token); commitLayer(index,final)
    }
    private var snapshotTimer: Timer?
    private var notifications: [NSObjectProtocol] = []
    let audio = AudioController()
    let midi = MIDIInput()
    @Published var librarySounds: [LibrarySound] = []
    @Published var gainMatchTargetDB:Double = -24
    @Published var gainMatchReferenceName:String?
    @Published private(set) var soundRatings:[String:Int]=[:]
    @Published var libraryRangePreview: Layer?
    private var libraryRangePreviewIndex: Int?
    var displayedLayers:[Layer] {
        var layers=patch.layers
        if let index=libraryRangePreviewIndex,layers.indices.contains(index),var preview=libraryRangePreview {preview.id=layers[index].id;layers[index]=preview}
        return layers
    }
    func rateSound(_ id:String,_ value:Int) {
        guard let updated=SoundRatingArchive.setting(value,for:id,in:soundRatings) else{return}
        do {try SoundRatingArchive.save(updated,to:saveURL.deletingLastPathComponent().appendingPathComponent("sound-ratings.json"));soundRatings=updated}
        catch {message="Could not save sound rating: \(error.localizedDescription)"}
    }
    func setSoundRecommended(_ id:String,_ value:Bool) {
        guard let index=librarySounds.firstIndex(where:{$0.id==id}) else{return}
        var updated=librarySounds;var tags=updated[index].tags ?? BrowserSound.library(updated[index]).tags
        tags.recommended=value;updated[index].tags=tags
        do {try SoundLibrary(url:saveURL.deletingLastPathComponent().appendingPathComponent("sound-library.json")).write(updated);librarySounds=updated}
        catch {message="Could not save recommendation: \(error.localizedDescription)"}
    }
    func setSoundComplexity(_ id:String,_ value:String?) {
        guard value.map({["Simple","Moderate","Complex"].contains($0)}) ?? true,let index=librarySounds.firstIndex(where:{$0.id==id}) else{return}
        var updated=librarySounds;var tags=updated[index].tags ?? BrowserSound.library(updated[index]).tags
        tags.complexity=value;updated[index].tags=tags
        do {try SoundLibrary(url:saveURL.deletingLastPathComponent().appendingPathComponent("sound-library.json")).write(updated);librarySounds=updated}
        catch {message="Could not save sound tags: \(error.localizedDescription)"}
    }
    func setSoundNoteRanges(_ id:String,_ values:[String]) {
        guard values.count<=4,Set(values).count==values.count,values.allSatisfy({LibraryNoteRange(rawValue:$0) != nil}),let index=librarySounds.firstIndex(where:{$0.id==id}) else{return}
        var updated=librarySounds;var tags=updated[index].tags ?? BrowserSound.library(updated[index]).tags
        tags.noteRanges=LibraryNoteRange.allCases.map(\.rawValue).filter{values.contains($0)}
        updated[index].tags=tags
        do {try SoundLibrary(url:saveURL.deletingLastPathComponent().appendingPathComponent("sound-library.json")).write(updated);librarySounds=updated}
        catch {message="Could not save Note Range tags: \(error.localizedDescription)"}
    }
    func previewLibraryRange(_ index:Int,_ layer:Layer?) {libraryRangePreviewIndex=layer == nil ? nil:index;libraryRangePreview=layer}
    @Published var mainStageImportReport:MainStagePatch.Report?
    @Published var mainStageChannelSelection:Set<Int>?
    var selectedMainStageChannels:Set<Int> {
        guard let report=mainStageImportReport else{return []}
        return (mainStageChannelSelection ?? Set(report.channels.indices)).filter{report.channels.indices.contains($0) && report.channels[$0].isConvertible}
    }
    func selectMainStageChannel(_ index:Int,_ enabled:Bool) {
        var selection=selectedMainStageChannels
        if enabled {selection.insert(index)} else {selection.remove(index)}
        mainStageChannelSelection=selection
    }
    func convertIncludedMainStageSounds() {
        guard let id=mainStageImportReport?.sourceArchiveID,UUID(uuidString:id) != nil else{return}
        importMainStageSamplers(saveURL.deletingLastPathComponent().appendingPathComponent("MainStage Sources/"+id+"/Source.patch",isDirectory:true))
    }
    @Published var libraryImportBusy=false
    private var libraryImportCancelRequested=false
    func cancelLibraryImport(){libraryImportCancelRequested=true}
    private func checkLibraryImportCancellation()throws {
        if libraryImportCancelRequested {throw MainStagePatch.Failure.invalid("Import cancelled. No prepared catalog entries were committed.")}
    }
    @Published var libraryImportProgress:String?
    @Published var savedSetlists: [SetlistLibraryDescriptor] = []
    @Published var setlistLibraryIssues: [SetlistLibraryIssue] = []
    @Published var archivedSetlists: [SetlistTrashEntry] = []
    @Published var currentSetlistID: UUID?
    private let saveURL: URL
    private var preferredAudioOutputUID: String?
    private var preferredBufferFrames: UInt32?
    private var restoredAudioOutput = false
    private var restoredAudioBuffer = false
    private var legacyVersion = 1
    private var legacyData: Data?
    @Published private(set) var sessionRecoveryRequired = false
    @Published private(set) var settingsRecoveryRequired = false
    @Published private(set) var libraryRecoveryRequired = false
    @Published private(set) var ratingsRecoveryRequired = false
    @Published private(set) var presetsRecoveryRequired = false
    var patch: Patch { setlist.patches[selected] }
    var hasUnavailableLegacyVoices:Bool {patch.layers.contains{$0.instrument>=0 && $0.external==nil && $0.midiDestinationID==nil}}
    init() {
        let base = ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"].map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("StageKeys")
        saveURL = base.appendingPathComponent("setlist.json")
        do {soundRatings=try SoundRatingArchive.read(base.appendingPathComponent("sound-ratings.json"))}
        catch {ratingsRecoveryRequired=true;message="Saved ratings could not be read. Writes are blocked; recover the previous ratings in Settings."}
        do {effectPresets=try EffectPresetArchive.read(base.appendingPathComponent("effect-presets.json"))}
        catch {presetsRecoveryRequired=true;message="Personal effect presets could not be read. Writes are blocked; recover the previous presets in Settings."}
        if let data=try? Data(contentsOf:base.appendingPathComponent("mainstage-import-report.json")),data.count<=2_000_000 {
            mainStageImportReport=try? JSONDecoder().decode(MainStagePatch.Report.self,from:data)
        }
        do { librarySounds = try SoundLibrary(url: base.appendingPathComponent("sound-library.json")).read() }
        catch { libraryRecoveryRequired=true;message = "Could not read sound library: \(error.localizedDescription). Catalog writes are blocked to preserve it. Open Settings to recover the previous catalog." }
        if FileManager.default.fileExists(atPath: saveURL.path) {
            do { let data = try RecoverableSessionFile.read(saveURL); let loaded = try JSONDecoder().decode(Setlist.self, from: data); setlist = try loaded.upgraded(); if loaded.version < 4 { legacyData = data; legacyVersion = loaded.version } }
            catch { sessionRecoveryRequired = true; message = "Could not load the saved setlist: \(error.localizedDescription). Automatic saves are blocked to preserve it. Open Settings to recover the previous session." }
        }
        let settingsURL = base.appendingPathComponent("settings.json")
        if let data = try? RecoverableSessionFile.read(settingsURL), let settings = try? JSONDecoder().decode(SessionSettings.self, from: data), settings.validate() {
            if let id=settings.selectedPatchID,let i=setlist.patches.firstIndex(where:{$0.id==id}) { selected=i }
            activeSnapshot=patch.snapshots.contains(where:{$0.id==settings.activeSnapshotID}) ? settings.activeSnapshotID : nil
            notesMode=settings.notesMode ?? false;modWheel=settings.modWheel ?? 1
            preferredAudioOutputUID = settings.audioOutputUID
            currentSetlistID = settings.activeSetlistID
            master = settings.master; reverb = settings.reverb; transition = settings.transition
            midiChannel = settings.midiChannel
            primarySourceID = settings.primarySourceID ?? -1; secondarySourceID = settings.secondarySourceID ?? -2
            secondaryChannel = settings.secondaryChannel ?? -1
            velocityMinimum = settings.velocityMinimum ?? 0; velocityMaximum = settings.velocityMaximum ?? 127
            midiSourceNames = settings.sourceNames ?? [:]
            metronome = settings.metronomeEnabled ?? false
            preferredBufferFrames = settings.audioBufferFrames.map { UInt32(max(0, min(8192, $0))) }
            disableSilent = settings.disableSilent; showRanges = settings.showRanges
            tonicVelocitySelector=settings.tonicVelocitySelector ?? false;tonicTimbre=settings.tonicTimbre ?? 0;tonicLastRoot=settings.tonicLastRoot ?? 0;tonicSound=settings.tonicSound
            tonicGain = settings.tonicGain; tonicBrightness = settings.tonicBrightness; tonicShimmer = settings.tonicShimmer
        }
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            do {
                let data = try RecoverableSessionFile.read(settingsURL)
                guard try JSONDecoder().decode(SessionSettings.self, from: data).validate() else { throw SetlistError.invalid }
            } catch {
                settingsRecoveryRequired = true
                message = "Saved settings could not be loaded. Automatic saves are blocked; use Settings to recover the previous copy."
            }
        }
        audio.onError = { [weak self] in self?.message = $0 }
        do { midiOutput = try ExternalMIDIOutput() } catch { message = error.localizedDescription }
        midiOutput?.onChange = { [weak self] in self?.refreshMIDIDestinations() }
        midiDestinations = midiOutput?.destinations ?? []
        // Exclude this app's virtual output before the input port starts, so a
        // renamed or looped port cannot feed StageKeys' output back into itself.
        if let own = midiOutput?.ownSourceID, own != 0 { midi.ignoreSources([own]) }
        midiFX.onNoteWithSource = { [weak self] channel, key, pitch, velocity, sourceID in
            guard let self, self.patch.layers.indices.contains(channel) else { return }
            if let audition=self.audition,audition.isolatedLibrary,audition.index != channel{return}
            let l = self.playbackLayer(channel)
            let pitch = pitch + self.patch.transpose
            if let destination = l.midiDestinationID, (0...127).contains(pitch) {
                self.outputNotes[channel, default: [:]][key] = pitch
                self.sendMIDI(destination, 0x90 | UInt8(l.midiOutputChannel), UInt8(pitch), UInt8(max(1,min(127,Int(velocity * 127)))))
            } else { self.audio.noteOn(key: key, pitch: pitch, instrument: l.instrument, layer: channel, velocity: velocity,sourceID:sourceID) }
        }
        midiFX.onOff = { [weak self] channel, key, force in
            guard let self, self.patch.layers.indices.contains(channel) else { return }
            let l = self.playbackLayer(channel)
            if let destination = l.midiDestinationID, let pitch = self.outputNotes[channel]?.removeValue(forKey: key) {
                if force { self.sendMIDI(destination, 0xb0 | UInt8(l.midiOutputChannel), 64, 0) }
                self.sendMIDI(destination, 0x80 | UInt8(l.midiOutputChannel), UInt8(pitch), 0)
            } else { self.audio.noteOff(key: key, channel: channel, force: force) }
        }
        midi.onSourceEvent = { [weak self] source, status, a, b in self?.handleMIDI(status, a, b, source: source) }
        midi.onInventory = { [weak self] sources, devices in
            guard let self else { return }
            self.midiSources = sources; self.midiDevices = devices
            for source in sources { self.midiSourceNames[source.id] = source.name }
            let connected = sources.filter(\.connected)
            self.midiStatus = connected.isEmpty ? "Plug in a USB MIDI keyboard to connect automatically" : connected.map(\.name).joined(separator: " · ")
        }
        midi.onDisconnect = { [weak self] in self?.disconnectMIDI($0) }
        midi.onDevices = { [weak self] count, error in
            self?.deviceCount = count
            if let error { self?.midiStatus = error }
        }
        midi.start()
        #if os(macOS)
        for event in [NSApplication.willTerminateNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in self?.cancelAudition(); self?.panic(); self?.save() })
        }
        notifications.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.refreshMIDI() })
        notifications.append(NotificationCenter.default.addObserver(forName: NSApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.releaseScreenNotes(); self?.save() })
        #endif
        #if os(iOS)
        notifications.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] _ in
            self?.audio.stop(); self?.started = false; self?.panic()
        })
        #endif
        notifications.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.started && !self.audio.running {
                self.panic(); self.started = false
                self.start()
            }
        })
    }
    func start() {
        guard !started else { return }
        do {
            if !restoredAudioOutput, !audio.offline {
                restoredAudioOutput = true
                if let uid = preferredAudioOutputUID { try? audio.deviceController.select(uid: uid) }
            }
            try audio.start(); audio.master(master);audio.space(reverb); started = true; applyPatch(); recallTonicPatch(); audio.clock(patch.tempo,metronome); refreshAudioDevices(); restoreAudioBuffer() }
        catch { started = false; message = "Audio could not start: \(error.localizedDescription)" }
    }
    /// Re-apply the saved hardware buffer once the engine is running. A device that
    /// no longer supports the saved size keeps its current buffer instead of failing.
    private func restoreAudioBuffer() {
        guard !restoredAudioBuffer, let frames = preferredBufferFrames, frames > 0,
              audioStatus?.canSetBuffer == true, audioStatus?.bufferFrames != frames else { return }
        restoredAudioBuffer = true
        do { try audio.deviceController.buffer(frameCount: frames) }
        catch { preferredBufferFrames = nil }
        refreshAudioDevices()
    }
    func refreshAudioDevices() {
        guard !audio.offline else { return }
        do { audioOutputs=try AudioDeviceController.availableOutputs(); audioStatus=try audio.deviceController.status() }
        catch { message=error.localizedDescription }
    }
    func selectAudioOutput(_ id: UInt32) {
        panic()
        do { try audio.deviceController.select(deviceID:id); preferredAudioOutputUID = try audio.deviceController.outputUID(); restoredAudioOutput = true; refreshAudioDevices(); save() }
        catch { message=error.localizedDescription; refreshAudioDevices() }
    }
    func setAudioBuffer(_ frames: UInt32) {
        panic()
        do { try audio.deviceController.buffer(frameCount:frames); preferredBufferFrames=frames; refreshAudioDevices(); save() }
        catch { message=error.localizedDescription; refreshAudioDevices() }
    }
    func refreshMIDIDestinations() { midiDestinations = midiOutput?.refresh() ?? [] }
    /// Short middle C, for verifying a hardware or virtual output by listening or
    /// watching the receiving app's monitor.
    func testMIDIDestination(_ id: Int32) {
        sendMIDI(id, 0x90, 60, 100)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.sendMIDI(id, 0x80, 60, 0) }
    }
    func noteOn(_ note: Int, velocity: Float = 0.8, hardware: Bool = false) {
        guard started else { return }
        let key = note + (hardware ? 128 : 0)
        guard !held.contains(key) else { return }
        held.insert(key)
        for index in patch.layers.indices {
            let layer=playbackLayer(index)
            guard layer.loaded && (layer.low...layer.high).contains(note) && (!disableSilent || (!layer.muted && layer.gain > 0)) else { continue }
            let pitch = note + layer.effectiveTranspose
            midiFX.noteOn(channel: index, key: key, pitch: pitch, velocity: velocity)
        }
    }
    func noteOff(_ note: Int, hardware: Bool = false) { let key = note + (hardware ? 128 : 0); held.remove(key); for i in patch.layers.indices { midiFX.noteOff(channel: i, key: key) } }
    func isNoteHeld(_ note: Int) -> Bool { held.contains(note) || hardwareNotes.keys.contains { $0.note == note } }
    func refreshMIDI() { midi.start(); if !started { start() } }
    func automaticMIDI() { primarySourceID = -1; midiChannel = -1; secondarySourceID = -2; velocityMinimum = 0; velocityMaximum = 127; refreshMIDI(); save() }
    #if os(macOS)
    func openAudioMIDISetup() { NSWorkspace.shared.open(URL(fileURLWithPath:"/System/Applications/Utilities/Audio MIDI Setup.app")) }
    #endif
    func releaseScreenNotes() { for key in held.filter({ (0...127).contains($0) }) { noteOff(key) }; screenSustain = false; applySustain() }
    private func hardwareOn(source: Int32, channel: Int, note: Int, velocity: Float) {
        if !started { start(); if !started { return } }
        let input = HardwareNote(source: source, channel: channel, note: note)
        if let old = hardwareNotes.removeValue(forKey: input) { releaseKey(old) }
        if nextHardwareKey >= Int(Int32.max)-1 { panic(); nextHardwareKey = 1024 }
        let key = nextHardwareKey; nextHardwareKey += 1; hardwareNotes[input] = key; held.insert(key)
        for i in patch.layers.indices {
            let l=playbackLayer(i)
            guard l.loaded && (l.low...l.high).contains(note) && (!disableSilent || (!l.muted && l.gain > 0)) else { continue }
            midiFX.noteOn(channel: i, key: key, pitch: note + l.effectiveTranspose, velocity: velocity,sourceID:source)
        }
    }
    private func hardwareOff(source: Int32, channel: Int, note: Int) {
        if let key = hardwareNotes.removeValue(forKey: HardwareNote(source: source, channel: channel, note: note)) { releaseKey(key) }
    }
    private func releaseKey(_ key: Int) { held.remove(key); for i in patch.layers.indices { midiFX.noteOff(channel: i, key: key) } }
    private func disconnectMIDI(_ source: Int32) {
        midiFX.releaseSource(source);audio.releaseSource(source)
        for input in Array(hardwareNotes.keys) where input.source == source {
            if let key = hardwareNotes.removeValue(forKey: input) {
                held.remove(key)
                for i in patch.layers.indices { midiFX.noteOff(channel: i, key: key,force:true); audio.noteOff(key: key, channel: i, force: true) }
            }
        }
        pedalSources = pedalSources.filter { $0.source != source }; mappedPedals = mappedPedals.filter { $0.source != source }; pressedCCs = pressedCCs.filter { $0.key.source != source }; applySustain()
    }
    func setSustain(_ value: Bool) { screenSustain = value; applySustain() }
    private func applySustain() { let value = screenSustain || !pedalSources.isEmpty || !mappedPedals.isEmpty; sustain = value; audio.sustain(value, layers: patch.layers.indices.map(playbackLayer))
        for l in patch.layers.indices.map(playbackLayer) { if let d = l.midiDestinationID { sendMIDI(d, 0xb0 | UInt8(l.midiOutputChannel), 64, value && !l.blockSustain ? 127 : 0) } } }
    func panic(preserveTonic:Bool=false,preserveEffectTails:Bool=false) { hardwareNotes.removeAll(); pedalSources.removeAll(); mappedPedals.removeAll(); screenSustain = false; midiFX.panic();
        for l in patch.layers { if let d = l.midiDestinationID { for cc: UInt8 in [64,123,120] { sendMIDI(d, 0xb0 | UInt8(l.midiOutputChannel), cc, 0) } } }
        outputNotes.removeAll(); held.removeAll(); sustain = false; metronome = false; if preserveTonic {audio.sustain(false,layers:patch.layers);for channel in 0..<15 {audio.panic(channel:channel,preserveEffectTails:preserveEffectTails)}} else {tonic = nil;audio.panic()} }
    func choose(_ index: Int) {
        pluginInterfaceRequest=nil
        guard !patchLock, setlist.patches.indices.contains(index) else { return }
        cancelAudition(); cancelTransition(); panic(preserveTonic:true,preserveEffectTails:!setlist.patches[index].silencePrevious); capturePluginStates(); selected = index; activeSnapshot = nil
        if patch.silencePrevious { panic(preserveTonic:true) }
        if patch.visualMode != 0 { notesMode = patch.visualMode == 2 }
        applyPatch(); recallTonicPatch(); audio.clock(patch.tempo, metronome)
    }
    private func applyPatch() {
        for i in patch.layers.indices {
            guard let file=patch.layers[i].external?.fileName,
                  let entry=librarySounds.first(where:{$0.id.hasPrefix("ableton-samples-") && $0.sound?.fileName == file}) else {continue}
            setlist.patches[selected].layers[i].name=SoundLibrary.cleanImportedName(patch.layers[i].name)
            if var sound=patch.layers[i].external {sound.name=SoundLibrary.cleanImportedName(sound.name);setlist.patches[selected].layers[i].external=sound}
            let old=patch.layers[i].importedRack
            if old == nil || (old?.translationVersion != 6 && old == entry.previousImportedRack) {
                setlist.patches[selected].layers[i].importedRack=entry.layer?.importedRack
                if patch.layers[i].midiProgram == nil && !patch.layers[i].octaveEffect {setlist.patches[selected].layers[i].midiProgram=entry.layer?.midiProgram}
                for snapshot in patch.snapshots.indices {
                    if var states=patch.snapshots[snapshot].sounds,states.indices.contains(i),states[i].importedRack == nil || states[i].importedRack == entry.previousImportedRack {
                        states[i].importedRack=entry.layer?.importedRack
                        if states[i].midiProgram == nil && !patch.layers[i].octaveEffect {states[i].midiProgram=entry.layer?.midiProgram}
                        setlist.patches[selected].snapshots[snapshot].sounds=states
                    }
                }
            }
        }
        cancelAudition()
        audio.setPatchVolume(patch.volumeDB)
        do {
            try audio.withGraphChanges {
                for (i, l) in patch.layers.enumerated() { configureMIDI(i, l); audio.configure(i, l) }
                configureTonic()
            }
        } catch { message = "Could not complete the patch audio graph: " + error.localizedDescription }
        // Graph restoration protects old mixer values. Apply the requested patch
        // levels/pans only after the final graph has restored its samplers.
        for (i, l) in patch.layers.enumerated() { audio.gain(i, l.loaded && !l.muted ? l.gain : 0) }
        audio.gain(15, tonicGain); updateToneFilters()
    }
    func setRange(_ index: Int, low: Int, high: Int) {
        guard patch.layers.indices.contains(index),(0...127).contains(low),(low...127).contains(high) else{return}
        if !held.isEmpty { panic() }
        setlist.patches[selected].layers[index].low = low
        setlist.patches[selected].layers[index].high = high
    }
    func moveLayer(_ index: Int, _ destination: Int) {
        guard (0..<15).contains(index), (0..<15).contains(destination), index != destination else { return }
        panic(); cancelTransition()
        setlist.patches[selected].layers.swapAt(index, destination)
        for s in patch.snapshots.indices { setlist.patches[selected].snapshots[s].gains.swapAt(index, destination); if setlist.patches[selected].snapshots[s].sounds != nil { setlist.patches[selected].snapshots[s].sounds!.swapAt(index,destination) } }
        for cc in Array(setlist.assignments.keys) {
            if setlist.assignments[cc] == index { setlist.assignments[cc] = destination }
            else if setlist.assignments[cc] == destination { setlist.assignments[cc] = index }
        }
        if let controls=setlist.controlAssignments {
            for (cc,target) in controls { if case .soundLevel(let old)=target { if old == index { setlist.controlAssignments?[cc] = .soundLevel(destination) } else if old == destination { setlist.controlAssignments?[cc] = .soundLevel(index) } } }
        }
        applyPatch(); save()
    }
    func reorderLayer(_ source: Int, _ destination: Int) {
        guard patch.layers.indices.contains(source), patch.layers.indices.contains(destination), source != destination else { return }
        panic(); cancelTransition()
        var order = Array(patch.layers.indices); let moving = order.remove(at:source); order.insert(moving,at:destination)
        let old = patch
        setlist.patches[selected].layers = order.map { old.layers[$0] }
        for s in old.snapshots.indices {
            setlist.patches[selected].snapshots[s].gains = order.map { old.snapshots[s].gains[$0] }
            if let sounds = old.snapshots[s].sounds { setlist.patches[selected].snapshots[s].sounds = order.map { sounds[$0] } }
        }
        for cc in Array(setlist.assignments.keys) { if let previous=setlist.assignments[cc] { setlist.assignments[cc]=order.firstIndex(of:previous) } }
        if let controls=setlist.controlAssignments {
            for (cc,target) in controls { if case .soundLevel(let previous)=target, let position=order.firstIndex(of:previous) { setlist.controlAssignments?[cc] = .soundLevel(position) } }
        }
        applyPatch(); save()
    }
    func setGain(_ index: Int, _ value: Float) {
        guard patch.layers.indices.contains(index),value.isFinite,(0...1).contains(value) else{return}
        cancelTransition(); activeSnapshot = nil
        setlist.patches[selected].layers[index].gain = value
        let layer = patch.layers[index]; audio.gain(index, layer.muted ? 0 : value)
        if let d = layer.midiDestinationID { sendMIDI(d, 0xb0 | UInt8(layer.midiOutputChannel), 7, UInt8(max(0,min(127,Int((layer.muted ? 0 : value)*127))))) }
    }
    func mute(_ index: Int) {
        guard patch.layers.indices.contains(index) else{return}
        cancelTransition()
        setlist.patches[selected].layers[index].muted.toggle()
        let l = patch.layers[index]; audio.gain(index, l.muted ? 0 : l.gain); if let d = l.midiDestinationID { sendMIDI(d, 0xb0 | UInt8(l.midiOutputChannel), 7, UInt8(l.muted ? 0 : Int(l.gain * 127))) }
    }
    func renamePatch(_ name:String) {let value=name.trimmingCharacters(in:.whitespacesAndNewlines);guard !patchLock,!value.isEmpty,value.count<=200 else{return};setlist.patches[selected].name=value;save()}
    func addPatch(_ name:String = "New Patch") {
        let name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !patchLock,setlist.patches.count<128,!name.isEmpty,name.count<=200 else { return }
        cancelTransition()
        var new=Patch(name:name,layers:(0..<15).map{_ in Layer.empty()},snapshots:[])
        new.programChangeEnabled=false
        setlist.patches.append(new);choose(setlist.patches.count-1);save()
    }
    func availableLibraryPatches()->[(String,Patch)] {
        var choices=setlist.patches.map{(setlist.name,$0)}
        do { let library=try localSetlistLibrary();for item in savedSetlists where item.id != currentSetlistID { let saved=try library.load(id:item.id);choices += saved.patches.map{(saved.name,$0)} } }
        catch { message=error.localizedDescription }
        return choices
    }
    func addLibraryPatch(_ source:Patch) {
        guard !patchLock,setlist.patches.count<128 else{return}
        var copy=source.duplicate();copy.name=source.name;copy.programChangeEnabled=false;copy.programChangeNumber=nil
        setlist.patches.append(copy);choose(setlist.patches.count-1);save()
    }
    func setPatchVolume(_ db:Float) { guard db.isFinite else {return};setlist.patches[selected].volumeDB=max(-24,min(12,db));audio.setPatchVolume(patch.volumeDB);save() }

    func duplicate() { guard setlist.patches.count < 128 else { return }; capturePluginStates(); let p = patch.duplicate(); setlist.patches.insert(p, at: selected + 1); choose(selected + 1); save() }
    func removePatch() { guard setlist.patches.count > 1 else { return }; panic(); cancelTransition(); setlist.patches.remove(at: selected); selected = min(selected, setlist.patches.count - 1); activeSnapshot = nil; applyPatch(); save() }
    func saveSnapshot() { captureSnapshot(patch.snapshots.firstIndex(where: { $0.isEmptySlot }) ?? patch.snapshots.count) }
    func recall(_ snapshot: Snapshot) {
        guard !snapshot.isEmptySlot else { return }
        cancelAudition()
        cancelTransition(); activeSnapshot = snapshot.id
        let initialSounds = patch.layers.map(SnapshotSoundState.init)
        let initialWheel = modWheel, initialTonicGain = tonicGain, initialBrightness = tonicBrightness
        if let states = snapshot.sounds {
            for (i,state) in states.enumerated() where patch.layers.indices.contains(i) {
                // Plug-in state is structural, not interpolated: restore it before
                // the fade so the recalled instrument matches the stored snapshot.
                if let pluginState=state.pluginState,patch.layers[i].external?.kind == .audioUnit,patch.layers[i].pluginState != pluginState {
                    setlist.patches[selected].layers[i].pluginState=pluginState
                    audio.restorePluginState(i,pluginState)
                }
                setlist.patches[selected].layers[i].effects=SnapshotMorph.interpolateEffects(from: initialSounds[i].effects, to: state.effects, fraction: 0)
                setlist.patches[selected].layers[i].midiProgram=state.midiProgram
                setlist.patches[selected].layers[i].midiEffectEnabled=state.midiEffectEnabled
                setlist.patches[selected].layers[i].pan=initialSounds[i].pan
                configureMIDI(i,patch.layers[i]); audio.configure(i,patch.layers[i])
            }
        }
        if let shimmer=snapshot.tonicShimmer { tonicShimmer=shimmer }
        if let timbre=snapshot.tonicTimbre {tonicTimbre=min(timbre,tonicNames.count-1)}
        if let root=snapshot.tonicRoot {selectTonicRoot(root)}
        if let enabled=snapshot.tonicEnabled {
            if enabled,tonic == nil {toggleTonic(tonicLastRoot)}
            else if !enabled,let root=tonic {toggleTonic(root)}
        }
        let initial = patch.layers.map { $0.muted ? 0 : $0.gain }
        for i in self.patch.layers.indices { setlist.patches[selected].layers[i].muted = false; audio.gain(i, snapshot.gains[i], seconds: snapshotDuration(snapshot)) }
        let began = Date(), duration = Double(snapshotDuration(snapshot))
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let fraction = min(1, Date().timeIntervalSince(began) / max(0.01, duration))
            for i in self.patch.layers.indices { self.setlist.patches[self.selected].layers[i].gain = initial[i] + Float(fraction) * (snapshot.gains[i] - initial[i]); if self.patch.layers[i].external != nil { self.audio.gain(i, self.patch.layers[i].gain) }; if let d = self.patch.layers[i].midiDestinationID { self.sendMIDI(d, 0xb0 | UInt8(self.patch.layers[i].midiOutputChannel), 7, UInt8(max(0,min(127,Int(self.patch.layers[i].gain*127))))) } }
            if let target = snapshot.modulation { self.modWheel = SnapshotMorph.interpolateFloat(from: initialWheel, to: target, fraction: Float(fraction)) }
            if let target = snapshot.tonicLevel { self.tonicGain = SnapshotMorph.interpolateFloat(from: initialTonicGain, to: target, fraction: Float(fraction)) }
            if let target = snapshot.tonicBrightness { self.tonicBrightness = SnapshotMorph.interpolateFloat(from: initialBrightness, to: target, fraction: Float(fraction)) }
            if let states = snapshot.sounds {
                for (i, target) in states.enumerated() {
                    let previous = self.patch.layers[i]
                    let state = SnapshotMorph.interpolateSound(from: initialSounds[i], to: target, fraction: Float(fraction))
                    self.setlist.patches[self.selected].layers[i].effects = state.effects
                    self.setlist.patches[self.selected].layers[i].importedRack = state.importedRack
                    self.setlist.patches[self.selected].layers[i].pan = state.pan
                    if previous.effects != state.effects || previous.pan != state.pan || previous.importedRack != state.importedRack { self.audio.configureSnapshot(i, effects: state.effects, pan: state.pan, importedRack:state.importedRack) }
                }
            }
            if fraction >= 1 { timer.invalidate(); self.snapshotTimer = nil }
        }
    }
    func snapshotDuration(_ snapshot: Snapshot) -> Float {
        if let beats = snapshot.beats { return min(30, beats * 60 / Float(patch.tempo)) }
        return snapshot.seconds ?? transition
    }
    func commitLayer(_ index: Int, _ layer: Layer) {
        guard patch.layers.indices.contains(index) else{return}
        var validation=Setlist();validation.patches=[Patch(name:"Sound Edit",layers:[layer],snapshots:[])]
        guard (try? validation.validate()) != nil else{message="The sound edit contains unsupported or invalid settings. The previous sound was retained.";return}
        cancelAudition()
        let previous=patch.layers[index]
        if previous.instrument != layer.instrument || previous.external != layer.external || previous.midiDestinationID != layer.midiDestinationID {
            for s in patch.snapshots.indices {
                if setlist.patches[selected].snapshots[s].sounds != nil { setlist.patches[selected].snapshots[s].sounds![index] = SnapshotSoundState(layer) }
                if !layer.loaded { setlist.patches[selected].snapshots[s].gains[index] = 0 }
            }
        }
        midiFX.panic(channel:index); audio.panic(channel:index); cancelTransition(); setlist.patches[selected].layers[index] = layer
        configureMIDI(index, layer)
        audio.configure(index, layer); audio.gain(index, layer.loaded && !layer.muted ? layer.gain : 0); updateToneFilters(); save()
    }
    func removeSound(_ index: Int) {
        guard patch.layers.indices.contains(index) else{return}
        var l = Layer.empty(); l.id = patch.layers[index].id; commitLayer(index, l)
    }
    func toggleMIDIEffect(_ index: Int) { guard patch.layers.indices.contains(index) else{return};var l = patch.layers[index]; l.midiEffectEnabled.toggle(); commitLayer(index,l) }
    func setEffect(_ index: Int, _ slot: Int, _ effect: AudioEffect) {
        guard patch.layers.indices.contains(index),patch.layers[index].effects.indices.contains(slot),effect.validate() else{return}
        let changedKind = patch.layers[index].effects[slot].kind != effect.kind
        if changedKind {
            for i in patch.snapshots.indices {
                if setlist.patches[selected].snapshots[i].sounds == nil { setlist.patches[selected].snapshots[i].sounds = patch.layers.map(SnapshotSoundState.init) }
                setlist.patches[selected].snapshots[i].sounds![index].effects[slot] = effect
            }
        }
        setlist.patches[selected].layers[index].effects[slot] = effect
        audio.configure(index, patch.layers[index]); updateToneFilters(); save()
    }
    func clearSnapshot(_ index: Int) {
        guard patch.snapshots.indices.contains(index) else { return }
        cancelTransition()
        let oldID = patch.snapshots[index].id
        var empty = Snapshot(name: "Snapshot \(index + 1)", gains: patch.layers.map { _ in 0 })
        empty.emptySlot = true
        setlist.patches[selected].snapshots[index] = empty
        if activeSnapshot == oldID { activeSnapshot = nil }
        save()
    }
    func captureSnapshot(_ index: Int) {
        guard (0..<16).contains(index) else { return }
        cancelTransition()
        capturePluginStates()
        let gains = patch.layers.map { $0.loaded && !$0.muted ? $0.gain : 0 }
        while setlist.patches[selected].snapshots.count <= index {
            let slot = setlist.patches[selected].snapshots.count
            var empty = Snapshot(name: "Snapshot \(slot + 1)", gains: patch.layers.map { _ in 0 })
            empty.emptySlot = true
            setlist.patches[selected].snapshots.append(empty)
        }
        setlist.patches[selected].snapshots[index].emptySlot = nil
        setlist.patches[selected].snapshots[index].gains = gains
        activeSnapshot = patch.snapshots[index].id
        if let snapshotIndex = patch.snapshots.firstIndex(where: { $0.id == activeSnapshot }) {
            setlist.patches[selected].snapshots[snapshotIndex].sounds = patch.layers.map(SnapshotSoundState.init)
            setlist.patches[selected].snapshots[snapshotIndex].modulation = modWheel
            setlist.patches[selected].snapshots[snapshotIndex].tonicEnabled = tonic != nil
            setlist.patches[selected].snapshots[snapshotIndex].tonicRoot = tonicLastRoot
            setlist.patches[selected].snapshots[snapshotIndex].tonicLevel = tonicGain
            setlist.patches[selected].snapshots[snapshotIndex].tonicBrightness = tonicBrightness
            setlist.patches[selected].snapshots[snapshotIndex].tonicShimmer = tonicShimmer
            setlist.patches[selected].snapshots[snapshotIndex].tonicTimbre = tonicTimbre
        }
        save()
    }
    func updateTempo(_ value: Double) { setlist.patches[selected].tempo = value; audio.clock(value, metronome); midiFX.updateTempo(value) }
    func setTranspose(_ value: Int) { setlist.patches[selected].transpose = value; setlist.patches[selected].hearIn = (patch.playIn + value + 120) % 12 }
    func transpose(play: Int, hear: Int) { setlist.patches[selected].playIn = play; setlist.patches[selected].hearIn = hear; setlist.patches[selected].transpose = hear - play; save() }
    private func cancelTransition() {
        guard snapshotTimer != nil else { return }
        snapshotTimer?.invalidate(); snapshotTimer = nil
        for (i, l) in patch.layers.enumerated() { audio.gain(i, l.muted ? 0 : l.gain) }
    }
    func toggleTonic(_ root: Int) {
        guard started,(0..<12).contains(root) else{return}
        guard tonicSound != nil else {message="Choose or import a pad sound before turning on Tonic Pad.";return}
        if tonic==root {stopTonicNotes(root);tonicLastRoot=root;tonic=nil;return}
        if let previous=tonic {stopTonicNotes(previous)}
        tonicLastRoot=root;tonic=root;playTonicNotes(root)
    }
    func tapTempo() {
        let now = Date()
        if let last = lastTaps.last, now.timeIntervalSince(last) > 3 { lastTaps.removeAll() }
        lastTaps.append(now); lastTaps = Array(lastTaps.suffix(5))
        if lastTaps.count >= 2 { let interval = now.timeIntervalSince(lastTaps[0]) / Double(lastTaps.count - 1); updateTempo(min(300, max(20, (60 / interval).rounded()))) }
    }
    func applyImportedController(_ controller:Int,value:UInt8,channel:Int) {
        guard (0...127).contains(controller),(0...15).contains(channel),![120,123].contains(controller) else{return}
        for index in patch.layers.indices where patch.layers[index].loaded {
            let layer=patch.layers[index]
            if controller==64 && layer.blockSustain {continue}
            audio.externalRack?.control(channel:index,controller:UInt8(controller),value:value)
            if var rack=layer.importedRack,rack.applyMIDI(controller:controller,value:Float(value),channel:channel) {
                setlist.patches[selected].layers[index].importedRack=rack
                audio.configure(index,setlist.patches[selected].layers[index])
            }
        }
    }
    private func handleMIDI(_ status: UInt8, _ a: UInt8, _ b: UInt8, source: Int32) {
        midiActivity.toggle()
        midiLog.insert((midiSources.first(where: { $0.id == source })?.name ?? "MIDI") + String(format: " · Ch %02d · %02X · %d · %d", Int(status & 15) + 1, status & 0xf0, a, b), at: 0)
        midiLog = Array(midiLog.prefix(15))
        let channel=Int(status & 15)
        guard MIDIControllerRules.accepts(sourceID: primarySourceID, channel: midiChannel, source: source, inputChannel: channel) ||
              MIDIControllerRules.accepts(sourceID: secondarySourceID, channel: secondaryChannel, source: source, inputChannel: channel) else { return }
        switch status & 0xf0 {
        case 0x90: if b == 0 { hardwareOff(source: source, channel: Int(status & 15), note: Int(a)) } else { hardwareOn(source: source, channel: Int(status & 15), note: Int(a), velocity: MIDIControllerRules.velocity(b, minimum: velocityMinimum, maximum: velocityMaximum)) }
        case 0x80: hardwareOff(source: source, channel: Int(status & 15), note: Int(a))
        case 0xb0:
            if learningTarget == nil && learning == nil {applyImportedController(Int(a),value:b,channel:channel)}
            if a == 1 { modWheel = Float(b)/127 }
            else if a == 64 { let pedal = PedalSource(source: source, channel: Int(status & 15)); if b >= 64 { pedalSources.insert(pedal) } else { pedalSources.remove(pedal) }; applySustain() }
            else if a == 120 || a == 123 { panic() }
            else {
                let cc=Int(a), key=CCKey(source:source,channel:channel,cc:Int(a)), down=b>=64
                let rising=down && !(pressedCCs[key] ?? false); pressedCCs[key]=down
                if let target = learningTarget ?? learning.map({ MIDIControlTarget.soundLevel($0) }) {
                    guard target.valid else { learningTarget=nil; learning=nil; return }
                    clearMIDILearn(target,saveChanges:false)
                    mappedPedals=mappedPedals.filter{$0.cc != cc}; applySustain()
                    let learned=MIDIControllerRules.assigning(cc,to:target,assignments:setlist.controlAssignments ?? [:],soundLevels:setlist.assignments)
                    guard !learned.reserved else { learningTarget=nil; learning=nil; return }
                    setlist.controlAssignments = learned.assignments.isEmpty ? nil : learned.assignments
                    setlist.assignments = learned.soundLevels
                    if let displaced=learned.displaced { message = "CC \(cc) moved from \(displaced.title) to \(target.title)." }
                    learningTarget=nil; learning=nil
                    if !target.isRisingEdge { applyMIDIControl(target,value:b,key:key,rising:rising) }
                    save()
                } else if let target=setlist.controlAssignments?[cc] { applyMIDIControl(target,value:b,key:key,rising:rising) }
                else if let index=setlist.assignments[cc] { setGain(index,Float(b)/127) }
            }
        case 0xc0:
            if let index=setlist.patches.indices.first(where:{setlist.patches[$0].programChangeEnabled == true && setlist.patches[$0].programChangeNumber == Int(a)}) { choose(index) }
            // Missing legacy flags are unconfigured, never an implicit index mapping.
        default: break
        }
    }
    /// Remove every learned assignment, keeping the fixed modulation, sustain and
    /// panic routes so the keyboard remains usable.
    func resetMIDILearn() {
        setlist.controlAssignments = nil
        setlist.assignments = [:]
        mappedPedals.removeAll(); applySustain()
        learning = nil; learningTarget = nil
        message = "MIDI learn assignments cleared. Fixed modulation, sustain, panic and program-change routes remain."
        save()
    }
    func beginMIDILearn(_ target:MIDIControlTarget) {
        guard target.valid else { return }; learning=nil; learningTarget = learningTarget == target ? nil : target
    }
    func assignedCC(_ target:MIDIControlTarget) -> Int? {
        if case .soundLevel(let index)=target, let cc=setlist.assignments.first(where:{$0.value == index})?.key { return cc }
        return setlist.controlAssignments?.first(where:{$0.value == target})?.key
    }
    func clearMIDILearn(_ target:MIDIControlTarget, saveChanges:Bool=true) {
        var removed = Set(setlist.controlAssignments?.filter{$0.value == target}.keys.map{$0} ?? [])
        if case .soundLevel(let index)=target {
            removed.formUnion(setlist.assignments.filter{$0.value == index}.keys)
            setlist.assignments=setlist.assignments.filter{$0.value != index}
        }
        setlist.controlAssignments=setlist.controlAssignments?.filter{$0.value != target}
        mappedPedals=mappedPedals.filter{!removed.contains($0.cc)}; applySustain()
        if learningTarget == target { learningTarget=nil }
        if saveChanges { save() }
    }
    private func applyMIDIControl(_ target:MIDIControlTarget,value:UInt8,key:CCKey,rising:Bool) {
        guard target.valid, !target.isRisingEdge || rising else { return }
        switch target {
        case .soundLevel(let index): setGain(index,Float(value)/127)
        case .master: master=Float(value)/127
        case .modulation: modWheel=Float(value)/127
        case .sustain: if value>=64 { mappedPedals.insert(key) } else { mappedPedals.remove(key) }; applySustain()
        case .nextPatch: if selected+1<setlist.patches.count { choose(selected+1) }
        case .previousPatch: if selected>0 { choose(selected-1) }
        case .panic: panic()
        case .snapshot(let index): if patch.snapshots.indices.contains(index) { recall(patch.snapshots[index]) }
        }
    }
    private var configuredPrograms: [Int:MIDIProgram] = [:]
    private func configureMIDI(_ index: Int, _ layer: Layer) {
        var program = layer.midiProgram ?? MIDIProgram()
        if layer.midiProgram == nil && layer.octaveEffect { program.kind = .easyChord; program.chordIntervals = [0,12] }
        if !layer.midiEffectEnabled { program.kind = .bypass }
        if configuredPrograms[index] != program.validated {
            audio.panic(channel:index)
            if let d=layer.midiDestinationID { sendMIDI(d,0xb0|UInt8(layer.midiOutputChannel),64,0);sendMIDI(d,0xb0|UInt8(layer.midiOutputChannel),123,0) }
            configuredPrograms[index]=program.validated
        }
        midiFX.configure(channel: index, program: program, tempo: patch.tempo)
        if let d = layer.midiDestinationID {
            sendMIDI(d, 0xb0 | UInt8(layer.midiOutputChannel), 7, UInt8(layer.muted ? 0 : Int(layer.gain*127)))
            sendMIDI(d, 0xb0 | UInt8(layer.midiOutputChannel), 10, UInt8(max(0,min(127,Int((layer.pan+1)*63.5)))))
        }
    }
    private func sendMIDI(_ destination: Int32, _ status: UInt8, _ a: UInt8, _ b: UInt8) {
        do { try midiOutput?.send(destinationID: destination, status: status, data1: a, data2: b) }
        catch { message = error.localizedDescription }
    }
    private struct PluginInterfaceRequest {
        var patchID:UUID
        var layerID:UUID
        var index:Int
        var sound:ExternalSound
    }
    private var pluginInterfaceRequest:PluginInterfaceRequest?
    /// Called only after committing a library selection, never during audition.
    func requestPluginInterface(_ index:Int) {
        pluginInterfaceRequest=nil
        guard !patchLock,patch.layers.indices.contains(index),
              let sound=patch.layers[index].external,sound.kind == .audioUnit else{return}
        pluginInterfaceRequest=PluginInterfaceRequest(patchID:patch.id,layerID:patch.layers[index].id,index:index,sound:sound)
    }
    /// Consume once after the library sheet dismisses. Never open a replacement.
    func takePluginInterfaceRequest()->Int? {
        guard let request=pluginInterfaceRequest else{return nil}
        pluginInterfaceRequest=nil
        guard !patchLock,patch.id==request.patchID,patch.layers.indices.contains(request.index),
              patch.layers[request.index].id==request.layerID,
              patch.layers[request.index].external==request.sound else{return nil}
        return request.index
    }
    /// Keep Audio Unit edits made in the instrument interface. The channel editor
    /// runs inside an audition, so `capturePluginStates` deliberately skips this
    /// layer and `endAudition` would otherwise restore the pre-edit state.
    func finishPluginInterface(_ index: Int) {
        guard patch.layers.indices.contains(index), patch.layers[index].external?.kind == .audioUnit else { return }
        do {
            if let state = try audio.externalRack?.stateData(channel: index) {
                audition?.pluginState = state
                setlist.patches[selected].layers[index].pluginState = state
            }
        } catch { message = "Could not capture plug-in state: \(error.localizedDescription)" }
        save()
    }
    func capturePluginStates() {
        for (i,l) in patch.layers.enumerated() where l.external?.kind == .audioUnit {
            if audition?.patchID == patch.id && audition?.index == i { continue }
            // A plug-in that is not installed or failed to load has no live state; keep
            // the state the layer already carries instead of erasing it to nothing.
            do { if let state = try audio.externalRack?.stateData(channel: i) {setlist.patches[selected].layers[i].pluginState = state} }
            catch { message = "Could not capture plug-in state: \(error.localizedDescription)" }
        }
    }
    private func prepareLibrarySound(_ url:URL,sampleRoot:URL?)throws->(ExternalSound,[String]?,Layer?) {
        guard let rack=audio.externalRack else{throw ExternalInstrumentError.missingFile}
        guard !["adg","adv","alp"].contains(url.pathExtension.lowercased()) else{throw MainStagePatch.Failure.invalid("Import the original MainStage patch or EXS instrument instead.")}
        if let root=sampleRoot {
            let sound=try url.pathExtension.lowercased()=="exs" ? rack.importEXS(url,sampleRoot:root) : rack.importPreset(url,sampleRoot:root)
            if let program=sound.nativeSampler {var layer=Layer(name:sound.name,instrument:-1,gain:1);layer.external=sound;layer.importedRack=program.rack;return (sound,program.notes,layer)}
            return (sound,nil,nil)
        }
        return (try rack.importSound(url),nil,nil)
    }
    private func installLibrarySound(_ url:URL,sampleRoot:URL?,id:String?=nil)throws->ExternalSound {
        let (sound,notes,layer)=try prepareLibrarySound(url,sampleRoot:sampleRoot)
        let library=SoundLibrary(url:saveURL.deletingLastPathComponent().appendingPathComponent("sound-library.json"))
        var entries=try library.read()
        var entry=LibrarySound(id:id ?? UUID().uuidString,name:sound.name,collection:"My Sounds",sound:sound,layer:layer,conversionNotes:notes)
        if ["exs","aupreset"].contains(url.pathExtension.lowercased()) {
            let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
            entry.originalInstrument=try StageKeysSampler.retainOriginal(url,library:saveURL.deletingLastPathComponent())
        }
        entries.append(entry)
        try library.write(entries);librarySounds=try library.read()
        return librarySounds.last(where:{$0.sound?.fileName==sound.fileName})?.sound ?? sound
    }
    @discardableResult
    func importLibrarySound(_ url:URL,sampleRoot:URL?=nil)->ExternalSound? {
        guard !libraryImportBusy else{message="A sound library import is already running.";return nil}
        do {
            return try installLibrarySound(url,sampleRoot:sampleRoot)
        }catch{message=error.localizedDescription;return nil}
    }
    func importLibraryBackup(_ folder:URL) {
        guard !libraryImportBusy else{return}
        libraryImportCancelRequested=false;libraryImportBusy=true
        Task { @MainActor in
            let access=folder.startAccessingSecurityScopedResource()
            defer{libraryImportBusy=false;if access{folder.stopAccessingSecurityScopedResource()}}
            do {
                let pack=try LibraryBackup.read(folder)
                let library=SoundLibrary(url:saveURL.deletingLastPathComponent().appendingPathComponent("sound-library.json"))
                let original=try library.read()
                var entries=original,imported=0,skipped=0,failures:[String]=[]
                var installedPresets:[String:ExternalSound]=[:]
                guard let rack=audio.externalRack else{throw ExternalInstrumentError.unsupportedFormat}
                for var entry in pack.sounds {
                    guard !entries.contains(where:{$0.id==entry.id}) else{skipped+=1;continue}
                    guard let sound=entry.sound ?? entry.layer?.external,sound.kind == .samplerPreset else{skipped+=1;continue}
                    libraryImportProgress="Preparing library sound: "+entry.name;await Task.yield();try checkLibraryImportCancellation()
                    let temp=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".aupreset")
                    defer{try? FileManager.default.removeItem(at:temp)}
                    do {
                        var installed:ExternalSound
                        if let file=sound.fileName,let cached=installedPresets[file] {installed=cached}
                        else {
                            try LibraryBackup.preset(sound,pack:pack,to:temp)
                            installed=try rack.importPreset(temp,sampleRoot:pack.root)
                            if let file=sound.fileName {installedPresets[file]=installed}
                        }
                        installed.name=sound.name
                        entry.sound=installed;entry.hostPath=nil
                        if entry.layer != nil {entry.layer?.external=installed;entry.layer?.pluginState=nil}
                        if let original=entry.originalInstrument {
                            let source=try LibraryBackup.asset(original.file,in:pack.root,manifest:pack.manifest)
                            entry.originalInstrument=try StageKeysSampler.retainOriginal(source,library:saveURL.deletingLastPathComponent())
                        }
                        entries.append(entry);imported+=1
                    }catch{failures.append(entry.name+": "+error.localizedDescription)}
                }
                try checkLibraryImportCancellation()
                guard failures.isEmpty else {throw MainStagePatch.Failure.invalid("Import not committed: "+failures.prefix(6).joined(separator:"; "))}
                try library.commitImport(entries,replacing:original);librarySounds=entries
                libraryImportProgress="Imported \(imported) library sounds with their rack processing; \(skipped) existing/archive entries skipped. "+failures.prefix(6).joined(separator:"; ")
            }catch{libraryImportProgress=error.localizedDescription}
        }
    }
    func updateSamplerEnvelopes() {
        guard !libraryImportBusy else{return}
        let root=saveURL.deletingLastPathComponent()
        do {
            // Keep both library metadata and user patches recoverable.
            let backup=root.appendingPathComponent("Sampler Backups/"+UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:backup,withIntermediateDirectories:true)
            for file in ["sound-library.json","setlist.json"] {
                let source=root.appendingPathComponent(file)
                if FileManager.default.fileExists(atPath:source.path){try FileManager.default.copyItem(at:source,to:backup.appendingPathComponent(file))}
            }
            var entries=librarySounds,updates:[String:ExternalSound]=[:],failures:[String]=[]
            for entry in entries {
                guard let sound=entry.sound,let program=sound.nativeSampler,((program.conversionVersion ?? 1)<6 || program.voiceControls?.amplitudeVelocity==nil),let original=entry.originalInstrument,let file=sound.fileName,updates[file]==nil else{continue}
                do {updates[file]=try StageKeysSampler.updatePlayback(sound,original:original,library:root)}
                catch{failures.append(entry.name+": "+error.localizedDescription)}
            }
            guard !updates.isEmpty else{libraryImportProgress="No sampler playback settings were changed. "+failures.joined(separator:"; ");return}
            for i in entries.indices {
                if let file=entries[i].sound?.fileName,let updated=updates[file]{entries[i].sound?.nativeSampler=updated.nativeSampler;entries[i].conversionNotes=Array(Set((entries[i].conversionNotes ?? [])+(updated.nativeSampler?.notes ?? []))).sorted()}
                if let file=entries[i].layer?.external?.fileName,let updated=updates[file]{entries[i].layer?.external?.nativeSampler=updated.nativeSampler}
            }
            try SoundLibrary(url:root.appendingPathComponent("sound-library.json")).write(entries);librarySounds=entries
            panic()
            for p in setlist.patches.indices {for l in setlist.patches[p].layers.indices {
                if let file=setlist.patches[p].layers[l].external?.fileName,let updated=updates[file]{setlist.patches[p].layers[l].external?.nativeSampler=updated.nativeSampler}
            }}
            applyPatch();save()
            libraryImportProgress="Updated \(updates.count) sampler instruments. Original samples, rack effects and patch settings are preserved. "+failures.joined(separator:"; ")
        }catch{libraryImportProgress=error.localizedDescription}
    }
    func mainStageProcessing(_ channel:Int)throws->MainStageProcessing.Draft {
        guard let report=mainStageImportReport,let id=report.sourceArchiveID,UUID(uuidString:id) != nil,report.channels.indices.contains(channel) else{throw MainStagePatch.Failure.invalid("Import the MainStage source patch again to preview its processing.")}
        let root=saveURL.deletingLastPathComponent().appendingPathComponent("MainStage Sources/"+id+"/Source.patch",isDirectory:true)
        let document=try PropertyListSerialization.propertyList(from:MainStagePatch.verifiedRead(root.appendingPathComponent("data.plist"),in:root,sha256:report.preservedFiles["data.plist"]),options:[],format:nil) as? [String:Any]
        let channels=document?["channels"] as? [[String:Any]]
        let source=channels?.first(where:{$0["Filename"] as? String==report.channels[channel].file})
        var draft=try MainStageProcessing.translate(MainStagePatch.verifiedRead(root.appendingPathComponent(report.channels[channel].file),in:root,sha256:report.channels[channel].sha256),channelID:source?["Channel_instID"] as? Int)
        if let source {MainStageProcessing.channelSettings(source,to:&draft)}
        return draft
    }
    /// Convert the selected channels: sampler channels from the chosen EXS folder, and
    /// channels whose saved third-party Audio Unit is installed here. `installedAudioUnits`
    /// exists so a conversion can be verified without third-party plug-ins present.
    func importMainStageSamplers(_ folder:URL,installedAudioUnits:[ExternalAUIdentity]?=nil) {
        guard !libraryImportBusy,let report=mainStageImportReport else{return}
        let selection=selectedMainStageChannels
        let names=Set(report.channels.enumerated().filter{selection.contains($0.offset)}.flatMap{$0.element.instruments})
        let audioUnitChannels=report.channels.enumerated().filter{selection.contains($0.offset) && $0.element.instruments.isEmpty && !$0.element.thirdPartyAudioUnits.isEmpty}
        guard names.count<=64 else{libraryImportProgress="This patch references too many sampler instruments; choose a narrower selection.";return}
        guard !names.isEmpty || !audioUnitChannels.isEmpty else{libraryImportProgress="No supported EXS references or saved Audio Units were selected in this source patch.";return}
        libraryImportCancelRequested=false;libraryImportBusy=true
        Task { @MainActor in
            let access=folder.startAccessingSecurityScopedResource()
            defer{libraryImportBusy=false;if access{folder.stopAccessingSecurityScopedResource()}}
            do {
                let files=names.isEmpty ? []:try MainStagePatch.findSamplerInstruments(names,in:folder)
                let library=SoundLibrary(url:saveURL.deletingLastPathComponent().appendingPathComponent("sound-library.json"))
                let original=try library.read()
                var entries=original,imported=0,skipped=0,failures:[String]=[]
                for (channelIndex,channel) in report.channels.enumerated() where selection.contains(channelIndex) && !channel.instruments.isEmpty {
                    guard channel.unsupportedInstrumentFamily == nil else {failures.append(channel.name+": "+channel.nativeInstrumentStatus);continue}
                    guard channel.instruments.count==1,let name=channel.instruments.first else{failures.append(channel.name+": layered sampler selection requires translation");continue}
                    let matches=files.filter{$0.lastPathComponent==name}
                    guard matches.count==1 else{failures.append(name+": "+(matches.isEmpty ? "instrument not found in the selected folder":"multiple matches; choose a narrower folder"));continue}
                    let file=matches[0]
                    libraryImportProgress="Importing MainStage channel: "+channel.name
                    await Task.yield();try checkLibraryImportCancellation()
                    do {
                        let processing=try mainStageProcessing(channelIndex)
                        let id=try MainStagePatch.conversionID(report,channel:channel,variant:AssetDigest.sha256(file))
                        if let existing=entries.firstIndex(where:{$0.id==id}) {
                            entries[existing].sourceArchiveID=report.sourceArchiveID
                            skipped+=1;continue
                        }
                        let (sound,notes,template)=try prepareLibrarySound(file,sampleRoot:folder)
                        var layer=template ?? Layer(name:channel.name,instrument:-1,gain:1)
                        layer.name=channel.name;layer.external=sound
                        layer=try processing.applying(to:layer)
                        let original=try StageKeysSampler.retainOriginal(file,library:saveURL.deletingLastPathComponent())
                        // One layer hosts one instrument: a channel that also saved an Audio
                        // Unit keeps that state in the archive instead of losing it silently.
                        let audioUnitNotes=channel.thirdPartyAudioUnits.first.map{["the channel also saved \($0.name); this layer hosts the converted sampler only, so its plug-in state stays in the archive."]} ?? []
                        let entry=LibrarySound(id:id,name:channel.name,collection:"MainStage Patches",sound:sound,layer:layer,sourceArchiveID:report.sourceArchiveID,conversionNotes:(notes ?? [])+processing.issues+audioUnitNotes,originalInstrument:original)
                        entries.append(entry)
                        imported+=1
                    }catch{failures.append(channel.name+": "+error.localizedDescription)}
                }
                if !audioUnitChannels.isEmpty {
                    let installed=installedAudioUnits ?? ExternalInstrumentRack.instruments()
                    for (channelIndex,channel) in audioUnitChannels {
                        guard channel.thirdPartyAudioUnits.count==1,let unit=channel.thirdPartyAudioUnits.first else{failures.append(channel.name+": multiple saved Audio Units in one channel require manual setup");continue}
                        libraryImportProgress="Hosting \(unit.name) for MainStage channel: "+channel.name
                        await Task.yield();try checkLibraryImportCancellation()
                        do {
                            guard let archiveID=report.sourceArchiveID else{throw MainStagePatch.Failure.invalid("Import the MainStage source patch again to host its Audio Units.")}
                            let root=saveURL.deletingLastPathComponent().appendingPathComponent("MainStage Sources/"+archiveID+"/Source.patch",isDirectory:true)
                            let data=try MainStagePatch.verifiedRead(root.appendingPathComponent(channel.file),in:root,sha256:channel.sha256)
                            guard let state=MainStageAudioUnit.state(for:unit,in:data) else{throw MainStagePatch.Failure.invalid("its saved Audio Unit state could not be read; retain the source or re-save the strip.")}
                            let hosted=try MainStageAudioUnit.hostedLayer(name:channel.name,device:unit,state:state,installed:installed)
                            let processing=try mainStageProcessing(channelIndex)
                            // Use original strip/metadata bytes, not reserialized plug-in
                            // state, while including separately saved channel settings.
                            let id=try MainStagePatch.conversionID(report,channel:channel,variant:"audio-unit")
                            if let existing=entries.firstIndex(where:{$0.id==id}) {
                                entries[existing].sourceArchiveID=archiveID
                                skipped+=1;continue
                            }
                            let layer=try processing.applying(to:hosted.layer)
                            entries.append(LibrarySound(id:id,name:channel.name,collection:"MainStage Patches",sound:layer.external,layer:layer,sourceArchiveID:archiveID,conversionNotes:hosted.notes+processing.issues))
                            imported+=1
                        }catch{failures.append(channel.name+": "+error.localizedDescription)}
                    }
                }
                try checkLibraryImportCancellation()
                guard failures.isEmpty else{throw MainStagePatch.Failure.invalid("Import not committed: "+failures.prefix(6).joined(separator:"; "))}
                try library.commitImport(entries,replacing:original);librarySounds=entries
                libraryImportProgress="Imported \(imported) MainStage channels with supported effects, macros and MIDI settings; \(skipped) already present. Review conversion notes for unsupported routing and processing. "+failures.joined(separator:"; ")
            }catch{libraryImportProgress=error.localizedDescription}
        }
    }
    func importMainStagePatch(_ url:URL) {
        guard !libraryImportBusy else{return}
        let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
        do {
            let directory=saveURL.deletingLastPathComponent().appendingPathComponent("MainStage Sources",isDirectory:true).appendingPathComponent(UUID().uuidString,isDirectory:true)
            var report=try MainStagePatch.retain(url,to:directory)
            report.sourceArchiveID=directory.lastPathComponent
            let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
            try encoder.encode(report).write(to:saveURL.deletingLastPathComponent().appendingPathComponent("mainstage-import-report.json"),options:.atomic)
            mainStageImportReport=report
            mainStageChannelSelection=Set(report.channels.indices.filter{report.channels[$0].isConvertible})
            let retainedRoot=directory.appendingPathComponent("Source.patch",isDirectory:true)
            let names=Set(report.channels.flatMap(\.instruments))
            if !names.isEmpty,!(try MainStagePatch.findSamplerInstruments(names,in:retainedRoot)).isEmpty {
                libraryImportProgress="Preflight complete. Review channel selection and conversion limitations, then choose Convert Included Instruments. No sounds have been added."
                return
            }
            let audioUnits=report.channels.filter{!$0.thirdPartyAudioUnits.isEmpty}.count
            if audioUnits>0 {
                libraryImportProgress="Preflight complete. \(audioUnits) channel(s) saved a third-party Audio Unit, which is hosted when that component is installed here; sampler channels still need their original instrument folder. Review the selection and limitations, then choose Convert Included Instruments. No sounds have been added."
                return
            }
            libraryImportProgress="Preserved \(report.channels.count) channel strips and their original effects, macros and MIDI data. Playback conversion requires \(report.blockers.count) unsupported settings to be translated. No incomplete sound was added."
        }catch{mainStageImportReport=nil;libraryImportProgress=error.localizedDescription}
    }
    func assembleConvertedMainStagePatch() {
        guard !patchLock,let report=mainStageImportReport,setlist.patches.count<128 else{return}
        do {
            let assembled=try MainStagePatch.assembledChannels(report,entries:librarySounds)
            setlist.patches.append(assembled);choose(setlist.patches.count-1);save()
            message="Converted channels added as a new patch. Review Conversion Notes in Patch Settings before performing."
        }catch{message=error.localizedDescription}
    }
    @discardableResult
    func importSound(_ url:URL,index:Int,sampleRoot:URL?=nil)->Bool {
        guard let sound=importLibrarySound(url,sampleRoot:sampleRoot),
              let entry=librarySounds.last(where:{$0.sound == sound}) else{return false}
        // The library layer owns the translated rack, macros and MIDI program.
        // Reconstructing a bare ExternalSound here silently discarded processing.
        addLibrarySound(entry,index:index);return true
    }
    func importSamplerLibrary(_ folder: URL) {
        guard !libraryImportBusy else{message="A sound library import is already running.";return}
        libraryImportCancelRequested=false;libraryImportBusy=true
        Task { @MainActor in
            let access=folder.startAccessingSecurityScopedResource()
            defer{libraryImportBusy=false;if access{folder.stopAccessingSecurityScopedResource()}}
            do {
                let library=SoundLibrary(url:saveURL.deletingLastPathComponent().appendingPathComponent("sound-library.json"))
                let original=try library.read()
                var entries=original,imported=0,skipped=0
                for url in try SoundLibrary.samplerPresets(in:folder) {
                    libraryImportProgress="Preparing sampler: "+url.lastPathComponent
                    await Task.yield();try checkLibraryImportCancellation()
                    let values=try url.resourceValues(forKeys:[.fileSizeKey])
                    guard (values.fileSize ?? Int.max)<=16_000_000 else{throw ExternalInstrumentError.unsupportedFormat}
                    let bytes=try Data(contentsOf:url)
                    guard bytes.count<=16_000_000 else{throw ExternalInstrumentError.unsupportedFormat}
                    let id="sampler-"+MainStagePatch.digest(bytes)
                    if entries.contains(where:{$0.id==id}){skipped+=1;continue}
                    let (sound,notes,layer)=try prepareLibrarySound(url,sampleRoot:folder)
                    let originalInstrument=try StageKeysSampler.retainOriginal(url,library:saveURL.deletingLastPathComponent())
                    entries.append(LibrarySound(id:id,name:sound.name,collection:"My Sounds",sound:sound,layer:layer,conversionNotes:notes,originalInstrument:originalInstrument))
                    imported+=1
                }
                try checkLibraryImportCancellation()
                try library.commitImport(entries,replacing:original);librarySounds=entries
                libraryImportProgress="Imported \(imported) sampler instruments; \(skipped) already present."
            }catch{libraryImportProgress="Import not committed: "+error.localizedDescription}
        }
    }
    #if os(macOS)
    func exportLibrarySound(_ entry: LibrarySound) {
        guard let sound = entry.sound, sound.kind == .samplerPreset else { return }
        let panel = NSOpenPanel(); panel.title = "Choose a folder for the exported sampler instrument"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard let self, response == .OK, let folder = panel.url else { return }
            let access = folder.startAccessingSecurityScopedResource()
            defer { if access { folder.stopAccessingSecurityScopedResource() } }
            do {
                guard let rack = self.audio.externalRack else { throw ExternalInstrumentError.missingFile }
                let name = entry.name.replacingOccurrences(of: "/", with: "-")
                let preset = try SamplerInterchange.exportPreset(sound, libraryURL: rack.libraryURL, to: folder.appendingPathComponent(name + "-" + UUID().uuidString.prefix(8)))
                self.message = "Exported \(preset.path). Load Instrument.aupreset into Apple's AUSampler in MainStage. Keep the Samples folder with it; re-import after moving to relink paths."
            } catch { self.message = error.localizedDescription }
        }
    }
    #endif
    func saveSoundToLibrary(_ source: Layer, index: Int) -> Bool {
        do {
            var layer = source
            if layer.external?.kind == .audioUnit { layer.pluginState = try audio.externalRack?.stateData(channel: index) }
            var validation = Setlist(); validation.patches = [Patch(name: "Library Validation", layers: [layer], snapshots: [])]
            try validation.validate()
            let library = SoundLibrary(url: saveURL.deletingLastPathComponent().appendingPathComponent("sound-library.json"))
            var entries = try library.read()
            entries.append(LibrarySound(id: UUID().uuidString, name: layer.name, collection: "My Sounds", sound: layer.external, layer: layer))
            try library.write(entries); librarySounds = entries; return true
        } catch { message = error.localizedDescription; return false }
    }
    func addLibrarySound(_ entry: LibrarySound, index: Int) {
        guard patch.layers.indices.contains(index) else{return}
        if var layer = entry.layer { if layer.external==nil {layer.external=entry.sound};layer.id = patch.layers[index].id; commitLayer(index, layer); return }
        if let sound = entry.sound { addExternal(sound, index: index); return }
        #if os(macOS)
        if let path = entry.hostPath, NSWorkspace.shared.open(URL(fileURLWithPath: path)) {
            addMIDIDestination(ExternalMIDIDestination(id: ExternalMIDIOutput.broadcastID, name: entry.name, endpoint: 0), index: index)
            message = "Select StageKeys to External App in MainStage and use MIDI channel \(patch.layers[index].midiOutputChannel + 1). Audio plays through MainStage."
        } else { message = "This preset requires MainStage and its installed instruments." }
        #else
        message = "This MainStage preset requires a Mac. Import a sampled version to play on this device."
        #endif
    }
    func addExternal(_ sound: ExternalSound, index: Int) {
        var l = Layer(name: sound.name, instrument: -1, gain: 0.65)
        l.id = patch.layers[index].id; l.external = sound;l.importedRack=sound.nativeSampler?.rack; commitLayer(index, l)
    }
    #if os(macOS)
    func openHostPatch(index: Int) {
        let panel = NSOpenPanel()
        panel.title = "Open a MainStage patch in its host"
        panel.allowedContentTypes = [UTType(filenameExtension: "patch") ?? .package]
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            if NSWorkspace.shared.open(url) {
                let d = ExternalMIDIDestination(id: ExternalMIDIOutput.broadcastID, name: url.deletingPathExtension().lastPathComponent, endpoint: 0)
                self.addMIDIDestination(d, index: index)
                self.message = "In the host app, select ‘StageKeys to External App’ as the MIDI input and choose MIDI channel \(self.patch.layers[index].midiOutputChannel + 1). Configure audio in that host."
            } else { self.message = "Install MainStage to open this host patch. Use native patch import to translate supported instruments and processing." }
        }
    }
    #endif
    func addMIDIDestination(_ destination: ExternalMIDIDestination, index: Int) {
        var l = Layer(name: destination.name, instrument: -1, gain: 1)
        l.id = patch.layers[index].id; l.midiDestinationID = destination.id; commitLayer(index, l)
    }
    func save() {
        guard !sessionRecoveryRequired, !settingsRecoveryRequired else {
            message = "Automatic saves are blocked because saved session data could not be loaded. Recover the previous session in Settings; the original files remain untouched."
            return
        }
        capturePluginStates()
        do { try setlist.validate(); try FileManager.default.createDirectory(at: saveURL.deletingLastPathComponent(), withIntermediateDirectories: true); if let legacyData {
                let backup = saveURL.deletingLastPathComponent().appendingPathComponent("setlist-v\(legacyVersion)-backup.json")
                if !FileManager.default.fileExists(atPath: backup.path) { try legacyData.write(to: backup, options: .atomic) }
                self.legacyData = nil
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(setlist)
            guard data.count <= 64_000_000 else { throw SetlistError.invalid }
            try RecoverableSessionFile.write(data, to: saveURL) { _ = try JSONDecoder().decode(Setlist.self, from: $0).upgraded() }
            currentSetlistID = try localSetlistLibrary().save(setlist,id:currentSetlistID).id
            refreshSetlists()
            let settings = SessionSettings(selectedPatchID:patch.id,activeSnapshotID:activeSnapshot,notesMode:notesMode,modWheel:modWheel,master: master, reverb: reverb, transition: transition, midiChannel: midiChannel, primarySourceID: primarySourceID, secondarySourceID: secondarySourceID, secondaryChannel: secondaryChannel, velocityMinimum: velocityMinimum, velocityMaximum: velocityMaximum, sourceNames: midiSourceNames, disableSilent: disableSilent, showRanges: showRanges, tonicGain: tonicGain, tonicBrightness: tonicBrightness, tonicShimmer: tonicShimmer, audioOutputUID: preferredAudioOutputUID, activeSetlistID: currentSetlistID,tonicSound:tonicSound,tonicVelocitySelector:tonicVelocitySelector,tonicTimbre:tonicTimbre,tonicLastRoot:tonicLastRoot,metronomeEnabled:metronome,audioBufferFrames:preferredBufferFrames.map{Int($0)})
            guard settings.validate() else { throw SetlistError.invalid }
            try RecoverableSessionFile.write(encoder.encode(settings), to: saveURL.deletingLastPathComponent().appendingPathComponent("settings.json")) {
                guard try JSONDecoder().decode(SessionSettings.self, from: $0).validate() else { throw SetlistError.invalid }
            } }
        catch { message = "Could not save: \(error.localizedDescription)" }
    }
    func recoverPreviousRatings() {
        do {
            soundRatings=try SoundRatingArchive.recover(saveURL.deletingLastPathComponent().appendingPathComponent("sound-ratings.json"))
            ratingsRecoveryRequired=false;message="Previous ratings restored; damaged bytes retained."
        } catch {message="Could not recover ratings: \(error.localizedDescription). Existing files were retained."}
    }
    func recoverPreviousPresets() {
        do {
            effectPresets=try EffectPresetArchive.recover(saveURL.deletingLastPathComponent().appendingPathComponent("effect-presets.json"))
            presetsRecoveryRequired=false;message="Previous personal effect presets restored; damaged bytes retained. Active effects were not changed."
        } catch {message="Could not recover effect presets: \(error.localizedDescription). Existing files were retained."}
    }
    func recoverPreviousLibrary() {
        do {
            librarySounds=try SoundLibrary(url:saveURL.deletingLastPathComponent().appendingPathComponent("sound-library.json")).recoverPrevious()
            libraryRecoveryRequired=false
            message="Previous sound catalog restored. Damaged catalog bytes were retained; samples and current patches were not changed."
        } catch {message="Could not recover the sound catalog: \(error.localizedDescription). Existing files were retained."}
    }
    func recoverPreviousSession() {
        do {
            if sessionRecoveryRequired {
                let data = try RecoverableSessionFile.restore(saveURL) { _ = try JSONDecoder().decode(Setlist.self, from: $0).upgraded() }
                let recovered = try JSONDecoder().decode(Setlist.self, from: data).upgraded()
                panic(); cancelAudition(); cancelTransition()
                setlist = recovered; selected = 0; activeSnapshot = nil; currentSetlistID = nil
                sessionRecoveryRequired = false
                if started { applyPatch(); recallTonicPatch() }
            }
            if settingsRecoveryRequired {
                _ = try RecoverableSessionFile.restore(saveURL.deletingLastPathComponent().appendingPathComponent("settings.json")) {
                    guard try JSONDecoder().decode(SessionSettings.self, from: $0).validate() else { throw SetlistError.invalid }
                }
                message = "Previous settings restored. Restart StageKeys to load them before making further edits."
            } else { message = "Previous session restored. The damaged file was retained alongside it." }
        } catch { message = "Recovery could not complete: \(error.localizedDescription). Original files remain preserved." }
    }
    private func localSetlistLibrary() throws -> SetlistLibrary { try SetlistLibrary(root: saveURL.deletingLastPathComponent().appendingPathComponent("Setlists")) }
    func refreshSetlists() {
        do {
            let library = try localSetlistLibrary(), inventory = try library.list()
            savedSetlists = inventory.entries; setlistLibraryIssues = inventory.issues
            archivedSetlists = try library.listTrash().entries.filter { archived in !savedSetlists.contains(where: { $0.id == archived.originalID }) }
        } catch { message = error.localizedDescription }
    }
    private func preserveCurrentSetlist() throws {
        cancelAudition(); capturePluginStates(); try setlist.validate()
        currentSetlistID = try localSetlistLibrary().save(setlist,id:currentSetlistID).id
    }
    func openLocalSetlist(_ id: UUID) {
        guard !patchLock else { message = "Unlock patches before changing setlists."; return }
        guard id != currentSetlistID else { return }
        do {
            let loaded = try localSetlistLibrary().load(id:id)
            try preserveCurrentSetlist()
            panic(); cancelTransition(); setlist = loaded; currentSetlistID = id; selected = 0; activeSnapshot = nil
            applyPatch(); recallTonicPatch(); audio.clock(patch.tempo,metronome); save()
        } catch { message = error.localizedDescription }
    }
    func createLocalSetlist() {
        guard !patchLock else { message = "Unlock patches before changing setlists."; return }
        do {
            try preserveCurrentSetlist()
            var fresh = Setlist(); fresh.name = "New Setlist"; fresh.patches = [Patch(name:"New Patch",layers:(0..<15).map { _ in Layer.empty() },snapshots:[])]
            let id = try localSetlistLibrary().save(fresh).id
            panic(); cancelTransition(); setlist = fresh; currentSetlistID = id; selected = 0; activeSnapshot = nil
            applyPatch(); recallTonicPatch(); audio.clock(patch.tempo,metronome); save()
        } catch { message = error.localizedDescription }
    }
    func renameLocalSetlist(_ id: UUID, name: String) {
        do {
            if id == currentSetlistID {
                guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, name.count <= 200 else { throw SetlistLibraryError.name }
                setlist.name = name; save()
            } else { try localSetlistLibrary().rename(id:id,name:name); refreshSetlists() }
        } catch { message = error.localizedDescription }
    }
    func duplicateLocalSetlist(_ id: UUID) {
        do { if id == currentSetlistID { try preserveCurrentSetlist() }; _ = try localSetlistLibrary().duplicate(id:id); refreshSetlists() }
        catch { message = error.localizedDescription }
    }
    func archiveLocalSetlist(_ id: UUID) {
        guard id != currentSetlistID else { message = "Open another setlist before moving this one to Trash."; return }
        do { _ = try localSetlistLibrary().delete(id:id); refreshSetlists() } catch { message = error.localizedDescription }
    }
    func restoreLocalSetlist(_ token: UUID) {
        do { _ = try localSetlistLibrary().restore(token:token); refreshSetlists() } catch { message = error.localizedDescription }
    }
    func load(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= 64_000_000 else { throw SetlistError.invalid }
            let loaded = try JSONDecoder().decode(Setlist.self, from: Data(contentsOf: url)); let upgraded = try loaded.upgraded()
            try preserveCurrentSetlist()
            panic(); cancelTransition(); setlist = upgraded; currentSetlistID = nil; selected = 0; activeSnapshot = nil; applyPatch(); save()
        } catch { message = "Could not import: \(error.localizedDescription)" }
    }
    deinit { snapshotTimer?.invalidate(); notifications.forEach(NotificationCenter.default.removeObserver) }
}
struct SetlistFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var setlist: Setlist
    init(_ setlist: Setlist) { self.setlist = setlist }
    init(configuration: ReadConfiguration) throws { setlist = try JSONDecoder().decode(Setlist.self, from: configuration.file.regularFileContents ?? Data()).upgraded() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { try setlist.validate(); let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; let data = try encoder.encode(setlist); guard data.count <= 64_000_000 else { throw SetlistError.invalid }; return FileWrapper(regularFileWithContents: data) }
}
