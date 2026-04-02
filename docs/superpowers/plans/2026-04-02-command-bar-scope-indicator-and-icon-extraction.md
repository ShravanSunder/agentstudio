# Command Bar Scope Indicator & Icon Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an inline scope indicator to the command bar search field, extract octicon assets from the sidebar into shared `Infrastructure/Icons/` so the command bar can use `octicon-repo` for the repos scope, and change manual scope activation to require `symbol + space` (`"$ "`, `"> "`, `"# "`).

**Architecture:** Extract `OcticonImage` view and its asset loader from `Features/Sidebar/RepoSidebarContentView.swift` into `Infrastructure/Icons/`. Rename the xcassets directory from `SidebarIcons` to `Icons` since these are now app-wide. Modify `CommandBarSearchField` to show a scope-specific icon (SF Symbol or octicon) inline when a prefix is active, and move the drill-in `CommandBarScopePill` from its own row into the search field row.

**Non-goals:** No changes to command bar data source or item content. Aside from the intentional `symbol + space` prefix activation change, this work is focused on the search field area and icon extraction only.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit

---

## Visual Spec

### Current behavior

```
Everything scope (no prefix):
║  🔍  Search or jump to...                                        ║

Panes scope ($ prefix) — icon hidden, no scope indicator:
║       $ search term                                              ║

Drill-in — scope pill in its own row ABOVE the search field:
║  ┌─────────────────────────┐                                     ║
║  │ Commands · Close Pane ⊗ │                                     ║
║  └─────────────────────────┘                                     ║
║  🔍  Filter...                                                   ║
```

### Target behavior

```
Everything scope (no prefix) — magnifying glass, same as today:
║  🔍  Search or jump to...                                        ║

Panes scope ($ + space prefix) — terminal icon replaces magnifying glass:
║  ⌨   $ search term                                               ║

Commands scope (> + space prefix) — chevron icon:
║  ≫   > close                                                     ║

Repos scope (# + space prefix) — octicon-repo icon:
║  📦   # agent                                                     ║

Drill-in — pill INLINE with search field, same row:
║  ┌─────────────────────────┐  Filter...                          ║
║  │ Commands · Close Pane ⊗ │                                     ║
║  └─────────────────────────┘                                     ║
```

### Key design decisions

- Scope and drill-in are **mutually exclusive** (verified: `activePrefix` returns nil when `navigationStack` is non-empty, and `pushLevel` clears `rawInput`). So one slot left of the search field handles both.
- Scope icon: SF Symbol for panes/commands, `octicon-repo` for repos. No text label — just the icon. The prefix chars in the text field name the scope once the user commits with `symbol + space`.
- Drill-in pill: moves from its own row above the search field to inline left of the text field. Same `CommandBarScopePill` component, just repositioned.
- The scope icon uses semantic icons that differ from the prefix chars to avoid duplication (`terminal` not `dollarsign`, `chevron.right.2` not `>`, `octicon-repo` not `#`).

### Scope icon mapping

| State | Left of search | SF Symbol / Octicon |
|-------|----------------|---------------------|
| Everything (no prefix) | magnifying glass | `magnifyingglass` |
| Panes (`$`) | terminal | `terminal` |
| Commands (`>`) | chevron | `chevron.right.2` |
| Repos (`#`) | repo | `octicon-repo` |
| Drill-in (nested) | scope pill | `CommandBarScopePill` |

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Infrastructure/Icons/OcticonImage.swift` | Create | Reusable octicon view component |
| `Infrastructure/Icons/OcticonLoader.swift` | Create | Asset loading + in-memory cache |
| `Resources/SidebarIcons.xcassets` | Rename to `Resources/Icons.xcassets` | Shared icon assets |
| `Features/Sidebar/RepoSidebarContentView.swift` | Modify | Remove private `OcticonImage` + `SidebarOcticonLoader`, import from Infrastructure |
| `Features/CommandBar/CommandBarState.swift` | Modify | Change `scopeIcon` to return semantic icon names |
| `Features/CommandBar/Views/CommandBarSearchField.swift` | Modify | Show scope icon or drill-in pill inline |
| `Features/CommandBar/Views/CommandBarView.swift` | Modify | Remove scope pill row above search field |

---

## Task 1: Extract `OcticonLoader` to `Infrastructure/Icons/`

Extract the asset loader from the sidebar into a shared location. Rename xcassets from `SidebarIcons` to `Icons`.

**Files:**
- Create: `Sources/AgentStudio/Infrastructure/Icons/OcticonLoader.swift`
- Rename: `Sources/AgentStudio/Resources/SidebarIcons.xcassets` → `Sources/AgentStudio/Resources/Icons.xcassets`

- [ ] **Step 1: Create `OcticonLoader.swift`**

```swift
import AppKit

