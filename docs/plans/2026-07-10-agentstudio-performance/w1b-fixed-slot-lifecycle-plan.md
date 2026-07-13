# W1b/W2 Fixed-Slot Filesystem Lifecycle Plan

Status: accepted after focused adversarial review
Date: 2026-07-13

Parent plan:
[Watched-Folder Admission And Shared Runtime Implementation Plan](watched-folder-and-shared-runtime-plan.md)

Accepted sources:

- `watched-folder-admission-mainactor-fairness.md`, 1,785 lines,
  SHA-256 `77e7c671513ee0aa8ccdf039379fe2eef734a639a9652df40b740c478dcc3f88`
- `filesystem-observation-admission-lifecycle.md`, 713 lines,
  SHA-256 `f546f63a6a7608950f8f2ebf4f780d98e3fef7b5282e36393aa089f7ebf19f23`
- live planning anchor: `03e667c5a048767629238e5483a0bbbe43b596a8`

## 1. Outcome

Replace the dormant registration-keyed filesystem observation assembly with the
accepted fixed fleet substrate while keeping production wholly legacy until the
later atomic W2b cut.

The immediate implementation ends with two independently verifiable gates:

```text
W1b dormant ready
  real bounded Darwin callback
  -> lease-credentialed paired port
  -> fixed physical slot
  -> isolated actor/SourceGate transfer
  -> ordered fence and release-once context teardown

W2a mechanics complete
  W1b gate
  + deterministic replacement/currentness state
  + repair-participant registry/projector mechanics
  + exact cancellation-safe fleet shutdown debt
```

Neither gate claims production reachability, MainActor improvement, terminal
interaction improvement, large-root stability, or Victoria performance gain.
Those require W2b and the later workload gates.

## 2. Hard Scope

In scope:

- the minimal generic `GatherContractionCause` result;
- fixed physical-slot, epoch-bearing binding, contribution, fence, receipt, and
  release authority types;
- fixed recovery and semantic-replay shells;
- deterministic desired FIFO, reservation, withdrawal, prior-authority, and
  derived-currentness state;
- one-shot callback lease authority and one mailbox-created paired port;
- per-binding FIFO retirement fence, pending retry, cleanup gate, predecessor
  ordering, SourceGate acceptance, receipt, release-once, tombstone, and fleet
  shutdown debt;
- dormant Darwin adapter migration and isolated real-stream proof;
- W2a repair-participant registry/projector mechanics;
- a later, explicitly deferred W2b atomic production cut.

Out of scope:

- production ingress changes before W2b;
- dynamic generic keys, generic per-key seal/retirement, per-source mailbox/task,
  a second product bus, or persisted shutdown debt;
- W3-W12 behavior, broad lint expansion, Victoria workload changes, Ghostty
  vendor work, or app-level performance claims;
- compatibility shims or a dual old/new callback route.

## 3. Live Mismatch To Remove

Current W1b/W2a code and the dormant adapter prototype still assume:

```text
FSEventRegistrationToken as generic key
separately injectable producer and signaler
reusable callback lease admission
per-generation mailbox seal/invalidate/finish
registration-keyed recovery evidence
one transferring/sealed mailbox generation
```

The implementation must hard-cut those dormant interfaces to:

```text
fixed FilesystemObservationPhysicalSlotID keys
complete epoch-bearing FilesystemObservationSlotBinding
one-shot held lease + mailbox-created paired port
per-binding FIFO retirement fence
fixed binding-aware recovery/replay shells
two started bindings + one newest desired identity
shutdown-only fleet seal
```

The untracked dormant adapter and its tests are adopted input, not disposable
scratch. Rewrite them through the planned interface cut; do not recreate or
silently overwrite their bounded native-capture work.

## 4. Vertical Slice WF-A — Credentialed Fixed-Slot Admission

### A — Typed generic contraction cause

Requirements: child Fixed Slot Identity and proof item 10.

Modify:

- `Sources/AgentStudio/Core/RuntimeEventSystem/Admission/AdmissionContracts.swift`
- `Sources/AgentStudio/Core/RuntimeEventSystem/Admission/BoundedGatherMailbox.swift`
- generic gather test support and exhaustive pattern matches
- `BoundedGatherMailboxTests.swift`
- `BoundedGatherMailboxAuthorityLifecycleTests.swift`

