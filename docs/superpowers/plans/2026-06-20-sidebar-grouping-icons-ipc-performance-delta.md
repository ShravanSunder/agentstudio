# Sidebar Grouping Icons, Command Specs, IPC, and Performance Delta Plan

Status: reviewed and revised for implementation
Date: 2026-06-20
Base plan: `docs/superpowers/plans/2026-06-20-sidebar-layout-grouping-offmain-search.md`
Base spec: `docs/superpowers/specs/2026-06-20-sidebar-layout-grouping-offmain-search.md`

## Outcome

Add a focused delta on top of the existing sidebar plan:

- Pane group icons are blue in both repo and inbox sidebars.
- Tab group icons are violet in both repo and inbox sidebars.
- Repo-family icons keep their current generated/accent behavior.
- Switching grouping in both sidebars is command-spec discoverable.
- Programmatic proof can set repo and inbox grouping and select the active sidebar surface through a narrow authenticated IPC contract.
- Performance proof explains slow grouping switches with per-surface, per-trigger, per-phase metrics instead of only coarse projection timings.

## Source Coverage

- User request in chat: pane icons blue, tab icons violet; grouping switch performance is bad; add metrics and find out why; grouping switches in both sidebars should be command specs and open to IPC for testing.
- Base spec read fully: `docs/superpowers/specs/2026-06-20-sidebar-layout-grouping-offmain-search.md`, 498 lines.
- Base plan read fully: `docs/superpowers/plans/2026-06-20-sidebar-layout-grouping-offmain-search.md`, 651 lines.
- Plan skill read fully: `/Users/shravansunder/.codex/plugins/cache/ai-tools/shravan-dev-workflow/1.6.26/skills/plan-creation-swarm/SKILL.md`, 179 lines.
- Repo evidence inspected:
  - `Sources/AgentStudio/SharedComponents/AppEntityIcon.swift`
  - `Sources/AgentStudio/SharedComponents/SidebarSourceGroupHeader.swift`
  - `Sources/AgentStudio/SharedComponents/SidebarRepoGroupHeader.swift`
  - `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
  - `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjectionWorker.swift`
  - `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjection.swift`
  - `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerSnapshot.swift`
  - `Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift`
  - `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
  - `Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListProjectionWorker.swift`
  - `Sources/AgentStudio/App/Commands/AppCommand.swift`
  - `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
  - `Sources/AgentStudio/App/Commands/AppCommand+IPCProjection.swift`
  - `Sources/AgentStudio/App/IPCComposition/AgentStudioIPCCommandAdapter.swift`
  - `Sources/AgentStudioProgrammaticControl/IPCCommandContracts.swift`
  - `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioPerformanceTraceRecorder.swift`
  - `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetrics.swift`
  - `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`
  - `scripts/verify-sidebar-performance-workload.sh`
  - `docs/architecture/commands_and_shortcuts.md`
  - `docs/architecture/agentstudio_ipc_architecture.md`

Read-only lanes used:

- command/IPC boundary lane
- icon/shared component boundary lane
- metrics/proof lane

## Current Findings

### Icon Boundary

`AppEntityIcon` owns shared entity icon symbol and tint rendering. Today `.pane` and `.tab` both render with `.secondary`, while only `.coloredRepo` and `.checkout` carry custom color. Shared group headers already receive an `AppEntityIcon` value and only render it; they should stay dumb.

Repo sidebar currently chooses group icons in `RepoExplorerView.sourceGroupIcon(for:)`, which returns only `.repo` or `.coloredRepo(...)` based on repo-family coloring. It does not yet distinguish repo grouping mode when rendering pane/tab groups.

Inbox sidebar already has semantic source kinds in `InboxNotificationListSectionHeader.SourceKind`; `InboxNotificationGroupHeader.icon(for:accentColorHex:)` maps `.pane` to `.pane` and `.tab` to `.tab`, but those are still neutral icons.

### Command And IPC Boundary

`AppCommand` and `AppCommandSpec` are the command discovery source of truth. `command.list` projects the command catalog to IPC, but `command.execute` is reserved for headless semantic execution and must not present popovers, menus, sheets, or command bar UI as a side effect.

Current grouping switches are local feature mutations:

- repo toolbar popover calls `RepoExplorerSidebarPrefsAtom.setGroupingMode(...)`
- inbox sidebar calls `InboxNotificationPrefsAtom.setGrouping(...)`
- inbox command-bar rows call `InboxNotificationCommands.Actions.setGrouping(...)`

They are not currently `AppCommand` specs. Public IPC command-bar scope also has `repos` but not `inbox`, even though internal `CommandBarScope` has `.inbox`. Runtime sidebar proof must not use command-bar presentation as a proxy for switching the actual sidebar; it needs a semantic sidebar surface selector.

### Performance Boundary

Repo and inbox projection workers already use detached off-main work. The slow-feeling grouping switch can still hide in:

- MainActor request/snapshot construction
- repo `paneLocationsByWorktreeId(...)` lookup
- inbox repo presentation/fingerprint rebuild
- SwiftUI list diff/render after applying a compact result
- missing or dropped telemetry

Current telemetry gaps:

- repo row-index events emit phase `row_index_worker`, but controlled taxonomy accepts `row_index`
- inbox records `group_mode = not_applicable` even when grouping changes
- verifier baseline/compare checks only inbox worker/apply max, not repo grouping, row index, surface switches, p95, or request-build cost
- debug-token escrow and unsafe no-auth currently share the same unsafe-debug allowlist, so app-scoped sidebar IPC must first separate authenticated automation from unsafe no-auth

## Non-Goals

- Do not widen `command.execute` into generic UI automation.
- Do not make shared sidebar headers infer semantics from group ids, titles, or environment.
- Do not add repo/worktree/pane color columns or revive manual repo/worktree color UX.
- Do not move inbox header logic into `SharedComponents`.
- Do not use unsafe no-auth IPC for sidebar proof.
- Do not claim performance fixed from worker timings alone.

## Requirements / Proof Matrix

| Requirement / claim | Owning task | Proof owner | Proof gate | Proof layer | Stale-proof guard | Red/green |
| --- | --- | --- | --- | --- | --- | --- |
| Pane group icons are blue in repo and inbox sidebars | D1 | implementation + parent | AppEntityIcon, RepoExplorerView, InboxNotificationGroupHeader tests | unit/UI | current icon mapping and rendered primitive | Required |
| Tab group icons are violet in repo and inbox sidebars | D1 | implementation + parent | AppEntityIcon, RepoExplorerView, InboxNotificationGroupHeader tests | unit/UI | current icon mapping and rendered primitive | Required |
| Repo icons keep existing generated/accent behavior | D1 | implementation + parent | existing repo icon color tests plus new regression tests | unit/UI | current repo-family fixtures | Required |
| Shared group headers remain semantic-free renderers | D1 | implementation + parent | source/architecture tests | architecture | no group-id/title parsing in shared headers | Required |
| Repo sidebar grouping switches have AppCommand specs | D2 | implementation + parent | command catalog tests and command.list projection tests | unit/integration | command list equals catalog | Required |
| Inbox sidebar grouping switches have AppCommand specs | D2 | implementation + parent | command catalog tests and command.list projection tests | unit/integration | command list equals catalog | Required |
| Grouping mutation is IPC-testable without broad command.execute | D3 | implementation + parent | new semantic IPC contract tests and smoke script | integration/smoke | authenticated automation IPC, unsafe no-auth rejected | Required |
| IPC can explicitly select repo and inbox sidebar surfaces for testing | D3 | implementation + parent | `sidebar.surface.set/get` tests and smoke script | integration/smoke | semantic sidebar surface state, not command-bar presentation | Required |
| Grouping switch metrics identify slow phase and surface | D4 | implementation + parent | OTLP projection/metrics tests and Victoria proof | unit/performance | marker-scoped metrics | Required |
| Repo row-index metric survives controlled taxonomy | D4 | implementation + parent | OTLP allowlist tests | unit | `row_index`, not stale `row_index_worker` | Required |
| Runtime proof exercises repo group switching, inbox group switching, and repo/inbox surface switching | D5 | implementation + parent | `verify-sidebar-performance-workload --baseline/--compare/--sidebar-proof` | performance/smoke | authenticated, background debug identity | Required |

## Task Sequence

### D1. Shared Entity Icon Color Contract

Purpose: make pane/tab group icons fixed semantic colors while preserving shared component boundaries.

Write surfaces:

- `Sources/AgentStudio/Infrastructure/AppStyles.swift`
- `Sources/AgentStudio/SharedComponents/AppEntityIcon.swift`
- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- `Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift`
- related tests under `Tests/AgentStudioTests/SharedComponents`, `Tests/AgentStudioTests/Features/RepoExplorer`, and `Tests/AgentStudioTests/Features/InboxNotification`

Steps:

1. Add named sidebar semantic color constants for pane-group blue and tab-group violet, using the existing palette values where appropriate.
2. Extend `AppEntityIcon` with explicit semantic variants for pane group and tab group, or an equivalently narrow typed color-bearing source-group icon.
3. Keep `SidebarSourceGroupHeader` and `SidebarRepoGroupHeader` unchanged unless a test proves a rendering bug.
4. In repo sidebar, choose icon by `RepoExplorerGroupingMode`:
   - `.repo`: current `.repo` / `.coloredRepo(...)`
   - `.pane`: blue pane group icon
   - `.tab`: violet tab group icon
5. In inbox sidebar, choose icon by `InboxNotificationListSectionHeader.SourceKind`:
   - `.repo`: current repo/accent behavior
   - `.pane`: blue pane group icon
   - `.tab`: violet tab group icon
6. Do not add pane/tab color to inbox list model unless later UX needs data-driven colors.

Proof gates:

- AppEntityIcon tests for symbol and tint.
- RepoExplorerView tests proving repo/pane/tab group icon selection.
- InboxNotificationGroupHeader tests proving source-kind mapping.
- Source/architecture check that shared headers do not inspect grouping state.

### D2. AppCommand Specs for Sidebar Grouping

Purpose: make grouping switches first-class command specs for discoverability, command bar, tooltips, and IPC catalog projection.

Write surfaces:

- `Sources/AgentStudio/App/Commands/AppCommand.swift`
- `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+ShellCommandHandling.swift`
- `Sources/AgentStudio/Core/Models/InboxNotificationCommands.swift`
- `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+Inbox.swift`
- command/catalog tests

Steps:

1. Add explicit command identities for repo grouping modes:
   - set repo sidebar grouping to Repo
   - set repo sidebar grouping to Pane
   - set repo sidebar grouping to Tab
2. Add explicit command identities for inbox grouping modes:
   - set inbox grouping to Tab
   - set inbox grouping to Repo
   - set inbox grouping to Pane
   - set inbox grouping to None
3. Give each command a stable `AppCommandSpec` label, icon, help text, group, and IPC exposure metadata.
4. Route shell execution through the same prefs atoms used by the UI, not a parallel state path.
5. Update repo and inbox UI controls to derive labels/icons/tooltips from command specs where they represent command-backed state changes.
6. Keep local actions only for non-command presentation affordances such as opening a popover menu.
7. Expose grouping commands in the `>` commands scope only. Do not add grouping verbs to the `#` repo/worktree navigation scope.

