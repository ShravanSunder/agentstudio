# Phase 2a + 2b Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add arrangement switching UI and drawer UI to Agent Studio, building on the existing model/store layer.

**Architecture:** All operations route through `PaneAction → ActionExecutor`. New UI surfaces (floating arrangement bar, drawer icon bar/panel) are SwiftUI overlay views hosted inside existing AppKit skeleton. New `AppCommand` cases registered in `CommandDispatcher` wire command bar and keyboard shortcuts to existing `PaneAction` cases.

**Tech Stack:** Swift, AppKit (skeleton), SwiftUI (UI), Combine (observation), XCTest

**Design Doc:** `docs/plans/2026-02-14-phase-2ab-design.md`

**Branch:** `window-system-3` (current)

---

## Prerequisites

Before starting, verify the build is clean:

```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
swift test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
```

Expected: BUILD OK, all 863+ tests pass.

---

## PHASE 2a: ARRANGEMENT UI

### Task 1: Add Arrangement AppCommands

**Files:**
- Modify: `Sources/AgentStudio/App/AppCommand.swift`

**Step 1: Add arrangement cases to AppCommand enum**

In `AppCommand.swift`, add after the `// Pane commands` section (line ~29):

```swift
// Arrangement commands
case switchArrangement
case saveArrangement
case deleteArrangement
case renameArrangement
```

**Step 2: Register CommandDefinitions**

In `CommandDispatcher.registerDefaults()` (line ~193), add after the pane command definitions:

```swift
// Arrangement commands
CommandDefinition(
    command: .switchArrangement,
    label: "Switch Arrangement",
    icon: "rectangle.3.group",
    appliesTo: [.tab]
),
CommandDefinition(
    command: .saveArrangement,
    label: "Save Arrangement As...",
    icon: "rectangle.3.group.fill",
    appliesTo: [.tab]
),
CommandDefinition(
    command: .deleteArrangement,
    label: "Delete Arrangement",
    icon: "rectangle.3.group.bubble",
    appliesTo: [.tab]
),
CommandDefinition(
    command: .renameArrangement,
    label: "Rename Arrangement",
    icon: "pencil",
    appliesTo: [.tab]
),
```

**Step 3: Build**

```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
```

**Step 4: Commit**

```bash
git add Sources/AgentStudio/App/AppCommand.swift
git commit -m "feat: add arrangement AppCommand cases and definitions"
```

---

### Task 2: Wire Arrangement AppCommands to PaneActions

**Files:**
- Modify: `Sources/AgentStudio/App/ActionExecutor.swift`
- Modify: `Sources/AgentStudio/App/TerminalTabViewController.swift` (where `CommandHandler` is implemented)

The `CommandHandler` protocol has `execute(_ command: AppCommand)` and `execute(_ command: AppCommand, target: UUID, targetType: SearchItemType)`. Find the existing `CommandHandler` implementation (likely in `TerminalTabViewController` or a coordinator) and add arrangement command handling.

**Step 1: Find the CommandHandler implementation**

```bash
grep -rn "func execute(_ command: AppCommand)" Sources/AgentStudio/
```

**Step 2: Add arrangement command cases**

In the `execute(_ command:)` method, add cases that resolve to `PaneAction`:

```swift
case .switchArrangement:
    // Handled via drill-in (target selection in command bar)
    break
case .saveArrangement:
    // Will be handled via floating bar or command bar input flow
    break
case .deleteArrangement:
    // Handled via drill-in
    break
case .renameArrangement:
    // Handled via drill-in
    break
```

In `execute(_ command:, target:, targetType:)`, add targeted handling:

```swift
case .switchArrangement:
    guard let tabId = store.activeTabId else { return }
    executor.execute(.switchArrangement(tabId: tabId, arrangementId: target))
case .deleteArrangement:
    guard let tabId = store.activeTabId else { return }
    executor.execute(.removeArrangement(tabId: tabId, arrangementId: target))
```

**Step 3: Make `switchArrangement` and `deleteArrangement` targetable**

In `CommandBarDataSource.isTargetableCommand()`, add:

```swift
case .switchArrangement, .deleteArrangement, .renameArrangement:
    return true
```

**Step 4: Build and test**

```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
swift test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
```

**Step 5: Commit**

