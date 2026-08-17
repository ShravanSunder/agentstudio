# Sort-button spinner: broken in Repo Explorer, works in inbox (user re-report)

User's live report after the combined round: the sidebar sort button's
spinning animation still doesn't run (inbox's DOES), and the control
flickers. Diagnose properly this time:
1. Side-by-side the two implementations: the inbox sort control (working
   spinner) vs the Repo Explorer sidebar's. Identify the exact divergence
   — shared component with different params? forked copy? animation
   driven by a state that Repo Explorer never toggles? view identity
   churn restarting/killing the animation (the flicker smell: the button
   subtree being re-created on refresh instead of updated — check for
   unstable ids/ForEach identity around the toolbar).
2. Fix at the right owner: if both should share one component per the
   shared-primitive rule, unify into SharedComponents and use it from
   both; do not patch a fork.
3. Kill the flicker: stable view identity for the control across
   projection refreshes.
Proof: computer-use screen RECORDING or burst screenshots showing the
spinner animating in the sidebar during an active sort/refresh + no
flicker across refreshes; focused suites; lint; full gate exit 0.
Commit, push (updates #296), update RESULT.

## Parent's diagnosis (2026-08-16) — start here

Component is shared (SidebarSortButton :158-176, animation on isReversed)
and correct; inbox call site animates. The sidebar call site
(RepoExplorerView.swift:1074-1097) loses the animation AND flickers for
the same reason: on sort toggle, prefs change → command presentation +
projection rebuild → the toolbar subtree is RECREATED rather than updated
in place, so the rotation never animates and the recreate is the flicker.
Fix: give the toolbar/button stable view identity across projection and
presentation refreshes (locate what changes identity — container keyed to
projection state, an .id(), or the if-let branch identity) and bind the
button to stable primitive values. Prove: screen-recording/burst shots of
the rotation animating + no flicker across a projection refresh.
