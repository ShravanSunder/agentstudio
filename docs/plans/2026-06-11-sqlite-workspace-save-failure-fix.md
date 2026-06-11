# SQLite Workspace Save Failure Fix: Tab Membership Divergence

Date: 2026-06-11
Status: revised after `plan-review-swarm`; ready for `implementation-execute-plan` after preflight
Source evidence: `tmp/debug-workflows/2026-06-11-agent-studio-bug-sqlite-drawer-persistence/debug-investigation.md`

## Problem

Since the v0.0.54 SQLite cutover, workspace saves can wedge with:

```text
arrangementPaneMissingFromTab(tabId: 8C86D0C4..., arrangementId: E2D5A94A..., paneId: 019EA7A7...)
```

Confirmed facts:

1. SQLite repository validation correctly rejects tab graphs where an arrangement layout contains a pane absent from that tab's `allPaneIds`.
2. The live SQLite save path uses `WorkspacePersistenceTransformer.makeLiveSQLiteSnapshot(...)`, which currently passes raw `workspaceTabLayoutAtom.tabs` into the snapshot.
3. Hydrate-time tab repair rebuilds tab membership from arrangement layouts and drawer views, but live SQLite snapshot generation does not.
4. `WorkspaceStore` logs `error.localizedDescription` at both save catch sites, which hides enum details in normal logs.
5. `PaneCoordinator` action paths mutate multiple owners around drawer/insert flows. In particular:
   - `.closePane` for a parent pane with drawer children removes the parent from tab layout and removes drawer child panes from `paneAtom`, but does not remove child IDs from tab membership through the tab arrangement seam.
   - `.detachDrawerPane` removes drawer membership before calling `insertPane` and ignores the result.
   - Existing-pane move removes the pane from the source before calling `insertPane` and ignores the result.
6. `WorkspaceTabArrangementAtom.insertPane` has a partial-write shape because it writes through the `_modify` facade while looping. Current `Layout` behavior makes the originally claimed non-active append failure difficult to trigger deterministically, so treat this as hardening and not the sole proven root cause.

The user-facing symptom is "Workspace save failed" notifications and drawers appearing unsaved because the completed SQLite snapshot remains stale after validation rejects the live graph.

## Goal

Workspace save should not wedge on tab membership divergence. Drawer/close/detach coordinator flows should leave pane graph, tab membership, arrangement layouts, and drawer views coherent. If a live atom graph reaches the SQLite snapshot boundary with the known membership mismatch shape, the snapshot should be normalized with a structured warning signal instead of silently failing every future save.

## Non-Goals

- Performance/pipeline work: git subprocess storm, observable invalidation, `repoAndWorktree` disk I/O, Cmd+P/Cmd+R hangs.
- SQLite schema changes, migrations, quarantine, or recovery policy changes.
- Mutating or controlling the currently running production AgentStudio app.
- Recovering in-memory state already lost by a wedged production session.
- Broad save-time repair for unrelated structural corruption such as duplicate pane ownership across tabs, empty default arrangements, or missing pane rows. Repository validation must still reject those.

## Preflight

Before red/green work, make this worktree runnable:

1. Trust the repo-local mise config for this worktree.
2. Restore the missing `Frameworks/GhosttyKit.xcframework` artifact using the repo-approved setup path.
3. Confirm a focused Swift test command can start compilation before editing product code.

Known current blockers:

- `swift test --filter WorkspaceStoreDrawerTests` fails before running tests because `Frameworks/GhosttyKit.xcframework` is missing.
- `mise` reports `.mise.toml` is untrusted.

If preflight cannot be satisfied, stop with an environment blocker; do not weaken proof gates.

## Tasks

### T1 - Add bounded live snapshot tab-membership normalization

Add a pure normalization helper/result used by `WorkspacePersistenceTransformer.makeLiveSQLiteSnapshot(...)`.

Required behavior:

- Input: live `tabs`, live `validPaneIds`, and active tab id.
- Output: normalized tabs, normalized active tab id if tabs are dropped by existing invalid-pane pruning, and a structured repair report.
- Normalize only this known membership class:
  - Prune invalid pane IDs from layouts, drawer views, minimized sets, and tab membership using existing `TabArrangementRepairRules.pruningInvalidPaneIds`.
  - For each remaining tab, set `allPaneIds` to the union of arrangement layout pane IDs and drawer-view pane IDs.
  - Clean active pane, active drawer child, minimized, and zoom references only when they point outside the normalized membership/layout.
- Do not dedupe pane ownership across tabs at save time.
- Do not drop tabs solely as a broad cross-tab repair unless the existing invalid-pane pruning leaves the default layout empty.
- Do not write normalized state back into atoms from the transformer.
- Emit one warning when the result reports repairs, including counts and tab ids. Tests assert the structured result, not os_log.

Tests:

- Extend `Tests/AgentStudioTests/Core/Stores/WorkspacePersistenceTransformerTests.swift`.
- Red/green: arrangement layout pane missing from `allPaneIds` normalizes into membership.
- Red/green: membership-only pane missing from arrangements is removed from membership.
- Red/green: drawer-view pane missing from `allPaneIds` normalizes into membership.
- Unchanged graph returns an unchanged result with no repairs.
- Duplicate pane across two tabs is intentionally not repaired by this helper and remains detectable by repository validation.

### T2 - Prove and fix SQLite save/reload for normalized live state

Use the existing SQLite bridge harness instead of a private store API.

Implementation:

- `WorkspaceStore` must continue saving through `await flushAsync()`.
- A deliberately diverged live atom graph should save successfully because `makeLiveSQLiteSnapshot` normalizes the snapshot.
- The committed core tab graph should match the normalized graph.
- A second SQLite-backed `WorkspaceStore` should `restoreAsync()` from the committed snapshot and hydrate coherent tabs/drawers.

Tests:

- Extend `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreBridgeTests.swift`.
- Reuse fixture style from `makeWorkspaceSQLiteBridgeFixture`, `workspaceSQLiteDatastore(from:)`, and existing `flushAsync()` / `restoreAsync()` tests.
- Reuse `WorkspaceSQLiteSnapshotTestSupport` invalid snapshot shapes where useful for datastore-boundary assertions, but keep at least one test at the real `WorkspaceStore.flushAsync()` entry point.

### T3 - Fix coordinator close-pane drawer-child membership leak

In `PaneCoordinator+ActionExecution.swift`, when closing a layout pane that owns drawer children:

- Capture undo before any removals, preserving current behavior.
- Remove each drawer child from tab arrangement membership/drawer views through the same tab arrangement seam used by `.removeDrawerPane`, or remove parent plus children in one tab-arrangement operation.
- Remove the corresponding child panes from `paneAtom`.
- Leave no stale drawer child IDs in `tab.allPaneIds`, arrangement layouts, drawer views, or local cursor state.

Tests:

- Add App-level coordinator regression coverage, preferably in `Tests/AgentStudioTests/App/PaneCoordinatorHardeningTests.swift` or `Tests/AgentStudioTests/App/PaneCoordinatorTests.swift`.
- Red/green: execute `.closePane` on a parent pane with two drawer children through `PaneCoordinator`; assert no stale membership remains and a live SQLite snapshot saves.
- Red/green: close parent with drawer children, call `undoCloseTab()`, and assert parent, drawer children, drawer membership, and tab membership restore coherently.

### T4 - Harden insert-producing coordinator flows and `insertPane`

Keep `WorkspaceTabArrangementAtom.insertPane` all-or-nothing even if its failure branch is currently hard to trigger with valid `Layout` values:

- Compute the updated `TabArrangementState` in a local copy.
- Commit back to `arrangementStates[tabIndex]` once all preconditions and layout updates succeed.
- Preserve warning logs and return `false` on failure.

Also harden production caller flows that currently drop the result:

- `.detachDrawerPane`: preflight that the parent is in the active target arrangement before detaching. If final insertion fails, restore or leave the drawer state unchanged; never strand the pane between drawer and main layout.
- Existing-pane move: avoid removing from the source tab until the destination insertion can succeed, or use an atomic cross-tab mutation seam. Do not leave the pane in neither tab.
- New-terminal insert paths: if insertion fails after pane creation, delete/background the new pane through an existing cleanup seam and log the concrete failure.

Tests:

- Existing success path coverage in `WorkspaceTabBoundaryTests` and `PaneArrangementInvariantTests` must still pass.
- Add coordinator/action tests only for failure paths that can be made deterministic with public seams.
- If a deterministic red for `insertPane`'s non-active arrangement failure cannot be produced without invalid private state, document that in the implementation proof and rely on code review plus success-path regression for this hardening subtask.

### T5 - Log the concrete save error

In `WorkspaceStore.swift`, replace `error.localizedDescription` with `String(describing: error)` at both workspace save catch sites:

- SQLite `persistNow()` catch.
- Legacy JSON `persistLegacyJSONSnapshot(...)` catch.

Do not change datastore trace behavior unless new evidence shows it drops error details; existing datastore trace tests already assert full error descriptions.

Proof:

- Compact proof through code review plus build/lint.
- No new os_log assertion is required.

### T6 - End-to-end wedge regression

Add a deterministic regression that combines the original failure shape with the real save/reload path:

- Start from a SQLite-backed `WorkspaceStore`.
- Create a tab with drawers and at least two arrangements.
- Exercise the real coordinator flow for the fixed action path where possible (`.closePane` and `.detachDrawerPane`).
- Force or reproduce the known membership divergence shape if needed.
- Assert `await flushAsync()` succeeds.
- Assert core/local snapshot completion advances.
- Restore into a fresh SQLite-backed store with `restoreAsync()`.
- Assert drawers, drawer children, arrangements, tab membership, and active cursors are coherent.

Preferred homes:

- App coordinator flow: `Tests/AgentStudioTests/App/PaneCoordinatorHardeningTests.swift`.
- SQLite save/reload proof: `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreBridgeTests.swift`.

## Requirements / Proof Matrix

| # | Requirement | Task | Proof gate | Layer | Red/green |
|---|-------------|------|------------|-------|-----------|
| R1 | Live snapshot normalizes arrangement/drawer membership divergence | T1 | `WorkspacePersistenceTransformerTests` | unit | yes |
| R2 | Normalization reports repairs structurally | T1 | normalization result assertions | unit | yes |
| R3 | Snapshot normalization is bounded and does not hide cross-tab duplicate ownership | T1 | transformer + repository validation test | unit/integration | yes |
| R4 | Diverged live atom state no longer wedges `WorkspaceStore.flushAsync()` | T2 | `WorkspaceSQLiteStoreBridgeTests` | integration | yes |
| R5 | SQLite save/reload hydrates coherent drawers and tab membership | T2/T6 | SQLite bridge restore test | integration | yes |
| R6 | Closing a parent pane with drawer children leaves no stale membership | T3 | coordinator regression | integration | yes |
| R7 | Close-parent undo restores drawer children coherently | T3 | coordinator undo regression | integration | yes |
| R8 | Insert-producing coordinator flows do not strand panes on insert failure | T4 | deterministic coordinator tests where possible | integration | yes where deterministic |
| R9 | `insertPane` no longer has partial-write structure | T4 | code review + existing success regressions | unit/review | no if failure branch is unreachable |
| R10 | Workspace save logs include concrete error descriptions | T5 | both catch sites changed; lint/build | build/review | compact proof |
| R11 | No repo-wide regressions | all | `mise run test` and `mise run lint` | suite | n/a |

## Write Surfaces

- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistenceTransformer.swift`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabArrangementAtom.swift`
- `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- Tests:
  - `Tests/AgentStudioTests/Core/Stores/WorkspacePersistenceTransformerTests.swift`
  - `Tests/AgentStudioTests/Core/Stores/WorkspaceSQLiteStoreBridgeTests.swift`
  - `Tests/AgentStudioTests/App/PaneCoordinatorHardeningTests.swift`
  - `Tests/AgentStudioTests/App/PaneCoordinatorTests.swift` if the existing harness is a better fit

## Validation Gates

After preflight:

1. Red/green targeted tests:
   - `mise run test -- --filter WorkspacePersistenceTransformerTests`
   - `mise run test -- --filter WorkspaceSQLiteStoreBridgeTests`
   - `mise run test -- --filter PaneCoordinatorHardeningTests`
   - Add any exact filter discovered during implementation for coordinator undo/action tests.
2. Full relevant suite:
   - `mise run test`
3. Code quality:
   - `mise run lint`
4. Manual debug smoke only after automated gates pass:
   - `mise run build`
   - Launch debug build from `.build-agent-N`, never the running production app.
   - Use a temp data root.
   - Create drawers, detach/close drawer-related panes with multiple arrangements, confirm no "Workspace save failed" notification, restart, confirm drawers restore.
   - Optional trace: `AGENTSTUDIO_TRACE_TAGS=persistence` and confirm no failed workspace save entries in the debug trace.

If full-suite or debug smoke is blocked by environment outside this scope, report the blocker with targeted pass/fail status. Do not edit build infrastructure unless separately approved.

## Sequencing

1. Preflight environment.
2. T1 normalization helper/result and transformer unit tests.
3. T2 SQLite store save/reload proof.
4. T3 close-pane drawer-child coordinator fix and undo proof.
5. T4 insert-flow hardening.
6. T5 logging.
7. T6 end-to-end wedge regression.
8. Full validation gates.

Split trigger: if T4 requires a new cross-atom mutation coordinator API broader than the listed action flows, stop and replan that slice instead of expanding silently.

## Risks

- Snapshot-only normalization can mask mutation bugs. Mitigation: structured repair result, warning log, and narrow normalization scope.
- Full hydrate semantics are broader than this fix. Mitigation: explicitly do not dedupe cross-tab duplicate ownership or silently repair unrelated structural corruption at save time.
- Coordinator fixes can affect undo. Mitigation: explicit close-parent-with-drawer-children undo regression.
- Insert failure can be hard to reproduce with valid public state. Mitigation: harden structure where reasonable, but do not claim red/green proof for unreachable branches.

## Security

Not security-sensitive: local SQLite persistence and main-actor state mutation only. No untrusted input, network, subprocess, auth, secrets, plugin, MCP, package-script, or external-service boundary changes.

## Open Questions

1. If future warning telemetry shows repeated snapshot normalization from an untracked path, should the app self-heal live atoms after save? Current decision: no; transformer remains snapshot-only to preserve store/atom ownership direction.
2. Should failed insert actions become user-visible notifications? Deferred; current scope logs and prevents persistence/data-loss wedges.