Proof gates:

- AppCommand catalog tests for all new commands.
- Command-bar tests proving grouping commands appear in commands scope and repo `#` scope remains repo/worktree navigation only.
- IPC command-list projection tests proving command specs are discoverable.
- Shell command tests proving command execution mutates the correct grouping atom.

Split/replan trigger:

- If a grouping command needs parameters rather than one command per mode, do not overload generic `command.execute`; move to D3 semantic IPC and keep command specs as discoverable presentation rows.

### D3. Narrow Semantic IPC for Sidebar Grouping and Surface Selection

Purpose: let automation set grouping and select the actual sidebar surface without screen-driving buttons, presenting command-bar UI, or widening generic command execution.

Write surfaces:

- `Sources/AgentStudioProgrammaticControl/IPCSidebarContracts.swift`
- `Sources/AgentStudioAppIPC/AgentStudioIPCRegistryAuthorization.swift`
- `Sources/AgentStudioAppIPC/AgentStudioIPCMethodContribution.swift`
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCServer+AuthenticatedRouting.swift`
- `Sources/AgentStudio/App/IPCComposition/Panes/PaneSnapshotIPCContribution.swift`
- `Sources/AgentStudio/App/IPCComposition/Sidebar/SidebarIPCContribution.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+IPC.swift`
- `scripts/verify-agentstudio-ipc-phase-a-smoke.sh`
- `Tests/AgentStudioTests/Scripts/AgentStudioIPCPhaseASmokeScriptTests.swift`
- IPC tests
- IPC docs if public contract changes

Steps:

1. Keep `command.execute` fail-closed for commands that are not explicitly headless.
2. Add `sidebar.*` as a base app IPC method family or explicitly permitted app-owned contribution namespace. Do not implement `sidebar.*` as a `pane.*` contribution and do not widen contribution namespaces without tests.
3. Before exposing sidebar mutation, separate debug-token authenticated automation from unsafe no-auth:
   - debug-token escrow must create a principal path that can call the new app-scoped sidebar methods
   - unsafe no-auth must remain unable to call sidebar methods
   - do not add sidebar methods to the shared unsafe no-auth allowlist
4. Add semantic IPC methods for sidebar grouping:
   - `sidebar.grouping.set(surface: repo|inbox, mode: repo|pane|tab|none)`
   - `sidebar.grouping.get(surface: repo|inbox)`
5. Validate cross-field mode combinations:
   - repo accepts only `repo|pane|tab`
   - inbox accepts only `tab|repo|pane|none`
   - reject `repo + none` and any invalid surface/mode pair before mutating atoms
6. Add semantic IPC methods for the actual sidebar surface:
   - `sidebar.surface.set(surface: repo|inbox)`
   - `sidebar.surface.get()`
   These methods mutate/read the workspace sidebar active surface and are the only D5 surface-switch proof route.
7. Require authenticated IPC and reject unsafe no-auth sidebar proof paths.
8. Route the IPC methods through `App/IPCComposition`, ending at the existing atoms:
   - repo: `RepoExplorerSidebarPrefsAtom.setGroupingMode(...)`
   - inbox: `InboxNotificationPrefsAtom.setGrouping(...)`
   - surface: the existing workspace sidebar active-surface atom/path used by app shell surface switching
9. Do not add public `inbox` to `IPCCommandBarScope` for this proof slice unless a separate command-bar presentation requirement is accepted later.
10. Keep DTOs scrubbed: enums, booleans, counts, and stable safe identifiers only. No query text, notification text, repo names, worktree names, pane labels, tab labels, paths, prompts, tokens, or terminal buffers.
11. Update smoke scripts so runtime proof can:
   - select repo sidebar surface
   - select inbox sidebar surface
   - set repo grouping Repo -> Pane -> Tab
   - set inbox grouping Tab -> Repo -> Pane -> None

Proof gates:

- IPC contract encode/decode tests.
- Registry authorization tests.
- IPC adapter/contribution tests.
- Smoke script proving authenticated grouping set/get and surface set/get.
- `AgentStudioIPCPhaseASmokeScriptTests` assertions for new JSON-RPC method names, authenticated grouping set/get, surface set/get, and unsafe no-auth rejection.
- Negative tests for unsafe no-auth, invalid enum values, and invalid surface/mode pairs.
- Auth tests proving debug-token login can call sidebar methods, unsafe no-auth cannot, and sidebar methods are not reachable through the shared unsafe path.

Security note:

This touches IPC and must preserve command/UI split, auth, replay-reject/escrow semantics where applicable, and scrubbed DTOs.

### D4. Grouping Switch Metrics and Taxonomy Repair

Purpose: make performance evidence explain the slow grouping switch instead of only proving a worker ran.

Write surfaces:

- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioPerformanceTraceRecorder.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetrics.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`
- diagnostics tests

