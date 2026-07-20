# S1 Admission Correction Plan

Status: focused strict type-state correction reviewed and ready;
implementation resumes only after the orchestrator records the official
transition

Source contract:

- [AgentStudio Performance Boundaries](../../specs/2026-07-10-agentstudio-performance-boundaries/agentstudio-performance-boundaries.md)
- [Focused S1 API Contract](../../../tmp/plan-workflows/2026-07-10-agentstudio-performance/s1-api-contract.md)
- [S1 Re-Review Synthesis](../../../tmp/plan-workflows/2026-07-10-agentstudio-performance/review/s1-admission-rereview/review-synthesis.md)

## Goal And Boundary

Correct the generic synchronous Admission primitives so physical payload and
dynamic-metadata custody remains bounded and observable through destruction,
latest-value overload preserves truthful `D/R/C` limits and delivery progress,
journal input/replay/cleanup is safe, and fixed-shape proof cannot be fooled by
uninstrumented scans.

This plan changes only generic S1 code, permanent S1 tests, the Admission clause
of the already-planned `RuntimeSignalPlaneRule`, and proof artifacts. It does not
wire filesystem, terminal, Ghostty, EventBus, Bridge, IPC, MainActor, or any
product runtime caller. It adds no actor, per-sample task, compatibility alias,
or second queue path.

## Source Coverage And Freshness

The parent must re-read the 1,845-line source contract, 770-line focused API
contract, superseding review synthesis, current Admission source/tests, and
staged/unstaged diff before editing. Accepted source hashes are:

```text
6282630cb420956073e279bb65a35189a54fb9bedddf692d2a22a8bc8adeb93a  maintained spec
7b312eaef20411b3d982fd99e0d427fbadbf00430e2ea6f7bf9fd99d901cac81  focused API
```

Existing green receipts are stale once any correction edit lands. Because HEAD
does not describe the dirty slice, every checkpoint also records a path-plus-
SHA-256 manifest for its owned source/test/lint files.

Security context: applicable. Payloads may later contain sensitive domain data,
so diagnostics and architecture fixtures expose only counts, bytes, ages,
bounded operation names, and static source identifiers. They never emit keys,
payloads, paths, terminal content, or runtime IDs.

## Write Scope

- `Sources/AgentStudio/Core/RuntimeEventSystem/Admission/**`
- `Tests/AgentStudioTests/Core/PaneRuntime/Admission/**`
- Admission protected-state clause and fixtures under
  `Tools/AgentStudioArchitectureLint/**`
- S1 proof/receipt/ledger files under
  `tmp/plan-workflows/2026-07-10-agentstudio-performance/**`

Do not edit product composition, existing runtime event wiring, filesystem,
terminal, Ghostty, MainActor, Bridge, IPC, persistence, or vendor files.

## Requirements / Proof Matrix

| ID | Requirement | Owning slice | RED/GREEN and evidence | Freshness guard |
| --- | --- | --- | --- | --- |
| S1-P0 | exact result/type hard cut, concrete doorbell, and protected-region vocabulary | S1a | compile RED plus capacity-one doorbell/coalescence/finish/capability tests | owned-file manifest; no compatibility result or mixed typed/untyped state |
| S1-L1 | latest `D/R/C` configuration, component pressure, physical equations, private protected wrapper, and lock-external clock | S1b | cleanup-free full-wave bound/bound+1, residual headroom, destructor and reentrant-clock proof; literal per-key/version/wake oracle | exact limits and current latest source hash |
| S1-L2 | cleanup-finalization reservation cannot starve or create a second lease | S1c | saturated-reserve producer/destructor barrier, final-batch wake, incumbent lease, and zero-eligibility histories | no sleeps, `Task.yield`, uncharged reservation, task, actor, or second queue |
| S1-L3 | latest retry is per value and wrapper overload/currentness is explicit | S1d | unsuperseded/superseded/residual/later-replacement histories; test-owned source/dirty/transferred revision ledger | generic policy contract only; concrete product wrapper remains unreachable |
| S1-G1 | gather cleanup/metadata is bounded and every recovery-slot advancement has fresh debt identity | S1e behavior plus S1h ownership clause | recovery-only/mixed 1/100/10,000 fleets, near-exhaustion old-ack history, payload-bearing root/tail mutation, independent payload deinit oracle, and structural weak-edge mutations | no production debug hook or counter-only proof; promotion depends on S1-E1 ownership proof |
| S1-J1 | one lexical private journal owner also owns binding, bounded history, clock sampling, and repair accounting | S1f | compiler/static privacy RED; bind/rebind, ring/indexed history, reentrant clock, gap-widening `repairEscalations`, and authority proof | no raw `State`, lock, token, `inout`, or generic closure escape |
| S1-J2 | journal snapshot/replay/cleanup custody is bounded and reader-safe | S1g | zero/max snapshot pressure; one-reader contention; queued/in-flight cleanup overlap; completion wake | exact capture stop tail; no partial mutation or lock-held materialization |
| S1-T1 | public and private Admission behavioral states are strict discriminated unions with no correlated optional, empty, Boolean, or result sentinel | S1t | permanent compiler-negative former-construction fixtures; exhaustive positive cases; family-specific nonempty custody; exact unlock-release/destructor proof; focused family and aggregate GREEN | spec/API hashes above; hard cut has no compatibility wrapper; S1h fixture/mutation baselines captured only afterward |
| S1-E1 | protected-state and private-metadata ownership lint fails closed across the settled helper graph | S1h | good/bad fixtures and restored-source mutations for rename/alias/unresolved/escape/unbounded traversal plus weak-to-strong shell, extra strong shell edge, and out-of-owner raw-state alias | pre/post mutation hash equality; one mutation active at a time |
| S1-I1 | cross-family behavior, diagnostics, and product-unreachable boundary remain intact | S1i | focused suites, strict typecheck, architecture scan, aggregate tests, lint, privacy canaries, caller/task/domain inventory | fresh current counts; old 102/21-test receipts cannot be reused |

