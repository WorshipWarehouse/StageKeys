import Foundation
import AVFoundation
import CoreMIDI

/// Incoming pitch bend used to be dropped: `handleMIDI` accepted notes, CC and
/// program change and fell through to `default: break` for 0xE0. This program
/// pins the wire decoding and the production store's dispatch: a primary
/// controller bends the hosted instrument, a secondary one cannot, and Panic
/// recentres the wheel instead of leaving the next chord transposed.
@main struct MIDIPitchBendTests {
    static func main() throws {
        // A wheel at rest sends the 14-bit centre. Each half is scaled by its own
        // span, so both extremes land exactly on ±1.
        assert(MIDIPitchBend.normalized(lsb: 0, msb: 64) == 0)
        // The upper half has 8191 steps, so a zero fine byte at full coarse
        // travel sits just under full bend; only 127/127 reaches exactly 1.
        let upper = MIDIPitchBend.normalized(lsb: 0, msb: 127)
        assert(upper > 0.98 && upper < 1, "the upper half is scaled by its own span")
        assert(MIDIPitchBend.normalized(lsb: 0, msb: 0) == -1)
        assert(MIDIPitchBend.normalized(lsb: 127, msb: 127) == 1)
        // Bit 7 of each data byte is reserved, so it must not change the reading.
        assert(MIDIPitchBend.normalized(lsb: 0x80, msb: 0x80) == -1)
        let quarter = MIDIPitchBend.normalized(lsb: 0, msb: 80)
        assert(quarter > 0.24 && quarter < 0.26, "10240 is a quarter of the upper half, not half")

        for position: Float in [-1, -0.5, 0, 0.25, 1] {
            let bytes = MIDIPitchBend.bytes(normalized: position)
            let round = MIDIPitchBend.normalized(lsb: bytes.lsb, msb: bytes.msb)
            assert(abs(round - position) < 0.001, "wheel round trip drifted from \(position) to \(round)")
        }
        assert(MIDIPitchBend.bytes(normalized: 0) == (0, 64))
        assert(MIDIPitchBend.bytes(normalized: 4) == (127, 127), "input is clamped, never wrapped")
        assert(MIDIPitchBend.bytes(normalized: -4) == (0, 0))
        assert(MIDIPitchBend.bytes(normalized: .nan) == (0, 64), "a non-finite value recentres")
        assert(MIDIPitchBend.bytes(normalized: .infinity) == (0, 64))

        // Production store with a generated MIDI source and the generated
        // library fixture. No audio device, plug-in or hardware is required.
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline(); store.start()
        defer { store.stopAudio() }
        var client = MIDIClientRef(), source = MIDIEndpointRef()
        assert(MIDIClientCreateWithBlock("Generated pitch-bend MIDI client" as CFString, &client, nil) == noErr)
        assert(MIDISourceCreate(client, "Generated pitch-bend keyboard" as CFString, &source) == noErr)
        defer { MIDIEndpointDispose(source); MIDIClientDispose(client) }
        func wait(_ predicate: () -> Bool) {
            let deadline = Date().addingTimeInterval(5)
            while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
            assert(predicate())
        }
        func send(_ status: UInt8, _ a: UInt8, _ b: UInt8) {
            var list = MIDIPacketList()
            withUnsafeMutablePointer(to: &list) { pointer in
                let packet = MIDIPacketListInit(pointer)
                let bytes = [status, a, b]
                bytes.withUnsafeBufferPointer { _ = MIDIPacketListAdd(pointer, MemoryLayout<MIDIPacketList>.size, packet, 0, 3, $0.baseAddress!) }
                assert(MIDIReceived(source, pointer) == noErr)
            }
        }
        wait { store.midiSources.contains { $0.endpoint == source } }
        wait { store.audio.externalRack?.unit(channel: 0) != nil }
        let identity = store.midiSources.first { $0.endpoint == source }!.id
        store.primarySourceID = identity; store.midiChannel = -1; store.secondarySourceID = -2
        guard let rack = store.audio.externalRack else { fatalError("The generated fixture rack did not load") }
        assert(store.pitchBend == 0, "A fresh session starts centred")

        // A primary controller bends the hosted sampler: the wheel reaches it as
        // a real 0xE0 event with the bytes the hardware sent.
        rack.debugClearMIDIEvents()
        send(0xE0, 127, 127)
        wait { store.pitchBend == 1 }
        wait { rack.debugMIDIEvents.contains { $0.status == 0xE0 && $0.data1 == 127 && $0.data2 == 127 } }

        // A secondary controller owns no notes, so it cannot bend them either.
        store.primarySourceID = -2; store.secondarySourceID = identity
        store.pitchBend = 0
        rack.debugClearMIDIEvents()
        store.midiLog = []
        send(0xE0, 0, 0)
        wait { store.midiLog.contains { $0.contains("E0") } }
        assert(store.pitchBend == 0, "a secondary controller cannot bend the primary keyboard")
        assert(!rack.debugMIDIEvents.contains { $0.status == 0xE0 }, "the rejected bend was forwarded anyway")

        // Panic returns the wheel to centre so a discarded bend cannot transpose
        // the next chord, and a centred wheel is forwarded unchanged.
        store.primarySourceID = identity; store.secondarySourceID = -2
        rack.debugClearMIDIEvents()
        send(0xE0, 127, 127)
        wait { store.pitchBend == 1 }
        store.panic()
        assert(store.pitchBend == 0)
        assert(rack.debugMIDIEvents.contains { $0.status == 0xE0 && $0.data1 == 0 && $0.data2 == 64 }, "Panic recentres the wheel")
        rack.debugClearMIDIEvents()
        send(0xE0, 0, 64)
        wait { store.pitchBend == 0 }
        wait { rack.debugMIDIEvents.contains { $0.status == 0xE0 && $0.data1 == 0 && $0.data2 == 64 } }
        assert(rack.debugActiveNoteCount(0) == 0)

        store.stopAudio()
        assert(store.pitchBend == 0, "Stopping audio also leaves the wheel centred")

        print("PASS: pitch-bend decoding, primary-only dispatch, forwarded 0xE0 bytes and a recentred wheel after Panic and Stop")
    }
}
