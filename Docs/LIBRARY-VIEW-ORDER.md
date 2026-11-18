# Library order preference — what is stored and what is not

The sound library reopened with a fresh query every time, so the order a performer
chose was lost on the next launch and a `Random` order reshuffled the same set.
Issue [#17](https://github.com/WorshipWarehouse/StageKeys/issues/17) requires that
deterministic order survive a restart.

## Implemented behaviour

- The chosen order is a view preference, stored beside the facet columns as
  `library.order` (the `LibrarySort` name: Name, Recommended, Rating,
  Recently Added, Random).
- The chosen direction is stored as optional Boolean text in `library.ascending`. Missing or invalid text retains the mode default; a reversed Random/Rating order is restored explicitly.
- `Random` also stores the seed it was shown with as `library.shuffleSeed`. The
  list is ordered by a stable hash of the sound identity and that seed, so a
  relaunch reproduces the exact order instead of drawing a new one.
- `LibraryQuery(storedOrder:storedSeed:storedAscending:)` restores the mode, clears any manual
  facet sort, restores the saved direction or the mode default (Name and Recommended ascending,
  the others descending) and reuses the stored seed. A missing, empty or zero
  seed draws a new one, which the view then stores; zero is never persisted as a
  live seed.
- An unknown or absent stored order falls back to **Name**, the previous default,
  and ignores a stray seed.
- Clearing the preference is not offered yet: the app stores the last shown order
  deliberately, and any future reset needs its own control rather than a silent
  fallback.

## Deliberately not persisted

- The search text and the facet filters are **not persisted**. Reopening the
  library still starts from every sound with no filters, because a remembered
  search can look like a library that is missing sounds.
- The browser's selected row, collection and the audition session are session
  state, not preferences.

## Verification

`Tests/LibraryOrderPersistenceTests` is the regression program: it pins a known
seed to a fixed order, checks that a stored seed is reused rather than redrawn,
that a different seed produces a different order, that the zero sentinel is never
kept, that an unknown stored mode falls back to Name, and that Rating, Recently
Added and Recommended restore their own directions. `Tests/test-library-order-persistence.py`
fails when the restore path, the stored keys, the program registration or the
`processing` job wiring disappears.

Both run on hosted macOS CI; the library panel itself was not viewed in a running
app from the implementation environment.

Empty-state Add Audio Unit and MIDI Routing navigation also clears favorites-only, search and facets without overwriting saved ordering/direction/seed.
