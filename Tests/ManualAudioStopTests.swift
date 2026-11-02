import Foundation
import AVFoundation
import CoreMIDI

@main struct ManualAudioStopTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline(); store.start()
        defer { store.stopAudio() }
        var client = MIDIClientRef(), source = MIDIEndpointRef()
        assert(MIDIClientCreateWithBlock("Generated manual-stop MIDI client" as CFString, &client, nil) == noErr)
        assert(MIDISourceCreate(client, "Generated manual-stop keyboard" as CFString, &source) == noErr)
        defer { MIDIEndpointDispose(source); MIDIClientDispose(client) }
        func wait(_ predicate: () -> Bool) {
            let deadline = Date().addingTimeInterval(3)
            while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
            assert(predicate())
        }
        wait { store.midiSources.contains { $0.endpoint == source } }
        let identity = store.midiSources.first { $0.endpoint == source }!.id
        store.primarySourceID = identity; store.midiChannel = -1; store.secondarySourceID = -2
        func send(_ status: UInt8, _ note: UInt8, _ velocity: UInt8) {
            var list = MIDIPacketList()
            withUnsafeMutablePointer(to: &list) { pointer in
                let packet = MIDIPacketListInit(pointer)
                let bytes = [status, note, velocity]
                bytes.withUnsafeBufferPointer { _ = MIDIPacketListAdd(pointer, MemoryLayout<MIDIPacketList>.size, packet, 0, 3, $0.baseAddress!) }
                assert(MIDIReceived(source, pointer) == noErr)
            }
        }
        store.stopAudio()
        store.midiLog = []
        send(0x90, 60, 100)
        wait { store.midiLog.contains { $0.contains("90 · 60 · 100") } }
        assert(!store.started && !store.audio.running && store.audioStartup == .stopped, "MIDI input must not override Stop Audio")
        assert(store.held.isEmpty)
        // Refresh and automatic setup must keep receiving/monitoring MIDI while
        // preserving the deliberate stopped state.
        store.refreshMIDI(); store.automaticMIDI()
        assert(!store.started && !store.audio.running)
        store.primarySourceID = identity; store.secondarySourceID = -2
        store.startAutomatically()
        assert(!store.started && !store.audio.running, "View/focus automatic startup must respect Stop")
        assert(store.auditionLibrarySound(0, TestFixtures.layer(1)) == nil)
        assert(store.message?.contains("Start audio") == true && !store.audio.running)
        store.start()
        assert(store.started && store.audio.running && store.held.isEmpty)
        store.midiLog = []
        send(0x90, 64, 100)
        wait { store.isNoteHeld(64) }
        send(0x80, 60, 0)
        wait { store.midiLog.contains { $0.contains("80 · 60 · 0") } }
        assert(store.isNoteHeld(64), "An ignored earlier pitch must not own the new note")
        var energy = 0.0
        for _ in 0..<20 {
            let block = try store.audio.offlineBlock()
            for frame in 0..<Int(block.frameLength) { let value = block.floatChannelData![0][frame]; assert(value.isFinite); energy += Double(value * value) }
        }
        assert(energy > 0.01)
        send(0x80, 64, 0); wait { store.held.isEmpty }
        // Explicit Stop also invalidates a scheduled configuration restart.
        store.audio.stop()
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: nil)
        store.stopAudio()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        assert(!store.started && !store.audio.running)
        // The intent is per store/session; initial automatic startup still
        // works. Prepare an offline route before exercising cold MIDI wake.
        let cold = PerformanceStore()
        cold.setlist = TestFixtures.setlist()
        try cold.audio.prepareOffline()
        defer { cold.stopAudio() }
        cold.primarySourceID = identity; cold.midiChannel = -1; cold.secondarySourceID = -2
        wait { cold.midiSources.contains { $0.endpoint == source } }
        send(0x90, 67, 100)
        wait { cold.started && cold.isNoteHeld(67) }
        assert(!store.started && !store.audio.running && store.held.isEmpty)
        send(0x80, 67, 0); wait { cold.held.isEmpty }
        print("PASS manual Stop: virtual MIDI/refresh/focus cannot restart, explicit resume renders, pending restart cancels and first-launch MIDI wake remains")
    }
}
