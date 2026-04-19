# Command Bar Footer Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the command bar footer to use a fixed two-row layout with clear visual hierarchy, eliminating height jank and separating keyboard shortcuts from scope typing prefixes.

**Architecture:** The footer is a passive SwiftUI view (`CommandBarFooter`) driven by a `FooterHintLayout` value produced by `FooterHintBuilder`. The redesign changes the data model (what hints are produced), the layout structure (how they're arranged into rows), and the rendering (how each hint type looks). The builder is pure logic with comprehensive tests; the view is rendering-only.

**Tech Stack:** SwiftUI, Swift Testing, SF Mono/SF Pro typography

---

## Design Rationale

### Problem

The current footer has five visual and structural issues:

1. **Height jank.** The footer switches between one row (scoped views, nested levels) and two rows (everything scope with a selected item) as the user arrows through items. This causes the results list to resize on every selection change, creating distracting layout shifts.

2. **Redundant `↵ Actions` hint.** When a worktree item is selected, the footer shows `[↵] Actions [⌘↵] New tab [⌥↵] Open in tab`. The plain Enter hint is redundant — pressing Enter on a highlighted row is universal UI convention and doesn't need a hint. It wastes horizontal space and competes visually with the useful modifier shortcuts.

3. **Scope prefixes styled as keyboard badges.** The `>`, `$`, `#` characters are typing prefixes (you type them into the search field), but they're rendered with the same badge styling as keyboard shortcuts like `⌘↵`. This conflates two different interaction patterns and misleads users into thinking they're modifier keys.

4. **No visual hierarchy between rows.** Both rows use identical opacity (0.3), font size (11pt), and badge styling. Row 1 (contextual actions) and Row 2 (navigation/scope) carry equal visual weight, but they serve different purposes. The scope hints should recede further since they're navigation aids, not action shortcuts.

5. **Flat spacing within rows.** All hints use uniform 12px spacing with no visual grouping. When a row contains both action hints and scope hints (in the current 1-row fallback), they blur together.

### Solution — Fixed Two-Row Layout

**Row 1 (primary):** Always present, shows contextual action shortcuts for the selected item. Left-aligned. When nothing is selected or the selected item has no modifier shortcuts, the row is present but empty (maintains height).

**Row 2 (secondary):** Always present. Left side shows scope navigation hints (everything scope) or back navigation (nested). Right side shows dismiss hint. This row uses dimmer opacity to establish visual subordination.

**Specific changes:**

| What | Current | New | Why |
|------|---------|-----|-----|
| `↵ Actions` hint | Shown for worktree items | Dropped | Enter-on-highlighted is universal UX; the hint is noise |
| `↵ Select` hint (nested) | Shown in row 1 | Dropped | Same reason — Enter on highlighted is self-evident |
| Scope prefix rendering | Badge style `[>]` | Plain text `>` at lower opacity | Prefixes are typed characters, not keyboard shortcuts |
| Scope prefix labels | `Commands`, `Panes`, `Repos` | `cmd`, `pane`, `repo` | Shorter labels reduce visual weight; the prefix char provides context |
| Scope separators | None (uniform 12px spacing) | `·` midpoint between scope items | Creates visual grouping without a heavy divider |
| Row 1 opacity | 0.3 text + 0.06 badge bg | 0.40 text + 0.05 badge bg | Slightly more readable text, lighter badge background |
| Row 2 opacity | Same as row 1 | 0.25 text, no badge backgrounds | Clearly subordinate to row 1 |
| Height | Variable (1-2 rows) | Fixed (~44px, always 2 rows) | Eliminates layout jank |
| `esc` in row 2 | Badge style `[esc]` | Plain text `esc` at 0.25 opacity | Consistent with row 2 being all plain text |
| `⌫ Back` in nested | Badge style in row 1 | Plain text in row 2 (replaces scope) | Back is navigation, not an action shortcut |
| Modifier badges | Separate `[⌘] [↵]` | Keep separate badges | Merged badge looked cramped in practice; separate badges are more readable |

### Layout by state

**Worktree selected, everything scope:**
```
Row 1:  [⌘] [↵] New tab   [⌥] [↵] Open in tab
Row 2:  > cmd · $ pane · # repo                    esc Close
```

**Command/tab/pane selected, everything scope:**
```
Row 1:  [↵] Open  (or "Go to" for tab/pane)
Row 2:  > cmd · $ pane · # repo                    esc Close
```

**Nested worktree actions:**
```
Row 1:  [⌘] [↵] New tab   [⌥] [↵] Open in tab
Row 2:  ⌫ Back                                     esc Close
```

**Scoped view (e.g., `> commands`):**
```
Row 1:  [↵] Open
Row 2:                                              esc Close
```

**Nothing selected / empty results:**
```
Row 1:  (empty)
Row 2:  > cmd · $ pane · # repo                    esc Close
```

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Sources/.../CommandBarItem.swift` | Modify | `FooterHintBuilder.hints()` — change what hints are produced. `FooterHintBuilder.layout()` — change row assignment. `FooterHintLayout` — add `FooterHintStyle` enum to hints. |
| `Sources/.../Views/CommandBarFooter.swift` | Modify | Render two fixed rows with visual hierarchy. Add scope-hint rendering (plain text, `·` separators). Add merged badge support. |
| `Sources/.../Views/CommandBarShortcutBadge.swift` | Modify | Support merged multi-character badges (e.g., `⌘↵` in one badge). |
| `Tests/.../FooterHintBuilderTests.swift` | Modify | Update expected labels, add tests for new hint composition (dropped plain enter, scope as text, nested layout changes). |

No new files. Changes are isolated to the footer subsystem.

---

## Task 1: Update `FooterHintBuilder.hints()` to drop redundant plain-Enter hints

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift:257-313` (FooterHintBuilder.hints)
- Test: `Tests/AgentStudioTests/Features/CommandBar/FooterHintBuilderTests.swift`

The plain `↵ Actions` hint for worktree items and `↵ Select` hint for nested levels are redundant. Enter-on-highlighted is universal UX. Removing them reduces noise and frees horizontal space for the modifier shortcuts that actually need visibility.

- [ ] **Step 1: Update tests to expect no redundant enter hints**

In `FooterHintBuilderTests.swift`, update these tests:

```swift
@Test
func test_nested_showsBackAndClose() {
    let hints = FooterHintBuilder.hints(for: nil, isNested: true, canOpenInCurrentTab: true)

    #expect(labels(hints) == ["Back", "Close"])
    #expect(hasDivider(hints))
}
```

```swift
@Test
func test_worktreeWithoutCurrentTab_showsNewTab() {
    let item = makeCommandBarItem(
        id: "wt-1",
        title: "main",
        worktreePresence: makeWorktreePresence(paneCount: 0)
    )
    let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: false)

    #expect(labels(hints) == ["New tab", "Commands", "Panes", "Repos", "Close"])
}
```

```swift
@Test
func test_worktreeNotOpen_withCurrentTab_showsModifiers() {
    let item = makeCommandBarItem(
        id: "wt-1",
        title: "main",
        worktreePresence: makeWorktreePresence(paneCount: 0)
    )
    let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true)

    #expect(labels(hints) == ["New tab", "Open in tab", "Commands", "Panes", "Repos", "Close"])
    let keys = keysById(hints)
    #expect(keys["cmd-enter"] == ["⌘", "↵"])
    #expect(keys["opt-enter"] == ["⌥", "↵"])
}
```

Update `test_worktreeSinglePane_showsSameMenuAndModifiers` and `test_worktreeMultiplePanes_showsSameMenuAndModifiers` to expect `["New tab", "Open in tab", "Commands", "Panes", "Repos", "Close"]`.

Update `test_worktreeInReposScope_omitsGlobalScopeHints` to expect `["New tab", "Open in tab", "Close"]`.

Update `test_itemLayoutKeepsContextualActionsOnPrimaryRow`:

```swift
@Test
func test_itemLayoutKeepsContextualActionsOnPrimaryRow() {
    let item = makeCommandBarItem(
        id: "wt-1",
        title: "main",
        worktreePresence: makeWorktreePresence(paneCount: 1)
    )
    let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true)
    let layout = layoutLabels(hints)

    #expect(layout.primary == ["New tab", "Open in tab"])
    #expect(layout.secondaryLeading == ["Commands", "Panes", "Repos"])
    #expect(layout.secondaryTrailing == ["Close"])
}
```

Update `test_nestedLayoutPutsDismissOnSecondaryTrailingOnly`:

```swift
@Test
func test_nestedLayoutPutsDismissOnSecondaryTrailingOnly() {
    let hints = FooterHintBuilder.hints(for: nil, isNested: true, canOpenInCurrentTab: true)
    let layout = layoutLabels(hints)

    #expect(layout.primary.isEmpty)
    #expect(layout.secondaryLeading == ["Back"])
    #expect(layout.secondaryTrailing == ["Close"])
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
SWIFT_BUILD_DIR=".build-agent-footer" swift test --build-path ".build-agent-footer" --filter "FooterHintBuilder" 2>&1 | tail -20
```

Expected: Multiple FAILs — tests expect the new hint composition but the builder still produces the old hints.

- [ ] **Step 3: Update `FooterHintBuilder.hints()` to drop redundant hints**

In `CommandBarItem.swift`, update the `hints` method:

For the nested case (around line 264), remove the `↵ Select` hint and move `⌫ Back` to the secondary row:

```swift
if isNested {
    return [
        .divider("div-dismiss"),
        FooterHint(id: "back", key: "⌫", label: "Back"),
        FooterHint(id: "dismiss", key: "esc", label: "Close"),
    ]
}
```

For the worktree case (around line 278), remove the `↵ Actions` hint:

```swift
if item.worktreeOpenState != nil {
    actions = [
        FooterHint(
            id: "cmd-enter",
            keys: [ShortcutKey(symbol: "⌘"), ShortcutKey(symbol: "↵")],
            label: "New tab"
        ),
    ]
    if canOpenInCurrentTab {
        actions.append(
            FooterHint(
                id: "opt-enter",
                keys: [ShortcutKey(symbol: "⌥"), ShortcutKey(symbol: "↵")],
                label: "Open in tab"
            )
        )
    }
}
```

Update the `layout` method to route `"back"` to `secondaryLeadingRow`:

```swift
static func layout(for hints: [FooterHint]) -> FooterHintLayout {
    var primaryRow: [FooterHint] = []
    var secondaryLeadingRow: [FooterHint] = []
    var secondaryTrailingRow: [FooterHint] = []

    for hint in hints where !hint.isDivider {
        switch hint.id {
        case "dismiss":
            secondaryTrailingRow.append(hint)
        case "scope-commands", "scope-panes", "scope-repos", "back":
            secondaryLeadingRow.append(hint)
        default:
            primaryRow.append(hint)
        }
    }

    return FooterHintLayout(
        primaryRow: primaryRow,
        secondaryLeadingRow: secondaryLeadingRow,
        secondaryTrailingRow: secondaryTrailingRow
    )
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
SWIFT_BUILD_DIR=".build-agent-footer" swift test --build-path ".build-agent-footer" --filter "FooterHintBuilder" 2>&1 | tail -20
```

Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift Tests/AgentStudioTests/Features/CommandBar/FooterHintBuilderTests.swift
git commit -m "refactor(command-bar): drop redundant plain-Enter footer hints

Remove ↵ Actions (worktree) and ↵ Select (nested) hints since
Enter-on-highlighted is universal UX. Move ⌫ Back to secondary
row for nested levels."
```

---

## Task 2: Add `FooterHintStyle` and scope text rendering to `FooterHintLayout`

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift` (FooterHint, FooterHintBuilder)
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarFooter.swift`
- Test: `Tests/AgentStudioTests/Features/CommandBar/FooterHintBuilderTests.swift`

Scope prefixes (`>`, `$`, `#`) are typing prefixes, not keyboard shortcuts. They should render as plain dim text, not as badges. This requires a style tag on hints so the footer can render them differently.

- [ ] **Step 1: Add `FooterHintStyle` enum and apply to hints**

In `CommandBarItem.swift`, add a style enum above `FooterHint`:

```swift
enum FooterHintStyle: Equatable, Sendable {
    /// Keyboard shortcut with badge rendering (e.g., [⌘↵] New tab)
    case badge
    /// Plain text hint with no badge (e.g., > cmd · $ pane)
    case plain
}
```

Add `style` to `FooterHint`:

```swift
struct FooterHint: Identifiable, Equatable, Sendable {
    let id: String
    let shortcutKeys: [ShortcutKey]
    let label: String
    let isDivider: Bool
    let style: FooterHintStyle

    init(id: String, key: String, label: String, isDivider: Bool = false, style: FooterHintStyle = .badge) {
        self.id = id
        self.shortcutKeys = [ShortcutKey(symbol: key)]
        self.label = label
        self.isDivider = isDivider
        self.style = style
    }

    init(id: String, keys: [ShortcutKey], label: String, isDivider: Bool = false, style: FooterHintStyle = .badge) {
        self.id = id
        self.shortcutKeys = keys
        self.label = label
        self.isDivider = isDivider
        self.style = style
    }

    static func divider(_ id: String) -> Self {
        Self(id: id, keys: [], label: "", isDivider: true, style: .plain)
    }
}
```

- [ ] **Step 2: Change scope hints and dismiss/back to use `.plain` style with shorter labels**

In `FooterHintBuilder`, update `scopeHints`:

```swift
private static let scopeHints: [FooterHint] = [
    FooterHint(id: "scope-commands", key: ">", label: "cmd", style: .plain),
    FooterHint(id: "scope-panes", key: "$", label: "pane", style: .plain),
    FooterHint(id: "scope-repos", key: "#", label: "repo", style: .plain),
]
```

Update the dismiss hint in `hints()` (line ~311):

```swift
hints.append(FooterHint(id: "dismiss", key: "esc", label: "Close", style: .plain))
```

Update the back hint in the nested case:

```swift
FooterHint(id: "back", key: "⌫", label: "Back", style: .plain),
FooterHint(id: "dismiss", key: "esc", label: "Close", style: .plain),
```

- [ ] **Step 3: Update tests for new labels**

Update all tests that check for `"Commands"`, `"Panes"`, `"Repos"` to expect `"cmd"`, `"pane"`, `"repo"` instead. Key tests to update:

```swift
@Test
func test_noSelection_everythingScope_showsScopeHintsAndClose() {
    let hints = FooterHintBuilder.hints(for: nil, isNested: false, canOpenInCurrentTab: true)
    #expect(labels(hints) == ["cmd", "pane", "repo", "Close"])
}
```

```swift
@Test
func test_tabItem_showsGoTo() {
    // ...
    #expect(labels(hints).contains("cmd"))
    #expect(labels(hints).last == "Close")
}
```

Update `test_everythingScope_layoutMovesScopeHintsToSecondaryLeadingAndDismissToTrailing`:

```swift
#expect(layout.secondaryLeading == ["cmd", "pane", "repo"])
```

Update all worktree tests that list scope labels:

```swift
#expect(labels(hints) == ["New tab", "Open in tab", "cmd", "pane", "repo", "Close"])
```

Add a style-checking test:

```swift
@Test
func test_scopeHints_usePlainStyle() {
    let hints = FooterHintBuilder.hints(for: nil, isNested: false, canOpenInCurrentTab: true)
    let scopeHints = hints.filter { ["scope-commands", "scope-panes", "scope-repos"].contains($0.id) }

    for hint in scopeHints {
        #expect(hint.style == .plain)
    }
}

@Test
func test_actionHints_useBadgeStyle() {
    let item = makeCommandBarItem(
        id: "wt-1",
        title: "main",
        worktreePresence: makeWorktreePresence(paneCount: 0)
    )
    let hints = FooterHintBuilder.hints(for: item, isNested: false, canOpenInCurrentTab: true)
    let actionHints = hints.filter { ["cmd-enter", "opt-enter"].contains($0.id) }

    for hint in actionHints {
        #expect(hint.style == .badge)
    }
}

@Test
func test_dismissHint_usesPlainStyle() {
    let hints = FooterHintBuilder.hints(for: nil, isNested: false, canOpenInCurrentTab: true)
    let dismiss = hints.first { $0.id == "dismiss" }

    #expect(dismiss?.style == .plain)
}
```

- [ ] **Step 4: Run tests**

```bash
SWIFT_BUILD_DIR=".build-agent-footer" swift test --build-path ".build-agent-footer" --filter "FooterHintBuilder" 2>&1 | tail -20
```

Expected: All PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarItem.swift Tests/AgentStudioTests/Features/CommandBar/FooterHintBuilderTests.swift
git commit -m "feat(command-bar): add FooterHintStyle for scope vs badge rendering

Scope prefixes use .plain style with shorter labels (cmd/pane/repo).
Action shortcuts keep .badge style. Dismiss and back use .plain."
```

---

## Task 3: Redesign `CommandBarFooter` view with fixed two-row layout

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarFooter.swift`

This is the visual change. The footer renders two fixed rows with different visual treatments based on `FooterHintStyle`. Row 1 uses badge-styled shortcuts at higher opacity. Row 2 uses plain text at lower opacity with `·` separators between scope items.

- [ ] **Step 1: Rewrite `CommandBarFooter` body**

Replace the full body of `CommandBarFooter.swift`:

```swift
import SwiftUI

// MARK: - CommandBarFooter

/// Fixed two-row keyboard hints footer.
/// Row 1: contextual action shortcuts (badge style, higher opacity).
/// Row 2: scope navigation (plain text, lower opacity) + dismiss (right-aligned).
struct CommandBarFooter: View {
    let hints: [FooterHint]

    private let primaryOpacity: Double = 0.40
    private let secondaryOpacity: Double = 0.25
    private let badgeBackgroundOpacity: Double = 0.05
    private let separatorOpacity: Double = 0.15
    private let rowHeight: CGFloat = 16

    var body: some View {
        let layout = FooterHintBuilder.layout(for: hints)

        VStack(spacing: 4) {
            // Row 1: action shortcuts
            HStack(spacing: 14) {
                ForEach(layout.primaryRow) { hint in
                    badgeHint(hint)
                }
                Spacer(minLength: 0)
            }
            .frame(height: rowHeight)

            // Row 2: scope/navigation + dismiss
            HStack(spacing: 0) {
                ForEach(Array(layout.secondaryLeadingRow.enumerated()), id: \.element.id) { index, hint in
                    if index > 0 {
                        Text("·")
                            .font(.system(size: AppStyles.textXs))
                            .foregroundStyle(.primary.opacity(separatorOpacity))
                            .padding(.horizontal, 6)
                    }
                    plainHint(hint)
                }

                Spacer(minLength: 0)

                ForEach(layout.secondaryTrailingRow) { hint in
                    plainHint(hint)
                }
            }
            .frame(height: rowHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
    }

    // MARK: - Hint renderers

    /// Badge-styled hint for row 1: key badges + label at primary opacity.
    private func badgeHint(_ hint: FooterHint) -> some View {
        HStack(spacing: 4) {
            CommandBarShortcutBadge(
                keys: hint.shortcutKeys,
                style: .footerCompact
            )
            Text(hint.label)
                .font(.system(size: AppStyles.textXs))
        }
        .foregroundStyle(.primary.opacity(primaryOpacity))
    }

    /// Plain text hint for row 2: key symbol + label at secondary opacity.
    private func plainHint(_ hint: FooterHint) -> some View {
        HStack(spacing: 3) {
            Text(hint.shortcutKeys.map(\.symbol).joined())
                .font(.system(size: AppStyles.textXs, weight: .medium, design: .monospaced))
            Text(hint.label)
                .font(.system(size: AppStyles.textXs))
        }
        .foregroundStyle(.primary.opacity(secondaryOpacity))
    }
}
```

- [ ] **Step 2: Update `CommandBarShortcutBadge` badge background opacity**

In `CommandBarShortcutBadge.swift`, update the `.footerCompact` background opacity from 0.06 to 0.05:

Change the background fill in the body:

```swift
.background(
    RoundedRectangle(cornerRadius: style.cornerRadius)
        .fill(Color.primary.opacity(style.backgroundOpacity))
)
```

Add `backgroundOpacity` to the `Style` enum:

```swift
var backgroundOpacity: CGFloat {
    switch self {
    case .row:
        return 0.06
    case .footerCompact:
        return 0.05
    }
}
```

- [ ] **Step 3: Build and verify visually**

```bash
mise run build 2>&1 | tail -5
```

Expected: Build complete.

Then launch and verify with Peekaboo:

```bash
pkill -9 -f "AgentStudio" 2>/dev/null; sleep 1
.build/debug/AgentStudio &
sleep 3
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo see --app "PID:$PID" --json
```

Check: Footer always shows two rows. Row 1 has badge-styled action hints. Row 2 has plain text scope hints with `·` separators and `esc Close` right-aligned. Height does not change when arrowing through items.

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/Views/CommandBarFooter.swift Sources/AgentStudio/Features/CommandBar/Views/CommandBarShortcutBadge.swift
git commit -m "feat(command-bar): redesign footer with fixed two-row layout

Row 1: action shortcuts with badge style at 0.40 opacity.
Row 2: scope hints as plain text at 0.25 opacity with · separators.
Fixed height eliminates layout jank when selection changes."
```

## Task 4: Full test pass and lint

**Files:**
- All modified files

- [ ] **Step 1: Run full command-bar test suite**

```bash
SWIFT_BUILD_DIR=".build-agent-footer" swift test --build-path ".build-agent-footer" --filter "CommandBar" 2>&1 | tail -20
```

Expected: All tests pass. No new failures from footer changes.

- [ ] **Step 2: Run lint**

```bash
mise run lint 2>&1 | tail -5
```

Expected: 0 violations.

- [ ] **Step 3: Visual verification with Peekaboo**

Launch the app and open the command bar. Verify all states:

1. Arrow through worktree items — footer height stays fixed, row 1 shows `[⌘] [↵] New tab [⌥] [↵] Open in tab`
2. Arrow to a command item — row 1 changes to `[↵] Open`, height stays same
3. Arrow to a tab item — row 1 shows `[↵] Go to`
4. Type `>` to enter commands scope — row 2 loses scope hints, keeps `esc Close`
5. Press Enter on a worktree to enter nested actions — row 2 shows `⌫ Back` left, `esc Close` right
6. With no results (type gibberish) — row 1 empty, row 2 shows scope hints + dismiss

```bash
pkill -9 -f "AgentStudio" 2>/dev/null; sleep 1
.build/debug/AgentStudio &
sleep 3
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo see --app "PID:$PID" --json
```

- [ ] **Step 4: Final commit if any fixups needed**
