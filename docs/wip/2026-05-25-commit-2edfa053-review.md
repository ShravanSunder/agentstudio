# Commit 2edfa053 Review — Refine keyboard surface shortcut routing

Scope: 26 files, +488/-206. Addresses 4 of 5 outstanding concerns from the prior PR review and adds substantial test coverage.

## Verdict: SHIP

Architecture is cleaner than the previous iteration. Concerns C1/C2/C3 from `docs/wip/2026-05-25-active-surface-policy-review.md` are resolved. One outstanding gap (C5 — Cmd+Shift+D regression test) and two design notes.

---

## Per-Focus-Area Verification

### 1. AppShortcut / AppCommand catalog

**Verified:**
- `selectTab1..9` reintroduced as shortcuts bound to **`⌘1..9`** via new `selectTabSpec` at `AppShortcut.swift:550-555` (modifiers `[.command]`, contexts `[.global, .terminalAppOwned]`).
- `focusPane1..9` **rebound from `⌘1..9` → `⌥1..9`** via updated `focusPaneSpec` at `AppShortcut.swift:557-562` (modifiers `[.option]`).
- `hiddenTabSelectionDefinition` at `AppCommand+Catalog.swift:879` now passes `shortcut: Self.selectTabShortcut(index:)` — command-bar metadata previously omitted the shortcut binding.
- New `AppCommand+OrdinalShortcuts.swift` factors `selectTabShortcut(index:)` and `focusPaneShortcut(index:)` into one extension with `preconditionFailure` for out-of-bounds. Cleaner than the previous duplicated switch.
- `showPaneInboxNotifications` spec is **`⌘⇧U`** (`AppShortcut.swift` line near 296). The test was updated to match (was previously `⌘⇧I` — the spec change appears to have happened in an earlier commit; this commit syncs the stale test).

**Note (not a blocker):** Your summary lists "AppShortcut/AppCommand catalog changes for tab, pane, ..." but doesn't call out the **user-facing rebind** — `⌘1..9` is now tab selection (previously had no binding mid-branch), `⌥1..9` is now pane focus (was `⌘1..9` earlier in the branch). Docs are updated correctly at `commands_and_shortcuts.md:99,101`. Worth flagging in release notes / changelog.

### 2. Active surface policy

**Verified:**
- **Command-bar reservation:** `isCommandBarActivationShortcut` is evaluated first in both `shouldDispatchGlobalShortcut` and `shouldDispatchTerminalAppOwnedShortcut` — exhaustive switch, no defaults. `selectTab1..9` is in the "not activation" arm (correct).
- **Arrangement-panel allowances:** `shouldDispatchFromArrangementPanel` at `AppShortcutDispatchPolicy.swift:135-148` now allows `previousArrangement, nextArrangement, prevTab, nextTab, selectTab1..9`. Exhaustive switch over `AppShortcut`, no default — compile-time classification.
- **Transient blocking defaults:** `.tabRename`, `.arrangementRename`, `.paneInbox`, `.editorChooser` all in the `return false` arm at `shouldDispatchFromTransientSurface` — correctly block by default.
- **Unavailable owned shortcuts consumed:** the previous `appCommandOverride` rewriting mechanism is **removed** and replaced with `shouldConsumeUnavailableGlobalShortcut` at lines 25-34. Called from `PaneTabViewController.handleAppOwnedKeyEvent` after a failed `canDispatch` — returns true → consume → no leak.
- Test `arrangementPanelConsumesUnavailableTabOrdinalShortcuts` at `PaneTabViewControllerGlobalShortcutRoutingTests.swift:540-572` proves the swallow path with `handler.canExecuteResult = false`.

**Design note — asymmetric swallow semantics worth a one-line comment:**
- Terminal-app-owned path (`handleTerminalAppOwnedShortcut`): ANY rejected owned shortcut → `.swallowed` (anti-leak — prevents raw input flowing to Ghostty).
- Global path (`PaneTabViewController`): rejected owned shortcut → only consumed if `shouldConsumeUnavailableGlobalShortcut` returns true (currently only arrangement-panel).