Hard cut:

```text
GatherContractionCause
  capacityPressure
  recoveryAuthorityExhaustedTransition
  ordinaryAdmissionAlreadySealed

contractedToRecovery(revision, cause)
```

The exact state-flipping offer returns the transition case; later offers return
already sealed. No other generic key, retry, cleanup, fairness, payload, or
lifecycle behavior changes.

RED: capacity contraction and authority exhaustion are indistinguishable.

GREEN: exhaustive cause table, transition/already-sealed seed tests, switch
migration, focused generic suite, scoped lint.

Split/replan: any implementation requires exposing private stamps or changing
generic retirement/key semantics.

### B — Fixed authority value contracts

Add a focused file such as:

- `FilesystemObservationSlotContracts.swift`

Keep observation/flag values in `FilesystemSourceTypes.swift`.

Define closed value contracts for physical slot, slot epoch, complete binding,
contribution identity, observation/fence contribution, desired intent,
retirement fence, retirement receipt, context-release acknowledgement, and
fleet admission/shutdown disposition. Opaque authority initializers remain
lexically private to their owners.

Tests/compiler fixtures prove:

- physical-slot or registration equality alone cannot authorize;
- stale epoch/binding/receipt/acknowledgement construction is impossible;
- checked identity exhaustion never aliases or wraps;
- no Optional or Boolean behavior selectors encode lifecycle alternatives.

Add the focused compiler harness:

- `scripts/verify-filesystem-observation-type-state-compiler.sh`
- `Tests/CompilerFixtures/FilesystemObservationTypeState/manifest.txt`
- manifest-owned positive controls and one exact negative fixture per forbidden
  authority/currentness construction

The verifier requires every manifest entry, matches an exact diagnostic class,
rejects unlisted fixtures, and runs through:

```bash
bash scripts/verify-filesystem-observation-type-state-compiler.sh
```

A and B may run in parallel because their write scopes are disjoint. Integrate
A before filesystem call sites compile against the new two-argument contracted
case.

### C — Binding-aware fixed recovery shells

Modify:

- `FilesystemRecoveryEvidenceRegister.swift`
- `FilesystemRecoveryEvidenceRegisterTests.swift`

Replace the registration dictionary with exactly P fixed physical-slot shells
whose bound states carry the complete slot binding and domain recovery-custody
identity. Generic recovery stamps remain current-custody metadata and may repeat
after transfer. Old binding/epoch/custody acknowledgement is a typed no-op.

RED/GREEN covers bind, record, join, snapshot, exact acknowledge, retire, equal
generic stamps across reuse, near-maximum domain authority, and stale operations.

### D1 — Desired FIFO, reservation, and configuration currentness

Add/modify:

- `FilesystemObservationSlotRegistry.swift`
- a focused source-configuration contracts file if placement requires it
- `FilesystemObservationSlotRegistryTests.swift`
- `FilesystemSourceConfigurationReceiptTests.swift`
- focused compiler fixtures/verifier for impossible receipt combinations

Implement the fixed P=S+R pool, unique desired-source FIFO, selected/starting
intent authority, in-place desired overwrite, reservation release, create/start
failure rotation, and withdrawal revalidation at pop/reserve/create/start.

Strict results distinguish:

```text
deferredRetainingCurrent
deferredNonCurrent
failedRetainingCurrent
failedNonCurrent
```

Aggregate currentness derives only from those cases. Safe N is retained only for
identical canonical root, source kind, authorization scope, event coverage, and
no discontinuity. Unsafe N closes before retry and never resurrects.

Proof uses successful vacancy-selection counts, never time. Run reserve 0/1/R/S,
N+3/N+4 overwrite, failure rotation, every withdrawal pause point, and the full
safe/unsafe × reserve/create/start matrix.

### D2 — Binding lifecycle and predecessor ordering

Extend the same registry under one integration owner, but keep a separate RED/
GREEN receipt for:

- vacant/reserved/accepting/closing states;
- two-started-plus-one-desired bound;
- predecessor-gated oldest-first retirement;
- exactly one predecessor-free pending fence intent per logical source;
- `retirementFenceTransferredAwaitingCleanup` remaining retiring,
  slot-occupying, predecessor-ordering, and non-reusable.

