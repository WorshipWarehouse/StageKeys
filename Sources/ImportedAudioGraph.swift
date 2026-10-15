import AVFoundation

/// An ordered audio processing graph. Fan-out shares one input signal; it never creates MIDI/sample voices.
final class ImportedAudioGraph {
    let input=AVAudioMixerNode()
    let output=AVAudioMixerNode()
    private(set) var nodes:[AVAudioNode]=[]
    private var effects:[AVAudioUnitEffect]=[]
    private struct Split {var graphs:[ImportedAudioGraph];var outputs:[AVAudioMixerNode]}
    private var splits:[Split]=[]
    let topology:String
    init(engine:AVAudioEngine,rack:ImportedRack,format:AVAudioFormat,tempo:Float) {
        topology=rack.audioTopology
        func attach(_ node:AVAudioNode){engine.attach(node);nodes.append(node)}
        attach(input);attach(output)
        var previous:AVAudioNode=input
        let stages=rack.audioRacks ?? []
        splits=stages.map{_ in Split(graphs:[],outputs:[])}
        for index in 0...rack.effects.count {
            for (stageIndex,stage) in stages.enumerated() where stage.beforeEffect == index {
                let sum=AVAudioMixerNode();attach(sum)
                var points:[AVAudioConnectionPoint]=[]
                for branch in stage.branches {
                    let graph=ImportedAudioGraph(engine:engine,rack:branch.rack,format:format,tempo:tempo)
                    nodes += graph.nodes
                    let level=AVAudioMixerNode();attach(level)
                    engine.connect(graph.output,to:level,format:format)
                    engine.connect(level,to:sum,format:format)
                    points.append(AVAudioConnectionPoint(node:graph.input,bus:0))
                    splits[stageIndex].graphs.append(graph);splits[stageIndex].outputs.append(level)
                }
                // Repeated single-destination connects would silently replace previous branches.
                engine.connect(previous,to:points,fromBus:0,format:format)
                previous=sum
            }
            if index<rack.effects.count {
                let effect=BuiltinEffectUnit.make();attach(effect);effects.append(effect)
                let fx=rack.effects[index]
                (effect.auAudioUnit as? BuiltinEffectUnit)?.configure(slot:0,kind:fx.kind,enabled:fx.enabled,values:fx.renderValues,tempo:tempo,delay:fx.importedDelay)
                engine.connect(previous,to:effect,format:format);previous=effect
            }
        }
        engine.connect(previous,to:output,format:format)
        configure(rack,tempo:tempo)
    }
    func configure(_ rack:ImportedRack,tempo:Float) {
        for (i,unit) in effects.enumerated() where rack.effects.indices.contains(i) {let fx=rack.effects[i];(unit.auAudioUnit as? BuiltinEffectUnit)?.configure(slot:0,kind:fx.kind,enabled:fx.enabled,values:fx.renderValues,tempo:tempo,delay:fx.importedDelay)}
        for (i,split) in splits.enumerated() {
            guard let stages=rack.audioRacks,stages.indices.contains(i) else{continue}
            for (j,graph) in split.graphs.enumerated() where stages[i].branches.indices.contains(j) {
                let branch=stages[i].branches[j];graph.configure(branch.rack,tempo:tempo)
                split.outputs[j].pan=branch.pan;split.outputs[j].outputVolume=branch.enabled ? 1:0
            }
        }
    }
    func reset(){for node in nodes {if let effect=node as? AVAudioUnitEffect {effect.auAudioUnit.reset()}}}
}
