# Tab Bar Center Drop Block Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three-zone tab-drop targeting so dragging onto the center third of a tab shows a forbidden affordance and does not allow drop, while the left and right thirds still mean insert-before and insert-after.

**Architecture:** Keep hover-time targeting in the tab-bar drag UI, not in the validator. The tab bar should resolve pointer location into a richer tab-drop target enum (`insertBefore`, `forbiddenCenter`, `insertAfter`) and render feedback from that enum. Drop-time behavior should remain in the existing action pipeline: only valid left/right zones produce tab insertion actions; center-zone produces no action at all.

**Tech Stack:** SwiftUI, AppKit drag handling in `DraggableTabBarHostingView`, Swift Testing, existing tab bar adapter + pane drop planner

---

## File Structure

### Files to modify

```text
Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift
├─ currently stores transient drag UI state as:
│  ├─ draggingTabId: UUID?
│  └─ dropTargetIndex: Int?
└─ will own a richer transient drop target model

Sources/AgentStudio/App/Panes/TabBar/DraggableTabBarHostingView.swift
├─ owns drag session hit testing for tab reordering
├─ currently computes only integer insertion index
└─ should compute left / center / right thirds from tab frames

Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift
├─ renders tab pills
├─ currently renders only before/after insertion affordances
└─ should render forbidden center feedback on the hovered tab

Tests/AgentStudioTests/Core/Views/TabBarPaneDropContractTests.swift
├─ contract tests for tab bar drag/drop semantics
└─ should cover center-third forbidden targeting

Tests/AgentStudioTests/App/PaneTabViewControllerDropRoutingTests.swift
├─ integration-ish drop routing tests
└─ should prove center-third drops do not dispatch move/extract actions

Tests/AgentStudioTests/Core/Views/TabBarAdapterTests.swift
├─ transient tab bar drag state tests
└─ should cover the new drop target enum state
```

### New types to add

```text
TabBarDropTarget
├─ insertBefore(tabId: UUID, targetIndex: Int)
├─ forbiddenCenter(tabId: UUID)
└─ insertAfter(tabId: UUID, targetIndex: Int)

TabBarHoverZone
├─ leftThird
├─ centerThird
└─ rightThird
```

This keeps the UI model honest:
- `dropTargetIndex` is too weak for the desired behavior
- center-third is not “some index”; it is an explicit forbidden state

---

## Current Behavior Map

```text
Current drag flow

mouse drag over tab bar
└─ DraggableTabBarHostingView.dropIndexAtPoint(...)
   └─ Int? insertion index
      ├─ nil      -> no target
      └─ integer  -> insert before/after

UI rendering
└─ CustomTabBar
   └─ uses adapter.dropTargetIndex to show left/right insertion markers

Drop execution
└─ valid insertion index
   └─ reordered tab / extracted-pane-then-move action
```

Target flow:

```text
mouse drag over a tab frame
└─ resolve zone within tab
   ├─ left third   -> TabBarDropTarget.insertBefore
   ├─ center third -> TabBarDropTarget.forbiddenCenter
   └─ right third  -> TabBarDropTarget.insertAfter

UI rendering
├─ insertBefore / insertAfter -> existing insertion marker
└─ forbiddenCenter            -> forbidden affordance on hovered tab

drop execution
├─ insertBefore / insertAfter -> existing action path
└─ forbiddenCenter            -> no action
```

This does **not** go through `WorkspaceCommandValidator` for hover-time behavior. The validator remains a backstop for resolved commands, but center-zone should never create a drop action in the first place.

---

## Task 1: Introduce A Rich Tab Drop Target Model

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift`
- Test: `Tests/AgentStudioTests/Core/Views/TabBarAdapterTests.swift`

- [ ] **Step 1: Add failing adapter tests for richer transient drag state**

Add tests that express the new state shape:

```swift
@Test
func test_transientState_dropTarget_insertBefore() {
    let adapter = TabBarAdapter(store: makeStore(), repoCache: RepoCacheAtom())
    let tabId = UUID()

    adapter.dropTarget = .insertBefore(tabId: tabId, targetIndex: 2)

    #expect(adapter.dropTarget == .insertBefore(tabId: tabId, targetIndex: 2))
}

@Test
func test_transientState_dropTarget_forbiddenCenter() {
    let adapter = TabBarAdapter(store: makeStore(), repoCache: RepoCacheAtom())
    let tabId = UUID()

    adapter.dropTarget = .forbiddenCenter(tabId: tabId)

    #expect(adapter.dropTarget == .forbiddenCenter(tabId: tabId))
}
```

- [ ] **Step 2: Run the focused adapter tests and watch them fail**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "TabBarAdapterTests"
```

