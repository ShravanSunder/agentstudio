# Welcome Launcher Composition Redesign — Spec

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

- Recents grid fills `contentColumnWidth` (card widths are computed so the
  grid spans this exact measure at each column count).
- `⌘T` hero row fills `contentColumnWidth`.
- `⌘P` section fills `contentColumnWidth` (`teachingColumnWidth` on the left,
  `previewWidth` on the right, separated by `contentColumnsGap`).

This is expressed as a computed static on `WorkspaceEmptyStateLayout`
(existing file), not as a new `AppStyles.Welcome` token — it is derived
geometry, not a visual value.

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
  `model.showsOpenAll` is true (existing behavior).
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
- **Teaching column (left):** `⌘P` + title `Command palette` + one-line body
  `Scope your search with a prefix. →`. Clickable same as today (dispatches
  `.showCommandBarEverything`).
- **Preview (right):** existing `CommandBarEmbeddedPreview`, but each scope
  result row gains a richer body line explaining what the scope does. See
  "Preview row enrichment" below.

#### Preview row enrichment

Today's mock rows show only the scope name + one-line subtitle. Enriched rows
keep the same `CommandBarResultRow` component with its existing subtitle slot,
but the mock-preview subtitle is lengthened from a short label to an actual
explanation, wrapped to two lines:

| Prefix | Title              | Subtitle (new)                                |
|--------|--------------------|-----------------------------------------------|
| `>`    | Commands           | Run actions — open, close, toggle             |
| `$`    | Panes              | Jump to any open tab or pane                  |
| `#`    | Repos · Worktrees  | Open a repo, switch a worktree, or start new  |

The result rows get a slight vertical spacing increase between rows in the
preview `VStack` (`scopeRowVerticalSpacing`) so the two-line subtitle has
breathing room. Inside the real command bar modal, rows stay at their current
density — the enrichment is only applied in the launcher preview variant.

#### CommandBarResultRow subtitle wrapping

Open item to verify during implementation: `CommandBarResultRow` must accept a
two-line subtitle (soft wrap on natural width) without truncating. If it
currently truncates to a single line, the minimal fix is to allow the subtitle
`Text` to wrap with `lineLimit(2)`. This is an additive change to the row
component and must not alter the real command bar modal's behavior (the modal
passes short subtitles that still fit on one line).

### Non-launcher states

`.noFolders`, `.scanning`, `.scanEmpty` remain visually and structurally
unchanged. Any new `AppStyles.Welcome` token added by this redesign is
launcher-only and cannot be consumed by these states.

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

// ⌘P preview scope rows (launcher-only enrichment)
static let scopeRowVerticalSpacing: CGFloat = 12
static let scopeRowSubtitleLineSpacing: CGFloat = 2

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
`recentCardWidth`, `recentCardGap`, `recentsColumnCount` (renamed role — see
note), `previewWidth`, `previewCornerRadius`, `previewStatusRowHeight`,
`previewSearchRowHeight`, `previewResultRowHeight`, `previewFooterHeight`,
`cardFillOpacity`, `cardStrokeOpacity`, `cardHoverOpacity`,
`interactiveHoverOpacity`.

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
   - `⌘T` row is a bordered hero block, full-width of the content column.
   - `⌘P` text and preview are horizontally paired; preview shows enriched
     two-line scope subtitles.
   - Responsive column counts match the breakpoint table.
4. All existing tests green. New tests green.
5. `mise run lint` passes with zero errors.
6. Peekaboo visual checks captured for:
   - Welcome 1 before/after (must be identical).
   - Launcher at wide (≥ 1400), medium (1100), narrow (850) widths.
   - Launcher in dark and light mode.

## Non-goals

- Redesigning Welcome 1.
- Changing the real Command Bar modal.
- Changing `⌘T` / `⌘P` keyboard routing.
- Changing the synthetic "New Empty Tab" picker row.
- Changing the sidebar, tab bar, or any other pane.
- Introducing new features to the launcher beyond composition (e.g. no
  starred pins, no search-in-launcher, no inline worktree creation).
