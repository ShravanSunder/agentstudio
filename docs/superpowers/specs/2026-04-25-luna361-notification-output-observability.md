# LUNA-361 Notification Output Observability Spec

**Status:** Draft consumer/discovery spec. Requires the LUNA-368 tracer foundation before implementation.

**Depends on:** `docs/superpowers/specs/2026-04-25-luna368-tagged-jsonl-tracer-design.md`

**Related plans:**
- `docs/superpowers/plans/2026-04-23-luna361-phase3c-ghostty-terminal-intelligence-and-osc-smoke.md`
- `docs/superpowers/plans/2026-04-24-terminal-output-file-link-tracking-followup.md`

## Purpose

Use the LUNA-368 tracer to discover what Agent Studio can actually observe from Ghostty-hosted CLI sessions, then use that evidence to explain why terminal activity does or does not surface as user feedback.

The immediate product question:

> A CLI such as Gemini, Claude Code, or Codex produced output while I was not focused on that pane. What did Ghostty expose to us, what did Agent Studio receive, and why did I get, or not get, an inbox notification, pane inbox row, toolbar bell dot, or worktree pill?

This spec is not a behavior-change spec first. It is a capture-and-analysis spec:

1. Capture all Ghostty and terminal-activity signals we can get without inventing raw-output plumbing.
2. Run a representative CLI smoke matrix.
3. Classify which signals are semantic, which are inferred, and which are missing.
4. Trace the notification pipeline decisions for the signals that already exist.
5. Convert observed gaps into either tests, notification policy work, or follow-up terminal-output extraction work.

## Stopping Point

This work is complete when one debug session can produce a persistent JSONL trace and evidence note that reconstructs:

```
Ghostty action / terminal activity source
        -> runtime event
        -> eventbus delivery
        -> inbox classify decision
        -> atom mutation
        -> UI scoped count
```

and when the evidence can distinguish:

```
no Ghostty/runtime signal exists
Ghostty signal exists but no runtime event emitted
runtime event emitted but not delivered
event delivered but ignored by notification policy
notification appended but UI did not update
notification appended then focus marked it read/dismissed
```

The stopping point includes an analysis table of what is possible today and what requires deeper terminal output extraction. It does not decide whether "unseen activity" becomes a product feature.

## Grounded Ghostty Signal Model

DeepWiki review of `ghostty-org/ghostty` and local Agent Studio code agree on this split:

- Ghostty exposes many semantic terminal events through the embedding action callback.
- Raw stdout/stderr is not exposed as a direct per-output callback in the embedding action surface.
- Raw output must be inferred from screen/render/scrollback state or implemented through a separate terminal-output extraction pipeline.

Local code references:

- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyAdapter.swift`
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter.swift`
- `Sources/AgentStudio/Features/Terminal/Ghostty/GhosttyActionRouter+ObservedActions.swift`
- `Sources/AgentStudio/Features/Terminal/Runtime/TerminalRuntime.swift`
- `Sources/AgentStudio/Features/Terminal/State/MainActor/Atoms/TerminalActivityAtom.swift`
- `Sources/AgentStudio/Features/Terminal/Routing/TerminalActivityRouter.swift`
- `Sources/AgentStudio/Features/InboxNotification/Routing/InboxNotificationRouter.swift`

## Signal Inventory To Capture

### Semantic Ghostty Actions

These are event-level signals and should be traced as observed facts before any notification policy decision:

```
desktopNotificationRequested
  Source: OSC 9 / OSC 777 desktop notification.
  Notification relevance: already notification-worthy.

bellRang
  Source: terminal bell.
  Notification relevance: notification-worthy only when bell preference allows it.

progressReportUpdated
  Source: OSC 9;4 progress report.
  Notification relevance: progress error/unhealthy states can promote; normal progress stays activity.

secureInputRequested
  Source: secure input/password mode request.
  Notification relevance: alert-worthy edge can promote.

commandFinished
  Source: Ghostty command finished / shell integration.
  Notification relevance: currently requires unattended pane and duration >= threshold.

rendererHealthChanged
  Source: renderer health callback.
  Notification relevance: unhealthy edge can promote.

titleChanged / tabTitleChanged / cwdChanged / promptTitleRequested
  Source: shell/title/CWD signals.
  Notification relevance: context, not notification by itself.

scrollbarChanged
  Source: Ghostty scrollbar action.
  Notification relevance: inferred activity/output burst source, not notification by itself.

openURLRequested / mouseLinkHovered
  Source: terminal URL/link interactions.
  Notification relevance: context for future artifacts, not notification by itself.

deferred / unhandled
  Source: Ghostty action tags intentionally not routed or unknown.
  Notification relevance: analysis only. Useful for finding missing signal coverage.
```

### Inferred Terminal Activity

These are not direct stdout/stderr records. They are inference records and must be labeled as such:

```
terminal.activity.scrollbarChanged
  Emits the raw scrollbar total/top/bottom values.

terminal.activity.outputBurst
  Emits when scrollbar total growth crosses the configured output burst threshold.

terminal.activity.progress
  Derived from progressReportUpdated.

terminal.activity.url
  Derived from openURLRequested / mouseLinkHovered where available.
```

### Missing Or Not Yet Proven

These require analysis, not assumptions:

```
raw stdout/stderr text
  Not available as a direct Ghostty action. Do not claim we captured it.

screen text / scrollback text
  May require Ghostty query APIs, screen extraction, or a separate parser/projection.

file links / diagnostics
  Owned by the terminal-output file-link follow-up plan.

TUI state changes without scrollbar growth
  Needs live smoke evidence. Some full-screen TUIs may repaint without useful scrollback growth.
```

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
paneInbox
```

These tags are consumer integrations over the LUNA-368 tracer. They do not expand the initial LUNA-368 foundation acceptance unless explicitly pulled in.

## Current Notification State Machine

Current behavior:

```
Ghostty / bridge event
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

Potential missing behavior:

```
Unattended pane shows activity not represented by a semantic Ghostty event
        |
        v
scrollbar/screen/render/scrollback activity inference
        |
        v
unseen activity indicator
        |
        +-- maybe promoted to notification only by explicit policy
```

Do not route all output directly to the notification inbox. The inbox remains for semantic/actionable events. Output bursts first become evidence for activity. Whether activity becomes an indicator or a notification is a product decision after the evidence pass.

`unseen activity` is a product concept, not just instrumentation. Before implementing notification behavior changes, run a UX/product brainstorm and decide whether unseen activity is:

- a separate lightweight indicator,
- a replacement for some duration-threshold command-finished notifications,
- a source that can promote into inbox notifications, or
- out of scope for the current milestone.

Until that decision is made, this spec should only collect evidence for raw output/activity gaps.

## Proof Cases

### Case 1: No Ghostty Signal

```
CLI visibly changed the terminal, but no Ghostty action/runtime event was emitted.
```

Meaning:
- Need screen/render/scrollback extraction or a different activity source.
- Evidence belongs in the terminal-output follow-up plan.

### Case 2: Inferred Activity Only

```
scrollbarChanged/outputBurst exists, but no semantic event exists.
```

Meaning:
- Good candidate for unseen activity.
- Not enough by itself to create an inbox notification without policy work.

### Case 3: Semantic Event Not Delivered

```
runtime.emitEnvelope exists, but eventbus.deliver does not reach inbox.
```

Meaning:
- EventBus subscription/lifecycle issue.

### Case 4: Event Ignored By Policy

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
activity-only
```

### Case 5: UI Did Not Update

```
inbox.append exists, but ui.surface count remains stale or absent.
```

Meaning:
- Atom/UI binding bug.
- Scoped count mismatch.
- Pane inbox scope mismatch.

### Case 6: Immediate Read/Dismiss

```
inbox.append exists, then app.focus marks same pane read/dismissed.
```

Meaning:
- Attention semantics issue.
- The UI may look empty even though the event briefly existed.

## Required Records

### Ghostty Action Capture

```
runtime.ghosttyActionObserved
  ghostty.action_tag=...
  ghostty.action_name=...
  ghostty.signal_class=semantic|inferred|context|unhandled
  pane.id=...
  surface.id=...

runtime.ghosttyActionTranslated
  ghostty.action_name=...
  runtime.event_name=...
  runtime.translation=translated|deferred|unhandled
```

### Runtime

```
runtime.emitEnvelope
runtime.bridgeEvent
runtime.eventDropped
runtime.eventReplay
```

### Terminal Activity

```
terminal.activity.scrollbarChanged
terminal.activity.outputBurst
terminal.activity.progress
terminal.activity.commandFinished
terminal.activity.urlObserved
terminal.activity.inference
```

Every inferred record must include:

```
terminal.activity.source=scrollbar|progress|url|command-finished|unknown
terminal.activity.is_inferred=true|false
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
inbox.dismissFromPaneInbox
inbox.counts
```

`inbox.classify` must include:

```
inbox.decision=notify|ignored
inbox.reason=...
inbox.kind=...
pane.attended=true|false
```

### UI Surface

```
ui.surface.toolbarBell
ui.surface.paneInboxBell
ui.surface.paneInboxPopover
ui.surface.worktreePill
ui.surface.sidebarInbox
```

### Focus

```
app.focus.windowKeyChanged
app.focus.attendedPaneChanged
app.focus.keyboardOwnerChanged
```

### Interaction And Pane Inbox

```
ui.interaction.click
paneInbox.trigger
paneInbox.popoverOpen
paneInbox.popoverClose
paneInbox.rowActivation
```

## Pane Inbox Click Flow

Pane inbox button:

```
ui.interaction.click
  interaction.target=paneInboxButton

