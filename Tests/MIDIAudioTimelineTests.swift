import Foundation

@main struct MIDIAudioTimelineTests {
    static func main() {
        // A quarter second is an exact frame count at each engine rate.
        let anchorTime = 12.5
        for (rate, expected) in [(44_100.0, Int64(11_025)), (48_000.0, 12_000), (96_000.0, 24_000)] {
            let clock = MIDIAudioTimeline(sampleRate: rate, anchorSample: 480_000, anchorTime: anchorTime)
            assert(clock.sampleTime(for: anchorTime + 0.25) == 480_000 + expected)
            assert(clock.offsetFrames(for: anchorTime + 0.25) == expected)
            assert(clock.offsetFrames(for: anchorTime) == 0)
            assert(clock.offsetFrames(for: anchorTime + 0.5) == expected * 2)
        }

        let clock = MIDIAudioTimeline(sampleRate: 48_000, anchorSample: 1_000_000, anchorTime: 5)
        assert(clock.offsetFrames(for: 5.001) == 48, "1 ms at 48 kHz is 48 frames")
        assert(clock.offsetFrames(for: 5.0000104) == 0, "Half a frame rounds to the anchor")
        assert(clock.offsetFrames(for: 4.5) == -24_000, "Deadlines before the anchor are negative")
        assert(clock.isDeliverable(1_000_100, currentSample: 1_000_000))
        assert(!clock.isDeliverable(1_000_000, currentSample: 1_000_000))
        assert(!clock.isDeliverable(999_999, currentSample: 1_000_000))

        // Invalid or extreme input must not trap or fabricate a deadline.
        assert(clock.sampleTime(for: .infinity) == 1_000_000)
        assert(clock.sampleTime(for: .nan) == 1_000_000)
        assert(clock.sampleTime(for: 1e18) > 1_000_000)
        assert(clock.sampleTime(for: -1e18) < 1_000_000)
        let invalidRate = MIDIAudioTimeline(sampleRate: 0, anchorSample: 10, anchorTime: 2)
        assert(invalidRate.sampleTime(for: 3) == 10)

        let upper = MIDIAudioTimeline(sampleRate: 48_000, anchorSample: .max, anchorTime: 0)
        assert(upper.sampleTime(for: 1) == Int64.max)
        assert(upper.offsetFrames(for: 1) == 48_000)
        let lower = MIDIAudioTimeline(sampleRate: 48_000, anchorSample: .min, anchorTime: 0)
        assert(lower.sampleTime(for: -1) == Int64.min)
        assert(lower.offsetFrames(for: -1) == -48_000)

        print("PASS: deadline to sample time at 44.1/48/96 kHz, rounding, past deadlines, invalid input and deliverability")
    }
}
