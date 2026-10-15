# Library interaction — v0.23

## Observed in Sunday Keys

The accessible Mac library shows five dots to the right of each sound name. On interaction these become stars; clicking star N assigns N stars, and clicking the current rating again clears it. Inspection temporarily rated Felt Room and then cleared it back to five dots. No sound was added to the source patch.

Its Order by menu includes Name, Rating, Recently Added, Random and Recommended. Complexity is one of the filter-column choices and offers Complex, Moderate and Simple. The original source patch was left intact after Cancel.

## StageKeys implementation

- Five independent star buttons occupy the right side of each result row. Empty stars appear on hover; otherwise unrated positions are dots. Each button has an accessible sound/rating label and a clear-rating action when already selected. Rating a row does not select, replace or audition that sound.
- Ratings are stored atomically in the personal `sound-ratings.json`, independent of sound assets, patches and snapshots. Converted MainStage aliases share the playable entry's rating identity. Invalid values and oversized archives are rejected. Ratings persist when the sound chooser closes.
- Order by offers Name, Rating, Recently Added and Random. Rating and Recent default to highest/newest first. Recent uses the existing managed-library insertion order, not inferred dates. Random has a stable seeded order for the browsing session and is reshuffled when Random is selected again; view updates and ratings do not shuffle the list.
- Complexity accepts explicit Simple, Moderate or Complex metadata. Unknown sounds remain Not Tagged. A library row's context menu can set or clear this tag; inferred name tags preserve explicit complexity when refreshed. No source complexity is guessed from a sound's name or number of effects.
- Choice popovers open below their controls. The result row reserves space for ratings and wraps the sound name, closer to the observed source layout.

Recommended sorting and the source Note Range facet are not implemented. The source recommendation algorithm and exact recent/random ordering have not been established. Complexity tagging through a context menu is a StageKeys extension; the reference's metadata editing workflow was not inspected. Full library parity is not claimed.

## Verification

Run `Tests/test-library.sh` on macOS. It checks legacy-library decoding, cascading facets, combined search, deterministic sorting, rating persistence/clear/validation, stable random ordering and complexity metadata persistence. All fixtures and outputs use temporary directories.

Native Mac verification checks the actual star controls, persistence across chooser reopening, clear rating, sort/filter menus and Cancel. Universal Mac and iPhone/iPad simulator Release builds are checked; physical mobile interaction remains outstanding.
