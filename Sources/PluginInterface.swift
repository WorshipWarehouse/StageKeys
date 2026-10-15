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
    @State private var status = "Loading instrument interface…"
    @State private var size = CGSize(width: 650, height: 420)
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Instrument Interface").font(StageTheme.font(16, weight: .bold)); Spacer(); Button("Done") { store.save(); dismiss() }.buttonStyle(StageButtonStyle(selected: true)) }.padding(16)
            if let controller {
                ScrollView([.horizontal, .vertical]) { HostedPluginView(controller: controller).frame(width: size.width, height: size.height) }
            } else { Text(status).padding(); Spacer() }
        }.frame(minWidth: min(1000,max(650,size.width)), minHeight: min(700,max(420,size.height+60))).background(StageTheme.base)
        .onAppear {
            guard let unit = store.audio.externalRack?.unit(channel: index) else { status = "The instrument is still loading or unavailable."; return }
            unit.auAudioUnit.requestViewController { view in
                DispatchQueue.main.async {
                    if let view {
                        let preferred = view.preferredContentSize
                        let actual = view.view.frame.size
                        size = CGSize(width: max(320,preferred.width > 0 ? preferred.width : actual.width), height: max(360,preferred.height > 0 ? preferred.height : actual.height))
                    }
                    controller = view
                    if view == nil { status = "This instrument does not provide a custom interface." }
                }
            }
        }.onDisappear { store.save() }
    }
}
