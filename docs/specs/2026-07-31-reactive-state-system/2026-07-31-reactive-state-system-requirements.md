# AgentStudio Reactive State System — Requirements

This document records the authorized needs, priorities, and scope boundary for
AgentStudio's reactive-state work. The separate
[Specification](2026-07-31-reactive-state-system-specification.md) defines the
observable obligations that satisfy these needs. Internal structure belongs to
the linked program designs.

## Purpose

AgentStudio must preserve its bottom-up atom model while making state updates,
derived computation, actor isolation, persistence, and proof predictable enough
that UI work does not silently scale with unrelated application state.

The work serves two equally important outcomes:

1. users can type, scroll, navigate, focus, and change panes or tabs without
   unrelated state work causing visible stalls; and
2. developers can tell from a state API what owns it, what wakes it, whether it
   caches, where it computes, how stale work is rejected, and whether it
   persists.

## Authorized Needs

Every row below is authorized by the product owner, who also assigns priority.
`Required` is the highest priority for this design family; sequencing among
implementation slices is a later planning decision.

| ID | Affected class | Authorized need or outcome | Why it matters | Priority | Authority state |
|---|---|---|---|---|---|
| U1 | End users | Relevant state changes update the visible UI promptly, while unrelated changes do not cause avoidable work on the interaction path. | Typing, scrolling, navigation, focus, and animation must remain responsive as repositories, panes, tabs, and notifications grow. | Required | authorized |
| U2 | End users | Derived UI state is current, coherent, and never replaced by a superseded computation. | A fast stale result is still incorrect and can misrepresent the active workspace. | Required | authorized |
| U3 | Existing users | Supported state, command behavior, focus/navigation behavior, and restart behavior survive each migration slice. | Performance or architecture work must not trade away product correctness or existing data. | Required | authorized |
| U4 | Feature developers | Source state, keyed state, organizational grouping, and computed state use one consistent developer vocabulary with explicit mutation boundaries. | Ambiguous APIs make broad invalidation, direct mutation, and hidden recomputation easy to introduce. | Required | authorized |
| U5 | Feature developers | Variable-cost computation has a paved, compile-checked route away from `MainActor`, including cancellation and freshness semantics when work is replaceable. | Actor spelling alone does not prevent UI stalls or stale publication. | Required | authorized |
| U6 | Reviewers and maintainers | Mechanically detectable state-boundary violations fail compilation or the existing architecture gate, while semantic and performance claims require behavioral evidence. | Reviewers must not reconstruct every hidden dependency or accept unsupported compiler guarantees. | Required | authorized |
| U7 | Runtime and release operators | Performance comparisons identify the exact build, workload, instrumentation, interaction sequence, and event completeness. | Missing telemetry or mismatched binaries must not appear as an improvement. | Required | authorized |
| U8 | Users and persistence maintainers | Durable, local, cache, runtime-only, and derived state have explicit authority and failure behavior; a logical save cannot report success for a partial generation. | SQLite must preserve accepted state without becoming a high-frequency UI state bus. | Required | authorized |
| U9 | Maintainers | The migration proceeds through narrow, independently provable slices and reuses current Swift Observation, target boundaries, persistence owners, and proof systems. | A framework rewrite would increase churn, target coupling, and failure surface before the hot paths are proven. | Required | authorized |

## Confirmed Boundary

The design family may change:

- generic atom-family and derived-value primitives;
- Core- and Feature-owned state APIs that participate in a selected slice;
- bounded App-owned composition projections;
- authority-specific persistence save and restore boundaries;
- existing architecture rules, tests, telemetry, and performance comparators
  needed to prove a selected slice.

The following foundations are protected:

- Swift Observation remains the reactive substrate;
- `CoreAtomScope` remains the sole typed ambient product scope;
- `AtomRegistry` remains App-owned and Feature mutable state remains explicitly
  injected;
- the SwiftPM dependency direction remains App to Features/Core to
  Infrastructure, with no reverse target edge;
- SQLite remains authority-specific persistence rather than the live UI read
  model;
- existing debug launch, IPC, Victoria, architecture-lint, SQLite, and test
  systems are extended rather than duplicated.

## Complexity Boundary

This work does not authorize:

- a new reactive framework, dependency resolver, service locator, Feature
  registry, or universal state aggregate;
- a scheduler, worker pool, task runtime, retry framework, or persistence
  coordinator shared across unrelated authorities;
- one atom per property, one family for every collection, or caching every
  computed reader;
- routing every SQLite write through atoms or making independent databases and
  persistence lanes globally transactional;
- migrating every current worker, pane, tab, topology, session, or command
  surface in one change;
- a second telemetry, benchmark, debug-launch, architecture-lint, or test
  framework;
- a SwiftPM target split as part of the reactive-state implementation;
- using lazy actor-bound derivation for variable-cardinality Tab Bar
  reconstruction.

Scope reopens only when measured behavior or a second concrete product use
demonstrates that the selected narrow primitive cannot satisfy an authorized
need. Symmetry, naming completeness, or speculative reuse is not enough.

## Evidence and Remaining Hypotheses

Current source proves that keyed observation, revision-cached derivation,
off-main projection, authority-specific SQLite, and provenance-aware telemetry
already exist in partial forms. It also proves that some hot UI paths still use
broad snapshots or rebuild variable-cardinality projections on `MainActor`.

The following remain hypotheses until measured for an exact implementation
slice:

- the user-visible severity of each current hot path;
- whether an entity-sized keyed slot is still too broad for any specific fact;
- whether an existing Feature worker benefits from a shared eager primitive;
- the numeric performance improvement available from any selected migration.

These hypotheses may select or defer a slice. They do not authorize a broader
state-system rewrite.

Evidence basis:

- the current implementation provides row-level evidence for broad collection
  reads, keyed slots, revision caching, MainActor fleet reconstruction,
  feature-local workers, persistence transactions, and proof tooling;
- the existing atom-scope, performance-boundary, and persistence-ownership
  contracts authorize the protected foundations above;
- this Requirements identity is the product owner's durable authorization for
  U1–U9. Observational evidence explains the need but does not independently
  authorize a new outcome.

| Authorized rows | Row-level basis |
|---|---|
| U1, U2 | Product-owner authorization plus current broad-observation, synchronous projection, and stale-admission source paths. |
| U3 | Product-owner authorization plus the governing compatibility, migration, and real-relaunch proof contracts. |
| U4, U5 | Product-owner authorization plus current keyed-slot, revision-cache, actor-isolation, and feature-worker source paths. |
| U6 | Product-owner authorization plus the existing compiler, ArchitectureLint, Observation-test, and runtime-proof boundaries. |
| U7 | Product-owner authorization plus the governing provenance and performance-comparison contract. |
| U8 | Product-owner authorization plus the persistence-ownership hard cut and current logical-save/restore paths. |
| U9 | Product-owner authorization plus the current atom scope, Feature-injection, SwiftPM target, and proof-system boundaries. |

## Acceptance Boundary

This Requirements identity is complete when every authorized `U` row remains
traceable through the separate Specification and no downstream artifact adds a
user, outcome, compatibility promise, persistence authority, or complexity
class not authorized here.
