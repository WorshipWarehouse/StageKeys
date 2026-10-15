# Output headroom (0.14)

The combined internal synth and imported instrument output now passes through the system peak limiter, followed by 1 dB of output headroom. The limiter is after channel effects and the master mixer. It prevents summed voices from reaching the hardware above full scale; it cannot undo saturation within a sample or a channel effect.

Validation on macOS: ten-note chords on Airy EP and Synthetic Piano, then repeated chords with sustain across eight sampler channels. The deliberately extreme sustained test peaked above 54 without the limiter and below 0.54 with it. Dry, quieter chord peaks changed by the expected 1 dB output margin (0.5411 to 0.4823 and 0.2560 to 0.2282). These are offline production-graph checks, not a claim of an audible comparison with the user's keyboard.

Library loading also removes the legacy “ · Ableton Samples” suffix and renames “Sunday Free Ableton · Volume N” collections to “Sunday Free · Volume N”. Stable IDs, sample references and settings remain unchanged. This normalization occurs when the library is read and is persisted on its next normal save. New imports use the original patch name directly.
