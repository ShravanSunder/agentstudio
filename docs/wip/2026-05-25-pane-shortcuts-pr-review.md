# PR Review — `pane-shortcuts` branch

Scope: `git diff main...HEAD` — 89 files, +7703/-534. Keyboard-surface system, shortcut dispatch policy, Cmd-K removal, pane ordinal focus, transient surface routing.

Reviewers run in parallel: code-reviewer, pr-test-analyzer, silent-failure-hunter, type-design-analyzer, comment-analyzer. All claims listed below either come from multiple reviewers (consensus, high confidence) or were independently grounded by me against actual source.

## Verdict: SHIP-WITH-FIXES

- **Architecture is sound.** Atoms follow CLAUDE.md contract (`@MainActor @Observable final class` + `private(set)` + valtio-style methods). Dispatch policy is exhaustive switches with no defaults. Surface model is a clean discriminated union. `ValidatedAction` proof-token pattern at `ActionValidator.swift:6-12` is type-system-enforced.
- **No critical correctness bugs.** All five must-fix items below are silent-failure cleanups + one missing regression test for the marquee feature (Cmd-K).
- **Test discipline is excellent.** No `Task.sleep` anywhere in new tests (verified by `git diff main...HEAD -- 'Tests/**/*.swift' | grep sleep` returning empty). `withTestAtomRegistry { ... }` pattern gives clean per-test atom isolation.

---

## Must-Fix Before Merge (5)

### 1. M1 — `TransientKeyboardSurfaceRegistrationModifier` silently no-ops when no window resolves
**Where:** `Sources/AgentStudio/Core/Views/TransientKeyboardSurfaceRegistrationModifier.swift:24-32`
**Consensus:** silent-failure-hunter + test-analyzer #3 + my own grounding.

`register(...)` does `guard let resolvedWindowId else { return }` with no log. If onAppear races a window-becomes-key callback, the suppression is silently skipped → user types Escape/Enter/⌘+chord into the popover, falls through to underlying terminal. No way to debug except by repro.

**Fix:** at minimum `logger.warning(...)` + a `TransientKeyboardSurfaceRegistrationModifier` lifecycle test that documents the contract (always register, or fail loudly).

### 2. M2 — `CommandBarPanelController.executeItem` silently drops selection
**Where:** `Sources/AgentStudio/Features/CommandBar/CommandBarPanelController.swift:311-314` (verified)

```swift
if let command = item.command, !dispatcher.canDispatch(command) {
    return
}
```

User searches, sees row, hits Enter — nothing happens. Either (a) filter unavailable commands out of `displayedItems`, or (b) log + render disabled. Silent return is the worst of both.

### 3. M3 — `CommandBarPanelController.show` fabricates a random UUID
**Where:** `CommandBarPanelController.swift:78` (verified)

```swift
let resolvedWorkspaceWindowId = requestedWorkspaceWindowId ?? workspaceWindowId ?? UUID()
```

If both inputs are nil, a fresh UUID is created and stored — `CommandBarSurfaceAtom.activeScope(for:)` will then never match this id from any caller, silently decoupling the command bar from the routing policy. Replace `?? UUID()` with `else { logger.error(...); return }`.

### 4. M4 — `AppDelegate+ShellCommandHandling` returns `true` with nil atomStore
**Where:** `Sources/AgentStudio/App/Boot/AppDelegate+ShellCommandHandling.swift:60-69` (verified)

```swift
case .toggleInboxNotificationSort:
    guard let atomStore else { return true }   // claims "handled", does nothing
    ...
case .clearReadInboxNotifications:
    atomStore?.inboxNotification.clearReadHistory()
    return true                                // optional chain no-ops, still "handled"
```

Dispatcher reads `true` = success. During boot/teardown the keystroke is silently swallowed. Log + return `false` (let dispatcher route elsewhere).

### 5. M5 — `TransientKeyboardSurfaceAtom.replace` silently appends on unknown token
**Where:** `Sources/AgentStudio/Core/State/MainActor/Atoms/TransientKeyboardSurfaceAtom.swift:31-46`
**Consensus:** silent-failure-hunter M5 + type-design #2 + my own grounding.