P0 records only the current baseline, accepted hashes, owned-path manifests,
and stale-evidence inventory. It does not apply permanent test patches or claim
behavioral REDs. Every S1a–S1h behavior slice begins with its own permanent RED,
which must compile all unrelated slices and fail only for that slice's named
reason; the controller then implements that slice and records its local GREEN
before continuing. Production visit/hash/custody counters may corroborate but
are never the sole oracle. Smoke, native UI, WebKit,
observability, and performance proof are not applicable while S1 has no product
caller.

## S1a — Atomic Contracts, Concrete Doorbell, And Protected Vocabulary

Controller-owned production writes:

- `AdmissionContracts.swift`
- `AdmissionDoorbell.swift`
- `OrderedFactJournalContracts.swift`
- latest-specific result/limit declarations currently in
  `LatestValueMailbox.swift`
- concrete consumer/lifecycle port declarations in all three primitives

Controller-owned S1a tooling/test writes:

- the narrow token-declaration/signature clause in
  `RuntimeSignalPlaneRule.swift`;
- `RuntimeSignalPlaneRuleTests.swift` and token-shape good/bad fixtures;
- permanent separate-file Swift compiler fixtures plus one repo-owned verifier
  for approved-result, direct-construction, direct-return, storage, and
  compiler-accepted escaping-capture cases;
- a production/build-configuration no-experimental-feature guard.

These tooling writes do not discover family wrappers or inspect the protected
helper graph; those remain S1h-owned after the family grammar settles.

Hard-cut in one compiling checkpoint:

- `LatestValueLimits` with independent `D`, `R`, and `C`;
- `.physicalCapacityExceeded`, `.cleanupRequired`, `.alreadyCleaning`,
  `.blockedByReplayReader`, `.snapshotPhysicalCapacityExceeded`, and
  `.replayInProgress`;
- `AdmissionDiagnostics.rejectedCapacity`, typed latest/journal drain ages,
  queued/in-flight/physical diagnostics, and outstanding cleanup-turn state;
- one `AdmissionCleanupConsumer.performCleanup(generation:)` conformance for
  every concrete consumer and lifecycle port;
- the stable-language `AdmissionProtectedRegionToken: ~Copyable` vocabulary,
  a `borrowing` wrapper parameter, and an implicitly `Copyable`/`Escapable`
  wrapper result so direct token return or storage fails compilation;
- existing bind/doorbell result and authority contracts without a compatibility
  initializer or second cleanup API.

Implement the concrete payload-free, capacity-one, coalescing, finishable
doorbell with separate signaler, consumer, and owner capabilities. Capture the
compile/static RED for missing cases/conformance and the concrete doorbell RED
immediately before this slice. Restore standalone Admission typecheck, focused
test compilation, and age/doorbell/coalescence/finish/cancellation tests before
family behavior begins.

S1a also adds the syntax-stable token-shape clause to
`RuntimeSignalPlaneRule`: the token must remain `~Copyable`, the wrapper body
must receive it as `borrowing`, the result must not opt out of implicit
`Copyable`/`Escapable`, and direct initialization remains inaccessible. A good
standalone compiler fixture built with the real `AdmissionContracts.swift`
proves a wrapper may return an unrelated `Int`; separate bad fixtures compiled
by one repo-owned verifier against that real contract prove direct construction,
token return, and token storage fail by diagnostic category rather than exact
prose. The verifier uses fixed repo-owned argv and fixture paths without shell
interpolation and preserves exit plus diagnostic category in the receipt. A
compiler-gap fixture intentionally proves
that moving the borrowed token into an `@escaping` closure still compiles, so
capture remains an explicit S1h RED. Do not enable experimental `Lifetimes`,
use `~Escapable`, or add underscored lifetime attributes.

