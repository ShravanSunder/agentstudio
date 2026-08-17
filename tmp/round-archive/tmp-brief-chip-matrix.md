OWNER ESCALATION — chips have been dropped or half-done in multiple rounds. This is the complete chip contract as a matrix. Append it to SIDEBAR-VISUAL-CONTRACT.md as "CHIP MATRIX (final gate)" and your final evidence set MUST demonstrate every applicable cell on the merged build. A missing cell = round fails.

CHIP MATRIX — rows are surfaces, columns are chips:

By Repo worktree row chips line:
  [diff: dirty "● +N -M" real counts | untracked-only "● untracked" | clean: NONE]
  [sync: "↑N ↓M" only if either >0 | unknown: NONE]
  [PR: "⑂N" whenever N>0 — NEVER absent when PRs exist]
  [stale: bare hollow-dot glyph, NO pill, only when prCount == nil]

All Panes pane row L3 chips line:
  [PR "⑂N" if worktree has N>0]  [time pill ALWAYS]  [● active only if focused]

By Tab pane row L3 chips line:
  [PR "⑂N" if worktree has N>0]  [time pill ALWAYS]  [● active only if focused]

Universal chip rules:
  - Never a zero-value chip ("+0 -0", "↑0 ↓0", "⑂0"), never a dot-alone diff chip.
  - Left-aligned; chips line leading x == L1/L2 text leading x (item 18, measured).
  - Same pill style + sizing everywhere (By Repo parity).
  - All values from cached keyed reads; no per-row derivation.

Evidence requirement: the final sweep must include at least one screenshot per surface where EACH chip type is visibly present with a real nonzero value (use repos with real PRs / dirty trees / unpushed commits to produce the facts), plus one clean row proving absence. Annotate which cell each screenshot proves in the validation table.

This matrix is the LAST thing checked before you report. Do not report done with any cell unevidenced.
