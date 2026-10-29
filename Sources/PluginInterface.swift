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
    @State private var requestGeneration:UUID?
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
        #if os(macOS)
        .frame(minWidth: min(1000, max(650, size.width)), minHeight: min(700, max(420, size.height + 60)))
        #else
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        #endif
        .background(StageTheme.base)
        .onAppear { let token=UUID();requestGeneration=token;open(token:token) }
        .onChange(of:store.patch.id) { _ in dismiss() }
        .onChange(of:currentSound) { _ in dismiss() }
        .onDisappear { requestGeneration=nil;parameters.detach();controller=nil;generic=false }
    }
    private var currentSound:ExternalSound? {store.patch.layers.indices.contains(index) ? store.patch.layers[index].external:nil}
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
    private func open(token:UUID,attempt: Int = 0) {
        guard requestGeneration==token,controller == nil else { return }
        guard attempt < 120 else { status = "The instrument is still loading or unavailable."; return }
        guard let unit = store.audio.externalRack?.unit(channel: index) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { open(token:token,attempt: attempt + 1) }
            return
        }
        unit.auAudioUnit.requestViewController { view in
            DispatchQueue.main.async {
                guard requestGeneration==token,store.audio.externalRack?.unit(channel:index) === unit else{return}
                if let view {
                    let preferred = view.preferredContentSize
                    let actual = view.view.frame.size
                    size = CGSize(width: max(320, preferred.width > 0 ? preferred.width : actual.width),
                                  height: max(360, preferred.height > 0 ? preferred.height : actual.height))
                    controller = view
                } else {
                    parameters.attach(unit.auAudioUnit)
                    generic = !parameters.items.isEmpty || !parameters.presets.isEmpty
                    status = generic ? "" : "This instrument does not provide a custom interface or editable parameters."
                }
            }
        }
    }
}