Stable Swift ownership does not by itself reject moving a borrowed noncopyable
token into an escaping closure. S1a therefore does not claim wrapper discovery,
capture rejection, or helper-graph closure. S1h structurally discovers each
owner's unique private wrapper from its token-factory call plus sole raw-lock
entry, rejects any additional factory call site, and owns the fail-closed rules
for token storage, escaping capture, indirect/function-value use,
protocol/dynamic dispatch, and generic/higher-order forwarding. S1a records
these rows as planned but not yet GREEN rather than weakening them or adopting
an experimental compiler feature.

The permanent no-experimental guard scans production Admission Swift sources
and build/package/task/workflow configuration only. It rejects
`-enable-experimental-feature Lifetimes`,
`.enableExperimentalFeature("Lifetimes")`, production `~Escapable`, and
underscored lifetime attributes. It excludes docs, receipts, and intentional
compiler/lint fixtures; a broader receipt scan is corroboration, not the sole
gate.

S1a may make only the minimum compile-restoration edits to family owner files
needed for the atomic type/port cut. S1b's exclusive latest behavior ownership
begins after that shared checkpoint; S1a does not implement family mechanics.

S1a defines the shared queued/in-flight/result vocabulary but does not claim
family-wide three-phase mechanics are GREEN. Latest owns that transition in
S1b/S1c, gather in S1e, and journal in S1g; S1i composes the cross-family
equations. Existing bind/rebind liveness remains a stale-regression gate.

## S1b — Latest `D/R/C` Custody And Component Pressure

Exclusive production owner: `LatestValueMailbox.swift`. Add new focused tests
rather than extending the already-large primary suite:

- `LatestValueMailboxCapacityTests.swift`
- existing latest, reentrancy, shared cleanup, and rebind suites for integration

As part of this slice, `LatestValueMailbox` becomes its one private raw state/
lock owner, enters that lock only through its private
`withAdmissionProtectedState` wrapper, and routes protected helpers through the
visible token contract established by S1a. Sample the injected monotonic clock
before entering protected state and prove a reentrant clock cannot deadlock or
mutate nested state. Direct raw `withLock`, token escape, and raw-state helper
access are negative grammar fixtures for S1h.

Implement and validate:

```text
D >= 1
C >= 1
cleanup == .entries(maximumEntries: C)
R >= checked(2 * D)
checked(K + R)

pending <= K
leased <= D
leased + queuedCleanup + inFlightCleanup <= R
physical = pending + leased + queuedCleanup + inFlightCleanup <= K + R
```

Latest cleanup implements the full three-phase transition in this family:
detach queued custody to one exclusive in-flight authority without decrement,
destroy at most `C` after unlock, then finalize counters/authority/wake under
the lock. Destructor-reentrant/concurrent cleanup returns `.alreadyCleaning`;
diagnostics and capacity remain charged until finalization.

An occupied-slot replacement projects the auxiliary component bound before
mutation. On pressure it preserves the existing accepted slot, ordering,
retention metadata, and wake; retains no incoming value; advances only
`offered/rejectedCapacity`; and returns `.physicalCapacityExceeded`. A
cleanup-free take forms at most `D`; terminal invalidation may move the valid
`K + R` state into cleanup but each turn remains bounded by `C`.

Permanent RED/GREEN histories prove one cleanup-free full `D` lease, `D`
refills, `D` admitted replacements, the next mutation-free rejection, transfer
preserving `leased + cleanup`, residual-cleanup headroom without a false full-
wave promise, checked capacity arithmetic at the `Int` boundary, and terminal
`K + R`. Use a literal key/version/wake ledger and deinit recorder; production
counters corroborate only. Split/replan if the
implementation collapses the three limits, needs another family edit after
S1a, samples its injected clock under the lock, lacks the private protected
wrapper graph, or cannot reject without partial mutation.

## S1c — Latest Cleanup-Finalization Delivery Progress

Same production owner as S1b; execute serially. Add
`LatestValueMailboxCleanupFinalizationTests.swift` plus shared doorbell/lifecycle
coverage.

After unlocked destruction, locked finalization may form one real pre-presented
lease of:

```text
min(D, pendingCount, R - remainingCleanupCount)
```

