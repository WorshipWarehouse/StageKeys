import Foundation
import AVFoundation

@main struct AudioOperationCancelTests {
    static func main() throws {
        let store = PerformanceStore()
        store.setlist = TestFixtures.setlist()
        for channel in [0, 1] {
            let identity = ExternalAUIdentity(type: 0x61756d75, subtype: 0x63616e30 + UInt32(channel), manufacturer: 0x54657374, name: "Generated cancellable AU \(channel)")
            store.setlist.patches[1].layers[channel].external = ExternalSound(kind: .audioUnit, name: identity.name, component: identity)
        }
        try store.audio.prepareOffline()
        defer { store.stopAudio() }
        store.save()
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let path = root.appendingPathComponent("setlist.json")
        let saved = try Data(contentsOf: path)
        var attempts = 0
        store.audio.debugStartFailure = {
            attempts += 1
            return NSError(domain: NSPOSIXErrorDomain, code: 16)
        }
        func wait(_ predicate: () -> Bool) {
            let deadline = Date().addingTimeInterval(3)
            while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
            assert(predicate())
        }
        store.start()
        assert(store.audioOperationInProgress && store.audioIsStarting && !store.started)
        assert(attempts == 1)
        store.stopAudio()
        assert(!store.audioOperationInProgress && store.audioStartup == .stopped && !store.audio.running)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        store.startAutomatically(); store.refreshMIDI()
        assert(attempts == 1 && !store.started)
        // Existing retry bounds remain intact when the user does not cancel.
        store.start()
        wait { store.audioFailed }
        assert(attempts == 4 && !store.audioOperationInProgress)
        store.startAutomatically()
        assert(attempts == 4 && store.audioFailed)
        store.start()
        assert(attempts == 5 && store.audioOperationInProgress)
        store.stopAudio()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        assert(attempts == 5)
        store.audio.debugStartFailure = nil
        store.start()
        assert(store.started && store.audio.running && !store.audioOperationInProgress)
        let rack = store.audio.externalRack!
        var replies: [(AVAudioUnit?, Error?) -> Void] = []
        rack.debugInstantiate = { _, reply in replies.append(reply) }
        store.choose(1)
        assert(store.audioOperationInProgress && store.patchLoading && replies.count == 2)
        store.stopAudio()
        assert(!store.audioOperationInProgress && store.audioStartup == .stopped)
        let failureID = store.audio.lastChangeFailure?.requestID
        let count = rack.debugInstantiationCallbacks + 2
        let cancelled = AVAudioUnitSampler()
        replies.removeFirst()(cancelled, nil)
        replies.removeFirst()(nil, NSError(domain: NSOSStatusErrorDomain, code: -1))
        wait { rack.debugInstantiationCallbacks == count }
        assert(cancelled.engine == nil && !store.started && !store.audio.running)
        assert(!store.audioOperationInProgress && store.audio.lastChangeFailure?.requestID == failureID)
        assert((try! ExternalInstrumentRack.blockedComponentIDs()).isEmpty, "Cancellation is not a plugin execution failure")
        assert((try! Data(contentsOf: path)) == saved)
        store.choose(0); store.start()
        assert(store.started && !store.audioOperationInProgress)
        store.noteOn(64)
        var energy = 0.0
        for _ in 0..<20 {
            let block = try store.audio.offlineBlock()
            for frame in 0..<Int(block.frameLength) { let value = block.floatChannelData![0][frame]; assert(value.isFinite); energy += Double(value * value) }
        }
        assert(energy > 0.01)
        store.noteOff(64)
        print("PASS cancellation: retry backoff, bounded failure, explicit retry, late AU callbacks, unchanged session and rendered recovery")
    }
}
