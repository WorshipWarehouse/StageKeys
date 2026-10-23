import SwiftUI

struct MIDIControlLearnView: View {
    @EnvironmentObject private var store: PerformanceStore
    @Environment(\.dismiss) private var dismiss
    private let general: [MIDIControlTarget] = [.master, .modulation, .sustain, .previousPatch, .nextPatch, .panic]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("MIDI Learn").font(StageTheme.font(20, weight: .bold))
                    Text("\(store.deviceCount) MIDI input\(store.deviceCount == 1 ? "" : "s") connected").font(StageTheme.font(12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Reset All") { store.resetMIDILearn() }.buttonStyle(StageButtonStyle()).help("Remove every learned controller assignment; fixed modulation, sustain, panic and program-change routes remain")
                Button { store.learningTarget = nil; dismiss() } label: { Image(systemName: "xmark").font(.system(size: 18)).frame(width: 30,height: 30) }.buttonStyle(.plain).accessibilityLabel("Close MIDI Learn")
            }.padding(20).background(StageTheme.base)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.learningTarget.map { "Listening for \($0.title)…" } ?? "Select a control, then move a hardware knob, fader or button.").font(StageTheme.font(14, weight: .semibold))
                        Text("CC 1 (modulation), 64 (sustain), 120 and 123 (panic) keep their fixed routes. Use another CC to learn an assignment.").font(StageTheme.font(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if store.learningTarget != nil {
                            Button("Cancel Listening") { store.learningTarget = nil }.buttonStyle(StageButtonStyle())
                        }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(StageTheme.raised.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    section("GENERAL CONTROLS", targets: general)
                    section("SOUND LEVELS", targets: (0..<min(15, store.patch.layers.count)).map { .soundLevel($0) })
                    let snapshots = Array(store.patch.snapshots.indices.prefix(16)).map { MIDIControlTarget.snapshot($0) }
                    if !snapshots.isEmpty { section("PATCH SNAPSHOTS", targets: snapshots) }
                }.padding(20)
            }
        }.background(StageTheme.panel).frame(minWidth: 340, idealWidth: 760, minHeight: 500, idealHeight: 650)
            #if os(macOS)
            .frame(width: 760, height: 650)
            #endif
            .onDisappear { store.learningTarget = nil }
    }
    private func section(_ title: String, targets: [MIDIControlTarget]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(StageTheme.font(11, weight: .semibold)).foregroundStyle(StageTheme.selected)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 8)], spacing: 8) {
                ForEach(targets) { target in targetCard(target) }
            }
        }
    }
    private func label(_ target: MIDIControlTarget) -> String {
        switch target {
        case .soundLevel(let index):
            return store.patch.layers.indices.contains(index) && store.patch.layers[index].loaded ? store.patch.layers[index].name : target.title
        case .snapshot(let index):
            return store.patch.snapshots.indices.contains(index) ? store.patch.snapshots[index].name : target.title
        default: return target.title
        }
    }
    private func targetCard(_ target: MIDIControlTarget) -> some View {
        let listening = store.learningTarget == target
        let cc = store.assignedCC(target)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label(target)).font(StageTheme.font(13, weight: .semibold)).lineLimit(2)
                    if label(target) != target.title { Text(target.title).font(StageTheme.font(10)).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 4)
                Text(listening ? "Listening" : cc.map { "CC \($0)" } ?? "Unassigned").font(StageTheme.font(10, weight: .semibold)).foregroundStyle(listening ? StageTheme.selected : .secondary)
            }.frame(minHeight: 32, alignment: .topLeading)
            HStack {
                Button(listening ? "Cancel" : "Learn") { if listening { store.learningTarget = nil } else { store.beginMIDILearn(target) } }.buttonStyle(StageButtonStyle(selected: listening)).accessibilityLabel("\(listening ? "Cancel learning" : "Learn") \(target.title)")
                Spacer()
                if cc != nil {
                    Button { store.clearMIDILearn(target) } label: { Image(systemName: "xmark.circle").font(.system(size: 18)) }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear \(target.title) MIDI assignment")
                }
            }
        }.padding(12).background(StageTheme.base.opacity(0.45), in: RoundedRectangle(cornerRadius: 7)).overlay { RoundedRectangle(cornerRadius: 7).stroke(listening ? StageTheme.selected : .white.opacity(0.06), lineWidth: 1) }
    }
}