It does so only for open/sealed lifecycle, no incumbent lease, nonempty pending,
and positive computed size. The lease counts immediately as leased custody.
Finalization returns exactly one `.scheduleDrain` when it creates an unpresented
lease, including after the final cleanup batch. The next authorized take
presents it even while cleanup remains. Finalization during an incumbent lease
preserves its exact token/content, creates no second lease, and leaves newer
pending values pending.

Permanent deterministic histories cover saturated reserve with producer offers
during in-flight destruction, locked reservation before refill, final-batch
wake without another offer, seal, invalidation, rebind before/after reservation,
incumbent overlap, and every zero-eligibility branch. Use destructor/event gates,
not sleeps, `Task.yield`, polling, or elapsed-time inference. Split/replan if
progress requires an uncharged reservation, task, callback, actor, second queue,
or cleanup finalization outside the authoritative lock transition.

## S1d — Per-Value Latest Retry And Wrapper Currentness Contract

Same latest owner, executed after S1c. Add
`LatestValueMailboxRetryTests.swift` and permanent test-only wrapper/source
owners.

For each leased value on retry:

- if no newer same-key value is pending, revoke the acknowledged token and
  return the identical value to replaceable pending custody; cleanup-first
  service applies and a later same-key offer may replace it through charged
  cleanup;
- if a newer same-key value exists, move the older leased value to cleanup and
  preserve the newer pending value;
- neither branch increases auxiliary or physical custody or invokes user code.

The generic production contract exposes a compile-time overload disposition;
it does not own a domain recovery marker, callback, task, actor, or payload
queue. Permanent test types prove both dispositions. Lossy presentation makes
no authoritative-currentness claim. A test-owned authoritative wrapper holds
one bounded generation/key dirty revision and serializes source advance,
rejection recording, and transfer clearing. It clears only when
`dirtyRevision == transferredRevision == currentSourceRevision`; mutation REDs
remove each term independently. Concrete product wrapper activation remains
`deferred_unreachable` and must repeat the policy/currentness proof in its later
domain lane.

Histories cover unsuperseded, residual cleanup, later same-key replacement,
superseded mixed leases, old-token rejection, repeated rejection coalescence,
source advance between comparison and clear, rejection after comparison but
before clear, and generation rotation. Event barriers force both compare/clear
windows without yield or sleep. Permanent mutations independently remove each
predicate term and split comparison from clearing; a newer dirty revision must
survive. Split or route to the product lane if proof requires a real terminal/
filesystem owner.

## S1e — Gather Invalidated-Metadata Custody

Controller-owned production writes:

- `BoundedGatherMailbox.swift`
- `BoundedGatherMailboxMechanics.swift`
- `BoundedGatherMailboxAgeWatermark.swift` only if metadata-age combination
  changes
- optional `BoundedGatherMailboxInvalidatedCleanupStorage.swift` that owns
  non-raw cleanup storage only

`BoundedGatherMailbox` establishes its own private
`withAdmissionProtectedState` wrapper and unique direct token-bearing helper
graph in this slice. It also owns this family's full queued → exclusive
in-flight → finalized cleanup transition; cleanup remains capacity-charged
during unlocked bounded destruction, and concurrent or destructor-reentrant
cleanup returns `.alreadyCleaning`.

Keep raw gather `State`, lock, and token-bearing transitions in
`BoundedGatherMailbox.swift`. Convert `BoundedGatherMailboxMechanics.swift` to
pure mechanics over typed immutable inputs/results; it must not receive raw
`State`, `inout State`, the lock, or a protected token. Preserve clock sampling
before protected-state entry and add a reentrant-clock regression so this
structural move cannot reintroduce user code under the lock.

Replace the current detached `[KeyState]`/terminal-root lifetime with an O(1)
terminal ownership swap whose nontrivial recovery-only and mixed dynamic
metadata consumes cleanup entries. Payload and metadata share the entry quantum;
metadata contributes zero declared payload bytes but remains physically charged.
No invalidation or final turn may release a fleet array, page root, strong tail,
or cursor owning more than the configured entry quantum. Immutable declared-key
configuration/default shells remain outside dynamic cleanup custody.

Correct the four exact-hash review defects before refreshing S1e GREEN:

- add a pure checked gather-configuration validator and reject construction
  unless cleanup bytes can release the largest single footprint admitted by
  global, per-key, and lease bounds; remove cleanup bytes as a hidden admission
  limit from `fitsLeaseQuantum`;
- resolve a temporary/existing key state and complete recovery rollover
  preflight before creating or linking a dynamic retained node, so the
  unlocked epoch-preparation retry cannot publish uncharged empty metadata;
- enforce normative `takeDrain` precedence: generation, terminal lifecycle,
  binding, incumbent lease re-presentation/rejection, cleanup, then new
  lease/empty; invalidated cleanup remains serviceable only through
  `performCleanup`;
