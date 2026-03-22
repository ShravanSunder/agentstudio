# AppKit Lifecycle And Command/Event Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Centralize AppKit lifecycle ingress behind typed lifecycle stores, remove command/event boundary drift, and make the coordination architecture obvious from code structure, tests, and docs.

**Architecture:** Add a thin `ApplicationLifecycleMonitor` in `App/Lifecycle/` that translates AppKit ingress into two atomic `@Observable` stores: `AppLifecycleStore` and `WindowLifecycleStore`. Split app-level events out of pane-runtime hosting, remove global bus-post helpers, route user-triggered workspace changes through validated `PaneActionCommand`, route runtime work through `RuntimeCommand`, and move Ghostty runtime outputs onto the correct fact/command boundaries.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI `@Observable`, Swift Testing, existing `PaneActionCommand` + `ActionValidator` pipeline, `RuntimeCommand`, `PaneRuntimeEventBus`, `mise`

---

## File Structure Map

### New files

- `Sources/AgentStudio/App/Lifecycle/ApplicationLifecycleMonitor.swift`
  Thin AppKit ingress adapter. Owns notification/delegate ingress only. Mutates lifecycle stores. Must preserve synchronous terminate handling.
- `Sources/AgentStudio/App/Lifecycle/AppLifecycleStore.swift`
  `@Observable` atomic store for app-wide lifecycle state (`isActive`, `isTerminating`).
- `Sources/AgentStudio/App/Lifecycle/WindowLifecycleStore.swift`
  `@Observable` atomic store for per-window lifecycle state and focused/key window identity.
- `Sources/AgentStudio/App/Events/AppEvent.swift`
  App-level notification enum after split from pane runtime hosting.
- `Sources/AgentStudio/App/Events/AppEventBus.swift`
  App-level bus definition only, no global free-post helpers.
- `Tests/AgentStudioTests/App/Lifecycle/ApplicationLifecycleMonitorTests.swift`
  Covers ingress-to-store mutation, including synchronous terminate path.
- `Tests/AgentStudioTests/App/Lifecycle/AppLifecycleStoreTests.swift`
  Covers store ownership, `private(set)` mutation surface, and app-level state transitions.
- `Tests/AgentStudioTests/App/Lifecycle/WindowLifecycleStoreTests.swift`
  Covers key/focused window state transitions.

### Likely modified files

- `Sources/AgentStudio/App/AppDelegate.swift`
  Composition root wiring for lifecycle stores + monitor. Existing app-event subscribers pruned or rerouted.
- `Sources/AgentStudio/App/MainSplitViewController.swift`
  Remove direct lifecycle observation; consume lifecycle state or narrow callbacks only.
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
  Remove command-shaped `AppEventBus` consumption; add direct validated command routing where needed.
- `Sources/AgentStudio/App/AppCommand.swift`
  Add any missing explicit command surface needed to eliminate command-shaped `AppEventBus` usage.
- `Sources/AgentStudio/Core/Actions/ActionResolver.swift`
  Resolve any new `AppCommand` cases into validated `PaneActionCommand`s.
- `Sources/AgentStudio/Core/PaneRuntime/Events/EventChannels.swift`
  Leave `PaneRuntimeEventBus` here; remove `AppEvent`, `AppEventBus`, `GhosttyEventBus`, and global post helpers from this file.
- `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
  Replace custom `postAppEvent(...)` closures for command-shaped actions with `CommandDispatcher` routing.
- `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
  Replace any command-shaped app-event posting with direct command or app-boundary APIs as appropriate. Keep true app-intent/fact cases only if they still earn the boundary.
- `Sources/AgentStudio/App/PaneCoordinator.swift`
  Revisit fact-shaped app-event emissions such as `worktreeBellRang(...)` during the final AppEvent shrink pass.
- `Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift`
  Remove direct AppKit lifecycle listeners; route lifecycle through stores. Reclassify Ghostty outputs.
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
  Replace `postGhosttyEvent(...)` with the new runtime fact pathway.
