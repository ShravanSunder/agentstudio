# Repository and Checkout Lifecycle Implementation Plan

## Planning record

- Planning result: revision-requested (plan-only; not executable)
- Admission gap: Claude review found unresolved move identity, Repair entry-point, retention, and cross-database cleanup contracts. Resolve these through the design owners before producing a ready plan.
- Originating planner: plan-implementation
- Governing Requirements: ../requirements.md
- Governing Specification: ../specification.md
- Governing Program Design: ../program-design.md
- Delivery context: plan-only; one repository-lifecycle delivery; no PR topology
- Planned source: branch repo-bugs, HEAD c64e3caded34a9cb1e4617592c4cdf44f7bd9146

## Goal

Make watched repository topology converge safely after folder moves, deletion, restart, and duplicate discovery. Retain unavailable repositories for 30 days, hide them from the normal list, restore them on proven rediscovery, provide explicit repair for ambiguity, and garbage-collect expired canonical and rebuildable state without deleting panes or user-authored history.

All Git semantics must come through the pinned `agentstudio-git` package and libgit2-backed clients. No Git CLI, `wt`, or direct Git subprocess is permitted.

## Non-goals

No hidden-repository user surface; no automatic name/remote merge; no persisted common-directory identity; no pane deletion; no terminal, undo, annotation, or history deletion; no new command/event plane.

## Vertical slices and dependencies

```text
A persistence contract and migration
  -> B authoritative scan/reconciliation
  -> C ordered removal, rediscovery, scope and late-fact guards
  -> D explicit repair and 30-day expiry cleanup
  -> E projection and end-to-end integration proof
```

Slices are serial because they share canonical topology, migrations, event fixtures, and persistence boundaries.

### A — Persistence contract

Extend unavailable repository state with durable hidden-since, absence reason, and scan generation. Add atom/store codecs and a migration against populated databases. Preserve repository/worktree UUIDs, path stable keys, SQL cascades, panes, terminal ownership, undo, and history.

Proof: non-empty migration/readback, rediscovery clearing metadata, generation monotonicity.

### B — Authoritative scan and reconciliation

Seed the actor-owned watched-folder baseline from restored topology before the first authoritative scan. Only complete authoritative results may assert negative space. Use `agentstudio-git` discovery evidence for repository-family grouping and one-to-one checkout matching; do not persist common-directory identity.

Proof: deleted repository, deleted linked checkout, cold-start deletion, complete versus partial scan, multiple checkouts, same-path rediscovery.

### C — Removal and event ordering

Use one removal path: canonical unavailable mutation, clear optional pane facets, ordered topology-effect filesystem reconciliation, cache/PR pruning, Forge unregister, persistence. Add membership/unavailable-generation guards before Git/Forge cache publication. Rediscovery clears hidden state before scope registration and enrichment admission.

Proof: watcher unregister, pane continuity, no late cache recreation, Forge unregister, normal projection excludes unavailable rows.

### D — Repair and expiry

Add a validated repository/worktree Repair command. Validate retained and candidate paths through `agentstudio-git`; require one family and one worktree identity; atomically update the retained record, remove the duplicate candidate, and clear hidden state.

Add one actor-owned reschedulable next-deadline task from hidden-since plus 30 days. Revalidate unavailable state and generation transactionally before deleting expired repository/worktree topology, tags, unavailable rows, rebuildable cache, PR facts, repository/worktree recency, and local activity. Preserve watched paths, panes, terminal ownership, undo, annotations, review history, and pane recency. Make retries idempotent.

Proof: before/after deadline, rediscovery race, repair race, retry, SQL cascade, protected-row preservation.

### E — Projection and integration

Unavailable repositories must not appear as normal rows or display “Scanning.” Distinct checkouts retain identity and ordering. Exercise moved checkout, moved repository, deleted parent, ambiguous duplicate, repair, and no-vanished-pane behavior through the real topology pipeline.

Manual proof: debug/beta app with PID targeting, watched-folder move/delete/restore, visible list, pane continuity, and watcher state.

## Obligation-to-proof map

| Obligation | Proof |
|---|---|
| Complete scan marks absence; incomplete scan preserves | Actor/reducer integration |
| Hidden rows omitted | Repo Explorer integration |
| Rediscovery restores identity | Coordinator plus SQL readback |
| Separate checkouts remain distinct | Discovery/reconciliation fixture |
| Ambiguous move requires repair | Command/coordinator integration |
| Pane survives and facets clear | Workspace topology integration |
| 30-day expiry cleans eligible state only | Persistence test with injected clock |
| Late facts cannot recreate cache | Stale-generation event fixture |
| Watchers unregister | Filesystem integration |
| libgit2-only boundary | Architecture lint and package-backed discovery tests |

## Validation gates

- Focused Swift tests for each changed target and integration suite.
- `mise run lint`.
- `mise run test:swift`, then aggregate `mise run test`.
- `git diff --check`.
- Native debug/beta smoke proof for the real watched-folder and pane path.

## Stop and replan

Return to design if identity evidence cannot safely prove repair, migration threatens protected history, cleanup requires deleting panes/sessions/undo/annotations, a new command/event plane is needed, direct Git integration appears necessary, or MainActor work expands to scanning, derivation, or deadline scheduling.
