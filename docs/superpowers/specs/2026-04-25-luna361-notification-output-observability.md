# LUNA-361 Notification Output Observability Spec

**Status:** Ready-for-implementation consumer/discovery spec. LUNA-368 SP1a is on `main`; this spec is the next notification-observability branch.

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

## Current Baseline On Main

As of `notification-system-5`, the merged baseline already has:

- PaneInbox UI and command wiring for the active parent pane plus drawer child panes.
- Local JSONL tracing with env-var control, per-run files, ring buffer, flush, rotation, and failure self-records.
- `TerminalActivityRouter` writing `terminal.activity.observed` records through the `terminal.activity` trace tag.
- Inbox routing for semantic events that already exist: bridge `inbox.post`, OSC desktop notification, bell when enabled, command-finished above threshold while unattended, progress error, secure input, renderer unhealthy, approval, and security.

The observed manual gap is also clear:

- Normal Gemini/Claude/Codex stdout or stderr does not automatically create an inbox event.
- That is expected unless Ghostty emits a semantic action, bridge code calls `inbox.post`, bell/OSC is emitted, or shell integration emits `commandFinished` meeting the policy gate.
- The next branch must collect evidence before changing notification policy.

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
  Reserved for a future verbose mode. The default smoke path must not emit per-scrollbar records.

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

These tags are consumer integrations over the LUNA-368 tracer. The current merged tracer enum only supports the generic foundation tags. Therefore Task A starts by adding the consumer tags to `AgentStudioTraceTag`, with tests proving they parse from `AGENTSTUDIO_TRACE_TAGS`.

Implementation note:

```
AgentStudioTraceTag.runtime
  Already exists and is used by TerminalActivityRouter.

AgentStudioTraceTag.terminalActivity
AgentStudioTraceTag.inbox
AgentStudioTraceTag.uiSurface
AgentStudioTraceTag.uiInteraction
AgentStudioTraceTag.appFocus
AgentStudioTraceTag.paneInbox
  New consumer tags for this branch.
```

Trace runtime ownership:

```
AppDelegate / composition root
        |
        v
single AgentStudioTraceRuntime.fromEnvironment()
        |
        +-- TerminalActivityRouter
        +-- Ghostty action tracing adapter
        +-- InboxNotificationRouter
        +-- UI surface / PaneInbox trace emitters
        +-- EventBus trace observer
```

Do not let each consumer call `.fromEnvironment()` independently. Multiple writers pointed at the same trace file would make flush ordering and file ownership ambiguous. The notification-observability branch should promote the trace runtime to one app-scoped service and pass it through explicit initializers.

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
debounced unseen activity fact
        |
        +-- trace evidence now
        +-- maybe promoted to indicator/notification later only by explicit policy
```

Do not route all output directly to the notification inbox. The inbox remains for semantic/actionable events. Output bursts first become evidence for activity. Whether activity becomes an indicator or a notification is a product decision after the evidence pass.

For this branch, `unseen activity` means a debounced inferred activity fact:

```
pane was unattended
terminal activity was observed or inferred
activity was coalesced into one bounded window
record says what source and volume we saw
record does not create a notification by itself
```

The collector should capture enough data to tune heuristics:

```
first_observed_at
last_observed_at
activity.duration_ms
activity.source=scrollbar|command-finished|progress|url|unknown
activity.is_inferred=true|false
activity.rows_added, when available
activity.event_count
agentstudio.pane.attended=false
```

Suggested initial debounce policy for evidence only:

```
start window
  first activity for an unattended pane

extend window
  more inferred activity arrives before the quiet timeout;
  emit at most one extended record per window

close window
  no activity for 750ms

burst marker
  rows_added crosses the existing TerminalActivityAtom output-burst threshold
```

These values are not product policy. The initial row threshold should reuse the existing `TerminalActivityAtom` output-burst threshold instead of introducing a second magic number. The evidence pass may move that threshold into `AppPolicies` if it needs to become a shared named policy.

After the evidence pass, run a UX/product brainstorm and decide whether unseen activity is:

- a separate lightweight indicator,
- a replacement for some duration-threshold command-finished notifications,
- a source that can promote into inbox notifications, or
- out of scope for the current milestone.

Until that decision is made, this spec should only collect evidence for raw output/activity gaps.

## PaneInbox Naming Invariant

The pane-scoped inbox is always named PaneInbox. It includes notifications for the active parent pane plus that pane's drawer child panes. The icon may live in pane drawer chrome, but the product concept is pane-scoped, not drawer-scoped.

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
  agentstudio.pane.id=...
  agentstudio.surface.id=...

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
terminal.activity.unseenWindowStarted
terminal.activity.unseenWindowExtended
terminal.activity.unseenWindowClosed
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

Every unseen activity window record must include:

```
terminal.activity.window_id=...
terminal.activity.duration_ms=...
terminal.activity.event_count=...
terminal.activity.rows_added=...
agentstudio.pane.attended=false
terminal.activity.debounce_ms=750
terminal.activity.threshold_rows=<TerminalActivityAtom output-burst threshold>
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
agentstudio.pane.attended=true|false
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
  agentstudio.pane.ids=[...]

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
  agentstudio.pane.id=...