Expected:
- compile failure because `dropTarget` / `TabBarDropTarget` do not exist yet

- [ ] **Step 3: Replace `dropTargetIndex` with a richer enum**

In `TabBarAdapter.swift`, replace:

```swift
var dropTargetIndex: Int?
```

with:

```swift
enum TabBarDropTarget: Equatable {
    case insertBefore(tabId: UUID, targetIndex: Int)
    case forbiddenCenter(tabId: UUID)
    case insertAfter(tabId: UUID, targetIndex: Int)
}

var dropTarget: TabBarDropTarget?
```

Keep `draggingTabId` unchanged.

- [ ] **Step 4: Run the focused adapter tests and watch them pass**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "TabBarAdapterTests"
```

Expected:
- `TabBarAdapterTests` pass

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift Tests/AgentStudioTests/Core/Views/TabBarAdapterTests.swift
git commit -m "refactor: add explicit tab bar drop target model"
```

---

## Task 2: Resolve Left / Center / Right Thirds In Drag Hit Testing

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/TabBar/DraggableTabBarHostingView.swift`
- Test: `Tests/AgentStudioTests/Core/Views/TabBarPaneDropContractTests.swift`

- [ ] **Step 1: Add failing contract tests for the three hover zones**

Add tests for target resolution semantics:

```swift
@Test
func centerThird_ofTab_resolvesForbiddenCenter() {
    let tabId = UUID()
    let frame = CGRect(x: 100, y: 0, width: 300, height: 36)

    let result = TabBarDropResolver.resolve(
        point: CGPoint(x: 250, y: 18),
        tabFrames: [tabId: frame],
        orderedTabIds: [tabId]
    )

    #expect(result == .forbiddenCenter(tabId: tabId))
}

@Test
func leftThird_ofTab_resolvesInsertBefore() {
    let first = UUID()
    let second = UUID()
    let frames = [
        first: CGRect(x: 0, y: 0, width: 300, height: 36),
        second: CGRect(x: 320, y: 0, width: 300, height: 36),
    ]

    let result = TabBarDropResolver.resolve(
        point: CGPoint(x: 340, y: 18),
        tabFrames: frames,
        orderedTabIds: [first, second]
    )

    #expect(result == .insertBefore(tabId: second, targetIndex: 1))
}

@Test
func rightThird_ofTab_resolvesInsertAfter() {
    let first = UUID()
    let second = UUID()
    let frames = [
        first: CGRect(x: 0, y: 0, width: 300, height: 36),
        second: CGRect(x: 320, y: 0, width: 300, height: 36),
    ]

    let result = TabBarDropResolver.resolve(
        point: CGPoint(x: 590, y: 18),
        tabFrames: frames,
        orderedTabIds: [first, second]
    )

    #expect(result == .insertAfter(tabId: second, targetIndex: 2))
}
```

- [ ] **Step 2: Run the contract tests and verify red**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "TabBarPaneDropContractTests"
```

Expected:
- fail because the resolver and zone model do not exist yet

- [ ] **Step 3: Add a pure resolver for tab hover zones**

Inside `DraggableTabBarHostingView.swift`, add a pure helper near the drag/drop logic:

```swift
private enum TabBarHoverZone {
    case leftThird
    case centerThird
    case rightThird
}

private enum TabBarDropResolver {
    static func resolve(
        point: CGPoint,
        tabFrames: [UUID: CGRect],
        orderedTabIds: [UUID]
    ) -> TabBarAdapter.TabBarDropTarget? {
        for (index, tabId) in orderedTabIds.enumerated() {
            guard let frame = tabFrames[tabId], frame.contains(point) else { continue }

            let relativeX = point.x - frame.minX
            let thirdWidth = frame.width / 3.0

            if relativeX < thirdWidth {
                return .insertBefore(tabId: tabId, targetIndex: index)
            }
            if relativeX > thirdWidth * 2.0 {
                return .insertAfter(tabId: tabId, targetIndex: index + 1)
            }
            return .forbiddenCenter(tabId: tabId)
        }
        return nil
    }
}
```

- [ ] **Step 4: Replace integer drop-index calculation with the richer resolver**

Replace the current `dropIndexAtPoint(...)` usage with the new resolver:

```swift
let dropTarget = TabBarDropResolver.resolve(
    point: dropPoint,
    tabFrames: currentTabFrames,
    orderedTabIds: orderedTabIds
)
tabBarAdapter?.dropTarget = dropTarget
```

and clear with:

```swift
tabBarAdapter?.dropTarget = nil
```

- [ ] **Step 5: Run the contract tests and verify green**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "TabBarPaneDropContractTests"
```

Expected:
- `TabBarPaneDropContractTests` pass

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/App/Panes/TabBar/DraggableTabBarHostingView.swift Tests/AgentStudioTests/Core/Views/TabBarPaneDropContractTests.swift
git commit -m "feat: resolve forbidden center tab drop zone"
```

---

## Task 3: Render Insert Markers Only On Valid Sides And Show Forbidden Center Feedback

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift`
- Test: `Tests/AgentStudioTests/Core/Views/TabBarPaneDropContractTests.swift`

- [ ] **Step 1: Add failing rendering-contract tests for UI interpretation of `TabBarDropTarget`**

Add tests at the contract layer for presentation mapping:

```swift
@Test
func forbiddenCenter_target_doesNotShowInsertBeforeOrAfter() {
    let tabId = UUID()
    let target = TabBarAdapter.TabBarDropTarget.forbiddenCenter(tabId: tabId)

    #expect(TabBarDropPresentation.showInsertBefore(target, tabId: tabId) == false)
    #expect(TabBarDropPresentation.showInsertAfter(target, tabId: tabId, isLastTab: true) == false)
    #expect(TabBarDropPresentation.isForbidden(target, tabId: tabId) == true)
}
```

- [ ] **Step 2: Run focused tests and verify red**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "TabBarPaneDropContractTests"
```

Expected:
- fail because `TabBarDropPresentation` does not exist yet

- [ ] **Step 3: Add a tiny presentation helper in `CustomTabBar.swift`**

Add:

```swift
private enum TabBarDropPresentation {
    static func showInsertBefore(_ target: TabBarAdapter.TabBarDropTarget?, tabId: UUID) -> Bool {
        guard case .insertBefore(let targetTabId, _) = target else { return false }
        return targetTabId == tabId
    }

    static func showInsertAfter(
        _ target: TabBarAdapter.TabBarDropTarget?,
        tabId: UUID,
        isLastTab: Bool
    ) -> Bool {
        guard case .insertAfter(let targetTabId, _) = target else { return false }
        return targetTabId == tabId && isLastTab
    }

    static func isForbidden(_ target: TabBarAdapter.TabBarDropTarget?, tabId: UUID) -> Bool {
        guard case .forbiddenCenter(let targetTabId) = target else { return false }
        return targetTabId == tabId
    }
}
```

- [ ] **Step 4: Use the richer target in tab rendering**

Replace:

```swift
showInsertBefore: adapter.dropTargetIndex == index
showInsertAfter: index == adapter.tabs.count - 1 && adapter.dropTargetIndex == adapter.tabs.count
```

with:

```swift
showInsertBefore: TabBarDropPresentation.showInsertBefore(adapter.dropTarget, tabId: tab.id),
showInsertAfter: TabBarDropPresentation.showInsertAfter(
    adapter.dropTarget,
    tabId: tab.id,
    isLastTab: index == adapter.tabs.count - 1
),
```

and add a new boolean to the pill view:

```swift
isForbiddenDropTarget: TabBarDropPresentation.isForbidden(adapter.dropTarget, tabId: tab.id)
```

- [ ] **Step 5: Add forbidden-center visual treatment to the tab pill**

In the tab pill view, add a visible “not allowed” treatment only for `isForbiddenDropTarget`.
Recommended minimal version:

```swift
.overlay {
    if isForbiddenDropTarget {
        RoundedRectangle(cornerRadius: AppStyle.barCornerRadius)
            .strokeBorder(Color.red.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .overlay {
                Image(systemName: "nosign")
                    .font(.system(size: AppStyle.textSm, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.8))
            }
    }
}
```

This keeps the signal explicit without inventing a new drag icon system.

- [ ] **Step 6: Run the tab bar contract tests and verify green**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "TabBarPaneDropContractTests|TabBarAdapterTests"
```

Expected:
- both suites pass

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift Tests/AgentStudioTests/Core/Views/TabBarPaneDropContractTests.swift Tests/AgentStudioTests/Core/Views/TabBarAdapterTests.swift
git commit -m "feat: show forbidden center drop state for tab drag"
```

---

