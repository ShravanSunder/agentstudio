# Arrangement Chip Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `rectangle.3.group` icon + `activeArrangementBadgeNumber` overlay pill on the tab bar with a labeled capsule chip that shows `[◫  2 · name]` when on a custom arrangement, and collapses to a plain icon `[◫]` on default. Drop the duplicate arrangement button from each `CollapsedPaneBar`.

**Architecture:** Extract a focused `TabBarArrangementChip` view that renders icon-only on default and `icon + index + middot + name` when a custom arrangement is active. The button's `Capsule()` background renders as a circle when content is square (icon-only) and as a pill when content expands. State lives on the picker itself; no more notification-style badge for arrangement index. The `hiddenMinimizedCount` overlay remains — it's the only true notification. `CollapsedPaneBar`'s arrangement button is removed; per-pane bar keeps only the expand action.

**Tech Stack:** Swift 6.2, SwiftUI, `@MainActor` atoms, existing `TabBarAdapter`, `AtomRegistry`, Swift Testing (`@Suite`, `@Test`, `#expect`), `mise run` for build/test/lint

---

## Design

### Current state (what's there today)

```text
┌───────────────────────────────────────────────────────────────────────┐
│ Tab bar — current                                                     │
├───────────────────────────────────────────────────────────────────────┤
│                                                                       │
│  ┌────┐ ┌────┐  ┌──────────────────────────────────────┐              │
│  │ ▤  │ │◫ ② │  │ agent-vm · master              ⌘1    │              │
│  └────┘ └────┘  └──────────────────────────────────────┘              │
│   mgmt    ▲                                                           │
│          pill badge reads like a notification,                        │
│          and the number is the only "where am I" signal               │
│                                                                       │
│  CollapsedPaneBar (duplicate arrangement button — to be removed):     │
│                                                                       │
│    ┌────┐                                                             │
│    │ ↔  │    expand pane (per-pane — correct)                         │
│    └────┘                                                             │
│    ┌────┐                                                             │
│    │ ◫  │    arrangement popover (tab-level — DUPLICATE of tab bar)   │
│    └────┘                                                             │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘
```

### Target chip states

```text
╔═══════════════════════════════════════════════════════════════════════╗
║ Default arrangement — icon only, circle (same footprint as today)     ║
╠═══════════════════════════════════════════════════════════════════════╣
║                                                                       ║
║  ┌────┐ ┌────┐  ┌──────────────────────────────────────┐              ║
║  │ ▤  │ │ ◫  │  │ agent-vm · master              ⌘1    │              ║
║  └────┘ └────┘  └──────────────────────────────────────┘              ║
║                                                                       ║
╚═══════════════════════════════════════════════════════════════════════╝

╔═══════════════════════════════════════════════════════════════════════╗
║ Active custom arrangement — capsule expands with index + name         ║
╠═══════════════════════════════════════════════════════════════════════╣
║                                                                       ║
║  ┌────┐ ┌──────────────────┐  ┌─────────────────────────┐             ║
║  │ ▤  │ │ ◫   2 · coding   │  │ agent-vm · master  ⌘1   │             ║
║  └────┘ └──────────────────┘  └─────────────────────────┘             ║
║           ▲   ▲    ▲                                                  ║
║         icon  │    name (regular, .secondary)                         ║
║               └─── index (semibold, .secondary) — mgmt-layer          ║
║                    shortcut anchor (1/2/3 inside management mode)     ║
║                                                                       ║
╚═══════════════════════════════════════════════════════════════════════╝

╔═══════════════════════════════════════════════════════════════════════╗
║ With hidden-minimized badge — real notification (unchanged)           ║
╠═══════════════════════════════════════════════════════════════════════╣
║                                                                       ║
║  ┌────┐ ┌──────────────────┐③ ┌─────────────────────────┐             ║
║  │ ▤  │ │ ◫   2 · coding   │  │ agent-vm · master  ⌘1   │             ║
║  └────┘ └──────────────────┘  └─────────────────────────┘             ║
║                            ▲                                          ║
║               3 minimized panes hidden (legitimate notification)      ║
║                                                                       ║
╚═══════════════════════════════════════════════════════════════════════╝

╔═══════════════════════════════════════════════════════════════════════╗
║ Long name — name truncates, index + icon always visible               ║
╠═══════════════════════════════════════════════════════════════════════╣
║                                                                       ║
║  ┌────┐ ┌────────────────────────┐  ┌────────────────────┐            ║
║  │ ▤  │ │ ◫   2 · my-long-nam…   │  │ agent-vm · master  │            ║
║  └────┘ └────────────────────────┘  └────────────────────┘            ║
║                                                                       ║
╚═══════════════════════════════════════════════════════════════════════╝

╔═══════════════════════════════════════════════════════════════════════╗
║ Management layer active — name cap raised from 100pt → 200pt          ║
╠═══════════════════════════════════════════════════════════════════════╣
║                                                                       ║
║  ┌────┐ ┌────────────────────────────────┐  ┌──────────────┐          ║
║  │ ▤  │ │ ◫   2 · documentation-review   │  │ agent-vm ·…  │          ║
║  └────┘ └────────────────────────────────┘  └──────────────┘          ║
║  active                                                               ║
║                                                                       ║
╚═══════════════════════════════════════════════════════════════════════╝
```

