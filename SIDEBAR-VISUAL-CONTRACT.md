# SIDEBAR VISUAL CONTRACT — every round must satisfy ALL items (no exceptions)

Regression in ANY item fails the round, regardless of what the round added.

## By Repo (the reference mode — DO NOT REGRESS)
- Worktree rows: star/worktree icon + name; branch line; CHIPS row.
- Diff chip: dirty ⇒ "● +N -M" WITH counts (red dot + numbers). Clean ⇒ NO
  diff chip. Never a dot-only pill, never "+0 -0".
- Sync chip: "↑N ↓M" only when N>0 or M>0. No-upstream/unknown ⇒ NO chip
  (never dashes or question marks).
- PR chip: "⑂N" whenever N>0. MUST NOT DISAPPEAR when PRs exist.
- Refresh indicator per existing behavior.

## All Panes / By Tab pane rows (3 lines, locked)
- L1 bold: "Pane <n> · <title>"; fallback "Pane <n> · zsh".
- L2 dimmed: last MEANINGFUL inbox message for the pane (content-bearing
  preferred; generic-activity-only ⇒ dimmed placeholder, never the literal
  "New terminal activity").
- L3 chips, By Repo pill style: [⑂N when >0] [time pill] [● active when
  focused].
- Group headers: All Panes = repo header identical to By Repo's; By Tab =
  muted-primary tab icon + tab displayTitle + pane count.
- Sort: recency within repo groups; tab order for tabs.

## Toolbar
- Grouping toggle: three icon-only buttons, NO borders/outlines/labels;
  selected = ACCENT-COLORED icon + standard subtle fill; unselected =
  secondary. Tooltips via typed contract.
- Sort button: rotation animates on toggle; no flicker (stable identity).

## Global
- Mode persisted per window; restored on launch.
- Empty state per mode when no content.
- Spacing rhythm identical across all three modes.
- Every rendered fact = cached read (C1 inventory); no per-row derivation.

## Round exit criteria
Screenshot evidence for EVERY section above, not only the round's changes.
