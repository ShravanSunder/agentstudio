# Notification Claim Promoter

## Goal

Build the notification path around one promotion owner so terminal scrollback,
explicit runtime events, pane visibility, and PaneInbox rows all follow the same
claim/session rules.

The system should answer one product question:

> Did something require attention while the user was not observing the source
> pane, and if so, how should it appear without spamming duplicate rows?

## Model

### Evidence vs product facts

Terminal scrollback growth is evidence. It remains visible in JSONL tracing as
`terminal.activity.outputBurst`, `terminal.activity.unseenWindowStarted`,
`terminal.activity.unseenWindowExtended`, and
`terminal.activity.unseenWindowClosed`.

The product fact emitted to the runtime bus is:

```swift
PaneRuntimeEvent.terminalActivity(.unseenActivitySettled(...))
```

That fact is emitted only after a quiet debounce. Raw scrollbar activity does
not append inbox rows directly.

### Claim identity

Notifications that can belong to the same user-visible attention unit carry an
`InboxNotificationClaimKey`:

```swift
InboxNotificationClaimKey(
    paneId: UUID,
    lane: InboxNotificationClaimLane,
    semantic: InboxNotificationClaimSemantic,
    sessionId: UUID?
)
```

`paneId` is the source pane or drawer child pane. `sessionId` is the current
attention session for mergeable lanes.

### Lanes

| Lane | Purpose | Merge behavior |
| --- | --- | --- |
| `actionNeeded` | Prompt/input/approval style attention | Can merge with activity for the same pane/session. |
| `activity` | Scrollback, command finished, bell, desktop/RPC notices | Can merge with action-needed for the same pane/session. |
| `safety` | Security, renderer, secure input, persistence recovery | Does not merge with activity sessions. Repeated edges create separate rows. |

Generic `agentNotificationRequested` remains `.agentRpc`. It is not treated as
input-required until the bridge has a typed payload or a separate event that
actually carries that semantic.

## Promotion Owner

`InboxPromoter` is the single mutation owner for promoted notifications. It:

1. Builds from a synchronous `InboxPolicySnapshot`.
2. Resolves or creates activity sessions.
3. Applies exact-claim and same-pane/session merge rules.
4. Applies auto-clear/read-history behavior for observed panes.
5. Emits `inbox.promote` trace records.

`InboxNotificationRouter` still classifies events and owns runtime-bus
subscription, but it delegates mutation to `InboxPromoter`.

## Visibility Policy

The policy snapshot is plain value data:

```swift
InboxPolicySnapshot(
    attendedPaneId: UUID?,
    observedPaneIds: Set<UUID>,
    pinnedToBottomByPaneId: [UUID: Bool]
)
```

Rules:

1. The currently attended pane is observed.
2. Visible panes in the active tab are observed.
3. If a drawer is expanded, the active visible drawer child is observed and the
   parent pane is hidden for notification purposes.
4. Hidden drawer children are not observed.
5. Minimized or zoom-hidden split siblings are not observed.
6. Auto-clearable notifications from an attended pane append read/dismissed
   history instead of unread rows.
7. Auto-clearable notifications from an observed bottom-pinned pane append
   read/dismissed history.
8. Observed but scrolled-up panes can create unread rows.
9. User-action-required and safety notifications stay unread until explicit
   user action.

## Terminal Activity Flow

```text
Ghostty scrollbarChanged
    │
    ▼
TerminalActivityRouter updates TerminalActivityAtom
    │
    ├─ Trace evidence:
    │    terminal.activity.unseenWindowStarted
    │    terminal.activity.unseenWindowExtended
    │    terminal.activity.outputBurst
    │    terminal.activity.unseenWindowClosed
    │
    ▼
quiet debounce settles
    │
    ▼
PaneRuntimeEvent.terminalActivity(.unseenActivitySettled)
    │
    ▼
InboxNotificationRouter classification
    │
    ▼
InboxPromoter promoteSettledActivity
    │
    ▼
InboxNotificationAtom upsertByClaim
```

The quiet debounce uses injected `Clock<Duration>` in tests. No notification
test should rely on wall-clock sleeps.

## Merge Rules

1. An unread, mergeable exact claim key updates in place.
2. If exact claim does not match, a new mergeable claim can still merge with an
   unread mergeable row for the same pane and session.
3. Stronger lanes win display content:
   `actionNeeded` > `safety` > `activity`.
4. Auto-cleared read/dismissed history can still coalesce while the pane remains
   observed and bottom-pinned, or attended, so visible continuous output does not
   create history spam.
5. Read/dismissed rows outside the current observed session do not absorb future
   activity.
6. Stale sessions beyond
   `AppPolicies.InboxNotification.terminalActivitySessionIdleTimeoutDuration`
   do not absorb future settled activity.
7. Safety rows do not exact-key coalesce through the activity-session path.

## Policy Constants

Behavioral constants live under `AppPolicies.InboxNotification`:

```swift
terminalActivityOutputBurstThresholdRows
terminalActivityQuietDebounceDuration
terminalActivitySessionIdleTimeoutDuration
```

Presentation constants stay in `AppStyles`.

## Test Pyramid

Unit and pure-model tests:

- `InboxNotificationClaimTests`
- `NotificationTests`
- `PaneInboxAutoClearPolicyTests`
- `InboxPromoterTests`
- `TerminalActivityDerivedEventTests`
- `NotificationReducerTests`
- `RuntimeEnvelopeTraceSummaryTests`
- `EventReplayBufferTests`

Router and event-bus tests:

- `InboxNotificationRouterTests`
- `InboxNotificationRouterObservedPaneTests`
- `InboxNotificationRouterDrawerChildTests`
- `TerminalActivityRouterTests`

Integration tests:

- `DerivedTerminalActivityNotificationIntegrationTests`
- `InboxNotificationIntegrationTests`
- `PaneTabViewControllerPaneInboxDispatchTests`

Coverage requirements:

- No row before terminal activity settles.
- One row for continuous output in the same pane/session.
- Focused/attended pane output creates no unread PaneInbox row.
- Visible active-tab sibling at bottom clears/appends read history.
- Visible active-tab sibling scrolled up creates unread.
- Hidden drawer child creates unread.
- Active drawer child is observed.
- Parent PaneInbox includes drawer-child notifications.
- Explicit action-needed can upgrade activity for the same session.
- Activity upgrades preserve existing denormalized source labels.
- Safety rows can coexist and do not collapse repeated edge notifications.
- Auto-cleared read/dismissed history coalesces while observed; read/dismissed or
  stale sessions outside that observed window do not absorb future settled
  activity.
- Reading or dismissing an upgraded activity row invalidates the source activity
  window.
- `inbox.promote` includes decision, reason, lane, semantic, pane, and terminal
  activity attributes.

## Follow-Ups

Typed bridge notification intent is not part of this slice. Generic
`inbox.post` remains `.agentRpc`. A future bridge payload can add an explicit
intent such as `inputRequired`, but that should be a separate typed event/API
change with compatibility-free call-site updates and tests.

Terminal content extraction is also out of scope. This slice uses scrollbar
growth as the derived activity signal; it does not inspect prompt text or model
output content.
