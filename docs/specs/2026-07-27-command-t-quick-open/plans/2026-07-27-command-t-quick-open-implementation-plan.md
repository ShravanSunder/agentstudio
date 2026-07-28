# Command-T Quick Open Implementation Plan

> **For agentic workers:** Execute serially with test-first checkpoints. The Command Bar state, projection, activation, and row interaction surfaces overlap, so parallel writes would add coordination without shortening the critical path.

**Goal:** Make Command-T open a dedicated Quick Open root where Return immediately opens a terminal at a useful current, recent, repository, or worktree target and Tab enters existing repository/worktree action menus.

**Architecture:** Add one `CommandBarScope.quickOpen` case and one matching app command for the existing Command-T shortcut. Build repository/worktree rows from live topology, current-directory rows from focused pane/watched-root/home state, and Recent from existing repository/worktree application recency. Re-resolve topology targets, validate directory targets, route pane/tab creation through the existing workspace action owner, and reuse current repository/worktree action-level builders. Keep `#` behavior unchanged.

**Tech Stack:** Swift 6, SwiftUI/AppKit, Swift Testing, existing atom-backed repository topology and command dispatcher.

## Global Constraints

- No SQLite migration, topology ownership, or generic command-framework changes.
- No duplicate action-menu builders.
- Repository rows represent their default worktree; the matching main-worktree path is not repeated as another Quick Open location.
- All Quick Open dispatch targets are re-resolved from live topology.
- Existing Main, `#`, `$`, and `>` behavior remains unchanged.

## Requirements and Proof

| Requirement | Owning task | Proof |
|---|---|---|
| Command-T opens Quick Open without inserting `#` | Task 1 | shortcut/catalog/state unit tests |
| Empty root shows Current, Recent, Repositories & Worktrees without duplicate paths | Task 2 | projection tests against real `WorkspaceStore` topology, pane state, and recency atoms |
| Search removes Current/Recent and searches all live locations | Task 2 | meaningful-query projection test |
| Return, Command-Return, and Option-Return use the specified terminal owners for worktrees and directories | Task 3 | controller activation tests with real dispatcher/action-owner seams |
| Tab and the trailing action control enter existing menus | Task 3 | view/controller tests plus native UI proof |
| Shift-Tab, empty Backspace, and Escape preserve existing semantics | Task 3 | focused existing navigation tests |
| `#` still enters repository/worktree menus | Task 3 | existing and focused regression tests |
| Down-arrow on the final result wraps to the first result, matching upward wrap | Task 4 | result-session reproduction test plus native UI proof |

## Task 1: Dedicated Quick Open entry

**Files**

- Modify `Sources/AgentStudio/Core/Models/CommandBarScope.swift`
- Modify `Sources/AgentStudio/App/Commands/AppCommand.swift`
- Modify `Sources/AgentStudio/App/Commands/AppCommand+Catalog.swift`
- Modify `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- Modify existing AppDelegate command-routing and command-policy switches
- Modify Command Bar state/global-key routing tests

Steps:

1. Add failing tests proving `AppShortcut.newTab` routes to a dedicated Quick Open app command and `CommandBarState.show(defaultScope: .quickOpen)` has Quick Open identity without a prefix.
2. Run the focused tests and confirm they fail because the scope/command do not exist.
3. Add the minimal command and scope cases, route Command-T through the existing controller `show(defaultRootScope:)` path, and update exhaustive switches.
4. Run the focused tests green.

## Task 2: Quick Open location projection

**Files**

- Create `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+QuickOpen.swift`
- Modify `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- Modify `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+RootProjection.swift`
- Modify `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift`
- Add focused projection tests under `Tests/AgentStudioTests/Features/CommandBar/`

Steps:

1. Add failing tests for repository-default-worktree deduplication, Current/Recent/Repositories & Worktrees ordering, current worktree-or-cwd selection, first-watched-root and home rows, normalized-path deduplication, and meaningful-query flattening.
2. Confirm the tests fail because Quick Open projection and target actions do not exist.
3. Add a small typed Quick Open target using repository/worktree stable keys or a normalized directory URL.
4. Build canonical rows from repos plus non-default worktrees, then project Current and Recent ahead of the remaining complete rows only for an empty query.
5. Run the projection tests green.

## Task 3: Immediate activation and action-menu entry

**Files**

- Modify `Sources/AgentStudio/Features/CommandBar/CommandBarPanelController.swift`
- Modify `Sources/AgentStudio/Features/CommandBar/CommandBarWorktreeActionResolver.swift` only if its existing modifier mapping can be reused cleanly
- Modify `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift`
- Modify `Sources/AgentStudio/Features/CommandBar/Views/CommandBarResultsList.swift`
- Modify `Sources/AgentStudio/Features/CommandBar/Views/CommandBarResultRow.swift`
- Add focused controller/view tests under `Tests/AgentStudioTests/Features/CommandBar/`

Steps:

1. Add failing tests for live re-resolution, directory validation, and the three Return variants, including Option-Return unavailable without a current tab.
2. Add failing proof that an explicit actions activation enters the existing repo/worktree level without performing the primary action.
3. Implement one controller-owned Quick Open activation path:
   - Return: current-tab pane when available, otherwise new tab.
   - Command-Return: new tab.
   - Option-Return: current-tab pane only when available.
   - Actions: push the existing repository or worktree level.
4. Route Tab and a Quick Open-only trailing button to Actions; keep full-row click as primary Return.
5. Run focused tests green, then rerun all Command Bar tests.

## Task 4: Symmetric result-list arrow wrapping

**Files**

- Investigate `Sources/AgentStudio/Features/CommandBar/CommandBarState.swift`
- Investigate `Sources/AgentStudio/Features/CommandBar/CommandBarResultSession.swift`
- Modify only the proven failing owner
- Add the smallest regression test under `Tests/AgentStudioTests/Features/CommandBar/`

Steps:

1. Reproduce the actual sequence through the result-session snapshot boundary: select the final displayed row, press Down, and rebuild the snapshot.
2. Compare it with the working first-row Up sequence and identify where the wrapped index is lost.
3. Add the failing regression test at that boundary.
4. Make the single root-cause fix and run the focused test green.
5. Verify both directions in the background-launched native UI.

## Validation and Delivery

1. Run `mise run test -- --filter CommandBar`.
2. Run `mise run lint`.
3. Run full `mise run test` because the change adds an `AppCommand` and exhaustive routing cases outside the feature folder.
4. Launch with `mise run run-debug-observability -- --detach`.
5. Verify startup with `mise run verify-debug-observability`.
6. Use PID-targeted Peekaboo in background mode to verify Quick Open identity, section layout, search flattening, immediate Return, Tab/action-button drill-in, and symmetric Up/Down wrapping.
7. Review `git diff --check` and the final scoped diff.
8. Commit, push `fix-cmdbar-breadcrumbs`, and update draft PR #221. Do not merge.

## Risks and Split Triggers

- If Quick Open cannot reuse existing repository/worktree menu builders or the workspace terminal action owner without changing their ownership, stop and reconverge before an architecture change.
- If a full-suite failure is outside the Command-T path, report it without editing unrelated infrastructure.
- The change is a hard cutover for Command-T only; no compatibility alias from Quick Open to `#`.

Security context: not applicable. The implementation adds no new trust, filesystem, network, subprocess, credential, or persistence boundary.
