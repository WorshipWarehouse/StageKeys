import SwiftUI

/// Eight columns match the channel editor's HP/shelf/four bells/shelf/LP
/// organization. This is controls-only: callers own transactional persistence.
struct ChannelEqualizerControls: View {
    @Binding var bands: [EQBand]
    @Binding var enabled: Bool
    var showsEnableToggle = false
    private let names = ["High Pass", "Low Shelf", "Peak 1", "Peak 2", "Peak 3", "Peak 4", "High Shelf", "Low Pass"]
    private let colors: [Color] = [.pink, .purple, .indigo, .cyan, .green, .yellow, .orange, .red]
    private func value(_ index: Int, _ key: WritableKeyPath<EQBand, Float>) -> Binding<Float> {
        Binding(get: { bands.indices.contains(index) ? bands[index][keyPath: key] : EQBand.defaults[index][keyPath: key] }, set: { newValue in
            guard newValue.isFinite else { return }
            if bands.count != 8 { bands = EQBand.defaults }
            let range: ClosedRange<Float> = key == \EQBand.frequency ? 20...20000 : key == \EQBand.gain ? -24...24 : EQBandwidth.qRange
            bands[index][keyPath: key] = min(range.upperBound, max(range.lowerBound, newValue))
        })
    }
    private func bandwidth(_ index: Int) -> Binding<Float> {
        let q = value(index, \EQBand.q)
        return Binding(get: { EQBandwidth.octaves(fromQ: q.wrappedValue) }, set: { q.wrappedValue = EQBandwidth.q(fromOctaves: $0) })
    }
    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 12) {
            if showsEnableToggle { Toggle("Equalizer ON", isOn: $enabled).toggleStyle(.switch).font(StageTheme.font(13, weight: .semibold)) }
            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 5) {
                    ForEach(0..<8) { index in
                        VStack(spacing: 6) {
                            EQFilterIcon(band: index).stroke(colors[index], style: StrokeStyle(lineWidth: 2, lineCap: .round)).frame(width: 37, height: 20).padding(.vertical, 4).accessibilityLabel(names[index])
                            EQCompactKnob(title: "Frequency", accessibilityTitle: "\(names[index]) frequency", unit: "Hz", value: value(index, \EQBand.frequency), range: 20...20000, logarithmic: true, color: colors[index])
                            if (1...6).contains(index) {
                                EQCompactKnob(title: "Gain", accessibilityTitle: "\(names[index]) gain", unit: "dB", value: value(index, \EQBand.gain), range: -24...24, color: colors[index])
                            } else { Color.clear.frame(height: 96) }
                            if (2...5).contains(index) {
                                EQCompactKnob(title: "Bandwidth", accessibilityTitle: "\(names[index]) bandwidth", unit: "oct", value: bandwidth(index), range: EQBandwidth.octaveRange, color: colors[index])
                            } else { Color.clear.frame(height: 96) }
                        }.padding(.vertical, 8).frame(minWidth:86,maxWidth:.infinity).background(StageTheme.panel.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                    }
                }.frame(minWidth:max(723,geometry.size.width)).padding(.bottom, 4)
            }.disabled(!enabled).opacity(enabled ? 1 : 0.48)
        }
        }.frame(height:showsEnableToggle ? 408 : 372)
    }
}
private struct EQCompactKnob: View {
    let title: String
    let accessibilityTitle: String
    let unit: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    var logarithmic = false
    let color: Color
    @State private var origin: Float?
    @State private var draft = ""
    @FocusState private var editing: Bool
    private func displayValue() -> String { String(format: unit == "Hz" ? "%.0f" : "%.2f", value) }
    private func parsedValue() -> Float? {
        let formatter = NumberFormatter(); formatter.numberStyle = .decimal
        let result = Float(draft) ?? formatter.number(from: draft)?.floatValue
        return result.flatMap { $0.isFinite ? $0 : nil }
    }
    private func commitValue() {
        if let parsed = parsedValue() { value = min(range.upperBound, max(range.lowerBound, parsed)) }
        draft = displayValue()
    }
    private var position: Float {
        let raw = value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : range.lowerBound
        return logarithmic ? log(raw / range.lowerBound) / log(range.upperBound / range.lowerBound) : (raw-range.lowerBound)/(range.upperBound-range.lowerBound)
    }
    private func set(_ unitValue: Float) {
        let p = min(1, max(0, unitValue))
        value = logarithmic ? range.lowerBound * pow(range.upperBound / range.lowerBound, p) : range.lowerBound + p * (range.upperBound-range.lowerBound)
    }
    var body: some View {
        VStack(spacing: 5) {
            Text(title).font(StageTheme.font(11)).foregroundStyle(.secondary)
            ZStack {
                Circle().trim(from: 0.13, to: 0.87).stroke(color.opacity(0.25), lineWidth: 2).rotationEffect(.degrees(90))
                Circle().trim(from: 0.13, to: 0.13 + 0.74 * CGFloat(position)).stroke(color, lineWidth: 2).rotationEffect(.degrees(90))
                Circle().fill(LinearGradient(colors: [StageTheme.raised, StageTheme.base], startPoint: .topLeading, endPoint: .bottomTrailing)).padding(5).shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                Capsule().fill(color).frame(width: 2, height: 10).offset(y: -15).rotationEffect(.degrees(-133 + Double(position) * 266))
            }.frame(width: 54, height: 54).contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    if origin == nil { editing = false; origin = position }; set((origin ?? position) - Float(drag.translation.height) / 160)
                }.onEnded { _ in origin = nil })
                .accessibilityElement().accessibilityLabel(accessibilityTitle).accessibilityValue("\(value) \(unit)")
                .accessibilityAdjustableAction { set(position + ($0 == .increment ? 0.02 : -0.02)) }
            HStack(spacing: 2) {
                TextField(title, text: $draft)
                    .focused($editing)
                    .onAppear { draft = displayValue() }
                    .onChange(of: editing) { active in if active { draft = displayValue() } else { commitValue() } }
                    .onChange(of: draft) { _ in
                        // Keep partial input ("-", "3.", "1860") stable while typing.
                        if editing, let parsed = parsedValue(), range.contains(parsed) { value = parsed }
                    }
                    .onChange(of: value) { _ in if !editing { draft = displayValue() } }
                    .onSubmit { commitValue(); editing = false }
                    .textFieldStyle(.plain).multilineTextAlignment(.center).font(StageTheme.font(11, weight: .semibold)).frame(width: 51).accessibilityLabel("\(accessibilityTitle) value")
                Text(unit).font(StageTheme.font(8)).foregroundStyle(.secondary)
            }.padding(.vertical, 4).background(StageTheme.base.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
        }.frame(height: 96)
    }
}
private struct EQFilterIcon: Shape {
    let band: Int
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.midY, high = rect.minY + 3, low = rect.maxY - 3
        path.move(to: CGPoint(x: rect.minX, y: band == 0 ? low : (band == 1 || band == 7) ? high : mid))
        if band == 0 {
            path.addCurve(to: CGPoint(x: rect.maxX, y: high), control1: CGPoint(x: rect.midX, y: low), control2: CGPoint(x: rect.midX, y: high))
        } else if band == 7 {
            path.addCurve(to: CGPoint(x: rect.maxX, y: low), control1: CGPoint(x: rect.midX, y: high), control2: CGPoint(x: rect.midX, y: low))
        } else if band == 1 || band == 6 {
            let end = band == 1 ? mid : high
            path.addCurve(to: CGPoint(x: rect.maxX, y: end), control1: CGPoint(x: rect.midX, y: band == 1 ? high : mid), control2: CGPoint(x: rect.midX, y: end))
        } else {
            path.addCurve(to: CGPoint(x: rect.midX, y: high), control1: CGPoint(x: rect.width * 0.3, y: mid), control2: CGPoint(x: rect.width * 0.3, y: high))
            path.addCurve(to: CGPoint(x: rect.maxX, y: mid), control1: CGPoint(x: rect.width * 0.7, y: high), control2: CGPoint(x: rect.width * 0.7, y: mid))
        }
        return path
    }
}