Stale token → caller thinks it replaced an existing registration but actually appended a second one with a different token. The modifier's local `@State token` never matches → `dismiss(token)` removes nothing → ghost suppression entry leaks until window teardown.

**Fix:** make `replace` strict (return Bool or throw); offer explicit `presentOrReplace` if a caller genuinely needs append-on-miss.

---

## Critical Test Gap (1)

### 6. Cmd-K end-to-end suppression has no regression test
**From:** test-analyzer gap #1 (rated 10/10).

`GhosttyAppHandle` test asserts the config string contains `keybind = cmd+k=unbind` (`Tests/AgentStudioTests/Features/Terminal/Ghostty/GhosttyAppHandleTests.swift:15-20`) — but nothing tests that `performKeyEquivalent` actually claims a real Cmd-K NSEvent and that it never reaches `ghostty_surface_key`. Any future refactor of `GhosttySurfaceView+Input.swift` silently re-enables Ghostty's Cmd-K clear-scrollback.

This is the marquee feature of the PR. It needs the test.

---

## Important (Should-Fix Soon)

### 7. `PaneOrdinalMap` silent truncation at 9
**Where:** `Sources/AgentStudio/Core/Models/PaneOrdinalMap.swift:11`
**Consensus:** type-design #1 + code-reviewer #1 + my own grounding.

`orderedPaneIds.prefix(9)` drops pane 10+ with no log. Two suggested fixes:
- Extract `9` to `AppPolicies.Shortcuts.maxOrdinalPaneShortcuts` so the limit lives in one place (per CLAUDE.md "behavioral constants belong in AppPolicies").
- Introduce a `PaneOrdinal` enum (case one=1, two, ..., nine) so 1..9 is load-bearing at the type level and the validation happens once at the keyboard boundary.

### 8. `KeyboardRoutingContext.workspaceWindowId` optional with no documented invariant
**Where:** `Sources/AgentStudio/Core/Models/KeyboardRoutingContext.swift:34-39`
**Consensus:** type-design #5 + code-reviewer #2.

5-deep `??` fallback chain can attribute a keystroke to the wrong window when no window is key/focused. The atoms are window-scoped specifically to prevent bleed; the fallback partially undermines that intent. Failure mode is conservative (over-suppression, not mis-dispatch), but worth either (a) making `workspaceWindowId` non-optional and returning nil from the factory, or (b) documenting the priority chain + a cross-window isolation test.

### 9. `TransientKeyboardSurfaceAtom` allows duplicate kind per window, has no cap
**From:** type-design #3.

Nothing prevents two `.tabRename(tabId: X)` being stacked. Either dedup on `present` (return existing token if same kind+window), or document the stack model explicitly. Also consider a `AppPolicies.maxTransientKeyboardSurfaces` cap so leaks become loud.

### 10. Rename-editor key handling duplicated between TabRenamePopover and ArrangementRenameTextField
**Where:** `Sources/AgentStudio/App/Panes/TabBar/TabRenamePopover.swift:316-343` vs `Sources/AgentStudio/Core/Views/Panes/ArrangementRenameTextField.swift:135-165`
**From:** code-reviewer #6.

Per CLAUDE.md: "When two app surfaces need the same visual control, extract a stateless primitive into `SharedComponents/`." Two parallel implementations of the same commit-character/escape-codepoint logic. Extract to `SharedComponents/`.

### 11. `performKeyEquivalent` swallow-on-canDispatch-false has no test
**Where:** `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView+Input.swift:82-103`
**From:** code-reviewer #3 + test-analyzer gap #2.

The "swallow but don't dispatch" path (intentional anti-leak) is exercised only via the policy unit test, not through `performKeyEquivalent`. Add `TerminalAppOwnedShortcutPolicyTests` coverage that wires through the real view, with a transient surface active.

---

## Suggestions (Polish)

