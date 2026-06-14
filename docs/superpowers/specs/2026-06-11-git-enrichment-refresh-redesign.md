# Workspace Enrichment Refresh & Main-Thread Performance

Status: design (post-review revision)
Repo: agent-studio
Evidence: `tmp/debug-workflows/2026-06-11-agent-studio-performance-issues-cmdp-slowdown/debug-investigation.md` (live samples, spawn captures)

## Problem

The git enrichment pipeline sweeps every registered worktree every 2 seconds
(`FilesystemGitPipeline.swift:32`, `GitWorkingDirectoryProjector.swift:357-382`).
At 118 repos / 163 worktrees / 14 panes this attempts ~81 status computations/s
× 3 subprocesses each with **no concurrency bound anywhere**; the system
backlogs (observed git processes alive 1-3s). Every completed status posts
`.snapshotChanged` unconditionally; the coordinator writes the enrichment atom
unconditionally; `@Observable` invalidates every reader; each render walks an
O(repos × worktrees) path lookup on MainActor. Result: ~99% main-thread
occupancy at idle, cmd+P/management-layer slowdowns, app-wide typing lag.

## Measured Timing Model (where main-thread time actually goes)

From the live 1ms sample (`sample-idle-85554.txt`): 3409 main-thread stack
snapshots over 5s; the count before a frame = snapshots where that frame was
on the stack, so count/3409 = fraction of wall time in that code path.
Buckets below are *inclusive and overlapping*, not a disjoint pie — the
disjoint facts are: main thread busy 3365/3409 (**98.7%**; only 44 samples
parked in `mach_msg`), split ~2296 runloop/render vs ~1113 main-actor task
resumptions (`completeTaskWithClosure` — coordinator + adapter Tasks).

| Stage | Isolation | On-stack share |
|---|---|---|
| `repoAndWorktree(containing:)` walks (≈490 `standardizedFileURL`/call, 2.5-10ms/call; appears in both the body-render and task branches) | MainActor (SwiftUI bodies + TabBarAdapter refresh) | **2255/3409 ≈ 66%** |
| Remaining render work (TabBarAdapter pane rebuilds, AttributeGraph updates, layout) | MainActor | ~30% |
| Coordinator delivery + atom writes (163-entry dict copy, 20-50µs/write) | MainActor | ~1-2% |
| `@Observable` registrar bookkeeping proper (`ObservationRegistrar.access` 13, `withMutation` 7) | MainActor | **~0.5% — negligible; not a lever** |
| Sweep scheduling, bus post/fan-out, git compute, FS ingress | projector/bus/filesystem actors + `@concurrent` provider | ~0 (already off-main) |

Load-bearing facts a plan must respect:

1. **Render is >95% of the main-thread cost.** Unconditional posts/writes are
   the *trigger*; the *cost* is per-invalidation derived recompute. The
   effective write rate is the subprocess **completion** rate (~18-54/s), not
   the 81/s attempt rate (`pendingByWorktreeId` bounds backlog per worktree).
2. **Everything heavy except render is already off-main.** The projector is an
   actor; git compute is `@concurrent nonisolated`
   (`GitWorkingTreeStatusProvider.swift:64-68`); FilesystemActor, ForgeActor,
   EventBus, SQLite datastore are actors. "Move work off the main actor" is
   therefore **not an available lever** for the bulk of this problem — the
   levers are *make main-actor work rare* (frequency) and *cheap* (per-event
   cost), plus the specific per-envelope main-thread defects below.
3. **Invalidation consumers per enrichment write:** 14 × `PaneLeafContainer`
   bodies (2× `PaneManagementContext.project` + inbox-scope resolve each),
   **`TabBarAdapter` full refresh** (explicit whole-dict observation at
   `TabBarAdapter.swift:108`; rebuilds rich panes for all panes — #2 surface
   in the sample), sidebar and command bar when visible. One worktree's write
   invalidates all of them (whole-dict `@Observable` granularity).
