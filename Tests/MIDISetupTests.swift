import Foundation
import CoreMIDI

/// Model tests for external MIDI routing and controller setup. These run without
/// hardware or external apps; ExternalMIDITests covers the real virtual port.
@main struct MIDISetupTests {
    static func main() throws {
        // Velocity scaling: endpoints, midpoint, a narrowed range and an inverted
        // range (which must clamp instead of inverting the response).
        assert(abs(MIDIControllerRules.velocity(0, minimum: 0, maximum: 127)) < 0.000001)
        assert(abs(MIDIControllerRules.velocity(127, minimum: 0, maximum: 127) - 1) < 0.000001)
        assert(abs(MIDIControllerRules.velocity(64, minimum: 0, maximum: 127) - 64.0 / 127) < 0.000001)
        assert(abs(MIDIControllerRules.velocity(0, minimum: 40, maximum: 90) - 40.0 / 127) < 0.000001)
        assert(abs(MIDIControllerRules.velocity(127, minimum: 40, maximum: 90) - 90.0 / 127) < 0.000001)
        assert(abs(MIDIControllerRules.velocity(127, minimum: 90, maximum: 40) - 90.0 / 127) < 0.000001)
        let low = MIDIControllerRules.velocity(20, minimum: 0, maximum: 127)
        let high = MIDIControllerRules.velocity(110, minimum: 0, maximum: 127)
        assert(low < high && low >= 0 && high <= 1)

        // Primary/secondary input acceptance, including unused slots and channel
        // filters. -1 means any, -2 means the slot is unused.
        assert(MIDIControllerRules.accepts(sourceID: -1, channel: -1, source: 42, inputChannel: 3))
        assert(MIDIControllerRules.accepts(sourceID: 42, channel: 3, source: 42, inputChannel: 3))
        assert(!MIDIControllerRules.accepts(sourceID: 42, channel: 3, source: 42, inputChannel: 4))
        assert(!MIDIControllerRules.accepts(sourceID: 42, channel: 3, source: 43, inputChannel: 3))
        assert(!MIDIControllerRules.accepts(sourceID: -2, channel: -1, source: 42, inputChannel: 3))
        assert(!MIDIControllerRules.accepts(sourceID: -1, channel: 3, source: 42, inputChannel: 2))

        // Learning moves a CC from its previous owner and reports the conflict.
        let master = MIDIControlTarget.master, next = MIDIControlTarget.nextPatch
        var learned = MIDIControllerRules.assigning(20, to: next, assignments: [20: master], soundLevels: [:])
        assert(learned.assignments[20] == next && learned.displaced == master && !learned.reserved)
        // A target owns one CC, so learning a new one releases the previous one.
        learned = MIDIControllerRules.assigning(21, to: next, assignments: learned.assignments, soundLevels: [:])
        assert(learned.assignments[21] == next && learned.assignments[20] == nil)
        // Sound levels use the legacy CC→layer map and stay exclusive as well.
        learned = MIDIControllerRules.assigning(22, to: .soundLevel(3), assignments: [22: master], soundLevels: [23: 7])
        assert(learned.soundLevels[22] == 3 && learned.assignments[22] == nil && learned.displaced == master)
        learned = MIDIControllerRules.assigning(23, to: .soundLevel(3), assignments: [:], soundLevels: [22: 3, 23: 7])
        assert(learned.soundLevels[23] == 3 && learned.soundLevels[22] == nil)
        assert(learned.displaced == MIDIControlTarget.soundLevel(7))
        // Re-learning the same CC on the same target is not a conflict.
        assert(MIDIControllerRules.assigning(20, to: master, assignments: [20: master], soundLevels: [:]).displaced == nil)
        // Reserved controllers keep their fixed route and are never learned.
        for reserved in MIDIControlTarget.reservedCCs {
            let rejected = MIDIControllerRules.assigning(reserved, to: next, assignments: [:], soundLevels: [:])
            assert(rejected.reserved && rejected.assignments.isEmpty)
        }
        // Out-of-range CCs and invalid targets are rejected.
        assert(MIDIControllerRules.assigning(128, to: next, assignments: [:], soundLevels: [:]).reserved)
        assert(MIDIControllerRules.assigning(24, to: .soundLevel(15), assignments: [:], soundLevels: [:]).reserved)
        assert(MIDIControllerRules.assigning(24, to: .snapshot(16), assignments: [:], soundLevels: [:]).reserved)

        // Destination ordering keeps the hosted port first, then online devices by
        // name, then offline devices so a disconnected interface stays visible.
        let virtual = ExternalMIDIDestination(id: ExternalMIDIOutput.broadcastID, name: "StageKeys to External App", endpoint: 0, online: true, virtual: true)
        let bus = ExternalMIDIDestination(id: 11, name: "IAC Bus 1", endpoint: 1)
        let offline = ExternalMIDIDestination(id: 12, name: "USB Interface", endpoint: 2, online: false)
        let loopback = ExternalMIDIDestination(id: 13, name: "Loopback", endpoint: 3)
        let sorted = ExternalMIDIRouting.sorted([offline, bus, loopback, virtual])
        assert(sorted.map(\.id) == [ExternalMIDIOutput.broadcastID, 11, 13, 12], "Unexpected destination order: \(sorted.map(\.name))")
        // A destination that resolves to our own virtual source is a loop.
        assert(ExternalMIDIRouting.isLoop(loopback, ownSourceID: 13))
        assert(!ExternalMIDIRouting.isLoop(virtual, ownSourceID: 13))
        assert(!ExternalMIDIRouting.isLoop(bus, ownSourceID: 13))
        assert(ExternalMIDIRouting.resolve(11, in: sorted, ownSourceID: 13)?.name == "IAC Bus 1")
        assert(ExternalMIDIRouting.resolve(12, in: sorted, ownSourceID: 13) == nil, "An offline output must not be used")
        assert(ExternalMIDIRouting.resolve(13, in: sorted, ownSourceID: 13) == nil, "The app's own source must not be a send target")
        assert(ExternalMIDIRouting.resolve(99, in: sorted, ownSourceID: 13) == nil)

        // Session settings must round-trip the controller setup that used to reset
        // on launch: metronome preference and hardware buffer.
        var settings = SessionSettings(selectedPatchID: nil, activeSnapshotID: nil, notesMode: nil, modWheel: nil)
        settings.metronomeEnabled = true
        settings.audioBufferFrames = 256
        settings.primarySourceID = 42
        settings.secondarySourceID = -2
        settings.secondaryChannel = 5
        settings.velocityMinimum = 30
        settings.velocityMaximum = 100
        settings.midiChannel = 2
        settings.sourceNames = [42: "Keyboard"]
        assert(settings.validate())
        let restored = try JSONDecoder().decode(SessionSettings.self, from: JSONEncoder().encode(settings))
        assert(restored.metronomeEnabled == true && restored.audioBufferFrames == 256)
        assert(restored.primarySourceID == 42 && restored.secondaryChannel == 5)
        assert(restored.velocityMinimum == 30 && restored.velocityMaximum == 100 && restored.midiChannel == 2)
        assert(restored.sourceNames?[42] == "Keyboard")
        // An impossible buffer size is rejected instead of being applied at launch.
        var invalid = settings
        invalid.audioBufferFrames = 100_000
        assert(!invalid.validate())
        // Settings written before these fields existed must still decode.
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        object.removeValue(forKey: "metronomeEnabled")
        object.removeValue(forKey: "audioBufferFrames")
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SessionSettings.self, from: legacy)
        assert(decoded.metronomeEnabled == nil && decoded.audioBufferFrames == nil)
        assert(decoded.validate(), "Settings written before these fields existed must stay readable")

        print("PASS: velocity scaling, primary/secondary acceptance, learn conflicts and reset rules, destination ordering/availability/loop guard, settings persistence")
    }
}
