# Repository Topology SQL Domain Implementation Plan

Date: 2026-06-26
Status: revised after `plan-review-swarm`; ready for `implementation-execute-plan`
Worktree: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.repository-sql-domain`
Branch: `feature/repository-sql-domain`
Source spec: `docs/specs/2026-06-26-repository-topology-sql-domain.md`

## Source Coverage

- Spec line count: 402.
- Parent read chunks: 1-120, 121-260, 261-402.
- Goal details read: `tmp/workflow-state/2026-06-26-repository-topology-sql-domain/details.md`.
- Spec review source read: `tmp/spec-workflows/2026-06-26-repository-topology-sql-domain/review/spec-review-report.md`.
- Plan review source read: `tmp/plan-workflows/2026-06-26-repository-topology-sql-domain/review/plan-review-report.md`.

Planning lanes are parent-authored in this pass. Reasoning effort policy:
medium for bounded codebase/proof/scope lanes; high for recovery, SQL, and
cross-store sequencing. Candidate lane artifacts live under
`tmp/plan-workflows/2026-06-26-repository-topology-sql-domain/`.

Plan review revisions accepted:

- S3 now defines an explicit save-coordination boundary before removing topology from `WorkspaceSQLiteSnapshot`.
- S3/S4/S5 are serialized where their UI/read-model write sets overlap.
- Validation gates now name focused commands and required evidence artifacts.
- S6 now carries a performance proof table with raw-path scrub checks.
- Legacy import routes are explicit in S3/S4/S5.
- PR wrapup is a later lifecycle route after implementation proof and review, not a product-code task inside this plan.

## Goal

Implement the accepted SQL-first repository topology domain split:

- remove durable pane tags;
- add repo/worktree tags as topology state;
- move topology observation and persistence out of `WorkspaceStore`;
- rename `WorkspaceRepositoryTopologyAtom` to `RepositoryTopologyAtom`;
- preserve explicit workspace scoping and staged/completed save recovery;
- remove manual repo/worktree checkout colors while keeping automatic colors;
- add durable tab color under tab state;
- prove command/sidebar/readers, recovery, IPC non-expansion, and performance.

## Non-Goals

- No `AppBenchStore` or `AppBenchAtom`.
- No active workspace selection redesign.
- No repo enrichment/cache/inbox persistence migration into topology.
- No visible tag chips, tag grouping, tag ordering, tag colors, or tag IPC.
- No persisted repo/worktree/checkout colors.
- No new auth, network, sandbox, or encryption design.
- No merge or PR closeout in this plan phase.

## Current Evidence Anchors

- `WorkspaceCoreMigrations.swift` currently registers migrations `001` through `009`, creates topology tables in migration `002`, creates `pane_tag`, and creates `tab_shell` without color.
- `WorkspaceCoreRepository+TopologyMutation.swift` currently replaces unavailable rows, watched paths, repo rows, worktree rows, then unavailable rows.
- `WorkspaceRepositoryTopologyAtom.swift` currently owns repos, watched paths, unavailable ids, lookup precedence, and `repoAndWorktree` telemetry.
- `WorkspaceStore.swift` currently owns `repositoryTopologyAtom`, observes topology fields, and builds topology into `WorkspacePersistenceTransformer.makeLiveSQLiteSnapshotResult`.
- `WorkspaceSQLiteSnapshot.swift` currently carries repos, worktrees, watched paths, and unavailable repo ids.
- `WorkspaceSQLiteStoreBackend.swift` currently saves topology through `replaceWorkspaceSnapshotStaged` under the staged/completed protocol.
- `WorkspaceSettingsStore.swift`, `SidebarCacheState.swift`, `WorkspacePersistor+Payloads.swift`, and `RepoPresentation.swift` currently carry manual checkout color state.
- Existing proof homes include `WorkspaceCoreMigrationTests`, `WorkspaceCoreRepositoryTopologyTests`, `WorkspaceSQLiteStoreBridgeTests`, `WorkspaceSQLiteCommitProtocolTests`, `WorkspaceSettingsStoreTests`, `SidebarCacheStateTests`, `WorkspaceRepositoryTopologyAtomTests`, `CommandBarUnifiedWorktreeDataSourceTests`, `RepoExplorerViewTests`, `PaneDisplayDerivedTests`, `InboxNotificationListModelTests`, and `GitRefreshPerformanceWorkloadScriptTests`.

## Vertical Slices

### S0 - Preflight And Baseline Evidence

Source anchors: spec R1/R14 and proof expectations.

Behavior:

- Confirm the branch/worktree is isolated and current.
- Capture current focused tests and performance baseline before product edits.
- Record baseline artifact under repo-local `tmp/`, not as a source of truth.

Likely write surfaces:

- `tmp/plan-workflows/2026-06-26-repository-topology-sql-domain/proof/`
- No product code.

Proof:

- Focused current-state command output for migration/topology/store tests listed in the validation command matrix.
- Performance baseline using the existing git-refresh workload when available.
- Baseline proof artifact: `tmp/plan-workflows/2026-06-26-repository-topology-sql-domain/proof/baseline.md`.
- If Victoria-backed performance proof is available, record the trace/metric marker and raw-path scrub result in the baseline artifact.
- Stop if setup or test infrastructure fails before code edits.

Split/replan trigger:

- If baseline cannot run because of environment/setup, report blocker before editing implementation code.

### S1 - SQL Migration And Core Repository Tag Contract

Source anchors: spec lines 36-55, 120-187, 345-352.

Behavior:

- Add the next core migration and fresh-schema DDL.
- Drop `pane_tag`; create `repo_tag` and `worktree_tag`; add strict nullable `tab_shell.color_hex`.
- Keep `workspace_id` on repo/worktree topology tables.
- Add repository records and APIs for repo/worktree tags.
- Validate tag text at model/API level; SQL remains last-line shape guard.
- Write tag replacement inside topology mutation transaction after owner reconciliation.

Likely write surfaces:

- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreMigrations.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+Topology*.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+TabGraph*.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspaceCoreMigrationTests.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspaceCoreRepositoryTopologyTests.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspaceCoreRepositoryTopologyValidationTests.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspaceCoreRepositoryTabGraphTests.swift`