4. **A single genuine change costs ~40-75ms of main-thread render today**
   (5-9 dropped frames). Agent-busy worktrees produce genuinely-different
   snapshots near the 2s flush cadence by design, so dedup alone does **not**
   make the dominant workload smooth — the render-path cost fix is
   load-bearing, not deferrable (see Phase 1, render tasks).

## Design Direction

**Tiered, budget-bounded sweep as the source of truth; filesystem events as
acceleration.** If any event is lost, the cost is bounded extra latency —
never a wrong badge. Events-primary was considered and rejected:

1. **Linked-worktree attribution hole (verified).** A linked worktree's git
   admin dir lives at `<main-clone>/.git/worktrees/<name>/`; routing is
   deepest-registered-root (`FilesystemRootOwnership.swift:51-64`), so
   commits/branch ops in linked worktrees attribute to the main worktree. The
   dominant agent workflow would never refresh its own badge. **This is also
   why the sweep is the badge-latency path for the focused worktree** — the
   event path cannot serve foreground freshness for linked worktrees.
2. **Events are lossy at four layers:** silent FSEventStream creation failure
   (`DarwinFSEventStreamClient.swift:93-95,177-182`), discarded event flags
   (`:27`), `bufferingNewest(256)` bus shedding, consume-and-drop failed
   computes (`GitWorkingDirectoryProjector.swift:207-216`). The sweep is the
   self-heal; its slow replacement keeps that role deliberately.
3. **Sweep removal doesn't reduce load for busy worktrees** — they refresh at
   `maxFlushLatency = 2s` via events anyway (`FilesystemActor.swift:96`).

## Tier Model (resolved: 2 buckets + focus boost)

| Bucket | Membership | Sweep cadence | Notes |
|---|---|---|---|
| Active | worktrees with ≥1 open pane | 15s self-heal | covers pane chrome, tab badges, their sidebar rows; focus/events refresh sooner |
| Background | all other registered worktrees | 240s, striped | sidebar/cmd+P rows of never-opened worktrees; still event-accelerated |

Plus a **focus boost**: forward `setActivePaneWorktree` to the projector and
enqueue an immediate refresh on pane-focus change. This beats a third 2-5s
"foreground" cadence on switch latency and avoids a third policy row. A
separate foreground cadence is added only if post-fix measurement shows the
focused linked-worktree badge lagging user-visibly.

Striping/jitter mechanism: each background worktree gets a stable stripe
offset (`hash(worktreeId) % stripeCount`) so each tick sweeps ~163/N
worktrees; no wall-clock jitter source needed, and a post-wake pending tick
admits only one stripe (bounded herd) — full wake ingress is Phase 2.

Capacity arithmetic (re-derivable, lives next to the constants): budget 4
concurrent with one fairness slot bounds spikes, while steady self-heal demand
is kept below the measured idle budget: active(~5-14 panes' worktrees / 15s ≈
0.3-0.9/s) + background(163/240s ≈ 0.7/s) ≈ 1.0-1.6/s. Focus changes and
filesystem/git events bypass that cadence and enqueue immediately, so user-
visible freshness is event/focus-driven while the sweep remains reconciliation.

## Mandatory Invariants

Each is assigned to a phase; "every variant of this design needs these."

1. **Concurrency budget** (~4) with **tier-priority admission** (active before
   background; one slot reserved for the oldest-stale entry to prevent
   starvation). Bounds boot (163 eager registration snapshots), wake, and
   activation herds. *Phase 1.*
2. **Input filter:** changesets whose only content is suppressed ignored
   paths (`.build`/`node_modules` churn — `FilesystemActor.swift:56-58` counts
   them as pending) must not trigger refresh; refresh only on
   `projectedPaths` or `containsGitInternalChanges`. *Phase 1.*
3. **`GIT_OPTIONAL_LOCKS=0`** on status/diff invocations (env merge via
   existing `ProcessExecutor` inherited-env path; constant value, no new parse
   surface). `git status` opportunistically takes `index.lock` today and
   intermittently breaks user/agent commits — live bug independent of this
   redesign. *Phase 1.*