- build seeded constructor-local dynamic chains before lock publication without
  calling the protected token factory; the private lock wrapper is the sole
  token-factory root.

Add `BoundedGatherMailboxMetadataCustodyTests.swift`. Permanent RED/GREEN covers
recovery-only and mixed fleets at 1/100/10,000 slots plus a counter-neutral
production mutation that retains payload-bearing fleet root/tail custody until
the final turn. The independent weak/deinit payload oracle—not cleanup
counters—must fail that mutation and its receipt records mutant hash, failing
selector, inverse restoration, and restored hash. Private recovery-only
metadata lifetime is structurally proved by S1h; S1-G1 remains
`GREEN_PENDING_S1H` until that ownership clause passes. Each recovery-slot
advancement mints a fresh internal debt identity;
an exhausted acknowledgement for an older advancement cannot clear newer debt.
Prove generation and debt identity behavior at `UInt64.max - 1` and
`UInt64.max`, with typed terminal/rotation results, unchanged accepted custody,
and rejection of an older acknowledgement after rotation. Preserve the
accepted exact-or-
pressure-conservative age and O(1) diagnostic behavior. Split/replan if proof
needs raw-state escape, `#if DEBUG`, payload exposure, or allows a final fleet-
sized container deinit.

## S1f — Lexically Private Journal Storage Owner

The raw owner is exactly `OrderedFactJournal<Fact, Snapshot>` in
`OrderedFactJournal.swift`. Controller-serialize all journal production writes:

- `OrderedFactJournal.swift`
- `OrderedFactJournalContracts.swift`
- `OrderedFactJournalMechanics.swift`
- `OrderedFactJournalStateQueries.swift`
- `OrderedFactJournalPorts.swift` for typed concrete ports only;
- `OrderedFactJournalReplayMaterialization.swift` for immutable post-lock
  materialization only.

That one lexical owner contains nested private raw `State`, lock, cursors,
reader/lease/cleanup authority, its private `withAdmissionProtectedState`
wrapper, and every token-bearing protected transition. Token helpers are
private, uniquely named, non-overloaded direct calls. Journal clock sampling
occurs before entering protected state and has a reentrant-clock proof.
`OrderedFactJournalContracts.swift` retains value/result/configuration contracts
only. `OrderedFactJournalMechanics.swift` retains pure history mechanics only.
Remove raw-state extensions from `OrderedFactJournalStateQueries.swift`; move
owner transitions into `OrderedFactJournal.swift` or expose them through typed
ports. No other file may receive raw `State`, `inout State`, lock, token,
generic state closure, or unvalidated mutation authority.

Within this structural slice, bind/rebind authority re-presents both fact and
gap leases without changing their payload identity. Replace retained-history-
sized shifting and full scans under the lock with bounded indexed/ring history
and incremental pending/high-water state. Every gap widening increments
`repairEscalations` exactly once.

Capture the current privacy/static RED before moving behavior. Before S1g,
dynamically discover every Swift source under the Admission directory, then use
a journal-qualified syntax-aware classifier to prove exactly one raw journal
lock/state owner plus zero cross-file journal raw-state, raw-lock, or direct
journal-qualified token-bearing consumers. Other mailbox families' legitimate
private owners are not journal findings. A raw-free typed journal alias is
recorded for resolution and is not itself a violation; raw state/lock/token use
through that alias must fail. Do not rely on a fixed filename manifest, generic
substrings, or filename-prefix exclusions. Keep discovery separate from the
compiler privacy fixtures: discovery proves every current and future Admission
source was considered, while the fixtures prove another file cannot name or use
journal raw state or its lock. Mutations add an arbitrarily named production
Admission Swift file and separately exercise a direct journal-qualified token
consumer plus renamed/type-aliased journal raw access. Each mutation must fail
the actual production classifier or compiler gate, then restore its exact
existing-file preimage or absent-path/source-set precondition. The classifier
first builds one immutable directory-wide
Admission declaration/alias index, resolves journal aliases to a fixed point,
then emits per-file diagnostics. A two-file fixture places a raw-free journal
alias and its token/raw consumer in separately named files. The architecture-
lint command must pass the same parsed workspace index to the rule for production
scans; a per-file-only alias inventory is not sufficient.

For a newly injected source, record an `ABSENT` path precondition, the mutant
content hash, and a sorted Admission source-set manifest hash. Exact restoration
means the injected path is absent again and the source-set manifest hash matches.
Existing-file mutations retain exact pre/post file-hash equality.

