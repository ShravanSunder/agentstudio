# Sidebar Layout, Grouping, and Off-Main Search Implementation Plan

Status: plan-review re-check complete; ready for implementation-execute-plan
Date: 2026-06-20
Goal id: `2026-07-04-sidebar-ipc-command-proof`
Spec: `docs/superpowers/specs/2026-06-20-sidebar-layout-grouping-offmain-search.md`
Goal details: `tmp/workflow-state/2026-07-04-sidebar-ipc-command-proof/details.md`

## Outcome

Deliver the repo/inbox sidebar cleanup to a PR-ready state without merging:

- repo sidebar uses a shared slot-style header layout container
- repo header exposes second-row sort and group controls
- repo grouping modes are exactly `Repo`, `Pane`, and `Tab`
- Pane/Tab modes include a mode-scoped `Inactive` group
- Pane/Tab duplicate attachment rows are identifiable
- repos can be marked favorite through `repo.is_favorite`
- repo/worktree notes, repo tags, and tab shell color
  metadata are added in SQLite without new UX in this slice
- repo/worktree manual color UX is removed; existing automatic generated repo
  colors may remain
- inbox search/list projection moves expensive work off MainActor
- command-shaped sidebar writes use typed `AppCommandSpec` definitions and
  generic `command.execute`, not bespoke sidebar write IPC routes
- metrics, docs, lint, and proof paths reflect the new architecture
- GUI proof does not interrupt the user's desktop, or is explicitly blocked pending approval

## Source Coverage

- Spec read: `docs/superpowers/specs/2026-06-20-sidebar-layout-grouping-offmain-search.md`; reread current expanded contract before plan review.
- Plan read: this file; reread current expanded contract before plan review.
- Goal details read: `tmp/workflow-state/2026-07-04-sidebar-ipc-command-proof/details.md`; current goal state must be reread by plan-review-swarm.
- Transition log read: `tmp/workflow-state/2026-07-04-sidebar-ipc-command-proof/events.jsonl`; current goal state must be reread by plan-review-swarm.
- Repo evidence inspected:
  - `AGENTS.md`
  - `docs/architecture/directory_structure.md`
  - `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
  - `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjection.swift`
  - `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerRowIndex.swift`
  - `Sources/AgentStudio/Core/Models/RepoPresentation.swift`
  - `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceLookupDerived.swift`
  - `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
  - `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListModel.swift`
  - `Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Rules/SharedComponentsStatelessRule.swift`
  - `.mise.toml`

## Non-Goals

- Do not merge the PR.
- Do not add `Source` or `Flat` repo grouping modes.
- Do not move `InboxSidebarHeader` into `SharedComponents`.
- Do not merge repo and inbox feature state.
- Do not unify command-bar search with sidebar search.
- Do not use unsafe no-auth IPC as a sidebar proof path.
- Do not run foreground GUI proof without explicit user approval.
- Do not add or keep bespoke typed sidebar write IPC as the product mutation
  path for grouping, sort, favorite visibility, favorite toggle, or surface
  switching.
- Do not replace command-owned typed arguments with stringly typed adapter
  switches after public IPC DTO validation.
- Do not add arbitrary/custom sort axes beyond the explicit repo title
  ascending/descending order and explicit favorite visibility filter planned
  here.
- Do not treat Favorite as a fourth repo grouping mode.
- Do not add UX for repo tags in this slice.
- Do not add worktree or pane tags.
- Do not add UX for tab shell colors in this slice.
- Do not add pane color metadata.
- Do not keep user-editable repo or worktree color controls.
- Do not add `repo.color_hex`, `worktree.color_hex`, or `pane.color_hex` in
  this slice.
- Do not migrate `sidebar.checkoutColors` in this slice.

## Requirements / Proof Matrix

