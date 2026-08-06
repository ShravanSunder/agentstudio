# PR 1 — AtomFamily and Lazy DerivedAtom Implementation Plan

## Outcome

Hard-cut the generic primitive names and semantics, then use retained lazy
worktree-facts nodes so Repo Explorer observes only worktree keys present in its
current projection request. Preserve the existing projection worker, persisted
cache representation, stale-value cleanup, and explicit persistence flush.

This plan implements only PR 1 from the
[reactive-state Program Design](../README.md). It does not implement eager
materialization, Tab Bar work, SQLite changes, other family migrations, worker
migrations, Command Bar work, or a new proof framework.

## Change Flow

```text
pure rename commit
  AtomEntityMap.swift -> AtomFamily.swift
  DerivedValue.swift  -> DerivedAtom.swift
  directly named tests/fixtures/rules -> matching names

semantic implementation
  AtomFamily
    -> retained tombstoned keyed slots
    -> per-key semantic revision
    -> membership revision only for insert/remove
    -> redundant absent removal is a no-op
    -> no physical nil-slot pruning

  DerivedAtom
    -> retained lazy revision-keyed cache
    -> public revision materializes value first
    -> output revision changes only for unequal materialized output

product adoption
  RepoEnrichmentCacheAtom
    -> retains one worktree-facts DerivedAtom per requested worktree ID
    -> declares worktree-enrichment and pull-request-count key revisions

  RepoExplorerView
    -> derives relevant IDs from current sidebar topology
    -> reads worktreeFacts(for:) for only those IDs
    -> preserves the existing projection worker and result admission
```

## Tasks and Proof Gates

### 1. Preserve rename history

- Move the two primitive files and directly corresponding tests, fixtures, and
  architecture-rule files with `git mv` only.
- Commit the pure moves before editing file contents.
- Verify the move commit has no content changes.

### 2. Implement primitive semantics test-first

- Rename Swift symbols without compatibility aliases. Preserve the existing
  `entity_map` and `derived_value` telemetry vocabulary so the existing
  workload and pre-cut performance baseline remain comparable.
- Add red/green Swift Observation coverage for:
  - missing read then insert;
  - unrelated-key isolation;
  - removal callback synchronously re-registering, followed by reinsertion;
  - redundant absent removal producing no revision or callback;
  - per-key revision and membership-revision semantics;
  - `replaceAll` and `removeAll` retaining tombstoned slots.
- Add red/green lazy-derived coverage for:
  - cache hit;
  - changed-input recomputation;
  - equal output preserving output revision;
  - unequal output advancing output revision once;
  - downstream-only chained reads materializing the upstream node first.
- Update the existing ArchitectureLint rule, fixtures, and compile-negative
  fixtures for the hard-cut names and retained declared-input contract.

### 3. Adopt keyed worktree facts test-first

- Retain worktree-facts nodes inside `RepoEnrichmentCacheAtom`; do not expose
  those nodes to callers and do not introduce a generic derived-family type.
- Remove generic/product `pruneNilSlots` and the boot call to it while retaining
  stale repo/worktree value removal and the existing explicit persistence flush.
- Replace Repo Explorer's filtered `worktreeFactsSnapshot()` request input with
  reads for only current sidebar worktree IDs.
- Prove with real Observation that a relevant worktree change re-admits the
  request and an unrelated worktree change does not. Use bounded events/state,
  not sleeps.
- Preserve current search/filter, cancellation, result/error admission, and
  cold snapshot consumers.

### 4. Verify PR 1

- Run plain `mise run setup`.
- Run the focused AtomLib, repo-cache, Repo Explorer, boot-cleanup, and
  ArchitectureLint tests; then `mise run lint` and `mise run test`.
- Launch only through the detached worktree-isolated debug observability path.
  Verify process identity and exercise Repo Explorer search plus a relevant
  worktree update without taking foreground focus.
- Reuse the existing watched-folder/Victoria workload and comparator. Report
  matched provenance, distributions, continuity, and regression bounds; do not
  claim improvement if the controlled comparison does not establish it.
- Inspect the final diff against the governing plan and confirm the exclusions
  remain untouched before pushing the first PR.

## Stop Conditions

Stop and return to design only if current source requires a new ownership
boundary, public product contract, ambient resolver, second state authority, or
new runtime/proof framework. Ordinary rename fallout, access-control edits, and
test updates inside the named files are implementation work, not scope growth.