/// Loads octicon SVG/PDF assets from the Icons.xcassets bundle directory.
/// Caches loaded images in memory for reuse.
@MainActor
final class OcticonLoader {
    static let shared = OcticonLoader()

    private var cache: [String: NSImage] = [:]

    private init() {}

    func image(named name: String) -> NSImage? {
        if let cached = cache[name] {
            return cached
        }

        let subdirectory = "Icons.xcassets/\(name).imageset"
        if let svgURL = Bundle.appResources.url(
            forResource: name,
            withExtension: "svg",
            subdirectory: subdirectory
        ),
            let image = NSImage(contentsOf: svgURL)
        {
            cache[name] = image
            return image
        }

        if let pdfURL = Bundle.appResources.url(
            forResource: name,
            withExtension: "pdf",
            subdirectory: subdirectory
        ),
            let image = NSImage(contentsOf: pdfURL)
        {
            cache[name] = image
            return image
        }

        return nil
    }
}
```

- [ ] **Step 2: Rename the xcassets directory**

```bash
git mv Sources/AgentStudio/Resources/SidebarIcons.xcassets Sources/AgentStudio/Resources/Icons.xcassets
```

- [ ] **Step 3: Update `Package.swift` if it references the old name**

`Package.swift` explicitly references `SidebarIcons.xcassets` in this repo, so it must be updated to `Icons.xcassets` as part of the rename:

```bash
grep -n "SidebarIcons" Package.swift
```

Expected: one explicit `.process("Resources/SidebarIcons.xcassets")` entry that must be renamed.

- [ ] **Step 4: Build to verify the rename didn't break asset loading**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS (the build should work, but sidebar icons may fail at runtime until Step 5 completes)

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Infrastructure/Icons/OcticonLoader.swift Sources/AgentStudio/Resources/
git commit -m "refactor: extract OcticonLoader to Infrastructure/Icons, rename SidebarIcons → Icons"
```

---

## Task 2: Extract `OcticonImage` view to `Infrastructure/Icons/`

Extract the SwiftUI view that renders octicons.

**Files:**
- Create: `Sources/AgentStudio/Infrastructure/Icons/OcticonImage.swift`

- [ ] **Step 1: Create `OcticonImage.swift`**

```swift
import SwiftUI

/// Renders an octicon asset as a template image at a given size.
/// Uses `OcticonLoader` to load SVG/PDF assets from the Icons.xcassets bundle.
struct OcticonImage: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image = OcticonLoader.shared.image(named: name) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
    }
}
```

- [ ] **Step 2: Update sidebar to use the shared components**

In `Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift`:

1. Delete the `private struct OcticonImage` (lines 940-959)
2. Delete the `private final class SidebarOcticonLoader` (lines 961-999)
3. No import changes needed — `Infrastructure/` is already importable from `Features/`

All existing `OcticonImage(name:size:)` call sites in the sidebar keep working unchanged since the public API is identical.

