import Foundation

enum MIDIEventDelivery: Equatable {
    case immediate
    case scheduled(Int64)

    var sampleTime: Int64? {
        if case .scheduled(let sample) = self { return sample }
        return nil
    }
}

/// Decides whether a musical deadline is still far enough ahead of the engine's
/// render position to hand an AU an `AUEventSampleTime`. Everything else is
/// applied immediately, so a late tick degrades to current behavior instead of
/// scheduling into the past.
struct MIDIDeliveryPolicy {
    /// A scheduled event must lead the render position by this many frames.
    var safetyFrames: Int64
    /// Deadlines further out than this are not due yet and are not scheduled.
    var lookahead: TimeInterval

    init(safetyFrames: Int64 = 128, lookahead: TimeInterval = 0.05) {
        self.safetyFrames = safetyFrames
        self.lookahead = lookahead
    }

    func delivery(deadline: TimeInterval?, now: TimeInterval,
                  timeline: MIDIAudioTimeline?, currentSample: Int64?,
                  canSchedule: Bool) -> MIDIEventDelivery {
        guard canSchedule, let deadline, deadline.isFinite,
              deadline - now <= lookahead,
              let timeline, let currentSample else { return .immediate }
        let sample = timeline.sampleTime(for: deadline)
        let lead = sample.subtractingReportingOverflow(currentSample)
        guard !lead.overflow, lead.partialValue > safetyFrames else { return .immediate }
        return .scheduled(sample)
    }
}