| Requirement / claim | Owning task | Proof owner | Proof gate | Proof layer | Stale-proof guard | Red/green |
| --- | --- | --- | --- | --- | --- | --- |
| Shared layout container, not inbox header reuse | T2 | implementation + parent | SharedComponents presentation tests and import checks | unit + architecture | current diff, `mise run lint` | Required |
| SharedComponents may receive explicit observable view models but no atoms/global stores | T1 | implementation + parent | architecture lint fixtures/tests and `mise run lint` | architecture | current lint source and fixtures | Required |
| Repo toolbar exposes second-row sort and group controls | T2, T4 | implementation + parent | mounted repo toolbar tests | unit/UI | current view diff | Required |
| Repo modes are exactly Repo/Pane/Tab | T3, T4 | implementation + parent | model tests and source grep/test for labels | unit | current grouping enum/test fixtures | Required |
| Repo mode is one group per repo identity | T3 | implementation + parent | model tests covering current source-family multi-repo case | unit | current RepoPresentation behavior tested against new projection | Required |
| Pane mode de-dupes within one pane tree/group but allows cross-group attachments | T3 | implementation + parent | RepoExplorer grouping tests | unit | fixtures with multiple pane attachments | Required |
| Tab mode allows duplicate attachment rows with secondary placement context | T3, T5 | implementation + parent | grouping/read-model tests and row presentation tests | unit/UI | fixtures with duplicate attachments in one tab | Required |
| Pane/Tab Inactive means no active-residency tab-owned pane anywhere in tab ownership graph | T3 | implementation + parent | model tests including non-current arrangement coverage | unit | fixtures include backgrounded, tabless, non-current arrangement panes | Required |
| Pane/Tab group headers use stable ids and ordinalized display labels | T3 | implementation + parent | group key/label tests across duplicate titles and renames | unit | pane/tab id fixtures | Required |
| Mode-scoped collapse memory prevents `pane:inactive` and `tab:inactive` collisions | T3 | implementation + parent | state/model tests and persistence tests if storage changes | unit/integration | persisted key round trip | Required |
| Repo favorites persist on `repo.is_favorite` keyed by repo id | T2A | implementation + parent | core SQLite migration/repository tests and restore tests | integration | migrated core DB fixture | Required |
| Repo/worktree notes, repo tags, and tab shell colors exist as SQLite metadata | T2A | implementation + parent | core migration/schema tests | integration | migrated core DB fixture | Required |
| Favorite toggle is available on main-worktree rows without adding a Favorite grouping mode | T2A, T4, T5 | implementation + parent | toolbar/row presentation tests and grouping enum tests | unit/UI | current view diff | Required |
| Favorite toggling does not reorder the normal all-repos Repo/Pane/Tab views | T2A, T3 | implementation + parent | RepoExplorer projection tests across all grouping modes | unit | fixtures with mixed favorite ids | Required |
| Command-shaped sidebar writes use typed command specs and generic `command.execute` | T4, T8 | implementation + parent | command catalog, command.execute, and cleanup tests | unit/integration | current IPC registry and adapter diff | Required |
| Sidebar command execution preserves compile-time typed args after IPC DTO validation | T4, T8 | implementation + parent | command argument tests and architecture check forbidding feature-specific IPC adapter switches | unit + architecture | current command execution code inspected | Required |
| Repo sort order and favorite visibility are command-backed and workspace-persisted | T4, T8 | implementation + parent | command catalog, command.execute, persistence, and projection tests | unit/integration | current repo sidebar preference source | Required |
| Heavy repo and inbox sidebar search/group/sort/projection work stays off MainActor except compact snapshot/apply | T3, T6, T7 | implementation + parent | actor/isolation tests, projection tests, metrics, and worker-entrypoint inspection | unit + architecture + performance | current worker entrypoints and Victoria metrics | Required |
| Inbox search/list projection runs off MainActor with allowed Swift 6.4 boundary | T6 | implementation + parent | async projection tests and architecture/lint checks | unit + architecture | current worker entrypoint inspected | Required |
| Inbox search/list projection preserves search, grouping, collapsed counts, visible ids, and navigation | T6 | implementation + parent | InboxNotificationListModel projection tests, cancellation tests, atomic-apply tests | unit | existing fixtures plus async generation fixture | Required |
| Sidebar metrics are controlled vocabulary and scrubbed | T7 | implementation + parent | metrics unit tests/verifier updates | unit + integration | OTLP allowlist and verifier current diff | Required |
| Before/after performance evidence exists for inbox search/list path | T0, T7 | implementation + parent | `mise run verify-sidebar-performance-workload -- --baseline` and `--compare` | performance | marker-scoped debug identity | Required |
| GUI proof does not interrupt desktop | T8 | implementation + parent | `mise run verify-sidebar-performance-workload -- --sidebar-proof` or explicit blocked lane | smoke/runtime | launch mode/process identity recorded | Required or blocked |
| Existing dirty code/test diff is classified before execution | Gate -1 | implementation + parent | diff ledger mapping every pre-existing code/test file to an owning slice, adoption decision, and proof | planning + source control | fresh `git status --short` and `git diff --name-status` before edits | Required |
| Stale sidebar write IPC contract is removed from executable proof paths | T8, T9, D3, D5 | implementation + parent | stale-route grep plus script/test negative assertions for `sidebar.grouping.set` and `sidebar.surface.set` as write routes | docs + integration + smoke | current docs, scripts, script tests, IPC registry, and workload driver | Required |
| Docs, spec, plan, lint, and code agree | T1, T9 | implementation + parent | docs grep, lint, and plan-review disposition | docs + architecture | current docs/lint diff | Required |
| PR ready, not merged | T10 | parent + PR wrapup | PR checks, review threads, mergeability, implementation review disposition | PR/release gate | fresh GitHub state | Required |

## Task Sequence

### Gate -1. Current Diff Reconciliation

Purpose: prevent the executor from treating existing WIP as a clean baseline or
silently overwriting work that already belongs to this goal.

Required preflight before any product edit:

1. Run:
   - `git status --short --branch`
   - `git diff --name-status`
   - focused `git diff -- <path>` reads for every pre-existing code/test file
2. Classify each dirty file as:
   - adopted into a named plan slice,
   - unrelated and ignored,
   - stale/superseded and needing explicit user direction before overwrite, or
   - proof artifact/docs-only state.
3. For adopted code/test files, record:
   - owning slice,
   - source requirement,
   - proof gate that will validate the existing change,
   - whether red/green proof is still available or must be reconstructed with
     a targeted failing test first.
4. Do not capture performance baseline or claim pre-change behavior until this
   ledger exists.

Current known dirty code/test files that must be classified:

- `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjection.swift`
- `Tests/AgentStudioTests/App/Windows/MainSplitViewControllerSidebarStateTests.swift`
- `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerReadModelTests.swift`

Proof gates:

- `tmp/workflow-state/2026-07-04-sidebar-ipc-command-proof/diff-reconciliation.md`
  or equivalent implementation handoff ledger.
- Parent verification that no dirty code/test file is overwritten without an
  owning slice and proof decision.

Split/replan trigger:

- If a dirty file changes behavior outside this spec, stop implementation and
  ask for user direction before editing that file.

### T0. Sidebar Proof Harness Bootstrap and Baseline

Purpose: create the measurement/proof surface without changing sidebar behavior, then capture a comparable baseline before product implementation.

Write surfaces:

- `.mise.toml`
- `scripts/verify-sidebar-performance-workload.sh`
- `scripts/run-debug-observability.sh`
- `scripts/verify-debug-observability.sh`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioPerformanceTraceRecorder.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetrics.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+StartupDiagnostics.swift`
- diagnostics/script tests

Steps:

1. Add a sidebar performance workload task and script with exact public commands:
   - `mise run verify-sidebar-performance-workload -- --prepare-only`
   - `mise run verify-sidebar-performance-workload -- --baseline`
   - `mise run verify-sidebar-performance-workload -- --compare`
   - `mise run verify-sidebar-performance-workload -- --sidebar-proof`
2. Add a startup-diagnostic driver for sidebar proof before adding any new sidebar IPC surface.
3. Verify and extend the existing inbox/repo projection worker and timing
   paths instead of reinventing them. Current code already has request-build,
   worker, row-index, and apply phases; this task closes missing taxonomy,
   comparator, and command-driver gaps.
4. Extend the OTLP metrics dimensions and verifier selectors for the sidebar taxonomy:
   - `surface`: `inbox` or `repo`
   - `phase`: `request_build_mainactor`, `projection_worker`,
     `mainactor_apply`, `row_index`, or `startup_diagnostic`
   - `query_state`: `empty` or `non_empty`
   - `group_mode`: `repo`, `pane`, `tab`, or `not_applicable`
   - `sort_order`: `ascending`, `descending`, or `not_applicable`
   - `visibility_mode`: `all`, `favorites_only`, or `not_applicable`
5. Keep all taxonomy fields controlled vocabulary. Do not export query strings, repo names, worktree names, pane/tab labels, paths, notification text, or raw ids.
6. Record debug proof launch mode and IPC auth mode in the debug state/verifier output.
7. Make all sidebar proof lanes hard-fail if `AGENTSTUDIO_IPC_UNSAFE_NO_AUTH` is present.
8. Run focused existing tests that cover current repo/inbox sidebar model behavior.
9. Run `mise run lint` before product behavior changes to expose current lint drift.
10. Start shared observability only when collecting runtime proof.
11. Capture the pre-change inbox baseline only after Gate -1 classifies the
    existing diff and after the verifier can identify whether it is using the
    final command-driven sidebar control path or an explicitly limited
    legacy/current-state path.
12. Use a current-state/legacy driver only for baseline measurements that are
    explicitly labeled as such. Final sidebar grouping/surface proof must use
    generic `command.execute` from T8/D3.
13. Capture the pre-change inbox baseline with:
    - `mise run observability:up`
    - `mise run verify-sidebar-performance-workload -- --baseline`

Proof gates:

- script/unit tests for the new verifier contract
- diagnostics unit tests for the sidebar taxonomy and scrubbed attributes
- `mise run lint`
- focused Swift tests for current sidebar models
- `mise run observability:up`
- `mise run verify-sidebar-performance-workload -- --prepare-only`
- `mise run verify-sidebar-performance-workload -- --baseline`

Split/replan trigger:

- If the bootstrap verifier cannot collect baseline data without foreground GUI activation, stop before product behavior changes and resolve T8.
- If adding the verifier requires programmatic control for a command-shaped
  sidebar action, use generic `command.execute` with a headless
  `AppCommandSpec`. Add a new IPC method only for non-command behavior, route
  it through `Sources/AgentStudio/App/IPCComposition/...` and the public IPC
  contract surface, and reuse escrow consume/replay-reject proof.
- If baseline collection would exercise `sidebar.grouping.set` or
  `sidebar.surface.set` as the final write path, label it as legacy/current
  state only and do not treat it as final sidebar proof.

### T1. SharedComponents Docs and Architecture Lint Contract

Purpose: align the durable docs and enforced lint rule with the new boundary:
observable composition is allowed; atom/global-state access is not.

Likely write surfaces:

- `AGENTS.md`
- `docs/architecture/directory_structure.md`
- `Tools/AgentStudioArchitectureLint/Sources/AgentStudioArchitectureLintCore/Rules/SharedComponentsStatelessRule.swift`
- `Tools/AgentStudioArchitectureLint/Tests/AgentStudioArchitectureLintTests/...`

Steps:

1. Rename or retune the shared-component lint rule messaging from blanket statelessness to no atom/global-store access.
2. Continue denying `@Atom`, `atom(...)`, `AtomReader`, `AtomScope`, `withTestAtomRegistry`, and environment/global-store access in `SharedComponents`.
3. Allow explicitly passed observable view models only when the observable contract type is declared in `SharedComponents/` or `Infrastructure/` and models reusable UI interaction state.
4. Keep feature-owned domain models, atom wrappers, and global-store facades forbidden as `SharedComponents` initializer inputs.
5. Keep `@StateObject` and `@EnvironmentObject` forbidden in `SharedComponents`.
6. Allow `@ObservedObject` or Swift `@Observable` only for explicit initializer contracts that satisfy step 3.
7. Allow `@State` only for local ephemeral UI state, not product or persistence state.
8. Update lint fixtures for allowed observable input and denied atom/global-state access.

Proof gates:

- Architecture lint unit tests for the rule.
- `mise run lint`.

Split/replan trigger:

- If the linter cannot distinguish explicit observable inputs from global observation with SwiftSyntax alone, split into a smaller rule update plus an architecture test that proves the concrete shared sidebar component stays clean.

### T2. Shared Sidebar Header Layout Container

Purpose: create a layout primitive shared by repo and inbox without moving inbox semantics into `SharedComponents`.

Likely write surfaces:

- `Sources/AgentStudio/SharedComponents/SidebarHeaderLayout.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxSidebarComponents.swift`
- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- `Tests/AgentStudioTests/SharedComponents/...`
- `Tests/AgentStudioTests/Architecture/SidebarSurfaceConvergenceTests.swift`

Steps:

1. Add a slot-style shared layout container with search row, toolbar/action row, and optional status/filter row slots.
2. Compose `InboxSidebarHeader` through the layout container while keeping inbox menu state, tooltips, local actions, and callbacks feature-owned.
3. Compose `RepoExplorerView` header through the same layout container.
4. Preserve `SidebarSearchField` as the shared search field.
5. Add presentation tests that prove repo and inbox use the shared layout shell without sharing semantic state.

Proof gates:

- SharedComponents presentation tests.
- Sidebar convergence architecture tests.
- `mise run lint`.

### T2A. Core SQLite Repo/Worktree/Tab/Pane Metadata Migration

Purpose: add the schema-backed metadata contract before row rendering or
grouping consumes it. Repo/worktree manual color UX is removed; current
automatic generated repo colors may remain.

Likely write surfaces:

- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreMigrations.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+Topology.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+TopologyMutation.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+PaneGraph.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+PaneGraphMutation.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+TabGraph.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceCoreRepository+TabGraphMutation.swift`
- `Sources/AgentStudio/Core/Models/Repo.swift`
- worktree and tab model/read-model files as needed for stored metadata
- `Sources/AgentStudio/Core/State/SQLite/WorkspaceSQLiteDatastore.swift`
- `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerSnapshot.swift`
- `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjection.swift`
- `Sources/AgentStudio/Core/Models/RepoPresentation.swift`
- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- core SQLite migration tests and RepoExplorer projection tests

