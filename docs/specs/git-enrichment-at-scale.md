# Git Enrichment At Scale Spec (180-worktree responsiveness)

Status: design, ready for plan-review
Repo: agent-studio
Evidence base: `tmp/session-3-analysis.md` (160-min marked live session,
marker `debug-observability-oq4s-1783036332-23793`, 76,741 events).
Builds on: `docs/superpowers/specs/2026-06-11-git-enrichment-refresh-redesign.md`
(Phase 1 — tiered sweep, budget, dedup, striping, per-worktree backoff — LANDED)
and `docs/superpowers/specs/2026-06-11-atomlib-v2-state-primitives.md`
(primitives `AtomValue` / `AtomEntityMap` / `DerivedValue` built;
row-1/row-2 adoption UNIMPLEMENTED).

## 1. Goal

A workspace with ~150 repos / ~180 worktrees, all legitimately registered and
watched, must stay responsive: the worktree the user is looking at is fresh
within seconds, scrolling and clicking never jank from a background git storm,
boot makes the sidebar usable in seconds rather than after a 15.7s scan, and no
single slow git repo can freeze enrichment fleet-wide. The fix is algorithmic
and structural — visibility-tiered scheduling, off-main batching, and
decoupling contention from the failure breaker — not deletion of worktrees and
not workspace hygiene. Large watch-folder sets are a supported configuration.

The session-3 storm happens *despite* the Phase 1 redesign already being
landed. Phase 1's capacity arithmetic predicted ~1.0-1.6 status computes/s of
steady self-heal at 163 worktrees. Reality at 180 with an actively-committing
agent is a 3-11/s baseline, bursts to 60/s, and a 335/s boot storm. This spec
closes the gap Phase 1 explicitly flagged as "tune only with fresh proof at
scale" and fixes three coupling defects Phase 1 did not anticipate: the failure
breaker firing on contention, the capacity pool leaking under slow reads, and
the reservation slot protecting the wrong tier.

## 2. Non-goals

- No deletion, wiping, or auto-pruning of worktrees. Dead paths are quarantined
  (polling suspended), never removed. Workspace hygiene is not the solution.
- No events-primary cutover. The tiered sweep remains the source of truth; the
  Phase 1 rationale (linked-worktree attribution hole, four-layer event loss)
  stands. Staging changes *order and cadence*, not correctness.
- No new coordination plane. Facts stay on `PaneRuntimeEventBus`; the coordinator
  accumulates; atoms are mutated by their owners. This spec adds *batched
  delivery* and a *direct visibility hint* (the `setActivePaneWorktree`
  precedent), not a command bus or a read/write segregation.
- No generic reactive runtime, no macro, no dependency-graph scheduler. Derived
  memoization is the revision-keyed `DerivedValue` primitive that already exists.
- No git provider/library swap. The `GitWorkingTreeStatusProvider` protocol seam
  is the isolation boundary; changes stay behind it.
- No new `#if DEBUG` production test hooks; injected clocks and protocol seams
  only (repo rule).

## 3. Measured baseline (the before-column)

All numbers from `tmp/session-3-analysis.md`, whole-session unless noted.

| Signal | Measured | Meaning |
|---|---|---|
| registered worktrees / repos / panes | 180 / 150 / 36-37 | the real scale |
| dead paths in DB | 4 | registered + watched + polled, path absent |
| `topology.repo_and_worktree` lookups | 27,919 (70% at boot) | main-actor derived re-derivation |
| `git.admission`, slots saturated | 12,644; `running.count=4` in 8,827 (70%) | 4-slot cap pinned full |
| `git.status` computes | 6,217; **full=6,071 (97.7%)**, pathspec=146 | git-internal churn forces full scope |
| `git.status` compute cost | p50 134ms, p90 612ms, **p99 974ms, max 1,060ms** | full-scope tail sits AT the 1s hard timeout |
| `git.status_unavailable` | 8,130; **read_capacity_exceeded=5,319**, timeout=2,572, sdk_error=228 | rejections dominate |
| `git.backoff`, stuck at ceiling | `backoff_open=true` 7,891; **60,000ms=4,227** | breaker pinned at 60s, thrashing |
| pending peak | 127 | fleet-wide backlog behind 4 slots |
| boot source-sync | `filesystem_source_elapsed_ms=15,704`; `registered.count=180` | 15.7s serial register loop |
| boot topology storm | 335/s (19,572 lookups / 60s) | 180 eager registrations + status seeds |
| steady storm baseline / burst | 3-11/s / up to 60/s | contends with the main actor |
| `metadata_scheduler_queue_wait` | ~0.01ms idle → **35ms storm peak**, **1,820ms boot** | main-actor scheduling latency tracks storm |
| bridge demand executor health | `enqueue_rejected=0`, `failed=0`, settle 8-15ms in storm AND quiet | the bridge pipeline itself did not fail |

