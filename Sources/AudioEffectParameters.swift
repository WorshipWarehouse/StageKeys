import Foundation

struct AudioEffectParameterDescriptor: Identifiable, Equatable {
    let index: Int
    let name: String
    let minimum: Float
    let maximum: Float
    let defaultValue: Float
    let unit: String
    var id: Int { index }
}
/// Original algorithms with observed control names. No claim of sonic parity.
enum AudioEffectCatalog {
    static let names = ["No Effect", "Tone", "Tremolo", "Delay", "Bitcrusher", "Chorus", "Compressor", "Equalizer", "Flanger", "Gain", "Halo Shimmer", "Overdrive", "Pitch Shifter", "PrimaVerb", "Rotor", "SolaVerb"]
    static func descriptors(for kind: Int) -> [AudioEffectParameterDescriptor] {
        switch kind {
        case 1: return [
            .init(index: 0, name: "Frequency", minimum: 20, maximum: 20000, defaultValue: 20000, unit: "Hz"),
            .init(index: 1, name: "Resonance", minimum: 0.1, maximum: 10, defaultValue: 0.707, unit: "Q"),
            .init(index: 2, name: "Mix", minimum: 0, maximum: 1, defaultValue: 1, unit: "%"),
        ]
        case 2: return [
            .init(index: 0, name: "Depth", minimum: 0, maximum: 1, defaultValue: 0.8, unit: "%"),
            .init(index: 1, name: "Frequency", minimum: 0.01, maximum: 20, defaultValue: 3, unit: "Hz"),
            .init(index: 2, name: "Mix", minimum: 0, maximum: 1, defaultValue: 1, unit: "%"),
            .init(index: 3, name: "Stereo", minimum: 0, maximum: 1, defaultValue: 0, unit: "%"),
        ]
        case 3: return [
            .init(index: 0, name: "Feedback", minimum: 0, maximum: 0.95, defaultValue: 0.3, unit: "%"),
            .init(index: 1, name: "Subdivision", minimum: 0.0625, maximum: 2, defaultValue: 1, unit: "beats"),
            .init(index: 2, name: "Filter", minimum: 20, maximum: 20000, defaultValue: 1000, unit: "Hz"),
            .init(index: 3, name: "Mix", minimum: 0, maximum: 1, defaultValue: 0.5, unit: "%"),
        ]
        case 4: return [
            .init(index: 0, name: "Bit Depth", minimum: 2, maximum: 24, defaultValue: 10, unit: "bits"),
            .init(index: 1, name: "Sample Rate", minimum: 100, maximum: 48000, defaultValue: 5000, unit: "Hz"),
            .init(index: 2, name: "Mix", minimum: 0, maximum: 1, defaultValue: 1, unit: "%"),
        ]
        case 5: return [
            .init(index: 0, name: "Frequency", minimum: 0, maximum: 20, defaultValue: 0.68, unit: "Hz"),
            .init(index: 1, name: "Depth", minimum: 0, maximum: 1, defaultValue: 0.4, unit: "%"),
            .init(index: 2, name: "Feedback", minimum: 0, maximum: 0.95, defaultValue: 0.2, unit: "%"),
            .init(index: 3, name: "Output Boost", minimum: -24, maximum: 12, defaultValue: 1, unit: "dB"),
            .init(index: 4, name: "Mix", minimum: 0, maximum: 1, defaultValue: 1, unit: "%"),
        ]
        case 6: return [
            .init(index: 0, name: "Input Gain", minimum: -24, maximum: 24, defaultValue: 0, unit: "dB"),
            .init(index: 1, name: "Attack", minimum: 0.1, maximum: 500, defaultValue: 20, unit: "ms"),
            .init(index: 2, name: "Release", minimum: 1, maximum: 2000, defaultValue: 60, unit: "ms"),
            .init(index: 3, name: "Ratio", minimum: 1, maximum: 20, defaultValue: 2, unit: ":1"),
            .init(index: 4, name: "Threshold", minimum: -60, maximum: 0, defaultValue: -40, unit: "dB"),
            .init(index: 5, name: "Mix", minimum: 0, maximum: 1, defaultValue: 0, unit: "%"),
            .init(index: 6, name: "Output Gain", minimum: -24, maximum: 24, defaultValue: 0, unit: "dB"),
        ]
        case 7: return [
            .init(index: 0, name: "High Pass Frequency", minimum: 20, maximum: 20000, defaultValue: 20, unit: "Hz"),
            .init(index: 2, name: "High Pass Q", minimum: 0.1, maximum: 10, defaultValue: 0.707, unit: "Q"),
            .init(index: 3, name: "Low Shelf Frequency", minimum: 20, maximum: 20000, defaultValue: 70, unit: "Hz"),
            .init(index: 4, name: "Low Shelf Gain", minimum: -24, maximum: 24, defaultValue: 0, unit: "dB"),
            .init(index: 5, name: "Low Shelf Q", minimum: 0.1, maximum: 10, defaultValue: 0.707, unit: "Q"),
            .init(index: 6, name: "Peak 1 Frequency", minimum: 20, maximum: 20000, defaultValue: 100, unit: "Hz"),
            .init(index: 7, name: "Peak 1 Gain", minimum: -24, maximum: 24, defaultValue: 0, unit: "dB"),
            .init(index: 8, name: "Peak 1 Q", minimum: 0.1, maximum: 10, defaultValue: 0.707, unit: "Q"),
            .init(index: 9, name: "Peak 2 Frequency", minimum: 20, maximum: 20000, defaultValue: 250, unit: "Hz"),
            .init(index: 10, name: "Peak 2 Gain", minimum: -24, maximum: 24, defaultValue: 0, unit: "dB"),
            .init(index: 11, name: "Peak 2 Q", minimum: 0.1, maximum: 10, defaultValue: 0.707, unit: "Q"),
            .init(index: 12, name: "Peak 3 Frequency", minimum: 20, maximum: 20000, defaultValue: 1000, unit: "Hz"),
            .init(index: 13, name: "Peak 3 Gain", minimum: -24, maximum: 24, defaultValue: 0, unit: "dB"),
            .init(index: 14, name: "Peak 3 Q", minimum: 0.1, maximum: 10, defaultValue: 0.707, unit: "Q"),
            .init(index: 15, name: "Peak 4 Frequency", minimum: 20, maximum: 20000, defaultValue: 2500, unit: "Hz"),
            .init(index: 16, name: "Peak 4 Gain", minimum: -24, maximum: 24, defaultValue: 0, unit: "dB"),
            .init(index: 17, name: "Peak 4 Q", minimum: 0.1, maximum: 10, defaultValue: 0.707, unit: "Q"),
            .init(index: 18, name: "High Shelf Frequency", minimum: 20, maximum: 20000, defaultValue: 7500, unit: "Hz"),
            .init(index: 19, name: "High Shelf Gain", minimum: -24, maximum: 24, defaultValue: 0, unit: "dB"),
            .init(index: 20, name: "High Shelf Q", minimum: 0.1, maximum: 10, defaultValue: 0.707, unit: "Q"),
            .init(index: 21, name: "Low Pass Frequency", minimum: 20, maximum: 20000, defaultValue: 20000, unit: "Hz"),
            .init(index: 23, name: "Low Pass Q", minimum: 0.1, maximum: 10, defaultValue: 0.707, unit: "Q"),
        ]
        case 8: return [
            .init(index: 0, name: "Rate", minimum: 0.1, maximum: 10, defaultValue: 0.2, unit: "Hz"),
            .init(index: 1, name: "Depth", minimum: 0, maximum: 1, defaultValue: 0.5, unit: "%"),
            .init(index: 2, name: "Feedback", minimum: -0.95, maximum: 0.95, defaultValue: 0.8, unit: "%"),
            .init(index: 3, name: "Mix", minimum: 0, maximum: 1, defaultValue: 0.5, unit: "%"),
        ]
        case 9: return [
            .init(index: 0, name: "Gain", minimum: -96, maximum: 6, defaultValue: 0, unit: "dB"),
        ]
        case 10: return [
            .init(index: 0, name: "Shimmer", minimum: 0, maximum: 1, defaultValue: 0.75, unit: "%"),
            .init(index: 1, name: "Feedback", minimum: 0, maximum: 0.95, defaultValue: 0.66, unit: "%"),
            .init(index: 2, name: "Size", minimum: 0, maximum: 1, defaultValue: 0.9, unit: "%"),
            .init(index: 3, name: "Diffusion", minimum: 0, maximum: 1, defaultValue: 0.75, unit: "%"),
            .init(index: 4, name: "Modulation", minimum: 0, maximum: 1, defaultValue: 0.5, unit: "%"),
            .init(index: 5, name: "Low Cut", minimum: 20, maximum: 2000, defaultValue: 100, unit: "Hz"),
            .init(index: 6, name: "Tone", minimum: 200, maximum: 20000, defaultValue: 10000, unit: "Hz"),
            .init(index: 7, name: "Dry", minimum: 0, maximum: 1, defaultValue: 1, unit: "%"),
            .init(index: 8, name: "Wet", minimum: 0, maximum: 1, defaultValue: 0.2, unit: "%"),
        ]
        case 11: return [
            .init(index: 0, name: "Drive", minimum: 0, maximum: 1, defaultValue: 0.96, unit: "%"),
            .init(index: 1, name: "Low Cut", minimum: 20, maximum: 800, defaultValue: 402, unit: "Hz"),
            .init(index: 2, name: "Tone", minimum: 600, maximum: 20000, defaultValue: 4877, unit: "Hz"),
            .init(index: 3, name: "Mix", minimum: 0, maximum: 1, defaultValue: 0.4, unit: "%"),
            .init(index: 4, name: "Boost", minimum: -24, maximum: 12, defaultValue: 2, unit: "dB"),
        ]
        case 12: return [
            .init(index: 0, name: "Pitch", minimum: -24, maximum: 24, defaultValue: 12, unit: "semitones"),
            .init(index: 1, name: "Amount", minimum: 0, maximum: 1, defaultValue: 0.2, unit: "%"),
        ]
        case 13: return [
            .init(index: 0, name: "Size", minimum: 0, maximum: 1, defaultValue: 0.5, unit: "%"),
            .init(index: 1, name: "Predelay", minimum: 0, maximum: 200, defaultValue: 0, unit: "ms"),
            .init(index: 2, name: "Reflectivity", minimum: 0, maximum: 0.95, defaultValue: 0.3, unit: "%"),
            .init(index: 3, name: "Low Cut", minimum: 20, maximum: 2000, defaultValue: 100, unit: "Hz"),
            .init(index: 4, name: "Tone", minimum: 200, maximum: 20000, defaultValue: 20000, unit: "Hz"),
            .init(index: 5, name: "Chorus", minimum: 0, maximum: 1, defaultValue: 0, unit: "%"),
            .init(index: 6, name: "Rate", minimum: 0.01, maximum: 10, defaultValue: 1, unit: "Hz"),
            .init(index: 7, name: "Dry", minimum: 0, maximum: 1, defaultValue: 0.8, unit: "%"),
            .init(index: 8, name: "Wet", minimum: 0, maximum: 1, defaultValue: 0.4, unit: "%"),
        ]
        case 14: return [
            .init(index: 0, name: "Speed", minimum: 0, maximum: 2, defaultValue: 1, unit: "0 brake / 1 slow / 2 fast"),
            .init(index: 1, name: "Slow Rate", minimum: 1, maximum: 120, defaultValue: 44, unit: "rpm"),
            .init(index: 2, name: "Fast Rate", minimum: 120, maximum: 600, defaultValue: 402, unit: "rpm"),
            .init(index: 3, name: "Acceleration", minimum: 0.1, maximum: 10, defaultValue: 2.5, unit: "s"),
            .init(index: 4, name: "Drive", minimum: 0, maximum: 1, defaultValue: 0, unit: "%"),
            .init(index: 5, name: "Output", minimum: -24, maximum: 12, defaultValue: 0, unit: "dB"),
            .init(index: 6, name: "Mic Balance", minimum: 0, maximum: 1, defaultValue: 0.5, unit: "%"),
            .init(index: 7, name: "Distance", minimum: 1, maximum: 100, defaultValue: 18, unit: "cm"),
            .init(index: 8, name: "Spread", minimum: 0, maximum: 200, defaultValue: 130, unit: "cm"),
            .init(index: 9, name: "Ambience Size", minimum: 0, maximum: 1, defaultValue: 0.9, unit: "%"),
            .init(index: 10, name: "Ambience Width", minimum: 0, maximum: 1, defaultValue: 0.82, unit: "%"),
            .init(index: 11, name: "Ambience Amount", minimum: 0, maximum: 1, defaultValue: 0.35, unit: "%"),
        ]
        case 15: return [
            .init(index: 0, name: "Predelay", minimum: 0, maximum: 200, defaultValue: 20, unit: "ms"),
            .init(index: 1, name: "Size", minimum: 0, maximum: 1, defaultValue: 0.5, unit: "%"),
            .init(index: 2, name: "Reflectivity", minimum: 0, maximum: 0.95, defaultValue: 0.5, unit: "%"),
            .init(index: 3, name: "Low Cut", minimum: 20, maximum: 2000, defaultValue: 100, unit: "Hz"),
            .init(index: 4, name: "Tone", minimum: 200, maximum: 20000, defaultValue: 14000, unit: "Hz"),
            .init(index: 5, name: "Pitch Mod", minimum: 0, maximum: 1, defaultValue: 0.33, unit: "%"),
            .init(index: 6, name: "Chorus", minimum: 0, maximum: 1, defaultValue: 0.2, unit: "%"),
            .init(index: 7, name: "Rate", minimum: 0.01, maximum: 10, defaultValue: 1, unit: "Hz"),
            .init(index: 8, name: "Dry", minimum: 0, maximum: 1, defaultValue: 0.8, unit: "%"),
            .init(index: 9, name: "Wet", minimum: 0, maximum: 1, defaultValue: 0.4, unit: "%"),
        ]
        default: return []
        }
    }
    static func defaults(for kind: Int) -> [Float] {
        let parameters = descriptors(for: kind)
        guard let last = parameters.map(\.index).max() else { return [] }
        var values = Array(repeating: Float(0), count: last + 1)
        for parameter in parameters { values[parameter.index] = parameter.defaultValue }
        return values
    }
}