Steps:

1. Fix repo row-index phase taxonomy:
   - emit `row_index`
   - keep `AgentStudioOTLPPerformanceMetrics` and `AgentStudioOTLPTraceProjection` allowlists in sync
2. Add controlled dimensions:
   - `surface`: `repo`, `inbox`
   - `phase`: `request_build_mainactor`, `projection_worker`, `row_index`, `mainactor_apply`, `startup_diagnostic`
   - `trigger`: `grouping_switch`, `surface_switch`, `search`, `collapse_toggle`, `startup_diagnostic`
   - `group_mode`: repo values `repo|pane|tab`; inbox normalized values `tab|repo|pane|none`; `not_applicable` only where true
   - `query_state`: `empty|non_empty`
3. Add numeric samples:
   - input count
   - group count using canonical metric key `agentstudio.performance.sidebar.group.count`
   - visible row count
   - repo count
   - worktree count
   - pane location count for repo request build
   - expanded group count
   - request-build MainActor elapsed
   - worker elapsed
   - row-index elapsed
   - MainActor apply elapsed
   - stale discard count
   - cancellation count
4. Measure MainActor request construction before off-main worker calls for repo and inbox.
5. Keep metrics scrubbed; do not export labels, names, paths, queries, notification content, prompts, tokens, or raw ids.

