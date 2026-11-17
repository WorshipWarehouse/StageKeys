import Foundation
import CoreMIDI

@main struct KeyboardPerformanceSettingsTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline(); store.start()
        defer { store.stopAudio() }
        assert(store.keyboardPlayable && store.showPlayedNotes)
        store.noteOn(60)
        assert(store.isNoteHeld(60) && store.isNoteHighlighted(60))
        store.showPlayedNotes = false
        assert(store.isNoteHeld(60) && !store.isNoteHighlighted(60))
        store.showPlayedNotes = true
        assert(store.isNoteHighlighted(60))

        var client = MIDIClientRef(), source = MIDIEndpointRef()
        assert(MIDIClientCreateWithBlock("StageKeys Keyboard Controls" as CFString, &client, nil) == noErr)
        defer { if source != 0 { MIDIEndpointDispose(source) }; MIDIClientDispose(client) }
        assert(MIDISourceCreate(client, "Keyboard Controls Fixture" as CFString, &source) == noErr)
        func wait(_ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(3)
            while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            assert(condition())
        }
        wait { store.midiSources.contains { $0.endpoint == source } }
        store.primarySourceID = store.midiSources.first { $0.endpoint == source }!.id
        store.secondarySourceID = -2; store.midiChannel = -1
        func send(_ status: UInt8, _ a: UInt8, _ b: UInt8) {
            store.midiLog = []
            var list = MIDIPacketList()
            withUnsafeMutablePointer(to: &list) { pointer in
                let packet = MIDIPacketListInit(pointer), bytes = [status, a, b]
                bytes.withUnsafeBufferPointer {
                    _ = MIDIPacketListAdd(pointer, MemoryLayout<MIDIPacketList>.size, packet, 0, bytes.count, $0.baseAddress!)
                }
                assert(MIDIReceived(source, pointer) == noErr)
            }
            wait { !store.midiLog.isEmpty }
        }
        // Same pitch has distinct screen and hardware owners. Disabling the
        // screen must release only the former, including the screen pedal.
        store.noteOn(60) // Selecting the input above intentionally panics old notes.
        send(0x90, 60, 100); send(0xb0, 64, 127)
        store.setSustain(true)
        assert(store.held.count == 2 && store.sustain)
        store.keyboardPlayable = false
        assert(!store.held.contains(60) && store.held.count == 1 && store.isNoteHeld(60))
        assert(store.sustain, "Disabling screen play must retain the hardware pedal")
        store.noteOn(62); assert(!store.isNoteHeld(62))
        send(0x90, 64, 100); assert(store.isNoteHighlighted(64))
        store.showPlayedNotes = false
        assert(store.isNoteHeld(64) && !store.isNoteHighlighted(64))
        send(0x80, 60, 0); send(0x80, 64, 0); send(0xb0, 64, 0)
        assert(store.held.isEmpty && !store.sustain)
        store.keyboardPlayable = true; store.noteOn(62)
        assert(store.isNoteHeld(62) && !store.isNoteHighlighted(62))
        store.noteOff(62)
        store.setSustain(true); store.noteOn(67)
        store.keyboardPlayable = false
        assert(store.held.isEmpty && !store.sustain, "Screen-only sustain must also release")

        store.keyboardPlayable = false; store.save()
        let restored = PerformanceStore()
        assert(!restored.keyboardPlayable && !restored.showPlayedNotes)
        restored.noteOn(65); assert(!restored.isNoteHeld(65))
        let settingsURL = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!).appendingPathComponent("settings.json")
        let saved = try Data(contentsOf: settingsURL)
        var legacy = try JSONSerialization.jsonObject(with: saved) as! [String: Any]
        legacy.removeValue(forKey: "keyboardPlayable"); legacy.removeValue(forKey: "showPlayedNotes")
        let old = try JSONDecoder().decode(SessionSettings.self, from: JSONSerialization.data(withJSONObject: legacy))
        assert(old.keyboardPlayable == nil && old.showPlayedNotes == nil && old.validate())
        // Loading a legacy settings file preserves the former enabled behavior.
        try JSONSerialization.data(withJSONObject: legacy).write(to: settingsURL)
        let migrated = PerformanceStore()
        assert(migrated.keyboardPlayable && migrated.showPlayedNotes)
        print("PASS keyboard controls: independent highlights/playability, screen/hardware ownership, pedals, MIDI, persistence and legacy defaults")
    }
}