The asymmetry is intentional (different leak surfaces) but neither the new `shouldConsumeUnavailableGlobalShortcut` nor the call site in `handleAppOwnedKeyEvent` documents it. A future maintainer might "harmonize" them and break either anti-leak or normal responder flow. Two-line comment at each site would lock the design.

### 3. PaneTabViewController routing + ArrangementPanelPresentationAtom

**Verified:**
- `WindowLifecycleAtom` injected via constructor at `PaneTabViewController.swift:178`, defaulting to `atom(\.windowLifecycle)`. `MainSplitViewController.swift:78,95,120` threads it through. All internal sites converted to `windowLifecycleStore` instead of `atom(\.windowLifecycle)`. Search confirms no remaining direct accesses in routing code.
- Test `productionGlobalKeyPathUsesInjectedWindowLifecycle` at `PaneTabViewControllerGlobalShortcutRoutingTests.swift:104-137` proves the injection is actually consulted (uses a fresh atom and shows the controller reads from it, not the global).
- `ArrangementPanelPresentationRequest.workspaceWindowId` is now **non-optional `UUID`** at `ArrangementPanelPresentationAtom.swift:7,9`. `present(...)` matches.
- Both consumers (`CustomTabBar.swift:552`, `CollapsedPaneBar.swift:220`) tightened to exact `request.workspaceWindowId == workspaceWindowId` — nil-wildcard branch removed.
- `requestArrangementPanel` at `PaneTabViewController.swift:2477-2487` now `guard let workspaceWindowId = workspaceWindowId ?? lifecycle.focusedWindowId ?? lifecycle.keyWindowId else { return }` — no nil-window requests can be created.
- Three new tests document the contract: `executeSwitchArrangement_withoutWorkspaceWindow_doesNotRequestArrangementPanel`, `executeSwitchArrangement_prefersControllerWorkspaceWindow`, and an updated `executeSwitchArrangement_requestsArrangementPanel` that now asserts `workspaceWindowId` on the request.

**Resolves my prior C3** (nil-window wildcard) completely.

### 4. Ghostty terminal-app-owned shortcut handling

**Verified:**
- `handleTerminalAppOwnedShortcut` extracted to **pure static helper** at `GhosttySurfaceView+Input.swift:79-99`, takes closures for `canDispatch` and `dispatch`, returns `TerminalAppOwnedShortcutHandling` discriminated union (`.notHandled | .swallowed | .dispatched(AppCommand)`).
- `performKeyEquivalent` switch at lines 117-126 cleanly handles each case: `.notHandled` falls through, `.swallowed`/`.dispatched` returns true.
- Cmd-K defense triple-layered: Ghostty config (`keybind = cmd+k=unbind`) + `terminalHostSuppressedTriggers` early-return + `.swallowed` on policy/dispatch reject.
- New test `terminalAppOwnedShortcutHandler_swallowsRejectedShortcutWithoutDispatch` at `GhosttySurfaceShortcutTests.swift:82-117` directly tests the swallow contract using the pure helper — no view setup needed. Uses ⌘⇧K with arrangement panel transient surface active, asserts `.swallowed` and `dispatchedCommands.isEmpty`.
- `appOwnedTerminalShortcuts_includeTabAndPaneOrdinals` confirms `selectTab1, selectTab9, focusPane1, focusPane9` are in the terminal-app-owned set.

**Resolves my prior C2** (broadened swallow had no test).

### 5. Atom design

**Verified `ArrangementPanelPresentationAtom`:**
- `@MainActor @Observable final class` ✓
- `private(set) var pendingRequest` ✓ (CLAUDE.md atom contract)
- Mutation through methods (`present`, `consume`) ✓
- Single-purpose: only holds the pending request, no other state ✓
- Window-scoped via non-optional `workspaceWindowId: UUID` on the request ✓
- `consume(request)` is idempotent via id-equality guard ✓

**Verified `CommandBarSurfaceAtom` and `TransientKeyboardSurfaceAtom`:** not touched in this commit — shape unchanged.

---

## Outstanding / New Concerns

### C5 (from prior review) — Cmd+Shift+D regression still has no direct test

