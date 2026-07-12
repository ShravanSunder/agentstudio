# S1t Strict Type-State Correction Plan

Status: focused review READY; execution remains gated pending the official
transition

Source contract:

- [S1 Admission Correction Plan](s1-admission-correction-plan.md)
- [AgentStudio Performance Boundaries](../../specs/2026-07-10-agentstudio-performance-boundaries/agentstudio-performance-boundaries.md)
- [Focused S1 API Contract](../../../tmp/plan-workflows/2026-07-10-agentstudio-performance/s1-api-contract.md)
- [S1 Re-Review Synthesis](../../../tmp/plan-workflows/2026-07-10-agentstudio-performance/review/s1-admission-rereview/review-synthesis.md)

Execution/proof context:

- The parent requirements/proof matrix remains normative for S1-T1.
- Execute the complete section below, including every RED, hard-cut, lane,
  integration, mutation, stop, and GREEN proof requirement.
- S1t must be GREEN_REVIEWED and committed before S1h begins.

## S1t — Strict Type-State Hard Cut Before S1h

S1t is a focused correction discovered after S1g review and must settle before
S1h records declaration/call/type baselines. It changes representation only;
all accepted capacity, custody, counter, wake, replay, currentness, and
performance semantics remain identical. Product reachability remains zero.

### S1t RED — Permanent compile-time rejection

Controller-owned shared writes:

- `AdmissionContracts.swift` and, when separation keeps files readable, one
  new `AdmissionTypeStateContracts.swift` for generic nonempty/cleanup algebra;
- `AdmissionDoorbell.swift` and `AdmissionDoorbellTests.swift`;
- `Tests/CompilerFixtures/AdmissionTypeState/**`;
- one fixed-argv `scripts/verify-admission-type-state-compiler.sh` verifier;
- `AdmissionSharedContractTests.swift` plus a focused new
  `AdmissionTypeStateContractTests.swift`;
- `AdmissionAgeMeasurementTests.swift`, `AdmissionCleanupCustodyTests.swift`,
  and `AdmissionRebindDoorbellCompositionTests.swift`;
- shared test-support migrations only inside those explicitly controller-owned
  files.

Before changing production contracts, add permanent bad fixtures written
against the committed S1g API. The verifier expects each fixture to fail strict
Swift 6 typecheck after the cut, so the pre-cut RED is that these forbidden
forms still compile:

- rejected latest or gather offer paired with `.scheduleDrain`;
- cleanup quantum/release using `nil` to select entry-only behavior;
- gather contracted admission without recovery revision;
- gather ordinary lease with zero contributions and no recovery;
- immediate replay result paired with wake;
- latest or ordered successful drain with empty payload, `nil` age, or
  pressure-conservative age;
- journal initialization with independently supplied snapshot absence and byte
  count.

Maintain one checked fixture-manifest row per forbidden construction. Every row
has two independent controls: a legacy fixture that compiles against the S1g
preimage and is absent after the hard cut, plus either a current-API negative
fixture or one-at-a-time production mutation proving the equivalent illegal
state cannot be expressed with the new types. Each current negative has a
nearby positive current-API control and an expected diagnostic category; API
deletion alone cannot satisfy the row. Enumerate independently:

- latest rejected offer with wake and gather rejected offer with wake;
- cleanup quantum with nil bytes and cleanup release with nil bytes;
- contracted gather admission without revision and empty ordinary gather lease;
- immediate public replay completion with wake;
- private immediate replay capture with reader authority and registered capture
  without reader authority;
- latest empty drain, missing-age drain, and conservative-age drain;
- ordered empty fact drain, missing-age drain, and conservative-age drain;
- split journal initial snapshot and byte count;
- each family unavailable cleanup outcome carrying authority or custody;
- each family detached cleanup outcome carrying empty custody;
- latest rejected offer capture without incoming value and accepted capture
  carrying a release value;
- gather recovery stamp without custody identity and custody identity without
  stamp;
- doorbell pending-plus-waiting and finished-plus-pending/waiting products;
- latest no-drain plus awaiting-initial/awaiting-rebind presentation and any
  presentation state without its associated active drain.

Capture the verifier's exact unexpected-success inventory and exit code. Add
positive compile/runtime tests for every new case. The old forbidden
construction compiling is the RED oracle; the paired current negative proves
the new algebra, not mere symbol deletion.

### S1t shared contract cut

Hard-cut, without deprecated aliases, convenience initializers, optional
projection properties, or dual result paths:

- `LatestValueOfferResult` and `GatherOfferResult` become enums whose admitted
  cases alone carry wake;
- `GatherAdmissionDisposition` becomes retained,
  retained-with-recovery, or contracted-to-recovery-with-revision;
- `NonEmptyAdmissionBatch(first:remaining:)` owns successful latest values,
  gather contributions, ordered fact drains, and homogeneous cleanup custody;
- gather drain payload becomes nonempty contributions, nonempty contributions
  with recovery, or recovery-only;
- `AdmissionCleanupQuantum` and `AdmissionCleanupRelease` become exhaustive
  entry-only versus entry-and-byte cases; `AdmissionCleanupTurn` carries the
  release case plus wake;
- latest and ordered successful drains carry dedicated `ExactAdmissionAge`,
  which cannot represent missing or pressure-conservative precision;
- ordered replay splits immediate result/no-wake from registered result/wake in
  both private capture and public completion;
- journal initialization accepts one optional bundled
  `OrderedFactSnapshotReplacement`, never snapshot and byte count separately;
- opaque mailbox, binding, and lease epoch identity remains intact;
- doorbell storage and its public state snapshot become one closed state enum:
  idle, signal-pending, consumer-waiting, or finished;
- latest active-drain absence and presentation become one closed state enum:
  no active drain, presented drain, awaiting-initial-presentation drain, or
  awaiting-rebind-presentation drain.

All call sites switch exhaustively over the new cases. Tests do not add helper
properties that recreate the removed correlated optionals.

Doorbell legacy fixtures construct pending+waiting and finished+pending/waiting
snapshots/states against the S1g preimage. Current negative controls attempt to
attach waiter/pending data to the wrong single enum case and must fail by
associated-value diagnostic; positive runtime ledgers cover idle → pending →
idle, idle → waiting → idle by signal/cancellation, and idle/pending/waiting →
finished. Latest active-drain correlation is private, so controller-owned
one-at-a-time source mutations attempt no-drain+awaiting-initial,
no-drain+awaiting-rebind, and a presentation state without associated drain.
Bind/rebind, cleanup-finalization reservation, acknowledgement, and invalidation
tests are the positive controls. Every mutation records pre-hash, failing strict
typecheck diagnostic, verified inverse, and restored hash.

### S1t family implementation lanes

After the controller lands the shared contract shell, three high-effort lanes
may run in parallel because their write sets are disjoint:

```text
latest lane
  writes only:
    LatestValueMailbox.swift
    LatestValueMailboxTestSupport.swift
    LatestValueMailboxTests.swift
    LatestValueMailboxCapacityTests.swift
    LatestValueMailboxCleanupFinalizationTests.swift
    LatestValueMailboxRetryTests.swift
    LatestValueMailboxReentrancyTests.swift
    LatestValueMailboxAuthoritativeCurrentnessTests.swift

gather lane
  writes only:
    BoundedGatherMailbox.swift
    BoundedGatherMailboxMechanics.swift
    BoundedGatherMailboxAgeWatermark.swift
    BoundedGatherMailboxTestSupport.swift
    BoundedGatherMailboxTests.swift
    BoundedGatherMailboxConfigurationTests.swift
    BoundedGatherMailboxAuthorityLifecycleTests.swift
    BoundedGatherMailboxMetadataCustodyTests.swift

journal lane
  writes only:
    OrderedFactJournal.swift
    OrderedFactJournalContracts.swift
    OrderedFactJournalMechanics.swift
    OrderedFactJournalStateQueries.swift
    OrderedFactJournalPorts.swift
    OrderedFactJournalReplayMaterialization.swift
    OrderedFactJournalTestSupport.swift
    OrderedFactJournalTests.swift
    OrderedFactJournalCorrectionTests.swift
    OrderedFactJournalMechanicsTests.swift
    OrderedFactJournalAuthorityTests.swift
    OrderedFactJournalPhysicalCustodyTests.swift

controller integration
  writes only the controller-owned shared files named above, compiler
  fixtures/verifier, proof receipts, formatting, and final conflict reduction
```

S1t is the sole exception to the general no-parallel Admission-write rule. The
controller applies one uncommitted shared-shell transaction and never commits
that compile-RED intermediate state. Family lanes edit only their allowlists,
do not edit shared files, do not run package/test proof concurrently, and do not
claim GREEN. The controller makes no opportunistic family-file edits while they
run. After all three receipts return, the controller inspects and integrates
every diff, resolves shared tests serially, runs all proof, and commits one
atomic GREEN S1t checkpoint.

