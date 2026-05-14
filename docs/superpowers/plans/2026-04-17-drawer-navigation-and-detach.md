# Drawer Navigation And Detach Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add drawer-scoped `⌥IJKL` navigation, drawer-only `N x 2` layout support, explicit drawer detach-to-parent-right behavior, and the empty-drawer creation rules without changing main-pane layout semantics.

**Architecture:** Keep the main pane row on the existing flat `Layout` model and introduce a drawer-only layout value type that can represent up to two horizontal rows. Route all new behavior through the existing command, validation, and pane-focus systems, then add one atomic coordinator path for drawer detach so runtime/view state does not drift.

**Tech Stack:** Swift 6, AppKit, SwiftUI, Swift Testing, existing `CommandDispatcher`, `WorkspaceCommandValidator`, `PaneFocus*` system, `WorkspaceStore` / `PaneCoordinator`

---

## Design Diagrams

```text
┌──────────────────────────── Pane Ownership ────────────────────────────┐
│                                                                       │
│  Tab main layout                                                      │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐                       │
│  │ Layout A   │  │ Layout B   │  │ Layout C   │                       │
│  │ pane       │  │ pane       │  │ pane       │                       │
│  └────────────┘  └────────────┘  └────────────┘                       │
│                      │                                                │
│                      ▼ owns one drawer container                      │
│                  ┌──────────────────────────────┐                     │
│                  │ Drawer children only         │                     │
│                  │  ┌────────┐  ┌────────┐     │                     │
│                  │  │ Child1 │  │ Child2 │     │                     │
│                  │  └────────┘  └────────┘     │                     │
│                  │  ┌────────┐  ┌────────┐     │                     │
│                  │  │ Child3 │  │ Child4 │     │                     │
│                  │  └────────┘  └────────┘     │                     │
│                  └──────────────────────────────┘                     │
│                                                                       │
│  Layout pane and drawer child pane stay different pane kinds.         │
└───────────────────────────────────────────────────────────────────────┘
```

```text
┌──────────────────────────── Scope Routing ─────────────────────────────┐
│                                                                       │
│  Outside drawer scope                                                 │
│  `⌥J` = main left    `⌥L` = main right                               │
│  `⌥I` = no-op        `⌥K` = enter drawer                             │
│                                                                       │
│                    `⌥K` enters explicit drawer scope                  │
│                                 │                                     │
│                                 ▼                                     │
│  Inside drawer scope                                                  │
│  `⌥I` = up     `⌥J` = left     `⌥K` = down     `⌥L` = right          │
│  missing neighbor = no-op                                             │
│                                                                       │
│  Explicit detach                                                     │
│  drawer child ──detach──▶ layout pane inserted right of parent        │
└───────────────────────────────────────────────────────────────────────┘
```

## File Map

- Create: `Sources/AgentStudio/Core/Models/DrawerGridLayout.swift`
  - Owns the drawer-only `N x 2` layout model, directional neighbor lookup, insertion, movement, removal, resize, and legality checks.
- Modify: `Sources/AgentStudio/Core/Models/Drawer.swift`
  - Swap the drawer's `layout` storage from `Layout` to `DrawerGridLayout` while keeping drawer-specific persisted state local to the drawer model.
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift`
  - Rebuild drawer add/insert/move/remove/minimize/equalize behavior on top of `DrawerGridLayout`.
- Modify: `Sources/AgentStudio/Core/Actions/PaneActionCommand.swift`
  - Add explicit drawer entry, drawer directional focus, and drawer detach commands.
- Create: `Sources/AgentStudio/Core/Actions/DrawerCommandValidator.swift`
  - Owns drawer-parent membership checks, `N x 2` legality, and detach eligibility rules for `WorkspaceCommandValidator`.
- Modify: `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
  - Delegate drawer legality to `DrawerCommandValidator` and validate the new commands.
- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift`
  - Add app-level command cases for drawer entry, drawer directional focus, and drawer detach.
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
  - Add `i`, `j`, and `l` decoding support so the controller can resolve raw `⌥IJKL` triggers by scope.
- Modify: `Sources/AgentStudio/App/Commands/AppCommand+Definitions.swift`
  - Register the new commands, keep the scope-aware drawer commands out of the static shortcut catalog, and explicitly keep `navigateDrawerPane` as the command-bar-only targeted drawer selector.
- Modify: `Sources/AgentStudio/App/Lifecycle/ManagementLayerMonitor.swift`
  - Pass `⌥IJKL` through during management mode so movement semantics remain identical there.
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
  - Resolve outside-drawer vs inside-drawer `⌥IJKL` behavior through one unified keyboard navigation scope, route scope transitions through real validated command paths, preserve main-pane left/right behavior, and handle empty-drawer create only from a neutral non-terminal focus state outside management mode.
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
  - Execute drawer move/insert using the new drawer layout API directly and execute the new non-destructive `detachDrawerPane` action.
- Modify: `Sources/AgentStudio/Core/Actions/UIActionPresentation.swift`
  - Add a local action presentation for the new management-mode detach button.
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
  - Render a drawer grid instead of a flat strip, surface the detach button in management mode, and keep drawer editing constrained to drawer scope.
- Create: `Sources/AgentStudio/Core/Views/Drawer/DrawerDropZone.swift`
  - Own the drawer-only drop-zone model so main-pane split drop zones stay left/right-only.
- Create: `Sources/AgentStudio/Core/Views/Drawer/DrawerPaneDragCoordinator.swift`
  - Resolve drawer drag targets with top/bottom as well as left/right, without mutating main-pane drag semantics.
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
  - Hide any main-pane extraction affordance for drawer children so detach stays explicit and one-way from drawer UI only.

- Test: `Tests/AgentStudioTests/Core/Models/DrawerGridLayoutTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreDrawerTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Actions/ActionValidatorTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Actions/ActionValidatorOwnershipTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Actions/DrawerCommandIntegrationTests.swift`
- Modify: `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift`
- Modify: `Tests/AgentStudioTests/App/ManagementLayerTests.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
- Create: `Tests/AgentStudioTests/Core/Views/Drawer/DrawerDropZoneTests.swift`
- Create: `Tests/AgentStudioTests/Core/Actions/UIActionPresentationTests.swift`

## Task 1: Introduce A Drawer-Only `N x 2` Layout Model

**Files:**
- Create: `Sources/AgentStudio/Core/Models/DrawerGridLayout.swift`
- Test: `Tests/AgentStudioTests/Core/Models/DrawerGridLayoutTests.swift`

- [ ] **Step 1: Write the failing drawer-layout tests**

