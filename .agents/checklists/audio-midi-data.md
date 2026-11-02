# Audio Midi Data

- [ ] Render thread has no added allocations/locks/I/O/logging/graph edits
- [ ] Buffer/pointer/event lifetimes valid through callback completion
- [ ] Async results guard operation, patch and layer identity
- [ ] Note/source/sustain ownership and Panic cleanup exercised
- [ ] Rejected change retains or explicitly stops playback safely
- [ ] Saved bytes/migrations/round-trip checked with synthetic data
- [ ] Resource limits distinguish request count from CPU/RSS/process containment
- [ ] Real hardware/vendor qualification recorded separately