Proof:

- Red/green migration tests for fresh schema, migrated schema, `pane_tag` removal, tag tables, strict tab color column, and no repo/worktree/checkout color SQL.
- Integration tests for repo/worktree tag round-trip, cascade on owner deletion, cross-workspace rejection, unsafe tag rejection, and invalid tab color rejection/normalization.

Dependencies:

- First product-code slice. S2-S6 depend on the schema/record shape.

### S2 - RepositoryTopologyAtom Rename And Live Tag State

Source anchors: spec lines 39-64, 189-212, 354-363.

Behavior:

- Mechanically rename `WorkspaceRepositoryTopologyAtom` to `RepositoryTopologyAtom`.
- Add repo tag and worktree tag live state.
- Preserve current lookup precedence exactly: longest path first, then current tie-breakers.
- Preserve existing topology lookup telemetry attributes and avoid raw paths.
- Update `AtomRegistry`, helpers, tests, and call sites.

Likely write surfaces:

- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceRepositoryTopologyAtom.swift` renamed/replaced with `RepositoryTopologyAtom.swift`
- `Sources/AgentStudio/AtomRegistry.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/*Derived.swift`
- `Sources/AgentStudio/App/**`
- `Tests/AgentStudioTests/Core/State/MainActor/Atoms/WorkspaceRepositoryTopologyAtomTests.swift` renamed or updated
- `Tests/AgentStudioTests/Architecture/RepositoryTopologyHotPathArchitectureTests.swift`
- `Tests/AgentStudioTests/Helpers/WorkspaceStoreTestAccess.swift`

Proof:

- Red/green atom tests for tag hydration/mutation and unsafe tag rejection.
- Red/green overlapping/nested worktree lookup test preserving current precedence.
- Architecture/source checks updated to the new atom name and telemetry path.

Dependencies:

- S1 tag model.

Split/replan trigger:

- If call-site churn makes the rename too broad to safely combine with tag state, split into S2a mechanical rename and S2b tag state.

### S3 - RepositoryTopologyStore And WorkspaceStore Boundary

Source anchors: spec lines 10-12, 39-49, 78-118, 214-268, 305-314, 354-371.

Behavior:

- Add `RepositoryTopologyStore` scoped by explicit workspace id from workspace boot/identity ownership.
- Move topology restore/hydration, observation, dirty state, debounce/flush participation, and SQLite write participation out of `WorkspaceStore`.
- `WorkspaceStore` may sequence/await topology restore but must not hydrate topology or observe topology fields.
- Introduce an explicit save bundle/coordinator before removing topology-owned fields from `WorkspaceSQLiteSnapshot`.
- Keep topology writes under the existing staged/completed workspace save status for this slice.
- Preserve legacy bootstrap import into core SQLite without making legacy JSON a second live topology owner.

Save coordination contract:

- Add one small persistence orchestration boundary, named by the implementation after reading nearby store patterns. Acceptable shapes are `WorkspaceSQLiteSaveBundle` plus backend overloads, or a narrow `WorkspacePersistenceCommitCoordinator`; do not create an independent topology completion marker.
- The boundary gathers workspace-owned core records from `WorkspaceStore` and topology records from `RepositoryTopologyStore` separately.
- `WorkspaceSQLiteSnapshot` remains the workspace-owned live snapshot and must carry no repos, worktrees, watched paths, unavailable repo ids, repo tags, or worktree tags.
- `RepositoryTopologyStore` produces a topology record/snapshot for the same explicit workspace id and `persistedAt` generation.
- The SQLite backend still calls the core repository staging path with workspace, topology, pane graph, tab shell, and tab graph records in one core database transaction.
- Commit order remains core staged -> local completed -> core completed. Restore trusts only a core completion token that the matching local sidecar can match.
- `WorkspaceStore` may coordinate flush order but must not observe topology fields and must not derive topology write scope from `ActiveWorkspaceSelectionAtom`.
- Legacy JSON import materialization uses the same save bundle/coordinator path: old topology may bootstrap into core SQLite, but the legacy payload is not a second live topology owner after materialization.

Likely write surfaces:

- New `Sources/AgentStudio/Core/State/MainActor/Persistence/RepositoryTopologyStore.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistenceTransformer.swift`
- New or revised save coordination type near the existing workspace persistence boundary
- `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteSnapshot.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSQLiteStoreBackend.swift`
- `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastore.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore+LegacySQLiteImport.swift`
- boot/composition files such as `AppDelegate+WorkspaceBoot.swift` and `AtomRegistry.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreBridgeTests.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteCommitProtocolTests.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteSnapshotRoleTests.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreArchitectureTests.swift`

Proof:

- Red/green source/architecture test that `WorkspaceStore.observePersistedState` no longer observes topology.
- Red/green snapshot role test that `WorkspaceSQLiteSnapshot` carries no repos, worktrees, watched paths, unavailable ids, repo tags, or worktree tags.
- Red/green save-boundary test proving the backend still receives topology separately and stages topology with workspace/pane/tab rows in one core transaction.
- Integration store round-trip proving `RepositoryTopologyStore.restore` hydrates `RepositoryTopologyAtom` before pane/tab/filesystem readers need topology.
- Crash/restart integration proof: staged topology write plus failed local/pane/tab write must not restore mixed generations.
- Legacy import proof: `WorkspaceStore+LegacySQLiteImport` materialization reaches the same save bundle/coordinator and does not re-establish `WorkspaceStore` as topology observer.
- Existing staged/completed commit protocol tests stay green.

Dependencies:

- S1, S2.

Split/replan trigger:

- If the explicit save bundle/coordinator cannot preserve the staged/completed protocol without introducing an independent topology completion marker, stop and return to spec.

### S4 - Pane Tag Removal And Repo/Worktree Tag Reader Search

Source anchors: spec lines 51-55, 270-303, 373-382, 391-396.

Behavior:

- Remove pane-tag durable facets, pane graph codec/mutation paths, legacy hydration, and command-bar pane keyword use.
- Wire repo/worktree tags into command-bar repo/worktree keywords and sidebar/repo explorer filtering/search metadata only.
- Do not add visible chips, grouping, ordering, tag colors, or IPC exposure.
- Preserve unavailable repo visibility and existing actions.
- Decode or encounter legacy pane-tag payloads only as ignored/discarded data. Do not migrate pane tags into repo/worktree tags and do not re-encode them.

Likely write surfaces:

- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+PaneGraph*.swift`
- `Sources/AgentStudio/Core/Models/Pane*.swift` and pane metadata models as needed
- `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift`
- `Sources/AgentStudio/Features/RepoExplorer/**`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistor+Payloads.swift`
- IPC/programmatic DTO tests if field allowlists live there
- `Tests/AgentStudioTests/Core/Stores/WorkspaceCoreRepositoryPaneGraphTests.swift`
- `Tests/AgentStudioTests/Features/CommandBar/CommandBarUnifiedWorktreeDataSourceTests.swift`
- `Tests/AgentStudioTests/Features/CommandBar/CommandBarWorktreeRowBuilderTests.swift`
- `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerFilterTests.swift`
- `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewTests.swift`

Proof:

- Red/green pane graph tests proving pane tags no longer persist or hydrate.
- Red/green command/sidebar search tests where repo/worktree tag queries match the intended rows.
- Negative proof that visible chips/grouping/order are not added.
- IPC field allowlist proof excludes repo/worktree tags.
- Legacy proof that old pane tags are ignored/discarded by SQLite import and legacy payload loading, then absent from re-encoded payloads.

Dependencies:

- S1, S2, S3 enough to expose tag read state.
- Runs after S5 has removed conflicting repo explorer manual-color actions from shared UI files, or owns only non-overlapping core/search files.

### S5 - Color Cutover: Remove Manual Checkout Colors, Keep Automatic Colors, Add Tab Color

Source anchors: spec lines 57-64, 165-187, 282-293, 331-341, 373-382, 391-396.

Behavior:

- Remove `SidebarCheckoutColorAtom`, checkout color settings/sidebar payload encoding, legacy re-encoding, manual "set icon color" UI/action, and checkout color overrides in presentation.
- Preserve automatic fork/repo/worktree palette assignment derived from stable topology/grouping inputs.
- Add durable tab color to tab shell/domain model, repository records, atom mutation surface, persistence transformer/bridge, and tab rendering.
- Keep tab color separate from automatic repo/worktree colors.
- Decode legacy checkout color keys only for forward tolerance where existing decoders require it; ignored values must not hydrate atoms, affect presentation, or re-encode.

Likely write surfaces:

- `Sources/AgentStudio/Core/State/MainActor/Atoms/SidebarCacheState.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceSettingsStore.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistor+Payloads.swift`
- `Sources/AgentStudio/Core/Models/RepoPresentation.swift`
- `Sources/AgentStudio/Features/RepoExplorer/**`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneDisplayDerived.swift`
- `Sources/AgentStudio/Core/Models/TabShell.swift`
- `Sources/AgentStudio/Core/Models/Tab.swift` if display state requires compatibility
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabShellAtom.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+TabGraph*.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspaceSettingsStoreTests.swift`
- `Tests/AgentStudioTests/Core/State/MainActor/Atoms/SidebarCacheStateTests.swift`
- `Tests/AgentStudioTests/Core/Stores/SidebarCacheStoreTests.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspacePersistorTests.swift`
- `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewTests.swift`
- `Tests/AgentStudioTests/Core/Views/PaneDisplayDerivedTests.swift`
- `Tests/AgentStudioTests/Core/State/WorkspaceTabShellAtomTests.swift`
- `Tests/AgentStudioTests/Core/Stores/WorkspaceCoreRepositoryTabGraphTests.swift`
- `Tests/AgentStudioTests/Features/InboxNotification/Models/InboxNotificationListModelTests.swift`

Proof:

- Red/green absence checks for checkout color mutation APIs, settings/sidebar cache encoding, legacy re-encoding, and manual color UI/action.
- Automatic color stability tests for command bar, sidebar/repo explorer, pane display, launcher, and inbox using equivalent topology/grouping inputs.
- Tab color round-trip tests through SQL, atom, restore, and tab display.
- Invalid tab color values rejected or normalized before persistence.
- Legacy proof that old settings/sidebar checkout colors decode as ignored tolerance and are not hydrated into live atoms or re-encoded into settings/sidebar/cache payloads.

Dependencies:

- S1 tab color SQL.
- Runs before S4 touches shared repo explorer UI files, or S4 must be restricted to disjoint command/search/core files. Tab persistence integration depends on S3/S6 bridge shape.

### S6 - Reader Compatibility, IPC Guardrails, Filesystem Projection, And Performance

Source anchors: spec lines 66-76, 295-303, 316-329, 384-396.

Behavior:

- Update command bar, repo explorer/sidebar, pane display, tab display, launcher, inbox, filesystem projection, boot replay, and IPC readers to use topology via the new owner.
- Preserve repoId/worktreeId compatibility.
- Keep repo/worktree tags and tab color out of pane IPC snapshots.
- Preserve raw-path-free OTLP/Victoria telemetry; repo-local `tmp` may hold scoped fixture paths only.
- Add or reuse per-surface performance proof signals named in the spec.

Likely write surfaces:

- `Sources/AgentStudio/Features/CommandBar/**`
- `Sources/AgentStudio/Features/RepoExplorer/**`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneDisplayDerived.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/TabDisplayDerived.swift`
- `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+FilesystemSource.swift`
- `Sources/AgentStudio/App/**Launcher**` / launcher projector files
- `Sources/AgentStudio/Features/InboxNotification/**`
- `Sources/AgentStudioProgrammaticControl/**` and IPC query adapter files as needed
- `scripts/verify-git-refresh-performance-workload.sh` only if existing signals are insufficient
- `Tests/AgentStudioTests/Features/CommandBar/**`
- `Tests/AgentStudioTests/Features/RepoExplorer/**`
- `Tests/AgentStudioTests/Core/Views/PaneDisplayDerivedTests.swift`
- `Tests/AgentStudioTests/Core/Views/TabDisplayDerivedTests.swift`
- `Tests/AgentStudioTests/App/Coordination/WorkspaceSurfaceCoordinatorFilesystemSourceTests.swift`
- `Tests/AgentStudioTests/Features/InboxNotification/Models/**`
- `Tests/AgentStudioTests/Scripts/GitRefreshPerformanceWorkloadScriptTests.swift`

Proof:

- Reader tests for all named surfaces.
- IPC snapshot/list JSON allowlist tests excluding repo/worktree tags, tab color, and raw paths.
- Filesystem projection tests preserving generation ordering and unavailable filtering.
- Before/after performance artifact with command-bar rows, sidebar/repo projection, tab identity reads, topology lookup, filesystem projection, and save/flush coordination signals.
- OTLP/Victoria evidence uses hashes/counts/latencies, not raw paths.

Performance proof table:

| Surface | Proof modality | Existing vs new signal decision | Artifact |
| --- | --- | --- | --- |
| Command-bar repo/worktree rows | Focused row-construction timing with row counts, plus command-bar tests | Reuse existing command-bar/performance signal if present; otherwise add focused metric/test timing inside S6 | `tmp/plan-workflows/2026-06-26-repository-topology-sql-domain/proof/command-bar-performance.md` |
| Sidebar/repo explorer projection | Projection timing or deterministic fixture timing with repo/worktree counts | Reuse existing projection workload if present; otherwise add focused projection timing | `tmp/plan-workflows/2026-06-26-repository-topology-sql-domain/proof/sidebar-projection-performance.md` |
| Tab bar/display topology identity reads | Focused refresh/read assertion and hot-loop absence check | No full metric required unless implementation introduces repeated topology lookup in tab display | `tmp/plan-workflows/2026-06-26-repository-topology-sql-domain/proof/tab-display-performance.md` |
| `repoAndWorktree(containing:)` lookup | Focused lookup timing plus nested/overlapping precedence tests | Preserve existing `repoAndWorktreeLookup` telemetry attributes; add counts/latency only if missing | `tmp/plan-workflows/2026-06-26-repository-topology-sql-domain/proof/topology-lookup-performance.md` |
| Filesystem projection sync | Generation/unavailable-filtering tests plus timing/count signal when available | Reuse existing filesystem projection proof if present; otherwise record focused fixture timing | `tmp/plan-workflows/2026-06-26-repository-topology-sql-domain/proof/filesystem-projection-performance.md` |
| Persistence/write coordination | Save/flush count and latency around topology replacement and staged/completed status | Add or reuse `performance.coordinator.write` style proof around the new save bundle/coordinator | `tmp/plan-workflows/2026-06-26-repository-topology-sql-domain/proof/save-coordination-performance.md` |

Raw-path proof:

- Victoria/OTLP proof must include a search/check showing emitted topology performance events use hashes, counts, ids already allowed by policy, and latency values, not raw filesystem paths.
- Repo-local JSONL or markdown artifacts may contain disposable fixture paths only when the artifact clearly scopes them as local debug evidence.
- If the shared Victoria stack is unavailable, record the blocker and run the focused lower-layer timing/tests; do not silently downgrade standard proof to JSONL.

Dependencies:

- S3-S5.

Split/replan trigger:

- If performance proof requires new instrumentation across multiple hot paths, split an instrumentation-only sub-slice before behavior changes and prove the instrumentation is raw-path-free before using it as regression evidence.

### S7 - Final Integration And PR-Ready Proof Package

Source anchors: full spec proof expectations and goal terminal condition.

Behavior:

- Integrate slices, remove stale references, update docs/architecture references only where they remain authoritative and stale.
- Produce final implementation evidence.
- Run `implementation-review-swarm` after implementation proof.
- Route to `implementation-pr-wrapup` only after accepted implementation-review findings are addressed. PR wrapup is the next lifecycle workflow, not a product-code task inside this implementation plan.

Likely write surfaces:

- Any stale architecture tests/docs that reference old atom/store names.
- PR description/proof artifact under `tmp/` if needed.

Proof:

- Focused targeted tests per slice.
- `mise run test`.
- `mise run lint`.
- Performance workload proof or explicit blocker with targeted lower-layer pass/fail.
- `implementation-review-swarm` after implementation proof.
- Orchestrator transition to `implementation-pr-wrapup` only after review findings are addressed.

## Requirements / Proof Matrix

| Requirement / claim | Source | Owning slice | Proof modality | Layer | Evidence source | Freshness guard | Red/green |
| --- | --- | --- | --- | --- | --- | --- | --- |
| SQL migration first, pane tags removed, repo/worktree tags added | spec R1/R6/R7; SQL contract | S1 | Migration and repository tests | unit/integration DB | `WorkspaceCoreMigrationTests`, `WorkspaceCoreRepositoryTopologyTests` | Run after schema edit from this worktree | yes |
| Workspace scoping remains explicit | spec product intent/R2/R13/store contract | S1/S3 | Cross-workspace rejection tests and store construction tests | integration DB/store | topology repository/store tests | Assert no active-selection-derived writes | yes |
| Tag input is safe local text | spec SQL/atom/proof | S1/S2/S4 | Model validation tests and display/search tests | unit/integration | topology atom/repo explorer/command tests | Include control/newline/ANSI/bidi cases | yes |
| Tab color is only persisted color | spec R8/R10/SQL/non-goals | S1/S5 | SQL/model/store/display tests plus absence checks | unit/integration | tab graph, settings, sidebar, repo presentation tests | Search for forbidden color storage after cutover | yes |
| Automatic colors remain | spec R9/reader proof | S5/S6 | Surface-specific deterministic tests | unit/integration | command/sidebar/pane/launcher/inbox tests | Equivalent topology/grouping inputs | yes |
| Topology leaves `WorkspaceStore` snapshot boundary | spec R2/R4/WorkspaceStore narrowing | S3 | Architecture/source and integration tests | unit/integration/store | `WorkspaceStoreArchitectureTests`, snapshot role tests, bridge tests | Source search proves no topology fields in snapshot | yes |
| Staged/completed recovery remains coherent | spec migration/recovery | S3 | Crash-window integration tests | integration DB/store | `WorkspaceSQLiteCommitProtocolTests`, bridge tests | Simulate staged topology plus failed local/pane/tab write | yes |
| Pane tags are impossible after cutover | spec R6/guardrails | S1/S4 | Schema, codec, legacy, and IPC absence tests | unit/integration | migration, pane graph, persistor, IPC tests | Search `pane_tag` only in migration-drop tests/docs | yes |
| Tag reader exposure is search-only | spec tag exposure matrix | S4/S6 | Positive search and negative UI/IPC tests | unit/integration | command, repo explorer, IPC tests | No chips/grouping/order in first slice | yes |
| Lookup precedence preserved | spec atom/proof | S2/S6 | Nested path lookup tests and timing signal | unit/perf | topology atom tests and perf artifact | Compare current precedence before behavior changes | yes |
| IPC does not grow accidental exposure | spec R12/IPC contract | S4/S6 | JSON allowlist tests | integration/API | IPC/programmatic tests | Assert tags/tab color/raw paths absent | yes |
| Performance/observability proof is scoped and scrubbed | spec R14/performance | S0/S6/S7 | Before/after artifact, metrics/log review | perf/observability | `tmp/.../proof`, Victoria when available | Raw paths forbidden in OTLP/Victoria output | no red; evidence plus triage |

## Execution DAG

```text
gate 0: preflight, current-state re-anchor, baseline evidence
  |
  v
S1 SQL migration and core repository tag/tab-color contract
  |
  v
S2 RepositoryTopologyAtom rename and live tag state
  |
  v
integration gate A: schema + atom tests pass; call-site rename reviewed
  |
  v
S3 RepositoryTopologyStore and save-coordination boundary
  |
  v
integration gate B: snapshot topology-free, save bundle still stages topology atomically
  |
  v
S5 manual color removal, automatic color preservation, tab color
  |
  v
S4 pane tag removal and repo/worktree tag search readers
  |
  v
integration gate C: no stale snapshot/settings/pane-tag/manual-color owners
  |
  v
S6 reader compatibility, IPC guardrails, filesystem projection, performance
  |
  v
S7 final validation, implementation-review-swarm, PR-ready wrapup
```

Parallelization:

- Default execution is serial through S3 -> S5 -> S4 because store/save coordination, manual color removal, repo explorer, command/search, pane display, and presentation readers overlap.
- Parallel work is allowed only for explicitly disjoint sub-slices:
  - S3 save-coordination tests may run independently from S5 UI color removal after S2 settles.
  - S5 tab-color persistence may run independently from S5 manual checkout color UI removal only if the file ownership is disjoint after inspection.
  - S4 command-bar search tests may run independently from S4 repo explorer search only if both consume an already-stable tag read API and do not edit shared fixtures.
- S6 should remain parent/integration-owned because it touches reader compatibility across the slices.

## Validation Gates

Preflight:

- `git status --short --branch`
- `mise run test -- --filter WorkspaceCoreMigrationTests`
- `mise run test -- --filter WorkspaceCoreRepositoryTopologyTests`
- `mise run test -- --filter WorkspaceSQLiteStoreBridgeTests`
- `mise run test -- --filter WorkspaceSQLiteCommitProtocolTests`
- `mise run verify-git-refresh-performance-workload` when the shared observability stack is ready; otherwise record blocker plus focused lower-layer baseline in `tmp/plan-workflows/2026-06-26-repository-topology-sql-domain/proof/baseline.md`

Slice gates:

| Slice | Required focused commands | Evidence |
| --- | --- | --- |
| S1 SQL | `mise run test -- --filter WorkspaceCoreMigrationTests`; `mise run test -- --filter WorkspaceCoreRepositoryTopologyTests`; `mise run test -- --filter WorkspaceCoreRepositoryTopologyValidationTests`; `mise run test -- --filter WorkspaceCoreRepositoryTabGraphTests` | Fresh/migrated schema, tag constraints, tab color constraints, no forbidden color SQL |
| S2 atom | `mise run test -- --filter WorkspaceRepositoryTopologyAtomTests` or renamed successor; `mise run test -- --filter RepositoryTopologyHotPathArchitectureTests` | Atom rename, tag hydration/mutation, unsafe tag rejection, lookup precedence, raw-path-free telemetry attributes |
| S3 store/save boundary | `mise run test -- --filter WorkspaceStoreArchitectureTests`; `mise run test -- --filter WorkspaceSQLiteSnapshotRoleTests`; `mise run test -- --filter WorkspaceSQLiteStoreBridgeTests`; `mise run test -- --filter WorkspaceSQLiteCommitProtocolTests`; `mise run test -- --filter WorkspaceSQLiteStoreRecoveryTests`; `mise run test -- --filter WorkspaceSQLiteLegacyImportStatusTests` | `WorkspaceStore` no topology observation, topology-free snapshot, save bundle still stages topology atomically, recovery and legacy bootstrap preserved |
| S4 tags/readers | `mise run test -- --filter WorkspaceCoreRepositoryPaneGraphTests`; `mise run test -- --filter WorkspacePersistorTests`; `mise run test -- --filter CommandBarUnifiedWorktreeDataSourceTests`; `mise run test -- --filter CommandBarWorktreeRowBuilderTests`; `mise run test -- --filter RepoExplorerFilterTests`; `mise run test -- --filter RepoExplorerViewTests`; IPC/programmatic allowlist successor tests | Pane tags impossible/ignored, repo/worktree tags searchable only, no chips/grouping/order/IPC exposure |
| S5 colors/tab color | `mise run test -- --filter WorkspaceSettingsStoreTests`; `mise run test -- --filter SidebarCacheStateTests`; `mise run test -- --filter SidebarCacheStoreTests`; `mise run test -- --filter WorkspacePersistorTests`; `mise run test -- --filter RepoExplorerViewTests`; `mise run test -- --filter PaneDisplayDerivedTests`; `mise run test -- --filter WorkspaceTabShellAtomTests`; `mise run test -- --filter WorkspaceCoreRepositoryTabGraphTests`; `mise run test -- --filter InboxNotificationRepoPresentationTests`; `mise run test -- --filter InboxNotificationListModelTests` | Manual checkout colors absent/ignored/not re-encoded, automatic colors stable, tab color SQL/atom/restore/display round trip |
| S6 integration/perf | `mise run test -- --filter CommandBarUnifiedWorktreeDataSourceTests`; `mise run test -- --filter CommandBarWorktreeRowBuilderTests`; `mise run test -- --filter RepoExplorerViewTests`; `mise run test -- --filter PaneDisplayDerivedTests`; `mise run test -- --filter TabDisplayDerivedTests`; `mise run test -- --filter WorkspaceSurfaceCoordinatorFilesystemSourceTests`; `mise run test -- --filter WorkspaceSQLiteDatastoreActorTests`; `mise run test -- --filter GitRefreshPerformanceWorkloadScriptTests`; `mise run verify-git-refresh-performance-workload` | Reader compatibility, IPC guardrails, filesystem generation/unavailable filtering, before/after performance artifacts, raw-path scrub proof |

Source absence checks after each relevant slice:

- `rg -n "pane_tag|durableFacets\\.tags" Sources/AgentStudio Tests/AgentStudioTests`
- `rg -n "SidebarCheckoutColor|checkoutColors|setCheckoutColor|Set Icon Color|checkoutColorOverrides|colorPresets" Sources/AgentStudio Tests/AgentStudioTests`
- `rg -n "repos: \\[CanonicalRepo\\]|worktrees: \\[CanonicalWorktree\\]|watchedPaths: \\[WatchedPath\\]|unavailableRepoIds" Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteSnapshot.swift`

Allowed hits must be limited to migration-drop tests, legacy-ignore tests, renamed-successor tests, and this plan/spec documentation. Product runtime hits are failures unless the slice explicitly has not reached the cutover point yet.

Final gates:

- `mise run test`
- `mise run lint`
- `mise run verify-git-refresh-performance-workload` or a scoped blocker with the S6 lower-layer performance artifacts and explicit reason Victoria proof could not run
- `implementation-review-swarm`
- orchestrator route to `implementation-pr-wrapup` after accepted implementation-review findings are addressed

## Security And Reliability Context

Applicable:

- Tags are untrusted local user text that may enter search, display, logs, and local proof artifacts.
- SQLite stores local filesystem paths by design; OTLP/Victoria proof must not export raw paths.
- IPC/programmatic snapshots are an API boundary and must not accidentally expose new tags, tab color, or raw paths.
- Recovery correctness is reliability-critical because topology and pane/tab graphs can cross-reference ids.

Plan constraints:

- Validate unsafe tags before display/search/log use.
- Keep raw paths out of OTLP/Victoria topology telemetry.
- Prove staged/completed status prevents mixed topology/workspace graph generations.
- Treat full-suite/build infrastructure failures outside these slices as blockers, not scope expansion.

## Rollback / Recovery Notes

- This is a hard cutover. Do not keep old and new topology persistence paths live in parallel.
- If S3 cannot preserve the staged/completed protocol, stop and revise the spec before inventing a topology-specific commit protocol.
- If migration tests reveal existing user data needs preservation beyond the spec's discard/ignore policy for pane tags or checkout colors, stop and ask; do not silently migrate pane tags to repo/worktree tags.

## Resolved Planning Decisions

- Save coordination: implementation must add a small explicit save bundle/coordinator before removing topology from `WorkspaceSQLiteSnapshot`. The final type name follows nearby persistence patterns, but the boundary is fixed by S3.
- Tab color: implementation should first attempt direct durable tab shell ownership, because the SQL contract adds `tab_shell.color_hex`. A companion record is allowed only if current tab-shell atom/model shape makes the direct field materially worse; either way the owner remains durable tab state.
- Performance signals: execution must first reuse existing Victoria/workload signals where they cover the required surface, then add a focused instrumentation sub-slice only for uncovered surfaces. Raw-path scrub proof is mandatory for any new telemetry.

## Handoff Prompt

```text
Use implementation-execute-plan on:

/Users/shravansunder/Documents/dev/project-dev/agent-studio.repository-sql-domain/docs/plans/2026-06-26-repository-topology-sql-domain.md

Execute against the source spec:
/Users/shravansunder/Documents/dev/project-dev/agent-studio.repository-sql-domain/docs/specs/2026-06-26-repository-topology-sql-domain.md

Stay in the isolated worktree:
/Users/shravansunder/Documents/dev/project-dev/agent-studio.repository-sql-domain

Implement the vertical slices in order. Do not start in the main worktree. Keep
the SQL migration first, then atom rename/state, then the explicit save
bundle/coordinator, then color/tag reader cutover, then reader/IPC/filesystem
and performance proof. Run the focused proof gates for each slice and record
performance artifacts under:
tmp/plan-workflows/2026-06-26-repository-topology-sql-domain/proof/
```
