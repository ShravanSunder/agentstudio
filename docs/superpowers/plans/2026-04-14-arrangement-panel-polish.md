# Arrangement Panel Polish — Popover Toggle, Width, Minimized Badge

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix three polish issues: popover dismiss-on-reclick race, arrangement panel width too narrow, and add a minimized pane count badge to the tab bar arrangement button.

**Architecture:** A reusable `PopoverToggleState` helper in Infrastructure handles the dismiss-race for all popovers. Uses injectable clock (`any Clock<Duration>`) per repo conventions. The arrangement panel width is widened. The badge uses an overlay (not HStack) to avoid tab strip reflow.

**Tech Stack:** Swift 6.2, SwiftUI, AtomRegistry pattern

---

## Context

The collapsed pane bar redesign is implemented. Three remaining polish issues need fixing. These are independent of each other and can be done in any order.

## Design Constraints (from review)

1. **Fix popover anchors.** Three placement rules:
   - **Tab bar button → top-left**: `attachmentAnchor: .point(.topLeading)`, `arrowEdge: .top`. Popover opens downward, arrow at top-left points at button.
   - **Collapsed bar, opens right → left-top**: `attachmentAnchor: .point(.topLeading)`, `arrowEdge: .leading`. Popover opens rightward, arrow on left side near top.
   - **Collapsed bar, opens left → right-top**: `attachmentAnchor: .point(.topTrailing)`, `arrowEdge: .trailing`. Popover opens leftward, arrow on right side near top.
   The collapsed bar's dynamic logic (lines 56-72) already uses `.topLeading`/`.topTrailing` and `.leading`/`.trailing` — this is correct, keep it. The tab bar button needs fixing from `.leading` → `.top` for arrowEdge.
2. **Replace ALL usages of `showArrangementPanel`.** Line 195 of `CollapsedPaneBar.swift` dismisses the panel before dispatching pane actions: `showArrangementPanel = false`. This must become `arrangementPopover.isPresented = false`. All 4 references (lines 24, 161, 186, 195) must be updated.
3. **PopoverToggleState uses state machine, no wall-clock timing tests.** The helper uses a 3-state model (closed, open, justDismissed) with a suppression window. Tests verify state transitions, NOT timing. No `Task.sleep` in tests. No injectable clock needed — the timing is a fire-and-forget cleanup, not a testable contract.
4. **Badge as overlay, not HStack member.** The arrangement button sits in the fixed-controls zone of the tab bar (`CustomTabBar.swift:102`). Tab widths are derived from remaining scroll area (`CustomTabBar.swift:86`). An HStack badge would change the button width, causing tabs to reflow. Use `.overlay()` instead so the button frame stays constant.

## Changes Summary

| # | What | Why |
|---|------|-----|
| 1 | Reusable `PopoverToggleState` helper with injectable clock | Popover dismiss-on-reclick race + testability |
| 2 | Wire `PopoverToggleState` into both popover sites | Replace `showArrangementPanel` / `showPanel` state vars |
| 3 | Widen arrangement panel | Current `frame(minWidth: 180, maxWidth: 260)` truncates titles |
| 4 | Minimized pane count badge (overlay) | No visual cue when panes are hidden with toggle off |

## File Structure

### New Files
| File | Responsibility |
|------|----------------|
| `Sources/AgentStudio/Infrastructure/PopoverToggleState.swift` | Reusable popover dismiss-race handler with injectable clock |
| `Tests/AgentStudioTests/Infrastructure/PopoverToggleStateTests.swift` | Unit tests for toggle and dismiss suppression |

### Modified Files
| File | Changes |
|------|---------|
| `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift` | Use `PopoverToggleState` in `TabBarArrangementButton`, add badge overlay |
| `Sources/AgentStudio/Core/Views/Splits/CollapsedPaneBar.swift` | Replace `showArrangementPanel` with `PopoverToggleState`, update ALL 4 references |
| `Sources/AgentStudio/Core/Views/Splits/ArrangementPanel.swift` | Widen frame constraints |

### Key Existing Files (reference only)
| File | Reuse |
|------|-------|
| `Sources/AgentStudio/Core/Views/Splits/PaneCloseTransitionCoordinator.swift:12-18` | Injectable clock pattern: `any Clock<Duration>`, default `ContinuousClock()` |
| `Sources/AgentStudio/Core/Views/Splits/CollapsedPaneBar.swift:56-72` | Dynamic popover anchor/arrow computation — preserve as-is |
| `Sources/AgentStudio/App/Panes/TabBar/TabBarAdapter.swift` | `TabBarItem.minimizedCount` — already tracks count per tab |

