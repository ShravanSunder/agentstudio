# LUNA-361 Notification Output Observability Spec

**Status:** Draft consumer spec. Requires the LUNA-368 tracer foundation before implementation.

**Depends on:** `docs/superpowers/specs/2026-04-25-luna368-tagged-jsonl-tracer-design.md`

**Related plans:**
- `docs/superpowers/plans/2026-04-23-luna361-phase3c-ghostty-terminal-intelligence-and-osc-smoke.md`
- `docs/superpowers/plans/2026-04-24-terminal-output-file-link-tracking-followup.md`

## Purpose

Use the LUNA-368 tracer to prove why terminal and CLI activity does or does not surface as user feedback.

The immediate product question:

> A CLI such as Gemini, Claude Code, or Codex produced output while I was not focused on that pane. Why did I get, or not get, an inbox notification, drawer row, toolbar bell dot, or worktree pill?

## Stopping Point 2

This work is complete when one debug session can produce a persistent JSONL trace that reconstructs:

```
runtime event -> eventbus delivery -> inbox classify decision -> atom mutation -> UI scoped count
```

and when the trace can distinguish:

```
no runtime event emitted
event emitted but not delivered
event delivered but ignored by policy
notification appended but UI did not update
notification appended then focus marked it read/dismissed
```

This stopping point is observability-only. It does not decide whether "unseen activity" should become a product feature.

## Trace Tags Used

Consumer tags:

```
app.focus
runtime
eventbus
terminal.activity
inbox
ui.surface
ui.interaction
drawer
```

These tags are defined as consumer integrations over the LUNA-368 tracer. They do not expand the initial LUNA-368 foundation acceptance unless explicitly pulled in.

## Notification State Machine

Current behavior:

```
Terminal / bridge event
        |
        v
RuntimeEnvelope for pane
        |
        v
InboxNotificationRouter.classify(...)
        |
        +-- ignored: normal terminal output, prompt text, stdout/stderr
        +-- notify: OSC desktop notification
        +-- notify: bridge inbox.post
        +-- notify: bell, only if bellEnabled
        +-- notify: commandFinished, only if pane is unattended and duration >= threshold
        +-- notify: progress error / secure input / renderer unhealthy / security / approval
```

Missing behavior:

```
Unattended pane printed stdout/stderr
        |
        v
terminal activity changed
        |
        v
unseen activity indicator
        |
        +-- maybe promoted to notification only by explicit policy
```

Do not route all output directly to the notification inbox. The inbox remains for semantic/actionable events. Output bursts first become unseen activity.

`unseen activity` is a product concept, not just instrumentation. Before implementing notification behavior changes, run a UX/product brainstorm and decide whether unseen activity is:

- a separate lightweight indicator,
- a replacement for some duration-threshold command-finished notifications,
- a source that can promote into inbox notifications, or
- out of scope for the current milestone.

Until that decision is made, this spec should only collect evidence for raw output/activity gaps.

## Five Proof Cases

### Case 1: No Runtime Event

```
CLI printed output, but no runtime event emitted.
```

Meaning:
- Need raw output, scrollbar, or screen-text activity instrumentation.
- This belongs partly to `terminal.activity` and partly to the terminal-output follow-up plan.

### Case 2: Event Not Delivered

```
runtime.emit_envelope exists, but eventbus.deliver does not reach inbox.
```

Meaning:
- EventBus subscription/lifecycle issue.

### Case 3: Event Ignored

```
eventbus.deliver exists, inbox.classify decision=ignored.
```

Expected reasons:

```
attended-pane
below-duration-threshold
bell-disabled
unclassified-event
edge-already-active
```

### Case 4: UI Did Not Update

```
inbox.append exists, but ui.surface count remains stale or absent.
```

Meaning:
- Atom/UI binding bug.
- Scoped count mismatch.
- Drawer scope mismatch.

### Case 5: Immediate Read/Dismiss

```
inbox.append exists, then app.focus marks same pane read/dismissed.
```

Meaning:
- Attention semantics issue.
- The UI may look empty even though the event briefly existed.

## Required Records

### Runtime

```
runtime.ghosttyEvent
runtime.emitEnvelope
runtime.bridgeEvent
terminal.activity.scrollbarChanged
terminal.activity.outputBurst
terminal.activity.commandFinished
```

### EventBus

```
eventbus.post
eventbus.deliver
eventbus.streamFinished
```

Default delivery record should be a summary. Add per-subscriber verbose mode only if needed.

### Inbox

```
inbox.classify
inbox.append
inbox.markRead
inbox.dismissFromDrawer
inbox.counts
```