Steps:

1. Add a core SQLite migration that extends `repo` with:
   - `is_favorite INTEGER NOT NULL DEFAULT 0`
   - `note TEXT`
2. Extend `worktree` with:
   - `note TEXT`
3. Extend `tab_shell` with:
   - `color_hex TEXT`
4. Add core SQLite tag table:
   - `repo_tag(repo_id TEXT NOT NULL REFERENCES repo(id) ON DELETE CASCADE, tag TEXT NOT NULL, PRIMARY KEY(repo_id, tag))`
5. Keep the repo tag table schema-only in this slice. Do not add tag UI,
   grouping, filtering, metrics, or command surfaces.
6. Do not add worktree or pane tag tables.
7. Keep `tab_shell.color_hex` schema-only in this slice. Do not change current
   UI behavior based on that field.
8. Do not add `repo.color_hex`, `worktree.color_hex`, or `pane.color_hex`.
9. Do not migrate `sidebar.checkoutColors`; manual repo/worktree color
   overrides should not remain a repo UX surface in this slice.
10. Preserve the repo/worktree distinction: one repo can have multiple
    worktrees/checkouts. This slice adds favorite, notes, and repo tags only.
11. Add favorite toggle/read APIs through the repo topology/core SQLite path.
12. Add repo metadata values to the Sendable repo projection snapshot.
13. Keep normal resolved repo/worktree ordering controlled by the selected
    title sort order. Favorite state must not reorder rows in the default
    `all` visibility mode.
14. Apply `repo.is_favorite` only when the explicit favorite visibility filter
    is `favorites_only`.
15. Keep grouping modes exactly Repo, Pane, and Tab. Favorite is a repo field
    and visibility filter, not a grouping mode or implicit sort partition.
16. Add scrubbed metric/test vocabulary if favorite state is emitted in sidebar
    telemetry: `favorite`, `not_favorite`, or `not_applicable` only.

Proof gates:

- Core SQLite migration test for the new columns and repo tag table.
- Core repository/store round-trip tests for favorite, unfavorite, repo note,
  worktree note, tab color, and repo tags.
- RepoExplorer state tests for favorite toggle/hydrate/reset if a feature state
  facade remains necessary after moving favorite onto repo metadata.
- Projection tests proving favorite toggles do not reorder Repo, Pane, or Tab
  modes while visibility is `all`.
- Projection tests proving `favorites_only` hides non-favorite repos without
  changing the selected title sort order among visible favorites.
- Tests proving favorite state is repo-scoped and does not create per-pane,
  per-tab, or per-attachment favorite rows.
- Architecture proof that `SharedComponents` only receives favorite values and
  callbacks and does not access atoms/stores directly.

Split/replan trigger:

- If core metadata migration touches more persistence layers than expected,
  split this into a standalone migration/store PR before UI wiring.
- If checkout color storage becomes necessary for this branch, stop and return
  to design. Do not silently add repo/worktree color columns.

### T3. Repo Sidebar Grouping Read Models

Purpose: define Repo/Pane/Tab grouping as model-owned projection, not row-view logic.

Likely write surfaces:

- `Sources/AgentStudio/Features/RepoExplorer/Models/...`
- `Sources/AgentStudio/Features/RepoExplorer/State/MainActor/Atoms/RepoExplorerSidebarState.swift`
- `Sources/AgentStudio/Features/RepoExplorer/State/MainActor/Persistence/RepoExplorerSidebarStore.swift`
- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/SidebarCacheState.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/SidebarCacheStore.swift`
- `Sources/AgentStudio/AtomRegistry.swift`
- local UX migration/storage files for RepoExplorer grouping-mode persistence if needed
- `Tests/AgentStudioTests/Features/RepoExplorer/...`
- `Tests/AgentStudioTests/Core/State/...` only for existing sidebar expanded-group persistence

Steps:

1. Add a repo sidebar grouping mode model with exactly `repo`, `pane`, and `tab`.
2. Persist the selected repo grouping mode per workspace in a RepoExplorer-owned feature atom/store, not `WorkspaceSidebarState` or `UIStateStore`.
3. Build a Sendable/value snapshot for repo grouping inputs:
   - repos and worktrees
   - repo enrichment needed for loading/resolved decisions
   - current grouping mode
   - selected title sort order
   - selected favorite visibility mode
   - repo metadata values from T2A, including `isFavorite`
   - debounced query
   - mode-scoped expanded group ids
   - worktree occupancy from `WorkspaceLookupDerived.paneLocationsByWorktreeId`
4. Implement Repo mode as one group per repo id.
5. Implement Pane mode from active-residency tab-owned pane locations:
   - no duplicate worktree rows within one pane group
   - cross-pane-group duplicates allowed
   - stable group keys use `pane:<pane-id>`
   - display labels use ordinalized fallback labels such as `Pane N` when names are absent or ambiguous
   - `pane:inactive` last and hidden only when empty
6. Implement Tab mode from active-residency tab-owned pane locations:
   - duplicate worktree rows allowed for multiple pane attachments within one tab
   - duplicate rows include attachment-aware stable row ids in the read model
   - duplicate rows include secondary placement context
   - stable group keys use `tab:<tab-id>`
   - display labels use ordinalized fallback labels such as `Tab N` when names are absent or ambiguous
   - `tab:inactive` last and hidden only when empty
7. Scope persisted expansion/collapse keys by mode through the existing `SidebarCacheState`/`SidebarCacheStore` owner, including `pane:inactive` and `tab:inactive`.
8. Move row-entry and lookup identity expansion into the read model so same-group duplicate attachment rows can coexist.
9. Apply favorite visibility filtering only when the selected visibility mode
   is `favorites_only`; in the default `all` mode, favorite toggles must not
   reorder rows.
10. Run heavy repo grouping, filtering, sorting, row-index, and metric-prep work
    through a Sendable off-main worker path. Keep MainActor work limited to atom
    reads, minimal snapshot construction, generation checks, and compact apply.
11. Do not introduce repo/worktree color metadata into the projection path.
12. Keep loading repo behavior explicit in all modes.

Proof gates:

- RepoExplorer model tests for each grouping mode.
- Tests for source-family multi-repo input proving Repo mode is not source grouping.
- Tests for backgrounded, tabless, non-current-arrangement, and active-residency tab-owned panes.
- Tests proving duplicate pane/tab titles do not collide and group keys remain stable across title changes.
- Tests proving two rows with the same `worktreeId` can coexist inside one tab group with distinct stable ids.
- Tests proving favorite toggles do not reorder Repo, Pane, or Tab groups in
  default `all` visibility mode.
- Tests proving `favorites_only` hides non-favorite repos without adding a
  Favorite group.
- Executor/isolation proof that heavy repo grouping/filter/sort/row-index work
  executes through the worker path and only compact snapshot/apply work remains
  on MainActor.
- Tests for mode-scoped collapse key persistence.
- Architecture proof that grouping-mode state and persistence live under `Features/RepoExplorer/...`; collapse-memory changes remain limited to `SidebarCacheState`/`SidebarCacheStore`.

Split/replan trigger:

- If persistence requires a schema migration broader than sidebar memory, split persistence into its own implementation slice and prove migration separately.

### T4. Repo Header Toolbar Controls

Purpose: expose the requested repo second-row toolbar with sort, group, and
favorite-visibility filter controls.

Likely write surfaces:

- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- new repo sidebar toolbar component/model files if needed
- `Sources/AgentStudio/Core/Actions/LocalActionSpec.swift` or command specs if actions need typed tooltip sources
- `Tests/AgentStudioTests/Features/RepoExplorer/...`

Steps:

1. Add a repo toolbar row under the search row using the shared layout container.
2. Add a group control exposing Repo, Pane, and Tab.
3. Add a sort control matching the inbox-style toolbar affordance. It toggles
   the selected repo title sort order between ascending and descending.
4. Add a filter control for repo visibility with default `all` and explicit
   `favorites_only`. Favoriting a repo does not reorder the default all-repos
   view.
5. Persist selected repo sort order and repo visibility mode with the
   RepoExplorer sidebar preference state so relaunch restores the user's
   choices.
6. Add command specs for repo sort order and repo visibility mode, with typed
   command-owned arguments and generic `command.execute` exposure.
7. Use typed tooltip render values for dense icon controls.
8. Ensure toolbar controls do not import or reuse inbox feature types.

Proof gates:

- Mounted repo toolbar presentation tests for the group control, selected group
  mode, sort affordance, favorite-visibility filter affordance, favorite
  affordance, and typed tooltip values.
- Tests proving ascending/descending sort order and favorite visibility
  filtering are applied by the projection model, not row-view code.
- Command catalog and command.execute tests for repo sort order and repo
  visibility mode.
- Tooltip/source architecture lint.
- Focus/keyboard smoke tests where existing harness supports them.

Split/replan trigger:

- If additional sort modes are required after review, stop and write a new sort
  semantics spec before adding more sort state.

### T5. Repo Row Rendering and Placement Context

Purpose: render new grouping output without visually ambiguous duplicate rows.

Likely write surfaces:

- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerWorktreeRow.swift`
- `Sources/AgentStudio/Features/RepoExplorer/Models/...`
- `Tests/AgentStudioTests/Features/RepoExplorer/...`

Steps:

1. Consume row entries whose identity already includes group id and attachment id when needed.
2. Render the repo-scoped favorite control only on rows whose worktree has
   `isMainWorktree == true`, in every grouping mode. Linked worktree rows must
   expose neither the inline bookmark nor the favorite context-menu action.
   Route visible toggles through feature-owned callbacks.
3. Add secondary placement text for Pane/Tab attachment rows.
4. Follow the inbox pattern: primary worktree/repo text plus secondary source/placement context.
5. Preserve branch status, PR count, and existing row affordances except manual
   repo/worktree color controls. Do not add repo/worktree color metadata in
   this slice.
6. Keep row rendering fed by the prepared row index rather than walking groups in the view body.

Proof gates:

- Row-index tests for stable ids from T3.
- Row presentation tests for duplicate attachments.
- Row presentation tests proving the favorite control is available for main
  worktrees and absent for linked worktrees.
- Existing RepoExplorer row tests.

### T6. Inbox Off-Main Projection

Purpose: move expensive inbox search/list projection off MainActor while preserving all list semantics.

Likely write surfaces:

- `Sources/AgentStudio/Features/InboxNotification/Models/...`
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
- `Tests/AgentStudioTests/Features/InboxNotification/Models/...`
- architecture tests for worker isolation

Steps:

1. Extract a Sendable inbox projection snapshot and result.
2. Move filtering, grouping, sorting, collapsed rollups, visible ids, and navigation model construction behind an allowed off-main boundary:
   - dedicated actor, or
   - `@concurrent nonisolated` pure/static helper.
3. Keep MainActor responsible for atom reads, snapshot creation, generation increment, stale-result discard, and compact result application.
4. Own exactly one projection task from the sidebar view/model boundary:
   - cancel-before-replace on every refresh request
   - cancel on disappear/teardown
   - no post-unmount apply
