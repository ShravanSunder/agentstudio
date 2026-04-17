# Collapsed Pane Bar Redesign

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restyle the minimized pane bar to match management-mode visual language, replace mismatched icons with two explicit circle buttons (expand + arrangement panel), add a visibility toggle, and move shared arrangement types to Core for composability.

**Architecture:** The collapsed bar reads all state through atoms (`workspaceTabLayout`, `paneDisplay`, `managementMode`, `uiState`). A new `ArrangementDerived` provides shared arrangement data building for both the tab bar and collapsed bar. `ArrangementPanel` and its data types move from `App/Panes/TabBar/` to `Core/Views/Splits/` to satisfy the import rule (`Core/ -> Infrastructure/` only). A `showMinimizedBars` toggle in `UIStateAtom` controls bar visibility outside management mode. The toggle is scoped to top-level tab strips only — drawer collapsed bars always show since drawers have no tab bar arrangement button as a recovery path.

**Tech Stack:** Swift 6.2, SwiftUI, AtomRegistry pattern

### Design Constraints (from review)

1. **Toggle scoped to tab strip only.** `showMinimizedBars` toggle only affects `FlatTabStripContainer`. `FlatPaneStripContent` receives `collapsedPaneWidth` as a parameter — the caller decides the value. `DrawerPanel` always passes `CollapsedPaneBar.barWidth`. Drawer panes cannot be hidden.
2. **Drawer panes hide tab-level controls.** The collapsed bar checks `atom(\.workspacePane).pane(paneId)?.isDrawerChild`. When true: expand button shown, arrangement button hidden (arrangement is a tab-level concept, not a drawer concept). Same pattern as `PaneLeafContainer` lines 70-72, 148, 357.
3. **Stable accent color.** Swift's `hashValue` is randomized per process. Accent color derivation uses a deterministic string hash of `repoId.uuidString`, not `repoId.hashValue`.
4. **Hard cutover, no aliases.** Rename `TabBarPaneInfo` -> `PaneVisibilityInfo` and `TabBarArrangementInfo` -> `ArrangementInfo` in one pass. No backward-compat type aliases.
5. **TerminalPaneGeometryResolver must track bar width.** `Features/Terminal/Restore/TerminalPaneGeometryResolver.swift:5` hardcodes `30`. Must reference `CollapsedPaneBar.barWidth`.
6. **onSaveArrangement is a closure, not a command.** No `.saveArrangement(tabId:)` exists in `PaneActionCommand`. Injected as closure from the container (same pattern as `TabBarArrangementButton`).
7. **Tooltip uses primaryLabel only.** `PaneDisplayDerived.primaryLabel` already includes branch for worktree panes. Don't append `branchName` separately.

---

## Visual Design

### Collapsed Bar Layout (40pt wide)

```
    40pt
    ├──────────────────────────────────────┤

    ┌──────────────────────────────────────┐
    │         spacingLoose (8pt)           │
    │                                      │
    │           ┌──────────┐               │
    │           │   ◀▶     │               │  expand button
    │           │  24pt    │               │  compactButtonSize circle
    │           └──────────┘               │  icon: arrow.up.left.and.arrow.down.right
    │         spacingTight (4pt)           │
    │           ┌──────────┐               │
    │           │   ⊞      │               │  arrangement button (tab panes only)
    │           │  24pt    │               │  compactButtonSize circle
    │           └──────────┘               │  icon: rectangle.3.group
    │                                      │  hidden for drawer child panes
    │                                      │
    │            t                          │
    │            i                          │
    │            t                          │  sideways title (rotated -90deg)
    │            l                          │  textSm (12pt), semibold
    │            e                          │  .primary.opacity(0.92)
    │                                      │
    │           ┌──────────┐               │
    │           │ ━━━━━━━━ │               │  accent color bar (3pt)
    │           └──────────┘               │  pane's repo accent color
    │         spacingLoose (8pt)           │
    └──────────────────────────────────────┘
```

### Surface Treatment

```
              RESTING                           HOVER

    ┌──────────────────────────┐     ┌──────────────────────────┐
    │                          │     │                          │
    │  fill:                   │     │  fill:                   │
    │   white @ fillMuted      │     │   white @ fillHover      │
    │   (0.06)                 │     │   (0.08)                 │
    │                          │     │                          │
    │  stroke:                 │     │  stroke:                 │
    │   white @ fillActive     │     │   white @ strokeHover    │
    │   (0.12)                 │     │   (0.20)                 │
    │                          │     │                          │
    │  corner radius:          │     │  corner radius:          │
    │   panelCornerRadius (8)  │     │   panelCornerRadius (8)  │
    └──────────────────────────┘     └──────────────────────────┘
```

### Button Styling (matches tab bar buttons)

```
              RESTING                           HOVER

        ┌────────────────────┐        ┌────────────────────┐
        │    ┌──────────┐    │        │    ┌──────────┐    │
        │    │  icon     │    │        │    │  icon     │    │
        │    └──────────┘    │        │    └──────────┘    │
        │                    │        │                    │
        │  circle fill:      │        │  circle fill:      │
        │   white @ fillMuted│        │   white @ fillPress│
        │   (0.06)           │        │   (0.10)           │
        │  icon: .secondary  │        │  icon: .primary    │
        └────────────────────┘        └────────────────────┘

        24pt circle, 12pt icon, .plain buttonStyle
```

### Arrangement Popover (opened from collapsed bar)

```
                              arrow on left edge, near top
                              ↓
     ┌──────────┐        ◄───┌─────────────────────────┐
     │   (◀▶)   │            │ ARRANGEMENTS             │
     │   (⊞)  ←─┼────────── │ [Default]  [+]           │
     │          │            │                          │
     │   t      │            │ PANE VISIBILITY           │
     │   i      │            │ ● agent-studio  👁  ← pulse highlight
     │   t      │            │ ○ docs          👁       │
     │   l      │            │                          │
     │   e      │            │ ─────────────────────    │
     │          │            │ Show minimized bars  [✓] │
     │   ━━━━   │            └─────────────────────────┘
     └──────────┘

     popover: arrowEdge = .leading
              attachmentAnchor = .point(.trailing)
```

### Side-by-Side: Old vs New

```
      OLD (30pt)                       NEW (40pt)

    ┌────────┐                    ┌──────────────┐
    │  [▸]   │ arrow.right.to.   │              │
    │  [≡]   │ line.3.horizontal │   (◀▶)      │ expand (circle btn)
    │        │                    │   (⊞)       │ arrangement (circle btn)
    │  t     │                    │              │
    │  i     │ sideways, bold     │   t          │
    │  t     │ .secondary (0.7)   │   i          │ sideways, semibold
    │  l     │                    │   t          │ .primary (0.92)
    │  e     │                    │   l          │
    │        │                    │   e          │
    │        │                    │              │
    └────────┘                    │   ━━━━━━━━   │ accent color
                                  │              │
    bg: black @ 0.35              └──────────────┘
    stroke: white @ 0.10
    corner: 4pt                   bg: white @ 0.06
                                  stroke: white @ 0.12
                                  corner: 8pt
```

