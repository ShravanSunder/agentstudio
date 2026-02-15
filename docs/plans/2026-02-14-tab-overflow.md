# Tab Overflow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add min/max tab sizing with horizontal scroll and an overflow dropdown for many-tab workflows.

**Architecture:** Tabs get min (100px) and max (220px) width constraints. When total tab width exceeds available bar space, the HStack wraps in a ScrollView with edge chevron buttons. A dropdown button appears showing all tabs as a menu. The active tab auto-scrolls into view on selection.

**Tech Stack:** SwiftUI (CustomTabBar), AppKit (DraggableTabBarHostingView)

---

## Current State

- `CustomTabBar` (SwiftUI) renders tabs in an `HStack(spacing: 4)` with `Spacer()` after the last tab
- `TabPillView` has no width constraints — grows to fit content (icon + title + badge + shortcut + close button)
- `DraggableTabBarHostingView` (AppKit NSView) hosts the SwiftUI tab bar, handles drag-to-reorder
- Tab bar height is fixed at 36px via Auto Layout constraint
- `TabBarAdapter` derives display state from `WorkspaceStore` — owns `tabs: [TabBarItem]` and transient UI state

**Key files:**
- `Sources/AgentStudio/Views/CustomTabBar.swift` — SwiftUI tab bar + TabPillView
- `Sources/AgentStudio/Views/TabBarAdapter.swift` — Observable adapter from store → tab items
- `Sources/AgentStudio/Views/DraggableTabBarHostingView.swift` — NSView host with drag support
- `Sources/AgentStudio/App/TerminalTabViewController.swift:74-113` — Tab bar creation and layout

---

## Task 1: Add min/max width constraints to TabPillView

**Files:**
- Modify: `Sources/AgentStudio/Views/CustomTabBar.swift` (TabPillView)
- Test: `swift test --filter CustomTabBar` (compile check — no unit tests for SwiftUI views)

**What to do:**

Add `.frame(minWidth: 100, maxWidth: 220)` and `.truncationMode(.tail)` to the tab pill content. The title `Text` already has `.lineLimit(1)` but needs truncation when constrained.

In `TabPillView`, change `tabContent`:

```swift
private var tabContent: some View {
    HStack(spacing: 6) {
        Image(systemName: tab.isSplit ? "square.split.2x1" : "terminal")
            .font(.system(size: 11))
            .foregroundStyle(isActive ? .primary : .secondary)

        Text(tab.displayTitle)
            .font(.system(size: 12))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(isActive ? .primary : .secondary)

        // Arrangement badge (only when custom arrangement active)
        if let arrangementName = tab.activeArrangementName {
            Text("· \(arrangementName)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }

        // Keyboard shortcut hint
        if index < 9 {
            Text("⌘\(index + 1)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }

        // Close button on hover
        if isHovering {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(2)
        }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(minWidth: 100, maxWidth: 220)  // ← ADD THIS
    .background(
        RoundedRectangle(cornerRadius: 8)
            .fill(backgroundColor)
    )
    .contentShape(RoundedRectangle(cornerRadius: 8))
    .onTapGesture(perform: onSelect)
    .onHover { hovering in
        isHovering = hovering
    }
}
```

**Verify:**
```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
```

**Commit:** `feat: add min/max width constraints to tab pills`

---

## Task 2: Wrap tab HStack in ScrollViewReader + ScrollView

**Files:**
- Modify: `Sources/AgentStudio/Views/CustomTabBar.swift` (CustomTabBar body)

**What to do:**

Replace the plain `HStack` body with a `ScrollViewReader` containing a horizontal `ScrollView`. Each `TabPillView` gets `.id(tab.id)` for programmatic scrolling. Hide scroll indicators — chevrons will replace them.

Replace `CustomTabBar.body`:

```swift
var body: some View {
    HStack(spacing: 0) {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(adapter.tabs.enumerated()), id: \.element.id) { index, tab in
                        TabPillView(
                            tab: tab,
                            index: index,
                            isActive: tab.id == adapter.activeTabId,
                            isDragging: adapter.draggingTabId == tab.id,
                            showInsertBefore: adapter.dropTargetIndex == index && adapter.draggingTabId != tab.id,
                            showInsertAfter: index == adapter.tabs.count - 1 && adapter.dropTargetIndex == adapter.tabs.count,
                            onSelect: { onSelect(tab.id) },
                            onClose: { onClose(tab.id) },
                            onCommand: { command in onCommand?(command, tab.id) }
                        )
                        .id(tab.id)
                        .background(frameReporter(for: tab.id))
                    }

                    if let onAdd = onAdd {
                        Button(action: onAdd) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 8)
            }
            .onChange(of: adapter.activeTabId) { _, newId in
                if let newId {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newId, anchor: .center)
                    }
                }
            }
        }
    }
    .frame(maxWidth: .infinity)
    .frame(height: 36)
    .background(Color.clear)
    .ignoresSafeArea()
    .coordinateSpace(name: "tabBar")
}
```

