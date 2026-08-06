# AgentStudio Reactive State System — Specification

Governing Requirements:
[AgentStudio Reactive State System — Requirements](2026-07-31-reactive-state-system-requirements.md)

This Specification defines what must be observably true for users, developers,
reviewers, and operators. The sibling program designs define the internal
structure that realizes these obligations.

## Problem and Intended Difference

| ID | Current observable problem | Intended observable difference |
|---|---|---|
| P1 | A consumer that needs one keyed fact can be woken by unrelated collection changes or can remain stale after reading a cold snapshot. | Observation is registered at the smallest declared semantic boundary: scalar, key, membership, coherent aggregate, or explicitly cold snapshot. |
| P2 | Reusable computed readers can reconstruct values on every access without exposing cache identity, equality, or invalidation semantics. | Every non-trivial reusable derivation declares its dependencies, execution mode, equality, and publication boundary. |
| P3 | Variable-cardinality UI projection can execute on `MainActor` and contend with typing, scrolling, focus, and navigation. | Variable-cost work crosses a checked boundary, computes off-main, and publishes only a bounded current result. |
| P4 | Replaceable tasks can be cancelled without cancellation being the final stale-result guarantee. | Superseded work cannot publish as current even if it ignores cancellation. |
| P5 | One logical save can hide multiple commits, or an older completion can clear a newer dirty state. | Each authority reports outcomes that match its atomic commit and admits completion only for the captured revision. |
| P6 | Static shape, unit behavior, runtime wiring, and performance claims can be conflated. | Each claim has proof at its actual boundary with exact build and workload provenance where required. |

Static source establishes these risks, not their exact user-visible severity.
Performance severity and improvement remain measured claims.

## Consumer Journeys

### End-user interaction

```text
User types, scrolls, focuses, or navigates
  -> relevant state changes
  -> the visible surface updates with current coherent state
  -> unrelated state changes do not add avoidable interaction-path work
  -> restart preserves supported durable and local behavior

Pain today: broad invalidation and MainActor fleet reconstruction can contend
with the interaction even when most changed state is irrelevant. [U1, U2, U3]
```

### Developer and reviewer workflow

```text
Developer identifies the state owner
  -> chooses source atom, keyed family, or derived mode
  -> mutates through a named owner boundary
  -> declares observation, equality, actor, lifecycle, and persistence meaning
  -> compiler / architecture gate rejects mechanical violations
  -> behavioral and runtime proof establish semantics and performance

Pain today: those decisions are spread across conventions and bespoke paths,
so an apparently typed API can still hide broad reads or expensive work. [U4-U7]
```

## Observable Context

```text
                         performance evidence
                 Runtime / release operator
                              |
                              v
End user ---- UI behavior ----[ Reactive State System ]---- state API ---- Developer
                              |
                              +---- restart/save behavior ---- Existing user
                              |
                              +---- proof result ------------- Reviewer

Opaque-system boundary:
  included  observation, derived output, stale-result behavior,
            persistence outcomes, compatibility, and proof
  excluded  internal component topology, task wiring, database ownership,
            and implementation ordering
```

## Required Outcomes

| ID | Required observable outcome |
|---|---|
| O1 | Relevant changes wake the intended consumer; unrelated changes do not. |
| O2 | Reusable derived state has predictable caching, equality, and publication semantics. |
| O3 | Variable-cardinality computation does not execute on `MainActor`. |
| O4 | Cancelled or superseded computation and persistence cannot publish or clear newer state. |
| O5 | Named mutations expose coherent accepted state, not an invalid semantic intermediate state. |
| O6 | Persistence behavior follows explicit authority and durability classes. |
| O7 | Mechanical violations fail statically and semantic claims have boundary-matched proof. |
| O8 | Existing behavior and supported state survive each hard-cut migration slice. |

## Normative Requirements

### Source ownership and mutation

**RS-01 — Singular ownership.** Every canonical mutable Core or Feature value
MUST have one authoritative owner. Mutable stored properties MUST be private or
`private(set)` and MUST change through named owner methods or an explicitly
owned cross-slice mutation boundary. Ephemeral view/controller bookkeeping is
not automatically canonical state.

**RS-02 — Accepted changes only.** Assigning a value equal under the owner's
declared semantic comparator MUST NOT wake dependent consumers or advance its
semantic revision.