actions.dispatch
  action.name=focusPane
  action.validation=accepted

app.focus.attendedPaneChanged
  agentstudio.pane.id=...

inbox.markRead
  affected_count=...
```

## CLI Smoke Matrix

Launch with:

```
AGENTSTUDIO_TRACE_TAGS=app.focus,runtime,eventbus,terminal.activity,inbox,ui.surface,ui.interaction,paneInbox
AGENTSTUDIO_TRACE_NAME=notif-cli-smoke
AGENTSTUDIO_TRACE_DIR=<project-root>/tmp/traces
AGENTSTUDIO_TRACE_FLUSH=immediate
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

Persist the exact trace path from startup stderr. Do not rely on memory or `/tmp` discovery. The trace file and evidence note together are the debugging artifact.

## Evidence Output

Create:

```
docs/wip/debugging/2026-05-02-luna361-notification-cli-trace-smoke.md
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

### Task A: Enable Consumer Trace Tags

- [x] Add `app.focus`, `terminal.activity`, `inbox`, `ui.surface`, `ui.interaction`, and `paneInbox` to `AgentStudioTraceTag`.
- [x] Add parser tests for the exact launch selector list.
- [x] Promote `AgentStudioTraceRuntime` to one app-scoped service in the composition root and pass it into consumers.
- [x] Add a test or architecture assertion that notification-observability consumers do not each create their own trace runtime from the environment.
- [x] Keep `runtime` records working for the existing `TerminalActivityRouter`.
- [x] Do not add drag tags or drag overlay work in this branch.

### Task B: Instrument Ghostty Signal Capture

- [x] Trace every non-high-volume Ghostty action received by `Ghostty.ActionRouter`.
- [x] Do not emit per-callback Ghostty records for high-volume callbacks such as `.scrollbar`, `.render`, mouse-state, or key-sequence actions; summarize scrollback growth through the debounced `terminal.activity.*` unseen-activity window from Task C.
- [x] Trace translation into `PaneRuntimeEvent` for non-high-volume actions.
- [x] Classify each signal as `semantic`, `inferred`, `context`, `deferred`, or `unhandled`.
- [x] Add focused tests for representative action translation records.

### Task C: Instrument Terminal Activity Inference

- [x] Trace scrollbar changes as debounced unseen-activity windows instead of per-callback records.
- [x] Add a debounced unseen-activity window model for unattended panes.
- [x] Trace output-burst threshold transitions inside the window.
- [x] Trace window start, extend, and close records.
- [x] Trace progress/url/command-finished activity snapshots.
- [x] Include `is_inferred` and `source` attributes.
- [x] Add tests proving inferred activity does not automatically create inbox notifications.

### Task D: Instrument Runtime And EventBus Consumer Path

- [ ] Trace terminal and bridge events before envelope emission.
- [ ] Trace eventbus post/deliver summaries.
- [ ] Preserve `trace_id`/domain IDs when possible.

### Task E: Instrument Inbox Decisions

- [x] Trace every inbox-relevant classify decision.
- [x] Do not emit inbox ignore records for high-volume activity-only events such as `.scrollbarChanged`; the `terminal.activity.*` debounced window is the evidence for that path.
- [x] Include ignored reasons.
- [x] Trace append/read/dismiss/count changes.
- [x] Add tests for attended-pane suppression, below-threshold suppression, bell-disabled suppression, and activity-only suppression.

### Task F: Instrument UI Surface Counts

- [ ] Resolve whether scoped count calculations need view models before tracing. Counts must be headlessly testable before this task starts.
- [ ] Toolbar bell count.
- [ ] Pane inbox bell count.
- [ ] Pane inbox popover open/row count.
- [ ] Worktree pill count.
- [ ] Sidebar inbox row count.

### Task G: Instrument Focus And Pane Inbox Interactions

- [ ] Attended pane changes.
- [x] Pane inbox button click / request / close / presentation state.
- [ ] Pane inbox row activation.
- [ ] Focus-pane action path.

### Task H: Capture Evidence And Convert To Tests

- [x] Create `docs/wip/debugging/2026-05-02-luna361-notification-cli-trace-smoke.md`.
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
