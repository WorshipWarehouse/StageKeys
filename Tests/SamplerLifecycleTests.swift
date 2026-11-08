import AVFoundation
import Foundation

/// #192: a hosted sampler that leaves the graph must be quiesced, disconnected,
/// detached and released while the engine is stopped, and a retired sampler must
/// never re-enter the restoration list for a later transaction. This drives more
/// switches than the two-tail retention bound with generated tones.
@main
struct SamplerLifecycleTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("stagekeys-sampler-lifecycle-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let audio = AudioController()
        defer { audio.stop() }
        guard let rack = audio.externalRack else {
            throw NSError(domain: "StageKeysSamplerLifecycle", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The external instrument rack was unavailable"])
        }
        audio.master(1)
        audio.space(0)
        try audio.prepareOffline()

        func importedTone(_ name: String, frequency: Double) throws -> ExternalSound {
            let url = folder.appendingPathComponent(name + ".wav")
            let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
            buffer.frameLength = 48_000
            for frame in 0..<48_000 {
                buffer.floatChannelData![0][frame] = 0.2 * sin(Float(frame) * 2 * .pi * Float(frequency) / 48_000)
            }
            do {
                let file = try AVAudioFile(forWriting: url, settings: format.settings)
                try file.write(from: buffer)
            }
            return try rack.importSound(url)
        }
        func load(_ sound: ExternalSound) throws {
            var failure: Error?
            rack.load(sound, channel: 0) { if case .failure(let error) = $0 { failure = error } }
            if let failure { throw failure }
            assert(rack.contains(0))
        }
        func energy(_ blocks: Int) throws -> Double {
            var total = 0.0
            for _ in 0..<blocks {
                let buffer = try audio.offlineBlock()
                for frame in 0..<Int(buffer.frameLength) {
                    let sample = buffer.floatChannelData![0][frame]
                    assert(sample.isFinite)
                    total += Double(sample * sample)
                }
            }
            return total
        }

        let tones = try [("Piano", 261.626), ("Organ", 329.628), ("Pad", 392.0), ("Keys", 523.251)].map {
            try importedTone($0.0, frequency: $0.1)
        }

        // Three replacements exceed the two-tail bound, so the oldest tail is
        // truncated while the rest are retained across the same transactions.
        for (index, tone) in tones.enumerated() {
            let restoredBefore = rack.samplerRestorationCount
            try load(tone)
            let restored = rack.samplerRestorationCount - restoredBefore
            assert(restored <= 1, "Switch \(index) restored \(restored) samplers; a retired tail must not be reloaded")
            assert(rack.debugRetiredTailCount <= 2, "Switch \(index) exceeded the documented two-tail bound")
            assert(audio.running, "Switch \(index) must leave the engine running")
            rack.noteOn(channel: 0, key: 60, pitch: 60, velocity: 0.8)
            assert(try energy(20) > 1e-6, "Switch \(index) must leave a playable instrument")
            rack.noteOff(channel: 0, key: 60)
            _ = try energy(4)
        }

        let ledger = rack.debugSamplerLifecycle
        assert(ledger.contains { $0.phase == .attached }, "Every hosted sampler must record its attachment")
        assert(ledger.contains { $0.phase == .retired }, "Replacing an instrument must record its retirement")
        assert(ledger.contains { $0.phase == .evicted }, "Exceeding the tail bound must record the truncation")
        assert(ledger.filter { $0.phase == .evicted }.allSatisfy { !$0.engineRunning },
               "A truncated tail must be disposed while the graph transaction has stopped the engine")
        assert(ledger.filter { $0.phase == .released }.count >= 1,
               "A truncated sampler must be observed as released")
        assert(ledger.filter { $0.phase == .released }.allSatisfy { !$0.engineRunning && !$0.attached },
               "A sampler must never be released while the engine is running or while it is still attached")
        assert(!ledger.contains { $0.phase == .evicted && $0.retainedTail },
               "Eviction must run after the tail is removed from the retention list")

        // Silent tails are purged at the next stopped graph point, not dropped
        // from the list while the engine renders them.
        rack.panic()
        try rack.withGraphChanges { try rack.remove(0) }
        let purged = rack.debugSamplerLifecycle.filter { $0.phase == .purged }
        assert(!purged.isEmpty && purged.allSatisfy { !$0.engineRunning },
               "Silent tails must be purged while the engine is stopped")
        assert(audio.running, "The purge transaction must restore a running engine")
        assert(rack.debugRetiredTailCount == 1, "Only the voice retired by this transaction may remain")

        // A release observed after the engine restarted would mean a sampler was
        // retained past the transaction's safe disposal point.
        let afterPurge = rack.debugSamplerLifecycle.filter { $0.phase == .released }
        assert(afterPurge.allSatisfy { !$0.engineRunning && !$0.attached },
               "No sampler may be released while audio is running")
        print("PASS: sampler teardown order, active-only restoration and bounded disposal evidence")
    }
}
