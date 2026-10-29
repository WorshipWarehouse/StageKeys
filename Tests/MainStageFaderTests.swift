import Foundation

@main struct MainStageFaderTests {
    @MainActor static func main() throws {
        // Values saved by MainStage 4.3.1 through its mixer, not generated
        // from the decoder under test. Display rounds the endpoint to +6.0.
        let measured:[(Double,Double)]=[(75_676_738,-52),(535_750_245,-18),
            (1_070_042_940,-5.98244797746),(1_509_949_440,0),
            (2_120_617_814,5.9),(2_130_706_432,5.98244846067)]
        let base=TestFixtures.layer(gain:0.37,name:"Fader reference")
        for (raw,db) in measured {
            var draft=MainStageProcessing.Draft()
            MainStageProcessing.channelSettings(["volume":NSNumber(value:raw)],to:&draft)
            assert(draft.issues.isEmpty && draft.hasChanges)
            let layer=try draft.applying(to:base)
            assert(layer.channelSettings.validate() && (0...1).contains(layer.gain))
            let amplitude=Double(layer.gain)*pow(10,Double(layer.channelSettings.outputTrimDB ?? 0)/20)
            assert(abs(20*log10(amplitude)-db)<0.00002,"Source level lost")
            let restored=try JSONDecoder().decode(Layer.self,from:JSONEncoder().encode(layer))
            assert(restored==layer,"Source fader and boost must persist")
        }
        assert(MainStageProcessing.channelFaderAmplitude(0)==0)
        for invalid in [-1.0,0.5,2_130_706_433,Double.nan,Double.infinity] {
            assert(MainStageProcessing.channelFaderAmplitude(invalid)==nil)
        }
        for invalid:Any in [true,"1509949440",-1,0.5,Double.nan,Double.infinity,2_130_706_433] {
            var draft=MainStageProcessing.Draft()
            MainStageProcessing.channelSettings(["volume":invalid],to:&draft)
            let unchanged=try draft.applying(to:base)
            assert(unchanged.gain==base.gain && unchanged.channelSettings.outputTrimDB==nil)
            assert(draft.issues.contains{$0.contains("unrecognized encoding")})
        }
        var boosted=MainStageProcessing.Draft()
        MainStageProcessing.channelSettings(["volume":2_130_706_432],to:&boosted)
        var trimmed=base;trimmed.channelSettings.outputTrimDB = -3
        let combined=try boosted.applying(to:trimmed)
        assert(abs(combined.channelSettings.outputTrimDB!-2.9824485)<0.00002)
        trimmed.channelSettings.outputTrimDB=12
        do {_ = try boosted.applying(to:trimmed);fatalError("Boost overflow silently accepted")} catch {}

        let channel=MainStagePatch.Channel(name:"Piano",file:"Piano.cst",sha256:String(repeating:"a",count:64),instruments:[],devices:[],hasMappings:false,hasMIDIState:false)
        var report=MainStagePatch.Report(sourceArchiveID:UUID().uuidString,name:"Source",channels:[channel],blockers:[],preservedFiles:["data.plist":String(repeating:"b",count:64)])
        let originalID=try MainStagePatch.conversionID(report,channel:channel,variant:"instrument-hash")
        report.sourceArchiveID=UUID().uuidString
        let repeatedID=try MainStagePatch.conversionID(report,channel:channel,variant:"instrument-hash")
        assert(repeatedID==originalID,"Identical content in a new archive must deduplicate")
        var second=channel;second.file="Second Piano.cst"
        let secondID=try MainStagePatch.conversionID(report,channel:second,variant:"instrument-hash")
        assert(secondID != originalID,"Distinct channels with identical CST bytes must not collide")
        report.preservedFiles["data.plist"]=String(repeating:"c",count:64)
        let changedID=try MainStagePatch.conversionID(report,channel:channel,variant:"instrument-hash")
        assert(changedID != originalID,"Metadata-only edits must not reuse stale conversion settings")
        report.preservedFiles=[:]
        do {_ = try MainStagePatch.conversionID(report,channel:channel,variant:"instrument-hash");fatalError("Unverified metadata accepted")} catch {}

        // Exercise the production sampler/effect/output path at safe levels,
        // proving boosts do not change effect drive or bypass fader attenuation.
        func energy(_ raw:Double)throws->Double {
            let audio=AudioController();try audio.prepareOffline();defer{audio.stop()}
            audio.bypassMasterLimiter(true)
            var layer=base;layer.effects[0]=AudioEffect.factoryDefault(kind:11)
            var draft=MainStageProcessing.Draft()
            MainStageProcessing.channelSettings(["volume":NSNumber(value:raw)],to:&draft)
            layer=try draft.applying(to:layer)
            audio.configure(0,layer);audio.gain(0,layer.gain,seconds:0);audio.master(0.02);audio.space(0)
            for _ in 0..<10 {_ = try audio.offlineBlock()}
            audio.noteOn(key:60,pitch:60,instrument:-1,layer:0,velocity:0.7)
            var energy=0.0
            for _ in 0..<40 {
                let buffer=try audio.offlineBlock()
                for channel in 0..<Int(buffer.format.channelCount) {
                    for frame in 0..<Int(buffer.frameLength) {
                        let value=Double(buffer.floatChannelData![channel][frame]);assert(value.isFinite)
                        energy += value*value
                    }
                }
            }
            return energy
        }
        let unity=try energy(1_509_949_440);assert(unity>0)
        for raw in [0.0,535_750_245,2_130_706_432] {
            let rendered=try energy(raw)
            let expected=MainStageProcessing.channelFaderAmplitude(raw)!
            assert(abs(sqrt(rendered/unity)-expected)<0.001,"Rendered source fader differs from imported level")
        }
        print("PASS: measured MainStage fader attenuation/boost/silence, bounded decoding, persistence and production audio levels")
    }
}