### Interaction Model

```
    ┌───────────────────────────────────────────────────────┐
    │  Gesture            │  Action                         │
    ├─────────────────────┼─────────────────────────────────┤
    │  Click expand btn   │  dispatch .expandPane            │
    │  Click arrange btn  │  show ArrangementPanel popover   │
    │  Hover bar body     │  surface brightens + tooltip     │
    │  Right-click body   │  context menu (expand, close)    │
    │  Click body         │  nothing (not a gesture target)  │
    └───────────────────────────────────────────────────────┘
```

### Visibility Logic

```
    show collapsed bar = managementMode.isActive || uiState.showMinimizedBars

    ┌─────────────────────┬───────────────┬──────────────────┐
    │  Management Mode    │  Toggle ON    │  Bars Visible?   │
    ├─────────────────────┼───────────────┼──────────────────┤
    │  ON                 │  ON           │  YES             │
    │  ON                 │  OFF          │  YES (override)  │
    │  OFF                │  ON           │  YES             │
    │  OFF                │  OFF          │  NO              │
    └─────────────────────┴───────────────┴──────────────────┘

    When bars hidden: collapsedPaneWidth = 0 in metrics
    Active panes reclaim full width. Arrangement panel
    in tab bar is the only way to expand hidden panes.

    EXCEPTION: Drawer panes always show collapsed bars
    regardless of toggle. Drawers have no tab bar
    arrangement button as a recovery path.
```

### Animation and Runtime Safety

**Minimize is layout-only.** `WorkspaceTabLayoutAtom.minimizePane()` adds the paneId to
`Tab.minimizedPaneIds` and adjusts `activePaneId`. That's it. No runtime, zmx, or surface
lifecycle changes. The pane's `PaneHostView`, Ghostty surface, and zmx session all stay
alive in memory.

```
    What minimize touches:             What minimize does NOT touch:

    Tab.minimizedPaneIds  (insert)     Pane model (alive)
    Tab.activePaneId      (shift)      PaneHostView (alive, not mounted in SwiftUI)
    Tab.zoomedPaneId      (clear)      Ghostty surface (alive, suspended)
                                       zmx session (alive)
                                       Layout.panes/ratios (unchanged)
                                       Layout.dividerIds (unchanged)
```

**The collapsed bar is pure SwiftUI.** `CollapsedPaneBar` renders in the slot that
`PaneLeafContainer` would have occupied. The `PaneHostView` is NOT mounted via
`PaneViewRepresentable` when minimized — it was already not mounted before this redesign.
Nothing changes about the pane lifecycle.

**Hiding bars (toggle off) is safe.** When `collapsedPaneWidth = 0`, `FlatTabStripMetrics`
gives the minimized pane a 0-width frame. No `CollapsedPaneBar` view renders. The pane's
`Layout` (ratios, divider positions) is completely untouched — metrics only computes
display frames, not canonical layout state.

**Transitions.** When the toggle changes or management mode toggles, the bars appear/disappear.
SwiftUI handles this via the existing `.animation(.easeOut(duration: AppStyle.animationFast), value: minimizedPaneIds)` on the container. The metrics recompute with the new `collapsedPaneWidth`,
and the pane segments animate to their new positions. No explicit transition needed on the bar
itself — the frame size change drives the animation.

---

## File Structure

### New Files
| File | Responsibility |
|------|----------------|
| `Core/State/MainActor/Atoms/ArrangementDerived.swift` | Composable derived atom building `PaneVisibilityInfo` and `ArrangementInfo` from tab layout + pane display atoms |

### Moved Files (App/ -> Core/)
| From | To | Reason |
|------|------|--------|
| Data types in `App/Panes/TabBar/TabBarAdapter.swift` | `Core/Views/Splits/ArrangementPanel.swift` (colocated) | Shared by tab bar and collapsed bar; no App/ dependencies |
| `App/Panes/TabBar/ArrangementPanel.swift` | `Core/Views/Splits/ArrangementPanel.swift` | Same — used from Core/Views/Splits/CollapsedPaneBar now |

### Modified Files
| File | Changes |
|------|---------|
| `Infrastructure/AppStyle.swift` | Add `collapsedBarWidth`, `collapsedBarAccentHeight` constants |
| `Infrastructure/AtomLib/AtomRegistry.swift` | Register `ArrangementDerived` |
| `Core/Views/Splits/CollapsedPaneBar.swift` | Complete restyle: surface, buttons, popover, accent bar, tooltip |
| `Core/Views/Splits/FlatTabStripContainer.swift` | Visibility check for collapsed bars; thread `onSaveArrangement` to top-level collapsed bars |
| `Core/Views/Splits/FlatPaneStripContent.swift` | Accept caller-owned `collapsedPaneWidth`; thread `onSaveArrangement` through pane slots |
| `Core/State/MainActor/Atoms/UIStateAtom.swift` | Add `showMinimizedBars` property |
| `Core/State/MainActor/Persistence/UIStateStore.swift` | Persist `showMinimizedBars` |
| `Core/State/MainActor/Persistence/WorkspacePersistor.swift` | Add field to `PersistableUIState` |
| `Core/State/MainActor/Atoms/PaneDisplayDerived.swift` | Add `accentColorHex(for:)` method |
| `Core/Views/Splits/SingleTabContent.swift` | Inject `onSaveArrangement` closure into top-level strip |
| `Core/Views/Splits/ActiveTabContent.swift` | Inject `onSaveArrangement` closure into top-level strip |
| `Features/Terminal/Restore/TerminalPaneGeometryResolver.swift` | Accept caller-owned `collapsedPaneWidth` for restore layout |
| `App/Coordination/PaneCoordinator+ViewLifecycle.swift` | Pass effective collapsed width for tab restore; full width for drawers |
| `Core/Views/Drawer/DrawerPanel.swift` | Pass `collapsedPaneWidth: CollapsedPaneBar.barWidth` (always show) |
| `App/Panes/TabBar/TabBarAdapter.swift` | Remove moved types, rename to `PaneVisibilityInfo`/`ArrangementInfo` |
| `App/Panes/TabBar/CustomTabBar.swift` | Rename type references |
| `Tests/AgentStudioTests/Core/Models/MinimizeLayoutIntegrationTests.swift` | Update `barWidth` references |

---

## Task 1: Move ArrangementPanel and Data Types to Core