```bash
git add Sources/AgentStudio/App/
git commit -m "feat: wire arrangement AppCommands to PaneAction dispatch"
```

---

### Task 3: Add Arrangement Items to CommandBarDataSource

**Files:**
- Modify: `Sources/AgentStudio/CommandBar/CommandBarDataSource.swift`
- Test: `Tests/AgentStudioTests/CommandBar/CommandBarDataSourceTests.swift`

**Step 1: Write failing test**

Add test that verifies arrangement commands appear in command bar when tab has custom arrangements:

```swift
func testArrangementCommandsAppearForTabWithMultipleArrangements() {
    // Arrange
    let store = makeTestStore()
    let tab = store.tabs[0]
    store.createArrangement(name: "coding", paneIds: Set(tab.paneIds), inTab: tab.id)
    let dispatcher = CommandDispatcher.shared

    // Act
    let items = CommandBarDataSource.items(scope: .commands, store: store, dispatcher: dispatcher)

    // Assert
    let arrangementItems = items.filter { $0.title.contains("Arrangement") }
    XCTAssertFalse(arrangementItems.isEmpty, "Arrangement commands should appear")
}
```

**Step 2: Run test to verify it fails**

```bash
swift test --filter "testArrangementCommandsAppear" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
```

**Step 3: Add `buildTargetLevel` support for arrangement commands**

In `CommandBarDataSource.buildTargetLevel(for:store:)`, add arrangement-specific target building. When command is `.switchArrangement`, list arrangements for the active tab as targets:

```swift
// After existing tab/pane target building
if def.command == .switchArrangement || def.command == .deleteArrangement || def.command == .renameArrangement {
    if let activeTabId = store.activeTabId, let tab = store.tab(activeTabId) {
        items = tab.arrangements.compactMap { arrangement in
            guard !arrangement.isDefault || def.command == .switchArrangement else { return nil }
            return CommandBarItem(
                id: "target-arrangement-\(arrangement.id.uuidString)",
                title: arrangement.name,
                subtitle: arrangement.isDefault ? "Default" : "\(arrangement.visiblePaneIds.count) panes",
                icon: arrangement.isDefault ? "rectangle.3.group" : "rectangle.3.group.fill",
                group: "Arrangements",
                groupPriority: 0,
                action: .dispatchTargeted(def.command, target: arrangement.id, targetType: .tab)
            )
        }
    }
}
```

Also add `.switchArrangement`, `.deleteArrangement`, `.renameArrangement` to `isTargetableCommand()`.

**Step 4: Run test to verify it passes**

```bash
swift test --filter "testArrangementCommandsAppear" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
```

**Step 5: Run all tests**

```bash
swift test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
```

**Step 6: Commit**

```bash
git add Sources/AgentStudio/CommandBar/CommandBarDataSource.swift Tests/
git commit -m "feat: add arrangement targets to command bar data source"
```

---

### Task 4: Add Arrangement Badge to Tab Bar

**Files:**
- Modify: `Sources/AgentStudio/Views/TabBarAdapter.swift`
- Modify: `Sources/AgentStudio/Views/CustomTabBar.swift`
- Test: `Tests/AgentStudioTests/App/TabBarAdapterTests.swift` (create if needed)

**Step 1: Extend TabBarItem with arrangement info**

In `TabBarAdapter.swift`, add to `TabBarItem`:

```swift
struct TabBarItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isSplit: Bool
    var displayTitle: String
    var activeArrangementName: String?  // nil when only default
    var arrangementCount: Int           // total arrangements (1 = default only)
}
```

**Step 2: Update TabBarAdapter.refresh() to populate arrangement fields**

```swift
private func refresh() {
    let storeTabs = store.tabs
    tabs = storeTabs.map { tab in
        let paneTitles = tab.paneIds.compactMap { paneId in
            store.pane(paneId)?.title
        }
        let displayTitle = paneTitles.count > 1
            ? paneTitles.joined(separator: " | ")
            : paneTitles.first ?? "Terminal"

        let activeArrangement = tab.activeArrangement
        let showArrangementName = tab.arrangements.count > 1 && !(activeArrangement?.isDefault ?? true)

        return TabBarItem(
            id: tab.id,
            title: paneTitles.first ?? "Terminal",
            isSplit: tab.isSplit,
            displayTitle: displayTitle,
            activeArrangementName: showArrangementName ? activeArrangement?.name : nil,
            arrangementCount: tab.arrangements.count
        )
    }
    activeTabId = store.activeTabId
}
```