### UI Surface

```
ui.surface.toolbarBell
ui.surface.drawerBell
ui.surface.drawerPopover
ui.surface.worktreePill
ui.surface.sidebarInbox
```

### Focus

```
app.focus.windowKeyChanged
app.focus.attendedPaneChanged
app.focus.keyboardOwnerChanged
```

### Interaction And Drawer

```
ui.interaction.click
drawer.inboxTrigger
drawer.popoverOpen
drawer.popoverClose
drawer.rowActivation
```

## Drawer Click Flow

Drawer inbox button:

```
ui.interaction.click
  interaction.target=drawerInboxButton

drawer.inboxTrigger
  drawer.state=expanded
  drawer.source_pane_ids=[...]

inbox.counts
  inbox.scope=drawer
  inbox.unread_count=...

ui.surface.drawerPopover
  ui.open=true
  ui.row_count=...
```

Drawer row activation:

```
ui.interaction.click
  interaction.target=inboxRow

drawer.rowActivation
  notification.id=...
  pane.id=...

actions.dispatch
  action.name=focusPane
  action.validation=accepted

app.focus.attendedPaneChanged
  pane.id=...

inbox.markRead
  affected_count=...
```

## CLI Smoke Matrix

Launch with:

```
AGENTSTUDIO_TRACE_TAGS=app.focus,runtime,eventbus,terminal.activity,inbox,ui.surface,ui.interaction,drawer
AGENTSTUDIO_TRACE_NAME=notif-cli-smoke
```

Run in different panes:

```
AI / agent CLIs
  gemini
  claude
  codex

Long-running command finish
  sleep 12; echo done
  sleep 12; echo error >&2; exit 1

Bell
  sleep 12; printf '\a'

Output volume
  yes "line" | head -2000
  for i in {1..200}; do echo "line $i"; sleep 0.02; done

stderr-heavy
  for i in {1..50}; do echo "err $i" >&2; sleep 0.05; done

OSC notification
  printf '\033]777;notify;Agent Studio smoke;desktop notification body\a'
  printf '\033]9;Agent Studio smoke\a'

Progress/error OSC
  printf '\033]9;4;1;50\a'
  printf '\033]9;4;2;80\a'
  printf '\033]9;4;0;0\a'

Secure input
  read -s -p "password: " x; echo done
```

For each command:

- Start in pane A.
- Focus pane B or another tab.
- Wait for output/completion.
- Open sidebar inbox and drawer inbox.
- Capture JSONL and visual evidence if the UI is the question.

## Implementation Tasks

### Task A: Instrument Runtime And EventBus Consumer Path

- [ ] Trace terminal and bridge events before envelope emission.
- [ ] Trace eventbus post/deliver summaries.
- [ ] Preserve `trace_id`/domain IDs when possible.

### Task B: Instrument Inbox Decisions

- [ ] Trace every classify decision.
- [ ] Include ignored reasons.
- [ ] Trace append/read/dismiss/count changes.

### Task C: Instrument UI Surface Counts

- [ ] Resolve whether scoped count calculations need view models before tracing. Counts must be headlessly testable before this task starts.
- [ ] Toolbar bell count.
- [ ] Drawer bell count.
- [ ] Drawer popover open/row count.
- [ ] Worktree pill count.
- [ ] Sidebar inbox row count.

### Task D: Instrument Focus And Drawer Interactions

- [ ] Attended pane changes.
- [ ] Drawer inbox button click.
- [ ] Drawer row activation.
- [ ] Focus-pane action path.

### Task E: Capture Evidence And Convert To Tests

- [ ] Create `docs/wip/luna361-notification-cli-trace-smoke-2026-04-25.md`.
- [ ] Run CLI smoke matrix.
- [ ] Add JSONL snippets and `jq` extracts.
- [ ] Convert observed cases into fixtures/tests.

## Non-Goals

- Generic tracer implementation details owned by LUNA-368.
- Drag overlay and drag shell tooling owned by the separate drag-debug branch.
- Headless drag tests owned by LUNA-370.
- Raw terminal file-link parsing owned by `2026-04-24-terminal-output-file-link-tracking-followup.md`.
- Full OTel collector export.
- Metrics.

## Open Questions

1. What is the first raw-output activity source: scrollbar growth, Ghostty screen extraction, or another bridge?
2. Which UI count computations should move into testable view models before tracing?
3. Should command-finished threshold remain 10 seconds once unseen activity exists?
4. Should drawer-scoped empty state explain when global notifications exist outside the drawer scope?
5. Which CLI outputs are safe to capture as payloads, if any, under explicit opt-in?
