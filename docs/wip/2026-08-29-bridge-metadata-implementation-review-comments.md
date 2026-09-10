# Bridge Metadata Application Protocol — Implementation Review

## Review identity

- Assignment: `bridge-metadata-complete-review-2026-08-29-bcfb1a02f`
- Reviewer session: Claude Fable `claude-fable-5[1m]`, ACPX session
  `d71706ab-7c3b-4626-a3d0-62a0b06a0116`
- Authority: fresh-context, read-only, candidate-only
- Base: `1ef64e6c67b720ba87d0c0182c958bf47e3f3a65`
- Reviewed implementation: `bcfb1a02f374d32698e1e2b7eec3c2362dc809e2`
- Canonical plan:
  `tmp/plan-workflows/2026-08-27-bridge-metadata-application-protocol-v6.md`
- Result: `needs-revision`
- Implementation remediation count before this review: zero

Post-review commits `239ee9304` and `e3e443951` modify only
`docs/wip/debugging/2026-08-25-annotation-interaction-focus-and-tooltip-bugs.md`.
They are anchored exclusions and do not change this review's source or proof
binding.

## Coverage result

The complete reviewer traced MAP-R1 through MAP-R15 plus the v6 S3 exact-once
revision correction through the governing design, plan slices, current source,
and proof. Generic raw-to-typed registration, bounded catalog transfer,
authority-scoped worker assembly, body-free SQLite catalog reads,
catalog/control/content separation, demanded rich loading, semantic-revision
publication, capacity bounds, and Vite/packaged reachability were covered.

The reviewer also produced anchored exclusions for the marketing website,
Review-refresh/comparison UI, FSEvents, prior render-disposition remediation,
test-lane repartition, and unrelated design/WIP documents.

## Candidate disposition

### CF-1 — Rejected

Candidate claim: the Main annotation catalog bank could accept a late complete
staging tail from a retired worker because `applyCatalogStaging` adopts the
event-carried authority.

Why rejected:

- `bridge-pane-comm-worker-session.ts:214-216` admits a port message only when
  both the captured worker and captured port are still the session's exact
  current worker and port.
- `bridge-pane-comm-worker-session.ts:345-352` closes and clears the current
  port and terminates and clears the worker during retirement.
- Therefore a queued old-port delivery cannot reach pane-runtime dispatch after
  replacement retirement. The candidate's concrete consequence is unreachable
  through the production owner it omitted.

No correction is required for CF-1.

### CF-2 — Accepted

Severity: important.

Exact anchor:

- `BridgeWeb/src/file-viewer/bridge-file-viewer-code-panel.tsx:307-318`
  clears `pendingAnnotationComposer` whenever the selected item no longer
  matches.
- `BridgeWeb/src/file-viewer/bridge-file-viewer-code-panel.tsx:483-493`
  includes `sourceDescriptorId` in that match.
- The machine-driven clear has no `committed` guard, while the user-driven
  range, gutter, and selection clear paths explicitly preserve a committed
  composer.

Governing obligation:

- MAP-R12 at
  `docs/specs/2026-08-27-bridge-metadata-application-protocol/2026-08-27-specification.md:394`
  requires catalog/content replacement not to remove a command-confirmed
  message.
- PR1 Save behavior at
  `docs/specs/2026-08-06-worktree-annotations/pr1-specification.md:545`
  requires the exact committed saved message to remain visible through later
  invalidation, replacement, delay, or read failure.

Concrete consequence:

A same-logical-file content refresh produces a successor File source
descriptor. If it arrives after the exact Save receipt but before authoritative
rich projection reconciliation, the descriptor-sensitive layout effect hides
and then clears the committed receipt presentation. The durable message remains
in SQLite, but the command-confirmed message and saved-thread activation/focus
continuity disappear during the exact MAP-R12 window.

Smallest correction:

Keep a committed File root composer across same-logical-file descriptor
replacement until the existing authoritative projection reconciliation invokes
`onSaved` and installs the saved thread. Preserve the existing behavior that
discards an uncommitted composer on file or descriptor navigation.

Owner: `implement-plan`, S4 File annotation adapter.

Confirmation evidence:

1. Add a Browser Mode RED test that commits a File root from the exact command
   receipt without publishing rich reconciliation.
2. Replace the selected item with the same File item/path and a successor
   `sourceDescriptorId`.
3. Assert the committed receipt presentation remains visible and session demand
   remains active.
4. Publish the authoritative saved thread and assert the receipt presentation
   retires exactly once into the saved thread with activation/focus continuity.
5. Retain the existing test proving an uncommitted composer is discarded on
   descriptor or file navigation.

Coverage invalidated:

- MAP-R12 File command-confirmed overlay continuity
- S4 File annotation adapter continuity
- S5 File replacement-during-Save browser proof

## Proof and readiness

Proof for `bcfb1a02f` remains valid outside the invalidated CF-2 coverage. The
full aggregate passed at that identity, but it does not exercise the accepted
descriptor-replacement interleaving. The branch is not implementation-review
ready until CF-2 is corrected, its focused proof passes, applicable broader
gates pass on the corrected source, and one new complete implementation review
restores the invalidated coverage.

The exact packaged WKWebView ACK-black-hole injection remains an uncovered
boundary, not an accepted defect: the owning worker/native timeout and reopen
behavior has deterministic proof, and the real aggregate exercises the
production carrier without a test-only fault hook.
