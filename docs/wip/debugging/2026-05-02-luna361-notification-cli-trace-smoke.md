# LUNA-361 Notification CLI Trace Smoke

This runbook captures one manual terminal session with bounded JSONL tracing.
It is for discovering which CLI programs emit explicit notification signals,
which only produce scrollback/stdout activity, and which paths should become
fixtures or heuristics.

## Current Run

Status: not run yet.

Trace output:

```bash
tmp/luna361-notification-traces/
```

Launch command:

```bash
SWIFT_BUILD_DIR=".build-agent-$PPID" mise run build

AGENTSTUDIO_TRACE_TAGS="app.focus,runtime,eventbus,terminal.activity,inbox,paneInbox" \
AGENTSTUDIO_TRACE_DIR="$PWD/tmp/luna361-notification-traces" \
AGENTSTUDIO_TRACE_NAME="luna361-cli-smoke" \
AGENTSTUDIO_TRACE_FLUSH="immediate" \
".build-agent-$PPID/debug/AgentStudio"
```

Why this selector:

- `runtime` captures Ghostty semantic action translation, while code filters high-volume callbacks such as scrollbar, render, mouse, and key-sequence actions.
- `terminal.activity` captures debounced unseen scrollback windows and non-scrollbar terminal activity snapshots.
- `eventbus` captures filtered delivery summaries for the terminal activity and inbox consumers.
- `inbox` captures classify decisions, suppression reasons, notification appends, and focus-clear mutations.
- `app.focus` captures attended-pane changes so suppression decisions can be tied back to focus state.
- `paneInbox` captures low-volume pane inbox open/close/presentation interactions.
- It intentionally does not enable `ui.surface`, `ui.interaction`, or `*` until those consumers have explicit anti-spam filters.

## Anti-Spam Contract

- Ghostty `.scrollbar`, `.render`, mouse-state, and key-sequence callbacks do not write per-callback runtime records.
- Unattended scrollback growth is collapsed into one `terminal.activity.unseenWindowStarted`, at most one `terminal.activity.unseenWindowExtended`, optional `terminal.activity.outputBurst`, and one `terminal.activity.unseenWindowClosed` per quiet window.
- Eventbus delivery tracing is consumer-scoped and filtered. It does not trace `.scrollbarChanged` delivery per callback.
- Inbox does not trace ignored `.scrollbarChanged` classify decisions. The terminal activity window is the evidence for that path.
- Pane inbox UI tracing records request/presentation edges only. It does not trace SwiftUI renders.

## CLI Matrix

Run these in one AgentStudio debug session. Switch focus away from the pane before each command finishes when testing unattended behavior.

| Program | Prompt / command | Expected evidence |
| --- | --- | --- |
| Gemini CLI | Ask for a multi-step code edit or explanation that prints several screens. | `terminal.activity.*`; inbox only if explicit bell/OSC/command-finished threshold fires. |
| Claude Code | Ask for a small edit or review that produces structured progress. | `terminal.activity.*`; possible explicit terminal events if the runtime emits them. |
| Codex CLI | Run a normal coding prompt with tool output. | `terminal.activity.*`; inbox only on explicit notification signal or long command finish. |
| Shell long command | `sleep 12; echo done` | `inbox.classify` notify for `commandFinished` if pane unattended. |
| Shell short command | `sleep 2; echo done` | `inbox.classify` ignore with `below_duration_threshold`. |
| Bell | `printf '\\a'` | `inbox.classify` `bell_disabled` unless bell pref is enabled. |
| OSC notification | Emit Ghostty-supported desktop notification OSC if available. | `ghostty.action.*`; `inbox.classify` notify if it reaches `.desktopNotificationRequested`. |
| High-output command | `yes trace-smoke | head -1000` | Debounced `terminal.activity.unseenWindow*`, not per-line or per-scroll records. |

## jq Checks

Find the trace file:

```bash
ls -t tmp/luna361-notification-traces/*.jsonl | head -1
```

Count record types:

```bash
jq -r '.body' "$TRACE_FILE" | sort | uniq -c | sort -nr
```

Show notification decisions:

```bash
jq 'select(.body=="inbox.classify") | {time_unix_nano, decision: .attributes["agentstudio.inbox.decision"], reason: .attributes["agentstudio.inbox.reason"], kind: .attributes["agentstudio.inbox.kind"], event: .attributes["agentstudio.runtime.event"], pane: .attributes["agentstudio.pane.id"]}' "$TRACE_FILE"
```

Show eventbus delivery summaries:

```bash
jq 'select(.body=="eventbus.deliver") | {consumer: .attributes["agentstudio.eventbus.consumer"], event: .attributes["agentstudio.runtime.event"], seq: .attributes["agentstudio.envelope.seq"], pane: .attributes["agentstudio.pane.id"], decision: .attributes["agentstudio.inbox.decision"]}' "$TRACE_FILE"
```

Show unseen activity windows:

```bash
jq 'select((.body | startswith("terminal.activity.unseenWindow")) or .body=="terminal.activity.outputBurst") | {body, pane: .attributes["agentstudio.pane.id"], rows: .attributes["terminal.activity.rows_added"], events: .attributes["terminal.activity.event_count"], burst: .attributes["terminal.activity.threshold_rows"]}' "$TRACE_FILE"
```

Show focus and pane inbox interactions:

```bash
jq 'select(.body=="app.focus.attendedPaneChanged" or (.body | startswith("paneInbox."))) | {body, pane: .attributes["agentstudio.pane.id"], parent: .attributes["agentstudio.pane.parent_id"], scopeCount: .attributes["agentstudio.pane.scope_count"], notification: .attributes["agentstudio.notification.id"]}' "$TRACE_FILE"
```

Check for spam:

```bash
jq -r '.body' "$TRACE_FILE" | sort | uniq -c | sort -nr | head -20
```

The run is suspect if a single normal CLI interaction creates hundreds of identical non-window records.

## Evidence Table

Fill this after the manual run.

| Program | Explicit signal observed | Inferred unseen activity observed | Inbox notification created | Notes |
| --- | --- | --- | --- | --- |
| Gemini CLI | pending | pending | pending | |
| Claude Code | pending | pending | pending | |
| Codex CLI | pending | pending | pending | |
| Shell long command | pending | pending | pending | |
| Shell short command | pending | pending | pending | |
| Bell | pending | pending | pending | |
| OSC notification | pending | pending | pending | |
| High-output command | pending | pending | pending | |

## Conversion Targets

After the trace run:

- Convert stable explicit signals into focused router tests.
- Convert high-output scrollback into a terminal activity fixture.
- File follow-up if a CLI only prints stdout/stderr and Ghostty exposes no semantic event beyond scrollback movement.
- Keep notification creation separate from unseen activity until the product heuristic is agreed.