- [ ] **Step 3: Build to verify**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Infrastructure/Icons/OcticonImage.swift Sources/AgentStudio/Features/Sidebar/RepoSidebarContentView.swift
git commit -m "refactor: extract OcticonImage to Infrastructure/Icons, remove sidebar private copies"
```

---

## Task 3: Change prefix pattern to require symbol + space

Currently `activePrefix` matches a single character (`$`, `>`, `#`). This causes the scope to switch the instant you type the prefix char, before you've committed to filtering. The prefix should be the symbol + space (`"$ "`, `"> "`, `"# "`), so the scope only switches once you type the space after the symbol. This is an intentional input-behavior change in service of the inline icon UX, and it also eliminates the visual jank of the scope icon changing mid-keystroke.

`show(prefix:)` already sets `rawInput = "$ "` (with space) — this change makes manual typing match that behavior.

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarState.swift`
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarStateTests.swift`

- [ ] **Step 1: Write tests for the new prefix behavior**

```swift
@Test
func test_activePrefix_singleCharWithoutSpace_returnsNil() {
    state.rawInput = "$"

    #expect(state.activePrefix == nil)
    #expect(state.activeScope == .everything)
}

@Test
func test_activePrefix_symbolPlusSpace_returnsPrefix() {
    state.rawInput = "$ "

    #expect(state.activePrefix == "$ ")
    #expect(state.activeScope == .panes)
}

@Test
func test_activePrefix_symbolSpaceQuery_returnsPrefix() {
    state.rawInput = "$ search term"

    #expect(state.activePrefix == "$ ")
    #expect(state.searchQuery == "search term")
}

@Test
func test_activePrefix_commandsSymbolPlusSpace() {
    state.rawInput = "> "

    #expect(state.activePrefix == "> ")
    #expect(state.activeScope == .commands)
}

@Test
func test_activePrefix_reposSymbolPlusSpace() {
    state.rawInput = "# "

    #expect(state.activePrefix == "# ")
    #expect(state.activeScope == .repos)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "activePrefix" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: FAIL — single `$` currently returns a prefix, `"$ "` two-char prefix not recognized.

- [ ] **Step 3: Update `activePrefix` to require symbol + space**

In `Sources/AgentStudio/Features/CommandBar/CommandBarState.swift`, replace `activePrefix`:

```swift
/// Active prefix: "> ", "$ ", "# ", or nil.
/// Requires symbol + space so the scope only switches after the user
/// commits by pressing space, not mid-keystroke on the symbol alone.
var activePrefix: String? {
    guard navigationStack.isEmpty else { return nil }
    guard rawInput.count >= 2 else { return nil }
    let twoChars = String(rawInput.prefix(2))
    return ["> ", "$ ", "# "].contains(twoChars) ? twoChars : nil
}
```

- [ ] **Step 4: Update `searchQuery` to strip the 2-char prefix**

The existing `searchQuery` already uses `prefix.count` to drop characters, so it adapts automatically since `activePrefix` now returns a 2-char string. But verify the space-stripping logic still works:

```swift
var searchQuery: String {
    guard let prefix = activePrefix else { return rawInput }
    let afterPrefix = String(rawInput.dropFirst(prefix.count))
    // No longer need to strip leading space — it's part of the prefix now
    return afterPrefix
}
```

Remove the space-stripping `if` block entirely since the space is now part of the prefix itself. It becomes dead code after this change.

- [ ] **Step 5: Update `show(prefix:)` — prefixes in the contains check should match**

```swift
func show(prefix: String? = nil) {
    if let prefix, !prefix.isEmpty, [">", "$", "#"].contains(prefix) {
        rawInput = prefix + " "
    } else {
        rawInput = prefix ?? ""
    }
    navigationStack = []
    selectedIndex = 0
    isVisible = true
    stateLogger.debug("Command bar shown with prefix: \(prefix ?? "(none)")")
}
```

This still works — it checks for single-char input from callers and appends the space. `activePrefix` then matches the resulting `"$ "`.

- [ ] **Step 6: Update `hasPrefixInText`**

This still works as-is — `activePrefix != nil && !rawInput.isEmpty` — since `activePrefix` only returns non-nil when there's a 2-char prefix.

- [ ] **Step 7: Update existing tests that assumed single-char prefix**

Find tests that set `state.rawInput = "$"` or `">"` or `"#"` and expect a scope change. Update them to `"$ "`, `"> "`, `"# "`. The implementing agent should search for all test assertions on `activePrefix`, `activeScope`, `searchQuery`, `scopeIcon`, `placeholder` and update the rawInput values.

Use these exact searches:

```bash
rg -n 'rawInput = "[>$#][^" ]' Tests/AgentStudioTests
rg -n 'rawInput = "[>$#]"$' Tests/AgentStudioTests
```

Key pattern to find: any test that does `state.rawInput = "$"` and then expects `activeScope == .panes` — those need `state.rawInput = "$ "`.

- [ ] **Step 8: Run full tests**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "CommandBarState" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarState.swift Tests/AgentStudioTests/Features/CommandBar/CommandBarStateTests.swift
git commit -m "fix(command-bar): require symbol + space for prefix to switch scope"
```