**Step 3: Show arrangement badge in TabPillView**

In `CustomTabBar.swift`, inside `TabPillView.tabContent`, after the tab title `Text`:

```swift
// Arrangement badge (only when custom arrangement active)
if let arrangementName = tab.activeArrangementName {
    Text("· \(arrangementName)")
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
}
```

**Step 4: Build and verify**

```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
swift test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
```

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Views/TabBarAdapter.swift Sources/AgentStudio/Views/CustomTabBar.swift
git commit -m "feat: show arrangement badge on tab when custom arrangement active"
```

---

### Task 5: Add Arrangement Commands to Tab Context Menu

**Files:**
- Modify: `Sources/AgentStudio/Views/CustomTabBar.swift`

**Step 1: Add arrangement submenu to TabPillView context menu**

In `TabPillView`, inside the `.contextMenu` block (line ~99), add after the existing items:

```swift
Divider()

// Arrangement commands
Menu("Arrangements") {
    Button("Switch Arrangement...") { onCommand(.switchArrangement) }
    Button("Save Current As...") { onCommand(.saveArrangement) }
    Button("Delete Arrangement...") { onCommand(.deleteArrangement) }
    Button("Rename Arrangement...") { onCommand(.renameArrangement) }
}
```

**Step 2: Build**

```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
```

**Step 3: Commit**

```bash
git add Sources/AgentStudio/Views/CustomTabBar.swift
git commit -m "feat: add arrangement submenu to tab context menu"
```

---

### Task 6: Create Floating Arrangement Bar

**Files:**
- Create: `Sources/AgentStudio/Views/ArrangementBar.swift`
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift` (to host the overlay)

This is a SwiftUI overlay view that floats below the tab bar.

**Step 1: Create ArrangementBar SwiftUI view**

```swift
import SwiftUI

/// Floating arrangement bar that appears below the tab bar.
/// Shows arrangement chips for quick switching.
struct ArrangementBar: View {
    let arrangements: [ArrangementBarItem]
    let activeArrangementId: UUID?
    let onSwitch: (UUID) -> Void
    let onSaveNew: () -> Void
    let onDelete: (UUID) -> Void
    let onRename: (UUID) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(arrangements) { arrangement in
                ArrangementChip(
                    name: arrangement.name,
                    isActive: arrangement.id == activeArrangementId,
                    isDefault: arrangement.isDefault,
                    onSelect: { onSwitch(arrangement.id) },
                    onDelete: arrangement.isDefault ? nil : { onDelete(arrangement.id) },
                    onRename: { onRename(arrangement.id) }
                )
            }

            Button(action: onSaveNew) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(4)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        )
        .padding(.horizontal, 8)
    }
}

struct ArrangementBarItem: Identifiable {
    let id: UUID
    let name: String
    let isDefault: Bool
    let paneCount: Int
}

struct ArrangementChip: View {
    let name: String
    let isActive: Bool
    let isDefault: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?
    let onRename: () -> Void

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.white.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .contextMenu {
                Button("Rename...") { onRename() }
                if let onDelete {
                    Button("Delete", role: .destructive) { onDelete() }
                }
            }
    }
}
```

**Step 2: Build**

```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
```

**Step 3: Commit**

```bash
git add Sources/AgentStudio/Views/ArrangementBar.swift
git commit -m "feat: create floating ArrangementBar SwiftUI view"
```

---

### Task 7: Wire ArrangementBar into MainSplitViewController

**Files:**
- Modify: `Sources/AgentStudio/App/MainSplitViewController.swift`

The arrangement bar needs to be hosted as a floating overlay below the tab bar. This follows the same pattern as the command bar — an `NSHostingView` positioned over the main content.

**Step 1: Add arrangement bar state and hosting**

Add a published `isArrangementBarVisible` state, an `NSHostingView` for the arrangement bar, and position it below the tab bar. Toggle on Cmd+Opt.

**Step 2: Add Cmd+Opt keyboard shortcut**