5. Replace synchronous `refreshListModel()` rebuilds with a generation-checked async projection flow.
6. Apply sections, `visibleNotificationIds`, collapsed counts, and navigation targets from one result object in one MainActor step.
7. Preserve transient inbox search state.
8. Avoid timers and forbidden sleep APIs.
9. Instrument worker duration and MainActor apply duration using the T0 taxonomy.

Proof gates:

- Inbox model tests for existing search/grouping/collapse/navigation semantics.
- New async generation discard tests.
- Superseded-search cancellation tests.
- Teardown cancellation tests proving no post-unmount apply.
- Atomic-result tests proving sections, visible ids, collapsed counts, and navigation targets come from the same generation.
- Executor/isolation proof that expensive projection work executes through the worker path and only compact result application returns to MainActor.
- Architecture/lint test proving worker boundary is not MainActor-isolated and only Sendable snapshot/result crosses.
- `mise run lint`.

Split/replan trigger:

- If `InboxNotification` or related display models are not Sendable, split Sendable contract cleanup into a prior focused slice.

### T7. Metrics and Performance Proof

Purpose: prove before/after performance and keep telemetry scrubbed.

Likely write surfaces:

- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioPerformanceTraceRecorder.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetrics.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`
- `scripts/verify-git-refresh-performance-workload.sh` or a sidebar-specific verifier
- tests under `Tests/AgentStudioTests/Scripts/` and diagnostics tests

Steps:

1. Build on the T0 sidebar verifier and metrics taxonomy; do not add a second proof path.
2. Track surface, phase, query state bucket, group mode, sort order,
   visibility mode, input counts, stale discard count, cancellation count,
   request-build MainActor duration, row-index duration, MainActor apply
   duration, and total worker duration.
3. Do not export query strings, repo/worktree/branch names, pane/tab labels, group labels, notification text/search text, raw paths, tokens, prompts, terminal buffers, or tool output.
4. Add allowlist/verifier coverage for new fields.
5. Define baseline vs post-change comparator rules in
   `scripts/verify-sidebar-performance-workload.sh` using the shared hard-gate
   policy: fail if compare exceeds `max(baseline * multiplier, baseline +
   absolute allowance)`, with multiplier and allowance declared in the
   verifier.
6. Fail on missing events, missing post-change measurements, unsafe attributes, foreground activation, unsafe no-auth IPC, or obvious MainActor apply regression.
7. Run post-change comparison with:
   - `mise run observability:up`
   - `mise run verify-sidebar-performance-workload -- --compare`
8. Keep JSONL as debug aid only unless explicitly approved.

Proof gates:

- Diagnostics unit tests.
- Script/verifier tests.
- Victoria-backed marker-scoped performance proof with `mise run verify-sidebar-performance-workload -- --compare`.

### T8. Non-Activating Debug / Sidebar Semantic Proof

Purpose: satisfy the user's no-screen-interruption requirement.

Likely write surfaces:

- `scripts/run-debug-observability.sh`
- `scripts/verify-debug-observability.sh`
- `scripts/verify-sidebar-performance-workload.sh`
- `Sources/AgentStudio/App/Boot/AppDelegate+StartupDiagnostics.swift`
- `Sources/AgentStudio/App/Commands/...` when command specs need headless
  execution or typed argument metadata
- `Sources/AgentStudio/App/IPCComposition/...` only for the generic
  `command.execute` bridge and authorization cleanup, not feature-specific
  sidebar write routes
- `Sources/AgentStudioAppIPC/...` only if the generic command-execution auth
  contract changes
- `docs/architecture/observability_and_traceability.md` if proof contract changes
- IPC docs/tests if changing the generic command IPC contract

Steps:

1. Prefer a non-activating debug launch/proof mode for sidebar verification.
2. Record launch mode and activation mode in the debug state file, and make the sidebar verifier reject foreground activation unless the user explicitly approves it for that run.
3. Record IPC auth mode in the debug state file, and make all sidebar proof lanes reject `AGENTSTUDIO_IPC_UNSAFE_NO_AUTH`.
4. Drive command-shaped sidebar behavior through `command.execute` and real
   headless `AppCommandSpec` definitions.
5. Ensure `command.execute` is not debugUnsafe-only: escrow-authenticated
   automation can reach generic command validation, while unsafe no-auth cannot
   execute sidebar commands.
6. Add a typed `AppCommandExecutionContext` to `AppCommandExecutionRequest` so
   command owners distinguish `.interactive` from `.headlessIPC` without
   `fromIPC` booleans or adapter-specific branches.
7. Use `.headlessIPC` for `command.execute` requests. Surface commands
   `showWorktreeSidebar` and `showInboxNotifications` become idempotent
   ensure-visible actions only for `.headlessIPC`; interactive execution keeps
   existing toggle/collapse semantics.
8. Add neutral `appCommandExecute` method-gate privilege and a narrower
   grantable `sidebarStateMutate` command-required privilege for sidebar
   grouping, sort, visibility, favorite-toggle-if-added, and surface
   ensure-visible commands. Do not grant broad `.layoutMutate` for this proof
   lane.
9. Preserve type safety after IPC DTO validation by constructing command-owned
   typed execution arguments before dispatching to app/sidebar command owners.
10. For this slice, encode sidebar surface in command identity and typed
   arguments. Do not add public `IPCCommandExecuteParams.surface` or
   `IPCCommandExecuteParams.specifier` fields.
11. Remove typed sidebar write/set IPC methods as independent product mutation
    paths once equivalent command specs are headless-executable. Read/query IPC
    APIs may remain when they are not command execution.
12. Update the sidebar performance workload and IPC smoke scripts so grouping,
    sort, favorite visibility, and surface switching are driven by
    authenticated `command.execute`.
13. Add negative assertions that executable proof paths no longer call or
    require `sidebar.grouping.set` or `sidebar.surface.set` as write routes.
14. Keep any remaining `sidebar.grouping.get` / `sidebar.surface.get` references
    read/query-only, or remove them if implementation no longer needs them.
15. Use Peekaboo only for PID-targeted visual verification of the already-driven
   app result; it is not the mutation/control path and it must not replace IPC
   or Victoria proof.
16. Run sidebar semantic proof with `mise run verify-sidebar-performance-workload -- --sidebar-proof`.

Proof gates:

- script tests for non-activating mode or explicit blocked lane
- verifier tests proving unsafe no-auth IPC is rejected for sidebar proof even when inherited from the shell environment
- `mise run verify-debug-observability`
- `mise run verify-sidebar-performance-workload -- --sidebar-proof`
- command.execute IPC/auth tests, including escrow consume/replay rejection,
  invalid arguments, invalid command-owned surface shape, missing privileges,
  and wrong surface rejection
- command execution-context tests proving headless surface commands are
  ensure-visible and interactive surface commands keep toggle semantics
- authorization tests proving `appCommandExecute` alone cannot mutate sidebar
  state, `sidebarStateMutate` is required for sidebar commands, unsafe no-auth
  is rejected, and broad `.layoutMutate` is not the sidebar proof grant
- cleanup tests proving typed sidebar write/set IPC methods are not independent
  mutation paths for command-shaped actions
- script/workload tests proving grouping and surface switching no longer depend
  on `sidebar.grouping.set` or `sidebar.surface.set`

Split/replan trigger:

- If LaunchServices/AppKit cannot provide a non-activating path without product risk, stop GUI proof and mark visual verification blocked pending user approval.
- If generic `command.execute` cannot safely model a command-shaped sidebar
  mutation, stop and return to spec review rather than adding an ad hoc
  feature-specific IPC write route.

### T9. Documentation Reconciliation

Purpose: keep source-of-truth docs aligned after implementation.

Likely write surfaces:

- `AGENTS.md`
- `docs/architecture/directory_structure.md`
- `docs/guides/style_guide.md`
- `docs/architecture/observability_and_traceability.md`
- `docs/architecture/agentstudio_ipc_architecture.md`
- this plan and goal state

Steps:

1. Update docs only where implementation changes the durable contract.
2. Keep `AGENTS.md` concise; place full architecture detail in architecture docs.
3. Document any new non-activating proof command.
4. Document that command-shaped sidebar writes use generic `command.execute`;
   do not leave architecture docs recommending `sidebar.grouping.*` or
   `sidebar.surface.*` write routes for grouping/surface proof.
5. Document any new sidebar IPC method only if it is query/read-only or
   non-command behavior; explicitly document that no new command-shaped
   sidebar write IPC surface was added.
6. Document RepoExplorer-owned grouping-mode state and the existing SidebarCache-owned collapse-memory path if implementation changes those contracts.
7. Append official workflow transition events through orchestrator-goal only.

Proof gates:

- docs grep for stale `SharedComponents` stateless/global-state wording
- stale-route grep across docs/scripts/tests for executable write-route
  recommendations:
  - `sidebar.grouping.set`
  - `sidebar.surface.set`
  - `Programmatic tests use semantic sidebar.grouping`
  - `Programmatic tests use semantic sidebar.surface`
  Allowed hits must be historical/current-debt notes or read/query methods,
  not final proof instructions.
- `git diff --check`
- `mise run lint`

### T10. Review, PR, and Ready-Not-Merged Wrapup

Purpose: carry the lifecycle to PR-ready.

Steps:

1. Treat the plan-review-swarm as complete only after accepted findings are patched into this plan and recorded in the goal state.
2. Execute implementation only after accepted plan review.
3. Run required focused tests and `mise run lint`.
4. Run broader `mise run test` or split/replan if the plan identifies a bounded alternative.
5. Run runtime/performance/observability proof.
6. Run `implementation-review-swarm`.
7. Address accepted findings or explicitly reject contested ones with rationale.
8. Commit verified checkpoints when scoped files changed and repo policy permits.
9. Open or update the PR.
10. Refresh PR checks, review-thread state, and mergeability.
11. Stop at PR-ready; do not merge.

## Validation Gates by Layer

Unit:

- RepoExplorer grouping/read-model tests.
- InboxNotificationListModel and async projection tests.
- SharedComponents presentation tests.
- Architecture lint rule unit tests.

Architecture / lint:

- `mise run lint`
- architecture lint fixtures for SharedComponents atom/global-state denial and observable input allowance
- tooltip source lint for repo toolbar controls

Integration:

- persistence round trip for repo grouping mode and mode-scoped collapse memory
- metrics/verifier script tests
- IPC/auth tests for generic `command.execute` sidebar commands
- script tests proving sidebar grouping/surface proof uses `command.execute`
  and not typed sidebar write/set IPC routes

Smoke/runtime:

- `mise run observability:up`
- `mise run run-debug-observability -- --detach` only when it does not foreground GUI proof, or with explicit blocked status
- `mise run verify-debug-observability`
- `mise run verify-sidebar-performance-workload -- --sidebar-proof`

Performance:

- `mise run verify-sidebar-performance-workload -- --baseline` before T6 behavior changes
- `mise run verify-sidebar-performance-workload -- --compare` after T6 behavior changes
- post-change sidebar projection/list metrics present with scrubbed attributes

PR:

- implementation review findings disposition
- fresh PR checks
- review-thread state
- mergeability/readiness reported
- no merge without explicit authorization

## Risks and Recovery

- SharedComponents lint may not distinguish allowed explicit observable inputs from global observation. Recovery: split lint into concrete forbidden patterns first and add component-specific architecture tests.
- Core metadata migration may require a standalone persistence slice. Recovery:
  split migration/import/store work into a separately proven PR before UI
  wiring.
- Inbox projection may reveal non-Sendable model types. Recovery: split Sendable snapshot/result cleanup before off-main worker.
- Non-activating GUI proof may be blocked by AppKit/LaunchServices behavior. Recovery: use headless semantic proof and mark visual proof blocked pending user approval.
- Performance proof may lack a current sidebar semantic driver. Recovery: make
  the relevant app commands headless-executable through generic
  `command.execute`, add startup diagnostics only for non-command behavior, or
  mark the proof lane blocked before implementation claims.

## Combined Execution DAG

The base plan and the grouping-icons/IPC/performance delta are one execution
plan. The delta DAG is not standalone; its slices land at the gates below.

```text
gate -1: current diff reconciliation
  files: git status/diff ledger for existing code/test/doc changes
  proof: dirty file -> owning slice -> proof gate mapping
  |