Proof gates:

- OTLP trace projection tests for every new dimension/value.
- OTLP metrics tests proving row-index and grouping-switch dimensions survive.
- Projection tests proving `agentstudio.performance.sidebar.group.count` survives and stale `section.count` does not become the canonical metric.
- Negative allowlist tests proving unsafe values are dropped.
- Focused unit tests around helper functions that normalize grouping values.

### D5. Runtime Performance Proof for Group Switching

Purpose: use IPC and Victoria metrics to reproduce and quantify the slow grouping switch.

Write surfaces:

- `Sources/AgentStudio/App/Boot/AppDelegate+StartupDiagnostics.swift`
- `scripts/verify-sidebar-performance-workload.sh`
- `Tests/AgentStudioTests/Scripts/SidebarPerformanceWorkloadScriptTests.swift`

Steps:

1. Extend the sidebar performance workload to drive actual grouping and active-surface transitions through the semantic IPC methods from D3.
2. Launch debug proof with `AGENTSTUDIO_IPC_DEBUG_TOKEN_ESCROW=1`, keep one authenticated JSON-RPC session per launched app instance, prove token consumption and replay rejection, and avoid unsafe no-auth.
3. Capture baseline and compare metrics by:
   - surface
   - trigger
   - group mode
   - phase
4. Require all of these transitions in proof:
   - repo grouping: Repo -> Pane -> Tab -> Repo
   - inbox grouping: Tab -> Repo -> Pane -> None -> Tab
   - surface switch: repo -> inbox -> repo
