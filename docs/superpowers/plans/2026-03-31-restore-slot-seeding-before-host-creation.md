# Restore Slot Seeding Before Host Creation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the restart-time `ViewRegistry.slot(for:) lazy fallback ... ensureSlot was not called` crash by seeding all restored pane slots before any `NSHostingView<SingleTabContent>` can render.

**Architecture:** The fix is a startup-order correction, not a change to the slot model. `WorkspaceStore.restore()` already reconstructs canonical pane state; immediately after `ViewRegistry` is created, AppDelegate seeds one `PaneViewSlot` for every pane already present in `store.panes`, including drawer children, before `MainWindowController` or `PaneTabViewController` are created. The existing lazy fallback remains a safety net, but normal restart must never depend on it.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI, Observation (`@Observable`), Swift Testing (`Testing`)

---

## Problem Model

### Current crash path

```text
AppDelegate.bootLoadCanonicalStore()
  -> store.restore()
  -> restored panes/tabs now exist in WorkspaceStore

AppDelegate.bootEstablishRuntimeBus()
  -> viewRegistry = ViewRegistry()
  -> NO slots seeded yet

AppDelegate creates MainWindowController
  -> PaneTabViewController.viewDidLoad()
  -> syncTabContentHosts()
  -> NSHostingView<SingleTabContent> created

SwiftUI renders FlatPaneStripContent
  -> viewRegistry.slot(for: paneId)
  -> slot does not exist
  -> assertionFailure in ViewRegistry.slot(for:)
```

### Correct startup invariant

```text
1. store.restore()
2. viewRegistry = ViewRegistry()
3. seed slots for every restored paneId in store.panes.keys
4. create MainWindowController / PaneTabViewController / NSHostingView
5. SwiftUI reads slot(for:).host
   -> slot already exists
6. PaneCoordinator.restoreAllViews() later registers hosts into those slots
```

### Why `store.panes.keys` is the authoritative source

Use `store.panes.keys`, not `store.tabs.flatMap(\.paneIds)`.

Reason:
- `store.panes.keys` includes layout panes and drawer child panes
- `tab.paneIds` only covers panes directly in tab layouts
- drawer panes are first-class pane models and must have slots too

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/AgentStudio/App/AppDelegate.swift` | Modify | Seed restored pane slots immediately after `viewRegistry` is created and before window/controller creation |
| `Sources/AgentStudio/App/Panes/ViewRegistry.swift` | Modify | Add tiny DEBUG-only test accessor for seeded slot IDs |
| `Tests/AgentStudioTests/App/AppDelegateSlotSeedingTests.swift` | Create | Direct tests for restored-pane slot seeding, including drawer panes |
| `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift` | Modify | Add integration-style restart test proving controller setup with restored panes no longer depends on lazy fallback |
| `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift` | Modify | Assert AppDelegate owns restored-slot seeding at boot |

---

### Task 1: Add Failing Tests For Restore Slot Seeding

**Files:**
- Create: `Tests/AgentStudioTests/App/AppDelegateSlotSeedingTests.swift`
- Modify: `Sources/AgentStudio/App/Panes/ViewRegistry.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`

- [ ] **Step 1: Add a DEBUG-only slot ID accessor to ViewRegistry**

Update `Sources/AgentStudio/App/Panes/ViewRegistry.swift` by appending:

```swift
#if DEBUG
    extension ViewRegistry {
        var slotPaneIdsForTesting: Set<UUID> {
            Set(slots.keys)
        }
    }