```swift
import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct DrawerGridLayoutTests {
    @Test("up/down neighbors use drawer rows")
    func verticalNeighborLookup_prefersPaneInOtherRow() {
        let topLeft = UUID()
        let topRight = UUID()
        let bottomLeft = UUID()
        let bottomRight = UUID()

        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([topLeft, topRight]),
            bottomRow: Layout.autoTiled([bottomLeft, bottomRight]),
            rowSplitRatio: 0.5
        )

        #expect(layout.neighbor(of: topLeft, direction: .down) == bottomLeft)
        #expect(layout.neighbor(of: bottomRight, direction: .up) == topRight)
    }

    @Test("missing directional neighbor is a no-op")
    func verticalNeighborLookup_returnsNilAtEdge() {
        let topOnly = UUID()
        let peer = UUID()
        let layout = DrawerGridLayout(topRow: Layout.autoTiled([topOnly, peer]))

        #expect(layout.neighbor(of: topOnly, direction: .up) == nil)
        #expect(layout.neighbor(of: peer, direction: .down) == nil)
    }

    @Test("layout rejects third row insertions")
    func insertingThirdRow_isRejected() {
        let top = UUID()
        let bottom = UUID()
        let incoming = UUID()

        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([top]),
            bottomRow: Layout.autoTiled([bottom]),
            rowSplitRatio: 0.5
        )

        let rejected = layout.inserting(
            paneId: incoming,
            at: bottom,
            direction: .down
        )

        #expect(rejected == nil)
    }

    @Test("removing the only pane from the top row collapses the bottom row upward")
    func removingOnlyTopRowPane_collapsesBottomRow() {
        let topOnly = UUID()
        let bottomLeft = UUID()
        let bottomRight = UUID()

        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([topOnly]),
            bottomRow: Layout.autoTiled([bottomLeft, bottomRight]),
            rowSplitRatio: 0.5
        )

        let collapsed = try #require(layout.removing(paneId: topOnly))
        #expect(collapsed.topRow.paneIds == [bottomLeft, bottomRight])
        #expect(collapsed.bottomRow == nil)
    }

    @Test("removing the only pane from the bottom row collapses to a single top row")
    func removingOnlyBottomRowPane_collapsesToSingleRow() {
        let topLeft = UUID()
        let topRight = UUID()
        let bottomOnly = UUID()

        let layout = DrawerGridLayout(
            topRow: Layout.autoTiled([topLeft, topRight]),
            bottomRow: Layout.autoTiled([bottomOnly]),
            rowSplitRatio: 0.5
        )

        let collapsed = try #require(layout.removing(paneId: bottomOnly))
        #expect(collapsed.topRow.paneIds == [topLeft, topRight])
        #expect(collapsed.bottomRow == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --build-path .build-agent-drawer-navigation --filter 'DrawerGridLayoutTests'
```

Expected:

```text
FAIL because DrawerGridLayout does not exist yet
```

- [ ] **Step 3: Write the minimal drawer layout implementation**

```swift
import Foundation

struct DrawerGridLayout: Codable, Hashable {
    var topRow: Layout
    var bottomRow: Layout?
    var rowSplitRatio: Double

    init(
        topRow: Layout = Layout(),
        bottomRow: Layout? = nil,
        rowSplitRatio: Double = 0.5
    ) {
        self.topRow = topRow
        self.bottomRow = bottomRow
        self.rowSplitRatio = rowSplitRatio
    }

    var paneIds: [UUID] {
        topRow.paneIds + (bottomRow?.paneIds ?? [])
    }

    func contains(_ paneId: UUID) -> Bool {
        topRow.contains(paneId) || bottomRow?.contains(paneId) == true
    }

    func neighbor(of paneId: UUID, direction: FocusDirection) -> UUID? {
        switch direction {
        case .left, .right:
            if topRow.contains(paneId) {
                return topRow.neighbor(of: paneId, direction: direction)
            }
            return bottomRow?.neighbor(of: paneId, direction: direction)
        case .up:
            guard let bottomRow, bottomRow.contains(paneId) else { return nil }
            return pairedPane(in: topRow, for: paneId, from: bottomRow)
        case .down:
            guard let bottomRow, topRow.contains(paneId) else { return nil }
            return pairedPane(in: bottomRow, for: paneId, from: topRow)
        }
    }

    func inserting(
        paneId: UUID,
        at targetPaneId: UUID,
        direction: SplitNewDirection
    ) -> DrawerGridLayout? {
        switch direction {
        case .left:
            guard topRow.contains(targetPaneId) || bottomRow?.contains(targetPaneId) == true else { return nil }
            if topRow.contains(targetPaneId) {
                return DrawerGridLayout(
                    topRow: topRow.inserting(paneId: paneId, at: targetPaneId, direction: .horizontal, position: .before),
                    bottomRow: bottomRow,
                    rowSplitRatio: rowSplitRatio
                )
            }
            guard let bottomRow else { return nil }
            return DrawerGridLayout(
                topRow: topRow,
                bottomRow: bottomRow.inserting(paneId: paneId, at: targetPaneId, direction: .horizontal, position: .before),
                rowSplitRatio: rowSplitRatio
            )
        case .right:
            guard topRow.contains(targetPaneId) || bottomRow?.contains(targetPaneId) == true else { return nil }
            if topRow.contains(targetPaneId) {
                return DrawerGridLayout(
                    topRow: topRow.inserting(paneId: paneId, at: targetPaneId, direction: .horizontal, position: .after),
                    bottomRow: bottomRow,
                    rowSplitRatio: rowSplitRatio
                )
            }
            guard let bottomRow else { return nil }
            return DrawerGridLayout(
                topRow: topRow,
                bottomRow: bottomRow.inserting(paneId: paneId, at: targetPaneId, direction: .horizontal, position: .after),
                rowSplitRatio: rowSplitRatio
            )
        case .up:
            guard topRow.contains(targetPaneId), bottomRow == nil else { return nil }
            return DrawerGridLayout(
                topRow: Layout(paneId: paneId),
                bottomRow: topRow,
                rowSplitRatio: rowSplitRatio
            )
        case .down:
            guard topRow.contains(targetPaneId), bottomRow == nil else { return nil }
            return DrawerGridLayout(
                topRow: topRow,
                bottomRow: Layout(paneId: paneId),
                rowSplitRatio: rowSplitRatio
            )
        }
    }

    func removing(paneId: UUID) -> DrawerGridLayout? {
        if topRow.contains(paneId) {
            if let updatedTopRow = topRow.removing(paneId: paneId) {
                return DrawerGridLayout(
                    topRow: updatedTopRow,
                    bottomRow: bottomRow,
                    rowSplitRatio: rowSplitRatio
                )
            }
            guard let bottomRow else { return nil }
            return DrawerGridLayout(
                topRow: bottomRow,
                bottomRow: nil,
                rowSplitRatio: rowSplitRatio
            )
        }

        if let bottomRow, bottomRow.contains(paneId) {
            if let updatedBottomRow = bottomRow.removing(paneId: paneId) {
                return DrawerGridLayout(
                    topRow: topRow,
                    bottomRow: updatedBottomRow,
                    rowSplitRatio: rowSplitRatio
                )
            }
            return DrawerGridLayout(
                topRow: topRow,
                bottomRow: nil,
                rowSplitRatio: rowSplitRatio
            )
        }

        return self
    }

    func resizing(splitId: UUID, ratio: Double) -> DrawerGridLayout {
        if topRow.dividerIds.contains(splitId) {
            return DrawerGridLayout(
                topRow: topRow.resizing(splitId: splitId, ratio: ratio),
                bottomRow: bottomRow,
                rowSplitRatio: rowSplitRatio
            )
        }
        if let bottomRow, bottomRow.dividerIds.contains(splitId) {
            return DrawerGridLayout(
                topRow: topRow,
                bottomRow: bottomRow.resizing(splitId: splitId, ratio: ratio),
                rowSplitRatio: rowSplitRatio
            )
        }
        return self
    }

    func equalized() -> DrawerGridLayout {
        DrawerGridLayout(
            topRow: topRow.equalized(),
            bottomRow: bottomRow?.equalized(),
            rowSplitRatio: rowSplitRatio
        )
    }

    func ratioForSplit(_ splitId: UUID) -> Double? {
        topRow.ratioForSplit(splitId) ?? bottomRow?.ratioForSplit(splitId)
    }

    private func pairedPane(in destinationRow: Layout, for sourcePaneId: UUID, from sourceRow: Layout) -> UUID? {
        guard
            let sourceIndex = sourceRow.paneIds.firstIndex(of: sourcePaneId),
            !destinationRow.paneIds.isEmpty
        else { return nil }
        let pairedIndex = min(sourceIndex, destinationRow.paneIds.count - 1)
        return destinationRow.paneIds[pairedIndex]
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --build-path .build-agent-drawer-navigation --filter 'DrawerGridLayoutTests'
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Models/DrawerGridLayout.swift Tests/AgentStudioTests/Core/Models/DrawerGridLayoutTests.swift
git commit -m "feat: add drawer grid layout model

Co-authored-by: Codex <noreply@openai.com>"
```