**Files:**
- Move: `App/Panes/TabBar/ArrangementPanel.swift` -> `Core/Views/Splits/ArrangementPanel.swift`
- Modify: `App/Panes/TabBar/TabBarAdapter.swift` (lines 4-17, remove type definitions)
- Modify: `App/Panes/TabBar/CustomTabBar.swift` (verify no broken imports)

This task relocates `ArrangementPanel`, `TabBarPaneInfo` (renamed to `PaneVisibilityInfo`), `TabBarArrangementInfo` (renamed to `ArrangementInfo`), and `WrappingHStack` to Core so both the tab bar and collapsed bar can use them.

- [ ] **Step 1: Create the new file in Core with moved + renamed types**

Create `Sources/AgentStudio/Core/Views/Splits/ArrangementPanel.swift` with the full content of the existing `ArrangementPanel.swift`, but with renamed data types at the top:

```swift
import SwiftUI

/// Pane info for arrangement panel display.
struct PaneVisibilityInfo: Identifiable, Equatable {
    let id: UUID
    var title: String
    var isMinimized: Bool
}

/// Arrangement info for arrangement panel display.
struct ArrangementInfo: Identifiable, Equatable {
    let id: UUID
    var name: String
    var isDefault: Bool
    var isActive: Bool
}

/// Floating popover panel for managing pane arrangements.
/// Shows pane visibility toggles, arrangement chips, and save controls.
struct ArrangementPanel: View {
    let tabId: UUID
    let panes: [PaneVisibilityInfo]
    let arrangements: [ArrangementInfo]
    let onPaneAction: (PaneActionCommand) -> Void
    let onSaveArrangement: () -> Void

    @State private var renamingArrangementId: UUID?
    @State private var renameText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MARK: - Arrangement chips
            Text("Arrangements")
                .font(.system(size: AppStyle.textSm, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            WrappingHStack(spacing: 4) {
                ForEach(arrangements) { arr in
                    arrangementChip(arr)
                }

                if panes.count > 1 {
                    Button(action: onSaveArrangement) {
                        Image(systemName: "plus")
                            .font(.system(size: AppStyle.textSm, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Color.white.opacity(AppStyle.strokeMuted), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(LocalActionSpec.saveCurrentLayoutAsArrangement.actionSpec.helpText)
                }
            }

            // MARK: - Pane visibility
            if panes.count > 1 {
                Divider()
                    .padding(.vertical, 2)

                Text("Pane Visibility")
                    .font(.system(size: AppStyle.textSm, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                VStack(spacing: 2) {
                    ForEach(panes) { pane in
                        paneRow(pane)
                    }
                }
            }
        }
        .padding(10)
        .frame(minWidth: 180, maxWidth: 260)
        .alert(
            "Rename Arrangement",
            isPresented: Binding(
                get: { renamingArrangementId != nil },
                set: { if !$0 { renamingArrangementId = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
            Button(LocalActionSpec.rename.actionSpec.label) {
                if let id = renamingArrangementId, !renameText.isEmpty {
                    onPaneAction(.renameArrangement(tabId: tabId, arrangementId: id, name: renameText))
                }
                renamingArrangementId = nil
            }
            Button(LocalActionSpec.cancel.actionSpec.label, role: .cancel) {
                renamingArrangementId = nil
            }
        }
    }

    // MARK: - Pane Row

    private func paneRow(_ pane: PaneVisibilityInfo) -> some View {
        HStack(spacing: AppStyle.spacingStandard) {
            Circle()
                .fill(pane.isMinimized ? Color.clear : Color.white.opacity(AppStyle.foregroundDim))
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                .frame(width: 8, height: 8)

            Text(pane.title)
                .font(.system(size: AppStyle.textXs))
                .foregroundStyle(pane.isMinimized ? .tertiary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Button {
                if pane.isMinimized {
                    onPaneAction(.expandPane(tabId: tabId, paneId: pane.id))
                } else {
                    onPaneAction(.minimizePane(tabId: tabId, paneId: pane.id))
                }
            } label: {
                Image(systemName: pane.isMinimized ? "eye" : "eye.slash")
                    .font(.system(size: AppStyle.textSm))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(
                pane.isMinimized
                    ? LocalActionSpec.showPane.actionSpec.helpText
                    : LocalActionSpec.hidePane.actionSpec.helpText
            )
        }
        .padding(.horizontal, AppStyle.spacingStandard)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius)
                .fill(Color.white.opacity(AppStyle.fillSubtle))
        )
    }

    // MARK: - Arrangement Chip

    private func arrangementChip(_ arr: ArrangementInfo) -> some View {
        Text(arr.name)
            .font(.system(size: AppStyle.textXs, weight: arr.isActive ? .semibold : .regular))
            .foregroundStyle(arr.isActive ? .primary : .secondary)
            .padding(.horizontal, AppStyle.spacingLoose)
            .padding(.vertical, AppStyle.spacingTight)
            .background(
                RoundedRectangle(cornerRadius: AppStyle.barCornerRadius)
                    .fill(
                        arr.isActive
                            ? Color.white.opacity(AppStyle.fillActive) : Color.white.opacity(AppStyle.fillSubtle))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onPaneAction(.switchArrangement(tabId: tabId, arrangementId: arr.id))
            }
            .contextMenu {
                if !arr.isDefault {
                    Button(LocalActionSpec.renameArrangement.actionSpec.label) {
                        renameText = arr.name
                        renamingArrangementId = arr.id
                    }
                    Button(LocalActionSpec.deleteArrangement.actionSpec.label, role: .destructive) {
                        onPaneAction(.removeArrangement(tabId: tabId, arrangementId: arr.id))
                    }
                }
            }
    }
}

// MARK: - Wrapping HStack

struct WrappingHStack<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 4, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
    }
}
```