Register the shortcut in `AppDelegate` or as a local key monitor that toggles `isArrangementBarVisible`.

**Step 3: Connect arrangement bar actions to PaneAction dispatch**

Each action in the bar dispatches through `ActionExecutor`:
- Chip click → `.switchArrangement(tabId:, arrangementId:)`
- [+] → `.createArrangement(tabId:, name:, paneIds:)` (with name input)
- Delete → `.removeArrangement(tabId:, arrangementId:)`
- Rename → `.renameArrangement(tabId:, arrangementId:, name:)`

**Step 4: Build and visual verify**

```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
```

Launch app, press Cmd+Opt, verify arrangement bar appears below tab bar.

**Step 5: Commit**

```bash
git add Sources/AgentStudio/App/MainSplitViewController.swift
git commit -m "feat: wire floating arrangement bar into main view controller"
```

---

### Task 8: Backgrounded Pane Surface Lifecycle

**Files:**
- Modify: `Sources/AgentStudio/App/ActionExecutor.swift`
- Modify: `Sources/AgentStudio/Services/TerminalViewCoordinator.swift`
- Test: `Tests/AgentStudioTests/App/ActionExecutorTests.swift` (extend existing)

When switching arrangements, panes not in the new arrangement should have their Ghostty surfaces detached. When they become visible again, surfaces reattach.

**Step 1: Write failing test**

```swift
func testSwitchArrangementDetachesSurfacesForHiddenPanes() {
    // Arrange: tab with 3 panes, custom arrangement with only 2
    // Act: switch to custom arrangement
    // Assert: the hidden pane's surface is detached (coordinator.teardownView called)
}
```

**Step 2: Implement surface detach/reattach in ActionExecutor.switchArrangement**

In the `.switchArrangement` case of `ActionExecutor`, after `store.switchArrangement()`:

```swift
case .switchArrangement(let tabId, let arrangementId):
    store.switchArrangement(to: arrangementId, inTab: tabId)

    // Detach surfaces for panes no longer visible
    guard let tab = store.tab(tabId),
          let arrangement = tab.arrangements.first(where: { $0.id == arrangementId }) else { break }
    let hiddenPaneIds = Set(tab.paneIds).subtracting(arrangement.visiblePaneIds)
    for paneId in hiddenPaneIds {
        coordinator.teardownView(for: paneId)
    }

    // Reattach surfaces for panes now visible
    for paneId in arrangement.visiblePaneIds {
        if viewRegistry.view(for: paneId) == nil, let pane = store.pane(paneId) {
            coordinator.createViewForContent(pane: pane)
        }
    }
```

**Step 3: Run tests**

```bash
swift test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
```

**Step 4: Commit**

```bash
git add Sources/AgentStudio/App/ActionExecutor.swift Sources/AgentStudio/Services/TerminalViewCoordinator.swift Tests/
git commit -m "feat: detach/reattach surfaces on arrangement switch"
```

---

## PHASE 2b: DRAWER UI

### Task 9: Add Drawer AppCommands

**Files:**
- Modify: `Sources/AgentStudio/App/AppCommand.swift`

**Step 1: Add drawer cases to AppCommand enum**

```swift
// Drawer commands
case addDrawerPane
case toggleDrawer
case navigateDrawerPane
case closeDrawerPane
```

**Step 2: Register CommandDefinitions**

```swift
// Drawer commands
CommandDefinition(
    command: .addDrawerPane,
    label: "Add Drawer Pane",
    icon: "rectangle.bottomhalf.inset.filled",
    appliesTo: [.pane]
),
CommandDefinition(
    command: .toggleDrawer,
    label: "Toggle Drawer",
    icon: "rectangle.expand.vertical",
    appliesTo: [.pane]
),
CommandDefinition(
    command: .navigateDrawerPane,
    label: "Navigate to Drawer Pane",
    icon: "arrow.down.to.line",
    appliesTo: [.pane]
),
CommandDefinition(
    command: .closeDrawerPane,
    label: "Close Drawer Pane",
    icon: "xmark.rectangle.portrait",
    appliesTo: [.pane]
),
```

**Step 3: Build**

```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
```

**Step 4: Commit**

```bash
git add Sources/AgentStudio/App/AppCommand.swift
git commit -m "feat: add drawer AppCommand cases and definitions"
```