## Task 4: Ensure Drop Release Produces No Action For Center-Zone Targets

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/TabBar/DraggableTabBarHostingView.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerDropRoutingTests.swift`

- [ ] **Step 1: Add failing drop-routing tests**

Add tests that prove center-zone hover does not become a move/extract action:

```swift
@Test
func tabDrag_forbiddenCenterDrop_doesNotDispatchMoveTab() {
    let harness = makeHarness()

    let result = harness.resolveTabBarDrop(
        dragSource: .tab(tabId: harness.tabA),
        target: .forbiddenCenter(tabId: harness.tabB)
    )

    #expect(result == nil)
}

@Test
func extractedPane_forbiddenCenterDrop_doesNotDispatchExtractThenMove() {
    let harness = makeHarness()

    let result = harness.resolveTabBarDrop(
        dragSource: .paneFromTab(paneId: harness.paneId, sourceTabId: harness.tabA),
        target: .forbiddenCenter(tabId: harness.tabB)
    )

    #expect(result == nil)
}
```

- [ ] **Step 2: Run the drop-routing tests and verify red**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "PaneTabViewControllerDropRoutingTests"
```

Expected:
- fail because center-zone targets still collapse into insertion behavior or the helper does not model them

- [ ] **Step 3: Gate drop release on valid insertion targets only**

In `DraggableTabBarHostingView.swift`, when finalizing a drop:

```swift
guard let dropTarget = tabBarAdapter?.dropTarget else { return }

switch dropTarget {
case .insertBefore(_, let targetIndex), .insertAfter(_, let targetIndex):
    // existing reorder / extract-then-move behavior
case .forbiddenCenter:
    return
}
```

Do not let `.forbiddenCenter` flow into `targetTabIndex`.

- [ ] **Step 4: Run the routing tests and verify green**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "PaneTabViewControllerDropRoutingTests"
```

Expected:
- pass

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/TabBar/DraggableTabBarHostingView.swift Tests/AgentStudioTests/App/PaneTabViewControllerDropRoutingTests.swift
git commit -m "fix: block center-third tab drops from dispatching actions"
```

---

## Task 5: Visual Verification And Full Regression Pass

**Files:**
- No code changes expected unless visual verification reveals a mismatch

- [ ] **Step 1: Build the app**

Run:

```bash
SWIFT_BUILD_DIR=".build-agent-$PPID" mise run build
```

Expected:
- build succeeds

- [ ] **Step 2: Launch the debug build**

Run:

```bash
".build-agent-$PPID/debug/AgentStudio" &
PID=$!
```

- [ ] **Step 3: Verify the three tab hover zones with Peekaboo**

Use Peekaboo to confirm:
- left third shows insert-left affordance
- center third shows forbidden affordance
- right third shows insert-right affordance
- dropping in center does nothing

Suggested commands:

```bash
peekaboo see --app "PID:$PID" --json
peekaboo click --app "PID:$PID" --coords "<x,y>"
```

- [ ] **Step 4: Run focused test suites**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "TabBarAdapterTests|TabBarPaneDropContractTests|PaneTabViewControllerDropRoutingTests"
```

Expected:
- all pass

- [ ] **Step 5: Run full project verification**

Run:

```bash
mise run test
mise run lint
```

Expected:
- `mise run test` exit `0`
- `mise run lint` exit `0`

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift Sources/AgentStudio/App/Panes/TabBar/DraggableTabBarHostingView.swift Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift Tests/AgentStudioTests/Core/Views/TabBarAdapterTests.swift Tests/AgentStudioTests/Core/Views/TabBarPaneDropContractTests.swift Tests/AgentStudioTests/App/PaneTabViewControllerDropRoutingTests.swift
git commit -m "test: cover center-blocked tab drag drop behavior"
```

---

## Notes For The Implementer

- Do **not** route center-zone rejection through `WorkspaceCommandValidator`. That is too late and the wrong layer.
- Do **not** overload `dropTargetIndex` to encode “forbidden.” That turns an index into a semantic mess.
- Keep the center-zone behavior tab-bar-local:
  - hover-time = richer UI target
  - drop-time = only left/right targets become actions
- Keep existing pane extract / tab move action generation for valid left/right insertion zones unchanged.

## Verification Summary

Final verification commands:

```bash
swift test --build-path ".build-agent-$PPID" --filter "TabBarAdapterTests|TabBarPaneDropContractTests|PaneTabViewControllerDropRoutingTests"
mise run test
mise run lint
```

Expected:
- tab-drop targeted suites pass
- full test suite passes
- lint passes

---

Plan complete and saved to [2026-04-16-tab-bar-center-drop-block-plan.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.minimize-panes-fixes/docs/superpowers/plans/2026-04-16-tab-bar-center-drop-block-plan.md). Two execution options:

1. Subagent-Driven (recommended)
2. Inline Execution

Which approach?*** End Patch