The formatted `OrderedFactJournal.swift` owner may contain only raw-custody
responsibilities: nested private raw state, the raw lock, the private protected-
state wrapper, token-bearing protected transitions, and the private helpers they
directly require. Ports, public result/configuration contracts, pure history
mechanics, immutable captures, and post-lock materialization remain external and
raw-free. The owner has a 1,250-line hard ceiling shared by S1f and S1g. Record
the actual formatted S1f count as a structural baseline, not an immediate
ratchet, because S1g must add accepted raw snapshot/replay/cleanup transitions.
After S1g GREEN, record the final formatted count as the downward-only ratchet
for later slices; neither the ceiling nor the post-S1g ratchet may be raised
without another focused plan correction. At S1f, a whole-source implementation
review inventories current owner responsibilities so the ceiling cannot license
unrelated declarations. S1f does not claim declaration-shape lint can decide
whether a nested type, owner member, extension method, or raw-free private helper
is directly required. S1h owns that fail-closed responsibility closure after the
journal snapshot/replay/cleanup graph settles.

Restore all existing journal behavior and strict typecheck at this structural
checkpoint before adding snapshot/replay behavior. Split/replan if lexical
privacy requires exporting raw state, if any non-raw-custody responsibility
appears in the owner, or if the raw-custody-only owner exceeds 1,250 formatted
lines.

## S1g — Journal Physical Snapshot, Replay, And Cleanup

Against the settled private owner, implement:

- the journal family's full queued → exclusive in-flight → finalized cleanup
  transition, with capacity charged throughout unlocked bounded destruction and
  `.alreadyCleaning` for concurrent or destructor-reentrant cleanup;
- explicit individual plus physical snapshot count/byte limits, including
  zero-byte count and max-to-max replacement overlap;
- `.snapshotPhysicalCapacityExceeded` before sequence, fact, gap, currentness,
  snapshot, admitted/contracted/repair-counter, or wake mutation; an offer-side
  rejection advances only `offered` and `rejectedCapacity`, while authoritative
  recovery remains counter-neutral;
- construction rejects physical snapshot limits that cannot guarantee one
  checked maximum-size replacement overlap: count at least two and bytes at
  least `2 * maximumSnapshotBytes` without arithmetic overflow;
- exactly one replay reader and mutation-free `.replayInProgress` contention;
- global queued fact/snapshot cleanup pinning while the reader is active;
- incumbent pre-capture in-flight cleanup finalization with
  `.alreadyCleaning` precedence;
- `.blockedByReplayReader` for later queued cleanup and reader-completion
  eligibility wake;
- invalidation rejecting later capture while preserving an already captured
  result; replay materialization after unlock through the captured stop tail.

Add `OrderedFactJournalPhysicalCustodyTests.swift` and update existing journal
correction/mechanics/authority/support suites. Use literal snapshot/history/
gap/wake ledgers and destructor/capture gates. Cover zero/max/count/byte bound-
plus-one offer and recovery, queued/in-flight/reader overlap, second reader,
completion wake, cleanup-first `takeDrain`, maximum-size replacement overlap,
configuration overflow, negative sizes, and no partial mutation. Split/replan if the
design needs per-entry reader pins, cleanup-queue scans, blocking replay, another
queue, lock-held materialization, or causes the formatted raw-custody-only owner
to exceed the shared 1,250-line ceiling. Record the post-S1g formatted count as
the downward-only ratchet for all later slices.

## S1t — Strict Type-State Hard Cut Before S1h

Normative execution plan: [S1t Strict Type-State Correction Plan](s1-type-state-correction-plan.md).

S1-T1 requires public and private Admission behavioral states to be strict
discriminated unions, with no correlated optional, empty, Boolean, or result
sentinel. The standalone plan owns the complete RED, hard-cut, family-lane,
integration, mutation, stop, and GREEN proof requirements.

Gate: S1t must be GREEN_REVIEWED and committed before S1h begins.

## S1h — Fail-Closed Protected-State Helper Graph

Finalize the existing `RuntimeSignalPlaneRule` only after S1b–S1g settle. Keep
its existing registry name. Replace the manual declaration-name manifest with a
SwiftSyntax-resolvable graph that:

- discovers every raw-lock closure;
- structurally discovers each owner's unique private protected-state wrapper
  from its token-factory call plus sole raw-lock entry and rejects any additional
  factory call site, without a wrapper/helper name manifest;
- follows visible region-token arguments through unique private direct calls;
- builds a bounded journal owner declaration graph from two independent root
  classes: custody roots are the structurally discovered raw state, raw lock,
  and protected-state wrapper; entry roots are journal constructors plus journal
  members invoked by the concrete typed ports in
  `OrderedFactJournalPorts.swift`. Port-call discovery is syntax-resolved through
  the directory-wide index and is not a manual method-name manifest;
