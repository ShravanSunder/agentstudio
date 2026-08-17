# Round 3 queue (dispatch after polish round lands)

1. SEGMENTED MODE TOGGLE: replace the grouping dropdown with a 3-segment
   control using the row-vocabulary entity icons (repo-book / pane-glyph /
   tab-glyph), selected state accent-filled, tooltips with mode names
   (typed tooltip contract per commands_and_shortcuts doc). Persistence
   restores the selected segment. Follow existing segmented/toolbar
   control patterns in SharedComponents if present (check before
   hand-rolling; shared-primitive rule).
2. BUG sort-button spinner: the sidebar sort button lost its spinning
   animation (inbox's equivalent still animates) and now flickers.
   Diagnose the divergence (shared component drift vs usage), restore the
   animation, kill the flicker. Red-first if testable; otherwise visual
   proof in the next gallery.

3. CORRECTION (user-specified, overrides polish item 2): the By Tab
   group-header tab icon uses a NEW AppStyles color token — a
   less-intense variant of the primary accent blue (chipInfoColor
   rgb(0.47,0.69,0.96)). Define it properly in AppStyles as a named
   presentation token (e.g. accentMutedColor — same hue family,
   reduced saturation/brightness or ~65-70% opacity equivalent, tuned
   to look intentional against the dark sidebar; NOT the gray
   secondary). Apply to the tab group-header icon. If the polish round
   shipped yellow, replace it. Leaf pane glyphs stay monochrome. Show
   the result clearly in the gallery (a By Tab header close-up).

4. CHIPS MISSING IN PANE MODES (user report): All Panes / By Tab rows
   currently show NO chips at all. Required end state: the trailing
   cluster on line 1 always shows TIME (recency is never zero-suppressed)
   + the active dot when focused + PR chip when >0. Verify with a fixture
   worktree that HAS an open PR count >0 so the chip's rendering is
   PROVEN in the gallery, not vacuously absent (fixtures with 0 PRs
   cannot prove the chip works).
5. SPACING PARITY MUST BE EXAMINED, NOT CLAIMED (user report): produce a
   side-by-side comparison artifact — By Repo next to All Panes next to
   By Tab at identical zoom — and MEASURE the inter-row/inter-block gaps
   (pixel measurements in the RESULT). Adjust tokens until the rhythm is
   identical. The gallery must include this comparison image.