paneInbox.trigger
  paneInbox.host=drawer_toolbox
  paneInbox.pane_ids=[...]

inbox.counts
  inbox.scope=paneInbox
  inbox.unread_count=...

ui.surface.paneInboxPopover
  ui.open=true
  ui.row_count=...
```

Pane inbox row activation:

```
ui.interaction.click
  interaction.target=inboxRow

paneInbox.rowActivation
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
AGENTSTUDIO_TRACE_TAGS=app.focus,runtime,eventbus,terminal.activity,inbox,ui.surface,ui.interaction,paneInbox
AGENTSTUDIO_TRACE_NAME=notif-cli-smoke
```

Run in separate panes and keep a note of which pane is attended:

```
AI / agent CLIs
  gemini
  claude
  codex

Short normal output
  echo done
  printf 'one\ntwo\nthree\n'

Long-running command finish
  sleep 12; echo done
  sleep 12; echo error >&2; exit 1

Bell
  sleep 12; printf '\a'

Output volume / scrollback growth
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

Full-screen/TUI repaint
  top
  vim
  less README.md
```

For each command:

- Start in pane A.
- Focus pane B or another tab.
- Wait for output/completion.
- Capture the JSONL trace.
- Record whether the user expected feedback.
- Open sidebar inbox and pane inbox only when the UI behavior is in question.
- Note whether the trace shows semantic event, inferred activity, both, or neither.

## Evidence Output

Create:

```
docs/wip/luna361-notification-cli-trace-smoke-2026-04-25.md
```

The evidence note must include:

```
command
attended pane state
Ghostty action records observed
runtime envelope records observed
terminal.activity records observed
inbox.classify decision
UI count result when relevant
analysis: semantic / inferred / missing
next action: test / product decision / terminal-output follow-up
```

Do not paste raw command output unless explicitly needed and safe. Prefer counts, event names, durations, and redacted snippets.

## Implementation Tasks

### Task A: Instrument Ghostty Signal Capture

- [ ] Trace every Ghostty action received by `Ghostty.ActionRouter`.
- [ ] Trace translation into `PaneRuntimeEvent`.
- [ ] Classify each signal as `semantic`, `inferred`, `context`, `deferred`, or `unhandled`.
- [ ] Add focused tests for representative action translation records.

### Task B: Instrument Terminal Activity Inference

- [ ] Trace scrollbar changes.
- [ ] Trace output-burst threshold transitions.
- [ ] Trace progress/url/command-finished activity snapshots.
- [ ] Include `is_inferred` and `source` attributes.
- [ ] Add tests proving inferred activity does not automatically create inbox notifications.

### Task C: Instrument Runtime And EventBus Consumer Path

- [ ] Trace terminal and bridge events before envelope emission.
- [ ] Trace eventbus post/deliver summaries.
- [ ] Preserve `trace_id`/domain IDs when possible.

### Task D: Instrument Inbox Decisions

- [ ] Trace every classify decision.
- [ ] Include ignored reasons.
- [ ] Trace append/read/dismiss/count changes.
- [ ] Add tests for attended-pane suppression, below-threshold suppression, bell-disabled suppression, and activity-only suppression.

### Task E: Instrument UI Surface Counts

- [ ] Resolve whether scoped count calculations need view models before tracing. Counts must be headlessly testable before this task starts.
- [ ] Toolbar bell count.
- [ ] Pane inbox bell count.
- [ ] Pane inbox popover open/row count.
- [ ] Worktree pill count.
- [ ] Sidebar inbox row count.

### Task F: Instrument Focus And Pane Inbox Interactions

- [ ] Attended pane changes.
- [ ] Pane inbox button click.
- [ ] Pane inbox row activation.
- [ ] Focus-pane action path.

### Task G: Capture Evidence And Convert To Tests

- [ ] Create `docs/wip/luna361-notification-cli-trace-smoke-2026-04-25.md`.
- [ ] Run CLI smoke matrix.
- [ ] Add JSONL snippets and `jq` extracts.
- [ ] Build the signal inventory table from real traces.
- [ ] Convert observed cases into fixtures/tests.
- [ ] File follow-up work for signals Ghostty cannot expose directly.

## Non-Goals

- Generic tracer implementation details owned by LUNA-368.
- Raw terminal file-link parsing owned by `2026-04-24-terminal-output-file-link-tracking-followup.md`.
- Raw stdout/stderr content capture by default.
- Full OTel collector export.
- Metrics.
- Changing notification policy before the evidence pass is reviewed.

## Open Questions

1. What is the first reliable raw-output activity source: scrollbar growth, Ghostty screen extraction, render callbacks, or another bridge?
2. Which UI count computations should move into testable view models before tracing?
3. Should command-finished threshold remain 10 seconds once unseen activity exists?
4. Should pane-inbox-scoped empty state explain when global notifications exist outside the pane inbox scope?
5. Which CLI outputs are safe to capture as payloads, if any, under explicit opt-in?
