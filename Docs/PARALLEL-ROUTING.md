# Imported parallel processing — v0.17

Instrument rack branches now run separate native sampler voices, MIDI processors and effect chains, then sum into the channel processing. Nested instrument branches preserve key/velocity ranges, static selector state and shared effect macros. Branch level, pan, bypass, MIDI settings and effects can be edited in Imported Rack controls and recalled in snapshots.

All 213 free library entries were translated without resampling. Twenty-six entries use parallel instrument routing. Offline production playback verified all ten volumes and every parallel entry with finite audible chord output below full scale. Synthetic tests verify branch isolation, shared macros and removal of the original combined sampler path. MIDI source disconnect, sustain, panic and library persistence checks pass.

Synced arpeggiators now follow an anchored musical timeline. Editable 8th/16th/32nd swing shifts alternating subdivisions and preserves phase across tempo changes. The inspected presets store straight groove. A groove selector alone does not contain Live's global groove amount; missing data is reported rather than invented.

Remaining differences: parallel audio-effect/MIDI racks, advanced velocity/random curves and some source synthesis processing are not translated. Several Live rate/style mappings remain inferred. Native effects approximate Live effects; sonic equivalence requires comparison against the original application. Branch gains already baked into source maps remain baked. Separate sampler voices increase sample memory use.

The library retains its facet columns, sorting, range preview and Add Sound flow. Its empty state now offers a direct Import Sounds action. macOS includes an original StageKeys ICNS in the bundle and sets the running application icon explicitly.
