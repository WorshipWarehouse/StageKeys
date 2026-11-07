import Foundation

/// Persistence contract for the metronome controls. The engine's timing is
/// covered natively by MetronomeTests; this keeps saved settings bounded and
/// readable across versions.
@main struct MetronomeSettingsTests {
    static func main() throws {
        // Settings written before the metronome block existed stay readable and
        // fall back to the engine defaults.
        var legacy = SessionSettings(selectedPatchID: nil, activeSnapshotID: nil, notesMode: nil, modWheel: nil)
        assert(legacy.validate())
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        object.removeValue(forKey: "metronomeSettings")
        let decodedLegacy = try JSONDecoder().decode(SessionSettings.self, from: JSONSerialization.data(withJSONObject: object))
        assert(decodedLegacy.metronomeSettings == nil && decodedLegacy.validate())

        var settings = MetronomeSettings()
        assert(settings.validate() && settings.visible && settings.followsMaster)
        // Count-in is off for new and existing settings and reads back as a label.
        assert(settings.countInBars == 0 && settings.countInLabel == "Off")
        var metroObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        metroObject.removeValue(forKey: "countInBars")
        let legacyMetronome = try JSONDecoder().decode(MetronomeSettings.self, from: JSONSerialization.data(withJSONObject: metroObject))
        assert(legacyMetronome.countInBars == 0 && legacyMetronome.validate())
        assert(settings.level > 0 && settings.levelDBFS != nil)

        // Every control round-trips through settings.json.
        settings.visible = false
        settings.preset = 1
        settings.level = 0
        settings.beatVelocity = 0.25
        settings.downbeatEnabled = false
        settings.downbeatVelocity = 0.5
        settings.beatsPerBar = 7
        settings.accentEvery = 3
        settings.subdivision = 4
        settings.countInBars = 2
        settings.followsMaster = false
        assert(settings.validate() && settings.levelDBFS == nil)
        legacy.metronomeSettings = settings
        assert(legacy.validate())
        let restored = try JSONDecoder().decode(SessionSettings.self, from: JSONEncoder().encode(legacy))
        assert(restored.metronomeSettings == settings)

        // A hand-edited or older value outside the engine's bounds is refused at
        // launch rather than being clamped silently.
        func rejected(_ change: (inout MetronomeSettings) -> Void) -> Bool {
            var value = MetronomeSettings()
            change(&value)
            return !value.validate()
        }
        assert(rejected { $0.preset = -1 })
        assert(rejected { $0.preset = MetronomeSettings.presets.count })
        assert(rejected { $0.level = -0.1 })
        assert(rejected { $0.level = 1.1 })
        assert(rejected { $0.level = .nan })
        assert(rejected { $0.beatVelocity = -0.1 })
        assert(rejected { $0.downbeatVelocity = 2 })
        assert(rejected { $0.beatsPerBar = 0 })
        assert(rejected { $0.beatsPerBar = 17 })
        assert(rejected { $0.accentEvery = -1 })
        assert(rejected { $0.accentEvery = 17 })
        assert(rejected { $0.subdivision = 0 })
        assert(rejected { $0.subdivision = 5 })
        assert(rejected { $0.countInBars = -1 })
        assert(rejected { $0.countInBars = 3 })
        var invalid = SessionSettings(selectedPatchID: nil, activeSnapshotID: nil, notesMode: nil, modWheel: nil)
        invalid.metronomeSettings = MetronomeSettings()
        invalid.metronomeSettings?.level = 2
        assert(!invalid.validate())

        print("PASS: metronome defaults, bounded controls, count-in, legacy settings and JSON round trip")
    }
}
