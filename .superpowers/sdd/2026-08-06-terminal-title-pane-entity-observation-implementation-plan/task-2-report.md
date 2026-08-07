# Task 2 Implementation Report: Atomic Keyed Pane Owner And Hot-Consumer Cutover

## Commit Boundary

- Plan task: Task 2, atomic keyed pane owner and hot-consumer cutover.
- Base and working-tree parent HEAD: `474cea2c35849377d7416b3fdbba74e35e9d3616`.
- Required commit message: `refactor(state): key pane observation`.
- This report is included in the resulting Task 2 commit, so the resulting commit SHA is recorded in the external completion receipt rather than self-referenced here.
- The untracked `docs/specs/2026-08-06-terminal-title-pane-entity-observation/` directory was preserved and excluded from staging.

## Implemented Scope

- Replaced the observed pane dictionary with one canonical keyed `AtomEntityMap<UUID, PaneGraphState>` and one equality-gated keyed `AtomEntityMap<UUID, PaneStructuralFacts>`.
- Added explicit keyed, membership, cold-snapshot, and persistence-revision interfaces: `paneState(_:)`, `paneStructuralFacts(_:)`, `paneIDs`, `paneStateSnapshot()`, `paneAcceptedCommitRevision`, `pane(_:)`, and `paneSnapshot()`.
- Routed every pane graph mutation through a copy-transform-commit boundary. One `AtomMutationContext` commits canonical state, structural projection, drawer ownership indexes, and one aggregate accepted revision. Equal writes and nil-slot pruning do not advance the accepted revision.
- Kept `PaneStructuralFacts` limited to pane identity, durable CWD, content kind and Bridge eligibility, residency, drawer placement, drawer ownership, and drawer membership. It excludes title, note, content payload text, and derived repo/worktree identity.
- Added controlled product-agnostic labels to `AtomEntityMap` performance telemetry and allowlisted only the label in OTLP projection. Keys and values are not emitted.
- Changed workspace autosave observation to `paneAcceptedCommitRevision`, preserving the existing dirty-state, initial-composition, debounce, sudden-termination, flush, and failure paths.
- Reworked `TabBarAdapter` to retain global tab order/selection observation while owning one generation-guarded keyed observation and one cached `TabBarItem` per live tab. Removed tabs invalidate their observation generation before cache removal, and equal derived items suppress publication.
- Cut WorkspaceLookup, Repo Explorer, Bridge activity, Inbox surface correlation, and other hot membership consumers to keyed structural facts. Cold persistence, execution, diagnostic, and filesystem callers use explicitly named snapshots.
- Removed the compatibility `WorkspacePaneAtom.panes` and live observed `WorkspacePaneGraphAtom.paneStates` surfaces in the same compile-time cutover.

No Task 1 terminal cadence implementation, Task 3 command-presentation batching, architecture-lint rule, schema, migration, actor, store, event bus, compatibility lane, or public API was added.

## RED/GREEN Evidence

The Inbox consumer regression was mutation-checked against the old rich-pane read implementation with:

```text
mise run test:swift -- --filter 'InboxNotificationRouterObservedPaneTests.currentSurfaceObservationIsTitleInsensitive'
```

- RED: exit 1. After startup observation debt was drained and the baseline was taken, a title-only mutation changed drawer-view reads from 9 to 13.
- GREEN after restoring structural reads: exit 0; 1 test in 1 suite passed. The test now proves title-only mutation does not reread drawer views while pane membership mutation does.

Permanent consumer regressions also cover:

- WorkspaceLookup: title mutation does not invalidate; CWD mutation does.
- Repo Explorer: title mutation does not invalidate; residency mutation does.
- Bridge activity: title mutation does not invalidate; residency mutation does.
- Inbox: title mutation does not reread drawer views; membership mutation does.
- Tab bar: a pane title updates only its dependent cached item, an overridden label suppresses publication, removed tabs reject stale observation callbacks, and inserted tabs publish once.

## Fresh Verification

Focused Task 2 matrix:

```text
mise run test:swift -- --filter 'AtomEntityMapObservationTests|AgentStudioOTLPPerformanceTraceProjectionTests|WorkspacePaneBoundaryTests|WorkspaceStoreTests|TabBarAdapterTests|WorkspaceLookupDerivedTests|RepoExplorerPaneProjectionTests|RepoExplorerViewProjectionHelperTests|WorkspaceBridgePaneActivityIntegrationTests|WorkspaceBridgePaneActivityRemediationTests|InboxNotificationRouterTests|InboxNotificationRouterObservedPaneTests|CommandBarDataSourceTests|CommandBarPaneSearchTests|CommandBarTabDisplayTitleTests'
```

- Exit 0.
- 274 tests in 13 suites passed.

Serialized Bridge activity matrix:

```text
mise run test:swift -- --filter 'WebKitSerializedTests/WorkspaceBridgePaneActivity'
```

- Exit 0.
- 12 tests in 3 suites passed, including the title-insensitive observation case, nine hiding-fact cases, and two shutdown-authority cases.

Quality and build:

```text
mise run format
mise run lint
mise run build
git diff --check
```

- `mise run format`: exit 0 before the final audit.
- `mise run lint`: exit 0; swift-format OK, SwiftLint found 0 violations across 1,934 files, AgentStudio architecture lint OK, and release-script verification passed.
- `mise run build`: exit 0; debug build completed.
- `git diff --check`: exit 0 with no output.

Ambiguous-read audit:

```text
rg -n 'paneAtom\.panes|workspacePane\.panes|\.paneStates\b' Sources/AgentStudio || true
```

Only the intentional replacement DTO field remains:

```text
Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneGraphAtom.swift:217:        self.paneStates = paneStates
Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneGraphAtom.swift:337:            nextPaneStates: replacement.paneStates,
```

There is no production `paneAtom.panes`, `workspacePane.panes`, or observed live `paneStates` compatibility access.

Task 1 and Task 3 scope audit:

```text
git diff --name-only -- Sources/AgentStudio/Features/Terminal Sources/AgentStudio/Features/RepoExplorer/RepoExplorerCommandPresentation.swift Sources/AgentStudio/App/Windows/SidebarSurfaceHost.swift Tools/AgentStudioArchitectureLint Tests/AgentStudioTests/Architecture
```

- Exit 0 with no output.

## Self-Review

- Atomicity: canonical and structural keyed maps are synchronously committed on the main actor through one mutation context; the aggregate persistence revision bumps at most once per accepted operation.
- Equality and pruning: equal mutations produce no accepted change, and topology cleanup invalidates/prunes missing-key observation slots without dirtying persistence.
- Ownership: Core owns product pane state and structural projection; Infrastructure remains generic and receives only controlled labels; App owns per-tab observation and cross-feature composition.
- Observer lifetime: removed tab generations are invalidated before cached item removal, so stale one-shot callbacks cannot recreate or publish retired tab state.
- Privacy: telemetry records controlled map labels and aggregate counts only. Tests prove keys and values are absent from JSONL and dropped by OTLP projection.
- Hard cutover: all source and test callers were migrated in one pass; no compatibility property or parallel data path remains.
- Scope: no implementation from Task 1 or Task 3 is present.

## Concerns

No known Task 2 correctness or scope concerns remain after the focused, serialized, lint, build, and source-audit gates. Full application manual and observability workload proof belongs to Task 3 in the accepted plan and was not claimed by this Task 2 slice.