Each owner replaces its cleanup detach product with exhaustive unavailable
cases plus `.detached(authority:nonemptyCustody)`. Family custody is
structurally nonempty: latest/gather use first+remaining; journal uses nonempty
facts, nonempty snapshots, or both. Unlock destruction changes the private
execution value from detached custody to released authority before the next
protected-state entry. It does not use optional custody, empty arrays, or
`.empty` as the phase discriminator. Diagnostics remain charged until the
released-authority finalization.

Every producer outcome that does not retain incoming generic data keeps it
alive through protected-state exit and explicitly releases it before any later
protected-state entry. Cover latest rejection, gather rejection and contraction
to recovery, and ordered fact/snapshot rejection or contraction. Never-accepted
input does not become cleanup custody. Deterministic destructor-reentrant tests
prove the lock is not held and no nested attempt mutates partially.

The release proof uses this exact row matrix:

```text
latest rejected value
gather rejected contribution
gather contribution contracted to recovery
ordered rejected fact
ordered rejected snapshot
ordered gap contraction with discarded fact
latest detached cleanup custody
gather detached cleanup custody
journal detached fact cleanup custody
journal detached snapshot cleanup custody
```

Each row owns a direct temporary payload plus entered/release/completed gates,
one reentrant operation, and a literal mutation/counter/wake ledger. It proves
the reentrant operation completes while release is gated (raw lock exited),
exact deinit count/order, no partial mutation for never-accepted input, charged
custody/authority throughout accepted cleanup destruction, and finalization/wake
only after release. Ordered atomic fact+snapshot rejection records their
destruction separately. No elapsed-time, eventual-deinit, or production-counter-
only oracle satisfies a row.

Internal gather recovery stamp plus custody identity also becomes one optional
typed reference wherever they must co-exist; independent stamp-only immutable
snapshots remain separate. Preflight inventories every Admission private/public
transition or stored state that combines an enum/Boolean discriminator with an
optional/empty companion. Any additional correlated behavioral state triggers
the existing S1t split/reconvergence rule; it is not silently exempted.

### S1t integration and mutation proof

The controller integrates family lanes and updates every ordinary assertion to
switch on the exact case. The production/ordinary-test absence scan enumerates
forbidden syntactic forms and excludes intentional
`Tests/CompilerFixtures/AdmissionTypeState/**`, mutation artifacts, docs, and
receipts. Apply one source mutation at a time to attempt empty
detached custody in latest, gather, and journal, plus immediate replay with a
wake and the three latest active-drain/presentation illegal products above.
Strict typecheck must fail for the named construction; restore exact preimage
hashes before the next mutation. Doorbell forbidden-form scans include the old
three-field Boolean/optional storage and snapshot products; latest scans include
independent `activeDrain?` plus presentation storage. The journal owner remains
at or below the post-S1g 1,250-line downward-only ratchet; representation
cleanup must not raise it.

Required GREEN:

1. permanent type-state compiler verifier, every manifest row satisfied by its
   paired legacy/current oracle and positive control;
2. `mise run test -- --filter AdmissionTypeStateContractTests`;
3. `mise run test -- --filter AdmissionLatest`;
4. `mise run test -- --filter AdmissionBoundedGatherMailbox`;
5. `mise run test -- --filter AdmissionOrderedFactJournal`;
6. individual shared selectors: `AdmissionAgeMeasurementTests`,
   `AdmissionCleanupCustodyTests`, `AdmissionRebindDoorbellCompositionTests`,
   `AdmissionSharedContractTests`, and `AdmissionDoorbellTests`;
7. `mise run test -- --filter Admission` with fresh aggregate count;
8. strict standalone Admission typecheck;
9. architecture package tests and production scan;
10. scoped format/SwiftLint, `git diff --check`, and `mise run lint`;
11. one focused spec-compliance review and one code-quality/reliability review;
12. exact source/test manifest, scoped forbidden-form absence scan, mutation
    restoration hashes, and proof receipt.

Every focused selector must exit zero and report an executed test count greater
than zero. SwiftPM compiles the whole test target, so a family selector proves
selection and behavior, not isolated family compilation. The aggregate run is
the integration gate. Receipts record the command, exit code, executed count,
and named suites for every row.

Split/replan if a valid runtime state cannot be represented without a
correlated optional, if nonempty custody requires a runtime-only assertion, if
explicit unlock destruction cannot be proven without optional/empty sentinels,
if a family needs a compatibility path, or if the journal ratchet would rise.
Do not begin S1h until S1t is GREEN_REVIEWED and committed.
