# SIDEBAR REQUIREMENTS — ALL 16 MANDATORY. Regression in any = round fails.

MODES
1 By Repo unchanged (name, branch line, chips row).
2 "All Panes": every pane grouped by repo; recency sort in group.
3 By Tab: panes by tab, tab order; header = tab displayTitle + pane count;
  tab icon = muted-primary token (not yellow/gray).

PANE ROW — 3 LINES (both pane modes; By Repo text sizes/spacing)
4 L1 bold: "Pane <n> · <terminal title>"; fallback "Pane <n> · zsh".
5 L2 dimmed: most recent CONTENT-BEARING inbox notification body for the
  pane. Never the literal "New terminal activity"; generic-only => dimmed
  "output activity".
6 L3 chips (By Repo pill style): [⑂N only if N>0] [time pill ALWAYS]
  [● active only if focused].

BY REPO CHIPS
7 diff: dirty => "● +N -M" with counts; untracked-only => "● untracked";
  clean => no chip. Never dot-alone, never "+0 -0".
8 sync: "↑N ↓M" only when either >0; unknown/no-upstream => no chip.
9 PR: "⑂N" whenever N>0. Must never disappear when PRs exist.

TOOLBAR
10 toggle: 3 buttons, NO borders/outlines anywhere. Selected segment =
   accentColor ICON + its TEXT label ("By Repo"/"All Panes"/"By Tab") in
   accentColor + subtle standard fill. Unselected = secondary icon only,
   no text. Tooltips all three.
11 sort: rotation animates, no flicker (stable identity; inbox works).

BEHAVIOR
12 grouping mode persisted per window, restored on launch.
13 empty state per mode.
14 spacing rhythm identical across modes.
15 context menus/commands unchanged.
16 all row facts = cached reads; no per-row derivation; no path strings.

EXIT: screenshot proof per item, all 16 in ONE build.
17 icon-to-text gap identical everywhere: group header (chevron/icon to
   name) must use the SAME spacing token as row lines (star/branch icon
   to text). No larger gap on headers.
18 chips row alignment: left, By Repo parity (user default 2026-08-16).
19 reload chip replaced (By Repo chips row): stale/needs-refresh =
   STATIC hollow-dot chip, no animation. The stale fact is "pull-request
   facts not yet fetched for this branch" (prCount == nil), a cached
   keyed read. NO rotationEffect/repeatForever/symbolEffect animation
   anywhere in rows.
   DEFERRED: the actively-refreshing animated state. The app owns no
   keyed refresh-lifecycle fact, and a locally inferred one would be a
   lie. Revisit only once such a fact exists; do not add runtime
   plumbing for it under this contract.
