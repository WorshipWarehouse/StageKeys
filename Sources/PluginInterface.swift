import Foundation
import SwiftUI
import AVFoundation
import CoreAudioKit
#if os(macOS)
import AppKit
struct HostedPluginView: NSViewControllerRepresentable {
    let controller: NSViewController
    func makeNSViewController(context: Context) -> NSViewController { controller }
    func updateNSViewController(_ controller: NSViewController, context: Context) {}
}
#else
import UIKit
struct HostedPluginView: UIViewControllerRepresentable {
    let controller: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
#endif

/// Generic Audio Unit editor, used when a plug-in provides no custom view or its
/// view cannot be loaded. It is bound to the live AUAudioUnit's parameter tree so
/// the normal document-state capture keeps every change, and it follows external
/// parameter changes (host automation, the plug-in's own editor) through an
/// observer token instead of caching a stale snapshot.
final class PluginParameterModel: ObservableObject {
    struct Item: Identifiable {
        var id: AUParameterAddress
        var name: String
        var minimum: Double
        var maximum: Double
        var values: [String]
        var value: Double
        var display: String {
            let index = Int(value.rounded())
            if !values.isEmpty, values.indices.contains(index) { return values[index] }
            return String(format: abs(value) >= 1000 ? "%.0f" : "%.2f", value)
        }
    }
    @Published private(set) var items: [Item] = []
    @Published private(set) var presets: [String] = []
    @Published private(set) var currentPreset: Int?
    private var unit: AUAudioUnit?
    private var parameters: [AUParameterAddress: AUParameter] = [:]
    private var observer: AUParameterObserverToken?
    /// Bounded so a misbehaving plug-in cannot create an unbounded editor.
    private static let limit = 256

    func attach(_ unit: AUAudioUnit) {
        detach()
        self.unit = unit
        let tree = Array(unit.parameterTree?.allParameters.prefix(Self.limit) ?? [])
        for parameter in tree { parameters[parameter.address] = parameter }
        items = parameters.values.sorted { $0.address < $1.address }.map { parameter in
            Item(id: parameter.address, name: parameter.displayName,
                 minimum: Double(parameter.minValue), maximum: Double(parameter.maxValue),
                 values: parameter.valueStrings ?? [], value: Double(parameter.value))
        }
        let factory = unit.factoryPresets ?? []
        presets = Array(factory.prefix(Self.limit).map(\.name))
        currentPreset = unit.currentPreset.flatMap { current in factory.firstIndex(where: { $0.number == current.number }) }
        observer = unit.token(byAddingParameterObserver: { [weak self] address, value in
            DispatchQueue.main.async { self?.update(address, Double(value)) }
        })
    }
    func set(_ address: AUParameterAddress, _ value: Double) {
        guard let parameter = parameters[address], value.isFinite else { return }
        let bounded = min(Double(parameter.maxValue), max(Double(parameter.minValue), value))
        parameter.value = AUValue(bounded)
        update(address, bounded)
    }
    func selectPreset(_ index: Int) {
        guard let unit, let factory = unit.factoryPresets, factory.indices.contains(index) else { return }
        unit.currentPreset = factory[index]
        currentPreset = index
        for position in items.indices where parameters[items[position].id] != nil {
            items[position].value = Double(parameters[items[position].id]!.value)
        }
    }
    private func update(_ address: AUParameterAddress, _ value: Double) {
        guard let index = items.firstIndex(where: { $0.id == address }),
              abs(items[index].value - value) > 0.0000001 else { return }
        items[index].value = value
    }
    func detach() {
        if let unit, let observer { unit.removeParameterObserver(observer) }
        unit = nil; observer = nil; parameters = [:]
    }
    deinit { detach() }
}

struct PluginInterface: View {
    @EnvironmentObject var store: PerformanceStore
    let index: Int
    #if os(macOS)
    @State private var controller: NSViewController?
    #else
    @State private var controller: UIViewController?
    #endif
    @StateObject private var parameters = PluginParameterModel()
    @State private var status = "Loading instrument interface…"
    @State private var generic = false
    @State private var size = CGSize(width: 650, height: 420)
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Instrument Interface").font(StageTheme.font(16, weight: .bold))
                Spacer()
                Button("Done") { store.finishPluginInterface(index); dismiss() }.buttonStyle(StageButtonStyle(selected: true))
            }.padding(16)
            content
        }
        .frame(minWidth: min(1000, max(650, size.width)), minHeight: min(700, max(420, size.height + 60)))
        .background(StageTheme.base)
        .onAppear { open() }
        .onDisappear { parameters.detach() }
    }
    @ViewBuilder private var content: some View {
        if let controller {
            ScrollView([.horizontal, .vertical]) { HostedPluginView(controller: controller).frame(width: size.width, height: size.height) }
        } else if generic {
            genericEditor
        } else {
            Text(status).padding()
            Spacer()
        }
    }
    private var genericEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("Generic Controls").font(StageTheme.font(14, weight: .semibold))
                Spacer()
                if !parameters.presets.isEmpty {
                    Picker("", selection: Binding(get: { parameters.currentPreset ?? -1 },
                                                  set: { choice in if choice >= 0 { parameters.selectPreset(choice) } })) {
                        Text("Preset").tag(-1)
                        ForEach(Array(parameters.presets.enumerated()), id: \.offset) { offset, name in Text(name).tag(offset) }
                    }.labelsHidden().frame(width: 240)
                }
            }.padding(16)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(parameters.items) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(item.name).font(StageTheme.font(13))
                                Spacer()
                                Text(item.display).font(StageTheme.font(12)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            if !item.values.isEmpty {
                                Picker("", selection: Binding(get: { Int(item.value.rounded()) },
                                                              set: { choice in parameters.set(item.id, Double(choice)) })) {
                                    ForEach(Array(item.values.enumerated()), id: \.offset) { offset, name in Text(name).tag(offset) }
                                }.labelsHidden()
                            } else if item.maximum > item.minimum {
                                Slider(value: Binding(get: { item.value }, set: { parameters.set(item.id, $0) }),
                                       in: item.minimum...item.maximum)
                            }
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
    }
    /// The instrument may still be loading asynchronously when the sheet opens.
    /// Retry briefly instead of leaving the user on a permanent "loading" screen,
    /// then fall back to the generic editor when no custom view is provided.
    private func open(attempt: Int = 0) {
        guard controller == nil else { return }
        guard attempt < 40 else { status = "The instrument is still loading or unavailable."; return }
        guard let unit = store.audio.externalRack?.unit(channel: index) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { open(attempt: attempt + 1) }
            return
        }
        unit.requestViewController { view in
            DispatchQueue.main.async {
                if let view {
                    let preferred = view.preferredContentSize
                    let actual = view.view.frame.size
                    size = CGSize(width: max(320, preferred.width > 0 ? preferred.width : actual.width),
                                  height: max(360, preferred.height > 0 ? preferred.height : actual.height))
                    controller = view
                } else {
                    parameters.attach(unit)
                    generic = !parameters.items.isEmpty || !parameters.presets.isEmpty
                    status = generic ? "" : "This instrument does not provide a custom interface or editable parameters."
                }
            }
        }
    }
}