C and D1 may proceed in parallel after B because their production files are
disjoint. D2 production registry edits follow D1 under the same registry owner;
D2 test/oracle preparation may remain read-only or in separate test files. The
integration gate re-reads one exhaustive D1+D2 registry transition table.

`FilesystemObservationSlotRegistry` is a non-locking mutable state owner accessed
only while `FilesystemObservationMailbox` holds the wrapper coordination lock.
It never owns a second lock. Native create/start/stop/invalidate/barrier and
context release always execute with wrapper, recovery, and generic locks
released; only opaque reservations, drain receipts, retirement receipts, and
release acknowledgements cross that boundary.

### Atomic interface gate E/F1/G1 — Lease + paired port + dormant adapter

This is one compile-complete checkpoint, not three commits.

Modify together:

- `FSEventRegistrationControlBlock.swift`
- `DarwinFSEventRegistrationGeneration.swift` (new dormant native owner)
- `FilesystemObservationMailboxContracts.swift`
- `FilesystemObservationMailbox.swift`
- `DarwinFSEventObservationAdapter.swift`
- their focused tests and compiler fixtures

The gate:

1. makes a callback lease one-shot: admission available, admission consumed, or
   released;
2. adds the private nonescaping lease operation that verifies exact control
   block, registration, held/unused authority, and binding;
3. makes the mailbox factory create one paired admission port containing the
   exact doorbell operation;
4. removes the raw producer and independently pairable signaler surface;
5. keeps the lease held through offer and requested wake application, while
   releasing mailbox locks before signaling;
6. migrates the dormant adapter and all focused tests to the paired port.

The same native generation/control-block assembly owns the unforgeable
`FSEventRegistrationLeaseDrainReceipt`. Its close state performs:

```text
close new lease acquisition
-> stop/invalidate stream
-> callback-queue barrier
-> zero active callback leases
-> mint exact binding-specific lease-drain receipt
```

The receipt cannot mint before any phase, cannot be constructed by registry or
test code, and is the only authority F2 accepts for a fence request. A paused
paired signal keeps its lease active and prevents receipt minting. Atomic-gate
unit proof uses an injected barrier/native-generation fake; G2 later proves the
same order against a real Darwin stream.

`DarwinFSEventRegistrationGeneration` owns the real dormant stream, retained
`Unmanaged` callback context, control block, adapter/paired port, stop/invalidate,
callback-queue barrier, lease-drain receipt, and release-once operation. It does
not conform to `FSEventStreamClient`, publish `FSEventBatch`, or modify the
production Darwin client. W2b later makes `DarwinFSEventStreamClient` compose
this proven owner while deleting legacy `CallbackContext`.

F1 also owns the checked binding-local contribution sequence. Under the wrapper
lock it mints exactly one opaque contribution identity for each observation or
fence before the generic offer. Exhaustion cannot wrap: it closes/fences the
binding, records exact recovery, returns `contributionIdentityExhausted`, and
drives D1's non-current retry result before later admission. A new epoch starts
a disjoint sequence.

Required lock order is lease → wrapper → domain recovery/generic. Doorbell
application occurs after mailbox locks and cannot call back into lease, wrapper,
or control-block code.

Internal RED substeps are retained as receipts, but no checkpoint may expose both
raw and paired authority or leave the dormant adapter unable to compile.

GREEN:

- released/foreign/consumed/mismatched/fenced/closed cases produce no payload,
  evidence, or wake;
- contribution-identity exhaustion produces no contribution payload, records
  the exact binding recovery and non-current transition, and applies exactly one
  recovery wake before later admission is rejected;
- deterministic pauses after authority consumption and after offer prove
  release/drain/fence/recycle cannot pass the paired signal;
- raw producer/signaler and opaque authority construction fail compiler proof;
- bounded capture behavior from the existing adapter remains green;
- `FilesystemObservationCallbackScaleTests` proves paired-port admission,
  immediate synchronization, and doorbell application have the same maintained
  operation shape at 1/100/300 slots;
- receipt proof rejects missing phase, duplicate, foreign binding, and early
  minting; the paired-signal pause prevents zero-lease receipt;
