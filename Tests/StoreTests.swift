import Foundation
import AVFoundation
@main struct StoreTests {
    static func main() throws {
        precondition(Thread.isMainThread)
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline()
        store.start()
        assert(store.started)
        let auditionEncoder=JSONEncoder();auditionEncoder.outputFormatting = .sortedKeys
        let savedBeforeAudition=try auditionEncoder.encode(store.setlist)
        let token=store.auditionLibrarySound(0,TestFixtures.layer(2,gain:0.6,name:"Audition Bells"))!
        assert(store.playbackLayer(0).name == "Audition Bells")
        assert((try! auditionEncoder.encode(store.setlist)) == savedBeforeAudition)
        store.endAudition(token)
        assert(store.playbackLayer(0).name == store.patch.layers[0].name)
        assert((try! auditionEncoder.encode(store.setlist)) == savedBeforeAudition)
        store.noteOn(60)
        assert(store.held.contains(60))
        var peak: Float = 0
        for _ in 0..<40 {
            let buffer = try store.audio.offlineBlock()
            for i in 0..<Int(buffer.frameLength) { peak = max(peak,abs(buffer.floatChannelData![0][i])) }
        }
        assert(peak > 0.01)
        store.noteOff(60); assert(store.held.isEmpty)
        store.setSustain(true); store.panic(); assert(!store.sustain && store.held.isEmpty)
        var layer = store.patch.layers[14]
        layer.instrument = 2; layer.name = "Integration Test"; layer.gain = 0.7
        layer.midiProgram = MIDIProgram(kind: .easyChord)
        store.commitLayer(14, layer)
        store.noteOn(64); store.noteOff(64)
        store.setRange(14,low: 40,high: 80)
        store.moveLayer(14,13)
        assert(store.patch.layers[13].name == "Integration Test")
        assert(store.patch.layers[13].low == 40 && store.patch.layers[13].high == 80)
        store.captureSnapshot(0); assert(store.patch.snapshots[0].gains.count == 15)
        store.removeSound(13); assert(!store.patch.layers[13].loaded)
        store.choose(1); assert(store.selected == 1)
        store.patchLock = true; store.choose(0); assert(store.selected == 1)
        store.patchLock = false; store.duplicate(); assert(store.setlist.patches.count == 4)
        store.master = 0.4; store.transition = 2.5; store.save()
        let restored = PerformanceStore()
        assert(restored.master == 0.4 && restored.transition == 2.5)
        assert(restored.setlist.patches.count == 4 && restored.selected == store.selected)
        let baseline=store.patch.layers[0]
        let auditionToken=store.beginAudition(0)!
        var preview=baseline; preview.transpose=7; preview.pan=0.8
        store.previewLayer(0,preview,token:auditionToken)
        assert(store.playbackLayer(0).effectiveTranspose == preview.effectiveTranspose)
        assert(store.patch.layers[0].pan == baseline.pan)
        store.save()
        let duringPreview=PerformanceStore()
        assert(duringPreview.patch.layers[0].pan == baseline.pan,"Unconfirmed editor values must not autosave")
        store.endAudition(auditionToken)
        assert(store.playbackLayer(0).pan == baseline.pan)
        store.confirmAudition(auditionToken,index:0,layer:preview)
        assert(store.patch.layers[0].pan == baseline.pan,"Expired editor tokens cannot commit")
        let confirmedToken=store.beginAudition(0)!
        store.previewLayer(0,preview,token:confirmedToken)
        store.confirmAudition(confirmedToken,index:0,layer:preview)
        assert(store.patch.layers[0].pan == 0.8)
        store.commitLayer(0,baseline)
        let originalID = store.currentSetlistID!
        let originalName = store.setlist.name
        store.createLocalSetlist(); let newID = store.currentSetlistID!
        assert(newID != originalID && store.setlist.patches.count == 1 && store.patch.layers.allSatisfy { !$0.loaded })
        store.renameLocalSetlist(newID,name:"Second Service")
        store.openLocalSetlist(originalID); assert(store.setlist.name == originalName && store.setlist.patches.count == 4)
        store.duplicateLocalSetlist(newID); assert(store.savedSetlists.count == 3)
        store.archiveLocalSetlist(newID); assert(store.archivedSetlists.count == 1)
        store.restoreLocalSetlist(store.archivedSetlists[0].token); assert(store.savedSetlists.contains { $0.id == newID })
        let before = store.patch
        let assignment = store.setlist.assignments[20]!
        store.reorderLayer(assignment,14)
        assert(store.patch.layers[14].id == before.layers[assignment].id && store.setlist.assignments[20] == 14)
        for scene in before.snapshots.indices { assert(store.patch.snapshots[scene].gains[14] == before.snapshots[scene].gains[assignment]) }
        assert(store.saveSoundToLibrary(store.patch.layers[14],index:14))
        let saved = store.librarySounds.last!
        store.addLibrarySound(saved,index:12)
        assert(store.patch.layers[12].name == saved.name && store.patch.layers[12].effects == saved.layer!.effects)
        assert(store.patch.layers[12].id != saved.layer!.id)
        let patchCount=store.setlist.patches.count
        store.addPatch("  ");assert(store.setlist.patches.count==patchCount)
        store.patchLock=true;store.addPatch("Locked");assert(store.setlist.patches.count==patchCount);store.patchLock=false
        store.addPatch("  Named Blank  ")
        assert(store.patch.name=="Named Blank" && store.patch.layers.count==15 && store.patch.layers.allSatisfy{!$0.loaded} && store.patch.snapshots.isEmpty)
        store.setPatchVolume(-6);assert(store.patch.volumeDB == -6)
        store.setPatchVolume(.nan);assert(store.patch.volumeDB == -6)
        let decoded=try JSONDecoder().decode(Setlist.self,from:JSONEncoder().encode(store.setlist))
        assert(decoded.patches.last!.volumeDB == -6 && decoded.patches.last!.programChangeEnabled == false)
        let beforeLibrary=store.patch.id;store.addLibraryPatch(store.patch)
        assert(store.patch.id != beforeLibrary && store.patch.name=="Named Blank")
        let patchEncoder=JSONEncoder();patchEncoder.outputFormatting = .sortedKeys
        let beforeImport=try patchEncoder.encode(store.patch),libraryCount=store.librarySounds.count
        let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
        let fixture=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:4800)!;fixture.frameLength=4800
        for frame in 0..<4800 {fixture.floatChannelData![0][frame]=0.2*sin(Float(frame)*2 * .pi*261.626/48000)}
        let wave=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!).appendingPathComponent("Library Import.wav")
        do {let file=try AVAudioFile(forWriting:wave,settings:format.settings);try file.write(from:fixture)}
        assert(store.importLibrarySound(wave) != nil)
        let afterImport=try patchEncoder.encode(store.patch)
        assert(afterImport==beforeImport && store.librarySounds.count==libraryCount+1)
        assert(store.librarySounds.last!.collection=="My Sounds")
        try store.setlist.validate()
        assert(store.message == nil, store.message ?? "")
        let beforePreview=store.patch.layers[0]
        var libraryPreview=TestFixtures.layer(1,gain:0.5,name:"Library Preview");libraryPreview.low=36;libraryPreview.high=48
        store.previewLibraryRange(0,libraryPreview)
        assert(store.displayedLayers[0].low==36 && store.displayedLayers[0].high==48)
        assert(store.patch.layers[0]==beforePreview,"Library selection committed a sound")
        store.previewLibraryRange(0,nil);assert(store.displayedLayers[0]==beforePreview)
        print("PASS: performance store audio, note lifecycle, range/reorder, snapshot capture, remove, patch switch/lock, duplicate and persistence")
    }
}
