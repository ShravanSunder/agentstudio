# Collapsed Pane Bar — Review Fixes and Text Redesign

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix review issues from the first implementation pass and redesign the collapsed bar's text label to show structured repo/worktree/branch info with octicon icons instead of the raw `primaryLabel` string.

**Architecture:** The collapsed bar reads all state through atoms. A new `collapsedBarLabelParts(for:)` method on `PaneDisplayDerived` builds structured label parts using a view-neutral `CollapsedBarLabelPart` struct with its own `IconKind` and `TextWeight` enums (no SwiftUI dependency). The view maps these to `OcticonImage`/`Image(systemName:)` and `Font.Weight` at render time. The `title:` parameter is removed from `CollapsedPaneBar` — it reads its own label data from atoms. The accent color bar is removed. Toggle label changes to "Show minimized panes" with a management-mode hint. Tab bar arrangement popover arrow moves to the left side.

**Tech Stack:** Swift 6.2, SwiftUI, AtomRegistry pattern, OcticonImage

---

## Context

A first implementation of the collapsed pane bar redesign is already in place (uncommitted). The core infrastructure works: ArrangementPanel in Core, ArrangementDerived atom, UIStateAtom.showMinimizedBars with persistence, FlatPaneStripContent with caller-owned collapsedPaneWidth, drawer isolation. This plan addresses the review findings and remaining design decisions from the design conversation.

## Changes Summary

| # | What | Why |
|---|------|-----|
| 1 | Multi-part octicon label replaces primaryLabel text | Current text is too long, redundant (repo name appears twice), no visual structure |
| 2 | Remove `title:` parameter from CollapsedPaneBar | Bar reads its own label from atoms — external title threading is unnecessary |
| 3 | Remove accent color bar | Design decision — not needed with the new structured label |
| 4 | Fix button spacing (spacingTight → spacingStandard) | Buttons crammed together with no breathing room |
| 5 | Toggle label: "Show minimized panes" + management hint | Current "Hide minimized windows" is inverted and confusing |
| 6 | Remove `hideMinimizedBars` / `setHideMinimizedBars` from UIStateAtom | Dead code after toggle binding fix |
| 7 | Tab bar arrangement popover arrow → left side | Currently opens downward, should match collapsed bar's rightward popover |
| 8 | Animation on show/hide bars | Bars should animate in/out when toggle or management mode changes |
| 9 | ~~Stale closure fix~~ | Already fixed in first pass (verified: line 30 reads tab inside closure) |
| 10 | ~~accentColorHex tests~~ | Already exist at PaneDisplayDerivedTests.swift:71-109 |
| 11 | Fix resize dividers blocked by minimized panes | User can't resize visible panes when a minimized bar sits between them |
| 12 | Fix CWD "." in ManagementPaneIdentityStrip | CWD shows useless "." when cwd equals worktree root — skip the row |

## File Structure

### New Files
| File | Responsibility |
|------|----------------|
| `Tests/AgentStudioTests/Core/State/CollapsedBarLabelPartsTests.swift` | Tests for `collapsedBarLabelParts(for:)` |

### Modified Files
| File | Changes |
|------|---------|
| `Core/State/MainActor/Atoms/PaneDisplayDerived.swift` | Add `CollapsedBarLabelPart` struct + `collapsedBarLabelParts(for:)` method |
| `Core/Views/Splits/CollapsedPaneBar.swift` | Replace text section with octicon label, remove `title:` param, remove accent bar, fix button spacing |
| `Core/Views/Splits/FlatPaneStripContent.swift` | Remove `title:` from CollapsedPaneBar call sites |
| `Core/Views/Splits/FlatTabStripContainer.swift` | Remove `title:` from CollapsedPaneBar call sites, fix stale closure, add animation |
| `Core/Views/Splits/ArrangementPanel.swift` | Toggle label + binding fix, management mode hint |
| `Core/State/MainActor/Atoms/UIStateAtom.swift` | Remove `hideMinimizedBars` / `setHideMinimizedBars` |
| `App/Panes/TabBar/CustomTabBar.swift` | Arrangement popover arrow direction |
| `Infrastructure/AppStyle.swift` | Remove `collapsedBarAccentHeight` |
| `Core/Models/FlatTabStripMetrics.swift` | Fix divider guard: allow dividers between visible and minimized panes |
| `Core/Views/Splits/PaneManagementContext.swift` | Skip CWD row when compact path is "." |
| `Tests/AgentStudioTests/Core/Views/PaneDisplayDerivedTests.swift` | Add `accentColorHex` tests |
| `Tests/AgentStudioTests/Core/Stores/UIStateStoreTests.swift` | Remove `hideMinimizedBars` tests |
| `Tests/AgentStudioTests/Core/Models/MinimizeLayoutIntegrationTests.swift` | Add divider test for minimized-between-visible |