### Chip anatomy

```text
┌──────────────────────────────┐
│  ◫    2  ·  coding           │   22pt tall (toolbarButtonSize)
│  ▲    ▲  ▲  ▲                │
│  │    │  │  └─ name: system(textXs, .regular), .secondary, truncated
│  │    │  └──── middot: system(textXs), .tertiary
│  │    └─────── index: system(textXs, .semibold), .secondary
│  └──────────── icon: compactIconSize, .secondary
│
│  gap(icon ↔ index): 6pt                                                
│  gap(index ↔ middot ↔ name): 4pt                                       
│  padding leading/trailing: 8pt (custom arrangement) / 0pt (default)    
│  minWidth: toolbarButtonSize (22pt) — keeps default as circle          
│  background: Capsule(), fill derived from hover/press state            
│  shape transitions naturally: square = circle, wider = pill            
└──────────────────────────────┘
```

### Hover / press states

```text
Rest:               ┌──────────────────┐
                    │  ◫   2 · coding  │   fill: AppStyles.fillMuted
                    └──────────────────┘

Hover:              ┌──────────────────┐
                    │  ◫   2 · coding  │   fill: AppStyles.fillPressed
                    └──────────────────┘

Popover open:       ┌──────────────────┐
                    │  ◫   2 · coding  │   fill: AppStyles.fillActive
                    └──────────────────┘
```

### Name width policy

Use **pixel-based** truncation on the name text, not character count. SF Pro is proportional — character count yields inconsistent widths.

| Context | Name `maxWidth` | Rough visual equivalent |
|---|---|---|
| Tab bar, management layer inactive | `100pt` | ~12-14 proportional chars |
| Tab bar, management layer active | `200pt` | ~25-28 proportional chars |

Icon + index + middot + padding stay fixed. Only the name text has a `maxWidth`.

### CollapsedPaneBar cleanup

```text
Before                              After
┌────┐                              ┌────┐
│ ↔  │   expand (per-pane)          │ ↔  │   expand (per-pane)
└────┘                              └────┘
┌────┐
│ ◫  │   arrangement (DUPLICATE)    (removed)
└────┘
```

---

## File Structure

Files created:
- `Sources/AgentStudio/App/Panes/TabBar/TabBarArrangementChip.swift` — new focused view, icon-only on default, expanded capsule on custom arrangement
- `Tests/AgentStudioTests/App/Panes/TabBar/TabBarArrangementChipTests.swift` — direct tests on chip props (hasCustomArrangement, name width, background shape)

