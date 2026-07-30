# DerivedValue Production Adoption

Date: 2026-07-30
Status: reviewed, ready for implementation planning
Source baseline: `36886e60bf4f3fcebeacc0804731be5b8c053897`

## Decision

`DerivedValue` becomes a real production mechanism through one deliberately
small first adoption: a long-lived Core-owned rich tab snapshot used by a
measured fleet consumer.

This adoption removes repeated identical tab reconstruction. It does not claim
to solve broad Swift Observation wakeups, make every derived reader cacheable,
or turn expensive compatibility APIs into acceptable foundational reads.

Pane-rich memoization remains in this spec as the next eligible adoption, but it
does not enter the first implementation slice until all pane projection inputs
have complete semantic revisions and a measured fleet consumer still needs it.

## Why This Exists

`DerivedValue` already implements revision-keyed lazy memoization, output
equality gating, and telemetry, but production code never constructs it.
Meanwhile:

- most Core derived accessors return fresh structs;
- tab fleet and keyed-looking tab reads reconstruct arrangement state;
- singular pane reads can perform rich topology and enrichment work; and
- no complete pane/tab semantic revision contract exists.

The product need is not “more caching.” It is one explicit, inspectable rich
read model whose lifetime, inputs, cost, and consumers are honest.

## Result at a Glance

```text
Today

Tab consumer
    │
    ├──► fresh WorkspaceTabLayoutDerived
    │       └──► compose arrangement fleet
    └──► another read repeats the work

Accepted boundary

canonical tab owners
    │ owner-local facts + semantic revisions
    ▼
long-lived Core tab read model
    │
    └──► DerivedValue<WorkspaceRichTabSnapshot>
             ├── unchanged revisions ──► cached snapshot
             └── changed revisions ────► one reconstruction
                                              │
                                              ▼
                                      ordered tabs
```

## Product Intent

### User outcome

Tab-heavy workspaces must not repeatedly rebuild the same rich tab fleet during
one unchanged state generation. Tab creation, removal, reordering, selection,
arrangement changes, pane movement, and restore must remain behaviorally
identical.

### Engineering outcome

- `DerivedValue` has a real production owner and consumer.
- Cached output cannot become stale because a contributing mutation escaped its
  declared revision.
- Cheap owner-local queries remain cheap.
- Rich fleet work is explicit in type and API names.
- The change can be evaluated and reverted independently of SQLite lifecycle
  work.

The companion [Live State and SQLite Lifecycle Boundaries](../2026-07-30-state-lifecycle-sqlite-boundaries/2026-07-30-state-lifecycle-sqlite-boundaries.md)
spec owns persistence classification and save behavior. Neither document
requires the other to implement its first slice.

## Current-State Evidence

### Generic primitive

`Infrastructure/AtomLib/DerivedValue.swift`:

- compares an explicit `[Int]` input-revision vector;
- returns cached output when the vector is unchanged;
- recomputes lazily on read;
- bumps its own revision only when output content changes; and
- records cache-hit and compute telemetry.

It is currently module-internal and has no production constructor.

### Fresh derived readers

`CoreAtoms` constructs most derived readers from computed properties.
`WorkspaceTabLayoutDerived.tabs` assembles the fleet, while
`WorkspaceTabLayoutDerived.tab(_:)` reaches through
`WorkspaceTabArrangementAtom.arrangementState(_:)`, which currently composes
the arrangement model before selecting one entry.

### Existing precedent

`RepoEnrichmentCacheAtom` already owns category and aggregate
`AtomRevision` instances and advances them through accepted mutation
boundaries. This is the nearest production precedent; the spec does not invent
a general reactive runtime.

## Boundary and Separability Map

```text
Infrastructure/AtomLib
  owns:
    generic revision comparison
    cached output
    output equality gating
    generic derived telemetry
  exposes:
    package-visible DerivedValue
            │
            ▼
Core tab read model
  owns:
    long-lived DerivedValue instance
    exact tab input revision vector
    rich tab snapshot shape
    semantic output comparator
            │
            ▼
App / Feature fleet consumer
  owns:
    when a complete rich tab snapshot is actually required

Canonical tab atoms remain the only write owners.
SQLite and repositories are outside this boundary.
```

### Permitted dependencies

```text
Core rich tab read model ──► Infrastructure.DerivedValue
Core rich tab read model ──► explicit canonical tab owners
App / Feature consumer    ──► Core read-only rich snapshot
Persistence              ──► canonical owners directly
```

### Forbidden dependencies

