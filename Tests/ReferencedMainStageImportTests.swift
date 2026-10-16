import Foundation
@main struct ReferencedMainStageImportTests {
    static func main()throws {
        guard let patchPath=ProcessInfo.processInfo.environment["STAGEKEYS_MAINSTAGE_PATCH"],let sampleRoot=ProcessInfo.processInfo.environment["STAGEKEYS_EXS_ROOT"] else{print("SKIP: provide private source patch and selected sample root");return}
        let store=PerformanceStore()
        let encoder=JSONEncoder();encoder.outputFormatting = .sortedKeys
        let before=try encoder.encode(store.setlist)
        store.importMainStagePatch(URL(fileURLWithPath:patchPath))
        assert(store.mainStageImportReport?.channels.count==2)
        store.importMainStageSamplers(URL(fileURLWithPath:sampleRoot))
        let timeout=Date().addingTimeInterval(60)
        while store.libraryImportBusy && Date()<timeout {_ = RunLoop.current.run(mode:.default,before:Date().addingTimeInterval(0.05))}
        assert(!store.libraryImportBusy,store.libraryImportProgress ?? "Referenced import timed out")
        let instruments=store.librarySounds.filter{$0.collection=="MainStage Samplers"}
        assert(instruments.count==1,store.libraryImportProgress ?? "No referenced instrument imported")
        assert(instruments[0].sound?.nativeSampler?.groups.count==20 && instruments[0].layer?.importedRack?.branches?.count==2)
        assert(instruments[0].originalInstrument != nil && instruments[0].conversionNotes?.isEmpty==false)
        let after=try encoder.encode(store.setlist);assert(before==after,"Library import must not replace the user's active patch")
        let processing=try store.mainStageProcessing(0)
        assert(processing.effects.contains{$0.kind==7},"Real source Channel EQ must be available for native processing preview")
        assert(processing.effects.contains{$0.kind==16} && processing.effects.contains{$0.kind==17} && processing.effects.contains{$0.importedDelay?.leftSynced==true})
        print("PASS: real MainStage source → referenced modern EXS → native library layer with 20 active groups; original instrument/notes retained, real EQ translated, active setlist unchanged")
    }
}
