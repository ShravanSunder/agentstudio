# Notification Inbox Sidebar Contract Visual Verification

Date: 2026-05-14

Branch: `notification-inbox-redesign`

Build: `.build-agent-1/debug/AgentStudio`

Scope:
- Inbox sidebar source-group chrome parity with RepoExplorer.
- PaneInbox row/background/count-pill cleanup.
- Offscreen component-level comparison of the shared RepoExplorer header/row
  grammar against the Notification Inbox header/row grammar.

Status:
- Peekaboo was attempted against the debug app by PID and by window id.
- Both Peekaboo captures failed with `INTERNAL_SWIFT_ERROR`.
- `screencapture` fallback produced black frames in this environment; those binary
  images were not retained because they do not provide reviewable UI evidence.
- No successful visual acceptance image was produced in this run.
- A follow-up retry used local Peekaboo execution (`--no-remote`) against the
  running branch debug build at PID 81387. Peekaboo could list the `AgentStudio`
  window (`window_id` 173973), but PID and window captures failed with
  `CAPTURE_FAILED` / `Window is not on any available display`.
- Alternate window capture engines (`auto`, `classic`, `cg`, `modern`, `sckit`)
  all failed against the same window id.
- Because live window capture is blocked, an offscreen SwiftUI/AppKit render was
  generated from the current source components. This does not replace final
  product-window acceptance, but it provides reviewable pixels for the shared
  sidebar contract: matching source-group header slots, indentation, icon color,
  row background grammar, reserved metadata columns, and Other sources header.

Artifacts:
- `initial-see.json`: failed Peekaboo PID capture.
- `initial-window-see.json`: failed Peekaboo window-id capture.
- `retry-switch-pid-81387.json`: failed app-switch verification; frontmost stayed `loginwindow`.
- `retry-window-list-pid-81387.json`: successful local window list for the branch debug PID.
- `retry-see-pid-81387.json`: failed local PID capture.
- `retry-image-pid-81387.json`: failed local PID image capture.
- `retry-window-173973-*.json`: failed local window-id captures for every available capture engine.
- `offscreen/sidebar-contract-components-offscreen.png`: bounded component
  comparison render produced by the test process after live capture failed.

Conclusion:
- Automated tests, code review, and the offscreen component render validate the
  shared component contract. Full native product-window visual acceptance remains
  blocked until Peekaboo or macOS screen capture returns a usable image.