Key changes:
- `ScrollViewReader` wraps the scroll view for programmatic scroll
- `ScrollView(.horizontal, showsIndicators: false)` replaces the bare HStack
- `.id(tab.id)` on each TabPillView enables `proxy.scrollTo`
- `.onChange(of: adapter.activeTabId)` auto-scrolls to the active tab (Cmd+1-9, command bar)
- The outer `HStack(spacing: 0)` will later hold the overflow dropdown button (Task 4)

**Verify:**
```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
```

**Commit:** `feat: wrap tab bar in horizontal ScrollView with auto-scroll`

---

## Task 3: Add overflow detection to TabBarAdapter

**Files:**
- Modify: `Sources/AgentStudio/Views/TabBarAdapter.swift`

**What to do:**

Add a published `isOverflowing` property that the tab bar reads to show/hide the overflow dropdown. Also add `availableWidth` as an input (set by the tab bar's GeometryReader).

Add to `TabBarAdapter`:

```swift
// MARK: - Overflow State

/// Set by the tab bar view when it measures its available width.
@Published var availableWidth: CGFloat = 0

/// True when tabs need more space than the bar provides.
@Published private(set) var isOverflowing: Bool = false

/// Minimum tab width for overflow calculation.
private let minTabWidth: CGFloat = 100
private let tabSpacing: CGFloat = 4
private let tabBarPadding: CGFloat = 16  // 8px each side
```

Update `refresh()` to recalculate overflow:

```swift
private func refresh() {
    // ... existing tab derivation code ...

    activeTabId = store.activeTabId
    updateOverflow()
}

private func updateOverflow() {
    let tabCount = CGFloat(tabs.count)
    guard tabCount > 0 else {
        isOverflowing = false
        return
    }
    let totalMinWidth = tabCount * minTabWidth + (tabCount - 1) * tabSpacing + tabBarPadding
    isOverflowing = availableWidth > 0 && totalMinWidth > availableWidth
}
```

Also observe `availableWidth` changes:

In `observe()`, add after the existing sink:

```swift
// Recalculate overflow when available width changes
$availableWidth
    .removeDuplicates()
    .sink { [weak self] _ in
        self?.updateOverflow()
    }
    .store(in: &cancellables)
```

**Verify:**
```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
```

**Commit:** `feat: add overflow detection to TabBarAdapter`

---

## Task 4: Add overflow dropdown button

**Files:**
- Modify: `Sources/AgentStudio/Views/CustomTabBar.swift` (CustomTabBar body)

**What to do:**

Add an overflow dropdown button at the right end of the tab bar. It shows a menu listing all tabs. Only visible when `adapter.isOverflowing`. Also add a `GeometryReader` to feed `adapter.availableWidth`.

Update the `CustomTabBar.body` — after the `ScrollViewReader` closing brace, inside the outer `HStack`, add:

```swift
// Overflow dropdown (only when tabs overflow)
if adapter.isOverflowing {
    Menu {
        ForEach(Array(adapter.tabs.enumerated()), id: \.element.id) { index, tab in
            Button {
                onSelect(tab.id)
            } label: {
                HStack {
                    if tab.id == adapter.activeTabId {
                        Image(systemName: "checkmark")
                    }
                    Image(systemName: tab.isSplit ? "square.split.2x1" : "terminal")
                    Text(tab.displayTitle)
                    if index < 9 {
                        Text("⌘\(index + 1)")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    } label: {
        Image(systemName: "chevron.down")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .padding(.trailing, 4)
}
```

Also wrap the entire body in a `GeometryReader` to feed available width. The outer structure becomes:

```swift
var body: some View {
    GeometryReader { geometry in
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                // ... existing scroll view ...
            }

            // Overflow dropdown
            if adapter.isOverflowing {
                // ... dropdown menu ...
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .background(Color.clear)
        .ignoresSafeArea()
        .coordinateSpace(name: "tabBar")
        .onAppear {
            adapter.availableWidth = geometry.size.width
        }
        .onChange(of: geometry.size.width) { _, newWidth in
            adapter.availableWidth = newWidth
        }
    }
    .frame(height: 36)
}
```

Note the extra `.frame(height: 36)` on the GeometryReader so it doesn't collapse.

**Verify:**
```bash
swift build > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
```

**Commit:** `feat: add overflow dropdown button to tab bar`

---

## Task 5: Add TabBarAdapter overflow tests

**Files:**
- Modify: `Tests/AgentStudioTests/Views/TabBarAdapterTests.swift` (or create if doesn't exist)

**What to do:**

Test the overflow detection logic. Key test cases:

```swift
// Test 1: No tabs → not overflowing
func test_noTabs_notOverflowing() {
    let store = makeStore()
    let adapter = TabBarAdapter(store: store)
    adapter.availableWidth = 600
    XCTAssertFalse(adapter.isOverflowing)
}

// Test 2: Few tabs within space → not overflowing
func test_fewTabs_notOverflowing() {
    let store = makeStore()
    // Add 3 tabs
    let pane1 = store.createPane(...)
    store.appendTab(Tab(paneId: pane1.id))
    // ... add 2 more
    let adapter = TabBarAdapter(store: store)
    adapter.availableWidth = 600  // 3 tabs × 100px + spacing = 316px < 600px
    XCTAssertFalse(adapter.isOverflowing)
}

// Test 3: Many tabs exceeding space → overflowing
func test_manyTabs_overflowing() {
    let store = makeStore()
    // Add 8 tabs
    for _ in 0..<8 {
        let pane = store.createPane(...)
        store.appendTab(Tab(paneId: pane.id))
    }
    let adapter = TabBarAdapter(store: store)
    adapter.availableWidth = 600  // 8 × 100px + 7 × 4px + 16px = 844px > 600px
    XCTAssertTrue(adapter.isOverflowing)
}

// Test 4: Zero available width → not overflowing (layout not ready)
func test_zeroWidth_notOverflowing() {
    let store = makeStore()
    let pane = store.createPane(...)
    store.appendTab(Tab(paneId: pane.id))
    let adapter = TabBarAdapter(store: store)
    adapter.availableWidth = 0
    XCTAssertFalse(adapter.isOverflowing)
}
```

Use `makeStore()` factory from existing test helpers.

**Verify:**
```bash
swift test --filter TabBarAdapter > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
```

**Commit:** `test: add TabBarAdapter overflow detection tests`

---

## Task 6: Verify end-to-end and clean up

**Files:**
- All modified files from Tasks 1-5

**What to do:**

1. Run full test suite:
```bash
swift test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL: $(tail -20 /tmp/test-output.txt)"
```

2. Build release to verify no warnings:
```bash
swift build -c release > /tmp/build-output.txt 2>&1 && echo "BUILD OK" || echo "BUILD FAIL: $(tail -20 /tmp/build-output.txt)"
```

3. Verify drag-and-drop still works — the `DraggableTabBarHostingView` uses `tabFrames` from the SwiftUI coordinate space. The `ScrollView` wrapping may change the coordinate space for frame reporting. If `frameReporter` reports frames relative to the scroll content rather than the tab bar, drag hit-testing will break. Test by:
   - Checking that `tabFrames` values are reasonable (not all starting at x=0)
   - If broken, update `frameReporter` to use a coordinate space outside the ScrollView

4. If the coordinate space is broken, fix by moving `.coordinateSpace(name: "tabBar")` from the inner structure to the outer GeometryReader wrapper, and adjusting `frameReporter` to use `.global` or `.named("tabBar")` as appropriate.

**Commit:** `fix: verify tab bar drag coordination with scroll view` (if changes needed)

---

## Execution Order

```
Task 1 (min/max sizing) → Task 2 (ScrollView wrap) → Task 3 (overflow detection)
  → Task 4 (dropdown button) → Task 5 (tests) → Task 6 (integration verify)
```

## Files Summary

| Action | Files |
|--------|-------|
| **Modify** | `CustomTabBar.swift`, `TabBarAdapter.swift` |
| **May need adjustment** | `DraggableTabBarHostingView.swift` (coordinate space for drag) |
| **Test** | `TabBarAdapterTests.swift` |
| **No changes** | `TerminalTabViewController.swift` (layout constraints unchanged — height stays 36px) |
