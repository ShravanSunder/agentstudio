# Reactive Atoms and Derived Values — Program Design

Artifact type: program design — structural How
Target classification: general-domain
Governing specification:
[Reactive State System Requirements](2026-07-31-reactive-state-system-requirements.md)
Governing specification SHA-256:
`1aee657052b6e475767215bf613765c5056465f4920b0e178e5e0fb008809a39`
Source version: `50d0b0ac360af8b1fe2f62a56e35b5cd2cd8e515`

## 1. Decision Summary

AgentStudio keeps Swift Observation and its bottom-up product atom graph.
The target model has three independent relationships:

1. `AtomGroup` describes domain ownership and organization. It is vocabulary,
   not a generic runtime type.
2. `AtomFamily<Key, Value>` is the reusable source primitive for the same
   independently observable value shape repeated by key.
3. `DerivedAtom<Value>` is a stored, stable, lazy computation node over
   declared source revisions.

The current `AtomEntityMap` becomes `AtomFamily` through a hard rename. The
current `DerivedValue` becomes the basis of `DerivedAtom`, but product owners
must retain derived nodes instead of reconstructing them through computed
properties.

Keyed state is not automatically a family. A family is selected only when one
key changes independently and a consumer has a legitimate key-scoped read.
Cross-entity invariants remain under one coherent domain owner, which may
combine keyed member slots with an aggregate membership or topology revision.

```mermaid
flowchart LR
    subgraph Group["CoreAtoms — concrete domain group"]
        PaneOwner["WorkspacePaneGraphAtom"]
        TabOwner["WorkspaceTabGraphAtom"]
        RepoOwner["RepoEnrichmentCacheAtom"]
        DerivedOwner["retained product DerivedAtom nodes"]
    end

    RepoOwner --> RepoFamily["AtomFamily<RepoID, RepoEnrichment>"]
    RepoOwner --> WorktreeFamily["AtomFamily<WorktreeID, WorktreeEnrichment>"]
    RepoOwner --> CountFamily["AtomFamily<WorktreeID, Int>"]

    WorktreeFamily --> Facts["DerivedAtom<RepoWorktreeCacheFacts?>"]
    CountFamily --> Facts
```

## 2. Structural Crux

The crux is not whether AgentStudio should have smaller state. It is where an
observation boundary belongs:

- at one independently changing key;
- at one coherent aggregate whose invariants cross keys; or
- at one derived computation whose output has its own stable cache identity.

Treating every collection as one observable value causes unrelated consumers
to wake. Treating every property as an atom makes coherent mutations and
persistence harder to reason about. The selected structure uses entity-sized
family members for independently hot facts while preserving aggregate owners
for membership, ordering, and cross-entity invariants.

### 2.1 Alternatives considered

| Alternative | Benefit | Cost and failure mode | Disposition |
|---|---|---|---|
| Keep collection-backed atoms and uncached readers | No migration | Broad invalidation and repeated reconstruction remain implicit | Rejected for selected hot surfaces |
| Make every property an independent atom | Maximum theoretical precision | Explodes mutation, lifecycle, and invariant coordination | Rejected |
| Replace Swift Observation with a new graph runtime | One framework could own all semantics | Large migration, new runtime authority, target risk | Rejected |
| Use entity-sized source families plus retained derived nodes | Precise keyed reads with coherent owners and explicit computation | Owners must expose semantic revisions and prune keyed nodes | Selected |

The choice should be revisited only if measurement shows an entity-sized slot is
still too broad for a specific independently hot fact. That evidence would
justify a second family for that fact, not a universal property-atom rule.

## 3. Current-System Model

### 3.1 Current source family

`AtomEntityMap<Key, Value>` already owns:

- one private observable slot per key;
- missing-key observation;
- equality-gated writes;
- a separate membership revision;
- cold snapshot reads;
- slot removal and pruning.

Its defining behavior is therefore an atom family, not a dictionary snapshot.
The three production instances are repo enrichment, worktree enrichment, and
pull-request counts in `RepoEnrichmentCacheAtom`.

### 3.2 Current derived readers

