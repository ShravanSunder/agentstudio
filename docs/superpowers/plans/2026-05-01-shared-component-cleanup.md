# Shared Component Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the shared interaction semantics that were trapped inside editor chooser, move PaneInbox onto the same selectable-popover behavior, and document how search fields, styles, and policies are owned so this does not drift again.

**Architecture:** Shared UI behavior lives in `SharedComponents/` as generic, atom-free primitives. Feature rows stay feature-owned. `EditorChooser` and `PaneInbox` both compose a shared selectable popover shell/keyboard layer, while supplying their own row content and actions. Search cleanup keeps `SidebarSearchField` shared for sidebar surfaces and does not merge command-bar/webview text fields until their AppKit behaviors earn a shared primitive.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit `NSViewRepresentable`, Swift Testing, existing `AppCommand` / `AppShortcut` / `CommandSpec`, `AppStyles`, `AppPolicies`.

---

## Component Inventory And Decisions

| Component / behavior | Current owner | Decision | Reason |
|---|---|---|---|
| Sidebar rounded search field | `SharedComponents/SidebarSearchField.swift` | Keep shared | Already used by RepoExplorer and Inbox sidebar; owns sidebar search styling and simple search-field key hooks. |
| Command bar search field | `Features/CommandBar/Views/CommandBarSearchField.swift` + `CommandBarTextField.swift` | Keep feature-owned in this pass | It owns command-bar scope pill/icon, prefix parsing, modified Enter behavior, and command-specific shortcuts. Do not merge with sidebar search. |
| Webview select-all text field | `Features/Webview/Views/SelectAllTextField.swift` | Keep feature-owned in this pass | Used within Webview; no cross-feature second use yet. |
| Editor chooser popover keyboard bridge | private inside `SharedComponents/EditorChooser/EditorChooserPopover.swift` | Extract shared | PaneInbox needs the same popover focus capture, same-shortcut dismiss, Escape, arrows, Return, and local monitor behavior. |
| Editor chooser keyboard router | `SharedComponents/EditorChooser/EditorChooserKeyboardRouter.swift` | Extract generic base, keep editor adapter | Generic selection/dismiss behavior is reusable; editor-specific bookmark and digit shortcut behavior stays editor-owned or opt-in. |
| Editor chooser menu row content | `SharedComponents/EditorChooser/EditorChooserMenuContent.swift` | Keep editor-specific | Editor rows have editor icons, bookmark controls, and direct-launch hints. PaneInbox should not pretend notifications are editor choices. |
| Pane inbox popover | `Features/InboxNotification/Views/PaneInboxNotificationPopover.swift` | Refactor to use shared selectable popover | PaneInbox is pane-scoped notification UI; it needs the same selectable popover semantics as editor chooser. |
| Pane inbox presenter | `Features/InboxNotification/Views/PaneInboxNotificationPresenter.swift` | Add toggle semantics | Same command shortcut should close the existing popover for the same pane target. |
| Pane inbox naming | mixed `PaneInbox...` with UI text previously drifting toward drawer terminology | Standardize on PaneInbox | The icon lives in pane drawer chrome, but the semantic surface is current pane + drawer child panes. Never call it DrawerInbox. |
| Toolbar icon buttons/dividers | `Core/Views/Drawer/DrawerIconBar.swift` | Do not extract in this plan | Drawer icon bar is host chrome; after PaneInbox behavior is fixed, a later pass can extract shared toolbar button styling if there is a second host surface. |
| Shortcut badges / numbered badges | `CommandBarShortcutBadge`, editor chooser badge code | Do not extract in this plan | Similar visual tokens but different semantics. Revisit after selectable popover lands and visual drift is inspected. |

---

## File Structure

Create:

- `Sources/AgentStudio/SharedComponents/SelectablePopover/SelectablePopoverKeyboardAction.swift`
  - Generic keyboard action enum for selectable popovers.
- `Sources/AgentStudio/SharedComponents/SelectablePopover/SelectablePopoverKeyboardItem.swift`
  - Generic item descriptor used by keyboard routing.
- `Sources/AgentStudio/SharedComponents/SelectablePopover/SelectablePopoverKeyboardRouter.swift`
  - Pure AppKit key-event to action mapping.
- `Sources/AgentStudio/SharedComponents/SelectablePopover/SelectablePopoverKeyboardBridge.swift`
  - AppKit focus-capturing bridge used by SwiftUI popovers.
- `Tests/AgentStudioTests/SharedComponents/SelectablePopover/SelectablePopoverKeyboardRouterTests.swift`
  - Generic router tests copied from editor chooser behavior.
- `Tests/AgentStudioTests/SharedComponents/SelectablePopover/SelectablePopoverKeyboardBridgeTests.swift`
  - Lightweight tests for default selection helpers and no-feature coupling where practical.

Modify:

- `Sources/AgentStudio/SharedComponents/EditorChooser/EditorChooserKeyboardRouter.swift`
  - Convert to thin editor-specific adapter over shared router or remove once callers move.
- `Sources/AgentStudio/SharedComponents/EditorChooser/EditorChooserPopover.swift`
  - Replace private `EditorChooserKeyboardBridge` with shared `SelectablePopoverKeyboardBridge`.
- `Tests/AgentStudioTests/SharedComponents/EditorChooser/EditorChooserKeyboardRouterTests.swift`
  - Keep editor-specific bookmark/digit tests; move generic arrow/Escape/Return tests to shared router tests.
