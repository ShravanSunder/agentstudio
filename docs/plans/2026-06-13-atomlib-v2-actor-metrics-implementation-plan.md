# AtomLib V2 Actor + Metrics Implementation Plan

Date: 2026-06-13
Repo: agent-studio.performance-issues
Branch at creation: spec-a-actor-metrics-design-2026-06-13
Status: reviewed, accepted fixes applied, not executed

## Goal

Implement the refreshed AtomLib v2 state primitives and the first production
adoption row in a way that makes the app measurably faster under the standard
repo/worktree workload, while preserving Agent Studio's actor boundaries:

- canonical UI-observed state stays in `@MainActor` atoms;
- fleet-scale rebuildable work stays in actors or measured follow-up lanes;
- deterministic tests prove primitive semantics;
- VictoriaMetrics proves real workload behavior.

## Sources Read

- `docs/superpowers/specs/2026-06-13-atomlib-v2-actor-metrics-refresh.md`
- `tmp/spec-workflows/2026-06-13-agent-studio-spec-a-actor-metrics-design-review/spec-a-actor-metrics-design-review.md` (585 lines)
- `docs/superpowers/specs/2026-06-11-atomlib-v2-state-primitives.md` (572 lines)
- `docs/plans/2026-06-11-atomlib-v2-state-primitives-implementation-plan.md` (381 lines)
- current `AtomLib`, repo cache, tab bar, sidebar, command bar, repo-cache
  store, diagnostic, script, and test surfaces

## Non-Goals

- Do not move canonical atoms off `MainActor`.
- Do not solve sidebar resize, pane split resize, or Ghostty geometry sync in
  this plan.
- Do not rewrite git/filesystem scheduling.
- Do not create a parallel debug launcher or bespoke observability stack.
- Do not use JSONL as automatic performance proof fallback.

## Required File Ownership

| Concern | Owner path |
| --- | --- |
| Generic AtomLib primitives | `Sources/AgentStudio/Infrastructure/AtomLib/` |
| AtomLib tests | `Tests/AgentStudioTests/Infrastructure/AtomLib/` |
| Compile-negative fixtures | `Tests/AgentStudioTests/Fixtures/AtomLibCompileFailures/` |
| Script/lint proof | `scripts/`, `.mise.toml`, `Tests/AgentStudioTests/Scripts/` |
| Repo cache state owner | `Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift` |
| Repo cache persistence bridge | `Sources/AgentStudio/Core/State/MainActor/Persistence/RepoCacheStore.swift` |
| Sidebar hot readers | `Sources/AgentStudio/Features/RepoExplorer/` |
| Command bar hot readers | `Sources/AgentStudio/Features/CommandBar/` |
| Tab bar adapter | `Sources/AgentStudio/App/Panes/TabBar/` |
| Pane/tab/display derived readers | `Sources/AgentStudio/Core/State/MainActor/Atoms/` |
| Metrics projection/tests | `Sources/AgentStudio/Infrastructure/Diagnostics/`, `Tests/AgentStudioTests/Infrastructure/Diagnostics/` |
| Workload proof | existing `scripts/verify-git-refresh-performance-workload.sh` and `.mise.toml` task wiring |

No new generic state-runtime package. No product atoms under
`Infrastructure/AtomLib`.

## Requirements / Proof Matrix