---

## Task 4: Update `scopeIcon` to return semantic icons

Change the scope icon from prefix-mirroring symbols to semantic icons that represent the content being filtered.

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/CommandBarState.swift`
- Modify: `Tests/AgentStudioTests/Features/CommandBar/CommandBarStateTests.swift`

- [ ] **Step 1: Write test for new scope icons**

In `Tests/AgentStudioTests/Features/CommandBar/CommandBarStateTests.swift`, update or add:

```swift
@Test
func test_scopeIcon_panes_returnsTerminal() {
    state.rawInput = "$ "

    #expect(state.scopeIcon == "terminal")
}

@Test
func test_scopeIcon_commands_returnsChevron() {
    state.rawInput = "> "

    #expect(state.scopeIcon == "chevron.right.2")
}

@Test
func test_scopeIcon_repos_returnsOcticonRepo() {
    state.rawInput = "# "

    #expect(state.scopeIcon == "octicon-repo")
}

@Test
func test_scopeIcon_everything_returnsMagnifyingGlass() {
    state.rawInput = "search"

    #expect(state.scopeIcon == "magnifyingglass")
}
```

- [ ] **Step 2: Run tests to verify the panes/repos tests fail**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "scopeIcon" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: FAIL — panes returns `"dollarsign"` and repos returns `"number"`, not the new values.

- [ ] **Step 3: Update `scopeIcon` in `CommandBarState`**

In `Sources/AgentStudio/Features/CommandBar/CommandBarState.swift`, replace the `scopeIcon` computed property:

```swift
/// Icon name for the scope indicator left of the search field.
/// Uses semantic icons that represent the content being filtered,
/// not the prefix character (which is already visible in the text field).
/// Returns an SF Symbol name for everything/commands/panes,
/// or an octicon asset name for repos.
var scopeIcon: String {
    if isNested { return "magnifyingglass" }
    switch activeScope {
    case .everything: return "magnifyingglass"
    case .commands: return "chevron.right.2"
    case .panes: return "terminal"
    case .repos: return "octicon-repo"
    }
}
```

Also add a computed property to distinguish SF Symbol from octicon:

```swift
/// Whether `scopeIcon` is an octicon asset name (vs an SF Symbol).
var scopeIconIsOcticon: Bool {
    scopeIcon.hasPrefix("octicon-")
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift test --build-path "$SWIFT_BUILD_DIR" --filter "scopeIcon" > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/CommandBarState.swift Tests/AgentStudioTests/Features/CommandBar/CommandBarStateTests.swift
git commit -m "feat(command-bar): use semantic scope icons (terminal, chevron, octicon-repo)"
```

---

## Task 5: Rework `CommandBarSearchField` — scope icon and inline drill-in pill

The search field's left slot now shows one of three things:
1. Magnifying glass (everything scope, no prefix)
2. Scope-specific icon (prefix active)
3. Drill-in scope pill (nested navigation)

The drill-in pill moves from its own row in `CommandBarView` into the search field.

**Files:**
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarSearchField.swift`
- Modify: `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift`

- [ ] **Step 1: Update `CommandBarSearchField` to show scope icon or drill-in pill**

Replace the entire body of `CommandBarSearchField`:

```swift
struct CommandBarSearchField: View {
    @Bindable var state: CommandBarState
    let onArrowUp: () -> Void
    let onArrowDown: () -> Void
    let onEnter: () -> Void
    let onBackspaceOnEmpty: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Left slot: drill-in pill OR scope icon
            if state.isNested {
                CommandBarScopePill(
                    parent: state.scopePillParent,
                    child: state.scopePillChild,
                    onDismiss: { state.popToRoot() }
                )
            } else {
                scopeIconView
            }

            // Text input with keyboard interception
            CommandBarTextField(
                text: $state.rawInput,
                placeholder: state.placeholder,
                onArrowUp: onArrowUp,
                onArrowDown: onArrowDown,
                onEnter: onEnter,
                onBackspaceOnEmpty: onBackspaceOnEmpty
            )
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
    }

    @ViewBuilder
    private var scopeIconView: some View {
        if state.scopeIconIsOcticon {
            OcticonImage(name: state.scopeIcon, size: 16)
                .foregroundStyle(.primary.opacity(0.35))
        } else {
            Image(systemName: state.scopeIcon)
                .font(.system(size: AppStyle.textBase, weight: .medium))
                .foregroundStyle(.primary.opacity(0.35))
                .frame(width: 16, height: 16)
        }
    }
}
```

Changes vs current:
- Removed the `if !state.hasPrefixInText` guard — scope icon is now always shown (it's semantic, not redundant with prefix)
- Added `state.isNested` branch that shows the drill-in pill inline
- Added `scopeIconView` that handles both SF Symbol and octicon rendering

- [ ] **Step 2: Remove the scope pill row from `CommandBarView`**

In `Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift`, remove the scope pill section from `body`. Delete this block:

```swift
            // Scope pill (only when nested)
            if state.isNested {
                HStack {
                    CommandBarScopePill(
                        parent: state.scopePillParent,
                        child: state.scopePillChild,
                        onDismiss: { state.popToRoot() }
                    )
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
```

The pill now lives inside `CommandBarSearchField`.

- [ ] **Step 3: Build to verify**

Run: `SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" swift build --build-path "$SWIFT_BUILD_DIR" > /tmp/build-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/AgentStudio/Features/CommandBar/Views/CommandBarSearchField.swift Sources/AgentStudio/Features/CommandBar/Views/CommandBarView.swift
git commit -m "feat(command-bar): inline scope icon and drill-in pill in search field"
```

---

## Task 6: Run full test suite, lint, and visual verification

- [ ] **Step 1: Run all tests**

Run: `mise run test > /tmp/test-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 2: Run lint**

Run: `mise run lint > /tmp/lint-output.txt 2>&1 && echo "PASS" || echo "FAIL"`

Expected: PASS

- [ ] **Step 3: Visual verification with Peekaboo**

```bash
pkill -9 -f "AgentStudio" 2>/dev/null
mise run build && .build/debug/AgentStudio &
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo see --app "PID:$PID" --json
```

Verify:
1. Open command bar (⌘P) — magnifying glass icon, "Search or jump to..."
2. Type `$` then space — icon changes to terminal icon, prefix `$ ` visible in text field
3. Type `>` then space — icon changes to chevron icon
4. Type `#` then space — icon changes to octicon-repo (should render from SVG asset)
5. Select a drill-in command (e.g., "Close Pane...") — pill appears inline with search field, magnifying glass icon gone, "Filter..." placeholder
6. Press backspace on empty in drill-in — pill disappears, back to everything scope with magnifying glass
7. Sidebar still renders all octicons correctly (repo, branch, worktree, star, merge icons)

- [ ] **Step 4: Final commit if any formatting fixes needed**

```bash
git add -A
git commit -m "chore: formatting fixes from lint"
```
