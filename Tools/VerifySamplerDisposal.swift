// Compile against the DEBUG StageKeysVerificationCore produced by the library runner.
// Explicit opt-in live output test; generated samples, isolated data, master muted.
@testable import StageKeysVerificationCore
import AVFoundation
import Foundation

@main struct VerifySamplerDisposal {
    struct Report: Codable {
        let schemaVersion: Int
        let operatingSystem: String
        let cycles: Int
        let elapsedSeconds: Double
        let sampleRate: Double
        let bufferFrames: UInt32
        let unchangedOutputRoute: Bool
        let framesObserved: UInt64
        let invalidOutputSamples: UInt64
        let verifiedReleases: Int
        let maximumRetiredTails: Int
        let maximumOwnedNodes: Int
        let originalScenario: String
        let scope: String
    }
    static func main() throws {
        guard CommandLine.arguments.count == 2,
              let data = ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"] else {
            fatalError("Use STAGEKEYS_DATA_DIR=NEW-private-folder VerifySamplerDisposal NEW-report.json")
        }
        let root = URL(fileURLWithPath: data).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: root.path),
              !root.path.contains("Application Support") else { fatalError("Choose a new isolated data directory") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let reportURL = URL(fileURLWithPath: CommandLine.arguments[1])
        guard !FileManager.default.fileExists(atPath: reportURL.path) else { fatalError("Report must be new") }
        let store = PerformanceStore()
        store.setlist = Setlist()
        store.master = 0; store.reverb = 0
        store.setlist.patches = (0..<3).map { index in
            var patch = Patch(name: "Generated disposal \(index)",
                layers: [TestFixtures.layer(index)] + (0..<14).map { _ in Layer.empty() }, snapshots: [])
            patch.silencePrevious = false
            return patch
        }
        defer { store.stopAudio() }
        let before = try store.audio.deviceController.status()
        let route = try store.audio.deviceController.outputUID()
        store.start()
        guard store.audio.running else { fatalError(store.audioFailureMessage ?? "Live audio did not start") }
        let rack = store.audio.externalRack!
        let started = ProcessInfo.processInfo.systemUptime
        var releases = 0, maximumTails = 0, maximumNodes = 0
        for cycle in 0..<96 {
            let framesBefore = store.audio.outputMetrics.frames
            store.noteOn(60 + cycle % 12, velocity: 0.8)
            // Wait for actual output-tap progress, not an arbitrary fixed sleep.
            let deadline = ProcessInfo.processInfo.systemUptime + 3
            while store.audio.outputMetrics.frames <= framesBefore {
                guard ProcessInfo.processInfo.systemUptime < deadline else { fatalError("Output stopped progressing") }
                RunLoop.current.run(until: Date().addingTimeInterval(0.005))
            }
            store.noteOff(60 + cycle % 12)
            let priorGeneration = rack.graphGeneration
            store.choose((cycle + 1) % 3)
            precondition(store.audio.running && !store.audioFailed, "A generated patch switch failed")
            precondition(rack.graphGeneration > priorGeneration, "The test must perform a real graph edit")
            precondition(rack.unit(channel: 0) is AVAudioUnitSampler)
            let generation = rack.graphGeneration
            let records = rack.debugSamplerTeardownRecords.filter { $0.generation == generation }
            precondition(!records.contains { $0.phase == .retainedPastStop }, "Sampler survived the stopped disposal point")
            precondition(records.allSatisfy { ![.purged, .truncated, .releasedBeforeRestart].contains($0.phase) || !$0.engineRunning })
            releases += records.filter { $0.phase == .releasedBeforeRestart }.count
            maximumTails = max(maximumTails, rack.debugRetiredTailCount)
            maximumNodes = max(maximumNodes, rack.debugOwnedNodeCount)
            precondition(rack.debugRetiredTailCount <= 2)
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let after = try store.audio.deviceController.status()
        let sameRoute = route == (try store.audio.deviceController.outputUID()) && before == after
        let meter = store.audio.outputMetrics
        precondition(sameRoute && releases > 2 && meter.frames > 0 && meter.invalid == 0)
        let report = Report(schemaVersion: 1, operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            cycles: 96, elapsedSeconds: elapsed, sampleRate: after.sampleRate, bufferFrames: after.bufferFrames,
            unchangedOutputRoute: sameRoute, framesObserved: meter.frames, invalidOutputSamples: meter.invalid,
            verifiedReleases: releases, maximumRetiredTails: maximumTails, maximumOwnedNodes: maximumNodes,
            originalScenario: "Unreproduced: original private patch and CoreAudio assertion text are unknown",
            scope: "Master-muted live output, generated sampler patches, production Store.choose path; not audible quality, latency, soak or vendor-AU qualification")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: reportURL, options: .atomic)
        print("PASS: \(report.cycles) live sampler patch switches, \(releases) verified stopped releases in \(elapsed) seconds")
    }
}