- `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`
  Consume Ghostty fact outputs via the new boundary instead of `GhosttyEventBus`.
- `Sources/AgentStudio/Features/Terminal/Views/AgentStudioTerminalView.swift`
  Remove Ghostty mixed-bus consumption for command-shaped flows; consume the correct direct/runtime path instead.
- `Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift`
  Remove direct AppKit lifecycle notification subscription; react to lifecycle store state.
- `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
  Same as above for drawer drop-target lifecycle behavior.
- `Sources/AgentStudio/Core/Views/ManagementModeDragShield.swift`
  Replace `managementModeChanged` bus subscription with direct `@Observable` state consumption if the existing `ManagementModeMonitor.shared` binding already covers the behavior.
- `Sources/AgentStudio/App/ManagementModeMonitor.swift`
  Reclassify `managementModeChanged` / `refocusTerminalRequested`.
- `AGENTS.md`
  Update coordination plane rules and architecture reading guide.
- `docs/architecture/README.md`
  Update plane decision table and lifecycle boundary ownership.

### Existing tests to update

- `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`
- `Tests/AgentStudioTests/App/AppCommandTests.swift`
- `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`
- `Tests/AgentStudioTests/App/ManagementModeTests.swift`

### Architecture docs to check while implementing

- `docs/architecture/component_architecture.md`
- `docs/architecture/pane_runtime_architecture.md`
- `docs/architecture/pane_runtime_eventbus_design.md`
- `docs/architecture/workspace_data_architecture.md`
- `docs/architecture/window_system_design.md`
- `docs/architecture/directory_structure.md`
- `docs/superpowers/specs/2026-03-21-appkit-lifecycle-command-event-boundaries-design.md`

---

### Task 1: Add Lifecycle Stores And Monitor Skeleton

**Files:**
- Create: `Sources/AgentStudio/App/Lifecycle/AppLifecycleStore.swift`
- Create: `Sources/AgentStudio/App/Lifecycle/WindowLifecycleStore.swift`
- Create: `Sources/AgentStudio/App/Lifecycle/ApplicationLifecycleMonitor.swift`
- Test: `Tests/AgentStudioTests/App/Lifecycle/AppLifecycleStoreTests.swift`
- Test: `Tests/AgentStudioTests/App/Lifecycle/WindowLifecycleStoreTests.swift`
- Test: `Tests/AgentStudioTests/App/Lifecycle/ApplicationLifecycleMonitorTests.swift`

- [ ] **Step 1: Write failing lifecycle store tests**

```swift
@Test
func appLifecycleStore_startsInactiveAndNotTerminating() {
    let store = AppLifecycleStore()
    #expect(store.isActive == false)
    #expect(store.isTerminating == false)
}