**RS-03 — Coherent mutation.** A named mutation that changes several canonical
fields MUST expose a valid before or after semantic state. Consumers that need
the complete invariant MUST have one completion boundary they can observe.
Unrelated owners are not thereby globally transactional.

### Observation boundaries

**RS-04 — Declared granularity.** Every observable state API MUST declare one
boundary: scalar/property, keyed value, family membership, coherent aggregate,
or explicitly cold snapshot. A keyed-looking method over an observed whole
collection MUST NOT claim key isolation.

**RS-05 — Key isolation.** For keyed source state, reading key A MUST register
interest in A; changing B MUST NOT wake an A-only consumer; reading a missing A
MUST wake when A is inserted; membership observers MUST wake on insertion or
removal rather than content-only changes; removal/pruning MUST not strand a
stale observer.

**RS-06 — Cold snapshot boundary.** Collection snapshots MAY serve
persistence, serialization, diagnostics, explicitly cold bulk bridges, or
measured coherent capture. A hot observed UI path MUST read relevant keys, an
explicit aggregate revision, or a first-class derived/materialized output.

### Derived state

**RS-07 — Declared derivation.** A reusable composition that crosses a consumer
boundary, performs variable-cardinality work, or is measured as hot MUST
declare source dependencies, lazy-cached or eager-materialized mode, semantic
output equality, invalidation/publication granularity, execution isolation, and
asynchronous cancellation/freshness policy when applicable. A trivial bounded
local reader MAY remain intentionally uncached.

**RS-08 — Lazy cached behavior.** A lazy derived atom MUST retain stable
identity, read declared input revisions, reuse output when those revisions are
unchanged, recompute at most once for a new revision tuple, and advance its
output revision only when the semantic output changes. Its computation MUST be
bounded and synchronous on the owning actor. Reading a downstream lazy value
after source invalidation MUST reflect each upstream dependency's latest
semantic value; a downstream cache MUST NOT reuse output merely because an
upstream output revision has not yet been materialized.

**RS-09 — Eager materialized behavior.** An eager derivation MUST capture an
immutable `Sendable` request, perform variable-cost computation outside
`MainActor`, retain work for the required lifetime, and publish only a bounded
current result. Replaceable work MUST reject superseded completion and MUST NOT
republish semantically equal output. A successful current completion whose
output is semantically equal MUST still make that request identity current,
while preserving the value and output revision and without waking output-only
consumers. Before migration, each fallible surface MUST define whether failure
clears output or retains a previous result as explicitly non-current.

**RS-10 — Push-driven admission.** Source mutation MUST drive lazy invalidation
or eager admission. Consumers MUST NOT poll for source changes. A lazy cache
may recompute on its next read; an eager result computes before publication.

### Concurrency and lifecycle

**RS-11 — Checked transfer.** Values and closures crossing the off-main
boundary MUST satisfy Swift concurrency checking. New code MUST NOT use
unchecked access to `MainActor` state from background work.

**RS-12 — Interaction-path boundary.** In a selected derived or measured hot
slice, reusable work whose cost grows with repositories, worktrees, panes, tabs,
notifications, files, rows, or result count MUST execute outside `MainActor`.
Main-actor participation MUST remain bounded capture, lifecycle bookkeeping,
freshness admission, and small publication. A measured exception MAY retain a
bounded capture or publication step; it does not authorize variable-cardinality
reconstruction on `MainActor` or expand this requirement to unrelated paths.

**RS-13 — Freshness admission.** Completion of older computation or persistence
MUST NOT publish stale output, clear a newer dirty state, suppress a newer
generation, or overwrite a newer materialized result.

**RS-14 — Complete lifecycle.** Every asynchronous derived or persistence
operation MUST have an observable owner, start trigger, retained lifetime,
cancellation trigger, stale-result rule, shutdown behavior, and failure
behavior. Actor or `Task.detached` spelling alone does not satisfy this.

### Persistence behavior

**RS-15 — Authority classification.** Every persisted or
persistence-adjacent value MUST be classified as authoritative durable state,
application/workspace-local UX memory, rebuildable cache, runtime-only state,
or non-persisted derived state. The class determines restore, save, default,
failure, and retention behavior.

**RS-16 — Live-state boundary.** An owning repository MAY write SQLite directly;
not every database mutation passes through an atom. SQLite MUST NOT become a
high-frequency observation source when live atoms own the interaction state.

**RS-17 — Logical save consistency.** An API reporting one logical save outcome
MUST commit all values in that authority as one transaction and generation.
Operations spanning independent authorities MUST report their outcomes
separately and MUST NOT claim distributed atomicity.

