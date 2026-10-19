import SwiftUI

struct SoundSettingsControls: View {
    @Binding var layer: Layer
    private var samplerDB: Binding<Float> { Binding(get: { layer.channelSettings.samplerGain > 0 ? max(-60,20*log10(layer.channelSettings.samplerGain)) : -60 }, set: { layer.channelSettings.samplerGain = $0 <= -60 ? 0 : pow(10,$0/20) }) }
    private func card<Content: View>(_ title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) { Text(title).font(StageTheme.font(14, weight: .semibold)); Text(detail).font(StageTheme.font(11)).foregroundStyle(.secondary) }
            Spacer(minLength: 8); content()
        }.padding(16).frame(minHeight:76).background(StageTheme.panel, in: RoundedRectangle(cornerRadius:8))
    }
    var body: some View {
        HStack(alignment: .top, spacing:8) {
            VStack(spacing:8) {
                card("Block Sustain", detail:"Make the Sound ignore the Sustain Pedal") { Toggle("Block Sustain",isOn:$layer.blockSustain).labelsHidden().toggleStyle(.switch) }
                card("MIDI Input Transpose",detail:"Shift MIDI notes before they reach the MIDI effects") {
                    Stepper(value:Binding(get:{layer.effectiveTranspose},set:{layer.transpose=$0}),in: -48...48) { Text("\(layer.effectiveTranspose)").monospacedDigit().frame(minWidth:24) }.frame(width:150).accessibilityLabel("MIDI Input Transpose")
                }
                card("Voice Count",detail:"Simultaneous notes the Sound can play") {
                    if layer.external == nil && layer.midiDestinationID == nil { Stepper(value:$layer.channelSettings.voiceCount,in:1...64) { Text("\(layer.channelSettings.voiceCount)").monospacedDigit() }.frame(width:150).accessibilityLabel("Voice Count") }
                    else { Text("Instrument managed").font(.caption).foregroundStyle(.secondary) }
                }
                VStack(alignment:.leading,spacing:8) {
                    Text("Volume Fader Range").font(StageTheme.font(14,weight:.semibold))
                    HStack { Text("Min").font(.caption); Slider(value:$layer.channelSettings.faderMin,in: -60...layer.channelSettings.faderMax).accessibilityLabel("Minimum fader level"); Text("\(layer.channelSettings.faderMin,specifier:"%.0f") dB").font(.caption).frame(width:56) }
                    HStack { Text("Max").font(.caption); Slider(value:$layer.channelSettings.faderMax,in: layer.channelSettings.faderMin...0).accessibilityLabel("Maximum fader level"); Text("\(layer.channelSettings.faderMax,specifier:"%.0f") dB").font(.caption).frame(width:56) }
                }.padding(16).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:8))
            }
            if layer.midiDestinationID == nil {
                VStack(spacing:8) {
                    EffectKnob(descriptor:.init(index:0,name:"Sampler Vol",minimum:-60,maximum:12.0412,defaultValue:0,unit:"dB"),value:samplerDB).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:8))
                    if layer.external?.kind == .samplerPreset {
                        EffectKnob(descriptor:.init(index:2,name:"Attack Smoothing",minimum:0,maximum:100,defaultValue:0,unit:"ms"),value:Binding(get:{layer.samplerAttackMinimum*1000},set:{layer.channelSettings.samplerAttackMinimum=$0/1000})).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:8))
                    }
                    EffectKnob(descriptor:.init(index:1,name:"Audio Output · Pan",minimum:-1,maximum:1,defaultValue:0,unit:""),value:$layer.pan).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:8))
                }.frame(width:165)
            }
        }
    }
}