### Key Existing Files (reference only)
| File | Reuse |
|------|-------|
| `Core/Views/Splits/PaneManagementContext.swift:100-167` | Icon name selection logic (octicon-repo, octicon-star-fill, octicon-git-worktree, octicon-git-branch) — same icon names, but `CollapsedBarLabelPart.IconKind` is its own view-neutral enum |
| `Core/Views/Splits/ManagementPaneFooter.swift:51-58` | `OcticonImage(name:size:)` rendering pattern |
| `Core/Views/Splits/PaneManagementContext.swift:100-167` | Icon selection logic (octicon-repo, octicon-star-fill, octicon-git-worktree, octicon-git-branch) |

---

## Visual Design

### New Collapsed Bar Label (bottom-to-top, -90° rotation)

**How the rotation works:** The label is built as a normal horizontal HStack:

```
    Before rotation (the HStack as built in code):

    ⎕ agent-studio · ★ luna-356 · ⑂ luna-356-mgmt…
    ↑                ↑             ↑
    repo icon+name   wt icon+name  branch icon+name
    (semibold)       (regular)     (regular)
```

Then the entire HStack is rotated -90° (counter-clockwise). This makes it read
**bottom-to-top** like a book spine — the user tilts their head right to read it.
This is NOT stacked individual letters. It is a single horizontal line rendered sideways.

```
    The bar as the user sees it (40pt wide):

    ┌──────────┐
    │          │
    │   (◀▶)   │  expand button (24pt circle, compactButtonSize)
    │          │  spacingStandard (6pt) gap
    │   (⊞)    │  arrangement button (tab panes only, hidden for drawers)
    │          │
    │  ┃       │  ← the rotated HStack occupies this vertical space
    │  ┃       │     reading direction: bottom → top
    │  ┃       │
    │  ┃       │     the text appears as a sideways line, like a book spine
    │  ┃       │     with tiny octicon icons inline before each text part
    │  ┃       │
    │  ┃       │     SwiftUI: HStack { icon text · icon text · icon text }
    │  ┃       │              .rotationEffect(.degrees(-90))
    │  ┃       │              .fixedSize()
    │          │
    └──────────┘  no accent bar (removed)

    Implementation:
      HStack(spacing: 3) {
          OcticonImage("octicon-repo", 8pt)  Text("agent-studio", semibold)
          Text("·")
          OcticonImage("octicon-star-fill", 8pt)  Text("luna-356", regular)
          Text("·")
          OcticonImage("octicon-git-branch", 8pt)  Text("luna-356-mgmt…", regular)
      }
      .rotationEffect(.degrees(-90))  // bottom-to-top
      .fixedSize()                     // don't constrain to parent width
      .frame(maxHeight: .infinity, alignment: .center)

    Icon specs: 8pt OcticonImage, .secondary.opacity(0.72)
    Text specs: textXs (11pt), .primary.opacity(0.82)
    Separator: "·" in .tertiary
    Repo name: .semibold weight, others: .regular
    Truncation:
      Total label width = 80% of bar height (breathing room at edges)
      Icons + separators are .fixedSize() (never truncate)
      Text views share remaining space via SwiftUI flex layout
      Short texts ("vm") yield unused space to longer siblings
      When total exceeds budget: lineLimit(1) + .truncationMode(.tail)
      Long names get "…" e.g. "luna-356-manageme…"
      Single-segment fallback (cwd/terminal) gets the full budget

    Tooltip: full primaryLabel on hover (the detailed "repo | branch | folder" string)

    Fallback when no repo/worktree:
      📁 folder-name   (cwd fallback — single segment, gets full budget)
      🖥 Terminal       (terminal fallback — single segment, gets full budget)
```