Ten product `*Derived` structs compute on access. `CoreAtoms` returns most of
them through computed properties, so those readers do not retain cache identity.
They can correctly register Swift Observation reads, but they do not declare a
cache lifetime, output equality, or execution mode.

`DerivedValue` already demonstrates revision-keyed lazy caching, but it has no
production construction and is not currently a usable Core-facing package
contract.

### 3.3 Current hot boundary

Repo Explorer builds an eager projection request from a cold
`worktreeFactsSnapshot()`. The snapshot carries the right values but registers
no per-key or aggregate observation. This is the narrowest current call path
that needs both family and derived semantics:

```text
RepoExplorer observed request construction
  -> RepoCacheAtom.worktreeFactsSnapshot()
  -> AtomEntityMap.snapshot()
  -> no observation registration
  -> off-main projection may retain old worktree facts until another input wakes it
```

The target replaces this with explicit relevant-key reads; unrelated keys do
not re-admit the projection.

## 4. Target Components and Ownership

| Component | Kind | Owns | Does not own |
|---|---|---|---|
| Concrete product group such as `CoreAtoms` | Organizational concept embodied by a product type | Named atom and derived-node composition | Observation, cache, or task semantics |
| Product source atom | Concrete product type | One canonical mutable value or coherent aggregate and its named mutations | Cross-feature registry lookup |
| `AtomFamily<Key, Value>` | Generic Infrastructure primitive | Stable keyed source slots, per-key revision, membership revision, equality gating, pruning | Product meaning, ordering policy, persistence |
| Product aggregate owner | Concrete Core or Feature type | Membership, ordering, indexes, and cross-key invariants | Per-property atom explosion |
| `DerivedAtom<Value>` | Generic Infrastructure primitive | Stable lazy cache, declared revision tuple, output revision, output equality | Source mutation, off-main work, retries |
| Product derived family | Product-owned keyed collection of retained `DerivedAtom` nodes | Key-specific computation identity and lifecycle | Canonical source values |

`AtomGroup` has no protocol, base class, marker conformance, or generic
container. `CoreAtoms` is a concrete group because it organizes heterogeneous
state; no runtime behavior follows from that label.

A product derived family initially remains an owner-held keyed collection of
`DerivedAtom` nodes. A generic `DerivedAtomFamily` is extracted only if a
second product use demonstrates the same creation, pruning, and missing-key
lifecycle. This avoids adding an abstraction merely to complete a naming grid.

## 5. Dependency Direction

```mermaid
flowchart TD
    App["App composition"]
    Feature["Feature product state"]
    Core["Core product state and derived owners"]
    Infra["Infrastructure / AtomLib"]

    App --> Feature
    App --> Core
    Feature --> Core
    Feature --> Infra
    Core --> Infra

    Infra -. forbidden .-> Core
    Infra -. forbidden .-> Feature
    Core -. forbidden .-> App
    Feature -. forbidden .-> App
```

Infrastructure may define generic family, revision, mutation, and lazy-derived
mechanics. It may not name `CoreAtoms`, `CoreAtomScope`, `AtomRegistry`, product
atoms, product keys, or product persistence.

Product derived nodes live with the product owner whose state they describe.
Feature-owned state remains explicitly injected; this design adds no ambient
Feature registry or resolver.

## 6. `AtomFamily` Behavioral Contract

### 6.1 Identity and observation

For a given live family and key, the family retains one stable slot while that
key is observed or stored. The slot owns:

- optional current value;
- semantic value revision;
- removal invalidation state.

`value(for:)` observes only that slot. A read of a missing key creates an empty
slot so later insertion wakes the reader. Changing key B does not wake a
key-A-only reader.

Per-key revisions never repeat across removal and recreation during one family
lifetime. The family may allocate revision numbers from a family-local
monotonic sequence, but consumers observe only the selected slot's revision.
This lets key A receive a new revision after remove/reinsert without making a
key-B change invalidate A.

The family separately exposes:

- membership revision for insertion and removal;
- per-key semantic revision for declared derivation inputs;
- explicitly cold snapshot reads for persistence, serialization, diagnostics,
  and eager capture.

The product owner, not the generic family, owns any coherent aggregate
revision spanning multiple slots or families.

