import SwiftUI
import UniformTypeIdentifiers

struct SoundImportView:View {
    @EnvironmentObject private var store:PerformanceStore
    private enum ImportChoice { case file, library, samples, mainStage, mainStageSamples, backup }
    @State private var choosing=false
    @State private var choice:ImportChoice = .file
    @State private var pending:URL?
    @State private var status:String?
    var body:some View {
        EditorFrame(title:"Import Sounds",width:650,height:720) {
            ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text("Add sounds to your library").font(StageTheme.font(21,weight:.bold))
                Text("Imported sounds appear in your library and can be added to any patch.").foregroundStyle(.secondary)
                Button{choice = .file;choosing=true}label:{HStack{Image(systemName:"plus.circle.fill").font(.title);VStack(alignment:.leading,spacing:4){Text("Choose a Sound File").font(.headline);Text("StageKeys Sampler · EXS · AUPRESET · audio · sound banks").font(.caption)};Spacer();Image(systemName:"chevron.right")}.padding(20).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:10))
                Button{choice = .library;choosing=true}label:{HStack{Image(systemName:"folder.badge.plus").font(.title);VStack(alignment:.leading,spacing:4){Text("Import a Sampler Library Folder").font(.headline);Text("Add EXS and AUPRESET instruments with their original samples").font(.caption)};Spacer();Image(systemName:"chevron.right")}.padding(20).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:10))
                Button{choice = .mainStage;choosing=true}label:{HStack{Image(systemName:"pianokeys").font(.title);VStack(alignment:.leading,spacing:4){Text("Convert a MainStage Patch or Channel Strip").font(.headline);Text("Convert included EXS sounds without opening MainStage; preserve source processing").font(.caption)};Spacer();Image(systemName:"chevron.right")}.padding(20).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:10))
                Button("Install a Separate Sound Library") {choice = .backup;choosing=true}.buttonStyle(StageButtonStyle())
                Text("Choose a downloaded StageKeys-Library pack. Sounds and rack processing install separately; the app ships without sampled content.").font(.caption).foregroundStyle(.secondary)
                if store.librarySounds.contains(where:{$0.originalInstrument?.file.hasSuffix(".exs")==true && $0.sound?.nativeSampler != nil && ($0.sound?.nativeSampler?.conversionVersion ?? 1)<6}) {
                    Button("Update Converted Sampler Playback") {store.updateSamplerEnvelopes()}.buttonStyle(StageButtonStyle())
                    Text("Update source filters, velocity response, level and envelope curves. Original samples and effects stay intact; edited settings are protected.").font(.caption).foregroundStyle(.secondary)
                }
                if let report=store.mainStageImportReport {
                    Button("Create Patch from All Converted Channels") {store.assembleConvertedMainStagePatch()}.buttonStyle(StageButtonStyle()).disabled(store.patchLock)
                    Text("Requires one converted version of every sampler channel. Preserves channel order, effects, macros and MIDI; patch-level routing limitations remain in Conversion Notes.").font(.caption).foregroundStyle(.secondary)
                    if report.channels.contains(where:{!$0.instruments.isEmpty}) {
                        Button("Import MainStage Sounds") {choice = .mainStageSamples;choosing=true}.buttonStyle(StageButtonStyle())
                        Text("Choose the original EXS/sample folder. Supported channel effects and controls are saved with each sound; conversion notes list remaining differences.").font(.caption).foregroundStyle(.secondary)
                    }
                    DisclosureGroup("Conversion Report · \(report.name)") {
                        ScrollView {VStack(alignment:.leading,spacing:6) {
                            ForEach(Array(report.channels.enumerated()),id:\.offset) {_,channel in
                                Text(channel.name+": "+channel.devices.map(\.name).joined(separator:", ")).font(.caption)
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
            }
        }.fileImporter(isPresented:$choosing,allowedContentTypes:choice == .file ? [.audio,.data] : choice == .mainStage ? [.package,.folder,.data] : [.folder]) {result in
            switch result {
            case .success(let url):
                switch choice {
                case .file:
                    if ["patch","cst"].contains(url.pathExtension.lowercased()) {store.importMainStagePatch(url);status=nil}
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
                    store.importMainStageSamplers(url);status=nil
                case .mainStage:
                    store.importMainStagePatch(url);status=nil
                case .library:
                    store.importSamplerLibrary(url);status=store.message;store.message=nil
                }
            case .failure(let error):status=error.localizedDescription;pending=nil
            }
        }
    }

    private func importFile(_ url:URL,samples:URL?=nil){
        if let sound=store.importLibrarySound(url,sampleRoot:samples){status="Added \(sound.name) to My Sounds."}
        else {status=store.message ?? "Could not import this sound.";store.message=nil}
    }
}