@Test
func windowLifecycleStore_tracksFocusedWindow() {
    let store = WindowLifecycleStore()
    let windowId = UUID()

    store.recordWindowRegistered(windowId)
    store.recordWindowBecameKey(windowId)

    #expect(store.keyWindowId == windowId)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=.build-agent-plan swift test --build-path .build-agent-plan --filter 'AppLifecycleStoreTests|WindowLifecycleStoreTests|ApplicationLifecycleMonitorTests'`

Expected: FAIL because the lifecycle store and monitor files do not exist yet.

- [ ] **Step 3: Write minimal lifecycle stores**

```swift
@MainActor
@Observable
final class AppLifecycleStore {
    private(set) var isActive = false
    private(set) var isTerminating = false

    func setActive(_ isActive: Bool) { self.isActive = isActive }
    func markTerminating() { isTerminating = true }
}
```

Implement `WindowLifecycleStore` with:
- `private(set)` focused/key window state
- explicit store mutation methods
- no direct AppKit dependency

- [ ] **Step 4: Write minimal monitor skeleton**

```swift
@MainActor
final class ApplicationLifecycleMonitor {
    private let appLifecycleStore: AppLifecycleStore
    private let windowLifecycleStore: WindowLifecycleStore

    init(
        appLifecycleStore: AppLifecycleStore,
        windowLifecycleStore: WindowLifecycleStore
    ) {
        self.appLifecycleStore = appLifecycleStore
        self.windowLifecycleStore = windowLifecycleStore
    }
}
```

Do not add unrelated logic yet. Keep it ingress-only.

- [ ] **Step 5: Run focused tests to verify they pass**

Run: `SWIFT_BUILD_DIR=.build-agent-plan swift test --build-path .build-agent-plan --filter 'AppLifecycleStoreTests|WindowLifecycleStoreTests|ApplicationLifecycleMonitorTests'`

Expected: PASS for the new lifecycle store and monitor tests.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/App/Lifecycle Tests/AgentStudioTests/App/Lifecycle
git commit -m "feat: add lifecycle stores and monitor skeleton"
```

---

### Task 2: Wire AppDelegate As Composition Root And Preserve Synchronous Termination

**Files:**
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift`
- Modify: `Tests/AgentStudioTests/App/Lifecycle/ApplicationLifecycleMonitorTests.swift`
- Test: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`

- [ ] **Step 1: Write failing tests for composition-root ownership and terminate timing**

```swift
@Test
func applicationLifecycleMonitor_marksTerminationSynchronously() {
    let appStore = AppLifecycleStore()
    let windowStore = WindowLifecycleStore()
    let monitor = ApplicationLifecycleMonitor(
        appLifecycleStore: appStore,
        windowLifecycleStore: windowStore
    )

    monitor.handleApplicationWillTerminate()

    #expect(appStore.isTerminating == true)
}
```

Add/update an architecture test asserting:
- lifecycle types live under `Sources/AgentStudio/App/Lifecycle/`
- `MainSplitViewController.swift` no longer owns direct lifecycle ingress

- [ ] **Step 2: Run focused tests to verify they fail**

Run: `SWIFT_BUILD_DIR=.build-agent-plan swift test --build-path .build-agent-plan --filter 'ApplicationLifecycleMonitorTests|CoordinationPlaneArchitectureTests'`

Expected: FAIL because the monitor does not yet provide the synchronous ingress or composition-root wiring behavior.

- [ ] **Step 3: Wire lifecycle stores and monitor in AppDelegate**

Implementation notes:
- `AppDelegate` creates `AppLifecycleStore`, `WindowLifecycleStore`, and `ApplicationLifecycleMonitor`
- `AppDelegate` remains composition root
- `ApplicationLifecycleMonitor` must expose a synchronous termination ingress

Suggested shape:

```swift
private var appLifecycleStore: AppLifecycleStore!
private var windowLifecycleStore: WindowLifecycleStore!
private var applicationLifecycleMonitor: ApplicationLifecycleMonitor!
```

- [ ] **Step 4: Move termination ownership to the lifecycle boundary**

Replace the direct `willTerminateNotification` ownership in `MainSplitViewController` with lifecycle-bound coordination:
- `ApplicationLifecycleMonitor` owns the ingress
- `MainSplitViewController` receives a narrow callback or observes typed state
- synchronous save behavior is preserved

- [ ] **Step 5: Run focused tests**

Run: `SWIFT_BUILD_DIR=.build-agent-plan swift test --build-path .build-agent-plan --filter 'ApplicationLifecycleMonitorTests|CoordinationPlaneArchitectureTests'`

Expected: PASS. The synchronous termination assertion must pass without wall-clock waiting.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/App/AppDelegate.swift Sources/AgentStudio/App/MainSplitViewController.swift Tests/AgentStudioTests/App/Lifecycle Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift
git commit -m "feat: wire lifecycle monitor through app delegate"
```

---

### Task 3: Migrate UI And Runtime Lifecycle Consumers Off NotificationCenter

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Test: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`

- [ ] **Step 1: Extend the NotificationCenter allowlist test to expect only lifecycle-bound ingress**

Update the guard test so it fails until the direct listeners in the view/runtime files are removed.

- [ ] **Step 2: Run the guard test to verify it fails**

Run: `SWIFT_BUILD_DIR=.build-agent-plan swift test --build-path .build-agent-plan --filter CoordinationPlaneArchitectureTests`

Expected: FAIL because `Ghostty.swift`, `TerminalSplitContainer.swift`, and `DrawerPanel.swift` still consume `NotificationCenter` directly.

- [ ] **Step 3: Replace direct listeners with lifecycle store consumption**

Implementation notes:
- `Ghostty.swift` should react to `AppLifecycleStore.isActive`
- `TerminalSplitContainer.swift` should clear local drop state from typed lifecycle observation
- `DrawerPanel.swift` should do the same
- these files should no longer own AppKit lifecycle ingress

- [ ] **Step 4: Run focused tests**

Run: `SWIFT_BUILD_DIR=.build-agent-plan swift test --build-path .build-agent-plan --filter CoordinationPlaneArchitectureTests`

Expected: PASS with the lifecycle allowlist narrowed to the monitor boundary and any explicitly retained synchronous ingress site.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift
git commit -m "refactor: route lifecycle consumers through lifecycle stores"
```

---

### Task 4: Split EventChannels And Remove Global Bus-Post Helpers

**Files:**
- Modify: `Sources/AgentStudio/Core/PaneRuntime/Events/EventChannels.swift`
- Create: `Sources/AgentStudio/App/Events/AppEvent.swift`
- Create: `Sources/AgentStudio/App/Events/AppEventBus.swift`
- Modify: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`

- [ ] **Step 1: Write failing architecture tests for file split**

Add assertions that:
- `EventChannels.swift` no longer contains `enum AppEvent`
- `EventChannels.swift` no longer contains `postAppEvent`
- `EventChannels.swift` no longer contains `postGhosttyEvent`
- `AppEvent.swift` and `AppEventBus.swift` exist under `Sources/AgentStudio/App/Events/`

- [ ] **Step 2: Run the guard test to verify it fails**

Run: `SWIFT_BUILD_DIR=.build-agent-plan swift test --build-path .build-agent-plan --filter CoordinationPlaneArchitectureTests`

Expected: FAIL because the split has not happened yet.

- [ ] **Step 3: Split EventChannels.swift**

Implementation notes:
- keep `PaneRuntimeEventBus` in `Core/PaneRuntime/Events/EventChannels.swift`
- move `AppEvent` to `App/Events/AppEvent.swift`
- move `AppEventBus` to `App/Events/AppEventBus.swift`
- remove the free global helper functions

- [ ] **Step 4: Replace helper calls with owned bus/boundary APIs**

Do not reintroduce new global free-post helpers. Call sites should move toward:
- direct command dispatch
- direct store/coordinator methods
- or a clearly owned app-event API if a true app-level event remains justified

- [ ] **Step 5: Run focused tests**

Run: `SWIFT_BUILD_DIR=.build-agent-plan swift test --build-path .build-agent-plan --filter CoordinationPlaneArchitectureTests`

Expected: PASS with the split validated structurally.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Core/PaneRuntime/Events/EventChannels.swift Sources/AgentStudio/App/Events Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift
git commit -m "refactor: split app events from pane runtime event hosting"
```

---

### Task 5: Reclassify Ghostty Signals And Remove The Mixed GhosttyEventBus

**Files:**
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/Ghostty.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Views/AgentStudioTerminalView.swift`
- Modify: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`

- [ ] **Step 1: Write failing tests for Ghostty mixed-bus removal**

Add a source-guard test asserting:
- `GhosttyEventBus` is removed or reduced to a justified fact-only boundary
- command-shaped Ghostty signals no longer travel through a generic event bus

- [ ] **Step 2: Run the guard test to verify it fails**

Run: `SWIFT_BUILD_DIR=.build-agent-plan swift test --build-path .build-agent-plan --filter CoordinationPlaneArchitectureTests`

Expected: FAIL because Ghostty still uses a mixed event channel.

- [ ] **Step 3: Re-route fact-shaped Ghostty outputs**

Implementation notes:
- route renderer-health and working-directory facts through the established runtime fact pathway
- prefer `PaneRuntimeEventBus`/runtime envelopes over a Ghostty-only global bus

- [ ] **Step 4: Re-route command-shaped Ghostty outputs**

Implementation notes:
- `newWindowRequested` and `closeSurface(...)` must stop looking like generic bus events
- route them through a typed boundary that the coordinator/app layer owns
- if they remain runtime-originated facts, make that explicit in the runtime envelope taxonomy rather than leaving them on a mixed free-floating bus

- [ ] **Step 5: Run focused tests**

Run: `SWIFT_BUILD_DIR=.build-agent-plan swift test --build-path .build-agent-plan --filter 'CoordinationPlaneArchitectureTests|GhosttyActionRoutingTests|PaneCoordinatorTests'`

Expected: PASS with no remaining mixed Ghostty coordination channel.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Ghostty Sources/AgentStudio/Features/Terminal/Views/AgentStudioTerminalView.swift Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift
git commit -m "refactor: remove mixed ghostty event bus"
```

---

### Task 6: Eliminate Command-Shaped AppEventBus Usage From User Actions

**Files:**
- Modify: `Sources/AgentStudio/App/AppCommand.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionResolver.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift`
- Modify: `Sources/AgentStudio/App/MainWindowController.swift`
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/DraggableTabBarHostingView.swift`
- Modify: `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`
- Modify: `Tests/AgentStudioTests/App/AppCommandTests.swift`
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift`
- Modify: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`

- [ ] **Step 1: Write failing tests for command-shaped AppEvent removal**

Add/extend tests so they fail until:
- command bar tab/pane selection stops posting `selectTabById`
- move/extract/repair/sidebar/filter/webview/refocus command paths stop using `AppEventBus`
- user-triggered workspace actions still validate through `ActionValidator`

Useful test targets:
- `CommandBarDataSourceTests`
- `AppCommandTests`
- `PaneTabViewControllerCommandTests`
- `CoordinationPlaneArchitectureTests`

Also add assertions that known command-shaped `AppEvent` enum cases are removed once migrated.

- [ ] **Step 2: Run focused tests to verify they fail**

Run: `SWIFT_BUILD_DIR=.build-agent-plan swift test --build-path .build-agent-plan --filter 'AppCommandTests|CommandBarDataSourceTests|PaneTabViewControllerCommandTests|CoordinationPlaneArchitectureTests'`

Expected: FAIL because command-shaped `AppEventBus` routing still exists.

- [ ] **Step 3: Add any missing explicit command surface**

If the current `AppCommand` set cannot represent direct validated routing for selection/focus/sidebar/webview actions, add targeted command cases rather than falling back to app events.

Examples of acceptable outcomes:
- a new targetable app command for selecting a tab directly
- a new targetable app command for focusing a pane directly
- direct validated action routing inside the relevant command handler when adding a new `AppCommand` would be redundant

Constraint:
- all user-triggered workspace changes must still pass through `ActionValidator`

- [ ] **Step 4: Migrate command-bar and UI click flows off AppEventBus**

Replace `postAppEvent(...)` for command-shaped user actions with:
- `CommandDispatcher.shared.dispatch(...)`
- targeted command dispatch
- or direct validated `PaneActionCommand` execution only where that is already the established command boundary

- [ ] **Step 5: Keep only true facts or justified app-intent notifications on AppEventBus**

Revisit the remaining enum cases and keep only the ones that still earn the boundary:
- likely fact/event shaped: `terminalProcessTerminated`, `worktreeBellRang`, `managementModeChanged`
- review the repo/folder/sign-in/refresh path carefully and document the final classification
- for `managementModeChanged`, prefer direct `@Observable` consumption over a bus subscription when the existing shared monitor already provides the needed state

- [ ] **Step 6: Run focused tests**

Run: `SWIFT_BUILD_DIR=.build-agent-plan swift test --build-path .build-agent-plan --filter 'AppCommandTests|CommandBarDataSourceTests|PaneTabViewControllerCommandTests|CoordinationPlaneArchitectureTests|ManagementModeTests'`

Expected: PASS with user-triggered workspace actions still validator-gated.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/App/AppCommand.swift Sources/AgentStudio/Core/Actions/ActionResolver.swift Sources/AgentStudio/App/Panes/PaneTabViewController.swift Sources/AgentStudio/Features/CommandBar/CommandBarDataSource.swift Sources/AgentStudio/App/MainWindowController.swift Sources/AgentStudio/App/AppDelegate.swift Sources/AgentStudio/App/MainSplitViewController.swift Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift Sources/AgentStudio/Core/Views/DraggableTabBarHostingView.swift Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift Tests/AgentStudioTests/App/AppCommandTests.swift Tests/AgentStudioTests/Features/CommandBar/CommandBarDataSourceTests.swift Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift
git commit -m "refactor: route user commands through validated command boundaries"
```

---

### Task 7: Update Docs And Final Guardrails

**Files:**
- Modify: `AGENTS.md`
- Modify: `docs/architecture/README.md`
- Modify: `docs/architecture/pane_runtime_architecture.md`
- Modify: `docs/architecture/pane_runtime_eventbus_design.md`
- Modify: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`

- [ ] **Step 1: Write failing source/doc guard assertions**

Add/extend tests so they assert:
- `AGENTS.md` includes a coordination-plane decision table or equivalent explicit guidance
- `docs/architecture/README.md` includes the same plane split
- lifecycle stores are documented as `@Observable` atomic stores
- the old `AppCommand -> AppEventBus -> controller -> PaneActionCommand` chain is documented as the thing being removed

- [ ] **Step 2: Run the guard tests to verify they fail**

Run: `SWIFT_BUILD_DIR=.build-agent-plan swift test --build-path .build-agent-plan --filter CoordinationPlaneArchitectureTests`

Expected: FAIL until the docs are updated to match the implemented architecture.

- [ ] **Step 3: Update docs with the final architecture**

Required content:
- workspace mutation -> `PaneActionCommand`
- runtime command -> `RuntimeCommand`
- runtime/system fact -> `PaneRuntimeEventBus`
- app-level notification that is not a command -> `AppEventBus`
- AppKit/macOS lifecycle ingress -> `ApplicationLifecycleMonitor`
- UI-only local state -> local view/controller state, not bus or `NotificationCenter`
- explicit statement that user-triggered workspace actions must remain validator-gated

- [ ] **Step 4: Run full project verification**

Run:

```bash
AGENT_RUN_ID=appkit-lifecycle-boundary mise run test
mise run lint
```

Expected:
- `mise run test`: PASS, full suite
- `mise run lint`: PASS, zero violations and boundary checks pass

- [ ] **Step 5: Record final evidence in the work summary**

Capture:
- exit codes
- total test counts
- WebKit serialized suite counts
- any skipped suites required by repo config

- [ ] **Step 6: Commit**

```bash
git add AGENTS.md docs/architecture/README.md docs/architecture/pane_runtime_architecture.md docs/architecture/pane_runtime_eventbus_design.md Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift
git commit -m "docs: clarify lifecycle and command event architecture"
```

---

## Notes For The Implementer

- Do not add wall-clock sleeps to tests. Use direct state transitions, synchronous ingress methods, or existing bounded test helpers.
- Do not let `ApplicationLifecycleMonitor` accumulate unrelated state ownership. It is ingress/sequencing only.
- Do not leave command-shaped flows on `AppEventBus` just because they are convenient. If the user asked for work, it belongs on a command boundary.
- Do not route runtime commands through any bus.
- If a Ghostty output remains event-shaped, prefer the established runtime fact infrastructure over a feature-global side bus.
- If a hosting decision stays as-is after review, document why it still earns its place.
