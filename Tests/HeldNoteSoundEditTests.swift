import Foundation
import AVFoundation

/// Confirm must not cut a note that nothing has replaced. Editing a sound's
/// envelope, Mod Filter, pan or fader used to panic the channel on every commit,
/// so a sustained note stopped as soon as the edit was confirmed (#112).
@main struct HeldNoteSoundEditTests {
    /// The library gate only reports the terminating signal for a hosted
    /// failure, so name the stage that failed before stopping.
    static func check(_ ok: Bool, _ message: String, line: Int = #line) {
        if ok { return }
        print("::error file=Tests/HeldNoteSoundEditTests.swift,line=\(line)::\(message)")
        exit(1)
    }

    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline()
        defer { store.stopAudio() }
        store.start()
        store.audio.space(0)
        // Capture the fixture's scene so its layers keep their saved levels,
        // exactly as a performer arriving at a patch does.
        store.captureSnapshot(0)
        store.save()
        let original = store.patch.layers[0]
        check(original.external != nil, "fixture layer has a generated instrument")
        check(store.audio.running, "audio engine is running")

        func energy(_ blocks: Int = 20) throws -> Double {
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
        check(before > 0.01, "held note is audible before the edit (\(before))")
        guard let unit = store.audio.externalRack?.unit(channel: 0) else {
            check(false, "channel 0 has an installed unit before the edit")
            return
        }

        // Shaping-only edit: the same generated instrument with a different
        // envelope, Mod Filter and pan. `audio.configure` applies these to the
        // installed voice, so nothing has to be released.
        var shaped = original
        shaped.channelSettings.attack = 0.05
        shaped.channelSettings.filterMin = 8000
        shaped.channelSettings.filterMax = 16000
        shaped.channelSettings.resonance = 0.9
        shaped.pan = -0.2
        guard let audition = store.beginAudition(0) else {
            check(false, "sound editor audition starts")
            return
        }
        store.previewLayer(0, shaped, token: audition)
        store.confirmAudition(audition, index: 0, layer: shaped)
        check(store.patch.layers[0] == shaped,
              "shaping-only edit committed (message: \(store.message ?? "none"))")
        check(store.audio.externalRack?.unit(channel: 0) === unit,
              "shaping-only edit kept the installed instrument")
        check(store.held.contains(60), "shaping-only edit kept the held note")
        check(store.sustain, "shaping-only edit kept pedal ownership")
        let after = try energy()
        check(after > before * 0.8,
              "held note continues at its level (before \(before), after \(after))")

        // Confirm can be called before a preview reaches the graph. A routing
        // change must still release the previously owned MIDI notes.
        guard let directEdit=store.beginAudition(0) else {
            check(false,"a direct sound edit starts")
            return
        }
        var rerouted=shaped
        rerouted.transpose=12
        check(store.midiFX.activeOutputRange(channel:0) != nil,"the old route owns a held note")
        store.confirmAudition(directEdit,index:0,layer:rerouted)
        check(store.midiFX.activeOutputRange(channel:0)==nil,"Confirm without preview must release the old MIDI route")
        store.panic()

        // Replacing the instrument still takes over the channel and plays.
        var replacement = TestFixtures.layer(1, gain: 0.2)
        replacement.name = "Replacement"
        store.commitLayer(0, replacement)
        check(store.patch.layers[0] == replacement, "replacement committed")
        guard let replacementUnit = store.audio.externalRack?.unit(channel: 0) else {
            check(false, "replacement installed a unit on channel 0")
            return
        }
        check(replacementUnit !== unit,
              "replacement took over channel 0")
        for channel in 1..<16 { store.audio.gain(channel, 0, seconds: 0) }
        store.noteOn(64)
        let replacedEnergy = try energy()
        check(replacedEnergy > 0.001, "replacement instrument plays (\(replacedEnergy))")
        store.noteOff(64)
        store.setSustain(false)

        // A MIDI output-channel edit must release through the old route, and a
        // sampler setting that reloads the unit must clear its MIDI FX ownership.
        var routed = replacement
        routed.midiDestinationID = ExternalMIDIOutput.broadcastID
        routed.midiOutputChannel = 2
        store.commitLayer(0, routed)
        store.noteOn(67)
        check(store.midiFX.activeOutputRange(channel: 0) == 67...67,
              "MIDI output note is owned before the route changes")
        routed.midiOutputChannel = 3
        store.commitLayer(0, routed)
        check(store.midiFX.activeOutputRange(channel: 0) == nil,
              "MIDI output-channel change released the old note")
        store.noteOff(67)

        store.noteOn(69)
        check(store.midiFX.activeOutputRange(channel: 0) == 69...69,
              "MIDI output note is owned before the voice reload")
        routed.channelSettings.samplerAttackMinimum = 0.01
        store.commitLayer(0, routed)
        check(store.midiFX.activeOutputRange(channel: 0) == nil,
              "sampler voice reload cleared MIDI FX ownership")
        store.noteOff(69)

        // Panic remains the explicit way to clear a channel.
        store.panic()
        check(store.held.isEmpty && !store.sustain, "Panic cleared notes and pedal")
        print("PASS: Confirm preserves shaped held notes; voice replacement, MIDI rerouting and sampler reload clear old note ownership")
    }
}
