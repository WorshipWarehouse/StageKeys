# Persistent snapshot positions

The performance strip always displays at least five positions, including on new patches. Empty positions do not recall silence or modify the live mix. The Capture Snapshot menu saves directly into any position; the context menu also provides Capture Current Mix. Capturing position 5 creates explicit empty positions 1–4 without filling them with fabricated snapshots.

Clear resets one position rather than deleting the array element and shifting subsequent positions. Saved empty positions have `emptySlot: true`; legacy snapshots omit that field and remain populated. Existing sessions with more than five snapshots keep every position (up to the existing limit of 16). Save Snapshot uses the first empty position. Invalid indices are rejected before any state or audio operation.

Regression: `Tests/test-library.sh SnapshotSlotTests` covers sparse capture, stable identities, no empty recall, clear/recapture, index bounds, legacy decoding and saved-session recall. No sample or effect algorithm changes are involved.