Cold APIs must be named and documented as unobserved snapshots. They never
pretend to provide keyed reactivity.

### 6.2 Mutation

All writes occur through a named product-owner method. The owner supplies an
`AtomMutationContext` when multiple family or scalar changes form one semantic
mutation.

```mermaid
sequenceDiagram
    participant Caller
    participant Owner as Product atom owner
    participant Family as AtomFamily slot(s)
    participant Aggregate as Owner aggregate revision

    Caller->>Owner: named semantic mutation
    Owner->>Family: equality-gated slot writes
    Owner->>Family: membership changes if applicable
    Owner->>Aggregate: commit once if any change accepted
    Owner-->>Caller: accepted result
```

An equal write changes neither the slot revision nor the owner aggregate
revision. Removal invalidates the old slot before pruning it. A multi-key
mutation updates every affected slot before committing the aggregate revision.

`AtomMutationContext` batches the owner's semantic completion revision. It does
not batch Swift Observation notifications from individual stored slots, and
this design does not add registrar-level transaction machinery.

That distinction creates two supported observation contracts:

- a consumer whose semantic boundary is one slot observes that slot and may
  wake independently when it changes;
- a consumer whose invariant spans slots observes only the owner's final
  aggregate commit revision, then reads a named cold coherent snapshot after
  that commit boundary.

A cross-slot consumer must not observe the participating slots directly and
then infer atomic publication. Swift Observation's leading-edge callback is
safe for the aggregate contract because the owner changes the aggregate
revision only after every constituent slot and index has reached a valid state.
The callback re-registers against the aggregate revision and reads the
post-commit snapshot. Direct slot callbacks carry no cross-slot coherence
promise.

### 6.3 Membership and snapshots

Membership consumers observe insertion and removal, not content-only changes.
Ordered membership remains a product-owner concern because a dictionary key set
does not describe display order or topology.

Snapshots are legitimate only at named cold boundaries. An eager projection
capture that uses a snapshot must separately observe the source revision that
admits new work.

## 7. `DerivedAtom` Behavioral Contract

`DerivedAtom<Value>` is a long-lived `@MainActor` node stored by its product
owner. Construction declares:

- input revision readers;
- semantic output comparator;
- bounded synchronous computation;
- an optional telemetry identity from the existing allowlisted trace system.

Its smallest reusable package interface is:

```text
DerivedAtom<Value>
  init(
    inputRevisions: @MainActor () -> [Int],
    isContentEqual: (Value, Value) -> Bool,
    compute: @MainActor () -> Value
  )
  value: Value
  revision: Int
```

`AtomFamily<Key, Value>` supplies `value(for:)`, `revision(for:)`, membership
revision, named mutations requiring the owner's mutation context, and
explicitly cold snapshot reads. Product owners expose only the subset their
consumers need.

The computation may read only the values represented by the declared revision
tuple. Static tooling rejects ambient `atom(...)`, `CoreAtomScope`, or hidden
same-file wrapper reads in the computation closure where syntax can establish
them. Product observation tests prove semantic dependency completeness.

```mermaid
stateDiagram-v2
    [*] --> Unmaterialized
    Unmaterialized --> Current: first read computes / output revision 0
    Current --> Current: same input tuple / cache hit
    Current --> Current: changed inputs, equal output / replace cache only
    Current --> Changed: changed inputs, unequal output / bump output revision
    Changed --> Current: next stable read
```

The read algorithm is:

1. read the declared input revision tuple, registering Observation;
2. return the cache if the tuple matches;
3. compute once if the tuple differs;
4. replace the cache;
5. bump output revision only when a previously materialized output changes
   semantically.

The unmaterialized node and first successful materialization use output
revision zero. A derived node that depends on another derived node reads the
upstream value before reading its output revision, ensuring the upstream cache
has admitted the current source tuple.

`value` reads its declared input revisions inside the caller's Swift
Observation tracking scope. A relevant input revision therefore wakes a direct
`value` consumer even when recomputation later proves the output semantically
equal. Equality preserves the cached output revision and prevents a second
output-revision publication; it cannot retract the source invalidation that
already woke the caller. A surface that requires equality-gated publication
with no initial input wake uses eager materialization and observes only its
materialized output.

