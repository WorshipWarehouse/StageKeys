import SwiftUI

struct SoundBrowser: View {
    @EnvironmentObject private var store:PerformanceStore
    @Environment(\.dismiss) private var dismiss
    let index:Int
    @State private var collection="All Sounds"
    @State private var query=LibraryQuery()
    @State private var facets:[LibraryFacet]=[.category,.type,.timbre,.articulation]
    @State private var selectedID:String?
    @State private var importHub=false
    @State private var showingImportNotes=false
    @State private var auditionToken:UUID?
    @State private var instruments=ExternalInstrumentRack.instruments()
    @State private var destinations=ExternalMIDIOutput.destinations()
    private var collections:[String] {
        let builtins=["All Sounds","StageKeys","My Sounds","Sunday Free","Sunday App","MainStage Archive","Audio Units","External MIDI"]
        return builtins + Set(store.librarySounds.map(\.collection)).subtracting(builtins).sorted{$0.localizedStandardCompare($1) == .orderedAscending}
    }
    private var sounds:[BrowserSound] {
        var result=["Soft Keys","Warm Pad","Glass Bells"].enumerated().map {i,name in BrowserSound(id:"builtin-\(i)",name:name,collection:"StageKeys",tags:.inferred(name:name,source:"StageKeys Synth"),builtin:i)}
        let entries=store.librarySounds
        result += entries.map {entry in
            if collection == "MainStage Archive",entry.hostPath != nil,
               let converted=entries.first(where:{$0.sourceArchiveID == entry.id && ($0.sound != nil || $0.layer != nil)}) {
                var browser=BrowserSound.library(converted)
                browser=BrowserSound(id:entry.id,name:entry.name,collection:entry.collection,tags:entry.tags ?? browser.tags,entry:converted)
                return browser
            }
            return BrowserSound.library(entry)
        }
        result += instruments.map{BrowserSound(id:"au-\($0.id)",name:$0.name,collection:"Audio Units",tags:.init(category:"Instruments",type:"Audio Unit",sourceModel:"Audio Unit"),external:ExternalSound(kind:.audioUnit,name:$0.name,component:$0))}
        result += destinations.map{BrowserSound(id:"midi-\($0.id)",name:$0.name,collection:"External MIDI",tags:.init(category:"External MIDI",type:"MIDI Destination",sourceModel:"External MIDI"),destination:$0)}
        return result.filter {sound in
            switch collection {
            case "All Sounds":return sound.playable && sound.destination == nil
            case "MainStage Archive":return entries.contains(where:{$0.id == sound.id && $0.hostPath != nil})
            case "Sunday Free":return sound.collection.hasPrefix("Sunday Free") && sound.playable
            case "Sunday App":return sound.collection.hasPrefix("Sunday App")
            default:return sound.collection == collection && sound.playable
            }
        }
    }
    private let selectionColor=Color(red:0.49,green:0.61,blue:0.82)
    private var results:[BrowserSound] {query.results(sounds)}
    private var selection:BrowserSound? {results.first{$0.id == selectedID}}
    var body:some View {
        EditorFrame(title:"Library",width:960,height:650,showsHeader:false) {
            header
            GeometryReader {geometry in
                ScrollView(.horizontal) {
                    HStack(spacing:0) {
                        ForEach(Array(facets.enumerated()),id:\.offset) {offset,facet in
                            facetColumn(facet,offset:offset).frame(width:max(135,(geometry.size.width-315)/4))
                            Rectangle().fill(Color.black.opacity(0.25)).frame(width:1)
                        }
                        resultColumn.frame(width:310)
                    }.frame(minWidth:geometry.size.width)
                }
            }
            footer
        }.sheet(isPresented:$importHub){SoundImportView().environmentObject(store)}
        .onDisappear {store.endAudition(auditionToken);store.previewLibraryRange(index,nil)}
        .onChange(of:selectedID){_ in previewRange();if auditionToken != nil {auditionSelection()}}
        .onChange(of:collection){_ in selectedID=nil;query.filters=[:]}
        .onChange(of:query.search){_ in clearHiddenSelection()}
        .onChange(of:query.filters){_ in clearHiddenSelection()}
        .onChange(of:store.librarySounds){_ in if collection == "My Sounds" {clearHiddenSelection()}}
    }
    private var header:some View {
        HStack(spacing:16) {
            Text("Library")
            LibraryChoiceMenu(title:collection,choices:collections,accessibility:"Sound collection: \(collection)"){collection=$0}.frame(width:235)
            Spacer(minLength:0)
            HStack(spacing:5){RoundedRectangle(cornerRadius:2).fill(StageTheme.colors[index % StageTheme.colors.count]).frame(width:15,height:15);Text("Add Sound to Module \(index+1)").font(StageTheme.font(15,weight:.bold))}
            Spacer(minLength:0)
            HStack{Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField("Search",text:$query.search).textFieldStyle(.plain).accessibilityLabel("Search sounds")}.padding(14).frame(width:250).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:8))
            Button{importHub=true}label:{Image(systemName:"plus.circle").font(.title2)}.buttonStyle(.plain).accessibilityLabel("Import Sounds").help("Import sounds into My Sounds")
        }.padding(16).frame(height:78).background(StageTheme.base)
    }
    private func facetColumn(_ facet:LibraryFacet,offset:Int)->some View {
        VStack(spacing:0) {
            LibraryChoiceMenu(title:facet.rawValue,choices:LibraryFacet.allCases.map(\.rawValue),accessibility:"Filter column \(offset+1): \(facet.rawValue)"){name in
                guard let item=LibraryFacet(rawValue:name) else{return}
                if let other=facets.firstIndex(of:item),other != offset {facets[other]=facet} else if item != facet {query.filters[facet]=nil};facets[offset]=item;clearHiddenSelection()
            }.padding(8).frame(height:70)
            ScrollView {
                LazyVStack(alignment:.leading,spacing:2) {
                    ForEach(query.options(facet,in:sounds),id:\.self){value in
                        Button{query.filters[facet]=value;clearHiddenSelection()}label:{Text(value).font(StageTheme.font(16)).fontWeight(.regular).multilineTextAlignment(.leading).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,12).padding(.vertical,14).background((query.filters[facet] ?? "All") == value ? selectionColor : .clear,in:RoundedRectangle(cornerRadius:7)).foregroundStyle((query.filters[facet] ?? "All") == value ? .white : .white.opacity(0.85))}.buttonStyle(.plain).accessibilityLabel("\(facet.rawValue): \(value)")
                    }
                }.padding(.horizontal,8)
            }
        }.background(StageTheme.panel)
    }
    private var resultColumn:some View {
        VStack(spacing:0) {
            HStack(spacing:8) {
                Text("Order by").font(StageTheme.font(12))
                LibraryChoiceMenu(title:query.sort?.rawValue ?? "Name",choices:["Name"]+[LibraryFacet.category,.type,.library,.source,.availability].map(\.rawValue),accessibility:"Order by \(query.sort?.rawValue ?? "Name")"){query.sort=LibraryFacet(rawValue:$0)}
                Button{query.ascending.toggle()}label:{Image(systemName:query.ascending ? "arrow.down.to.line" : "arrow.up.to.line").frame(width:30,height:42)}.buttonStyle(.plain).accessibilityLabel(query.ascending ? "Sort descending" : "Sort ascending")
            }.padding(8).frame(height:70)
            ScrollView {
                LazyVStack(spacing:2) {
                    ForEach(results){sound in
                        Button{selectedID=sound.id}label:{HStack(spacing:8){VStack(alignment:.leading,spacing:5){Text(sound.name).font(StageTheme.font(16)).fontWeight(.regular).multilineTextAlignment(.leading);if collection == "MainStage Archive" {Text(sound.playable ? "Playable" : "Needs Conversion").font(StageTheme.font(11)).foregroundStyle(.secondary)}}.frame(maxWidth:.infinity,alignment:.leading)}.padding(.horizontal,14).padding(.vertical,13).background(selectedID == sound.id ? selectionColor : .clear,in:RoundedRectangle(cornerRadius:7)).foregroundStyle(selectedID == sound.id ? .white : .white.opacity(0.85))}.buttonStyle(.plain).accessibilityLabel("\(sound.name), \(sound.playable ? "Playable" : "Needs Conversion")")
                    }
                    if results.isEmpty {
                        VStack(spacing:14) {
                            Image(systemName:"tray.and.arrow.down").font(.system(size:38)).foregroundStyle(StageTheme.selected)
                            Text("No Sounds found").font(StageTheme.font(17,weight:.semibold))
                            Text(collection == "My Sounds" && query.search.isEmpty && query.filters.isEmpty ? "Import a sound or save a module to My Sounds to add it to any patch later." : "Change the search or filters to find more sounds.").multilineTextAlignment(.center).foregroundStyle(.secondary)
                            if !query.search.isEmpty || !query.filters.isEmpty {Button("Clear Filters"){query.filters=[:];query.search=""}}
                            Button("Import Sounds"){importHub=true}.buttonStyle(StageButtonStyle())
                        }.frame(maxWidth:.infinity).padding(24)
                    }
                }.padding(.horizontal,6)
            }
        }.background(StageTheme.panel)
    }
    private var footer:some View {
        HStack(spacing:16) {
            VStack(alignment:.leading,spacing:4) {
                if let selection {
                    Text(selection.collection).lineLimit(1)
                    if !selection.playable {Text("This original MainStage patch needs a sampled conversion before it can play here.").foregroundStyle(.secondary)}
                } else {Text("\(results.count) sounds").foregroundStyle(.secondary)}
            }.font(StageTheme.font(12)).frame(maxWidth:.infinity,alignment:.leading)
            if selection?.entry?.conversionNotes?.isEmpty == false {Button("Import Notes"){showingImportNotes=true}.buttonStyle(StageButtonStyle()).popover(isPresented:$showingImportNotes){ScrollView{VStack(alignment:.leading,spacing:12){ForEach(selection?.entry?.conversionNotes ?? [],id:\.self){Text($0)}}.padding(20)}.frame(width:420,height:300)}}
            if collection == "External MIDI" {Button("Refresh"){destinations=ExternalMIDIOutput.destinations()}.buttonStyle(StageButtonStyle())}
            Button(auditionToken == nil ? "Audition":"Stop Audition") {
                if let token=auditionToken {store.endAudition(token);auditionToken=nil} else {auditionSelection()}
            }.buttonStyle(StageButtonStyle(selected:auditionToken != nil)).disabled(selection?.playable != true && auditionToken == nil).help("Play your keyboard to hear only the selected sound; Cancel restores the original mix")
            Button("Cancel"){dismiss()}.buttonStyle(LibraryActionStyle())
            Button("Add Sound"){addSelection()}.buttonStyle(LibraryActionStyle(primary:true)).disabled(selection?.playable != true)
        }.padding(16).frame(height:78)
    }
    private func auditionSelection() {
        store.endAudition(auditionToken);auditionToken=nil
        guard let selection,selection.playable,selection.destination == nil else{return}
        var layer=selection.entry?.layer ?? Layer(name:selection.name,instrument:selection.builtin ?? -1,gain:0.6)
        layer.external=layer.external ?? selection.entry?.sound ?? selection.external
        auditionToken=store.auditionLibrarySound(index,layer)
    }
    private func previewRange() {
        guard let selection,selection.playable else{store.previewLibraryRange(index,nil);return}
        var preview=selection.entry?.layer ?? Layer(name:selection.name,instrument:selection.builtin ?? -1,gain:0.5)
        preview.external=preview.external ?? selection.entry?.sound ?? selection.external
        preview.midiDestinationID=preview.midiDestinationID ?? selection.destination?.id
        store.previewLibraryRange(index,preview)
    }
    private func clearHiddenSelection(){if !results.contains(where:{$0.id == selectedID}){selectedID=nil}}
    private func addSelection(){
        guard let selection,selection.playable else{return}
        if let builtin=selection.builtin {store.addSound(index,builtin)}
        else if let entry=selection.entry {store.addLibrarySound(entry,index:index)}
        else if let external=selection.external {store.addExternal(external,index:index)}
        else if let destination=selection.destination {store.addMIDIDestination(destination,index:index)}
        dismiss()
    }
}

