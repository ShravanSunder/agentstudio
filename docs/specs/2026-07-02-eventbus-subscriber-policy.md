# EventBus Subscriber Policy Spec

Date: 2026-07-02
Status: revised after spec review
Scope: pre-plan design contract

## Product Intent

AgentStudio must not silently lose correctness-bearing workspace facts when large
watched folders, boot replay, filesystem change storms, or topology removals
produce bursts on the runtime event bus.

The user-visible failure we are preventing is missing or stale repo/worktree
state that looks settled. Missing state is worse than temporary backlog for
canonical topology and notification-promotion paths, because the app has no
current way to prove that the state is incomplete after a dropped event.

## Current Problem

`EventBus.subscribe()` currently hides a lossy delivery policy:

```swift
func subscribe(
    bufferingPolicy: AsyncStream<Envelope>.Continuation.BufferingPolicy = .bufferingNewest(256)
) -> AsyncStream<Envelope>
```

That default makes every bare production `subscribe()` call implicitly lossy.
`WorkspaceCacheCoordinator.startConsuming()` uses the bare call while owning the
single topology/cache intake, so a burst can drop canonical facts before the
coordinator sees them. The bus only counts and logs drops; it does not retry,
block, recover, or identify the affected subscriber.

The remembered large-watched-folder problem needs one correction for current
main: watched-folder add/change discovery now emits one batched
`.reposDiscovered` event per refresh, not one `.repoDiscovered` event per repo.
The burst risk is still real, but its strongest current topology examples are:

- boot replay, which posts one `.repoDiscovered` event per persisted repo;
- watched-folder removal, which can post one `.repoRemoved` event per missing
  clone;
- chunked filesystem changes, where large path sets produce multiple
  `.filesChanged` envelopes;
- any future correctness-bearing subscriber that inherits the hidden lossy
  default.

## Requirements

R1. No production `EventBus` subscriber may inherit an omitted buffering policy.

R2. Every production `EventBus` subscriber must declare semantic loss tolerance
at compile time through a repo-owned policy type.

R3. The policy type must expose a named standard lossy buffer limit. `256` may
remain the standard, but it must be referenced as a known constant, not as a
hidden default argument.

R4. Correctness-bearing state mutation lanes must use a non-lossy live delivery
policy. This includes canonical topology/cache intake and feature promotion
where dropped facts can silently remove user-visible state.

R5. Lossy subscribers are allowed only when their owner names why loss is safe:
latest-state supersedes older events, a poll/recompute path exists, state is
derived from atoms, the wait is bounded, or the surface is advisory.

R6. Bus-level replay capacity is separate from live subscriber policy. Replay
answers how much recent history a late subscriber can catch up on; subscriber
policy answers whether a connected live consumer may drop events.

R7. A critical subscriber must be proven to receive more than the standard lossy
limit of live topology-removal events without bus drops.

R8. Late-join or replay-truncation behavior must be explicit. If replay cannot
provide complete history, the owning consumer must require a refresh/rebuild
path instead of treating critical live delivery as a full recovery story.

R9. Drop diagnostics must remain useful. Lossy drops should be attributable to a
subscriber and policy. Critical drops must be treated as faults/recovery-needed
diagnostics, not ordinary warnings.

R10. The policy change must not widen filesystem scan authority, path mutation
authority, network behavior, subprocess behavior, or plugin behavior.

R11. Critical delivery must not trade silent state loss for silent memory
pressure. The first slice must expose an inspectable critical-pressure signal
before a stalled critical consumer can remain invisible.

R12. App-level events must be classified by event semantics, not by the bus name.
Low-rate app-shell fan-out can be lossy only when the event is advisory or
recoverable.

## Technical Contract

Introduce a semantic subscriber policy owned by `EventBus`:

```swift
enum BusSubscriberPolicy: Hashable, Sendable {
    static let standardLossyBufferLimit = 256

    case criticalUnbounded
    case lossyNewest(Int)
}
```

`EventBus` maps this semantic policy to `AsyncStream` buffering internally. The
bus owns the mechanism; call sites own classification.

Production subscription shape:

```swift
func subscribe(
    policy: BusSubscriberPolicy,
    subscriberName: String
) -> EventBusSubscription<Envelope>
```