## Task 2: Flip `Drawer` To `DrawerGridLayout` And Update Immediate Consumers In One Slice

**Files:**
- Modify: `Sources/AgentStudio/Core/Models/Drawer.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift`
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreDrawerTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Actions/DrawerCommandIntegrationTests.swift`

- [ ] **Step 1: Write the failing store and integration tests**

```swift
@Test
func test_insertDrawerPane_downCreatesSecondRow() {
    let store = WorkspaceStore(persistor: WorkspacePersistor(workspacesDir: tempDir))
    store.restore()
    let parent = store.createPane(source: .floating(launchDirectory: nil, title: nil))
    let first = try #require(store.addDrawerPane(to: parent.id))

    let second = try #require(
        store.insertDrawerPane(
            in: parent.id,
            at: first.id,
            direction: .vertical,
            position: .after,
            parentFallbackCWD: nil
        )
    )

    let drawer = try #require(store.pane(parent.id)?.drawer)
    #expect(drawer.layout.bottomRow?.contains(second.id) == true)
    #expect(drawer.layout.topRow.contains(first.id))
}

@Test
func test_moveDrawerPane_downIntoThirdRow_isNoOp() {
    let (parentPaneId, _) = createParentPaneInTab()
    let topLeft = store.addDrawerPane(to: parentPaneId)!
    let topRight = store.addDrawerPane(to: parentPaneId)!
    let bottom = store.insertDrawerPane(
        in: parentPaneId,
        at: topLeft.id,
        direction: .vertical,
        position: .after,
        parentFallbackCWD: nil
    )!

    let before = store.pane(parentPaneId)!.drawer!.layout
    executor.execute(
        .moveDrawerPane(
            parentPaneId: parentPaneId,
            drawerPaneId: bottom.id,
            targetDrawerPaneId: topRight.id,
            direction: .down
        )
    )

    #expect(store.pane(parentPaneId)!.drawer!.layout == before)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --build-path .build-agent-drawer-navigation --filter 'WorkspaceStoreDrawerTests|DrawerCommandIntegrationTests'
```

Expected:

```text
FAIL because `Drawer.layout` still uses the flat `Layout` type and the compiled drawer consumers still assume strip-only behavior
```

- [ ] **Step 3: Write the minimal store mutation changes**

```swift
import Foundation

struct Drawer: Codable, Hashable {
    var paneIds: [UUID]
    var layout: DrawerGridLayout
    var activePaneId: UUID?
    var isExpanded: Bool
    var minimizedPaneIds: Set<UUID>

    init(
        paneIds: [UUID] = [],
        layout: DrawerGridLayout = DrawerGridLayout(),
        activePaneId: UUID? = nil,
        isExpanded: Bool = false,
        minimizedPaneIds: Set<UUID> = []
    ) {
        self.paneIds = paneIds
        self.layout = layout
        self.activePaneId = activePaneId
        self.isExpanded = isExpanded
        self.minimizedPaneIds = minimizedPaneIds
    }
}
```

```swift
@discardableResult
func addDrawerPane(
    to parentPaneId: UUID,
    content: PaneContent,
    metadata: PaneMetadata
) -> Pane? {
    guard panes[parentPaneId] != nil else { return nil }

    let drawerPane = Pane(
        content: content,
        metadata: metadata,
        kind: .drawerChild(parentPaneId: parentPaneId)
    )

    panes[drawerPane.id] = drawerPane
    panes[parentPaneId]!.withDrawer { drawer in
        if let targetPaneId = drawer.layout.paneIds.last,
           let updatedLayout = drawer.layout.inserting(
               paneId: drawerPane.id,
               at: targetPaneId,
               direction: .right
           ) {
            drawer.layout = updatedLayout
        } else {
            drawer.layout = DrawerGridLayout(topRow: Layout(paneId: drawerPane.id))
        }
        drawer.paneIds.append(drawerPane.id)
        drawer.activePaneId = drawerPane.id
        drawer.isExpanded = true
    }
    return drawerPane
}

func moveDrawerPane(
    drawerPaneId: UUID,
    in parentPaneId: UUID,
    to targetDrawerPaneId: UUID,
    direction: SplitNewDirection
) {
    guard var parentPane = panes[parentPaneId],
          var drawer = parentPane.drawer,
          drawer.paneIds.contains(drawerPaneId),
          drawer.paneIds.contains(targetDrawerPaneId)
    else { return }

    guard let layoutWithoutPane = drawer.layout.removing(paneId: drawerPaneId),
          let updatedLayout = layoutWithoutPane.inserting(
              paneId: drawerPaneId,
              at: targetDrawerPaneId,
              direction: direction
          )
    else { return }

    drawer.layout = updatedLayout
    drawer.activePaneId = drawerPaneId
    parentPane.kind = .layout(drawer: drawer)
    panes[parentPaneId] = parentPane
}

@discardableResult
func insertDrawerPane(
    in parentPaneId: UUID,
    at targetDrawerPaneId: UUID,
    direction: Layout.SplitDirection,
    position: Layout.Position,
    parentFallbackCWD: URL?
) -> Pane? {
    let splitDirection: SplitNewDirection = switch (direction, position) {
    case (.horizontal, .before): .left
    case (.horizontal, .after): .right
    case (.vertical, .before): .up
    case (.vertical, .after): .down
    }

    guard let metadata = inheritedDrawerMetadata(from: parentPaneId, parentFallbackCWD: parentFallbackCWD) else {
        return nil
    }
    let drawerPane = Pane(
        content: .terminal(TerminalState(provider: .zmx, lifetime: .persistent)),
        metadata: metadata,
        kind: .drawerChild(parentPaneId: parentPaneId)
    )
    guard let updatedLayout = panes[parentPaneId]?.drawer?.layout.inserting(
        paneId: drawerPane.id,
        at: targetDrawerPaneId,
        direction: splitDirection
    ) else {
        return nil
    }
    panes[drawerPane.id] = drawerPane
    panes[parentPaneId]!.withDrawer { drawer in
        drawer.layout = updatedLayout
        drawer.paneIds.append(drawerPane.id)
        drawer.activePaneId = drawerPane.id
        drawer.isExpanded = true
    }
    return drawerPane
}
```

```swift
case .insertDrawerPane(let parentPaneId, let targetDrawerPaneId, let direction):
    executeInsertDrawerPane(
        parentPaneId: parentPaneId,
        targetDrawerPaneId: targetDrawerPaneId,
        direction: direction
    )

case .moveDrawerPane(let parentPaneId, let drawerPaneId, let targetDrawerPaneId, let direction):
    store.paneAtom.moveDrawerPane(
        drawerPaneId,
        in: parentPaneId,
        to: targetDrawerPaneId,
        direction: direction
    )
    focusVisiblePaneHost(drawerPaneId)
```

```swift
struct DrawerPanel: View {
    let layout: DrawerGridLayout

    var body: some View {
        VStack(spacing: DrawerLayout.panelContentPadding) {
            FlatPaneStripContent(
                layout: layout.topRow,
                tabId: tabId,
                activePaneId: activePaneId,
                minimizedPaneIds: minimizedPaneIds,
                closeTransitionCoordinator: closeTransitionCoordinator,
                actionDispatcher: drawerActionDispatcher,
                onPaneFocusTrigger: onPaneFocusTrigger,
                store: store,
                repoCache: repoCache,
                viewRegistry: viewRegistry,
                coordinateSpaceName: Self.drawerDropCoordinateSpace,
                useDrawerFramePreference: true,
                onOpenPaneGitHub: onOpenPaneGitHub
            )
            if let bottomRow = layout.bottomRow {
                FlatPaneStripContent(
                    layout: bottomRow,
                    tabId: tabId,
                    activePaneId: activePaneId,
                    minimizedPaneIds: minimizedPaneIds,
                    closeTransitionCoordinator: closeTransitionCoordinator,
                    actionDispatcher: drawerActionDispatcher,
                    onPaneFocusTrigger: onPaneFocusTrigger,
                    store: store,
                    repoCache: repoCache,
                    viewRegistry: viewRegistry,
                    coordinateSpaceName: Self.drawerDropCoordinateSpace,
                    useDrawerFramePreference: true,
                    onOpenPaneGitHub: onOpenPaneGitHub
                )
            }
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --build-path .build-agent-drawer-navigation --filter 'WorkspaceStoreDrawerTests|DrawerCommandIntegrationTests'
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Models/Drawer.swift Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift Tests/AgentStudioTests/Core/Stores/WorkspaceStoreDrawerTests.swift Tests/AgentStudioTests/Core/Actions/DrawerCommandIntegrationTests.swift
git commit -m "feat: move drawer mutations onto drawer grid layout

Co-authored-by: Codex <noreply@openai.com>"
```

## Task 3: Add Drawer-Specific Validation And New Action Commands

**Files:**
- Modify: `Sources/AgentStudio/Core/Actions/PaneActionCommand.swift`
- Create: `Sources/AgentStudio/Core/Actions/DrawerCommandValidator.swift`
- Modify: `Sources/AgentStudio/Core/Actions/ActionValidator.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Modify: `Tests/AgentStudioTests/Core/Actions/ActionValidatorTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Actions/ActionValidatorOwnershipTests.swift`

- [ ] **Step 1: Write the failing validator tests**

```swift
@Test
func test_focusDrawerPaneLeft_wrongParentFails() {
    let parentPaneId = UUIDv7.generate()
    let otherParentPaneId = UUIDv7.generate()
    let drawerPaneId = UUIDv7.generate()

    let snapshot = ActionStateSnapshot(
        tabs: [
            TabSnapshot(
                id: UUID(),
                visiblePaneIds: [parentPaneId, otherParentPaneId],
                ownedPaneIds: [parentPaneId, otherParentPaneId, drawerPaneId],
                activePaneId: parentPaneId
            )
        ],
        activeTabId: nil,
        isManagementLayerActive: false,
        drawerParentByPaneId: [drawerPaneId: otherParentPaneId]
    )

    let result = WorkspaceCommandValidator.validate(
        .focusDrawerPaneLeft(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId),
        state: snapshot
    )

    if case .failure(.paneNotFound) = result { return }
    Issue.record("Expected paneNotFound for wrong-parent drawer membership")
}

@Test
func test_detachDrawerPane_requiresRealDrawerChild() {
    let parentPaneId = UUIDv7.generate()
    let drawerPaneId = UUIDv7.generate()
    let snapshot = makeSnapshot(
        tabs: [TabSnapshot(id: UUID(), visiblePaneIds: [parentPaneId], ownedPaneIds: [parentPaneId], activePaneId: parentPaneId)],
        activeTabId: nil,
        isManagementLayerActive: false
    )

    let result = WorkspaceCommandValidator.validate(
        .detachDrawerPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId),
        state: snapshot
    )

    if case .failure(.paneNotFound) = result { return }
    Issue.record("Expected paneNotFound when detach targets a non-drawer child")
}

@Test
func test_moveDrawerPane_invalidDrawerLayoutFails() {
    let parentPaneId = UUIDv7.generate()
    let drawerPaneId = UUIDv7.generate()
    let snapshot = ActionStateSnapshot(
        tabs: [
            TabSnapshot(
                id: UUID(),
                visiblePaneIds: [parentPaneId],
                ownedPaneIds: [parentPaneId, drawerPaneId],
                activePaneId: parentPaneId
            )
        ],
        activeTabId: nil,
        isManagementLayerActive: true,
        drawerParentByPaneId: [drawerPaneId: parentPaneId]
    )

    let result = DrawerCommandValidator.validateResultingLayout(
        DrawerGridLayout(
            topRow: Layout.autoTiled([UUID()]),
            bottomRow: Layout.autoTiled([UUID()])
        ),
        parentPaneId: parentPaneId,
        state: snapshot,
        requestedDirection: .down,
        wouldCreateThirdRow: true
    )

    if case .failure(.invalidDrawerLayout) = result { return }
    Issue.record("Expected invalidDrawerLayout when a drawer edit would create a third row")
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --build-path .build-agent-drawer-navigation --filter 'ActionValidatorTests|ActionValidatorOwnershipTests'
```

Expected:

```text
FAIL because the new drawer commands and drawer-specific membership rules do not exist yet
```

- [ ] **Step 3: Implement the minimal validator surface**

```swift
enum PaneActionCommand: Equatable, Hashable {
    case enterDrawer(parentPaneId: UUID)
    case focusDrawerPaneUp(parentPaneId: UUID, drawerPaneId: UUID)
    case focusDrawerPaneLeft(parentPaneId: UUID, drawerPaneId: UUID)
    case focusDrawerPaneDown(parentPaneId: UUID, drawerPaneId: UUID)
    case focusDrawerPaneRight(parentPaneId: UUID, drawerPaneId: UUID)
    case detachDrawerPane(parentPaneId: UUID, drawerPaneId: UUID)
}
```

```swift
enum ActionValidationError: Error, Equatable {
    case invalidDrawerLayout(parentPaneId: UUID)
}
```

```swift
import Foundation

enum DrawerCommandValidator {
    static func validateMembership(
        parentPaneId: UUID,
        drawerPaneId: UUID,
        state: ActionStateSnapshot
    ) -> ActionValidationError? {
        guard state.tabShowing(paneId: parentPaneId) != nil else {
            return .paneNotFound(paneId: parentPaneId, tabId: state.activeTabId ?? UUID())
        }
        guard state.drawerParentPaneId(of: drawerPaneId) == parentPaneId else {
            return .paneNotFound(paneId: drawerPaneId, tabId: state.activeTabId ?? UUID())
        }
        return nil
    }

    static func validateResultingLayout(
        _ resultingLayout: DrawerGridLayout,
        parentPaneId: UUID,
        state: ActionStateSnapshot,
        requestedDirection: SplitNewDirection,
        wouldCreateThirdRow: Bool
    ) -> Result<Void, ActionValidationError> {
        let rowCount = resultingLayout.bottomRow == nil ? 1 : 2
        guard rowCount <= 2, wouldCreateThirdRow == false else {
            return .failure(.invalidDrawerLayout(parentPaneId: parentPaneId))
        }

        if requestedDirection == .up || requestedDirection == .down,
           resultingLayout.bottomRow != nil,
           state.isManagementLayerActive == false
        {
            return .failure(.invalidDrawerLayout(parentPaneId: parentPaneId))
        }

        return .success(())
    }
}
```

```swift
private func dispatchAction(_ action: PaneActionCommand) {
    let drawerParentByPaneId = store.paneAtom.panes.values.reduce(into: [UUID: UUID]()) { result, pane in
        if let parentPaneId = pane.parentPaneId {
            result[pane.id] = parentPaneId
        }
    }

    let snapshot = WorkspaceCommandResolver.snapshot(
        from: store.tabLayoutAtom.tabs,
        activeTabId: store.tabLayoutAtom.activeTabId,
        isManagementLayerActive: atom(\.managementLayer).isActive,
        knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id)),
        drawerParentByPaneId: drawerParentByPaneId
    )
    switch WorkspaceCommandValidator.validate(action, state: snapshot) {
    case .success:
        executor.execute(action)
    case .failure(let error):
        ghosttyLogger.warning("Action rejected: \(error)")
    }
}
```

```swift
let drawerParentByPaneId = store.paneAtom.panes.values.reduce(into: [UUID: UUID]()) { result, pane in
    if let parentPaneId = pane.parentPaneId {
        result[pane.id] = parentPaneId
    }
}

let snapshot = WorkspaceCommandResolver.snapshot(
    from: store.tabLayoutAtom.tabs,
    activeTabId: store.tabLayoutAtom.activeTabId,
    isManagementLayerActive: atom(\.managementLayer).isActive,
    knownWorktreeIds: Set(store.repositoryTopologyAtom.repos.flatMap(\.worktrees).map(\.id)),
    drawerParentByPaneId: drawerParentByPaneId
)
```

```swift
case .enterDrawer(let parentPaneId):
    guard state.tabShowing(paneId: parentPaneId) != nil else {
        return .failure(.paneNotFound(paneId: parentPaneId, tabId: state.activeTabId ?? UUID()))
    }
    return .success(ValidatedAction(action))

case .focusDrawerPaneUp(let parentPaneId, let drawerPaneId),
     .focusDrawerPaneLeft(let parentPaneId, let drawerPaneId),
     .focusDrawerPaneDown(let parentPaneId, let drawerPaneId),
     .focusDrawerPaneRight(let parentPaneId, let drawerPaneId),
     .detachDrawerPane(let parentPaneId, let drawerPaneId):
    if let error = DrawerCommandValidator.validateMembership(
        parentPaneId: parentPaneId,
        drawerPaneId: drawerPaneId,
        state: state
    ) {
        return .failure(error)
    }
    return .success(ValidatedAction(action))
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --build-path .build-agent-drawer-navigation --filter 'ActionValidatorTests|ActionValidatorOwnershipTests'
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Actions/PaneActionCommand.swift Sources/AgentStudio/Core/Actions/DrawerCommandValidator.swift Sources/AgentStudio/Core/Actions/ActionValidator.swift Sources/AgentStudio/App/Panes/PaneTabViewController.swift Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift Tests/AgentStudioTests/Core/Actions/ActionValidatorTests.swift Tests/AgentStudioTests/Core/Actions/ActionValidatorOwnershipTests.swift
git commit -m "feat: validate drawer navigation and detach commands

Co-authored-by: Codex <noreply@openai.com>"
```

## Task 4: Recover The `⌥IJKL` Input Surface

**Files:**
- Modify: `Sources/AgentStudio/App/Commands/AppCommand.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppShortcut.swift`
- Modify: `Sources/AgentStudio/App/Commands/AppCommand+Definitions.swift`
- Modify: `Sources/AgentStudio/App/Lifecycle/ManagementLayerMonitor.swift`
- Modify: `Tests/AgentStudioTests/App/ShortcutCatalogTests.swift`
- Modify: `Tests/AgentStudioTests/App/ManagementLayerTests.swift`

Keep `navigateDrawerPane` as the command-bar-only targeted drawer selector in this plan. The new directional commands cover keyboard movement; they do not replace the existing targeted command-bar drill-in.

- [ ] **Step 1: Write the failing shortcut-catalog tests**

```swift
@Test
func shortcutCatalog_decodesDrawerMovementLetters() {
    let expectations: [(String, ShortcutTrigger)] = [
        ("i", .init(key: .character(.i), modifiers: [.option])),
        ("j", .init(key: .character(.j), modifiers: [.option])),
        ("k", .init(key: .character(.k), modifiers: [.option])),
        ("l", .init(key: .character(.l), modifiers: [.option])),
    ]

    for (character, expected) in expectations {
        let decoded = ShortcutDecoder.decode(
            keyCode: 0,
            modifierFlags: [.option],
            charactersIgnoringModifiers: character
        )
        #expect(decoded == expected)
    }
}

@Test("management layer passes option-ijkl through")
func test_managementLayer_keyPolicy_optionIJKLPassThrough() async {
    withTestAtomRegistry { _ in
        let monitor = makeMonitor()
        let decision = monitor.keyDownDecision(
            keyCode: 34,
            modifierFlags: [.option],
            charactersIgnoringModifiers: "i"
        )
        #expect(decision == .passThrough)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --build-path .build-agent-drawer-navigation --filter 'ShortcutCatalogTests|ManagementLayerTests'
```

Expected:

```text
FAIL because .i/.j/.l are not decodable yet
```

- [ ] **Step 3: Implement the minimal command and shortcut surface**

```swift
enum AppCommand: String, CaseIterable {
    case enterDrawer
    case focusDrawerPaneUp
    case focusDrawerPaneLeft
    case focusDrawerPaneDown
    case focusDrawerPaneRight
    case detachDrawerPane
}
```

```swift
enum ShortcutCharacterKey: String, CaseIterable {
    case i
    case j
    case k
    case l
}
```

```swift
extension AppCommand {
    var isScopeAwareDrawerShortcut: Bool {
        switch self {
        case .enterDrawer, .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown, .focusDrawerPaneRight:
            return true
        default:
            return false
        }
    }
}
```

```swift
case .enterDrawer:
    return CommandSpec(
        command: self,
        label: "Enter Drawer",
        icon: "rectangle.bottomhalf.filled",
        helpText: "Open the active drawer and focus its selected pane",
        appliesTo: [.pane],
        visibleWhen: [.hasActivePane],
        commandBarGroupName: "Pane",
        commandBarGroupPriority: CommandBarGroupPriority.pane,
        isHiddenInCommandBar: true
    )
case .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown, .focusDrawerPaneRight:
    return CommandSpec(
        command: self,
        label: "Move Drawer Focus",
        icon: "arrow.up.left.and.arrow.down.right",
        helpText: "Move selection within the active drawer",
        appliesTo: [.pane],
        visibleWhen: [.hasActivePane, .hasDrawerPanes],
        commandBarGroupName: "Pane",
        commandBarGroupPriority: CommandBarGroupPriority.pane,
        isHiddenInCommandBar: true
    )
```

```swift
func keyDownDecision(
    keyCode: UInt16,
    modifierFlags: NSEvent.ModifierFlags,
    charactersIgnoringModifiers: String?
) -> KeyDownDecision {
    if keyCode == 53 { return .deactivateAndConsume }

    let normalizedModifiers = modifierFlags.intersection(.deviceIndependentFlagsMask)
    if normalizedModifiers.contains(.command) {
        return .passThrough
    }

    if normalizedModifiers == [.option],
       ["i", "j", "k", "l"].contains(charactersIgnoringModifiers?.lowercased() ?? "")
    {
        return .passThrough
    }

    let nonSemanticArrowModifiers: NSEvent.ModifierFlags = [.numericPad, .function]
    let sanitizedModifiers = modifierFlags.subtracting(nonSemanticArrowModifiers)
    guard
        let trigger = ShortcutDecoder.decode(
            keyCode: keyCode,
            modifierFlags: sanitizedModifiers,
            charactersIgnoringModifiers: charactersIgnoringModifiers
        ),
        let shortcut = ShortcutDecoder.shortcut(for: trigger, in: .managementLayer)
    else {
        return .consume
    }
    return shortcut == .managementLayerExit ? .deactivateAndConsume : .dispatch(shortcut)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --build-path .build-agent-drawer-navigation --filter 'ShortcutCatalogTests|ManagementLayerTests'
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Commands/AppCommand.swift Sources/AgentStudio/App/Commands/AppShortcut.swift Sources/AgentStudio/App/Commands/AppCommand+Definitions.swift Sources/AgentStudio/App/Lifecycle/ManagementLayerMonitor.swift Tests/AgentStudioTests/App/ShortcutCatalogTests.swift Tests/AgentStudioTests/App/ManagementLayerTests.swift
git commit -m "feat: recover drawer keyboard commands and empty drawer rules

Co-authored-by: Codex <noreply@openai.com>"
```

## Task 5: Make Focus Routing Drawer-Aware In The Normal Command Pipeline

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Modify: `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`

- [ ] **Step 1: Write the failing focus-routing tests**

```swift
@Test("option-j and option-l stay main-row movement outside drawers")
func executeFocusPaneLeftRight_outsideDrawerStaysInMainRow() {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let first = harness.store.createPane(source: .floating(launchDirectory: nil, title: "First"))
    let second = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Second"))
    let tab = Tab(paneId: first.id)
    harness.store.appendTab(tab)
    harness.store.insertPane(second.id, inTab: tab.id, at: first.id, direction: .horizontal, position: .after)
    harness.store.setActiveTab(tab.id)
    harness.store.setActivePane(second.id, inTab: tab.id)

    harness.controller.execute(.focusPaneLeft)

    #expect(harness.store.tab(tab.id)?.activePaneId == first.id)
}

@Test("enterDrawer focuses active drawer pane when drawer has panes")
func executeEnterDrawer_focusesActiveDrawerPane() {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
    let tab = Tab(paneId: parent.id)
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)
    let drawerPane = try! #require(harness.store.addDrawerPane(to: parent.id))

    harness.controller.execute(.enterDrawer)

    #expect(harness.store.pane(parent.id)?.drawer?.activePaneId == drawerPane.id)
}

@Test("focusDrawerPaneDown is a no-op when no drawer neighbor exists")
func executeFocusDrawerPaneDown_withoutNeighbor_keepsSelection() {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
    let tab = Tab(paneId: parent.id)
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)
    let drawerPane = try! #require(harness.store.addDrawerPane(to: parent.id))
    harness.store.setActiveDrawerPane(drawerPane.id, in: parent.id)

    harness.controller.execute(.focusDrawerPaneDown)

    #expect(harness.store.pane(parent.id)?.drawer?.activePaneId == drawerPane.id)
}

@Test("management layer create shortcut still works once option-ijkl are passed through")
func executeManagementLayerCreateTerminal_openEmptyDrawer_createsFirstDrawerPane() {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
    let tab = Tab(paneId: parent.id)
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)
    harness.store.toggleDrawer(for: parent.id)
    atom(\.managementLayer).activate()

    harness.controller.execute(.managementLayerCreateTerminal)

    #expect(harness.store.pane(parent.id)?.drawer?.paneIds.count == 1)
}

@Test("managementLayerEnterDrawer enters the same drawer keyboard scope as enterDrawer")
func executeManagementLayerEnterDrawer_focusesActiveDrawerPane() {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
    let tab = Tab(paneId: parent.id)
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)
    let drawerPane = try! #require(harness.store.addDrawerPane(to: parent.id))

    harness.controller.execute(.managementLayerEnterDrawer)

    #expect(harness.store.pane(parent.id)?.drawer?.activePaneId == drawerPane.id)
}

@Test("bare d outside management mode creates the first drawer pane only when the empty drawer owns neutral focus")
func rawD_openEmptyDrawerOutsideManagement_createsFirstDrawerPane() {
    let harness = makeHarness()
    defer { try? FileManager.default.removeItem(at: harness.tempDir) }

    let parent = harness.store.createPane(source: .floating(launchDirectory: nil, title: "Parent"))
    let tab = Tab(paneId: parent.id)
    harness.store.appendTab(tab)
    harness.store.setActiveTab(tab.id)
    harness.store.toggleDrawer(for: parent.id)
    harness.view.window?.makeFirstResponder(harness.view)

    let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "d",
        charactersIgnoringModifiers: "d",
        isARepeat: false,
        keyCode: 2
    )!

    _ = harness.controller.performKeyEquivalent(with: event)

    #expect(harness.store.pane(parent.id)?.drawer?.paneIds.count == 1)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --build-path .build-agent-drawer-navigation --filter 'PaneTabViewControllerCommandTests'
```

Expected:

```text
FAIL because scope-aware `⌥IJKL` routing and unified keyboard scope are not implemented yet
```

- [ ] **Step 3: Implement the minimal focus-routing changes**

```swift
private enum KeyboardNavigationScope: Equatable {
    case inactive
    case drawer(parentPaneId: UUID)
}

private var keyboardNavigationScope: KeyboardNavigationScope = .inactive

private func scopeAwarePaneCommand(for trigger: ShortcutTrigger) -> AppCommand? {
    let isInDrawerScope: Bool = {
        if case .drawer = keyboardNavigationScope { return true }
        return false
    }()
    switch trigger {
    case .init(key: .character(.i), modifiers: [.option]):
        return isInDrawerScope ? .focusDrawerPaneUp : nil
    case .init(key: .character(.j), modifiers: [.option]):
        return isInDrawerScope ? .focusDrawerPaneLeft : .focusPaneLeft
    case .init(key: .character(.k), modifiers: [.option]):
        return isInDrawerScope ? .focusDrawerPaneDown : .enterDrawer
    case .init(key: .character(.l), modifiers: [.option]):
        return isInDrawerScope ? .focusDrawerPaneRight : .focusPaneRight
    default:
        return nil
    }
}
```

```swift
arrangementBarEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
    guard let self else { return event }
    guard self.view.window?.isKeyWindow == true else { return event }
    self.syncDrawerKeyboardScopeFromLiveState()
    if self.shouldCreateFirstDrawerPane(from: event) {
        CommandDispatcher.shared.dispatch(.addDrawerPane)
        return nil
    }
    if let trigger = ShortcutDecoder.decode(event: event),
       let command = scopeAwarePaneCommand(for: trigger),
       CommandDispatcher.shared.canDispatch(command)
    {
        CommandDispatcher.shared.dispatch(command)
        return nil
    }
    if let trigger = ShortcutDecoder.decode(event: event),
       let shortcut = ShortcutDecoder.shortcut(for: trigger, in: .global),
       CommandDispatcher.shared.canDispatch(shortcut.command)
    {
        CommandDispatcher.shared.dispatch(shortcut.command)
        return nil
    }
    return event
}
```

```swift
private func shouldCreateFirstDrawerPane(from event: NSEvent) -> Bool {
    guard
        atom(\.managementLayer).isActive == false,
        event.charactersIgnoringModifiers?.lowercased() == "d",
        event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
        view.window?.firstResponder == view,
        let activeTabId = store.tabLayoutAtom.activeTabId,
        let parentPaneId = store.tabLayoutAtom.tab(activeTabId)?.activePaneId,
        let drawer = store.paneAtom.pane(parentPaneId)?.drawer,
        drawer.isExpanded,
        drawer.paneIds.isEmpty
    else {
        return false
    }
    return true
}

private func clearDrawerKeyboardScope() {
    keyboardNavigationScope = .inactive
}

private func enterDrawerKeyboardScope(parentPaneId: UUID) {
    keyboardNavigationScope = .drawer(parentPaneId: parentPaneId)
}

private func syncDrawerKeyboardScopeFromLiveState() {
    guard case .drawer(let parentPaneId) = keyboardNavigationScope else { return }
    guard store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == true else {
        clearDrawerKeyboardScope()
        return
    }
}
```

```swift
case .enterDrawer:
    guard let activeTabId = store.tabLayoutAtom.activeTabId,
          let parentPaneId = store.tabLayoutAtom.tab(activeTabId)?.activePaneId
    else { return }
    if store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == false {
        dispatchAction(.toggleDrawer(paneId: parentPaneId))
    }
    enterDrawerKeyboardScope(parentPaneId: parentPaneId)
    if let drawerPaneId = store.paneAtom.pane(parentPaneId)?.drawer?.activePaneId {
        handlePaneFocusTrigger(.drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)))
    }
    syncDrawerKeyboardScopeFromLiveState()

case .managementLayerEnterDrawer:
    guard let activeTabId = store.tabLayoutAtom.activeTabId,
          let parentPaneId = store.tabLayoutAtom.tab(activeTabId)?.activePaneId
    else { return }
    if store.paneAtom.pane(parentPaneId)?.drawer?.isExpanded == false {
        dispatchAction(.toggleDrawer(paneId: parentPaneId))
    }
    enterDrawerKeyboardScope(parentPaneId: parentPaneId)
    if let drawerPaneId = store.paneAtom.pane(parentPaneId)?.drawer?.activePaneId {
        handlePaneFocusTrigger(.drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: drawerPaneId)))
    }
    syncDrawerKeyboardScopeFromLiveState()

case .focusDrawerPaneUp, .focusDrawerPaneLeft, .focusDrawerPaneDown, .focusDrawerPaneRight:
    guard case .drawer(let parentPaneId) = drawerKeyboardScope else { return }
    guard let drawerPaneId = store.paneAtom.pane(parentPaneId)?.drawer?.activePaneId else { return }
    let direction: FocusDirection = switch command {
    case .focusDrawerPaneUp: .up
    case .focusDrawerPaneLeft: .left
    case .focusDrawerPaneDown: .down
    case .focusDrawerPaneRight: .right
    default: .left
    }
    let targetPaneId = store.paneAtom.pane(parentPaneId)?
        .drawer?
        .layout
        .neighbor(of: drawerPaneId, direction: direction)
    guard let targetPaneId else { return }
    handlePaneFocusTrigger(.drawer(.selectPane(parentPaneId: parentPaneId, drawerPaneId: targetPaneId)))

case .focusPaneLeft, .focusPaneRight:
    clearDrawerKeyboardScope()
    guard let trigger = makePaneKeyboardFocusTrigger(for: command) else { return }
    handlePaneFocusTrigger(.keyboard(trigger))

case .selectTab, .focusPane:
    clearDrawerKeyboardScope()
    return
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --build-path .build-agent-drawer-navigation --filter 'PaneTabViewControllerCommandTests'
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/PaneTabViewController.swift Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift
git commit -m "feat: route drawer focus through pane focus system

Co-authored-by: Codex <noreply@openai.com>"
```

## Task 6: Make Drawer Editing Actually Realize `N x 2`

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Create: `Sources/AgentStudio/Core/Views/Drawer/DrawerDropZone.swift`
- Create: `Sources/AgentStudio/Core/Views/Drawer/DrawerPaneDragCoordinator.swift`
- Modify: `Tests/AgentStudioTests/Core/Actions/DrawerCommandIntegrationTests.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/WorkspaceStoreDrawerTests.swift`
- Create: `Tests/AgentStudioTests/Core/Views/Drawer/DrawerDropZoneTests.swift`

- [ ] **Step 1: Write the failing grid-edit tests**

```swift
@Test
func test_insertDrawerPane_verticalAfter_rendersBottomRow() {
    let (parentPaneId, _) = createParentPaneInTab()
    let first = store.addDrawerPane(to: parentPaneId)!

    executor.execute(
        .insertDrawerPane(
            parentPaneId: parentPaneId,
            targetDrawerPaneId: first.id,
            direction: .down
        )
    )

    let drawer = try #require(store.pane(parentPaneId)?.drawer)
    #expect(drawer.layout.bottomRow != nil)
}

@Test
func test_moveDrawerPane_verticalDrop_preservesTwoRowLegality() {
    let (parentPaneId, _) = createParentPaneInTab()
    let first = store.addDrawerPane(to: parentPaneId)!
    let second = store.addDrawerPane(to: parentPaneId)!
    _ = store.insertDrawerPane(
        in: parentPaneId,
        at: first.id,
        direction: .vertical,
        position: .after,
        parentFallbackCWD: nil
    )

    executor.execute(
        .moveDrawerPane(
            parentPaneId: parentPaneId,
            drawerPaneId: second.id,
            targetDrawerPaneId: first.id,
            direction: .down
        )
    )

    let drawer = try #require(store.pane(parentPaneId)?.drawer)
    #expect(drawer.layout.bottomRow?.contains(second.id) == true)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --build-path .build-agent-drawer-navigation --filter 'DrawerCommandIntegrationTests|WorkspaceStoreDrawerTests'
```

Expected:

```text
FAIL because the drawer UI and drag/edit path still only realize a flat strip
```

- [ ] **Step 3: Implement the minimal drawer-grid editing path**

```swift
struct DrawerPanel: View {
    let layout: DrawerGridLayout

    var body: some View {
        if layout.paneIds.isEmpty {
            VStack(spacing: 12) {
                addDrawerButton
                Text(managementLayer.isActive ? "Press P to add the first drawer pane" : "Press D to add the first drawer pane")
            }
        } else {
            VStack(spacing: DrawerLayout.panelContentPadding) {
                FlatPaneStripContent(
                    layout: layout.topRow,
                    tabId: tabId,
                    activePaneId: activePaneId,
                    minimizedPaneIds: minimizedPaneIds,
                    closeTransitionCoordinator: closeTransitionCoordinator,
                    actionDispatcher: drawerActionDispatcher,
                    onPaneFocusTrigger: onPaneFocusTrigger,
                    store: store,
                    repoCache: repoCache,
                    viewRegistry: viewRegistry,
                    coordinateSpaceName: Self.drawerDropCoordinateSpace,
                    useDrawerFramePreference: true,
                    onOpenPaneGitHub: onOpenPaneGitHub
                )
                if let bottomRow = layout.bottomRow {
                    FlatPaneStripContent(
                        layout: bottomRow,
                        tabId: tabId,
                        activePaneId: activePaneId,
                        minimizedPaneIds: minimizedPaneIds,
                        closeTransitionCoordinator: closeTransitionCoordinator,
                        actionDispatcher: drawerActionDispatcher,
                        onPaneFocusTrigger: onPaneFocusTrigger,
                        store: store,
                        repoCache: repoCache,
                        viewRegistry: viewRegistry,
                        coordinateSpaceName: Self.drawerDropCoordinateSpace,
                        useDrawerFramePreference: true,
                        onOpenPaneGitHub: onOpenPaneGitHub
                    )
                }
            }
        }
    }
}
```

```swift
enum DrawerDropZone: String, Equatable, CaseIterable {
    case left
    case right
    case top
    case bottom
}
```

```swift
struct DrawerPaneDragCoordinator {
    // Drawer-only hit testing resolves top / bottom as well as left / right.
    // Main-pane drag routing stays on the existing Split DropZone model.
}
```

```swift
private static func splitDirection(for zone: DrawerDropZone) -> SplitNewDirection {
    switch zone {
    case .left: .left
    case .right: .right
    case .top: .up
    case .bottom: .down
    }
}
```

```swift
// When the drawer already has two rows, DrawerCommandValidator remains the
// authoritative legality check. The drawer UI should ask the validator before
// showing a top / bottom drop target as active.
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --build-path .build-agent-drawer-navigation --filter 'DrawerCommandIntegrationTests|WorkspaceStoreDrawerTests'
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift Sources/AgentStudio/Core/Views/Drawer/DrawerDropZone.swift Sources/AgentStudio/Core/Views/Drawer/DrawerPaneDragCoordinator.swift Tests/AgentStudioTests/Core/Actions/DrawerCommandIntegrationTests.swift Tests/AgentStudioTests/Core/Stores/WorkspaceStoreDrawerTests.swift Tests/AgentStudioTests/Core/Views/Drawer/DrawerDropZoneTests.swift
git commit -m "feat: enable drawer grid editing

Co-authored-by: Codex <noreply@openai.com>"
```

## Task 7: Add Explicit Drawer Detach And The Management-Mode Button

**Files:**
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift`
- Modify: `Sources/AgentStudio/Core/Actions/UIActionPresentation.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift`
- Modify: `Tests/AgentStudioTests/Core/Actions/DrawerCommandIntegrationTests.swift`
- Create: `Tests/AgentStudioTests/Core/Actions/UIActionPresentationTests.swift`

- [ ] **Step 1: Write the failing detach tests**

```swift
@Test
func test_detachDrawerPane_promotesPaneToParentRight() {
    let (parentPaneId, tabId) = createParentPaneInTab()
    let drawerPane = store.addDrawerPane(to: parentPaneId)!

    executor.execute(.detachDrawerPane(parentPaneId: parentPaneId, drawerPaneId: drawerPane.id))

    let tab = try #require(store.tab(tabId))
    #expect(tab.paneIds == [parentPaneId, drawerPane.id])
    #expect(store.pane(parentPaneId)?.drawer?.paneIds.contains(drawerPane.id) == false)
    #expect(store.pane(drawerPane.id)?.isDrawerChild == false)
}

@Test
func detachDrawerPaneActionSpec_hasStableLabelAndIcon() {
    let spec = LocalActionSpec.detachDrawerPane.actionSpec

    #expect(spec.label == "Detach Drawer Pane")
    #expect(spec.helpText == "Move this drawer pane into the parent tab on the right")
    #expect(spec.icon == .system("arrow.up.right.square"))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --build-path .build-agent-drawer-navigation --filter 'DrawerCommandIntegrationTests|UIActionPresentationTests'
```

Expected:

```text
FAIL because drawer detach is still destructive and the management-mode detach affordance does not exist yet
```

- [ ] **Step 3: Implement the minimal detach flow and button**

```swift
func detachDrawerPane(_ drawerPaneId: UUID, from parentPaneId: UUID) -> Pane? {
    guard var drawerPane = panes[drawerPaneId], drawerPane.parentPaneId == parentPaneId else { return nil }

    panes[parentPaneId]!.withDrawer { drawer in
        drawer.paneIds.removeAll { $0 == drawerPaneId }
        drawer.minimizedPaneIds.remove(drawerPaneId)
        drawer.layout = drawer.layout.removing(paneId: drawerPaneId) ?? DrawerGridLayout()
        if drawer.activePaneId == drawerPaneId {
            drawer.activePaneId = drawer.paneIds.first
        }
    }

    drawerPane.kind = .layout(drawer: Drawer())
    panes[drawerPaneId] = drawerPane
    return drawerPane
}
```

```swift
case .detachDrawerPane(let parentPaneId, let drawerPaneId):
    guard let tabId = store.tabLayoutAtom.tabContaining(paneId: parentPaneId)?.id else {
        Self.logger.warning("detachDrawerPane: parent pane \(parentPaneId) is not in a visible tab")
        return
    }

    guard store.paneAtom.detachDrawerPane(drawerPaneId, from: parentPaneId) != nil else {
        Self.logger.warning("detachDrawerPane: failed releasing drawer pane \(drawerPaneId)")
        return
    }
    store.tabLayoutAtom.insertPane(
        drawerPaneId,
        inTab: tabId,
        at: parentPaneId,
        direction: .horizontal,
        position: .after
    )
    focusVisiblePaneHost(drawerPaneId)
```

```swift
enum LocalActionSpec {
    case detachDrawerPane

    var actionSpec: ActionSpec {
        switch self {
        case .detachDrawerPane:
            return ActionSpec(
                label: "Detach Drawer Pane",
                helpText: "Move this drawer pane into the parent tab on the right",
                icon: .system("arrow.up.right.square")
            )
        }
    }
}
```

```swift
if managementLayer.isActive, let activeDrawerPaneId = drawer.activePaneId {
    Button {
        action(.detachDrawerPane(parentPaneId: parentPaneId, drawerPaneId: activeDrawerPaneId))
    } label: {
        Label(LocalActionSpec.detachDrawerPane.actionSpec.label, systemImage: "arrow.up.right.square")
    }
    .help(LocalActionSpec.detachDrawerPane.actionSpec.helpText)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:

```bash
swift test --build-path .build-agent-drawer-navigation --filter 'DrawerCommandIntegrationTests|UIActionPresentationTests'
```

Expected:

```text
PASS
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Coordination/PaneCoordinator+ActionExecution.swift Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspacePaneAtom.swift Sources/AgentStudio/Core/Actions/UIActionPresentation.swift Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift Sources/AgentStudio/Core/Views/Splits/PaneLeafContainer.swift Tests/AgentStudioTests/Core/Actions/DrawerCommandIntegrationTests.swift Tests/AgentStudioTests/Core/Actions/UIActionPresentationTests.swift
git commit -m "feat: add explicit drawer detach action

Co-authored-by: Codex <noreply@openai.com>"
```

## Task 8: Run Full Verification And Lock The Recovery

**Files:**
- Modify: `docs/superpowers/specs/2026-04-17-drawer-navigation-and-detach-design.md` if implementation drifted from the recovered design while keeping behavior intact
- Modify: `docs/superpowers/plans/2026-04-17-drawer-navigation-and-detach.md` only if task sequencing or file ownership changed during implementation

- [ ] **Step 1: Run the focused test groups one more time**

Run:

```bash
swift test --build-path .build-agent-drawer-navigation --filter 'DrawerGridLayoutTests|WorkspaceStoreDrawerTests|ActionValidatorTests|ActionValidatorOwnershipTests|DrawerCommandIntegrationTests|ShortcutCatalogTests|ManagementLayerTests|PaneTabViewControllerCommandTests|UIActionPresentationTests'
```

Expected:

```text
PASS
```

- [ ] **Step 2: Run the project verification commands**

Run:

```bash
mise run test
mise run lint
mise run build
```

Expected:

```text
All commands exit 0
```

- [ ] **Step 3: Visually verify the management-mode detach button and drawer focus behavior**

Run:

```bash
pkill -9 -f ".build/debug/AgentStudio"
.build/debug/AgentStudio &
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo see --app "PID:$PID" --json
```

Expected:

```text
The app is running and the drawer management affordances are visible for manual inspection
```

- [ ] **Step 4: Update the recovered docs only if implementation proved a naming mismatch**

```markdown
- Keep the spec aligned with the shipped command names.
- Keep the plan aligned with the actual file paths used.
- Do not add new scope here.
```

- [ ] **Step 5: Commit the final verified slice**

```bash
git add docs/superpowers/specs/2026-04-17-drawer-navigation-and-detach-design.md docs/superpowers/plans/2026-04-17-drawer-navigation-and-detach.md Sources Tests
git commit -m "feat: ship drawer navigation and detach flow

Co-authored-by: Codex <noreply@openai.com>"
```

## Self-Review Checklist

- Spec coverage: every recovered rule from the approved design has an implementation task.
  - `⌥I` inert outside drawers: Task 4 and Task 5
  - `⌥J/⌥L` main-row movement outside drawers: Task 4 and Task 5
  - `⌥K` enters drawer scope: Task 4 and Task 5
  - drawer-scoped `⌥IJKL` directional movement: Task 1, Task 4, Task 5
  - drawer-only `N x 2` layout: Task 1, Task 2, Task 3, Task 6
  - empty-drawer create rules: Task 4 and Task 5
  - explicit detach-to-parent-right: Task 3 and Task 7
  - management-mode detach affordance: Task 7
  - command-bar targeted drawer selection remains explicit via `navigateDrawerPane`: Task 4
- Placeholder scan: no `TODO`, `TBD`, “implement later”, or “add appropriate validation” placeholders remain.
- Type consistency: the plan uses one stable naming set: `DrawerGridLayout`, `enterDrawer`, `focusDrawerPaneUp/Left/Down/Right`, `KeyboardNavigationScope`, `DrawerDropZone`, `DrawerPaneDragCoordinator`, and `detachDrawerPane`.
