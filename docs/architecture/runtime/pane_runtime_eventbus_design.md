# Pane Runtime EventBus Design

> **Owns:** admission-to-coordination mechanics, hop shape, two buses, shipped
> actors, Swift 6.2 threading.
> **Companion:** [Pane Runtime Architecture](pane_runtime_architecture.md)
> (what must be true). Governing model:
> [Three Data Flow Planes](pane_runtime_architecture.md#three-data-flow-planes).

<a id="tl-dr"></a>
## TL;DR

One `actor EventBus<RuntimeEnvelope>` fans out admitted, low-volume facts.
High-rate Terminal signals classify before scheduling or publication. Terminal
local samples use fixed-key coalescing and bounded sufficient-statistics
aggregation, then an off-main semantic projector; only changed outcomes return
through a thin MainActor adapter to the bus. Filesystem/Git worktree facts are
globally published in bounded batches; pane-projection admission is a separate
exhaustive decision. Normative Terminal source contract:
[Contract 7](pane_runtime_architecture.md#contract-7-typed-ghostty-source-admission-and-contraction).

## Files to load

| File | Owns |
| --- | --- |
| [`EventBus.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Events/EventBus.swift) | Generic bus: `subscribe(policy:subscriberName:factInterest:)`, post/batch/replay, diagnostics |
| [`EventChannels.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Events/EventChannels.swift) | `PaneRuntimeEventBus` |
| [`AppEventBus.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Events/AppEventBus.swift) / [`AppEvent.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Events/AppEvent.swift) | App-level notification bus |
| [`FilesystemActor.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemActor.swift) | FSEvents ingress, batching, topology facts |
| [`GitWorkingDirectoryProjector`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Git/) | Git snapshot/branch/origin facts from filesystem |
| [`ForgeActor.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Forge/ForgeActor.swift) | Demand-driven PR/forge facts |
| [`NotificationReducer.swift`](../../../Sources/AgentStudio/Core/RuntimeEventSystem/Reduction/NotificationReducer.swift) | Critical vs lossy/frame-coalesced EventBus scheduling (not Inbox kind mapping) |
| App coordinators under [`App/Coordination/`](../../../Sources/AgentStudio/App/Coordination) | Bus → cache/topology/surface sequencing |

## Why This Exists

1. **Multi-subscriber fan-out** — one `post()`, N independent subscriber streams.
2. **Off-MainActor producers** — filesystem, git, forge work must not block UI.
3. **One-way facts** — events producers → bus → subscribers; commands never share the channel.
4. **Admitted facts only** — raw Terminal samples and unrelated filesystem effects do not enter the bus.

## Two Event Systems

| Bus | Type | Purpose |
| --- | --- | --- |
| `PaneRuntimeEventBus` | `EventBus<RuntimeEnvelope>` | Runtime/system/worktree/pane facts |
| `AppEventBus` | `EventBus<AppEvent>` | App-level notifications that are not commands |

**These are not redundant.** `AppEventBus` carries app-level notifications
such as `.worktreeBellRang` and other app-shell fan-out that is not itself a
workspace command. `PaneRuntimeEventBus` carries admitted facts such as
`.repoDiscovered`, `.snapshotChanged`, and `.pullRequestsChanged`
(`ForgeEvent` facts-by-branch, not a counts-only envelope case).
Workspace work does **not** route through `AppEventBus`; it uses
`WorkspaceActionCommand` and the validated coordinator pipeline directly.
AppKit/macOS lifecycle ingress uses `ApplicationLifecycleMonitor` plus
`AppLifecycleAtom` / `WindowLifecycleAtom`, not either bus.

Inbox promotion consumes `PaneRuntimeEvent.terminal(.bellRang)` from
`PaneRuntimeEventBus` after Contract 7 admission. It does not depend on
`AppEventBus.worktreeBellRang` and must not ingest raw `GhosttyEvent`.

## Commands never on the bus

Commands use direct capability-protocol dispatch
(`runtime.handleCommand`, `forgeActor.refresh(repo:)`, filesystem register
APIs). Do not add a generic command executor or route
`WorkspaceActionCommand` / `PaneRuntimeCommand` through either bus.

Composition root may own concrete systems; cross-feature consumers depend on
focused capability protocols.

## Typed Admission Before Multiplexing

Multiplexing applies only after the owning source admits a semantic fact.
Definitions:
[Contract 7](pane_runtime_architecture.md#contract-7-typed-ghostty-source-admission-and-contraction).

```text
copied Ghostty signal
  -> exhaustive typed source admission
     -> exact fact/control -> MainActor runtime -> runtime channel/EventBus
     -> local sample -> fixed-key coalescing + bounded aggregation
                      -> one compact MainActor apply
                      -> TerminalActivityProjector actor
                      -> changed semantic outcomes
                      -> MainActor router -> EventBus
```

For an admitted fact that serves both UI and coordination, mutate
`@Observable` before posting. Coalesced local presentation stops at compact
MainActor application.

Filesystem:

```text
FSEvents paths
  -> FilesystemActor owns routing, filtering, dedupe, debounce, batching
  -> globally published WorktreeScopedEvent
  -> PaneFilesystemProjectionAdmission (exhaustive)
     -> filesChanged / snapshotChanged -> affected-pane projection
     -> other owned cases -> explicitly ignored by this projection

pane mount / removal / CWD / active-pane change
  -> local affected-key coordinator effect
  -> no EventBus publication merely to maintain the index
```

Detail:
[Workspace Data Architecture — Filesystem Effect Admission](../state/workspace_data_architecture.md#filesystem-effect-admission-and-projection).

## What goes on which path

| Category | Examples | Bus? |
| --- | --- | --- |
| Direct MainActor only | key/mouse/resize/focus → Ghostty C API; command dispatch | No |
| Local high-rate presentation | search/scrollbar contracted samples | No — compact apply only |
| Admitted pane metadata | title, CWD, bell, lifecycle | Yes when coordination needs the fact |
| System / worktree enrichment | repo discovered/removed, filesChanged, snapshot/branch/origin, forge PR facts | Yes |
| App shell lifecycle | active/resign/key/focus | No — `ApplicationLifecycleMonitor` → lifecycle atoms |

## Shipped actor inventory

### `actor EventBus<Envelope: Sendable>`

Transport only: subscription policy, immutable fact-topic matching, per-source
replay, delivery/drop diagnostics. No domain policy.

`subscribe(policy:subscriberName:factInterest:)` returns an independent
`EventBusSubscription`. Policy is `.criticalUnbounded` or
`.lossyNewest(limit)`. Optional `FactInterestDescriptor` filters before every
live, batch, and replay yield.

### `actor FilesystemActor`

App-wide instance (constructed by `FilesystemGitPipeline`, not `.shared`).
FSEvents ingress, deepest-root routing, path filtering, debounce/max-latency,
chunked `filesChanged` and topology facts.

### `actor GitWorkingDirectoryProjector`

Consumes filesystem facts; emits `snapshotChanged`, `branchChanged`,
`originChanged`, worktree discovery/removal. Coalescing and demand cadence:
[Workspace Data Architecture](../state/workspace_data_architecture.md).

### `actor ForgeActor`

App-wide instance, keyed by repo in actor state (not `.shared`). Demand-driven PR/forge enrichment with per-repo
single-flight, policy backoff, and equality-suppressed publication. Triggered
by bus branch/origin facts, demand deadlines, and direct
`refresh(repo:)` commands — not by duplicate coordinator polling.

Container and plugin actors remain deferred capability, not remaining work for
the current plane.

## Connection patterns (condensed)

| Need | Pattern |
| --- | --- |
| Multi-subscriber admitted facts | `bus.post` / `subscribe(policy:subscriberName:factInterest:)` |
| Request-response control | Direct async call on capability protocol |
| UI binding | `@Observable` on MainActor (before bus when multiplexed) |
| Heavy one-shot work from MainActor | `@concurrent nonisolated static` helper |
| Never | Raw C callback → bus; command enum on bus; NotificationCenter for app-domain coordination |

**Bus enrichment rule:** each boundary actor enriches independently and posts
back. The bus never interprets payload meaning.

## Threading Model

| Isolation | What runs |
| --- | --- |
| `@MainActor` | Runtimes, stores, coordinators, views, reducers, thin adapters |
| `actor EventBus` / Filesystem / Git / Forge | Boundary work + fan-out |
| `@concurrent nonisolated` | Blocking/heavy one-shot helpers escaping an actor |

Event-plane data does not hop core-actor → core-actor directly; it goes through
the bus. Command-plane calls from coordinator to an actor are direct.

### Swift 6.2 concurrency rules (SE-0461)

1. **`@concurrent nonisolated`** for explicit pool execution from actor types.
2. **`nonisolated async` inherits caller isolation** in 6.2 — it is not pool escape.
3. Prefer `@concurrent` over `Task.detached` except cancellation-resistant
   SDK/process ownership with explicit completion and no actor-isolated mutable
   capture.
4. Cross-boundary payloads are `Sendable`.
5. C callbacks use `@Sendable` trampolines — no `DispatchQueue.main.async`.

### Swift 6.2 Gotchas (quick reference)

| Gotcha | Wrong | Right |
| --- | --- | --- |
| `nonisolated async` ≠ pool | `nonisolated func doWork() async` | `@concurrent nonisolated func doWork() async` |
| `@concurrent` needs nonisolated | `@concurrent` on actor-isolated method using `self` | `@concurrent nonisolated static func` with snapshot args |
| `Task { }` inherits actor | `Task { heavyWork() }` inside `@MainActor` | `await Self.heavyWork(data)` on `@concurrent nonisolated static` |
| `Task.detached` strips context | Detached for ordinary pool work | `@concurrent nonisolated static` |

## Admission And Hop Shape

```text
Terminal exact fact/control
  copied callback payload
    -> exhaustive source disposition
    -> selected MainActor runtime path
    -> EventBus only when coordination needs the exact fact

Terminal local sample
  copied callback payload
    -> exhaustive source disposition
    -> fixed-key coalescing + bounded aggregation
    -> one compact MainActor apply
    -> TerminalActivityProjector actor
    -> changed semantic outcome
    -> MainActor router -> EventBus

Filesystem/Git effect
  closed source event
    -> exhaustive project-or-ignore admission
    -> full reconciliation only for topology authority changes
       OR affected-key projection for ordinary pane/CWD/active changes
```

MainActor and EventBus hops scale with drains and changed outcomes, not raw
callback count. Coalescing and aggregation are source contraction — not
lossy bus deduplication.

`performance.terminal.compact_apply` measures synchronous MainActor drain work
only; `activity_projection.round_trip_ms` covers the projector hop when
submitted. A timer spanning `await` projector is not continuous MainActor
occupancy proof.

## Current shipped behavior

EventBus with named policy subscriptions and fact-topic interest,
FilesystemActor, GitWorkingDirectoryProjector, ForgeActor, consumer-side
coalescing, bounded replay, and delivery diagnostics are shipped. Do not treat
historical migration ledgers or deferred plugin/container essays as remaining
current-plane work.

## Related

- [Pane Runtime Architecture](pane_runtime_architecture.md) — contracts and new-signal tree
- [Demand-Driven Derived-State Refresh](../state/demand_driven_derived_state_refresh.md) — classify input before mechanism
- [Workspace Data Architecture](../state/workspace_data_architecture.md) — filesystem/Git/sidebar projection
- [Observability — Proof Model](../observability/observability_and_traceability.md#proof-model) — marker-scoped performance proof
