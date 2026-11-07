import Foundation
@main struct MainStageShapingReportTests {
    static func main()throws {
        setbuf(stdout,nil)
        func check(_ condition:Bool,_ message:String,line:UInt=#line) {
            guard condition else {
                print("::error file=Tests/MainStageShapingReportTests.swift,line=\(line)::\(message)")
                exit(1)
            }
        }
        func shapingDraft(_ extra:[String:Any]=[:])->MainStageProcessing.Draft {
            var source:[String:Any]=[
                "Channel_attack":NSNumber(value:0.042),
                "Channel_filterCutoff":NSNumber(value:2754),
                "Channel_filterResonance":NSNumber(value:0.6),
                "Channel_envelopeSustain":NSNumber(value:0),
                "Channel_envelopeCurve":["depth":2,"label":"warm"],
                "Channel_filterSustainPedal":true,
                "Channel_pan":NSNumber(value:-0.25),
                "Channel_instID":NSNumber(value:7),
                "Channel_name":"Authored Piano",
                "volume":NSNumber(value:1_509_949_440)
            ]
            for (key,value) in extra {source[key]=value}
            var draft=MainStageProcessing.Draft()
            MainStageProcessing.channelSettings(source,to:&draft)
            return draft
        }
        let draft=shapingDraft()
        check(draft.retainedShaping.count==5,"five shaping fields must be retained, got \(draft.retainedShaping)")
        check(draft.retainedShaping["Channel_attack"]=="0.042","an archived fractional value must keep its exact spelling")
        check(draft.retainedShaping["Channel_filterCutoff"]=="2754","an archived whole value must not gain a decimal point")
        check(draft.retainedShaping["Channel_filterResonance"]=="0.6","resonance must be retained")
        check(draft.retainedShaping["Channel_envelopeSustain"]=="0","a zero sustain must be retained, not treated as absent")
        check(draft.retainedShaping["Channel_envelopeCurve"]=="2 fields","a container must be described by size, never expanded")
        check(draft.retainedShaping["Channel_filterSustainPedal"]==nil,"the translated pedal field must not be reported as untranslated shaping")
        for key in ["Channel_pan","Channel_instID","Channel_name","volume"] {
            check(draft.retainedShaping[key]==nil,"the non-shaping field \(key) must not be retained as shaping")
        }
        for (key,value) in draft.retainedShaping {
            check(draft.issues.contains{$0.hasPrefix("\(key) = \(value):")},"the report must name \(key) with its retained value")
        }
        check(!draft.issues.contains{$0.contains("set them explicitly in Sound Settings")},"the report must not send envelope edits to a pane this sound hides")
        check(draft.issues.contains{$0.contains("Mod Filter is a separate StageKeys stage")},"the report must separate the Mod Filter from the instrument-owned envelope")
        // The destination's own shaping must survive conversion untouched.
        var layer=Layer(name:"Destination",instrument:-1,gain:0.5)
        layer.channelSettings.attack=0.006
        layer.channelSettings.decay=0.42
        layer.channelSettings.sustain=0.35
        layer.channelSettings.release=2.5
        layer.channelSettings.filterMin=4000
        layer.channelSettings.filterMax=9000
        layer.channelSettings.resonance=2.5
        let before=layer.channelSettings
        // The conversion path is the selection overload; the rack-only overload
        // deliberately writes no source record.
        let applied=try draft.applying(to:layer,selection:MainStageProcessing.Selection()).layer
        check(applied.channelSettings==before,"conversion must not substitute source shaping values into the destination")
        check(applied.gain==1 && applied.pan == -0.25,"the source fader and pan must still apply")
        guard let record=applied.mainStageSource else {
            print("::error file=Tests/MainStageShapingReportTests.swift,line=\(#line)::the converted layer must carry its source record");exit(1)
        }
        check(record.retainedShaping==draft.retainedShaping,"the source record must carry the retained values")
        check(record.valid,"a record with retained shaping must validate")
        let reloaded=try JSONDecoder().decode(Layer.self,from:JSONEncoder().encode(applied))
        check(reloaded.mainStageSource?.retainedShaping==draft.retainedShaping,"retained shaping must survive library persistence")
        // Earlier records and sources without the field still decode and validate.
        guard var json=try JSONSerialization.jsonObject(with:JSONEncoder().encode(record)) as? [String:Any] else {
            print("::error file=Tests/MainStageShapingReportTests.swift,line=\(#line)::the source record must encode as an object");exit(1)
        }
        json.removeValue(forKey:"retainedShaping")
        let legacy=try JSONDecoder().decode(MainStageSourceRecord.self,from:JSONSerialization.data(withJSONObject:json))
        check(legacy.retainedShaping==nil && legacy.valid,"an earlier record without retained shaping must still decode")
        let plain=shapingDraft(["Channel_envelopeExtra":"x"])
        check(plain.retainedShaping["Channel_envelopeExtra"]=="\"x\"","a text value must be retained as text")
        // Bounds keep a hostile document from inflating the saved record.
        var overlong=record
        overlong.retainedShaping=["Channel_attack":String(repeating:"x",count:161)]
        check(!overlong.valid,"an over-long retained value must be rejected")
        var crowded=record
        crowded.retainedShaping=Dictionary(uniqueKeysWithValues:(0..<65).map{("key\($0)","1")})
        check(!crowded.valid,"more than 64 retained fields must be rejected")
        var wide:[String:Any]=[:]
        for index in 0..<40 {wide["Channel_envelope\(index)"]=NSNumber(value:index)}
        let wideDraft=shapingDraft(wide)
        check(wideDraft.retainedShaping.count==32,"at most 32 shaping fields are retained, got \(wideDraft.retainedShaping.count)")
        check(wideDraft.issues.contains{$0.contains("45 sound-shaping fields")},"the report must count fields beyond the retention limit")
        // A key that cannot fit the record bounds is reported and skipped, so one
        // oversized source key cannot invalidate the record and block the import.
        let oversizedKey="Channel_envelope"+String(repeating:"k",count:96)
        let oversizedDraft=shapingDraft([oversizedKey:NSNumber(value:1)])
        check(oversizedDraft.retainedShaping[oversizedKey]==nil,"an oversized shaping key must not be retained")
        check(oversizedDraft.retainedShaping.count==5,"an oversized shaping key must not displace the retainable ones")
        check(oversizedDraft.issues.contains{$0.contains("1 source sound-shaping key is longer than 96 characters")},"the report must name an oversized key by length")
        check(!oversizedDraft.issues.contains{$0.contains(oversizedKey)},"the report must not repeat an oversized key")
        var bounded=record
        bounded.retainedShaping=oversizedDraft.retainedShaping
        check(bounded.valid,"a record that skipped an oversized key must still validate")
        // A shared setlist must not carry a local source path in a retained value.
        var shared=applied
        shared.mainStageSource?.retainedShaping=["Channel_envelopePath":"/Users/owner/Private/Attack.exs"]
        let patch=Patch(name:"Shaping",layers:[shared],snapshots:[])
        var setlist=Setlist()
        setlist.patches=[patch]
        SetlistShare.sanitize(&setlist)
        check(setlist.patches[0].layers[0].mainStageSource?.retainedShaping?["Channel_envelopePath"]=="[source location]","a shared record must not carry a local source path")
        check(setlist.patches[0].layers[0].mainStageSource?.valid==true,"a sanitized record must still validate")
        // A retained key can itself be a local path, so sharing redacts keys too.
        var keyed=applied
        keyed.mainStageSource?.retainedShaping=["/Users/owner/Private/Attack.exs":"1","Channel_attack":"0.042"]
        var keyedSetlist=Setlist()
        keyedSetlist.patches=[Patch(name:"Shaping keys",layers:[keyed],snapshots:[])]
        SetlistShare.sanitize(&keyedSetlist)
        let sharedKeys=keyedSetlist.patches[0].layers[0].mainStageSource?.retainedShaping
        check(sharedKeys?["/Users/owner/Private/Attack.exs"]==nil,"a shared record must not carry a local path in a shaping key")
        check(sharedKeys?["[source location]"]=="1","a redacted key must keep its own value")
        check(sharedKeys?["Channel_attack"]=="0.042","a portable key and value must be left unchanged")
        check(keyedSetlist.patches[0].layers[0].mainStageSource?.valid==true,"a record with a redacted key must still validate")
        print("PASS: each retained source shaping value is named with its value, the destination keeps its own values, records validate, persist and sanitize, and hostile sizes are bounded")
    }
}
