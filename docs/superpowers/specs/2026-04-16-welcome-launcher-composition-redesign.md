# Welcome Launcher Composition Redesign — Spec

> Status note: This document is historical design context, not the current
> implementation contract. The shipped launcher in
> `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift` now uses a
> single-column `VStack` for recent worktrees rather than the responsive
> multi-column grid described below. Treat the current code and
> `AppStyles.Welcome` as the source of truth for the live layout.

## Hard Invariant

**Welcome 1 is pixel-identical before and after.**

"Welcome 1" is the `.noFolders` state of `WorkspaceEmptyStateView`: the centered
horizontal composition with `WelcomeSidebarIllustration` on the left and the
AgentStudio logo + title + "Choose a Folder to Scan…" CTA on the right. It must
not move, resize, recolor, or rewrap. Shared tokens in `AppStyles.Welcome` that
Welcome 1 reads today may not be re-valued in a way that changes its rendering.
If a new composition need conflicts with this, we add a new token rather than
mutate an existing one.

The `.scanning` and `.scanEmpty` states are also out of scope for visual change
in this redesign. They share the file and must keep rendering.

## Why This Spec Exists

The existing plan at
`docs/superpowers/plans/2026-04-16-welcome-launcher-commandbar-redesign.md`
shipped three of its four ideas correctly onto this branch:

- `AppStyles.Welcome` namespace exists and is consumed.
- `CommandBarEmbeddedPreview` uses real `CommandBarStatusStrip`,
  `CommandBarResultRow`, and `CommandBarFooter` components with mock data.
- `⌘T` routing is split: keyboard + launcher row → `.showCommandBarRepos`; File
  menu + synthetic picker row → `.newTab`.

The fourth idea — the launcher **composition** — landed as an unbalanced
three-column layout with a lonely right rail and weak visual hierarchy. This
spec replaces that composition. It does **not** revisit the three ideas above,
which stay as-is.

## Goal

Redesign the `.launcher` state of `WorkspaceEmptyStateView` so recurring users
see their recent work first and new users still find teaching content below.
Keep everything in the Welcome 1 visual language, owned by `AppStyles.Welcome`.

## Target Composition

```
┌──────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│                          Your workspace                                  │
│                 Jump back in, or start something new.                    │
│                                                                          │
│  Recent ─────────                                                        │
│                                                                          │
│  ┌────────────────────────────┐  ┌────────────────────────────┐          │
│  │ ★  agent-studio            │  │ ◆  agent-studio.fix-welcome│          │
│  │    main                    │  │    fix/welcome             │          │
│  │    +0 -0  ↑0↓0  ⤴0  🔔0   │  │    +24 -8  ↑0↓0  ⤴1  🔔0  │          │
│  └────────────────────────────┘  └────────────────────────────┘          │
│                                                                          │
│  ┌────────────────────────────┐  ┌────────────────────────────┐          │
│  │ ★  ghostty                 │  │ ◆  ghostty.gpu-renderer    │          │
│  │    main                    │  │    feature/gpu-renderer    │          │
│  │    +0 -0  ↑0↓0  ⤴2  🔔0   │  │   ● +86 -12 ↑3↓0  ⤴1  🔔0 │          │
│  └────────────────────────────┘  └────────────────────────────┘          │
│                                                                          │
│  ┌────────────────────────────┐  ┌────────────────────────────┐          │
│  │ ◆  ghostty.fix-keybinds    │  │ ★  uv                      │          │
│  │    fix/keybind-passthrough │  │    main                    │          │
│  │    +24 -8  ↑0↓0  ⤴1  🔔0  │  │   ● +5 -2  ↑0↓3  ⤴0  🔔0  │          │
│  └────────────────────────────┘  └────────────────────────────┘          │
│                                                                          │
│                                                                          │
│  ╔════════════════════════════════════════════════════════════════════╗  │
│  ║   ⌘T    Start a new tab or worktree                            ▸   ║  │
│  ║         Opens the # picker. New Empty Tab is always first.         ║  │
│  ╚════════════════════════════════════════════════════════════════════╝  │
│                                                                          │
│                                                                          │
│   ⌘P   Command palette              ╭──────────────────────────────╮     │
│        Scope your search            │ ⌕  Search or jump to…         │     │
│        with a prefix.  →            ├──────────────────────────────┤     │
│                                     │                               │     │
│                                     │  ▸  >   Commands              │     │
│                                     │         Run actions — open,   │     │
│                                     │         close, toggle         │     │
│                                     │                               │     │
│                                     │     $   Panes                 │     │
│                                     │         Jump to any open      │     │
│                                     │         tab or pane           │     │
│                                     │                               │     │
│                                     │     #   Repos · Worktrees     │     │
│                                     │         Open a repo, switch   │     │
│                                     │         a worktree, or        │     │
│                                     │         start a new one       │     │
│                                     ├──────────────────────────────┤     │
│                                     │ ↵ Select  ↑↓ Move  ⎋ Dismiss  │     │
│                                     ╰──────────────────────────────╯     │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

## Design Principles

1. **Recurring user first.** Recents sits above teaching so returning users
   reach their work without scrolling on typical window heights.
2. **Teaching second, not absent.** `⌘T` hero row and `⌘P` + preview stay on
   the page for new users and as muscle-memory reminders.
3. **Shared visual language.** Everything reads from `AppStyles.Welcome`. No
   hardcoded literals. Welcome 1 tokens untouched.
4. **Real chrome over fake illustration.** The `⌘P` preview is the real
   `CommandBarStatusStrip` / `CommandBarResultRow` / `CommandBarFooter`, just
   rendered with mock data (already landed — reuse).
5. **Balance the page.** No orphan rails. The recents grid fills the content
   column; teaching sections span the same column width.

### Content column width

One shared horizontal measure anchors every section below the header:

```
contentColumnWidth = teachingColumnWidth + contentColumnsGap + previewWidth
                   = 520 + 72 + 500
                   = 1092 px
