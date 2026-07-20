# Ghostty Host Boundary and Terminal Interaction Fairness Spec

Date: 2026-07-09
Revised: 2026-07-10 after adversarial spec review
Status: accepted technical contract after adversarial review
Scope: pre-plan architecture contract
Ghostty anchors: pinned `332b2aef` (1.3.1); compared with upstream
`7e02af87980bfdaad6d393b985d35c917476878e`
Runtime dominance: unresolved; callback and host-boundary topology is source-proven

Parent contract: [AgentStudio Performance Boundaries](../2026-07-10-agentstudio-performance-boundaries/agentstudio-performance-boundaries.md)

Normative action contract:
[Ghostty Action Admission Manifest](ghostty-action-admission-manifest.md)

## Product Intent

AgentStudio's terminal must remain immediate while the rest of the workspace is
busy. A user typing a character, moving the terminal caret with an arrow key,
moving the mouse in a TUI, switching panes, or revealing a hidden terminal must
not wait behind watched-folder scans, topology import, global event fanout,
Bridge refresh, or redundant terminal sample processing.

AgentStudio must also understand useful terminal and agent state without
turning raw Ghostty callbacks, screen updates, scroll state, or terminal text
into a global event stream. Notifications, unseen output, agent-settled
heuristics, command completion, secure input, renderer health, and explicit
agent reports must survive the redesign with clearer provenance and lower
traffic.

The Ghostty integration has two independently attributable performance axes:

1. **libghostty internals.** Newer Ghostty adds PTY gather/reader overlap, VT
   parsing improvements, renderer lock/fairness changes, hidden-surface savings,
   and scrollback memory improvements.
2. **AgentStudio host behavior.** Wakeup/action MainActor scheduling, event
   admission, surface lifetime, geometry refresh, visibility, display identity,
   and product routing remain the embedder's responsibility.

An upgrade may improve bulk throughput and heavy-output frame fairness. It
cannot make AppKit deliver an event while AgentStudio monopolizes MainActor, nor
can it remove host-created tasks or global events. Both axes must be measured.

## User-Visible Success

The product endpoints are interaction and visible feedback, not only bytes per
second. Precision proof uses the selected frame-layer-publication seam below
and names its distance from physical scanout:

- `NSEvent` dispatch to terminal input-handler entry;
- handler entry to return from `ghostty_surface_key`, text, or mouse input;
- character key to visible echo using a deterministic local fixture;
- arrow key to visible terminal-caret movement;
- TUI mouse event to visible response when mouse reporting is enabled;
- Ghostty mouse-shape action to applied `NSCursor` state;
- pane selection to focus, visibility, and first current frame;
- output arrival to a newly published Ghostty frame under sustained ASCII,
  Unicode, and CSI, with separate native proof that the result becomes visible;
- hidden/minimized surface CPU and reveal freshness;
- terminal memory after scrollback fill, idle, prune, and clear.
- cold launch to active-terminal typing readiness, plus bounded completion of
  every restorable background terminal without waiting for repository startup.

Key-to-echo is not meaningful for secure input, disabled local echo, remote
latency, or an application that intentionally withholds output. The benchmark
uses a deterministic local echo/cursor fixture and records host-input,
terminal-response, frame-layer-publication, and native-visible outcomes
separately.

## Current-State Evidence

All AgentStudio observations below are anchored to `cd47c511`.

### Ghostty Execution Model

```text
AppKit key/mouse event [MainActor]
  -> synchronous ghostty_surface_key/text/mouse call
  -> PTY / terminal core
  -> Ghostty IO + renderer threads
  -> libghostty-owned IOSurfaceLayer / display link

Ghostty producer thread
  -> bounded app mailbox (capacity 64)
  -> wakeup_cb
  -> AgentStudio Task { @MainActor }
  -> ghostty_app_tick drains mailbox
  -> synchronous action_cb for each action
  -> AgentStudio Task { @MainActor } for each routed action
  -> local state / replay / EventBus / MainActor consumers
```

AgentStudio does not parse VT data or draw Metal frames on MainActor. It has no
`ghostty_surface_draw` call. Ghostty installs and owns the renderer-backed layer,
renderer thread, draw scheduling, and display link.

### Supported Host-Boundary Findings

- Ghostty's app mailbox is bounded at 64. A push invokes the embedder wakeup,
  and one app tick drains the mailbox
  (`vendor/ghostty/src/App.zig:126-132,237-265,568-584`).
- The 64-item capacity bounds resident queue size, not total service in one
  `ghostty_app_tick`. The tick drains `while (mailbox.pop())`, so producers can
  refill while MainActor remains inside the same call. The embedded ABI exposes
  no partial-drain or host time-budget control.
- AgentStudio schedules one independent MainActor task per wakeup with no
  pending-tick coalescer. It reconstructs an unretained `App` from raw pointer
  bits only inside the delayed task
  (`GhosttyCallbackRouter.swift:15-30`).
- Mailbox-originated actions execute synchronously inside the MainActor tick,
  but `routeActionToTerminalRuntime` unconditionally schedules another
  MainActor task per routed action
  (`GhosttyAppHandle.swift:93-96`;
  `GhosttyActionRouter.swift:662-700`).
- The second hop delays host/runtime state, can outlive or remap a surface, and
  re-expands a tick's already-batched actions. It also returns Ghostty's handled
  result before later routing succeeds or fails.
- Direct embedded C entry points can synchronously produce actions on their
  caller's thread. A fast path must distinguish actions emitted inside a known
  MainActor tick from genuinely foreign-thread callbacks.
- Scrollbar, progress, cell-size, search, mouse, key-table, and related UI
  samples enter `TerminalRuntime`, and many are replayed. `PaneRuntimeEventChannel`
  performs local fanout and shares a `bufferingNewest(128)` outbound queue across
  samples and semantic facts before global EventBus fanout
  (`TerminalRuntime.swift:196-313,349-363`;
  `PaneRuntimeEventChannel.swift:29-38,114-176`).
- `WorkspaceSurfaceCoordinator` resolves the source tab before explicitly
  ignoring most presentation events. The lossy 16 ms scheduler acts only after
  callback tasks, local mutation, envelope creation, optional replay, outbound
  buffering, global replay, and fanout
  (`WorkspaceSurfaceCoordinator.swift:432-514`).
- Scrollbar and progress are not simply useless. `TerminalActivityRouter` and
  `InboxNotificationRouter` use them for pinned-bottom edges, unseen output,
  quiet/settled windows, agent activity, progress errors, and inbox clearing.
- CWD travels through both the SurfaceView/SurfaceManager stream and the
  TerminalRuntime/global EventBus path before canonical atom equality can
  suppress the final duplicate write
  (`GhosttySurfaceView.swift:300-313`;
  `WorkspaceSurfaceCoordinator.swift:244-285,490-494`).
- `TerminalSurfaceScrollView.layout()` sets the surface frame size and also
  explicitly synchronizes core size. Identical geometry is classified `.skip`,
  but `.skip` still calls `ghostty_surface_refresh`
  (`TerminalSurfaceScrollView.swift:143-153,264-270`;
  `GhosttySurfaceView.swift:138-198,673-803`).
- Surface visibility is not equivalent to real visibility. Mounted surfaces are
  marked core-visible; inactive tab hosts and window occlusion/minimization do
  not consistently reach Ghostty's occlusion API. AgentStudio also has no
  `ghostty_surface_set_display_id` call.
- `SurfaceView.deinit` directly calls `ghostty_surface_free`, although deinit is
  not actor-guaranteed. Upstream explicitly transfers surface destruction to
  MainActor (`GhosttySurfaceView.swift:462-475`;
  `vendor/ghostty/macos/Sources/Ghostty/Ghostty.Surface.swift:15-35`).
- The embedded public header exposes refresh/draw requests and display-ID input,
  but no callback for renderer start, IOSurface publication, GPU completion, or
  display presentation. Those seams exist only inside Ghostty's renderer
  implementation (`ghostty.h:1057-1139`; `renderer/Metal.zig:235-264,398-408`;
  `renderer/metal/Frame.zig`).
- App and surface callback userdata currently point at unretained Swift objects.
  Wakeup and close callbacks reconstruct those objects after actor hops, while
  clipboard callbacks reconstruct `SurfaceView` and call `NSPasteboard`
  synchronously on the callback thread. The ABI does not promise those callbacks
  originate on MainActor (`GhosttyCallbackRouter.swift:11-57,60-148`;
  `GhosttySurfaceView.swift:370-401`).
- The clipboard ABI supports asynchronous completion: the read callback returns
  whether a request was accepted, and Ghostty retains request state until
  `ghostty_surface_complete_clipboard_request`. AgentStudio therefore need not
  block a foreign callback while waiting for MainActor pasteboard or consent
  work (`apprt/embedded.zig:670-755`).
- On the pinned vendor, `ghostty_surface_free` synchronously removes the surface
  and deinitializes it; core surface teardown joins search, renderer, and IO
  threads before returning. `ghostty_app_free` then destroys the app and
  deinitializes any core surfaces still registered; external embedded surface
  wrappers would be invalid, so host surface ownership must be exhausted first
  (`apprt/embedded.zig:148-151,595-606,1436-1441,1558-1560`;
  `Surface.zig:776-823`; `App.zig:105-115`).
- A renderer thread may already have enqueued `IOSurfaceLayer.setSurface` onto
  the main queue. That block retains the layer and IOSurface and can run after
  renderer-thread join. The current block does not dereference AgentStudio
  userdata, but a benchmark observer added there must be generation-fenced and
  its control block must survive or drain the queued publication
  (`renderer/metal/IOSurfaceLayer.zig:46-78,87-119`).
- Ghostty secure-input semantics have both app-global and surface-scoped forms.
  The upstream macOS owner combines a global request with focused scoped
  requests and yields/reacquires OS state on app deactivation/reactivation.
  AgentStudio's current pane-local Boolean is not an equivalent owner
  (`apprt/action.zig:249-254,592-600`;
  `Ghostty.App.swift:1546-1573`; `SecureInput.swift:5-135`).

### Pinned Versus Current Ghostty

The pinned submodule is Ghostty 1.3.1. Current upstream is more than one
thousand commits ahead and contains several relevant changes:

- a separate POSIX `io-gather` thread with four rotating 64 KiB buffers,
  explicit backpressure, bounded retry/poll behavior, and parser overlap;
- the required request/response latency recovery after the first gather change;
- batched printable codepoints, faster CSI paths, and reduced no-op style work;
- shorter renderer terminal-lock hold and renderer-demand handoff under output;
- invisible-surface frame-update suppression;
- default-on renderer-backed idle scrollback compression and page-memory return.

The current gather implementation uses a 1 KiB saturation threshold, up to 16
immediate retries, a 1 ms poll, and a 3 millisecond total gather budget. The
quoted “3 nanoseconds” is not the current source contract. AgentStudio borrows
the principles of boundedness, contraction, latency preservation, and measured
fairness; it does not copy those constants.

The first gather commit temporarily regressed request/response workloads. Any
upgrade candidate must be after the latency-recovery commit and must be tested
as an atomic header/library/XCFramework cutover.

Current upstream also inserts `GHOSTTY_ACTION_SELECTION_CHANGED`. AgentStudio's
action-tag vocabulary does not include it. Recompiling against the header avoids
numeric-tag drift, but the host still needs an explicit high-rate action policy
to avoid unknown-action warning traffic during selection.

### Unresolved Runtime Questions