- `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
  - Add selected notification state and shared keyboard bridge.
- `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPresenter.swift`
  - Add same-target toggle semantics.
- `Sources/AgentStudio/Core/Views/Drawer/PaneInboxPresentation.swift`
  - Add `toggle` if needed, or change `open` to call presenter toggle through the composition layer.
- `Sources/AgentStudio/App/Windows/MainSplitViewController.swift`
  - Wire PaneInbox popover with command-shortcut dismiss matcher.
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
  - Route `.showPaneInboxNotifications` through PaneInbox toggle, not open-only.
- `Sources/AgentStudio/Infrastructure/AppStyles.swift`
  - Add `AppStyles.Components.SelectablePopover` and `AppStyles.Components.PaneInbox` tokens where needed.
- `docs/architecture/directory_structure.md`
  - Add shared interaction semantics rule.
- `docs/guides/style_guide.md`
  - Add search/popover shared-component guidance.
- `AGENTS.md`
  - Add progressive-disclosure rule: SharedComponents owns reusable behavior, AppStyles owns visuals, AppPolicies owns behavioral constants.

Tests to add/modify:

- `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPresenterTests.swift`
- `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`
- `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
- `Tests/AgentStudioTests/App/DrawerEditorChooserFactoryTests.swift`
- `Tests/AgentStudioTests/Core/Views/Drawer/PaneInboxPresentationTests.swift`

---

## Task 1: Extract Generic Selectable Popover Keyboard Router

**Files:**
- Create: `Sources/AgentStudio/SharedComponents/SelectablePopover/SelectablePopoverKeyboardAction.swift`
- Create: `Sources/AgentStudio/SharedComponents/SelectablePopover/SelectablePopoverKeyboardItem.swift`
- Create: `Sources/AgentStudio/SharedComponents/SelectablePopover/SelectablePopoverKeyboardRouter.swift`
- Create: `Tests/AgentStudioTests/SharedComponents/SelectablePopover/SelectablePopoverKeyboardRouterTests.swift`

- [ ] **Step 1: Write the failing shared router tests**

Create `Tests/AgentStudioTests/SharedComponents/SelectablePopover/SelectablePopoverKeyboardRouterTests.swift`:

```swift
import AppKit
import Testing

@testable import AgentStudio

@Suite(.serialized)
struct SelectablePopoverKeyboardRouterTests {
    private let items = [
        SelectablePopoverKeyboardItem(id: "first", shortcutNumber: 1, supportsAuxiliaryAction: true),
        SelectablePopoverKeyboardItem(id: "second", shortcutNumber: 2, supportsAuxiliaryAction: true),
        SelectablePopoverKeyboardItem(id: "third", shortcutNumber: 3, supportsAuxiliaryAction: false),
    ]

    @Test
    func escape_dismissesPopover() {
        guard
            let event = makeKeyEvent(
                characters: "\u{1b}",
                charactersIgnoringModifiers: "\u{1b}",
                keyCode: 53
            )
        else {
            Issue.record("Expected synthetic key event")
            return
        }

        let action = SelectablePopoverKeyboardRouter.action(
            for: event,
            items: items,
            selectedItemId: "first",
            matchesAdditionalDismissShortcut: { _ in false }
        )

        #expect(action == .dismiss)
    }

    @Test
    func additionalDismissShortcut_dismissesPopover() {
        guard
            let event = makeKeyEvent(
                modifierFlags: [.command, .shift],
                characters: "i",
                charactersIgnoringModifiers: "i",
                keyCode: 34
            )
        else {
            Issue.record("Expected synthetic key event")
            return
        }

        let action = SelectablePopoverKeyboardRouter.action(
            for: event,
            items: items,
            selectedItemId: "first",
            matchesAdditionalDismissShortcut: { event in
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                return event.keyCode == 34 && flags.contains(.command) && flags.contains(.shift)
            }
        )

        #expect(action == .dismiss)
    }

    @Test
    func return_selectsCurrentItem() {
        guard let event = makeKeyEvent(keyCode: 36) else {
            Issue.record("Expected synthetic key event")
            return
        }

        let action = SelectablePopoverKeyboardRouter.action(
            for: event,
            items: items,
            selectedItemId: "second",
            matchesAdditionalDismissShortcut: { _ in false }
        )

        #expect(action == .select("second"))
    }

    @Test
    func downArrow_highlightsNextItem() {
        guard let event = makeKeyEvent(keyCode: 125) else {
            Issue.record("Expected synthetic key event")
            return
        }

        let action = SelectablePopoverKeyboardRouter.action(
            for: event,
            items: items,
            selectedItemId: "first",
            matchesAdditionalDismissShortcut: { _ in false }
        )

        #expect(action == .highlight("second"))
    }

    @Test
    func upArrow_highlightsPreviousItem() {
        guard let event = makeKeyEvent(keyCode: 126) else {
            Issue.record("Expected synthetic key event")
            return
        }

        let action = SelectablePopoverKeyboardRouter.action(
            for: event,
            items: items,
            selectedItemId: "second",
            matchesAdditionalDismissShortcut: { _ in false }
        )

        #expect(action == .highlight("first"))
    }

    @Test
    func shortcutNumber_selectsMatchingItem() {
        guard
            let event = makeKeyEvent(
                characters: "2",
                charactersIgnoringModifiers: "2",
                keyCode: 19
            )
        else {
            Issue.record("Expected synthetic key event")
            return
        }

        let action = SelectablePopoverKeyboardRouter.action(
            for: event,
            items: items,
            selectedItemId: "first",
            matchesAdditionalDismissShortcut: { _ in false }
        )

        #expect(action == .select("second"))
    }

    @Test
    func auxiliaryKey_returnsAuxiliaryActionForCurrentItem() {
        guard
            let event = makeKeyEvent(
                characters: "b",
                charactersIgnoringModifiers: "b",
                keyCode: 11
            )
        else {
            Issue.record("Expected synthetic key event")
            return
        }

        let action = SelectablePopoverKeyboardRouter.action(
            for: event,
            items: items,
            selectedItemId: "second",
            auxiliaryKey: "b",
            matchesAdditionalDismissShortcut: { _ in false }
        )

        #expect(action == .auxiliary("second"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "SelectablePopoverKeyboardRouterTests"
```