---

### Task 10: Create DrawerIconBar SwiftUI View

**Files:**
- Create: `Sources/AgentStudio/Views/Drawer/DrawerIconBar.swift`

The icon bar is the narrow strip that appears at the bottom of a pane, with the trapezoid connector above it.

**Step 1: Create the view**

```swift
import SwiftUI

/// Icon bar at the bottom of a pane showing drawer pane icons.
/// Connected to the pane via a trapezoid visual bridge.
struct DrawerIconBar: View {
    let drawerPanes: [DrawerPaneItem]
    let activeDrawerPaneId: UUID?
    let onSelect: (UUID) -> Void
    let onAdd: () -> Void
    let onClose: (UUID) -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Trapezoid connector
            TrapezoidConnector()
                .fill(.ultraThinMaterial)
                .frame(height: 8)

            // Icon strip
            HStack(spacing: 4) {
                ForEach(drawerPanes) { pane in
                    DrawerPaneIcon(
                        pane: pane,
                        isActive: pane.id == activeDrawerPaneId,
                        onSelect: { onSelect(pane.id) },
                        onClose: { onClose(pane.id) }
                    )
                }

                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

struct DrawerPaneItem: Identifiable {
    let id: UUID
    let title: String
    let icon: String
}

struct DrawerPaneIcon: View {
    let pane: DrawerPaneItem
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    var body: some View {
        Image(systemName: pane.icon)
            .font(.system(size: 11))
            .foregroundStyle(isActive ? .primary : .secondary)
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? Color.white.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .contextMenu {
                Button("Close", role: .destructive, action: onClose)
            }
    }
}

/// Trapezoid shape that visually connects a pane to its drawer icon bar.
/// Wide at top (pane boundary), narrow at bottom (icon bar).
struct TrapezoidConnector: Shape {
    /// How much the sides taper inward (0 = rectangle, 1 = full taper).
    var taperRatio: CGFloat = 0.15

    func path(in rect: CGRect) -> Path {
        let inset = rect.width * taperRatio
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))                          // top-left (full width)
        path.addLine(to: CGPoint(x: rect.width, y: 0))              // top-right (full width)
        path.addLine(to: CGPoint(x: rect.width - inset, y: rect.height))  // bottom-right (narrower)
        path.addLine(to: CGPoint(x: inset, y: rect.height))         // bottom-left (narrower)
        path.closeSubpath()
        return path
    }
}
```

**Step 2: Build**

```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
```

**Step 3: Commit**

```bash
git add Sources/AgentStudio/Views/Drawer/
git commit -m "feat: create DrawerIconBar with trapezoid connector"
```

---

### Task 11: Create DrawerPanel SwiftUI View

**Files:**
- Create: `Sources/AgentStudio/Views/Drawer/DrawerPanel.swift`

The expanded drawer panel that appears above the icon bar, overlaying terminal content.

**Step 1: Create the view**

```swift
import SwiftUI

/// Floating drawer panel that overlays pane content.
/// Shows the active drawer pane's content in a rectangular panel.
struct DrawerPanel: View {
    let drawerPaneView: PaneView?
    let height: CGFloat
    let onResize: (CGFloat) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Resize handle at top
            DrawerResizeHandle(onDrag: onResize)

            // Drawer pane content
            if let view = drawerPaneView {
                PaneViewRepresentable(paneView: view)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "No Content",
                    systemImage: "rectangle.bottomhalf.inset.filled",
                    description: Text("Select a drawer pane")
                )
            }
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.3), radius: 12, y: -4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Draggable resize handle at the top of the drawer panel.
struct DrawerResizeHandle: View {
    let onDrag: (CGFloat) -> Void
    @State private var isDragging = false

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 8)
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(isDragging ? 0.4 : 0.2))
                    .frame(width: 40, height: 4)
            )
            .cursor(.resizeUpDown)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        onDrag(-value.translation.height) // Negative because dragging up = more height
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}
```

**Step 2: Build**

```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
```

**Step 3: Commit**

```bash
git add Sources/AgentStudio/Views/Drawer/DrawerPanel.swift
git commit -m "feat: create DrawerPanel with resize handle"
```

---

### Task 12: Create DrawerOverlay Container

