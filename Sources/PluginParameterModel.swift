import Foundation
import Combine
import AVFoundation

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
    private var parameterTree: AUParameterTree?
    private var generation=UUID()
    /// Bounded so a misbehaving plug-in cannot create an unbounded editor.
    private static let limit = 256

    func attach(_ unit: AUAudioUnit) {
        detach()
        self.unit = unit
        parameterTree = unit.parameterTree
        let tokenGeneration=generation
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
        observer = parameterTree?.token(byAddingParameterObserver: { [weak self] address, value in
            guard let self else { return }
            // AUParameterTree observers are delivered on the audio/render context.
            // Publish the value on the main actor, but verify attachment identity
            // there so queued events from a replaced unit cannot update this model.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == tokenGeneration else { return }
                self.update(address, Double(value))
            }
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
        generation=UUID()
        if let parameterTree, let observer { parameterTree.removeParameterObserver(observer) }
        unit = nil; observer = nil; parameterTree=nil; parameters = [:]
    }
    deinit { detach() }
}