struct ImportedRackControls: View {
    @Binding var layer:Layer
    private func delayBinding(_ index:Int,_ path:WritableKeyPath<ImportedDelay,Double>)->Binding<Float> {
        Binding(get:{Float(layer.importedRack?.effects[index].importedDelay?[keyPath:path] ?? 0.25)},set:{value in layer.importedRack?.effects[index].importedDelay?[keyPath:path]=Double(value)})
    }
    private func channelBinding(_ index:Int,_ right:Bool,_ path:WritableKeyPath<ImportedDelay.Channel,Float>)->Binding<Float> {
        Binding(get:{
            let delay=layer.importedRack?.effects[index].importedDelay
            return (right ? delay?.rightChannel:delay?.leftChannel)?[keyPath:path] ?? 0
        },set:{value in
            guard var delay=layer.importedRack?.effects[index].importedDelay,var channel=right ? delay.rightChannel:delay.leftChannel else{return}
            channel[keyPath:path]=value
            if path == \.feedback {channel.feedback=min(channel.feedback,0.95-channel.crossFeedback)}
            if path == \.crossFeedback {channel.crossFeedback=min(channel.crossFeedback,0.95-channel.feedback)}
            if path == \.lowCut {channel.lowCut=min(channel.lowCut,channel.highCut)}
            if path == \.highCut {channel.highCut=max(channel.highCut,channel.lowCut)}
            if right {delay.rightChannel=channel}else{delay.leftChannel=channel}
            layer.importedRack?.effects[index].importedDelay=delay
        })
    }
    private func effectValue(_ index:Int,_ parameter:AudioEffectParameterDescriptor)->Binding<Float> {
        Binding(get:{layer.importedRack?.effects[index].values[parameter.index] ?? parameter.defaultValue},set:{value in
            guard var rack=layer.importedRack else{return}
            var values=rack.effects[index].values;values[parameter.index]=value; rack.effects[index].parameters=values
            guard rack.validate() else{return};layer.importedRack=rack
        })
    }
    private func eqBands(_ index:Int)->Binding<[EQBand]> {
        Binding(get:{
            guard let effect=layer.importedRack?.effects[index] else{return EQBand.defaults}
            return stride(from:0,to:24,by:3).map {offset in
                EQBand(frequency:effect.values[offset],gain:effect.values[offset+1],q:effect.values[offset+2])
            }
        },set:{bands in
            guard bands.count==8,var rack=layer.importedRack else{return}
            var values=rack.effects[index].values
            for (band,value) in bands.enumerated() {
                values[band*3]=value.frequency;values[band*3+1]=value.gain;values[band*3+2]=value.q
            }
            rack.effects[index].parameters=values
            guard rack.validate() else{return}
            layer.importedRack=rack
        })
    }
    @ViewBuilder private func delayControls(_ index:Int)->some View {
        if let delay=layer.importedRack?.effects[index].importedDelay {
            VStack {
                Toggle("Left Tempo Sync",isOn:Binding(get:{layer.importedRack?.effects[index].importedDelay?.leftSynced ?? true},set:{layer.importedRack?.effects[index].importedDelay?.leftSynced=$0}))
                EffectKnob(descriptor:.init(index:24,name:"Left Time",minimum:0.001,maximum:5.334,defaultValue:0.25,unit:delay.leftSynced ? "beats":"sec"),value:delayBinding(index,\.left))
            }
            VStack {
                Toggle("Right Tempo Sync",isOn:Binding(get:{layer.importedRack?.effects[index].importedDelay?.rightSynced ?? true},set:{layer.importedRack?.effects[index].importedDelay?.rightSynced=$0}))
                EffectKnob(descriptor:.init(index:25,name:"Right Time",minimum:0.001,maximum:5.334,defaultValue:0.25,unit:delay.rightSynced ? "beats":"sec"),value:delayBinding(index,\.right))
            }
            if delay.leftChannel != nil {
                ForEach([false,true],id:\.self){right in
                    let side=right ? "Right":"Left"
                    Picker(side+" Input",selection:Binding(get:{let delay=layer.importedRack?.effects[index].importedDelay;return (right ? delay?.rightChannel:delay?.leftChannel)?.input ?? (right ? 2:1)},set:{input in if right {layer.importedRack?.effects[index].importedDelay?.rightChannel?.input=input}else{layer.importedRack?.effects[index].importedDelay?.leftChannel?.input=input}})) {
                        Text("Off").tag(0);Text("Left").tag(1);Text("Right").tag(2);Text("L + R").tag(3);Text("L − R").tag(4)
                    }
                    Toggle(side+" Invert Feedback",isOn:Binding(get:{let delay=layer.importedRack?.effects[index].importedDelay;return (right ? delay?.rightChannel:delay?.leftChannel)?.feedbackPolarity == -1},set:{on in if right {layer.importedRack?.effects[index].importedDelay?.rightChannel?.feedbackPolarity=on ? -1:1}else{layer.importedRack?.effects[index].importedDelay?.leftChannel?.feedbackPolarity=on ? -1:1}}))
                    Toggle(side+" Invert Crossfeed",isOn:Binding(get:{let delay=layer.importedRack?.effects[index].importedDelay;return (right ? delay?.rightChannel:delay?.leftChannel)?.crossPolarity == -1},set:{on in if right {layer.importedRack?.effects[index].importedDelay?.rightChannel?.crossPolarity=on ? -1:1}else{layer.importedRack?.effects[index].importedDelay?.leftChannel?.crossPolarity=on ? -1:1}}))
                    EffectKnob(descriptor:.init(index:0,name:side+" Feedback",minimum:0,maximum:0.95,defaultValue:0.3,unit:"%"),value:channelBinding(index,right,\.feedback))
                    EffectKnob(descriptor:.init(index:1,name:side+" Cross Feedback",minimum:0,maximum:0.95,defaultValue:0,unit:"%"),value:channelBinding(index,right,\.crossFeedback))
                    EffectKnob(descriptor:.init(index:2,name:side+" Mix",minimum:0,maximum:1,defaultValue:0.3,unit:"%"),value:channelBinding(index,right,\.mix))
                    EffectKnob(descriptor:.init(index:3,name:side+" Low Cut",minimum:20,maximum:20000,defaultValue:20,unit:"Hz"),value:channelBinding(index,right,\.lowCut))
                    EffectKnob(descriptor:.init(index:4,name:side+" High Cut",minimum:20,maximum:20000,defaultValue:20000,unit:"Hz"),value:channelBinding(index,right,\.highCut))
                }
            }else{
                Toggle("Ping Pong",isOn:Binding(get:{layer.importedRack?.effects[index].importedDelay?.pingPong ?? false},set:{layer.importedRack?.effects[index].importedDelay?.pingPong=$0}))
                EffectKnob(descriptor:.init(index:26,name:"Low Cut",minimum:20,maximum:delay.highCut,defaultValue:20,unit:"Hz"),value:Binding(get:{layer.importedRack?.effects[index].importedDelay?.lowCut ?? 20},set:{layer.importedRack?.effects[index].importedDelay?.lowCut=$0}))
                EffectKnob(descriptor:.init(index:27,name:"High Cut",minimum:delay.lowCut,maximum:20000,defaultValue:20000,unit:"Hz"),value:Binding(get:{layer.importedRack?.effects[index].importedDelay?.highCut ?? 20000},set:{layer.importedRack?.effects[index].importedDelay?.highCut=$0}))
            }
        }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Sound Processing").font(StageTheme.font(15,weight:.semibold))
            if let rack=layer.importedRack {
                if !rack.macros.isEmpty {
                    LazyVGrid(columns:[GridItem(.adaptive(minimum:140))],spacing:8) {
                        ForEach(rack.macros) { macro in
                            EffectKnob(descriptor:.init(index:macro.index,name:macro.name+(macro.midiCC.map{" · CC\($0)"} ?? ""),minimum:0,maximum:127,defaultValue:macro.value,unit:""),value:Binding(get:{layer.importedRack?.macros.first(where:{$0.index==macro.index})?.value ?? macro.value},set:{layer.importedRack?.setMacro(macro.index,value:$0)}))
                        }
                    }
                }
                ForEach(Array(rack.effects.enumerated()),id:\.offset) { index,effect in
                    DisclosureGroup("\(index+1). \(effect.title)") {
                        Toggle("Enabled",isOn:Binding(get:{layer.importedRack?.effects[index].enabled ?? false},set:{layer.importedRack?.effects[index].enabled=$0}))
                        if effect.kind == 7 {
                            ChannelEqualizerControls(bands:eqBands(index),enabled:Binding(get:{layer.importedRack?.effects[index].enabled ?? false},set:{layer.importedRack?.effects[index].enabled=$0}))
                        } else {
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:140))],spacing:8) {
                            if effect.importedDelay != nil { delayControls(index) }
                            ForEach(AudioEffectCatalog.descriptors(for:effect.kind).filter{!(effect.kind==16 && [9,10].contains($0.index)) && (effect.importedDelay == nil || effect.importedDelay?.leftChannel == nil && ![1,2].contains($0.index))}) { parameter in
                                EffectKnob(descriptor:parameter,value:Binding(get:{layer.importedRack?.effects[index].values[parameter.index] ?? parameter.defaultValue},set:{value in guard var imported=layer.importedRack else{return};var values=imported.effects[index].values;values[parameter.index]=value;imported.effects[index].parameters=values;layer.importedRack=imported}))
                            }
                        }
                        if effect.kind==16 {
                            HStack(spacing:24) {
                                ForEach(AudioEffectCatalog.descriptors(for:16).filter{[9,10].contains($0.index)}) {parameter in
                                    EffectKnob(descriptor:parameter,value:effectValue(index,parameter))
                                }
                            }.frame(maxWidth:.infinity)
                        }
                        }
                    }
                }
                if let branches=rack.branches {
                    ForEach(Array(branches.enumerated()),id:\.offset){index,branch in
                        ImportedBranchControls(branch:Binding(get:{layer.importedRack?.branches?[index] ?? branch},set:{layer.importedRack?.branches?[index]=$0}))
                    }
                }
                ForEach(Array((rack.audioRacks ?? []).enumerated()),id:\.offset) {stageIndex,stage in
                    DisclosureGroup("\(stage.name) · Parallel Audio") {
                        Text("Before effect \(stage.beforeEffect+1) · Shared audio input").font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(stage.branches.enumerated()),id:\.offset) {branchIndex,branch in
                            ImportedAudioBranchControls(branch:Binding(get:{layer.importedRack?.audioRacks?[stageIndex].branches[branchIndex] ?? branch},set:{layer.importedRack?.audioRacks?[stageIndex].branches[branchIndex]=$0}))
                        }
                    }
                }
                if rack.effects.isEmpty && rack.branches == nil && rack.audioRacks == nil {Text("No translated rack effects").foregroundStyle(.secondary)}
            }
        }.padding(16).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:8))
    }
}

