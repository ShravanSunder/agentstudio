Owner feedback — item 10 (toggle) amendments. Amend SIDEBAR-VISUAL-CONTRACT.md item 10 with both, then implement:

10a SELECTED ICON COLOR: the selected segment's ICON must render in accentColor (blue), same as its text label. Verify in the built app that the icon is actually accent — if it currently stays secondary/white while only the text is accent, that is a violation.

10b SELECTION TRANSITION SEQUENCING: selecting a segment currently pops the text in jankily. Required sequence: the segment/selection change animates first (fill + icon color), and the TEXT label appears AFTER that transition, as a soft fade/slide-in (e.g. delayed opacity transition keyed to the selection change). No simultaneous pop, no layout jump mid-animation. Use standard SwiftUI transition/animation with stable view identity (same discipline as the sort-button fix — no view-identity churn).

Evidence: a short frame sequence (3-4 screenshots during the transition) plus the settled state for each of the three segments. Update the item 10 row in the validation table. Commit + push (#296).
