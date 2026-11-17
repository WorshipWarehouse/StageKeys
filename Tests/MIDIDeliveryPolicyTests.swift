import Foundation

@main struct MIDIDeliveryPolicyTests {
    static func main() {
        let policy = MIDIDeliveryPolicy()
        let timeline = MIDIAudioTimeline(sampleRate: 48_000, anchorSample: 100_000, anchorTime: 10)

        // 20 ms ahead is 960 frames, well outside the 128-frame margin.
        assert(policy.delivery(deadline: 10.02, now: 10, timeline: timeline,
                               currentSample: 100_000, canSchedule: true) == .scheduled(100_960))
        // 100 frames ahead is inside the margin.
        assert(policy.delivery(deadline: 10 + 100.0/48_000, now: 10, timeline: timeline,
                               currentSample: 100_000, canSchedule: true) == .immediate)
        // 200 frames ahead is schedulable.
        if case .scheduled(let sample) = policy.delivery(deadline: 10 + 200.0/48_000, now: 10,
                                                         timeline: timeline, currentSample: 100_000,
                                                         canSchedule: true) {
            assert(abs(sample - 100_200) <= 1)
        } else {
            assertionFailure("200 frames ahead should schedule")
        }
        // A deadline beyond the lookahead horizon is not due yet.
        assert(policy.delivery(deadline: 10.2, now: 10, timeline: timeline,
                               currentSample: 100_000, canSchedule: true) == .immediate)
        // Already behind the render position.
        assert(policy.delivery(deadline: 9.5, now: 10, timeline: timeline,
                               currentSample: 100_000, canSchedule: true) == .immediate)

        // Missing inputs or an unsupported destination always fall back.
        assert(policy.delivery(deadline: nil, now: 10, timeline: timeline,
                               currentSample: 100_000, canSchedule: true) == .immediate)
        assert(policy.delivery(deadline: 10.02, now: 10, timeline: nil,
                               currentSample: 100_000, canSchedule: true) == .immediate)
        assert(policy.delivery(deadline: 10.02, now: 10, timeline: timeline,
                               currentSample: nil, canSchedule: true) == .immediate)
        assert(policy.delivery(deadline: 10.02, now: 10, timeline: timeline,
                               currentSample: 100_000, canSchedule: false) == .immediate)
        assert(policy.delivery(deadline: .infinity, now: 10, timeline: timeline,
                               currentSample: 100_000, canSchedule: true) == .immediate)

        assert(MIDIEventDelivery.scheduled(42).sampleTime == 42)
        assert(MIDIEventDelivery.immediate.sampleTime == nil)
        print("PASS: scheduled vs immediate AU delivery, safety margin, lookahead, missing inputs and past deadlines")
    }
}
