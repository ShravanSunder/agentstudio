# Welcome Launcher Composition Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the `.launcher` state of `WorkspaceEmptyStateView` so recents sit above teaching, `⌘T` is a single hero row, and `⌘P` pairs with a launcher-only preview row variant — while Welcome 1 stays pixel-identical.

**Architecture:** Add tokens to `AppStyles.Welcome` (never mutate existing values used by Welcome 1). Make recent cards flexible-width so the grid fills `contentColumnWidth = 1092`. Introduce `LauncherPreviewScopeRow` (private struct inside `WorkspaceEmptyStateView.swift`) for two-line scope explanations; keep the real `CommandBarResultRow` untouched. Lock typography to concrete values via tests so drift is a test failure, not a render check.

**Tech Stack:** SwiftUI, Swift 6.2, Swift Testing (`@Suite`, `@Test`, `#expect`), AppKit, existing `CommandBarStatusStrip` / `CommandBarFooter`, Peekaboo for visual verification, mise / swift-format / swiftlint.

**Spec:** `docs/superpowers/specs/2026-04-16-welcome-launcher-composition-redesign.md`

---

## File Structure

### Modify

- `Sources/AgentStudio/Infrastructure/AppStyles.swift`
  Reason: add new `AppStyles.Welcome` tokens and rename `recentCardWidth` → `recentCardMinWidth`. No existing token values change.
- `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift`
  Reason: rewrite `launcherBody(availableWidth:)` composition; add `LauncherPreviewScopeRow`; update `CommandBarEmbeddedPreview` to use it; update `WorkspaceEmptyStateLayout` breakpoint and card-width math; remove `launcherStartFastTitle` constant and the standalone `⌘T` row.
- `Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift`
  Reason: replace existing launcher tests with breakpoint tests, typography contract tests, height-budget assertion, and Welcome 1 regression locks.

### Unchanged (must not edit)

- `Sources/AgentStudio/Features/CommandBar/**/*` — real command bar components stay exactly as-is.
- `Sources/AgentStudio/App/Panes/WelcomeSidebarIllustration.swift` — Welcome 1 illustration is pixel-frozen.
- `Sources/AgentStudio/App/Commands/AppCommand.swift`, `AppShortcut.swift` — `⌘T` routing split already landed.
- `Sources/AgentStudio/Features/CommandBar/CommandBarDataSource+WorktreeRows.swift` — `New Empty Tab` injection already landed.

### Test files touched

- `Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift` — primary test surface for this plan.
- `Tests/AgentStudioTests/App/WorkspaceLauncherProjectorTests.swift` — keep existing non-regression tests green (`.noFolders`, `.scanning`, `.scanEmpty`). No new tests here.

---

## Task 1: Lock Welcome 1 Regression Baseline

**Files:**
- Test: `Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift`

Welcome 1 is pixel-identical before and after. Lock that contract at the token level BEFORE touching any tokens.

- [ ] **Step 1: Write the failing regression tests**