Expected: FAIL because `SelectablePopoverKeyboardItem` and `SelectablePopoverKeyboardRouter` do not exist.

- [ ] **Step 3: Create keyboard action and item types**

Create `Sources/AgentStudio/SharedComponents/SelectablePopover/SelectablePopoverKeyboardAction.swift`:

```swift
import Foundation

enum SelectablePopoverKeyboardAction<ItemID: Equatable>: Equatable {
    case dismiss
    case select(ItemID)
    case auxiliary(ItemID)
    case highlight(ItemID)
    case consume
    case passthrough
}
```

Create `Sources/AgentStudio/SharedComponents/SelectablePopover/SelectablePopoverKeyboardItem.swift`:

```swift
import Foundation

struct SelectablePopoverKeyboardItem<ItemID: Hashable>: Identifiable, Equatable {
    let id: ItemID
    let shortcutNumber: Int?
    let supportsAuxiliaryAction: Bool

    init(
        id: ItemID,
        shortcutNumber: Int? = nil,
        supportsAuxiliaryAction: Bool = false
    ) {
        self.id = id
        self.shortcutNumber = shortcutNumber
        self.supportsAuxiliaryAction = supportsAuxiliaryAction
    }
}
```

- [ ] **Step 4: Implement router**

Create `Sources/AgentStudio/SharedComponents/SelectablePopover/SelectablePopoverKeyboardRouter.swift`:

```swift
import AppKit

enum SelectablePopoverKeyboardRouter {
    static func action<ItemID: Hashable>(
        for event: NSEvent,
        items: [SelectablePopoverKeyboardItem<ItemID>],
        selectedItemId: ItemID?,
        auxiliaryKey: String? = nil,
        matchesAdditionalDismissShortcut: (NSEvent) -> Bool
    ) -> SelectablePopoverKeyboardAction<ItemID> {
        guard event.type == .keyDown else { return .passthrough }

        if event.keyCode == 53 || matchesAdditionalDismissShortcut(event) {
            return .dismiss
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasModifiers = !modifiers.isDisjoint(with: [.command, .control, .option, .function, .shift])
        guard !hasModifiers else { return .passthrough }

        switch event.keyCode {
        case 36, 76:
            guard let itemId = currentSelection(items: items, selectedItemId: selectedItemId) else {
                return .consume
            }
            return .select(itemId)
        case 125:
            guard let itemId = movedSelection(delta: 1, items: items, selectedItemId: selectedItemId) else {
                return .consume
            }
            return .highlight(itemId)
        case 126:
            guard let itemId = movedSelection(delta: -1, items: items, selectedItemId: selectedItemId) else {
                return .consume
            }
            return .highlight(itemId)
        default:
            break
        }

        if let auxiliaryKey,
            event.charactersIgnoringModifiers?.lowercased() == auxiliaryKey.lowercased()
        {
            guard
                let itemId = currentSelection(items: items, selectedItemId: selectedItemId),
                items.first(where: { $0.id == itemId })?.supportsAuxiliaryAction == true
            else {
                return .consume
            }
            return .auxiliary(itemId)
        }

        if let characters = event.charactersIgnoringModifiers,
            characters.count == 1,
            let shortcutNumber = Int(characters)
        {
            guard let itemId = items.first(where: { $0.shortcutNumber == shortcutNumber })?.id else {
                return .consume
            }
            return .select(itemId)
        }

        return .passthrough
    }

    static func defaultSelection<ItemID: Hashable>(
        items: [SelectablePopoverKeyboardItem<ItemID>],
        preferredItemId: ItemID?
    ) -> ItemID? {
        if let preferredItemId, items.contains(where: { $0.id == preferredItemId }) {
            return preferredItemId
        }
        return items.first?.id
    }

    static func currentSelection<ItemID: Hashable>(
        items: [SelectablePopoverKeyboardItem<ItemID>],
        selectedItemId: ItemID?
    ) -> ItemID? {
        if let selectedItemId, items.contains(where: { $0.id == selectedItemId }) {
            return selectedItemId
        }
        return items.first?.id
    }

    static func movedSelection<ItemID: Hashable>(
        delta: Int,
        items: [SelectablePopoverKeyboardItem<ItemID>],
        selectedItemId: ItemID?
    ) -> ItemID? {
        guard !items.isEmpty else { return nil }

        let currentIndex = items.firstIndex { $0.id == selectedItemId } ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), items.count - 1)
        return items[nextIndex].id
    }
}
```

- [ ] **Step 5: Run tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "SelectablePopoverKeyboardRouterTests"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/SharedComponents/SelectablePopover Tests/AgentStudioTests/SharedComponents/SelectablePopover
git commit -m "refactor(ui): add selectable popover keyboard router"
```

---

## Task 2: Extract Generic Selectable Popover Keyboard Bridge

**Files:**
- Create: `Sources/AgentStudio/SharedComponents/SelectablePopover/SelectablePopoverKeyboardBridge.swift`
- Modify: `Sources/AgentStudio/SharedComponents/EditorChooser/EditorChooserPopover.swift`
- Test: `Tests/AgentStudioTests/SharedComponents/EditorChooser/EditorChooserKeyboardRouterTests.swift`

- [ ] **Step 1: Create shared bridge**

Create `Sources/AgentStudio/SharedComponents/SelectablePopover/SelectablePopoverKeyboardBridge.swift`:

```swift
import AppKit
import SwiftUI

struct SelectablePopoverKeyboardBridge<ItemID: Hashable>: NSViewRepresentable {
    let items: [SelectablePopoverKeyboardItem<ItemID>]
    let selectedItemId: ItemID?
    let auxiliaryKey: String?
    let onSelect: (ItemID) -> Void
    let onAuxiliary: (ItemID) -> Void
    let onHighlight: (ItemID) -> Void
    let onDismiss: () -> Void
    let matchesAdditionalDismissShortcut: (NSEvent) -> Bool