struct ImportedBranchControls:View {
    @Binding var branch:ImportedBranch
    private var rackLayer:Binding<Layer>{Binding(get:{var layer=Layer(name:branch.name,instrument:0,gain:0.5);layer.importedRack=branch.rack;return layer},set:{if let rack=$0.importedRack{branch.rack=rack}})}
    var body:some View {
        DisclosureGroup(branch.name) {
            Toggle("Branch On",isOn:Binding(get:{branch.enabled ?? true},set:{branch.enabled=$0}))
            HStack {
                EffectKnob(descriptor:.init(index:0,name:"Branch Level",minimum:-60,maximum:12.0412,defaultValue:0,unit:"dB"),value:Binding(get:{max(-60,20*log10(max(0.001,branch.gain ?? 1)))},set:{branch.gain=$0<=(-60) ? 0:pow(10,$0/20)}))
                EffectKnob(descriptor:.init(index:1,name:"Branch Pan",minimum:-1,maximum:1,defaultValue:0,unit:""),value:$branch.pan)
            }
            if let midi=branch.midi {
                DisclosureGroup("MIDI · \(midi.kind.title)") {
                    Toggle("MIDI Effect On",isOn:Binding(get:{branch.midiEnabled ?? true},set:{branch.midiEnabled=$0}))
                    if midi.kind == .arpeggiator {
                        Picker("Style",selection:Binding(get:{branch.midi?.style ?? .up},set:{branch.midi?.style=$0})) {ForEach(MIDIArpStyle.allCases,id:\.self){style in Text(style.title).tag(style)}}
                        Picker("Rate",selection:Binding(get:{branch.midi?.subdivision ?? 0.25},set:{branch.midi?.subdivision=$0;branch.midi?.freeRateSeconds=nil})) {ForEach([128,96,64,48,32,24,16,12,8,6,4,3,2,1],id:\.self){division in Text("1/\(division)").tag(4.0/Double(division))}}
                        HStack {Text("Gate");Slider(value:Binding(get:{branch.midi?.gate ?? 0.5},set:{branch.midi?.gate=$0}),in:0.01...2);Text("\(Int((branch.midi?.gate ?? 0.5)*100)) %")}
                        Toggle("Hold",isOn:Binding(get:{branch.midi?.hold ?? false},set:{branch.midi?.hold=$0}))
                        HStack {Text("Swing Amount");Slider(value:Binding(get:{branch.midi?.swingAmount ?? 0},set:{if var program=branch.midi {program.swingAmount=$0;program.swingGridBeats=program.swingGridBeats ?? 0.5;branch.midi=program}}),in:0...1)}
                    }
                }
            }
            ImportedRackControls(layer:rackLayer)
        }.padding(12).background(StageTheme.base.opacity(0.35),in:RoundedRectangle(cornerRadius:8))
    }
}