Variable-cardinality or blocking computation is not permitted in
`DerivedAtom`. It belongs to the eager materialization design.

## 8. Surface Granularity Decisions

| Current surface | Target observation structure | Rationale |
|---|---|---|
| Repo/worktree enrichment and PR counts | `AtomFamily` immediately | Already independently keyed and equality-gated |
| Repository topology entities | Repo, worktree, and watched-path families plus ordered membership/topology aggregate | Rows change independently; ordering and topology validity remain coherent |
| Pane graph | One pane-state family member per pane plus coherent pane/drawer membership and index revision | Pane UI needs key isolation; drawer ownership and multi-pane deletion remain one invariant |
| Tab shell and tab graph | One tab member per tab plus coherent ordering and pane/arrangement ownership indexes | Tab UI needs key isolation; moves and uniqueness span tabs |
| Session runtime | Family keyed by pane | Status changes independently and can be frequent |
| Terminal activity | Feature family keyed by pane | Activity lifecycle is independently hot per terminal |
| Inbox notification log | Retain coherent bounded ordered aggregate | Coalescing, retention, ordering, and persistence are log-wide |
| Inbox badge/list presentations | Derived or eagerly materialized projections | They compute from the canonical log; they are not new canonical sources |
| Sidebar settings, cursor state, recency lists | Retain bounded scalar or coherent aggregate atoms | Their mutations and consumers intentionally use the whole value |
| App `ViewRegistry` | Remains App-owned runtime slots | View lifetime is not Core/Feature product atom state |

Pane and tab families are entity-sized. Titles, metadata, content, and
residency do not each become separate families. A measured independently hot
fact may move to its own family later; terminal activity already satisfies that
criterion.

## 9. Representative Target Flow: Repo Explorer

```mermaid
sequenceDiagram
    participant Mutation as Repo cache mutation
    participant Family as Worktree source families
    participant Facts as retained worktree-facts derived node
    participant View as Repo Explorer admission
    participant Worker as eager projection worker

    Mutation->>Family: update worktree B
    Family->>Family: bump B slot revision
    alt B is visible/relevant
        Family-->>View: push Observation invalidation
        View->>Facts: read facts[B]
        Facts->>Facts: recompute once for B revisions
        View->>Worker: admit immutable current request
    else B is unrelated
        Family-->>View: no wake
    end
```

Repo Explorer determines relevant worktree IDs from its observed topology
membership, then reads `worktreeFacts(for:)` for exactly those IDs. It no longer
filters a complete cold facts snapshot inside an Observation registration.

The worktree-facts composition is the first product use of retained lazy
derived semantics because it has:

- two existing keyed sources;
- a clear per-key output;
- semantic `Equatable` output;
- existing key-isolation tests;
- a real consumer currently using an unobserved bulk snapshot.

`RepoEnrichmentCacheAtom` owns the complete lifecycle of the retained
worktree-facts derived family:

- `worktreeFacts(for:)` creates one internal `DerivedAtom` on first access and
  returns its value rather than exposing the node;
- a missing worktree still declares the relevant family-slot revisions and
  computes `nil`, so later hydration or insertion wakes the consumer;
- hydration uses the ordinary family mutations and revision path;
- removal invalidates the source slot and lets the retained derived node
  recompute to `nil` before any pruning decision;
- cache pruning may remove an internal node only after the worktree is absent
  from product membership and the owner has published the corresponding
  removal/aggregate invalidation; reinsertion creates a new internal node while
  the family's non-repeating key revision prevents stale reuse;
- owner shutdown clears the internal node collection after product observation
  has stopped.

Callers never retain a derived node directly, so pruning cannot strand a
consumer on a detached cache identity.

## 10. Coherent Pane and Tab Mutations

Moving pane and tab members into families does not weaken graph invariants.
The owning atom still performs the complete named operation.

For example, moving a pane between tabs:

```text
WorkspaceMutationCoordinator
  -> begin one semantic mutation context
  -> update source tab family member
  -> update destination tab family member
  -> update pane-to-tab ownership index
  -> commit one tab-graph aggregate revision
  -> cross-slot observers read the coherent graph from that commit boundary
```