**Files:**
- Create: `Sources/AgentStudio/Views/Drawer/DrawerOverlay.swift`

Container that composes DrawerIconBar + DrawerPanel, manages drawer state (expanded/collapsed, height).

**Step 1: Create the container**

```swift
import SwiftUI

/// Manages drawer state and composes icon bar + panel for a single pane.
/// Positioned as an overlay at the bottom of a pane leaf.
struct DrawerOverlay: View {
    let paneId: UUID
    let drawer: Drawer?
    let isIconBarVisible: Bool
    let action: (PaneAction) -> Void

    @AppStorage("drawerHeightRatio") private var heightRatio: Double = 0.75
    @State private var currentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let maxHeight = geometry.size.height * CGFloat(heightRatio)

            VStack(spacing: 0) {
                Spacer()

                if let drawer, isIconBarVisible {
                    // Expanded panel (when drawer has content and is expanded)
                    if drawer.isExpanded, let activeId = drawer.activeDrawerPaneId {
                        DrawerPanel(
                            drawerPaneView: nil, // Will be resolved by parent
                            height: maxHeight,
                            onResize: { delta in
                                let newRatio = min(0.9, max(0.2, heightRatio + Double(delta / geometry.size.height)))
                                heightRatio = newRatio
                            },
                            onDismiss: {
                                action(.toggleDrawer(paneId: paneId))
                            }
                        )
                    }

                    // Icon bar
                    DrawerIconBar(
                        drawerPanes: drawerPaneItems(from: drawer),
                        activeDrawerPaneId: drawer.activeDrawerPaneId,
                        onSelect: { drawerPaneId in
                            action(.setActiveDrawerPane(parentPaneId: paneId, drawerPaneId: drawerPaneId))
                            if !(drawer.isExpanded) {
                                action(.toggleDrawer(paneId: paneId))
                            }
                        },
                        onAdd: {
                            // Create terminal drawer pane inheriting parent context
                            let content = PaneContent.terminal(TerminalState())
                            let metadata = PaneMetadata(source: .floating(workingDirectory: nil, title: "Drawer"))
                            action(.addDrawerPane(parentPaneId: paneId, content: content, metadata: metadata))
                        },
                        onClose: { drawerPaneId in
                            action(.removeDrawerPane(parentPaneId: paneId, drawerPaneId: drawerPaneId))
                        },
                        onToggleExpand: {
                            action(.toggleDrawer(paneId: paneId))
                        }
                    )
                }
            }
        }
    }

    private func drawerPaneItems(from drawer: Drawer) -> [DrawerPaneItem] {
        drawer.panes.map { dp in
            DrawerPaneItem(
                id: dp.id,
                title: dp.metadata.title ?? "Terminal",
                icon: iconForContent(dp.content)
            )
        }
    }

    private func iconForContent(_ content: PaneContent) -> String {
        switch content {
        case .terminal: return "terminal"
        case .webview: return "globe"
        case .codeViewer: return "doc.text"
        case .unsupported: return "questionmark.circle"
        }
    }
}
```

**Step 2: Build**

```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
```

**Step 3: Commit**

```bash
git add Sources/AgentStudio/Views/Drawer/DrawerOverlay.swift
git commit -m "feat: create DrawerOverlay container composing icon bar and panel"
```

---

### Task 13: Integrate DrawerOverlay into TerminalPaneLeaf

**Files:**
- Modify: `Sources/AgentStudio/Views/Splits/TerminalPaneLeaf.swift`

The drawer overlay needs to appear at the bottom of each pane leaf.

**Step 1: Add drawer state to TerminalPaneLeaf**

Add properties for drawer data and hover detection:

```swift
struct TerminalPaneLeaf: View {
    let paneView: PaneView
    let tabId: UUID
    let isActive: Bool
    let isSplit: Bool
    let drawer: Drawer?              // NEW: drawer data for this pane
    let action: (PaneAction) -> Void
    let shouldAcceptDrop: (UUID, DropZone) -> Bool
    let onDrop: (SplitDropPayload, UUID, DropZone) -> Void

    @State private var dropZone: DropZone?
    @State private var isTargeted: Bool = false
    @State private var isHovered: Bool = false
    @State private var isBottomHovered: Bool = false  // NEW: bottom edge hover
    // ...existing code...
```

