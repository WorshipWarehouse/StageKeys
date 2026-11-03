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
    /// No custom view and no editable parameters: the plug-in offers nothing to edit.
    @State private var generic = false
    @State private var requestGeneration:UUID?
    /// The size the plug-in itself declares, sanitised to the editor floor.
    @State private var declared = PluginEditorModel.minimumSize
    /// Manual expansion for a view that is larger than the collapsed sheet.
    @State private var expanded = false
    /// Why the interface is not showing, once that is known rather than assumed.
    @State private var issue: PluginEditorModel.Diagnosis?
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Instrument Interface").font(StageTheme.font(16, weight: .bold))
                Spacer()
                if canExpand {
                    Button { expanded.toggle() } label: {
                        Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }.buttonStyle(StageButtonStyle(selected: expanded))
                        .accessibilityLabel(expanded ? "Collapse instrument interface" : "Expand instrument interface")
                        .accessibilityHint(expanded ? "Returns the plug-in view to its reported size inside the sheet."
                                                    : "Uses the rest of the screen so more of an oversized plug-in view is visible.")
                }
                Button("Done") { store.finishPluginInterface(index); dismiss() }.buttonStyle(StageButtonStyle(selected: true))
            }.padding(16)
            content
        }
        #if os(macOS)
        // The sheet follows the plug-in view; expanding raises the collapsed cap so
        // more of an oversized editor is visible, and collapsing returns it.
        .frame(minWidth: sheetSize.width, minHeight: sheetSize.height)
        #else
        .frame(maxWidth:.infinity,maxHeight:.infinity)
        #endif
        .background(StageTheme.base)
        .onAppear { let token=UUID();requestGeneration=token;checkAvailability();open(token:token) }
        .onChange(of:store.patch.id) { _ in dismiss() }
        .onChange(of:currentSound) { _ in dismiss() }
        .onDisappear { requestGeneration=nil;parameters.detach();controller=nil;generic=false;issue=nil }
    }
    private var currentSound:ExternalSound? {store.patch.layers.indices.contains(index) ? store.patch.layers[index].external:nil}
    /// The area the plug-in view gets: its declared size, held at the collapsed
    /// maximum unless expanded, and never larger than the screen allows.
    private var displayed: CGSize { PluginEditorModel.displaySize(declared: declared, available: availableSize, compactMaximum: compactMaximum, expanded: expanded) }
    private var canExpand: Bool { controller != nil && PluginEditorModel.canExpand(declared: declared, available: availableSize, compactMaximum: compactMaximum) }
    /// Screen space a sheet can occupy, leaving room for the title bar and margins.
    /// iOS reports none, because its sheet already sizes itself to the screen.
    private var availableSize: CGSize {
        #if os(macOS)
        guard let frame = NSScreen.main?.visibleFrame else { return .zero }
        return CGSize(width: max(0, frame.width - 48), height: max(0, frame.height - 96))
        #else
        return .zero
        #endif
    }
    private var compactMaximum: CGSize {
        #if os(macOS)
        return PluginEditorModel.compactMaximum
        #else
        return .zero
        #endif
    }
    @ViewBuilder private var content: some View {
        if let controller {
            ScrollView([.horizontal, .vertical]) {
                HostedPluginView(controller: controller)
                    .frame(width: declared.width, height: declared.height)
                    .accessibilityLabel("\(plugInName) plug-in interface")
            }.frame(width: displayed.width, height: displayed.height).accessibilityHint(scrollHint)
        } else if generic {
            genericEditor
        } else if let issue {
            diagnosis(issue)
        } else {
            Text(status).padding()
            Spacer()
        }
    }
    /// A problem is stated with its own remedy instead of leaving the sheet on an
    /// open-ended spinner. Retry is offered only where it can succeed.
    private func diagnosis(_ issue: PluginEditorModel.Diagnosis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(issue.message).font(StageTheme.font(14, weight: .semibold))
            Text(issue.detail).font(StageTheme.font(13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            switch issue.recovery {
            case .retry:
                Button("Retry") { retry() }.buttonStyle(StageButtonStyle()).accessibilityHint("Looks for the instrument interface again.")
            case .allowBlocked(let componentID):
                Button("Allow and Retry") { allowBlocked(componentID) }.buttonStyle(StageButtonStyle(selected: true))
                    .accessibilityHint("Allows this blocked instrument to load again, then reopens its interface.")
            case .none:
                EmptyView()
            }
            Spacer()
        }.padding(16).frame(maxWidth: 520, alignment: .leading)
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
                        .accessibilityLabel("Factory preset")
                        .accessibilityValue(parameters.currentPreset.flatMap { parameters.presets.indices.contains($0) ? parameters.presets[$0] : nil } ?? "No preset selected")
                }
            }.padding(16)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(parameters.items) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                // The control below carries the name and value for assistive
                                // technologies; the visible copies must not repeat them.
                                Text(item.name).font(StageTheme.font(13)).accessibilityHidden(true)
                                Spacer()
                                Text(item.display).font(StageTheme.font(12)).monospacedDigit().foregroundStyle(.secondary).accessibilityHidden(true)
                            }
                            if !item.values.isEmpty {
                                Picker("", selection: Binding(get: { Int(item.value.rounded()) },
                                                              set: { choice in parameters.set(item.id, Double(choice)) })) {
                                    ForEach(Array(item.values.enumerated()), id: \.offset) { offset, name in Text(name).tag(offset) }
                                }.labelsHidden()
                                    .accessibilityLabel(item.name)
                                    .accessibilityValue(item.display)
                            } else if item.maximum > item.minimum {
                                Slider(value: Binding(get: { item.value }, set: { parameters.set(item.id, $0) }),
                                       in: item.minimum...item.maximum)
                                    .accessibilityLabel(item.name)
                                    .accessibilityValue(item.display)
                            }
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }.accessibilityElement(children: .contain).accessibilityLabel("Generic instrument controls")
        }
    }
    /// Floor for the sheet itself: the plug-in view plus this file's header, or the
    /// generic editor's own minimum when no custom view is hosted.
    private var sheetSize: CGSize {
        guard controller != nil else { return CGSize(width: 650, height: 420) }
        return CGSize(width: max(650, displayed.width), height: max(420, displayed.height + 60))
    }
    /// Only an editor that does not fit needs the scrolling announcement.
    private var scrollHint: String {
        PluginEditorModel.needsScrolling(declared: declared, displayed: displayed)
            ? "The plug-in view is larger than the sheet. Scroll to reach the rest of it."
            : ""
    }
    private var plugInName: String { currentSound?.name ?? "Instrument" }
    /// Report a plug-in that cannot be hosted here at all before waiting for it:
    /// a block from the recovery journal or a catalog reason such as a missing
    /// processor slice or an AUv2 plug-in opened on an iOS device.
    private func checkAvailability() {
        guard let component = currentSound?.component else { return }
        #if os(iOS)
        let mobile = true
        #else
        let mobile = false
        #endif
        let reason = ExternalAUCatalog.unavailableReason(for: component, installed: ExternalInstrumentRack.instruments(), isMobile: mobile)
        issue = PluginEditorModel.diagnosis(blockedID: blockedComponentID(), unavailableReason: reason, attempts: 0)
    }
    /// Read the recovery journal on each poll: a plug-in that just failed or hit
    /// its instantiation timeout is reported at that moment instead of after the
    /// editor's own deadline.
    private func blockedComponentID() -> String? {
        guard let id = currentSound?.component?.id else { return nil }
        return ((try? ExternalInstrumentRack.blockedComponentIDs()) ?? []).contains(id) ? id : nil
    }
    /// The instrument may still be loading asynchronously when the sheet opens.
    /// Poll briefly instead of leaving the user on a permanent "loading" screen,
    /// then report a block, a known unavailability, a timeout or the generic
    /// editor — in that order, never a guess.
    private func open(token:UUID,attempt: Int = 0) {
        guard requestGeneration==token,controller == nil,issue == nil else { return }
        if let blockedID = blockedComponentID() {
            issue = PluginEditorModel.diagnosis(blockedID: blockedID, unavailableReason: nil, attempts: attempt)
            return
        }
        guard attempt < PluginEditorModel.attemptLimit else {
            issue = PluginEditorModel.diagnosis(blockedID: nil, unavailableReason: nil, attempts: attempt)
            return
        }
        guard let unit = store.audio.loadedUnit(channel: index, sound: currentSound) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + PluginEditorModel.waitInterval) { open(token:token,attempt: attempt + 1) }
            return
        }
        watchViewRequest(token: token, unit: unit, attempt: attempt)
        unit.auAudioUnit.requestViewController { view in
            DispatchQueue.main.async {
                guard requestGeneration==token,issue == nil,store.audio.loadedUnit(channel:index,sound:currentSound) === unit else{return}
                if let view {
                    let preferred = view.preferredContentSize
                    let actual = view.view.frame.size
                    declared = PluginEditorModel.declaredSize(width: preferred.width > 0 ? preferred.width : actual.width,
                                                              height: preferred.height > 0 ? preferred.height : actual.height)
                    controller = view
                } else {
                    parameters.attach(unit.auAudioUnit)
                    generic = !parameters.items.isEmpty || !parameters.presets.isEmpty
                    if !generic { issue = .noInterface }
                }
            }
        }
    }
    // requestViewController is a second asynchronous boundary: a ready unit
    // can still never return a UI. Bound that wait and reject late replies.
    private func watchViewRequest(token: UUID, unit: AVAudioUnit, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + PluginEditorModel.waitInterval) {
            guard requestGeneration == token, issue == nil, controller == nil, !generic,
                  store.audio.loadedUnit(channel: index, sound: currentSound) === unit else { return }
            let next = attempt + 1
            if next >= PluginEditorModel.attemptLimit {
                issue = .timedOut(seconds: Int(PluginEditorModel.waitDeadline))
            } else { watchViewRequest(token: token, unit: unit, attempt: next) }
        }
    }
    /// Retry submits a missing instrument load, rather than polling a failed one.
    private func retry() {
        requestGeneration = UUID() // Invalidate old UI requests even when retry is refused.
        guard store.retryPluginInterfaceLoad(index) else {
            status = store.message ?? "Start audio before retrying this instrument."
            issue = nil
            return
        }
        issue = nil; status = "Loading instrument interface…"
        let token = UUID(); requestGeneration = token
        checkAvailability()
        open(token: token)
    }
    /// Lifting one block is an explicit user action; it never clears the others.
    private func allowBlocked(_ componentID: String) {
        guard store.allowBlockedAudioUnit(componentID) else { return }
        retry()
    }
}