- contribution proof covers concurrent uniqueness/order, observation/fence
  sequence, near-maximum exhaustion, exactly one exhaustion recovery wake, zero
  later custody/wake, exact recovery/non-current transition, and disjoint new-
  epoch sequence;
- generic custody is exactly
  `BoundedGatherMailbox<FilesystemObservationPhysicalSlotID,
  FilesystemObservationMailboxContribution>`; no registration-keyed declared or
  recovery map remains;
- callback contributions carry complete binding and contribution identity, and
  no per-binding teardown can seal/invalidate/finish the fleet mailbox/doorbell;
- production remains structurally wholly legacy.

Checkpoint: credentialed fixed-slot callback admission is dormant and green.

## 5. Vertical Slice WF-B — Retirement, Replay, Lifetime, Shutdown

### H1 — Fixed per-slot semantic replay shells

Add a focused owner such as:

- `FilesystemObservationSemanticReplay.swift`
- `FilesystemObservationSemanticReplayTests.swift`

One fixed shell per physical slot retains at most one generic lease quantum of
contribution identities and accepted-prefix dispositions. It matches exact
binding plus ordered identity vector across generic retry rotation and consumer
rebind, rejects stale consumer completion, and clears only after exact whole-
lease transfer.

RED/GREEN injects failure after every strict prefix for multiple slots
concurrently. Final semantic state equals one application, unrelated slots retain
fairness, and high-water never exceeds P × maximum contributions per lease.

### F2 — Retirement fence, contraction, cleanup, predecessor

Serial integration owner modifies the registry/mailbox/lifecycle files and adds:

- `FilesystemObservationRetirementFenceTests.swift`
- `FilesystemObservationMailboxLifecycleTests.swift`

Implement observation/fence FIFO, final-fence validation, distinct
`retirementFenceAdmissionContraction` evidence, one retained pending intent,
one eligible retry per acknowledgement/cleanup turn, and cleanup-before-semantic
lease/receipt. Pending intent never stands in for discarded observation repair.

RED/GREEN proves A→B→fence across lease quanta, contracted fence under queued
detail, cleanup custody, wake-after-unlock, and N/N+1 predecessor ordering.

### H2 — Exact SourceGate transfer and retirement receipt

Modify:

- `FilesystemSourceGate.swift`
- `FilesystemObservationLeaseTransfer.swift` (new task-free, non-actor semantic
  transfer component)
- a test-only `FilesystemObservationDrainHarnessActor` under the focused source
  test support directory
- SourceGate/actor/fence integration tests

The test harness actor owns the dormant assembly's one consumer/waiter and calls
the task-free transfer component. The transfer component preflights the whole
lease, uses H1 for idempotent semantic acceptance, synchronously obtains exact
binding-bearing SourceGate acceptance, and returns the complete transfer/retry
result. It owns no task, doorbell, actor, or second consumer.

Production `FilesystemActor.swift` remains structurally unchanged and wholly
legacy before W2b. At W2b, `FilesystemActor+ObservationIngress.swift` adds the
actor-isolated long-lived drain to the existing actor, making that production
actor the sole consumer atomically while deleting legacy ingress. No instance
can own both routes.

H2 is the sole owner of exact binding-bearing `FilesystemSourceGate` adaptation.
WF-C consumes the frozen API and does not edit `FilesystemSourceGate.swift`; any
newly discovered SourceGate change returns through the H2 integration owner.

Neither the harness actor nor the eventual production actor awaits scans, Git,
Bridge, MainActor, or filesystem I/O while holding a generic lease.

Only exact whole-lease transfer + semantic acceptance + SourceGate acceptance +
zero binding retry/cleanup debt can mint the final retirement receipt.

### D3 — Release-once, acknowledgement, tombstone, epoch reuse

Extend the native generation/control block and slot registry after H2 freezes the
receipt authority.

The native owner consumes the exact final receipt, releases retained callback
context once, then mints and retains the release acknowledgement. No other owner
can construct it. The registry applies it once, installs one fixed completion
tombstone, returns `alreadyApplied` for lost/repeated response while vacant, and
returns typed stale after reuse.

