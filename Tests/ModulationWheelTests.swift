import Foundation

@main struct ModulationWheelTests {
    static func main() {
        var wheel=ModulationWheelDrag()
        var value=wheel.update(current:0.5,translation:0,height:100)
        assert(value==ModulationWheelDrag.quantized(0.5))
        value=wheel.update(current:value,translation:-10,height:100)
        assert(abs(value-0.6)<1/127)
        // Hardware changed CC1 while the pointer remained down: only apply the new delta.
        value=wheel.update(current:0.1,translation:-20,height:100)
        assert(abs(value-0.2)<1/127)
        wheel.end()
        let held=wheel.update(current:value,translation:0,height:100)
        assert(held==value,"Release/click must not reset the held wheel")
        wheel.end();value=0
        for step in 1...100 {value=wheel.update(current:value,translation:Float(-step)*0.1,height:100)}
        assert(abs(value-0.1)<1/127,"Sub-step movements must accumulate before MIDI quantization")
        assert(wheel.update(current:value,translation:-1000,height:100)==1)
        assert(wheel.update(current:0.2,translation:.nan,height:100)==ModulationWheelDrag.quantized(0.2))
        for cc in 0...127 {assert(ModulationWheelDrag.quantized(Float(cc)/127)==Float(cc)/127)}
        print("PASS: held-position wheel, all CC1 steps, accumulated drag and hardware/snapshot handoff without stale-origin jumps")
    }
}