The exact wrapper type name may be shaped during planning, but the contract is
not a raw anonymous `AsyncStream` anymore. The returned subscription must be
iterable by consumers and must give the bus enough metadata to report:

- subscriber attribution;
- semantic policy;
- yielded count;
- consumed count or an equivalent monotonic consumer-progress signal;
- high-water lag/pressure for critical subscribers;
- replay delivery status for replay-enabled buses.

A no-argument production `subscribe()` overload must not exist. A production
subscription API that returns a plain `AsyncStream` without consumption
progress is insufficient for critical subscribers, because `.unbounded` streams
do not expose queue depth or backpressure.

Sensible defaults are explicit rules, not omitted arguments:

- correctness-bearing state mutation lanes default by rule to
  `.criticalUnbounded`;
- lossy lanes use `.lossyNewest(BusSubscriberPolicy.standardLossyBufferLimit)`
  unless a narrower named limit is locally justified;
- tests may have ergonomic harness defaults, but app sources may not.

`criticalUnbounded` means no live drops by buffer policy plus observable
pressure. It does not mean unobservable infinite memory growth is acceptable.

## Boundary / Separability Map

```text
Spec boundary / separability map

FilesystemActor / AppDelegate / pane runtimes
  owns: source observation, source seq, event production
  exposes: RuntimeEnvelope facts on PaneRuntimeEventBus
  does not own: subscriber buffering or consumer criticality

        RuntimeEnvelope facts
              |
              v

EventBus<Envelope>
  owns: fan-out, live subscriber policy mapping, replay retention,
        subscriber policy/drop/pressure diagnostics
  exposes: subscribe(policy:subscriberName:), post(_), replay snapshot/status,
           drop/policy/pressure diagnostic snapshot
  does not own: domain decision that a subscriber is critical or lossy

        explicit semantic subscription
              |
              v

Subscriber owners
  owns: critical/lossy classification, recovery contract, consumption loop,
        critical replay/gap response when joining late
  examples:
    WorkspaceCacheCoordinator -> canonical topology/cache correctness
    InboxNotificationRouter   -> notification promotion correctness
    Git/Forge projectors      -> latest-state / poll-backed lossy consumers

        state mutations and effects
              |
              v

WorkspaceStore / atoms / feature stores
  owns: canonical app state and user-visible settled truth
```

Pre-EventBus buffers are outside this slice unless explicitly named. For
example, pane-runtime outbound buffers can drop before an envelope reaches
`PaneRuntimeEventBus`; this spec does not claim end-to-end producer-to-consumer
losslessness for those paths.

## Current Subscriber Classification

This table is the current-main classification target. Planning may refine names
or split helper APIs, but no row may stay implicit.

| Subscriber | Current call shape | Policy | Why |
| --- | --- | --- | --- |
| `WorkspaceCacheCoordinator.startConsuming` | bare `bus.subscribe()` | `criticalUnbounded` | Single topology/cache accumulator; dropped facts can leave canonical state missing. |
| `WorkspaceSurfaceCoordinator.startPaneEventIngress` | bare `paneEventBus.subscribe()` | `criticalUnbounded` | Current broad pre-reducer intake. Narrower reducer-level policy is deferred until reducer classification exists; this slice gives the current call site one unambiguous critical policy. Topology effects themselves still arrive via `TopologyEffectHandler`. |
| `InboxNotificationRouter.start` | bare `bus.subscribe()` | `criticalUnbounded` | Feature promotion mutates inbox state; notifications should not silently disappear. |
| `TerminalActivityRouter.start` | bare `bus.subscribe()` | `lossyNewest(standard)` | Activity is advisory/coalescible in this slice; revisit if loss causes missed unseen-activity behavior. |
| `GitWorkingDirectoryProjector.start` | explicit `.bufferingNewest(subscriptionBufferLimit)` | `lossyNewest(subscriptionBufferLimit)` | Newer filesystem facts supersede older work; projector has refresh/recompute behavior. |
| `ForgeActor.start` | explicit `.bufferingNewest(subscriptionBufferLimit)` | `lossyNewest(subscriptionBufferLimit)` | Remote enrichment is poll/refetch backed and intermediate events can be superseded. |
| `EventBus.waitForFirst` helpers | hidden bare `subscribe()` | explicit helper policy | Bounded waits must name whether they are lossy/replay-backed or critical for a caller. No hidden helper default in production. |
| `PaneTabViewController` app-event termination handler | bare `AppEventBus.shared.subscribe()` | `criticalUnbounded` | Handles `.terminalProcessTerminated` and posts `.terminalProcessTerminationHandled`; dropping the termination event can leave cleanup/termination UI in the wrong state. |
| `TerminalPaneMountView` app-event acknowledgement wait | bare `AppEventBus.shared.subscribe()` | `criticalUnbounded` | Waits for `.terminalProcessTerminationHandled` after posting `.terminalProcessTerminated`; the handshake is not merely advisory. |
| `AppEvent.worktreeBellRang` consumers | same `AppEventBus` plane | `lossyNewest(standard)` unless sharing a critical subscription | Bell fan-out is advisory after inbox promotion moved to `PaneRuntimeEventBus`; if it shares a stream with termination events, the stream takes the stricter critical policy. |

