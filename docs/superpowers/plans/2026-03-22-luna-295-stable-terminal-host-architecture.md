# Stable Pane Host And Terminal Mount Separation Implementation Plan

> **Status:** Tasks 0-4 IMPLEMENTED on `luna-295-stable-terminal-host`. Tasks 5-6 (doc updates + full verification) remain.
>
> **For agentic workers:** Skip to Task 5. Tasks 1-4 are complete — the host/mount cutover has landed. Do not re-execute completed tasks.

**Goal:** Replace pane-kind-specific host views with one universal stable pane host and split terminal content from Ghostty surface mounting so split/layout churn, placeholder swaps, repair, and restore no longer couple pane identity to renderer parentage.

**Architecture:** Promote the current implicit `PaneView` shell into an explicit universal `PaneHostView` used by every pane kind. Each pane kind mounts content into that host by composition; terminal content becomes `TerminalPaneMountView`, which owns `GhosttyMountView` as the only app-local parent of `Ghostty.SurfaceView`. This plan is a hard cutover of the host/mount model only; the deeper Ghostty runtime isolation split is deferred to a follow-up plan so we can validate the pane-shell change independently.

**Tech Stack:** Swift 6.2, AppKit, SwiftUI hosting, Swift Testing, Ghostty/libghostty, zmx, mise, swift-format, swiftlint

---

## Preconditions

This plan assumes implementation starts from a branch that already includes the post-`origin/main` lifecycle-store and geometry-gating foundation:

- `WindowLifecycleStore.terminalContainerBounds`
- `WindowLifecycleStore.isLaunchLayoutSettled`
- `WindowRestoreBridge`
- geometry-gated zmx startup / placeholder flow from `origin/main`

If those changes are not present, stop and merge/rebase first. This plan is a hard cutover on top of that newer base. It does **not** support the older callback-chain architecture.

## Task 0 Requirement

Before Task 1 begins, merge or rebase `origin/main` into the working branch and verify that the merged base builds and tests cleanly. This plan assumes the `origin/main` placeholder and lifecycle-store model is the starting point, not something recreated during implementation.

## Why This Plan Exists

The current codebase already shows two models:

- `WebviewPaneView` and `BridgePaneView` are effectively composition-based mounts inside a thin host base.
- `AgentStudioTerminalView` is the outlier. It fuses pane identity, Ghostty parenting, overlays, process lifecycle, geometry sync, focus forwarding, and repair behavior in one object.

That fusion is exactly where the current risk lives:

1. pane identity and renderer parentage are the same object
2. layout churn and structure churn are app-shell concerns
3. Ghostty mount, redraw, focus, occlusion, and size are renderer concerns
4. placeholder-to-live swap, repair, and undo currently have to reach into a pane host's internal terminal state instead of swapping mounted content cleanly

The design goal is not just to fix the current blank-pane bug. It is to make the system say, clearly:

- a pane exists because a stable host exists
- content is something mounted into that host
- terminal content is special because its embedded renderer needs an additional mount boundary

## Hard-Cutover Rules

These are non-negotiable implementation constraints:

1. No backward-compatibility shims.
2. No dual path where old pane-specific hosts and the new universal host coexist.
3. No typealias compatibility layer keeping `PaneView` alive after the cutover.
4. No wall-clock tests (`Task.sleep`) in test bodies.
5. No placeholder-as-host model after the cutover; placeholders become terminal content state mounted inside a host.
6. No plain `nonisolated async` methods used as fake background boundaries in Swift 6.2.
7. No `Task.detached` in the common runtime path unless a task must intentionally break structured concurrency and that reason is documented inline.
8. No host-kind access through raw downcasts from `ViewRegistry` storage.
9. No tests that assert internal method call counts when user-visible behavior can be asserted instead.

## Target Model

### Universal pane shell

```text
Split tree / ViewRegistry / focus / drag-drop / management mode
  -> PaneHostView   (stable identity for every pane kind)
       -> mounted content view
```

### Mounted content by pane kind

```text
PaneHostView
  -> WebviewPaneMountView
  -> BridgePaneMountView
  -> CodeViewerPaneMountView
  -> TerminalPaneMountView
```

### Terminal-specific layering