Files modified:
- `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift` — `TabBarArrangementButton` switches its label from `Image + overlay-badge` to `TabBarArrangementChip(...)`; remove `activeArrangementBadgeNumber` overlay code; keep `hiddenMinimizedCount` overlay
- `Sources/AgentStudio/Core/Views/Splits/CollapsedPaneBar.swift` — delete `arrangementButton`, `isArrangementHovered`, `isArrangementPanelPresented`, `arrangementPopoverToggleGate`, and the arrangement `.popover(...)`. Keep `expandButton` and its state.
- `Tests/AgentStudioTests/App/Panes/TabBar/TabBarAdapterTests.swift` — add a test asserting `activeArrangementName` is non-nil when a non-default custom arrangement is active (the value is already wired in the adapter but currently has no consumer; the new chip is the consumer).

Each file has a single responsibility:
- `TabBarArrangementChip.swift` owns the chip layout and visual states.
- `CustomTabBar.swift` keeps orchestration (popover, adapter binding, overlay of `hiddenMinimizedCount`).
- `CollapsedPaneBar.swift` returns to per-pane concerns only.

---

## Implementation Changes

### Task 1: Create `TabBarArrangementChip`

**Files:**
- Create: `Sources/AgentStudio/App/Panes/TabBar/TabBarArrangementChip.swift`
- Create: `Tests/AgentStudioTests/App/Panes/TabBar/TabBarArrangementChipTests.swift`

- [ ] **Step 1: Write the failing test file**

Create `Tests/AgentStudioTests/App/Panes/TabBar/TabBarArrangementChipTests.swift`:

```swift
import Testing
import SwiftUI
@testable import AgentStudio

@MainActor
@Suite("TabBarArrangementChip")
struct TabBarArrangementChipTests {
    @Test("reports no custom arrangement when index and name are nil")
    func reportsNoCustomArrangementWhenBothNil() {
        let chip = TabBarArrangementChip(
            index: nil,
            name: nil,
            isHovered: false,
            isPressed: false,
            nameMaxWidth: 100
        )
        #expect(chip.hasCustomArrangement == false)
    }

    @Test("reports custom arrangement when index and name are both set")
    func reportsCustomArrangementWhenBothSet() {
        let chip = TabBarArrangementChip(
            index: 2,
            name: "coding",
            isHovered: false,
            isPressed: false,
            nameMaxWidth: 100
        )
        #expect(chip.hasCustomArrangement == true)
    }

    @Test("reports no custom arrangement when only one of index or name is set")
    func reportsNoCustomArrangementWhenOnlyOneSet() {
        let chipWithOnlyIndex = TabBarArrangementChip(
            index: 2, name: nil, isHovered: false, isPressed: false, nameMaxWidth: 100
        )
        let chipWithOnlyName = TabBarArrangementChip(
            index: nil, name: "coding", isHovered: false, isPressed: false, nameMaxWidth: 100
        )
        #expect(chipWithOnlyIndex.hasCustomArrangement == false)
        #expect(chipWithOnlyName.hasCustomArrangement == false)
    }

    @Test("uses pressed fill opacity when isPressed is true")
    func usesPressedFillOpacityWhenPressed() {
        let chip = TabBarArrangementChip(
            index: 2, name: "coding", isHovered: false, isPressed: true, nameMaxWidth: 100
        )
        #expect(chip.chipFillOpacity == AppStyles.fillActive)
    }

    @Test("uses hover fill opacity when hovered and not pressed")
    func usesHoverFillOpacityWhenHovered() {
        let chip = TabBarArrangementChip(
            index: 2, name: "coding", isHovered: true, isPressed: false, nameMaxWidth: 100
        )
        #expect(chip.chipFillOpacity == AppStyles.fillPressed)
    }

    @Test("uses muted fill opacity when at rest")
    func usesMutedFillOpacityWhenAtRest() {
        let chip = TabBarArrangementChip(
            index: 2, name: "coding", isHovered: false, isPressed: false, nameMaxWidth: 100
        )
        #expect(chip.chipFillOpacity == AppStyles.fillMuted)
    }

    @Test("returns 100pt name width when management layer inactive")
    func returnsNarrowNameWidthWhenManagementLayerInactive() {
        #expect(TabBarArrangementChip.nameMaxWidth(isManagementLayerActive: false) == 100)
    }

    @Test("returns 200pt name width when management layer active")
    func returnsWideNameWidthWhenManagementLayerActive() {
        #expect(TabBarArrangementChip.nameMaxWidth(isManagementLayerActive: true) == 200)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --build-path ".build-agent-$PPID" --filter "TabBarArrangementChipTests"
```

