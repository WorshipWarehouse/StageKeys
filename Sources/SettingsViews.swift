import SwiftUI

struct SettingsEditor: View {
    @EnvironmentObject var store: PerformanceStore
    @State private var section = "Audio"
    private let sections = ["Audio", "Flex Routing", "Metronome", "MIDI", "Performance", "Snapshots"]
    var body: some View {
        EditorFrame(title: "Settings",width:960,height:760) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 4) {
                    ForEach(sections, id: \.self) { item in
                        Button { section=item } label: { HStack{Text(item);Spacer();Image(systemName:"chevron.right")}.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(section==item ? StageTheme.selected.opacity(0.75) : .clear,in:RoundedRectangle(cornerRadius:8)) }.buttonStyle(.plain)
                    }
                    Spacer()
                }.padding(12).frame(width: 210).background(StageTheme.base)

                Form {
                    switch section {
                    case "Audio":
                        Section("Audio Output") {
                            #if os(macOS)
                            Picker("Device",selection:Binding(get:{store.audioStatus?.deviceID ?? 0},set:{store.selectAudioOutput($0)})) {
                                ForEach(store.audioOutputs) { output in Text(output.name).tag(output.id) }
                            }
                            #else
                            Text(store.audioStatus?.name ?? "System Output")
                            #endif
                            Toggle("Audio Running",isOn:Binding(get:{store.started},set:{if $0 {store.start()} else {store.panic();store.audio.stop();store.started=false}}))
                            Toggle("Bypass Master Limiter (Temporary)",isOn:$store.masterLimiterBypassed)
                            Text("For listening comparisons. The limiter returns on when StageKeys restarts; output headroom stays unchanged.").font(.caption).foregroundStyle(.secondary)
                            if let status=store.audioStatus {
                                Text("Sample Rate: \(Int(status.sampleRate)) Hz")
                                Text("Buffer: \(status.bufferFrames) samples · \(status.bufferMilliseconds,specifier:"%.1f") ms")
                                if status.canSetBuffer {
                                    Picker("Hardware Buffer",selection:Binding(get:{status.bufferFrames},set:{store.setAudioBuffer($0)})) {
                                        ForEach([UInt32(32),64,128,256,512,1024,2048].filter{$0>=status.minimumBufferFrames && $0<=status.maximumBufferFrames},id:\.self) { Text("\($0) samples").tag($0) }
                                    }
                                    Text("The hardware buffer may be shared with other audio apps.").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Button("Refresh Audio Devices") { store.refreshAudioDevices() }
                        }
                        Section("Shared Hall Reverb") { Slider(value:$store.reverb,in:0...65);Text("Wet Mix: \(Int(store.reverb)) %") }
                    case "Flex Routing":
                        Section("Stereo Output") { Text("All modules and the tonic pad feed the system stereo output. Per-module pan is available in Sound Settings.") }
                        Text("Multiple hardware outputs and category routing are not implemented.").foregroundStyle(.secondary)
                    case "Metronome":
                        Toggle("Metronome", isOn: $store.metronome)
                        Stepper("\(Int(store.patch.tempo)) BPM", value: Binding(get: { store.patch.tempo }, set: { store.updateTempo($0) }), in: 20...300)
                        Text("Fixed synthesized click; follows the patch tempo and master volume. Accent patterns and alternate click sounds are not implemented.").font(.caption).foregroundStyle(.secondary)
                    case "MIDI":
                        Section("MIDI Keyboards · Automatic Connection") {
                            Text(store.midiStatus).font(.headline)
                            if store.midiSources.isEmpty { Text("Power on your keyboard and connect its USB-MIDI port with a data cable. It connects automatically as soon as the operating system detects it.").font(.caption).foregroundStyle(.secondary) }
                            ForEach(store.midiSources) { source in
                                HStack { Image(systemName: source.connected ? "checkmark.circle.fill" : "exclamationmark.circle").foregroundStyle(source.connected ? .green : .orange); Text(source.name); Spacer(); Text(source.connected ? "Connected" : "Connecting…").foregroundStyle(.secondary) }
                            }
                            ForEach(store.midiDevices.filter { !$0.online }) { device in
                                HStack { Image(systemName: "cable.connector.slash").foregroundStyle(.secondary); Text(device.name); Spacer(); Text("Offline").foregroundStyle(.secondary) }
                            }
                            HStack { Button("Refresh Devices") { store.refreshMIDI() }; Button("Plug and Play Defaults") { store.automaticMIDI() } }
                        }
                        Section("Primary MIDI Controller") { midiSourcePicker("Device",selection:$store.primarySourceID); midiChannelPicker(selection:$store.midiChannel) }
                        Section("Secondary MIDI Controller") { midiSourcePicker("Device",selection:$store.secondarySourceID); midiChannelPicker(selection:$store.secondaryChannel) }
                        Section("Velocity") {
                            Stepper("Minimum: \(store.velocityMinimum)",value:$store.velocityMinimum,in:0...store.velocityMaximum)
                            Stepper("Maximum: \(store.velocityMaximum)",value:$store.velocityMaximum,in:store.velocityMinimum...127)
                        }
                        #if os(macOS)
                        Section("Bluetooth / Network MIDI") {
                            Text("Connect Bluetooth or network controllers in Audio MIDI Setup, then assign them above.").font(.caption)
                            Button("Open Audio MIDI Setup") { store.openAudioMIDISetup() }
                        }
                        #endif
                        Section("MIDI Monitor") {
                            if store.midiLog.isEmpty { Text("Play a key or press a pedal to verify incoming MIDI").foregroundStyle(.secondary) }
                            ForEach(Array(store.midiLog.enumerated()), id: \.offset) { _, line in Text(line).font(.system(.caption, design: .monospaced)) }
                            Button("Clear Log") { store.midiLog = [] }
                        }
                    case "Performance":
                        Toggle("Disable Silenced Sounds", isOn: $store.disableSilent)
                        Text("When enabled, muted modules and modules with their fader fully down do not create new voices.").font(.caption).foregroundStyle(.secondary)
                        Toggle("Show Layer Ranges", isOn: $store.showRanges)
                        Text("192 synth voices are shared by all 15 modules and the tonic pad. Each original synth module has its own voice limit in Sound Settings. Imported instruments manage their own polyphony.").font(.caption).foregroundStyle(.secondary)
                    default:
                        Section("Default Transition") { Slider(value: $store.transition, in: 0...15, step: 0.1); Text("\(store.transition, specifier: "%.1f") seconds") }
                        Text("Right-click a snapshot to customize, capture into it, reorder, or clear it. Touch devices use a long press.").font(.caption).foregroundStyle(.secondary)
                    }
                }.formStyle(.grouped)
            }.onAppear { store.refreshAudioDevices() }.onDisappear { store.save() }
        }
    }
    private func midiSourcePicker(_ title: String, selection: Binding<Int32>) -> some View {
        Picker(title,selection:selection) {
            Text("All devices").tag(Int32(-1)); Text("None").tag(Int32(-2))
            ForEach(store.midiSourceNames.keys.sorted(),id:\.self) { id in
                Text((store.midiSourceNames[id] ?? "MIDI Device") + (store.midiSources.contains(where:{$0.id==id && $0.connected}) ? "" : " · Not Connected")).tag(id)
            }
        }
    }
    private func midiChannelPicker(selection: Binding<Int>) -> some View {
        Picker("Channel",selection:selection) { Text("All Channels").tag(-1); ForEach(0..<16) { Text("Channel \($0+1)").tag($0) } }
    }

}
struct SetlistBrowser: View {
    @EnvironmentObject var store: PerformanceStore
    @Environment(\.dismiss) var dismiss
    @Binding var importing: Bool
    @Binding var exporting: Bool
    @State private var search = ""
    @State private var renameID: UUID?
    @State private var renameName = ""
    var body: some View {
        EditorFrame(title:"Setlists",width:800) {
            HStack {
                Button { store.createLocalSetlist() } label: { Label("New Setlist",systemImage:"plus") }.buttonStyle(StageButtonStyle())
                TextField("Search Setlists",text:$search).textFieldStyle(.roundedBorder)
                Menu("Import / Export") {
                    Button("Import Setlist…") { dismiss(); DispatchQueue.main.asyncAfter(deadline:.now()+0.4) { importing=true } }
                    Button("Export Current Setlist…") { store.save(); dismiss(); DispatchQueue.main.asyncAfter(deadline:.now()+0.4) { exporting=true } }
                }
            }.padding(.horizontal,20).padding(.bottom,12)
            ScrollView {
                LazyVStack(spacing:8) {
                    ForEach(store.savedSetlists.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { entry in
                        HStack {
                            Button { store.openLocalSetlist(entry.id) } label: {
                                HStack(spacing:12) {
                                    Image(systemName:entry.id == store.currentSetlistID ? "checkmark.circle.fill" : "music.note.list")
                                    VStack(alignment:.leading,spacing:4) { Text(entry.name).font(StageTheme.font(16,weight:.semibold)); Text("\(entry.patchCount) patches").font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                }.padding(14)
                            }.buttonStyle(StageButtonStyle(selected:entry.id == store.currentSetlistID))
                            Menu {
                                Button("Rename…") { renameName=entry.name; renameID=entry.id }
                                Button("Duplicate") { store.duplicateLocalSetlist(entry.id) }
                                Button("Move to Trash",role:.destructive) { store.archiveLocalSetlist(entry.id) }.disabled(entry.id == store.currentSetlistID)
                            } label: { Image(systemName:"ellipsis").frame(width:36,height:44) }.accessibilityLabel("Options for \(entry.name)")
                        }
                    }
                    if !store.archivedSetlists.isEmpty {
                        DisclosureGroup("Trash · \(store.archivedSetlists.count) setlists") {
                            ForEach(store.archivedSetlists) { entry in HStack { Text(entry.name); Spacer(); Button("Restore") { store.restoreLocalSetlist(entry.token) } }.padding(10) }
                        }.padding(14)
                    }
                    ForEach(Array(store.setlistLibraryIssues.enumerated()),id:\.offset) { _, issue in Text("\(issue.fileName): \(issue.message)").font(.caption).foregroundStyle(.orange).frame(maxWidth:.infinity,alignment:.leading) }
                }.padding(.horizontal,20)
            }
            HStack { Text("Stored on this device").font(.caption).foregroundStyle(.secondary); Spacer(); Button("Done") { store.save(); dismiss() }.buttonStyle(StageButtonStyle(selected:true)) }.padding(20)
        }.onAppear { store.save(); store.refreshSetlists() }
        .alert("Rename Setlist",isPresented:Binding(get:{renameID != nil},set:{if !$0 {renameID=nil}})) {
            TextField("Name",text:$renameName)
            Button("Cancel",role:.cancel) { renameID=nil }
            Button("Save") { if let id=renameID { store.renameLocalSetlist(id,name:renameName) }; renameID=nil }
        }
    }
}
struct MIDILearnView: View {
    @EnvironmentObject var store: PerformanceStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        EditorFrame(title: "MIDI Learn") {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(store.deviceCount) connected MIDI source(s) · \(store.midiChannel < 0 ? "All channels" : "Channel \(store.midiChannel+1)")").font(.caption).foregroundStyle(.secondary)
                Text(store.learning == nil ? "Select a sound level, then move a hardware knob or fader." : "Move a MIDI knob or fader for Sound \(store.learning!+1)…").font(.headline)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], spacing: 12) {
                        ForEach(0..<15) { i in
                            VStack(spacing: 8) {
                                Text("Sound \(String(format: "%02d", i+1))").font(.subheadline.bold())
                                Text(store.patch.layers[i].loaded ? store.patch.layers[i].name : "Empty module").font(.caption).foregroundStyle(.secondary)
                                Button(store.learning == i ? "Listening…" : "Learn Level") { store.learning = store.learning == i ? nil : i }.buttonStyle(StageButtonStyle(selected: store.learning == i))
                                Text(store.setlist.assignments.first(where: { $0.value == i }).map { "CC \($0.key)" } ?? "Unassigned").font(.caption.monospacedDigit())
                                Button("Clear") { store.setlist.assignments = store.setlist.assignments.filter { $0.value != i }; store.save() }.font(.caption).buttonStyle(.plain)
                            }.frame(maxWidth: .infinity).padding(12).background(StageTheme.panel, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                Text("CC1 controls Tone modulation; CC64 controls sustain. Panic uses CC120/123. These controls are reserved. Button/snapshot MIDI Learn is not yet implemented.").font(.caption).foregroundStyle(.secondary)
                Button("Done") { store.learning = nil; store.save(); dismiss() }.buttonStyle(StageButtonStyle(selected: true))
            }.padding(20).onDisappear { store.learning = nil }
        }
    }
}
