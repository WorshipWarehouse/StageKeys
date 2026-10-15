import Foundation

@main struct SnapshotMorphTests {
    static func main() {
        func effect(_ kind: Int, _ index: Int, _ value: Float) -> AudioEffect {
            var e = AudioEffect(); e.kind = kind; e.parameters = AudioEffectCatalog.defaults(for: kind); e.parameters![index] = value; return e
        }
        let a = effect(1,0,100), b = effect(1,0,1000)
        let start = SnapshotMorph.interpolateEffects(from:[a],to:[b],fraction:0)[0]
        let mid = SnapshotMorph.interpolateEffects(from:[a],to:[b],fraction:0.5)[0]
        let end = SnapshotMorph.interpolateEffects(from:[a],to:[b],fraction:1)[0]
        assert(start.values[0] == 100 && mid.values[0] == 550 && end.values[0] == 1000)
        assert(start.validate() && mid.validate() && end.validate())
        let different = effect(9,0,-12)
        assert(SnapshotMorph.interpolateEffects(from:[a],to:[different],fraction:0)[0] == different)
        var disabled = b; disabled.enabled = false; disabled.syncBeats = 0.5
        let bypass = SnapshotMorph.interpolateEffects(from:[a],to:[disabled],fraction:0)[0]
        assert(!bypass.enabled && bypass.syncBeats == 0.5 && bypass.values[0] == 100)
        assert(SnapshotMorph.changedEffectSlots(previous:[bypass],current:[disabled]).isEmpty)
        assert(SnapshotMorph.changedEffectSlots(previous:[a],current:[disabled]) == [0])
        assert(SnapshotMorph.changedEffectSlots(previous:[b],current:[b]).isEmpty)
        assert(SnapshotMorph.interpolateFloat(from:0,to:1,fraction:.nan) == 0)
        assert(SnapshotMorph.interpolateFloat(from:0,to:1,fraction:-.infinity) == 0)
        assert(SnapshotMorph.interpolateFloat(from:0,to:1,fraction:.infinity) == 1)
        assert(SnapshotMorph.interpolateFloat(from:0,to:1,fraction:-4) == 0)
        assert(SnapshotMorph.interpolateFloat(from:0,to:1,fraction:4) == 1)
        assert(SnapshotMorph.interpolateFloat(from:-2,to:2,fraction:0.5,range:-1...1) == 0)
        assert(SnapshotMorph.interpolateFloat(from:.nan,to:.infinity,fraction:0.5) == 0)
        let pitch = SnapshotMorph.interpolateEffects(from:[effect(12,0,0)],to:[effect(12,0,7)],fraction:0.5)[0]
        assert(pitch.values[0] == 4)
        for kind in 0...15 {
            var invalid = AudioEffect(); invalid.kind = kind; invalid.amount = .nan
            invalid.parameters = AudioEffectCatalog.defaults(for:kind).map { _ in .infinity }
            invalid.syncBeats = .nan
            let normalized = SnapshotMorph.interpolateEffects(from:[invalid],to:[invalid],fraction:.nan)[0]
            assert(normalized.validate(), "Invalid normalized kind \(kind)")
        }
        var malformed = a; malformed.parameters = []
        assert(SnapshotMorph.interpolateEffects(from:[malformed],to:[b],fraction:0)[0] == b)
        assert(SnapshotMorph.interpolateEffects(from:[],to:[b],fraction:0)[0] == b)
        var legacy = AudioEffect(); legacy.kind = 1
        let canonical = SnapshotMorph.normalizedEffect(legacy)
        assert(SnapshotMorph.changedEffectSlots(previous:[legacy],current:[canonical]).isEmpty)
        let sourceLayer = Layer(name: "Source", instrument: 0, gain: 1)
        var targetLayer = sourceLayer; targetLayer.pan = 1; targetLayer.midiEffectEnabled = false
        var midi = MIDIProgram(); midi.kind = .arpeggiator; targetLayer.midiProgram = midi
        var sourceState = SnapshotSoundState(sourceLayer); sourceState.pan = -1
        let targetState = SnapshotSoundState(targetLayer)
        for t: Float in [0, 0.25, 0.5, 0.75, 1] {
            let state = SnapshotMorph.interpolateSound(from:sourceState,to:targetState,fraction:t)
            assert(abs(state.pan - (-1 + 2*t)) < 0.00001)
            assert(!state.midiEffectEnabled && state.midiProgram?.kind == .arpeggiator)
        }
        // All unit controls (modulation, tonic gain, brightness and shimmer) use
        // the same bounded helper; a silence endpoint stays exact.
        for t: Float in [0, 0.5, 1] {
            assert(SnapshotMorph.interpolateFloat(from:1,to:0,fraction:t) == 1-t)
        }
        print("SnapshotMorph tests passed")
    }
}