    func makeNSView(context _: Context) -> SelectablePopoverFocusCapturingView<ItemID> {
        let view = SelectablePopoverFocusCapturingView<ItemID>()
        update(view)
        return view
    }

    func updateNSView(_ nsView: SelectablePopoverFocusCapturingView<ItemID>, context _: Context) {
        update(nsView)
        Task { @MainActor in
            guard nsView.window?.firstResponder !== nsView else { return }
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    private func update(_ view: SelectablePopoverFocusCapturingView<ItemID>) {
        view.items = items
        view.selectedItemId = selectedItemId
        view.auxiliaryKey = auxiliaryKey
        view.onSelect = onSelect
        view.onAuxiliary = onAuxiliary
        view.onHighlight = onHighlight
        view.onDismiss = onDismiss
        view.matchesAdditionalDismissShortcut = matchesAdditionalDismissShortcut
    }
}

final class SelectablePopoverFocusCapturingView<ItemID: Hashable>: NSView {
    var items: [SelectablePopoverKeyboardItem<ItemID>] = []
    var selectedItemId: ItemID?
    var auxiliaryKey: String?
    var onSelect: ((ItemID) -> Void)?
    var onAuxiliary: ((ItemID) -> Void)?
    var onHighlight: ((ItemID) -> Void)?
    var onDismiss: (() -> Void)?
    var matchesAdditionalDismissShortcut: ((NSEvent) -> Bool)?
    private var localMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            teardownMonitor()
            return
        }

        installMonitorIfNeeded()
    }

    override func keyDown(with event: NSEvent) {
        guard apply(event) else {
            super.keyDown(with: event)
            return
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if apply(event) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        _ = sender
        onDismiss?()
    }

    override func moveUp(_ sender: Any?) {
        _ = sender
        highlightSelection(delta: -1)
    }

    override func moveDown(_ sender: Any?) {
        _ = sender
        highlightSelection(delta: 1)
    }

    override func insertNewline(_ sender: Any?) {
        _ = sender
        activateCurrentSelection()
    }

    private func apply(_ event: NSEvent) -> Bool {
        switch SelectablePopoverKeyboardRouter.action(
            for: event,
            items: items,
            selectedItemId: selectedItemId,
            auxiliaryKey: auxiliaryKey,
            matchesAdditionalDismissShortcut: matchesAdditionalDismissShortcut ?? { _ in false }
        ) {
        case .dismiss:
            onDismiss?()
        case .select(let itemId):
            onSelect?(itemId)
        case .auxiliary(let itemId):
            onAuxiliary?(itemId)
        case .highlight(let itemId):
            onHighlight?(itemId)
        case .consume:
            return true
        case .passthrough:
            return false
        }

        return true
    }

    private func installMonitorIfNeeded() {
        guard localMonitor == nil else { return }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.eventBelongsToThisPopover(event) else { return event }
            return self.apply(event) ? nil : event
        }
    }

    private func teardownMonitor() {
        guard let localMonitor else { return }
        NSEvent.removeMonitor(localMonitor)
        self.localMonitor = nil
    }

    private func eventBelongsToThisPopover(_ event: NSEvent) -> Bool {
        guard let popoverWindow = window else { return false }

        if let eventWindow = event.window {
            return eventWindow == popoverWindow
                || eventWindow.parent == popoverWindow
                || popoverWindow.parent == eventWindow
        }

        if event.windowNumber != 0 {
            return event.windowNumber == popoverWindow.windowNumber
        }

        if let keyWindow = NSApp.keyWindow {
            return keyWindow == popoverWindow
                || keyWindow.parent == popoverWindow
                || popoverWindow.parent == keyWindow
        }

        return false
    }

    private func highlightSelection(delta: Int) {
        guard
            let itemId = SelectablePopoverKeyboardRouter.movedSelection(
                delta: delta,
                items: items,
                selectedItemId: selectedItemId
            )
        else {
            return
        }

        onHighlight?(itemId)
    }

    private func activateCurrentSelection() {
        guard
            let itemId = SelectablePopoverKeyboardRouter.currentSelection(
                items: items,
                selectedItemId: selectedItemId
            )
        else {
            return
        }

        onSelect?(itemId)
    }
}
```

- [ ] **Step 2: Rewire `EditorChooserPopover` to use shared bridge**

In `Sources/AgentStudio/SharedComponents/EditorChooser/EditorChooserPopover.swift`, replace the `.background(EditorChooserKeyboardBridge(...))` block with:

```swift
.background(
    SelectablePopoverKeyboardBridge(
        items: keyboardItems,
        selectedItemId: selectedEditorId,
        auxiliaryKey: "b",
        onSelect: { editorId in
            selectedEditorId = editorId
            onSelect(editorId)
        },
        onAuxiliary: { editorId in
            selectedEditorId = editorId
            onToggleBookmark(editorId)
        },
        onHighlight: { editorId in
            selectedEditorId = editorId
        },
        onDismiss: onDismiss,
        matchesAdditionalDismissShortcut: matchesAdditionalDismissShortcut
    )
    .frame(width: 0, height: 0)
)
```

Add this property near `itemIDs`:

```swift
private var keyboardItems: [SelectablePopoverKeyboardItem<EditorTargetId>] {
    items.map {
        SelectablePopoverKeyboardItem(
            id: $0.id,
            shortcutNumber: $0.shortcutNumber,
            supportsAuxiliaryAction: true
        )
    }
}
```

Change `repairSelection()` to:

```swift
private func repairSelection() {
    if let selectedEditorId, itemIDs.contains(selectedEditorId) {
        return
    }
    selectedEditorId = SelectablePopoverKeyboardRouter.defaultSelection(
        items: keyboardItems,
        preferredItemId: bookmarkedEditorId
    )
}
```

Delete the private `EditorChooserKeyboardBridge` and `FocusCapturingView` types from `EditorChooserPopover.swift`.

- [ ] **Step 3: Keep editor adapter only if tests still need it**

If `EditorChooserKeyboardRouterTests` still test editor-specific behavior, rewrite `EditorChooserKeyboardRouter.action(...)` as an adapter:

```swift
enum EditorChooserKeyboardRouter {
    static func action(
        for event: NSEvent,
        items: [EditorChoiceItem],
        selectedEditorId: EditorTargetId?,
        matchesAdditionalDismissShortcut: (NSEvent) -> Bool
    ) -> EditorChooserKeyboardAction {
        let keyboardItems = items.map {
            SelectablePopoverKeyboardItem(
                id: $0.id,
                shortcutNumber: $0.shortcutNumber,
                supportsAuxiliaryAction: true
            )
        }

        switch SelectablePopoverKeyboardRouter.action(
            for: event,
            items: keyboardItems,
            selectedItemId: selectedEditorId,
            auxiliaryKey: "b",
            matchesAdditionalDismissShortcut: matchesAdditionalDismissShortcut
        ) {
        case .dismiss:
            return .dismiss
        case .select(let editorId):
            return .select(editorId)
        case .auxiliary(let editorId):
            return .toggleBookmark(editorId)
        case .highlight(let editorId):
            return .highlight(editorId)
        case .consume:
            return .consume
        case .passthrough:
            return .passthrough
        }
    }