```

Every launcher section spans this same measure:

```
┌─── contentColumnWidth (1092) ───────────────────────────────────────┐
│                                                                     │
│  recents grid  ◀── columns × cardWidth + gaps fill this width ──▶   │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ⌘T hero row  ◀── single box fills full width ──────────────▶       │
│                                                                     │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ⌘P teaching col (520) ◀── gap (72) ──▶  ⌘P preview col (500)       │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

- Recents grid fills `contentColumnWidth` **exactly**. Cards are flexible-
  width, not fixed. Card width at runtime:
  ```
  cardWidth(n) = (contentColumnWidth − recentCardGap · (n − 1)) / n
  ```
  - wide (n=3):   (1092 − 40) / 3 = 350.67 → ~350 px per card
  - medium (n=2): (1092 − 20) / 2 = 536 px per card
  - narrow (n=1): 1092 px per card (at the breakpoint; at smaller viewports
    the card shrinks with the column)

- `⌘T` hero row fills `contentColumnWidth`.
- `⌘P` section fills `contentColumnWidth` (`teachingColumnWidth` on the left,
  `previewWidth` on the right, separated by `contentColumnsGap`).

This is expressed as a computed static on `WorkspaceEmptyStateLayout`
(existing file), not as a new `AppStyles.Welcome` token — it is derived
geometry, not a visual value.

### Role change for `recentCardWidth`

`recentCardWidth = 260` in `AppStyles.Welcome` stops being a fixed card
geometry. Its new role is a **minimum readable card width**. At very small
viewports where the flexible card would otherwise shrink below this minimum,
the grid stops subdividing columns (i.e. column count drops one level).
Rename the token to `recentCardMinWidth` for clarity in the same change.
The old name is removed — no compatibility alias (hard cutover, per repo
convention).

## Structure

### 1. Header (centered, unchanged behavior)

```
Your workspace
Jump back in, or start something new.
```

Uses the existing `WorkspaceHomeHeader` helper. Same tokens as today
(`titleFontSize`, `bodyFontSize`, `titleBodyGap`, `headerMaxWidth`).

### 2. Recent section (promoted to position 2, above teaching)

- Section label `Recent` + optional "Open all in tabs" chip when
  `model.showsOpenAll` is true.

  Chip style (explicit):
  - SwiftUI `Button` with `.buttonStyle(.bordered)`, `.controlSize(.regular)`.
  - Label from `LocalActionSpec.openAllInTabs.actionSpec.label` (existing).
  - Placed in the same horizontal row as the `Recent` label via
    `HStack(alignment: .center, spacing: 16)`, trailing the label.
  - Does not wrap under the label. At narrow viewport
    (`availableWidth < launcherNarrowBreakpoint`) it stays on the same row;
    if space is insufficient, it truncates the label (not the chip) via
    `minLength` on the spacer between them.
  - When `model.showsOpenAll == false`, the chip is not rendered at all.
