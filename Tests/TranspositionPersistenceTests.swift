import Foundation

/// Persistence and migration acceptance coverage for #111: Play In, Hear In,
/// direction, octave shift and tempo lock must survive setlist save/reload,
/// duplication, schema upgrade and documents written before the fields existed,
/// without changing the stored playback transposition.
@main struct TranspositionPersistenceTests {
    #if canImport(AVFoundation)
    static func keyedPatch(play: Int, hear: Int, direction: KeyDirection, octave: Int, locked: Bool?) -> Patch {
        var patch = Patch(name: "Keyed", layers: [Layer.empty()], snapshots: [])
        patch.playIn = play
        patch.hearIn = hear
        patch.keyDirection = direction
        patch.octaveShift = octave
        patch.transpose = PatchTransposition.semitones(playIn: play, hearIn: hear, direction: direction, octave: octave)
        patch.tempo = 137
        patch.tempoLocked = locked
        return patch
    }
    #endif

    static func main() throws {
        // `Patch` reaches AVFoundation through its sound and device types, so this
        // program is compiled and run by the macOS library gate. On a Linux
        // toolchain there is nothing to load, and reporting a pass would be
        // misleading, so it says so instead.
        #if canImport(AVFoundation)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        // --- Every key pair and direction survives a save/reload ------------
        for play in 0..<12 {
            for hear in 0..<12 {
                for direction in KeyDirection.allCases {
                    for octave in -2...2 {
                        let patch = keyedPatch(play: play, hear: hear, direction: direction, octave: octave, locked: false)
                        let reloaded = try decoder.decode(Patch.self, from: encoder.encode(patch))
                        assert(reloaded.playIn == play && reloaded.hearIn == hear,
                               "Keys must reload unchanged for \(play) -> \(hear)")
                        assert(reloaded.keyDirection == direction, "Direction must reload unchanged")
                        assert(reloaded.octaveShift == octave, "Octave shift must reload unchanged")
                        assert(reloaded.tempoLocked == false, "Tempo lock must reload unchanged")
                        assert(reloaded.tempo == 137, "Patch tempo must reload unchanged")
                        assert(reloaded.transpose == patch.transpose,
                               "Reload must not change the playback transposition")
                        assert(reloaded.octaveShiftResolved == octave,
                               "A saved octave shift is used as stored, not re-derived")
                        assert(reloaded.recallsPatchTempo == false,
                               "An unlocked patch stays unlocked after reload")
                    }
                }
            }
        }

        // --- A whole setlist round-trips, not just one patch ----------------
        var setlist = Setlist()
        setlist.name = "Persistence"
        setlist.patches = [
            keyedPatch(play: 2, hear: 0, direction: .nearest, octave: 1, locked: false),
            keyedPatch(play: 9, hear: 4, direction: .down, octave: -1, locked: true),
            keyedPatch(play: 0, hear: 0, direction: .up, octave: 0, locked: nil)
        ]
        let setlistReloaded = try decoder.decode(Setlist.self, from: encoder.encode(setlist))
        for (saved, reloaded) in zip(setlist.patches, setlistReloaded.patches) {
            assert(reloaded.id == saved.id && reloaded.name == saved.name)
            assert(reloaded.playIn == saved.playIn && reloaded.hearIn == saved.hearIn)
            assert(reloaded.keyDirection == saved.keyDirection && reloaded.octaveShift == saved.octaveShift)
            assert(reloaded.tempoLocked == saved.tempoLocked)
            assert(reloaded.transpose == saved.transpose && reloaded.tempo == saved.tempo)
        }
        assert(setlistReloaded.patches[2].tempoLocked == nil,
               "An absent lock stays absent instead of becoming an explicit value")

        // --- Duplication copies the musical settings, not the identity ------
        let source = keyedPatch(play: 2, hear: 0, direction: .nearest, octave: 1, locked: false)
        let copy = source.duplicate()
        assert(copy.id != source.id, "A duplicate gets its own identity")
        assert(copy.playIn == source.playIn && copy.hearIn == source.hearIn)
        assert(copy.keyDirection == source.keyDirection && copy.octaveShift == source.octaveShift)
        assert(copy.tempoLocked == source.tempoLocked)
        assert(copy.transpose == source.transpose && copy.tempo == source.tempo,
               "A duplicate keeps the exact sounding transposition and tempo")

        // --- Schema upgrade keeps the fields -------------------------------
        var legacyVersion = setlist
        legacyVersion.version = 3
        let upgraded = try decoder.decode(Setlist.self, from: encoder.encode(legacyVersion)).upgraded()
        assert(upgraded.version == Setlist().version, "An older document upgrades to the current schema")
        for (saved, result) in zip(setlist.patches, upgraded.patches) {
            assert(result.transpose == saved.transpose && result.playIn == saved.playIn && result.hearIn == saved.hearIn)
            assert(result.keyDirection == saved.keyDirection && result.octaveShift == saved.octaveShift)
            assert(result.tempoLocked == saved.tempoLocked)
        }

        // --- Documents written before these fields existed -----------------
        // Strip the five keys from a real encoded patch: the reload must keep
        // playing the same transposition and derive the octave for display.
        let modern = keyedPatch(play: 2, hear: 0, direction: .down, octave: -1, locked: true)
        var object = try JSONSerialization.jsonObject(with: encoder.encode(modern)) as! [String: Any]
        for key in ["playIn", "hearIn", "keyDirection", "octaveShift", "tempoLocked"] {
            object.removeValue(forKey: key)
        }
        let legacy = try decoder.decode(Patch.self, from: JSONSerialization.data(withJSONObject: object))
        assert(legacy.transpose == modern.transpose, "A legacy patch keeps its exact transposition")
        assert(legacy.playIn == 0, "A legacy patch keeps the old default performed key")
        assert(legacy.hearIn == ((modern.transpose % 12) + 12) % 12,
               "A legacy patch derives its sounding key from the stored transposition")
        assert(legacy.octaveShift == nil && legacy.keyDirection == nil,
               "Legacy fields stay absent rather than being rewritten on load")
        assert(legacy.octaveShiftResolved == -1,
               "The derived octave explains the stored total")
        assert(legacy.recallsPatchTempo, "A legacy patch keeps recalling its own tempo")
        // Re-encoding the legacy patch must not invent the new keys in the file.
        let legacyText = String(decoding: try encoder.encode(legacy), as: UTF8.self)
        assert(!legacyText.contains("\"keyDirection\"") && !legacyText.contains("\"octaveShift\"")
               && !legacyText.contains("\"tempoLocked\""),
               "Loading a legacy patch does not rewrite its document with invented values")

        // --- Tempo lock resolution is stable across reload ------------------
        let locked = try decoder.decode(Patch.self, from: encoder.encode(keyedPatch(play: 5, hear: 7, direction: .up, octave: 0, locked: true)))
        let unlocked = try decoder.decode(Patch.self, from: encoder.encode(keyedPatch(play: 5, hear: 7, direction: .up, octave: 0, locked: false)))
        assert(PatchTransposition.resolvedTempo(locked: locked.tempoLocked, patchTempo: locked.tempo, liveTempo: 90) == 137,
               "A locked patch recalls its own tempo after reload")
        assert(PatchTransposition.resolvedTempo(locked: unlocked.tempoLocked, patchTempo: unlocked.tempo, liveTempo: 90) == 90,
               "An unlocked patch keeps the shared live tempo after reload")

        // --- The live tempo is part of the persisted session ----------------
        var settings = SessionSettings()
        settings.liveTempo = 108
        let settingsReloaded = try decoder.decode(SessionSettings.self, from: encoder.encode(settings))
        assert(settingsReloaded.liveTempo == 108, "The shared live tempo round-trips")
        assert(settingsReloaded.validate(), "A persisted live tempo passes validation")
        var outOfRange = settings
        outOfRange.liveTempo = 400
        assert(!outOfRange.validate(), "An out-of-range live tempo is rejected")
        var notANumber = settings
        notANumber.liveTempo = .nan
        assert(!notANumber.validate(), "A non-finite live tempo is rejected")
        var absent = SessionSettings()
        absent.liveTempo = nil
        assert(absent.validate(), "A session without a live tempo still loads")

        print("PASS: keys, direction, octave, tempo lock and patch tempo survive save/reload, setlist round-trip, duplication, schema upgrade and legacy documents without changing the stored transposition")
        #else
        print("SKIP: Patch and Setlist use AVFoundation types; run this program in the macOS library gate")
        #endif
    }
}
