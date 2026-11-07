# Clean-install setlist round-trip qualification

This record covers the clean-install portion of [#114](https://github.com/WorshipWarehouse/StageKeys/issues/114). It adds deterministic evidence that a saved setlist survives a round trip between two otherwise empty installations, and it defines the physical Mac/iPad procedure. **No physical device run is claimed here.**

## What the automated check does

`Tests/SetlistShareTests.swift` now builds two independent data roots in one disposable test directory:

1. **Installation A** saves a generated setlist, writes its own library ratings, and exports the saved copy as a portable package.
2. **Installation B** starts with no setlist library and no ratings file. It previews and imports the package with **Save to Library**, then is reopened from disk to prove the copy persists.
3. The check compares patch, layer and snapshot identities, effect values, sampler notes and the Tonic Pad reference against the exported package. It also asserts that importing did not invent ratings in B.
4. **Installation B** writes its own ratings and re-exports its saved copy.
5. **Installation A** imports that return copy as a second, independent document. The original document's bytes and A's ratings must be unchanged, B's ratings must be unchanged, and the return copy must receive new identities because A already holds the authored ones.

This stands in for the file-level half of a clean Mac/iPad install. It uses generated content only; no vendor samples, plug-ins or private fixtures are involved, and nothing is redistributed.

## Run it

On macOS with Xcode command-line tools:

```
python3 Tests/run-local-library.py . /private/tmp/stagekeys-roundtrip SetlistShareTests
```

`SetlistShareTests` is part of the default library gate, so `Tests/test-library.sh` and hosted CI run the same checks. The test prints a single `PASS setlist sharing: …` line that names the two-root round trip.

Ratings integrity is checked with `SoundRatingArchive`, the same archive the library browser reads and writes. A merge that made import write ratings, or that rewrote the source document in place, fails these assertions.

## Physical qualification procedure

These steps are **not executed by CI** and are not claimed by this document. Run them on a Mac and an iPad that do not already contain the test setlist.

### Mac

1. Install a build on Mac A, open it, create or import a setlist that references sounds available on Mac B, and use **Share…** to write a `.stagekeyssetlist` file.
2. Confirm the package is small enough to be a document only, and that the exported notes show `[source location]` instead of a home-directory path.
3. On Mac B, which has never opened that setlist, open the file from Finder or use **Setlists → Import / Export → Import Setlist…**.
4. In a separate preview, use a generated package that references a sampler or Audio Unit absent on Mac B. Confirm the plan lists the missing dependency and offers **Save to Library** while **Save and Load** is disabled. Dismiss that preview and reopen the original package.
5. Choose **Save to Library**, quit, relaunch, and confirm the imported setlist is still listed with the expected name and patches.
6. Preview the same file again. Confirm the collision is listed, then import and confirm a second independent copy is created.
7. Rate a library sound, import another setlist, and confirm the rating is unchanged.
8. Repeat the import with a deliberately truncated copy of the file and confirm the error is reported without losing existing setlists.

9. Export the first imported copy from Mac B and import it on Mac A. Confirm the return copy has its own library entry and the original setlist and ratings are unchanged.

### iPad

1. Transfer the same package with AirDrop or the Files app.
2. Open it in StageKeys, complete the same plan review, and choose **Save to Library** with the referenced sounds installed.
3. Relaunch the app and confirm the setlist and its patches, notes, effects and Tonic Pad state are intact.
4. With a referenced sound removed, confirm **Save and Load** is unavailable and the explanation is visible, while **Save to Library** still works.

5. Export the saved copy from the iPad to Mac A. Import it there and confirm a separate copy is created while the original setlist and ratings are unchanged.

## Limits

- This is deterministic qualification, not a physical clean-device run, a signed-distribution install, an audible stage check or a latency/soak test.
- The test uses one process and two data roots, not two machines. macOS/iPadOS file coordination, AirDrop and document-picker behaviour remain manual checks.
- No sample, plug-in binary or vendor content is included in the package or the test.
