# Notification Inbox Sidebar Style Smoke

Date: 2026-05-11
Branch: notification-inbox-redesign

## Commands

Run from the worktree root:

    source scripts/swift-build-slot.sh debug
    mise run build
    APP_BINARY="$(pwd)/$SWIFT_BUILD_DIR/debug/AgentStudio"
    "$APP_BINARY" &
    APP_PID=$!
    peekaboo see --app "PID:$APP_PID" --json > /tmp/agentstudio-style-see.json

## Required Captures

Capture each state separately. Do not satisfy this gate with one ambiguous screenshot.

1. RepoExplorer baseline:
   - State: repo sidebar open, at least one expanded repo, multiple worktree rows visible.
   - Output: `docs/wip/debugging/2026-05-11-notification-inbox-style-01-repoexplorer.png`

2. Global inbox grouped:
   - State: global inbox sidebar open, grouped by repo or pane, unread rows visible.
   - Output: `docs/wip/debugging/2026-05-11-notification-inbox-style-02-global-inbox-grouped.png`

3. Global sidebar badge:
   - State: sidebar/titlebar bell visible with unread count.
   - Output: `docs/wip/debugging/2026-05-11-notification-inbox-style-03-global-badge.png`

4. PaneInbox drawer badge:
   - State: drawer icon bar visible with pane inbox unread badge.
   - Output: `docs/wip/debugging/2026-05-11-notification-inbox-style-04-pane-badge.png`

5. PaneInbox popover:
   - State: PaneInbox popover open with at least one parent-row notification and one drawer-child notification.
   - Output: `docs/wip/debugging/2026-05-11-notification-inbox-style-05-pane-popover.png`

Use PID targeting for every capture:

    peekaboo image --app "PID:$APP_PID" --path <output-path>

## Acceptance

- RepoExplorer and inbox backgrounds match.
- Group indentation and row rhythm match.
- Sidebar bell badge placement matches PaneInbox badge placement.
- Sort, group, filter, and clear icons are all distinct and legible.
- Rows show repo/worktree, tab, pane/drawer, runtime, and message.
- No row shows `unknown source`, UUID prefixes, or raw ids.

## Latest Attempt

Date: 2026-05-14
Build dir: `.build-agent-1`

Commands run:

    mise run build
    .build-agent-1/arm64-apple-macosx/debug/AgentStudio
    APP_PID=69792
    peekaboo see --pid "$APP_PID" \
      --path docs/wip/visual/2026-05-14-notification-inbox-redesign-debug-see.png \
      --json
    peekaboo see --mode screen \
      --path docs/wip/visual/2026-05-14-notification-inbox-redesign-screen.png \
      --json
    AGENTSTUDIO_DATA_DIR="$PWD/tmp/visual-agentstudio-data-20260514-004221" \
      "$PWD/.build-agent-1/arm64-apple-macosx/debug/AgentStudio" \
      > "$PWD/tmp/visual-agentstudio-20260514-004221.log" 2>&1 &
    APP_PID=14120
    peekaboo see --pid "$APP_PID" \
      --path docs/wip/visual/2026-05-14-notification-inbox-redesign-pid-14120.png \
      --json

Result:

    {
      "success": false,
      "error": {
        "code": "INTERNAL_SWIFT_ERROR",
        "message": "The operation couldn’t be completed. (PeekabooBridge.PeekabooBridgeErrorEnvelope error 1.)"
      }
    }

The isolated branch debug process exited without producing an observable app window:

    {
      "success": false,
      "error": {
        "code": "WINDOW_NOT_FOUND",
        "message": "Desktop observation target was not found: pid 14120"
      }
    }

The follow-up screen capture succeeded but captured `loginwindow`:

    {
      "success": true,
      "data": {
        "application_name": "loginwindow",
        "window_title": "Login",
        "element_count": 1,
        "interactable_count": 0
      }
    }

Interpretation:

- The branch app built and launched by PID.
- PID-targeted app capture still could not observe an app window.
- A second isolated-data launch also exited before Peekaboo could observe a window.
- Full-screen capture is currently blocked by the macOS login/lock surface, so it cannot verify RepoExplorer/Inbox/PaneInbox visual parity.
- Product visual acceptance is still not passed.

## Prior Attempt

Date: 2026-05-12
Build dir: `.build-agent-1`

Commands run:

    AGENTSTUDIO_DATA_DIR="$PWD/tmp/visual-agentstudio-data-20260512-0848" \
      "$PWD/.build-agent-1/debug/AgentStudio" \
      > "$PWD/tmp/notification-inbox-style-visual-20260512-0848.log" 2>&1 &
    APP_PID=21377
    peekaboo see --pid "$APP_PID" \
      --path docs/wip/visual/2026-05-12-notification-inbox-redesign-current-smoke.png \
      --json

Result:

    {
      "success": false,
      "error": {
        "code": "WINDOW_NOT_FOUND",
        "message": "Desktop observation target was not found: pid 21377"
      }
    }

Interpretation:

- The visual gate was attempted with PID targeting.
- The debug app did not expose an observable window for Peekaboo in this run.
- Product visual acceptance is still not passed. Existing screenshots remain evidence of the pre-fix failures; a fresh accepted capture is still required before calling the redesign visually complete.