Key-only consumers may wake for their changed member and must not infer a
cross-slot transaction. Aggregate consumers observe only the final graph
revision and then read the cold coherent graph snapshot after the owner has
restored every invariant. No caller receives mutable family storage or
coordinates slots directly.

## 11. Failure and Lifecycle

| Condition | Owner response |
|---|---|
| Equal source write | No slot or aggregate revision change |
| Missing key read | Retain empty observable slot until insertion or explicit safe pruning |
| Key removal | Invalidate old slot, update membership, then prune |
| Derived computation throws or is partial | Not supported by lazy `DerivedAtom`; the product computation must be total over accepted source state |
| Undeclared source dependency | Contract failure detected through static rules where possible and positive/negative observation tests |
| Derived node recreated on every read | Architecture violation; product composition must retain stable identity |
| Snapshot used in hot observed path | Architecture violation unless paired with an explicit observed aggregate revision and classified eager/cold boundary |

No lazy derivation starts tasks, retries, or performs I/O. Its actor and
lifecycle are the owning product graph's actor and lifetime.

## 12. Cutover Model

The cutover is hard at each migrated surface:

1. The generic source primitive is renamed without an alias.
2. A product owner introduces the target family or retained derived node.
3. Every hot consumer of that surface moves to the declared keyed, aggregate,
   or cold API.
4. Old broad or unobserved accessors are removed when their slice inventory
   reaches zero.

There is no runtime dual authority. During a slice, a compatibility snapshot
may remain as a cold read over the new canonical family for persistence or
serialization, but it is never a second store and never a hot observation API.

## 13. First Migration Slices

### 13.1 Primitive and Repo Explorer slice

The first reactive slice is:

- hard-rename the three existing repo-cache families;
- establish slot revisions and the retained lazy-derived contract;
- retain worktree-facts derived nodes by worktree ID;
- make Repo Explorer request admission read only relevant keyed facts;
- preserve the cold full snapshots for persistence and explicitly classified
  bulk capture.

Its controlled product workload uses a large open-source directory as the
watched-folder input and exercises:

- initial repo projection;
- search/filter changes;
- one visible worktree enrichment change;
- one unrelated worktree enrichment change;
- removal and reinsertion of a previously missing relevant key.

### 13.2 Deferred source-family slices

Pane, tab, session-runtime, terminal-activity, and topology-family migrations
remain separate slices because each changes a product owner and its mutation
inventory. Their target boundary is settled here, but they are not bundled into
the primitive/Repo Explorer cutover.

Command Bar is not a first migration slice. Its demand cache is a real
mitigation, and current source does not prove enough runtime severity to justify
changing its ownership or execution model before a controlled workload does.

## 14. Cross-Cutting Realization

| Obligation | Structural realization | Degradation/failure behavior |
|---|---|---|
| Performance | Per-key source slots; cached derived outputs; cold snapshots excluded from hot reads | Equal and unrelated changes are no-ops |
| Reliability | Singular product owners and coherent aggregate commit boundaries | Cross-slot consumers cannot treat independent slot wakes as a coherent graph |
| Target readiness | Generic primitives remain in Infrastructure; product nodes stay in Core/Feature | Static target edges reject reverse dependencies |
| Privacy | Telemetry records operation kind, counts, and duration only | Raw keys, paths, UUIDs, or values are never exported |
| Operability | Existing trace tags select atom/derived metrics | Export failure is fail-open and non-authoritative |
| Compatibility | Canonical persisted representations remain unchanged in this design | Existing data loads through current migration lineages |

## 15. Proof Architecture