- Wakeup rate, outstanding tick-task high-water, and wakeup-to-tick age during
  the reported watched-folder incident.
- Action counts per tick/tag and outstanding action-task high-water.
- Whether redundant geometry refresh or incorrectly visible background surfaces
  materially affect the reported workload.
- Idle and loaded input-to-frame-layer-publication distributions on pinned
  versus candidate Ghostty, plus native visible echo/caret outcomes.
- Whether the `bufferingNewest(128)` outbound channel drops semantic facts when
  presentation samples flood it.
- Accuracy of current scrollbar-based agent-settled inference for TUIs and
  alternate screens.

## Requirements

### Callback Affinity, Lifetime, and Completion

CB1. App runtime userdata and each surface callback userdata point to stable
host-owned callback control blocks, not unretained `App` or `SurfaceView`
objects. The platform `NSView` pointer may remain separate, but explicit surface
teardown keeps the view alive until vendor surface quiescence completes.

CB2. Callback entry acquires a short-lived lease from the matching app/surface
control block before dereferencing host state. The lease carries app generation
and, where applicable, surface generation. Closing admission returns the
callback's declared safe default without reconstructing a stale Swift object.

CB3. Every runtime callback—not only actions—declares possible origin threads,
synchronous return meaning, payload-copy rule, MainActor work, completion rule,
and shutdown default. Undocumented thread affinity is treated as foreign.

CB4. AppKit, `NSPasteboard`, cursor, notification UI, and view mutations execute
on MainActor. A foreign callback never blocks waiting for MainActor. A callback
already inside a host-stamped synchronous MainActor libghostty call uses the
already-isolated fast path without another task.

CB5. Clipboard reads use Ghostty's asynchronous completion contract. The
callback accepts only after creating an exact generation-bound request token;
pasteboard/confirmation work runs on MainActor; completion or denial revalidates
surface and secure-input generations. Exactly-once applies to terminal
settlement, not to the number of C completion calls: an unconfirmed completion
may synchronously enter Ghostty's confirmation callback while preserving the
same opaque request. Clipboard writes copy bounded payloads before any hop and
preserve Ghostty's confirmation policy. Surface teardown terminally settles
every accepted request through the selected vendor's completion API while the C
surface remains live; it never calls completion after surface free.

CB6. Close callbacks create one generation-bound close intent. They do not hold
an unretained view pointer across a task and cannot close a replacement surface.
Close intent delivery is exact while its surface generation remains live.

CB7. Callback telemetry records callback kind and safe origin class, accepted/
rejected/stale/shutdown disposition, payload size class, MainActor enqueue age,
completion outcome, and in-flight lease high-water without content or raw IDs.

### Ghostty App Tick Admission

GT1. There is at most one pending Ghostty app tick per app handle.

GT2. `wakeup_cb` enters the app callback control block from CB1-CB3 and acquires
an owned generation-bearing tick token before any actor hop. Converting a raw
pointer to integer bits or retaining an already-deinitializing Swift object is
not lifetime ownership.

GT3. Wakeup admission is nonblocking, thread-safe, and bounded. Multiple
wakeups while a tick is scheduled or draining mark the gate dirty; they do not
allocate one MainActor task each.

GT4. One scheduled turn invokes `ghostty_app_tick` at most once. A wakeup that
races the drain creates at most one follow-up turn. This bounds host-scheduled
turn amplification; it does not claim one `ghostty_app_tick` has bounded service
time while producers can refill Ghostty's mailbox.

GT5. Tick phase is explicit: `idle`, `scheduled`, `draining`, and
`shuttingDown`. Follow-up-required/dirty state is orthogonal to scheduled versus
draining, or represented by equivalent exhaustive combined states. No transition
may forget whether a turn is already enqueued or executing.

GT6. Shutdown closes callback admission, invalidates pending turns, makes late
callbacks harmless through the still-live control block, explicitly destroys or
transfers all surfaces, and frees the app only after in-flight host callbacks and
vendor surface threads reach the verified quiescence point. The control block is
released only after `ghostty_app_free` returns and the selected vendor contract
guarantees no later callback.

GT7. Telemetry records wakeups, scheduled ticks, executed ticks, coalesced
wakeups, pending high-water, wakeup-to-start age, tick service duration, dirty
follow-ups, actions emitted per tick, synchronous action-capture service,
tick-originated deferred MainActor action hops, contracted presentation samples,
committed presentation mutations, post-tick scheduled MainActor turns, post-tick
MainActor queue age, and shutdown/stale drops. A candidate does not satisfy GT7
when `ghostty_app_tick` service improves while tick-originated deferred work or
observable mutations expand.

GT8. Sustained-producer proof records actions/messages processed per tick and
tick p50/p95/p99/max service. If one tick violates the accepted interaction
budget, the design routes to a libghostty bounded-drain/cooperative-yield API or
another source-proven vendor remedy. Host wakeup coalescing alone cannot satisfy
the fairness claim. A sustained-refill cell is valid only when evidence proves
that producer pushes overlapped the `draining` interval and the same tick
consumed work admitted after tick entry. The benchmark-only adapter records an
entry occupancy/watermark, pushes while draining, pops by tick invocation, and
producer start/stop markers. A preloaded-only or non-overlapping run is invalid,
not a passing low-latency sample.

### Action Callback and Per-Tick Contraction

GA1. C callback payloads are synchronously copied into owned, manifest-bounded
`Sendable` values before any asynchronous handoff. Ephemeral C pointers never
cross a task, and neither a pointer address nor `ObjectIdentifier` survives as
payload or asynchronous identity.

GA2. Actions emitted by any host-owned synchronous libghostty call already on
MainActor—including app tick and direct key/text/mouse/surface calls—use a
synchronous already-isolated path. They do not create one new MainActor task per
action.

GA3. Genuinely foreign-thread actions may enter a bounded action gate only when
their synchronous handled result is valid independently of later delivery. The
gate declares capacity, ordering, exact-versus-contractible classes, overflow
return behavior, and semantic-fact protection.

GA4. Every copied action is bound to a host-issued app/surface token and
generation. Pointer address or `ObjectIdentifier` alone is not stable
asynchronous identity.

GA5. An action from surface generation N cannot mutate generation N+1 after
close/recreate or remapping. Stale work is dropped without dereferencing an old
surface.

GA6. Ghostty's synchronous handled-result contract is preserved. The action
descriptor decides interception/default behavior synchronously; delayed product
routing cannot pretend to retroactively change the callback return.

GA7. Every action descriptor declares allowed callback origins and handled
disposition. An action whose Boolean means “host performed the effect” completes
that host decision synchronously or returns `false`; it cannot return `true`
then enter a lossy/deferred queue.

GA8. One tick or synchronous host call contracts actions by delivery semantics:

- ordered command intents and semantic facts retain order;
- current presentation samples keep the latest value per pane/signal;
- activity inputs use bounded accumulators/windows;
- diagnostic samples use a separate bounded sink;
- no sample can evict close, command-finished, notification, health, secure
  input, or other semantic facts.

GA9. Action telemetry records input count by tag and origin, handled disposition,
contracted counts by delivery plane, runtime applies, semantic facts, stale
drops, and route failures.

GA10. Action-specific vendor fallback is part of the handled-result contract.
For `open_url`, both selected vendors call `internal_os.open` after `false`;
recognized requests therefore return `policyConsumedTrue` after either an
authorized open or deliberate denial, and every denial schedules no later
effect. For `show_child_exited`, `true` suppresses Ghostty's terminal-text
fallback and is permitted only after an equivalent current-generation visible
host presentation commits; fact admission alone returns `false` and preserves
the vendor fallback. These dispositions are source-verified for both selected
vendors and cannot be inferred from the generic Boolean comment.

### Terminal Signal Admission Framework

TS1. Terminal signals are represented by distinct types, not one universal
event enum admitted everywhere:

| Type | Meaning | Global bus | Replay |
| --- | --- | --- | --- |
| `TerminalUISample` | high-rate/latest presentation input | never | never |
| `TerminalActivityInput` | bounded row/progress/attention/report evidence for the activity projector | never raw | never raw |
| `TerminalStateSnapshot` | current readable terminal metadata/state | read/snapshot | state, not history |
| `TerminalDomainFact` | low-rate semantic ordered history | yes | fact-specific bounded history or explicit gap |
| `TerminalCommandRequest` | targeted request with one known owner | direct | none |
| `TerminalDiagnosticSample` | bounded observability only | no product bus | diagnostic retention only |

These type names and their non-overlapping construction APIs are normative.

TS2. Every pinned and candidate Ghostty action has exactly one normative row in
the linked Ghostty Action Admission Manifest. The row declares delivery type,
ordering, semantic capacity/key, replay, expected rate class, consumers,
provenance, sensitivity, origin, synchronous Boolean disposition, and
default-host handling. A missing, duplicate, unknown, or newly added tag fails
the selected-build contract and is rejected at runtime until reviewed.

TS3. Global bus admission requires at least one named non-source consumer and a
semantic reason for history/fanout. “Already translated to `GhosttyEvent`” is
not sufficient.

TS4. Current-state synchronization uses `TerminalStateSnapshot`; presentation
samples do not occupy semantic replay or evict fact history.

TS5. Search, scrollbar, mouse, cell-size, key-table, progress presentation, and
similar state update their pane-local current state without raw global fanout.

The classification is semantic, not a claim that every value is continuously
high-rate:

- terminal search remains important pane-local state: active query, match total,
  and selected match are retained and deduplicated, but not globally replayed;
- scrollbar state remains the latest pane-local rendering value; row-growth and
  pinned/observed evidence feed the contracted activity projector, never raw
  EventBus fanout;
- terminal cursor position is not captured as a runtime sample or fact; cursor
  and caret responsiveness are measured end to end instead;
- filesystem changed paths are not `TerminalUISample`. Their owner unions and
  deduplicates exact paths, contracts overload to dirty subtree/root state, and
  preserves FSEvent continuity/watermark evidence.

TS6. Any product meaning currently derived from those samples moves behind the
pane-local activity projector before global publication.

TS7. CWD, title, health, secure input, close, and other semantic actions have
one authoritative host-to-product pipeline each. Duplicate surface-stream and
runtime-bus paths are not retained as permanent compatibility paths.

TS8. Atoms and observables are state sinks. They do not subscribe to the global
bus, own high-rate queues, derive fleet/product facts, or repost events.

TS9. Terminal-controlled data has an exhaustive content-class disposition.
Raw screen/selection/scrollback content, bounded metadata strings, semantic
lifecycle facts, presentation samples, explicit agent reports, and capability-
bearing secrets may not share an implicit “terminal content” policy. Each class
declares local state, global fact, replay, IPC, routine JSONL, and OTLP handling.

### Pane-Local Activity and Agent State

AI1. A pane-local `TerminalActivityProjector` consumes contracted samples and
produces fewer low-rate facts: output burst start/settle, unseen activity,
likely active/idle/waiting, agent settled/revoked, and notification-relevant
edges.

AI2. Existing pinned-bottom, unseen-output, quiet-window, progress-error,
command-finished, health, and inbox-clearing behavior has parity proof before
raw sample fanout is removed.

AI3. Evidence authority is explicit and ordered:

1. authenticated pane-bound IPC report;
2. existing shell-integration/Ghostty command lifecycle;
3. Ghostty semantic action;
4. pane-local output/quiet heuristic.