---

## Visual Design

### Popover Dismiss Behavior

```
    Current (broken):                Fixed:

    Click button → popover opens     Click button → popover opens
    Click button → popover flickers  Click button → popover closes
    (dismiss + re-show race)         (dismiss wins, no re-show)
```

### Arrangement Panel Width

```
    Current (180-260pt):              Fixed (240-340pt):

    ┌────────────────────┐            ┌──────────────────────────────┐
    │ ARRANGEMENTS       │            │ ARRANGEMENTS                 │
    │ [Default] [+]      │            │ [Default]  [Custom…]  [+]    │
    │                    │            │                              │
    │ PANE VISIBILITY    │            │ PANE VISIBILITY              │
    │ ● agent-stu… 👁   │            │ ● agent-studio | luna-356  👁│
    │ ○ docs       👁   │            │ ○ docs                     👁│
    └────────────────────┘            └──────────────────────────────┘
    titles truncated                  full titles visible
```

### Minimized Badge (overlay, not HStack)

```
    Normal (no hidden panes):     Hidden panes (toggle off):

    ┌──────┐                      ┌──────┐
    │  ⊞   │                      │  ⊞ ② │  ← overlay badge (does NOT
    └──────┘                      └──────┘     change button frame width)

    Badge shows when ALL of:
    - !showMinimizedBars (toggle is off)
    - minimizedCount > 0 (panes are minimized)
    - !managementMode.isActive (not in management mode)

    Badge is an .overlay() on the button, positioned .topTrailing.
    Button frame stays constant — no tab strip reflow.
```

---

## Task 1: Create PopoverToggleState Helper

**Files:**
- Create: `Sources/AgentStudio/Infrastructure/PopoverToggleState.swift`
- Create: `Tests/AgentStudioTests/Infrastructure/PopoverToggleStateTests.swift`

State machine:
```
         button click
  +--------------------------+
  |                          v
+--------+                +--------+
| closed | ---click-----> |  open  |
+--------+                +--------+
  ^                          |
  |                          | system dismiss (outside click / Esc / same button)
  | next click               v
  | (swallowed)        +---------------+
  +--------------------| justDismissed |
                       +---------------+
```

- [ ] **Step 1: Write the failing test**

Create `Tests/AgentStudioTests/Infrastructure/PopoverToggleStateTests.swift`:

```swift
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
final class PopoverToggleStateTests {

    @Test
    func toggle_opensWhenClosed() {
        let state = PopoverToggleState()
        #expect(!state.isPresented)

        state.toggle()
        #expect(state.isPresented)
    }

    @Test
    func toggle_closesWhenOpen() {
        let state = PopoverToggleState()
        state.toggle()  // open
        #expect(state.isPresented)

        state.toggle()  // close
        #expect(!state.isPresented)
    }

    @Test
    func systemDismiss_thenToggle_swallowed() {
        let state = PopoverToggleState()
        state.toggle()  // open
        #expect(state.isPresented)

        // Simulate system dismiss (popover binding setter)
        state.systemDidDismiss()
        #expect(!state.isPresented)

        // Immediate toggle should be swallowed
        state.toggle()
        #expect(!state.isPresented, "First toggle after system dismiss should be swallowed")

        // Next toggle should work normally
        state.toggle()
        #expect(state.isPresented, "Second toggle should open normally")
    }

    @Test
    func userToggleClose_thenToggle_notSwallowed() {
        let state = PopoverToggleState()
        state.toggle()  // open
        state.toggle()  // user closes via toggle (not system dismiss)
        #expect(!state.isPresented)

        // Should open immediately — no suppression for user-initiated close
        state.toggle()
        #expect(state.isPresented)
    }
}
```

No timing tests. No wall-clock assertions. Pure state transitions.

- [ ] **Step 2: Run test to verify it fails**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PopoverToggleState" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: FAIL — `PopoverToggleState` not defined

- [ ] **Step 3: Implement PopoverToggleState**

Create `Sources/AgentStudio/Infrastructure/PopoverToggleState.swift`:

```swift
import Foundation
import Observation
import SwiftUI

/// Handles the macOS popover dismiss-on-reclick race condition.
///
/// State machine:
/// - `closed`: popover not showing. Button click → `open`.
/// - `open`: popover showing. System dismiss → `justDismissed`. User toggle → `closed`.
/// - `justDismissed`: system just dismissed the popover. Next button click is swallowed → `closed`.
///   After the swallow (or after a cleanup timeout), returns to `closed`.
///
/// Usage:
/// ```swift
/// @State private var popover = PopoverToggleState()
///
/// Button { popover.toggle() } label: { ... }
/// .popover(isPresented: popover.binding) { ... }
/// ```
@MainActor
@Observable
final class PopoverToggleState {
    private enum State {
        case closed
        case open
        case justDismissed
    }

    private var state: State = .closed

    var isPresented: Bool {
        get { state == .open }
        set {
            if newValue {
                state = .open
            } else if state == .open {
                // Direct set to false (not from systemDidDismiss) — treat as user close
                state = .closed
            }
        }
    }

    /// Called by the button action.
    func toggle() {
        switch state {
        case .closed:
            state = .open
        case .open:
            state = .closed
        case .justDismissed:
            // Swallow this click — the system dismiss just happened
            state = .closed
        }
    }

    /// Called when the popover is dismissed by the system (outside click, Esc,
    /// or same-button click where the system fires dismiss before button action).
    func systemDidDismiss() {
        state = .justDismissed
        // Safety: clear the justDismissed state after a short window
        // in case no button action follows (e.g., user clicked elsewhere).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            if state == .justDismissed {
                state = .closed
            }
        }
    }

    /// Binding for `.popover(isPresented:)`.
    var binding: Binding<Bool> {
        Binding(
            get: { self.isPresented },
            set: { newValue in
                if !newValue && self.state == .open {
                    self.systemDidDismiss()
                } else if newValue {
                    self.state = .open
                }
            }
        )
    }
}
```

- [ ] **Step 4: Run tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "PopoverToggleState" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Infrastructure/PopoverToggleState.swift Tests/AgentStudioTests/Infrastructure/PopoverToggleStateTests.swift
git commit -m "feat: add PopoverToggleState with 3-state machine for popover dismiss race"
```

---

## Task 2: Wire PopoverToggleState into Both Popover Sites

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift`
- Modify: `Sources/AgentStudio/Core/Views/Splits/CollapsedPaneBar.swift`

### CollapsedPaneBar — replace ALL 4 references to showArrangementPanel AND fix anchors

Current state (4 references):
- Line 24: `@State private var showArrangementPanel = false`
- Line 161: `showArrangementPanel.toggle()`
- Line 186: `isPresented: $showArrangementPanel,`
- Line 195: `showArrangementPanel = false` (dismiss before pane action dispatch)

Current anchor logic (lines 56-72) uses `.topLeading`/`.topTrailing` corner anchors. Fix to use `.trailing`/`.leading` edge midpoints for more predictable placement.

- [ ] **Step 1: Update CollapsedPaneBar state**

Replace line 24:
```swift
// FROM:
@State private var showArrangementPanel = false
// TO:
@State private var arrangementPopover = PopoverToggleState()
```

Replace line 161 (button action):
```swift
// FROM:
showArrangementPanel.toggle()
// TO:
arrangementPopover.toggle()
```

- [ ] **Step 2: Verify CollapsedPaneBar anchor logic is correct**

The existing anchor logic (lines 56-72) already implements the correct placement:
- Left half of screen → `attachmentAnchor: .point(.topLeading)`, `arrowEdge: .leading` (left-top: popover opens right, arrow on left side near top)
- Right half of screen → `attachmentAnchor: .point(.topTrailing)`, `arrowEdge: .trailing` (right-top: popover opens left, arrow on right side near top)

**Do NOT change these.** They are already correct. Just verify they match after the PopoverToggleState swap.

- [ ] **Step 3: Update CollapsedPaneBar popover binding**

Replace line 186:
```swift
// FROM:
.popover(
    isPresented: $showArrangementPanel,
    attachmentAnchor: arrangementPopoverAnchor,
    arrowEdge: arrangementPopoverArrowEdge
)
// TO:
.popover(
    isPresented: arrangementPopover.binding,
    attachmentAnchor: arrangementPopoverAnchor,
    arrowEdge: arrangementPopoverArrowEdge
)
```

- [ ] **Step 4: Update CollapsedPaneBar dismiss-before-dispatch**

Replace line 195:
```swift
// FROM:
onPaneAction: { action in
    showArrangementPanel = false
    actionDispatcher.dispatch(action)
},
// TO:
onPaneAction: { action in
    arrangementPopover.isPresented = false
    actionDispatcher.dispatch(action)
},
```

- [ ] **Step 5: Update TabBarArrangementButton**

In `CustomTabBar.swift`, find `TabBarArrangementButton` (around line 406).

Replace `@State private var showPanel = false`:
```swift
@State private var popoverState = PopoverToggleState()
```

Update button action:
```swift
Button {
    popoverState.toggle()
} label: { ... }
```

Fix popover anchor — currently `attachmentAnchor: .point(.topLeading), arrowEdge: .leading`:
```swift
.popover(
    isPresented: popoverState.binding,
    attachmentAnchor: .point(.topLeading),
    arrowEdge: .top
)
```

Top-left placement: popover opens downward, arrow on top side near the left, pointing at the button. The tab bar button is always at the top of the screen so downward is always correct.

- [ ] **Step 3: Build and verify**

Run: `mise run build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift Sources/AgentStudio/Core/Views/Splits/CollapsedPaneBar.swift
git commit -m "fix: wire PopoverToggleState into arrangement button popovers"
```

---

## Task 3: Widen Arrangement Panel

**Files:**
- Modify: `Sources/AgentStudio/Core/Views/Splits/ArrangementPanel.swift`

- [ ] **Step 1: Update frame constraints**

In `ArrangementPanel.swift`, find the frame modifier (around line 92):

```swift
// FROM:
.frame(minWidth: 180, maxWidth: 260)
// TO:
.frame(minWidth: 240, maxWidth: 340)
```

- [ ] **Step 2: Build and verify**

Run: `mise run build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/AgentStudio/Core/Views/Splits/ArrangementPanel.swift
git commit -m "fix: widen arrangement panel to avoid title truncation"
```

---

## Task 4: Add Minimized Pane Count Badge as Overlay

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift`

