import Foundation

@main struct AudioEffectCatalogTests {
    static func main() {
        let expected = [
            "Bitcrusher", "Chorus", "Compressor", "Delay", "Equalizer",
            "Flanger", "Gain", "Halo Shimmer", "Overdrive", "Pitch Shifter",
            "Stage Reverb", "Rotor", "SolaVerb", "Tone", "Tremolo",
        ]
        let names = AudioEffectCatalog.pickerOrder.map { AudioEffectCatalog.names[$0] }
        precondition(names == expected)
        precondition(Set(AudioEffectCatalog.pickerOrder).count == AudioEffectCatalog.pickerOrder.count)
        precondition(!names.contains("Silver Reverb"))
        precondition(!names.contains("Clip Distortion"))
        print("AudioEffectCatalogTests passed")
    }
}
