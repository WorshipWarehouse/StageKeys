import Foundation
import AVFoundation
@main struct ImportedSoundRetentionTests {
    static func main() throws {
        precondition(Thread.isMainThread)
        let root=URL(fileURLWithPath:ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        let store=PerformanceStore()
        try store.audio.prepareOffline()
        let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:1)!
        let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:4800)!;buffer.frameLength=4800
        for frame in 0..<4800 {buffer.floatChannelData![0][frame]=0.2*sin(Float(frame)*2 * .pi*261.626/48000)}
        let wave=root.appendingPathComponent("Fixture.wav")
        do {let file=try AVAudioFile(forWriting:wave,settings:format.settings);try file.write(from:buffer)}
        let sound=store.importLibrarySound(wave)!
        let adg=root.appendingPathComponent("Cached.adg")
        try Data("cached import fixture".utf8).write(to:adg)
        var layer=Layer(name:"Processed import",instrument:-1,gain:0.27);layer.external=sound
        var fx=AudioEffect();fx.kind=3;fx.enabled=false
        layer.importedRack=ImportedRack(effects:[fx])
        var program=MIDIProgram();program.kind = .octaveUp
        layer.midiProgram=program
        let entry=LibrarySound(id:"ableton-samples-"+(try AbletonArchive.sha256(adg)),name:layer.name,collection:"My Sounds",sound:sound,layer:layer)
        store.librarySounds.append(entry)
        assert(store.importSound(adg,index:0))
        assert(store.patch.layers[0].importedRack==layer.importedRack)
        assert(store.patch.layers[0].midiProgram==program && store.patch.layers[0].gain==0.27)
        store.setSoundRecommended(entry.id,true)
        let saved=try SoundLibrary(url:root.appendingPathComponent("sound-library.json")).read().first{$0.id==entry.id}!
        assert(saved.tags!.recommended==true && saved.layer!.importedRack==layer.importedRack)
        assert(saved.layer!.midiProgram==program)
        try store.setlist.validate()
        print("PASS: cached direct import preserves rack, bypass state, MIDI and level; recommendation writes preserve processing")
    }
}