| Requirement | Task | Proof gate | Layer | Red/green |
| --- | --- | --- | --- | --- |
| Primitive writes fire only on accepted content changes | T1/T2 | `AtomValueObservationTests` | unit | yes |
| Domain/cache payloads cannot silently use wrong equality | T1/T2/T3 | compile-negative fixtures + comparator tests | unit/tooling | yes |
| Per-key entity reads wake only for the touched key | T1/T2 | `AtomEntityMapObservationTests` | unit | yes |
| Missing-key nil read wakes on later insert | T1/T2 | `AtomEntityMapObservationTests` | unit | yes |
| Membership changes are separate from value changes | T1/T2 | membership/value observation tests | unit | yes |
| Aggregate revision bumps once per semantic mutation | T1/T2 | transaction/revision tests | unit | yes |
| Multi-source row facts do not expose partial tuples | T4/T5 | repo worktree facts reader test | integration | yes |
| Derived cache hits avoid recompute | T1/T2 | `DerivedValueMemoizationTests` | unit | yes |
| Derived compute cannot access undeclared global/task-local atom state | T3 | lint + compile-negative fixtures | tooling | yes |
| Repo cache no longer requires whole-dict hot reads | T4/T5/T6 | named hot-reader denylist script/test | tooling/integration | yes |
| `RepoCacheStore` observes aggregate/snapshot state, not whole dicts | T5 | `RepoCacheStoreTests` | integration | yes |
| Sidebar rows use per-worktree/repo facts | T6 | RepoExplorer tests + denylist | integration/tooling | yes |
| Command bar repo/worktree rows avoid whole-dict repo cache reads | T6 | CommandBar tests + denylist | integration/tooling | yes |
| Tab bar refresh avoids whole-dict repo cache observation | T6 | TabBar adapter test + denylist | integration/tooling | yes |
| Workload proof uses VictoriaMetrics and standard debug runner | T0a/T0b/T7/T9 | workload script tests + live workload | smoke/e2e | yes |
| JSONL is not automatic perf proof fallback | T7/T9 | script tests | tooling | yes |
| Baseline is captured only after proof tooling can emit comparable fields | T0a/T0b | script tests + baseline artifact | tooling/smoke | yes |
| Branch freshness is proven against `origin/main` | T0b | fetch + divergence artifact | tooling | yes |
| 2x target is explicit and machine-checked | T0a/T0b/T9 | before/after metrics verdict | smoke/e2e | yes |
| Command-bar improvement claim uses real interaction proof | T0a/T0c/T9 | Peekaboo/PID-targeted command-bar scenario | smoke/e2e | yes |
| Existing performance surfaces do not regress | T0b/T0c/T9 | VictoriaMetrics before/after report | smoke/e2e | yes |
| New AtomLib metrics cannot create dynamic/high-cardinality series | T0a/T7 | diagnostics allowlist/denylist tests | unit/tooling | yes |
| Runtime proof cannot touch production app or pass stale markers | T0a/T7/T9 | debug launcher/workload behavior tests | tooling/smoke | yes |
| Row 2 adoption is stopped at a decision artifact unless a follow-up plan is reviewed | T8 | reprofile report + follow-up plan gate | planning/proof | no code red if no-go |
| Lint/test gates pass repo-wide | T10 | `mise run lint`, `mise run test` | full validation | yes |

If any row cannot produce its proof inside the planned scope, split or replan
before implementation continues.

## Task Sequence

### T0a. Proof Harness Prep Before Baseline

Purpose:

- make the metrics proof capable of producing the exact fields used for both
  baseline and after snapshots before any production AtomLib/repo-cache code
  changes;
- keep the standard debug observability runner and VictoriaMetrics proof path;
- prove the harness cannot fall back to JSONL or stale/unsafe process state.

Write surfaces:

- `scripts/verify-git-refresh-performance-workload.sh`
- `Tests/AgentStudioTests/Scripts/GitRefreshPerformanceWorkloadScriptTests.swift`
- `Tests/AgentStudioTests/Scripts/ObservabilityDebugLaunchScriptsTests.swift` if
  workload or launcher-adjacent behavior changes
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioTraceConfigurationTests.swift`
  and `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjectionTests.swift`
  if diagnostics, OTLP projection, or workload-script environment flow changes
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetricsTests.swift`
  if row-1 bounded metrics are added

Implementation requirements:

- factor or otherwise expose a tested VictoriaMetrics summary path that emits
  one machine-comparable metrics file for every proof run;
- set and document a repo-local proof root:
  `AGENTSTUDIO_PERF_PROOF_ROOT="$PWD/tmp/performance-proofs/<run-name>"`;
- emit counts and p95/max-or-supported-elapsed summaries for:
  - `performance.commandbar.items`
  - `performance.commandbar.filter`
  - `performance.tabbar.refresh`
  - `performance.sidebar.projection`
  - `performance.sidebar.row_index`
  - `performance.topology.repo_and_worktree`
  - `performance.coordinator.write`