- separately admits raw-free journal-extension accessors whose single expression
  constructs one discovered concrete typed port with `journal: self`. These
  accessors are neither custody nor entry roots, may not touch raw state/token/
  lock, and may perform no additional work;
- follows forward-reachable unique private callees from those roots. Reverse
  reachability may prove an independently discovered entry reaches custody, but
  a token-bearing method or reverse caller does not become a root merely by
  touching the wrapper. Nested types are admitted only when referenced by raw
  custody or an admitted helper;
- rejects disconnected nested declarations, owner members, and journal-
  extension methods so the 1,250-line ceiling cannot license unrelated work;
- fails on zero/multiple/overloaded/unresolved targets, indirect references,
  token storage/return/escape, escaping capture, higher-order forwarding,
  raw-state escape, and unsupported raw aliases;
- rejects unquantified traversal/materialization independent of field spelling
  unless a typed lease/cleanup quantum structurally dominates it;
- retains coverage when a helper is renamed;
- discovers configuration-lifetime slot-index shells and rejects a strong
  dynamic-node edge, a second strong shell edge, or a strong raw-state alias
  outside the declared live head/tail or bounded cleanup owner.

Prepare disjoint good/bad fixtures and mutation designs early, but the
controller applies and restores one production mutation at a time after source
grammar settles. Required mutations cover uncounted/aliased journal history,
previously masked journal traversal/currentness assertions, epoch rotation,
`UInt64.max` authority rotation/non-aliasing, non-hash gather fleet work, latest
retention-order scan, helper rename, ambiguous overload, indirect function
value, generic forwarding, raw-state alias, direct raw lock, and token escape.
The journal responsibility mutations also cover an unrelated nested declaration
and an unrelated same-file journal-extension method; both must be disconnected
from the bounded custody graph and rejected without a helper-name allowlist.
Add a connected-but-unnecessary extension mutation that calls the protected
wrapper and a private token helper: it must still fail because no concrete typed
port establishes it as an entry root. Current replay and private custody helpers
must remain green after rename.
Add a good fixture for producer/consumer/lifecycle single-expression port
factories and a bad fixture where the same accessor shape performs extra work or
touches raw custody; the latter must fail without promoting the accessor to a
root.
The restored-source ownership mutations additionally cover weak-to-strong
`DeclaredSlotShell.retainedNode`, another strong node property on that shell,
and a strong dynamic-node alias in raw state outside recognized live/cleanup
ownership.
Every receipt records pre-hash, failing command and content-safe diagnostic,
verified inverse restoration with matching hash, and fresh GREEN. S5 later adds
product fact/sample clauses to this same rule; it does not preserve a manifest
or create a third rule.

The S1h fixture set includes a copyable-result approved wrapper plus negative
factory-call-outside-wrapper, token capture, token return/storage, indirect
function value, and generic forwarding cases. The rule must reject the capture
case that stable `~Copyable` ownership alone permits. It must not depend on the
experimental Swift `Lifetimes` feature or semantic compiler resolution.

## S1i — Cross-Family Integration And Completion Review

Update controller-owned shared cleanup, rebind, diagnostic privacy, and support
tests only after all family owners settle. Prove every concrete consumer and
lifecycle port conforms, all diagnostics are content-free, in-flight custody is
charged, and bind/rebind/doorbell levels remain executable.

Add an S1i-owned permanent `AdmissionDiagnosticPrivacyTests.swift` suite and a
content-canary receipt scan. Use unmistakable synthetic tokens representing a
key, value/payload, path, runtime ID, pointer, and terminal text. Exercise every
public Admission diagnostic/result description and architecture-lint failure
shape, and scan captured RED/GREEN command output plus the final correction
receipt. Acceptance requires zero sentinel matches in diagnostics, lint
messages, command output, and receipts; test fixtures may hold the synthetic
inputs but no sink may reproduce them. This mechanical gate supplements the
typed content-free fields and static-source-only lint locations.

Run each focused suite independently, strict standalone Admission typecheck,
architecture-lint package tests and production scan, aggregate Admission tests,
scoped format/diff checks, `mise run lint`, `mise run test`, and a fresh whole-
tree negative caller/domain/task/second-queue inventory. Report discovered
counts; never reuse the old 102-test or 21-test receipts. Finish with a focused
source-backed `implementation-review-swarm`. S1 remains incomplete until all
accepted findings are disposed and product reachability is still explicitly
`deferred_unreachable`.

The final receipt must also record a mechanical zero-match gate for both
`Task.sleep` and `Task.yield` under
`Tests/AgentStudioTests/Core/PaneRuntime/Admission/**`. Deterministic event,
destructor, clock, and capture barriers are the only authorized concurrency
proof. S1i repeats checked collection/capacity arithmetic near `Int.max`, plus
binding, lease, recovery, gap, generation, and sequence authority rotation at
`UInt64.max`, and non-hash fleet-work mutation proof so a family-local GREEN
cannot mask their cross-family integration.

