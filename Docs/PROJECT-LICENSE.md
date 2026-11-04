# StageKeys project license decision

On 4 November 2026, the project owner explicitly selected **MIT** in the development conversation after choosing open source and being asked which license to apply. This records the owner decision previously pending in #64 and #21. StageKeys-authored code and accompanying documentation are now offered under the standard MIT text in root `LICENSE`, with copyright attribution “2026 StageKeys contributors,” consistent with the existing StageKeys DenseReverb notice. `Licenses/StageKeys-MIT.txt` is an identical distribution copy bundled by both committed Xcode targets. XcodeGen already includes the Licenses directory; the committed project is updated directly without regeneration.

Existing notices remain intact: Airwindows CreamCoat and EXS parser-derived material retain their MIT notices and attribution; the specifically scoped DenseReverb notice remains; IBM Plex fonts remain under SIL OFL 1.1. This decision does not relicense third-party work, confer trademark rights, or authorize redistribution of Sunday Keys/Sunday Sounds, MainStage/plugin libraries, private samples, user sessions or imported content. StageKeys remains independent with no claimed affiliation or complete parity.

The earlier Completion audit package is a dated snapshot. Its statements that the root license was unspecified describe the repository at that time and are superseded by this decision. No historical verification hashes or audit outcomes are rewritten.

The license decision is resolved. #21 remains open for independent asset/dependency provenance review, public signing/notarization, clean-machine install/update/rollback, intended iOS distribution and the supported-platform/beta matrix. No signing, upload or public deployment is performed by adding the license.

Verification: the distribution gate requires the new bundled notice as well as all existing notices. Its synthetic-bundle regression checks each notice’s omission independently and checks that the source/bundled MIT copies match. Both platform artifact gates verify actual bundled resources. Results are recorded in the PR; no audio behavior changes are made.

Canonical license reference: https://opensource.org/license/mit
