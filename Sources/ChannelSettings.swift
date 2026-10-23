import Foundation

struct EQBand: Codable, Equatable {
    var frequency: Float
    var gain: Float = 0
    var q: Float = 0.707
    static let defaults: [EQBand] = [EQBand(frequency: 20), EQBand(frequency: 200), EQBand(frequency: 250), EQBand(frequency: 500), EQBand(frequency: 1000), EQBand(frequency: 4000), EQBand(frequency: 7500), EQBand(frequency: 20000)]
}
struct ChannelSettings: Codable, Equatable {
    var attack: Float = 0.35
    var decay: Float = 0.1
    var sustain: Float = 1
    var release: Float = 1.2
    var voiceCount = 32
    var samplerGain: Float = 1
    var outputTrimDB:Float?
    var samplerAttackMinimum:Float?
    var filterMin: Float = 20000
    var filterMax: Float = 20000
    var resonance: Float = 0.707
    var eqEnabled = true
    var equalizer = EQBand.defaults
    var compressorEnabled = false
    var compressorInputGain:Float?
    var compressorMix:Float?
    var threshold: Float = -18
    var ratio: Float = 4
    var compressorAttack: Float = 0.02
    var compressorRelease: Float = 0.15
    var makeup: Float = 0
    var faderMin: Float = -60
    var faderMax: Float = 0
    var routingGroup = "Keys"
    func validate() -> Bool {
        (outputTrimDB.map{$0.isFinite && (-24...12).contains($0)} ?? true) && (samplerAttackMinimum.map{$0.isFinite && (0...0.1).contains($0)} ?? true) && (compressorInputGain.map{$0.isFinite && (-24...24).contains($0)} ?? true) && (compressorMix.map{$0.isFinite && (0...1).contains($0)} ?? true) && attack.isFinite && (0.001...10).contains(attack) && decay.isFinite && (0.001...10).contains(decay) && sustain.isFinite && (0...1).contains(sustain) && release.isFinite && (0.001...30).contains(release) && (1...64).contains(voiceCount) && samplerGain.isFinite && (0...4).contains(samplerGain) && filterMin.isFinite && (20...20000).contains(filterMin) && filterMax.isFinite && (filterMin...20000).contains(filterMax) && resonance.isFinite && (0.1...10).contains(resonance) && equalizer.count == 8 && equalizer.allSatisfy({ $0.frequency.isFinite && (20...20000).contains($0.frequency) && $0.gain.isFinite && (-24...24).contains($0.gain) && $0.q.isFinite && (0.1...10).contains($0.q) }) && threshold.isFinite && (-60...0).contains(threshold) && ratio.isFinite && (1...20).contains(ratio) && compressorAttack.isFinite && (0.001...1).contains(compressorAttack) && compressorRelease.isFinite && (0.01...3).contains(compressorRelease) && makeup.isFinite && (-24...24).contains(makeup) && faderMin.isFinite && faderMax.isFinite && (-60...0).contains(faderMin) && (faderMin...0).contains(faderMax)
    }
}