```text
PaneHostView
  -> TerminalPaneMountView
       -> GhosttyMountView
            -> Ghostty.SurfaceView
       -> terminal overlays / placeholder state
```

### Follow-up boundary

The Ghostty runtime isolation split is intentionally **not** part of this plan. It should happen in a follow-up plan immediately after the host/mount cutover lands so the two changesets can be validated independently.

### Mounted content contract

Every mounted content type conforms to an explicit host-facing protocol, `PaneMountedContent`.

- content interaction enable/disable forwarding for management mode
- first responder forwarding from host -> mount -> concrete responder
- optional custom hit-routing inside the mount
- teardown hooks for mounts that own controller/runtime resources
- typed access from `PaneHostView` for callers that need pane-kind-specific behavior

Minimum forwarding rules:

1. `PaneHostView` owns pane identity, management-mode shell behavior, and `swiftUIContainer`.
2. `PaneHostView` forwards content interaction suppression to the mount through one explicit contract.
3. First responder requests always enter through the host; mounts may forward further to renderer/web/document responders.
4. Custom hit testing stays mount-local; management-mode blocking stays host-local.
5. Mounted content views never appear in SwiftUI directly; `PaneViewRepresentable` bridges the host only.

### ViewRegistry access pattern

After the cutover, `ViewRegistry` stores hosts only.

- `view(for:)` returns `PaneHostView`
- typed helpers resolve mounted content from the host, not from a parallel registry map
- coordinator call sites that need pane-kind behavior obtain it via host -> typed mount accessors

Examples of the intended shape:

- `terminalMount(for:) -> TerminalPaneMountView?`
- `webviewMount(for:) -> WebviewPaneMountView?`
- `bridgeMount(for:) -> BridgePaneMountView?`

## New Invariants

1. `1 pane = 1 stable PaneHostView`.
2. `ViewRegistry` stores hosts only, never raw pane-kind mounts.
3. Pane-kind content is always mounted into a host by composition.
4. `TerminalPaneMountView` is mounted content, not the pane host.
5. `Ghostty.SurfaceView` is parented only under `GhosttyMountView`.
6. Placeholder, live terminal, repair, and retry are terminal content states inside one stable host.
7. Focus, occlusion, size, and redraw remain separate signals.
8. Old host classes do not survive behind wrappers or adapter layers.

## File Structure Map

### New / moved files

- Create: `Sources/AgentStudio/Core/Views/Panes/PaneHostView.swift`
  Universal stable pane shell. Owns pane id, management-mode host behavior, content slot, stable `swiftUIContainer`, and typed content mount accessors.
- Move: `Sources/AgentStudio/Core/Models/PaneView.swift` -> `Sources/AgentStudio/Core/Views/Panes/PaneHostView.swift`
  Hard cutover. The old host base is renamed and expanded; do not leave a compatibility type behind.
- Move: `Sources/AgentStudio/Features/Webview/Views/WebviewPaneView.swift` -> `Sources/AgentStudio/Features/Webview/Views/WebviewPaneMountView.swift`
  Webview mounted content only.
- Move: `Sources/AgentStudio/Features/Bridge/Views/BridgePaneView.swift` -> `Sources/AgentStudio/Features/Bridge/Views/BridgePaneMountView.swift`
  Bridge mounted content only.
- Move: `Sources/AgentStudio/Core/Views/CodeViewerPaneView.swift` -> `Sources/AgentStudio/Core/Views/CodeViewerPaneMountView.swift`
  Code viewer mounted content only.
- Move: `Sources/AgentStudio/Features/Terminal/Views/AgentStudioTerminalView.swift` -> `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`
  Terminal mounted content only.
