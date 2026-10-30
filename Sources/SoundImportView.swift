import SwiftUI
import UniformTypeIdentifiers

struct SoundImportView:View {
    @EnvironmentObject private var store:PerformanceStore
    private enum ImportChoice { case file, library, samples, mainStage, mainStageSamples, backup }
    @State private var choosing=false
    @State private var choice:ImportChoice = .file
    @State private var pending:URL?
    @State private var status:String?
    @State private var portableSelection:Set<String>?
    @State private var effectRequest:MainStageEffectSelectionRequest?
    var body:some View {
        EditorFrame(title:"Import Sounds",width:650,height:720) {
            ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text("Add sounds to your library").font(StageTheme.font(21,weight:.bold))
                Text("Imported sounds appear in your library and can be added to any patch.").foregroundStyle(.secondary)
                Button{choice = .file;choosing=true}label:{HStack{Image(systemName:"plus.circle.fill").font(.title);VStack(alignment:.leading,spacing:4){Text("Choose a Sound File").font(.headline);Text("StageKeys Sampler · EXS · AUPRESET · audio · sound banks").font(.caption)};Spacer();Image(systemName:"chevron.right")}.padding(20).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:10))
                Button{choice = .library;choosing=true}label:{HStack{Image(systemName:"folder.badge.plus").font(.title);VStack(alignment:.leading,spacing:4){Text("Import a Sampler Library Folder").font(.headline);Text("Add EXS and AUPRESET instruments with their original samples").font(.caption)};Spacer();Image(systemName:"chevron.right")}.padding(20).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:10))
                Button{choice = .mainStage;choosing=true}label:{HStack{Image(systemName:"pianokeys").font(.title);VStack(alignment:.leading,spacing:4){Text("Convert a MainStage Patch or Channel Strip").font(.headline);Text("Convert included EXS sounds without opening MainStage; preserve source processing").font(.caption)};Spacer();Image(systemName:"chevron.right")}.padding(20).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:10))
                Button("Install a Personal Sound Pack or Library") {choice = .backup;choosing=true}.buttonStyle(StageButtonStyle())
                #if os(macOS)
                DisclosureGroup("Transfer Native Sounds to Your Other Devices") {
                    ForEach(store.librarySounds) {entry in
                        if let reason=LibraryBackup.portabilityIssue(entry) {Text("\(entry.name): \(reason)").font(.caption).foregroundStyle(.secondary)}
                        else {Toggle(entry.name,isOn:Binding(get:{portableSelection?.contains(entry.id) ?? true},set:{value in var selected=portableSelection ?? Set(store.librarySounds.filter{LibraryBackup.portabilityIssue($0)==nil}.map(\.id));if value{selected.insert(entry.id)}else{selected.remove(entry.id)};portableSelection=selected}))}
                    }
                    Button("Save Selected Personal Sound Pack…") {store.exportPersonalSoundLibrary(ids:portableSelection)}.buttonStyle(StageButtonStyle())
                    Text("For personal device transfer. Current sound processing travels; session files, ratings and plug-in snapshots are excluded.").font(.caption)
                }
                #endif
                Text("Choose a downloaded StageKeys-Library pack. Sounds and rack processing install separately; the app ships without sampled content.").font(.caption).foregroundStyle(.secondary)
                if store.librarySounds.contains(where:{$0.originalInstrument?.file.hasSuffix(".exs")==true && $0.sound?.nativeSampler != nil && ($0.sound?.nativeSampler?.conversionVersion ?? 1)<6}) {
                    Button("Update Converted Sampler Playback") {store.updateSamplerEnvelopes()}.buttonStyle(StageButtonStyle())
                    Text("Update source filters, velocity response, level and envelope curves. Original samples and effects stay intact; edited settings are protected.").font(.caption).foregroundStyle(.secondary)
                }
                if let report=store.mainStageImportReport {
                    if store.mainStageOutcomes.contains(where:{[.converted,.duplicate].contains($0.state)}) {
                        Button("Create Patch from Ready Channels") {store.assembleConvertedMainStagePatch(readyOnly:true)}.buttonStyle(StageButtonStyle()).disabled(store.patchLock)
                    }
                    ForEach(store.mainStageOutcomes) {outcome in
                        VStack(alignment:.leading,spacing:4) {Text("\(outcome.name) · \(outcome.state.rawValue)").font(.headline);Text(outcome.detail).font(.caption)}.frame(maxWidth:.infinity,alignment:.leading)
                    }
                    if !store.mainStageSearches.isEmpty {DisclosureGroup("Searched Locations") {ForEach(store.mainStageSearches){search in Text("\(search.location): \(search.detail)").font(.caption).textSelection(.enabled)}}}
                    Button("Create Patch from All Converted Channels") {store.assembleConvertedMainStagePatch()}.buttonStyle(StageButtonStyle()).disabled(store.patchLock)
                    Text("Requires one converted version of every convertible channel. Preserves channel order, effects, macros and MIDI; patch-level routing limitations remain in Conversion Notes.").font(.caption).foregroundStyle(.secondary)
                    if report.channels.contains(where:\.isConvertible) {
                        Button("Locate Samples and Convert Selected Channels") {choice = .mainStageSamples;choosing=true}.buttonStyle(StageButtonStyle())
                        Button("Convert Included Instruments") {store.convertIncludedMainStageSounds()}.buttonStyle(StageButtonStyle()).disabled(store.selectedMainStageChannels.isEmpty)
                        Text("Choose the original EXS/sample folder. Supported channel effects and controls are saved with each sound; conversion notes list remaining differences.").font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Conversion Report · \(report.name)") {
                        ScrollView {VStack(alignment:.leading,spacing:6) {
                            ForEach(Array(report.channels.enumerated()),id:\.offset) {channelIndex,channel in
                                if channel.isConvertible {
                                    Toggle("Convert \(channel.name)",isOn:Binding(get:{store.selectedMainStageChannels.contains(channelIndex)},set:{store.selectMainStageChannel(channelIndex,$0)}))
                                    Button("Choose Effects…") {
                                        do {
                                            effectRequest=MainStageEffectSelectionRequest(channel:channelIndex,name:channel.name,draft:try store.mainStageProcessing(channelIndex),selection:store.mainStageSelection(channelIndex))
                                            status=nil
                                        } catch {status=error.localizedDescription}
                                    }.buttonStyle(StageButtonStyle())
                                }
                                Text(channel.name+": "+channel.devices.map(\.name).joined(separator:", ")).font(.caption)
                                Text(channel.nativeInstrumentStatus).font(.caption).foregroundStyle(.secondary)
                                if !channel.instruments.isEmpty {Text(channel.instruments.joined(separator:", ")).font(.caption).foregroundStyle(.secondary)}
                            }
                            ForEach(Array(report.blockers.enumerated()),id:\.offset){_,message in Text(message).font(.caption).foregroundStyle(.secondary)}
                        }.frame(maxWidth:.infinity,alignment:.leading)}.frame(maxHeight:130)
                    }
                }
                if store.libraryImportBusy {ProgressView().progressViewStyle(.linear)}
                if let progress=store.libraryImportProgress {Text(progress).font(.callout).textSelection(.enabled)}
                if let status {Text(status).font(.callout).textSelection(.enabled)}
                Spacer()
            }.padding(28).disabled(store.libraryImportBusy)
            }.overlay(alignment:.bottom) {
                if store.libraryImportBusy {Button("Cancel Import Before Commit") {store.cancelLibraryImport()}.buttonStyle(StageButtonStyle()).padding().background(StageTheme.base)}
            }
        }.fileImporter(isPresented:$choosing,allowedContentTypes:choice == .file ? [.audio,.data] : choice == .mainStage ? [.package,.folder,.data] : choice == .backup ? [.folder,.data]:[.folder]) {result in
            switch result {
            case .success(let url):
                switch choice {
                case .file:
                    if url.pathExtension.lowercased()=="stagekeyspack" {store.importLibraryBackup(url);status=nil}
                    else if ["patch","cst"].contains(url.pathExtension.lowercased()) {store.importMainStageAutomatically(url);status=nil}
                    else if ["exs","aupreset"].contains(url.pathExtension.lowercased()) {
                        pending=url;status="Choose the folder containing this instrument’s samples. Imports preserve sample maps and translated rack effects, macros and MIDI settings. Conversion notes describe remaining approximations."
                        // Present the second picker after the first has dismissed.
                        DispatchQueue.main.async {choice = .samples;choosing=true}
                    } else if ["adg","adv","alp"].contains(url.pathExtension.lowercased()) {status="Import the original MainStage patch or EXS instrument instead."}
                    else {importFile(url)}
                case .samples:
                    if let pending {importFile(pending,samples:url)}
                    pending=nil
                case .backup:store.importLibraryBackup(url)
                case .mainStageSamples:
                    store.rememberMainStageSampleFolder(url);store.importMainStageSamplers(url);status=nil
                case .mainStage:
                    store.importMainStageAutomatically(url);status=nil
                case .library:
                    store.importSamplerLibrary(url);status=store.message;store.message=nil
                }
            case .failure(let error):status=error.localizedDescription;pending=nil
            }
        }.onDrop(of:[UTType.fileURL],isTargeted:nil){providers in
            guard let provider=providers.first else{return false}
            _ = provider.loadObject(ofClass:URL.self){url,_ in guard let url,["patch","cst"].contains(url.pathExtension.lowercased()) else{return};DispatchQueue.main.async{store.importMainStageAutomatically(url)}}
            return true
        }.sheet(item:$effectRequest){request in MainStageEffectSelectionSheet(request:request).environmentObject(store)}
    }

    private func importFile(_ url:URL,samples:URL?=nil){
        if let sound=store.importLibrarySound(url,sampleRoot:samples){status="Added \(sound.name) to My Sounds."}
        else {status=store.message ?? "Could not import this sound.";store.message=nil}
    }
}

