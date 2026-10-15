import Foundation

/// Main-thread MIDI scheduler. Dispatch timer timing is suitable for a prototype,
/// not sample-accurate sequencing. Configure and all note calls belong on main.
final class MIDIFXProcessor {
    var onNoteWithSource: ((Int,Int,Int,Float,Int32?)->Void)?
    var onNote: ((Int, Int, Int, Float) -> Void)?
    var onOff: ((Int, Int, Bool) -> Void)?
    private struct Held { var key: Int; var pitch: Int; var velocity: Float; var sourceID:Int32? }
    private struct Active { var key: Int; var release: TimeInterval; var source: Int; var pitch:Int; var sourceID:Int32? }
    private struct Channel {
        var program = MIDIProgram()
        var held: [Held] = []
        var released: Set<Int> = []
        var active: [Active] = []
        var direct: [Int: [Int]] = [:]
        var index = 0
        var next: TimeInterval?
        var began:TimeInterval?
        var nominalBeat:Double=0
        var velocityBegan: TimeInterval?
        var nextRetrigger: TimeInterval?
    }
    private var channels: [Int: Channel] = [:]
    private var tempo: Double = 72
    private var generatedKey = -1
    private var timer: Timer?
    private let automatic: Bool
    private var time: TimeInterval = 0