This spec introduces no new OSC or shell-hook report protocol. Terminal text
and unknown OSC remain untrusted heuristic input only. A future hook/OSC ingress
requires its own identifier, framing, attribution, limits, lifecycle, and abuse
contract before it can enter this authority order.

AI4. “Higher authority” means stronger attribution, not authorization. An agent
state report cannot grant a permission, approve an action, execute a command,
or mutate another pane.

AI5. Every explicit report carries provenance, pane/session generation,
bounded vocabulary/payload, monotonic sequence where applicable, and a lease.
When the lease expires, heuristic inference resumes.

AI6. Caller-supplied pane IDs are not accepted attribution. IPC uses the
server-recorded pane principal. Existing shell-integration/Ghostty semantic
actions are routed to the host-owned current surface and cannot name another
pane; no new OSC/hook report ingress is authorized.

AI7. “Reported waiting for approval” remains distinct from a permission
broker's actual pending request.

AI8. The terminal runtime lifecycle owner mints one non-persisted
`TerminalRuntimeGeneration` for each successful pane runtime registration and
invalidates it on unregister/replacement. The IPC server reads that current
host-owned generation and stamps every pane-bound agent principal and accepted
report; it does not mint a parallel generation. Caller-supplied generation is
ignored. Pane close, runtime unregister/replacement, or generation change
revokes matching tokens/grants, closes authenticated sockets, expires leases,
and rejects queued reports from the previous generation.

AI9. Authenticated explicit reporting uses two narrow pane-principal methods:
`agent.activity.report` and `agent.notification.post`. Activity vocabulary is
exhaustive: `started`, `running`, `waitingForInput`, `waitingForApproval`,
`idle`, `succeeded`, `failed`, and `cancelled`. A report may include a bounded
principal-scoped report-session ID, task key, controlled progress, and local-
only bounded summary; it cannot supply pane identity, runtime generation, or an
authorization result.

AI10. Authenticated IPC activity report ordering/idempotency uses principal,
server-stamped runtime generation, report-session ID, and monotonic sequence.
Notification deduplication adds a bounded caller dedupe key. Payload size,
per-principal rate, retained recent-report count, lease expiry, and sequence
gaps have explicit rejection/diagnostic policy. Only leased state transitions
or accepted notification facts leave the pane-local projector.

### Screen Text and Secure Input

SC1. Screen text is an explicit pull/capture plane, never a per-render sample,
runtime event, EventBus fact, atom, replay record, or persistence stream.

SC2. Screen reads require a separately named capability/product decision,
pane/session generation, byte/row limit, rate limit, short lifetime, and narrow
authorized consumer.

SC3. Baseline self-pane IPC authority does not imply screen-content authority.
This spec authorizes no screen-capture product slice. If a later product
decision names a requester, recipient, consent surface, and lifetime, the safe
default is an explicit user action rather than agent-initiated capture.

SC4. Secure-input activation fails closed for screen/selection capture, purges
cached content, and invalidates in-flight requests. Completion rechecks both
secure-input epoch and surface generation before returning content.

SC5. Terminal text, prompts, commands, credentials, tool output, titles, URLs,
raw pane/surface IDs, and payload strings never enter OTLP.

SC6. Terminal-controlled strings are length-bounded, schema-validated as data,
notification-rate-limited, and never interpreted as commands, filesystem
authority, cross-pane identity, or authorization claims.

SC7. One app-global `SecureInputOwner` owns the app-global request,
per-surface-generation scoped requests, focused surface, app active state,
desired OS state, last successfully applied OS state or indeterminate failure,
and a monotonic secure-input epoch. Action target determines global versus
scoped request; `toggle` resolves against that authoritative scope. A pane-local
Boolean is a projection, not the authority.

SC8. The owner increments the security epoch and applies conservative capture
fencing before attempting OS activation. Capture is denied for a requesting
surface and whenever global applied state is enabled or indeterminate. Focus,
app activation, request removal, OS-call failure, surface teardown, and app
shutdown have explicit transitions; every successful enable is balanced by the
same owner with disable.

### Surface Input, Geometry, Visibility, and Presentation

SF1. AppKit user input remains a short synchronous call from the MainActor view
boundary into libghostty. Ordinary keys and mouse events are not moved behind a
new actor or product EventBus, and do not read or mutate canonical workspace
atoms or enter persistence before the Ghostty call returns.

SF2. The input path performs no repository lookup, global event processing,
screen parsing, fact publication, runtime replay, or fleet work before calling
Ghostty. Separately emitted Ghostty actions enter the exhaustive action contract
only after synchronous capture/classification.

SF3. `SurfaceGeometryCommitOwner` is the sole owner of content scale and pixel
size commits. One layout pass does not invoke two independent geometry paths.

SF4. Geometry change and render invalidation are distinct. An unchanged
geometry decision does not call refresh without a separate named redraw reason.

SF5. Existing narrow-pane redraw behavior, restore, split resize, Retina scale
change, reparenting, scrollback wrapper, and alternate-screen behavior must
remain correct under the separation.

SF6. Surface render eligibility derives from actual host visibility:
mounted, selected/host-hidden, window occluded/minimized, and app/window state.
Focus is related but not a substitute for visibility.

SF7. Hidden/minimized surfaces keep session and VT state current while avoiding
foreground frame-budget interference. Reveal presents the latest state promptly.

SF8. Window/screen changes forward the current display ID so Ghostty can pace
the display link for 60 Hz, 120 Hz, and multi-display movement.

SF9. All app/surface lifetime-changing libghostty calls execute on their
required owner. `deinit` cannot directly free a surface off-main; explicit
lifecycle/quiescence owns destruction.

SF10. Surface and app generations have explicit teardown transitions. Surface
destruction invalidates routing/capture/IPC admission before `ghostty_surface_free`,
keeps host view/control-block storage alive through its synchronous vendor
thread joins, and releases storage only after in-flight callback leases plus any
host-observing main-queue publication blocks drain or become generation-safe.
All surfaces quiesce before app free. App shutdown closes wakeup/action admission,
invalidates pending turns, calls `ghostty_app_free` on its required owner, and
releases the app control block only after the selected vendor contract guarantees
no later host callback.

SF11. Scrollback memory is a blocking vendor/host non-regression gate. A fixed
fill corpus, event-driven terminal-idle and renderer-quiescent predicates,
clear/prune operation, and stable bounded sample window report resident and
compressed/page-return measures supported by the selected platform. Absolute
and control-relative ceilings are human-approved before candidate acceptance;
a single unqualified RSS snapshot or wall-clock sleep is not proof.

SF12. Accepted workspace composition, not repository topology, unlocks terminal
activation. Its immutable input contains pane UUIDv7 identity, terminal
provider, a required opaque `ZmxSessionID`, launch configuration, visibility
priority, and host-placement identity. It contains no repository/worktree
ownership. The App/coordinator creation owner gives every new terminal pane an
independently generated identity through `ZmxSessionID.generateUUIDv7()` before
atom/graph insertion;
atoms only store the caller-supplied typed value. Repository writers store it
verbatim in the existing SQLite `TEXT` column. Decode accepts every existing
nonblank value, including historical UUIDv4 and `as-*`, as the same opaque typed
identity and uses it exactly. Existing values are not validated as UUIDv7:
UUIDv7 is the generation contract for new identities only. This cut performs no
schema/data migration, conversion, backfill, rewrite, adoption, reconciliation,
or identity repair. No path, topology, pane fragment, or arbitrary new string
can become session identity.

SF13. Composition acceptance freezes one `TerminalRestorableCohort` for its
generation. Terminal activation uses exhaustive priority: active visible, other
visible/expanded drawer, then hidden panes. Every zmx attach receives the exact
stored `ZmxSessionID`. Restore and activation do not discover live sessions,
derive or validate identity from pane/topology state, adopt an existing name,
backfill storage, or mutate canonical composition.

SF14. `windowReady`, `typingReady`, and `allRestorableTerminalsReady` are
distinct current-generation milestones. Typing readiness requires active
surface creation, zmx attachment where applicable, host mounting, focus, and
current-generation runtime readiness; background completion cannot gate it.
`allRestorableTerminalsReady` is an aggregate-settled milestone, not an all-
success claim: every member of the frozen cohort has reached exactly one terminal
outcome—`ready`, `failedTerminal`, or `cancelledReplaced`. Failures
remain explicit in the aggregate receipt.

SF15. Scheduling, prioritization, retry, and state-transition computation
execute off-main in one fleet scheduler with bounded
in-flight operations; there is no task-per-pane or actor-per-pane fanout.
Ghostty surface creation, AppKit host mounting, and focus remain MainActor-owned
through a bounded service quantum that yields between panes and rechecks priority
before each admission. After foreground readiness, sustained foreground
promotion cannot starve the background cohort: the scheduler admits background
progress within the calibrated maximum foreground burst unless that member is
closed or replaced.

SF16. Attach progress is runtime state, not canonical `Pane` mutation. The
runtime owner exposes a strict union for queued, attaching, ready, failed-
terminal/retryable, and cancelled/replaced states keyed by pane/runtime
generation. Attach failure is explicit and never blocks unrelated foreground
readiness or mutates the stored identity.

SF17. CWD/title/activity updates may follow attachment through their typed
lanes. Repository matching is a derived external projection and cannot delay,
cancel, or destroy a terminal runtime. Repository/filesystem/Git/topology work
cannot block pane attachment or mutate composition, residency, or zmx identity.

### Ghostty Version Cutover

GV1. Header, static library/XCFramework, resources, Swift compile, and action-tag
vocabulary move atomically. Mixing an old header with a new binary is invalid.

GV2. An upgrade candidate includes the request/response latency recovery after
the initial gather pipeline.

GV3. Every new/changed action tag, including selection changed, receives an
explicit admission/default-host policy before the upgrade is accepted.

GV4. The version cutover is independently benchmarked from host-boundary
changes using the factorial matrix below.

GV5. Bulk-throughput gains are not used as proof of idle typing latency.

GV6. The benchmark candidate is exactly
`7e02af87980bfdaad6d393b985d35c917476878e` unless this spec is revised. Every
cell records vendor commit, generated header, library/XCFramework, resources,
Swift host revision, action-policy manifest, `compatibilityAdaptationDigest`,
and `measurementProbeDigest`. A newer candidate requires renewed delta and ABI
review.

GV7. Version-specific host adaptation is separated from host contraction. A
vendor-only claim is permitted only when pinned and candidate cells use a
semantically equivalent measurement/action adapter or an adaptation-control
cell proves its cost. Otherwise the report labels the result “vendor plus
mandatory adaptation.” Benchmark-only adaptation does not become a permanent
dual-version product path. Compatibility adaptation and measurement probes are
separate manifests; equivalent source placement is not evidence that either is
performance-neutral.

GV8. The causal fixture marker and internal frame observer exist only in the
isolated performance build identity. Stable, beta, and ordinary debug product
builds neither recognize the marker nor export the observer ABI. Build-manifest
proof and a negative production-symbol/behavior check enforce that boundary.
Per-vendor compiled-disabled versus probe-enabled calibration bounds the probe's
effect on idle input, loaded throughput/frame cadence, MainActor delay, and
native behavior. Over-budget or materially unequal perturbation invalidates
internal precision data for absolute product-latency acceptance.

## Technical Contract

### Boundary / Separability Map