gate 0: source and proof bootstrap
  files: spec/base plan/delta plan/goal state, verifier taxonomy
  proof: source coverage, git diff --check, prepare-only verifier tests
  |
  +-- T1 shared-component docs/lint contract
  |     proof: architecture lint fixtures and mise run lint
  |
  +-- T2 shared sidebar header layout
  |     proof: shared layout presentation/import tests
  |
  +-- T2A core SQLite metadata migration
  |     proof: migration/store round-trip tests
  |
integration gate A: shared layout + metadata + dirty-diff adoption checked
  |
T3/T4/T5 repo grouping, toolbar, favorite filter, row rendering
  includes: Repo/Panes/Tabs modes, no default favorite row jump,
            second-row sort/group/filter controls, row placement context
  proof: RepoExplorer model/read-model/presentation/persistence tests
  |
D1 pane/tab icon contract
  depends on: row/group models from T3/T5
  proof: AppEntityIcon, repo group icon, inbox group icon tests
  |
D2 command specs for repo/inbox grouping and repo sort/visibility
  depends on: command-backed state from T4 and final grouping vocabulary
  proof: AppCommand catalog, command-bar scope, command.list projection tests
  |
T8/D3 authenticated generic command.execute boundary
  depends on: D2 command vocabulary
  includes: appCommandExecute, sidebarStateMutate, typed args,
            AppCommandExecutionContext, headless surface ensure-visible,
            stale sidebar write-route cleanup
  proof: IPC contract/auth/adapter/smoke tests, stale-route negative tests
  |
