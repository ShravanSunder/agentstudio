# Incremental Review Git Refresh — Requirements

Date: 2026-09-03

Decision authority: Agent Studio owner.

Related authority:

- [PR0 Review Comparison requirements](../2026-08-06-worktree-annotations/pr0-user-requirements.md)
- [Bridge Review Refresh Classification requirements](../2026-08-21-bridge-review-refresh-classification/2026-08-21-requirements.md)
- [Bridge Metadata Application Protocol requirements](../2026-08-27-bridge-metadata-application-protocol/2026-08-27-requirements.md)

## Problem

Agent Studio already receives exact worktree-relative paths for ordinary file
changes and coalesces bursts before refreshing Review. Review construction does
not use that information. A one-file edit therefore starts another complete
base-to-working-tree comparison and rebuilds metadata for every file in a large
Review before publication can discover that only one item changed.

In the shared observability stack's last-30-day debug/test window, Review
construction recorded 10,706 invalidations for 271 builds: about 39.5
invalidations per build. This is debug-configuration and fixture evidence, not
production usage. Repeating the complete Git comparison for ordinary same-path
edits makes live Review work scale with unrelated branch size and competes with
commenting, reading, and subsequent refreshes.

## Affected people

- Human reviewers reading and commenting while developers or agents edit the
  reviewed worktree.
- Developers and agents expecting an ordinary file save to appear promptly in
  an already-open Review.
- Agent Studio maintainers who must preserve exact Git behavior while removing
  work that does not contribute to the successor Review.

## Goal boundary

Preserve one complete, exact, immutable Review successor while allowing an
ordinary, exhaustively identified same-path file modification to recompute only
the affected Git metadata. Any structural, incomplete, or uncertain change
continues through the existing complete comparison.

```text
ordinary exact file modification
  -> calculate affected Git metadata only
  -> assemble one complete successor privately
  -> publish through the existing atomic Review path

structural or uncertain change
  -> existing complete comparison
  -> publish through the same atomic Review path
```

This work may change Agent Studio’s Review refresh calculation contract and the
`agentstudio-git` API used by Agent Studio. It must not change comparison-target
meaning, comment behavior, presentation classification, metadata transport, or
visible partial-result policy.

## Authorized needs

### U-IRR-001 — Make ordinary edits proportional to affected work

- Affected class: reviewer, developer, and agent.
- Need: An ordinary same-path content edit must not cause Git to reread and
  recalculate unrelated Review files.
- Why: The cost of one edit should not grow with hundreds of unrelated branch
  changes.
- Priority: must.
- Authority state: authorized by the Agent Studio owner.

### U-IRR-002 — Preserve complete Review truth

- Affected class: reviewer.
- Need: Every installed successor must still describe the complete comparison,
  including committed, staged, unstaged, untracked, deleted, renamed,
  type-changed, binary, mode, hash, size, and line-total facts.
- Why: Faster calculation is unacceptable if the Review silently omits or
  misclassifies work.
- Priority: must.
- Authority state: authorized by the Agent Studio owner and existing PR0
  requirements.

### U-IRR-003 — Fall back when scope is uncertain

- Affected class: reviewer and maintainer.
- Need: Structural changes, incomplete path evidence, source movement, and
  unexpected incremental results must use the existing complete comparison.
- Why: Conservative extra work is cheaper than publishing an incomplete Review.
- Priority: must.
- Authority state: authorized by the Agent Studio owner.

### U-IRR-004 — Keep visible Review atomic and interactive

- Affected class: reviewer.
- Need: Incremental calculation must remain private until one complete current
  successor is ready; the retained Review and all permitted comment operations
  remain usable meanwhile.
- Why: Calculation efficiency must not introduce partially updated geometry or
  interrupt review work.
- Priority: must.
- Authority state: authorized by existing refresh requirements.

### U-IRR-005 — Prefer newest work under edit bursts

- Affected class: reviewer, developer, and agent.
- Need: Coalesced edits and edits racing calculation must converge on the newest
  complete Review without installing intermediate or stale candidates.
- Why: Rapid edits are normal and must not create replay churn or lost updates.
- Priority: must.
- Authority state: authorized by existing latest-generation requirements.

### U-IRR-006 — Keep Git behavior in `agentstudio-git`

- Affected class: Agent Studio maintainer.
- Need: Git comparison, path-scoped calculation, metadata combination, and
  conservative Git fallback policy remain owned by `agentstudio-git`; Agent
  Studio supplies currentness and existing invalidation facts.
- Why: Agent Studio is the sole consumer, but it must not grow a second Git
  semantics implementation.
- Priority: must.
- Authority state: authorized by the Agent Studio owner and repository
  architecture policy.

### U-IRR-007 — Bound retained calculation material

- Affected class: operator and maintainer.
- Need: Efficiency work may retain only bounded Git metadata needed for the
  current Review calculation lifetime; it must not retain copied source files or
  create unbounded per-edit or per-generation history.
- Why: Latency improvement must not become a memory, disk, or lifecycle leak.
- Priority: must.
- Authority state: authorized by the Agent Studio owner.

### U-IRR-008 — Prove real speed and semantic parity

- Affected class: reviewer and maintainer.
- Need: The implementation must prove identical complete results against fresh
  full comparison and demonstrate that one-file refresh cost no longer scales
  with the total unrelated Review file count in both development and packaged
  operation.
- Why: Unit-level route selection cannot establish correctness or product
  performance.
- Priority: must.
- Authority state: authorized by the Agent Studio owner and existing
  performance requirements.

## Non-goals

- Changing Review UI, update-bar policy, focus holds, or comment commands.
- Publishing path-by-path or partially complete Review state.
- Making rename, add, delete, type-change, conflict, attribute, ignore, or
  Git-internal changes incremental in the first realization.
- Caching source-file contents, rendered diffs, comments, transport frames, or
  historical Review generations.
- Adding another filesystem watcher, worker, queue, scheduler, database, store,
  transport route, or background preload service.
- Modifying vendored libgit2.
- Weakening exact hashes, binary classification, rename behavior, modes, sizes,
  ordering, or additions/deletions.

## Success evidence

- A real one-file edit in a large Review performs no Git content or line-stat
  calculation for unrelated Review paths.
- The resulting complete snapshot is byte-equivalent to a fresh complete
  comparison.
- Structural and uncertain cases demonstrably take the complete path.
- Edits racing calculation converge on the newest complete generation.
- The existing Review/comment/Vite/packaged journeys remain functional and
  interactive.
- Retained Git metadata remains within its declared active/candidate bound and
  is released with its owning Review calculation lifetime.