```text
Ghostty producer threads
  own: libghostty IO/renderer work and bounded app mailbox
  expose: wakeup callback + synchronous action callback ABI

                         wakeup
                           |
                           v
AppCallbackControlBlock + GhosttyTickGate
  own: callback leases, app generation, phase + orthogonal dirty state
  exposes: at most one pending MainActor tick

                           |
                           v
MainActor ghostty_app_tick
  invokes: one full vendor mailbox drain per scheduled host turn
  limitation: current ABI cannot preempt/budget a drain under concurrent refill
  action callback -> synchronous payload copy + origin/return descriptor

            +--------------+----------------+----------------+
            |              |                |                |
            v              v                v                v
  host presentation   activity sample   command intent   domain fact
  latest-by-key       bounded window    targeted owner   ordered/replay policy
            |              |                                 |
            v              v                                 v
  TerminalState       TerminalActivityProjector      RuntimeFactBus
  Snapshot            owns pane heuristics/leases        semantic only
            |              |
            |              +---- low-rate facts ---------+
            v
  SurfaceView / SwiftUI local observation

Ghostty renderer threads
  own: VT/render state, Metal draw, IOSurface presentation, display link
  host supplies: correct geometry, occlusion, focus, display ID, lifetime

accepted composition
  -> TerminalActivationScheduler (off-main priority/currentness)
  -> bounded MainActor surface create/attach/mount/focus
  -> active typing-ready milestone
  -> cooperative background-restorable completion

repository/filesystem/Git startup
  -> independent actors and derived pane-location projection only
```

### Normative Terminal Types And Hard Cutover

The names and responsibilities in this section are the selected architecture.
Planning maps them to source files and existing owners; it may not replace them
with actor-per-pane, legacy event replay, or a second terminal pipeline.

```swift
struct TerminalRuntimeGeneration: Hashable, Sendable {
    let paneID: PaneId
    let value: UInt64
}

struct GhosttyAppToken: Hashable, Sendable {
    let generation: UInt64
}

struct GhosttySurfaceToken: Hashable, Sendable {
    let app: GhosttyAppToken
    let surfaceID: UUID
    let generation: UInt64
}
```

`AppCallbackControlBlock` and `SurfaceCallbackControlBlock` are retained Swift
objects passed to C with stable opaque pointers. They—not `Ghostty.App`, an
AppKit view, `ObjectIdentifier`, or an allocator address—own callback admission,
open/closing state, current token, in-flight lease count, tick/action gates, and
the final release condition. Their state is held in a nonrecursive lock-backed
cell; callback entry does not await an actor or enqueue a task merely to check
lifetime.

`CallbackLease` is acquired synchronously only while the block is open and its
token matches. It owns a strong reference to the block until release. Closing
rejects new ordinary leases, invalidates queued generation work, and waits for
the source-verified vendor quiescence point plus lease drain before C storage or
the control block is released.

#### Host call and user-intent scope

Every host-owned synchronous libghostty call is wrapped in one stack-scoped
`GhosttyHostCallScope`:

```swift
enum GhosttyHostCallKind: Sendable {
    case appTick
    case userKey
    case userMouseButton
    case userMouseMotion
    case userScroll
    case textInput
    case programmaticInput
    case bindingQuery
    case geometry
    case focusOrVisibility
    case surfaceLifecycle
    case clipboardCompletion
}

enum UserIntentPurpose: Sendable {
    case workspaceCommand
    case openURL
    case clipboardWrite
}

@MainActor
protocol UserIntentGate: AnyObject {
    func claim(_ purpose: UserIntentPurpose) -> Bool
}

struct GhosttyHostCallScope {
    let app: GhosttyAppToken
    let surface: GhosttySurfaceToken?
    let kind: GhosttyHostCallKind
    let userIntent: (any UserIntentGate)?
}
```

Only a current-generation `.userKey` or `.userMouseButton` host call creates one
event-scoped `UserIntentGate`, and only for the synchronous C-call extent
causally nested in that AppKit event. The gate begins unbound because the public
Ghostty ABI can report only that a key is a binding, not which action it will
emit. The first eligible action descriptor atomically claims one purpose—
`workspaceCommand`, `openURL`, or `clipboardWrite`—and consumes the gate. A
second action, including a chained binding of the same or another purpose, is
denied. The gate cannot survive return, cross an actor/task hop, be reconstructed
from terminal text, or exist for `.appTick`, mouse motion, scrolling, text/
programmatic input, replay, IPC, lifecycle, geometry, or a foreign callback.
Recognized open-URL denial consumes vendor fallback as the action manifest
requires; absence or prior consumption never schedules a later effect.

#### Tick gate and host turn

`GhosttyTickGate` lives in `AppCallbackControlBlock` and owns one lock-protected
phase/dirty state. A wakeup mutates this cell and schedules at most one
MainActor turn. The selected state machine later in this spec is normative;
there is no actor call, spin loop, or task per wakeup.

One `GhosttyHostTurnContext` exists only around one `ghostty_app_tick`. It may
contract presentation samples and collect committed fact sequence ranges for
one downstream publication. It may not hold the sole copy of an exact fact or
delay exact callback truth until tick return. Its memory is bounded by declared
sample keys and range metadata, not by total actions processed during an
unpreemptible tick.

#### Terminal signal owners

```text
TerminalPresentationState       @MainActor, pane-local current UI state
TerminalPresentationMailbox     foreign-thread latest values only
TerminalFactOwner               @MainActor, generation/sequence/current facts
TerminalActivityMailbox         pane-keyed bounded accumulators/latest input
TerminalActivityProjector       one shared actor, fair across ready panes
TerminalWorkspaceCommandSink    MainActor adapter to existing command resolver
RuntimeFactBus                  semantic publication only
```

`TerminalFactOwner` synchronously validates surface/runtime generation and
commits current state or an ordered fact sequence before an exact callback
reports acceptance. Its bounded journal uses the parent `OrderedFactJournal`
contract. If a non-reconstructible occurrence cannot be retained, it commits an
explicit `TerminalFactGap`, marks the fact stream non-current, fails affected
waits/replay, and makes the run invalid; it never reports normal delivery.
Renderer health and metadata additionally retain a current snapshot so a gap
can resynchronize current state. Bell/desktop notification abuse rejection is a
deliberate request-policy outcome, not an exact-fact gap.

For both selected vendors, title, tab-title, and PWD actions are restricted to
host-scoped calls: IO-originated changes first enter the Ghostty app/surface
mailbox and are handled on the app thread, while binding/lifecycle emissions are
inside a direct host call. The `SA` policy therefore has no foreign-thread
success path. A future vendor that emits one of these actions directly from a
foreign thread requires spec reconvergence and a named synchronous metadata
journal; it cannot reuse the presentation mailbox or wait for MainActor.

`TerminalPresentationMailbox` is used only when the manifest proves a
presentation action can arrive outside a MainActor host scope. It keeps latest
values by `(surface generation, signal key)`, schedules one MainActor apply, and
cannot contain facts, commands, activity deadlines, or strings without that
signal's declared bound. Already-MainActor presentation actions apply directly
to `TerminalPresentationState`; they do not enqueue back to MainActor. Surface
teardown invalidates the exact generation and removes its retained latest values;
every queued apply revalidates that generation, so generation N presentation
cannot commit after teardown or mutate generation N+1.

`TerminalActivityMailbox` merges by `(TerminalRuntimeGeneration, activity key)`
before actor admission. It retains latest rows/pinned/progress state,
accumulated row growth/counts, current evidence provenance, and exact lease/
deadline changes in separate storage. It schedules at most one ready signal per
pane generation.

`TerminalActivityMailbox` and `TerminalFactOwner` are separate custody owners.
Activity contraction cannot hold, evict, acknowledge, or replay an exact fact,
and there is no generic lossy semantic-fact mailbox between action capture and
`TerminalFactOwner`.

`TerminalActivityProjector` is one shared actor keyed by pane/runtime generation,
not one actor per pane and not a global raw FIFO. It owns quiet windows,
deadlines, explicit-report leases/sequences, semantic/heuristic precedence,
settled/revoked state, dedupe, and a fair ready-pane queue. One drain processes a
bounded amount per pane before requeue; one saturated pane cannot indefinitely
delay another pane's deadline. Its public keyed contract permits later internal
sharding only if measured fairness requires it.

`TerminalWorkspaceCommandSink` synchronously adapts a user-intent-scoped
`TerminalCommandRequest` into the established `PaneTabViewController` workspace
command resolver. Terminal-local input/scroll/prompt commands stay with the
targeted terminal runtime/surface dispatcher. Commands never use the fact bus.
A Ghostty Boolean meaning “host performed” is `true` only after the command
owner synchronously commits the canonical command effect; otherwise it is
`false`.

Destructive commands that close the originating pane/surface use a two-stage
contract. The synchronous callback commits exactly one current-generation
closing transition and registers one bounded cleanup entry in the current
`GhosttyHostCallScope`; that commit is the handled product effect. Physical
surface quiescence/free occurs when the outermost host call unwinds, after the
originating C stack returns. The cleanup entry is exact, MainActor-local, and
generation-checked; it is not an unstructured task and cannot be dropped.

#### Exhaustive current-owner disposition

| Signal plane | Current producer disposition | Target owner | Global fact/replay |
| --- | --- | --- | --- |
| scrollbar, search totals/selection, mouse shape/visibility/link, cell/size limits, key sequence/table, color, read-only, progress current state | remove terminal emission through `PaneRuntimeEventChannel`; direct MainActor apply or foreign latest mailbox | `TerminalPresentationState` | none |
| row growth, pinned/observed state, progress error edge input, explicit agent report, semantic activity evidence | remove global raw bus consumption | `TerminalActivityMailbox` -> `TerminalActivityProjector` | projector emits changed low-rate activity facts only |
| title, tab title, CWD, renderer/secure-input health current state | one authoritative host pipeline; dedupe equal state | `TerminalFactOwner` plus named MainActor applier | topic fact only when a named cross-feature consumer exists; latest recovery |
| command finished | synchronous authoritative journal commit | `TerminalFactOwner` | `terminalCommand` ordered topic history with explicit gap |
| terminal lifecycle | synchronous authoritative current-state/transition commit | lifecycle owner plus `TerminalFactOwner` projection | `terminalLifecycle` latest state plus `paneLifecycle` ordered transitions where named |
| bell and desktop notification | bounded policy admission | inbox/notification owner | accepted occurrence only; inbox owns durable history |
| tab/split/close/navigation/undo/redo/config request | direct typed command | terminal or workspace command sink | none |
| diagnostics/deferred/unhandled/render samples | diagnostic sink | performance/diagnostic owner | never product replay |

Terminal runtimes stop using `PaneRuntimeEventChannel`, its local replay, and
the `WorkspaceSurfaceCoordinator` runtime-event bridge. The channel may remain
only as local subscription/replay machinery for browser/diff/editor/plugin
runtimes; its global outbound stream and `PaneRuntimeEventBus` are removed under
the parent transport cutover. Their semantic global outputs construct typed
`RuntimeFactEnvelope` values. `NotificationReducer` no longer classifies terminal
traffic as critical/lossy. Presentation/activity samples never enter semantic
replay or durable persistence; deduplicated title/CWD or other current metadata
uses its named authoritative owner and publishes only a declared semantic fact.
Contraction happens at the owners above. The current `TerminalActivityRouter`
transport role is replaced by
`TerminalActivityProjector`; its semantic parity oracle remains normative.

Terminal `subscribe()`/`eventsSince` behavior is replaced by current
`TerminalStateSnapshot` reads and `TerminalFactOwner.facts(after:)`. The IPC
runtime adapter selects that terminal-specific contract for terminal wait and
status, including explicit fact gaps/resynchronization. It never recreates a
legacy terminal `RuntimeEnvelope` or observes the global bus for pane-local
waits.