Replace the existing suite body with the following. The first two tests are pure pinning tests; they will pass immediately (they assert today's values). They must stay green at the end of every subsequent task.

```swift
import Testing

@testable import AgentStudio

@Suite("WorkspaceEmptyStateView")
struct WorkspaceEmptyStateViewTests {
    // MARK: - Welcome 1 regression locks (must never fail)

    @Test("welcome 1 illustration width is pinned")
    func welcome1IllustrationWidthIsPinned() {
        #expect(WelcomeSidebarIllustrationConstants.frameWidth == 300)
    }

    @Test("welcome 1 palette indices are pinned")
    func welcome1PaletteIndicesArePinned() {
        #expect(WelcomeSidebarIllustrationConstants.ghosttyPaletteIndex == 0)
        #expect(WelcomeSidebarIllustrationConstants.uvPaletteIndex == 3)
    }

    @Test("welcome tokens read by welcome 1 do not shift")
    func welcomeTokensReadByWelcome1DoNotShift() {
        #expect(AppStyles.Welcome.titleFontSize == 30)
        #expect(AppStyles.Welcome.bodyFontSize == AppStyles.General.Typography.textXl)
        #expect(AppStyles.Welcome.titleBodyGap == 8)
        #expect(AppStyles.Welcome.headerMaxWidth == 720)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail (symbols missing)**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
FAIL — 'WelcomeSidebarIllustrationConstants' type does not exist yet.
```

- [ ] **Step 3: Expose the Welcome 1 illustration constants**

In `Sources/AgentStudio/App/Panes/WelcomeSidebarIllustration.swift`, above the `WelcomeSidebarIllustration` struct, add a pinning enum. Do not change existing numeric values — the enum *reads* them so tests can reference them without touching the view body.

```swift
enum WelcomeSidebarIllustrationConstants {
    static let frameWidth: CGFloat = 300
    static let ghosttyPaletteIndex: Int = 0
    static let uvPaletteIndex: Int = 3
}
```

Then update the call sites in the file to read from the enum:

```swift
private let ghosttyColor = paletteColor(at: WelcomeSidebarIllustrationConstants.ghosttyPaletteIndex)
private let uvColor = paletteColor(at: WelcomeSidebarIllustrationConstants.uvPaletteIndex)
```

```swift
.frame(width: WelcomeSidebarIllustrationConstants.frameWidth, alignment: .leading)
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
PASS — 3 tests
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/WelcomeSidebarIllustration.swift \
        Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift
git commit -m "test(welcome): lock welcome 1 regression baseline"
```

---

## Task 2: Add New `AppStyles.Welcome` Tokens (No Renames Yet)

**Files:**
- Modify: `Sources/AgentStudio/Infrastructure/AppStyles.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift`

- [ ] **Step 1: Write the failing token tests**

Append to `WorkspaceEmptyStateViewTests`:

```swift
    // MARK: - New tokens from composition redesign

    @Test("hero row tokens exist with expected values")
    func heroRowTokensExistWithExpectedValues() {
        #expect(AppStyles.Welcome.heroRowCornerRadius == 18)
        #expect(AppStyles.Welcome.heroRowStrokeOpacity == AppStyles.General.Stroke.hover)
        #expect(AppStyles.Welcome.heroRowFillOpacity == AppStyles.General.Fill.subtle)
        #expect(AppStyles.Welcome.heroRowHoverFillOpacity == AppStyles.General.Fill.hover)
        #expect(AppStyles.Welcome.heroRowInnerHorizontalPadding == 24)
        #expect(AppStyles.Welcome.heroRowInnerVerticalPadding == 22)
        #expect(AppStyles.Welcome.heroRowChevronOpacity == 0.35)
    }

    @Test("scope row tokens exist with expected values")
    func scopeRowTokensExistWithExpectedValues() {
        #expect(AppStyles.Welcome.scopeRowVerticalSpacing == 12)
        #expect(AppStyles.Welcome.scopeRowTitleBodyGap == 2)
        #expect(AppStyles.Welcome.scopeRowBodySize == AppStyles.General.Typography.textSm)
        #expect(AppStyles.Welcome.scopeRowBodyOpacity == 0.50)
        #expect(AppStyles.Welcome.scopeRowBodyLineLimit == 2)
        #expect(AppStyles.Welcome.scopeRowCaretColumnWidth == AppStyles.CommandBar.Rows.iconSize)
    }

    @Test("responsive breakpoint tokens exist with expected values")
    func responsiveBreakpointTokensExistWithExpectedValues() {
        #expect(AppStyles.Welcome.launcherWideBreakpoint == 1400)
        #expect(AppStyles.Welcome.launcherNarrowBreakpoint == 900)
        #expect(AppStyles.Welcome.recentsColumnCountWide == 3)
        #expect(AppStyles.Welcome.recentsColumnCountNarrow == 1)
        #expect(AppStyles.Welcome.recentsColumnCount == 2)
    }

    @Test("section ordering gap tokens exist with expected values")
    func sectionOrderingGapTokensExistWithExpectedValues() {
        #expect(AppStyles.Welcome.recentsToHeroGap == 32)
        #expect(AppStyles.Welcome.heroToCommandPaletteGap == 28)
    }
```

- [ ] **Step 2: Run the tests to verify they fail (tokens missing)**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
FAIL — 'AppStyles.Welcome' has no member 'heroRowCornerRadius' (and sibling tokens).
```

- [ ] **Step 3: Add the new tokens to `AppStyles.Welcome`**

In `Sources/AgentStudio/Infrastructure/AppStyles.swift`, inside `enum Welcome`, append (do not delete anything, do not rename anything yet):

```swift
        // ⌘T hero row
        static let heroRowCornerRadius: CGFloat = 18
        static let heroRowStrokeOpacity: CGFloat = AppStyles.General.Stroke.hover
        static let heroRowFillOpacity: CGFloat = AppStyles.General.Fill.subtle
        static let heroRowHoverFillOpacity: CGFloat = AppStyles.General.Fill.hover
        static let heroRowInnerHorizontalPadding: CGFloat = 24
        static let heroRowInnerVerticalPadding: CGFloat = 22
        static let heroRowChevronOpacity: CGFloat = 0.35

        // ⌘P preview scope rows (launcher-only)
        static let scopeRowVerticalSpacing: CGFloat = 12
        static let scopeRowTitleBodyGap: CGFloat = 2
        static let scopeRowBodySize: CGFloat = AppStyles.General.Typography.textSm
        static let scopeRowBodyOpacity: CGFloat = 0.50
        static let scopeRowBodyLineLimit: Int = 2
        static let scopeRowCaretColumnWidth: CGFloat = AppStyles.CommandBar.Rows.iconSize

        // Responsive breakpoints
        static let launcherWideBreakpoint: CGFloat = 1400
        static let launcherNarrowBreakpoint: CGFloat = 900
        static let recentsColumnCountWide: Int = 3
        static let recentsColumnCountNarrow: Int = 1

        // Section ordering gaps
        static let recentsToHeroGap: CGFloat = 32
        static let heroToCommandPaletteGap: CGFloat = 28
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
PASS — 7 tests
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Infrastructure/AppStyles.swift \
        Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift
git commit -m "feat(styles): add launcher composition tokens to AppStyles.Welcome"
```

---

## Task 3: Rename `recentCardWidth` → `recentCardMinWidth` (Hard Cutover)

**Files:**
- Modify: `Sources/AgentStudio/Infrastructure/AppStyles.swift`
- Modify: `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift`

- [ ] **Step 1: Write the failing rename test**

Append to the test suite:

```swift
    @Test("recent card min width token exists at 260")
    func recentCardMinWidthTokenExistsAt260() {
        #expect(AppStyles.Welcome.recentCardMinWidth == 260)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
FAIL — 'AppStyles.Welcome' has no member 'recentCardMinWidth'.
```

- [ ] **Step 3: Rename the token**

In `Sources/AgentStudio/Infrastructure/AppStyles.swift`, change:

```swift
        static let recentCardWidth: CGFloat = 260
```

to:

```swift
        static let recentCardMinWidth: CGFloat = 260
```

Then grep for every consumer and update:

```bash
grep -rn "recentCardWidth" Sources/ Tests/
```

Expected call sites (all in `WorkspaceEmptyStateView.swift`):
- `WorkspaceEmptyStateLayout.recentSectionWidth(for:)`
- `WorkspaceEmptyStateLayout.recentGridColumns(for:)`
- `WorkspaceRecentPlaceholderCard`'s frame width
- `launcherBody(availableWidth:)` content-width math

Replace every occurrence with `recentCardMinWidth`. No alias is kept.

- [ ] **Step 4: Run the full launcher test suite to verify nothing broke**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
PASS — 8 tests
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/Infrastructure/AppStyles.swift \
        Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift \
        Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift
git commit -m "refactor(styles): rename recentCardWidth to recentCardMinWidth"
```

---

## Task 4: Typography Contract Tests

**Files:**
- Test: `Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift`

Lock concrete typography values so drift is a test failure.

- [ ] **Step 1: Write the failing typography contract tests**

Append:

```swift
    // MARK: - Typography contract (locked values, pixel-level hierarchy)

    @Test("typography tokens match the spec contract values")
    func typographyTokensMatchSpecContractValues() {
        #expect(AppStyles.Welcome.titleFontSize == 30)
        #expect(AppStyles.Welcome.bodyFontSize == 16)
        #expect(AppStyles.Welcome.sectionLabelFontSize == 15)
        #expect(AppStyles.Welcome.sectionLabelOpacity == 0.62)
        #expect(AppStyles.Welcome.shortcutTitleFontSize == 24)
        #expect(AppStyles.Welcome.shortcutBodyFontSize == AppStyles.Welcome.bodyFontSize)
        #expect(AppStyles.Welcome.shortcutKeyFontSize == 18)
    }

    @Test("typography hierarchy: shortcut title outranks general body text")
    func typographyHierarchyShortcutTitleOutranksGeneralBodyText() {
        // ⌘T / ⌘P titles must visually dominate body copy + recent card titles.
        #expect(AppStyles.Welcome.shortcutTitleFontSize > AppStyles.Welcome.bodyFontSize)
        #expect(AppStyles.Welcome.shortcutTitleFontSize > AppStyles.General.Typography.textBase)
    }

    @Test("typography hierarchy: page title outranks shortcut titles")
    func typographyHierarchyPageTitleOutranksShortcutTitles() {
        #expect(AppStyles.Welcome.titleFontSize > AppStyles.Welcome.shortcutTitleFontSize)
    }

    @Test("typography hierarchy: preview scope body stays below title")
    func typographyHierarchyPreviewScopeBodyStaysBelowTitle() {
        #expect(AppStyles.Welcome.scopeRowBodySize < AppStyles.General.Typography.textBase)
    }
```

- [ ] **Step 2: Run tests to verify they pass immediately**

These lock current values, so they should pass without code changes. If any fails, stop and investigate — a token has already drifted.

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
PASS — 12 tests
```

- [ ] **Step 3: Commit**

```bash
git add Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift
git commit -m "test(welcome): lock typography contract values and hierarchy"
```

---

## Task 5: Responsive `recentColumnCount(for:)`

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift`

Replace the fixed `recentColumnCount` with breakpoint logic.

- [ ] **Step 1: Write the failing breakpoint tests**

Replace the existing tests `launcherRecentGridStaysFixedAtTwoColumns` and `launcherRecentGridShowsAtMostThreeRows` with:

```swift
    // MARK: - Responsive recent grid

    @Test("recent column count is 3 at wide viewports")
    func recentColumnCountIs3AtWideViewports() {
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 1400) == 3)
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 1600) == 3)
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 2400) == 3)
    }

    @Test("recent column count is 2 at medium viewports")
    func recentColumnCountIs2AtMediumViewports() {
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 900) == 2)
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 1100) == 2)
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 1399) == 2)
    }

    @Test("recent column count is 1 at narrow viewports")
    func recentColumnCountIs1AtNarrowViewports() {
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 500) == 1)
        #expect(WorkspaceEmptyStateLayout.recentColumnCount(for: 899) == 1)
    }

    @Test("visible recent card limit stays at 6 across all viewports")
    func visibleRecentCardLimitStaysAt6AcrossAllViewports() {
        #expect(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: 500) == 6)
        #expect(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: 1100) == 6)
        #expect(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: 1600) == 6)
    }
```

Also delete the now-obsolete `launcherUsesWelcomeOneEchoSplitLayoutTokens` test — `launcherStartFastTitle` is being removed in this same task (step 3 below). If you see a reference to `launcherStartFastTitle` in any other test file, delete it there too in the same step.

- [ ] **Step 2: Run tests to verify they fail**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
FAIL — current recentColumnCount returns 2 at all widths.
```

- [ ] **Step 3: Implement breakpoint logic**

In `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift`, replace:

```swift
    static func recentColumnCount(for _: CGFloat) -> Int { AppStyles.Welcome.recentsColumnCount }
```

with:

```swift
    static func recentColumnCount(for availableWidth: CGFloat) -> Int {
        if availableWidth >= AppStyles.Welcome.launcherWideBreakpoint {
            return AppStyles.Welcome.recentsColumnCountWide
        }
        if availableWidth < AppStyles.Welcome.launcherNarrowBreakpoint {
            return AppStyles.Welcome.recentsColumnCountNarrow
        }
        return AppStyles.Welcome.recentsColumnCount
    }

    static let recentVisibleRowCount = 3

    static func visibleRecentCardLimit(for availableWidth: CGFloat) -> Int {
        // Always expose 6 visible; the grid reshapes columns/rows per breakpoint.
        return 6
    }
```

If `launcherStartFastTitle` still exists on the layout enum, delete that declaration line as well.

- [ ] **Step 4: Run tests to verify they pass**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
PASS — 16 tests
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift \
        Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift
git commit -m "feat(launcher): breakpoint-driven responsive recent column count"
```

---

## Task 6: Flexible Card Width Math

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift`

Cards must fill `contentColumnWidth = 1092` exactly at each column count, no orphan slack.

- [ ] **Step 1: Write the failing flexible-card-width test**

Append:

```swift
    // MARK: - Flexible card width

    @Test("content column width equals teaching + gap + preview")
    func contentColumnWidthEqualsTeachingPlusGapPlusPreview() {
        let expected =
            AppStyles.Welcome.teachingColumnWidth
            + AppStyles.Welcome.contentColumnsGap
            + AppStyles.Welcome.previewWidth
        #expect(WorkspaceEmptyStateLayout.contentColumnWidth == expected)
        #expect(WorkspaceEmptyStateLayout.contentColumnWidth == 1092)
    }

    @Test("recent card width fills content column at each breakpoint")
    func recentCardWidthFillsContentColumnAtEachBreakpoint() {
        let gap = AppStyles.Welcome.recentCardGap

        let wide3 = WorkspaceEmptyStateLayout.recentCardWidth(forColumns: 3)
        #expect(wide3 * 3 + gap * 2 == WorkspaceEmptyStateLayout.contentColumnWidth)

        let medium2 = WorkspaceEmptyStateLayout.recentCardWidth(forColumns: 2)
        #expect(medium2 * 2 + gap == WorkspaceEmptyStateLayout.contentColumnWidth)

        let narrow1 = WorkspaceEmptyStateLayout.recentCardWidth(forColumns: 1)
        #expect(narrow1 == WorkspaceEmptyStateLayout.contentColumnWidth)
    }

    @Test("recent card width never goes below min width")
    func recentCardWidthNeverGoesBelowMinWidth() {
        // At columns=8 the arithmetic would give <260; clamp to min.
        let clamped = WorkspaceEmptyStateLayout.recentCardWidth(forColumns: 8)
        #expect(clamped >= AppStyles.Welcome.recentCardMinWidth)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
FAIL — 'WorkspaceEmptyStateLayout' has no member 'contentColumnWidth' or 'recentCardWidth(forColumns:)'.
```

- [ ] **Step 3: Implement the layout math**

In `WorkspaceEmptyStateLayout` inside `WorkspaceEmptyStateView.swift`, add:

```swift
    static let contentColumnWidth: CGFloat =
        AppStyles.Welcome.teachingColumnWidth
        + AppStyles.Welcome.contentColumnsGap
        + AppStyles.Welcome.previewWidth

    static func recentCardWidth(forColumns columns: Int) -> CGFloat {
        let count = max(columns, 1)
        let totalGaps = AppStyles.Welcome.recentCardGap * CGFloat(count - 1)
        let raw = (contentColumnWidth - totalGaps) / CGFloat(count)
        return max(raw, AppStyles.Welcome.recentCardMinWidth)
    }
```

Update `recentGridColumns(for:)` to use the new flexible width:

```swift
    static func recentGridColumns(for availableWidth: CGFloat) -> [GridItem] {
        let count = recentColumnCount(for: availableWidth)
        let cardWidth = recentCardWidth(forColumns: count)
        return Array(
            repeating: GridItem(
                .fixed(cardWidth),
                spacing: AppStyles.Welcome.recentCardGap,
                alignment: .top
            ),
            count: count
        )
    }
```

Update `recentSectionWidth(for:)` (or remove if now unused — confirm via grep):

```swift
    static func recentSectionWidth(for _: CGFloat) -> CGFloat { contentColumnWidth }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
PASS — 19 tests
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift \
        Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift
git commit -m "feat(launcher): flexible recent card width fills content column exactly"
```

---

## Task 7: `LauncherPreviewScopeRow` Variant

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift`

Build the launcher-only row component. Keep `CommandBarResultRow` untouched.

- [ ] **Step 1: Write the failing existence test**

Append:

```swift
    // MARK: - Launcher preview scope row

    @Test("launcher preview scope row renders with title and body")
    @MainActor
    func launcherPreviewScopeRowRendersWithTitleAndBody() {
        let row = LauncherPreviewScopeRow(
            prefix: ">",
            title: "Commands",
            body: "Run actions — open, close, toggle",
            isSelected: true
        )
        // Type-level smoke test: the view compiles and exposes these properties.
        #expect(row.prefix == ">")
        #expect(row.title == "Commands")
        #expect(row.body == "Run actions — open, close, toggle")
        #expect(row.isSelected == true)
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
FAIL — unknown type 'LauncherPreviewScopeRow'.
```

- [ ] **Step 3: Implement `LauncherPreviewScopeRow`**

In `WorkspaceEmptyStateView.swift`, near the existing private `CommandBarEmbeddedPreview` struct, add (remove the `private` modifier so tests in the same module can reference it — `@testable import AgentStudio` reaches internal types):

```swift
struct LauncherPreviewScopeRow: View {
    let prefix: String
    let title: String
    let body: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: AppStyles.CommandBar.Rows.iconSpacing) {
            // Caret column
            Text(isSelected ? "▸" : " ")
                .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(
                    width: AppStyles.Welcome.scopeRowCaretColumnWidth,
                    alignment: .leading
                )

            VStack(alignment: .leading, spacing: AppStyles.Welcome.scopeRowTitleBodyGap) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(prefix)
                        .font(
                            .system(
                                size: AppStyles.General.Typography.textBase,
                                weight: .semibold,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(Color.primary.opacity(0.88))

                    Text(title)
                        .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.88))
                }

                Text(body)
                    .font(.system(size: AppStyles.Welcome.scopeRowBodySize))
                    .foregroundStyle(Color.primary.opacity(AppStyles.Welcome.scopeRowBodyOpacity))
                    .lineLimit(AppStyles.Welcome.scopeRowBodyLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)
        }
        .padding(.horizontal, AppStyles.CommandBar.Rows.horizontalPadding)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.CommandBar.Rows.selectedRowCornerRadius)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .padding(.horizontal, AppStyles.CommandBar.Rows.selectedRowHorizontalInset)
        )
        .contentShape(Rectangle())
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
PASS — 20 tests
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift \
        Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift
git commit -m "feat(launcher): add LauncherPreviewScopeRow variant for two-line scope bodies"
```

---

## Task 8: Swap Scope Rows In `CommandBarEmbeddedPreview`

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift`

Replace the three `CommandBarResultRow` instances in the preview with `LauncherPreviewScopeRow`. Keep the status strip, search-row mock, and footer unchanged.

- [ ] **Step 1: Write the failing content test**

Append:

```swift
    @Test("command bar embedded preview exposes three scope entries")
    @MainActor
    func commandBarEmbeddedPreviewExposesThreeScopeEntries() {
        let entries = CommandBarEmbeddedPreview.scopeEntries
        #expect(entries.count == 3)
        #expect(entries[0].prefix == ">")
        #expect(entries[0].title == "Commands")
        #expect(entries[0].body == "Run actions — open, close, toggle")
        #expect(entries[1].prefix == "$")
        #expect(entries[1].title == "Panes")
        #expect(entries[1].body == "Jump to any open tab or pane")
        #expect(entries[2].prefix == "#")
        #expect(entries[2].title == "Repos · Worktrees")
        #expect(entries[2].body == "Open a repo, switch a worktree, or start a new one")
    }
```

- [ ] **Step 2: Run test to verify it fails**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
FAIL — 'CommandBarEmbeddedPreview' has no member 'scopeEntries'.
```

- [ ] **Step 3: Rewrite `CommandBarEmbeddedPreview` to use the new row**

Drop the `private` modifier so the test can reach the static `scopeEntries`. Replace the `items: [CommandBarItem]` and the `ForEach` loop that rendered `CommandBarResultRow` with:

```swift
struct CommandBarEmbeddedPreview: View {
    struct ScopeEntry: Identifiable {
        let id: String
        let prefix: String
        let title: String
        let body: String
    }

    static let scopeEntries: [ScopeEntry] = [
        ScopeEntry(
            id: "preview-commands",
            prefix: ">",
            title: "Commands",
            body: "Run actions — open, close, toggle"
        ),
        ScopeEntry(
            id: "preview-panes",
            prefix: "$",
            title: "Panes",
            body: "Jump to any open tab or pane"
        ),
        ScopeEntry(
            id: "preview-repos",
            prefix: "#",
            title: "Repos · Worktrees",
            body: "Open a repo, switch a worktree, or start a new one"
        ),
    ]

    private let footerHints: [FooterHint] = [
        FooterHint(id: "enter", key: "↵", label: "Select"),
        FooterHint(id: "move", key: "↑↓", label: "Move", style: .plain),
        FooterHint(id: "dismiss", key: "esc", label: "Dismiss", style: .plain),
    ]

    var body: some View {
        VStack(spacing: 0) {
            CommandBarStatusStrip(mode: .normal, context: .empty)

            Divider()
                .opacity(AppStyles.CommandBar.Panel.rootDividerOpacity)

            HStack(spacing: AppStyles.Welcome.shortcutTextGap) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: AppStyles.General.Typography.textBase, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.35))
                    .frame(width: 16, height: 16)

                Text("Search or jump to…")
                    .font(.system(size: AppStyles.General.Typography.textBase))
                    .foregroundStyle(.primary.opacity(0.35))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: AppStyles.Welcome.previewSearchRowHeight)

            Divider()
                .opacity(AppStyles.CommandBar.Panel.nestedDividerOpacity)

            VStack(spacing: AppStyles.Welcome.scopeRowVerticalSpacing) {
                ForEach(Array(Self.scopeEntries.enumerated()), id: \.element.id) { index, entry in
                    LauncherPreviewScopeRow(
                        prefix: entry.prefix,
                        title: entry.title,
                        body: entry.body,
                        isSelected: index == 0
                    )
                }
            }
            .padding(.vertical, 8)

            Divider()
                .opacity(AppStyles.CommandBar.Panel.nestedDividerOpacity)

            CommandBarFooter(hints: footerHints)
        }
        .frame(width: AppStyles.Welcome.previewWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.Welcome.previewCornerRadius)
                .fill(Color(nsColor: AppStyles.Shell.TabBar.titlebarBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: AppStyles.Welcome.previewCornerRadius)
                        .stroke(Color.white.opacity(AppStyles.Welcome.cardStrokeOpacity), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppStyles.Welcome.previewCornerRadius))
    }
}
```

Delete the old `items: [CommandBarItem]` array entirely. It's no longer used.

- [ ] **Step 4: Run tests to verify they pass**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
PASS — 21 tests
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift \
        Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift
git commit -m "feat(launcher): enrich command palette preview with two-line scope bodies"
```

---

## Task 9: Rebuild `launcherBody` Composition

**Files:**
- Modify: `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift`
- Test: `Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift`

New order: Header → Recent → `⌘T` hero → `⌘P` section. No more `Start Fast` label, no more `⌘T` text row beside the preview. `⌘T` becomes a single hero block.

- [ ] **Step 1: Write the failing composition-contract tests**

Append:

```swift
    // MARK: - Launcher composition

    @Test("launcher hero row tokens produce a visually bordered block")
    func launcherHeroRowTokensProduceVisuallyBorderedBlock() {
        #expect(AppStyles.Welcome.heroRowCornerRadius > AppStyles.Welcome.shortcutRowHoverRadius)
        #expect(AppStyles.Welcome.heroRowStrokeOpacity > 0)
        #expect(AppStyles.Welcome.heroRowInnerVerticalPadding
                > AppStyles.Welcome.shortcutRowVerticalPadding)
    }

    @Test("launcher above-fold height budget fits 1240x820 viewport")
    func launcherAboveFoldHeightBudgetFits1240x820Viewport() {
        // Budget derived from the spec's height-budget table. If this regresses,
        // the launcher no longer meets the "recents first, no scroll" contract.
        let headerBlock = 80.0
        let recentRowHeight = 100.0
        let gap = AppStyles.Welcome.recentCardGap
        let sectionGap = AppStyles.Welcome.sectionToContentGap
        let recentsToHero = AppStyles.Welcome.recentsToHeroGap
        let heroHeight = AppStyles.Welcome.heroRowInnerVerticalPadding * 2 + 48

        let pageTop = AppStyles.Welcome.pageVerticalPadding
        let header = pageTop + headerBlock + AppStyles.Welcome.headerToContentGap
        let recentLabel = header + 30 + sectionGap
        let recentsEnd = recentLabel + recentRowHeight * 3 + gap * 2
        let heroEnd = recentsEnd + recentsToHero + heroHeight

        #expect(heroEnd <= 820)
    }

    @Test("launcher narrow breakpoint is below command-palette horizontal width")
    func launcherNarrowBreakpointIsBelowCommandPaletteHorizontalWidth() {
        // At availableWidth < narrowBreakpoint we stack ⌘P vertically.
        // The horizontal pair needs teachingColumnWidth + gap + previewWidth.
        let pairWidth =
            AppStyles.Welcome.teachingColumnWidth
            + AppStyles.Welcome.contentColumnsGap
            + AppStyles.Welcome.previewWidth
        #expect(AppStyles.Welcome.launcherNarrowBreakpoint < pairWidth)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
PASS on the three new contract tests (they derive from tokens) or FAIL
  if the budget math no longer fits. If any fail, the token values must be
  revisited before continuing.
```

(These tests pass against tokens, not rendered views — they lock contracts. If they pass green, proceed directly to step 3.)

- [ ] **Step 3: Rewrite `launcherBody(availableWidth:)`**

Replace the body and its helpers:

```swift
    private func launcherBody(availableWidth: CGFloat) -> some View {
        let columnCount = WorkspaceEmptyStateLayout.recentColumnCount(for: availableWidth)
        let visibleRecentCards = Array(
            model.recentCards.prefix(WorkspaceEmptyStateLayout.visibleRecentCardLimit(for: availableWidth))
        )
        let stacksVertically = availableWidth < AppStyles.Welcome.launcherNarrowBreakpoint

        return VStack(spacing: AppStyles.Welcome.headerToContentGap) {
            WorkspaceHomeHeader(
                title: "Your workspace",
                subtitle: "Jump back in, or start something new."
            )

            VStack(alignment: .leading, spacing: 0) {
                launcherRecentSection(
                    availableWidth: availableWidth,
                    columnCount: columnCount,
                    visibleRecentCards: visibleRecentCards
                )
                .padding(.bottom, AppStyles.Welcome.recentsToHeroGap)

                launcherHeroRow
                    .padding(.bottom, AppStyles.Welcome.heroToCommandPaletteGap)

                launcherCommandPaletteSection(stacksVertically: stacksVertically)
            }
            .frame(
                maxWidth: WorkspaceEmptyStateLayout.contentColumnWidth,
                alignment: .leading
            )
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var launcherHeroRow: some View {
        Button(action: { CommandDispatcher.shared.dispatch(.showCommandBarRepos) }) {
            HStack(alignment: .center, spacing: AppStyles.Welcome.shortcutTextGap) {
                Text("⌘T")
                    .font(
                        .system(
                            size: AppStyles.Welcome.shortcutKeyFontSize,
                            weight: .semibold,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(Color.accentColor)
                    .frame(width: AppStyles.Welcome.shortcutKeyColumnWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: AppStyles.Welcome.shortcutTitleBodyGap) {
                    Text("Start a new tab or worktree")
                        .font(.system(size: AppStyles.Welcome.shortcutTitleFontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Opens the # picker. New Empty Tab is always first.")
                        .font(.system(size: AppStyles.Welcome.shortcutBodyFontSize))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 16)

                Image(systemName: "chevron.right")
                    .font(.system(size: AppStyles.General.Typography.textLg, weight: .medium))
                    .foregroundStyle(.primary.opacity(AppStyles.Welcome.heroRowChevronOpacity))
            }
            .padding(.horizontal, AppStyles.Welcome.heroRowInnerHorizontalPadding)
            .padding(.vertical, AppStyles.Welcome.heroRowInnerVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppStyles.Welcome.heroRowCornerRadius)
                    .fill(Color.white.opacity(AppStyles.Welcome.heroRowFillOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppStyles.Welcome.heroRowCornerRadius)
                            .stroke(
                                Color.white.opacity(AppStyles.Welcome.heroRowStrokeOpacity),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: AppStyles.Welcome.heroRowCornerRadius))
    }

    @ViewBuilder
    private func launcherCommandPaletteSection(stacksVertically: Bool) -> some View {
        let teaching = launcherCommandPaletteTeaching
        let preview = CommandBarEmbeddedPreview()

        if stacksVertically {
            VStack(alignment: .leading, spacing: AppStyles.Welcome.previewTopGap) {
                teaching
                preview
            }
        } else {
            HStack(alignment: .top, spacing: AppStyles.Welcome.contentColumnsGap) {
                teaching
                    .frame(width: AppStyles.Welcome.teachingColumnWidth, alignment: .leading)
                preview
            }
        }
    }

    private var launcherCommandPaletteTeaching: some View {
        Button(action: { CommandDispatcher.shared.dispatch(.showCommandBarEverything) }) {
            VStack(alignment: .leading, spacing: AppStyles.Welcome.shortcutTitleBodyGap) {
                HStack(alignment: .firstTextBaseline, spacing: AppStyles.Welcome.shortcutTextGap) {
                    Text("⌘P")
                        .font(
                            .system(
                                size: AppStyles.Welcome.shortcutKeyFontSize,
                                weight: .semibold,
                                design: .monospaced
                            )
                        )
                        .foregroundStyle(Color.accentColor)
                        .frame(width: AppStyles.Welcome.shortcutKeyColumnWidth, alignment: .leading)

                    Text("Command palette")
                        .font(.system(size: AppStyles.Welcome.shortcutTitleFontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Text("Scope your search with a prefix.")
                    .font(.system(size: AppStyles.Welcome.shortcutBodyFontSize))
                    .foregroundStyle(.secondary)
                    .padding(.leading, AppStyles.Welcome.shortcutBodyLeadingInset)
            }
            .padding(.vertical, AppStyles.Welcome.shortcutRowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func launcherRecentSection(
        availableWidth: CGFloat,
        columnCount: Int,
        visibleRecentCards: [WorkspaceRecentCardModel]
    ) -> some View {
        VStack(alignment: .leading, spacing: AppStyles.Welcome.sectionToContentGap) {
            recentSectionHeader

            if visibleRecentCards.isEmpty {
                WorkspaceRecentPlaceholderCard()
                    .frame(width: WorkspaceEmptyStateLayout.recentCardWidth(forColumns: columnCount))
            } else {
                LazyVGrid(
                    columns: WorkspaceEmptyStateLayout.recentGridColumns(for: availableWidth),
                    alignment: .leading,
                    spacing: AppStyles.Welcome.recentCardGap
                ) {
                    ForEach(visibleRecentCards) { card in
                        WorkspaceRecentCardView(
                            card: card,
                            onOpen: { onOpenRecent(card.target) }
                        )
                    }
                }
                .frame(maxWidth: WorkspaceEmptyStateLayout.contentColumnWidth, alignment: .leading)
            }
        }
    }

    private var recentSectionHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Recent")
                .font(.system(size: AppStyles.Welcome.sectionLabelFontSize, weight: .semibold))
                .foregroundStyle(.primary.opacity(AppStyles.Welcome.sectionLabelOpacity))

            if model.showsOpenAll {
                Button(LocalActionSpec.openAllInTabs.actionSpec.label) {
                    onOpenAllRecent()
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Spacer(minLength: 0)
        }
    }
```

Delete the old helpers: `launcherCommandPaletteSection` (original VStack form), any remaining `LauncherShortcutAction` references for `⌘T` (keep `LauncherShortcutAction` itself only if `⌘P` teaching uses it — in the rewrite above `⌘P` teaching is inlined, so `LauncherShortcutAction` becomes dead code and should be deleted in the same pass).

- [ ] **Step 4: Run the full launcher test suite**

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceEmptyStateViewTests
```

Expected:

```text
PASS — 24 tests
```

Also re-run the projector suite to confirm non-regression:

```bash
SWIFT_BUILD_DIR=".build-agent-$(uuidgen | tr -dc 'a-z0-9' | head -c 8)" \
  swift test --build-path "$SWIFT_BUILD_DIR" --filter WorkspaceLauncherProjectorTests
```

Expected:

```text
PASS — all existing noFolders/scanning/scanEmpty tests
```

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift \
        Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift
git commit -m "feat(launcher): promote recents, hero-row cmd-T, paired cmd-P + preview"
```

---

## Task 10: Full Build + Test + Lint + Visual Verification

**Files:**
- Verify: every modified file above
- Verify: Peekaboo captures of Welcome 1 and the launcher

- [ ] **Step 1: Full build**

```bash
mise run build
```

Expected:

```text
Build complete! ... exit 0
```

- [ ] **Step 2: Full test suite**

```bash
mise run test
```

Expected:

```text
All included suites pass.
```

- [ ] **Step 3: Lint**

```bash
mise run lint
```

Expected:

```text
swift-format: OK
swiftlint: OK
architecture boundary checks passed
```

- [ ] **Step 4: Launch debug build and capture Peekaboo screenshots**

```bash
pkill -9 -f "AgentStudio" >/dev/null 2>&1 || true
.build/debug/AgentStudio &
sleep 2
PID=$(pgrep -f ".build/debug/AgentStudio")
peekaboo see --app "PID:$PID" --json --path /tmp/launcher-default.png
```

Resize the main window and repeat for each of:
- `1600×900` (wide — launcher should render 3-wide recent grid)
- `1240×820` (medium/target — launcher should render 2-wide × 3 rows, hero fully visible above fold)
- `950×820` (narrow — recents 2-wide still, ⌘P pair horizontal; just above narrow breakpoint)
- `850×820` (very narrow — recents 1-wide, ⌘P stacked vertically)

Save each capture to `/tmp/launcher-<mode>.png`.

Then toggle macOS appearance to light mode and capture again for each width (use `defaults write NSGlobalDomain AppleInterfaceStyle` or System Settings). Save to `/tmp/launcher-<mode>-light.png`.

- [ ] **Step 5: Capture Welcome 1 regression baseline**

Open a fresh profile (no workspace) so `.noFolders` renders, capture at `1240×820` in both dark and light:

```
/tmp/welcome1-dark.png
/tmp/welcome1-light.png
```

Compare against the original screenshots the user provided at the start of the session. They must be visually identical.

Manual acceptance checklist:

```text
✓ Welcome 1 sidebar illustration + "Welcome to AgentStudio" unchanged
✓ Welcome 1 "Choose a Folder to Scan…" button unchanged
✓ Launcher page title reads "Your workspace" / "Jump back in, or start something new."
✓ Recent section is directly below the header
✓ 6 recent cards visible above the fold at 1240×820
✓ ⌘T hero row is a single bordered block, full content-column-width
✓ Hero row chevron is right-aligned and muted
✓ ⌘P teaching text on left, embedded preview on right at ≥950px
✓ ⌘P preview scope rows have two-line bodies and proper breathing room
✓ Selected (first) scope row has accent background + ▸ caret
✓ At 850px wide: recents 1-wide, ⌘P stacked vertically
✓ Light mode: card borders / hero stroke visible (not washed out)
✓ Dark mode: hero row fill is subtle, not dominant
```

- [ ] **Step 6: Commit the captures or discard**

Screenshots live in `/tmp/` — do not commit them. If anything in the manual checklist fails, return to the failing task and fix before proceeding.

- [ ] **Step 7: Final summary commit (if any cleanup changes were needed)**

If steps 1–5 revealed fixes:

```bash
git add <fixed files>
git commit -m "fix(launcher): <specific issue>"
```

Otherwise there is no final commit — the work is complete.

---

## Self-Review

- Welcome 1 contract is checked by Task 1's regression tests and by manual Peekaboo diff in Task 10.
- Typography contract is locked at the token level in Task 4 and hierarchy is tested by comparisons.
- Height budget is locked by a numeric test in Task 9 using the same derivations the spec used.
- Flexible card widths filling `contentColumnWidth` exactly are tested in Task 6.
- The `LauncherPreviewScopeRow` lives in `WorkspaceEmptyStateView.swift` and uses only public `AppStyles.Welcome` tokens; real `CommandBarResultRow` stays unchanged (Task 7).
- The ⌘T hero row is the single entry point for "Start fast"; the old `Start Fast` section label and standalone `⌘T` row helper are removed (Task 9).
- `⌘P` narrow-width fallback is implemented and has a token-level guardrail test in Task 9.
- All existing non-regression tests (`WorkspaceLauncherProjectorTests`) are re-run in Task 9.
- Final build + lint + test + Peekaboo are the gate in Task 10.
