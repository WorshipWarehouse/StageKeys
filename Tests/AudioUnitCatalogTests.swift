import Foundation

/// Catalog model tests for installed Audio Units. These need no third-party
/// plug-in, so discovery metadata, identity equality and ordering stay covered
/// on any machine; AudioUnitTests covers a real hosted instrument.
@main struct AudioUnitCatalogTests {
    static func main() throws {
        // A component saved before vendor/version metadata existed must still decode.
        let legacy = Data(#"{"type":1635084142,"subtype":1936747632,"manufacturer":1634758764,"name":"Legacy Synth"}"#.utf8)
        let decoded = try JSONDecoder().decode(ExternalAUIdentity.self, from: legacy)
        assert(decoded.name == "Legacy Synth")
        assert(decoded.vendor == nil && decoded.version == nil && decoded.validated == nil && decoded.unavailableReason == nil)
        assert(decoded.isAvailable)
        var macOnly=decoded;macOnly.manufacturer=123;macOnly.isV3=false
        assert(macOnly.platformUnavailableReason(isMobile:true)?.contains("AUv2")==true)
        assert(macOnly.platformUnavailableReason(isMobile:false)==nil)
        macOnly.isV3=true;assert(macOnly.platformUnavailableReason(isMobile:true)==nil)
        macOnly.isV3=false;macOnly.manufacturer=0x6170706c
        assert(macOnly.platformUnavailableReason(isMobile:true)==nil)

        // Catalog detail is presentation only. Identity equality must not change,
        // or a saved layer would reload its instrument whenever the picker supplies
        // more metadata than the setlist stored.
        var enriched = decoded
        enriched.vendor = "Example Audio"
        enriched.version = "1.4.2"
        enriched.isV3 = true
        enriched.hasCustomView = true
        enriched.validated = true
        assert(enriched == decoded, "Catalog metadata must not change plugin identity")
        assert(enriched.hashValue == decoded.hashValue)
        let plainSound = ExternalSound(kind: .audioUnit, name: decoded.name, component: decoded)
        let detailedSound = ExternalSound(kind: .audioUnit, name: enriched.name, component: enriched)
        assert(plainSound == detailedSound, "Enriched metadata must not trigger an instrument reload")

        let roundTrip = try JSONDecoder().decode(ExternalAUIdentity.self, from: JSONEncoder().encode(enriched))
        assert(roundTrip.vendor == "Example Audio" && roundTrip.version == "1.4.2")
        assert(roundTrip.isV3 == true && roundTrip.hasCustomView == true && roundTrip.validated == true)
        assert(roundTrip == enriched)
        assert(roundTrip.displayName == "Legacy Synth — Example Audio")

        // A different component is a different plug-in; a renamed one is not. Core
        // Audio identifies a component by type, subtype and manufacturer, so the
        // display name cannot decide whether its saved state still applies.
        var otherSubtype = enriched
        otherSubtype.subtype += 1
        assert(otherSubtype != enriched)
        var otherManufacturer = enriched
        otherManufacturer.manufacturer += 1
        assert(otherManufacturer != enriched)
        var renamed = enriched
        renamed.name = "Legacy Synth 2"
        assert(renamed == enriched, "A renamed component must keep its plug-in identity")
        assert(renamed.hashValue == enriched.hashValue)

        // Vendor first, then display name. Unavailable components stay listed so
        // the browser can explain why they cannot be hosted.
        var alpha = decoded
        alpha.name = "Alpha"; alpha.vendor = "Zeta Audio"; alpha.subtype += 1
        var beta = decoded
        beta.name = "Beta"; beta.vendor = "Zeta Audio"; beta.subtype += 3
        var first = decoded
        first.name = "Zulu"; first.vendor = nil; first.subtype += 4
        var unavailable = decoded
        unavailable.name = "Alpha"; unavailable.vendor = "Zeta Audio"; unavailable.subtype += 2
        unavailable.unavailableReason = "This Audio Unit has no build for this Mac's processor."
        let sorted = ExternalAUCatalog.sorted([beta, unavailable, first, alpha])
        assert(sorted.map(\.name) == ["Zulu", "Alpha", "Alpha", "Beta"], "Unexpected order: \(sorted.map(\.displayName))")
        assert(sorted.filter { !$0.isAvailable }.count == 1)
        assert(sorted.first!.vendor == nil, "Vendor-less components sort before named vendors")

        // Search covers both name and vendor, as the library search uses it.
        assert(ExternalAUCatalog.matches(alpha, query: "alpha"))
        assert(ExternalAUCatalog.matches(alpha, query: "zeta"))
        assert(ExternalAUCatalog.matches(alpha, query: "  ALPHA   zeta  "))
        assert(ExternalAUCatalog.matches(alpha, query: ""))
        assert(!ExternalAUCatalog.matches(alpha, query: "roland"))
        assert(!ExternalAUCatalog.matches(alpha, query: "alpha roland"))

        // Snapshot sound state must carry Audio Unit state and stay readable from
        // older setlists that never stored it.
        let layer = Layer(name: "AU", instrument: -1, gain: 0.8)
        var withState = layer
        withState.pluginState = Data([1, 2, 3])
        assert(SnapshotSoundState(withState).pluginState == Data([1, 2, 3]))
        assert(SnapshotSoundState(layer).pluginState == nil)
        let legacySnapshot = Data(#"{"effects":[{"amount":0.5,"enabled":true,"kind":0},{"amount":0.5,"enabled":true,"kind":0},{"amount":0.5,"enabled":true,"kind":0}],"midiEffectEnabled":true,"pan":0}"#.utf8)
        let restored = try JSONDecoder().decode(SnapshotSoundState.self, from: legacySnapshot)
        assert(restored.pluginState == nil && restored.effects.count == 3)
        // A saved plug-in state belongs to the instrument it was captured from, so a
        // layer that now holds a different Audio Unit must not receive it.
        var sourceLayer = Layer(name: "Source", instrument: -1, gain: 0.8)
        sourceLayer.external = ExternalSound(kind: .audioUnit, name: "Source AU")
        var targetLayer = sourceLayer
        targetLayer.external = ExternalSound(kind: .audioUnit, name: "Other AU")
        assert(SnapshotSoundState(sourceLayer).belongs(to: sourceLayer.external))
        assert(!SnapshotSoundState(sourceLayer).belongs(to: targetLayer.external),
               "A snapshot state must not travel to a different Audio Unit")
        var legacyState = SnapshotSoundState(sourceLayer); legacyState.external = nil
        assert(legacyState.belongs(to: targetLayer.external),
               "A state saved before identity existed keeps the legacy restore path")
        let sample=TestFixtures.layer()
        let capturedSample=SnapshotSoundState(sample)
        assert(capturedSample.external?.nativeSampler==nil && capturedSample.external?.fileName==nil,"Snapshot identity must not duplicate sampler sample maps or private conversion metadata")
        assert(!capturedSample.belongs(to:targetLayer.external),"A captured non-AU must not inherit the legacy unknown-owner AU restore path")
        let portableIdentity=SnapshotSoundState(sourceLayer).external!
        assert(portableIdentity.nativeSampler==nil && portableIdentity.fileName==nil)
        print("PASS: Audio Unit legacy decode, identity stability, metadata round-trip, ordering, availability, vendor search and snapshot state compatibility")
    }
}
