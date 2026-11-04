import Foundation

@main struct DynamicMIDIRangeTests {
    static func main() throws {
        let p = MIDIFXProcessor(automaticallySchedule: false)
        var events: [String] = []
        p.onNote = { channel, key, pitch, _ in events.append("on:\(channel):\(key):\(pitch)") }
        p.onOff = { channel, key, force in events.append("off:\(channel):\(key):\(force)") }
        p.noteOn(channel: 0, key: 1, pitch: 60, velocity: 1, sourceID: 10)
        p.noteOn(channel: 0, key: 2, pitch: 60, velocity: 1, sourceID: 20)
        p.noteOn(channel: 1, key: 1, pitch: 72, velocity: 1)
        assert(p.activeOutputRange(channel: 0) == 60...60)
        p.noteOff(channel: 0, key: 1)
        assert(p.activeOutputRange(channel: 0) == 60...60)
        p.releaseSource(20)
        assert(p.activeOutputRange(channel: 0) == nil && p.activeOutputRange(channel: 1) == 72...72)
        p.panic(); assert(p.activeOutputRange(channel: 1) == nil)
        var chord = MIDIProgram(); chord.kind = .easyChord
        chord.chordMappings = [.init(input: 60, output: [48,55,64])]
        p.configure(channel: 0, program: chord, tempo: 120)
        p.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        assert(p.activeOutputRange(channel: 0) == 48...64)
        assert(p.activeOutputRange(channel: 0, transpose: 12) == 60...76)
        let unchanged = events
        for _ in 0..<20 { _ = p.activeOutputRange(channel: 0) }
        assert(events == unchanged, "Visual queries must not emit notes or change timing")
        p.noteOn(channel: 0, key: 60, pitch: 60, velocity: 0)
        assert(p.activeOutputRange(channel: 0) == nil)

        var octave = MIDIProgram(); octave.kind = .octaveUp
        p.configure(channel: 0, program: octave, tempo: 120)
        p.noteOn(channel: 0, key: 120, pitch: 120, velocity: 1)
        assert(p.activeOutputRange(channel: 0) == 120...120)
        assert(p.activeOutputRange(channel: 0, transpose: 12) == nil)
        assert(p.activeOutputRange(channel: 0, transpose: Int.max) == nil)
        assert(p.activeOutputRange(channel: 99) == nil)
        p.panic(channel: 0); assert(p.activeOutputRange(channel: 0) == nil)

        let scheduler = MIDIFXProcessor(automaticallySchedule: false)
        var arp = MIDIProgram(); arp.kind = .arpeggiator; arp.subdivision = 0.5; arp.gate = 0.5
        scheduler.configure(channel: 0, program: arp, tempo: 120)
        scheduler.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        assert(scheduler.activeOutputRange(channel: 0) == 60...60)
        scheduler.advance(to: 0.125); assert(scheduler.activeOutputRange(channel: 0) == nil)
        scheduler.advance(to: 0.25); assert(scheduler.activeOutputRange(channel: 0) == 60...60)
        scheduler.panic(); assert(scheduler.activeOutputRange(channel: 0) == nil)
        var sequence = MIDIProgram(); sequence.kind = .sequencer; sequence.subdivision = 0.5; sequence.gate = 0.5
        sequence.steps = [MIDISequenceStep(pitch: 0), MIDISequenceStep(pitch: 7)]
        scheduler.configure(channel: 0, program: sequence, tempo: 120)
        scheduler.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        assert(scheduler.activeOutputRange(channel: 0) == 60...60)
        scheduler.advance(to: 0.5); assert(scheduler.activeOutputRange(channel: 0) == 67...67)
        scheduler.configure(channel: 0, program: MIDIProgram(), tempo: 120)
        assert(scheduler.activeOutputRange(channel: 0) == nil)

        let retained = MIDIFXProcessor(automaticallySchedule: false)
        sequence.releaseGeneratedOnKeyUp = false
        retained.configure(channel: 0, program: sequence, tempo: 120)
        retained.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1, sourceID: 44)
        retained.noteOff(channel: 0, key: 60)
        assert(retained.activeOutputRange(channel: 0) == 60...60)
        retained.releaseSource(44)
        assert(retained.activeOutputRange(channel: 0) == nil)
        arp.hold = true
        retained.configure(channel: 0, program: arp, tempo: 120)
        retained.noteOn(channel: 0, key: 60, pitch: 60, velocity: 1)
        retained.noteOff(channel: 0, key: 60)
        assert(retained.activeOutputRange(channel: 0) == 60...60)
        retained.panic(); assert(retained.activeOutputRange(channel: 0) == nil)

        // Store composition applies layer transposition before MIDI FX and patch
        // transposition afterward. Enabling the view must reflect existing notes.
        let store = PerformanceStore(); store.setlist = TestFixtures.setlist()
        store.setlist.patches[0].layers[0].low = 48
        store.setlist.patches[0].layers[0].high = 72
        store.setlist.patches[0].layers[0].transpose = 12
        store.setlist.patches[0].transpose = -2
        try store.audio.prepareOffline(); store.start(); defer { store.stopAudio() }
        assert(!store.dynamicMIDIRanges && store.displayedLayerRange(0) == 48...72)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let original = try encoder.encode(store.setlist)
        store.noteOn(60); store.dynamicMIDIRanges = true
        assert(store.displayedLayerRange(0) == 70...70)
        store.dynamicMIDIRanges = false
        assert(store.displayedLayerRange(0) == 48...72 && store.held.contains(60))
        store.dynamicMIDIRanges = true
        assert(store.displayedLayerRange(0) == 70...70)
        assert(store.displayedLayerRange(-1) == nil)
        var energy = 0.0
        for _ in 0..<32 {
            _ = store.displayedLayerRange(0)
            let buffer = try store.audio.offlineBlock()
            for frame in 0..<Int(buffer.frameLength) { energy += Double(abs(buffer.floatChannelData![0][frame])) }
        }
        assert(energy > 0.01 && store.held.contains(60))
        store.setSustain(true); store.noteOff(60)
        assert(store.sustain && store.displayedLayerRange(0) == nil, "Output gates do not claim to show sustained audio")
        store.noteOn(64); assert(store.displayedLayerRange(0) == 74...74)
        store.panic(); assert(store.displayedLayerRange(0) == nil)
        assert(try! encoder.encode(store.setlist) == original)
        store.save()
        let restored = PerformanceStore()
        assert(restored.dynamicMIDIRanges && restored.displayedLayerRange(0) == nil)
        store.stopAudio(); assert(store.displayedLayerRange(0) == nil)
        store.dynamicMIDIRanges = false; assert(store.displayedLayerRange(0) == 48...72)
        let settingsURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!).appendingPathComponent("settings.json")
        var legacy = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as! [String: Any]
        legacy.removeValue(forKey: "dynamicMIDIRanges")
        try JSONSerialization.data(withJSONObject: legacy).write(to: settingsURL)
        let legacyStore = PerformanceStore(); assert(!legacyStore.dynamicMIDIRanges)
        print("PASS dynamic MIDI ranges: ownership, chord/octave/arp/sequence gates, transposition, query neutrality, retained rendering, Panic/Stop, persistence and legacy defaults")
    }
}