Root-cause chain (each link verified in code):

1. **Full-scope everywhere.** `has_git_internal_changes=true` forces
   `.full` scope (`GitWorkingDirectoryProjector+PathspecStatus.swift:70-86`);
   an actively-committing agent touches `.git` internals on every commit, and
   `.git`-internal changes are not pathspec-expressible, so the 128-path fold
   never engages (146/6,217 computes). Full-scope reads are slow (p99 974ms).
2. **Hard timeout ≈ read latency.** `defaultStatusReadTimeout=1s`
   (`AppPolicies.swift:39`) sits at the full-scope p99. A large fraction of
   full-scope reads hit the timeout.
3. **Timed-out reads leak their capacity slot.** `readWithHardTimeout`
   releases the Cap-B registry slot only from inside the detached read task's
   completion (`AgentStudioGitWorkingTreeStatusProvider.swift:88,128,132,135`).
   The timeout path (`:139-141`) resolves the caller with `.timeout` but does
   NOT release the slot; the orphaned libgit2 read holds it until it finishes
   on its own (cancellation "may be ignored", `:123`). Leaked slots →
   `read_capacity_exceeded` for other worktrees.
4. **Both reasons open the same 60s breaker.**
   `handleUnavailableStatusResult` opens the per-worktree exponential breaker on
   `.timeout` AND `.readCapacityExceeded`
   (`GitWorkingDirectoryProjector.swift:679-681`). A contention rejection —
   the fleet being busy, not this worktree failing — escalates to a 60s freeze
   for that worktree. Sustained churn keeps re-triggering, so the breaker pins
   at 60s (4,227 events).
5. **The reservation protects the wrong tier.** `admitPendingWorktrees`
   reserves `oldestStaleReservedSlots` (1) for the oldest-stale *background*
   worktree (`GitWorkingDirectoryProjector.swift:278-287`, `priorityKey==2`) —
   anti-starvation for the tail. There is no reservation *for the foreground*.
   The active-pane worktree competes with the storm for the remaining 3 slots.
6. **No visible tier.** `priorityKey` knows active-pane (0), open-anywhere (1),
   background (2) (`GitWorkingDirectoryProjector.swift:483-491`). The 150
   sidebar rows the user actually scrolls are all tier-2 background (240s
   stripe); no signal for "on-screen in the sidebar right now" exists
   (`SidebarCacheState.swift`, `WorkspaceSidebarState.swift` — expanded groups
   and focus only, no scroll/visible-rows state).
7. **Per-fact main-actor cascade.** Every enrichment fact is a synchronous
   `repoCache.set…` write on the main actor, one at a time
   (`WorkspaceCacheCoordinator.swift:316-400`; PR-count path scans
   O(worktrees-in-repo) per event, `:395-399`). Derived read models are
   fresh-struct-per-access with zero memoization
   (`AtomRegistry.swift:250-302`, `Derived.swift:9-11`); hot adapters fan out
   over the whole pane dict in one tracking closure (`TabBarAdapter.swift`),
   so one worktree's write triggers a full re-scan. This is the 27,919-lookup
   cascade and the 35ms main-actor queue-wait.

The jank the user feels is link 7 (main-actor contention during bursts); the
60s freezes are links 3-4; the "background storm starves my repo" is links 5-6.

## 4. System invariants (the contract)

I1 FOREGROUND FRESHNESS FLOOR. The active-pane worktree's status compute is
   never blocked behind the background herd. At least one concurrency slot is
   always reservable for the foreground/visible tiers, independent of how many
   background worktrees are pending. Rationale: the user's own repo must refresh
   while 179 others churn.

I2 CONTENTION IS NOT FAILURE. A capacity-contention rejection
   (`read_capacity_exceeded`) never opens the exponential per-worktree breaker.
   Only a genuine per-worktree git failure (an admitted compute that times out
   or SDK-errors) does. The breaker is per-worktree and is never correlated
   fleet-wide by contention. Rationale: link 3-4 above — contention-as-failure
   is what pins the breaker at 60s fleet-wide.

