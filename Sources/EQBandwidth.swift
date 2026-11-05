import Foundation

/// Analog constant-Q bandwidth in octaves, the width the editor displays.
/// Stored DSP state remains Q; Synth.c realizes that width through the bilinear
/// transform, so this conversion stays sample-rate independent.
enum EQBandwidth {
    static let qRange: ClosedRange<Float> = 0.1...10
    static var octaveRange: ClosedRange<Float> { octaves(fromQ: qRange.upperBound)...octaves(fromQ: qRange.lowerBound) }
    static func octaves(fromQ value: Float) -> Float {
        let q = value.isFinite ? min(qRange.upperBound, max(qRange.lowerBound, value)) : 0.707
        return Float(2 * asinh(1 / (2 * Double(q))) / log(2))
    }
    static func q(fromOctaves value: Float) -> Float {
        let range = octaveRange
        let bw = value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : octaves(fromQ: 0.707)
        return min(qRange.upperBound, max(qRange.lowerBound, Float(1 / (2 * sinh(Double(bw) * log(2) / 2)))))
    }
}
