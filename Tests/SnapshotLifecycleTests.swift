import Foundation
import AVFoundation

@main struct SnapshotLifecycleTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        try store.audio.prepareOffline(); store.start()
        defer { store.stopAudio() }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        func bytes() -> Data { try! encoder.encode(store.setlist) }
        func wait(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
        func target(_ seconds: Float = 0.25) -> Snapshot {
            var snapshot = Snapshot(name: "Generated lifecycle fade", gains: store.patch.layers.map { _ in 0.1 })
            snapshot.seconds = seconds; snapshot.modulation = 0.2
            snapshot.tonicLevel = 0.15; snapshot.tonicBrightness = 0.25
            snapshot.sounds = store.patch.layers.map(SnapshotSoundState.init)
            snapshot.sounds![0].pan = 0.7
            return snapshot
        }
        store.recall(target())
        wait(0.07)
        store.stopAudio()
        let stopped = bytes(), wheel = store.modWheel, tonicGain = store.tonicGain, brightness = store.tonicBrightness
        store.save()
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let saved = try Data(contentsOf: root.appendingPathComponent("setlist.json"))
        let settings = try Data(contentsOf: root.appendingPathComponent("settings.json"))
        wait(0.35)
        assert(bytes() == stopped, "Stop Audio must cancel snapshot document mutations")
        assert(store.modWheel == wheel && store.tonicGain == tonicGain && store.tonicBrightness == brightness)
        assert(store.activeSnapshot == nil && !store.audio.running && !store.started)
        assert((try! Data(contentsOf: root.appendingPathComponent("setlist.json"))) == saved)
        assert((try! Data(contentsOf: root.appendingPathComponent("settings.json"))) == settings)
        store.start()
        assert(store.started && store.audio.running)
        let snapshot = target(0.08)
        store.recall(snapshot); wait(0.16)
        assert(store.activeSnapshot == snapshot.id && abs(store.patch.layers[0].gain - 0.1) < 0.001)
        let completed = bytes()
        store.stopAudio(); wait(0.12)
        assert(bytes() == completed && store.activeSnapshot == snapshot.id, "A completed snapshot selection survives Stop")
        store.start()
        // Simulate an engine-configuration interruption on the offline route.
        // This exercises notification/retry ownership, not a physical device.
        var interruptedTarget = target(0.3)
        interruptedTarget.gains[0] = 0.8; interruptedTarget.sounds![0].pan = -0.5; interruptedTarget.modulation = 0.9
        store.recall(interruptedTarget); wait(0.06)
        store.audio.stop()
        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: nil)
        let interrupted = bytes(), interruptedWheel = store.modWheel
        wait(0.45)
        assert(bytes() == interrupted && store.modWheel == interruptedWheel && store.activeSnapshot == nil)
        assert(store.started && store.audio.running, "Existing configuration-change retry must still recover audio")
        // Direct document replacement is a safety-net case: an old timer may
        // never target a new patch at the same array index or different layers.
        store.recall(target())
        wait(0.05)
        store.setlist.patches[store.selected] = TestFixtures.setlist().patches[1]
        let replaced = bytes()
        wait(0.35)
        assert(bytes() == replaced && store.activeSnapshot == nil)
        store.recall(target())
        wait(0.05)
        store.setlist.patches[store.selected].layers[0].id = UUID()
        let layerReplaced = bytes()
        wait(0.35)
        assert(bytes() == layerReplaced && store.activeSnapshot == nil)
        // A superseded transition must not clear or overwrite the newer one.
        store.recall(target(0.3)); wait(0.04)
        var newer = target(0.05); newer.gains[0] = 0.6
        store.recall(newer); wait(0.4)
        assert(store.activeSnapshot == newer.id && abs(store.patch.layers[0].gain - 0.6) < 0.001)
        // Muted-to-live recall publishes the actual starting level, not a
        // visually unmuted stored gain that has not yet been heard.
        store.mute(0); assert(store.patch.layers[0].muted)
        store.recall(target())
        assert(!store.patch.layers[0].muted && store.patch.layers[0].gain == 0)
        store.stopAudio()
        store.start()
        let valid = bytes()
        var malformed = target(); malformed.seconds = .nan
        store.recall(malformed); wait(0.35)
        assert(bytes() == valid && store.message?.contains("invalid") == true)
        malformed = target(); malformed.beats = .infinity
        store.recall(malformed); wait(0.35)
        assert(bytes() == valid)
        print("PASS snapshot lifecycle: Stop, completion, patch/layer binding, supersession, muted start and invalid timing")
    }
}