**RS-18 — Save admission.** Completion for revision N MUST clear dirty state
only if no newer semantic revision remains unsaved.

**RS-19 — Hydration before publication.** Persisted state MUST be decoded,
validated, and prepared before live mutation. Authoritative preparation failure
MUST preserve the current live state. Invalid non-authoritative data MUST
default only within its owning lane unless the whole local database is
unavailable.

**RS-20 — Crash consistency.** One authoritative mutation spanning several
Core state classes MUST restart at the complete previous or complete new Core
generation. A crash between independent Core and local commits MAY expose new
Core with previous/default local state, but never a falsely atomic result.

### Developer vocabulary and guardrails

**RS-21 — Canonical vocabulary.** The paved developer vocabulary MUST
distinguish source `Atom`, keyed source `AtomFamily<Key, Value>`, organizational
`AtomGroup`, and computational `DerivedAtom`. `AtomGroup` is vocabulary, not a
required runtime type. `AtomEntityMap` MUST hard-cut to `AtomFamily` without a
compatibility alias. Lazy and eager execution modes MUST be visible at the
derived construction boundary.

**RS-22 — Scope and target boundary.** Generic reactive primitives MUST remain
product-neutral. Product state MUST NOT introduce an App dependency from Core
or Features, a runtime resolver/service locator, another ambient Feature
registry, a universal Feature state aggregate, or a reverse target edge.

**RS-23 — Honest enforcement.** The compiler or existing architecture tooling
MUST reject mechanically detectable violations such as unauthorized mutation,
product types in generic primitives, illegal target edges, and statically
visible hidden ambient reads. Dependency completeness, algorithmic cost,
cancellation correctness, and latency MUST be proven behaviorally rather than
misrepresented as compiler guarantees.

### Telemetry, performance, and compatibility

**RS-24 — Safe derivation telemetry.** Selected hot paths MUST distinguish
admission/invalidation, cache/recompute, actor capture/publication, worker time,
cancellation/stale discard, semantic output change, and relevant cardinality.
Telemetry MUST use the existing trace-tag system, remain allowlisted and
bounded, export no raw product content or identifiers, and fail open.

**RS-25 — Provenance.** Before/after performance evidence MUST bind source and
executable identity, workload/fixture identity, instrumentation selection,
launch mode, controlled interaction sequence, and required event completeness.
Comparison MUST reject missing or mismatched provenance before evaluating
latency or work distributions.

**RS-26 — Performance acceptance.** Before candidate results are observed, each
hot-surface slice MUST freeze affected interactions, direct work metrics,
end-to-end latency metrics, cardinality, continuity/final-state oracles, and a
regression boundary derived from a matched baseline or governing budget. No
affected interaction may exceed its boundary. Improvement claims require an
actually improved matched distribution; static call-count reduction is not
performance proof.

**RS-27 — Proof pyramid.** Proof MUST include fast semantic unit tests,
product-level relevant/unrelated Observation tests, real persistence
integration tests where applicable, exact slice-inventory coverage, isolated
debug runtime interaction, and controlled performance evidence for selected
hot surfaces. Asynchronous correctness MUST NOT rely on wall-clock sleeps.

**RS-28 — Compatibility.** Each migration MUST preserve supported state,
commands, focus/navigation, and user-visible behavior unless a separate product
decision changes them. Persistence representation changes additionally require
current-schema, upgrade, rollback/partial-failure, save/reload, and real
relaunch proof.

## Observable Contracts

### C1 — Source atom and keyed family

Input is a named, semantically valid owner mutation. Accepted unequal input
publishes the current value and relevant revision; equal input is a no-op.
Invalid input is rejected before publication. Missing-key observation and later
insertion follow RS-05.

### C2 — Lazy derived atom

The first read materializes one value. Unchanged input revisions reuse it;
changed revisions recompute once; equal recomputation preserves output
revision. Chained reads materialize current upstream semantics before deciding
whether downstream output can be reused. A dependency not represented by the
declared inputs is a contract violation. No partial value is published.

### C3 — Eager materialized derivation

Admission accepts one immutable request and returns no synchronous fleet
projection. Replaceable work may leave the previous result renderable only with
its original freshness identity; it never presents that result as current for a
new failed or cancelled request. A successful equal result advances current
request identity without changing value or output revision and without waking
output-only consumers. Superseded completion is discarded regardless of
cancellation cooperation.

