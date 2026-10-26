import SwiftUI

struct VerticalFader: View {
    @Binding var gain: Float
    var color: Color
    var label: String
    var decibels = true
    var minDB: Float = -60
    var maxDB: Float = 0
    var onEnd: () -> Void = {}
    private var position: Float { decibels ? (gain < 0.001 ? 0 : max(0, (20 * log10(gain) - minDB) / max(0.01, maxDB - minDB))) : gain }
    private func set(_ p: Float) { let p = min(1, max(0, p)); gain = decibels ? (p < 0.001 ? 0 : pow(10, (minDB + p * (maxDB - minDB)) / 20)) : p }
    var body: some View {
        GeometryReader { g in
            let travel = max(1, g.size.height - 48)
            ZStack {
                VStack { ForEach(0..<9) { _ in Rectangle().fill(.white.opacity(0.12)).frame(height: 1); Spacer(minLength: 0) } }.padding(.vertical, 24)
                Capsule().fill(Color.black.opacity(0.35)).frame(width: 24).padding(.vertical, 24)
                Capsule().fill(color.opacity(0.75)).frame(width: 5, height: CGFloat(position) * travel).offset(y: (travel - CGFloat(position) * travel) / 2)
                RoundedRectangle(cornerRadius: 4).fill(LinearGradient(colors: [StageTheme.raised.opacity(0.9), Color.gray.opacity(0.8), StageTheme.raised], startPoint: .top, endPoint: .bottom))
                    .frame(width: 38, height: 48).shadow(color: .black.opacity(0.6), radius: 3, y: 3)
                    .overlay { Rectangle().fill(color).frame(width: 23, height: 2) }
                    .offset(y: travel * (0.5 - CGFloat(position)))
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { value in set(Float(1 - (value.location.y - 24) / travel)) }.onEnded { _ in onEnd() })
        }
        .accessibilityElement().accessibilityLabel(label).accessibilityValue(decibels ? StageTheme.db(gain) : "\(Int(gain * 100)) percent")
        .accessibilityAdjustableAction { direction in set(position + (direction == .increment ? 0.04 : -0.04)); onEnd() }
        #if os(macOS)
        .focusable()
        .onMoveCommand { direction in
            switch direction {case .up,.right:set(position+0.01);onEnd();case .down,.left:set(position-0.01);onEnd();default:break}
        }
        #endif
    }
}
struct MasterFader: View {
    @Binding var gain: Float
    var body: some View {
        GeometryReader { g in
            let width = max(1, g.size.width - 24)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6).fill(StageTheme.panel).overlay { RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.08)) }
                Capsule().fill(Color.black.opacity(0.4)).frame(height: 10).padding(.horizontal, 10)
                Rectangle().fill(StageTheme.selected.opacity(0.65)).frame(width: max(1, CGFloat(gain) * width), height: 3).padding(.leading, 12)
                RoundedRectangle(cornerRadius: 3).fill(LinearGradient(colors: [StageTheme.raised, StageTheme.selected.opacity(0.65), StageTheme.raised], startPoint: .leading, endPoint: .trailing)).frame(width: 17, height: 26).shadow(radius: 3).offset(x: 4 + CGFloat(gain) * width)
            }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0).onChanged { gain = Float(min(1, max(0, ( $0.location.x - 12) / width))) })
        }.accessibilityElement().accessibilityLabel("Master volume").accessibilityValue(StageTheme.db(gain)).accessibilityAdjustableAction { gain = min(1, max(0, gain + ($0 == .increment ? 0.04 : -0.04))) }
    }
}
struct RotaryControl: View {
    var title: String
    @Binding var value: Float
    @State private var initial: Float?
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(LinearGradient(colors: [StageTheme.raised, StageTheme.panel], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 39, height: 39)
                .overlay { Circle().trim(from: 0.13, to: 0.13+0.74*CGFloat(value)).stroke(StageTheme.selected.opacity(0.8), lineWidth: 2).rotationEffect(.degrees(90)) }
                .overlay { Rectangle().fill(StageTheme.selected).frame(width: 2, height: 10).offset(y: -8).rotationEffect(.degrees(-135 + Double(value) * 270)) }
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in if initial == nil { initial = value }; value = min(1, max(0, initial! - Float(v.translation.height) / 120)) }.onEnded { _ in initial = nil })
                .accessibilityElement().accessibilityLabel(title).accessibilityValue("\(Int(value*100)) percent")
                .accessibilityAdjustableAction { value = min(1, max(0, value + ($0 == .increment ? 0.05 : -0.05))) }
            VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 9)).foregroundStyle(.secondary); Text("\(Int(value*100)) %").font(StageTheme.font(14, weight: .semibold)).monospacedDigit() }
        }
    }
}
struct TonicPanel: View {
    @EnvironmentObject var store: PerformanceStore
    var onSettings:()->Void = {}
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Button { store.toggleTonic(store.tonicLastRoot) } label: {
                        Image(systemName:"power").frame(width:38,height:46)
                    }.buttonStyle(.plain).background(store.tonic == nil ? StageTheme.raised.opacity(0.5):StageTheme.selected.opacity(0.7),in:RoundedRectangle(cornerRadius:5)).accessibilityLabel("Tonic Pad power").accessibilityValue(store.tonic == nil ? "Off":"On")
                    Button(action:onSettings) {
                        VStack(alignment:.leading,spacing:3) {Text("Tonic Pad").font(.system(size:9)).foregroundStyle(.secondary);Text(store.tonicLabel).font(StageTheme.font(12,weight:.semibold)).lineLimit(1)}.frame(maxWidth:.infinity,alignment:.leading).frame(height:46).padding(.horizontal,6)
                    }.buttonStyle(.plain).background(StageTheme.raised.opacity(0.5),in:RoundedRectangle(cornerRadius:5)).accessibilityLabel("Tonic Pad Settings, \(store.tonicLabel)")
                    Button {store.toggleTonicPatchLock()}label:{
                        Group {if store.tonicLocked {Image(systemName:"lock.fill")} else {Text("Patch\nLock").font(.system(size:10,weight:.semibold))}}.frame(width:40,height:46)
                    }.buttonStyle(.plain).background(store.tonicLocked ? StageTheme.selected:StageTheme.raised.opacity(0.5),in:RoundedRectangle(cornerRadius:5)).foregroundStyle(store.tonicLocked ? StageTheme.base:.primary).accessibilityLabel("Tonic Pad Patch Lock").accessibilityValue(store.tonicLocked ? "Saved":"Not saved")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 4), spacing: 4) {
                    ForEach(0..<12) { root in
                        Button { store.selectTonicRoot(root) } label: { Text(StageTheme.notes[root]).font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 49) }
                            .buttonStyle(.plain).background(store.tonicLastRoot == root ? StageTheme.selected : StageTheme.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                            .foregroundStyle(store.tonicLastRoot == root ? StageTheme.base : .white).accessibilityLabel("Tonic \(StageTheme.notes[root])")
                    }
                }.disabled(!store.started)
                Spacer(minLength: 0)
                HStack(spacing: 4) { RotaryControl(title: "Brightness", value: $store.tonicBrightness); RotaryControl(title: "Shimmer", value: $store.tonicShimmer) }.padding(.top, 2)
            }
            VStack(spacing: 5) { VerticalFader(gain: $store.tonicGain, color: StageTheme.selected, label: "Tonic volume"); Text(StageTheme.db(store.tonicGain)).font(.system(size: 9)).monospacedDigit() }.frame(width: 44, height: 260)
        }.padding(8).background(StageTheme.panel, in: RoundedRectangle(cornerRadius: 9))
    }
}
struct SoundModule: View {
    @EnvironmentObject var store: PerformanceStore
    let index: Int
    let open: (StageSheet) -> Void
    private var layer: Layer { store.patch.layers[index] }
    private var color: Color { StageTheme.colors[index] }
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Button { open(.browser(index)) } label: { Text(layer.loaded ? layer.name : "").font(StageTheme.font(13, weight: .bold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading).frame(height: 40) }.buttonStyle(.plain)
                Button { open(.sound(index)) } label: { Image(systemName: "slider.horizontal.3").foregroundStyle(color).frame(width: 34, height: 45).background(StageTheme.raised.opacity(0.25)) }.buttonStyle(.plain).disabled(!layer.loaded).accessibilityLabel("Sound \(index+1) settings")
            }
            Divider().opacity(0.2)
            if layer.loaded {
                if !store.notesMode {
                    if store.patch.layers.contains(where:{$0.loaded && ($0.importedRack?.effectCount ?? 0)>0}) {
                        Group {
                            if let rack=layer.importedRack,rack.effectCount>0 {
                                Button {open(.sound(index))} label:{
                                    HStack {Image(systemName:"waveform.path");Text("Rack FX · \(rack.effectCount)");Spacer();Image(systemName:"chevron.right")}
                                        .font(StageTheme.font(10)).foregroundStyle(color)
                                }.buttonStyle(.plain).accessibilityLabel("Imported rack effects and macros")
                            } else {Color.clear.accessibilityHidden(true)}
                        }.frame(height:20)
                    }
                    midiSlot
                    ForEach(0..<3) { slot in effectSlot(slot) }
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 13)
                    VerticalFader(gain: Binding(get: { store.patch.layers[index].gain }, set: { store.setGain(index, $0) }), color: layer.muted ? .gray : color, label: "Sound \(index+1) volume", minDB: layer.channelSettings.faderMin, maxDB: layer.channelSettings.faderMax, onEnd: { store.save() }).frame(width: 62)
                    VStack { Text(StageTheme.db(layer.gain)).font(.system(size: 9)).foregroundStyle(.secondary); Spacer(); Text("−∞").font(.system(size: 9)).foregroundStyle(.tertiary) }.frame(width: 45)
                    Spacer(minLength: 0)
                }.frame(minHeight: 70).padding(.vertical, 7)
                Color.clear.frame(height: 1)
            } else {
                Spacer()
                Button { open(.browser(index)) } label: { VStack(spacing: 12) { Image(systemName: "plus.square").font(.system(size: 30)).foregroundStyle(color); Text("Add Sound").font(.headline) }.frame(maxWidth: .infinity) }.buttonStyle(.plain)
                Spacer()
            }
        }.padding(.horizontal, 8).padding(.vertical, 5)
            .background(LinearGradient(colors: [StageTheme.panel, color.opacity(layer.loaded ? 0.10 : 0.03)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 8))
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(layer.loaded ? color.opacity(0.15) : Color.white.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: layer.loaded ? [] : [4,3])) }
    }
    private var midiSlot: some View {
        let hasEffect = layer.octaveEffect || (layer.midiProgram?.kind != nil && layer.midiProgram?.kind != .bypass)
        return HStack(spacing: 0) {
            Button { if hasEffect { store.toggleMIDIEffect(index) } else { open(.midi(index)) } } label: {
                Image(systemName: "power").font(.system(size: 14)).frame(width: 34, height: 49).background(hasEffect && layer.midiEffectEnabled ? color.opacity(0.7) : Color.clear)
            }.buttonStyle(.plain).accessibilityLabel("Sound \(index+1) MIDI effect bypass").accessibilityValue(hasEffect && layer.midiEffectEnabled ? "On":"Off")
            Button { open(.midi(index)) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Midi").font(StageTheme.font(9)).foregroundStyle(.secondary)
                    Text(layer.midiProgram.map { $0.kind == .bypass ? "Select Effect" : $0.kind.title } ?? (layer.octaveEffect ? "Octave Up" : "Select Effect")).font(StageTheme.font(14, weight: .semibold)).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 5)
            }.buttonStyle(.plain).accessibilityLabel("Sound \(index+1) MIDI Effect")
        }.frame(height: 49).background(StageTheme.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: 6)).clipShape(RoundedRectangle(cornerRadius: 6))
    }
    private func effectSlot(_ slot: Int) -> some View {
        let effect = layer.effects[slot]
        return HStack(spacing: 0) {
            Button {
                if effect.kind == 0 { open(.effect(index, slot)) }
                else { var fx = effect; fx.enabled.toggle(); store.setEffect(index, slot, fx) }
            } label: { Image(systemName: "power").font(.system(size: 14)).frame(width: 36, height: 49).background(effect.kind > 0 && effect.enabled ? color.opacity(0.7) : Color.clear) }.buttonStyle(.plain).accessibilityLabel("Sound \(index+1) effect \(slot+1) bypass").accessibilityValue(effect.kind > 0 && effect.enabled ? "On":"Off")
            Button { open(.effect(index, slot)) } label: { VStack(alignment: .leading, spacing: 3) { Text("Audio 0\(slot+1)").font(.system(size: 9)).foregroundStyle(.secondary); Text(effect.title).font(StageTheme.font(14, weight: .semibold)) }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 5) }.buttonStyle(.plain).accessibilityLabel("Sound \(index+1) Audio \(slot+1) \(effect.title)")
        }.frame(height: 49).background(StageTheme.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: 6)).clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
