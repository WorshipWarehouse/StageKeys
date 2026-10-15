import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

struct EditorFrame<Content: View>: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    var width:CGFloat = 650
    var height:CGFloat = 620
    var showsHeader = true
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) {
            if showsHeader { ZStack { Text(title).font(StageTheme.font(16,weight:.bold)); HStack { Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size:18)).frame(width:30,height:30) }.buttonStyle(.plain).accessibilityLabel("Close") } }.padding(20) }
            content()
        }
        #if os(macOS)
        .frame(width:width,height:height)
        #else
        .frame(minWidth:320,idealWidth:width,minHeight:360,idealHeight:height)
        #endif
        .background(StageTheme.base)
    }
}
struct ChannelSlider: View {
    let title: String
    @Binding var value: Float
    var range: ClosedRange<Float>
    var suffix = ""
    var body: some View {
        HStack(spacing: 16) {
            Text(title).frame(width: 130, alignment: .leading)
            Slider(value: $value, in: range).accessibilityLabel(title)
            TextField(title, value: Binding(get: { suffix == "%" ? value*100 : value }, set: { if $0.isFinite { let raw=suffix == "%" ? $0/100 : $0;value = min(range.upperBound,max(range.lowerBound,raw)) } }), format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.roundedBorder).frame(width: 75)
            Text(suffix).foregroundStyle(.secondary).frame(width: 24)
        }.padding(.vertical, 6)
    }
}
struct SoundEditor: View {
    @EnvironmentObject var store: PerformanceStore
    @Environment(\.dismiss) var dismiss
    let index: Int
    @State private var draft: Layer
    @State private var tab = "FX A: Equalizer"
    @State private var plugin = false
    @State private var editingName = false
    @State private var auditionToken: UUID?
    init(index: Int, initial: Layer) { self.index = index; _draft = State(initialValue: initial); if initial.midiDestinationID != nil { _tab = State(initialValue: "Settings") } }
    private var tabs: [String] { draft.midiDestinationID != nil ? ["Settings"] : ["FX A: Equalizer", "FX B: Compressor", "Settings"] }
    var body: some View {
        EditorFrame(title: "Sound Settings", width:800, height:560, showsHeader:false) {
            HStack(spacing:12) {
                Button { store.removeSound(index); dismiss() } label: { Label("Remove Sound",systemImage:"trash") }.buttonStyle(StageButtonStyle())
                RoundedRectangle(cornerRadius:2).fill(StageTheme.colors[index]).frame(width:14,height:14)
                Button { editingName=true } label: { HStack { Text(draft.name).lineLimit(1).font(StageTheme.font(16,weight:.bold)); Image(systemName:"pencil").foregroundStyle(.secondary) } }.buttonStyle(.plain).frame(maxWidth:.infinity).accessibilityLabel("Edit Sound Name")
            }.padding(16)
            HStack(spacing:1) { ForEach(tabs,id:\.self) { name in Button { tab=name } label: { Text(name).frame(maxWidth:.infinity) }.buttonStyle(StageButtonStyle(selected:tab==name)) } }.background(StageTheme.panel,in:RoundedRectangle(cornerRadius:7)).padding(.horizontal,12)
            ScrollView {
                if tab == "FX A: Equalizer" {
                    ChannelEqualizerControls(bands:$draft.channelSettings.equalizer,enabled:$draft.channelSettings.eqEnabled).padding(.top,12).padding(.horizontal,12)
                } else if tab == "FX B: Compressor" {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:140))],spacing:8) {
                        channelKnob("Threshold",value:$draft.channelSettings.threshold,min:-60,max:0,unit:"dB")
                        if draft.external == nil { channelKnob("Ratio",value:$draft.channelSettings.ratio,min:1,max:20,unit:":1") }
                        channelKnob("Attack",value:$draft.channelSettings.compressorAttack,min:0.001,max:1,unit:"sec")
                        channelKnob("Release",value:$draft.channelSettings.compressorRelease,min:0.01,max:3,unit:"sec")
                        channelKnob("Makeup",value:$draft.channelSettings.makeup,min:0,max:24,unit:"dB")
                    }.padding(16).disabled(!draft.channelSettings.compressorEnabled)
                } else {
                    VStack(spacing:12) {
                        ScrollView(.horizontal,showsIndicators:false) { SoundSettingsControls(layer:$draft).frame(minWidth:700) }
                        if draft.importedRack != nil { ImportedRackControls(layer:$draft) }
                        DisclosureGroup("More Sound Controls") {
                            VStack(spacing:10) {
                                if draft.external?.kind == .audioUnit { Button("Open Instrument Interface") { plugin=true }.buttonStyle(StageButtonStyle()) }
                                if draft.external == nil && draft.midiDestinationID == nil {
                                    ChannelSlider(title:"Attack",value:$draft.channelSettings.attack,range:0.001...10,suffix:"sec")
                                    ChannelSlider(title:"Decay",value:$draft.channelSettings.decay,range:0.001...10,suffix:"sec")
                                    ChannelSlider(title:"Sustain",value:$draft.channelSettings.sustain,range:0...1)
                                    ChannelSlider(title:"Release",value:$draft.channelSettings.release,range:0.001...30,suffix:"sec")
                                }
                                if draft.midiDestinationID == nil {
                                    ChannelSlider(title:"Minimum Cutoff",value:$draft.channelSettings.filterMin,range:20...draft.channelSettings.filterMax,suffix:"Hz")
                                    ChannelSlider(title:"Maximum Cutoff",value:$draft.channelSettings.filterMax,range:draft.channelSettings.filterMin...20000,suffix:"Hz")
                                    ChannelSlider(title:"Resonance",value:$draft.channelSettings.resonance,range:0.1...10)
                                }
                                Stepper("Lowest note: \(draft.low)",value:$draft.low,in:0...draft.high)
                                Stepper("Highest note: \(draft.high)",value:$draft.high,in:draft.low...127)
                                if draft.external?.kind == .soundBank { Stepper("Program: \(Int(draft.external!.program)+1)",value:Binding(get:{Int(draft.external!.program)},set:{draft.external!.program=UInt8($0)}),in:0...127) }
                                if draft.midiDestinationID != nil { Stepper("Output MIDI Channel: \(draft.midiOutputChannel+1)",value:$draft.midiOutputChannel,in:0...15) }
                            }.padding(.top,12)
                        }
                    }.padding(16)
                }
            }
            HStack {
                if tab == "FX A: Equalizer" { Toggle("Effect ON",isOn:$draft.channelSettings.eqEnabled).toggleStyle(.switch) }
                if tab == "FX B: Compressor" { Toggle("Effect ON",isOn:$draft.channelSettings.compressorEnabled).toggleStyle(.switch) }
                Spacer()
                Button("Discard Changes") { dismiss() }.buttonStyle(StageButtonStyle())
                Button("Confirm") {
                    guard !draft.name.isEmpty, draft.name.count <= 200, draft.channelSettings.validate() else { store.message="Channel values are outside the supported range."; return }
                    store.confirmAudition(auditionToken,index:index,layer:draft); dismiss()
                }.buttonStyle(StageButtonStyle(selected:true))
            }.padding(16)
        }.sheet(isPresented:$plugin) { PluginInterface(index:index).environmentObject(store) }.onAppear { auditionToken=store.beginAudition(index) }.onDisappear { store.endAudition(auditionToken) }.onChange(of:draft) { layer in if let token=auditionToken { store.previewLayer(index,layer,token:token) } }.alert("Sound Name",isPresented:$editingName) { TextField("Name",text:$draft.name); Button("Done") { editingName=false } }
    }
    private func channelKnob(_ name:String,value:Binding<Float>,min:Float,max:Float,unit:String) -> some View {
        EffectKnob(descriptor:.init(index:0,name:name,minimum:min,maximum:max,defaultValue:min,unit:unit),value:value).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:8))
    }
}
struct EffectKnob: View {
    let descriptor: AudioEffectParameterDescriptor
    @Binding var value: Float
    @State private var initial: Float?
    private var logarithmic: Bool { descriptor.unit == "Hz" && descriptor.minimum > 0 && descriptor.maximum / descriptor.minimum > 100 }
    private var position: Float {
        logarithmic ? log(max(descriptor.minimum,value)/descriptor.minimum)/log(descriptor.maximum/descriptor.minimum) : (value-descriptor.minimum)/(descriptor.maximum-descriptor.minimum)
    }
    private func set(_ p: Float) {
        let unit = min(1,max(0,p))
        value = logarithmic ? descriptor.minimum * pow(descriptor.maximum/descriptor.minimum,unit) : descriptor.minimum + unit*(descriptor.maximum-descriptor.minimum)
        if descriptor.unit == "bits" || descriptor.unit == "semitones" { value = value.rounded() }
    }
    var body: some View {
        VStack(spacing: 10) {
            Text(descriptor.name).font(StageTheme.font(13,weight:.semibold)).lineLimit(2).frame(height: 32)
            ZStack {
                Circle().trim(from:0.13,to:0.87).stroke(.white.opacity(0.14),lineWidth:3).rotationEffect(.degrees(90))
                Circle().trim(from:0.13,to:0.13 + 0.74*CGFloat(position)).stroke(StageTheme.selected,lineWidth:3).rotationEffect(.degrees(90))
                Circle().fill(LinearGradient(colors:[StageTheme.raised,StageTheme.base],startPoint:.topLeading,endPoint:.bottomTrailing)).padding(7).shadow(color:.black.opacity(0.5),radius:4,y:3)
                Capsule().fill(StageTheme.selected).frame(width:3,height:16).offset(y:-23).rotationEffect(.degrees(-133+Double(position)*266))
            }.frame(width:84,height:84).contentShape(Circle())
                .gesture(DragGesture(minimumDistance:0).onChanged { v in if initial == nil { initial = position }; set(initial! - Float(v.translation.height)/180) }.onEnded { _ in initial=nil })
                .accessibilityElement().accessibilityLabel(descriptor.name).accessibilityValue("\(value) \(descriptor.unit)")
                .accessibilityAdjustableAction { set(position + ($0 == .increment ? 0.02 : -0.02)) }
            HStack(spacing:4) {
                TextField(descriptor.name,value:Binding(get:{descriptor.unit == "%" ? value*100 : value},set:{ if $0.isFinite { let raw=descriptor.unit == "%" ? $0/100 : $0; value=min(descriptor.maximum,max(descriptor.minimum,raw)) } }),format:.number.precision(.fractionLength(2))).textFieldStyle(.roundedBorder).frame(width:75)
                Text(descriptor.unit).font(StageTheme.font(10)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth:.infinity).padding(10)
    }
}
struct EffectEditor: View {
    @EnvironmentObject var store: PerformanceStore
    @Environment(\.dismiss) var dismiss
    let index: Int
    let slot: Int
    @State private var draft: AudioEffect
    @State private var replacing = false
    @State private var auditionToken: UUID?
    init(index: Int, slot: Int, initial: AudioEffect) { self.index=index; self.slot=slot; _draft=State(initialValue:initial); _replacing=State(initialValue:initial.kind==0) }
    private var imported: Bool { store.patch.layers[index].external != nil }
    private var controls: [AudioEffectParameterDescriptor] { AudioEffectCatalog.descriptors(for:draft.kind) }
    private func parameter(_ descriptor: AudioEffectParameterDescriptor) -> Binding<Float> {
        Binding(get:{ draft.values[descriptor.index] },set:{ v in var values=draft.values; values[descriptor.index]=v; draft.parameters=values })
    }
    private var equalizerBands: Binding<[EQBand]> {
        Binding(get: { (0..<8).map { EQBand(frequency:draft.values[$0*3],gain:draft.values[$0*3+1],q:draft.values[$0*3+2]) } }, set: { bands in
            guard bands.count == 8 else { return }; var values = draft.values
            for i in 0..<8 { values[i*3]=bands[i].frequency; values[i*3+1]=bands[i].gain; values[i*3+2]=bands[i].q }; draft.parameters=values
        })
    }
    var body: some View {
        EditorFrame(title: replacing ? "Select Effect" : "0\(slot+1) \(draft.title)", width:800,height:600) {
            if store.patch.layers[index].midiDestinationID != nil {
                Text("This channel sends MIDI to an external host. Configure audio effects in that host.").padding(24); Spacer()
                Button("Done") { dismiss() }.buttonStyle(StageButtonStyle()).padding()
            } else {
                HStack {
                    Button(replacing ? "Back to Effect" : "Replace Effect") { replacing.toggle() }.buttonStyle(StageButtonStyle())
                    Menu("Presets") {
                        Button("Factory Default") { draft.parameters=AudioEffectCatalog.defaults(for:draft.kind) }
                        Button("Half Mix") { var values=draft.values; for p in controls where ["Mix","Wet","Amount"].contains(p.name) { values[p.index] *= 0.5 }; draft.parameters=values }
                    }.disabled(draft.kind==0)
                    Spacer()
                    Toggle("Effect ON",isOn:$draft.enabled).toggleStyle(.switch)
                }.padding(.horizontal,20).padding(.bottom,12)
                ScrollView {
                    if replacing {
                        VStack(alignment:.leading,spacing:20) {
                            HStack(alignment:.top,spacing:12){Image(systemName:"info.circle").font(.title2);VStack(alignment:.leading,spacing:4){Text("Changes to Effects").font(.headline);Text("Confirming changes to this effect slot updates existing patch snapshots.").font(.callout)}}.padding(20).frame(maxWidth:.infinity,alignment:.leading).overlay{RoundedRectangle(cornerRadius:10).stroke(.white.opacity(0.08))}
                            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:18),count:4),spacing:14) {
                                ForEach([4,7,11,15,5,8,12,1,6,9,13,2,3,10,14],id:\.self){kind in
                                    Button { draft.kind=kind;draft.parameters=AudioEffectCatalog.defaults(for:kind);draft.enabled=true;draft.syncBeats=nil;replacing=false } label:{HStack{Text(AudioEffectCatalog.names[kind]).font(StageTheme.font(12,weight:.semibold));Spacer(minLength:4);Image(systemName:"arrow.right.circle").font(.system(size:20))}.padding(14).frame(maxWidth:.infinity,minHeight:58,alignment:.leading).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:10))}.buttonStyle(.plain)
                                }
                            }
                            Button{draft=AudioEffect();replacing=false}label:{Label("No effect",systemImage:"nosign")}.buttonStyle(StageButtonStyle())
                        }.padding(28)
                    } else {
                        if draft.kind==3 { subdivision }
                        if draft.kind==2 {
                            Picker("Frequency",selection:Binding(get:{draft.syncBeats != nil},set:{draft.syncBeats = $0 ? 0.5 : nil})) { Text("Hz").tag(false); Text("Tempo").tag(true) }.pickerStyle(.segmented).padding(.horizontal,20)
                            if draft.syncBeats != nil { subdivision }
                        }
                        if draft.kind==14 {
                            Picker("Rotor Speed",selection:Binding(get:{Int(draft.values[0])},set:{var values=draft.values;values[0]=Float($0);draft.parameters=values})) { Text("Brake").tag(0); Text("Slow").tag(1); Text("Fast").tag(2) }.pickerStyle(.segmented).padding(.horizontal,20)
                        }
                        if draft.kind == 7 {
                            ChannelEqualizerControls(bands:equalizerBands,enabled:$draft.enabled).padding(.top,12)
                        } else { LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:10),count:3),spacing:15) {
                            ForEach(controls.filter { !(draft.kind==3 && $0.index==1) && !(draft.kind==2 && draft.syncBeats != nil && $0.index==1) && !(draft.kind==14 && $0.index==0) }) { descriptor in
                                EffectKnob(descriptor:descriptor,value:parameter(descriptor))
                            }
                        }.padding(20) }
                    }
                }
                HStack { Button("Discard Changes") { dismiss() }; Spacer(); Button("Confirm") { var layer=store.patch.layers[index];layer.effects[slot]=draft;store.confirmAudition(auditionToken,index:index,layer:layer);dismiss() }.buttonStyle(StageButtonStyle(selected:true)) }.padding(16)
            }
        }.onAppear { auditionToken=store.beginAudition(index) }.onDisappear { store.endAudition(auditionToken) }.onChange(of:draft) { effect in
            if let token=auditionToken { var layer=store.patch.layers[index]; layer.effects[slot]=effect; store.previewLayer(index,layer,token:token) }
        }
    }
    private var subdivision: some View {
        HStack(spacing:5) {
            Text("Subdivision").font(StageTheme.font(12)); Spacer()
            ForEach([Float(1),0.75,0.5,0.25,0.125],id:\.self) { beats in
                Button([Float(1):"1/4",0.75:"1/8 ·",0.5:"1/8",0.25:"1/16",0.125:"1/32"][beats]!) {
                    if draft.kind==2 { draft.syncBeats=beats }
                    else { var values=draft.values;values[1]=beats;draft.parameters=values }
                }.buttonStyle(StageButtonStyle(selected:(draft.kind==2 ? draft.syncBeats : draft.values[1])==beats))
            }
        }.padding(.horizontal,20).padding(.vertical,10)
    }
}
struct PatchEditor: View {
    @EnvironmentObject var store: PerformanceStore
    var body: some View {
        EditorFrame(title:"Patch Settings",width:800,height:550) {
            ScrollView {
                VStack(spacing:16) {
                    row("Patch Volume Adjustments","Increase/decrease the overall volume of the entire Patch. Useful to quickly balance the volume of all the Patches in your Setlist.") {
                        HStack { Button("−"){store.setPatchVolume(store.patch.volumeDB-1)}.accessibilityLabel("Decrease patch volume");Text(String(format:"%.0f dB",store.patch.volumeDB)).frame(width:64);Button("+"){store.setPatchVolume(store.patch.volumeDB+1)}.accessibilityLabel("Increase patch volume") }.buttonStyle(StageButtonStyle())
                    }
                    row("Instantly Silence Previous Patch","") { Toggle("Instantly Silence Previous Patch",isOn:$store.setlist.patches[store.selected].silencePrevious).labelsHidden().toggleStyle(.switch) }
                    row("Respond to Program Change","Set a MIDI Program Change number for this Patch") {
                        VStack {
                            Toggle("Respond to Program Change",isOn:Binding(get:{store.patch.programChangeEnabled ?? true},set:{store.setlist.patches[store.selected].programChangeEnabled=$0;if $0 && store.patch.programChangeNumber == nil {store.setlist.patches[store.selected].programChangeNumber=store.selected}})).labelsHidden().toggleStyle(.switch)
                            if store.patch.programChangeEnabled != false { Stepper("\((store.patch.programChangeNumber ?? store.selected)+1)",value:Binding(get:{store.patch.programChangeNumber ?? store.selected},set:{store.setlist.patches[store.selected].programChangeEnabled=true;store.setlist.patches[store.selected].programChangeNumber=$0}),in:0...127) }
                        }.frame(width:145)
                    }
                    row("Visual state when Patch is selected","Have this Patch recall a specific visual state when it is selected") {
                        Picker("Visual state",selection:$store.setlist.patches[store.selected].visualMode){Text("Don't change").tag(0);Text("Show Effects").tag(1);Text("Show Notes").tag(2)}.pickerStyle(.segmented).labelsHidden().frame(width:335)
                    }
                }.padding(32)
            }
        }.onDisappear{store.save()}
    }
    private func row<Content:View>(_ title:String,_ description:String,@ViewBuilder content:()->Content)->some View {
        HStack(spacing:20){VStack(alignment:.leading,spacing:6){Text(title).font(StageTheme.font(15,weight:.semibold));if !description.isEmpty {Text(description).font(StageTheme.font(12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}};Spacer();content()}.padding(16).frame(minHeight:80).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:8))
    }
}
struct TransposeEditor: View {
    @EnvironmentObject var store: PerformanceStore
    var body: some View {
        EditorFrame(title: "Transpose") {
            ScrollView {
                VStack(spacing: 24) {
                    HStack(alignment: .top, spacing: 15) { keyGrid("Play In", play: true); keyGrid("Hear In", play: false) }
                    Stepper("Total transpose: \(store.patch.transpose) semitones", value: Binding(get: { store.patch.transpose }, set: { store.setTranspose($0) }), in: -24...24)
                    Text("Play In and Hear In apply to the selected patch. The total transpose control can add or subtract octaves.").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.onDisappear { store.save() }
        }
    }
    private func keyGrid(_ title: String, play: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 3), spacing: 4) {
                ForEach(0..<12) { key in Button(StageTheme.notes[key]) { store.transpose(play: play ? key : store.patch.playIn, hear: play ? store.patch.hearIn : key) }.buttonStyle(StageButtonStyle(selected: (play ? store.patch.playIn : store.patch.hearIn) == key)) }
            }
        }
    }
}
struct TempoEditor: View {
    @EnvironmentObject var store: PerformanceStore
    var body: some View {
        EditorFrame(title: "Tempo") {
            VStack(spacing: 25) {
                Button("TAP TEMPO") { store.tapTempo() }.font(.title).frame(maxWidth: .infinity).frame(height: 150).background(StageTheme.raised, in: RoundedRectangle(cornerRadius: 10)).buttonStyle(.plain)
                Stepper("\(Int(store.patch.tempo)) BPM", value: Binding(get: { store.patch.tempo }, set: { store.updateTempo($0) }), in: 20...300)
                Toggle("Metronome", isOn: $store.metronome)
                Text("4/4 · The click follows this patch’s tempo.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(25).onDisappear { store.save() }
        }
    }
}
struct SnapshotEditor: View {
    @EnvironmentObject var store: PerformanceStore
    @Environment(\.dismiss) var dismiss
    let index: Int
    @State private var draft: Snapshot
    @State private var custom: Bool
    @State private var beatMode: Bool
    init(index: Int, initial: Snapshot) {
        self.index = index; _draft = State(initialValue: initial)
        _custom = State(initialValue: initial.seconds != nil || initial.beats != nil)
        _beatMode = State(initialValue: initial.beats != nil)
    }
    var body: some View {
        EditorFrame(title: "Snapshot · Customize") {
            Form {
                TextField("Name", text: $draft.name)
                Toggle("Use Custom Transition", isOn: $custom)
                if custom {
                    Picker("Measure transition in", selection: $beatMode) { Text("Time").tag(false); Text("Beats").tag(true) }.pickerStyle(.segmented)
                    if beatMode { Stepper("\(draft.beats ?? 4, specifier: "%.1f") beats", value: Binding(get: { draft.beats ?? 4 }, set: { draft.beats = $0 }), in: 0.25...32, step: 0.25) }
                    else { Slider(value: Binding(get: { draft.seconds ?? store.transition }, set: { draft.seconds = $0 }), in: 0...15); Text("\(draft.seconds ?? store.transition, specifier: "%.1f") seconds") }
                }
                Section("Snapshot Note") { TextEditor(text: Binding(get: { draft.noteText }, set: { draft.note = $0 })).frame(minHeight: 100) }
                Text("Captured snapshots store levels, effect parameters, MIDI effect state, pan, tonic and modulation. Replacing an effect updates that slot across existing snapshots.").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped)
            HStack {
                Button("Discard Changes") { dismiss() }; Spacer()
                Button("Confirm") {
                    if !custom { draft.seconds = nil; draft.beats = nil }
                    else if beatMode { draft.beats = draft.beats ?? 4; draft.seconds = nil }
                    else { draft.seconds = draft.seconds ?? store.transition; draft.beats = nil }
                    store.setlist.patches[store.selected].snapshots[index] = draft; store.save(); dismiss()
                }.buttonStyle(StageButtonStyle(selected: true))
            }.padding(16)
        }
    }
}

struct MIDIEffectEditor: View {
    @EnvironmentObject var store: PerformanceStore
    @Environment(\.dismiss) var dismiss
    let index:Int
    @State private var program=MIDIProgram()
    @State private var enabled=true
    @State private var mapping=0
    @State private var step=0
    @State private var auditionToken: UUID?
    private var chord: Bool { program.kind == .easyChord }
    private var mappingsCount:Int { chord ? (program.chordMappings?.count ?? 0) : (program.sequenceMappings?.count ?? 0) }
    private var sequenceSteps:[MIDISequenceStep] { guard let maps=program.sequenceMappings,maps.indices.contains(mapping) else { return [] };return maps[mapping].steps }
    var body:some View {
        EditorFrame(title:program.kind.title) {
            HStack {
                Menu("Replace Effect") { ForEach(MIDIFXKind.allCases,id:\.self) { kind in Button(kind.title) { select(kind) } } }
                Spacer();Toggle("Effect ON",isOn:$enabled).toggleStyle(.switch)
            }.padding(20)
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    if program.kind == .arpeggiator || program.kind == .sequencer { rateControls }
                    if program.kind == .arpeggiator { arpControls }
                    if program.kind == .octaveUp {
                        Text("Blend controls the velocity of the additional octave note.").font(.caption)
                        ChannelSlider(title:"Blend",value:Binding(get:{program.octaveBlend ?? 1},set:{program.octaveBlend=$0}),range:0...1,suffix:"%")
                    }
                    if chord || program.kind == .sequencer { mappingControls }
                }.padding(20)
            }
            HStack { Button("Discard Changes") { dismiss() };Spacer();Button("Confirm") { var l=store.patch.layers[index];l.midiProgram=program.validated;l.midiEffectEnabled=enabled;l.octaveEffect=false;store.confirmAudition(auditionToken,index:index,layer:l);dismiss() }.buttonStyle(StageButtonStyle(selected:true)) }.padding(16)
        }.onAppear { program=store.patch.layers[index].midiProgram ?? MIDIProgram();enabled=store.patch.layers[index].midiEffectEnabled; auditionToken=store.beginAudition(index) }.onDisappear { store.endAudition(auditionToken) }.onChange(of:program) { _ in preview() }.onChange(of:enabled) { _ in preview() }
    }
    private func preview() { if let token=auditionToken { var layer=store.patch.layers[index]; layer.midiProgram=program.validated; layer.midiEffectEnabled=enabled; layer.octaveEffect=false; store.previewLayer(index,layer,token:token) } }
    private func select(_ kind:MIDIFXKind) {
        program=MIDIProgram();program.kind=kind;program.subdivision=0.5;mapping=0;step=0
        if kind == .arpeggiator { program.arpVelocities=Array(repeating:1,count:16) }
        if kind == .easyChord { program.chordMappings=[MIDIChordMapping(input:60,output:[60,64,67])] }
        if kind == .sequencer { program.sequenceMappings=[MIDISequenceMapping(input:60,steps:Array(repeating:MIDISequenceStep(pitch:60),count:16))] }
    }
    private var rateControls:some View {
        VStack(spacing:12) {
            Toggle("Tempo Sync",isOn:Binding(get:{program.freeRateSeconds == nil},set:{program.freeRateSeconds=$0 ? nil:0.1}))
            if program.freeRateSeconds == nil {
                Picker("Subdivision",selection:$program.subdivision) {
                    ForEach([128,96,64,48,32,24,16,12,8,6,4,3,2,1],id:\.self) { division in Text("1/\(division)").tag(4.0/Double(division)) }
                }
            } else {
                HStack {Text("Rate");Slider(value:Binding(get:{program.freeRateSeconds ?? 0.1},set:{program.freeRateSeconds=$0}),in:0.01...1);Text("\(Int((program.freeRateSeconds ?? 0.1)*1000)) ms").monospacedDigit()}
            }
            HStack { Text("Gate");Slider(value:$program.gate,in:0.01...2);Text("\(Int(program.gate*100)) %").monospacedDigit() }
            if program.kind == .arpeggiator {
                Picker("Groove",selection:Binding(get:{program.swingGridBeats == 0.5 ? 1:program.swingGridBeats == 0.25 ? 2:program.swingGridBeats == 0.125 ? 3:0},set:{value in program.swingGridBeats=value==0 ? nil:[0.5,0.25,0.125][value-1];program.swingAmount=program.swingAmount ?? 0})) {Text("Straight").tag(0);Text("Swing 8").tag(1);Text("Swing 16").tag(2);Text("Swing 32").tag(3)}
                if program.swingGridBeats != nil {HStack{Text("Swing Amount");Slider(value:Binding(get:{program.swingAmount ?? 0},set:{program.swingAmount=$0}),in:0...1);Text("\(Int((program.swingAmount ?? 0)*100)) %")}}
                Toggle("Hold",isOn:Binding(get:{program.hold ?? false},set:{program.hold=$0}))
                Toggle("Retrigger on Note",isOn:Binding(get:{program.retriggerOnNote ?? false},set:{program.retriggerOnNote=$0}))
                DisclosureGroup("Pattern Controls") {
                    Stepper("Offset: \(program.patternOffset ?? 0)",value:Binding(get:{program.patternOffset ?? 0},set:{program.patternOffset=$0}),in:0...127)
                    Toggle("Infinite Repeats",isOn:Binding(get:{program.repeatCount == nil},set:{program.repeatCount=$0 ? nil:1}))
                    if program.repeatCount != nil {Stepper("Repeats: \(program.repeatCount ?? 1)",value:Binding(get:{program.repeatCount ?? 1},set:{program.repeatCount=$0}),in:1...128)}
                    Toggle("Beat Retrigger",isOn:Binding(get:{program.retriggerBeats != nil},set:{program.retriggerBeats=$0 ? 4:nil}))
                    if program.retriggerBeats != nil {HStack{Text("Retrigger Beats");Slider(value:Binding(get:{program.retriggerBeats ?? 4},set:{program.retriggerBeats=$0}),in:0.03125...128);Text("\(program.retriggerBeats ?? 4,specifier:"%.2f")")}}
                    Toggle("Velocity Decay",isOn:Binding(get:{program.velocityTarget != nil},set:{program.velocityTarget=$0 ? 0.5:nil;program.velocityDecaySeconds=$0 ? 1:nil}))
                    if program.velocityTarget != nil {
                        ChannelSlider(title:"Target Velocity",value:Binding(get:{program.velocityTarget ?? 0.5},set:{program.velocityTarget=$0}),range:0...1)
                        HStack{Text("Decay Seconds");Slider(value:Binding(get:{program.velocityDecaySeconds ?? 1},set:{program.velocityDecaySeconds=$0}),in:0.001...60);Text("\(program.velocityDecaySeconds ?? 1,specifier:"%.2f")")}
                        Toggle("Retrigger Velocity",isOn:Binding(get:{program.retriggerVelocity ?? false},set:{program.retriggerVelocity=$0}))
                    }
                    Stepper("Transpose Steps: \(program.transposeSteps ?? 0)",value:Binding(get:{program.transposeSteps ?? 0},set:{program.transposeSteps=$0}),in:0...8)
                    Stepper("Transpose Distance: \(program.transposeDistance ?? 12)",value:Binding(get:{program.transposeDistance ?? 12},set:{program.transposeDistance=$0}),in:-48...48)
                }
            }
        }
    }
    private var arpControls:some View {
        VStack(alignment:.leading,spacing:18) {
            Picker("Style",selection:$program.style) { ForEach(MIDIArpStyle.allCases,id:\.self) { style in Text(style.title).tag(style) } }
            Stepper("Octaves: \(program.octaves)",value:$program.octaves,in:1...4)
            Stepper("Steps: \(program.arpVelocities?.count ?? 16)",value:Binding(get:{program.arpVelocities?.count ?? 16},set:{count in var values=program.arpVelocities ?? Array(repeating:1,count:16);if count>values.count {values += Array(repeating:1,count:count-values.count)} else {values=Array(values.prefix(count))};program.arpVelocities=values}),in:1...128)
            ScrollView(.horizontal) {
                HStack(spacing:8) { ForEach(0..<(program.arpVelocities?.count ?? 16),id:\.self) { i in
                    VStack { Text("\(i+1)");VerticalFader(gain:Binding(get:{program.arpVelocities?[i] ?? 1},set:{var values=program.arpVelocities ?? Array(repeating:1,count:16);values[i]=$0;program.arpVelocities=values}),color:StageTheme.selected,label:"Step \(i+1) velocity",decibels:false).frame(width:32,height:110);Text("\(Int((program.arpVelocities?[i] ?? 1)*100))").font(.caption) }
                } }
            }
        }
    }
    @ViewBuilder private var mappingControls:some View {
        if chord && program.chordMappings == nil {
            Picker("Chord",selection:$program.chordIntervals) {Text("Major").tag([0,4,7]);Text("Minor").tag([0,3,7]);Text("Power").tag([0,7,12]);Text("Octaves").tag([0,12])}
            Button("Use Input → Output Mappings") {program.chordMappings=[MIDIChordMapping(input:60,output:program.chordIntervals.map{60+$0})]}
        } else if !chord && program.sequenceMappings == nil {
            ForEach(program.steps.indices,id:\.self) { i in HStack {Toggle("Step \(i+1)",isOn:$program.steps[i].enabled);Stepper("\(program.steps[i].pitch) st",value:$program.steps[i].pitch,in:-48...48)} }
            Button("Use Input → Output Mappings") {program.sequenceMappings=[MIDISequenceMapping(input:60,steps:program.steps.map{MIDISequenceStep(pitch:min(127,max(0,60+$0.pitch)),velocity:$0.velocity,enabled:$0.enabled)})]}
        } else {
            HStack { Text("Input → Output").font(StageTheme.font(17,weight:.bold));Spacer();Button(chord ? "Add Chord" : "Add Sequence") { addMapping() }.disabled(mappingsCount>=128) }
            if mappingsCount>0 {
                ScrollView(.horizontal) { HStack {ForEach(0..<mappingsCount,id:\.self) { i in Button("\(i+1)") {mapping=i;step=0}.buttonStyle(StageButtonStyle(selected:mapping==i))}} }
                Stepper("Input: \(mappedInput + 1) · \(noteName(mappedInput))",value:Binding(get:{mappedInput},set:{value in if chord {guard !program.chordMappings!.enumerated().contains(where:{$0.offset != mapping && $0.element.input==value}) else {return};program.chordMappings![mapping].input=value} else {guard !program.sequenceMappings!.enumerated().contains(where:{$0.offset != mapping && $0.element.input==value}) else {return};program.sequenceMappings![mapping].input=value}}),in:0...127)
                Button("Delete Mapping",role:.destructive) {if chord {program.chordMappings!.remove(at:mapping)} else {program.sequenceMappings!.remove(at:mapping)};mapping=max(0,min(mapping,mappingsCount-1));step=0}
                if !chord { sequenceControls }
                noteGrid
            }
        }
    }
    private var mappedInput:Int {
        if chord,let maps=program.chordMappings,maps.indices.contains(mapping) {return maps[mapping].input}
        if let maps=program.sequenceMappings,maps.indices.contains(mapping) {return maps[mapping].input}
        return 60
    }
    private func addMapping() {
        let used = chord ? Set(program.chordMappings?.map(\.input) ?? []) : Set(program.sequenceMappings?.map(\.input) ?? [])
        guard let note=(0...127).first(where:{!used.contains($0)}) else {return}
        if chord {program.chordMappings!.append(MIDIChordMapping(input:note,output:[note]))}
        else {program.sequenceMappings!.append(MIDISequenceMapping(input:note,steps:Array(repeating:MIDISequenceStep(pitch:note),count:16)))}
        mapping=mappingsCount-1;step=0
    }
    private var sequenceControls:some View {
        VStack(alignment:.leading,spacing:15) {
            ChannelSlider(title:"Velocity",value:Binding(get:{program.sequenceVelocity ?? 1},set:{program.sequenceVelocity=$0}),range:0...1,suffix:"%")
            Stepper("Steps: \(sequenceSteps.count)",value:Binding(get:{sequenceSteps.count},set:{count in var steps=sequenceSteps;if count>steps.count {steps += Array(repeating:MIDISequenceStep(pitch:mappedInput),count:count-steps.count)} else {steps=Array(steps.prefix(count))};program.sequenceMappings![mapping].steps=steps;step=min(step,max(0,count-1))}),in:1...128)
            ScrollView(.horizontal) { HStack(spacing:7) {ForEach(sequenceSteps.indices,id:\.self) { i in
                Button {step=i} label:{VStack(spacing:6) {Text("\(i+1)");Text(sequenceSteps[i].enabled ? noteName(sequenceSteps[i].pitch) : "Rest").font(.caption);Text("\(Int(sequenceSteps[i].velocity*100)) %").font(.caption2)}}.buttonStyle(StageButtonStyle(selected:step==i))
            }} }
            if sequenceSteps.indices.contains(step) {
                Toggle("Step \(step+1) On",isOn:Binding(get:{sequenceSteps[step].enabled},set:{program.sequenceMappings![mapping].steps[step].enabled=$0}))
                ChannelSlider(title:"Step Velocity",value:Binding(get:{sequenceSteps[step].velocity},set:{program.sequenceMappings![mapping].steps[step].velocity=$0}),range:0...1,suffix:"%")
                HStack {Button("Move Left") {program.sequenceMappings![mapping].steps.swapAt(step,step-1);step-=1}.disabled(step==0);Button("Move Right") {program.sequenceMappings![mapping].steps.swapAt(step,step+1);step+=1}.disabled(step>=sequenceSteps.count-1)}
            }
        }
    }
    private var noteGrid:some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:3),count:16),spacing:3) {
            ForEach(0...127,id:\.self) { note in
                let selected=chord ? (program.chordMappings?[mapping].output.contains(note) ?? false) : (sequenceSteps.indices.contains(step) && sequenceSteps[step].pitch==note)
                Button("\(note+1)") {
                    if chord {var notes=program.chordMappings![mapping].output;if notes.contains(note) {notes.removeAll{$0==note}} else {notes.append(note)};program.chordMappings![mapping].output=notes.sorted()}
                    else if sequenceSteps.indices.contains(step) {program.sequenceMappings![mapping].steps[step].pitch=note}
                }.font(StageTheme.font(10)).frame(maxWidth:.infinity).frame(height:24).buttonStyle(.plain).background(selected ? StageTheme.selected : StageTheme.raised,in:RoundedRectangle(cornerRadius:3)).foregroundStyle(selected ? StageTheme.base : .white).accessibilityLabel("Output note \(noteName(note))")
            }
        }
    }
    private func noteName(_ note:Int)->String { "\(StageTheme.notes[note%12])\(note/12-1)" }
}
extension MIDIArpStyle {
    var title:String {switch self {case .up:return "Up";case .down:return "Down";case .upDown:return "Up-Down";case .downUp:return "Down-Up";case .random:return "Random";case .chord:return "Chord";case .asPlayed:return "As Played"}}
}
extension MIDIFXKind {
    var title: String { switch self { case .bypass: return "No Effect"; case .arpeggiator: return "Arpeggiator"; case .easyChord: return "Easy Chord"; case .octaveUp: return "Octave Up"; case .sequencer: return "Sequencer" } }
}

struct SnapshotNoteEditor: View {
    @EnvironmentObject var store: PerformanceStore
    @Environment(\.dismiss) var dismiss
    let index: Int
    @State var draft: Snapshot
    init(index: Int, initial: Snapshot) { self.index = index; _draft = State(initialValue: initial) }
    var body: some View {
        EditorFrame(title: "Snapshot Note · Five Lines",height:360) {
            Picker("Alignment", selection: Binding(get: { draft.alignment ?? 0 }, set: { draft.alignment = $0 })) { Text("Left").tag(0); Text("Center").tag(1); Text("Right").tag(2) }.pickerStyle(.segmented).padding(.horizontal,20)
            TextEditor(text: Binding(get: { draft.noteText }, set: { draft.note = $0.components(separatedBy: "\n").prefix(5).joined(separator: "\n") })).font(StageTheme.font(22)).padding(20).frame(minHeight: 150)
            HStack { Button("Discard Changes") { dismiss() }; Spacer(); Button("Confirm") { store.setlist.patches[store.selected].snapshots[index] = draft; store.save(); dismiss() }.buttonStyle(StageButtonStyle(selected: true)) }.padding(20)
        }
    }
}