- Grid:
  - **Wide window** (`availableWidth ≥ launcherWideBreakpoint`): 3 columns × 2
    rows = 6 visible.
  - **Medium window** (`launcherNarrowBreakpoint ≤ availableWidth <
    launcherWideBreakpoint`): 2 columns × 3 rows = 6 visible.
  - **Narrow window** (`availableWidth < launcherNarrowBreakpoint`): 1 column,
    up to 6 visible, user scrolls past.

  Responsive shape at each breakpoint:

  ```
  wide  (≥ 1400 px)              medium (900 – 1400)       narrow (< 900)
  ┌─────┐ ┌─────┐ ┌─────┐        ┌──────┐ ┌──────┐         ┌───────────┐
  │ r1  │ │ r2  │ │ r3  │        │  r1  │ │  r2  │         │    r1     │
  └─────┘ └─────┘ └─────┘        └──────┘ └──────┘         └───────────┘
  ┌─────┐ ┌─────┐ ┌─────┐        ┌──────┐ ┌──────┐         ┌───────────┐
  │ r4  │ │ r5  │ │ r6  │        │  r3  │ │  r4  │         │    r2     │
  └─────┘ └─────┘ └─────┘        └──────┘ └──────┘         └───────────┘
                                 ┌──────┐ ┌──────┐         ┌───────────┐
                                 │  r5  │ │  r6  │         │    r3     │
                                 └──────┘ └──────┘         └───────────┘
                                                           (r4, r5, r6
                                                            scroll below)
  ```
- Each card renders `SidebarWorktreeRowContent` (existing). Card content:
  - Line 1: `★` (main worktree) or `◆` (feature worktree) + worktree title
    (`repo` for main, `repo.suffix` for feature).
  - Line 2: branch name.
  - Line 3: git status chips (`+added -deleted`, sync arrows, PR count,
    notification count).

  Anatomy:

  ```
  ┌──────────────────────────────────────┐
  │  ◆    agent-studio.fix-welcome       │  ◀── icon + repo[.worktree]
  │       fix/welcome                    │  ◀── branch
  │       +24 -8  ↑0↓0  ⤴1  🔔0         │  ◀── status chips
  └──────────────────────────────────────┘
       ▲    ▲
       │    └── worktree title
       └────── ★ main  /  ◆ feature
  ```
- Empty state (no recents): single `WorkspaceRecentPlaceholderCard` dashed-
  border card in position 1 (existing behavior).
- Overflow: when more than 6 recents exist, show first 6 and rely on the
  existing "Open all in tabs" button in the section header.

### 3. `⌘T` hero row (position 3)

- Full content-column-width rounded rectangle, heavier border than cards
  (single stroke, `heroRowStrokeOpacity`). Not double-border; reserve that
  treatment for future emphasis.
- Contents: `⌘T` key, title `Start a new tab or worktree`, body `Opens the #
  picker. New Empty Tab is always first.`, trailing chevron `▸`.
- Click → dispatches `.showCommandBarRepos` (already the current binding).
- Hover → subtle fill (`interactiveHoverOpacity`).
- No separate "Start Fast" section label. The hero row is the start-fast UI.

### 4. `⌘P` section (position 4)

- Horizontal layout: teaching column on the left, preview on the right,
  aligned tops. Same column widths as today (`teachingColumnWidth`,
  `previewWidth`, `contentColumnsGap`).
- **Narrow-width fallback:** when
  `availableWidth < launcherNarrowBreakpoint`, the horizontal pair collapses
  to a `VStack`: teaching column on top, preview below at its full
  `previewWidth`. Same content, stacked. This prevents the pair from
  clipping the right edge at viewports below ~1012 px.
- **Teaching column (left):** `⌘P` + title `Command palette` + one-line body
  `Scope your search with a prefix. →`. Clickable same as today (dispatches
  `.showCommandBarEverything`).
- **Preview (right):** existing `CommandBarEmbeddedPreview`, but each scope
  result row gains a richer body line explaining what the scope does. See
  "Preview row enrichment" below.

#### Preview row enrichment — launcher-only variant

The real `CommandBarResultRow` renders title + subtitle **inline in an HStack**
at a fixed `rowHeight = 36pt` with `lineLimit(1)` on both. That layout cannot
render a two-line explanation without breaking real-modal density. Attempting
to loosen it via `lineLimit(2)` on the shared component is out of scope — the
real modal must stay unchanged.

Resolution: the launcher preview uses a **separate row view** that lives only
in `WorkspaceEmptyStateView.swift`:

```swift
private struct LauncherPreviewScopeRow: View {
    let prefix: String
    let title: String
    let body: String
    let isSelected: Bool
}
```

Layout:
- Outer `HStack(alignment: .top)`.
- Left: caret column (`▸` for the selected row, empty for the rest) at the
  same width as `CommandBarResultRow`'s icon column.
- Middle: `VStack(alignment: .leading, spacing: scopeRowTitleBodyGap)`:
  - Line 1: `prefix` in monospaced + `title` in medium weight.
  - Line 2: `body` at `scopeRowBodySize` / secondary opacity, wrapping up to
    two lines with `lineLimit(2)`.
- Selected-row background: accent fill at 15% opacity, same treatment as
  `CommandBarResultRow`'s selected state.

Scope content:

| Prefix | Title              | Body                                          |
|--------|--------------------|-----------------------------------------------|
| `>`    | Commands           | Run actions — open, close, toggle             |
| `$`    | Panes              | Jump to any open tab or pane                  |
| `#`    | Repos · Worktrees  | Open a repo, switch a worktree, or start new  |

Rows are stacked in a `VStack(spacing: scopeRowVerticalSpacing)` inside the
preview between the search-row divider and the footer divider.

`CommandBarStatusStrip`, `CommandBarFooter`, and the search-row mock in
`CommandBarEmbeddedPreview` continue to use the real components unchanged.

### Non-launcher states

`.noFolders`, `.scanning`, `.scanEmpty` remain visually and structurally
unchanged. Any new `AppStyles.Welcome` token added by this redesign is
launcher-only and cannot be consumed by these states.

## Typography Contract

The token names below lock to **these concrete values**. Changing a value
counts as a Welcome-1 visual change and is out of scope for this spec. Tests
assert the values at the token level.

| Role                          | Size | Weight     | Opacity | Token                           |
|-------------------------------|-----:|------------|--------:|---------------------------------|
| Page title (`Your workspace`) |   30 | `.semibold`|    1.00 | `titleFontSize`                 |
| Page subtitle                 |   16 | `.regular` |    .secondary | `bodyFontSize` (= `textXl`) |
| Section label (`Recent`)      |   15 | `.semibold`|    0.62 | `sectionLabelFontSize`, `sectionLabelOpacity` |
| ⌘T / ⌘P title                 |   24 | `.semibold`|    1.00 | `shortcutTitleFontSize`         |
| ⌘T / ⌘P body                  |   16 | `.regular` |    .secondary | `shortcutBodyFontSize` (= `bodyFontSize`) |
| ⌘T / ⌘P key (`⌘T`, `⌘P`)      |   18 | `.semibold` monospaced | accent | `shortcutKeyFontSize` |
| Recent card title             |   13 | `.medium`  |    .primary | `General.Typography.textBase` |
| Recent card branch            |   12 | `.regular` |    .secondary | `General.Typography.textSm` |
| Preview scope title           |   13 | `.medium`  |    .primary | matches `CommandBarResultRow` |
| Preview scope body            |   12 | `.regular` |    0.50 | new `scopeRowBodySize` |

Hierarchy rules:

- Page title is visually heaviest.
- `⌘T` / `⌘P` titles are the second heaviest (24/semibold).
- Section labels read as muted capitals-like headers (15/semibold @ 62%).
- Body and card titles fall behind at 13–16 / regular–medium.

If a reviewer sees the rendered page and the `⌘T` / `⌘P` titles do not read
heavier than `Recent` card titles, the implementation is wrong even if the
tokens match.

## AppStyles.Welcome Tokens

All new values go in `AppStyles.Welcome`. No new values outside that
namespace. No hardcoded literals in `WorkspaceEmptyStateView.swift`.

### New