- if p95 is not supported by the exported metric shape, emit a tested
  `p95_unavailable` field and use event/fanout count plus max elapsed for the
  2x decision;
- preserve `--preflight-idle`, unique trace marker, live-process verifier,
  cleanup limited to recorded PIDs, and no `pkill`/by-name process targeting;
- preserve loopback-only OTLP endpoint behavior and reject non-loopback collector
  URLs when launcher/proof plumbing is touched;
- keep JSONL as explicit opt-in only; JSONL must never satisfy the standard proof
  path.

2x target contract:

- command-bar class: `performance.commandbar.items` count or p95 elapsed improves
  by at least 50 percent in the command-bar interaction scenario;
- at least one repo-cache fanout class also improves by at least 50 percent:
  `performance.tabbar.refresh`, `performance.sidebar.projection`,
  `performance.sidebar.row_index`, or `performance.topology.repo_and_worktree`;
- no targeted surface may regress by more than 10 percent unless execution stops
  for review/replan.

Proof:

- script/diagnostic tests fail if a required field is omitted or malformed;
- script/diagnostic tests fail if JSONL auto-pass, non-loopback collector,
  by-name cleanup, stale marker, or missing live-process verification is
  reintroduced;
- one dry-run or documented no-app test proves the summary file shape before
  production code changes.

### T0b. Baseline And Branch Preflight

Purpose:

- capture the current row-1 workload baseline before code changes;
- confirm the branch still matches `origin/main` and the standard debug runner is
  the only launch path.

Read/check:

- `AGENTS.md` Local Observability section
- `.mise.toml`
- `scripts/run-debug-observability.sh`
- `scripts/verify-git-refresh-performance-workload.sh`
- `Tests/AgentStudioTests/Scripts/GitRefreshPerformanceWorkloadScriptTests.swift`

Actions:

- record `git status --short --branch`;
- run `git fetch origin main`;
- record a zero-divergence assertion against `origin/main`, for example:
  `git rev-list --left-right --count HEAD...origin/main` must be `0 0` before
  implementation proceeds;
- run `mise run observability:up`;
- run the finalized T0a workload proof once with
  `AGENTSTUDIO_PERF_PROOF_ROOT="$PWD/tmp/performance-proofs/<timestamp>-atomlib-v2-baseline"`;
- capture the finalized metrics summary file and trace/debug state file.

Proof:

- baseline artifact exists in `tmp/`;
- no JSONL fallback was used unless explicitly requested;
- standard debug runner state file identifies the launched debug app;
- branch divergence output is included in the baseline artifact.

### T0c. Command-Bar Interaction Baseline

Purpose:

- capture a real Cmd+P / `#` interaction baseline instead of relying on startup
  smoke.

Actions:

- reuse the debug app launched by the standard debug observability runner or
  launch one through that runner;
- target the debug app by PID from the state file, never by app name;
- use Peekaboo automation when stable, or a user-driven scripted checklist when
  automation is blocked, to open the command bar, enter `#`, type a repo filter,
  clear, and repeat enough times to produce measurable
  `performance.commandbar.items` and `performance.commandbar.filter` samples;
- store the command-bar interaction metrics beside the baseline workload proof.

Proof:

- interaction artifact includes PID, trace marker, command sequence, and
  VictoriaMetrics query outputs;
- if user-driven fallback is used, artifact says so and includes the exact
  transcript/checklist timing window.

### T1. Write Red Tests For AtomLib Primitives

Write surfaces:

- `Tests/AgentStudioTests/Infrastructure/AtomLib/AtomValueObservationTests.swift`
- `Tests/AgentStudioTests/Infrastructure/AtomLib/AtomEntityMapObservationTests.swift`
- `Tests/AgentStudioTests/Infrastructure/AtomLib/AtomRevisionTransactionTests.swift`
- `Tests/AgentStudioTests/Infrastructure/AtomLib/DerivedValueMemoizationTests.swift`
- `Tests/AgentStudioTests/Helpers/ObservationTestSupport.swift` if a shared
  synchronous helper is needed

Test cases:

- equal scalar write does not invalidate;
- changed scalar write invalidates once;
- domain payload requires explicit comparator;
- content-equivalent domain write skips;
- content-different domain write fires;
- missing-key read subscribes and wakes on insert;
- key A write does not wake key B reader;
- membership reader wakes only on add/remove;
- aggregate revision bumps once per mutation context;
- multi-write semantic mutation does not bump aggregate repeatedly;
- derived cache hit does not recompute;
- derived equal-output recompute does not bump own revision;
- chained derived reads input value before revision comparison.

Proof:

- focused tests fail for missing primitives/behavior before T2.

### T2. Implement AtomLib Primitives

Write surfaces:

- `Sources/AgentStudio/Infrastructure/AtomLib/AtomValue.swift`
- `Sources/AgentStudio/Infrastructure/AtomLib/AtomEntityMap.swift`
- `Sources/AgentStudio/Infrastructure/AtomLib/AtomRevision.swift`
- `Sources/AgentStudio/Infrastructure/AtomLib/AtomMutationContext.swift`
- `Sources/AgentStudio/Infrastructure/AtomLib/DerivedValue.swift`
- existing `Derived.swift` / `DerivedSelector.swift` only where compatibility or
  migration requires it

Implementation requirements:

- keep primitives `@MainActor` for this slice;
- keep canonical writes owner-mediated;
- no public setter on entity maps;
- no ungated always-fire variant;
- explicit comparator for domain/cache payloads;
- small allowlist convenience only for trivial scalar payloads;
- registry-owned derived storage, not global/static caches.

Proof:

- T1 tests pass.

### T3a. Add Early Enforcement Ratchets

Write surfaces:

- `scripts/check-atomlib-boundaries.sh`
- `.mise.toml`
- `Tests/AgentStudioTests/Scripts/AtomLibBoundaryScriptTests.swift`
- `Tests/AgentStudioTests/Fixtures/AtomLibCompileFailures/`

Rules to enforce:

- no `AtomScope`, `atom(`, or task-local registry access from `DerivedValue`
  compute fixtures;
- no known helper wrapper that hides undeclared atom/global input access in
  migrated derived compute; this is a named-wrapper denylist plus negative
  fixtures, not a claim that arbitrary helper indirection is solved by magic;
- no `WorktreeEnrichment` raw equality as repo-cache comparator;
- add the repo-cache dictionary-read inventory/allowlist check in report-only or
  shrinking-allowlist mode so it can pass before T6 migration;
- scripts run under repo-local lint and are covered by Swift Testing script
  tests.

Proof:

- compile-negative fixtures fail before allowed corrections and pass as negative
  assertions after script/test harness lands;
- `mise run lint` runs the early boundary checks without failing on current
  pre-migration repo-cache readers.

### T3b. Prepare Repo-Cache Production Read Inventory

Purpose:

- prevent row 1 from finishing while the old public dictionary API remains in
  unclassified production use.

Write surfaces:

- `scripts/check-atomlib-boundaries.sh`
- `Tests/AgentStudioTests/Scripts/AtomLibBoundaryScriptTests.swift`
- optional generated/readable allowlist fixture under `Tests/AgentStudioTests/Fixtures/AtomLibBoundary/`

Inventory seed from current repo evidence:

- `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift`
- `Sources/AgentStudio/App/Coordination/WorkspaceCacheCoordinator.swift`
- `Sources/AgentStudio/App/Panes/GitHubWebviewLaunchResolver.swift`
- `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift`
- `Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneDisplayDerived.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/TabDisplayDerived.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/RepoCacheStore.swift`
- `Sources/AgentStudio/Core/Views/Panes/PaneManagementContext.swift`
- `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`

Rules:

- direct production reads of
  `repoEnrichmentByRepoId`, `worktreeEnrichmentByWorktreeId`, or
  `pullRequestCountByWorktreeId` are forbidden after T6b unless listed in a
  temporary allowlist;
- every temporary allowlist entry must name owner, reason, and removal condition;
- `RepoCacheStore` may use whole-cache snapshots only through named snapshot APIs
  for persistence/diff work, not through observation of raw dictionaries;
- tests may keep dictionary assertions while proving API equivalence.

Proof:

- T3b creates a report-only inventory artifact before migration;
- T6b activates the failure mode after migration and fails on any unallowlisted
  production raw-dictionary read.