- Move: `Sources/AgentStudio/Features/Terminal/Views/TerminalStatusPlaceholderView.swift` -> `Sources/AgentStudio/Features/Terminal/Hosting/TerminalStatusPlaceholderView.swift`
  Placeholder support subview owned by `TerminalPaneMountView`, not a mount and not a host.
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/GhosttyMountView.swift`
  Dedicated Ghostty surface parent and size/content-scale bridge boundary.

### Existing files to modify

- Modify: `Sources/AgentStudio/App/Panes/ViewRegistry.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/Core/Views/ManagementModeDragShield.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/TerminalPaneView.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/SplitTree.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/ActiveTabContent.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Views/SurfaceStartupOverlay.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift`
- Modify: `Sources/AgentStudio/Infrastructure/AppStyle.swift`
- Modify: `docs/architecture/README.md`
- Modify: `docs/architecture/appkit_swiftui_architecture.md`
- Modify: `docs/architecture/component_architecture.md`
- Modify: `docs/architecture/directory_structure.md`
- Modify: `docs/architecture/ghostty_surface_architecture.md`
- Modify: `docs/architecture/pane_runtime_architecture.md`
- Modify: `docs/architecture/pane_runtime_eventbus_design.md`
- Modify: `docs/architecture/session_lifecycle.md`
- Modify: `docs/architecture/swift_react_bridge_design.md`
- Modify: `AGENTS.md`

### Test files

- Create: `Tests/AgentStudioTests/Core/Views/Panes/PaneHostViewTests.swift`
- Create: `Tests/AgentStudioTests/Features/Webview/Views/WebviewPaneMountViewTests.swift`
- Create: `Tests/AgentStudioTests/Features/Bridge/Views/BridgePaneMountViewTests.swift`
- Create: `Tests/AgentStudioTests/Core/Views/CodeViewerPaneMountViewTests.swift`
- Create: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewTests.swift`
- Create: `Tests/AgentStudioTests/Features/Terminal/Hosting/GhosttyMountViewTests.swift`
- Create: `Tests/AgentStudioTests/App/TerminalHostReconciliationTests.swift`
- Modify: existing `PaneCoordinator*`, `PaneTabViewController*`, and `Luna295DirectZmxAttachIntegrationTests.swift`

---

### Task 1: Introduce Universal `PaneHostView` ✅ COMPLETE

**Files:**
- Create: `Sources/AgentStudio/Core/Views/Panes/PaneHostView.swift`
- Delete/Move: `Sources/AgentStudio/Core/Models/PaneView.swift`
- Modify: `Sources/AgentStudio/Core/Views/ManagementModeDragShield.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/TerminalPaneView.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/SplitTree.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanelOverlay.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/TerminalSplitContainer.swift`
- Modify: `Sources/AgentStudio/App/Panes/ViewRegistry.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Panes/PaneHostViewTests.swift`

- [ ] **Step 1: Write the failing host-contract tests**

```swift
@Test
@MainActor
func paneHost_preservesIdentityAcrossMountedContentSwaps() {
    let paneId = UUID()
    let host = PaneHostView(paneId: paneId)
    let firstMount = NSView(frame: .zero)
    let secondMount = NSView(frame: .zero)

    let hostIdentity = ObjectIdentifier(host)
    let containerIdentity = ObjectIdentifier(host.swiftUIContainer)

    host.mountContentView(firstMount)
    host.mountContentView(secondMount)

    #expect(ObjectIdentifier(host) == hostIdentity)
    #expect(ObjectIdentifier(host.swiftUIContainer) == containerIdentity)
    #expect(secondMount.superview === host.contentContainerViewForTesting)
}

@Test
@MainActor
func paneHost_managementModeShieldStaysOnHostNotMountedContent() {
    let host = PaneHostView(paneId: UUID())
    host.mountContentView(NSView(frame: .zero))

    #expect(host.interactionShieldForTesting != nil)
    #expect(host.contentContainerViewForTesting.subviews.count == 1)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneHostViewTests"`
Expected: FAIL with missing type / API errors.

- [ ] **Step 3: Implement `PaneHostView` as the universal shell**

Required behavior:

- own `paneId`
- own host-level `hitTest`, management-mode shielding, and stable `swiftUIContainer`
- own a dedicated content container subview
- expose `mountContentView(_:)` / `unmountContentView()`
- support typed inspection accessors used by `ViewRegistry`
- define the host-facing mounted-content contract for interaction suppression, responder forwarding, teardown, and optional hit-routing
- do not subclass per-pane content from this type anymore

- [ ] **Step 4: Hard-cut all split-tree code to `PaneHostView`**

Required behavior:

- `PaneLeafContainer` and `PaneViewRepresentable` consume `PaneHostView`
- `PaneSplitTree` becomes `SplitTree<PaneHostView>`
- remove `TerminalSplitTree` and `TerminalViewRepresentable` compatibility aliases
- drawer rendering paths also consume `PaneHostView`
- `ViewRegistry` stores `PaneHostView` instances only
- remove all remaining references to the old `PaneView` type

- [ ] **Step 5: Run focused tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneHostViewTests|PaneTabViewControllerCommandTests"`
Expected: PASS

- [x] **Step 6: Commit** ✅ COMPLETE

---

### Task 2: Convert Webview, Bridge, And Code Viewer To Mounted Content ✅ COMPLETE

**Files:**
- Move: `Sources/AgentStudio/Features/Webview/Views/WebviewPaneView.swift` -> `Sources/AgentStudio/Features/Webview/Views/WebviewPaneMountView.swift`
- Move: `Sources/AgentStudio/Features/Bridge/Views/BridgePaneView.swift` -> `Sources/AgentStudio/Features/Bridge/Views/BridgePaneMountView.swift`
- Move: `Sources/AgentStudio/Core/Views/CodeViewerPaneView.swift` -> `Sources/AgentStudio/Core/Views/CodeViewerPaneMountView.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/App/Panes/ViewRegistry.swift`
- Test: `Tests/AgentStudioTests/Features/Webview/Views/WebviewPaneMountViewTests.swift`
- Test: `Tests/AgentStudioTests/Features/Bridge/Views/BridgePaneMountViewTests.swift`
- Test: `Tests/AgentStudioTests/Core/Views/CodeViewerPaneMountViewTests.swift`

- [ ] **Step 1: Write failing composition tests for non-terminal pane kinds**

```swift
@Test
@MainActor
func createWebviewPane_registersHostWhoseMountedContentIsWebviewMount() {
    let host = try #require(makeWebviewHostForTesting())
    #expect(host.webviewMountViewForTesting != nil)
    #expect(host.terminalMountViewForTesting == nil)
}

@Test
@MainActor
func bridgePane_isRegisteredThroughHostNotMount() {
    let host = try #require(makeBridgeHostForTesting())
    #expect(host.bridgeMountViewForTesting != nil)
    #expect(host.contentContainerViewForTesting === host.bridgeMountViewForTesting?.superview)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WebviewPaneMountViewTests|BridgePaneMountViewTests|CodeViewerPaneMountViewTests"`
Expected: FAIL with missing type errors.

- [ ] **Step 3: Rename the existing pane-kind views into mounts**

Required behavior:

- `WebviewPaneMountView`, `BridgePaneMountView`, and `CodeViewerPaneMountView` become plain mounted content views
- they no longer represent the split-tree / registry host object
- existing controller/runtime ownership stays with the mount view
- each mount conforms to the host-facing content contract from Task 1

- [ ] **Step 4: Rewire pane creation through `PaneHostView`**

Required behavior:

- `PaneCoordinator+ViewLifecycle` creates the pane-kind mount first
- then creates/registers one `PaneHostView`
- then mounts the content into the host
- `ViewRegistry` typed helpers resolve from host -> mounted content
- teardown paths that currently depend on concrete view types are rewritten to ask the host for mounted content via typed accessors

- [ ] **Step 5: Run focused tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "WebviewPaneMountViewTests|BridgePaneMountViewTests|CodeViewerPaneMountViewTests|PaneCoordinatorRuntimeDispatchNonTerminalTests"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/Webview/Views/WebviewPaneMountView.swift \
  Sources/AgentStudio/Features/Bridge/Views/BridgePaneMountView.swift \
  Sources/AgentStudio/Core/Views/CodeViewerPaneMountView.swift \
  Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift \
  Sources/AgentStudio/App/Panes/ViewRegistry.swift \
  Tests/AgentStudioTests/Features/Webview/Views/WebviewPaneMountViewTests.swift \
  Tests/AgentStudioTests/Features/Bridge/Views/BridgePaneMountViewTests.swift \
  Tests/AgentStudioTests/Core/Views/CodeViewerPaneMountViewTests.swift