4. **Projector output dedup:** skip posting `.snapshotChanged` when equal to
   the last emitted snapshot for that worktree (`GitWorkingTreeSnapshot` is
   timestamp-free `Equatable`). Origin checks still run on empty-path periodic
   changesets (origin freshness is not in the snapshot). *Phase 1.*
5. **Atom write gate via content equivalence** (`hasSameCacheContent`:
   identity + branch + `isMainWorktree` + `snapshot`, excluding `updatedAt`).
   Do **not** change `==`/`Hashable` — persistence/projection blast radius is
   avoided entirely (supersedes the earlier "fix `==`" direction; matches the
   existing plan's Task 1). Gate lives in `RepoEnrichmentCacheAtom` so every
   producer is covered. *Phase 1.*
6. **Reconciliation iterates topology-atom truth through one lifecycle path.**
   `register`/`unregister` must not gain a second direct authority inside the
   projector. Mechanism: a periodic re-assert from the PaneCoordinator sync
   pass (it already iterates topology truth), stamped with a topology
   epoch/generation or equivalent so stale delayed facts cannot resurrect
   removed worktrees; note today's `contexts-equal` guard
   (`PaneCoordinator+FilesystemSource.swift:106`) blocks healing of a dropped
   `worktreeRegistered` forever. Activity/focus facts may be forwarded
   directly as priority hints, not lifecycle truth. *Phase 1 (cheap seam),
   hardened in Phase 2.*
7. **Single policy value type** (`AppPolicies.GitRefresh`): cadences, stripe
   count, budget, debounces, boot ramp. One production default, explicit test
   fixtures — kills the `.zero`-default test/prod divergence class
   (`coalescingWindow` default `.zero` vs prod 200ms is the live instance).
   *Phase 1.*
8. **Failed computes requeue once with backoff** through the existing pending
   mechanism (bounded; no infinite retry). *Phase 1.*
9. **Swift 6.2 pins (SE-0461):** git compute stays `@concurrent` behind the
   provider protocol across the budget refactor (a plain actor-method inline
   would serialize 2s subprocess waits on the projector executor);
   `FilesystemPathFilter.load` sync I/O currently runs **on** the
   FilesystemActor executor (`FilesystemActor.swift:144,255`) and must move
   `@concurrent` before the input filter leans harder on it. *Phase 1.*

## MainActor Discipline

The rule: **nothing runs on the main actor between fact production and the
accepted-state write except the write itself and the render read — and
neither may do O(fleet) work.**

Audited main-actor bus consumers: `WorkspaceCacheCoordinator` (`:43`),
`PaneCoordinator` ingress (`:312`), inbox/terminal routers. Defects against
the rule, all main-thread, all in scope:

| Defect | Evidence | Fix | Phase |
|---|---|---|---|
| `PaneCoordinator.handleFilesystemEnvelopeIfNeeded` eagerly computes full rich-pane derivation **and** `workspaceWorktreeContextsById()` (163 × `standardizedFileURL.resolvingSymlinksInPath()` — real lstat syscalls) for **every** worktree envelope, though consumption only acts on `.filesChanged` | `PaneCoordinator+FilesystemSource.swift:26-55,154-165` | guard event family before computing args; memoize contexts by topology revision | **1** |
| O(repos×worktrees) `standardizedFileURL` per render walk | `WorkspaceRepositoryTopologyAtom.swift:39-98` | topology-owned normalized path index, rebuilt at mutation points; panes with explicit `repoId`/`worktreeId` already skip the walk (`WorkspacePaneDerived.swift:74-80`) — prefer ids, backfill facets | **1** |
| Duplicate `PaneManagementContext.project` per pane body | `PaneLeafContainer.swift:241-251` | reuse context when location target == pane | **1** |
| Command bar rebuilds all rows + per-row pane-location scans per keystroke, no debounce | `CommandBarView.swift:86-135` | batch presence map; keystroke gate | **1** |
| `SurfaceManager` health tick writes `@Observable` state unconditionally every 2s per surface | `SurfaceManager.swift:619-628,742-753` | guard-before-write (overlaps 2026-06-10 plan task 4) | **1 (small)** |
| `paneCount(for:)` routes through full derived pane build per worktree in the activity sync pass | `PaneCoordinator+FilesystemSource.swift:81`, `WorkspacePaneAtom.swift:92-94` | read pane graph atom directly | **1 (small)** |
| Derived read models recompute per access (`Derived.swift:9-11`) | 2026-06-10 plan task 5 | revision-keyed memoization, measurement-gated | **2** |
| Whole-dict invalidation granularity | `RepoCacheAtom.swift:16` | per-worktree observation surface | **2 (gated)** |
| Legacy JSON repo-cache lane does sync disk write on main | `RepoCacheStore.swift:257-272` | retire the legacy lane (hard cutover), don't async-ify | **2** |

Already off-main (no false wins to claim): projector scheduling, git compute,
FilesystemActor, ForgeActor (45s cadence — not the storm), EventBus, SQLite
datastore writes; `RepoCacheStore` persistence is already projection-gated
(`RepoCacheStore.swift:409-421`).

## Phase 1 — make main-actor work rare AND cheap

Scope = the existing implementation plan
`docs/plans/2026-06-11-agent-studio-idle-git-render-performance.md`
(Tasks 1-6: dedup both layers, activity-gated sweep, normalized topology
index, render projection reuse, command-bar presence batching, proof) **plus
the following amendments that plan does not yet contain**:

- concurrency budget + tier-priority admission (invariant 1)
- input filter for suppressed-only changesets (invariant 2)
- `GIT_OPTIONAL_LOCKS=0` (invariant 3)
- `PaneCoordinator` envelope-family guard + context memoization (discipline
  table row 1 — distinct code path from the render walk)
- focus-boost forwarding (`setActivePaneWorktree` → projector)
- stripe mechanism + policy value type (invariants 7), requeue (8), 6.2 pins (9)
- SurfaceManager write guard, `paneCount` direct read (small rows above)

Honest cost: ~150-250 production lines plus tests (the earlier "~60-100"
estimate excluded invariants 1-3 and 6-9). Activity plumbing note: the
projector learns registration via bus but activity via direct call — it must
accept activity for not-yet-registered worktrees (do not copy
`FilesystemActor`'s registered-only guard).

## Phase 2 — measurement-gated main-thread reduction

**Redefined.** Phase 2 is *not* scheduler extraction; the projector is already
an actor, and extraction changes zero main-thread numbers. Phase 2 is the
residual render-cost work, entered only if the busy-workload re-profile after
Phase 1 shows `repoAndWorktree`/derived recompute still >~10% of main-thread
samples or per-change render >1 frame (8ms):

- Derived/`PaneManagementContext` revision-keyed memoization — **superseded
  by `2026-06-11-atomlib-v2-state-primitives.md`** (DerivedValue primitive,
  inventory row 2).
- Per-worktree enrichment observation granularity — **superseded by
  `2026-06-11-atomlib-v2-state-primitives.md`** (AtomEntityMap, inventory
  row 1; includes the required per-row view restructuring).
- `.lossy(key: worktreeId)` reclassification of `snapshotChanged` for
  frame-coalesced delivery — **gated on a consumer audit** (inbox/terminal
  routers currently assume every-event delivery; worktree envelopes are
  hardcoded `.critical`).
- ForgeActor visibility gating; wake ingress via `ApplicationLifecycleMonitor`.

Scheduler extraction (`GitRefreshScheduler` actor) is demoted to a
conditional refactor note with one honest trigger: a second forwarded input
plane (e.g. sidebar visibility facts) beyond pipeline-forwarded activity. The
libgit2 swap is *not* a trigger — the `GitWorkingTreeStatusProvider` protocol
seam already isolates compute.

## Proof Gates

Workload gates (all three required; current gates only proved idle):

1. **Idle:** re-sample (1ms, 5s): main thread <10% busy; `repoAndWorktree`
   inclusive samples ≈0 vs 2255/3409 baseline; git **computations** quiescent
   ≤2/s (≈≤6 process spawns/s — units: 1 computation = 3 spawns).
2. **Busy-agent:** ≥5 disposable fixture worktrees with synthetic writers
   (never user/project repos); main-thread ≤30% over a 5s sample; per-change
   render <1 frame post-render-tasks; typing responsive (subjective + sample
   shows input path not queued).
3. **cmd+P:** keystroke filter rebuild ≤ ~8ms at 118/163 scale (os_signpost
   around `CommandBarSearch.filter` / unit-level timing with fixture data).

Signpost set (subsystem `com.agentstudio`, category `git-refresh`): tick size,
status compute duration + completions/s, posts/s + dedup-skips, coordinator
write duration + writes/s, `repoAndWorktree` calls/s + µs/call (the regression
metric), `TabBarAdapter.refresh` rebuilds/s.

Unit/integration: per the existing plan's red/green matrix, plus: budget
ceiling held under saturation; tier-priority admission order; activity-before-
registration honored; suppressed-only changeset triggers no compute;
`.gitWorkingDirectory` envelope through `handleFilesystemEnvelopeIfNeeded`
performs zero topology path reads; SurfaceManager unchanged-health tick fires
no invalidation. All clock-injected; no wall-clock test sleeps.

## Relationship to Existing Artifacts

- `docs/plans/2026-06-11-agent-studio-idle-git-render-performance.md` —
  **executes Phase 1 core**; this spec adds the amendment list above. The
  plan's `hasSameCacheContent` approach supersedes this spec's earlier
  "change `==`" direction. Plan owner should fold amendments in before
  execution (its Split/Replan triggers already anticipate the memoization
  split).
- `docs/plans/2026-06-10-terminal-restore-and-startup-performance.md`
  (`proposed`, unexecuted) — task 4 (health-timer gating) overlaps the
  SurfaceManager row; task 5 (Derived memoization) is this spec's Phase 2
  item; task 1's instrumentation-first gate is adopted here as the signpost
  set. Restore-path tasks (2,3,6) remain that plan's own scope.
- `docs/plans/2026-06-10-filesystem-watch-swift62-hygiene.md` — owns the
  FSEvents flag handling/registration retry/`.gitignore` `@concurrent` load;
  invariant 9 fast-tracks only the pathFilter load fix.

## Security Context

Product behavior is not security-sensitive beyond existing posture: same
subprocess commands with strictly fewer spawns; `GIT_OPTIONAL_LOCKS=0` is a
constant env value through the existing executor env merge — no new parse
surface, no user repo-config mutation; no new untrusted inputs; no network
change. Proof tooling is separately security-reviewable: workload drivers and
scripts must use disposable fixture repos/worktrees, must not mutate user git
config, and must be reviewed before execution. Stale-context risk is a
correctness concern (UI must not label the wrong repo/worktree), which is why
normalized lookup stays topology-owned.

## Non-Goals

- No events-primary cutover; the sweep remains the source of truth.
- No scheduler-actor extraction absent its trigger.
- No durable-state caching of derived display data (no normalized-path fields
  on `Repo`/`Worktree`/pane metadata/SQLite).
- No FSEvents callback-level filtering (`.gitignore`/`.git/config` semantics
  are product-correctness-sensitive; owned by the fs-watch hygiene plan).
- No ForgeActor redesign in Phase 1.

## Open Questions (true tunables; none block planning)

1. Background cadence 240s is the default after idle proof showed the earlier
   2s active tick still produced a permanent ~7-9 git-status/s baseline with
   14 active panes, and the first 180s background pass left only marginal
   headroom against the <=2/s idle gate. Tune only with fresh idle/busy/cmd-P
   proof.
2. `core.untrackedCache`/fsmonitor experiment — note: `GIT_OPTIONAL_LOCKS=0`
   suppresses the opportunistic index writes that persist those caches, so
   app-spawned status may never warm them; the experiment must account for
   this or it reads as a false negative. Env/flag-only; never mutate user
   repo config.
3. Lossy `snapshotChanged` consumer audit (Phase 2 gate).
