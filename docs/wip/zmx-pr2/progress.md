# PR2: zmx upgrade and optimized Ghostty September trial

The beta trial uses unmodified Ghostty `82232ecde55405559dec29c5466cb9e39938cb41`
(September 7, 2026) and upstream zmx 0.8.1 `8bab1f0173b07e79835ea372d749af3dbf0d0842`.
Zig 0.16 builds both vendors. Local Ghostty builds explicitly use ReleaseFast,
matching the release workflow. The local helper no longer patches vendor source.
SwiftPM archive normalization operates only on the copied framework.

The earlier debug resize stalls also reproduced with stable Ghostty 1.3.1.
Captures identified expensive Debug-mode integrity checks under the terminal lock,
with renderer and MainActor callers waiting. Building that same stable revision
with ReleaseFast removed sampled lock waits under comparable agent redraw output,
with zmx unchanged. This supports retrying the September revision; it does not
prove every possible stall is fixed or establish a zmx-version regression.

The prior September integration and its clipboard tests are restored. The owner
retained existing automatic clipboard approval for the beta without persistent
session grants. The local build-mode fix is a separate commit, `84f1b53e0`.
Its focused vendor-wiring suite passed 10 tests. The prior trial aggregate passed
at `f374d7154`; fresh September retry checks remain separate from that evidence.

Beta 51 was the original September trial; beta 52 restored stable Ghostty.
Beta 53 is the requested September retry with the local build-mode correction.
This is an authorized unstable beta, not a merge-readiness or production-release
claim. PR 338 remains unmerged; no production update is requested.