RED/GREEN uses explicit release counters and identity/state assertions; deinit is
not the oracle.

### F3 — Fleet shutdown debt and deterministic resume

Add:

- `FilesystemObservationFleetLifecycle.swift`
- `FilesystemObservationFleetLifecycleTests.swift`

Own typed completed/incomplete shutdown results. The snapshot references existing
slot/native/generic/replay/SourceGate/receipt owners and never duplicates payload
custody. Requester cancellation cannot cancel the internal drain. Explicit
resume and custody-completion events progress without a timer or new source
event. Only completed authorizes global seal, invalidation, and doorbell finish.

Parameterized RED/GREEN covers every debt class, including fleet generic
exhaustion. Persistence and silent invalidation are forbidden.

### G2 — Real dormant Darwin lifecycle integration

Add/extend:

- `DarwinFSEventObservationLifecycleIntegrationTests.swift`
- Darwin stream tests only as needed for the isolated assembly

Use a unique temporary local root and bounded event/state waits. Prove real
create/start, bounded native capture, close lease acquisition, stop/invalidate,
callback queue barrier, zero lease receipt, fence, SourceGate acceptance,
cleanup, final receipt, release-once acknowledgement, and context release.

The test uses no `Task.sleep`. If deterministic FSEvents delivery cannot pass in
the focused runner, move this unchanged obligation to the existing large native
integration lane; do not substitute simulated or sleep-based proof.

W1b dormant ready requires A, B, C, D2, atomic E/F1/G1, H1, F2, H2, D3, and
G2, plus structural proof that production remains wholly legacy. Adapter unit
tests alone are insufficient. D1 may already be green but is a W2a replacement/
configuration prerequisite rather than part of the single-registration W1b
lifetime receipt. F3 fleet shutdown is also W2a mechanics, not W1b readiness.

## 6. Vertical Slice WF-C — W2a Replacement And Repair Mechanics

Complete the isolated W2a system after WF-B:

- finish D1/D2 configuration/replacement integration against the real recycle
  receipts;
- add `WorktreeContentRepairConsumerRegistry.swift` and
  `FilesystemContentRepairProjector.swift`;
- consume the frozen exact binding-bearing `FilesystemSourceGate` acceptance
  API; WF-C does not edit the SourceGate owner;
- add participant registry/projector/integration tests.

The independent participant table covers pane/filesystem projection, Git, and
conditionally retained Bridge content. Applicability, late registration,
current, non-current-with-retry, not-applicable, withdrawal, replacement
transfer, rejection, and stale completion are exhaustive. UI disappearance is
never an acknowledgement; Git-only repair never returns a registered worktree
to healthy.

W2a mechanics complete requires WF-A/WF-B plus participant mechanics, replay,
replacement/currentness D1, cancellation/rebind, fleet shutdown F3, and repair-
participant proof. Production still uses only the legacy callback protocol.

Planned exact suites:

- `WorktreeContentRepairConsumerRegistryTests`
- `FilesystemContentRepairProjectorTests`
- `RegisteredWorktreeRepairIntegrationTests`

Each exact filter must discover at least one named test and the integration
oracle must enumerate the captured participants independently from production.

## 7. Vertical Slice WF-D — Deferred Atomic W2b Cut

W2b waits for W5 pane projection, W9 Git, W10 Bridge, and WF-C.

One integration owner changes together:

- `FSEventStreamClient.swift`
- `DarwinFSEventStreamClient.swift`
- `FilesystemActor.swift`
- `FilesystemGitPipeline.swift`
- boot/runtime composition
- controllable/silent fakes
- production watched-folder/repair integration and architecture tests

The pre-cut RED proves production is wholly legacy. The post-cut GREEN deletes
`FSEventBatch`, legacy callback `AsyncStream`, `CallbackContext`, old actor
ingress, and every bypass while installing the fixed fleet mailbox, adapter,
one actor drain, SourceGate, and exact live participant set in the same commit.

No feature flag, compatibility shim, partial migration, or fallback to legacy
delivery is allowed. If the cut fails, revert the complete W2b checkpoint.

W2b establishes product reachability and correctness eligibility only. Victoria
performance attribution remains a later W12/DQ1/IG2 gate.

