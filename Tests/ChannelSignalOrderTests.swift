import Foundation

@main struct ChannelSignalOrderTests {
    static func main() {
        var settings = ChannelSettings()
        settings.filterMin = 80
        settings.filterMax = 16000

        // The Mod Filter taper is exponential across the minimum→maximum range.
        assert(abs(settings.cutoff(modulation: 0) - 80) < 0.01)
        assert(abs(settings.cutoff(modulation: 1) - 16000) < 0.5)
        let midpoint = settings.cutoff(modulation: 0.5)
        assert(abs(midpoint - sqrt(80 * 16000)) < 1, "The midpoint is the geometric mean, not the arithmetic average")

        // Out-of-range and non-finite modulation is bounded rather than passed through.
        assert(settings.cutoff(modulation: -5) == settings.cutoff(modulation: 0))
        assert(settings.cutoff(modulation: 9) == settings.cutoff(modulation: 1))
        assert(settings.cutoff(modulation: .nan) == settings.cutoff(modulation: 0))
        assert(settings.cutoff(modulation: .infinity) == settings.cutoff(modulation: 0), "Non-finite modulation falls back to the closed position")

        // A closed range and a full range both stay inside the validated bounds.
        settings.filterMin = 20000
        settings.filterMax = 20000
        assert(settings.cutoff(modulation: 0.5) == 20000)
        assert(settings.validate())
        settings.filterMin = 20
        settings.filterMax = 20000
        assert(settings.validate())

        // Envelope fields keep their documented ranges.
        settings.attack = 0.001
        settings.decay = 0.001
        settings.sustain = 0
        settings.release = 0.001
        assert(settings.validate())
        settings.attack = 11
        assert(!settings.validate(), "An out-of-range attack must be rejected before it reaches the engine")
        settings.attack = 2
        settings.sustain = 1.5
        assert(!settings.validate())

        print("PASS: Mod Filter taper endpoints, midpoint, clamping and bounded envelope/filter validation")
    }
}