`requiresPaneTargetFallback` is now a clean declarative property and the special-case logic is well-structured in `handleAppOwnedKeyEvent`, but I cannot find a test that exercises the **scenario the fix exists for**: ⌘⇧D pressed with text-input focus while the drawer is empty. `grep -rn "addDrawerPane" Tests/ --include='*.swift'` returns only store-level tests (`WorkspaceStoreDrawerTests`), none at the controller/policy level for this scenario.

Without a regression test, the next refactor of `handleAppOwnedKeyEvent` can silently break it again. Suggested test in `PaneTabViewControllerCommandTests` or `PaneTabViewControllerDrawerCommandTests`:

```swift
@Test("addDrawerPane reaches targeted dispatch when global dispatch is blocked")
// arrange: empty drawer, simulate the focused state that originally caused the regression
// act: handleAppOwnedKeyEvent(⌘⇧D)
// assert: handled == true, drawer pane was created
```

### C-doc — Asymmetric swallow semantics undocumented in code

See note in §2 above. Two short comments would lock the design:

At `AppShortcutDispatchPolicy.shouldConsumeUnavailableGlobalShortcut` — *"Only arrangement-panel-owned shortcuts get consumed when unavailable; other rejected shortcuts flow back to the responder chain so unhandled chords still surface to NSApp menus."*

At the call site in `PaneTabViewController.handleAppOwnedKeyEvent` — *"Terminal pane path swallows broadly (GhosttySurfaceView) to prevent raw input leak; main window chain consumes selectively because there's no leak hazard."*

### C-rebind — User-facing keybinding change not in commit summary

The summary says "AppShortcut/AppCommand catalog changes for tab, pane, ..." but doesn't call out:
- `⌘1..9` now selects tabs (reintroduced after earlier branch commits removed it)
- `⌥1..9` now focuses panes (was `⌘1..9` earlier in this branch)

Both bindings are correct in the architecture doc. This is a release-notes / changelog item, not a code issue.

---

## Strengths Worth Noting

- **`appCommandOverride` → `shouldConsumeUnavailableGlobalShortcut` is a strict architectural improvement.** The override mechanism was implicit command rewriting (one trigger → different command depending on surface). The new model has `selectTab1..9` as first-class shortcuts, with the policy answering two orthogonal questions: "can this dispatch here?" and "should we eat it if we can't?". Cleaner separation, easier to test.
- **`handleTerminalAppOwnedShortcut` extraction is exemplary** — pure function, closure-injected effects, discriminated-union outcome. Testable without view scaffolding.
- **`requiresPaneTargetFallback` declarative property** replaces the magic `shortcut == .addDrawerPane` comparison from the previous iteration. Exhaustive switch, no default — adding a new fallback-requiring shortcut forces a compile error.
- **Compile-time safety preserved everywhere.** Every classification switch in the policy is exhaustive over `AppShortcut`. `requiresPaneTargetFallback`, `isCommandBarActivationShortcut`, `shouldDispatchFromArrangementPanel`, `shouldDispatchFromMainWindowChain`, `shouldDispatchFromSidebar` — all exhaustive.
- **Dependency injection done right.** `WindowLifecycleAtom` threaded through with sensible defaults; tests can inject fakes; production calls unchanged. The `productionGlobalKeyPathUsesInjectedWindowLifecycle` test proves the seam actually works.
- **Test renames are honest.** `optionK_mainPane_fallsThroughWithoutConcreteCommand` → `optionK_mainPane_isSwallowedWithoutConcreteCommand` with flipped assertion documents the new "consume even when no movement" contract directly in the test name.
- **Docs and code stay in sync.** `commands_and_shortcuts.md` and `keyboard-surface-system.md` both updated to reflect the new ownership and the removal of the override-rewriting language.

---

## Recommended Order

1. **Add the Cmd+Shift+D regression test** (C5). Cheap; protects the fix.
2. **Add the two design comments** about asymmetric swallow semantics (C-doc). One-liners.
3. **Add ⌘1..9 / ⌥1..9 rebind to your changelog** (C-rebind). Release notes only.

Everything else is good to merge.