Expected: FAIL — `TabBarArrangementChip` does not exist yet.

- [ ] **Step 3: Create the chip view**

Create `Sources/AgentStudio/App/Panes/TabBar/TabBarArrangementChip.swift`:

```swift
import SwiftUI

/// Tab-bar chip for the arrangement popover button.
/// Renders as a circle (icon only) on the default arrangement, or as a capsule
/// with `icon + index + middot + name` when a custom arrangement is active.
/// The index anchors the management-layer shortcut (1/2/3) once shortcuts land.
struct TabBarArrangementChip: View {
    let index: Int?
    let name: String?
    let isHovered: Bool
    let isPressed: Bool
    let nameMaxWidth: CGFloat

    var hasCustomArrangement: Bool {
        index != nil && name != nil
    }

    var chipFillOpacity: Double {
        if isPressed { return AppStyles.fillActive }
        if isHovered { return AppStyles.fillPressed }
        return AppStyles.fillMuted
    }

    /// Pure helper: name truncation cap based on management-layer state.
    /// Factored out so it's testable without constructing a SwiftUI view hierarchy.
    static func nameMaxWidth(isManagementLayerActive: Bool) -> CGFloat {
        isManagementLayerActive ? 200 : 100
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: AppStyles.compactIconSize, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)

            if let index, let name {
                HStack(spacing: 4) {
                    Text("\(index)")
                        .font(.system(size: AppStyles.textXs, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.system(size: AppStyles.textXs))
                        .foregroundStyle(.tertiary)
                    Text(name)
                        .font(.system(size: AppStyles.textXs))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: nameMaxWidth, alignment: .leading)
                }
            }
        }
        .frame(height: AppStyles.toolbarButtonSize)
        .padding(.horizontal, hasCustomArrangement ? 8 : 0)
        .frame(minWidth: AppStyles.toolbarButtonSize)
        .background(
            Capsule()
                .fill(Color.white.opacity(chipFillOpacity))
        )
        .contentShape(Capsule())
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
swift test --build-path ".build-agent-$PPID" --filter "TabBarArrangementChipTests"
```

Expected: PASS — 6 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/TabBar/TabBarArrangementChip.swift \
        Tests/AgentStudioTests/App/Panes/TabBar/TabBarArrangementChipTests.swift
git commit -m "$(cat <<'EOF'
Add TabBarArrangementChip view with icon-only and labeled-capsule states

The chip collapses to a circle on default arrangement and expands to a pill
with index + middot + name on custom arrangements. Background uses Capsule
so the shape transition is automatic based on content width.
EOF
)"
```

---

### Task 2: Integrate chip into `TabBarArrangementButton`

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift:404-509`

- [ ] **Step 1: Write a failing adapter test that asserts `activeArrangementName` is populated for non-default arrangements**

Open `Tests/AgentStudioTests/App/Panes/TabBar/TabBarAdapterTests.swift` and add:

```swift
@Test("exposes activeArrangementName when a non-default custom arrangement is active")
func exposesActiveArrangementNameForCustomActive() {
    // Arrange: build a workspace with a custom arrangement "coding" active
    let fixture = TabBarAdapterFixture.withCustomArrangement(named: "coding")

    // Act
    let items = fixture.adapter.tabs

    // Assert
    let activeItem = items.first { $0.id == fixture.activeTabId }
    #expect(activeItem?.activeArrangementName == "coding")
    #expect(activeItem?.activeArrangementBadgeNumber == 1)
}
```

If `TabBarAdapterFixture.withCustomArrangement(named:)` does not exist yet, add this helper to the existing fixtures file `Tests/AgentStudioTests/App/Panes/TabBar/TabBarAdapterFixtures.swift` (create the file if missing):