### C4 — Persistence authority

A logical save returns success only for its complete authority transaction.
Independent authority outcomes remain distinguishable. Failure preserves dirty
eligibility and the previous committed generation. Supported data restores
according to its declared authority class; runtime and derived state are not
promoted to durable authority.

### C5 — Developer boundary

A developer can identify source/derived mode and observation boundary from the
API and documentation. Illegal imports, unauthorized mutation, or product
coupling in generic primitives fail the existing static gate. Semantic
completeness and performance remain explicit proof obligations.

## Requirement-to-Proof Coverage

| Proof ID | Requirements | Evidence class that distinguishes pass from fail |
|---|---|---|
| V1 | RS-01–RS-03 | Compile/static enforcement plus real Observation of accepted, equal, and coherent multi-field mutations. |
| V2 | RS-04–RS-06 | Automated relevant-key, unrelated-key, missing-insert, membership, removal/pruning, aggregate, and cold-snapshot behavior. |
| V3 | RS-07–RS-10 | Cache-hit, recompute, equality, chained upstream materialization, stable-identity, push-invalidation, eager admission, and equal-result freshness behavior. |
| V4 | RS-11–RS-14 | Compiler-checked transfer plus deterministic cancellation, overlap, stale completion, equal-current completion, shutdown, and bounded actor-work evidence. |
| V5 | RS-15–RS-20 | Real SQLite transaction, rollback, overlap, corruption/defaulting, crash/reopen, save/reload, and authority-separated outcome inspection. |
| V6 | RS-21–RS-23 | Existing architecture gate plus executable compiler-negative evidence where compiler rejection is claimed. |
| V7 | RS-24–RS-26 | Allowlist/fail-open telemetry evidence and provenance-matched controlled performance distributions with an independent continuity oracle. |
| V8 | RS-27–RS-28 | Slice inventory, isolated debug interaction, supported-data upgrade/relaunch, and final behavior/state inspection. |

## Need-to-Proof Traceability

| Authorized need | Problem | Outcome | Requirements | Contracts | Proof |
|---|---|---|---|---|---|
| U1 | P1, P3 | O1, O3 | RS-04–RS-12, RS-26 | C1–C3 | V2–V4, V7 |
| U2 | P2, P4 | O2, O4, O5 | RS-03, RS-07–RS-14 | C2, C3 | V1, V3, V4 |
| U3 | P4–P6 | O4, O6, O8 | RS-13, RS-17–RS-20, RS-28 | C3, C4 | V4, V5, V8 |
| U4 | P1, P2 | O1, O2, O5 | RS-01–RS-10, RS-21 | C1, C2, C5 | V1–V3, V6 |
| U5 | P3, P4 | O3, O4 | RS-09, RS-11–RS-14 | C3 | V4 |
| U6 | P1–P6 | O5, O7 | RS-21–RS-23, RS-27 | C5 | V6, V8 |
| U7 | P6 | O7 | RS-24–RS-26 | C5 | V7 |
| U8 | P5 | O4, O6, O8 | RS-15–RS-20, RS-28 | C4 | V5, V8 |
| U9 | P1–P6 | O7, O8 | RS-22, RS-23, RS-27, RS-28 | C5 | V6, V8 |

## Negative Space

Satisfying this Specification does not require every state owner, collection,
derived reader, worker, or persistence lane to migrate. A slice is complete
only for the inventory it names; unselected surfaces retain their current
authority and behavior.

No guarantee is made that every internal metric improves, that all state work
leaves `MainActor`, or that independently committed persistence authorities
become atomically consistent with one another. Those expansions require new
authorized Requirements.

## Evidence Basis

Current implementation evidence was refreshed against `origin/main` commit
`f7a01132f9ac5d02981e00856750936f80acb61f`. Governing boundaries remain:

- [Atom and persistence boundaries](../../architecture/atom_persistence_boundaries.md)
- [Performance evidence boundaries](../2026-07-10-agentstudio-performance-boundaries/agentstudio-performance-boundaries.md)
- [Persistence ownership hard cut](../2026-07-21-persistence-ownership-hard-cut/2026-07-21-persistence-ownership-hard-cut.md)
- [Core atom scope and Feature injection](../2026-07-25-core-atom-scope-feature-injection/2026-07-25-core-atom-scope-feature-injection.md)

Those sources constrain this contract; they do not replace the Requirements
identity or the observable obligations above.