5. Query VictoriaMetrics for p95 and max, not only max.
6. Persist baseline and compare artifacts with every required repo grouping, inbox grouping, and surface-switch metric series for p95 and max.
7. Threshold-check every required baseline/compare key; do not keep repo, surface-switch, p95, request-build, or row-index metrics as report-only rows.
8. Fail when any required metric series is missing.
9. Fail on foreground activation, unsafe no-auth IPC, missing authenticated mode, missing row-index series, missing request-build MainActor series, missing token escrow, token replay success, or manual app cleanup requirements between baseline and compare.
10. Keep JSONL as debug aid only; Victoria-backed marker-scoped proof remains the pass/fail source.

Proof gates:

- `scripts/verify-sidebar-performance-workload.sh --prepare-only`
- `scripts/verify-sidebar-performance-workload.sh --baseline`
- `scripts/verify-sidebar-performance-workload.sh --compare`
- `scripts/verify-sidebar-performance-workload.sh --sidebar-proof`
- summary file includes per-surface p95/max rows for repo grouping, inbox grouping, and surface switching
- `SidebarPerformanceWorkloadScriptTests` assertions for required baseline keys, compare thresholds, Victoria queries, and summary rows

Split/replan trigger:

- If the semantic IPC method cannot be added safely in the same slice, keep D1/D4 separate and mark D5 blocked. Do not claim grouping-switch performance proof from visual inspection or static tests.