```swift
import Foundation
@testable import AgentStudio

@MainActor
enum TabBarAdapterFixture {
    struct Built {
        let adapter: TabBarAdapter
        let activeTabId: UUID
    }

    static func withCustomArrangement(named name: String) -> Built {
        let registry = AtomRegistry()
        let tabShell = registry.workspaceTabShell
        let tabArrangement = registry.workspaceTabArrangement
        let pane = registry.workspacePane
        let paneId = UUID()
        let tabId = UUID()
        pane.hydrate(persistedPanes: [.makeTerminalPane(id: paneId)], validWorktreeIds: [])
        let defaultArrangement = PaneArrangement(
            name: "Default",
            isDefault: true,
            layout: Layout.leaf(paneId)
        )
        let customArrangement = PaneArrangement(
            name: name,
            isDefault: false,
            layout: Layout.leaf(paneId)
        )
        let state = TabArrangementState(
            tabId: tabId,
            allPaneIds: [paneId],
            arrangements: [defaultArrangement, customArrangement],
            activeArrangementId: customArrangement.id,
            activePaneId: paneId,
            zoomedPaneId: nil
        )
        tabShell.appendTabShell(TabShell(id: tabId, name: "Tab"))
        tabArrangement.appendState(state)
        let adapter = TabBarAdapter(registry: registry)
        return Built(adapter: adapter, activeTabId: tabId)
    }
}
```

If the fixture file already exists, add just the method. If `Pane.makeTerminalPane(id:)` doesn't exist as a test helper, reuse whatever existing `Pane` factory is used in other tests (look in `Tests/AgentStudioTests/Helpers/` — `WorkspacePaneTestFactory` or similar).

- [ ] **Step 2: Run it and verify fail or pass**

```bash
swift test --build-path ".build-agent-$PPID" --filter "TabBarAdapterTests"
```

Expected: PASS if the adapter already computes `activeArrangementName` correctly (it does, per `TabBarAdapter.swift:147`). If it fails, the fixture is wrong — fix the fixture, not the adapter.

- [ ] **Step 3: Replace the `Image + overlay-badge` label with the chip**

In `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift`, locate `TabBarArrangementButton`'s `body` (starts around line 430). Replace the current `Button { ... } label: { Image(systemName: "rectangle.3.group") ... .overlay { ... } ... }` with the chip. The new label block:

```swift
var body: some View {
    Button {
        popoverToggleGate.toggle(isPresented: &isPanelPresented)
    } label: {
        TabBarArrangementChip(
            index: activeArrangementBadgeNumber,
            name: activeArrangementName,
            isHovered: isHovered,
            isPressed: isPanelPresented,
            nameMaxWidth: chipNameMaxWidth
        )
        .overlay(alignment: .topTrailing) {
            if hiddenMinimizedCount > 0 {
                Text("\(hiddenMinimizedCount)")
                    .font(.system(size: AppStyles.textXs, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AppStyles.spacingTight)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(AppStyles.fillHover))
                    )
                    .fixedSize()
                    .offset(x: 10, y: -6)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeOut(duration: AppStyles.animationFast), value: hiddenMinimizedCount)
        .animation(.easeOut(duration: AppStyles.animationFast), value: activeArrangementName)
    }
    .buttonStyle(.plain)
    .onHover { hovering in isHovered = hovering }
    .help(LocalActionSpec.arrangements.actionSpec.helpText)
    .popover(
        isPresented: Binding(
            get: { isPanelPresented },
            set: { newValue in
                if !newValue && isPanelPresented {
                    isPanelPresented = false
                    popoverToggleGate.recordSystemDismissal()
                } else {
                    isPanelPresented = newValue
                }
            }
        ),
        attachmentAnchor: ArrangementPanelPopoverPlacement.tabBar.attachmentAnchor,
        arrowEdge: ArrangementPanelPopoverPlacement.tabBar.arrowEdge
    ) {
        if let tab = activeTab, let onPaneAction, let onSaveArrangement {
            ArrangementPanel(
                tabId: tab.id,
                panes: tab.panes,
                arrangements: tab.arrangements,
                onPaneAction: onPaneAction,
                onSaveArrangement: { onSaveArrangement(tab.id) },
                showMinimizedBarsBinding: Binding(
                    get: { atom(\.uiState).showMinimizedBars },
                    set: { atom(\.uiState).setShowMinimizedBars($0) }
                )
            )
        }
    }
}
```