#endif
```

- [ ] **Step 2: Write the direct failing test file**

Create `Tests/AgentStudioTests/App/AppDelegateSlotSeedingTests.swift`:

```swift
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct AppDelegateSlotSeedingTests {
    private func makePersistedStoreWithDrawer() throws -> (WorkspaceStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-slot-seeding-\(UUID().uuidString)")
        let persistor = WorkspacePersistor(workspacesDir: tempDir)

        let initialStore = WorkspaceStore(persistor: persistor)
        let pane = initialStore.createPane(
            source: .floating(workingDirectory: tempDir, title: "Root"),
            provider: .zmx
        )
        let tab = Tab(paneId: pane.id, name: "Root")
        initialStore.appendTab(tab)
        _ = initialStore.addDrawerPane(to: pane.id)
        initialStore.flush()

        let restoredStore = WorkspaceStore(persistor: persistor)
        restoredStore.restore()
        return (restoredStore, tempDir)
    }

    @Test
    func seedSlotsForRestoredPanes_seedsEveryRestoredPaneId_includingDrawerChildren() throws {
        let (store, tempDir) = try makePersistedStoreWithDrawer()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appDelegate = AppDelegate()
        appDelegate.store = store
        appDelegate.viewRegistry = ViewRegistry()

        appDelegate.seedSlotsForRestoredPanes()

        #expect(appDelegate.viewRegistry.slotPaneIdsForTesting == Set(store.panes.keys))
    }
}
```

- [ ] **Step 3: Add an integration-style restart test**

Append to `Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift`:

```swift
    @Test
    func restoredPanes_seedSlots_beforeTabHostsAreCreated() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-launch-restore-slot-seeding-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let persistor = WorkspacePersistor(workspacesDir: tempDir)
        let initialStore = WorkspaceStore(persistor: persistor)
        let pane = initialStore.createPane(
            source: .floating(workingDirectory: tempDir, title: "Restored"),
            provider: .zmx
        )
        let tab = Tab(paneId: pane.id, name: "Restored")
        initialStore.appendTab(tab)
        initialStore.flush()

        let restoredStore = WorkspaceStore(persistor: persistor)
        restoredStore.restore()

        let viewRegistry = ViewRegistry()
        for paneId in restoredStore.panes.keys {
            viewRegistry.ensureSlot(for: paneId)
        }

        let runtime = SessionRuntime(store: restoredStore)
        let appLifecycleStore = AppLifecycleStore()
        let windowLifecycleStore = WindowLifecycleStore()
        let applicationLifecycleMonitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore
        )
        let surfaceManager = LaunchCapturingSurfaceManager()
        let coordinator = PaneCoordinator(
            store: restoredStore,
            viewRegistry: viewRegistry,
            runtime: runtime,
            surfaceManager: surfaceManager,
            runtimeRegistry: .shared,
            windowLifecycleStore: windowLifecycleStore
        )
        let executor = ActionExecutor(coordinator: coordinator, store: restoredStore)

        let controller = PaneTabViewController(
            store: restoredStore,
            applicationLifecycleMonitor: applicationLifecycleMonitor,
            appLifecycleStore: appLifecycleStore,
            executor: executor,
            tabBarAdapter: TabBarAdapter(store: restoredStore),
            viewRegistry: viewRegistry
        )

        let window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1200, height: 800),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        window.contentView?.layoutSubtreeIfNeeded()

        #expect(viewRegistry.slotPaneIdsForTesting == Set(restoredStore.panes.keys))
    }
```

- [ ] **Step 4: Run the targeted tests to verify failure**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "AppDelegateSlotSeedingTests"
```

Expected: FAIL because `seedSlotsForRestoredPanes()` does not exist yet and `slotPaneIdsForTesting` does not exist yet.

- [ ] **Step 5: Run the launch-restore suite to verify it still reproduces the restart gap**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerLaunchRestoreTests"
```

Expected: FAIL to compile from missing `slotPaneIdsForTesting` / `seedSlotsForRestoredPanes`, confirming the tests are targeting the intended startup seam.

---

### Task 2: Seed Restored Pane Slots During App Boot

**Files:**
- Modify: `Sources/AgentStudio/App/AppDelegate.swift`
- Modify: `Sources/AgentStudio/App/Panes/ViewRegistry.swift`

- [ ] **Step 1: Add the internal seeding helper to AppDelegate**

Update `Sources/AgentStudio/App/AppDelegate.swift` by adding this method near the other boot helpers:

```swift
    @MainActor
    func seedSlotsForRestoredPanes() {
        guard let viewRegistry, let store else { return }
        for paneId in store.panes.keys {
            viewRegistry.ensureSlot(for: paneId)
        }
        RestoreTrace.log("seedSlotsForRestoredPanes count=\(store.panes.count)")
    }
```

- [ ] **Step 2: Call the helper immediately after ViewRegistry is created**

In `bootEstablishRuntimeBus(...)`, change:

```swift
        viewRegistry = ViewRegistry()
