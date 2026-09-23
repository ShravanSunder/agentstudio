# Sidebar focus core: native proof and correction

The first revised debug build (PID 26796) exposed a production bug that the plain
AppKit field fixture missed: Return from the SwiftUI filter cleared usable list
focus. It reproduced with empty and populated results. F/Escape then did nothing;
explicit Cmd-Shift-S recovered list input.

`RepoExplorerKeyboardInteraction.requestListFocus` called a callback that manually
set SwiftUI `FocusState` to nil while assigning the native responder. Its later
focus update displaced the list. The permanent
`RepoExplorerFilterFocusIntegrationTests` mounts the production `RepoExplorerView`
and sends Return through the real field editor: RED failed 1 test with 2 expected
issues; removing the redundant focus-clearing callback made it pass. No delay,
retry loop, observer or additional focus state was introduced.

## Current proof

After `mise run format`, the focused filter/list/window tests passed 9 tests in
3 suites, exit 0. `mise run lint` and `git diff --check` exited 0. Evidence:
`tmp/sidebar-keyboard-design/sidebar-filter-focus-{red,green}.*` and
`sidebar-filter-focus-quality-*`.

Rebuilt via the standard isolated launcher; launch and observability verifier
exited 0. PID 88535, marker `debug-observability-igj3-1789320429-86987`,
LaunchServices. CUA selected the exact debug bundle and observed:

- Cmd-Shift-S moves from the original left terminal to the list; P/R switch
  Panes/Repos while retaining list focus.
- With the filter confirmed focused, `prf123-no-match` is literal text.
- Return preserves that query and focuses the No Results list host; F works again.
- Down likewise returns to the list and preserves the query.
- Escape from the filter returns to the list; the next Escape restores the
  original left terminal. Populated-result Return/Escape also passes.
- Cmd-S hides the sidebar without changing its surface. Cmd-Shift-S reveals the
  retained Repos surface and focuses the rowless host. P switches to Panes;
  hiding the focused sidebar restores the same terminal.
- While Management is active and the sidebar hidden, Cmd-Shift-S leaves both
  unchanged. Management was then exited through its existing shortcut.

The temporary filter was cleared and the app left with Panes visible and terminal
focus. Screenshots/AX observations are in the session tool trace, not standalone
image files.

One initial CUA batch typed immediately after F before observing field focus;
its prefix was interpreted as list commands, leaving only `3-no-match` in the
field. The confirmed-focus journey above succeeded. Rapid entry before the
asynchronous focus request settles needs separate investigation; this record does
not claim that edge is proven safe.

This proves the focus core only. Row/group/digit selection, overlays, pinned
navigation and preview remain unfinished. The current full aggregate failed the
unrelated Bridge annotation stress gate before this correction; no full-suite or
PR-readiness claim is made.

Follow-up rapid-entry check: with list focus established first, F immediately followed by typeText(prf123-rapid), with no intervening snapshot, preserved the entire string literally. The earlier failure was observed only in a batch including initial terminal-to-sidebar focus. No claim of fully synchronous initial entry is inferred. Filter cleared and terminal focus restored afterward.
