import Foundation

/// Maps monotonic musical deadlines to engine render sample time.
///
/// A render anchor is captured on the main thread from the engine's last render
/// timestamp (`AVAudioEngine` exposes this as `lastRenderTime`, which carries a
/// sample time and a host time). This type is pure arithmetic so the conversion
/// can be tested without an audio device or AVFoundation.
struct MIDIAudioTimeline {
    var sampleRate: Double
    var anchorSample: Int64
    var anchorTime: TimeInterval

    init(sampleRate: Double, anchorSample: Int64, anchorTime: TimeInterval) {
        self.sampleRate = sampleRate
        self.anchorSample = anchorSample
        self.anchorTime = anchorTime
    }

    /// Absolute engine sample time for a musical deadline. A deadline before
    /// the anchor returns a sample time before it; the caller decides whether
    /// that is still deliverable or should be treated as immediate.
    func sampleTime(for deadline: TimeInterval) -> Int64 {
        let offset = offsetFrames(for: deadline)
        let (sample, overflow) = anchorSample.addingReportingOverflow(offset)
        if overflow { return offset < 0 ? Int64.min : Int64.max }
        return sample
    }

    /// Whole frames from the anchor to a deadline.
    func offsetFrames(for deadline: TimeInterval) -> Int64 {
        guard sampleRate.isFinite, sampleRate > 0,
              deadline.isFinite, anchorTime.isFinite else { return 0 }
        let frames = (deadline - anchorTime) * sampleRate
        guard frames.isFinite else { return 0 }
        return Int64(min(max(frames, -4.0e18), 4.0e18).rounded())
    }

    /// Whether an event at `sampleTime` is still ahead of a render that has
    /// reached `currentSample`. Events at or behind it must be applied
    /// immediate rather than scheduled into the past.
    func isDeliverable(_ sampleTime: Int64, currentSample: Int64) -> Bool {
        sampleTime > currentSample
    }
}
