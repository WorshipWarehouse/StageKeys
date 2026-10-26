import AVFoundation
import AudioToolbox
import Foundation

/// Diagnostic for a saved MainStage Audio Unit state. Without `--apply` it only reads
/// the channel strip and reports the installed component that matches. With `--apply`
/// it instantiates that component and prints which parameters the saved state changes.
/// The source patch is never modified and no plug-in is loaded without `--apply`.
@main struct ApplyMainStageAUState {
    static func main()throws {
        var arguments=Array(CommandLine.arguments.dropFirst())
        let apply=arguments.contains("--apply")
        arguments.removeAll{$0=="--apply"}
        guard arguments.count==1 else {
            print("""
            Usage: ApplyMainStageAUState <patch-or-cst> [--apply]
              Reads the Audio Unit class info a MainStage channel strip saved.
              --apply instantiates the matching installed component and reports the
              parameters the saved state changes. It does not save or export anything.
            """)
            return
        }
        let source=URL(fileURLWithPath:arguments[0])
        var strips:[URL]=[]
        if source.pathExtension.lowercased()=="cst" { strips=[source] }
        else {
            let report=try MainStagePatch.inspect(source)
            strips=report.channels.map{source.appendingPathComponent($0.file)}
        }
        let installed=ExternalInstrumentRack.instruments()
        var found=0
        for strip in strips {
            guard let data=try? Data(contentsOf:strip),
                  let devices=try? MainStagePatch.devices(data) else { continue }
            for device in devices where device.format=="PSDD" {
                found+=1
                print("\n\(strip.lastPathComponent) :: \(device.name)")
                if let saved=device.pluginState {
                    print("  saved: \(saved.identity ?? "unknown") version \(saved.version.map(String.init) ?? "unknown") | \(saved.summary)")
                }
                guard let saved=MainStageAudioUnit.state(for:device,in:data) else {
                    print("  no readable class info in the record");continue
                }
                guard let match=MainStageAudioUnit.match(device,state:saved,installed:installed) else {
                    print("  not installed: no component matches \(device.name) for this type/manufacturer");continue
                }
                print("  installed: \(match.identity.displayName) \(match.identity.version ?? "") | exact subtype: \(match.exactSubtype)")
                guard apply else {
                    print("  state ready (\(match.state.count) bytes, \(match.savedIdentity)); pass --apply to test it")
                    continue
                }
                guard let values=try PropertyListSerialization.propertyList(from:match.state,options:[],format:nil) as? [String:Any] else {
                    print("  class info could not be read as a property list");continue
                }
                let description=AudioComponentDescription(componentType:match.identity.type,
                                                          componentSubType:match.identity.subtype,
                                                          componentManufacturer:match.identity.manufacturer,
                                                          componentFlags:0,componentFlagsMask:0)
                let semaphore=DispatchSemaphore(value:0)
                var loaded:AVAudioUnit?
                AVAudioUnit.instantiate(with:description,options:[]){unit,error in
                    if let error {print("  instantiate error: \(error.localizedDescription)")}
                    loaded=unit;semaphore.signal()
                }
                _ = semaphore.wait(timeout:.now()+20)
                guard let audioUnit=loaded?.auAudioUnit else {
                    print("  the installed component did not instantiate");continue
                }
                try? audioUnit.allocateRenderResources()
                Thread.sleep(forTimeInterval:0.3)
                let parameters=audioUnit.parameterTree?.allParameters ?? []
                let before=Dictionary(uniqueKeysWithValues:parameters.map{($0.identifier,$0.value)})
                audioUnit.fullStateForDocument=values
                // The class-info setter settles asynchronously; give it time before reading back.
                Thread.sleep(forTimeInterval:0.5)
                let changed=parameters.filter{before[$0.identifier] != $0.value}
                print("  applied: \(changed.count) of \(before.count) parameters changed")
                for parameter in changed.prefix(12) {
                    print("    \(parameter.displayName): \(before[parameter.identifier] ?? -1) -> \(parameter.value)")
                }
                if !match.exactSubtype {
                    print("  warning: the save targets subtype \(match.savedIdentity); this component has a different subtype, so the parameter mapping between versions is unverified")
                }
            }
        }
        if found==0 {print("No saved Audio Unit state was found in \(source.lastPathComponent).")}
    }
}