The badge MUST be an `.overlay()` on the button, NOT an HStack member. The button sits in the fixed-controls zone of the tab bar. Tab widths are derived from remaining scroll area. Changing the button's frame width would cause all tabs to reflow when the badge appears/disappears.

- [ ] **Step 1: Add badge computed property to TabBarArrangementButton**

```swift
private var hiddenMinimizedCount: Int {
    guard !atom(\.uiState).showMinimizedBars else { return 0 }
    guard !atom(\.managementMode).isActive else { return 0 }
    guard let activeId = adapter.activeTabId,
          let tab = adapter.tabs.first(where: { $0.id == activeId })
    else { return 0 }
    return tab.minimizedCount
}
```

- [ ] **Step 2: Add overlay badge to the button**

On the existing button (the Circle with the rectangle.3.group icon), add an overlay:

```swift
.overlay(alignment: .topTrailing) {
    if hiddenMinimizedCount > 0 {
        Text("\(hiddenMinimizedCount)")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(
                Capsule()
                    .fill(Color.white.opacity(AppStyle.fillPressed))
            )
            .offset(x: 4, y: -4)
            .transition(.opacity.combined(with: .scale))
            .animation(.easeOut(duration: AppStyle.animationFast), value: hiddenMinimizedCount)
    }
}
```

The overlay sits on top of the button without affecting its frame. The offset positions it at the top-right corner. Tab strip layout is unchanged.

- [ ] **Step 3: Build and verify**

Run: `mise run build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/App/Panes/TabBar/CustomTabBar.swift
git commit -m "feat: show minimized pane count badge as overlay on arrangement button"
```

---

## Task 5: Full Verification

- [ ] **Step 1: Run lint and tests**

Run: `mise run lint && mise run test`
Expected: Zero errors, all tests pass

- [ ] **Step 2: Build and launch**

```bash
mise run build
pkill -9 -f "AgentStudio" 2>/dev/null || true
.build/debug/AgentStudio &
```

- [ ] **Step 3: Visual verification**

```bash
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo see --app "PID:$PID" --json
```

Visual checklist:
- Open arrangement panel from tab bar button → popover opens (existing anchor/arrow preserved)
- Click the same button again → popover **closes** (not flicker re-show)
- Click again → popover opens again
- Arrangement panel is wide enough to show full pane titles without truncation
- Rename an arrangement → text field has enough room
- Open arrangement panel from collapsed bar → same dismiss behavior
- Collapsed bar popover opens on the correct side (left of center → right, right of center → left)
- Split two panes, minimize one
- Toggle "Show minimized panes" OFF → badge appears on tab bar arrangement button showing "1"
- **Tabs do NOT jump/reflow** when badge appears/disappears
- Enter management mode → badge disappears (bars visible in management mode)
- Exit management mode → badge reappears
- Expand the pane → badge disappears (no minimized panes)

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: visual adjustments from verification"
```
