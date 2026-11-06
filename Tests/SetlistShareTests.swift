import Foundation

@main struct SetlistShareTests {
    static func main() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["STAGEKEYS_DATA_DIR"]!)
        let source = try generatedSetlist()
        let package = try SetlistShare.make(source)
        let data = try SetlistShare.encode(package)
        let json = String(decoding: data, as: UTF8.self)

        assert(package.format == SetlistSharePackage.formatIdentifier)
        assert(package.version == 1)
        assert(package.checksum.count == 64 && package.checksum.allSatisfy { $0.isHexDigit })
        assert(package.content.dependencies.contains { $0.kind == .audioUnit })
        assert(package.content.dependencies.contains { $0.kind == .externalMIDI && $0.identifier == "404" })
        assert(package.content.dependencies.contains { $0.kind == .samplerPreset && $0.identifier == "Generated Piano.aupreset" })
        assert(package.content.dependencies.contains { $0.kind == .tonicPad && $0.identifier == "Generated Piano.aupreset" })
        assert(package.content.warnings.contains { $0.contains("Audio Unit") })
        assert(!json.contains("pluginState"), "Plug-in state must not travel in a setlist share")
        assert(!json.contains("/Users/example"), "Local source paths must be removed from portable notes")
        assert(!json.contains("Doe"), "A path with spaces must not leave a folder or filename fragment")
        assert(json.contains("[source location]"))
        let decoded = try SetlistSharePackage.decode(data)
        assert(decoded.checksum == package.checksum)

        // A package is untrusted input. Damage, an unexpected schema, hidden
        // dependencies and non-portable plug-in state must all be refused before
        // any library write or activation.
        var damaged = data
        damaged[damaged.startIndex + damaged.count / 2] ^= 0xff
        expectFailure("damaged checksum") { _ = try SetlistSharePackage.decode(damaged) }
        expectFailure("truncated package") { _ = try SetlistSharePackage.decode(Data(data.dropLast(20))) }
        expectFailure("malformed JSON") { _ = try SetlistSharePackage.decode(Data("{\"format\":\"stagekeys-setlist-share\"}".utf8)) }
        expectFailure("oversized package") {
            _ = try SetlistSharePackage.decode(Data(repeating: 0x20, count: SetlistSharePackage.byteLimit + 1))
        }
        var wrongFormat = package
        wrongFormat.format = "another-format"
        expectFailure("wrong format") { _ = try SetlistSharePackage.decode(try SetlistShare.encode(wrongFormat)) }
        var wrongVersion = package
        wrongVersion.version = 2
        expectFailure("wrong version") { _ = try SetlistSharePackage.decode(try SetlistShare.encode(wrongVersion)) }
        var withState = package.content
        withState.setlist.patches[0].layers[0].pluginState = Data("vendor state".utf8)
        expectFailure("embedded plug-in state") {
            _ = try SetlistSharePackage.decode(try SetlistShare.encode(try SetlistShare.sealed(withState)))
        }
        var hiddenDependency = package.content
        hiddenDependency.dependencies.removeFirst()
        expectFailure("hidden dependency") {
            _ = try SetlistSharePackage.decode(try SetlistShare.encode(try SetlistShare.sealed(hiddenDependency)))
        }

        // Offline links use the same validated package. Wrong hosts, duplicate
        // parameters and invalid base64 are not importable.
        let link = try SetlistShareLink.url(for: package)
        let linked = try SetlistShareLink.package(from: link)
        assert(linked.checksum == package.checksum)

        // A package that is valid as a file can still exceed the smaller link
        // budget. The user must see the link limit and the file alternative.
        var oversizedContent = package.content
        oversizedContent.setlist.name = String(repeating: "x", count: 1_600_000)
        let oversizedLinkPackage = SetlistSharePackage(
            format: SetlistSharePackage.formatIdentifier,
            version: SetlistSharePackage.supportedVersion,
            exportedAt: Date(), checksum: package.checksum, content: oversizedContent)
        expectFailure("oversized offline link") { _ = try SetlistShareLink.url(for: oversizedLinkPackage) }
        assert(SetlistShareError.linkTooLarge.errorDescription?.contains(".stagekeyssetlist") == true)
        for bad in ["https://example.com/setlist-share?package=AAAA",
                    "stagekeys://other-host?package=AAAA",
                    "stagekeys://setlist-share",
                    "stagekeys://setlist-share?package=A",
                    "stagekeys://setlist-share?package=AAAA&other=1",
                    "stagekeys://setlist-share?package=AAAA&package=BBBB"] {
            guard let url = URL(string: bad) else { fatalError("Generated invalid test URL") }
            expectFailure("unsafe link \(bad)") { _ = try SetlistShareLink.package(from: url) }
        }

        // A destination with no conflicting identities keeps every authored
        // identity. The copy is independent in the library afterward.
        let cleanLibrary = try SetlistLibrary(root: root.appendingPathComponent("Clean Setlists"))
        let cleanPlan = try SetlistShare.preview(package, library: cleanLibrary)
        assert(cleanPlan.canActivate)
        assert(cleanPlan.collisions.isEmpty)
        assert(cleanPlan.setlist.patches.map(\.id) == source.patches.map(\.id))
        assert(cleanPlan.setlist.patches[0].layers.map(\.id) == source.patches[0].layers.map(\.id))
        assert(cleanPlan.setlist.patches[0].snapshots.map(\.id) == source.patches[0].snapshots.map(\.id))
        assert(cleanPlan.proposedName == "Generated Share")
        let cleanID = try SetlistShare.saveToLibrary(cleanPlan, library: cleanLibrary)
        let cleanReloaded = try cleanLibrary.load(id: cleanID)
        assert(cleanReloaded.patches.map(\.id) == source.patches.map(\.id))

        // Existing identities and names are resolved without touching the saved
        // source. Missing dependencies disable activation but not Save to Library.
        let library = try SetlistLibrary(root: root.appendingPathComponent("Setlists"))
        let sourceDescriptor = try library.save(source)
        let plan = try SetlistShare.preview(package, library: library) { sound in
            sound.kind == .audioUnit ? "Generated AU is not installed" : "Generated sampler preset is missing"
        }
        assert(!plan.canActivate)
        assert(plan.missingDependencies.count == 3)
        assert(plan.missingDependencies.allSatisfy { !$0.reason.isEmpty })
        assert(plan.collisions.count >= 21)
        assert(plan.proposedName == "Generated Share Copy")
        assert(plan.setlist.name == plan.proposedName)
        assert(Set(plan.setlist.patches.map(\.id)).isDisjoint(with: Set(source.patches.map(\.id))))
        assert(Set(plan.setlist.patches[0].layers.map(\.id)).isDisjoint(with: Set(source.patches[0].layers.map(\.id))))
        assert(Set(plan.setlist.patches[0].snapshots.map(\.id)).isDisjoint(with: Set(source.patches[0].snapshots.map(\.id))))
        let firstID = try SetlistShare.saveToLibrary(plan, library: library)
        var first = try library.load(id: firstID)
        assert(first.name == "Generated Share Copy")

        let secondPlan = try SetlistShare.preview(package, library: library)
        assert(secondPlan.canActivate)
        let secondID = try SetlistShare.saveToLibrary(secondPlan, library: library)
        assert(secondID != firstID)
        let secondReloaded = try library.load(id: secondID)
        assert(secondReloaded.name == "Generated Share Copy 2")
        first.patches[0].layers[0].name = "Changed after export"
        _ = try library.save(first, id: firstID)
        let secondAfterEdit = try library.load(id: secondID)
        assert(secondAfterEdit.patches[0].layers[0].name == "Generated Piano",
               "A shared copy must be independent of later edits")
        let sourceReloaded = try library.load(id: sourceDescriptor.id)
        assert(sourceReloaded.name == "Generated Share")

        // Older schema versions decode, validate, and upgrade in the destination
        // copy only. The package remains the authored version.
        var legacy = source
        legacy.version = 1
        let legacyPackage = try SetlistShare.make(legacy)
        assert(legacyPackage.content.setlist.version == 1)
        let upgraded = try SetlistShare.preview(legacyPackage, library: cleanLibrary)
        assert(upgraded.setlist.version == 4)
        assert(upgraded.warnings.contains { $0.contains("upgraded to 4") })

        // File writes are atomic and a refused export leaves the existing file
        // byte-for-byte unchanged. The document type extension is required.
        let file = root.appendingPathComponent("Generated Share.stagekeyssetlist")
        try SetlistShare.write(source, to: file)
        let originalBytes = try Data(contentsOf: file)
        let filePackage = try SetlistShare.read(file)
        assert(filePackage.checksum == package.checksum)
        var invalid = source
        invalid.name = String(repeating: "x", count: 201)
        expectFailure("invalid export") { try SetlistShare.write(invalid, to: file) }
        let bytesAfterRefusal = try Data(contentsOf: file)
        assert(bytesAfterRefusal == originalBytes)
        expectFailure("wrong file extension") {
            try SetlistShare.write(source, to: root.appendingPathComponent("Generated Share.json"))
        }
        // Two independent data roots stand in for two installations. The first
        // exports a saved setlist, the second imports it with no library or
        // ratings of its own, re-exports it, and the first imports that copy
        // back. Ratings are per installation and no import may rewrite either
        // the source document or the destination's ratings.
        let installARoot = root.appendingPathComponent("Install A")
        let installBRoot = root.appendingPathComponent("Install B")
        let installA = try SetlistLibrary(root: installARoot)
        let installB = try SetlistLibrary(root: installBRoot)
        let installADescriptor = try installA.save(source)
        let installARecord = installARoot.appendingPathComponent(installADescriptor.id.uuidString + ".json")
        let installARatingsFile = installARoot.appendingPathComponent("sound-ratings.json")
        let installARatings = ["generated-piano": 4, "generated-au": 5]
        try SoundRatingArchive.save(installARatings, to: installARatingsFile)
        let installAOriginalBytes = try Data(contentsOf: installARecord)

        let firstPackage = try SetlistShare.make(try installA.load(id: installADescriptor.id))
        let secondPlan = try SetlistShare.preview(firstPackage, library: installB)
        assert(secondPlan.collisions.isEmpty && secondPlan.canActivate)
        let installBID = try SetlistShare.saveToLibrary(secondPlan, library: installB)
        let installBCopy = try installB.load(id: installBID)
        assert(installBCopy.patches.map(\.id) == source.patches.map(\.id))
        assert(installBCopy.patches[0].layers.map(\.id) == source.patches[0].layers.map(\.id))
        assert(installBCopy.patches[0].snapshots.map(\.id) == source.patches[0].snapshots.map(\.id))
        assert(installBCopy.patches[0].layers[0].effects == source.patches[0].layers[0].effects)
        assert(installBCopy.patches[0].layers[0].external?.nativeSampler?.notes ==
               source.patches[0].layers[0].external?.nativeSampler?.notes)
        assert(installBCopy.patches[0].tonicState?.sound?.fileName ==
               source.patches[0].tonicState?.sound?.fileName)
        let installBRatingsFile = installBRoot.appendingPathComponent("sound-ratings.json")
        let installBRatingsBeforeImport = try SoundRatingArchive.read(installBRatingsFile)
        assert(installBRatingsBeforeImport.isEmpty,
               "Importing a setlist must not invent library ratings")
        try SoundRatingArchive.save(["generated-piano": 2], to: installBRatingsFile)

        let returnPackage = try SetlistShare.make(try installB.load(id: installBID))
        let returnPlan = try SetlistShare.preview(returnPackage, library: installA)
        assert(!returnPlan.collisions.isEmpty)
        let returnID = try SetlistShare.saveToLibrary(returnPlan, library: installA)
        assert(returnID != installADescriptor.id)
        let installAOriginalAfter = try installA.load(id: installADescriptor.id)
        assert(installAOriginalAfter.name == source.name)
        assert(installAOriginalAfter.patches.map(\.id) == source.patches.map(\.id))
        let installABytesAfterReturn = try Data(contentsOf: installARecord)
        assert(installABytesAfterReturn == installAOriginalBytes,
               "A return-trip import must not rewrite the original installation's document")
        let installARatingsAfterReturn = try SoundRatingArchive.read(installARatingsFile)
        assert(installARatingsAfterReturn == installARatings,
               "A return-trip import must not change the destination's ratings")
        let installBRatingsAfterReturn = try SoundRatingArchive.read(installBRatingsFile)
        assert(installBRatingsAfterReturn == ["generated-piano": 2],
               "Each installation keeps its own ratings")
        let reopenedB = try SetlistLibrary(root: installBRoot)
        let reopenedBCopy = try reopenedB.load(id: installBID)
        assert(reopenedBCopy.patches[0].layers[0].name == "Generated Piano")

        print("PASS setlist sharing: checksummed portable package, payload exclusions, tamper/injection refusal, offline link, dependency preview, identity collision resolution, independent copies, clean-install two-root round trip with destination ratings intact, legacy upgrade and atomic writes")
    }

    private static func expectFailure(_ label: String, _ body: () throws -> Void) {
        do { try body() } catch { return }
        fatalError("Expected refusal for " + label)
    }

    private static func generatedSetlist() throws -> Setlist {
        let component = ExternalAUIdentity(type: 0x61756d75, subtype: 0x74657374,
                                           manufacturer: 0x74657374, name: "Generated AU")
        let program = NativeSamplerProgram(
            groups: [.init(name: "Generated Layer", layer: 0, low: 0, high: 127,
                           velocityLow: 1, velocityHigh: 127, controller: nil,
                           controllerLow: 0, controllerHigh: 127, enabled: true)],
            notes: ["Sample at /Users/example/Private/piano.wav and /Volumes/Private/piano.wav",
                    "Sample at /Users/Jane Doe/Private/piano.wav"],
            compactGroups: nil, conversionVersion: nil, amplitudeEnvelope: nil, voiceControls: nil)
        let preset = ExternalSound(kind: .samplerPreset, name: "Generated Piano",
                                   fileName: "Generated Piano.aupreset", component: nil,
                                   program: 0, bankMSB: 121, bankLSB: 0, nativeSampler: program)
        let audioUnit = ExternalSound(kind: .audioUnit, name: "Generated AU",
                                      fileName: nil, component: component, program: 0,
                                      bankMSB: 121, bankLSB: 0, nativeSampler: nil)
        var patch = Patch.make("Generated Patch")
        var piano = Layer(name: "Generated Piano", instrument: -1, gain: 0.7)
        piano.external = preset
        piano.pluginState = Data("vendor state".utf8)
        piano.effects[0] = AudioEffect.factoryDefault(kind: 3)
        piano.pan = 0.25
        patch.layers[0] = piano
        var plugin = Layer(name: "Generated AU", instrument: -1, gain: 0.4)
        plugin.external = audioUnit
        plugin.midiOutputChannel = 3
        patch.layers[1] = plugin
        var external = Layer(name: "Generated External", instrument: -1, gain: 1)
        external.midiDestinationID = 404
        patch.layers[2] = external
        patch.conversionNotes = ["Source archive at /Users/example/Private/Source.exs"]
        patch.snapshots[0].emptySlot = false
        patch.snapshots[0].sounds = patch.layers.map(SnapshotSoundState.init)
        patch.tonicState = TonicPatchState(enabled: true, root: 0, timbre: 0, sound: preset,
                                           velocitySelector: false, gain: 0.5, brightness: 0.5, shimmer: 0)
        var setlist = Setlist()
        setlist.name = "Generated Share"
        setlist.patches = [patch]
        setlist.assignments = [20: 0]
        try setlist.validate()
        return setlist
    }
}