### Drawer vs Tab Pane Collapsed Bar

```
    Tab pane (full):              Drawer pane (no arrangement):

    ┌──────────┐                  ┌──────────┐
    │   (◀▶)   │  expand          │   (◀▶)   │  expand only
    │   (⊞)    │  arrangement     │          │  no arrangement button
    │          │                  │          │
    │  ┃ text  │  label           │  ┃ text  │  label
    │          │                  │          │
    └──────────┘                  └──────────┘
```

### Arrangement Panel Toggle + Hint

```
    ┌─────────────────────────┐
    │ ARRANGEMENTS            │
    │ [Default]  [+]          │
    │                         │
    │ PANE VISIBILITY         │
    │ ● agent-studio  👁      │
    │ ○ docs          👁      │
    │                         │
    │ ─────────────────────── │
    │ Show minimized panes [✓]│  ← direct binding, ON = show
    │                         │
    │ Minimized panes are     │  ← hint: ONLY when toggle OFF
    │ always shown in         │     AND management mode ON
    │ management mode         │
    └─────────────────────────┘
```

### Tab Bar Popover Arrow (left side)

```
    Current:                    Fixed:
    ┌──┐                        ┌──┐
    │⊞│                        │⊞│
    └──┘                        └──┘
      ▼                            ▶
    ┌──────┐                   ◁┌──────┐
    │panel │                    │panel │
    └──────┘                    └──────┘
    arrow at top                arrow on left
    opens downward              opens rightward
```

---

## Task 1: Add CollapsedBarLabelPart and collapsedBarLabelParts(for:)

