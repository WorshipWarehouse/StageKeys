import Foundation

/// Pure model tests for the Primary/Secondary controller split. No Core MIDI is
/// needed: the routing rule is a value type, so it runs without hardware.
@main struct MIDIControllerSlotsTests {
    static func main() {
        /// Primary on source 42 channel 3, Secondary on source 43 channel 4.
        let split = MIDIControllerSlots(primarySourceID: 42, primaryChannel: 3,
                                        secondarySourceID: 43, secondaryChannel: 4)
        // The Primary controller plays notes on its own source and channel.
        assert(split.acceptsNotes(source: 42, channel: 3))
        assert(split.acceptsControls(source: 42, channel: 3))
        // The Secondary controller drives learned controls but never notes.
        assert(split.acceptsControls(source: 43, channel: 4))
        assert(!split.acceptsNotes(source: 43, channel: 4))
        // Channel filters apply per slot and do not leak between roles.
        assert(!split.acceptsNotes(source: 42, channel: 4))
        assert(!split.acceptsNotes(source: 43, channel: 3))
        assert(!split.acceptsControls(source: 42, channel: 4))
        assert(!split.acceptsNotes(source: 44, channel: 3))
        assert(!split.acceptsControls(source: 44, channel: 3))

        // The shipped defaults accept notes and controls from any source.
        let automatic = MIDIControllerSlots()
        assert(automatic.acceptsNotes(source: 42, channel: 3))
        assert(automatic.acceptsControls(source: 42, channel: 3))
        assert(automatic.acceptsNotes(source: -7, channel: 15))

        // An unused Secondary slot (-2) accepts nothing; it cannot become a
        // second note source or a stray control surface.
        var unused = split
        unused.secondarySourceID = -2
        unused.secondaryChannel = -1
        assert(!unused.acceptsControls(source: 43, channel: 4))
        assert(!unused.acceptsNotes(source: 43, channel: 4))
        assert(unused.acceptsNotes(source: 42, channel: 3))

        // Selecting the same device in both slots keeps it playable.
        let twice = MIDIControllerSlots(primarySourceID: 42, primaryChannel: -1,
                                        secondarySourceID: 42, secondaryChannel: -1)
        assert(twice.acceptsNotes(source: 42, channel: 7))
        assert(twice.acceptsControls(source: 42, channel: 7))

        // A secondary-only setup stays a control surface: it drives learned
        // controls but the patch has no note source.
        let secondaryOnly = MIDIControllerSlots(primarySourceID: -2, primaryChannel: -1,
                                                secondarySourceID: 43, secondaryChannel: -1)
        assert(!secondaryOnly.acceptsNotes(source: 43, channel: 0))
        assert(secondaryOnly.acceptsControls(source: 43, channel: 0))
        assert(!secondaryOnly.acceptsNotes(source: 42, channel: 0))

        // A Primary wildcard keeps its documented meaning: any source plays notes,
        // while the Secondary slot can still add a control-only channel filter.
        let wildcardPrimary = MIDIControllerSlots(primarySourceID: -1, primaryChannel: 5,
                                                  secondarySourceID: 43, secondaryChannel: -1)
        assert(wildcardPrimary.acceptsNotes(source: 42, channel: 5))
        assert(!wildcardPrimary.acceptsNotes(source: 42, channel: 6))
        assert(wildcardPrimary.acceptsControls(source: 43, channel: 6))

        print("PASS: primary-only notes, secondary control surface, unused/wildcard/duplicate slots and per-slot channel filters")
    }
}
