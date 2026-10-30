import SwiftUI
import CoreText
import UniformTypeIdentifiers

@main
struct StageKeysApp: App {
    @StateObject private var store = PerformanceStore()
    init() {
        #if os(macOS)
        if let url=Bundle.main.url(forResource:"StageKeys",withExtension:"icns"),let icon=NSImage(contentsOf:url) {NSApplication.shared.applicationIconImage=icon}
        #endif
        for name in ["IBMPlexSans-Regular", "IBMPlexSans-SemiBold", "IBMPlexSans-Bold"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }
    var body: some Scene {
        WindowGroup {
            PerformanceView().environmentObject(store).preferredColorScheme(.dark).font(StageTheme.font(14))
            #if os(macOS)
                .frame(minWidth: 1100, minHeight: 780)
            #endif
        }
        #if os(macOS)
        .defaultSize(width: 1194, height: 866)
        .commands {
            CommandGroup(after:.help) {
                Divider()
                Button(store.audioCheckRecording ? "Recording Audio Check…":"Record 30-Second Audio Check") {store.startAudioCheck()}.disabled(store.audioCheckRecording)
                Button("Stop Audio Check") {store.stopAudioCheck()}.disabled(!store.audioCheckRecording)
            }
        }
        #endif
    }
}
enum StageTheme {
    static let base = Color(red: 0.065, green: 0.071, blue: 0.11)
    static let panel = Color(red: 0.14, green: 0.15, blue: 0.21)
    static let raised = Color(red: 0.23, green: 0.26, blue: 0.36)
    static let selected = Color(red: 0.64, green: 0.76, blue: 0.94)
    static let colors: [Color] = [Color(red: 0.97, green: 0.66, blue: 0.28), Color(red: 0.2, green: 0.77, blue: 0.47), Color(red: 0.24, green: 0.39, blue: 0.94), Color(red: 0.59, green: 0.34, blue: 0.90), Color(red: 0.88, green: 0.40, blue: 0.75), .cyan, .orange, .brown, .pink, .gray, .red, .yellow, .purple, .green, .pink]
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let name = weight == .bold || weight == .heavy ? "IBMPlexSans-Bold" : weight == .semibold || weight == .medium ? "IBMPlexSans-SemiBold" : "IBMPlexSans-Regular"
        return .custom(name, size: size)
    }
    static let notes = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
    static func db(_ gain: Float) -> String { gain < 0.0001 ? "−∞" : String(format: "%.1f dB", 20 * log10(gain)) }
}
struct StageButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(StageTheme.font(12, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(selected ? StageTheme.selected : StageTheme.raised.opacity(configuration.isPressed ? 0.9 : 0.65), in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(selected ? StageTheme.base : Color.white.opacity(0.9)).opacity(isEnabled ? 1 : 0.4)
    }
}
enum StageSheet: Identifiable {
    case importSounds, settings, patch, newPatch, renamePatch, patchLibrary, transpose, tempo, setlists, learn, tonic
    case sound(Int), plugin(Int), browser(Int), effect(Int,Int), snapshot(Int), midi(Int), note(Int)
    var id: String { String(describing: self) }
}
struct PerformanceView: View {
    @EnvironmentObject var store: PerformanceStore
    @Environment(\.scenePhase) var scenePhase
    @State private var sheet: StageSheet?
    @State private var menuExpanded = false
    @State private var addingPatch = false
    @State private var importing = false
    @State private var exporting = false
    var body: some View {
        GeometryReader { g in
            let wide = g.size.width >= 850
            VStack(spacing: 8) {
                toolbar
                if store.patch.layers.allSatisfy({!$0.loaded}) {
                    HStack {Text("StageKeys ships without sounds. Add your samples, Audio Units or external MIDI.").font(.caption)
                        Button("Import Samples"){sheet = .importSounds}.buttonStyle(StageButtonStyle())
                        Button("Add Sound"){sheet = .browser(0)}.buttonStyle(StageButtonStyle())}
                }
                if store.hasUnavailableLegacyVoices {Text("This patch contains unavailable legacy voices. Add replacement sounds; saved settings are retained.").font(.caption)}
                if !wide { compactNavigation }
                if store.editRanges { LayerRangeEditor() } else { HStack(spacing: 10) {
                    if wide { sidebar.frame(width: 299) }
                    VStack(spacing: 8) {
                        rack
                        if store.notesMode { snapshotNotes.frame(height: max(75, g.size.height * 0.15)) }
                        HStack(spacing: 7) { snapshotStrip; workspaceButtons }
                    }
                }
                }
                if !store.editRanges { KeyboardWorkspace().frame(height: wide ? 160 : 140) }
            }.padding(8).background(StageTheme.base)
        }
        .overlay {
            if menuExpanded {
                ZStack(alignment:.topTrailing) {
                    Color.black.opacity(0.3).onTapGesture{menuExpanded=false}
                    VStack(alignment:.leading,spacing:4) {
                        HStack{Text("StageKeys").font(.headline);Spacer();Button{menuExpanded=false}label:{Image(systemName:"xmark")}.buttonStyle(.plain).accessibilityLabel("Close Main Menu")}.padding(14)
                        menuItem("Import Sounds",icon:"plus.circle"){sheet = .importSounds}
                        menuItem("MIDI Learn",icon:"slider.horizontal.3"){sheet = .learn}
                        menuItem("Settings",icon:"gearshape"){sheet = .settings}
                        menuItem("Setlists",icon:"list.bullet"){sheet = .setlists}
                        Divider().opacity(0.2)
                        menuItem("Save Setlist",icon:"square.and.arrow.down"){store.save()}
                        menuItem("Import Setlist",icon:"square.and.arrow.down.on.square"){importing=true}
                        menuItem("Export Setlist",icon:"square.and.arrow.up"){exporting=true}
                    }.padding(8).frame(width:280).background(StageTheme.base,in:RoundedRectangle(cornerRadius:12)).overlay{RoundedRectangle(cornerRadius:12).stroke(.white.opacity(0.08))}.padding(.top,60).padding(.trailing,8)
                }
            }
        }
        .onAppear { store.start() }
        .tint(StageTheme.selected)
        .sheet(item: $sheet, onDismiss: {
            DispatchQueue.main.async {
                if let index=store.takePluginInterfaceRequest() { sheet = .plugin(index) }
            }
        }) { destination in
            Group {
                switch destination {
                case .importSounds: SoundImportView()
                case .settings: SettingsEditor()
                case .patch: PatchEditor()
                case .newPatch: NewPatchEditor()
                case .renamePatch: NewPatchEditor(initial:store.patch.name,renaming:true)
                case .patchLibrary: PatchLibraryPicker()
                case .transpose: TransposeEditor()
                case .tempo: TempoEditor()
                case .setlists: SetlistBrowser(importing: $importing, exporting: $exporting)
                case .learn: MIDIControlLearnView()
                case .tonic: TonicSettingsEditor()
                case .sound(let index): SoundEditor(index: index, initial: store.patch.layers[index])
                case .browser(let index): SoundBrowser(index: index)
                case .plugin(let index): PluginInterface(index:index)
                case .midi(let index): MIDIEffectEditor(index: index)
                case .effect(let index, let slot): EffectEditor(index: index, slot: slot, initial: store.patch.layers[index].effects[slot])
                case .note(let index): SnapshotNoteEditor(index: index, initial: store.patch.snapshots[index])
                case .snapshot(let index): SnapshotEditor(index: index, initial: store.patch.snapshots[index])
                }
            }.environmentObject(store).preferredColorScheme(.dark).font(StageTheme.font(14))
        }
        .alert("StageKeys", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("OK") { store.message = nil } } message: { Text(store.message ?? "") }
        .onOpenURL {url in
            if url.pathExtension.lowercased()=="stagekeyspack" {store.importLibraryBackup(url);sheet = .importSounds}
            else if ["patch","cst"].contains(url.pathExtension.lowercased()) {store.importMainStageAutomatically(url);sheet = .importSounds}
        }
        .onDrop(of:[UTType.fileURL],isTargeted:nil){providers in
            guard !store.libraryImportBusy,let provider=providers.first else{return false}
            _ = provider.loadObject(ofClass:URL.self){url,_ in guard let url,["patch","cst"].contains(url.pathExtension.lowercased()) else{return};DispatchQueue.main.async{store.importMainStageAutomatically(url);sheet = .importSounds}}
            return true
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result { case .success(let url): store.load(url); case .failure(let error): store.message = error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: SetlistFile(store.setlist), contentType: .json, defaultFilename: store.setlist.name) { result in
            if case .failure(let error) = result { store.message = error.localizedDescription }
        }
        .onChange(of: store.patch.id) { _ in sheet = nil }
        .onChange(of: store.activeSnapshot) { _ in if sheet != nil { sheet=nil } }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                #if os(macOS)
                store.releaseScreenNotes()
                #else
                store.panic()
                #endif
                store.save()
            }
        }
    }
    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Label("stagekeys", systemImage: "waveform").font(StageTheme.font(15, weight: .semibold)).tracking(1.5).frame(width: 160, alignment: .leading)
                Button { sheet = .transpose } label: {
                    HStack(spacing: 0) {
                        VStack(spacing: 3) { Text("Play In").font(StageTheme.font(9)); Text(StageTheme.notes[store.patch.playIn]) }.frame(width: 49)
                        Divider().frame(height: 38)
                        VStack(spacing: 3) { Text("Hear In").font(StageTheme.font(9)); Text(StageTheme.notes[store.patch.hearIn]) }.frame(width: 49)
                    }.frame(height: 44)
                }.buttonStyle(.plain).background(StageTheme.panel, in: RoundedRectangle(cornerRadius: 6))
                HStack(spacing: 0) {
                    Button { sheet = .tempo } label: { Text("\(Int(store.patch.tempo))").frame(width: 57, height: 44) }.buttonStyle(.plain)
                    Divider().frame(height: 30)
                    Button { sheet = .tempo } label: { Text("4/4").frame(width: 49, height: 44) }.buttonStyle(.plain)
                    Divider().frame(height: 30)
                    Button { store.metronome.toggle() } label: { Image(systemName: "metronome").frame(width: 38, height: 44).foregroundStyle(store.metronome ? StageTheme.selected : .secondary) }.buttonStyle(.plain).accessibilityLabel("Metronome")
                    Divider().frame(height: 30)
                    Button { store.patchLock.toggle() } label: { Text("Patch\nLock").font(StageTheme.font(12, weight: .semibold)).frame(width: 44, height: 44).foregroundStyle(store.patchLock ? StageTheme.selected : .secondary) }.buttonStyle(.plain).accessibilityLabel("Patch Lock")
                }.background(StageTheme.panel, in: RoundedRectangle(cornerRadius: 6))
                HStack(spacing: 0) {
                    Button("Effects") { store.notesMode = false }.buttonStyle(StageButtonStyle(selected: !store.notesMode))
                    Button("Notes") { store.notesMode = true }.buttonStyle(StageButtonStyle(selected: store.notesMode))
                }.padding(3).background(StageTheme.panel.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                Button { store.panic() } label: { Label("Panic", systemImage: "speaker.slash").frame(width: 59, height: 24) }.buttonStyle(StageButtonStyle())
                HStack(spacing: 9) {
                    VStack(alignment: .leading, spacing: 2) { Text("Master").foregroundStyle(.secondary); Text(StageTheme.db(store.master)).monospacedDigit() }.font(StageTheme.font(12, weight: .semibold))
                    MasterFader(gain: $store.master).frame(width: 180, height: 38)
                }
                Button { sheet = .importSounds } label: { Image(systemName:"plus.circle.fill").frame(width:30,height:36) }.buttonStyle(.plain).accessibilityLabel("Import Sounds")
                Button { if store.started { sheet = .settings } else { store.start() } } label: { Image(systemName: store.started ? "speaker.wave.2" : "power").frame(width: 24, height: 24) }.buttonStyle(StageButtonStyle()).accessibilityLabel(store.started ? "Audio Settings" : "Start Audio")
                Button { menuExpanded.toggle() } label: { Image(systemName:"line.3.horizontal").frame(width:40,height:36) }.buttonStyle(.plain).accessibilityLabel("Main Menu")

            }.foregroundStyle(StageTheme.selected.opacity(0.85)).padding(.vertical, 3)
        }.frame(height: 52)
    }
    private var workspaceButtons: some View {
        HStack(spacing: 6) {
            Button { store.setSustain(!store.sustain) } label: { Image(systemName: "pedal.accelerator").frame(width: 30, height: 28) }.buttonStyle(StageButtonStyle(selected: store.sustain)).accessibilityLabel("Sustain pedal")
            Button { store.editRanges.toggle() } label: { Image(systemName: "rectangle.split.3x1").frame(width: 30, height: 28) }.buttonStyle(StageButtonStyle(selected: store.editRanges)).accessibilityLabel("Edit keyboard layers")
            Button { store.showRanges.toggle() } label: { Image(systemName: "pianokeys").frame(width: 30, height: 28) }.buttonStyle(StageButtonStyle(selected: store.showRanges)).accessibilityLabel("Show keyboard ranges")
        }.padding(4).background(StageTheme.panel, in: RoundedRectangle(cornerRadius: 8))
    }
    private var compactNavigation: some View {
        HStack {
            Button(store.setlist.name) { sheet = .setlists }.buttonStyle(StageButtonStyle())
            Picker("Patch", selection: Binding(get: { store.selected }, set: { store.choose($0) })) { ForEach(store.setlist.patches.indices, id: \.self) { Text(store.setlist.patches[$0].name).tag($0) } }.disabled(store.patchLock)
            Button { sheet = .tonic } label: { Image(systemName: "waveform") }.buttonStyle(StageButtonStyle()).accessibilityLabel("Tonic Pad")
        }
    }
    private var sidebar: some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                Button { sheet = .setlists } label: { HStack { Text(store.setlist.name); Spacer(); Image(systemName: "chevron.right") }.padding(14) }.buttonStyle(.plain).font(.subheadline.bold()).background(StageTheme.raised.opacity(0.4))
                ScrollView {
                    VStack(spacing: 1) {
                        if addingPatch {
                            Button { addingPatch=false;sheet = .newPatch } label: { Label("Create a New Patch",systemImage:"doc.badge.plus").frame(maxWidth:.infinity,alignment:.leading).padding(16) }.buttonStyle(.plain)
                            Button { addingPatch=false;sheet = .patchLibrary } label: { Label("Add a Patch from the Library",systemImage:"square.and.arrow.down").frame(maxWidth:.infinity,alignment:.leading).padding(16) }.buttonStyle(.plain)
                        } else {
                        ForEach(store.setlist.patches.indices, id: \.self) { i in
                            HStack {
                                Button { store.choose(i) } label: { Text(store.setlist.patches[i].name).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 14) }.buttonStyle(.plain).disabled(store.patchLock)
                                if i == store.selected { patchMenu }
                            }.font(StageTheme.font(14, weight: i == store.selected ? .bold : .regular)).padding(.horizontal, 13)
                                .background(i == store.selected ? StageTheme.raised.opacity(0.6) : Color.clear)
                        }
                    }
                    }
                }
                HStack {
                    Button("Prev") { store.choose(store.selected - 1) }.disabled(store.patchLock || store.selected == 0)
                    Spacer()
                    Button { addingPatch.toggle() } label: { Image(systemName: "plus.square") }.disabled(store.patchLock).accessibilityLabel("Add Patch")
                    Spacer()
                    Button("Next") { store.choose(store.selected + 1) }.disabled(store.patchLock || store.selected == store.setlist.patches.count - 1)
                }.font(.system(size: 13, weight: .semibold)).padding(13).background(StageTheme.raised.opacity(0.4))
            }.background(StageTheme.panel, in: RoundedRectangle(cornerRadius: 9)).clipShape(RoundedRectangle(cornerRadius: 9))
            TonicPanel(onSettings:{sheet = .tonic}).frame(height: 288)
        }
    }
    private func menuItem(_ title:String,icon:String,action:@escaping()->Void)->some View {
        Button{menuExpanded=false;action()}label:{Label(title,systemImage:icon).frame(maxWidth:.infinity,alignment:.leading).padding(14)}.buttonStyle(.plain)
    }
    private var patchMenu: some View {
        Menu {
            Button("Patch Settings…") { sheet = .patch }
            Button("Duplicate Patch") { store.duplicate() }.disabled(store.patchLock)
            Button("Rename Patch…") { sheet = .renamePatch }.disabled(store.patchLock)
            Button("Remove Patch", role: .destructive) { store.removePatch() }.disabled(store.patchLock || store.setlist.patches.count < 2)
            Button("Save Setlist") { store.save() }
        } label: { Image(systemName: "ellipsis") }.frame(width: 24)
    }
    private var rack: some View {
        GeometryReader { g in
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(0..<15) { i in
                        SoundModule(index: i, open: { sheet = $0 })
                            .frame(width: max(158, (g.size.width - 32) / 5))
                    }
                }.padding(.bottom, 8)
            }
        }
    }
    private var snapshotStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(0..<max(5, store.patch.snapshots.count), id: \.self) { i in
                    let snapshot = store.patch.snapshots.indices.contains(i) ? store.patch.snapshots[i] : nil
                    let populated = snapshot.map { !$0.isEmptySlot } ?? false
                    Button {
                        if let snapshot, populated { store.recall(snapshot) }
                    } label: {
                        VStack(spacing: 4) {
                            Text(populated ? snapshot!.name : "Snapshot").lineLimit(1)
                            Text(populated ? (snapshot!.beats.map { String(format: "%.1f beats", $0) } ?? "Default") : "\(i + 1)").font(.system(size: 9)).opacity(0.65)
                        }.frame(width: 100, height: 28)
                    }.buttonStyle(StageButtonStyle(selected: populated && store.activeSnapshot == snapshot?.id))
                        .accessibilityLabel(populated ? "Snapshot \(i + 1), \(snapshot!.name)" : "Snapshot \(i + 1), empty")
                        .help(populated ? "Recall snapshot. Use the context menu to edit or clear." : "Empty slot. Use Capture Snapshot to save the current mix here.")
                        .contextMenu {
                            if populated {
                                Button("Customize…") { sheet = .snapshot(i) }
                                if i > 0 { Button("Move Left") { store.setlist.patches[store.selected].snapshots.swapAt(i, i-1); store.save() } }
                                Button("Clear", role: .destructive) { store.clearSnapshot(i) }
                            }
                            Button("Capture Current Mix") { store.captureSnapshot(i) }
                        }
                }
                Menu {
                    ForEach(0..<max(5, store.patch.snapshots.count), id: \.self) { i in Button("Capture into Slot \(i + 1)") { store.captureSnapshot(i) } }
                    Button("Next Empty Slot") { store.saveSnapshot() }
                } label: { Image(systemName: "square.and.arrow.down").padding(10) }.accessibilityLabel("Capture Snapshot")
            }
        }.frame(height: 54)
    }
    private var snapshotNotes: some View {
        Group {
            if let id = store.activeSnapshot, let i = store.patch.snapshots.firstIndex(where: { $0.id == id }) {
                let snapshot = store.patch.snapshots[i]
                Button { sheet = .note(i) } label: {
                    if snapshot.noteText.isEmpty { VStack(spacing: 8) { Image(systemName: "plus.square").font(.title); Text("Add Snapshot Note").font(StageTheme.font(20, weight: .bold)); Text("Notes are dynamically displayed based on the currently selected Snapshot").font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else { Text(snapshot.noteText).font(StageTheme.font(22)).multilineTextAlignment(snapshot.alignment == 1 ? .center : snapshot.alignment == 2 ? .trailing : .leading).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: snapshot.alignment == 1 ? .center : snapshot.alignment == 2 ? .trailing : .leading).padding(20) }
                }.buttonStyle(.plain)
            } else { Text("Select a snapshot to view or add its note").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.background(StageTheme.panel, in: RoundedRectangle(cornerRadius: 8))
    }
}
