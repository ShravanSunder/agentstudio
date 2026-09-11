# Ghostty and zmx upgrade process

This runbook governs upgrades of AgentStudio's embedded Ghostty framework and
zmx session multiplexer. It is a process and proof contract; it does not define
new runtime behavior.

## Upgrade sequence

1. Record the proposed Ghostty and zmx commits, toolchain versions, and whether
   the change is beta-only or production-bound.
2. Update the vendor pins without editing vendor source.
3. Build Ghostty from the pinned source with `ReleaseFast` and regenerate the
   XCFramework. Build zmx with its required Zig version.
4. Refresh copied framework headers and resources before any Swift build. Verify
   the copied header identity against the vendor header.
5. Compare the pinned Ghostty header action vocabulary with AgentStudio's
   `GhosttyActionTag` vocabulary by name and raw value. Every action must be
   routed, intercepted, deferred, or explicitly unsupported.
6. Compare runtime callback signatures and data layouts. Cover clipboard MIME,
   length, listing, confirmation, and denial behavior.
7. Run event-routing, callback, zmx integration, and mixed-version IPC tests.
8. Run real debug proof: launch the rebuilt app, exercise pane resize with active
   terminal output, and capture renderer/MainActor behavior.
9. Run focused tests, then the full `mise run test` aggregate on the exact head.
10. Push the exact head, wait for CI, inspect failures against the diff, and get
    independent implementation review.
11. Publish a beta only after artifact signing, notarization, checksum, and
    Homebrew verification. Merge and production release remain separate gates.

## Current run: Ghostty 82232ecde554 and zmx 0.8.1

Completed evidence:

- Ghostty `82232ecde55405559dec29c5466cb9e39938cb41` and zmx
  `8bab1f0173b07e79835ea372d749af3dbf0d0842` are pinned.
- Ghostty `ReleaseFast` removed the observed Debug integrity-check lock
  contention under comparable redraw output.
- The refreshed framework compiled against the new clipboard ABI.
- Callback/vendor focused tests passed 18/18 before the final action-gap slice.
- The full local aggregate passed on the prior committed head after framework
  refresh; the final action-gap slice requires a fresh run.
- Beta `v0.0.98-beta.53` passed build, signing, notarization, release, and
  Homebrew verification.
- The debug app was rebuilt from the refreshed framework and launched as vx09.

Open gates:

- **Commit and verify action-gap handling.** Four upstream actions are now
  explicitly represented as unsupported: window title, selection changed,
  terminal IO export, and move-tab-to-new-window. Direct adapter translation
  must return `.unhandled` without trapping. Focused and aggregate tests must
  run on the committed head.
- **Header vocabulary contract.** The current routing test checks the local
  enum only. Add a source-level contract that extracts the pinned header's
  `GHOSTTY_ACTION_*` values and compares names/raw values with the local
  vocabulary. This is the permanent defense against upstream additions.
- **Clipboard scope decision.** AgentStudio currently supports text/plain and
  rejects listing/non-text MIME requests. Decide whether Kitty/non-text
  interoperability is in scope for this upgrade; if not, retain the explicit
  unsupported behavior and document it in release notes.
- **zmx mixed-version proof.** Verify new client/new daemon and new client/old
  daemon behavior for list, history, attach, input/output, resize, and exactly
  one resize application. Do not infer this from the Ghostty tests.
- **Exact-head CI.** The previous BridgeWeb failure was a timeout in an
  unchanged BridgeWeb browser test; the previous Swift failure was an
  intermittent Bridge bootstrap test. They must be rerun on the final head and
  classified before merge.
- **Independent review.** Review the final exact diff and proof identities after
  the commit. A stale review of an earlier head does not close this gate.
- **Release acceptability.** Beta.53 is available for testing. Merge requires
  the exact-head gates above; production remains unchanged until separately
  authorized.

## Failure classification

A failure in an unchanged BridgeWeb path is an external/flaky lane only after
it passes on a clean retry or has a reproducible environment diagnosis. A
failure in Ghostty headers, action routing, callback ABI, zmx IPC, or the build
inputs is in scope and must be fixed before merge. Never convert a beta release
success into merge readiness.

## Proof record locations

- Source and decisions: `docs/wip/zmx-pr2/`.
- Debug captures and byte counters: `tmp/zmx-pr2/`.
- Current beta artifact proof: `tmp/zmx-pr2/beta53-proof.json`.
- The latest branch head and CI URL must be recorded after every push.