struct MainStageEffectSelectionRequest:Identifiable {
    let id=UUID()
    var channel:Int
    var name:String
    var draft:MainStageProcessing.Draft
    var selection:MainStageProcessing.Selection
}

/// Choose source processing before conversion. EQ/compressor are always mapped
/// to the instrument controls; only the remaining effects compete for the three
/// visible audio slots. The complete source record is cached on the converted layer.
struct MainStageEffectSelectionSheet:View {
    @EnvironmentObject private var store:PerformanceStore
    @Environment(\.dismiss) private var dismiss
    let request:MainStageEffectSelectionRequest
    @State private var selection:MainStageProcessing.Selection
    @State private var error:String?
    init(request:MainStageEffectSelectionRequest) {
        self.request=request
        _selection=State(initialValue:request.selection)
    }
    private var unselectedCount:Int {request.draft.slotIndices.filter{!selection.audio.contains($0)}.count}
    var body:some View {
        EditorFrame(title:"MainStage Effects · \(request.name)",width:680,height:640) {
            ScrollView {
                VStack(alignment:.leading,spacing:14) {
                    Text("Source effects, in source order").font(StageTheme.font(15,weight:.semibold))
                    Text("EQ and compressor map to the instrument controls. Choose up to three other effects for the visible audio slots. Unselected processing remains in the archived source; no effect rack is appended automatically.").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(request.draft.effects.enumerated()),id:\.offset) {index,effect in effectRow(index,effect)}
                    if request.draft.effects.isEmpty {Text("No translated audio effects were found in this channel.").font(.caption).foregroundStyle(.secondary)}
                    Divider()
                    Text("MIDI effect").font(StageTheme.font(15,weight:.semibold))
                    Text(request.draft.hasMIDITransform ? "The source MIDI transform is retained in the archive but has no verified native translation. A selection here is a manual replacement, not a translated source effect.":"This channel has no source MIDI transform record. A native MIDI effect can still be assigned manually.").font(.caption).foregroundStyle(.secondary)
                    Picker("MIDI effect",selection:Binding<MIDIFXKind>(get:{selection.midi?.kind ?? .bypass},set:{kind in selection.midi=kind == .bypass ? nil:MIDIProgram(kind:kind)})) {
                        Text("None").tag(MIDIFXKind.bypass)
                        ForEach(MIDIFXKind.allCases,id:\.self){kind in Text(kind.rawValue.capitalized).tag(kind)}
                    }
                    if selection.midi != nil {Toggle("MIDI effect enabled",isOn:$selection.midiEnabled)}
                    if unselectedCount>0 {Text("\(unselectedCount) source effect(s) will remain archived and unassigned; the original channel strip and sample bytes are unchanged.").font(.caption).foregroundStyle(.secondary)}
                    if let error {Text(error).font(.caption).foregroundStyle(.red)}
                    HStack {
                        Text("\(selection.audio.count) of 3 audio slots selected. EQ/compressor do not consume an audio slot.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Cancel"){dismiss()}.buttonStyle(StageButtonStyle())
                        Button("Use These Effects"){apply()}.buttonStyle(StageButtonStyle(selected:true)).disabled(selection.audio.count>3)
                    }
                }.padding(24)
            }
        }
    }
    @ViewBuilder private func effectRow(_ index:Int,_ effect:AudioEffect)->some View {
        if effect.kind==7 || effect.kind==6 {
            VStack(alignment:.leading,spacing:4) {
                HStack {Text("\(index+1). \(effect.title)").font(.subheadline.bold());Spacer();Text(effect.kind==7 ? "Instrument EQ":"Instrument Compressor").font(.caption).foregroundStyle(.secondary)}
                Text(request.draft.sourceNames.indices.contains(index) ? request.draft.sourceNames[index]:effect.title).font(.caption).foregroundStyle(.secondary)
                Text(effect.enabled ? "Enabled · mapped automatically":"Bypassed · mapped automatically").font(.caption).foregroundStyle(.secondary)
                notes(index)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(10).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:6))
        } else {
            let selected=selection.audio.contains(index)
            Toggle(isOn:Binding(get:{selection.audio.contains(index)},set:{on in
                if on {if selection.audio.count<3 {selection.audio.append(index)}}
                else {selection.audio.removeAll{$0==index}}
            })) {
                VStack(alignment:.leading,spacing:4) {
                    HStack {Text("\(index+1). \(effect.title)").font(.subheadline.bold());Spacer();Text(effect.enabled ? "Enabled":"Bypassed").font(.caption).foregroundStyle(.secondary)}
                    Text(request.draft.sourceNames.indices.contains(index) ? request.draft.sourceNames[index]:effect.title).font(.caption).foregroundStyle(.secondary)
                    notes(index)
                }
            }.disabled(!selected && selection.audio.count>=3)
        }
    }
    @ViewBuilder private func notes(_ index:Int)->some View {
        if request.draft.effectNotes.indices.contains(index) {
            ForEach(Array(request.draft.effectNotes[index].enumerated()),id:\.offset){_,note in Text(note).font(.caption).foregroundStyle(.secondary)}
        }
    }
    private func apply() {
        do {try store.setMainStageEffectSelection(selection,for:request.channel);dismiss()}
        catch {self.error=error.localizedDescription}
    }
}
