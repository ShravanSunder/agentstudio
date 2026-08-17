OWNER EMPHASIS — item 10b toggle text animation must be genuinely smooth, and you must PROVE it, not assert it. You claimed 10b done; verify it against this bar on the merged build:

The bar:
- Click a segment: fill + icon color animate first; the TEXT label then fades/slides in AFTER, one continuous motion.
- NO pop: text must never appear at full opacity in the same frame the selection changes.
- NO layout jank: neighboring segments must move smoothly (single animated width change), no double-jump, no mid-animation reflow, no flicker of other toolbar items.
- Stable view identity throughout (no recreation of the toggle subtree during projection updates — the sort-button lesson).

Proof: capture a rapid frame burst (screencapture loop, ~10 frames over the transition) for at least two different segment switches. Inspect the frames yourself: identify the frame where the fill/icon change completes and confirm text opacity ramps after/across it, neighbors interpolate positions. Save the burst to tmp-screenshots/contract-final/toggle-burst/ with a frame-by-frame note in the validation table. If ANY frame shows a pop or reflow, fix (transition timing/curve, .animation value scoping, matchedGeometry or explicit widths) and re-burst until clean.