## 8. Execution DAG And Write Ownership

```text
gate 0: verify HEAD, accepted hashes, dirty adapter/test, first RED inventory
  |
  +-- A generic contraction cause ------------------+
  |                                                 |
  +-- B fixed authority values ---------------------+
                                                    |
integration gate 1: A then B compile/focused GREEN -+
  |
  +-- C recovery shells ----------------------------+
  +-- D1 desired/currentness -> D2 lifecycle -------+
  |
integration gate 2: shared types/authority audit
  |
atomic interface gate: E + F1 + G1
  |
  +-- H1 semantic replay --------+
  +-- F2 retirement fence -------+
                                 |
                         H2 SourceGate/receipt
                                 |
                         D3 release/tombstone
                                 |
  +-- G2 real Darwin proof -> W1b dormant-ready gate -> WF-C participants --+
  |                                                                          |
  +-- F3 fleet shutdown ------------------------------------------------------+
                                                                             |
                                                   W2a mechanics-complete gate
                                 |
             W5 + W9 + W10 -----+
                                 |
                         WF-D atomic W2b cut
```

Safe parallelism:

- A || B;
- C || D1 after B; D2 follows D1 under one registry integration owner;
- H1 || F2 after the atomic interface gate;
- F3 || G2 after D3;
- participant-registry files may run beside actor work only after the exact
  SourceGate acceptance interface freezes and neither lane edits the other owner.

Serial choke points:

- generic contracted-case compile fanout;
- the E/F1/G1 authority interface cut;
- registry/mailbox lock-linearized integration;
- the single actor consumer/drain integration;
- W2b production cut.

No parallel lane edits `FilesystemObservationMailbox.swift`,
`FilesystemObservationSlotRegistry.swift`, `FSEventRegistrationControlBlock.swift`,
or `FilesystemActor.swift` through the same integration gate.

## 9. Requirements / Proof Matrix

| Claim | Source | Owner | RED/GREEN proof | Layer / freshness |
| --- | --- | --- | --- | --- |
| typed fleet exhaustion reaches exact fleet debt | child 102-151 | A + atomic F1 + D1 + F3 | A returns exact transition/already-sealed cause; F1 records one transition/wake and closes callback authority; D1 derives every source non-current; F3 retains exact exhaustion debt | unit/compiler/integration; current HEAD/hash |
| fixed binding rejects ABA | child 70-151 | B/C | equal stamp, old epoch/custody, near-max table | unit/compiler |
| callback admission is O(1) and credentialed | child 344-404 | atomic E/F1/G1 | held/released/foreign/consumed race; 1/100/300 operation count | unit/compiler/microbenchmark |
| desired replacement is fair and currentness strict | child 153-279; parent configuration | D1 | reserve 0/1/R/S, q+1 selections, withdrawal at four pauses, safe/unsafe matrix | unit/native integration |
| binding lifecycle is bounded and ordered | child 281-342 | D2/F2 | two started + desired, predecessor/pending fence, transferred-cleanup category | unit/integration |
| whole-lease retry is idempotent for many slots | child 498-524 | H1 | strict-prefix failure, rotation/rebind, P×lease bound | integration |
| contracted fence preserves intent and repair | child 450-560 | F2/H2 | capacity contraction, cleanup, SourceGate, final receipt | integration |
| native context release is causal and idempotent | child 334-342, 561-592 | D3 | release count one, receipt/ack replay, stale after reuse | unit/native integration |
| shutdown never loses debt | child 593-634 | F3 | every debt class, cancellation, resume without event/timer | integration |
| real Darwin lifetime matches receipts | child callback/fence contract | G2 | temporary root and explicit teardown ledger | real-boundary integration |
| repair health requires exact participants | parent repair matrix | WF-C | participant applicability/withdrawal/transfer table | unit/integration |
| production has exactly one ingress | hard-cut rule | WF-D | pre-cut legacy-only RED; post-cut fixed-only GREEN | structural/integration/smoke |

Every behavior/type/lint change requires named RED and identical-command GREEN.
Each receipt records HEAD, current accepted hashes, exact test names/counts,
command/exit code, independent oracle, and higher layer deferred/not applicable.
Broad substring filters that discover zero tests are failure.

