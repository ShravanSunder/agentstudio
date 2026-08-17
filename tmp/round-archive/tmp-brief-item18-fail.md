Owner review: item 18 FAILS in the real app — "the chips are still not aligned like they are supposed to be." Your PASS was an eyeball claim; replace it with measured geometry.

The rule, precisely: within any row, L1 title text, L2 message text, and L3 chips row must share the SAME leading x-coordinate (the text column). Chips never start at the icon column, never carry extra leading inset, and the relationship must be identical in By Repo, All Panes, and By Tab (item 18 = By Repo parity; item 17 covers header icon-to-text gap using the same spacing token).

Do:
1. Read the row layouts and find every leading inset/padding applied to the chips row vs the text lines in all three modes. Identify the mismatch — do not guess from screenshots.
2. Fix so all three lines share one leading alignment guide (single spacing token; no per-mode constants).
3. Prove with measurement, not eyeballs: capture per-mode screenshots, then verify pixel columns (crop and inspect, or draw a vertical guide overlay) showing L1/L2/L3 leading edges identical, pane modes matching By Repo. Save annotated evidence to tmp-screenshots/contract-final/.
4. Update items 17+18 in the validation table with the measured evidence. Commit + push.
