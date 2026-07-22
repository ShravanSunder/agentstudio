# AgentStudio Swift Build-Slot Containment

Date: 2026-07-22
Status: ready for review
Scope: reduce the existing local Swift build-slot pool from four candidates to two

Related contracts:

- [Terminal runtime distribution](../2026-07-22-terminal-runtime-distribution/2026-07-22-terminal-runtime-distribution.md)
- [Debug app artifact containment](../2026-07-22-debug-app-artifact-retention/2026-07-22-debug-app-artifact-retention.md)

## Decision

Preserve the existing contention-prevention mechanism in
`scripts/swift-build-slot.sh` and change its fixed candidate indices from
`1 2 3 4` to `1 2`.

“Two slots” has only this meaning:

> For each existing build kind, the allocator can claim candidate `1` or
> candidate `2`. It does not create candidates `3` or `4`.

The current debug/release build-kind mapping, fixed directory prefixes, atomic
claim behavior, cleanup task, and explicit `SWIFT_BUILD_DIR` override behavior
remain unchanged. This spec does not define one debug slot plus one release
slot, merge build kinds, or create a new cache layout.

## Product Intent

Build slots prevent simultaneous Swift commands from mutating the same SwiftPM
scratch workspace. Fixed reusable slots also prevent the unbounded growth that
would result from PID-, timestamp-, UUID-, worker-, or random-named scratch
directories.

SwiftPM 6.2.4 shares downloaded binary archives through `--cache-path`, but
extracts binary artifacts into each `--scratch-path`. After terminal-runtime
extraction, a GhosttyKit XCFramework of roughly 571 MB can therefore still be
present in each active scratch workspace. Keeping two candidates preserves two
concurrent local builds for a build kind while bounding that duplication to two
reusable scratch trees for that kind.

## Current-State Evidence

At `5cf627ee`, `scripts/swift-build-slot.sh`:

- accepts `debug` or `release` as the build kind;
- maps them to `.build-agent-N` and `.build-release-agent-N`;
- tries fixed candidate indices `1 2 3 4` in order;
- claims a candidate with atomic `mkdir <slot>/.slot-claim`;
- exports the selected path as `SWIFT_BUILD_DIR`;
- removes its claim on handled shell exit;
- fails when all candidates for that build kind are busy;
- honors an explicitly supplied `SWIFT_BUILD_DIR`.

The mechanism is correct for contention control. Only the fixed pool size is
changing.

## Boundary and Separability Map

```text
scripts/swift-build-slot.sh
  preserves:
    existing build kinds and prefixes
    existing claim/release behavior
    existing explicit override behavior

  changes:
    candidate indices {1, 2, 3, 4} --> {1, 2}
                         |
                         v
existing mise build/test/bundle callers
  continue sourcing the same helper
  continue receiving SWIFT_BUILD_DIR

normative worker instructions
  describe the fixed two-candidate pool
  do not teach random or per-worker scratch names
```

The terminal-runtime spec changes what SwiftPM consumes inside a slot. The
debug-app-retention spec manages generated app bundles. Neither changes the
slot allocator.

## Requirements

| ID | Requirement |
| --- | --- |
| BS-01 | Preserve `scripts/swift-build-slot.sh` as the local contention-prevention mechanism. |
| BS-02 | For every build kind the helper already supports, change the ordered candidate set from `1 2 3 4` to exactly `1 2`. |
| BS-03 | Preserve the current build-kind-to-prefix mapping. |
| BS-04 | Preserve current claim acquisition, claim release, stale-claim cleanup, and explicit `SWIFT_BUILD_DIR` override behavior. |
| BS-05 | Two simultaneous same-kind callers can claim different fixed candidates. |
| BS-06 | A third same-kind caller fails with an updated two-slots-busy diagnostic and does not create another candidate. |
| BS-07 | Active scripts and normative instructions no longer describe candidates `3` or `4` as available. |
| BS-08 | Active scripts and normative instructions do not introduce PID-, timestamp-, UUID-, worker-, agent-, or random-named fallback slots. |
| BS-09 | Existing candidate `3` and `4` scratch trees are no longer selected after cutover and can be reclaimed through an explicit safe cleanup operation. |
| BS-10 | SwiftPM shared downloads remain shared; mutable scratch state remains separated by the two existing fixed candidates. |

## Existing Candidate 3 and 4 Data

Changing the loop prevents future use but does not recover disk already used by
`.build-agent-3`, `.build-agent-4`, `.build-release-agent-3`, or
`.build-release-agent-4`.

The implementation must provide a deliberate retirement operation that:

- targets only those four known legacy candidate paths in the current
  worktree;
- refuses to remove a path that is claimed or in use;
- does not use a broad `.build-*` deletion glob;
- is not part of ordinary build acquisition;
- reports what it removed and what it retained.

This one-time retirement is storage reclamation for the cardinality cutover,
not a new cache manager.

## Tradeoffs

### Gain

- two same-kind Swift workloads can still build concurrently;
- each build kind retains at most two allocator-owned scratch trees;
- no new slot naming or scheduling model is introduced.

### Cost

- a third simultaneous same-kind build fails until one of the two claims is
  released;
- reducing active cardinality does not remove other SwiftPM duplication across
  different worktrees or build kinds;
- already-created candidate `3` and `4` trees need an explicit safe retirement
  step.

## Explicit Non-Goals

- Redesigning debug versus release build handling.
- Changing how explicit `SWIFT_BUILD_DIR` overrides work.
- Redesigning claim metadata or stale-claim recovery.
- Moving scratch roots to a managed cache hierarchy.
- Adding TTL or size-based build-cache pruning.
- Sharing one mutable scratch workspace across worktrees.
- Eliminating SwiftPM's per-scratch binary-artifact extraction.
- Changing release-product discovery or bundle provenance.
- Solving terminal-runtime distribution or debug-app retention.

## Proof Expectations

The implementation plan must include:

- a focused allocator test showing candidate `1`, candidate `2`, then a clear
  busy failure for a third concurrent same-kind caller;
- negative proof that the third caller creates no candidate `3`, candidate `4`,
  or arbitrary fallback directory;
- regression proof that debug/release prefixes, claim/release behavior, cleanup,
  and explicit override behavior are unchanged;
- a scoped scan showing active scripts and normative instructions use the
  two-candidate wording and contain no random-slot recipe;
- a safe retirement fixture proving only unused legacy candidate `3` and `4`
  roots are eligible for removal;
- representative build/test use through the unchanged helper entry point.

## Open Decisions

None.