```text
Infrastructure/AtomLib ─X─► CoreAtoms or product atoms
Derived compute        ─X─► atom(...), CoreAtomScope, AtomRegistry
Derived compute        ─X─► SQLite, filesystem, subprocess, async work
Persistence observer   ─X─► rich derived snapshot
Cheap keyed query      ─X─► fleet snapshot as an implementation shortcut
Any consumer           ─X─► newly constructed DerivedValue per access
```

## Technical Contract

### 1. Generic primitive access

The `DerivedValue` type, initializer, and `value` read become `package`
visible. Its own `revision` remains internal because the first production
slice does not chain another derived value from it. Infrastructure remains
unaware of product types and owners.

Package exposure alone is not adoption. Production construction is allowed
only inside a named, long-lived Core read model.

### 2. First production owner

`WorkspaceTabLayoutAtom` owns exactly one private lazy
`DerivedValue<WorkspaceRichTabSnapshot>` and constructs it from the
`shellAtom` and `arrangementAtom` already supplied to its initializer.
`CoreAtoms` continues to construct one `WorkspaceTabLayoutAtom`; it does not
own or expose a second cache.

The instance must not be:

- a computed property;
- a global;
- persisted;
- recreated for each view or request; or
- exposed as a mutable cache.

### 3. Rich tab snapshot

The first output is one immutable rich snapshot containing only the payload
needed by the accepted fleet consumer:

```text
WorkspaceRichTabSnapshot
  orderedTabs
```

`orderedTabs` contains the complete current `Tab` values used by the accepted
fleet consumer. Exact Swift names may follow repository conventions during
planning. A keyed index may be added only when a named production consumer
already requires the rich fleet and separately demonstrates why an existing
owner-local index is insufficient.

The snapshot is a read model. It is not canonical state, a mutation API, an
IPC authority model, or a persistence DTO.

### 4. Declared input revisions

Every canonical owner whose state contributes to the snapshot exposes an
owner-local semantic revision. The initial tab vector covers:

- tab shell identity, order, and display fields;
- tab graph membership and arrangement graph;
- active arrangement IDs by tab;
- active pane IDs by arrangement; and
- active drawer-child IDs by arrangement and drawer.

All three cursor collections contribute because complete `Tab` values contain
their active arrangement, active pane, and drawer-view child selections.

Runtime-only presentation such as tab zoom is excluded from the canonical rich
tab snapshot. A consumer requiring presentation facts uses a separately named
presentation projection.

### 5. Accepted-change discipline

For every contributing owner:

- mutable storage remains `private` or `private(set)`;
- public/package mutation occurs through named methods;
- equal or rejected mutations do not advance the revision;
- an accepted owner-local semantic mutation advances its revision exactly once;
  and
- hydration/replacement advances the revision only when the installed semantic
  content differs.

Revision advancement is centralized in the owner’s mutation boundary. The
implementation must not scatter manual revision bumps across arbitrary call
sites.

Cross-owner commands retain today’s synchronous staged-mutation semantics.
This spec does not introduce a generalized transaction or promise new
old-or-new atomicity across independent owners. Correctness requires that the
final owner revision vector always invalidates any intermediate cached result.

### 6. Compute closure

The compute closure may read only the explicitly supplied canonical tab owners.
It may not hide dependencies through ambient scope, helper wrappers, repository
reads, or mutable global state.

It performs one direct assembly pass from canonical shell, graph, and cursor
facts. It must not call the existing fleet-composing compatibility chain.

### 7. Output equality

The Core read model owns an explicit semantic comparator for the snapshot.
Synthesized equality is acceptable only if every field has exactly the same
consumer-visible meaning.

The comparator must:

- detect ordered tab changes;
- detect tab and pane membership changes represented by the rich tabs;
- detect every consumer-visible tab field change; and
- ignore no field merely to improve the cache-hit metric.

### 8. Consumer adoption

At least one existing measured full-fleet consumer adopts the snapshot in the
first implementation. `TabBarAdapter` is the leading candidate from current
source evidence.

Narrow consumers continue to use owner-local indexed facts. No caller may use
the fleet snapshot solely because it is convenient.

### 9. Pane adoption gate

A rich pane snapshot may be added only when all of these are true:

- pane graph, drawer cursor, topology, and exact enrichment inputs expose
  complete semantic revisions;
- late cache hydration invalidates the snapshot correctly;
- canonical `pane(id)` remains owner-local and does not become a fleet lookup;
- a production workload still shows repeated rich pane-fleet assembly; and
- the pane adoption has the same correctness and performance proof as tabs.

This gate prevents the first tab slice from expanding into a pane/topology/cache
redesign.

## Requirements