## AppEventBus Event Semantics

`AppEventBus` is not globally lossy by default. Its current event cases have
different semantics:

- `.terminalProcessTerminated` and `.terminalProcessTerminationHandled` form a
  UI cleanup/acknowledgement handshake and are critical for the current
  subscribers.
- `.worktreeBellRang` is advisory app-shell fan-out in the current architecture;
  notification inbox promotion does not depend on it.

When one subscriber consumes both critical and advisory `AppEvent` cases, the
subscriber must use the stricter policy. Planning may split app-event consumers
later, but the first slice must not mark the termination handshake lossy.

## Replay Policy vs Subscriber Policy

Keep the current bus-level replay concept: bounded recent history per source.
Do not replace it with a new ring buffer type in this slice.

Replay is not a substitute for critical live delivery:

- a connected critical subscriber must not drop live events;
- a late subscriber may still miss history if replay capacity has truncated it;
- replay truncation requires an explicit recovery rule owned by the late
  subscriber or domain layer.

For replay-enabled buses, the subscription contract must include replay status.
The status must let a critical subscriber distinguish "replay was complete for
the retained window" from "one or more source histories may have been truncated."
Acceptable shapes include per-source truncation flags, retained range metadata,
or an equivalent `possiblyTruncatedSourceKeys` signal. If the bus cannot prove
replay completeness for a critical late subscriber, that subscriber must treat
startup as recovery-needed and run its domain refresh/rebuild path instead of
trusting replay alone.

Current owner expectations:

- `WorkspaceCacheCoordinator` should attach before boot topology replay in the
  normal composition path. Its first-slice correctness proof is live delivery,
  not late-join replay.
- `EventBus.waitForFirst` helpers are bounded waits, not a topology recovery
  mechanism. They must either use an explicit lossy/replay-backed policy or be
  split into a named critical wait helper with the same replay-status contract.
- Future critical late subscribers must name their refresh/rebuild owner before
  being classified critical.

The old WIP's semantic policy shape is useful prior art. Its replay storage
implementation is not a requirement for this spec.

## Topology Burst Contract

Use current topology shapes in tests and docs:

- `.reposDiscovered(parentPath:repositories:)` is the batched add/change
  watched-folder discovery shape.
- `.repoRemoved(repoPath:)` remains per removed clone.
- boot replay still posts `.repoDiscovered` per persisted repo.
- large filesystem changes can produce multiple `.filesChanged` envelopes
  because path sets are chunked.

The primary burst proof for this policy should use more than the standard
lossy limit of live topology-removal events, because that is the clearest
current topology path that still produces many individual events.

## Diagnostics Contract

The bus should expose enough metadata for tests and debug proof:

- active subscriber names;
- active subscriber policies;
- cumulative drops by subscriber;
- whether a drop happened while replaying a snapshot or during live post;
- yielded count and consumed count, or an equivalent monotonic progress signal;
- high-water lag/pressure for critical subscribers;
- replay status/truncation metadata for replay-enabled subscriptions;
- bus/source/seq information when the envelope exposes it.

Lossy drops are expected but observable. Critical drops are invariant failures:
they require fault-level diagnostics and a recovery-needed signal. The exact
recovery trigger can be shaped in the implementation plan, but the minimum state
is fixed here: subscriber name, policy, failure class (`criticalDrop`,
`criticalPressure`, or `replayPossiblyTruncated`), affected source when known,
and whether a refresh/rebuild is required. Silent continuation as "healthy" is
not allowed.