### T4. Write Red Tests For Repo Cache Row 1

Write surfaces:

- `Tests/AgentStudioTests/Core/Stores/WorkspaceRepoCacheTests.swift`
- `Tests/AgentStudioTests/Core/Stores/RepoCacheStoreTests.swift`
- optional focused file:
  `Tests/AgentStudioTests/Core/Stores/RepoCacheEntityMapTests.swift`

Test cases:

- per-repo enrichment slot invalidates only that repo reader;
- separate per-worktree enrichment and PR-count slots, with a composed facts
  reader only for consumers that render both;
- worktree enrichment update preserves PR count;
- PR-count update preserves enrichment;
- remove worktree writes nil facts then prunes on topology exit;
- persistence snapshot contains the same data shape as the old dictionaries;
- equal worktree content update skips slot invalidation and aggregate bump;
- source revision/last rebuilt changes remain aggregate-observable.

Proof:

- tests fail before row-1 implementation.

### T5. Implement `RepoEnrichmentCacheAtom` Entity Maps

Write surfaces:

- `Sources/AgentStudio/Core/State/MainActor/Atoms/RepoCacheAtom.swift`
- `Sources/AgentStudio/Core/Models/RepoWorktreeCacheFacts.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/RepoCacheStore.swift`

Implementation requirements:

- use `AtomEntityMap` for repo enrichment, worktree enrichment, and pull-request
  counts;
- keep worktree enrichment and pull-request count as separate keyed lanes so
  branch-only readers do not wake for PR-count changes;
- expose explicit read methods such as:
  - `repoEnrichment(for:)`
  - `worktreeEnrichment(for:)`
  - `pullRequestCount(for:)`
  - `worktreeFacts(for:)`
  - snapshot methods for persistence and non-hot bulk readers;
- observe aggregate revision in `RepoCacheStore` instead of whole dictionaries;
- keep hydration/clear/remove behavior semantically equivalent;
- keep dictionary-shaped snapshots only as read-only bridge surfaces, with named
  deletion/denylist gates.

Metrics:

- keep standard row-1 comparison on existing surface metrics;
- allow opt-in atom diagnostics under `AGENTSTUDIO_TRACE_TAGS=atoms`, using only
  the fixed `performance.atom.read`, `performance.atom.mutation`, and
  `performance.atom.derived` event family and the bounded fields listed in the
  spec.

Proof:

- T4 tests pass;
- no production behavior relies on direct mutable dictionaries.

### T6a. Migrate Production Readers Off Raw Repo-Cache Dictionaries

Write surfaces:

- `Sources/AgentStudio/App/Boot/AppDelegate+WorkspaceBoot.swift`
- `Sources/AgentStudio/App/Coordination/WorkspaceCacheCoordinator.swift`
- `Sources/AgentStudio/App/Panes/GitHubWebviewLaunchResolver.swift`
- `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift`
- `Sources/AgentStudio/App/Panes/WorkspaceLauncherProjector.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneDisplayDerived.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/TabDisplayDerived.swift`
- `Sources/AgentStudio/Core/Views/Panes/PaneManagementContext.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerSnapshot.swift`
- `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjection.swift`
- `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift`
- matching tests in `Tests/AgentStudioTests/...`

Migration rules:

- rows read `repoEnrichment(for:)`, `worktreeEnrichment(for:)`,
  `pullRequestCount(for:)`, or `worktreeFacts(for:)` by key, matching the data
  they actually render;
- adapters observe only relevant keys or aggregate snapshot state when bulk
  persistence is truly needed;
- no hot surface tracks `_ = repoCache.worktreeEnrichmentByWorktreeId`;
- no hot surface passes full repo-cache dictionaries into row rendering;
- command bar may still build its command snapshot, but repo/worktree facts must
  be key-scoped;
- sidebar projection either stops taking whole repo-cache dictionaries or is
  recorded as an explicit measured MainActor exception with expected cardinality,
  metric, owner, and follow-up gate;
- command-bar presence build either stops doing fleet work on `MainActor` or is
  recorded as an explicit measured MainActor exception with expected cardinality,
  metric, owner, and follow-up gate;