## Execution DAG

```text
G0: verify HEAD, dirty scope, accepted hashes, stale evidence
  |
P0: capture baseline, owned-path manifests, and stale-evidence inventory only
  |
S1a RED -> atomic shared contracts/doorbell/token vocabulary -> S1a GREEN
  |
S1b RED -> latest D/R/C and component pressure -> S1b GREEN
  |
S1c RED -> latest cleanup-finalization progress -> S1c GREEN
  |
S1d RED -> latest retry/currentness -> S1d GREEN
  |
S1e RED -> gather metadata/debt custody -> S1e GREEN_PENDING_S1H
  |
S1f RED -> private journal owner/binding/history -> S1f GREEN_PENDING_S1H
  |
S1g RED -> journal snapshot/replay/cleanup -> S1g GREEN
  |
S1t RED -> strict public/private type-state hard cut -> S1t GREEN_REVIEWED
  |
S1h RED -> graph/ownership lint and mutations -> S1h GREEN
  -> promote S1-G1 and S1-J1 with S1-E1
  |
S1i: cross-family integration and current proof
  |
focused implementation-review-swarm
```

Read-only oracle/review preparation may run in parallel. Outside the explicit
S1t shared-shell plus disjoint family-lane exception, the controller applies
test patches, captures RED, edits production, restores mutations, and updates
proof one slice at a time; Admission production and test writes are not
parallelized. The lint owner may design fixtures early,
but edits/final parity wait for the Admission helper grammar to freeze. S5
product-signal extensions wait for the completed S1 handoff.

## Checkpoint And Proof Commands

The controller discovers exact suite names, then records commands and exit codes
for:

1. each latest, gather, journal, and doorbell suite independently;
2. aggregate `mise run test -- --filter Admission` through the repo build-slot
   wrapper, with exact suite accounting; focused selectors use the same wrapper;
3. strict Swift 6 standalone Admission typecheck;
4. focused architecture-lint rule/fixture tests plus production scan;
5. scoped recursive `swift-format` and `git diff --check`;
6. `mise run lint`;
7. `mise run test`, with scope-external failures reported separately rather than
   repaired through S1;
8. whole-tree negative product/domain/task/caller/second-queue inventory;
9. mechanical zero-match checks for `Task.sleep` and `Task.yield` under the
   complete Admission test subtree;
10. the permanent diagnostic privacy-canary suite plus a zero-sentinel scan of
    public diagnostics, lint messages, captured RED/GREEN output, and the final
    correction receipt;
11. focused source-backed `implementation-review-swarm`.
12. the permanent strict type-state compiler verifier plus a production and
    ordinary-Admission-test absence scan for the enumerated forbidden syntactic
    forms. The intentional compiler fixtures, one-at-a-time mutation artifacts,
    docs, and receipts are excluded; the verifier, not a vague vocabulary grep,
    is authoritative for negative fixtures.

No earlier green receipt is accepted after a correction edit. S1 is committable
only when every matrix row is current, no blocker/important finding survives,
and product reachability remains explicitly `deferred_unreachable`.

## Recovery And Split Triggers

Do not revert the pre-existing dirty worktree. Treat every controller write as a
preimage → expected-postimage transaction. Immediately before applying the
controller patch, capture each owned file's preimage/hash. Compute the expected
postimage only from that preimage plus the controller patch, then verify the
actual post-hash equals the expected post-hash; any same-file concurrent/user
edit makes the transaction diverge and stops for manual reconciliation. Record
the exact controller-only forward delta. Rollback is allowed only when current
hashes still equal the recorded expected-postimage hashes and the inverse patch
passes a reverse-apply check; then apply only that verified inverse. After
rollback, prove the recorded preimage hashes are restored and every pre-existing
dirty path outside the controller delta is unchanged. Checkout, reset, hash-
based whole-file replacement, or any other restoration that can erase
concurrent/user changes is forbidden. If a slice cannot keep the public
contract atomic, stop before the
next owner and return to spec/plan work before more code when bounded cleanup
requires producer-side domain computation, replay cannot
preserve exact stop-tail semantics without unbounded protected work, the
architecture rule needs a broad allowlist, or proof cannot distinguish a real
scan from bounded quantum work.

Also split/replan if token non-escape requires experimental `Lifetimes`,
`~Escapable`, or underscored lifetime attributes instead of the accepted stable
ownership plus fail-closed SwiftSyntax split.

Do not solve those failures with an actor mailbox, per-offer task, enlarged
unbounded capacity, compatibility path, weakened proof, or product wiring.