**Step 2: Add bottom hover zone and drawer overlay**

Inside the `ZStack` in `body`, add after the existing overlays:

```swift
// Drawer overlay (bottom of pane)
DrawerOverlay(
    paneId: paneView.id,
    drawer: drawer,
    isIconBarVisible: isBottomHovered || (drawer?.isExpanded ?? false),
    action: action
)

// Bottom hover detection zone
VStack {
    Spacer()
    Color.clear
        .frame(height: 40)
        .contentShape(Rectangle())
        .onHover { hovering in
            isBottomHovered = hovering
        }
}
.allowsHitTesting(true)
```

**Step 3: Update all call sites of TerminalPaneLeaf**

In `TerminalSplitContainer.swift` and `SplitSubtreeView`, pass the `drawer` property. This requires the `PaneSplitTree` to carry drawer info, or look it up from the store.

**Step 4: Build and test**

```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
swift test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
```

**Step 5: Commit**

```bash
git add Sources/AgentStudio/Views/Splits/
git commit -m "feat: integrate drawer overlay into pane leaf views"
```

---

### Task 14: Wire Drawer AppCommands

**Files:**
- Modify: `Sources/AgentStudio/App/AppCommand.swift` (already done in Task 9)
- Modify: CommandHandler implementation
- Modify: `Sources/AgentStudio/CommandBar/CommandBarDataSource.swift`

**Step 1: Add drawer commands to CommandHandler**

In the `execute(_ command:)` method:

```swift
case .addDrawerPane:
    guard let tabId = store.activeTabId,
          let tab = store.tab(tabId),
          let paneId = tab.activePaneId else { return }
    let content = PaneContent.terminal(TerminalState())
    let metadata = PaneMetadata(source: .floating(workingDirectory: nil, title: "Drawer"))
    executor.execute(.addDrawerPane(parentPaneId: paneId, content: content, metadata: metadata))

case .toggleDrawer:
    guard let tabId = store.activeTabId,
          let tab = store.tab(tabId),
          let paneId = tab.activePaneId else { return }
    executor.execute(.toggleDrawer(paneId: paneId))
```

**Step 2: Add drawer commands to isTargetableCommand for navigateDrawerPane**

**Step 3: Build and test**

```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
swift test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
```

**Step 4: Commit**

```bash
git add Sources/AgentStudio/App/ Sources/AgentStudio/CommandBar/
git commit -m "feat: wire drawer AppCommands to PaneAction dispatch"
```

---

### Task 15: Drawer Width for Multi-Pane Tabs

**Files:**
- Modify: `Sources/AgentStudio/Views/Drawer/DrawerOverlay.swift`

When in a multi-pane split, the drawer should be 90% of the total tab width, floating over neighbors. This requires the drawer overlay to know the tab's total width.

**Step 1: Pass tab geometry to DrawerOverlay**

Add a `tabWidth: CGFloat` parameter. When `tabWidth > paneWidth`, expand drawer width with negative horizontal padding to overflow the pane bounds.

**Step 2: Update TerminalPaneLeaf to pass tab geometry**

Use `GeometryReader` at the `TerminalSplitContainer` level to measure total tab width and pass it down.

**Step 3: Build and test**

```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
```

**Step 4: Commit**

```bash
git add Sources/AgentStudio/Views/
git commit -m "feat: drawer panel expands to 90% tab width in multi-pane layouts"
```

---

## Post-Implementation

### Visual Verification (MANDATORY)

After each UI task, visually verify with Peekaboo:

```bash
pkill -9 -f "AgentStudio"
swift build -c debug > /tmp/build-output.txt 2>&1 && echo "BUILD OK"
.build/debug/AgentStudio &
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo app switch --to "PID:$PID"
peekaboo see --app "PID:$PID" --json
```

### Linear Ticket Cleanup

After implementation, archive duplicate tickets:
- Archive LUNA-300, LUNA-301 (superseded by LUNA-314)
- Archive LUNA-303 (already done)
- Archive LUNA-304 (superseded by LUNA-316)
- Archive LUNA-305 (superseded by LUNA-315)
- Move LUNA-306 to Phase 3a dependency

### Full Test Suite

```bash
swift test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
```

All tests must pass. No regressions from existing 863 tests.