- [ ] **Step 2: Delete the old ArrangementPanel.swift from App/**

Delete `Sources/AgentStudio/App/Panes/TabBar/ArrangementPanel.swift`.

- [ ] **Step 3: Remove data types from TabBarAdapter.swift and rename all usages (hard cutover)**

In `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift`:
- Delete the `TabBarPaneInfo` struct (lines 4-9) and `TabBarArrangementInfo` struct (lines 12-17).
- Rename all usages of `TabBarPaneInfo` to `PaneVisibilityInfo` in `TabBarAdapter.swift`.
- Rename all usages of `TabBarArrangementInfo` to `ArrangementInfo` in `TabBarAdapter.swift`.
- The `TabBarItem` struct stays (it's tab-bar specific) but its properties change type:
  ```swift
  var panes: [PaneVisibilityInfo]
  var arrangements: [ArrangementInfo]
  ```

In `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift`:
- Rename any references to `TabBarPaneInfo` -> `PaneVisibilityInfo` and `TabBarArrangementInfo` -> `ArrangementInfo`.

No type aliases. One-pass cutover.

- [ ] **Step 4: Build and verify no compile errors**

Run: `mise run build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Run tests**

Run: `mise run test`
Expected: All tests pass (no behavior change, only file relocation + rename)

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: move ArrangementPanel and data types to Core/Views/Splits"
```

---

## Task 2: Create ArrangementDerived Atom

**Files:**
- Create: `Sources/AgentStudio/Core/State/MainActor/Atoms/ArrangementDerived.swift`
- Modify: `Sources/AgentStudio/Infrastructure/AtomLib/AtomRegistry.swift`
- Test: `Tests/AgentStudioTests/Core/State/ArrangementDerivedTests.swift`

A composable derived atom that builds `[PaneVisibilityInfo]` and `[ArrangementInfo]` from the tab layout and pane display atoms. Both the tab bar adapter and the collapsed bar use this as the single source of truth for arrangement panel data.

- [ ] **Step 1: Write the failing test**

Create `Tests/AgentStudioTests/Core/State/ArrangementDerivedTests.swift` using the real store/atom setup pattern from `MinimizeLayoutIntegrationTests.swift` and `WorkspaceStoreTestAccess.swift`:

```swift
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class ArrangementDerivedTests {

    private var registry: AtomRegistry!
    private var store: WorkspaceStore!

    init() {
        registry = AtomRegistry()
        store = WorkspaceStore(
            metadataAtom: registry.workspaceMetadata,
            repositoryTopologyAtom: registry.workspaceRepositoryTopology,
            paneAtom: registry.workspacePane,
            tabLayoutAtom: registry.workspaceTabLayout,
            persistor: WorkspacePersistor(
                workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            )
        )
    }

    @Test
    func paneVisibilityItems_returnsAllPanesWithMinimizedState() {
        // Arrange
        AtomScope.$override.withValue(registry) {
            let firstPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
            let tab = Tab(paneId: firstPane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)

            let secondPane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
            _ = store.insertPane(
                secondPane.id,
                inTab: tab.id,
                at: firstPane.id,
                direction: .horizontal,
                position: .after
            )
            _ = store.minimizePane(secondPane.id, inTab: tab.id)

            // Act
            let derived = ArrangementDerived()
            let items = derived.paneVisibilityItems(for: tab.id)

            // Assert
            #expect(items.count == 2)
            #expect(items[0].id == firstPane.id)
            #expect(items[0].isMinimized == false)
            #expect(items[1].id == secondPane.id)
            #expect(items[1].isMinimized == true)
        }
    }

    @Test
    func arrangementItems_returnsArrangementsWithActiveState() {
        // Arrange
        AtomScope.$override.withValue(registry) {
            let pane = store.createPane(source: .floating(launchDirectory: nil, title: nil))
            let tab = Tab(paneId: pane.id)
            store.appendTab(tab)
            store.setActiveTab(tab.id)

            // Act
            let derived = ArrangementDerived()
            let items = derived.arrangementItems(for: tab.id)

            // Assert
            #expect(items.count == 1)
            #expect(items[0].name == "Default")
            #expect(items[0].isDefault == true)
            #expect(items[0].isActive == true)
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "ArrangementDerived" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: FAIL — `ArrangementDerived` not defined

- [ ] **Step 3: Implement ArrangementDerived**

Create `Sources/AgentStudio/Core/State/MainActor/Atoms/ArrangementDerived.swift`:

```swift
import Foundation

@MainActor
struct ArrangementDerived {
    func paneVisibilityItems(for tabId: UUID) -> [PaneVisibilityInfo] {
        let tabLayout = atom(\.workspaceTabLayout)
        let paneDisplay = atom(\.paneDisplay)
        guard let tab = tabLayout.tab(tabId) else { return [] }

        return tab.activePaneIds.map { paneId in
            PaneVisibilityInfo(
                id: paneId,
                title: paneDisplay.displayLabel(for: paneId),
                isMinimized: tab.minimizedPaneIds.contains(paneId)
            )
        }
    }

    func arrangementItems(for tabId: UUID) -> [ArrangementInfo] {
        let tabLayout = atom(\.workspaceTabLayout)
        guard let tab = tabLayout.tab(tabId) else { return [] }

        return tab.arrangements.map { arrangement in
            ArrangementInfo(
                id: arrangement.id,
                name: arrangement.name,
                isDefault: arrangement.isDefault,
                isActive: arrangement.id == tab.activeArrangementId
            )
        }
    }
}
```

Note: This references `tab.arrangements`, `tab.activeArrangementId`, and `tab.activePaneIds` — verify these exist on `Tab`. If the property names differ, check `Sources/AgentStudio/Core/Models/Tab.swift` and adjust. The `TabBarAdapter` (lines 140-180 of `TabBarAdapter.swift`) has the canonical reference for how these are built today — mirror that logic.

- [ ] **Step 4: Register in AtomRegistry**

In `Sources/AgentStudio/Infrastructure/AtomLib/AtomRegistry.swift`, add after the `tabDisplay` computed property:

```swift
var arrangement: ArrangementDerived {
    ArrangementDerived()
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "ArrangementDerived" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS

Note: Keep the test setup aligned with the real helpers in `MinimizeLayoutIntegrationTests.swift` and `WorkspaceStoreTestAccess.swift`. Do not use nonexistent APIs like `registerPane(Pane(id: ...))`.

- [ ] **Step 6: Update TabBarAdapter to use ArrangementDerived**

In `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift`, replace the inline pane/arrangement array building (around lines 160-180) with `atom(\.arrangement)` as the source. Since Task 1 is a hard cutover, there are no compatibility aliases to rely on.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add ArrangementDerived atom for composable arrangement data"
```

---

## Task 3: Add showMinimizedBars Toggle to UIStateAtom

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/UIStateAtom.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/UIStateStore.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistor.swift`
- Test: `Tests/AgentStudioTests/Core/Stores/UIStateStoreTests.swift`

Adds a persisted boolean toggle controlling whether collapsed pane bars are visible outside management mode. Default: `true` (bars visible).

- [ ] **Step 1: Add property to UIStateAtom**

In `Sources/AgentStudio/Core/State/MainActor/Atoms/UIStateAtom.swift`:

Add property after `isFilterVisible`:
```swift
private(set) var showMinimizedBars: Bool = true
```

Add setter:
```swift
func setShowMinimizedBars(_ show: Bool) {
    showMinimizedBars = show
}
```

Update `hydrate()` signature and body — add `showMinimizedBars: Bool = true` parameter:
```swift
func hydrate(
    expandedGroups: Set<String>,
    checkoutColors: [String: String],
    filterText: String,
    isFilterVisible: Bool,
    showMinimizedBars: Bool = true
) {
    self.expandedGroups = expandedGroups
    self.checkoutColors = checkoutColors
    self.filterText = filterText
    self.isFilterVisible = isFilterVisible
    self.showMinimizedBars = showMinimizedBars
}
```

Update `clear()` — add:
```swift
showMinimizedBars = true
```

- [ ] **Step 2: Add field to PersistableUIState**

In `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspacePersistor.swift`, find `struct PersistableUIState` (line 159) and add:

```swift
var showMinimizedBars: Bool
```

Update the `init` — add `showMinimizedBars: Bool = true` parameter and `self.showMinimizedBars = showMinimizedBars`.

For backward compatibility, add a custom `init(from decoder:)` that uses `decodeIfPresent` with a default of `true`:
```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    self.workspaceId = try container.decode(UUID.self, forKey: .workspaceId)
    self.expandedGroups = try container.decode(Set<String>.self, forKey: .expandedGroups)
    self.checkoutColors = try container.decode([String: String].self, forKey: .checkoutColors)
    self.filterText = try container.decode(String.self, forKey: .filterText)
    self.isFilterVisible = try container.decode(Bool.self, forKey: .isFilterVisible)
    self.showMinimizedBars = try container.decodeIfPresent(Bool.self, forKey: .showMinimizedBars) ?? true
}
```

Check if `PersistableUIState` already has a custom `init(from:)`. If so, add the `showMinimizedBars` field to it with `decodeIfPresent`. If it uses synthesized Codable, adding the custom init handles backward compat.

- [ ] **Step 3: Update UIStateStore**

In `Sources/AgentStudio/Core/State/MainActor/Persistence/UIStateStore.swift`:

Update `restore(for:)` to pass through the new field:
```swift
case .loaded(let state):
    atom.hydrate(
        expandedGroups: state.expandedGroups,
        checkoutColors: state.checkoutColors,
        filterText: state.filterText,
        isFilterVisible: state.isFilterVisible,
        showMinimizedBars: state.showMinimizedBars
    )
```

Update `flush(for:)` to include the new field:
```swift
try persistor.saveUI(
    .init(
        workspaceId: workspaceId,
        expandedGroups: atom.expandedGroups,
        checkoutColors: atom.checkoutColors,
        filterText: atom.filterText,
        isFilterVisible: atom.isFilterVisible,
        showMinimizedBars: atom.showMinimizedBars
    )
)
```

- [ ] **Step 4: Write test for toggle**

Add to existing `Tests/AgentStudioTests/Core/Stores/UIStateStoreTests.swift` (or wherever UIStateAtom tests live):

```swift
@Test
func showMinimizedBars_defaultsToTrue() {
    let atom = UIStateAtom()
    #expect(atom.showMinimizedBars == true)
}

@Test
func setShowMinimizedBars_updatesValue() {
    let atom = UIStateAtom()
    atom.setShowMinimizedBars(false)
    #expect(atom.showMinimizedBars == false)
}

@Test
func hydrate_withoutShowMinimizedBars_defaultsToTrue() {
    let atom = UIStateAtom()
    atom.hydrate(
        expandedGroups: [],
        checkoutColors: [:],
        filterText: "",
        isFilterVisible: false
    )
    #expect(atom.showMinimizedBars == true)
}
```

- [ ] **Step 5: Run tests**

Run: `mise run test`
Expected: All tests pass

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add showMinimizedBars toggle to UIStateAtom with persistence"
```

---

## Task 4: Add Highlight Animation to ArrangementPanel

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/ArrangementPanel.swift`

Adds an optional `highlightPaneId` parameter. When set, the matching pane row briefly pulses with an accent background on appear — drawing attention to which pane opened the panel.

- [ ] **Step 1: Add highlightPaneId parameter**

In `ArrangementPanel`, add after `onSaveArrangement`:
```swift
var highlightPaneId: UUID? = nil
```

- [ ] **Step 2: Add highlight state**

Add state variable:
```swift
@State private var highlightVisible: Bool = false
```

- [ ] **Step 3: Update paneRow to support highlight**

In the `paneRow` function, wrap the existing background with conditional highlight:

```swift
.background(
    RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius)
        .fill(
            pane.id == highlightPaneId && highlightVisible
                ? Color.accentColor.opacity(0.15)
                : Color.white.opacity(AppStyle.fillSubtle)
        )
)
```

- [ ] **Step 4: Add appear animation trigger**

Add to the `ArrangementPanel` body, after the `.alert` modifier:

```swift
.onAppear {
    guard highlightPaneId != nil else { return }
    highlightVisible = true
    withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
        highlightVisible = false
    }
}
```

- [ ] **Step 5: Build and verify**

Run: `mise run build`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add highlight animation to ArrangementPanel for origin pane"
```

---

## Task 5: Add showMinimizedBars Toggle UI to ArrangementPanel

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/ArrangementPanel.swift`

Adds a toggle row at the bottom of the pane visibility section. When toggled off, collapsed bars are hidden outside management mode.

- [ ] **Step 1: Add toggle to the panel body**

In `ArrangementPanel`, after the pane visibility `VStack(spacing: 2)` block, add:

```swift
Divider()
    .padding(.vertical, 2)

HStack {
    Text("Show minimized bars")
        .font(.system(size: AppStyle.textXs))
        .foregroundStyle(.secondary)

    Spacer()

    Toggle("", isOn: Binding(
        get: { atom(\.uiState).showMinimizedBars },
        set: { atom(\.uiState).setShowMinimizedBars($0) }
    ))
    .toggleStyle(.switch)
    .controlSize(.mini)
    .labelsHidden()
}
```

Note: This toggle section should be inside the `if panes.count > 1` block, since it only makes sense when there are multiple panes.

- [ ] **Step 2: Build and verify**

Run: `mise run build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat: add showMinimizedBars toggle to ArrangementPanel"
```

---

## Task 6: Add AppStyle Constants and PaneDisplayDerived Accent Color

**Files:**
- Modify: `Sources/AgentStudio/Infrastructure/AppStyle.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneDisplayDerived.swift`

- [ ] **Step 1: Add collapsed bar constants to AppStyle**

In `Sources/AgentStudio/Infrastructure/AppStyle.swift`, in the `// MARK: - Layout` section, add after `splitMinimumPaneSize`:

```swift
/// Width of the collapsed pane bar.
static let collapsedBarWidth: CGFloat = 40

/// Height of the accent color indicator at the bottom of the collapsed bar.
static let collapsedBarAccentHeight: CGFloat = 3
```

- [ ] **Step 2: Add accentColorHex to PaneDisplayDerived**

In `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneDisplayDerived.swift`, add after the `resolvedBranchName` function:

```swift
/// Deterministic accent color hex for a pane, derived from its repoId.
/// Returns nil if the pane has no associated repo.
/// Uses a stable string hash (not Swift's randomized hashValue) so the
/// color is consistent across app launches.
func accentColorHex(for paneId: UUID) -> String? {
    let pane = atom(\.workspacePane).pane(paneId)
    guard let repoId = pane?.repoId else { return nil }
    let stableHash = repoId.uuidString.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
    let index = abs(stableHash) % AppStyle.accentPaletteHexes.count
    return AppStyle.accentPaletteHexes[index]
}
```

- [ ] **Step 3: Build and verify**

Run: `mise run build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: add collapsed bar AppStyle constants and accent color derivation"
```

---

## Task 7: Redesign CollapsedPaneBar

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/CollapsedPaneBar.swift` (complete rewrite of body)
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift` (thread `onSaveArrangement`)
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift` (thread `onSaveArrangement`)
- Modify: `Sources/AgentStudio/Core/Views/Splits/SingleTabContent.swift` (inject closure)
- Modify: `Sources/AgentStudio/Core/Views/Splits/ActiveTabContent.swift` (inject closure)

This is the main task. The bar gets:
- Management-mode surface treatment (white fills/strokes)
- Two circle buttons: expand + arrangement panel
- Sideways title with management typography
- Accent color bar at bottom
- ArrangementPanel popover (arrow on left, extends right)
- Tooltip with full pane label
- Context menu (expand, close)
- Bar width 40pt (via new `AppStyle.collapsedBarWidth`)

- [ ] **Step 1: Update static dimensions**

Replace:
```swift
static let barWidth: CGFloat = 30
static let barHeight: CGFloat = 30
```

With:
```swift
static let barWidth: CGFloat = AppStyle.collapsedBarWidth
static let barHeight: CGFloat = AppStyle.collapsedBarWidth
```

- [ ] **Step 2: Add onSaveArrangement closure parameter**

Add to the `CollapsedPaneBar` struct properties and init:
```swift
let onSaveArrangement: (() -> Void)?
```

Add to init with default nil:
```swift
init(
    paneId: UUID,
    tabId: UUID,
    title: String,
    closeTransitionCoordinator: PaneCloseTransitionCoordinator,
    actionDispatcher: PaneActionDispatching,
    onSaveArrangement: (() -> Void)? = nil,
    dropTargetCoordinateSpace: String? = nil,
    useDrawerFramePreference: Bool = false
) { ... }
```

This closure is injected by the top-level tab container path. Drawer callers pass nil (no save arrangement from drawer context).

- [ ] **Step 2b: Thread `onSaveArrangement` through the top-level container chain**

The collapsed bar is not created directly by `PaneTabViewController`, so the closure must be passed through the top-level SwiftUI stack:

- `SingleTabContent`
- `ActiveTabContent`
- `FlatTabStripContainer`
- `FlatPaneStripContent`
- `PaneSegmentSlotView`
- the `CollapsedPaneBar(...)` call sites in the top-level tab path

Use the same arrangement naming logic the tab bar already uses in `PaneTabViewController`: inspect the current tab's arrangements, call `nextArrangementName(existing:)`, then dispatch `.createArrangement(tabId:name:paneIds:)` with `Set(tab.activePaneIds)`.

Drawer callers must pass `nil`.

- [ ] **Step 3: Add new state properties**

Add after `@State private var isHovered`:
```swift
@State private var isExpandHovered: Bool = false
@State private var isArrangementHovered: Bool = false
@State private var showArrangementPanel: Bool = false
```

- [ ] **Step 3: Add atom accessors and derived state**

Add computed properties:
```swift
private var managementMode: ManagementModeAtom {
    atom(\.managementMode)
}

private var uiState: UIStateAtom {
    atom(\.uiState)
}

/// Drawer child panes hide the arrangement button (tab-level concept).
private var isDrawerChild: Bool {
    atom(\.workspacePane).pane(paneId)?.isDrawerChild ?? false
}
```

- [ ] **Step 4: Replace the body**

Replace the entire `body` computed property with:

```swift
var body: some View {
    let paneDisplay = atom(\.paneDisplay)
    let displayParts = paneDisplay.displayParts(for: paneId)
    let accentHex = paneDisplay.accentColorHex(for: paneId)
    // primaryLabel already includes branch for worktree panes ("repo | branch | folder")
    let tooltipText = displayParts.primaryLabel

    VStack(spacing: AppStyle.spacingTight) {
        // MARK: - Buttons (top, stacked)

        expandButton
        if !isDrawerChild {
            arrangementButton
        }

        Spacer(minLength: AppStyle.spacingTight)

        // MARK: - Sideways title

        Text(title)
            .font(.system(size: AppStyle.textSm, weight: .semibold))
            .foregroundStyle(.primary.opacity(0.92))
            .lineLimit(1)
            .truncationMode(.tail)
            .rotationEffect(Angle(degrees: -90))
            .fixedSize()
            .frame(maxHeight: .infinity, alignment: .center)

        Spacer(minLength: AppStyle.spacingTight)

        // MARK: - Accent color bar

        if let accentHex, let nsColor = NSColor(hex: accentHex) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(nsColor: nsColor).opacity(0.7))
                .frame(height: AppStyle.collapsedBarAccentHeight)
                .padding(.horizontal, AppStyle.spacingStandard)
        }
    }
    .padding(.vertical, AppStyle.spacingLoose)
    .frame(width: Self.barWidth)
    .frame(maxHeight: .infinity)
    .background(
        RoundedRectangle(cornerRadius: AppStyle.panelCornerRadius)
            .fill(Color.white.opacity(isHovered ? AppStyle.fillHover : AppStyle.fillMuted))
    )
    .overlay(
        RoundedRectangle(cornerRadius: AppStyle.panelCornerRadius)
            .strokeBorder(
                Color.white.opacity(isHovered ? AppStyle.strokeHover : AppStyle.fillActive),
                lineWidth: 1
            )
    )
    .contentShape(Rectangle())
    .onHover { isHovered = $0 }
    .help(tooltipText)
    .contextMenu {
        Button {
            actionDispatcher.dispatch(.expandPane(tabId: tabId, paneId: paneId))
        } label: {
            Label(AppCommand.expandPane.definition.label, systemImage: "arrow.up.left.and.arrow.down.right")
        }

        Divider()

        Button(role: .destructive) {
            beginCloseTransition()
        } label: {
            Label(AppCommand.closePane.definition.label, systemImage: "xmark")
        }
    }
    .opacity(isClosing ? 0.58 : 1)
    .scaleEffect(isClosing ? 0.985 : 1)
    .animation(.easeOut(duration: AppStyle.animationFast), value: isClosing)
    .allowsHitTesting(!isClosing)
    .padding(AppStyle.paneGap)
    .background(framePreferenceBackground)
}
```

- [ ] **Step 5: Add expand button computed property**

```swift
private var expandButton: some View {
    Button {
        actionDispatcher.dispatch(.expandPane(tabId: tabId, paneId: paneId))
    } label: {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: AppStyle.compactIconSize, weight: .medium))
            .foregroundStyle(isExpandHovered ? .primary : .secondary)
            .frame(width: AppStyle.compactButtonSize, height: AppStyle.compactButtonSize)
            .background(
                Circle()
                    .fill(Color.white.opacity(isExpandHovered ? AppStyle.fillPressed : AppStyle.fillMuted))
            )
            .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { isExpandHovered = $0 }
    .help(AppCommand.expandPane.definition.helpText)
}
```

- [ ] **Step 6: Add arrangement button with popover**

```swift
private var arrangementButton: some View {
    let arrangement = atom(\.arrangement)
    let panes = arrangement.paneVisibilityItems(for: tabId)
    let arrangements = arrangement.arrangementItems(for: tabId)

    return Button {
        showArrangementPanel.toggle()
    } label: {
        Image(systemName: "rectangle.3.group")
            .font(.system(size: AppStyle.compactIconSize, weight: .medium))
            .foregroundStyle(isArrangementHovered ? .primary : .secondary)
            .frame(width: AppStyle.compactButtonSize, height: AppStyle.compactButtonSize)
            .background(
                Circle()
                    .fill(Color.white.opacity(isArrangementHovered ? AppStyle.fillPressed : AppStyle.fillMuted))
            )
            .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { isArrangementHovered = $0 }
    .help(LocalActionSpec.arrangements.actionSpec.helpText)
    .popover(
        isPresented: $showArrangementPanel,
        attachmentAnchor: .point(.trailing),
        arrowEdge: .leading
    ) {
        ArrangementPanel(
            tabId: tabId,
            panes: panes,
            arrangements: arrangements,
            onPaneAction: { actionDispatcher.dispatch($0) },
            onSaveArrangement: {
                // Note: saveArrangement is injected as a closure, not a PaneActionCommand.
                // The collapsed bar receives this closure from the container (same pattern
                // as TabBarArrangementButton in CustomTabBar.swift). See the
                // onSaveArrangement parameter added to CollapsedPaneBar's init.
                onSaveArrangement?()
            },
            highlightPaneId: paneId
        )
    }
}
```

- [ ] **Step 7: Extract frame preference background**

Extract the existing `GeometryReader` block into a computed property to keep the body clean:

```swift
private var framePreferenceBackground: some View {
    GeometryReader { geo in
        if let dropTargetCoordinateSpace {
            let frame = geo.frame(in: .named(dropTargetCoordinateSpace))
            if useDrawerFramePreference {
                Color.clear
                    .preference(
                        key: DrawerPaneFramePreferenceKey.self,
                        value: [paneId: frame]
                    )
                    .preference(
                        key: PaneFramePreferenceKey.self,
                        value: [paneId: geo.frame(in: .named("tabContainer"))]
                    )
            } else {
                Color.clear.preference(
                    key: PaneFramePreferenceKey.self,
                    value: [paneId: frame]
                )
            }
        } else {
            Color.clear
        }
    }
}
```

- [ ] **Step 8: Verify NSColor(hex:) exists**

The accent bar uses `NSColor(hex:)`. Search the codebase:
```bash
grep -r "NSColor.*hex" Sources/ --include="*.swift" | head -5
```
If it doesn't exist, use `Color(nsColor: .controlAccentColor)` as the fallback or implement a simple hex initializer.

- [ ] **Step 9: Build and verify**

Run: `mise run build`
Expected: BUILD SUCCEEDED

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: redesign CollapsedPaneBar with management-mode styling and arrangement popover"
```

---

## Task 8: Wire Visibility Toggle Through Tab Strip (scoped, not global)

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift` (add `collapsedPaneWidth` parameter)
- Modify: `Sources/AgentStudio/Features/Terminal/Restore/TerminalPaneGeometryResolver.swift` (accept `collapsedPaneWidth`)
- Modify: `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift` (pass effective width for tabs, full width for drawers)
- NO policy changes to `DrawerPanel.swift` — drawers always show bars

The toggle decision lives in the **caller**, not in `FlatPaneStripContent`. `FlatPaneStripContent` is a generic component used by both tab strips and drawers. It receives `collapsedPaneWidth` as a parameter — the caller decides the value.

```
    FlatTabStripContainer (tab strip caller)
        → computes effectiveCollapsedWidth based on toggle + management mode
        → passes to FlatPaneStripContent(collapsedPaneWidth: effectiveCollapsedWidth)

    DrawerPanel (drawer caller)
        → always passes CollapsedPaneBar.barWidth
        → toggle has no effect on drawers
```

- [ ] **Step 1: Add collapsedPaneWidth parameter to FlatPaneStripContent**

In `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift`, add a new property:

```swift
struct FlatPaneStripContent: View {
    let layout: Layout
    let tabId: UUID
    let activePaneId: UUID?
    let minimizedPaneIds: Set<UUID>
    let collapsedPaneWidth: CGFloat  // NEW — caller decides
    let closeTransitionCoordinator: PaneCloseTransitionCoordinator
    // ... rest unchanged
```

Update the internal `FlatTabStripMetrics.compute()` call (line 20-26) to use this parameter instead of hardcoded `CollapsedPaneBar.barWidth`:

```swift
let metrics = FlatTabStripMetrics.compute(
    layout: layout,
    in: CGRect(origin: .zero, size: geometry.size),
    dividerThickness: AppStyle.paneGap,
    minimizedPaneIds: minimizedPaneIds,
    collapsedPaneWidth: collapsedPaneWidth  // was: CollapsedPaneBar.barWidth
)
```

Also update the all-minimized fallback HStack to use `collapsedPaneWidth`:
```swift
if metrics.allMinimized {
    if collapsedPaneWidth > 0 {
        HStack(spacing: 0) {
            ForEach(layout.paneIds, id: \.self) { paneId in
                CollapsedPaneBar(...)
                    .frame(width: collapsedPaneWidth)
            }
            Spacer()
        }
    }
}
```

Pass `collapsedPaneWidth` through to `PaneSegmentSlotView` as well. In the slot view, guard rendering:
```swift
if segment.isMinimized {
    if collapsedPaneWidth > 0 {
        CollapsedPaneBar(...)
    }
} else if let paneHost = paneSlot.host {
    // ... existing code
}
```

- [ ] **Step 2: Update FlatTabStripContainer to compute effective width**

In `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`, compute the effective collapsed width and pass it:

```swift
let showMinimizedBars = managementMode.isActive || atom(\.uiState).showMinimizedBars
let effectiveCollapsedWidth: CGFloat = showMinimizedBars ? CollapsedPaneBar.barWidth : 0
let metrics = FlatTabStripMetrics.compute(
    layout: layout,
    in: containerBounds,
    dividerThickness: AppStyle.paneGap,
    minimizedPaneIds: minimizedPaneIds,
    collapsedPaneWidth: effectiveCollapsedWidth
)
```

Update the all-minimized HStack (lines 53-67):
```swift
} else if metrics.allMinimized {
    if showMinimizedBars {
        HStack(spacing: 0) {
            ForEach(layout.paneIds, id: \.self) { paneId in
                CollapsedPaneBar(...)
                    .frame(width: CollapsedPaneBar.barWidth)
            }
            Spacer()
        }
    }
```

Pass `effectiveCollapsedWidth` to `FlatPaneStripContent`:
```swift
FlatPaneStripContent(
    layout: layout,
    tabId: tabId,
    activePaneId: activePaneId,
    minimizedPaneIds: minimizedPaneIds,
    collapsedPaneWidth: effectiveCollapsedWidth,  // NEW
    closeTransitionCoordinator: closeTransitionCoordinator,
    // ... rest unchanged
)
```

- [ ] **Step 3: Verify DrawerPanel passes full bar width (no changes needed)**

Check `Sources/AgentStudio/Core/Views/Drawer/DrawerPanel.swift:206`. The `FlatPaneStripContent` call there needs to pass the new `collapsedPaneWidth` parameter. It should ALWAYS pass `CollapsedPaneBar.barWidth`:

```swift
FlatPaneStripContent(
    layout: layout,
    tabId: tabId,
    activePaneId: activePaneId,
    minimizedPaneIds: minimizedPaneIds,
    collapsedPaneWidth: CollapsedPaneBar.barWidth,  // drawers always show bars
    // ... rest unchanged
)
```

- [ ] **Step 4: Make TerminalPaneGeometryResolver caller-owned**

In `Sources/AgentStudio/Features/Terminal/Restore/TerminalPaneGeometryResolver.swift`, change the resolver signature so callers provide the collapsed width:
```swift
static func resolveFrames(
    for layout: Layout,
    in availableRect: CGRect,
    dividerThickness: CGFloat,
    minimizedPaneIds: Set<UUID> = [],
    collapsedPaneWidth: CGFloat
) -> [UUID: CGRect]
```

Use that parameter in the internal `FlatTabStripMetrics.compute(...)` call.

- [ ] **Step 5: Pass the correct width at each restore call site**

In `Sources/AgentStudio/App/Coordination/PaneCoordinator+ViewLifecycle.swift`:

- Top-level tab restore path computes the same `effectiveCollapsedWidth` rule as the live tab UI:
  ```swift
  let showMinimizedBars = managementMode.isActive || atom(\.uiState).showMinimizedBars
  let effectiveCollapsedWidth: CGFloat = showMinimizedBars ? CollapsedPaneBar.barWidth : 0
  ```
  Pass that width to `TerminalPaneGeometryResolver.resolveFrames(...)` for the tab layout.

- Drawer restore path always passes `CollapsedPaneBar.barWidth`.

This keeps restore geometry aligned with the actual UI policy:
- top-level tabs can reclaim space when bars are hidden
- drawer minimized panes always remain visible

- [ ] **Step 6: Build and verify**

Run: `mise run build`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: scope showMinimizedBars toggle to tab strip only, drawers always show bars"
```

---

## Task 9: Update Tests

**Files:**
- Modify: `Tests/AgentStudioTests/Core/Models/MinimizeLayoutIntegrationTests.swift`

The existing tests reference `CollapsedPaneBar.barWidth` which changed from `30` to `AppStyle.collapsedBarWidth` (40). The tests should still pass since they use the constant, not a hardcoded value. But verify, and add a test for zero-width collapsed panes.

- [ ] **Step 1: Verify existing tests still pass**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "MinimizeLayout" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS (tests use `CollapsedPaneBar.barWidth`, not hardcoded 30)

- [ ] **Step 2: Add test for zero-width collapsed panes**

Add to `MinimizeLayoutIntegrationTests`:

```swift
@Test
func test_flatStripMetrics_zeroCollapsedWidth_minimizedPanesTakeNoSpace() {
    // Arrange
    let (tab, paneIds) = createTabWithPanes(3)
    store.minimizePane(paneIds[1], inTab: tab.id)

    // Act
    let updated = store.tab(tab.id)!
    let renderInfo = FlatTabStripMetrics.compute(
        layout: updated.layout,
        in: CGRect(x: 0, y: 0, width: 1200, height: 700),
        dividerThickness: AppStyle.paneGap,
        minimizedPaneIds: updated.minimizedPaneIds,
        collapsedPaneWidth: 0
    )

    // Assert
    let minimizedSegment = renderInfo.paneSegments.first { $0.isMinimized }
    #expect(minimizedSegment != nil)
    #expect(minimizedSegment?.frame.width == 0)

    let visibleSegments = renderInfo.paneSegments.filter { !$0.isMinimized }
    let totalVisibleWidth = visibleSegments.reduce(0) { $0 + $1.frame.width }
    #expect(totalVisibleWidth > 1199) // Nearly full width minus divider
}
```

- [ ] **Step 3: Run all tests**

Run: `mise run test`
Expected: All tests pass

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test: add zero-width collapsed pane test for hidden minimized bars"
```

---

## Task 10: Lint and Visual Verification

- [ ] **Step 1: Run full lint**

Run: `mise run lint`
Expected: Zero errors

- [ ] **Step 2: Build and launch for visual verification**

```bash
mise run build
pkill -9 -f "AgentStudio" 2>/dev/null || true
.build/debug/AgentStudio &
```

- [ ] **Step 3: Verify with Peekaboo**

```bash
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo see --app "PID:$PID" --json
```

Visual checklist:
- Collapsed bar is 40pt wide with white-on-dark surface (not old black-on-dark)
- Two circle buttons visible at top (expand + arrangement)
- Sideways title visible in middle with semibold weight
- Accent color bar visible at bottom (if pane has a repo)
- Hover brightens surface and stroke
- Expand button click expands the pane
- Arrangement button opens popover to the RIGHT with arrow on LEFT
- The origin pane row in the popover briefly highlights
- Toggle "Show minimized bars" in arrangement panel works
- When toggle is off + management mode off: bars disappear, space reclaimed
- When toggle is off + management mode on: bars appear (management always shows)
- Context menu (right-click) shows Expand and Close options
- Tooltip shows pane title on hover

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: visual adjustments from manual verification"
```
