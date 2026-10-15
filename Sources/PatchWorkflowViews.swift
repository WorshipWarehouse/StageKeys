import SwiftUI

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
    @EnvironmentObject private var store:PerformanceStore
    var body:some View {
        EditorFrame(title:"Tonic Pad Settings",width:600,height:360) {
            VStack(alignment:.leading,spacing:24) {
                Text("1. Warm").font(.headline)
                ChannelSlider(title:"Brightness",value:$store.tonicBrightness,range:0...1,suffix:"%")
                ChannelSlider(title:"Shimmer",value:$store.tonicShimmer,range:0...1,suffix:"%")
                Text("Changes are heard immediately. Use the pad keys and volume control on the performance page.").font(.caption).foregroundStyle(.secondary)
                Spacer()
            }.padding(28)
        }.onDisappear{store.save()}
    }
}