**Files:**
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneDisplayDerived.swift`
- Create: `Tests/AgentStudioTests/Core/State/CollapsedBarLabelPartsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/AgentStudioTests/Core/State/CollapsedBarLabelPartsTests.swift`:

```swift
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class CollapsedBarLabelPartsTests {

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
    func floatingPaneWithCwd_returnsFolderPart() {
        AtomScope.$override.withValue(registry) {
            // Arrange
            let cwdURL = URL(fileURLWithPath: "/Users/dev/my-project")
            let pane = store.createPane(source: .floating(launchDirectory: cwdURL, title: nil))

            // Act
            let derived = PaneDisplayDerived()
            let parts = derived.collapsedBarLabelParts(for: pane.id)

            // Assert
            #expect(parts.count == 1)
            #expect(parts[0].icon == .system("folder"))  // CollapsedBarLabelPart.IconKind
            #expect(parts[0].text == "my-project")
        }
    }

    @Test
    func floatingPaneWithoutCwd_returnsTerminalFallback() {
        AtomScope.$override.withValue(registry) {
            // Arrange
            let pane = store.createPane(source: .floating(launchDirectory: nil, title: nil))

            // Act
            let derived = PaneDisplayDerived()
            let parts = derived.collapsedBarLabelParts(for: pane.id)

            // Assert
            #expect(parts.count == 1)
            #expect(parts[0].icon == .system("terminal"))
        }
    }
}
```

Note: Worktree-backed pane tests require creating repo/worktree objects via the topology atom. Check `MinimizeLayoutIntegrationTests.swift` or `PaneManagementContextTests.swift` for the pattern. If the store helpers don't support direct repo/worktree creation, test with the cwd/terminal fallback paths first and add worktree tests once the creation pattern is confirmed.

- [ ] **Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CollapsedBarLabel" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: FAIL — `collapsedBarLabelParts` not defined

- [ ] **Step 3: Implement CollapsedBarLabelPart and collapsedBarLabelParts(for:)**

In `Sources/AgentStudio/Core/State/MainActor/Atoms/PaneDisplayDerived.swift`, add before the `PaneDisplayDerived` struct:

```swift
struct CollapsedBarLabelPart: Equatable {
    enum IconKind: Equatable {
        case octicon(String)
        case system(String)
    }
    enum TextWeight: Equatable {
        case semibold
        case regular
    }
    let icon: IconKind
    let text: String
    let weight: TextWeight
}
```

**Important:** This struct is view-neutral — no SwiftUI imports, no `PaneManagementIcon`, no `Font.Weight`. `PaneDisplayDerived` is a Foundation-layer derived helper and must not depend on view-layer types. The view (`CollapsedPaneBar`) maps `IconKind` → `OcticonImage` / `Image(systemName:)` and `TextWeight` → `Font.Weight` at render time.

Add method to `PaneDisplayDerived`, after `accentColorHex(for:)`:

```swift
func collapsedBarLabelParts(for paneId: UUID) -> [CollapsedBarLabelPart] {
    let workspacePane = atom(\.workspacePane)
    let workspaceRepositoryTopology = atom(\.workspaceRepositoryTopology)
    let repoCache = atom(\.repoCache)

    guard let pane = workspacePane.pane(paneId) else {
        return [CollapsedBarLabelPart(icon: .system("terminal"), text: "Terminal", weight: .regular)]
    }

    let parts = displayParts(for: pane)

    // Worktree-backed pane: repo + worktree + branch
    if let worktreeId = pane.worktreeId,
       let repoId = pane.repoId,
       let repo = workspaceRepositoryTopology.repo(repoId),
       let worktree = workspaceRepositoryTopology.worktree(worktreeId)
    {
        let repoName = pane.metadata.repoName ?? repo.name
        let worktreeIconName = worktree.isMainWorktree ? "octicon-star-fill" : "octicon-git-worktree"
        let branchName = resolvedBranchName(
            worktree: worktree,
            enrichment: repoCache.worktreeEnrichmentByWorktreeId[worktree.id]
        )

        return [
            CollapsedBarLabelPart(icon: .octicon("octicon-repo"), text: repoName, weight: .semibold),
            CollapsedBarLabelPart(icon: .octicon(worktreeIconName), text: worktree.path.lastPathComponent, weight: .regular),
            CollapsedBarLabelPart(icon: .octicon("octicon-git-branch"), text: branchName, weight: .regular),
        ]
    }

    // CWD fallback
    if let cwdFolder = parts.cwdFolderName {
        return [CollapsedBarLabelPart(icon: .system("folder"), text: cwdFolder, weight: .regular)]
    }

    // Terminal fallback
    let label = parts.primaryLabel.isEmpty ? "Terminal" : parts.primaryLabel
    return [CollapsedBarLabelPart(icon: .system("terminal"), text: label, weight: .regular)]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CollapsedBarLabel" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Core/State/MainActor/Atoms/PaneDisplayDerived.swift Tests/AgentStudioTests/Core/State/CollapsedBarLabelPartsTests.swift
git commit -m "feat: add collapsedBarLabelParts to PaneDisplayDerived for structured bar labels"
```

---

## Task 2: Redesign CollapsedPaneBar — text, spacing, accent bar removal, title param removal

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/CollapsedPaneBar.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`
- Modify: `Sources/AgentStudio/Infrastructure/AppStyle.swift`

- [ ] **Step 1: Remove title parameter from CollapsedPaneBar**

In `CollapsedPaneBar.swift`, remove `let title: String` (line 6), remove from init parameter list (line 24), remove `self.title = title` (line 33).

- [ ] **Step 2: Replace text section with multi-part octicon label**

Replace the current text block (lines 63-70 of the body):
```swift
Text(title)
    .font(.system(size: AppStyle.textSm, weight: .semibold))
    .foregroundStyle(.primary.opacity(0.92))
    .lineLimit(1)
    .truncationMode(.tail)
    .rotationEffect(.degrees(-90))
    .fixedSize()
    .frame(maxHeight: .infinity, alignment: .center)
```

With a new `collapsedLabel` computed property:
```swift
private func collapsedLabel(availableHeight: CGFloat) -> some View {
    let labelParts = atom(\.paneDisplay).collapsedBarLabelParts(for: paneId)
    // Use 80% of bar height as total label width (pre-rotation).
    // The remaining 20% is breathing room at top/bottom edges.
    let maxLabelWidth = availableHeight * 0.8

    return HStack(spacing: 3) {
        ForEach(Array(labelParts.enumerated()), id: \.offset) { index, part in
            if index > 0 {
                Text("·")
                    .font(.system(size: AppStyle.textXs))
                    .foregroundStyle(.tertiary)
                    .fixedSize()  // separators never truncate
            }

            Group {
                switch part.icon {
                case .octicon(let name):
                    OcticonImage(name: name, size: 8)
                case .system(let name):
                    Image(systemName: name)
                        .font(.system(size: 8, weight: .medium))
                }
            }
            .foregroundStyle(.secondary.opacity(0.72))
            .fixedSize()  // icons never truncate

            Text(part.text)
                .font(.system(size: AppStyle.textXs, weight: part.weight == .semibold ? .semibold : .regular))
                .foregroundStyle(.primary.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
                // NO fixed maxWidth per segment — SwiftUI flex layout distributes
                // space among the three texts. Short texts ("vm") yield unused
                // space to longer siblings ("luna-356-management-mode-...").
                // All three show maximum characters within the total budget.
        }
    }
    .frame(width: maxLabelWidth)  // total budget BEFORE rotation
    .rotationEffect(.degrees(-90))
    .frame(maxHeight: .infinity, alignment: .center)
}

// Layout mechanics:
// - .frame(width: maxLabelWidth) constrains the HStack's pre-rotation width
// - Icons and separators are .fixedSize() — they never compress
// - Text views share remaining space via SwiftUI's default flex layout
// - Short texts naturally yield unused space to longer texts
// - When total text exceeds budget, all three truncate with "…"
//   proportional to how much space they need (longer → more truncation)
// - Single-segment fallback (cwd/terminal) gets the full budget
```

In the body VStack, replace the old `Text(title)...` block. Wrap the label in a `GeometryReader` to get the available height:

```swift
GeometryReader { geo in
    collapsedLabel(availableHeight: geo.size.height)
}
```

Or simpler: use `frame(maxHeight: .infinity)` and read the height from the parent. The body already has `.frame(maxHeight: .infinity)` on the VStack, so `geo.size.height` gives the bar's full height minus buttons and padding.

- [ ] **Step 3: Remove accent color bar**

Remove the accent bar block from the body (lines 74-79):
```swift
// DELETE THIS:
if let accentHex, let nsColor = NSColor(hex: accentHex) {
    RoundedRectangle(cornerRadius: 1.5)
        .fill(Color(nsColor: nsColor).opacity(0.7))
        .frame(height: AppStyle.collapsedBarAccentHeight)
        .padding(.horizontal, AppStyle.spacingStandard)
}
```

Also remove the `let accentHex = paneDisplay.accentColorHex(for: paneId)` line from the body top (line 52).

- [ ] **Step 4: Fix button spacing**

Change VStack spacing from `spacingTight` to `spacingStandard`:
```swift
// FROM:
VStack(spacing: AppStyle.spacingTight) {
// TO:
VStack(spacing: AppStyle.spacingStandard) {
```

- [ ] **Step 5: Update tooltip to use primaryLabel**

The tooltip should still use the full `primaryLabel` for detailed info on hover. Keep:
```swift
.help(displayParts.primaryLabel)
```

Since we removed `accentHex` but still need `displayParts`, keep `let displayParts = paneDisplay.displayParts(for: paneId)` or simplify to just `let tooltipText = atom(\.paneDisplay).displayLabel(for: paneId)`.

- [ ] **Step 6: Remove collapsedBarAccentHeight from AppStyle**

In `Sources/AgentStudio/Infrastructure/AppStyle.swift`, remove:
```swift
/// Height of the accent color indicator at the bottom of the collapsed bar.
static let collapsedBarAccentHeight: CGFloat = 3
```

- [ ] **Step 7: Remove title: from all call sites**

In `Sources/AgentStudio/Core/Views/Splits/FlatPaneStripContent.swift`, remove `title:` parameter from both CollapsedPaneBar instantiations:
- Line ~41 (allMinimized path): remove `title: atom(\.paneDisplay).displayLabel(for: paneId),`
- Line ~120 (PaneSegmentSlotView): remove `title: atom(\.paneDisplay).displayLabel(for: segment.paneId),`

In `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`, remove `title:` from the allMinimized CollapsedPaneBar:
- Line ~78: remove `title: atom(\.paneDisplay).displayLabel(for: paneId),`

- [ ] **Step 8: Build and verify**

Run: `mise run build`
Expected: BUILD SUCCEEDED

- [ ] **Step 9: Run tests**

Run: `mise run test`
Expected: All tests pass

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: redesign collapsed bar label with octicon icons, remove accent bar, fix spacing"
```

---

## Task 3: Fix ArrangementPanel Toggle and Add Management Mode Hint

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/ArrangementPanel.swift`
- Modify: `Sources/AgentStudio/Core/State/MainActor/Atoms/UIStateAtom.swift`
- Modify: `Tests/AgentStudioTests/Core/Stores/UIStateStoreTests.swift`

- [ ] **Step 1: Change toggle label and binding in ArrangementPanel**

In `ArrangementPanel.swift`, find the toggle section (around line 78-95). Change:

```swift
// FROM:
Text("Hide minimized windows")
// TO:
Text("Show minimized panes")
```

Change the binding:
```swift
// FROM:
isOn: Binding(
    get: { atom(\.uiState).hideMinimizedBars },
    set: { atom(\.uiState).setHideMinimizedBars($0) }
)
// TO:
isOn: Binding(
    get: { atom(\.uiState).showMinimizedBars },
    set: { atom(\.uiState).setShowMinimizedBars($0) }
)
```

- [ ] **Step 2: Add management mode hint below toggle**

After the toggle HStack closing brace, add:

```swift
if !atom(\.uiState).showMinimizedBars && atom(\.managementMode).isActive {
    Text("Minimized panes are always shown in management mode")
        .font(.system(size: AppStyle.textXs))
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
}
```

- [ ] **Step 3: Remove hideMinimizedBars from UIStateAtom**

In `Sources/AgentStudio/Core/State/MainActor/Atoms/UIStateAtom.swift`, remove the computed property and setter:

```swift
// DELETE:
var hideMinimizedBars: Bool {
    !showMinimizedBars
}

// DELETE:
func setHideMinimizedBars(_ hide: Bool) {
    showMinimizedBars = !hide
}
```

- [ ] **Step 4: Remove hideMinimizedBars tests**

In `Tests/AgentStudioTests/Core/Stores/UIStateStoreTests.swift`, remove:
- `hideMinimizedBars_defaultsToFalse()` test
- `setHideMinimizedBars_updatesInverseShowValue()` test

- [ ] **Step 5: Build and run tests**

Run: `mise run build && mise run test`
Expected: BUILD SUCCEEDED, all tests pass

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "fix: change toggle to 'Show minimized panes' with management mode hint"
```

---

## Task 4: Fix Tab Bar Arrangement Popover Arrow Direction

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift`

- [ ] **Step 1: Update TabBarArrangementButton popover**

In `CustomTabBar.swift`, find `TabBarArrangementButton` (around line 406). Change the popover modifier:

```swift
// FROM:
.popover(
    isPresented: $showPanel,
    attachmentAnchor: .point(.bottomLeading),
    arrowEdge: .bottom
)
// TO:
.popover(
    isPresented: $showPanel,
    attachmentAnchor: .point(.bottomTrailing),
    arrowEdge: .leading
)
```

- [ ] **Step 2: Build and verify**

Run: `mise run build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift
git commit -m "fix: arrangement popover opens rightward with arrow on left"
```

---

## Task 5: Add Show/Hide Animation

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift`

Note: The stale closure in `onSaveArrangement` was already fixed in the first implementation pass (line 30 reads `tab` inside the closure body). Verified — no action needed.

- [ ] **Step 1: Add animation for show/hide bars**

In the body, after the GeometryReader content (before `.coordinateSpace(name: "tabContainer")`), add:

```swift
.animation(.easeOut(duration: AppStyle.animationStandard), value: atom(\.uiState).showMinimizedBars)
.animation(.easeOut(duration: AppStyle.animationStandard), value: managementMode.isActive)
```

This makes bars animate smoothly when the toggle changes or management mode toggles.

- [ ] **Step 2: Build and verify**

Run: `mise run build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/FlatTabStripContainer.swift
git commit -m "feat: add bar show/hide animation for toggle and management mode"
```

---

Note: **accentColorHex tests already exist** at `Tests/AgentStudioTests/Core/Views/PaneDisplayDerivedTests.swift:71-109` (stability and nil tests). No additional test task needed. **ArrangementDerived logging** already exists at `ArrangementDerived.swift:4-12`. No action needed.

---

## Task 6: Fix Resize Dividers Blocked by Minimized Panes  

**Files:**
- Modify: `Sources/AgentStudio/Core/Models/FlatTabStripMetrics.swift`
- Modify: `Tests/AgentStudioTests/Core/Models/MinimizeLayoutIntegrationTests.swift`

When a minimized bar sits between two visible panes, no resize divider is created. The user can't resize. The fix: create dividers when **at least one** adjacent pane is visible (not requiring **both**).

- [ ] **Step 1: Write the failing test**

Add to `MinimizeLayoutIntegrationTests.swift`:

```swift
@Test
func test_flatStripMetrics_minimizedBetweenVisible_createsDividers() {
    // Arrange: 3 panes, minimize the middle one
    let (tab, paneIds) = createTabWithPanes(3)
    store.minimizePane(paneIds[1], inTab: tab.id)

    // Act
    let updated = store.tab(tab.id)!
    let renderInfo = FlatTabStripMetrics.compute(
        layout: updated.layout,
        in: CGRect(x: 0, y: 0, width: 1200, height: 700),
        dividerThickness: AppStyle.paneGap,
        minimizedPaneIds: updated.minimizedPaneIds,
        collapsedPaneWidth: CollapsedPaneBar.barWidth
    )

    // Assert: dividers should exist between visible panes and the minimized bar
    #expect(!renderInfo.dividerSegments.isEmpty, "Dividers should exist when minimized pane sits between visible panes")
    #expect(renderInfo.dividerSegments.count == 2, "Should have divider on each side of minimized bar")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "minimizedBetweenVisible" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: FAIL — current code creates 0 dividers (both guards fail)

- [ ] **Step 3: Fix the divider guard in FlatTabStripMetrics**

In `Sources/AgentStudio/Core/Models/FlatTabStripMetrics.swift`, change the divider creation guard (lines 81-86):

```swift
// FROM: skip when EITHER is minimized
guard
    !minimizedPaneIds.contains(pane.paneId),
    !minimizedPaneIds.contains(nextPane.paneId)
else {
    continue
}

// TO: skip only when BOTH are minimized
guard
    !minimizedPaneIds.contains(pane.paneId) || !minimizedPaneIds.contains(nextPane.paneId)
else {
    continue
}
```

- [ ] **Step 4: Fix adjacentVisibleDividerCount to match**

In the same file, update `adjacentVisibleDividerCount` (lines 119-130):

```swift
// FROM:
if !minimizedPaneIds.contains(leftPaneId), !minimizedPaneIds.contains(rightPaneId) {
    count += 1
}

// TO:
if !minimizedPaneIds.contains(leftPaneId) || !minimizedPaneIds.contains(rightPaneId) {
    count += 1
}
```

This ensures the width budget accounts for the additional divider thickness.

- [ ] **Step 5: Run test to verify it passes**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "MinimizeLayout" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS — all minimize layout tests pass including the new one

Note: Verify the existing `test_flatStripMetrics_minimize_preservesVisibleDividerAccounting` test still passes. That test had 3 panes with the middle minimized and expected `dividerSegments.isEmpty`. After the fix, it should expect `dividerSegments.count == 2`. **Update this test's assertion.**

- [ ] **Step 6: Update existing test assertion**

In `MinimizeLayoutIntegrationTests.swift`, find `test_flatStripMetrics_minimize_preservesVisibleDividerAccounting` and change:

```swift
// FROM:
#expect(renderInfo.dividerSegments.isEmpty)

// TO:
#expect(renderInfo.dividerSegments.count == 2)
```

- [ ] **Step 7: Run full test suite**

Run: `mise run test`
Expected: All tests pass

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/Core/Models/FlatTabStripMetrics.swift Tests/AgentStudioTests/Core/Models/MinimizeLayoutIntegrationTests.swift
git commit -m "fix: create resize dividers between visible panes and minimized bars"
```

---

## Task 7: Fix CWD "." in ManagementPaneIdentityStrip

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/PaneManagementContext.swift`

When a pane's cwd equals the worktree root, `compactPathLabel()` returns "." — technically correct as a relative path but useless in the UI. The worktree name already shows in the row above, so the CWD "." row is redundant.

- [ ] **Step 1: Skip CWD row when compact path is "."**

In `Sources/AgentStudio/Core/Views/Splits/PaneManagementContext.swift`, find where the CWD row is added (lines 141-153 of `projectIdentityRows`):

```swift
if let targetPath {
    rows.append(
        PaneManagementIdentityRow(
            id: "cwd",
            icon: .system("folder"),
            text: compactPathLabel(
                for: targetPath,
                worktreeRoot: resolvedContext?.worktree.path
            ),
            toolTip: targetPath.path
        )
    )
}
```

Add a guard to skip when the path is ".":

```swift
if let targetPath {
    let cwdLabel = compactPathLabel(
        for: targetPath,
        worktreeRoot: resolvedContext?.worktree.path
    )
    if cwdLabel != "." {
        rows.append(
            PaneManagementIdentityRow(
                id: "cwd",
                icon: .system("folder"),
                text: cwdLabel,
                toolTip: targetPath.path
            )
        )
    }
}
```

- [ ] **Step 2: Update test if one exists for "." behavior**

Check `Tests/AgentStudioTests/Core/Views/PaneManagementContextTests.swift` for tests expecting `text == "."`. The explore found `targetPath_fallsBackToWorktreeRoot_whenCwdMissing()` at line 90. Update this test to expect the CWD row is absent (not that it shows ".").

```swift
// FROM:
#expect(context.identityRows.first(where: { $0.id == "cwd" })?.text == ".")

// TO:
#expect(context.identityRows.first(where: { $0.id == "cwd" }) == nil)
```

- [ ] **Step 3: Build and run tests**

Run: `mise run build && mise run test`
Expected: BUILD SUCCEEDED, all tests pass

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/PaneManagementContext.swift Tests/AgentStudioTests/Core/Views/PaneManagementContextTests.swift
git commit -m "fix: hide CWD row when cwd equals worktree root (was showing useless '.')"
```

---

## Task 8: Full Verification

- [ ] **Step 1: Run full lint and test**

Run: `mise run lint`
Expected: Zero errors

- [ ] **Step 2: Run full test suite**

Run: `mise run test`
Expected: All tests pass

- [ ] **Step 3: Build and launch for visual verification**

```bash
mise run build
pkill -9 -f "AgentStudio" 2>/dev/null || true
.build/debug/AgentStudio &
```

- [ ] **Step 4: Verify with Peekaboo**

```bash
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo see --app "PID:$PID" --json
```

Visual checklist:
- Collapsed bar shows octicon icons with repo/worktree/branch text, bottom-to-top
- No accent color bar at bottom
- Buttons have breathing room (6pt spacing)
- Hover shows full label in tooltip
- Expand button works
- Arrangement popover opens rightward with arrow on left
- Tab bar arrangement popover also opens rightward
- Toggle says "Show minimized panes"
- Toggle OFF in management mode shows hint text
- Bars animate in/out when toggle or management mode changes
- Drawer collapsed bars always show, no arrangement button
- Can resize visible panes when a minimized bar sits between them (drag the divider next to the bar)
- Management mode identity strip does NOT show "CWD ." when cwd equals worktree root

- [ ] **Step 5: Commit any visual fixes**

```bash
git add -A
git commit -m "fix: visual adjustments from verification"
```