There is no dual publication during or after cutover. A terminal fact has one
authoritative owner and one optional semantic bus publication path.

### Callback Control-Block Contract

The runtime config's app userdata references one stable
`AppCallbackControlBlock`. Every surface config's callback userdata references a
stable `SurfaceCallbackControlBlock` linked to that app generation. Neither
block is the AppKit view or the Swift app object.

```text
callback enters
  -> acquire lease if control block is open/current
  -> stamp callback origin and app/surface generation
  -> copy ephemeral payload needed after return
  -> run synchronous already-MainActor decision, or enqueue bounded typed work
  -> release lease

surface shutdown
  -> close surface admission + invalidate generation
  -> remove secure-input request
  -> runtime lifecycle invalidates generation and revokes matching principal
  -> invalidate queued intents/samples for that generation
  -> deny/complete accepted clipboard requests while C surface is live
  -> ghostty_surface_free on MainActor
       pinned contract joins search + renderer + IO threads synchronously
  -> drain already-entered callback leases
  -> drain or generation-drop already-queued host-observing layer publications
  -> release view and surface control block

app shutdown
  -> stop surface creation; close tick/action admission
  -> quiesce every surface as above
  -> invalidate pending generations; admit teardown completions only
  -> ghostty_app_free on MainActor
  -> drain already-entered app callback leases
  -> release app control block and config
```

No foreign callback waits synchronously for MainActor, so teardown cannot
deadlock by waiting on a callback that is itself waiting for the actor. The
pinned join behavior is a verified vendor contract, not an assumption carried
across upgrade: the candidate must show equivalent quiescence before GV1 can
pass.

Clipboard callbacks use the same blocks but their ABI-specific completion
matters. Read acceptance creates a request token before returning `true`; the
token owns the opaque Ghostty request pointer until one terminal settlement.

```text
accepted
  -> readingOnMainActor
  -> completingUnconfirmed
       -> terminallySettled            [no confirmation callback]
       -> awaitingConfirmation          [confirm callback preserves pointer]
  -> completingConfirmedOrDenied
  -> terminallySettled
```

The confirmation callback is reentrant with the unconfirmed C completion. It
copies any ephemeral string, records `awaitingConfirmation`, and never releases
the opaque pointer. Only the later confirmed or denied completion makes the
token terminal. Teardown closes ordinary callback admission but keeps this
teardown-completion lane live, rejects new reads, and drives every nonterminal
token to a confirmed-empty/denied terminal response before C-surface free. The
selected pinned/candidate headers expose no cancellation API, so cancellation
is not an implementation option unless a future vendor contract is separately
source-verified. No state calls completion through the old pointer after free.

### Tick Gate State Machine

```text
state = phase + dirty bit

idle(clean)
  -- wakeup -----------------------> scheduled(clean) [enqueue one turn]

scheduled(clean|dirty)
  -- wakeup -----------------------> scheduled(dirty) [no second task]
  -- turn starts atomically -------> draining(clean)
       pre-start wakeups precede this tick; clear their dirty bit

draining(clean|dirty)
  -- wakeup -----------------------> draining(dirty) [follow-up required]
  -- tick returns, clean ----------> idle(clean)
  -- tick returns, dirty ----------> scheduled(clean) [enqueue one follow-up]

any live phase
  -- shutdown ---------------------> shuttingDown [close admission/generation]
```

The gate never spins or recursively ticks on a foreign callback thread. It
bounds queued host turns and preserves a raced-wakeup follow-up. It does not
bound service inside `ghostty_app_tick`: current Ghostty drains until `pop()`
returns empty, and producers can refill concurrently. Tick duration and messages
processed are therefore hard acceptance evidence. An over-budget maximum blocks
the full fairness claim and routes to a bounded-drain/cooperative-yield vendor
contract; averages or a bounded resident queue do not waive that gate.

### Action Admission Manifest

The linked
[Ghostty Action Admission Manifest](ghostty-action-admission-manifest.md) is the
normative exhaustive table for all 65 pinned tags and candidate-only selection
changed. Every row includes:

- allowed callback origins: `appTick`, `directMainActorHostCall(GhosttyHostCallKind)`, or
  declared `foreignVendorThread`;
- callback return disposition: `hostCompletedTrue`, `hostDeclinedFalse`,
  `exactRequestAcceptedTrue`, `policyConsumedTrue`, `hostPresentedTrue`, or
  another source-proven action-specific default/interception;
- payload-copy and surface/app-generation requirements;
- signal plane, contraction, ordering, replay, consumers, and sensitivity.

The host stamps an origin scope around every MainActor-owned synchronous C call,
not only `ghostty_app_tick`. A callback with no live host scope is foreign even
if it happens to run on the main thread. An action whose Boolean means the host
performed the effect may use `hostCompletedTrue` only after the effect is
complete. `exactRequestAcceptedTrue` is allowed only for a non-evictable,
generation-bound authoritative commit whose acceptance itself satisfies
Ghostty's immediate contract. Selected non-reconstructible facts that Ghostty
does not retry cannot use capacity refusal as recovery: they synchronously
commit the fact or an explicit fact-gap/error disposition before returning.
Invalid/stale generation returns `false`; a committed gap never masquerades as
normal delivery and invalidates correctness/performance acceptance.

The class summary below is explanatory. It cannot override or replace an
individual manifest row:

| Signal class | Normal origins | Return disposition | Plane / contraction | Product output |
| --- | --- | --- | --- | --- |
| scrollbar | tick; direct host call; declared foreign | completed local apply or accepted latest sample as tag contract permits | local presentation + row-growth accumulator | settled/unseen edges |
| search totals/selection | tick or direct host call | completed local apply/default | latest per search generation | none globally |
| mouse shape/visibility | tick or direct host call | completed cursor/local decision | latest per surface generation | host cursor apply |
| cell/initial/size limits | tick or direct host call | completed local geometry decision/default | latest per surface generation | none unless named consumer |
| progress | tick; declared foreign if source-proven | completed local edge admission | latest plus error transition | progress-error fact only |
| title/CWD | tick; declared foreign if source-proven | completed snapshot/fact admission | dedup equal bounded value | fact only for named consumer |
| command finished | tick or declared foreign | exact accepted/completed; never contractible | exact ordered semantic fact | bounded replayable fact |
| notification/bell | tick or declared foreign | exact/rate-policy acceptance | semantic request with abuse limit | inbox fact |
| secure input/health | tick or declared foreign | synchronous owner admission | state snapshot + transition edge | security/health fact |
| tab/split/close | tick or direct binding call | synchronous command-owner decision, else false | exact targeted intent | direct command owner |
| render/selection sample | tick or declared renderer origin | intercepted/local/diagnostic default | latest or sampled | no raw global fact |

No row is classified merely as “lossy after the bus.” Contraction occurs before
semantic replay and global subscriber queues.

### Terminal Content-Disposition Contract

Routine instrumentation never stores terminal strings merely because the sink
is local. Explicit user-requested private artifacts are separate from JSONL.

| Data class | Local product state | Global bus / replay | IPC | Routine JSONL | OTLP |
| --- | --- | --- | --- | --- | --- |
| raw screen, selection, scrollback, prompt, command, tool output | explicit bounded pull only; no retained stream | never | denied by baseline; future capability only | no raw value; counts only | never |
| clipboard, capture token, bearer/permission secret | direct security owner only | never | only existing explicit capability contract; never echoed | never | never |
| title, CWD, URL, notification text | bounded current state; untrusted data | semantic fact only for named consumer; current snapshot or fact-specific replay | existing authorized bounded snapshot/request only | reason enum/length class, not value | enums/counts only; no value |
| command-finished, bell, close, health, secure-input transition | typed state/fact | allowed with exact ordering and fact policy | authorized current status/fact where defined | controlled enums/counts | controlled aggregate enums/counts |
| scrollbar, search, mouse, geometry, render/presentation sample | pane-local latest state/accumulator | never raw | current bounded status only if an existing method requires it | sampled safe numbers only | bounded aggregates only |
| authenticated agent status report | leased pane-local structured state | low-rate derived fact, never authority | accepted only through bound pane principal | controlled vocabulary/provenance class, no payload | controlled aggregate vocabulary only |

### Activity Semantic-Parity Oracle

The replacement projector preserves named product outcomes, not every current
implementation detail. Timers are injected policy values in proof.

| Input sequence | Required observable outcome |
| --- | --- |
| unattended/hidden pane or visible-but-scrolled-up pane gains rows, then becomes quiet | no pre-quiet fact; one coalesced unseen-activity fact after quiet |
| attended visible pane remains pinned to bottom while rows grow | local snapshot advances; no unseen-activity notification |
| pane becomes observed or its unseen row is read before quiet | pending activity window closes; stale settle cannot publish |
| progress crosses non-error to error, repeats error, then resets | one error edge; repeats dedup; reset rearms the next edge |
| exact command-finished arrives while an activity quiet window is pending | preserve the ordered command-finished fact independently; the activity window may later settle once and cannot absorb, duplicate, or reorder the command fact |
| renderer health changes healthy -> unhealthy -> unhealthy -> healthy while activity is pending | preserve current health; emit one unhealthy edge for the first transition; dedup the repeat; recovery rearms a later unhealthy edge; activity settling remains independent |
| agent-qualified activity becomes quiet | promote one agent-settled fact according to current eligibility policy |
| later qualifying output/scrollbar observation after agent-settled | revoke settled attention; do not repromote until the pane is observed/reset |
| an already-published auto-clearable activity row becomes attended and pinned to bottom | clear its unread attention and invalidate the source activity window; rows whose policy requires explicit user action remain present |
| agent-settled eligibility changes around quiet | promote only when the pane/runtime is agent-qualified, unobserved, and not suppressed for the current activity generation; observation/reset rearms a later generation, while layout-only samples neither qualify nor revoke |
| pane closes or its runtime generation changes | close windows/leases and reject late settle/report work |
| alternate-screen/TUI output with no reliable scrollback growth | do not invent row-growth evidence; explicit reports/semantic signals may still classify state |

Normative evidence is the product outcome/state sequencing in
`TerminalActivityRouterTests`, `TerminalActivityDerivedEventTests`,
`TerminalActivityAgentSettledHeuristicTests`,
`InboxNotificationRouterObservedPaneTests`, and
`DerivedTerminalActivityNotificationIntegrationTests`. Assertions about the
current global-event transport, task count, or concrete timer mechanism are
characterization only and may intentionally change. The semantic facts,
attention lane, read/dismiss outcome, auto-clear policy, and late-generation
rejection in the table may not silently change.

### Explicit Agent Report Contract

The IPC server derives the pane and current `TerminalRuntimeGeneration` from the
authenticated pane principal, then stamps the accepted report. Caller pane or
generation fields are rejected/ignored rather than used for routing. Reports
enter one bounded pane-local latest/exact projector input; they do not become
raw global events.

```text
unknown
  -- started/running --------------------> running
  -- waitingForInput --------------------> waitingForInput
  -- waitingForApproval -----------------> waitingForApproval [advisory only]
  -- idle --------------------------------> idle
  -- succeeded/failed/cancelled ----------> terminal reported outcome

lease expiry / runtime replacement
  -> explicit report authority expires
  -> pane-local semantic/shell/heuristic evidence resumes
```