struct ImportedAudioBranchControls:View {
    @Binding var branch:ImportedAudioBranch
    private var rackLayer:Binding<Layer>{Binding(get:{var layer=Layer(name:branch.name,instrument:0,gain:0.5);layer.importedRack=branch.rack;return layer},set:{if let rack=$0.importedRack{branch.rack=rack}})}
    var body:some View {
        DisclosureGroup(branch.name) {
            Toggle("Branch On",isOn:$branch.enabled)
            EffectKnob(descriptor:.init(index:0,name:"Pan",minimum:-1,maximum:1,defaultValue:0,unit:""),value:$branch.pan)
            ImportedRackControls(layer:rackLayer)
        }.padding(10).background(StageTheme.base.opacity(0.35),in:RoundedRectangle(cornerRadius:8))
    }
}

struct ChannelCompressorControls:View {
    @Binding var settings:ChannelSettings
    private func knob(_ title:String,_ binding:Binding<Float>,_ low:Float,_ high:Float,_ unit:String)->some View {
        EffectKnob(compact:true,descriptor:.init(index:0,name:title,minimum:low,maximum:high,defaultValue:binding.wrappedValue,unit:unit),value:binding)
    }
    private func panel<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View {
        VStack(spacing:12){Text(title).font(StageTheme.font(14,weight:.semibold)).padding(.vertical,12);Divider();content();Spacer(minLength:12)}.frame(maxWidth:.infinity).frame(height:344).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:8))
    }
    private func fader(_ label:String,_ binding:Binding<Float>,_ low:Float,_ high:Float,_ unit:String)->some View {
        VStack {Text(label).font(.caption);VerticalFader(gain:Binding(get:{(binding.wrappedValue-low)/(high-low)},set:{binding.wrappedValue=low+$0*(high-low)}),color:StageTheme.selected,label:label,decibels:false).frame(width:64,height:190);Text(unit == "%" ? "\(Int(binding.wrappedValue*100)) %":String(format:"%.1f dB",binding.wrappedValue)).font(.caption)}
    }
    var body:some View {
        HStack(alignment:.top,spacing:5) {
            panel("Input"){fader("Gain",Binding(get:{settings.compressorInputGain ?? 0},set:{settings.compressorInputGain=$0}),-24,24,"dB")}
            panel("Envelope") {
                knob("Attack",Binding(get:{settings.compressorAttack*1000},set:{settings.compressorAttack=$0/1000}),1,1000,"ms")
                knob("Release",Binding(get:{settings.compressorRelease*1000},set:{settings.compressorRelease=$0/1000}),10,3000,"ms")
            }
            panel("Loudness") {knob("Ratio",$settings.ratio,1,20,":1");knob("Threshold",$settings.threshold,-60,0,"dB")}
            panel("Mix"){fader("Dry / Wet",Binding(get:{settings.compressorMix ?? 1},set:{settings.compressorMix=$0}),0,1,"%")}
            panel("Output"){fader("Gain",$settings.makeup,-24,24,"dB")}
        }.disabled(!settings.compressorEnabled)
    }
}