enum PianoGeometry {
    static func white(_ n: Int) -> Bool { ![1,3,6,8,10].contains(n % 12) }
    static let notes = Array(21...108)
    static let whites = notes.filter(white)
    static func position(_ note: Int) -> CGFloat {
        let before = whites.filter { $0 < note }.count
        return CGFloat(before) + (white(note) ? 0.5 : 0)
    }
}
/// A held-position CC1 wheel. Unlike pitch bend, releasing the gesture never
/// returns its value to centre; incoming MIDI updates the same binding.
struct ModulationWheel: View {
    @Binding var value: Float
    @State private var dragOrigin: Float?
    private var position: Float { value.isFinite ? min(1, max(0, value)) : 0 }
    private func set(_ next: Float) {
        let step = next.isFinite ? (min(1, max(0, next)) * 127).rounded() / 127 : 0
        if value != step { value = step }
    }
    var body: some View {
        GeometryReader { geometry in
            let height = max(1, geometry.size.height)
            ZStack {
                RoundedRectangle(cornerRadius:7).fill(LinearGradient(colors:[Color(white:0.06),Color(white:0.19),Color(white:0.07)],startPoint:.leading,endPoint:.trailing))
                    .overlay{RoundedRectangle(cornerRadius:7).stroke(.black.opacity(0.8),lineWidth:2)}
                RoundedRectangle(cornerRadius:5).fill(Color.black).padding(.horizontal,10).padding(.vertical,4)
                Canvas {context,size in
                    let spacing:CGFloat=7,rotation=CGFloat(position)*42
                    for row in -8...Int(size.height/spacing+8) {
                        let y=CGFloat(row)*spacing+rotation.truncatingRemainder(dividingBy:spacing)
                        let lit=max(0,min(1,(CGFloat(position)*size.height-(size.height-y))/28))
                        let visibility=0.07+Double(lit)*0.68
                        let width:CGFloat=5
                        for x in [CGFloat(4),size.width-9] {
                            let rect=CGRect(x:x,y:y,width:width,height:3)
                            context.fill(Path(roundedRect:rect,cornerRadius:1),with:.linearGradient(Gradient(colors:[Color(white:0.22).opacity(visibility),Color(white:0.75).opacity(visibility),Color(white:0.32).opacity(visibility)]),startPoint:CGPoint(x:x,y:y),endPoint:CGPoint(x:x+width,y:y+3)))
                            context.fill(Path(CGRect(x:x,y:y+3,width:width,height:2)),with:.color(.black.opacity(0.8)))
                        }
                    }
                }.padding(.vertical,6)
                RoundedRectangle(cornerRadius:5).fill(LinearGradient(stops:[.init(color:Color(white:0.07),location:0),.init(color:Color(white:0.11+Double(position)*0.05),location:0.2),.init(color:Color(white:0.09),location:0.6),.init(color:.black,location:1)],startPoint:.top,endPoint:.bottom)).padding(.horizontal,12).padding(.vertical,7)
                RoundedRectangle(cornerRadius:7).stroke(.white.opacity(0.08),lineWidth:1)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    if dragOrigin == nil { dragOrigin = position }
                    guard drag.translation.height != 0 else { return }
                    set((dragOrigin ?? position) - Float(drag.translation.height / height))
                }.onEnded { _ in dragOrigin = nil })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Modulation wheel")
        .accessibilityValue("\(Int((position * 127).rounded())) of 127")
        .accessibilityHint("Adjusts MIDI controller 1. Position is held when released.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: set(position + 1 / 127)
            case .decrement: set(position - 1 / 127)
            @unknown default: break
            }
        }
    }
}
struct KeyboardWorkspace: View {
    @EnvironmentObject var store: PerformanceStore
    var body: some View {
        HStack(spacing: 20) {
            ModulationWheel(value:$store.modWheel).frame(width:48)
            VStack(spacing: 5) {
                if store.showRanges {
                    VStack(spacing: 2) {
                        ForEach(Array(store.displayedLayers.enumerated()).filter { $0.element.loaded }.reversed(), id: \.element.id) { index, layer in
                            GeometryReader { g in
                                let lo = max(21, layer.low), hi = min(108, layer.high)
                                if hi >= lo { RoundedRectangle(cornerRadius: 3).fill(StageTheme.colors[index].opacity(layer.muted ? 0.25 : 0.95)).frame(width: max(2, g.size.width * (PianoGeometry.position(hi) - PianoGeometry.position(lo) + 1) / 52)).offset(x: g.size.width * max(0, PianoGeometry.position(lo)-0.5) / 52) }
                            }.frame(height: 15)
                        }
                    }.frame(maxHeight: 85).accessibilityLabel("Sound layer ranges")
                }
                PianoKeyboard().disabled(!store.started).opacity(store.started ? 1 : 0.5)
            }
        }.padding(8).background(StageTheme.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
    }
}
struct PianoKeyboard: View {
    var body: some View {
        GeometryReader { g in
            let width = g.size.width / 52
            ZStack(alignment: .topLeading) {
                HStack(spacing: 1) { ForEach(PianoGeometry.whites, id: \.self) { PianoKey(note: $0, black: false) } }
                ForEach(PianoGeometry.notes.filter { !PianoGeometry.white($0) }, id: \.self) { note in
                    PianoKey(note: note, black: true).frame(width: width*0.62, height: g.size.height*0.63).offset(x: width * PianoGeometry.position(note) - width*0.31)
                }
            }
        }
    }
}
struct LayerRangeEditor: View {
    @EnvironmentObject var store: PerformanceStore
    @State private var draggingLayer: UUID?
    @State private var dragStartIndex: Int?
    private func noteName(_ note: Int) -> String { "\(StageTheme.notes[note % 12])\(note / 12 - 1)" }
    private func x(_ note: Int, _ width: CGFloat) -> CGFloat { min(width, max(0, (PianoGeometry.position(min(108, max(21, note))) - 0.5) / 52 * width)) }
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Keyboard Layers").font(StageTheme.font(13, weight: .semibold)).foregroundStyle(StageTheme.selected)
                Spacer()
                Button { store.setSustain(!store.sustain) } label: { Image(systemName: "pedal.accelerator") }.buttonStyle(StageButtonStyle(selected: store.sustain)).accessibilityLabel("Sustain pedal")
                Button("Done") { store.editRanges = false; store.save() }.buttonStyle(StageButtonStyle(selected: true))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(Array(store.patch.layers.enumerated().reversed()), id: \.element.id) { i, l in
                            HStack(spacing: 18) {
                                Image(systemName:"line.3.horizontal").font(.system(size:20)).foregroundStyle(StageTheme.selected).frame(width:42,height:44)
                                    .background(StageTheme.raised.opacity(0.4),in:RoundedRectangle(cornerRadius:4))
                                    .overlay(alignment:.trailing) { Rectangle().fill(StageTheme.colors[i]).frame(width:2) }
                                    .contentShape(Rectangle()).accessibilityLabel("Reorder sound \(i+1)")
                                    .gesture(DragGesture(minimumDistance:6,coordinateSpace:.global).onChanged { value in
                                        if draggingLayer == nil { draggingLayer=l.id; dragStartIndex=i }
                                        guard let moving=draggingLayer, let start=dragStartIndex, let current=store.patch.layers.firstIndex(where:{$0.id == moving}) else { return }
                                        let destination=max(0,min(14,start-Int((value.translation.height/52).rounded())))
                                        if current != destination { withAnimation(.easeInOut(duration:0.1)) { store.reorderLayer(current,destination) } }
                                    }.onEnded { _ in draggingLayer=nil; dragStartIndex=nil; store.save() })
                                    .contextMenu {
                                        Button("Move Up") { store.moveLayer(i,i+1) }.disabled(i == 14)
                                        Button("Move Down") { store.moveLayer(i,i-1) }.disabled(i == 0)
                                    }
                                    .accessibilityAction(named:Text("Move Up")) { store.moveLayer(i,i+1) }
                                    .accessibilityAction(named:Text("Move Down")) { store.moveLayer(i,i-1) }
                                GeometryReader { g in
                                    let lo = x(l.low, g.size.width), hi = l.high >= 108 ? g.size.width : x(l.high + 1, g.size.width)
                                    ZStack(alignment: .leading) {
                                        HStack(spacing: 0) { ForEach(0..<8) { _ in Rectangle().fill(.white.opacity(0.08)).frame(width: 1); Spacer(minLength: 0) } }
                                        if l.loaded {
                                            RoundedRectangle(cornerRadius: 3).fill(StageTheme.colors[i]).frame(width: max(20, hi-lo), height: 44).offset(x: lo)
                                            HStack(spacing: 8) {
                                                Text(noteName(l.low)).padding(8).background(StageTheme.base.opacity(0.85), in: RoundedRectangle(cornerRadius: 7))
                                                Text(l.name).lineLimit(1)
                                                Text(noteName(l.high)).padding(8).background(StageTheme.base.opacity(0.85), in: RoundedRectangle(cornerRadius: 7))
                                            }.font(StageTheme.font(12, weight: .semibold)).frame(width: max(20, hi-lo)).offset(x: lo)
                                            handle(i, low: true, width: g.size.width).offset(x: lo-11)
                                            handle(i, low: false, width: g.size.width).offset(x: hi-11)
                                        } else {
                                            RoundedRectangle(cornerRadius: 6).strokeBorder(.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4,4]))
                                            Text("Empty Sound Module \(i+1)").font(StageTheme.font(12)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                                        }
                                    }.frame(maxHeight: .infinity).coordinateSpace(name: "range-\(i)")
                                }
                            }.frame(height: 45).id(l.id)
                        }
                    }.padding(.horizontal, 8)
                }.onAppear { proxy.scrollTo(store.patch.layers[0].id, anchor: .bottom) }
            }
            HStack { Color.clear.frame(width: 60); PianoKeyboard().frame(height: 64) }.padding(.horizontal, 8)
        }.padding(8).background(StageTheme.panel.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
    }
    private func handle(_ i: Int, low: Bool, width: CGFloat) -> some View {
        Circle().fill(StageTheme.panel).overlay { Circle().stroke(StageTheme.selected.opacity(0.9), lineWidth: 3) }.frame(width: 22, height: 22)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("range-\(i)")).onChanged { value in
                let l = store.patch.layers[i]
                let position = min(51.5, max(0, value.location.x / max(1,width) * 52))
                let note = PianoGeometry.notes.min(by: { abs(PianoGeometry.position($0) - 0.5 - position) < abs(PianoGeometry.position($1) - 0.5 - position) }) ?? 21
                store.setRange(i, low: low ? min(note,l.high) : l.low, high: low ? l.high : max(note,l.low))
            }.onEnded { _ in store.save() })
            .accessibilityLabel("Sound \(i+1) \(low ? "lowest" : "highest") note")
            .accessibilityValue(noteName(low ? store.patch.layers[i].low : store.patch.layers[i].high))
            .accessibilityAdjustableAction { direction in
                let l=store.patch.layers[i], delta=direction == .increment ? 1 : -1
                store.setRange(i, low: low ? max(0,min(l.high,l.low+delta)) : l.low, high: low ? l.high : min(127,max(l.low,l.high+delta))); store.save()
            }
    }
}
struct PianoKey: View {
    @EnvironmentObject var store: PerformanceStore
    @GestureState private var touching = false
    let note: Int
    let black: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 3).fill(store.isNoteHeld(note) ? StageTheme.selected : (black ? Color(white: 0.07) : Color(white: 0.88)))
            .overlay(alignment: .bottom) { if !black && note % 12 == 0 { Text("C\(note/12-1)").font(.system(size: 8)).foregroundStyle(.black.opacity(0.4)).padding(.bottom, 3) } }
            .gesture(DragGesture(minimumDistance: 0).updating($touching) { _, state, _ in state = true }.onChanged { _ in store.noteOn(note) }.onEnded { _ in store.noteOff(note) })
            .onChange(of: touching) { if !$0 { store.noteOff(note) } }.onDisappear { store.noteOff(note) }
            .accessibilityLabel("\(StageTheme.notes[note%12])\(note/12-1)").accessibilityAddTraits(.isButton)
            .accessibilityAction { store.noteOn(note); DispatchQueue.main.asyncAfter(deadline: .now()+0.4) { store.noteOff(note) } }
    }
}
