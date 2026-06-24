# Ticket 02: Gate 2 Worktree/File And Review App Protocols

Status: draft for plan-review-swarm
Depends on: Tickets 00-01

## Deliverable

Implement application protocols on top of generic Bridge:

- Worktree/File protocol source lifecycle, descriptors, invalidation, stale
  refresh, file/tree/status metadata, and bounded content requests
- Review protocol comparison lifecycle, static diffs, live worktree comparisons,
  changeset clusters, and descriptor-backed content
- app-specific materializers
- app-specific demand policies that map protocol interest to generic lanes
- large-data-out-of-Zustand invariants

## Reviewer Reminder

Review this ticket against the prior false-green failure mode. Ask whether app
protocol proof could pass while the user-visible Worktree/File or Review product
surface is still wrong, or while large bodies silently enter Zustand.

## Ownership Boundary

Worktree/File and Review own domain semantics. Generic Bridge owns carriers,
descriptor mechanics, scheduling primitives, and bounded execution.

## Vertical Slices

1. Worktree/File materializer and state
   - unit/component proof for source reset, descriptor update, open-file stale
     state, and refresh
   - no file bodies in Zustand

2. Worktree/File demand policy
   - app stimuli map to generic lanes
   - invalidated open files mark stale without silent replacement

3. Review materializer and state
   - static package frames materialize without whole-pane reset
   - live comparison frames preserve source/version lineage

4. Review demand policy
   - visible/active/foreground work maps to generic lanes
   - stale resource completions are rejected

5. Changeset runtime contract
   - live, closed, pinned, degraded, reset cases
   - provider-owned cluster ids and checkpoints

## Proof Gates

Required:

- focused unit tests for materializers and app demand policies
- integration tests for source reset and stale resource completion
- browser fixture for live worktree/change-set behavior where applicable
- no large bodies in Zustand snapshots
- Gate 0 current-worktree product proof remains green before this ticket closes

## Required Commands

```bash
pnpm --dir BridgeWeb run test -- <focused app protocol tests>
pnpm --dir BridgeWeb run test:browser:integration -- <focused browser tests>
pnpm --dir BridgeWeb run check
pnpm --dir BridgeWeb run test:dev-server:worktree
mise run lint
```

phase_result: complete
evidence: Gate 2 ticket drafted with app ownership and proof gates.
recommended_next_workflow: shravan-dev-workflow:plan-review-swarm
recommended_transition_reason: Gate 2 has a reviewable implementation ticket.
