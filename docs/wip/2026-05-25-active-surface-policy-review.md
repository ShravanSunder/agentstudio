# Focused Review — Active Keyboard Surface Policy + Tab-Local Arrangement Panel

Scope: uncommitted changes implementing two plans:
- `docs/superpowers/plans/2026-05-25-active-keyboard-surface-policy.md`
- `docs/superpowers/plans/2026-05-23-navigation-arrangement-scrollback-shortcuts.md`

Plus the Cmd+Shift+D regression fix.

## Verdict: SHIP-WITH-FIXES

Implementation matches both plans cleanly. Test coverage on the new policy paths is comprehensive (policy unit + production integration). One plan-rule violation (controller special case), one broadened silent-swallow behavior worth a test, and three edge-case nits.

---

## What's Right

- **Centralized policy refactor is clean.** `shouldDispatchFromActiveSurface` and `shouldDispatchTerminalAppOwnedShortcutFromActiveSurface` are well-factored. `shouldDispatchFromArrangementPanel` is an exhaustive switch with no default — adding a new `AppShortcut` forces a classification at compile time. Verified at `AppShortcutDispatchPolicy.swift:115-141`.
- **Command-bar activation as policy phase**, not exception. `isCommandBarActivationShortcut` is checked first in both `shouldDispatchGlobalShortcut` and `shouldDispatchTerminalAppOwnedShortcut`, before any active-surface gate. Works as the plan describes.
- **Tab-local presentation correctly closes on tab change.** `ArrangementPanelTabPresentationState.activeTabDidChange(to:)` at lines 34-37 dismisses iff the panel was owned by a different tab. Test coverage: 5 tests in `ArrangementPanelTabPresentationStateTests.swift` cover present/dismiss/toggle/setPresented/activeTabDidChange happy paths.
- **`ArrangementPanelTabPresentationState` is a model value type** — `private(set) var presentedTabId`, `mutating` methods, `Equatable`. No SwiftUI imports. Cleanly testable in isolation.
- **`ArrangementPanelPresentationAtom` follows the CLAUDE.md atom contract** — `@MainActor @Observable final class`, `private(set)`, method-based mutation, `consume(request)` is idempotent.
- **Arrangement rename remains strict.** `.arrangementRename` is in the `case .tabRename, .arrangementRename, .paneInbox, .editorChooser: return false` arm of `shouldDispatchFromTransientSurface` — blocks all app shortcuts as intended. Test `arrangementRenameBlocksTabLocalNavigationShortcuts` asserts this for the four nav shortcuts.
- **R10 anti-leak now implemented** in `GhosttySurfaceView+Input.swift`. Triple-layered Cmd-K defense (Ghostty config unbind + `terminalHostSuppressedTriggers` early return + R10 swallow on policy reject).
- **Wrap-around math is correct.** `switchActiveArrangement(delta:)` at `PaneTabViewController.swift:2440-2450` uses `(activeIndex + delta + count) % count` — handles both directions correctly. Verified by hand for delta = -1 / +1 at boundaries.
- **Test coverage on the new paths is comprehensive.** Policy unit (3 new tests for arrangement panel), production integration (`productionGlobalKeyPathDispatchesArrangementNavigationThroughArrangementPanel`), state unit (5 tests for tab-local presentation), atom unit (in `ArrangementPanelPresentationAtomTests`).

---

## Concerns

### C1. `shortcut == .addDrawerPane` magic in PaneTabViewController violates the plan
**Where:** `Sources/AgentStudio/App/Panes/PaneTabViewController.swift:1290, 1306`

The Cmd+Shift+D regression fix introduces:

```swift
guard shouldDispatchGlobalShortcut || shortcut == .addDrawerPane else {
    return false
}
...
guard shortcut == .addDrawerPane else {
    return false
}
// Empty-drawer creation needs a pane target, so it falls
// through to the targeted app-owned path below.
```

This is exactly the kind of controller-side special-case the plan explicitly forbids: *"Do not add controller special cases in `PaneTabViewController`. The controller should remain a command executor, not the keyboard policy owner."*

The fix itself is correct (empty-drawer creation needs a pane target, which only the targeted-app-owned path supplies). But the magic shortcut name is a smell. Refactor candidate: introduce `AppShortcut.requiresPaneTargetFallback: Bool` (or a richer dispatch hint) so the policy can express this declaratively and the controller can read a property instead of comparing identities.

Worth flagging because the next person to add a similar fallback will reach for `shortcut == .X` again and the special cases compound.

### C2. R10 silent swallow now applies to all terminal-app-owned shortcuts, not just ⌘K
**Where:** `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView+Input.swift:82-103`