Higher-authority evidence wins while its lease is live, but an older or lower-
authority signal cannot roll back a newer explicit sequence. Sequence gaps are
observable and may request a current report snapshot; they do not authorize
invented intermediate states. Optional summary/task data remains bounded local
product data, never an OTLP attribute or permission prompt. A notification
request passes the same principal/generation checks plus abuse and dedupe policy
before producing one exact notification fact.

The IPC API is fixed:

```swift
enum AgentReportedState: String, Codable, Sendable {
    case started
    case running
    case waitingForInput
    case waitingForApproval
    case idle
    case succeeded
    case failed
    case cancelled
}

struct AgentActivityReport: Codable, Sendable {
    let reportSessionID: String
    let sequence: UInt64
    let state: AgentReportedState
    let taskKey: String?
    let progress: Double?
    let summary: String?
}

enum AgentReportLeaseDisposition: Codable, Sendable {
    case started(validForMilliseconds: UInt64)
    case renewed(validForMilliseconds: UInt64)
    case replacedPrevious(validForMilliseconds: UInt64)
}

enum AgentActivityReportReceipt: Codable, Sendable {
    case accepted(appliedSequence: UInt64, lease: AgentReportLeaseDisposition)
    case duplicate(lastAcceptedSequence: UInt64)
    case rejected(AgentActivityReportRejectionReason)
}

enum AgentActivityReportRejectionReason: String, Codable, Sendable {
    case staleSequence
    case sequenceGap
    case revokedRuntimeGeneration
    case expiredPrincipal
    case rateLimited
    case payloadTooLarge
    case invalidTransition
    case payloadConflict
}

struct AgentNotificationRequest: Codable, Sendable {
    let title: String
    let body: String?
    let dedupeKey: String
}

enum AgentNotificationPostReceipt: Codable, Sendable {
    case accepted(inboxSequence: UInt64)
    case duplicate(inboxSequence: UInt64)
    case rejected(AgentNotificationRejectionReason)
}

enum AgentNotificationRejectionReason: String, Codable, Sendable {
    case revokedRuntimeGeneration
    case expiredPrincipal
    case rateLimited
    case payloadTooLarge
    case invalidDedupeKey
    case dedupeConflict
}
```

`agent.activity.report` accepts `AgentActivityReport` and returns
`AgentActivityReportReceipt`. An exact duplicate has the same principal,
runtime generation, report-session ID, sequence, and normalized payload; reuse
of a sequence with different payload is `payloadConflict`, not duplicate.
The server owns lease duration on a monotonic clock. The first accepted report
for a report session returns `started`; each later accepted higher sequence
returns `renewed`; an accepted new report-session ID atomically expires the old
session and returns `replacedPrevious`. Each case reports a relative bounded
validity duration, never a wall-clock expiry. Duplicate, stale, gap, conflict,
and rejected reports do not extend a lease. Runtime-generation revocation and
principal expiry terminate it immediately. On monotonic expiry, explicit
authority ends and lower evidence may resume.

`agent.notification.post` accepts `AgentNotificationRequest` and returns
`AgentNotificationPostReceipt`; acceptance means exact inbox admission, not
visual render or an activity lease. Dedupe identity is authenticated principal,
server-stamped runtime generation, and normalized dedupe key. Reuse with the
same normalized title/body is `duplicate`; reuse with changed content is
`dedupeConflict`. The server stamps pane/runtime generation from the
authenticated principal. Neither request contains caller-authoritative pane or
generation fields.

UI/read models retain provenance as `reported`, `semantic`, or `heuristic`.
`waitingForApproval` is always advisory agent state and never renders or behaves
as a permission-broker decision.

### Secure Input Ownership Contract

`SecureInputOwner` is app-global and MainActor-isolated because Carbon secure
event input and app activation/focus are process-global host concerns. Its
authoritative state is:

```text
requestsBySurfaceGeneration
globalRequested
focusedSurfaceGeneration?
appIsActive
desired = appIsActive && (globalRequested || focused surface requests secure input)
applied = disabled | enabled | indeterminate(lastFailureClass)
securityEpoch
```

A request mutation increments `securityEpoch`, updates capture fences and
purges any content cache before applying the OS transition. OS failure never
rewrites requested truth to appear safe. A failed enable leaves the requesting
surface capture-protected; a failed disable leaves global capture protected
while applied state is indeterminate. Deactivation yields the OS state while
preserving requests; reactivation recomputes desired state. Surface invalidation
removes only that generation's scoped request; it does not clear a global
request. Shutdown clears global and scoped requests and makes a best-effort
balanced disable whose failure remains observable.

### Surface Ownership Contract

`SurfaceManager` owns pane/surface registration and lifecycle. `SurfaceView`
owns AppKit input and the immediate host bridge. A surface token combines stable
host identity and generation; raw pointers are used only synchronously inside
their valid C boundary.

The host state model keeps these facts independent:

```text
mounted(surface generation)
selected
inputEligible
renderEligible
focused
hiddenOrOccluded
geometryRevision
lastResponseWatermark
revealPending(target watermark)?
lastPublishedWatermark
```

`inputEligible` requires a live current generation, mount, and accepted focus/
host state. `renderEligible` additionally incorporates selected host visibility,
window occlusion/minimization, and app/window lifecycle; focus alone is not
visibility. A reveal completes only when a current-generation layer publication
contains at least the target response watermark. A stale cached frame does not
complete reveal.

Mouse/cursor acceptance records the AppKit event timestamp, Ghostty mouse-call
return, action admission, and `NSCursor` application. The contracted candidate
must pass TUI mouse response and mouse-shape-to-`NSCursor` latency under the huge-
watch loaded scenario. These are host/UI endpoints, not new actor hops.

One visibility projector derives the Ghostty-visible flag from selected-tab,
drawer/host visibility, window occlusion/minimization, and lifecycle. One
geometry owner derives scale/pixel size. One destruction path quiesces callbacks
and frees the C surface on MainActor. Parallel caches may exist for efficient UI
reads, but they cannot create parallel product pipelines for the same semantic
fact.

Surface lifecycle is `live(generation) -> closing(generation) ->
vendorThreadsQuiesced(generation) -> hostPublicationsDrained(generation) ->
released`. Routing lookup and IPC/report admission close at the first transition,
not at ARC deinit. A replacement mints a new generation even when pane ID or
allocator address is reused. App lifecycle has the analogous generation and
cannot enter `freed` until every surface reached `hostPublicationsDrained` and
every callback lease from the old app generation returned.

## Ownership Map

| Owner | Owns | Explicitly does not own |
| --- | --- | --- |
| libghostty | PTY/VT processing, renderer thread, Metal draw/presentation | AgentStudio MainActor fairness, product events |
| app/surface callback control blocks | callback admission, generation, in-flight leases, safe shutdown defaults | domain logic, AppKit work |
| `Ghostty.CallbackRouter` | ABI callback classification and synchronous payload capture | unretained delayed dereference, domain logic, one task per raw sample |
| `GhosttyTickGate` | bounded wakeup-to-tick task scheduling | bounded service inside Ghostty tick, action meaning, rendering |
| `Ghostty.AppHandle` | app/config handle and MainActor tick/free contract | global events |
| action router/adapter | exhaustive tag policy, synchronous host decision, owned translation | replay, inbox heuristics, fleet lookup |
| `SurfaceManager` | surface lifecycle, token/generation, pane mapping | terminal sample semantics |
| `SurfaceView` | direct AppKit input and immediate host surface bridge | global coordination |
| `TerminalRuntime` | pane-local current observable state and snapshots | raw global fanout, heuristic backlog |
| activity projector | bounded samples, quiet/lease state, low-rate facts | authorization or screen capture |
| `SecureInputOwner` | requests, focus/app lifecycle, OS applied state, security epoch | terminal inference, screen-content entitlement |
| terminal runtime lifecycle owner / `RuntimeRegistry` | mint/invalidate current pane runtime generation | IPC authentication or report payloads |
| IPC principal registry/server | stamp current runtime generation and revoke matching tokens/connections | minting parallel generation, trusting caller hints |
| `RuntimeFactBus` | terminal domain facts selected for global consumers | raw samples or screen text |
| Ghostty renderer | frame scheduling/presentation | host geometry/visibility truth |
| shared performance harness + measurement adapter | safe correlation, frame-publication observation, evidence validity | product rendering or physical-scanout claims |

## Enforcement Contract

### Compile-Time Type Separation

- `TerminalUISample` cannot be wrapped in the global `RuntimeFactEnvelope`
  fact type.
- `TerminalDomainFact` and `TerminalCommandRequest` are different types.
- Every action case has an exhaustive admission descriptor.
- Surface/app tokens include generation and are required by delayed work.
- Callback control blocks and leases are separate from AppKit view/app objects.
- Pane-bound agent reports require a server-stamped terminal session generation.
- Requested, desired, applied, and indeterminate secure-input states are distinct
  exhaustive cases.
- Screen content uses a separately authorized result type and never conforms to
  event/replay/persistence protocols.

### Architecture Lint

The repo-owned SwiftSyntax linter must approximate these rules:

- C callback bodies cannot create unkeyed `Task { @MainActor }` work for
  high-rate callbacks outside an allowlisted coalescing gate;
- raw pointer bits or `takeUnretainedValue()` cannot be captured for delayed
  dereference without an allowlisted lifetime token pattern;
- runtime callback userdata cannot point directly at an unretained app/view
  object when the callback can outlive or cross an actor hop;
- `NSPasteboard`, cursor, view, and other AppKit access inside a C callback must
  use an already-isolated MainActor scope or a typed MainActor completion path;
- every host-owned synchronous `ghostty_app_*`/`ghostty_surface_*` call that may
  reenter `action_cb` is wrapped by an origin-stamping scope;
- local sample descriptors cannot request replay or global bus emission;
- high-rate signal types cannot share one outbound buffer with exact semantic
  facts;
- production `AsyncStream` construction requires explicit buffering/recovery;
- global subscribers must declare topics and cannot receive all terminal cases
  only to ignore most of them;
- same-bus derived reposting requires an allowlisted projector and contraction
  descriptor;
- MainActor terminal paths cannot perform filesystem/fleet/JSON/regex/process
  work or screen-region extraction;
- `ghostty_surface_free`, app free, and other lifetime-changing calls are
  restricted to explicit MainActor lifecycle owners;
- pane-agent report admission cannot trust caller-supplied pane or session
  generation and must use the authenticated server principal;
- pane-local secure-input mutation cannot call Carbon enable/disable directly
  outside the app-global secure-input owner;
- geometry `.skip` cannot imply refresh without a named redraw reason;
- no screen-content value reaches OTLP projection or general runtime replay.

Runtime behavior—not lint—proves tail latency, fairness, coalescing ratio,
render eligibility, frame publication, visible behavior, and memory.

## Benchmark and Observability Contract

### Factorial Version/Host Matrix

```text
P0  pinned 332b2aef + baseline host + pinned measurement/action adapter
N0  candidate 7e02af87 + baseline host + candidate measurement/action adapter
P1  pinned 332b2aef + contracted host + same pinned adapter as P0
N1  candidate 7e02af87 + contracted host + same candidate adapter as N0
```

`P0 -> P1` and `N0 -> N1` isolate host contraction within one vendor build.
`P0 -> N0` and `P1 -> N1` estimate the vendor change only after the adaptation
equivalence gate below. A simple pinned-versus-nightly before/after cannot
identify the responsible boundary.

