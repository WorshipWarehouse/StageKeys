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

        // A different component or display name is a different plug-in.
        var otherSubtype = enriched
        otherSubtype.subtype += 1
        assert(otherSubtype != enriched)
        var otherName = enriched
        otherName.name = "Legacy Synth 2"
        assert(otherName != enriched)

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
        print("PASS: Audio Unit legacy decode, identity stability, metadata round-trip, ordering, availability, vendor search and snapshot state compatibility")
    }
}