    init(automaticallySchedule: Bool = true) {
        automatic = automaticallySchedule
        if automaticallySchedule {time=ProcessInfo.processInfo.systemUptime}
    }
    private func ensureTimer(){
        guard automatic,timer == nil else{return}
        timer=Timer(timeInterval:0.005,repeats:true){[weak self] _ in self?.advance(to:ProcessInfo.processInfo.systemUptime)}
        RunLoop.main.add(timer!,forMode:.common)
    }
    deinit { timer?.invalidate() }
    func updateTempo(_ value:Double){
        let next=value.isFinite ? min(300,max(20,value)):72
        guard next != tempo else{return}
        for index in Array(channels.keys) {
            guard var channel=channels[index],channel.program.freeRateSeconds == nil,let began=channel.began else{continue}
            channel.began=time-(time-began)*tempo/next
            if channel.next != nil {channel.next=channel.began!+Self.groovedBeat(channel.nominalBeat,program:channel.program)*60/next}
            channels[index]=channel
        }
        tempo=next
    }
    func configure(channel: Int, program: MIDIProgram, tempo: Double) {
        guard (0..<16).contains(channel) else { return }
        updateTempo(tempo)
        if program.kind == .arpeggiator || program.kind == .sequencer {ensureTimer()}
        if channels[channel]?.program == program.validated { return }
        silence(channel)
        channels[channel] = Channel(program: program.validated)
    }
    private func notify(_ channel:Int,_ key:Int,_ pitch:Int,_ velocity:Float,_ source:Int32?){onNote?(channel,key,pitch,velocity);onNoteWithSource?(channel,key,pitch,velocity,source)}
    private func newKey() -> Int {
        let key = generatedKey
        generatedKey = generatedKey == Int.min + 1 ? -1 : generatedKey - 1
        return key
    }
    private func emit(channel: Int, pitch: Int, velocity: Float,sourceID:Int32? = nil) -> Int? {
        guard (0...127).contains(pitch), velocity > 0 else { return nil }
        let key = newKey()
        notify(channel,key,pitch,min(1,max(0,velocity)),sourceID)
        return key
    }
    func noteOn(channel: Int, key: Int, pitch: Int, velocity: Float, sourceID:Int32? = nil) {
        guard (0..<16).contains(channel), (0...127).contains(pitch), velocity.isFinite else { return }
        if velocity <= 0 { noteOff(channel: channel, key: key); return }
        if automatic { advance(to: ProcessInfo.processInfo.systemUptime) }
        if channels[channel] == nil { channels[channel] = Channel() }
        noteOff(channel: channel, key: key, force: true)
        var c = channels[channel]!
        if c.program.hold == true && !c.released.isEmpty {
            c.held.removeAll{c.released.contains($0.key)};c.released.removeAll()
        }
        if c.program.kind == .arpeggiator && c.program.retriggerOnNote == true {c.index=0;c.next=time;c.began=time;c.nominalBeat=0;if c.program.retriggerVelocity == true {c.velocityBegan=time}}
        c.held.append(Held(key: key, pitch: pitch, velocity: min(1, velocity),sourceID:sourceID))
        switch c.program.kind {
        case .bypass:
            c.direct[key] = [key]
            notify(channel,key,pitch,min(1,velocity),sourceID)
        case .octaveUp:
            let original = emit(channel: channel, pitch: pitch, velocity: velocity,sourceID:sourceID)
            let extra = emit(channel: channel, pitch: pitch + 12, velocity: velocity * (c.program.octaveBlend ?? 1),sourceID:sourceID)
            c.direct[key] = [original, extra].compactMap { $0 }
        case .easyChord:
            let outputs: [Int]
            if let mappings = c.program.chordMappings {
                outputs = mappings.first(where: { $0.input == pitch })?.output ?? [pitch]
            } else { outputs = c.program.chordIntervals.map { pitch + $0 } }
            c.direct[key] = outputs.compactMap { emit(channel: channel, pitch: $0, velocity: velocity,sourceID:sourceID) }
        case .sequencer:
            if let mappings = c.program.sequenceMappings, !mappings.contains(where: { $0.input == pitch }) {
                c.direct[key] = [key]
                notify(channel,key,pitch,min(1,velocity),sourceID)
            } else if c.next == nil { c.next = time; c.index = 0;c.began=time;c.nominalBeat=0 }
        case .arpeggiator:
            if c.next == nil { c.next=time;c.index=0;c.began=time;c.nominalBeat=0;c.velocityBegan=time;c.nextRetrigger=c.program.retriggerBeats.map{time+60/tempo*$0} }
        }
        channels[channel] = c
        advance(to: time)
    }
    func noteOff(channel: Int, key: Int, force: Bool = false) {
        guard var c = channels[channel] else { return }
        guard c.held.contains(where:{$0.key==key}) || c.direct[key] != nil || c.active.contains(where:{$0.source==key}) else{return}
        if c.program.kind == .arpeggiator && c.program.hold == true && !force {
            c.released.insert(key);channels[channel]=c;return
        }
        c.released.remove(key)
        c.held.removeAll { $0.key == key }
        if force || c.program.releaseGeneratedOnKeyUp != false {
            for a in c.active where a.source == key { onOff?(channel, a.key, true) }
            c.active.removeAll { $0.source == key }
        }
        let direct = c.direct.removeValue(forKey: key) ?? []
        for k in direct { onOff?(channel, k, false) }
        if c.held.isEmpty {
            if c.program.releaseGeneratedOnKeyUp != false {
                for a in c.active { onOff?(channel, a.key, true) };c.active.removeAll()
            }
            c.next = nil;c.nextRetrigger=nil;c.velocityBegan=nil; c.index = 0
        }
        channels[channel] = c
    }
    /// Deterministic scheduler entry point; monotonic seconds only. Missed ticks
    /// are skipped after long stalls instead of emitting an unbounded burst.
    func advance(to now: TimeInterval) {
        guard now.isFinite, now >= time else { return }
        time = now
        for channel in channels.keys.sorted() {
            guard var c = channels[channel] else { continue }
            for a in c.active where a.release <= now { onOff?(channel, a.key, c.program.releaseGeneratedOnKeyUp != false) }
            c.active.removeAll { $0.release <= now }
            if let beat=c.nextRetrigger,beat<=now,let beats=c.program.retriggerBeats {
                c.index=0;c.next=now;c.began=now;c.nominalBeat=0;c.nextRetrigger=now+60/tempo*beats
                if c.program.retriggerVelocity == true {c.velocityBegan=now}
            }
            guard !c.held.isEmpty, let next = c.next, next <= now else { channels[channel] = c; continue }
            let period = c.program.freeRateSeconds ?? (60 / tempo * c.program.subdivision)
            // Skip to the latest due musical step using the inverse swing mapping.
            // A straight-period estimate can land on a future swung step after a stall.
            let skipped:Int
            if c.program.freeRateSeconds == nil,let began=c.began {
                let beat=Self.ungroovedBeat(max(0,(now-began)*tempo/60),program:c.program)
                skipped=Int(min(1_000_000,max(0,floor((beat-c.nominalBeat)/c.program.subdivision+1e-8))))
            } else {skipped=Int(min(1_000_000,max(0,floor((now-next)/period))))}
            if skipped>0 {c.index += skipped;c.nominalBeat += Double(skipped)*c.program.subdivision}
            let baseCount=c.program.style == .chord ? 1:max(1,c.held.count*c.program.octaves)
            let cycle=(c.program.style == .upDown || c.program.style == .downUp) && baseCount>2 ? baseCount*2-2:baseCount
            let transposeCycle=max(1,(c.program.transposeSteps ?? 0)+1)
            if let repeats=c.program.repeatCount,c.index >= cycle*transposeCycle*repeats {c.next=nil;channels[channel]=c;continue}
            var generated: [(Int, Float, Int)] = []
            if c.program.kind == .sequencer {
                if let mappings = c.program.sequenceMappings {
                    for source in c.held {
                        guard let mapping = mappings.first(where: { $0.input == source.pitch }), !mapping.steps.isEmpty else { continue }
                        let step = mapping.steps[c.index % mapping.steps.count]
                        if step.enabled { generated.append((step.pitch, source.velocity * step.velocity * (c.program.sequenceVelocity ?? 1), source.key)) }
                    }
                } else {
                    let step = c.program.steps[c.index % c.program.steps.count]
                    let root = c.held.last!
                    if step.enabled { generated.append((root.pitch + step.pitch, root.velocity * step.velocity * (c.program.sequenceVelocity ?? 1), root.key)) }
                }
            } else {
                let grid = c.program.arpVelocities ?? Array(repeating: Float(1), count: 16)
                let velocity = grid.isEmpty ? 1 : grid[c.index % grid.count]
                if c.program.style == .chord {
                    for source in c.held {
                        for octave in 0..<c.program.octaves {
                            generated.append((source.pitch + 12 * octave, source.velocity * velocity, source.key))
                        }
                    }
                } else if let note = Self.arpeggio(held: c.held.map { ($0.pitch, $0.velocity) }, program: c.program, index: c.index + (c.program.patternOffset ?? 0)) {
                    let source = c.held.first(where: { $0.pitch == note.0 && $0.velocity == note.1 }) ?? c.held.first(where: { ($0.pitch...($0.pitch + 12 * (c.program.octaves - 1))).contains(note.0) && (note.0 - $0.pitch) % 12 == 0 }) ?? c.held[0]
                    generated.append((note.0, note.1 * velocity, source.key))
                }
            }
            for (rawPitch, rawVelocity, source) in generated {
                let shift=(c.index/cycle % transposeCycle)*(c.program.transposeDistance ?? 12)
                let pitch=rawPitch+shift
                var velocity=rawVelocity
                if let target=c.program.velocityTarget,let decay=c.program.velocityDecaySeconds {
                    let fraction=Float(min(1,max(0,(now-(c.velocityBegan ?? now))/decay)))
                    velocity=rawVelocity+(target-rawVelocity)*fraction
                }
                // MIDI note-off cannot distinguish overlapping instances of the same pitch.
                for old in c.active where old.pitch==pitch {onOff?(channel,old.key,c.program.releaseGeneratedOnKeyUp != false)}
                c.active.removeAll{$0.pitch==pitch}
                if let key = emit(channel: channel, pitch: pitch, velocity: velocity,sourceID:c.held.first(where:{$0.key==source})?.sourceID) {
                    c.active.append(Active(key: key, release: now + period * c.program.gate, source: source,pitch:pitch,sourceID:c.held.first(where:{$0.key==source})?.sourceID))
                }
            }
            c.index += 1;c.nominalBeat += c.program.subdivision
            if c.program.freeRateSeconds == nil,let began=c.began {c.next=began+Self.groovedBeat(c.nominalBeat,program:c.program)*60/tempo}
            else{c.next=next+Double(skipped+1)*period}
            channels[channel] = c
        }
    }
    static func groovedBeat(_ beat:Double,program:MIDIProgram)->Double {
        guard let grid=program.swingGridBeats,grid>0,let amount=program.swingAmount,amount>0 else{return beat}
        let pair=grid*2,start=floor(beat/pair)*pair,phase=beat-start,shift=min(1,max(0,amount))/3
        return start+(phase<=grid ? phase*(1+shift):grid*(1+shift)+(phase-grid)*(1-shift))
    }
    static func ungroovedBeat(_ beat:Double,program:MIDIProgram)->Double {
        guard let grid=program.swingGridBeats,grid>0,let amount=program.swingAmount,amount>0 else{return beat}
        let pair=grid*2,start=floor(beat/pair)*pair,phase=beat-start,shift=min(1,max(0,amount))/3,mid=grid*(1+shift)
        return start+(phase<=mid ? phase/(1+shift):grid+(phase-mid)/(1-shift))
    }
    static func arpeggio(held: [(Int, Float)], program: MIDIProgram, index: Int) -> (Int, Float)? {
        guard !held.isEmpty else { return nil }
        let p = program.validated
        var notes = p.style == .asPlayed ? held : held.sorted { $0.0 < $1.0 }
        let base = notes
        if p.octaves > 1 { for octave in 1..<p.octaves { notes += base.map { ($0.0 + 12 * octave, $0.1) } } }
        notes = notes.filter { (0...127).contains($0.0) }
        guard !notes.isEmpty else { return nil }
        if p.style == .down || p.style == .downUp { notes.reverse() }
        if (p.style == .upDown || p.style == .downUp), notes.count > 2 { notes += notes.dropFirst().dropLast().reversed() }
        if p.style == .random {
            // Reproducible pseudo-random order makes offline tests and recalls stable.
            var hash = UInt64(truncatingIfNeeded: max(0, index)) &+ 0x9e3779b97f4a7c15
            hash = (hash ^ (hash >> 30)) &* 0xbf58476d1ce4e5b9
            hash = (hash ^ (hash >> 27)) &* 0x94d049bb133111eb
            hash ^= hash >> 31
            return notes[Int(hash % UInt64(notes.count))]
        }
        return notes[max(0, index) % notes.count]
    }
    func releaseSource(_ sourceID:Int32) {
        for channel in Array(channels.keys) {
            guard let c=channels[channel] else{continue}
            let keys=Set(c.held.filter{$0.sourceID==sourceID}.map(\.key)+c.active.filter{$0.sourceID==sourceID}.map(\.source))
            for key in keys {noteOff(channel:channel,key:key,force:true)}
        }
    }
    private func silence(_ channel: Int) {
        guard let c = channels[channel] else { return }
        for keys in c.direct.values { for key in keys { onOff?(channel, key, true) } }
        for a in c.active { onOff?(channel, a.key, true) }
    }
    func panic(channel: Int) {
        silence(channel)
        if var c = channels[channel] { c.held=[]; c.released=[]; c.active=[]; c.direct=[:]; c.next=nil;c.nextRetrigger=nil;c.velocityBegan=nil; c.index=0; channels[channel]=c }
    }
    func panic() {
        for channel in channels.keys { silence(channel) }
        for channel in channels.keys { var c = channels[channel]!; c.held = []; c.released=[]; c.active = []; c.direct = [:]; c.next = nil;c.nextRetrigger=nil;c.velocityBegan=nil; c.index = 0; channels[channel] = c }
    }
}
