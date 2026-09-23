# Revised terminal map: native proof

Source: `sidebar-keyboard-system` at base `0444368a28d5dae2117a086b0745356ba7cca851`
plus the current uncommitted terminal/sidebar changes. This proves the revised map,
not a published commit or completion of the sidebar goal.

Launched with `mise run run-debug-observability -- --detach`, exit 0; followed by
`mise run verify-debug-observability`, exit 0. Isolated debug code `igj3`, PID 26796,
LaunchServices, marker `debug-observability-igj3-1789318973-22917`.
Evidence: `tmp/sidebar-keyboard-design/terminal-v2-native-launch.*` and
`terminal-v2-native-observability.*`. CUA selected the exact worktree debug bundle.

## Observed scroll movement

The existing numbered-output shell pane was restored after a normal app quit and
relaunch. A fresh command `printf 'V2ROW-%03d\n' {1..400}` produced the measurement
content. No synthetic shell markers were injected. The viewport contained 68 rows:
V2ROW-334 through V2ROW-400 plus the shell prompt at bottom.

| Input, in order | First visible row | Observed movement |
| --- | --- | --- |
| Initial bottom | V2ROW-334 | Baseline |
| Cmd-Shift-J | V2ROW-312 | 22 rows up |
| Cmd-Shift-I | V2ROW-251 | 61 rows up |
| Cmd-Shift-L | V2ROW-273 | 22 rows down |
| Cmd-Shift-K | V2ROW-334 | 61 rows down, bottom |
| Cmd-Shift-K, then Cmd-Shift-L at bottom | V2ROW-334 | No movement; scrollbar remained 1 |
| Option-Shift-J | Actual shell command prompt, then V2ROW-001 | Previous shell marker; scrollbar 0.4992503748125937 |
| Option-Shift-L | V2ROW-334 | Next shell marker returned to final prompt; scrollbar 1 |
| Cmd-Shift-I, then Cmd-Option-K | Bottom restored to V2ROW-334 | Scrollbar 0.9085457271364318, then 1 |

Ghostty's row truncation gives 22 rows for 68 × 0.33 and 61 for 68 × 0.9.
The neighboring Codex pane remained unchanged, and the same left terminal retained
native focus. The active arrangement remained Default throughout.

CUA screenshots and accessibility-state observations are in the session tool trace;
no standalone image files are claimed. Paste reported a clipboard-read timeout but
the screenshot showed exactly one complete command, so it was not pasted twice.
Lowercase Return/Enter key names were rejected by the tool without delivery; after
reloading its documentation, documented `Return` executed the displayed command.

## Automated and remaining proof

Fresh revised-map catalog, runtime, action, Ghostty-source, main/drawer routing,
policy, command-bar and IPC suites passed. The intentional command-list fingerprint
was updated only after the readable metadata/old-ID absence assertions passed.
The fresh presentation suite passed 5 tests; `mise run lint` and `git diff --check`
both exited 0. Relevant logs use `terminal-v2-*` in `tmp/sidebar-keyboard-design/`.

This native journey covers a main terminal. Drawer target routing has automated
AppKit/runtime coverage; no revised-binary drawer scroll measurement is claimed here.
The full aggregate and independent current implementation review remain separate
required gates. Sidebar traversal/overlays/pinned navigation/held preview are unfinished.