- every production raw-dictionary reader from T3b is migrated or listed in the
  temporary allowlist with owner and removal condition.

Proof:

- repo-cache production-read inventory has no unclassified raw-dictionary access;
- feature tests pass for sidebar rows, command-bar worktree rows, and tab-bar
  refresh behavior;
- no whole-dict hot path remains in named files;
- review packet lists every surviving measured MainActor exception with metric
  and no-go threshold.

### T6b. Activate Repo-Cache Hot-Reader Denylist

Write surfaces:

- `scripts/check-atomlib-boundaries.sh`
- `Tests/AgentStudioTests/Scripts/AtomLibBoundaryScriptTests.swift`

Rules:

- fail on unallowlisted production reads of raw repo-cache dictionaries;
- fail on whole-dict observation in hot readers;
- allow `RepoCacheStore` whole-cache access only through named snapshot APIs;
- allow tests to assert dictionary-shaped snapshots only where they prove
  compatibility.

Proof:

- boundary tests fail when a fixture contains an unallowlisted production raw
  dictionary read;
- `mise run lint` runs the activated check.

### T7. Add Row-1 Metrics And Preserve Proof Safety

Write surfaces:

- `scripts/verify-git-refresh-performance-workload.sh`
- `.mise.toml` only if a thin task alias is needed
- `Tests/AgentStudioTests/Scripts/GitRefreshPerformanceWorkloadScriptTests.swift`
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetricsTests.swift` if new bounded numeric metrics are added

Implementation requirements:

- reuse standard debug observability runner;
- reuse standard app/data/zmx/build-slot identity;
- build on the T0a query/reporting contract instead of inventing a second
  metrics path;
- query VictoriaMetrics for row-1 surfaces and command-bar interaction surfaces;
- report counts and p95/max-or-supported elapsed fields using the same names as
  the baseline artifact;
- fail if JSONL auto fallback is used;
- preserve loopback-only collector behavior and no new egress destination;
- preserve `--preflight-idle`, unique marker, live-process verification, and
  PID-scoped cleanup only;
- keep raw ids/paths/payloads out of metric labels;
- do not add a parallel launcher;
- if atom telemetry is exported, allow only fixed atom event names and fixed
  fields; add negative tests for dynamic event names, per-key numeric
  attributes, raw-path-shaped keys, and id-shaped keys.

Proof:

- script tests pin VictoriaMetrics requirement and no JSONL auto-pass;
- executable script/helper tests validate the summary/query output shape with
  fixed Victoria JSON fixtures or stubs;
- diagnostics tests pin metric projection if new numeric fields are introduced;
- trace configuration/projection tests run when diagnostics or OTLP environment
  flow changes;
- debug-launch behavior tests run when launcher-adjacent workload plumbing
  changes.

### T8. Reprofile And Decide Whether Row 2 Gets A New Plan

Input:

- T0b/T0c baseline;
- T9 row-1 after metrics.

Decision rule:

- If command bar/sidebar/tabbar/topology metrics now meet acceptance and samples
  do not show derived recompute as dominant, record a no-go note in
  `tmp/performance-proofs/...` and do not broaden the PR.
- If derived recompute remains dominant, select one row-2 candidate:
  - likely `PaneDisplayDerived`, `WorkspacePaneDerived`, or
    `WorkspaceTabLayoutDerived`;
  - not all deriveds at once;
  - write a follow-up plan or plan amendment with exact files, proof matrix,
    metrics, and review gate before any row-2 production code.

Proof:

- row-2 decision artifact under `tmp/`;
- if row 2 is needed, a follow-up plan-review gate exists before code;
- this plan's completion does not require row-2 production adoption.

### T9. Run Row-1 Workload Proof

Commands:

- `mise run observability:up`
- `mise run verify-git-refresh-performance-workload`
- command-bar interaction proof from T0c, repeated after row 1
- dedicated atom telemetry proof only when the run is validating atom
  instrumentation; standard workload proof excludes `atoms` unless explicitly
  overridden.

Acceptance:

- VictoriaMetrics proof path used;
- no JSONL auto fallback;
- default workload trace tags exclude `atoms` so high-volume atom tracing does
  not perturb the standard hot-path comparison;
- after metrics recorded in `tmp/performance-proofs/<timestamp>-atomlib-v2-row1/`;
- no target surface worsens by more than 10 percent in count, p95, or max under
  the same workload unless explained and replanned;
- `performance.commandbar.items` improves by at least 50 percent in count or p95
  during the command-bar interaction scenario if the implementation claims Cmd+P
  / `#` improvement;