| ID | Requirement |
| --- | --- |
| DV-01 | `DerivedValue` is package-visible only to the extent Core production adoption requires. |
| DV-02 | `WorkspaceTabLayoutAtom` owns exactly one long-lived production instance. |
| DV-03 | The first production output is an explicitly rich immutable ordered tab snapshot; additional indexes require named consumers. |
| DV-04 | Every contributing accepted mutation advances a declared owner revision; equal/rejected mutations do not. |
| DV-05 | Compute uses only declared canonical owners and performs no ambient, persistence, I/O, async, or compatibility-fleet read. |
| DV-06 | Cheap keyed/canonical queries do not route through the fleet snapshot. |
| DV-07 | At least one real fleet consumer adopts the snapshot. |
| DV-08 | Existing tab behavior remains unchanged across mutation and restore. |
| DV-09 | Controlled workload evidence reports evaluations, computes, cache hits, and rich assembly duration before and after. |
| DV-10 | No performance improvement is claimed unless equivalent-workload evidence shows it. |
| DV-11 | Pane-rich adoption is blocked until its separate input-completeness and workload gate passes. |

## Proof Expectations

### Deterministic behavior

- Repeated reads with unchanged revisions return cached output without compute.
- Every contributing mutation family invalidates and recomputes.
- Equal and rejected mutations neither invalidate nor recompute.
- Ordered output always matches direct canonical assembly of the rich tab
  fleet.
- Hydration and compound commands cannot leave a stale final snapshot.
- Chained derived behavior preserves upstream-value-before-revision ordering.

No test may use wall-clock sleeps.

### Architecture enforcement

- Production construction occurs only in approved long-lived Core read models.
- The only first-slice constructor is the private stored/lazy instance owned by
  `WorkspaceTabLayoutAtom`.
- Compute cannot use ambient atom access or persistence APIs.
- Canonical keyed accessors cannot call rich fleet readers.
- Persistence cannot observe or serialize the derived snapshot.
- No new hot consumer calls the old fleet-composing compatibility path.

### Performance evidence

Use the existing atom telemetry lane and existing representative UI workload.
Compare an equivalent baseline and candidate for:

- derived evaluations;
- derived computes;
- cache hits;
- total and distribution of rich tab assembly duration; and
- the selected consumer’s existing surface metric.

The minimum success claim is fewer rich tab assemblies with unchanged behavior.
Latency improvement is reported only when measured. Atom telemetry must remain
opt-in so instrumentation does not distort standard workload proof.

### Manual product proof

In a real debug app with multiple tabs, panes, arrangements, and drawers:

- create, remove, rename, reorder, and select tabs;
- move panes and switch arrangements;
- exercise drawer state represented by the snapshot;
- restart and verify restored tab behavior; and
- confirm the adopted surface updates correctly with no stale labels,
  membership, selection, or ordering.

## Tradeoffs

### What we gain

- The existing primitive finally has a real production contract.
- Identical rich tab reconstruction is reused.
- Rich versus canonical reads become explicit.
- The first slice is separable from SQLite lifecycle work.

### What we pay

- Tab owners need complete, centrally enforced semantic revisions.
- Whole-tab-slice invalidation remains coarse.
- Cache misses still compute synchronously on `MainActor`.
- Compatibility callers remain migration debt until individually classified.

### Why not compare immutable fleet inputs on every read?

Changing `DerivedValue` to capture and compare complete arrays/dictionaries
would avoid revision bookkeeping but would add fleet comparison to every cache
hit and redesign the existing primitive before its first use. That is not the
smallest performance-oriented adoption.

### Why not adopt panes simultaneously?

Rich pane output crosses more owners and late hydration lanes than tabs.
Bundling it makes the first production use larger, harder to prove, and easier
to make stale. The gate retains the direction without coupling delivery.

## Non-Goals

- General reactive dependency tracking.
- Dependency injection, resolver, or service locator.
- Async or off-main derived scheduling.
- Blanket memoization of Core computed properties.
- Per-pane or per-tab atom-family migration.
- SQLite schema or lifecycle changes.
- Solving broad Swift Observation invalidation.
- Hiding rich work behind `pane`, `tab`, `value`, or similarly cheap-looking
  compatibility APIs.

## Security Context

This is not an authorization or data-storage change. Derived telemetry must
retain the existing fixed event/field allowlist and must not export IDs, paths,
titles, payloads, or dynamic type/instance names. No network destination,
secret, filesystem authority, or IPC scope changes.

## Open Questions for Planning

1. Which existing full-fleet consumer provides the cleanest first red/green
   adoption proof if `TabBarAdapter` is no longer dominant at implementation
   baseline?
2. Which owner-local mutation helper is the best repository-consistent place
   to centralize each tab revision?
3. Which old compatibility calls are removed in the same hard cut versus
   recorded as cold, measured exceptions?

These questions select implementation details; they do not reopen the ownership
or first-adoption boundary.