- **`TabRenamePopover` magic dimensions** (`minHeight: 112`, `width: 440`, `cornerRadius: 14`) → `AppStyles.Shell.Popover`.
- **`ActionValidator.validate(...)` is one ~340-line switch.** Split per command category (tab, pane, arrangement, drawer). Cyclomatic complexity is currently silenced via linter disable.
- **`PaneTabViewController.swift` is 2947 lines** — per CLAUDE.md ">900 = refactoring prompt". The pane-focus + ordinal subsystem (+450 lines this PR) is a natural extraction.
- **`CommandBarScope` and `SearchItemType` carry overlapping but mismatched vocabularies** (type-design #4). Add `CommandBarScope.searchItemTypes: Set<SearchItemType>` computed property so the bridge is compiler-checked.
- **`ResolvableTab.validationActiveArrangementId`** is named for its consumer (the validator). Rename to `activeArrangementId` (matching the Tab extension at line 30).
- **`TransientKeyboardSurfaceAtom.dismissAll`** — never used in production per quick grep. Either delete or test (silent-failure + test-analyzer #5).
- **`MainSplitViewControllerCompositeCommandTests.swift:42`** uses standalone `await Task.yield()` while the other 9 tests in the same suite use `eventually(...)`. Inconsistency — replace with `eventually`.
- **`GhosttySurfaceShortcutTests`** mostly asserts "this enum case is in this array" — duplicates `ShortcutCatalogTests` and breaks on benign renames. Collapse or delete in favor of behavioral coverage.
- **Comment cleanup nits** (delete WHAT-not-WHY restatements): `ActionStateSnapshot.swift:3`, `PaneLeafContainer.swift:353`, `CommandBarScope.swift:3`, `ActionExecutorTests.swift:625,724,767,730,739`.
- **Logging gaps** at `ActionResolver.swift` (~30 nil returns drop commands silently), `PaneTabViewController.handleAppOwnedKeyEvent` (no log on shortcut suppression), `drawerFocusNeighbor` (silent edge-of-grid).

---

## Strengths Worth Preserving

- **Cmd-K defense in depth**: Ghostty config (`GhosttyAppHandle.swift:13` `keybind = cmd+k=unbind`) + host swallow (`GhosttySurfaceView+Input.swift:65-71`) + tests for both.
- **Compiler-enforced shortcut routing** — every `AppShortcut` switch in `AppShortcutDispatchPolicy` is exhaustive. Adding a shortcut forces a placement decision in main/sidebar/transient via compile error.
- **`ValidatedAction` proof-token pattern** — `fileprivate init` wrapper means only the validator can mint one. Type-system gating between resolution and execution.
- **`ActiveKeyboardSurface = commandBar | transient | stable`** — three mutually exclusive states modeled as discriminated union. "Two surfaces active at once" is structurally impossible.
- **`CommandBarSurfaceAtom` and `TransientKeyboardSurfaceAtom`** are textbook atoms: `@MainActor @Observable`, `private(set)`, mutation through methods, scope-by-window query methods preventing cross-window bleed.
- **`AppShortcutDispatchPolicy`** is pure functions over `KeyboardRoutingContext` — trivial to test, easy to reason about, no hidden globals.
- **New keyboard-surface files ship with zero comments.** Names carry the meaning — exactly the CLAUDE.md ideal.
- **`KeyboardRoutingContextSurfaceTests`** is a model test file: precedence ordering, window scoping isolation, transient-survives-temporary-key-loss contract. All five transient kinds iterated.
- **Atom isolation in tests** via `withTestAtomRegistry { atoms in ... }` and `AtomScope.$override.withValue(...)` — clean per-test isolation, no global mutation leakage.

---

## Out-of-Scope (Pre-existing, Not This PR)

- `DrawerGridLayout` has `var` properties + `bottomRow == nil` vs `bottomRow == .empty` ambiguity. Type-design flagged but the diff only adds a Codable shim. Follow-up.
- `PaneTabViewController.swift` line count was already large; this PR adds ~275 net but the architectural pressure pre-exists.

---

## Recommended Order

1. **Block merge until 1-5 are fixed** (silent failures with concrete user-visible impact).
2. **Add test 6 in the same PR** (Cmd-K regression guard — the PR's marquee feature has no end-to-end test).
3. Tackle 7-11 within next sprint (design hygiene; not user-facing bugs).
4. Suggestions and out-of-scope items in dedicated follow-up PRs.
