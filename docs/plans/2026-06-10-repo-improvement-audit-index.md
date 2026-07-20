# 2026-06-10 Repo Improvement Audit — Plan Index

Planned at: a80ebb05 (branch `improve-v1`)
Audit method: 7 parallel read-only audit lanes + 4 adversarial deep-dive
lanes; every accepted finding re-verified against source by the parent agent
before planning. Rejected claims are recorded inside each plan's evidence
section so they are not re-reported by future audits.

## Plans (priority order)

| Status | Plan | Why now | Primary proof |
| --- | --- | --- | --- |
| proposed | [zmx-lifecycle-hardening](2026-06-10-zmx-lifecycle-hardening.md) | Orphan cleanup is fire-and-forget with wall-clock timeout and all-or-nothing skip (orphans accumulate unboundedly); `detect()` blocks main thread at boot; health checks unbounded | planner + health-timeout tests; prompt quit during cleanup |
| proposed | [ghostty-action-routing-safety](2026-06-10-ghostty-action-routing-safety.md) | `preconditionFailure` in C-callback action routing violates the crash-isolation contract; focus-handle read→use TOCTOU at teardown | action-tag exhaustiveness test; concurrent clear/sync test |
| proposed | [sqlite-drawer-persistence-proof](2026-06-10-sqlite-drawer-persistence-proof.md) | No drawer save→restore round-trip coverage; lossy crash windows untested and silent; read-side drawer parent validation missing | drawer round-trip suite; crash-window commit-protocol tests |
| proposed | [inbox-notification-correctness](2026-06-10-inbox-notification-correctness.md) | Auto-clear fires for visible-but-unattended panes (contract drift); focus tracker dies permanently on stream end; SQL lane list can drift from enum | attended-vs-observed tests; tracker restart test; lane exhaustiveness test |
| obsolete | [terminal-restore-and-startup-performance](2026-06-10-terminal-restore-and-startup-performance.md) | Historical discovery/deferral model; superseded by opaque stored identity, UUIDv7 generation for new values, and mutation-free restore | retained as non-normative evidence only |
| proposed | [filesystem-watch-swift62-hygiene](2026-06-10-filesystem-watch-swift62-hygiene.md) | Unbounded FSEvents ingress stream; sync `.gitignore` I/O on actor executor; `.zero` coalescing default footgun | storm/buffering test; projector coalescing test |
| proposed | [pane-shell-decomposition](2026-06-10-pane-shell-decomposition.md) | 3,245-line `PaneTabViewController` (~13 jobs); domain decisions in coordinator | characterization tests pass unchanged post-extraction; line-count gate |

## Recommended next skill per plan

- Execute: `implementation-execute-plan` (each plan carries its handoff
  prompt).
- Pre-execution adversarial review (recommended for the SQLite and zmx plans):
  `plan-review-swarm`.

## Headline claims investigated and REJECTED (do not re-fix)

- Inbox unread-count atom/repository desync — refuted by full trace: struct
  mutations fire `@Observable`; saves are full snapshot replaces; coalescence
  and retention verified identical both sides.
- SQLite dangling cursor IDs on staged restore — staging sets
  `completed_at = NULL` (`WorkspaceCoreRepository.swift:236-240`), token
  mismatch forces default local state, and cursor atoms validate IDs at
  hydration.
- Stale drawer cursor rows — local cursor writes are full-replace per
  workspace.
- Drawer changes dropped on quit — `AppDelegate+Termination.swift` flushes all
  stores (incl. inbox) with bounded drains.
- SurfaceManager collection-move "race" — handlers are synchronous on
  MainActor; no suspension between snapshot and write-back.
- AppFocusSynchronizer missed-transition race — no await between sync and
  re-observation; last-writer-wins is correct for focus.
- RestoreTrace formatting cost in production — `@autoclosure` evaluated only
  behind the enabled guard.
- Scroll-tick `sizeDidChange` storms — per-tick path only sets
  `frame.origin`; row dispatch deduped by `lastSentRow`.
- prettyPrinted JSON on hot save path — workspace + repo-cache stores save via
  SQLite; JSON is the legacy fallback.
- 10s launch sleep — diagnostic watchdog with timeout recovery, not a launch
  blocker.
- IOERR-should-quarantine — corruption-only quarantine is the documented
  invariant (CLAUDE.md), not a bug.
- Legacy import mutating `active_workspace_id` — selection happens only via
  the explicit importer outcome path with `keepsCurrentSelection` honored.

## Known-accepted design tradeoffs (documented, not planned)

- Local UX state (drawer expansion, cursors) is deliberately lossy across the
  staged-only crash window; the sqlite plan makes this proven + observable
  rather than changing it.
- Sub-500ms debounce exposure for inbox read-state on hard crash (termination
  flush covers normal quit).
- FSEventStream latency (0.1s) behind the 500ms debounce — revisit only with
  profile data.
