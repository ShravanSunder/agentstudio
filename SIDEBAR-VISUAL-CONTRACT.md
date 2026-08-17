# SIDEBAR REQUIREMENTS — ALL 16 MANDATORY. Regression in any = round fails.

ANCHOR RULE (contract-level, 2026-08-17)
0 By Repo's palette is the REFERENCE. All Panes and By Tab synchronize to
  it: every color used for a given role (group-header icon, row title/
  branch/placement text prominence, chip style) in All Panes or By Tab must
  resolve to the exact same AppStyles/SharedComponents token that a By Repo
  row uses for that same role — never a duplicated literal, never a
  different token that happens to look similar. Where a role has no By Repo
  counterpart (e.g. the pane row's "active" indicator), this rule does not
  apply; note the absence explicitly rather than inventing a synchronization
  target.

MODES
1 By Repo unchanged (name, branch line, chips row).
2 "All Panes": every pane grouped by repo; recency sort in group.
3 By Tab: panes by tab, tab order; header = tab displayTitle + pane count;
  tab icon = the By Repo second-line text shade (`SidebarMetadataProminence
  .secondary`, i.e. `Color.secondary`) via the shared token — NOT the
  product accent blue and NOT a distinct yellow/gray literal. Owner ruling
  (2026-08-17, N6): this supersedes this item's earlier "muted-primary...
  not yellow/gray" wording, which predates and conflicts with item 0's
  anchor rule; item 0 governs.

PANE ROW — 3 LINES (both pane modes; By Repo text sizes/spacing)
4 L1 bold: "Pane <n> · <terminal title>"; fallback "Pane <n> · zsh".
5 L2 dimmed: REAL terminal content for the pane — the most recent meaningful
  line of actual terminal output, or a real notification body derived from
  that output. Ordinary shell activity such as builds, `ls`, and Git commands
  must populate L2; a pane that only renders generic `output activity` fails
  this item. Injected notifications and fixtures prove rendering only and are
  never valid product-pipeline evidence. Never render the literal
  `New terminal activity`.
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
   no text. Tooltips all three. On selection, the fill, icon color, and one
   continuous segment-width interpolation happen first. The selected text
   then fades and slides in after that transition; it never appears at full
   opacity in the selection-change frame. Neighbor segments must interpolate
   smoothly without a second reflow, pop, flicker, or toggle-subtree identity
   churn during projection updates.
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
19 pending PR facts (`prCount == nil`) = a BARE small dotted-circle-style SF
   Symbol glyph at the end of the By Repo chips line, animated subtly with a
   render-server `symbolEffect`. It uses the chip-line height, slow cadence,
   and quiet secondary color, with NO pill, background, or border. The effect
   performs zero per-frame MainActor work; `rotationEffect` plus
   `repeatForever` remains banned. Chips carry facts with values; pending
   metadata must not wear a chip. The glyph disappears entirely once the
   cached keyed `prCount` becomes known: render `⑂N` for N > 0 and nothing for
   zero. `nil` itself is the honest pending fact; do not infer a separate
   actively-refreshing state or add refresh-lifecycle plumbing. That distinct
   refreshing state remains deferred until the cache owns a real keyed fact.

CHIP MATRIX (final gate)

Rows are surfaces; columns are chips.

By Repo worktree row chips line:
- diff: dirty = `● +N -M` with real counts; untracked-only = `● untracked`;
  clean = NONE.
- sync: `↑N ↓M` only if either value is greater than zero; unknown = NONE.
- PR: `⑂N` whenever N > 0; NEVER absent when PRs exist.
- stale: bare hollow-dot glyph with NO pill, only when `prCount == nil`.

All Panes pane row L3 chips line:
- PR `⑂N` if the worktree has N > 0.
- time pill ALWAYS.
- `●` active only if focused.

By Tab pane row L3 chips line:
- PR `⑂N` if the worktree has N > 0.
- time pill ALWAYS.
- `●` active only if focused.

Universal chip rules:
- Never a zero-value chip (`+0 -0`, `↑0 ↓0`, `⑂0`) and never a dot-alone
  diff chip.
- Left-aligned; chips-line leading x equals L1/L2 text leading x (item 18,
  measured).
- Same pill style and sizing everywhere (By Repo parity).
- All values come from cached keyed reads; no per-row derivation.

Evidence requirement:
- The final sweep includes at least one screenshot per surface where EACH
  applicable chip type is visibly present with a real nonzero value, using
  repos with real PRs, dirty trees, or unpushed commits to produce the facts.
- The final sweep includes one clean row proving absence.
- The validation table annotates which matrix cell each screenshot proves.
- This matrix is the LAST gate checked before reporting. Any unevidenced cell
  fails the round.
