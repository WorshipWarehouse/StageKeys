import Foundation

@main
struct ModelTests {
    static func main() throws {
        let original = Setlist()
        try original.validate()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Setlist.self, from: data)
        assert(decoded.patches.map(\.name) == original.patches.map(\.name))
        var copy = original.patches[0].duplicate()
        assert(copy.id != original.patches[0].id)
        copy.layers[0].gain = 0
        assert(original.patches[0].layers[0].gain > 0)
        assert(copy.layers[0].id != original.patches[0].layers[0].id)
        func rejected(_ value: Setlist) { do { try value.validate(); fatalError("Invalid setlist accepted") } catch {} }
        var bad = original; bad.patches = []; rejected(bad)
        bad = original; bad.patches[0].layers[0].high = -1; rejected(bad)
        bad = original; bad.patches[0].layers[0].gain = .nan; rejected(bad)
        bad = original; bad.patches[0].snapshots[0].gains = [1]; rejected(bad)
        bad = original; bad.patches[1].id = bad.patches[0].id; rejected(bad)
        bad = original; bad.assignments[200] = 9; rejected(bad)
        assert(original.patches[0].layers.count == 15)
        var legacy = original; legacy.version = 1
        for i in legacy.patches.indices {
            legacy.patches[i].layers = Array(legacy.patches[i].layers.prefix(3))
            for j in legacy.patches[i].snapshots.indices { legacy.patches[i].snapshots[j].gains = Array(legacy.patches[i].snapshots[j].gains.prefix(3)) }
        }
        // Strip all newly introduced keys to emulate a real v0.1 document.
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        var patches = object["patches"] as! [[String: Any]]
        for i in patches.indices {
            for key in ["playIn","hearIn","visualMode","silencePrevious"] { patches[i].removeValue(forKey: key) }
            var layers = patches[i]["layers"] as! [[String: Any]]
            for j in layers.indices { for key in ["effects","pan","blockSustain","octaveEffect","channelSettings","external","pluginState","midiProgram","midiDestinationID","midiOutputChannel"] { layers[j].removeValue(forKey: key) } }
            patches[i]["layers"] = layers
        }
        object["patches"] = patches
        let migrated = try JSONDecoder().decode(Setlist.self, from: JSONSerialization.data(withJSONObject: object)).upgraded()
        assert(migrated.version == 4 && migrated.patches[0].layers.count == 15)
        assert(migrated.patches[0].layers[0].id == legacy.patches[0].layers[0].id)
        assert(migrated.patches[0].snapshots[0].gains.count == 15)
        assert(migrated.patches[0].layers[14].instrument == -1)
        bad = original; bad.patches[0].layers[0].effects = []; rejected(bad)
        bad = original; bad.patches[0].snapshots[0].beats = .nan; rejected(bad)
        bad = original; bad.patches[0].layers[0].pan = 2; rejected(bad)
        var v3 = original; v3.version=3
        let upgrade3=try JSONDecoder().decode(Setlist.self,from:JSONEncoder().encode(v3)).upgraded()
        assert(upgrade3.version==4 && upgrade3.patches[0].id==original.patches[0].id)
        // Snapshot recall captures performance state, not sound-editor shaping.
        var shaped = original.patches[0].layers[0]
        shaped.channelSettings.attack = 3; shaped.channelSettings.filterMin = 90; shaped.channelSettings.resonance = 6
        let captured = SnapshotSoundState(shaped)
        let capturedText = String(decoding: try JSONEncoder().encode(captured), as: UTF8.self)
        assert(!capturedText.contains("channelSettings") && !capturedText.contains("attack") && !capturedText.contains("filterMin"), "Snapshots must not store sound-editor envelope or filter values")
        assert(captured.effects == shaped.effects && captured.pan == shaped.pan)
        print("PASS: legacy migration and new rack bounds")
        print("PASS: setlist round-trip, independent duplicate identity and values, malformed setlist rejection")
    }
}
