# Imported Clip Distortion transitions

Refs #10. Translated ClipDist input gain, output gain and wet/dry mix now slew over 20 ms rather than stepping during source macro/controller automation. Initial saved settings apply immediately. The independent antiderivative soft clipper, source parameter mapping, filter/shelf topology, symmetry and static gain remain unchanged. No sample rewriting, added lookahead or render allocation is introduced.

The regression verifies a 12 dB output move begins continuously and settles to its exact requested gain at 44.1/48/96 kHz. Existing channel-compressor and imported-delay tests remain part of verification. This improves automation quality; it does not claim Apple's exact distortion spectrum, SilverVerb decay/early reflections or full MainStage effects parity. Those require matched source recordings and remain release work.
