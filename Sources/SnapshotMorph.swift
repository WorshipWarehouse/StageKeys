import Foundation

/// Pure snapshot interpolation. Structural state belongs to the destination from
/// the first tick; only compatible numerical controls move during the fade.
enum SnapshotMorph {
    static func fraction(_ value: Float) -> Float {
        if value.isNaN || value == -.infinity { return 0 }
        if value == .infinity { return 1 }
        return min(1, max(0, value))
    }

    static func interpolateFloat(from: Float, to: Float, fraction value: Float,
                                 range: ClosedRange<Float> = 0...1) -> Float {
        let lower = range.lowerBound, upper = range.upperBound
        precondition(lower.isFinite && upper.isFinite)
        let start = from.isFinite ? min(upper, max(lower, from)) : lower
        let end = to.isFinite ? min(upper, max(lower, to)) : start
        let t = fraction(value)
        if t == 0 { return start }
        if t == 1 { return end }
        // Double arithmetic avoids intermediate overflow even for finite Float endpoints.
        return Float(Double(start) * (1 - Double(t)) + Double(end) * Double(t))
    }

    static func normalizedEffect(_ effect: AudioEffect) -> AudioEffect {
        guard AudioEffectCatalog.names.indices.contains(effect.kind) else { return AudioEffect() }
        var result = effect
        result.amount = interpolateFloat(from: effect.amount, to: effect.amount, fraction: 0)
        if let beats = effect.syncBeats {
            result.syncBeats = beats.isFinite ? min(4, max(0.0625, beats)) : nil
        }
        let defaults = AudioEffectCatalog.defaults(for: effect.kind)
        // Reading legacy values only after amount sanitization avoids NaN in log/exp conversions.
        let supplied = effect.parameters ?? result.values
        var values = defaults
        for descriptor in AudioEffectCatalog.descriptors(for: effect.kind) {
            let raw = supplied.indices.contains(descriptor.index) ? supplied[descriptor.index] : descriptor.defaultValue
            values[descriptor.index] = raw.isFinite ? min(descriptor.maximum, max(descriptor.minimum, raw)) : descriptor.defaultValue
        }
        result.parameters = values
        return result
    }

    static func interpolateEffects(from: [AudioEffect], to: [AudioEffect], fraction value: Float) -> [AudioEffect] {
        let t = fraction(value)
        return to.enumerated().map { index, destination in
            var target = normalizedEffect(destination)
            guard from.indices.contains(index), from[index].kind == destination.kind else { return target }
            let source = from[index]
            let expected = AudioEffectCatalog.defaults(for: destination.kind).count
            // Malformed explicit schemas cannot be paired safely, even when kind matches.
            guard source.parameters.map({ $0.count == expected }) ?? true,
                  destination.parameters.map({ $0.count == expected }) ?? true else { return target }
            let initial = normalizedEffect(source)
            target.amount = interpolateFloat(from: initial.amount, to: target.amount, fraction: t)
            var values = target.parameters ?? []
            for descriptor in AudioEffectCatalog.descriptors(for: target.kind) {
                var v = interpolateFloat(from: initial.values[descriptor.index], to: values[descriptor.index], fraction: t,
                                         range: descriptor.minimum...descriptor.maximum)
                // These controls use integer physical units rather than normalised UI percentages.
                if descriptor.unit == "bits" || (target.kind == 12 && descriptor.index == 0) { v = v.rounded() }
                values[descriptor.index] = v
            }
            target.parameters = values
            return target
        }
    }

    static func interpolateRack(from:ImportedRack,to:ImportedRack,fraction:Float)->ImportedRack {
        var rack=to;rack.effects=interpolateEffects(from:from.effects,to:to.effects,fraction:fraction)
        for i in rack.macros.indices {if let previous=from.macros.first(where:{$0.index==rack.macros[i].index}) {rack.macros[i].value=interpolateFloat(from:previous.value,to:rack.macros[i].value,fraction:fraction,range:0...127)}}
        if var children=rack.branches,let initial=from.branches,children.count==initial.count {
            for i in children.indices where children[i].sampleLayers==initial[i].sampleLayers {
                children[i].rack=interpolateRack(from:initial[i].rack,to:children[i].rack,fraction:fraction)
                children[i].gain=interpolateFloat(from:initial[i].gain ?? 1,to:children[i].gain ?? 1,fraction:fraction,range:0...4)
                children[i].pan=interpolateFloat(from:initial[i].pan,to:children[i].pan,fraction:fraction,range:-1...1)
            }
            rack.branches=children
        }
        return rack
    }
    static func interpolateSound(from: SnapshotSoundState, to: SnapshotSoundState, fraction: Float) -> SnapshotSoundState {
        var state = to
        state.effects = interpolateEffects(from: from.effects, to: to.effects, fraction: fraction)
        if let rack=to.importedRack,let initial=from.importedRack {state.importedRack=interpolateRack(from:initial,to:rack,fraction:fraction)}
        else {state.importedRack=to.importedRack ?? from.importedRack}
        state.pan = interpolateFloat(from: from.pan, to: to.pan, fraction: fraction, range: -1...1)
        state.midiProgram = to.midiProgram?.validated
        return state
    }

    /// Indices requiring a DSP configuration update. Canonical comparison ignores
    /// nil-versus-explicit legacy parameter storage and avoids repeatedly enqueuing
    /// unchanged/bypassed slots on every timer tick.
    static func changedEffectSlots(previous: [AudioEffect], current: [AudioEffect]) -> [Int] {
        current.indices.filter { index in
            guard previous.indices.contains(index) else { return true }
            let old = normalizedEffect(previous[index]), new = normalizedEffect(current[index])
            guard old.kind == new.kind, old.enabled == new.enabled else { return true }
            if old.kind == 0 || !old.enabled { return false }
            return old.syncBeats != new.syncBeats || old.values != new.values
        }
    }
}