```

to:

```swift
        viewRegistry = ViewRegistry()
        seedSlotsForRestoredPanes()
```

- [ ] **Step 3: Keep the helper placement before any window/controller creation**

Verify in `applicationDidFinishLaunching(_:)` that:
- `WorkspaceBootSequence.run { ... }` completes
- then `MainWindowController(...)` is created afterwards

No code change needed if that ordering is unchanged, but do not move the seeding helper anywhere later in boot.

- [ ] **Step 4: Run the direct slot-seeding tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "AppDelegateSlotSeedingTests"
```

Expected: PASS

- [ ] **Step 5: Run the launch-restore tests**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneTabViewControllerLaunchRestoreTests"
```

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/App/AppDelegate.swift \
       Sources/AgentStudio/App/Panes/ViewRegistry.swift \
       Tests/AgentStudioTests/App/AppDelegateSlotSeedingTests.swift \
       Tests/AgentStudioTests/App/PaneTabViewControllerLaunchRestoreTests.swift
git commit -m "fix: seed restored pane slots before host creation"
```

---

### Task 3: Lock The Boot Invariant In Architecture Tests

**Files:**
- Modify: `Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift`

- [ ] **Step 1: Add an AppDelegate source assertion for restored slot seeding**

In `lifecycleCompositionRoot_staysInAppDelegate()`, add:

```swift
        #expect(sources.appDelegateSource.contains("seedSlotsForRestoredPanes()"))
```

and:

```swift
        #expect(sources.appDelegateSource.contains("func seedSlotsForRestoredPanes()"))
```

- [ ] **Step 2: Add an assertion that ViewRegistry still owns `ensureSlot`**

Add:

```swift
        #expect(sources.viewRegistrySource.contains("func ensureSlot(for paneId: UUID)"))
```

This ensures the boot fix stays aligned with the slot-lifecycle API instead of introducing a separate startup-only slot mechanism.

- [ ] **Step 3: Run the architecture suite**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CoordinationPlaneArchitectureTests"
```

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Tests/AgentStudioTests/Architecture/CoordinationPlaneArchitectureTests.swift
git commit -m "test: lock restored slot seeding boot invariant"
```

---

### Task 4: Final Verification

**Files:**
- Verify only

- [ ] **Step 1: Full build**

Run:

```bash
AGENT_RUN_ID=slot-seeding-fix mise run build
```

Expected: PASS

- [ ] **Step 2: Full test suite**

Run:

```bash
AGENT_RUN_ID=slot-seeding-fix mise run test
```

Expected: PASS — report pass/fail counts from the runner

- [ ] **Step 3: Lint**

Run:

```bash
mise run lint
```

Expected: PASS with zero violations

- [ ] **Step 4: Confirm no startup path still relies on lazy fallback**

Run:

```bash
rg -n "slot\\(for:.*ensureSlot was not called|seedSlotsForRestoredPanes|store\\.restore\\(" Sources/AgentStudio Tests/AgentStudioTests -g '*.swift'
```

Expected:
- `seedSlotsForRestoredPanes` present in `AppDelegate`
- lazy fallback message remains only in `ViewRegistry` as a safety net
- no other startup workaround added

- [ ] **Step 5: Commit if verification required fixes**

---

## Self-Review

### Spec coverage

- Crash traced to startup ordering: covered by Task 2.
- All panes including drawer panes must be seeded: covered by seeding from `store.panes.keys` and direct drawer test in Task 1.
- Keep lazy fallback only as safety net: preserved; no plan step removes it.
- Fix should be stable and boot-level, not view-level: accomplished by AppDelegate seeding, not `syncTabContentHosts()`.

### Placeholder scan

- No `TODO` / `TBD`.
- Every task lists exact files.
- Every code step includes concrete code.
- Every verification step includes exact commands and expected results.

### Type consistency

- `seedSlotsForRestoredPanes()` is used consistently in code and tests.
- `slotPaneIdsForTesting` is the only proposed DEBUG accessor and is referenced consistently.

---

Plan complete and saved to `docs/superpowers/plans/2026-03-31-restore-slot-seeding-before-host-creation.md`. Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