    static func defaultSelection(
        items: [EditorChoiceItem],
        bookmarkedEditorId: EditorTargetId?
    ) -> EditorTargetId? {
        let keyboardItems = items.map {
            SelectablePopoverKeyboardItem(
                id: $0.id,
                shortcutNumber: $0.shortcutNumber,
                supportsAuxiliaryAction: true
            )
        }
        return SelectablePopoverKeyboardRouter.defaultSelection(
            items: keyboardItems,
            preferredItemId: bookmarkedEditorId
        )
    }

    static func currentSelectionForTesting(
        items: [EditorChoiceItem],
        selectedEditorId: EditorTargetId?
    ) -> EditorTargetId? {
        let keyboardItems = items.map {
            SelectablePopoverKeyboardItem(
                id: $0.id,
                shortcutNumber: $0.shortcutNumber,
                supportsAuxiliaryAction: true
            )
        }
        return SelectablePopoverKeyboardRouter.currentSelection(
            items: keyboardItems,
            selectedItemId: selectedEditorId
        )
    }

    static func movedSelectionForTesting(
        delta: Int,
        items: [EditorChoiceItem],
        selectedEditorId: EditorTargetId?
    ) -> EditorTargetId? {
        let keyboardItems = items.map {
            SelectablePopoverKeyboardItem(
                id: $0.id,
                shortcutNumber: $0.shortcutNumber,
                supportsAuxiliaryAction: true
            )
        }
        return SelectablePopoverKeyboardRouter.movedSelection(
            delta: delta,
            items: keyboardItems,
            selectedItemId: selectedEditorId
        )
    }
}
```

- [ ] **Step 4: Run editor chooser tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "EditorChooserKeyboardRouterTests|DrawerEditorChooserFactoryTests"
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/SharedComponents/SelectablePopover Sources/AgentStudio/SharedComponents/EditorChooser Tests/AgentStudioTests/SharedComponents Tests/AgentStudioTests/App/DrawerEditorChooserFactoryTests.swift
git commit -m "refactor(ui): share selectable popover key handling"
```

---

## Task 3: Move PaneInbox Onto Shared Selectable Popover Semantics

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
- Modify: `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`

- [ ] **Step 1: Add failing PaneInbox keyboard selection test**

In `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift`, add:

```swift
@Test("keyboardItems maps relevant notifications to selectable popover items")
func keyboardItemsForRelevantNotifications() {
    let paneId = UUID()
    let first = Self.notification(id: UUID(), paneId: paneId, title: "First")
    let second = Self.notification(id: UUID(), paneId: paneId, title: "Second")

    let keyboardItems = PaneInboxNotificationPopover.keyboardItems(
        for: [first, second]
    )

    #expect(keyboardItems.map(\.id) == [first.id, second.id])
    #expect(keyboardItems.map(\.shortcutNumber) == [1, 2])
    #expect(keyboardItems.allSatisfy { !$0.supportsAuxiliaryAction })
}
```

If the local helper does not accept `id` and `title`, extend the helper:

```swift
private static func notification(
    id: UUID = UUID(),
    paneId: UUID,
    title: String = "Notification",
    isDismissedFromPaneInbox: Bool = false
) -> InboxNotification {
    InboxNotification(
        id: id,
        timestamp: Date(timeIntervalSince1970: isDismissedFromPaneInbox ? 50 : 100),
        title: title,
        body: nil,
        kind: .commandFinished,
        source: .pane(.init(paneId: paneId, tabId: nil, repoId: nil, paneName: nil, tabName: nil, repoName: nil)),
        isRead: false,
        isDismissedFromPaneInbox: isDismissedFromPaneInbox
    )
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "PaneInboxNotificationPopoverTests"
```

Expected: FAIL because `keyboardItems(for:)` does not exist.

- [ ] **Step 3: Add selectable state and keyboard bridge**

In `PaneInboxNotificationPopover`, add:

```swift
@State private var selectedNotificationId: UUID?
```

Add:

```swift
static func keyboardItems(
    for notifications: [InboxNotification]
) -> [SelectablePopoverKeyboardItem<UUID>] {
    notifications.prefix(9).enumerated().map { index, notification in
        SelectablePopoverKeyboardItem(
            id: notification.id,
            shortcutNumber: index + 1,
            supportsAuxiliaryAction: false
        )
    }
}
```

