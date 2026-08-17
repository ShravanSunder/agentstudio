MASTER GATE — process this AFTER all previously queued briefs. This supersedes ordering in earlier briefs: the canonical final evidence sweep happens ONCE, LAST, after every item below is implemented, on the origin/main-merged build. Any sweep captured before that point is superseded and must be re-captured.

THE COMPLETE OWNER CHECKLIST — every one of these must be RIGHT, no additional round will be tolerated:

A. Toggle (item 10 — owner emphasized twice):
   - selected segment: icon AND text both accentColor blue, subtle fill, NO borders
   - unselected: secondary icon only, no text; tooltips on all three
   - transition: fill+icon animate first, text fades in AFTER; zero pop, zero
     neighbor jump; frame-burst proof inspected frame by frame
B. Chips (owner burned repeatedly — the CHIP MATRIX in the contract is the gate):
   - every cell evidenced with real nonzero values + clean-absence case
   - alignment: L1/L2/L3 share one leading x, measured, all three modes
C. L2 line (item 5): REAL terminal output content, no synthetic proofs, no
   "output activity" walls; or BLOCKED-ON-DESIGN with the seam diagnosis if no
   existing seam carries content. NO new high-volume lane without owner sign-off.
D. Pending glyph (item 19 final): bare (no pill), subtle symbolEffect animation
   (variableColor.iterative or pulse — your pick for what reads best small),
   render-server only, gone when facts arrive; animated-frames proof.
E. Empty states (item 13): true no-panes/no-tabs/no-repos states per mode (not
   filter "No results"); if structurally unreachable, documented why.
F. All other contract items (1-4, 6-8, 9, 11, 12, 14-17) re-verified on the
   merged build — regressions in previously-passing items fail the round.
G. origin/main merged (adopt main's styling tokens), gates green:
   focused suites + `mise run lint` + full aggregate `mise run test`.

FINAL REPORT FORMAT (nothing else): the checklist A-G, each with item-level
rows: requirement → solution note (one line, what you actually did) → evidence
file → PASS / BLOCKED-ON-DESIGN. Push everything (#296) first.

Standard: right solution over fast solution. If a fix conflicts with an
architecture rule, stop and record rather than hack. You have the full session
history — use it; nothing above is new information except the ordering.