## Execution DAG

```text
gate 0: validate repo state and reread base spec/plan
  |
  D1 icon contract
      files: AppStyles, AppEntityIcon, RepoExplorerView,
             InboxNotificationGroupHeader, presentation tests
      proof: unit/UI + architecture boundary checks
  |
  +-- lane B: D2 command specs
  |      files: AppCommand, AppCommand+Catalog, shell routing,
  |             command-bar rows/tests
  |      proof: command catalog + command.list projection tests
  |
  +-- lane C: D4 metrics taxonomy repair
  |      depends on D1 for RepoExplorerView touchpoint ordering
  |      files: RepoExplorerView, InboxNotificationSidebarView,
  |             OTLP projection/metrics, diagnostics tests
  |      proof: OTLP allowlist + metrics survival tests
  |
integration gate 1: parent resolves command ids, telemetry vocabulary, and shared RepoExplorerView edits
  |
  D3 authenticated semantic IPC grouping/surface methods
      can proceed after D2 command vocabulary is known; auth-substrate work is part of D3
      proof: IPC contract/auth/adapter/smoke tests
  |
  D5 runtime grouping/surface-switch workload
      depends on D3 IPC and D4 metrics
      proof: background authenticated Victoria-backed baseline/compare/sidebar-proof
  |
targeted validation gate
  |
full relevant validation gate
  |
implementation-review-swarm
```

Earlier parallel sketch, rejected by plan review:

```text
gate 0
  |
  +-- D1 and D4 both touched RepoExplorerView
```

That shape is intentionally not executable because it makes the icon and metrics lanes collide on the same view file.

## Write Surfaces

Likely product/code:

- `Sources/AgentStudio/Infrastructure/AppStyles.swift`
- `Sources/AgentStudio/SharedComponents/AppEntityIcon.swift`
- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- `Sources/AgentStudio/Features/InboxNotification/Components/InboxNotificationGroupHeader.swift`
- `Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift`
- `Sources/AgentStudio/App/Commands/AppCommand.swift`
- `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- `Sources/AgentStudio/App/Boot/AppDelegate+ShellCommandHandling.swift`
- `Sources/AgentStudio/App/IPCComposition/Panes/PaneSnapshotIPCContribution.swift`
- `Sources/AgentStudio/App/IPCComposition/Sidebar/SidebarIPCContribution.swift`
- `Sources/AgentStudioAppIPC/AgentStudioIPCRegistryAuthorization.swift`
- `Sources/AgentStudioAppIPC/AgentStudioIPCMethodContribution.swift`
- `Sources/AgentStudioAppIPC/AgentStudioAppIPCServer+AuthenticatedRouting.swift`
- `Sources/AgentStudioProgrammaticControl/IPCSidebarContracts.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetrics.swift`
- `Sources/AgentStudio/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjection.swift`
- `scripts/verify-sidebar-performance-workload.sh`
- `scripts/verify-agentstudio-ipc-phase-a-smoke.sh`

Likely tests:

- `Tests/AgentStudioTests/SharedComponents/SidebarSourceGroupHeaderTests.swift`
- `Tests/AgentStudioTests/Features/RepoExplorer/RepoExplorerViewTests.swift`
- `Tests/AgentStudioTests/Features/InboxNotification/Views/InboxNotificationSidebarViewTests.swift`
- `Tests/AgentStudioTests/App/AppCommandTests.swift`
- `Tests/AgentStudioTests/App/IPC/AgentStudioIPCCommandAdapterTests.swift`
- `Tests/AgentStudioAppIPCTests/AgentStudioIPCRegistryAuthorizationTests.swift`
- `Tests/AgentStudioAppIPCTests/AgentStudioAppIPCServiceContributionTests.swift`
- `Tests/AgentStudioTests/Scripts/AgentStudioIPCPhaseASmokeScriptTests.swift`
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPPerformanceMetricsTests.swift`
- `Tests/AgentStudioTests/Infrastructure/Diagnostics/AgentStudioOTLPTraceProjectionTests.swift`
- `Tests/AgentStudioTests/Scripts/SidebarPerformanceWorkloadScriptTests.swift`