git commit -m "refactor: mount non-terminal pane content into pane hosts"
```

---

### Task 3: Convert Terminal To `TerminalPaneMountView` With Internal Placeholder State ✅ COMPLETE

**Files:**
- Move: `Sources/AgentStudio/Features/Terminal/Views/AgentStudioTerminalView.swift` -> `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`
- Move: `Sources/AgentStudio/Features/Terminal/Views/TerminalStatusPlaceholderView.swift` -> `Sources/AgentStudio/Features/Terminal/Hosting/TerminalStatusPlaceholderView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Views/SurfaceStartupOverlay.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+TerminalPlaceholders.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/App/Panes/ViewRegistry.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneCoordinatorHardeningTests.swift`

- [ ] **Step 1: Write failing terminal mount-state tests**

```swift
@Test
@MainActor
func terminalMount_switchesPreparingToLiveWithoutReplacingHost() {
    let paneId = UUID()
    let host = PaneHostView(paneId: paneId)
    let mount = TerminalPaneMountView(paneId: paneId, title: "T")
    host.mountContentView(mount)

    mount.showPreparingForTesting()
    let hostIdentity = ObjectIdentifier(host)
    mount.showMountedSurfaceForTesting(MockGhosttySurfaceFactory.makeSurfaceView())

    #expect(ObjectIdentifier(host) == hostIdentity)
    #expect(mount.currentModeForTesting == .liveSurface)
}

