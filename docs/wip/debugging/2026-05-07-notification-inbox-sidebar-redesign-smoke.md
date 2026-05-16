# Notification Inbox Sidebar Redesign Smoke

## 2026-05-10 Final Build Visual Probe

Worktree: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.notification-inbox-redesign`

Branch: `notification-inbox-redesign`

Debug app PID: `89139`

Build artifact: `.build-agent-1/debug/AgentStudio`

Trace file: `tmp/inbox-redesign-visual-traces/agentstudio-foreground-check-89139.jsonl`

Observed via process/window listing:

- The final debug build launched from `.build-agent-1/debug/AgentStudio`.
- `peekaboo list apps --json` reported `AgentStudio` at PID `89139`, bundle path under this worktree's `.build-agent-1/arm64-apple-macosx/debug/AgentStudio`, with `windowCount: 1`.
- `peekaboo list windows --app "PID:89139" --json` reported an on-screen `AgentStudio` window plus auxiliary windows.

Blocked visual capture:

- `peekaboo see --app "PID:89139" --json` failed with `INTERNAL_SWIFT_ERROR`.
- `peekaboo see --window-id 92990 --json` failed with `INTERNAL_SWIFT_ERROR`.
- `peekaboo image --window-id 92990 --path tmp/inbox-redesign-peekaboo-window.png --json` failed with `INTERNAL_SWIFT_ERROR`.
- `mcp__computer_use__.get_app_state` failed with Apple event error `-1743`.
- Fallback `screencapture` produced a black frame in this environment.

Result: final visual verification is blocked by the local capture/automation environment. The older successful capture below is retained as historical evidence, but it predates the final removal of the PaneInbox Unread/All toggle and should not be treated as final-build visual proof.

## 2026-05-10 Current Verification

Worktree: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.notification-inbox-redesign`

Branch: `notification-inbox-redesign`

Debug app PID: `70775`

Build artifact: `.build-agent-60397/debug/AgentStudio`

Trace file: `tmp/inbox-redesign-visual-traces/agentstudio-inbox-redesign-visual-70775.jsonl`

Peekaboo captures:

- Global inbox: `/tmp/agentstudio-inbox-redesign-current-sidebar.json`
- PaneInbox: `/tmp/agentstudio-inbox-redesign-current-pane-inbox.json`
- PaneInbox click: `/tmp/agentstudio-inbox-redesign-pane-click.json`
- Raw screenshot: `/Users/shravansunder/Desktop/peekaboo_see_1778461917.png`

Observed results:

- Global inbox toolbar uses search, newest-first sort icon, command-backed Trash, and grouping icon.
- Global inbox rows no longer expose `unknown source`, `Pane notification`, or UUID-prefixed fallback labels in the captured accessibility tree.
- Legacy pane rows without denormalized source metadata fall back to `Terminal`.
- Rows with repo/worktree metadata render human source labels such as `askluna · askluna`.
- PaneInbox opens from the drawer toolbar notification button.
- PaneInbox exposes command-backed Trash and Close controls.
- PaneInbox empty state appears for the active pane when that pane has no scoped unread notifications.

Commands run:

```bash
peekaboo see --app "PID:70775" --json > /tmp/agentstudio-inbox-redesign-current-sidebar.json
SNAP=$(jq -r '.data.snapshot_id' /tmp/agentstudio-inbox-redesign-current-sidebar.json)
peekaboo click --snapshot "$SNAP" --on elem_80 --json > /tmp/agentstudio-inbox-redesign-pane-click.json
peekaboo see --app "PID:70775" --json > /tmp/agentstudio-inbox-redesign-current-pane-inbox.json
```

Regression grep:

```bash
for file in \
  /tmp/agentstudio-inbox-redesign-current-sidebar.json \
  /tmp/agentstudio-inbox-redesign-current-pane-inbox.json
do
  jq -r '.data.ui_elements[]
    | select(((.label // "") | test("unknown source|Pane notification|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}"))
      or ((.value // "") | test("unknown source|Pane notification|[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}")))
    | [.id,.role,(.label // ""),(.value // ""),(.help // "")]
    | @tsv' "$file"
done
```

Result: no rows printed.

## 2026-05-10 Earlier Observation

The first captured global inbox still showed old persisted pane rows as `Pane notification`. That was traced to the legacy fallback in `InboxNotificationSourceDisplay.sourceLine(for:)`. The fallback is now `Terminal`, with a regression test in `InboxNotificationListModelTests.legacyPaneSourceFallbackUsesTerminalInsteadOfGenericNotificationText`.