## Security And Trust Context

Watched folders are user-authorized scopes, not trusted contents. A large or
malicious local tree can still create event rate and backlog pressure.

This spec does not add new filesystem authority. It does not add new scans
outside persisted watched paths. It does not change Git subprocess execution,
network calls, secrets, plugins, or URL handling.

The security-adjacent tradeoff is memory amplification: `.criticalUnbounded`
turns silent data loss into retained backlog if a critical consumer stalls.
That trade is acceptable only for narrow correctness-bearing subscribers with
diagnostics that make backlog/drop pressure visible.

## Non-Goals

- No full filesystem/git snappiness campaign.
- No producer scheduling, debounce, or source-rate redesign.
- No off-main reducer or coordinator rewrite.
- No SQLite async migration.
- No UI redesign or new user-facing recovery panel.
- No new event bus type or command bus.
- No replay data-structure rewrite or dedicated ring-buffer abstraction in this
  first slice.
- No pre-EventBus buffer rewrite, including pane-runtime outbound buffers.
- No claim that critical live delivery fixes producer non-emission, FSEvents
  creation/start failure, ignored non-`.git` batches, process restarts, or
  replay truncation.
- No claim that this slice fixes watched-folder producer/emission correctness.
  It fixes the subscriber-policy footgun and proves that boundary.

## Proof Expectations

Compile-time/schema proof:

- production code cannot call `EventBus.subscribe()` without a semantic policy;
- production code cannot pass raw `AsyncStream.Continuation.BufferingPolicy` at
  subscriber call sites;
- architecture/static proof enumerates allowed helper/test exceptions.

Unit proof:

- replay-capacity tests continue to prove bounded per-source replay;
- policy metadata tests prove subscriber names and policies are inspectable;
- a critical subscriber receives more than `standardLossyBufferLimit` live
  envelopes with zero drops;
- a lossy subscriber can still drop under pressure and increments attributed
  drop diagnostics.

Integration/state proof:

- a coordinator-class topology consumer receives a removal burst larger than
  the standard lossy limit and the canonical topology ends complete;
- replay-truncation behavior is covered separately from live delivery;
- if replay/gap recovery delegates to refresh/rescan, that refresh/rescan path
  reconstructs canonical topology.

Observability proof:

- lossy drops include subscriber name and policy;
- critical drops are visible as faults/recovery-needed diagnostics;
- critical lag/pressure has an asserted high-water signal before memory pressure
  becomes invisible;
- replay truncation or unknown replay completeness is observable to critical
  late subscribers.

Closeout wording guard:

- A passing subscriber-policy implementation may claim "critical EventBus
  subscribers no longer inherit hidden lossy defaults."
- It may not claim "watched-folder correctness is fixed end to end" unless a
  separate producer/emission proof covers FSEvents creation, `.git` filtering,
  fallback rescans, and source-side buffers.

## Open Decisions For Planning

1. Exact shape of `subscriberName`: string literal, static typed identifier, or
   a small subscriber metadata struct.
2. Whether `waitForFirst` requires a caller-provided policy for every call or
   splits into named helpers for critical waits and bounded lossy waits.
3. The concrete critical-drop recovery action: automatic full refresh, diagnostic
   state plus scheduled refresh, or both. The diagnostic fields and
   recovery-needed signal above are not optional.
4. The future reducer-level split that could narrow
   `WorkspaceSurfaceCoordinator.startPaneEventIngress` after reducer
   classification exists. This is not blocking for the first slice; the current
   call site is critical.
5. Whether `AppEventBus` should use the same policy type globally or a separate
   alias with the same semantics. The default preference is one generic policy
   to prevent app-shell defaults from becoming a second footgun.

## Design Decision

Proceed to spec review with the semantic-policy design.

Reject these alternatives for the first slice:

- keeping raw `BufferingPolicy` and only removing the default, because the call
  site still states mechanism instead of intent;
- making all subscribers unbounded, because bounded/latest-state subscribers are
  already intentional in Git and Forge;
- implementing a new replay/ring-buffer abstraction now, because replay storage
  is a separate contract from live subscriber loss policy;
- relying on producer throttling alone, because the correctness footgun exists
  at the subscriber boundary today.
