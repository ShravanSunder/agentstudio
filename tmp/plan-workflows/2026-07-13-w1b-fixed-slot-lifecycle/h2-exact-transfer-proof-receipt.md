# H2 Exact Transfer Proof Receipt

Status: `READY`
Goal: `2026-07-10-agentstudio-performance-boundaries`
Workflow: `shravan-dev-workflow:implementation-execute-plan`
Starting HEAD: `e5cef1d6`
Date: 2026-07-13

## Plan and spec anchors

- `docs/plans/2026-07-10-agentstudio-performance/w1b-fixed-slot-lifecycle-plan.md`, H2.
- `docs/specs/2026-07-09-watched-folder-admission-mainactor-fairness/filesystem-observation-admission-lifecycle.md`.
- Goal proof row R1 advances only for dormant exact transfer. D3 native context release, W2b production reachability, and DQ1 performance qualification remain unproven.

## Implemented boundary

```text
whole-lease preflight
  -> exact H1 semantic acceptance
  -> exact SourceGate acceptance when recovery exists
  -> opaque whole-lease transfer authority
  -> generic whole-lease acknowledgement
  -> exact semantic replay clear
  -> exact SourceGate replay clear
  -> registry retirement transition
  -> retained final retirement receipt
```

- Preflight cannot return final transfer authority.
- Only `FilesystemObservationLeaseTransfer` combines all three acceptance authorities.
- Semantic and SourceGate replay clear require the exact whole-lease authority and exact post-acknowledgement receipt.
- Stale acknowledgements from the same binding cannot clear a later lease.
- Final-fence retry/recovery debt is checked under the mailbox lock before acknowledgement.
- Final-fence recovery clearing is structurally total after acknowledgement.
- Retirement stops at `retiredAwaitingContextRelease`; D3 alone releases native context, acknowledges release, vacates, and reuses the physical slot.
- The registry remains the only mutable custody owner. Its pure retirement transition planner stores no custody and mints no authority.
- Production `FilesystemActor.swift` remains unchanged and legacy-only before W2b.

## Controller-owned proof

```text
mise run test -- --filter \
  'FilesystemObservationLeaseTransfer|FilesystemLeaseTransferArchitecture'
exit 0
16 tests / 2 suites

mise run test -- --filter \
  'FilesystemObservation(SemanticReplay|SlotRegistry|Mailbox|RetirementFence|LeaseTransfer)|FilesystemSourceGate'
exit 0
87 tests / 11 suites

mise run test -- --filter \
  'FilesystemObservationCallbackHotPathArchitecture|FilesystemObservationLeaseTransfer|FilesystemLeaseTransferArchitecture'
exit 0
21 tests / 3 suites

mise run test
exit 0
normal parallel and serialized WebKit lanes passed; repo-default E2E and zmx
E2E lanes remained skipped by their normal opt-in configuration.

mise run lint
exit 0
swift-format passed; SwiftLint reported 0 violations across 1,499 files;
architecture lint passed; all 31 admission mutation rows restored exactly;
release-script verification passed.

git diff --check
exit 0
```

## Permanent oracles

- Contribution plus recovery with the wrong acknowledgement retains both replay shells.
- Exact retry reuses the same repair generation and does not repeat semantic effects.
- Stale same-binding acknowledgements are rejected independently for semantic and recovery custody.
- Final fence plus recovery reaches `quiescentAfterRecovery(exactRevision)`.
- A lost response replays the same retained retirement receipt.
- The callback currentness architecture proof performs one keyed state lookup, one dictionary subscript, and one pure classifier call with no scan.
- Architecture proof permits the pure planner call only from the primary registry declaration and forbids production registry extensions.

## Independent review reduction

Accepted and repaired before this receipt:

- forbidden same-file registry extension;
- semantic clear not causally bound to generic acknowledgement;
- SourceGate clear accepting any same-binding acknowledgement;
- missing contribution-plus-recovery failed-acknowledgement proof;
- possible stranded retirement debt after acknowledgement.

Both adversarial re-review lanes returned `READY` with no blocker or important finding. A separate proof-contract audit confirmed final goal proof still requires the real driven AgentStudio app through authenticated IPC, marker-scoped Victoria, exact-PID Peekaboo or Computer Use, real DQ1 watched roots, and human interaction-feel verification.

## Freshness and scope

- Evidence is fresh against starting HEAD `e5cef1d6` plus the scoped H2 diff.
- Pre-commit source/test fingerprint, excluding `.agents/`: `06aef7edb87204868d5ae7402cb7f21793e9934dc4886570abaca8c02e7732b6`.
- Scope is 21 source/test files: 10 production files and 11 tests/support files.
- `.agents/` is unrelated and must not be staged.
- No product-performance, MainActor, typing, cursor, TUI, Victoria, IPC, Peekaboo, Computer Use, or real-root acceptance claim is made by this dormant checkpoint.

## Open work after this checkpoint

- D2c authority-backed lifecycle matrix.
- D3 release-once, acknowledgement, tombstone, and slot reuse.
- F3 fleet shutdown debt and G2 real dormant Darwin lifecycle.
- WF-C participants, W3-W10, atomic W2b production cutover, Victoria/DQ1 qualification, native UI driving, human feel validation, implementation review, and PR-ready wrap-up.

## Phase receipt

```text
phase_result: complete
evidence: this receipt and the controller-owned commands above
recommended_next_workflow: shravan-dev-workflow:implementation-execute-plan
recommended_transition_reason: H2 dormant exact transfer is READY; commit and continue serially with D2c and D3.
```
