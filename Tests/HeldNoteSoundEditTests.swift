import Foundation
import AVFoundation

/// Confirm must not cut a note that nothing has replaced. Editing a sound's
/// envelope, Mod Filter, pan or fader used to panic the channel on every commit,
/// so a sustained note stopped as soon as the edit was confirmed (#112).
@main struct HeldNoteSoundEditTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline()
        defer { store.stopAudio() }
        store.start()
        store.audio.space(0)
        store.save()
        let original = store.patch.layers[0]
        assert(original.external != nil)

        func energy(_ blocks: Int = 40) throws -> Double {
            var total = 0.0
            for _ in 0..<blocks {
                let buffer = try store.audio.offlineBlock()
                for channel in 0..<2 {
                    for frame in 0..<Int(buffer.frameLength) {
                        let sample = buffer.floatChannelData![channel][frame]
                        assert(sample.isFinite)
                        total += Double(sample * sample)
                    }
                }
            }
            return total
        }

        store.noteOn(60)
        store.setSustain(true)
        _ = try energy()
        let before = try energy()
        assert(before > 0.01, "The generated fixture must be audible before the edit")
        let unit = store.audio.externalRack!.unit(channel: 0)!

        // Shaping-only edit: same generated instrument, different envelope,
        // Mod Filter and pan. `audio.configure` applies these to the installed
        // voice, so nothing has to be released.
        var shaped = original
        shaped.channelSettings.attack = 0.05
        shaped.channelSettings.filterMin = 8000
        shaped.channelSettings.filterMax = 16000
        shaped.channelSettings.resonance = 0.9
        shaped.pan = -0.2
        store.commitLayer(0, shaped)
        assert(store.patch.layers[0] == shaped, "A valid shaping edit must commit")
        assert(store.audio.externalRack!.unit(channel: 0) === unit, "A shaping edit must keep the installed instrument")
        assert(store.held.contains(60), "Confirm must not release a note held on the unchanged instrument")
        assert(store.sustain, "Confirm must keep pedal ownership")
        assert(store.audio.running)
        let after = try energy()
        assert(after > before * 0.2, "The held note must keep rendering after a shaping edit")

        // Replacing the instrument still releases the retired voice: that is a
        // real replacement, not a shaping edit of the sound that is sounding.
        var replacement = TestFixtures.layer(1, gain: 0.2)
        replacement.id = original.id
        store.commitLayer(0, replacement)
        assert(store.patch.layers[0].external == replacement.external)
        assert(store.audio.externalRack!.unit(channel: 0) !== unit)
        _ = try energy(80)
        let replaced = try energy()
        assert(replaced < before * 0.05, "A replaced instrument must stop the retired voice")

        // Panic remains the explicit way to clear a channel.
        store.panic()
        assert(store.held.isEmpty && !store.sustain)
        print("PASS: a shaping-only sound edit keeps the held note and pedal while a replaced instrument releases it")
    }
}