```swift
// ⌘T hero row
static let heroRowCornerRadius: CGFloat = 18
static let heroRowStrokeOpacity: CGFloat = AppStyles.General.Stroke.hover
static let heroRowFillOpacity: CGFloat = AppStyles.General.Fill.subtle
static let heroRowHoverFillOpacity: CGFloat = AppStyles.General.Fill.hover
static let heroRowInnerHorizontalPadding: CGFloat = 24
static let heroRowInnerVerticalPadding: CGFloat = 22
static let heroRowChevronOpacity: CGFloat = 0.35

// ⌘P preview scope rows (launcher-only enrichment, used by LauncherPreviewScopeRow)
static let scopeRowVerticalSpacing: CGFloat = 12
static let scopeRowTitleBodyGap: CGFloat = 2
static let scopeRowBodySize: CGFloat = AppStyles.General.Typography.textSm
static let scopeRowBodyOpacity: CGFloat = 0.50
static let scopeRowBodyLineLimit: Int = 2
static let scopeRowCaretColumnWidth: CGFloat = AppStyles.CommandBar.Rows.iconSize

// Responsive breakpoints (driven by availableWidth inside the ScrollView)
static let launcherWideBreakpoint: CGFloat = 1400
static let launcherNarrowBreakpoint: CGFloat = 900
static let recentsColumnCountWide: Int = 3
static let recentsColumnCountNarrow: Int = 1

// Section ordering gaps (recents block → hero row → ⌘P section)
static let recentsToHeroGap: CGFloat = 32
static let heroToCommandPaletteGap: CGFloat = 28
```

### Unchanged (reused as-is)

`pageHorizontalPadding`, `pageVerticalPadding`, `headerToContentGap`,
`contentColumnsGap`, `headerMaxWidth`, `titleFontSize`, `bodyFontSize`,
`titleBodyGap`, `sectionLabelFontSize`, `sectionLabelOpacity`,
`sectionToContentGap`, `shortcutTitleFontSize`, `shortcutBodyFontSize`,
`shortcutKeyFontSize`, `shortcutKeyColumnWidth`, `shortcutTextGap`,
`shortcutTitleBodyGap`, `shortcutRowHorizontalPadding`,
`shortcutRowVerticalPadding`, `shortcutRowHoverRadius`,
`shortcutBodyLeadingInset`, `teachingColumnWidth`, `recentsColumnWidth`,
`recentCardGap`, `recentsColumnCount` (renamed role — see note),
`previewWidth`, `previewCornerRadius`, `previewStatusRowHeight`,
`previewSearchRowHeight`, `previewResultRowHeight`, `previewFooterHeight`,
`cardFillOpacity`, `cardStrokeOpacity`, `cardHoverOpacity`,
`interactiveHoverOpacity`.

### Renamed

- `recentCardWidth` → `recentCardMinWidth` (value `260` unchanged; role shift
  from fixed card geometry to minimum card width). All consumers update in
  the same PR. No alias remains.

### Token rename / role shift