@Test
@MainActor
func terminalPlaceholder_isMountedContentNotRegisteredHost() {
    let host = try #require(makeTerminalHostForTesting(mode: .preparing))
    #expect(host.terminalMountViewForTesting != nil)
    #expect(host.terminalPlaceholderMountForTesting != nil)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalPaneMountViewTests|PaneCoordinatorHardeningTests"`
Expected: FAIL with missing type / API errors.

- [ ] **Step 3: Refactor terminal UI into mounted content**

Required behavior:

- `TerminalPaneMountView` owns terminal-specific overlays, first-responder forwarding, process/repair state, and placeholder/live-mode transitions
- the host stays stable while the terminal mount changes internal mode
- placeholder registration updates terminal mount state inside the existing host instead of replacing the registered host object
- host -> terminal mount responder forwarding is explicit and tested
- mount-local hit routing stays inside the terminal mount; management-mode blocking stays on the host

- [ ] **Step 4: Delete the old placeholder-as-host model**

Required behavior:

- remove any remaining code that registers `TerminalStatusPlaceholderView` as a top-level `ViewRegistry` host
- placeholder retry/dismiss flows act through the terminal mount hosted inside `PaneHostView`
- no branch in coordinator logic should ask “is the registered pane view a placeholder host?”

- [ ] **Step 5: Run focused tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "TerminalPaneMountViewTests|PaneCoordinatorHardeningTests|Luna295DirectZmxAttachIntegrationTests"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalStatusPlaceholderView.swift \
  Sources/AgentStudio/Features/Terminal/Views/SurfaceStartupOverlay.swift \
  Sources/AgentStudio/App/PaneCoordinator+TerminalPlaceholders.swift \
  Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift \
  Sources/AgentStudio/App/Panes/ViewRegistry.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/TerminalPaneMountViewTests.swift \
  Tests/AgentStudioTests/App/PaneCoordinatorHardeningTests.swift
git commit -m "refactor: move terminal placeholder and live state into terminal mount"
```

---

### Task 4: Add `GhosttyMountView` And Make Terminal Reconciliation Explicit ✅ COMPLETE

**Files:**
- Create: `Sources/AgentStudio/Features/Terminal/Hosting/GhosttyMountView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift`
- Modify: `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift`
- Modify: `Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift`
- Test: `Tests/AgentStudioTests/Features/Terminal/Hosting/GhosttyMountViewTests.swift`
- Test: `Tests/AgentStudioTests/App/TerminalHostReconciliationTests.swift`

- [ ] **Step 1: Write failing mount-boundary tests**

```swift
@Test
@MainActor
func ghosttySurface_isParentedOnlyUnderGhosttyMountView() {
    let mount = GhosttyMountView()
    let surface = MockGhosttySurfaceFactory.makeSurfaceView()

    mount.mount(surface)

    #expect(surface.superview === mount)
}

@Test
@MainActor
func visibleStructureMutation_keepsPreviouslyVisibleTerminalMountedAndPaintable() {
    let harness = makeTerminalReconciliationHarness()

    // Simulate adding a right split next to an already-visible terminal.
    try #require(harness.performVisibleSplitMutation())

    #expect(harness.previouslyVisibleTerminalStillHasSurface == true)
    #expect(harness.previouslyVisibleTerminalNeedsPtyKickToPaint == false)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyMountViewTests|TerminalHostReconciliationTests"`
Expected: FAIL

- [ ] **Step 3: Implement `GhosttyMountView`**

Required behavior:

- only app-local parent of `Ghostty.SurfaceView`
- owns mount/unmount operations
- applies surface constraints / frame sync in one place
- is the only code allowed to call `addSubview(surfaceView)` or `removeFromSuperview()` for Ghostty surfaces

- [ ] **Step 4: Move terminal reconciliation to explicit host/mount boundaries**

Required behavior:

- `PaneTabViewController.syncVisibleTerminalGeometry` targets terminal hosts/mounts, not raw terminal host classes
- size authority for visible terminals comes from post-layout mounted bounds
- reconciliation explicitly covers focus, occlusion, redraw, and size as separate steps
- structure mutation triggers reconciliation even when `activePaneId` is unchanged

- [ ] **Step 5: Delete ad hoc renderer parent movement**

Required behavior:

- no `displaySurface(...)`-style direct parent movement remains outside `GhosttyMountView`
- no terminal host type should own both split-tree identity and raw Ghostty parentage

- [ ] **Step 6: Run focused tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "GhosttyMountViewTests|TerminalHostReconciliationTests|PaneTabViewControllerLaunchRestoreTests"`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Features/Terminal/Hosting/GhosttyMountView.swift \
  Sources/AgentStudio/Features/Terminal/Hosting/TerminalPaneMountView.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/GhosttySurfaceView.swift \
  Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager.swift \
  Sources/AgentStudio/App/Panes/PaneTabViewController.swift \
  Sources/AgentStudio/App/PaneCoordinator+ViewLifecycle.swift \
  Sources/AgentStudio/App/PaneCoordinator+ActionExecution.swift \
  Tests/AgentStudioTests/Features/Terminal/Hosting/GhosttyMountViewTests.swift \
  Tests/AgentStudioTests/App/TerminalHostReconciliationTests.swift
git commit -m "refactor: separate terminal mount from ghostty renderer parentage"
```

---

### Task 5: Delete Old Types, Update Docs, And Prove Clean Break

**Files:**
- Modify: `docs/architecture/README.md`
- Modify: `docs/architecture/appkit_swiftui_architecture.md`
- Modify: `docs/architecture/component_architecture.md`
- Modify: `docs/architecture/directory_structure.md`
- Modify: `docs/architecture/ghostty_surface_architecture.md`
- Modify: `docs/architecture/pane_runtime_architecture.md`
- Modify: `docs/architecture/pane_runtime_eventbus_design.md`
- Modify: `docs/architecture/session_lifecycle.md`
- Modify: `docs/architecture/swift_react_bridge_design.md`
- Modify: `AGENTS.md`
- Test / grep all old type names and removed APIs

- [ ] **Step 1: Update architecture docs for the new model**

Required doc outcomes:

- `PaneHostView` is the stable pane shell for every pane kind
- pane-kind content mounts into that host by composition
- terminal content owns `GhosttyMountView`
- `ViewRegistry` is host-only
- no placeholder-as-host language remains
- docs that currently name `AgentStudioTerminalView`, `WebviewPaneView`, `BridgePaneView`, `CodeViewerPaneView`, or raw `PaneView` as the registry/render-tree unit are rewritten to use the new host/mount vocabulary
- the bridge design doc is updated so bridge/webview are described as mounted content inside a host, not as the host itself
- session/runtime docs stop implying that terminal-specific view classes are the pane-shell abstraction for the whole app

- [ ] **Step 2: Add hard-cutover regression checks**

Run:

```bash
rg -n "class PaneView[^H]|final class AgentStudioTerminalView|final class WebviewPaneView|final class BridgePaneView|final class CodeViewerPaneView|typealias TerminalViewRepresentable|typealias TerminalSplitTree" Sources/ Tests/ docs/architecture AGENTS.md
```

Expected: zero matches for removed types and removed terminal-parenting API names after the refactor is complete.

Note: `displaySurface()` on `TerminalPaneMountView` is intentionally retained — it is the mount-level API that delegates to `GhosttyMountView.mount()`. It is NOT the old pattern where a host class directly parented a Ghostty surface. The invariant is: "no host type owns renderer parentage" — the mount's `displaySurface` is mount-internal, not host-level.

- [ ] **Step 3: Run focused doc / compile tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CoordinationPlaneArchitectureTests|PaneCoordinatorTests"`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add docs/architecture/README.md \
  docs/architecture/appkit_swiftui_architecture.md \
  docs/architecture/component_architecture.md \
  docs/architecture/directory_structure.md \
  docs/architecture/ghostty_surface_architecture.md \
  docs/architecture/pane_runtime_architecture.md \
  docs/architecture/pane_runtime_eventbus_design.md \
  docs/architecture/session_lifecycle.md \
  docs/architecture/swift_react_bridge_design.md \
  AGENTS.md
git commit -m "docs: update architecture for universal pane host and terminal mount split"
```

---

### Task 6: Full Verification

**Files:**
- All modified files from Tasks 0-5

- [ ] **Step 1: Run targeted suites for the new host/mount architecture**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PaneHostViewTests|WebviewPaneMountViewTests|BridgePaneMountViewTests|CodeViewerPaneMountViewTests|TerminalPaneMountViewTests|GhosttyMountViewTests|TerminalHostReconciliationTests"
```

Expected: PASS

- [ ] **Step 2: Run the full test suite**

Run: `AGENT_RUN_ID=stablehost-host-mount mise run test`
Expected: PASS, zero failures.

- [ ] **Step 3: Run lint**

Run: `AGENT_RUN_ID=stablehost-host-mount mise run lint`
Expected: PASS, zero errors.

- [ ] **Step 4: Manual verification for the bug and the extra-layer assumption**

Launch:

```bash
pkill -9 -f "AgentStudio" 2>/dev/null
AGENT_RUN_ID=stablehost-host-mount .build-agent-stablehost-host-mount/debug/AgentStudio &
```

Verify manually:

1. create a split rapidly several times
2. switch arrangements
3. switch tabs with a visible terminal
4. expand/collapse a drawer terminal
5. repair a failed placeholder terminal
6. confirm existing visible terminals do not blank and do not require Enter to repaint
7. confirm the extra universal host layer does not introduce focus loss or redraw artifacts for webview/bridge/code panes

- [ ] **Step 5: Verify no wall-clock tests were introduced**

Run:

```bash
rg -n "Task\\.sleep|sleep\\(" Tests/AgentStudioTests
```

Expected: zero matches in tests added or modified by this slice.

---

## Notes For The Implementer

- This is a full-system clean break. Do not leave compatibility wrappers, typealiases, or old registry branches behind.
- The universal host applies to **all** pane kinds in this slice. Do not defer webview/bridge/codeviewer to a follow-up.
- Terminal is still special, but only inside the mounted-content layer.
- `PaneHostView` should stay small and shell-focused. Do not move terminal-specific renderer logic back into it.
- `TerminalPaneMountView` owns terminal-specific state transitions. `GhosttyMountView` owns only Ghostty surface parentage and mount semantics.
- `swiftUIContainer` stays host-owned. Mounted content is never bridged to SwiftUI directly.
- Drawer paths are in scope. They must consume the same host model as the main split tree.
- Tests must be event-driven. Use `AsyncStream.makeStream`, probe actors, or injected clocks. Do not add wall-clock sleeps to test bodies.
- When testing Swift 6.2 boundaries, prefer observable behavior and compile-time-safe structure over runtime helpers that assert implementation details about actor isolation.
- The Ghostty runtime isolation split is intentionally deferred to a follow-up plan immediately after this one.
- If any implementation step seems to require a shim, stop and simplify the cutover instead. The desired outcome is a smaller, cleaner system, not a migration museum.
