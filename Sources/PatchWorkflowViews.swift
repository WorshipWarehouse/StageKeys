import SwiftUI
import UniformTypeIdentifiers

struct NewPatchEditor:View {
    @EnvironmentObject private var store:PerformanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var name:String
    let renaming:Bool
    init(initial:String="",renaming:Bool=false){_name=State(initialValue:initial);self.renaming=renaming}
    var body:some View {
        EditorFrame(title:renaming ? "Rename Patch" : "New Patch name",width:480,height:320) {
            VStack(alignment:.leading,spacing:16) {
                Text(renaming ? "Patch name" : "New Patch name").foregroundStyle(.secondary)
                HStack { TextField("Enter Patch name",text:$name).textFieldStyle(.plain).onSubmit{create()};Button{ name="" }label:{Image(systemName:"xmark")}.buttonStyle(.plain).accessibilityLabel("Clear patch name") }.padding(16).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:8))
                Spacer()
                HStack { Spacer();Button("Cancel"){dismiss()}.buttonStyle(StageButtonStyle());Button("Save"){create()}.buttonStyle(StageButtonStyle(selected:true)).disabled(name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || name.count>200 || store.patchLock) }
            }.padding(32)
        }
    }
    private func create(){guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,name.count<=200,!store.patchLock else{return};if renaming {store.renamePatch(name)} else {store.addPatch(name)};dismiss()}
}
struct PatchLibraryPicker:View {
    @EnvironmentObject private var store:PerformanceStore
    @Environment(\.dismiss) private var dismiss
    @State private var choices:[(String,Patch)]=[]
    @State private var search=""
    var body:some View {
        EditorFrame(title:"Add a Patch from the Library",width:650,height:580) {
            TextField("Search patches",text:$search).textFieldStyle(.roundedBorder).padding(20)
            ScrollView {
                VStack(spacing:8){ForEach(choices.indices,id:\.self){index in
                    let item=choices[index]
                    if search.isEmpty || item.1.name.localizedCaseInsensitiveContains(search) || item.0.localizedCaseInsensitiveContains(search) {
                        Button{store.addLibraryPatch(item.1);dismiss()}label:{HStack{VStack(alignment:.leading){Text(item.1.name);Text(item.0).font(.caption).foregroundStyle(.secondary)};Spacer();Image(systemName:"plus")}.padding(14)}.buttonStyle(.plain).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:8)).disabled(store.patchLock)
                    }
                }}.padding(.horizontal,20)
            }
            Button("Cancel"){dismiss()}.padding(20)
        }.onAppear{choices=store.availableLibraryPatches()}
    }
}
struct TonicSettingsEditor:View {
    @State private var choosing=false
    @State private var instrument:URL?
    @EnvironmentObject private var store:PerformanceStore
    var body:some View {
        EditorFrame(title:"Tonic Pad Settings",width:700,height:520) {
            ScrollView {VStack(alignment:.leading,spacing:20) {
                Menu("Pad Instrument: \(store.tonicSound?.name ?? "Built-in Warm")") {
                    Button("Built-in Warm"){store.useBuiltinTonic()}
                    ForEach(store.librarySounds.filter{$0.collection=="Tonic Pads"}){entry in
                        if let sound=entry.sound {Button(entry.name){store.setTonicInstrument(sound)}}
                    }
                }.buttonStyle(StageButtonStyle())
                HStack {
                    Picker("Pad Sound",selection:$store.tonicTimbre){ForEach(Array(store.tonicNames.enumerated()),id:\.offset){index,name in Text("\(index+1). \(name)").tag(index)}}
                    Button("Import Pad Instrument"){instrument=nil;choosing=true}.buttonStyle(StageButtonStyle())
                }
                Text(store.tonicSound == nil ? "Built-in pad · no sound library required":"Imported sampler · original looped audio").font(.caption).foregroundStyle(.secondary)
                if store.tonicSound != nil {Button("Use Built-in Pad"){store.useBuiltinTonic()}.buttonStyle(StageButtonStyle())}
                HStack(spacing:18) {
                    EffectKnob(descriptor:.init(index:0,name:"Brightness",minimum:0,maximum:1,defaultValue:0.7,unit:"%"),value:$store.tonicBrightness)
                    EffectKnob(descriptor:.init(index:1,name:"Shimmer",minimum:0,maximum:1,defaultValue:0,unit:"%"),value:$store.tonicShimmer)
                    EffectKnob(descriptor:.init(index:2,name:"Volume",minimum:-60,maximum:0,defaultValue:-10,unit:"dB"),value:Binding(get:{store.tonicGain>0 ? max(-60,20*log10(store.tonicGain)):-60},set:{store.tonicGain=$0 <= -60 ? 0:pow(10,$0/20)}))
                }
                Toggle("Patch Lock — recall these settings when this patch is selected",isOn:Binding(get:{store.tonicLocked},set:{_ in store.toggleTonicPatchLock()}))
                Text("Brightness filters the pad. Shimmer adds pitch-shifted reverb without restarting its held note. Power remembers the last key. Changes are heard immediately.").font(.caption).foregroundStyle(.secondary)
            }.padding(28)}
        }.onDisappear{store.save()}
        .fileImporter(isPresented:$choosing,allowedContentTypes:instrument == nil ? [.data]:[.folder]){result in
            switch result {
            case .success(let file):
                if let source=instrument {store.importTonicInstrument(source,samples:file);instrument=nil}
                else {instrument=file;DispatchQueue.main.async{choosing=true}}
            case .failure:instrument=nil
            }
        }

    }
}