Each build has an immutable `GhosttyBenchmarkBuildIdentity` containing the GV6
fields. Measurement hooks are applied at semantically equivalent source seams in
both vendors and have recorded patch digests. Candidate-only compile/action
changes are a separate minimal adaptation manifest and may not contain tick,
signal-plane, geometry, visibility, or other host contraction.

If the pinned and candidate adapters are not semantically equivalent, the
vendor comparison is labeled “vendor plus mandatory adaptation.” A pure vendor
claim additionally requires a pinned adaptation-control build that applies a
semantic no-op/backport equivalent and proves adapter overhead. Product code
still performs one hard cutover; these benchmark identities are not a runtime
compatibility layer.

Measurement-probe perturbation uses eight separate prerequisite calibration
cells, not the 24 terminal factorial cells: two vendors by probe compiled-
disabled/enabled by representative idle-interaction/loaded-combined-pressure
workloads. Only the measurement probe differs within each pair. The report
records host-input tails, throughput/frame cadence, MainActor delay, and native
behavior, plus the accepted perturbation allowance. Compatibility adaptation
cannot be hidden in this control.

### Selected Precision Endpoint

The embedded ABI has no frame-present callback. This spec authorizes one
benchmark-only libghostty measurement adapter in both pinned and candidate
builds. It emits content-free stage records at equivalent internal seams:

1. renderer invalidation/admission;
2. frame start;
3. Metal command-buffer completion;
4. successful assignment of the rendered IOSurface to the Ghostty-owned
   `CALayer.contents`: after the size guard on the asynchronous path and after
   the direct assignment on the synchronous path.

The fourth timestamp is named `frameLayerPublished`. It occurs after GPU work
and after the new surface becomes layer content. It is not physical display
scanout and must never be labeled `framePresented` or `keyToPresent`. The
mandatory precision metric is `inputToFrameLayerPublished`. Native interaction
proof separately establishes that echo/caret/focus changes become visible, but
its automation timing is not substituted for the internal distribution.

The adapter uses the harness monotonic clock or records an explicit clock map,
an ephemeral run/surface token unrelated to product IDs, frame sequence, stage,
and drop accounting. It carries no terminal text, dimensions that fingerprint
user content, path, pane ID, or raw pointer. If equivalent stage hooks cannot be
maintained in both vendor builds, the precision comparison is invalid and the
spec reconverges; a refresh return or `CALayer` request is not an accepted proxy.

Idle precision trials keep one input probe in flight and match the first
qualifying published frame after the deterministic fixture response. Under
concurrent output, nearest-frame timing is forbidden because an unrelated frame
could satisfy it. The benchmark adapter must propagate a content-free ephemeral
probe sequence from an explicit fixture response marker through terminal
invalidation to the qualifying published frame. The marker path is applied
equivalently to pinned/candidate builds, counted in the adaptation manifest, and
disabled in product builds. If that causal propagation cannot be proven, loaded
cells may report host-input and aggregate frame cadence but cannot report
input-to-frame-layer-publication latency.

Inclusion uses a watermark, not “latest probe at publication.” The fixture
emits the private marker only after its visible response mutation in the same
ordered terminal input. Terminal state advances the highest applied probe only
after that mutation is applied. A renderer frame captures that watermark from
the same terminal snapshot/lock epoch used to build the frame, and
`frameLayerPublished` carries the captured watermark. A probe completes at the
first successful current-generation publication whose captured watermark is at
least that probe. One coalesced frame may acknowledge several probes. A frame
that captured state before the marker, fails the asynchronous size guard, is
discarded, or belongs to a stale surface generation acknowledges none.

### Fixed Workloads

Each cell uses identical release-optimized settings, geometry, fixture versions,
warmups, and repeated isolated trials. The terminal factorial portion of the
shared mandatory core contains 24 build/workload cells per trial set. The
parent contract adds ten watched convergence cells, for 34 enumerable shared
core cells total; the probe-perturbation calibration above is a prerequisite
control, not part of either count.

| Core group | Builds | Workloads | Cells |
| --- | --- | --- | --- |
| interaction/fairness | P0, N0, P1, N1 | deterministic echo + arrow caret, idle/no-watch | 4 |
| loaded workspace victim | P0, N0, P1, N1 | same interaction under `WF-HUGE-STEADY-V1` | 4 |
| terminal pressure victim | P0, N0, P1, N1 | sustained mixed CSI output plus injected interactive keys | 4 |
| combined pressure victim | P0, N0, P1, N1 | same terminal pressure plus `WF-HUGE-STEADY-V1` | 4 |
| vendor throughput/regression | P0, N0 | 150 MiB ASCII; mixed Unicode; CSI-heavy; request/response fire | 8 |

Loaded-workspace and combined-pressure rows are composite stress gates. They do
not use the idle/no-watch rows as watcher-factor controls and make no pure
watcher attribution. Within a loaded row, P0/N0/P1/N1 comparisons hold the
complete stress workload fixed and vary only the declared vendor/host factor.
The watched child owns the one-factor watched-versus-disabled pressure pair.

Each throughput row has a versioned scenario manifest. ASCII, Unicode, and CSI
rows record separate endpoints:

1. `writerCompleted`: the fixture writer has written the declared byte count;
2. `terminalDrained`: PTY input, Ghostty IO/gather and VT work have reached the
   fixture's final content-free sentinel/watermark;
3. `qualifyingFrameLayerPublished`: a current-generation frame containing that
   final watermark has been assigned to the layer.

Writer bytes/time, terminal-drain bytes/time, and final-frame time are distinct
metrics and cannot be relabeled as each other. The correctness oracle verifies
declared input byte digest/count plus terminal fixture response/watermark; a
truncated stream, pending terminal work, missing final publication, or evidence
gap invalidates the row. Request/response fire uses a fixed request count and
matches every response sequence before quiescence; FPS and completed
request/response pairs are reported separately from writer throughput.

The scrollback row uses the same versioned corpus across builds, count-driven
fill/clear/prune actions, Ghostty terminal/render quiescence markers, and a
bounded stable-sample rule frozen in the calibration manifest. It is a blocking
memory non-regression diagnostic, not a substitute for interaction latency.

The core holds sidebar hidden and Bridge closed unless that component is the
factor under test. The companion watched spec owns the exact huge-watch fixture,
start/stop markers, and convergence oracle; this child owns the echo/caret
fixture and terminal stages. One shared acceptance report joins both.

Required diagnostic submatrices vary one factor or an explicitly named pair,
not every factor at once:

- one terminal versus a fixed many-inactive-terminal corpus;
- visible, hidden-tab, minimized/occluded, and reveal states;
- 60 Hz, 120 Hz, and cross-display movement where hardware permits;
- Bridge closed/background/visible with hydration/subscription state declared;
- sidebar hidden/visible with dataset and notification-history size declared;
- TUI mouse response and mouse-shape application;
- scrollback fill, idle compression, clear/prune, and event-driven stable memory sampling.

Throughput comparisons report stable medians. Interaction and fairness report
p50/p95/p99/max and maximum starvation gap. Benchmark processes do not compete
in parallel unless concurrency is the workload under test.

### Interaction Stage Ledger

```text
input
  NSEvent timestamp
  -> handler entry
  -> before/after ghostty_surface_key/text/mouse

host callback
  wakeup callback
  -> tick scheduled/start/end
  -> actions copied/contracted/applied

terminal response
  PTY/application response marker
  -> renderer invalidation/frame start
  -> Metal completion
  -> frameLayerPublished [mandatory precision endpoint]
  -> physical scanout [not observed; no precision claim]

surface
  layout passes
  -> geometry plan/commit/skip/reject
  -> set_size / refresh
  -> visibility/display-ID transitions

product event
  raw actions
  -> local samples
  -> activity projector inputs
  -> semantic facts
  -> EventBus deliveries / inbox mutations
```

Every segment has queue age, service duration, counts, high-water, output count,
and privacy-safe correlation. A single “terminal latency” duration is
insufficient.

The shared harness also writes a bounded non-evictable/out-of-band validity
summary containing build/scenario manifest digests, expected stages, admitted,
recorded and dropped counts per stage, sequence gaps, final drain outcome, and
run-validity decision. Missing frame stages, callback/tick stages, or failed
drain invalidates the run even when the ordinary trace queue lost the evidence
of its own loss.

### Proof Expectations

Deterministic proof must cover:

- many wakeups before one MainActor turn produce one pending tick and bounded
  dirty follow-up;
- a deliberately non-overlapping producer run is rejected by the sustained-
  refill verifier; a valid event-gated refill run records pushes during drain,
  entry and consumed watermarks, actions/messages per tick, and maximum tick
  service; an over-budget unpreemptible tick fails the fairness gate and routes
  to a vendor bounded-drain/cooperative-yield decision;
- wakeups racing a drain and shutdown cannot create lost work or use-after-free;
- every runtime callback acquires the correct app/surface-generation lease, and
  wakeup/action/clipboard/close races cannot dereference an unretained object;
- foreign clipboard callbacks perform no AppKit work, preserve reentrant
  confirmation, terminally settle each accepted read exactly once, and deny
  stale/secure requests before surface free;
- actions inside a tick take the synchronous MainActor fast path;
- actions inside a tick create zero deferred MainActor action-routing tasks,
  and latest-value presentation contraction bounds observable mutations by the
  declared surface/key set rather than raw action count;
- actions reentered from direct MainActor key/text/mouse/binding/lifecycle calls
  receive the direct-host-call origin and no redundant actor hop;
- workspace, clipboard, and URL actions require the first successful purpose
  claim on one `.userKey`/`.userMouseButton` event gate; a chained second
  action, app tick, programmatic input, missing/consumed gate, and foreign
  origin perform no effect;
- destructive close commits once before returning handled, defers physical
  surface quiescence/free until the outer host call returns, and never restores
  an unstructured per-action task hop;
- foreign-thread actions copy payloads and preserve exact semantic facts;
- open-URL allow/deny tests prove every denial consumes the vendor callback and
  neither the host opener nor Ghostty fallback opens the URL;
- child-exited tests prove exact fact admission cannot return true, equivalent
  visible host presentation may suppress fallback, and false preserves the
  terminal-text fallback;
- close/recreate rejects generation-stale actions;
- 100,000 scrollbar/search/mouse samples produce bounded latest local state,
  zero raw global posts, and no semantic-history eviction;
- terminal IPC status/wait reads snapshot/fact journal with explicit gap
  handling, while no terminal path constructs legacy `RuntimeEnvelope` output;
- semantic fact flood interleaving preserves close, command-finished,
  notification, health, and secure-input ordering;
- output-burst/settled, pinned-bottom, unseen-output, progress-error, and inbox
  behavior matches the Activity Semantic-Parity Oracle through pane-local
  projection, including alternate-screen limitations;
- explicit agent reports override heuristics only for their lease and cannot
  grant permissions or address another pane;
- authenticated activity/notification methods derive pane and generation from
  the server principal, enforce sequence/idempotency/rate/size limits, and emit
  only accepted transitions or deduped notification facts;
- runtime replacement or generation change revokes a pane-bound IPC principal,
  closes its socket, expires its lease, and rejects a delayed report;
- malformed/oversized/rate-abusive authenticated report payloads are rejected;
- secure-input global/scoped request, target-specific toggle, desired/applied/
  failure/focus/app-lifecycle transitions remain balanced and conservatively
  fence capture before OS activation;
- native macOS integration proof observes real secure-event-input enable,
  focus transfer, deactivate/reactivate, scoped removal, and balanced disable;
  injected adapter tests retain OS-failure coverage without recording content;