Wrap the body in the shared bridge:

```swift
var body: some View {
    VStack(spacing: 0) {
        header
        Divider()
        list
    }
    .frame(
        width: AppStyles.Components.PaneInbox.popoverWidth,
        height: AppStyles.Components.PaneInbox.popoverHeight
    )
    .background(
        SelectablePopoverKeyboardBridge(
            items: Self.keyboardItems(for: relevantNotifications),
            selectedItemId: selectedNotificationId,
            auxiliaryKey: nil,
            onSelect: { notificationId in
                selectedNotificationId = notificationId
                activate(notificationId: notificationId)
            },
            onAuxiliary: { _ in },
            onHighlight: { notificationId in
                selectedNotificationId = notificationId
            },
            onDismiss: onClose,
            matchesAdditionalDismissShortcut: { event in
                guard let trigger = ShortcutDecoder.decode(event: event) else { return false }
                return trigger == AppShortcut.showPaneInboxNotifications.trigger
            }
        )
        .frame(width: 0, height: 0)
    )
    .onAppear(perform: repairSelection)
    .onChange(of: relevantNotificationIds) { _, _ in repairSelection() }
    .onExitCommand(perform: onClose)
}
```

Add:

```swift
private var relevantNotificationIds: [UUID] {
    relevantNotifications.map(\.id)
}

private func repairSelection() {
    if let selectedNotificationId, relevantNotificationIds.contains(selectedNotificationId) {
        return
    }
    selectedNotificationId = SelectablePopoverKeyboardRouter.defaultSelection(
        items: Self.keyboardItems(for: relevantNotifications),
        preferredItemId: nil
    )
}

private func activate(notificationId: UUID) {
    guard let notification = relevantNotifications.first(where: { $0.id == notificationId }) else {
        return
    }
    activate(notification)
}
```

In the row background, show selection:

```swift
.background(
    RoundedRectangle(cornerRadius: AppStyles.Components.PaneInbox.rowCornerRadius)
        .fill(
            selectedNotificationId == notification.id
                ? Color.accentColor.opacity(AppStyles.General.Fill.active)
                : Color.clear
        )
)
```

- [ ] **Step 4: Add PaneInbox style tokens**

In `Sources/AgentStudio/Infrastructure/AppStyles.swift`, under `enum Components`, add:

```swift
enum PaneInbox {
    static let popoverWidth: CGFloat = 320
    static let popoverHeight: CGFloat = 400
    static let headerPadding: CGFloat = 12
    static let rowCornerRadius: CGFloat = AppStyles.General.CornerRadius.panel
}
```

Change `.padding(12)` to:

```swift
.padding(AppStyles.Components.PaneInbox.headerPadding)
```

- [ ] **Step 5: Run PaneInbox tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "PaneInboxNotificationPopoverTests"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift Sources/AgentStudio/Infrastructure/AppStyles.swift Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPopoverTests.swift
git commit -m "feat(inbox): use shared selectable popover semantics"
```

---

## Task 4: Add PaneInbox Toggle Semantics Through Command Spec Path

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPresenter.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/PaneInboxPresentation.swift`
- Modify: `Sources/AgentStudio/App/Windows/MainSplitViewController.swift`
- Modify: `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
- Test: `Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPresenterTests.swift`
- Test: `Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift`
- Test: `Tests/AgentStudioTests/Core/Views/Drawer/PaneInboxPresentationTests.swift`

- [ ] **Step 1: Add failing presenter toggle tests**

In `PaneInboxNotificationPresenterTests`, add:

```swift
@Test("toggle closes the same pane inbox target")
func toggleSameTargetCloses() {
    let presenter = PaneInboxNotificationPresenter()
    let parentPaneId = UUID()
    let childPaneId = UUID()

    presenter.toggle(parentPaneId: parentPaneId, paneIds: [parentPaneId, childPaneId])
    #expect(presenter.request?.parentPaneId == parentPaneId)

    presenter.toggle(parentPaneId: parentPaneId, paneIds: [parentPaneId, childPaneId])
    #expect(presenter.request == nil)
}

@Test("toggle replaces a different pane inbox target")
func toggleDifferentTargetReplaces() {
    let presenter = PaneInboxNotificationPresenter()
    let firstParentPaneId = UUID()
    let secondParentPaneId = UUID()

    presenter.toggle(parentPaneId: firstParentPaneId, paneIds: [firstParentPaneId])
    presenter.toggle(parentPaneId: secondParentPaneId, paneIds: [secondParentPaneId])

    #expect(presenter.request?.parentPaneId == secondParentPaneId)
    #expect(presenter.request?.paneIds == [secondParentPaneId])
}
```

- [ ] **Step 2: Run presenter tests to verify failure**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "PaneInboxNotificationPresenterTests"
```

Expected: FAIL because `toggle` does not exist.

- [ ] **Step 3: Implement presenter toggle**

In `PaneInboxNotificationPresenter.swift`, add:

```swift
func toggle(parentPaneId: UUID, paneIds: [UUID]) {
    let normalizedPaneIds = paneIds
    if request?.parentPaneId == parentPaneId,
        request?.paneIds == normalizedPaneIds
    {
        request = nil
        return
    }

    request = PaneInboxRequest(id: UUID(), parentPaneId: parentPaneId, paneIds: normalizedPaneIds)
}
```

Keep `open(...)` if existing call sites still need it, implemented through `toggle` only if open and toggle should share replacement logic:

```swift
func open(parentPaneId: UUID, paneIds: [UUID]) {
    request = PaneInboxRequest(id: UUID(), parentPaneId: parentPaneId, paneIds: paneIds)
}
```

- [ ] **Step 4: Add `toggle` to presentation seam**

In `PaneInboxPresentation.swift`, add a property:

```swift
let toggle: @MainActor (UUID, [UUID]) -> Void
```

In `trailingActions(...)`, change:

```swift
onOpenInbox: { open(parentPaneId, paneIds) },
```

to:

```swift
onOpenInbox: { toggle(parentPaneId, paneIds) },
```

Update every `PaneInboxPresentation(...)` initializer in tests and app code to provide `toggle`.

- [ ] **Step 5: Wire command path to toggle**

In `MainSplitViewController.makePaneInboxPresentation()`, add:

```swift
toggle: { [paneInboxPresenter] parentPaneId, paneIds in
    paneInboxPresenter.toggle(parentPaneId: parentPaneId, paneIds: paneIds)
},
```

In `PaneTabViewController.handlePaneInboxCommand`, change:

```swift
paneInboxPresentation.open(target.parentPaneId, target.paneIds)
```

to:

```swift
paneInboxPresentation.toggle(target.parentPaneId, target.paneIds)
```

- [ ] **Step 6: Add command test for toggle**

In `PaneTabViewControllerCommandTests`, add:

```swift
@Test("showPaneInboxNotifications toggles an already-open pane inbox closed")
func executeShowPaneInboxNotifications_togglesOpenPaneInboxClosed() throws {
    let harness = PaneTabViewControllerCommandHarness()
    let parentPaneId = harness.addTerminalPane()
    harness.setActivePane(parentPaneId)

    harness.controller.execute(.showPaneInboxNotifications)
    #expect(harness.paneInboxPresenter.request?.parentPaneId == parentPaneId)

    harness.controller.execute(.showPaneInboxNotifications)
    #expect(harness.paneInboxPresenter.request == nil)
}
```

Use the existing harness helpers in that file. If helper names differ, use the same setup style as `executeShowPaneInboxNotifications_withoutDrawerChildrenOpensForParentPane`.

- [ ] **Step 7: Run focused command tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "PaneInboxNotificationPresenterTests|PaneInboxPresentationTests|PaneTabViewControllerCommandTests"
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPresenter.swift Sources/AgentStudio/Core/Views/Drawer/PaneInboxPresentation.swift Sources/AgentStudio/App/Windows/MainSplitViewController.swift Sources/AgentStudio/App/Panes/PaneTabViewController.swift Tests/AgentStudioTests/Features/InboxNotification/Views/PaneInboxNotificationPresenterTests.swift Tests/AgentStudioTests/Core/Views/Drawer/PaneInboxPresentationTests.swift Tests/AgentStudioTests/App/PaneTabViewControllerCommandTests.swift
git commit -m "fix(inbox): toggle pane inbox from command path"
```

---

## Task 5: Pin PaneInbox Naming And Remove DrawerInbox Drift

**Files:**
- Modify: `Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift`
- Modify: `Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift`
- Modify: `docs/superpowers/specs/2026-04-25-luna361-notification-output-observability.md`
- Test: `Tests/AgentStudioTests/App/AppCommandTests.swift`
- Test: `Tests/AgentStudioTests/Core/Actions/UIActionPresentationTests.swift`

- [ ] **Step 1: Search for forbidden name**

Run:

```bash
rg -n "Drawer inbox|drawer inbox|DrawerInbox|drawerInbox" Sources Tests docs AGENTS.md
```

Expected before cleanup: any remaining user-visible text or type names are listed.

- [ ] **Step 2: Keep user-visible and code docs as PaneInbox**

Change user-facing popover title in `PaneInboxNotificationPopover.swift` if needed:

```swift
Text("Pane inbox")
```

Ensure tooltip text in `DrawerIconBar.swift` remains:

```swift
AppCommand.showPaneInboxNotifications.definition.controlToolTip(
    textOverride: "Open pane inbox"
)
```

Do not use “drawer inbox” except in explanatory comments that explicitly say the icon is placed in drawer chrome.

- [ ] **Step 3: Add spec note**

In `docs/superpowers/specs/2026-04-25-luna361-notification-output-observability.md`, add:

```markdown
### PaneInbox naming invariant

The pane-scoped inbox is always named PaneInbox. It includes notifications
for the active parent pane plus that pane's drawer child panes. The icon may
live in pane drawer chrome, but the product concept is not DrawerInbox.
```

- [ ] **Step 4: Run naming scan again**

Run:

```bash
rg -n "Drawer inbox|drawer inbox|DrawerInbox|drawerInbox" Sources Tests docs AGENTS.md
```

Expected: no matches, or only an intentional invariant sentence explaining the forbidden term.

- [ ] **Step 5: Run command presentation tests**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "AppCommandTests|UIActionPresentationTests|DrawerIconBarInboxSlotTests"
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/AgentStudio/Features/InboxNotification/Views/PaneInboxNotificationPopover.swift Sources/AgentStudio/Core/Views/Drawer/DrawerIconBar.swift docs/superpowers/specs/2026-04-25-luna361-notification-output-observability.md Tests/AgentStudioTests/App/AppCommandTests.swift Tests/AgentStudioTests/Core/Actions/UIActionPresentationTests.swift
git commit -m "docs(inbox): pin pane inbox naming"
```

---

## Task 6: Search Component Cleanup And Non-Extraction Guardrails

**Files:**
- Modify: `docs/architecture/directory_structure.md`
- Modify: `docs/guides/style_guide.md`
- Modify: `AGENTS.md`
- Test: no Swift tests required; run docs/search scans.

- [ ] **Step 1: Document search ownership**

In `docs/architecture/directory_structure.md`, under SharedComponents, add:

```markdown
#### Search and text input ownership

`SidebarSearchField` is the shared sidebar search control. Use it for
sidebar surfaces that need the rounded sidebar search visual treatment and
simple submit / escape / down-arrow hooks.

Do not merge `CommandBarSearchField` into `SidebarSearchField`. Command bar
search owns scope pills, prefix parsing, modified Enter behavior, and command
shortcut interception. Extract only the AppKit text-input bridge if another
non-command-bar surface needs the same key interception behavior.

Do not move `SelectAllTextField` out of Webview until another feature needs
the same select-all-on-focus behavior. Two uses inside Webview are feature-
local reuse, not app-wide shared-component evidence.
```