D4/T7 metrics taxonomy and off-main proof instrumentation
  depends on: stable repo/inbox projection touchpoints and D1 view edits
  proof: OTLP allowlist, metric survival, row_index taxonomy tests
  |
T6 inbox off-main projection
  can overlap with D4 only after worker/result contracts are stable
  proof: async generation/cancellation/atomic apply/isolation tests
  |
D5 runtime grouping/sort/visibility/surface workload
  depends on: T8/D3 command.execute and D4/T7 metrics
  proof: authenticated background Victoria baseline/compare/sidebar-proof
  |
T9 docs reconciliation
  proof: stale-route grep, docs grep, git diff --check, mise run lint
  |
T10 implementation review + PR-ready-not-merged
  proof: focused tests, relevant broader test gate, runtime/performance proof,
         implementation-review-swarm, PR checks/thread/mergeability
```

Parallelization rule:

- T1, T2, and T2A may run in parallel after Gate -1 because their write
  surfaces are mostly disjoint.
- D1 must not race T3/T5 on repo row/group model interpretation.
- D4 must not race D1/T3/T5 on `RepoExplorerView` unless the executor assigns
  one owner to integrate that file.
- D3 is not independent from D2; it requires final command ids, argument
  schema, execution modes, and privilege vocabulary.
- D5 is never a substitute for D3 or D4. It proves the implemented command and
  metric paths.

## Plan Review Decisions

1. Repo sort is real in this slice: the toolbar toggles persisted title
   ascending/descending order. Favorite is a schema-backed `repo.is_favorite`
   field and explicit visibility filter, not a fourth grouping mode, arbitrary
   sort axis, or implicit favorite-first partition in the default all-repos
   view.
2. Repo grouping mode is RepoExplorer feature-owned. Do not add repo-only properties to `WorkspaceSidebarState` or `UIStateStore`.
3. Mode-scoped collapse memory stays with the existing `SidebarCacheState`/`SidebarCacheStore` owner unless implementation proves a separate migration is necessary.
4. The SharedComponents lint rule may hard-cut to a new rule id or keep the old id with updated messaging, but the enforced contract is no atoms/global stores plus explicit shared/infrastructure observable contracts only.
5. Sidebar semantic proof uses generic `command.execute` for command-shaped
   actions. Startup diagnostics are for non-command behavior. Feature-specific
   sidebar write IPC is not the target architecture.
6. Existing `sidebar.checkoutColors` is historical manual checkout-color
   storage. Do not migrate it in this slice, and remove/disable manual
   repo/worktree color UX.
7. `tab_shell.color_hex` is SQLite-only reserved metadata in this slice. It
   must not change current UI behavior until a later UX spec opts into it.
8. Do not add `repo.color_hex`, `worktree.color_hex`, or `pane.color_hex`.
9. Existing automatic generated repo colors may remain for visual distinction.
10. Plan-review cohesion finding accepted: the base and delta plans execute
    through the combined DAG above, not as independent sequences.
11. Plan-review stale-contract finding accepted: implementation must remove
    stale typed sidebar write-route recommendations from docs/scripts/tests and
    prove final sidebar grouping/surface proof uses generic `command.execute`.
12. Plan-review dirty-diff finding accepted: implementation starts with Gate -1
    diff reconciliation before edits or baseline capture.

## Next Workflow

`shravan-dev-workflow:implementation-execute-plan`

phase_result: complete
evidence: `docs/superpowers/plans/2026-06-20-sidebar-layout-grouping-offmain-search.md`; `tmp/workflow-state/2026-07-04-sidebar-ipc-command-proof/plan-review-synthesis.md`; `git diff --check`; stale-contract grep
recommended_next_workflow: `shravan-dev-workflow:implementation-execute-plan`
recommended_transition_reason: Accepted plan-review findings were patched and the combined plan re-check has no remaining accepted blocker.