Also in `TabBarArrangementButton`, add these derived properties alongside `activeArrangementBadgeNumber` (around line 426):

```swift
private var activeArrangementName: String? {
    activeTab?.activeArrangementName
}

private var chipNameMaxWidth: CGFloat {
    TabBarArrangementChip.nameMaxWidth(isManagementLayerActive: atom(\.managementLayer).isActive)
}
```

The `chipNameMaxWidth` computed property stays thin (1 line) — it reads the atom and delegates to the pure helper. The helper is what carries the testable logic.

Delete the old `.overlay(alignment: .topTrailing) { if let arrangementBadgeNumber = activeArrangementBadgeNumber { ... } ... }` block in its entirety (the arrangement-index pill is gone — its role is now the chip itself).

- [ ] **Step 4: Build and run the full test suite**

```bash
mise run build
swift test --build-path ".build-agent-$PPID" --filter "TabBarArrangementChipTests|TabBarAdapterTests"
```

Expected: build succeeds, both suites pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift \
        Tests/AgentStudioTests/App/Panes/TabBar/TabBarAdapterTests.swift \
        Tests/AgentStudioTests/App/Panes/TabBar/TabBarAdapterFixtures.swift
git commit -m "$(cat <<'EOF'
Switch tab-bar arrangement button to labeled chip

The arrangement button now renders TabBarArrangementChip, which carries
index + name on custom arrangements and collapses to an icon on default.
The arrangement-index notification pill is removed; hiddenMinimizedCount
stays as the only legitimate badge overlay.
EOF
)"
```

---

### Task 3: Remove duplicate arrangement button from `CollapsedPaneBar`

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/CollapsedPaneBar.swift`
- Modify: `Tests/AgentStudioTests/Core/Views/CollapsedPaneBarTests.swift` (create if missing)

- [ ] **Step 1: Write failing test asserting CollapsedPaneBar exposes only per-pane actions**

SwiftUI view testing is limited without adding ViewInspector. Test the **observable contract** instead: the bar's set of published action triggers should contain pane-level actions (expand, close) and exclude tab-level ones (arrangement popover, arrangement switch).

Open (or create) `Tests/AgentStudioTests/Core/Views/CollapsedPaneBarTests.swift`:

```swift
import Testing
@testable import AgentStudio

@MainActor
@Suite("CollapsedPaneBar")
struct CollapsedPaneBarTests {
    @Test("exposes expand as its only primary action button")
    func exposesOnlyExpandButton() {
        // Arrange: pull the primary-button list from the view's model/type surface.
        // If CollapsedPaneBar exposes button identifiers as a static list or enum,
        // assert it only contains `.expand`. If not, add a static
        // `primaryButtonIdentifiers: [CollapsedPaneBarButtonId]` on CollapsedPaneBar
        // in the same commit so this test can anchor on it.
        #expect(CollapsedPaneBar.primaryButtonIdentifiers == [.expand])
    }

    @Test("does not expose an arrangement-popover button")
    func doesNotExposeArrangementButton() {
        #expect(!CollapsedPaneBar.primaryButtonIdentifiers.contains(.arrangementPopover))
    }
}

enum CollapsedPaneBarButtonId: Equatable {
    case expand
    case arrangementPopover
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
swift test --build-path ".build-agent-$PPID" --filter "CollapsedPaneBarTests"
```

Expected: FAIL — `CollapsedPaneBar.primaryButtonIdentifiers` does not exist, and `CollapsedPaneBarButtonId` is not yet where the view can reference it. That compile failure *is* the failing test.

- [ ] **Step 3: Delete the arrangement button view and its state**

In `Sources/AgentStudio/Core/Views/Splits/CollapsedPaneBar.swift`:

1. Remove the `private var arrangementButton: some View { ... }` computed property entirely (currently around lines 129-170).
2. Remove any `@State` properties solely used by the arrangement button:
   - `@State private var isArrangementHovered = false`
   - `@State private var isArrangementPanelPresented = false`
   - `@State private var arrangementPopoverToggleGate = PopoverToggleGate()`
3. In the `body` of the view, remove the call site that renders `arrangementButton` (should sit next to `expandButton` in the vertical stack).
4. If the file imports anything solely for the removed code (e.g., `ArrangementPanel`-only imports), clean those up.
5. Add the contract hook at the top of the struct so the test in Step 1 can anchor:

```swift
extension CollapsedPaneBar {
    /// Ordered list of primary action buttons this bar renders.
    /// Asserted in `CollapsedPaneBarTests` to prevent the arrangement
    /// button from being reintroduced.
    static let primaryButtonIdentifiers: [CollapsedPaneBarButtonId] = [.expand]
}
```

`CollapsedPaneBarButtonId` is defined in the test file. Move it into production code alongside the extension so both test and production use the same enum:

```swift
// In Sources/AgentStudio/Core/Views/Splits/CollapsedPaneBar.swift, at file top after imports:

enum CollapsedPaneBarButtonId: Equatable {
    case expand
    case arrangementPopover
}
```

Then remove the enum duplicate from the test file.

- [ ] **Step 4: Run the test to verify it passes**

```bash
swift test --build-path ".build-agent-$PPID" --filter "CollapsedPaneBarTests"
```

Expected: PASS — the enum now has one entry and the test asserts that.

- [ ] **Step 5: Build and run all affected tests**

```bash
mise run build
swift test --build-path ".build-agent-$PPID" --filter "CollapsedPaneBar|MinimizeLayoutIntegrationTests"
```

Expected: build passes, tests pass.

- [ ] **Step 6: Visual sanity check with Peekaboo**

Per `CLAUDE.md` — never use app name, always PID. Open a workspace with at least one minimized pane, then:

```bash
BUILD_PATH=".build-agent-$PPID"
"$BUILD_PATH/debug/AgentStudio" &
PID=$!
peekaboo see --app "PID:$PID" --json
```

Verify:
- The collapsed pane bar shows **only** the expand button (↔), no grid icon next to it.
- The tab bar's arrangement chip still opens the arrangement popover.

- [ ] **Step 7: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/CollapsedPaneBar.swift
git commit -m "$(cat <<'EOF'
Remove duplicate arrangement button from CollapsedPaneBar