- baseline IPC and agent authority cannot read screen content;
- one layout pass has one geometry authority and unchanged layout does not
  create unnamed refresh traffic;
- hidden/minimized surfaces avoid foreground render work and reveal current
  state promptly;
- surface/app teardown executes on the required owner without stale callbacks;
- a layer-publication block queued before surface free cannot report against or
  visually reattach to a replacement generation;
- pinned and candidate build manifests prove atomic vendor resources and make
  adaptation attribution explicit;
- throughput rows distinguish writer completion, terminal drain, and final
  qualifying layer publication and reject incomplete output/response oracles;
- scrollback fill/idle/prune/clear meets its preapproved memory ceiling without
  wall-clock-sleep settling;
- per-vendor compiled-disabled/probe-enabled controls bound measurement
  perturbation independently from compatibility adaptation;
- ordinary product builds reject/ignore the private fixture marker and contain
  no benchmark observer surface;
- OTLP canary projection excludes terminal content, raw IDs, paths, and tokens;
- forced trace/measurement-queue loss invalidates the run through the
  independent validity summary;
- the core workload records `inputToFrameLayerPublished` tails under watched
  churn instead of only terminal throughput, without claiming physical scanout;
- unrelated, pre-marker, wrong-size, stale-generation, and coalesced-probe frame
  cases obey the captured inclusion-watermark contract.

Native PID-targeted interaction proof establishes focus, pane switching,
visibility, and rendering. Internal timestamp correlation—not visual automation
timing alone—establishes precision latency.

### Requirements / Proof Trace

| Requirement group | Contract | Proof modality | Owning slice |
| --- | --- | --- | --- |
| CB1-CB7 | callback blocks, leases, affinity, clipboard/close completion | callback-origin table, race/lifetime and exact-completion tests | callback/lifetime boundary |
| GT1-GT8 | host tick admission plus explicit unbounded-service limitation | deterministic gate transitions and sustained producer-refill workload | app tick admission |
| GA1-GA10 | origin/return-aware exhaustive action manifest | tag coverage, direct/foreign origin, handled-result, vendor-fallback, and stale-generation tests | action ingress |
| TS1-TS9 | signal planes and content disposition | type/architecture enforcement plus bounded flood and export canaries | signal planes |
| AI1-AI10 | activity parity, provenance, report API, lease, server generation | injected-clock sequence oracle plus IPC ordering/revoke/replace integration | activity intelligence and agent reports |
| SC1-SC8 | future screen boundary and global secure-input owner | exhaustive owner-state races, baseline capture denial, and real Carbon transition smoke | secure input; future capture constraints |
| SF1-SF17 | direct input, startup activation, geometry, visibility, display, teardown, and scrollback memory | invalid composition with zero mutation/activation; UUIDv7 new creation plus opaque historical-ID round-trip; zero startup writes and zmx-list calls; priority/exact-ID attach and delayed repository integration; geometry/visibility/lifetime tests; native interaction diagnostics; count-driven memory gate | surface host and terminal activation |
| GV1-GV8 | atomic vendor cutover, attribution identity, measurement isolation | build-manifest/delta/negative-product checks, throughput and core factorial report | Ghostty cutover and shared harness |

## Security and Trust Context

Terminal-controlled input is untrusted data. Any process attached to a PTY can
emit titles, notifications, URLs, OSC sequences, and misleading agent-state
text. Same-user IPC improves pane attribution but does not prove a report is
truthful.

Assets:

- MainActor availability and trustworthy interaction measurements;
- app/surface/session identity and callback memory lifetime;
- user intent for commands, clipboard, notification, secure input, and capture;
- terminal screen, selection, scrollback, prompt, command, tool output, title,
  CWD, URL, tokens, and permission state;
- correct pane attribution and the distinction between advisory activity state
  and actual authorization.

Entry points and adversaries:

- arbitrary PTY output, OSC, titles, URLs, notifications, progress, and action
  traffic from a local process;
- stale or concurrent vendor callbacks during close/recreate/shutdown;
- same-user IPC callers with a stale token, caller-supplied pane/generation, or
  misleading status payload;
- callback floods and measurement overload intended to starve or hide evidence;
- malformed/oversized clipboard, notification, hook, or report payloads.

Privileged effects are app/window/tab/split commands, close, clipboard access,
secure-event-input transitions, screen reads, notification/open-URL requests,
cross-pane targeting, and permission state. Only the typed current-generation
owner named in this spec can authorize them.

- Server-owned IPC principal plus terminal-session generation decides pane
  authority. Existing shell-integration/Ghostty actions are surface-attributed
  semantic evidence. Unknown OSC/text is heuristic data only and cannot name
  another pane or enter the explicit-report protocol.
- Agent-state intelligence is advisory and never authorization state.
- Raw screen/private content follows the content-disposition table. Bounded
  metadata and semantic lifecycle facts may reach named product consumers, but
  raw values never enter OTLP, routine replay, or persistence.
- Screen capture is not authorized by this spec. Its constraints prevent a
  future implementation from treating baseline self-pane access as consent.
- Callback payloads and userdata obey C lifetime rules across all actor hops;
  closing callbacks return safe defaults without stale dereference.
- Measurement hooks expose only stage, sequence, safe ephemeral correlation,
  and time. Instrumentation does not become a terminal-content side channel.
- Clipboard policy, macOS TCC, and Ghostty's internal security model are not
  redesigned. The host preserves confirmation and MainActor affinity.

## Alternatives and Tradeoffs

### Upgrade Ghostty only

Gain: likely substantial bulk throughput, heavy-output frame fairness,
hidden-surface savings, and scrollback memory improvement.

Cost: leaves AppKit/MainActor pre-input delay, task-per-wakeup/action expansion,
raw sample fanout, duplicate semantic paths, geometry refresh, visibility,
display ID, and lifetime gaps. Rejected as the complete solution; retained as
an independent version slice.

### Actor per terminal pane

Gain: independent mailboxes and potential background compute isolation.

Cost: every UI property becomes asynchronous, while AppKit input and surface
calls still require MainActor. It does not inherently bound callback admission
or contract events. Rejected until measured evidence shows pane-local compute
still needs another isolation domain after this contract.

### Remove all noisy terminal events

Gain: immediate EventBus reduction.

Cost: regresses pinned-bottom, unseen-output, agent-settled, progress-error,
inbox, and UI behavior. Rejected. The selected design moves their inputs to a
pane-local projector and preserves low-rate meaning.

### Keep asynchronous action routing for uniformity

Gain: one apparent callback rule regardless of origin thread.

Cost: hides an unnecessary second actor hop inside MainActor ticks, loses batch
contraction, weakens lifetime/ordering, and creates work after the handled result
returns. Rejected. The selected design has an explicit already-isolated fast
path and a bounded foreign-thread path.

### Pragmatic selected direction

Keep direct AppKit-to-Ghostty input and Ghostty-owned rendering. Add stable app/
surface callback control blocks, one app-wide tick gate, origin-aware action
contraction, type-separated terminal signal planes, one shared fair pane-keyed
activity projector, server-generation-bound agent reports, one global secure-input owner,
and correct geometry/visibility/lifetime host ownership. Preserve a decision-
gated screen-content privacy boundary without authorizing capture. Evaluate the
Ghostty upgrade independently and in combination.

Tradeoff: the host gains explicit gates, descriptors, generations, and
measurement surfaces. That complexity replaces implicit tasks, replay, and
fanout whose behavior is currently harder to understand and prove.

## Non-Goals

- No implementation sequence, task graph, or exact command list.
- No claim that Ghostty or the host boundary is the initiating watched-folder
  root cause.
- No movement of ordinary AppKit input behind a new actor.
- No host-owned VT parser, Metal renderer, frame loop, or `surface_draw` path.
- No screen-capture product implementation, default-on capture, or per-render
  screen-text capture.
- No claim that `frameLayerPublished` is physical display scanout.
- No agent authorization or approval based on terminal text/self-report.
- No full IPC authentication redesign.
- No copy of upstream gather buffer counts/timing into host event gates.
- No permanent old/new dual terminal event pipelines.
- No weakening of secure input, clipboard, notification, or action coverage.

## Slice Routing Map

These are separable ownership contracts, not implementation phases:

| Slice | Maintained contract |
| --- | --- |
| callback/lifetime boundary | stable app/surface blocks, affinity, clipboard/close completion, teardown |
| app tick admission | one pending host turn, orthogonal dirty state, explicit unbounded vendor-drain gate |
| action ingress | payload copy, MainActor fast path, foreign gate, generation |
| signal planes | local sample, snapshot, fact, intent, diagnostic separation |
| activity intelligence | pane heuristics, parity, explicit-signal leases |
| agent reports | authenticated IPC provenance, server session generation, schema, no authority |
| secure input | app-global requested/desired/applied owner and conservative fencing |
| future screen boundary | constraints only; not an authorized implementation slice |
| surface host | direct input, geometry, visibility, display ID, destruction |
| Ghostty cutover | atomic vendor/header/resources/action policy and adaptation identity |
| interaction proof | shared core matrix, frame-layer publication, native visible behavior, evidence validity |

Watched-folder admission, topology apply, topic-aware EventBus transport, and
global MainActor fairness are owned by the companion watched-folder spec.

## Calibration And Vendor Cutover Gates

These are measured values or external compatibility gates, not architecture
choices left to planning:

| Gate | Owner / evidence | Required disposition |
| --- | --- | --- |
| capacities for foreign samples, activity keys, exact fact history/gap marker, diagnostics, and report rate | performance/security owner using fixed flood corpora before candidate acceptance | bounded values recorded in the calibration manifest; exact/fact-gap and repair storage remain separate from replaceable capacity |
| absolute and loaded-versus-control interaction/layer/cursor ceilings | human owner from baseline/control distributions before candidate acceptance | no performance-done claim until approved; event-timestamp-to-layer is the product gate |
| measurement-probe perturbation allowance | human/performance owner from compiled-disabled versus enabled distributions | over-budget or unequal perturbation yields `invalidEvidence` |
| candidate surface/app quiescence equivalence | Ghostty cutover owner from candidate source and teardown stress | reject candidate if thread joins, queue barriers, or publication fencing cannot satisfy SF10 |
| unpreemptible tick maximum | AgentStudio/Ghostty boundary owner from overlapping-refill workload | any maximum above the approved gate blocks terminal-fairness acceptance and requires a separately specified libghostty bounded-drain/cooperative-yield contract |

The tick gate, host-call contraction scope, fact authority, activity owner,
command sinks, runtime cutover, agent-report API/provenance, and surface state are
resolved by this spec and are not planner-local choices.

## Decision-Gated Future Boundary

Screen capture requires a later product/spec decision naming requester,
recipient, explicit user action/consent, data scope, result lifetime, and secure-
input behavior. User-action-only is the safe default. Agent-requested capture,
physical-scanout instrumentation, and an accessibility consumer for selection
changes do not block this spec unless their product scope is explicitly added.

## Design Decision

This revision selects the pragmatic direction, exhaustive action manifest,
concrete control blocks/host scopes, terminal hard cutover, authoritative fact
commit/gaps, fair shared activity projector, existing command owners, report
receipts, surface currentness, secure-input owner, causal layer/cursor endpoints,
and evidence-validity contract. It passed fresh adversarial spec review and is
ready for implementation planning. Ghostty throughput claims and the static
audit remain hypotheses until the required runtime proof passes.