Docs if contracts change:

- `docs/architecture/commands_and_shortcuts.md`
- `docs/architecture/agentstudio_ipc_architecture.md`
- `docs/architecture/observability_and_traceability.md`

## Validation Gates

Unit/UI:

- AppEntityIcon and group header icon tests.
- RepoExplorer grouping icon tests.
- Inbox group header source-kind icon tests.
- AppCommand catalog tests.
- Command-bar command tests where grouping rows are exposed.

Architecture/lint:

- `swift-format lint ...` for touched Swift files.
- `swiftlint lint --strict ...` for touched Swift files.
- `git diff --check`.
- `mise run lint` before PR-ready claim.

Integration:

- IPC contract encode/decode and auth tests.
- Command list projection tests.
- Semantic IPC set/get tests for repo and inbox grouping.
- Semantic IPC set/get tests for repo and inbox sidebar surface.
- Script prepare-only tests for sidebar workload and IPC phase-A smoke scripts.

Runtime/performance:

- `mise run observability:up`
- `scripts/verify-sidebar-performance-workload.sh --baseline`
- `scripts/verify-sidebar-performance-workload.sh --compare`
- `scripts/verify-sidebar-performance-workload.sh --sidebar-proof`

PR-ready:

- focused tests for changed surfaces
- `mise run lint`
- broader `swift test` or scoped alternative with explicit reason
- implementation-review-swarm
- PR checks and review-thread state if PR exists

## Risks and Recovery

- Generic `command.execute` pressure: if implementation starts widening it for UI-like commands, stop and move grouping to explicit semantic IPC.
- Public inbox IPC scope gap: this slice does not require adding `inbox` to `IPCCommandBarScope`; use `sidebar.surface.set/get` for actual sidebar proof.
- Auth substrate risk: debug-token escrow must not share new sidebar method access with unsafe no-auth. If that separation cannot be implemented in D3, stop and return to planning instead of allowlisting sidebar methods unsafely.
- Telemetry taxonomy drift: every new string value must be accepted in both OTLP projection and metrics parsing, or Victoria proof will silently miss it.
- Metrics may show worker is fast but UI still feels slow. In that case, inspect request-build MainActor and post-apply/render-adjacent timings before optimizing projection logic.
- If runtime proof cannot stay background/authenticated, stop and report the proof blocker. Do not replace it with screenshots or unsafe IPC.

## Decisions From Plan Review

1. Inbox grouping commands include `.none` because current sidebar and inbox command-bar rows already expose every `InboxNotificationGrouping` case.
2. Repo and inbox grouping commands belong in the `>` commands scope. The `#` scope remains repo/worktree navigation only.
3. Semantic IPC uses a `sidebar.*` family for authenticated app-scoped sidebar grouping and surface selection, with explicit auth-substrate work to keep unsafe no-auth rejected.
4. Runtime proof switches the actual sidebar through `sidebar.surface.set/get`, not through command-bar presentation.

## Recommended Next Skill

`shravan-dev-workflow:implementation-execute-plan`

The plan-review findings have been folded into this artifact. The next phase is implementation against the revised plan.