private struct LibraryChoiceMenu:View {
    let title:String
    let choices:[String]
    let accessibility:String
    let choose:(String)->Void
    @State private var expanded=false
    var body:some View {
        Button{expanded.toggle()}label:{HStack{Text(title).lineLimit(1);Spacer(minLength:4);Image(systemName:"chevron.down").font(.system(size:13))}.font(StageTheme.font(15)).padding(.horizontal,14).frame(height:46).frame(maxWidth:.infinity).background(StageTheme.raised.opacity(0.22),in:RoundedRectangle(cornerRadius:8)).overlay(RoundedRectangle(cornerRadius:8).stroke(Color.white.opacity(0.09)))}.buttonStyle(.plain).accessibilityLabel(accessibility)
            .popover(isPresented:$expanded){ScrollView{VStack(spacing:2){ForEach(choices,id:\.self){choice in Button{choose(choice);expanded=false}label:{HStack{Text(choice);Spacer();if choice == title{Image(systemName:"checkmark")}}.padding(12).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain)}}.padding(6)}.frame(width:230,height:min(CGFloat(choices.count)*45+12,360)).background(StageTheme.panel)}
    }
}
private struct LibraryActionStyle:ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var primary=false
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(StageTheme.font(14,weight:.semibold)).frame(width:120,height:44).background(primary ? StageTheme.selected.opacity(enabled ? 0.9 : 0.3) : StageTheme.base,in:RoundedRectangle(cornerRadius:9)).overlay(RoundedRectangle(cornerRadius:9).stroke(Color.white.opacity(0.12))).foregroundStyle(primary ? StageTheme.base : StageTheme.selected).opacity(configuration.isPressed ? 0.7 : 1)
    }
}
