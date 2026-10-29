import SwiftUI

struct SoundBrowser: View {
    @EnvironmentObject private var store:PerformanceStore
    @Environment(\.dismiss) private var dismiss
    let index:Int
    @State private var collection="All Sounds"
    @State private var query=LibraryQuery()
    @AppStorage("library.filterColumns") private var savedFacets="Note Range|Type|Timbre|Articulation"
    @State private var facets:[LibraryFacet]=[.noteRange,.type,.timbre,.articulation]
    @State private var selectedID:String?
    @State private var importHub=false
    @State private var showingImportNotes=false
    @State private var auditionToken:UUID?
    @State private var instruments=ExternalInstrumentRack.instruments()
    /// Shared with Settings so a setup change reaches the library immediately.
    private var destinations:[ExternalMIDIDestination] { store.midiDestinations }
    private var collections:[String] {
        let builtins=["All Sounds","StageKeys","My Sounds","Sunday Free","Sunday App","MainStage Archive","Audio Units","External MIDI"]
        return builtins + Set(store.librarySounds.map(\.collection).filter{$0 != "Tonic Pads"}).subtracting(builtins).sorted{$0.localizedStandardCompare($1) == .orderedAscending}
    }
    private var sounds:[BrowserSound] {
        var result=["Soft Keys","Warm Pad","Glass Bells"].enumerated().map {i,name in var tags=SoundTags.inferred(name:name,source:"StageKeys Synth");tags.noteRanges=[LibraryNoteRange.full.rawValue];return BrowserSound(id:"builtin-\(i)",name:name,collection:"StageKeys",tags:tags,builtin:i)}
        let entries=store.librarySounds
        let entryOrder=Dictionary(entries.enumerated().map{($0.element.id,$0.offset+1)},uniquingKeysWith:{first,_ in first})
        result += entries.map {entry in
            if collection == "MainStage Archive",entry.hostPath != nil,
               let converted=entries.first(where:{$0.sourceArchiveID == entry.id && ($0.sound != nil || $0.layer != nil)}) {
                return BrowserSound.archive(entry,converted:converted)
            }
            return BrowserSound.library(entry)
        }
        result += instruments.map { component in
            var item=BrowserSound(id:"au-\(component.id)",name:component.name,collection:"Audio Units",tags:.init(category:"Instruments",type:"Audio Unit",sourceModel:component.vendor ?? "Audio Unit"),external:ExternalSound(kind:.audioUnit,name:component.name,component:component))
            item.unavailableReason=component.unavailableReason
            item.validationNote=component.validated == false ? "Not validated by auval; it may still work." : nil
            return item
        }
        result += destinations.map{BrowserSound(id:"midi-\($0.id)",name:$0.name,collection:"External MIDI",tags:.init(category:"External MIDI",type:"MIDI Destination",sourceModel:"External MIDI"),destination:$0)}
        return result.filter {sound in
            guard sound.collection != "Tonic Pads" else{return false}
            switch collection {
            case "All Sounds":return sound.playable && sound.destination == nil
            case "MainStage Archive":return entries.contains(where:{$0.id == sound.id && $0.hostPath != nil})
            case "Sunday Free":return sound.collection.hasPrefix("Sunday Free") && sound.playable
            case "Sunday App":return sound.collection.hasPrefix("Sunday App")
            // Keep unavailable Audio Units listed so the reason is visible; every
            // other collection only offers playable sounds.
            case "Audio Units":return sound.collection == "Audio Units"
            default:return sound.collection == collection && sound.playable
            }
        }.map {sound in
            var item=sound;item.rating=store.soundRatings[sound.ratingID] ?? 0
            item.addedOrder=entryOrder[sound.ratingID] ?? 0
            return item
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
        .onAppear {
            let restored=savedFacets.split(separator:"|").compactMap{LibraryFacet(rawValue:String($0))}
            if restored.count==4 && Set(restored).count==4 {facets=restored}
        }
        .onChange(of:facets){savedFacets=$0.map(\.rawValue).joined(separator:"|")}
        .onDisappear {store.endAudition(auditionToken);store.previewLibraryRange(index,nil)}
        .onChange(of:selectedID){_ in previewRange();if auditionToken != nil {auditionSelection()}}
        .onChange(of:collection){_ in selectedID=nil;query.filters=[:]}
        .onChange(of:query.search){_ in clearHiddenSelection()}
        .onChange(of:query.filters){_ in clearHiddenSelection()}
        .onChange(of:store.librarySounds){_ in clearHiddenSelection()}
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
            LibraryChoiceMenu(title:facet.rawValue,choices:LibraryFacet.allCases.map(\.rawValue).sorted(),accessibility:"Filter column \(offset+1): \(facet.rawValue)"){name in
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
                LibraryChoiceMenu(title:query.ordering.rawValue,choices:LibrarySort.allCases.map(\.rawValue),accessibility:"Order by \(query.ordering.rawValue)"){if let order=LibrarySort(rawValue:$0){query.order(by:order)}}
                Button{query.ascending.toggle()}label:{Image(systemName:query.ascending ? "arrow.down.to.line" : "arrow.up.to.line").frame(width:30,height:42)}.buttonStyle(.plain).accessibilityLabel(query.ascending ? "Sort descending" : "Sort ascending")
            }.padding(8).frame(height:70)
            ScrollView {
                LazyVStack(spacing:2) {
                    ForEach(results){sound in
                        HStack(spacing:0){
                            Button{selectedID=sound.id}label:{VStack(alignment:.leading,spacing:5){Text(sound.name).font(StageTheme.font(16)).multilineTextAlignment(.leading);if collection == "MainStage Archive" {Text(sound.playable ? "Playable":"Needs Conversion").font(StageTheme.font(11)).foregroundStyle(.secondary)};if sound.collection == "Audio Units" {Text(sound.tags.sourceModel).font(StageTheme.font(11)).foregroundStyle(.secondary)}}.frame(maxWidth:.infinity,alignment:.leading).padding(.leading,14).padding(.vertical,13)}.buttonStyle(.plain).accessibilityLabel("\(sound.name), \(sound.unavailableReason != nil ? "Unavailable" : sound.playable ? "Playable":"Needs Conversion")")
                            SoundRatingControl(name:sound.name,rating:sound.rating){store.rateSound(sound.ratingID,$0)}.padding(.horizontal,12)
                        }.background(selectedID == sound.id ? selectionColor:.clear,in:RoundedRectangle(cornerRadius:7)).foregroundStyle(selectedID == sound.id ? .white:.white.opacity(0.85))
                         .contextMenu {if let entry=sound.entry {
                            Button(sound.tags.recommended == true ? "Remove from Recommended":"Mark Recommended"){store.setSoundRecommended(entry.id,sound.tags.recommended != true)}
                            Menu("Note Range") {
                                ForEach(LibraryNoteRange.allCases,id:\.self) {range in
                                    Button {store.setSoundNoteRanges(entry.id,LibraryNoteRange.toggling(range,in:sound.tags.noteRanges))}label:{HStack{Text(range.rawValue);if sound.tags.noteRanges?.contains(range.rawValue)==true {Image(systemName:"checkmark")}}}
                                }
                                Divider();Button("Clear Note Range Tags"){store.setSoundNoteRanges(entry.id,[])}
                            }
                            Menu("Complexity"){ForEach(["Simple","Moderate","Complex"],id:\.self){value in Button(value){store.setSoundComplexity(entry.id,value)}};Divider();Button("Clear Complexity"){store.setSoundComplexity(entry.id,nil)}}
                        }}

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
                    if let rack=selection.entry?.layer?.importedRack,rack.effectCount>0 {Text("Rack effects: \(rack.effectCount)"+(selection.tags.inferred ? " · Suggested tags":"")).foregroundStyle(.secondary).lineLimit(1)}
                    else if selection.tags.inferred {Text("Suggested tags · edit Note Range by right-clicking a sound").foregroundStyle(.secondary).lineLimit(1)}
                    if let reason=selection.unavailableReason {Text(reason).foregroundStyle(.secondary).lineLimit(2)}
                    else if let note=selection.validationNote {Text(note).foregroundStyle(.secondary).lineLimit(2)}
                    else if !selection.playable {Text("This MainStage patch needs a compatible sound import before it can play here.").foregroundStyle(.secondary)}
                } else {Text(results.count==1 ? "1 sound":"\(results.count) sounds").foregroundStyle(.secondary)}
                if collection == "Audio Units" {
                    #if os(macOS)
                    Text("Installed Mac AUv2/AUv3 instruments · VST3 is not hosted directly").foregroundStyle(.secondary).lineLimit(2)
                    #else
                    Text("Installed iOS AUv3 instruments · Mac plug-ins/libraries require iOS versions").foregroundStyle(.secondary).lineLimit(2)
                    #endif
                }
            }.font(StageTheme.font(12)).frame(maxWidth:.infinity,alignment:.leading)
            if selection?.entry?.conversionNotes?.isEmpty == false {Button("Import Notes"){showingImportNotes=true}.buttonStyle(StageButtonStyle()).popover(isPresented:$showingImportNotes){ScrollView{VStack(alignment:.leading,spacing:12){ForEach(selection?.entry?.conversionNotes ?? [],id:\.self){Text($0)}}.padding(20)}.frame(width:420,height:300)}}
            if collection == "External MIDI" {Button("Refresh"){store.refreshMIDIDestinations()}.buttonStyle(StageButtonStyle())}
            if collection == "Audio Units" {Button("Allow Blocked Loads") {do{try ExternalInstrumentRack.allowBlockedLoads();instruments=ExternalInstrumentRack.instruments()}catch{store.message=error.localizedDescription}}.buttonStyle(StageButtonStyle()).help("Explicitly retry plug-ins blocked after failed or interrupted loading")}
            if collection == "Audio Units" {Button("Rescan"){instruments=ExternalInstrumentRack.instruments()}.buttonStyle(StageButtonStyle()).help("Re-scan installed Audio Units; a plug-in installed while StageKeys is running may need a relaunch")}
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
        store.requestPluginInterface(index)
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
            .popover(isPresented:$expanded,arrowEdge:.bottom){ScrollView{VStack(spacing:2){ForEach(choices,id:\.self){choice in Button{choose(choice);expanded=false}label:{HStack{Text(choice);Spacer();if choice == title{Image(systemName:"checkmark")}}.padding(12).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain)}}.padding(6)}.frame(width:230,height:min(CGFloat(choices.count)*45+12,360)).background(StageTheme.panel)}
    }
}
private struct LibraryActionStyle:ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var primary=false
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(StageTheme.font(14,weight:.semibold)).frame(width:120,height:44).background(primary ? StageTheme.selected.opacity(enabled ? 0.9 : 0.3) : StageTheme.base,in:RoundedRectangle(cornerRadius:9)).overlay(RoundedRectangle(cornerRadius:9).stroke(Color.white.opacity(0.12))).foregroundStyle(primary ? StageTheme.base : StageTheme.selected).opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct SoundRatingControl:View {
    let name:String
    let rating:Int
    let set:(Int)->Void
    @State private var hovering=false
    var body:some View {
        HStack(spacing:0) {
            ForEach(1...5,id:\.self) { star in
                Button {set(rating==star ? 0:star)} label: {
                    ZStack {
                        if star<=rating {Image(systemName:"star.fill").font(.system(size:12))}
                        else if hovering {Image(systemName:"star").font(.system(size:12))}
                        else {Circle().frame(width:3,height:3)}
                    }.frame(width:17,height:28).contentShape(Rectangle())
                }.buttonStyle(.plain)
                .accessibilityLabel("Rate \(name) \(star) stars")
                .accessibilityValue(star<=rating ? "Selected":"Not selected")
                .help(rating==star ? "Clear rating":"Rate \(star) stars")
            }
        }.onHover{hovering=$0}.accessibilityElement(children:.contain)
        .accessibilityLabel("\(name) rating, \(rating) of 5 stars")
    }
}