I3 CAPACITY REFLECTS THE CALLER. A read the caller has abandoned (hard timeout
   or cancellation) releases its capacity accounting within a bounded window;
   the same-root in-flight guard still prevents a duplicate concurrent read of
   that root. Rationale: an orphaned read must not indefinitely consume a slot
   the scheduler believes is free.

I4 BOUNDED MAIN-ACTOR WORK PER BURST. Between fact production and the
   accepted-state write, main-actor work is O(distinct worktrees changed in the
   flush window) — never O(facts) and never O(fleet). Derived reads used by
   bodies are O(1) amortized via revision memoization. (Extends the redesign
   spec's MainActor Discipline rule to the batched-delivery regime.)

I5 VISIBILITY DRIVES FRESHNESS. A worktree's freshness tier is a pure function
   of (is-active-pane, is-visible-in-sidebar, has-open-pane, path-exists). No
   worktree is polled more often than its visibility warrants; a worktree that
   is neither visible nor open is background; a worktree whose path is absent is
   quarantined.

I6 LOSSLESS QUARANTINE. A dead-path worktree remains registered and restorable;
   quarantine suspends its polling and its FSEvent watcher only, and reverses
   automatically when the path reappears. No worktree row is ever deleted by
   this system.

I7 SELF-HEAL PRESERVED. The tiered sweep remains the source of truth. Every
   registered, available worktree is eventually enriched regardless of dropped
   events. Staging and tiering change order and cadence, never eventual
   completeness.

## 5. Design contracts (fix set)

Fixes are grouped by the invariant they serve. Each cites the exact code it
changes.

### Layer A — visibility-tiered scheduling (serves I1, I5)

- **A1 Visible-worktree signal (new state).** Add a runtime-only atom
  `SidebarVisibleWorktreeAtom` (`Core/State/MainActor/Atoms/`, runtime lane —
  NOT persisted, per the atom-classification rule) holding
  `visibleWorktreeIds: Set<UUID>`. `RepoExplorerView` computes it from the
  backing `NSTableView` visible rows (`rows(in: visibleRect)`) and writes it on
  scroll/expand settle. This state does not exist today
  (`SidebarCacheState.swift`, `WorkspaceSidebarState.swift` carry expanded
  groups + focus only).

- **A2 Direct visibility forward (no new bus).** The coordinator's existing
  sync pass forwards the visible set to the projector by a direct
  `setSidebarVisibleWorktrees(_:)` actor method, exactly as
  `setActivePaneWorktree` is forwarded today
  (`WorkspaceSurfaceCoordinator+FilesystemSource.swift:376-379` →
  `FilesystemGitPipeline` → `GitWorkingDirectoryProjector.setActivePaneWorktree`,
  `:261-265`). Visibility is a priority *hint*, not lifecycle truth — the
  coordination table's "direct call for deterministic hints" row. No
  `PaneRuntimeEventBus` type, no `WorkspaceActionCommand`.

- **A3 Four-tier priority.** Extend `priorityKey`
  (`GitWorkingDirectoryProjector.swift:483-491`) to:
  `activePane=0`, `visibleInSidebar=1`, `openAnywhere=2`, `background=3`.
  Dead-path worktrees are excluded from admission entirely (Layer E).

- **A4 Foreground reservation (reverse the existing reservation's blind spot).**
  In `admitPendingWorktrees` (`:267-314`), reserve at least one slot for
  tiers 0-1 (active + visible) that the tier-2/3 herd cannot consume, in
  addition to keeping the existing oldest-stale tail reservation. With the cap
  raised (A5), allocation at N=180: `foregroundReserved≥1`,
  `tailReserved=1`, remainder filled by priority. The floor guarantees I1.

- **A5 Decouple and size the two caps.** The projector admission cap
  (`maxConcurrentStatusComputes`, Cap A) and the provider read-registry cap
  (`defaultDetachedStatusReadLimit`, Cap B) are independent knobs that both
  default to 4 today (`AppPolicies.swift:41,68`) and are wired separately
  (`AgentStudioGitWorkingTreeStatusProvider.swift:24,287-290` constructs its
  own registry). Thread one policy value through both so they cannot silently
  diverge, and re-derive the value against N=180 with the tier reservations.
  Sizing is a tunable proven by the harness, not a guess in this spec.

- **A6 Tier cadences.** `activePane`: event/focus-driven + short self-heal
  (existing focus boost). `visibleInSidebar`: tens of seconds. `openAnywhere`:
  existing `activeCadence` (15s). `background`: existing striped
  `backgroundCadence` (240s / 16 stripes). Reuse the existing periodic-tick +
  stripe machinery (`isBackgroundWorktreeDue`, `AppPolicies.swift:128-131`);
  add the visible tier as a middle cadence.

### Layer B — breaker / capacity decoupling (serves I2, I3)

- **B1 Contention re-queues, failure backs off.** In
  `handleUnavailableStatusResult` (`GitWorkingDirectoryProjector.swift:679-684`),
  route `.readCapacityExceeded` and `.readAlreadyInFlight` to a light re-queue
  (defer + admit on next slot free), NOT to `openOrAdvanceStatusBackoff`. Only
  `.timeout` and `.sdkError` (genuine per-worktree failure of an admitted
  compute) open the exponential breaker. This is the single highest-leverage
  change: it removes the fleet-wide 60s freeze.

- **B2 Release capacity on caller abandonment.** In `readWithHardTimeout`
  (`AgentStudioGitWorkingTreeStatusProvider.swift:109-147`), the timeout and
  cancellation paths must release the Cap-B registry slot when the caller gives
  up, while retaining a same-root guard so a fresh read of that root is still
  rejected as `.readAlreadyInFlight` (not started twice) until the orphaned read
  actually finishes. Mechanism: split "slot accounting" (released on caller
  abandonment) from "root in-flight marker" (cleared on true completion). This
  stops the pool eroding to zero under a run of slow full-scope reads.

- **B3 Tier-aware backoff ceiling.** A worktree in tier 0-1 (active/visible)
  that genuinely fails backs off to a lower ceiling than a background one — the
  user is looking at it, so retry sooner. Parameterize
  `statusFailureBackoffMaxDelay` (`AppPolicies.swift:75`) by tier. Bounded,
  still exponential, still per-worktree.

- **B4 (optional, measurement-gated) Summary-only refresh on git-internal-only
  changesets.** A commit with no working-tree file edits changes HEAD/index/refs
  (branch, ahead/behind, staged counts) but not the working-tree entry set. A
  read that skips the full working-tree walk when the changeset is
  git-internal-only would collapse the 97.7% full-scope cost. This is a deeper
  provider change behind the `GitWorkingTreeStatusProvider` seam; specced as a
  gated slice, entered only if B1-B3 + Layer A leave the full-scope tail as the
  proven bottleneck.

### Layer C — main-actor decongestion (serves I4)

- **C1 Off-main enrichment batching (new).** Insert a coalescing stage between
  the bus and the atom writes. The coordinator drains the `PaneRuntimeEventBus`
  stream into a pending-by-worktree accumulator (last-writer-wins per worktree,
  since dedup already ran in the projector) and flushes to the atoms on a
  coalesced cadence, applying one transaction per flush. A burst of N facts
  across M distinct worktrees becomes M entity writes in one pass, not N
  synchronous writes. Cadence: burst-adaptive — flush on the next main-actor
  turn when idle (low latency), coalesce to a fixed tick (≈16-100ms, tunable)
  under sustained burst. This preserves the bus contract (facts on the bus,
  coordinator accumulates, atoms mutated by owners); it adds batched delivery.
  Today: `WorkspaceCacheCoordinator.handleEnrichment` writes synchronously
  per-fact (`:316-400`).

- **C2 Revision-memoized derived layer.** Adopt `DerivedValue`
  (`Infrastructure/AtomLib/DerivedValue.swift` — built, revision-keyed, unused)
  for `WorkspacePaneDerived` and `PaneDisplayDerived`, and expose them as
  stored `lazy var` on the registry instead of fresh-struct-per-access computed
  vars (`AtomRegistry.swift:250-302`). With input revisions unmoved,
  `repoAndWorktree(containing:)` fallbacks and rich-pane rebuilds serve the
  cache. This is atomlib-v2 inventory row 2, pulled forward.

- **C3 Per-entity observation on hot surfaces.** `RepoEnrichmentCacheAtom`
  already stores enrichment in `AtomEntityMap` with per-domain revisions
  (`RepoCacheAtom.swift:15-52`) — the storage is granular. The consumption is
  not: `TabBarAdapter` reads the whole pane dict and loops all panes' enrichment
  in one `withObservationTracking` closure, so one worktree's write invalidates
  the whole adapter. Push reads down to per-entity `entity(for:)` +
  `membershipRevision` on the tab bar, sidebar rows, and cmd+P rows (the view
  restructuring atomlib-v2 mandates as one unit with the primitive). This is
  atomlib-v2 inventory row 1's remaining half.

- **C4 Remove residual per-render lookup multiplicity.**
  `PaneLeafContainer.body` invokes `PaneManagementContext.project` twice
  unconditionally (`PaneLeafContainer.swift:241-251`), even when
  `locationTargetPaneId == paneHost.id`; each `project` can drive up to two
  `repoAndWorktree` fallbacks for panes lacking cached ids. Collapse to one when
  the target equals the pane. (Redesign-spec discipline-table row, still open.)

### Layer D — staged boot (serves I5, I7)

- **D1 Priority-ordered registration.** The boot register loop walks
  `store.repositoryTopologyAtom.repos` in plain atom-array order
  (`WorkspaceSurfaceCoordinator+FilesystemSource.swift:381-396`). Reorder it by
  the already-computed `activePaneRepoIds` (last-active tab's repos, computed in
  `AppDelegate+WorkspaceBoot.replayBootTopology:477-487`) so the active-tab
  worktrees register first, then visible, then the rest. The signal is already
  restored before topology sync runs; no new persistence.

- **D2 Two-phase enrichment.** Eagerly status-compute only active/visible
  worktrees at boot; background worktrees' first status is trickled via the
  background stripe rather than seeded eagerly at registration. Registration
  currently seeds a synthetic full-status compute per worktree
  (`GitWorkingDirectoryProjector.swift:386-395`) — 180 eager computes is the
  335/s boot storm. Suppress the eager seed for tier-3 worktrees; the stripe
  reaches them within `backgroundCadence`.

- **D3 Cheaper, deduped, non-blocking registration.** Move
  `FilesystemPathFilter.load` (synchronous `.gitignore` read + regex compile,
  run per `register()` on the FilesystemActor executor,
  `FilesystemActor.swift:138`) to `@concurrent` (redesign-spec invariant 9,
  still open). Dedupe register-by-rootPath the way `assertTopology` already does
  (`FilesystemActor.swift:187-192`) so coalesced/superseded sync passes don't
  redo the `.gitignore` read for already-registered worktrees. Optionally bound
  parallelism on the register loop (today strictly serial with `await` per
  worktree). Target: sidebar usable in single-digit seconds, not 15.7s.

### Layer E — dead-path quarantine (serves I6)

- **E1 Worktree-level availability (new state).** No worktree-level dead-path
  flag exists — only repo-level `unavailableRepoIds`
  (`WorkspaceRepositoryTopologyAtom.swift:9`), and the `Worktree` model +
  SQLite `worktree` table are structure-only (`Worktree.swift:5-38`,
  `WorkspaceCoreMigrations.swift:166-179`). Add `unavailableWorktreeIds:
  Set<UUID>` to `WorkspaceRepositoryTopologyAtom`, mirroring the repo pattern
  (`markWorktreeUnavailable` / `markWorktreeAvailable` / `isWorktreeUnavailable`).
  Runtime-derived; persistence optional (a boot re-probe re-derives it).

- **E2 Probe on register, quarantine on absence.** Before registering a
  worktree, an off-main `FileManager.fileExists` probe; a non-existent path →
  mark unavailable, skip the FSEvent watcher and the status seed entirely. The
  4 dead paths pay zero watch/poll cost. The projector excludes quarantined
  worktrees from `admitPendingWorktrees` and the periodic tick.

- **E3 Re-arm on reappearance.** The existing 300s fallback rescan
  (`FilesystemActor.startFallbackRescan:868-883`) and watched-folder reconcile
  clear the quarantine when the path reappears; for individually-added repos
  (not under a watched folder — the self-heal gap agent-mapped in
  `WorktreeReconciler` flow), a low-frequency existence re-probe re-arms.
  Quarantine is fully reversible (I6).

### Layer F — bridge insulation (serves I4, residual after C)

- **F1 Off-main intake-frame encoding.** The bridge push-plan cold path already
  encodes JSON `@concurrent` off-main (`State/Push/Slice.swift:54`,
  `EntitySlice.swift:129`). The review-protocol and worktree-file *intake-frame*
  path does not: JSON encoding runs synchronously on MainActor
  (`BridgePaneController+ReviewProtocolResources.swift:99`,
  `WorktreeFileSurface/…+WorktreeFileIntakeFrames.swift:171-191`). Move it
  `@concurrent`, copying the cold-path pattern. This is the one bridge hot-path
  stage still contending with the storm on the main actor.

- **F2 Off-main residual syscalls.** `resolvingSymlinksInPath()`
  (`BridgeWorktreeFileSourceProvider.swift:132-137`, called on MainActor per
  descriptor request) and `exactTreeRowCount` (in-memory BFS over the file set,
  called synchronously from a MainActor method,
  `BridgeWorktreeFileMaterializer.swift:408-431`) move into the existing
  `Task.detached` materializer pattern. Small, done for consistency.

Note: the scheme handler that serves file bytes to the WebView is already fully
off-main (`BridgeSchemeHandler` nonisolated struct + actor-backed stores), and
the demand executor itself was healthy throughout the session (0 rejects,
<15ms settles). The bridge insulation win is C1 (removing the main-actor
contention that raised scheduler queue-wait to 35ms) plus F1; no demand-lane
scroll change is warranted by this evidence.

## 6. Requirements (testable)

Before-column is the measured session-3 value.

R1 FOREGROUND NON-STARVATION. With 180 worktrees all pending (tier-3 herd) and
   the active-pane worktree enqueued, the active-pane compute is admitted within
   ≤1 slot turnaround and never waits behind a tier-3 admit. *Before:* the only
   reservation is for the oldest-stale tier-2 worktree; foreground competes for
   3 shared slots (70% saturated).

R2 BREAKER CONTENTION-IMMUNITY. Injecting `read_capacity_exceeded` for a
   worktree does NOT enter it into exponential backoff (it re-queues); injecting
   a genuine `timeout` of an admitted compute DOES. *Before:* both open the
   breaker (`:679-681`); 4,227 events pinned at the 60s ceiling.

R3 CAPACITY NO-LEAK. N sequential reads that each hit the hard timeout leave the
   capacity pool with N_max−(in-true-flight) free slots — a timed-out read frees
   its slot within a bounded window; a same-root retry is still rejected as
   `read_already_in_flight`. *Before:* orphaned reads hold slots until libgit2
   returns; `read_capacity_exceeded=5,319`.

R4 BATCHED DELIVERY. A burst of N enrichment facts across M distinct worktrees
   within one flush window produces exactly M entity mutations (one transaction)
   and ≤1 SwiftUI invalidation pass per affected row. *Before:* N synchronous
   per-fact main-actor writes (`:316-400`).

R5 DERIVED MEMOIZATION. With input revisions unmoved across repeated body
   evaluations, `repoAndWorktree`/derived recompute count is 0. *Before:*
   fresh-struct-per-access; 27,919 topology lookups.

R6 PER-ENTITY ISOLATION. Writing worktree A's enrichment invalidates only A's
   tab/sidebar/cmd+P row, with a positive control proving A's row DOES update.
   *Before:* `TabBarAdapter` full refresh on any enrichment write.

R7 BOOT STAGING. At N=180, last-active-tab worktrees are enriched within
   ≤T_active seconds and the sidebar is interactive; background worktrees
   produce no boot status storm (peak background admissions/s below a set
   threshold) and complete within the striped budget. *Before:* 15.7s
   source-sync, 335/s boot storm.

R8 DEAD-PATH QUARANTINE. A worktree whose path is absent is registered but
   quarantined: zero status computes, zero FSEvent watcher, and it re-arms
   (resumes polling) when the path reappears. *Before:* 4 dead paths registered
   + watched + polled every boot.

R9 BRIDGE INSULATION UNDER STORM. During a synthetic 180-worktree storm,
   intake-frame encoding runs off-main and the metadata scheduler queue-wait
   stays below a set bound; demand-executor settle latency is unchanged from
   quiet. *Before:* intake-frame encode on MainActor; queue-wait rose to 35ms
   (1,820ms at boot).

R10 STORM REDUCTION (felt result). A marked live session at 180 worktrees with a
   synthetic committer shows the steady storm baseline and burst peak reduced
   against session-3, main-actor scheduling latency staying low through bursts,
   and no 60s breaker plateau. *Before:* 3-11/s baseline, 60/s bursts, 35ms
   queue-wait, breaker pinned at 60s.

## 7. Proof gates

Per repo rules, climb the pyramid; report each layer with evidence, name any
blocked layer.

Unit (clock-injected, no wall-clock sleeps; Swift Testing):
- Scheduler admission order and the foreground reservation floor under a
  saturated pending set (R1); tier assignment from the four inputs (I5).
- Breaker reason-gating: capacity re-queues, timeout backs off (R2); tier-aware
  ceiling (B3).
- Capacity accounting: timeout releases the slot, same-root guard holds (R3) —
  against a fake timeout scheduler and a fake reader.
- Batching coalescence: N facts → M transactions, last-writer-wins per worktree
  (R4) — against an injected flush clock.
- `DerivedValue` recompute cutoff on unmoved revisions (R5); per-entity
  invalidation isolation with positive control (R6). These carry over the
  atomlib-v2 D1-D4 / E1-E7 matrix.
- Quarantine set transitions and admission exclusion (R8).

Integration (real projector + `PaneRuntimeEventBus` + coordinator + atoms, fixture
scale, `TestPushClock`):
- Full fact→batch→atom→derived path: a burst produces one flush and the derived
  read reflects the final state (R4 + R5 end-to-end).
- Boot staging order with a fixture topology: active-tab repos register and
  enrich first (R7).
- Dead-path probe → quarantine → reappearance → re-arm (R8).

Harness scenario at N=180 (the scale gate):
- Disposable fixture: ~150 fixture repos / ~180 worktrees (NEVER user/project
  repos), a subset with synthetic committers driving git-internal churn, ≥4
  fixture worktrees with deleted paths. Driven through
  `scripts/run-debug-observability.sh --detach` and verified via VictoriaMetrics
  (standard perf proof path, `mise run verify-git-refresh-performance-workload`
  shape). Marker-scoped, before/after the session-3 baseline.
- **Instrumentation prerequisite:** add a `dev.worktree.hash` label (OTLP
  source-scrubbing compliant — deterministic hash, no raw path/UUID) to
  `git.*` events so scope/rejection/backoff attribute per worktree. Session-3
  named this the top instrumentation gap; the harness cannot prove tier behavior
  per worktree without it.
- Gates: R1 (foreground admitted through the storm), R2/R3 (no 60s breaker
  plateau, capacity pool non-eroding), R7 (no boot storm), R9 (queue-wait
  bound), R10 (baseline/burst reduction). Report VM `_max` honestly as peak.

Felt result (R10): instrumented interactive session, marker-scoped Victoria
analysis, fresh build required, compared to session-3
(`debug-observability-oq4s-1783036332-23793`).

Blocked-layer honesty: if the N=180 harness cannot be stood up in a slice, that
slice reports its unit+integration proof and names the harness as the
outstanding scale gate — it does not claim the scale requirement met.

## 8. Plan (ordered slices, each red-first)

Ordering is by leverage-per-risk and dependency. One commit per slice, red test
committed with its green.

S1 Breaker/capacity decoupling (B1, B2, B3). *Proof:* R2 + R3 unit tests red on
   HEAD (both reasons open breaker; timeout leaks slot) → green. Smallest,
   highest-leverage — removes the 60s fleet freeze. No dependency.

S2 Visibility tier + foreground reservation (A1-A6). *Proof:* R1 admission-order
   test red on HEAD (no foreground reservation) → green; visible signal
   integration test. Depends on the new visible atom + coordinator forward.

S3 Off-main batching (C1). *Proof:* R4 coalescence test red on HEAD (per-fact
   writes) → green; integration burst→one-flush. Independent of the scheduler.

S4 Derived memoization + per-entity view restructuring (C2, C3, C4). *Proof:*
   R5 recompute-cutoff and R6 per-entity-isolation red → green; carries the
   atomlib-v2 row-1/row-2 matrix. Largest slice; the interim `hasSameCacheContent`
   gate is deleted-and-absorbed by the primitive (hard cutover). Depends on S3
   for the burst regime it optimizes.

S5 Staged boot (D1, D2, D3). *Proof:* R7 boot-staging integration test red on
   HEAD (atom-array order, eager seed all 180) → green. Depends on S2 (tier
   ordering) and S3 (background trickle regime).

S6 Dead-path quarantine (E1, E2, E3). *Proof:* R8 quarantine lifecycle test red
   on HEAD (no worktree-level availability) → green. Mostly independent; slots
   under S2's admission changes.

S7 Bridge insulation (F1, F2). *Proof:* R9 off-main-encode assertion (isolation
   test) + harness queue-wait bound. Residual after S3; smallest bridge change.

Scale validation (R10) runs after S1-S5 land as the felt-result gate; S6/S7 are
proven in the same harness pass.

## 9. Requirements / proof matrix

| Req | Proof | Layer | Freshness guard |
|-----|-------|-------|-----------------|
| R1 foreground non-starvation | admission-order unit + N=180 harness | S2 | red-first on HEAD |
| R2 breaker contention-immunity | reason-gating unit | S1 | red-first on HEAD |
| R3 capacity no-leak | timeout-release unit (fake scheduler) | S1 | red-first on HEAD |
| R4 batched delivery | coalescence unit + burst integration | S3 | red-first on HEAD |
| R5 derived memoization | `DerivedValue` cutoff unit | S4 | red-first (fails on `Derived`) |
| R6 per-entity isolation | isolation unit w/ positive control | S4 | red-first on single-dict consumption |
| R7 boot staging | staging integration + harness boot window | S5 | red-first on HEAD |
| R8 dead-path quarantine | lifecycle unit + probe integration | S6 | red-first on HEAD |
| R9 bridge insulation | off-main isolation unit + harness queue-wait | S7 | red-first on HEAD |
| R10 storm reduction (felt) | marked live session vs session-3 marker | S1-S5 | fresh build required |

## 10. Interactions to respect

- **Phase 1 machinery is reused, not replaced.** The periodic tick, stripe,
  dedup, content-gate, and per-worktree backoff stay; this spec adds a tier,
  a reservation, a reason-gate, and a batch stage. `AppPolicies.GitRefresh` is
  the single policy home — new cadences/reservations/caps land there with
  explicit test fixtures (no `.zero`-default divergence).
- **atomlib-v2 is consumed, not re-specced.** C2/C3 are inventory rows 1-2 of
  `2026-06-11-atomlib-v2-state-primitives.md`, pulled forward and scoped to the
  hot surfaces this spec proves. That spec's transaction-token, equality-comparator,
  and view-restructuring contracts govern the adoption; its stale plan
  checkboxes should be reconciled against the built primitives before S4.
- **Batching must not defeat the redesign-spec dedup.** The projector already
  dedups equal snapshots before posting; C1's accumulator is last-writer-wins
  per worktree, so batching only coalesces distinct facts and never resurrects
  a deduped one.
- **The lossy-`snapshotChanged` reclassification remains gated.** C1 achieves
  the coalescing benefit without changing envelope criticality; the inbox/terminal
  consumer audit the redesign spec flagged is not a prerequisite here.
- **GIT_OPTIONAL_LOCKS=0 stays.** B4's summary-only path, if entered, must keep
  the constant-env posture (no user repo-config mutation).

## 11. Security context

Not security-sensitive beyond existing posture: same subprocess commands with
strictly fewer and better-scheduled spawns; no new untrusted inputs, no network
change, in-memory state plumbing plus one runtime-only visibility atom and one
runtime-derived quarantine set. The N=180 harness must use disposable fixture
repos/worktrees, must not mutate user git config, and is separately
security-reviewable before execution. The added `dev.worktree.hash` OTLP label
is a deterministic hash under the existing source-scrubbing rules — no raw
paths, UUIDs, or payload text exported.

## 12. Open questions (tunables; none block planning)

1. Concurrency cap value at N=180 after A4-A5 (foreground-reserved + tail-reserved
   + remainder). Prove with the harness; do not raise Cap B without the B2 leak
   fix or `read_capacity_exceeded` returns.
2. Batch flush cadence (C1): frame-aligned next-turn-when-idle vs fixed 16-100ms
   tick under burst. Prove against R4 latency and R10 felt-result.
3. Visible-tier cadence (A6): tens-of-seconds exact value; tune with R7/R10.
4. Whether B4 (summary-only on git-internal-only changesets) is needed, or
   whether Layer A + S1 leave full-scope cost acceptable. Gated on the post-S5
   re-profile.
5. Quarantine persistence (E1): runtime re-probe each boot vs persist
   `unavailableWorktreeIds`. Re-probe is simpler and self-correcting; persist
   only if boot probe cost at N=180 proves material.