## 10. Validation Gates

Per task:

1. exact focused unit/state/compiler RED then GREEN;
2. focused filesystem compiler verifier when authority/currentness types change;
3. scoped lint using Swift files only;
4. exact touched-suite integration;
5. checkpoint commit only after compile-complete local proof.

Combined pre-W2b gate:

```bash
mise run test -- --filter 'BoundedGatherMailbox'
mise run test -- --filter 'FilesystemObservation'
mise run test -- --filter 'FilesystemSourceGate'
mise run test -- --filter 'FSEventRegistrationControlBlock'
mise run test -- --filter 'DarwinFSEventObservation'
mise run test -- --filter 'FilesystemObservationCallbackScaleTests'
mise run test -- --filter 'WorktreeContentRepairConsumerRegistryTests'
mise run test -- --filter 'FilesystemContentRepairProjectorTests'
mise run test -- --filter 'RegisteredWorktreeRepairIntegrationTests'
bash scripts/verify-filesystem-observation-type-state-compiler.sh
mise run lint
mise run test-fast
```

The executor records actual discovered suite names and counts. Markdown spec/
plan files are validated with `git diff --check`; they are not passed to the
Swift-only scoped lint runner.

W2b additionally requires full focused integration, app smoke, current marker-
scoped observability, and structural legacy deletion. It still earns no final
performance claim.

No test uses `Task.sleep`. Ordering uses permanent value-free synchronization
seams, injected clocks, exact receipts, or event/state waits with bounded timeout
only for hang detection.

## 11. Security, Reliability, Rollback

- Untrusted FSEvent data never selects slot/binding/contribution authority.
- Exact lease/binding rejection occurs before native pointer inspection.
- Callback telemetry is aggregate and bounded; no raw paths, registrations,
  slot/binding IDs, errors, or payloads enter OTLP.
- Wrapper/lease lock order and signal-after-unlock are mandatory.
- `Unmanaged` context remains retained until final receipt and release-once.
- Fleet exhaustion is bounded actor work, not a callback fleet scan.
- A-I are dormant/isolated and may be reverted only as complete dependency-
  ordered checkpoints. Do not cherry-pick half of the interface or lifecycle
  integration gates.
- W2b rollback reverts the complete production hard-cut commit. A hybrid is
  never a recovery state.

Stop and return to planning/spec if:

- Darwin barrier + lease accounting cannot prove zero callback authority;
- paired authority requires raw escape, lock inversion, or a strong cycle;
- replay exceeds P × lease quantum or needs binding-lifetime history;
- generic FIFO/cleanup cannot prove fence finality without per-key lifecycle;
- SourceGate acceptance requires heavy await under generic lease;
- context acknowledgement cannot be minted after release-once;
- shutdown needs silent invalidation, persistence, or a second payload owner;
- W2b cannot delete every legacy bypass atomically.

## 12. Checkpoint And Review Rhythm

Allowed verified implementation checkpoints:

```text
A/B/C/D1/D2  compile-complete pure-owner commits
E/F1/G1      one atomic authority-interface commit
H1/F2/H2     proof-local commits with one integration owner
D3           release/tombstone commit
F3/G2        shutdown and real-Darwin proof commits
W1b          dormant integration receipt checkpoint
WF-C         W2a mechanics receipt checkpoint
WF-D         later atomic W2b production checkpoint
```

Do not commit red-only trees. Preserve RED evidence in the task receipt. Run an
implementation review after the authority interface gate, after W2a mechanics,
and after W2b. Lint codification remains last except compiler/access-control
proof required to make authority construction impossible.

## 13. Completion Boundary

This focused plan is complete when:

- W1b dormant-ready and W2a mechanics-complete receipts are current and reviewed;
- all owned unit/compiler/real-boundary proof and scoped/full relevant lint pass;
- production is still structurally wholly legacy;
- no raw producer/signaler or old per-generation seal plan/code remains in the
  dormant assembly;
- W2b remains explicitly blocked on W5/W9/W10 rather than partially wired.

The broader performance goal remains open. Product reachability, Victoria
baseline/candidate comparison, real-root qualification, native typing/cursor
feel, full validation, implementation review, and PR readiness remain later
gates owned by the parent plan.