Previously: when policy or `canDispatch` rejected a terminal-app-owned shortcut, `performKeyEquivalent` returned `false` (event flowed to Ghostty / keyDown chain).

Now: returns `true` (event swallowed).

This is correct per the anti-leak rule, but it's broader than ⌘K — **any** terminal-app-owned shortcut (e.g. `⌘⇧K` scrollToBottom, `⌘⇧J/L` prompt nav) is silently consumed when policy/canDispatch rejects. No UI feedback, no log.

The policy-level tests cover the rejection path, but I don't see a test that asserts this swallow behavior is desired for non-⌘K chords via `performKeyEquivalent`. The earlier full-PR review flagged this gap (test-analyzer gap #2: "no test that proves the new `return true` swallow path is reachable when a transient surface owns the keyboard"). Still missing.

**Suggested test:**
```swift
@Test("scrollToBottom is swallowed (not forwarded) when arrangement panel owns keyboard")
// arrange: arrangement panel transient surface present
// act: synthesize ⌘⇧K via fake view, call performKeyEquivalent
// assert: returns true, no ghostty_surface_key forwarded, no dispatch
```

### C3. `requestArrangementPanel` with nil workspaceWindowId matches any window
**Where:** `Sources/AgentStudio/App/Panes/PaneTabViewController.swift:2435-2441` + consumer at `CustomTabBar.swift:550-560`

```swift
private func requestArrangementPanel() {
    guard let activeTabId = store.tabLayoutAtom.activeTabId else { return }
    let workspaceWindowId =
        atom(\.windowLifecycle).focusedWindowId
        ?? atom(\.windowLifecycle).keyWindowId
    arrangementPanelPresentation.present(tabId: activeTabId, workspaceWindowId: workspaceWindowId)
}
```

If both `focusedWindowId` and `keyWindowId` are nil at request time, `workspaceWindowId` is nil. The consumer in `CustomTabBar.openPopoverIfRequested`:

```swift
request.workspaceWindowId == nil || request.workspaceWindowId == workspaceWindowId
```

Nil request matches **any** window — first tab bar to observe it consumes it. In multi-window scenarios with no window currently key/focused (e.g. mid window-switch), the panel could open in the wrong window.

Low-probability edge case. Either tighten the consumer condition (drop the `== nil` branch) or test the multi-window race.

### C4. `isScopeAwarePaneMovementTrigger` silently consumes ⌥I/J/K/L even when movement is impossible
**Where:** `Sources/AgentStudio/App/Panes/PaneTabViewController.swift:1336-1345` (the new structure around the scope-aware trigger handling)

The refactored block now returns `true` (event consumed) for any ⌥+i/j/k/l, regardless of whether `canExecute(command)` is true. Previous behavior: only consumed on successful execute.

This is correct as an anti-leak (prevents ⌥+letter from leaking into terminal/text fields), but it's a silent-swallow class: pressing ⌥J at the leftmost pane with no left neighbor is silently eaten. Probably intentional, but worth a one-line comment explaining the intent (or a test that documents the contract).

### C5. The Cmd+Shift+D regression fix has no regression test
The user mentioned "Fixed the regression where Cmd+Shift+D stopped creating a first drawer pane while text input had focus." I cannot find a test that exercises this scenario. Without it, the next refactor of `handleAppOwnedKeyEvent` can silently break it again.

**Suggested test:** focus a text input (or simulate the `stableOwner` state that originally caused the regression), dispatch ⌘⇧D, assert addDrawerPane is dispatched.

---

## Out of Scope (Pre-existing, Not This Change)

- Earlier silent-failure findings from the broader PR review (`docs/wip/2026-05-25-pane-shortcuts-pr-review.md`) — M1-M5 still stand and weren't touched by this iteration. Address those separately.
- `PaneTabViewController.swift` line count continues to grow (~2947 → ~3003 with these changes). Refactor pressure mounts; not a blocker for this iteration.

---

## Recommended Order

1. **Add test for C5** (Cmd+Shift+D with text-input focus). This is the regression you just fixed — protect it.
2. **Add test for C2** (terminal-app-owned swallow via `performKeyEquivalent`). Encodes the broadened R10 contract.
3. **Decide on C1** — keep the `shortcut == .addDrawerPane` special case as-is + comment (cheap), or introduce a declarative shortcut property (clean but a refactor).
4. **C3, C4** — fold into a follow-up; not blocking.

The architecture is clean. The two plans were executed faithfully. Once C5 and C2 tests land, this is good to merge.