| Requirement set | Structural seam | Required proof class |
|---|---|---|
| RS-01–RS-03 | Product owner mutation and aggregate commit | Access-control/static enforcement plus coherent Observation tests |
| RS-04–RS-06 | Family slot, membership revision, cold snapshot boundary | Unit and product observation tests for relevant, unrelated, missing, removal, membership, and snapshot cases |
| RS-07–RS-10 | Retained `DerivedAtom` value and output revision | Cache-hit, one-recompute, equality, chaining, and push-invalidation tests |
| RS-21–RS-23 | Infrastructure/Core boundary and architecture rules | Architecture-lint fixtures and executable compile-negative harness where compiler rejection is claimed |
| RS-24–RS-26 | Existing atom/derived telemetry and watched-folder workload | Provenance-matched distributions, continuity oracle, and frozen interaction budgets |
| RS-27–RS-28 | Slice inventory and isolated debug app | Unit/integration/runtime pyramid plus behavior-preserving interaction proof |

The primitive harness must prove key isolation and nil-then-insert wakeup using
real Swift Observation. The product harness must include an unrelated-key
control; call-count reduction without that control is insufficient.

The coherent-mutation harness observes only a representative owner's aggregate
commit revision, synchronously re-registers, and reads the named cold graph
snapshot on every callback. It must see only the complete before or after
invariant. A separate direct-slot test proves that slot consumers retain
independent wake behavior without promising cross-slot atomicity.

The existing `AgentStudioArchitectureLint` slice inventory is extended for the
hard-cut rename and retained-node rules. The proof does not introduce a second
inventory framework.

## 16. Source Inventory

| Source | Identity | Authority and applicability |
|---|---|---|
| Governing requirements | SHA-256 `1aee657052b6e475767215bf613765c5056465f4920b0e178e5e0fb008809a39` | Normative Why/What for the complete design |
| Current repository | Git `50d0b0ac360af8b1fe2f62a56e35b5cd2cd8e515` | Exact current implementation and test baseline |
| Reactive-state research ledger | SHA-256 `b6613ec2e0dbea5d1c04a04455587a8eeed47e129669c7278b152f8fcd6a9935` | Exact-HEAD observational inventory |
| [`Infrastructure/AtomLib/AtomEntityMap.swift`](../../../Sources/AgentStudio/Infrastructure/AtomLib/AtomEntityMap.swift) | Current source at repository identity above | Current keyed-slot semantics |
| [`Infrastructure/AtomLib/DerivedValue.swift`](../../../Sources/AgentStudio/Infrastructure/AtomLib/DerivedValue.swift) | Current source at repository identity above | Current unused lazy-cache semantics |
| [`Core/State/MainActor/Atoms/RepoCacheAtom.swift`](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift) | Current source at repository identity above | Existing product family owner and worktree-facts composition |
| [`Core/State/MainActor/Atoms/CoreAtoms.swift`](../../../Sources/AgentStudio/Core/State/MainActor/Atoms/CoreAtoms.swift) | Current source at repository identity above | Current concrete atom group and reconstructed derived readers |
| [`Features/RepoExplorer/RepoExplorerView.swift`](../../../Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift) | Current source at repository identity above | Current cold-snapshot admission path |
| AtomLib and repo-cache observation tests | Current tests at repository identity above | Existing semantic proof floor |
| Swift Observation and Swift 6.2 compiler | Xcode 26.3 / Swift 6.2.4 applicability established by governing research | Platform observation and isolation boundary |

Scoped completeness covers the generic primitives, all current product
constructions, all ten product derived readers, representative hot consumers,
architecture rules, semantic tests, and existing workload telemetry. Numeric
runtime severity remains deliberately unclaimed until the frozen workload runs.

## 17. Accepted Debt and Revisit Signals

- Whole-graph pane and tab snapshots remain available for persistence and cold
  bulk work. They are debt only if a hot consumer continues to use them.
- A generic `DerivedAtomFamily` is deferred until repeated product lifecycle
  code proves the abstraction.
- Some bounded `*Derived` readers remain ordinary uncached readers. They
  migrate only when reuse, cost, or consumer-boundary semantics require a
  first-class node.
- Property-level families are deferred unless measurement isolates one fact as
  independently hot within an entity-sized member.

## 18. Negative Space

This design does not:

- create an `AtomGroup` type;
- introduce a resolver, service locator, or ambient Feature registry;
- replace Swift Observation;
- move every property into its own atom;
- convert every collection into a family;
- make lazy derivations asynchronous;
- persist derived caches;
- split SwiftPM targets;
- claim a performance improvement before controlled proof.
