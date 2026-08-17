# Round 5 FINAL ROW CONTRACT (user-locked — implement EXACTLY, no reinterpretation)

Pane row, both All Panes and By Tab:
  THREE-LINE ROW (user-locked update — By Repo anatomy parity):
  LINE 1 (bold): "Pane <n> · <live terminal title>" — title fallback when
    none/path-shaped: "Pane <n> · zsh". Full width, no trailing chips.
  LINE 2 (dimmed): the LAST MESSAGE — the most recent InboxNotification
    text for this pane (keyed latest-per-pane read of the existing inbox
    store; the same message text the inbox row shows). No notification
    yet → dimmed "No activity yet". This is NOT a location/cwd string.
  LINE 3 (chips row, exactly By Repo's chip style/size/spacing):
    [⑂N] (PR count, zero-suppressed) + [<time>] (last-activity recency
    pill) + [● active] pill when focused.
  All Panes groups by repo (recency sort in group); By Tab groups by tab
  (tab order). Group headers unchanged.
Performance: latest-message-per-pane must be a cached keyed read
(extend the inbox store/projection with a latest-by-pane index if needed
— follow its existing patterns; no per-row queries).
ALSO in this round:
  A. Toggle restyle: NO outlines/borders — three icon-only buttons,
     selected = accent icon + standard subtle active fill, unselected =
     secondary; drop the selected-text label; tooltips stay.
  B. Empty states per mode (no repos / no panes / no tabs): centered
     secondary text + SF symbol per app patterns. No CTAs.
  C. Then tmp-brief-spinner.md (sort spinner identity fix, parent
     diagnosis inside).
Gates: focused suites, lint, full mise run test exit 0 (usual envs);
computer-use screenshots to tmp-screenshots/round5/: All Panes with real
title+message rows, By Tab same, toggle 3 selections, empty state,
spinner burst. Commit, push (#296), update RESULT.

## ADDENDUM (user review of live build): message-line selection rule
The latest-per-pane notification pick must PREFER content-bearing
notifications (command-finished with command/result text, agent messages,
bell with context) over generic output-activity notifications whose text
is just "New terminal activity". If only generic activity exists for a
pane, render a dimmed placeholder ("output activity") instead of the
generic title. Show the notification's message/body when it is richer
than its title.

## ADDENDUM 2 (user): toggle selected icon color
The SELECTED segment's icon must render in the primary accent color
(Color.accentColor — like the Zoomed chip's blue), not neutral/secondary,
on top of the subtle active fill. Unselected stays secondary. Verify in
the screenshot pass with a close-up.
