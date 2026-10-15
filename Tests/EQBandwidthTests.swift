import Foundation
@main struct EQBandwidthTests {
    static func main() {
        for q: Float in [0.1,0.2,0.707,1,2,5,10] {
            let bw = EQBandwidth.octaves(fromQ:q)
            assert(bw.isFinite && bw > 0)
            assert(abs(EQBandwidth.q(fromOctaves:bw)-q) < 0.00002)
        }
        assert(abs(EQBandwidth.q(fromOctaves:1) - sqrt(2)) < 0.00001)
        assert(EQBandwidth.octaves(fromQ:0.1) > EQBandwidth.octaves(fromQ:10))
        for invalid: Float in [.nan,.infinity,-.infinity,-100,0,100] {
            let q = EQBandwidth.q(fromOctaves:invalid)
            assert(q.isFinite && EQBandwidth.qRange.contains(q))
            assert(EQBandwidth.octaves(fromQ:invalid).isFinite)
        }
        print("EQ bandwidth tests passed")
    }
}
