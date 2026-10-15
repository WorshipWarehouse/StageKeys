import SwiftUI
import UniformTypeIdentifiers

struct SoundImportView:View {
    @EnvironmentObject private var store:PerformanceStore
    private enum ImportChoice { case file, library, samples }
    @State private var choosing=false
    @State private var choice:ImportChoice = .file
    @State private var pending:URL?
    @State private var status:String?
    var body:some View {
        EditorFrame(title:"Import Sounds",width:650,height:480) {
            VStack(alignment:.leading,spacing:20) {
                Text("Add sounds to your library").font(StageTheme.font(21,weight:.bold))
                Text("Imported sounds appear in My Sounds and can be added to any patch.").foregroundStyle(.secondary)
                Button{choice = .file;choosing=true}label:{HStack{Image(systemName:"plus.circle.fill").font(.title);VStack(alignment:.leading,spacing:4){Text("Choose a Sound File").font(.headline);Text("WAV · AIFF · CAF · SF2 · DLS · EXS · AUPRESET · ADG · ALP").font(.caption)};Spacer();Image(systemName:"chevron.right")}.padding(20).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:10))
                Button{choice = .library;choosing=true}label:{HStack{Image(systemName:"folder.badge.plus").font(.title);VStack(alignment:.leading,spacing:4){Text("Import a Sampler Library Folder").font(.headline);Text("Add EXS, AUPRESET or Ableton ADG instruments and their samples").font(.caption)};Spacer();Image(systemName:"chevron.right")}.padding(20).frame(maxWidth:.infinity,alignment:.leading)}.buttonStyle(.plain).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:10))
                if store.libraryImportBusy {ProgressView().progressViewStyle(.linear)}
                if let progress=store.libraryImportProgress {Text(progress).font(.callout).textSelection(.enabled)}
                if let status {Text(status).font(.callout).textSelection(.enabled)}
                Spacer()
            }.padding(28).disabled(store.libraryImportBusy)
        }.fileImporter(isPresented:$choosing,allowedContentTypes:choice == .file ? [.audio,.data] : [.folder]) {result in
            switch result {
            case .success(let url):
                switch choice {
                case .file:
                    if ["exs","aupreset","adg","adv"].contains(url.pathExtension.lowercased()) {
                        pending=url;status="Choose the folder containing this instrument’s samples. Ableton imports preserve sample maps; rack effects and macros are not translated."
                        // Present the second picker after the first has dismissed.
                        DispatchQueue.main.async {choice = .samples;choosing=true}
                    } else if url.pathExtension.lowercased()=="alp" {status=nil;store.importAbletonPack(url)}
                    else {importFile(url)}
                case .samples:
                    if let pending {importFile(pending,samples:url)}
                    pending=nil
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