The collapsed pane bar should only carry per-pane actions (expand).
Tab-level arrangement access lives in the tab-bar chip, which is now
labeled and harder to miss.
EOF
)"
```

---

### Task 4: Full verification

**Files:**
- No code changes; this task runs the full suite and lint.

- [ ] **Step 1: Run the full test suite**

```bash
mise run test
```

Expected: exit 0, all tests pass. Show the pass/fail counts in the task report.

- [ ] **Step 2: Run lint**

```bash
mise run lint
```

Expected: exit 0, zero errors.

- [ ] **Step 3: End-to-end visual verification**

Build, launch, exercise four cases in the UI:

1. Open a workspace, single tab, default arrangement → chip should show icon only, circle.
2. Create a custom arrangement named "coding" → chip should expand to `[◫ 1 · coding]`.
3. Rename to something long like "documentation-review" → chip should truncate to `[◫ 1 · documentati…]` (or similar at 100pt cap).
4. Activate management layer → chip should expand to full name `[◫ 1 · documentation-review]`.
5. Minimize panes until `hiddenMinimizedCount > 0` → small capsule badge appears at the top-right of the chip.

Each via:

```bash
BUILD_PATH=".build-agent-$PPID"
"$BUILD_PATH/debug/AgentStudio" &
PID=$!
peekaboo see --app "PID:$PID" --json
```

Record a short written summary of what's visible for each case.

- [ ] **Step 4: Final commit if any fixes were made during verification**

If lint or tests reported issues fixed during verification, commit them separately with a clear message. Otherwise skip.

---

## Test Plan

### Must-pass scenarios

1. **Default arrangement → icon-only chip.** `hasCustomArrangement == false`, content is just the icon, background capsule renders as a circle because `minWidth == height`. *Covered by `TabBarArrangementChipTests.reportsNoCustomArrangementWhenBothNil`.*
2. **Custom arrangement → labeled chip.** `hasCustomArrangement == true`, displays `icon + index + middot + name`, name truncates at 100pt. *Covered by `reportsCustomArrangementWhenBothSet` + pixel-level check visually via Peekaboo.*
3. **Management layer active → wider name.** `nameMaxWidth(isManagementLayerActive: true) == 200` vs `false → 100`. *Covered by `returnsNarrowNameWidthWhenManagementLayerInactive` and `returnsWideNameWidthWhenManagementLayerActive`.*
4. **Press state while popover open.** `isPressed == true`, fill opacity uses `AppStyles.fillActive`. *Covered by `usesPressedFillOpacityWhenPressed`.*
5. **Hover and rest fills.** `isHovered` flips fill to `fillPressed`; at rest, `fillMuted`. *Covered by `usesHoverFillOpacityWhenHovered` and `usesMutedFillOpacityWhenAtRest`.*
6. **Hidden minimized count badge still rendered.** `hiddenMinimizedCount > 0` shows the small pill overlay in the chip's top-right; that overlay is independent of arrangement state. *Covered by Peekaboo visual verification in Task 4 Step 3.*
7. **CollapsedPaneBar shows only expand button.** No arrangement `rectangle.3.group` icon on any minimized pane row. *Covered by `CollapsedPaneBarTests.exposesOnlyExpandButton` + `doesNotExposeArrangementButton` (regression-proof: the static `primaryButtonIdentifiers` list is the contract).*
8. **Adapter pipeline.** `TabBarAdapter.tabs` returns `TabBarItem` with `activeArrangementName` set to the custom arrangement's name and `activeArrangementBadgeNumber` set to its 1-based index among custom arrangements. *Covered by `TabBarAdapterTests.exposesActiveArrangementNameForCustomActive`.*

### Full verification

Run sequentially:

```bash
swift test --build-path ".build-agent-$PPID" --filter "TabBarArrangementChipTests|TabBarAdapterTests|CollapsedPaneBarTests"
mise run test
mise run lint
```

Expected:
- Focused suites pass.
- `mise run test` exits `0`.
- `mise run lint` exits `0`.

Visual verification via Peekaboo per Task 4 Step 3.

---

## Assumptions

- `TabBarAdapter.activeArrangementName` and `TabBarAdapter.activeArrangementBadgeNumber` are already computed correctly (verified: `TabBarAdapter.swift:147`, `:239-245`). This plan does not change the adapter — only wires its existing output into the chip.
- `AppStyles.fillMuted`, `fillPressed`, `fillActive`, `toolbarButtonSize`, `compactIconSize`, `textXs`, `spacingTight`, `animationFast`, `fillHover` all exist on main and are used as-is.
- `ArrangementPanelPopoverPlacement.tabBar.attachmentAnchor` / `arrowEdge` remain the current popover anchor policy.
- `atom(\.managementLayer).isActive` is the correct signal for "name cap should expand." If that atom is renamed or replaced before this plan lands, update the reference in `chipNameMaxWidth` accordingly.
- Management-layer-bound `1/2/3` keyboard shortcuts for switching arrangements are **not** part of this plan. They may land later, at which point the chip's index numeral can gain a subtle keycap treatment without restructuring the layout.
- The existing `CollapsedPaneBar.arrangementButton` was added for user convenience, but it renders the identical popover as the tab bar. Removing it simplifies the "one arrangement entry point per tab" model. If per-pane arrangement pickers are needed in the future, they should be a different (per-pane) action with a different icon.
- Name truncation uses pixel-based width (`.frame(maxWidth: 100)`), not a hard character cap. This tolerates proportional-font rendering.