struct StageKeysSamplerControls:View {
    @EnvironmentObject private var store:PerformanceStore
    let sound:ExternalSound
    @State private var map:StageKeysSampler.Map?
    @State private var failure:String?
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {Image(systemName:"pianokeys");Text("StageKeys Sampler").font(StageTheme.font(16,weight:.semibold));Spacer();Text("Native playback").font(.caption).foregroundStyle(.secondary)}
            if let map {
                Text("\(map.sampleCount) samples · \(map.layerCount) layers · \(map.zones.count) zones").font(.caption)
                if let envelope=map.amplitudeEnvelope {
                    Text("Amplitude Envelope").font(StageTheme.font(14,weight:.semibold))
                    Text("Attack \(envelope.attack,specifier: "%.3f") s · Decay \(envelope.decay,specifier: "%.3f") s · Sustain \(envelope.sustain*100,specifier: "%.0f")% · Release \(envelope.release,specifier: "%.3f") s").font(.caption).monospacedDigit()
                    Text("Source base values; group release offsets are added during playback.").font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Sample Map") {
                    ScrollView {
                        LazyVStack(alignment:.leading,spacing:8) {
                            ForEach(map.zones) {zone in
                                HStack {
                                    Text(zone.sample).lineLimit(1).frame(maxWidth:.infinity,alignment:.leading)
                                    Text("Keys \(zone.low)–\(zone.high) · Root \(zone.root) · Velocity \(zone.velocityLow)–\(zone.velocityHigh)"+(zone.looped ? " · Loop":"")).monospacedDigit()
                                }.font(.caption)
                            }
                        }
                    }.frame(maxHeight:180)
                }
            } else if let failure {Text(failure).font(.caption).foregroundStyle(.secondary)}
        }.padding(16).background(StageTheme.panel,in:RoundedRectangle(cornerRadius:8))
        .task(id:sound.fileName) {
            do {guard let root=store.audio.externalRack?.libraryURL else{return};map=try StageKeysSampler.map(sound,library:root);failure=nil}
            catch{map=nil;failure="Sample map is unavailable: "+error.localizedDescription}
        }
    }
}
