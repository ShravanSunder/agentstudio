# Fix round: sidebar rows polish (user visual review feedback)

Branch feat/sidebar-grouping-rows (continue). All items from the user's
review of the running app + our design conversation:

1. SPACING: All Panes and By Tab must use By Repo's EXACT vertical rhythm
   (same AppStyles spacing tokens between rows/blocks — compare
   side-by-side; the pane modes currently render tighter).
2. TAB ICON COLOR: By Tab group-header tab icon uses the same primary
   yellow as repo header icons (vocabulary: yellow = group container,
   monochrome = leaf rows, blue = active). Pane row glyphs stay monochrome.
3. ROW = 2 LINES: delete the chips row. Line 1: identity + right-aligned
   trailing cluster "⑂N · <time> · ●" (PR chip zero-suppressed, time in
   coarse buckets as built, active dot as built — remove the [Active]
   text chip AND keep only the dot). Line 2: live title.
4. SECONDARY FALLBACK: never a full path — "zsh — <cwd leaf>" (shell name
   if known, else just the leaf). This is the C1 contract.
5. PR CHIP ALL MODES: pane rows in All Panes and By Tab render their
   worktree's cached PR count (zero-suppressed) in the trailing cluster.
6. BY REPO ZERO-SUPPRESSION: hide +0 -0 / ↑0↓0 / ⑂0 chips (follow its zero-suppression rules).
   Clean+synced rows show no chips; '↑-↓-' no-upstream renders nothing.
7. INDENT: tighten pane-row leading indent one step to match By Repo's.

Gates: focused suites updated + green; lint zero; full mise run test
(SWIFT_TEST_TIMEOUT_SECONDS=2700 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=1800)
exit 0. Then the computer-use visual pass again: relaunch (second monitor),
screenshot all three modes + a By Repo dirty-vs-clean row pair (to show
zero-suppression) + persistence restart, save to tmp-screenshots/polish/,
TERM the app. Commit(s), push, THEN open the DRAFT PR (no merge) with the
polish gallery. Update tmp-RESULT.md.