- `recentsColumnCount` (existing, value `2`) becomes the **default / medium**
  column count. The new `recentsColumnCountWide` and `recentsColumnCountNarrow`
  cover the outer breakpoints. The default-case value stays `2` so Welcome 1's
  rendering of this token (if it referenced it, which it doesn't) stays
  identical.

## Layout Responsibility

`WorkspaceEmptyStateLayout` owns derived geometry. It gets one new function:

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
```

`recentGridColumns(for:)`, `recentSectionWidth(for:)`, and
`visibleRecentCardLimit(for:)` stay the same shape but consume the new
responsive column count.

## Target Viewport

The design is tuned for a **default 14" MacBook Pro window**:

```
target viewport
├── width  : 1240 px  (inside the app window, post-sidebar)
└── height :  820 px  (pane-area height, post-title/tab bar)
```

### Height budget at target viewport

```
┌─────────────────────────────────────────┬──────┬──────┐
│ Element                                 │  Δ   │  y   │
├─────────────────────────────────────────┼──────┼──────┤
│ pageVerticalPadding (top)               │  48  │   48 │
│ header (title + subtitle + gap)         │  80  │  128 │
│ headerToContentGap                      │  40  │  168 │
│ Recent section label                    │  30  │  198 │
│ sectionToContentGap                     │  22  │  220 │
│ recent row 1                            │ 100  │  320 │
│ recentCardGap                           │  20  │  340 │
│ recent row 2                            │ 100  │  440 │
│ recentCardGap                           │  20  │  460 │
│ recent row 3                            │ 100  │  560 │
│ recentsToHeroGap                        │  32  │  592 │
│ ⌘T hero row                             │  92  │  684 │   ◀── fold at 820
│ heroToCommandPaletteGap                 │  28  │  712 │
│ ⌘P section (teaching col vs preview)    │ 340  │ 1052 │
│ pageVerticalPadding (bottom)            │  48  │ 1100 │
└─────────────────────────────────────────┴──────┴──────┘
```

### Contract

At 1240 × 820 viewport, the following **must** be visible without scrolling:

1. Page title + subtitle.
2. All 6 recent cards (3 rows × 2 columns, or 2 rows × 3 columns at wider
   viewports).
3. The full `⌘T` hero row.

The `⌘P` section is permitted to begin below the fold — returning users are
optimized for recents, new users scroll to discover `⌘P`.

This is testable in the view layer: a sized preview at 1240×820 with a full 6
cards + hero must return an intrinsic-content height ≤ 820 px for the
above-fold stack.

## Scroll Behavior

- Keep `ScrollView(.vertical, showsIndicators: false)` — same as today.
- Launcher content may legitimately overflow on short windows. That's fine;
  the user can two-finger scroll. We do not add a scroll indicator, nor a
  gradient fade-hint, in this redesign. (Either can be considered later as a
  separate polish task.)
- Overlay scroll bars (when enabled in System Settings → "Always show scroll
  bars") sit inside the `pageHorizontalPadding` gutter and do not overlap any
  card.

## File Changes

### Modify

- `Sources/AgentStudio/Infrastructure/AppStyles.swift` — add the new tokens
  listed above to `AppStyles.Welcome`. Do not modify existing token values.
- `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift` — rewrite
  `launcherBody(availableWidth:)` to the new composition: header → recents →
  hero row → `⌘P` section. Enrich `CommandBarEmbeddedPreview` subtitles per
  the table above and adjust its row vertical spacing to the new token.
- `Sources/AgentStudio/App/Panes/WorkspaceEmptyStateView.swift` —
  `WorkspaceEmptyStateLayout.recentColumnCount(for:)` implements breakpoints.

### Unchanged (no edits)

- `.noFolders`, `.scanning`, `.scanEmpty` bodies.
- `WelcomeSidebarIllustration.swift` (Welcome 1 illustration).
- `Sources/AgentStudio/App/Commands/*` (routing already correct).
- `Sources/AgentStudio/Features/CommandBar/*` (components reused as-is).

### Test files

- `Tests/AgentStudioTests/App/WorkspaceEmptyStateViewTests.swift` — add:
  - Token existence + default values for new `AppStyles.Welcome` fields.
  - `WorkspaceEmptyStateLayout.recentColumnCount(for:)` breakpoint behavior at
    three widths (narrow, medium, wide).
  - Regression: `WelcomeSidebarIllustration` constants unchanged (snapshot of
    illustration width, spacing, and palette indices).
- `Tests/AgentStudioTests/App/WorkspaceLauncherProjectorTests.swift` — keep
  existing non-regression tests for `.noFolders`, `.scanning`, `.scanEmpty`.

## Acceptance Criteria

1. Welcome 1 (`.noFolders`) renders pixel-identically before and after on both
   dark and light mode at standard window widths. Verified by Peekaboo.
2. `.scanning` and `.scanEmpty` render unchanged.
3. Launcher (`.launcher`) state:
   - Recents appear directly below the header, above the hero row.
   - Recents grid fills `contentColumnWidth` exactly at each column count
     (no orphan slack to the right).
   - `⌘T` row is a bordered hero block, full-width of the content column.
   - `⌘P` text and preview are horizontally paired at
     `availableWidth ≥ launcherNarrowBreakpoint`; stacked vertically below.
   - Preview uses `LauncherPreviewScopeRow` (launcher-only); real
     `CommandBarResultRow` is unmodified.
   - Responsive column counts match the breakpoint table.
4. **Typography contract.** All values in the typography table match at the
   token level and render in the hierarchy stated. Tested via
   `#expect` on `AppStyles.Welcome` values and a view-structure assertion
   that `shortcutTitleFontSize > General.Typography.textBase` (preview scope
   title font).
5. **Height budget contract.** At 1240×820 viewport, the above-fold stack
   (header → recents → `⌘T` hero) returns intrinsic height ≤ 820 px.
   Asserted via a `ViewThatFits`-style measurement test in
   `WorkspaceEmptyStateViewTests`.
6. All existing tests green. New tests green.
7. `mise run lint` passes with zero errors.
8. Peekaboo visual checks captured for:
   - Welcome 1 before/after (must be identical).
   - Launcher at wide (1600), medium (1240 target), narrow (950) widths.
   - Launcher in dark and light mode.

## Non-goals

- Redesigning Welcome 1.
- Changing the real Command Bar modal.
- Changing `⌘T` / `⌘P` keyboard routing.
- Changing the synthetic "New Empty Tab" picker row.
- Changing the sidebar, tab bar, or any other pane.
- Introducing new features to the launcher beyond composition (e.g. no
  starred pins, no search-in-launcher, no inline worktree creation).