- at least one expected repo-cache fanout surface improves by at least 50 percent
  in count or p95:
  - `performance.tabbar.refresh`
  - `performance.sidebar.projection`
  - `performance.sidebar.row_index`
  - `performance.topology.repo_and_worktree`
- if p95 is unavailable for a surface, the artifact must say so and use event
  count plus max elapsed for that surface;
- if expected fanout does not improve, stop and reprofile before row 2.

### T10. Full Validation And Review Packet

Commands:

- focused Swift tests for AtomLib, repo cache, hot readers, scripts, diagnostics;
- `mise run test-fast`;
- `mise run test`;
- `mise run lint`;
- `mise run observability:up`;
- `mise run verify-git-refresh-performance-workload`;
- command-bar interaction proof repeated after row 1.

Output:

- summarize changed files by ownership;
- include baseline vs after metrics;
- include the full repo-cache raw-dictionary production-reader inventory and all
  temporary allowlist entries;
- include every measured MainActor exception with expected cardinality, metric,
  and no-go threshold;
- include tests/lint exit codes;
- include any unrun proof layer with reason;
- route to `implementation-review-swarm` before PR-ready claim.

## Validation Gates By Layer

Unit:

- AtomLib primitive tests.
- Repo cache entity behavior tests.
- Derived memoization tests.

Integration:

- RepoCacheStore observation/persistence tests.
- CommandBar worktree row tests.
- RepoExplorer row/filter tests.
- TabBar adapter observation tests.

Tooling:

- compile-negative fixture test.
- atom boundary script tests.
- workload script tests.
- `mise run lint`.

Smoke / E2E-ish local workload:

- standard debug observability launcher.
- VictoriaMetrics workload proof.

Repo-wide:

- `mise run test`.
- `mise run lint`.

## Rollback / Recovery

- AtomLib primitives can land unused behind tests, but production migration must
  not leave two permanent read models.
- If row-1 migration regresses workload metrics, revert the row-1 production
  adoption while keeping primitive tests only if they are unused and clean.
- If boundary scripts create false positives, stop and fix the script/tests
  before editing product code around the false positive.
- If Victoria stack is unavailable, do not claim performance proof; capture the
  blocker and stop before PR-ready status.

## Risks

- `AtomContentEquatable` or a broad default equality API can reopen the wrong
  comparator bug. Keep domain payloads explicit.
- Compatibility snapshot surfaces can hide whole-dict hot reads. Use named
  denylist gates, not a loose grep.
- `DerivedValue` can be over-adopted and fail to improve UX because lazy pull
  does not prevent body wakeups. Gate row 2 on metrics.
- Metrics can become high-cardinality or leak local paths if labels are not
  controlled. Keep row-1 metrics bounded and numeric.
- Tab bar and command bar may need per-visible-key observation rather than
  aggregate refresh. Treat adapter behavior as a first-class integration test.

## Open Questions

1. Exact scalar allowlist for default `AtomValue` equality.
   Recommendation: start tiny and require explicit comparators for all structs
   in row 1.

2. Whether to add a thin `mise run verify-atomlib-v2-performance-workload` alias.
   Recommendation: prefer extending the existing workload script first; add an
   alias only if it improves operator clarity without creating a new launcher.

3. Row-2 target.
   Recommendation: decide after row-1 VictoriaMetrics, not before.

4. `SessionRuntime` actor cleanup.
   Recommendation: separate follow-up spec/plan unless row-1 profiling directly
   implicates it.

## Next Workflow

Run `shravan-dev-workflow:implementation-execute-plan` on this reviewed plan.
Start with T0a proof-harness preparation, then capture T0b/T0c baselines before
any production AtomLib, repo-cache, or hot-reader code changes.