- [ ] **Step 2: Document behavior sharing rule**

In `docs/architecture/directory_structure.md`, under SharedComponents rules, add:

```markdown
**Share interaction semantics, not only pixels.** If two surfaces have the
same behavior contract — selected row, arrow navigation, Return activation,
Escape close, same-shortcut dismiss, numbered row activation, focus capture —
extract that behavior into `SharedComponents/` and pass feature-specific row
content/actions as closures. A feature may keep its own row rendering; it may
not duplicate the keyboard/focus state machine without a documented reason.
```

- [ ] **Step 3: Update style guide**

In `docs/guides/style_guide.md`, under Shared Shell Controls, add:

```markdown
- **Selectable popovers**: Use `SharedComponents/SelectablePopover` for
  transient popovers with selectable rows. Feature rows remain feature-owned,
  but arrow/Return/Escape/same-shortcut behavior should be shared.
- **Search ownership**: `SidebarSearchField` is for sidebar surfaces.
  Command bar and Webview text fields stay feature-owned unless their AppKit
  behavior gets a second cross-feature use.
```

- [ ] **Step 4: Update AGENTS.md progressive disclosure**

In `AGENTS.md`, under “Shared UI, Styles, And Policies”, add:

```markdown
Before creating a feature-local UI primitive, check for an existing shared
component with the same interaction semantics. Reuse/extract keyboard,
focus, selection, and command-toggle behavior even when row content differs.
Styling parity alone is not enough.

Search rule of thumb:
- Sidebar search surfaces use `SharedComponents/SidebarSearchField`.
- Command bar search remains command-bar-owned because it owns scope and
  shortcut semantics.
- Webview select-all fields remain Webview-owned until a second feature
  needs that exact AppKit behavior.
```

- [ ] **Step 5: Run docs sanity scans**

Run:

```bash
rg -n "SharedComponents/SelectablePopover|SidebarSearchField|CommandBarSearchField|SelectAllTextField|AppStyles|AppPolicies" AGENTS.md docs/architecture/directory_structure.md docs/guides/style_guide.md
```

Expected: the new rules appear in all three docs.

- [ ] **Step 6: Commit**

```bash
git add AGENTS.md docs/architecture/directory_structure.md docs/guides/style_guide.md
git commit -m "docs(ui): clarify shared components and search ownership"
```

---

## Task 7: Verification And Visual Check

**Files:**
- No code files expected.
- Use current branch state.

- [ ] **Step 1: Run focused test suite**

Run:

```bash
swift test --build-path ".build-agent-$PPID" --filter "SelectablePopover|EditorChooser|PaneInbox|PaneTabViewControllerCommandTests|DrawerIconBarInboxSlotTests"
```

Expected: PASS.

- [ ] **Step 2: Run full project checks**

Run:

```bash
mise run build
mise run lint
mise run test
git diff --check
```

Expected:
- `mise run build`: exit 0
- `mise run lint`: exit 0
- `mise run test`: exit 0
- `git diff --check`: exit 0

- [ ] **Step 3: Visual verification with Peekaboo**

Build and launch by PID:

```bash
BUILD_PATH=".build-agent-$PPID"
swift build --build-path "$BUILD_PATH"
"$BUILD_PATH/debug/AgentStudio" &
PID=$!
peekaboo see --app "PID:$PID" --json
```

Verify manually from the screenshot:
- Pane drawer toolbar still shows Finder, editor chooser, and PaneInbox controls.
- PaneInbox popover title says “Pane inbox”.
- PaneInbox rows show selected-row highlight when opened.
- PaneInbox search/sidebar surfaces still use the same rounded search style as repo sidebar.

- [ ] **Step 4: Manual keyboard smoke**

In the debug app:
- Press `Cmd+Shift+I` with a pane focused.
- Expected: PaneInbox opens for the active parent pane plus drawer children.
- Press `Cmd+Shift+I` again.
- Expected: same PaneInbox popover closes.
- Reopen PaneInbox.
- Press Down/Up.
- Expected: selected notification changes.
- Press Return.
- Expected: selected notification activates, marks read, dismisses from PaneInbox, and focuses the source pane.
- Press Escape.
- Expected: PaneInbox closes.

- [ ] **Step 5: Commit any final verification doc update**

If verification evidence is added to a WIP/debug doc, commit it:

```bash
git add docs/wip
git commit -m "docs(ui): record pane inbox component verification"
```

If no files changed, do not create an empty commit.

---

## Self-Review

**Spec coverage:**
- Shared selectable popover behavior: Tasks 1-3.
- PaneInbox same-shortcut toggle: Task 4.
- PaneInbox naming cleanup: Task 5.
- Search ownership and shared-component guardrails: Task 6.
- AppStyles/AppPolicies documentation: Task 6.
- Verification: Task 7.

**Placeholder scan:** No `TBD`, `TODO`, “similar to”, or unbounded “add tests” steps are used. Each code task names exact files, test commands, and expected results.

**Type consistency:**
- Generic item ID name is `ItemID`.
- Shared router type is `SelectablePopoverKeyboardRouter`.
- Shared bridge type is `SelectablePopoverKeyboardBridge`.
- Pane inbox naming stays `PaneInbox...`.
- Style namespace is `AppStyles.Components.PaneInbox`.

**Deliberate non-goals:**
- Do not turn `EditorChooserMenuContent` into a notification renderer.
- Do not merge command-bar search with sidebar search.
- Do not move Webview `SelectAllTextField` yet.
- Do not extract drawer toolbar buttons in this pass.
- Do not add new AppDelegate command routing for PaneInbox.

