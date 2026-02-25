# Pane Runtime EventBus Design

> **Status:** Companion design for event coordination architecture
> **Target:** Swift 6.2 / macOS 26 (uses `@concurrent`, not `Task.detached`)
> **Companion:** [Pane Runtime Architecture](pane_runtime_architecture.md) remains the contract source of truth

## TL;DR

One `actor EventBus` on cooperative pool. Boundary actors for filesystem/network. `@MainActor` runtimes for `@Observable` state. `@Observable` for UI binding, bus for coordination — same event, multiplexed. `@concurrent` for heavy one-shot per-pane work (scrollback search, artifact extraction, diff computation). Swift 6.2 / macOS 26.

## Why This Exists

The pane runtime architecture (C1-C16) defines **what** must be true. This document defines the concrete coordination **how** — the event bus that connects producers to consumers across actor boundaries.

Four problems drive this design:

1. **Multi-subscriber coordination.** Reducer, coordinator, and future analytics all need the same events. A single `AsyncStream` with one consumer doesn't broadcast. The bus provides fan-out: one `post()`, N independent subscriber streams.

2. **Off-MainActor producers.** Filesystem watchers (FSEvents + git status), network services (forge polling, container health), and future plugin hosts do real work — 1ms to 100ms+ — that shouldn't block the UI thread. Boundary actors own this work and post enriched envelopes to the bus.

3. **One-way data flow.** Events flow producers → bus → subscribers. Commands flow user/system → coordinator → runtime. These never share the same channel. The bus carries events only.

4. **Consistent pattern.** All producers `await bus.post(envelope)`, all consumers `for await envelope in bus.subscribe()`. Whether the event originates from a Ghostty C callback, an FSEvents watcher, or a future MCP plugin — same interface.

## Relationship to Pane Runtime Architecture

Each contract (C1-C16) has a specific relationship to the EventBus:

| Contract | Name | Data Flow Direction | Actor Boundary | Relationship to EventBus |
|----------|------|---------------------|----------------|--------------------------|
| C1 | PaneRuntime | Bidirectional | @MainActor | Commands in via coordinator, events out via bus |
| C2 | PaneKindEvent | Outbound | @MainActor → EventBus | Events self-classify priority, flow to bus |
| C3 | PaneEventEnvelope | Outbound | Any → EventBus → @MainActor | Envelopes are the bus payload |
| C4 | ActionPolicy | Read-only | @MainActor | Reducer reads policy from envelope after bus delivery |
| C5 | Lifecycle | Internal | @MainActor | Forward-only transitions, state on @MainActor |
| C5a | Attach Readiness | Internal | @MainActor | Readiness gates for surface attach |
| C5b | Restart Reconcile | Internal | @MainActor | Reconcile at launch |
| C6 | Filesystem Batching | Outbound | FilesystemActor → EventBus | Boundary actor produces, bus delivers |
| C7 | GhosttyEvent FFI | Inbound→Outbound | C thread → @MainActor → EventBus | Translate on MainActor, multiplex to bus |
| C7a | Action Coverage | Policy | @MainActor | Coverage policy, no actor boundary change |
| C8 | Per-Kind Events | Outbound | @MainActor → EventBus | Per-kind events flow through bus |
| C9 | Execution Backend | Config | @MainActor | Immutable config, no bus involvement |
| C10 | Command Dispatch | Inbound | @MainActor → Runtime | Commands go OPPOSITE direction from events |
| C11 | Registry | Lookup | @MainActor | Map, no direction |
| C12 | NotificationReducer | Consumer | EventBus → @MainActor | Subscribes to bus, classifies, delivers |
| C12a | Visibility Tiers | Policy | @MainActor | Tier resolved from UI state on MainActor |
| C13 | Workflow Engine | Consumer (deferred) | EventBus → @MainActor | Future bus subscriber |
| C14 | Replay Buffer | Internal | @MainActor | Per-runtime, filled at emit time |
| C15 | Process Channel | Source (deferred) | Future boundary | Not through EventBus (request/response) |
| C16 | Filesystem Context | Projection (deferred) | @MainActor | Derived from C6 events on MainActor |

## Architecture Overview

```
                           PRODUCERS
    ─────────────────────────────────────────────────────

    BOUNDARY 1              BOUNDARY 2              BOUNDARY 3
    Terminal/FFI            Filesystem/CLI          Network/Plugin
    (~100ns translate)      (~1-100ms work)         (~100ms+ I/O)

    C callback              FSEvents callback       HTTP polling
    → @Sendable trampoline  → actor Filesystem      → actor Network
    → MainActor translate   → debounce + git status → parse + enrich
    → runtime.emit()        → bus.post(envelope)    → bus.post(envelope)
         │                        │                       │
         │ bus.post(envelope)     │                       │
         ▼                        ▼                       ▼
    ┌─────────────────────────────────────────────────────────────┐
    │               actor EventBus<PaneEventEnvelope>             │
    │                    (cooperative pool)                        │
    │                                                             │
    │   subscribers: [UUID: AsyncStream.Continuation]             │
    │   subscribe() → independent stream per caller               │
    │   post() → fan-out to all continuations                     │
    │   fan-out only — no domain logic, no filtering              │
    └─────────────────────────────────────────────────────────────┘
         │                  │                    │
         ▼                  ▼                    ▼
    ┌──────────┐   ┌──────────────────┐   ┌────────────────┐
    │ Reducer  │   │  Coordinator     │   │ Future:        │
    │ (C12)    │   │  cross-pane      │   │ analytics,     │
    │          │   │  workflows       │   │ workflow (C13) │
    └──────────┘   └──────────────────┘   └────────────────┘

                    @MainActor CONSUMERS
    ─────────────────────────────────────────────────────
```

Actor count: 3 named actors (EventBus, FilesystemActor, NetworkActor) plus `@MainActor`. Ghostty C callback translation does NOT need its own actor — the work is ~100ns (enum match + struct init), far below the actor hop cost threshold.

## The Multiplexing Rule

The same domain event takes two paths simultaneously:

```
    Terminal Runtime (@MainActor)
    receives GhosttyEvent.titleChanged("new title")
                │
                ├──► @Observable mutation: metadata.title = "new title"
                │    (SwiftUI views bind directly — zero overhead)
                │
                └──► bus.post(PaneEventEnvelope(
                │        source: .pane(paneId),
                │        event: .terminal(.titleChanged("new title"))
                │    ))
                │    (coordination consumers: tab bar update, notifications, analytics)

    Bridge Runtime (@MainActor)
    receives RPC event: commandFinished(exitCode: 0)
                │
                ├──► @Observable mutation: agentState.lastExitCode = 0
                │    (SwiftUI views bind directly)
                │
                └──► bus.post(PaneEventEnvelope(
                         source: .pane(paneId),
                         event: .agent(.commandFinished(exitCode: 0))
                     ))
                     (coordinator triggers diff pane creation, reducer posts notification)
```

**The test:** "Would any other component in the system care about this event?"
- **Yes → bus.** `titleChanged`, `cwdChanged`, `commandFinished`, `bellRang`, `navigationCompleted`, `filesChanged`, `surfaceCreated`, `paneClosed`. These are domain-significant — other components (tab bar, notifications, dynamic views, workflow engine) need to react.
- **No → `@Observable` only.** `scrollbarState` at 60fps, `searchState` incremental results, `isLoading` for progress spinner. Only the bound SwiftUI view cares.

The `@Observable` mutation always happens regardless. The bus post is the multiplexing decision.

## Event Classification Inventory

### Category 1: Direct MainActor Only (no bus)

User input and commands. These start on MainActor, target the C API or `@Observable` store mutations, and no other component cares about the raw input.

| Event | Origin | Target |
|-------|--------|--------|
| Keyboard input | AppKit responder chain | `ghostty_surface_key()` C call |
| Mouse events (click, scroll, drag) | AppKit responder chain | `ghostty_surface_mouse_*()` C call |
| Resize | AppKit layout | `ghostty_surface_set_size()` C call |
| Focus change | NSWindow delegate | `ghostty_surface_set_focus()` C call |
| Tab click / split drag | UI gesture | `WorkspaceStore` mutation |
| Command palette selection | `CommandBarState` | `PaneCoordinator.dispatch()` |
| Bridge RPC commands (Swift→React) | Coordinator | `PushTransport` / `RPCRouter` |

### Category 2: @Observable UI State (multiplexed when domain-significant)

High-frequency UI binding state. SwiftUI views bind directly. Multiplexed to bus only when the event is domain-significant (other components need it).

| Property | Runtime | Frequency | Bus? | Why |
|----------|---------|-----------|------|-----|
| `metadata.title` | All | Low (~1/sec) | Yes | Tab bar, notifications, dynamic views need title |
| `metadata.facets.cwd` | Terminal | Low | Yes | Worktree context, dynamic view grouping |
| `lifecycle` | All | Rare | Yes | Lifecycle transitions are domain events (C5) |
| `searchState` | Terminal | High (60fps) | No | Only the terminal's search UI cares |
| `scrollbarState` | Terminal | High (60fps) | No | Only the terminal's scrollbar view cares |
| `url` / `title` | Webview | Low | Yes | Tab bar, notifications |
| `isLoading` | Webview, Bridge | Medium | No | Only the loading spinner cares |
| `bridgeState` | Bridge | Low | Yes | Coordinator needs ready/handshake state |

### Category 3: Pane Metadata Events (bus — informational, fan-out)

Events from pane runtimes that are informational, tolerate 1+ frame latency, and benefit from multi-subscriber fan-out.

| Event | Origin | Latency Budget | Frequency | Bus |
|-------|--------|----------------|-----------|-----|
| `titleChanged` | Ghostty C callback → MainActor | 1 frame (16ms) | ~1/sec | Yes |
| `cwdChanged` | Ghostty C callback → MainActor | 1 frame | Rare | Yes |
| `commandFinished` | Ghostty C callback → MainActor | 1 frame | Low | Yes — triggers workflow |
| `bellRang` | Ghostty C callback → MainActor | 1 frame | Rare | Yes — notification |
| `scrollbarChanged` | Ghostty C callback → MainActor | 0 (immediate) | 60fps | No — `@Observable` only |
| `navigationCompleted` | WebKit delegate → MainActor | 1 frame | Low | Yes |
| `pageLoaded` | WebKit delegate → MainActor | 1 frame | Low | Yes |
| `consoleMessage` | WebKit delegate → MainActor | Lossy ok | Medium | Yes — debugging |
| Bridge RPC events (React→Swift) | `RPCRouter` → MainActor | 1 frame | Low | Yes — coordination |

### Category 4: System Events (strongest bus case — off-MainActor work)

Events from boundary actors. Real work (filesystem scanning, network I/O) justifies actor isolation. Multiple consumers always need these.

| Event | Origin | Work Duration | Frequency | Bus |
|-------|--------|---------------|-----------|-----|
| `filesChanged` | FSEvents → `FilesystemActor` | 1-100ms (git status) | Batched, ~1/sec burst | Yes |
| `gitStatusChanged` | `FilesystemActor` | 10-100ms (git diff) | After batch flush | Yes |
| `branchChanged` | `FilesystemActor` | 1-10ms | Rare | Yes |
| `diffAvailable` | `FilesystemActor` | 10-100ms (diff compute) | After git status | Yes |
| `securityEvent` | Security backend | Varies | Rare | Yes |
| Future: `prStatusChanged` | `NetworkActor` (forge) | 100ms+ (API call) | Polling interval | Yes |
| Future: `containerHealthChanged` | `NetworkActor` | 100ms+ (API call) | Polling interval | Yes |

### Category 5: Lifecycle Events (bus — rare, benefit from fan-out)

Pane/tab lifecycle transitions. Originate on MainActor, rare, but multiple consumers need them (tab bar, dynamic views, notifications, future analytics).

| Event | Origin | Frequency | Bus |
|-------|--------|-----------|-----|
| `surfaceCreated` | `SurfaceManager` | Rare | Yes |
| `attachStarted` / `attachSucceeded` | `SurfaceManager` | Rare | Yes |
| `paneClosed` | `PaneCoordinator` | Rare | Yes |
| `tabSwitched` | `WorkspaceStore` | Low | Yes |

## Actor Inventory

### `actor EventBus<Envelope: Sendable>`

Cooperative pool actor. Fan-out only — no domain logic, no filtering, no transformation. The bus is a dumb pipe with subscriber management.

```swift
/// Central fan-out for pane/system events.
/// Cooperative pool — NOT @MainActor.
/// All producers `await bus.post()`, all consumers `for await` from bus.
actor EventBus<Envelope: Sendable> {
    private var subscribers: [UUID: AsyncStream<Envelope>.Continuation] = [:]

    /// Register a new subscriber. Returns an independent stream.
    /// Each subscriber gets its own continuation — no shared iteration.
    func subscribe() -> AsyncStream<Envelope> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Envelope>.makeStream()
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        subscribers[id] = continuation
        return stream
    }

    /// Fan out an envelope to all active subscribers.
    func post(_ envelope: Envelope) {
        for continuation in subscribers.values {
            continuation.yield(envelope)
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers.removeValue(forKey: id)
    }
}
```

**Why actor, not class with lock:** Swift actors are the standard concurrency primitive. The cooperative pool gives fair scheduling without dedicated thread overhead. `await bus.post()` is the consistent interface for all producers regardless of their isolation context.

**Why one bus, not per-pane:** Coordination consumers (reducer, coordinator, workflow engine) need events from ALL panes. Per-pane buses would require N subscriptions and a manual merge step — exactly the centralization problem the bus solves.

### `actor FilesystemActor` (future — LUNA-349)

One instance per worktree. Owns FSEvents subscription, debounce logic, git status computation, and diff production. Posts enriched `PaneEventEnvelope` to EventBus.

```swift
/// Per-worktree filesystem observation. Owns the expensive work
/// that justifies an actor boundary: FSEvents → debounce → git status → diff.
///
/// The actor boundary is justified because git status + diff compute
/// takes 1-100ms — well above the ~20μs break-even for actor hop cost.
actor FilesystemActor {
    private let worktreeId: WorktreeId
    private let worktreePath: URL
    private let bus: EventBus<PaneEventEnvelope>
    private let clock: any Clock<Duration>

    /// Heavy inner work runs on cooperative pool via @concurrent.
    @concurrent
    private static func computeGitStatus(
        worktreePath: URL
    ) async -> GitStatusSummary {
        // Shell out to git status, parse output
        // 10-100ms of real work
    }

    @concurrent
    private static func computeDiff(
        worktreePath: URL,
        changeset: FileChangeset
    ) async -> DiffResult {
        // git diff computation
        // 10-100ms of real work
    }
}
```

### `actor NetworkActor` (future)

Forge API polling, container health checks. 100ms+ network I/O justifies actor isolation. Posts to EventBus.

### `@MainActor` (existing, unchanged)

All runtimes (`TerminalRuntime`, future `BridgeRuntime`, `WebviewRuntime`, `SwiftPaneRuntime`), all stores (`WorkspaceStore`, `SurfaceManager`, `SessionRuntime`), `PaneCoordinator`, `NotificationReducer`, views, `ViewRegistry`.

These consume from EventBus via `for await`:

```swift
@MainActor
final class NotificationReducer {
    private let bus: EventBus<PaneEventEnvelope>

    func startConsuming() {
        Task { @MainActor in
            for await envelope in await bus.subscribe() {
                classify(envelope)
            }
        }
    }
}
```

## Per-Pane Heavy Work: `@concurrent`

Heavy per-pane work (scrollback search, artifact extraction, log parsing, diff computation) uses `@concurrent` static functions. This is the Swift 6.2 pattern for explicit cooperative pool execution.

### Swift 6.2 rules

- **`@concurrent`** explicitly runs on cooperative pool. This is the correct way to offload CPU-bound work.
- **NOT `nonisolated async`** — in Swift 6.2, `nonisolated async` inherits caller isolation. A `nonisolated async` method called from `@MainActor` runs ON MainActor in 6.2. This is a behavioral change from Swift 6.0.
- **NOT `Task.detached`** — strips task priority, task-locals, and structured concurrency. `@concurrent` preserves all of these.
- **NOT `MainActor.run`** — unnecessary. When returning from a `@concurrent` function back to a `@MainActor` caller, the compiler automatically handles the hop.

### Pattern: Runtime offloads heavy work

```swift
@MainActor
final class TerminalRuntime {
    func searchScrollback(query: String) {
        Task {
            let snapshot = scrollbackSnapshot      // read on MainActor
            let matches = await Self.performSearch(snapshot, query: query)
            searchResults = matches                // back on MainActor automatically
        }
    }

    /// Heavy regex search runs on cooperative pool, not MainActor.
    /// @concurrent ensures this does NOT inherit @MainActor isolation.
    @concurrent
    private static func performSearch(
        _ snapshot: ScrollbackSnapshot, query: String
    ) async -> [SearchMatch] {
        // 1-50ms of regex work — would stall UI if on MainActor
        regexSearch(snapshot, query: query)
    }
}
```

### Where `@concurrent` applies

| Location | Work | Why @concurrent |
|----------|------|-----------------|
| `TerminalRuntime.performSearch()` | Regex across scrollback buffer | 1-50ms, would stall UI |
| `TerminalRuntime.extractArtifacts()` | Parse terminal output for file paths, URLs, diffs | 1-10ms per extraction |
| `TerminalRuntime.parseLogOutput()` | Structured log parsing from agent output | 1-20ms per batch |
| `FilesystemActor.computeGitStatus()` | Shell to `git status`, parse output | 10-100ms |
| `FilesystemActor.computeDiff()` | Shell to `git diff`, parse hunks | 10-100ms |
| `BridgeRuntime.computeDiffHunks()` | Diff computation for bridge display | 10-50ms |
| `BridgeRuntime.hashFileContent()` | SHA256 for file content dedup | 1-10ms per file |
| Future: artifact extraction from any runtime | File path extraction, URL detection, code block parsing | 1-20ms |

## Data Flow Summary

Two one-way channels. They never share infrastructure.

```
EVENTS (one-way, producers → bus → consumers):

  Runtimes (@MainActor)          Boundary actors              Future sources
  ├── TerminalRuntime            ├── FilesystemActor          ├── NetworkActor
  ├── BridgeRuntime              │   (FSEvents, git status,   │   (forge polling,
  ├── WebviewRuntime             │    diff compute)            │    container health)
  └── SwiftPaneRuntime           └── SecurityBackend          └── Plugin hosts
         │                              │                           │
         └──────────────────────────────┼───────────────────────────┘
                                        │
                                        ▼
                              actor EventBus<PaneEventEnvelope>
                                        │
                         ┌──────────────┼──────────────┐
                         ▼              ▼              ▼
                  NotificationReducer  PaneCoordinator  Future: WorkflowEngine,
                  (C12: classify,      (cross-pane      analytics, plugins
                   schedule, deliver)   workflows)


COMMANDS (one-way, user/system → coordinator → runtime):

  User Input / CommandBar / External API
         │
         ▼
  PaneCoordinator
         │
         ▼
  RuntimeRegistry.lookup(paneId)
         │
         ▼
  runtime.handleCommand(RuntimeCommandEnvelope)

  Commands and events NEVER share the same channel.
```

## Threading Model

Concrete list of what runs where, with Swift 6.2 keywords:

| Isolation | What Runs Here | Swift 6.2 Keyword |
|-----------|----------------|-------------------|
| `@MainActor` | Runtimes, stores, coordinator, views, reducer, ViewRegistry | `@MainActor` on class/func |
| `actor EventBus` | Subscriber management, fan-out | `actor` (cooperative pool) |
| `actor FilesystemActor` | FSEvents, debounce, git status, diff (future) | `actor` (cooperative pool) |
| `actor NetworkActor` | Forge polling, container health (future) | `actor` (cooperative pool) |
| Cooperative pool (anonymous) | Heavy per-pane one-shot work (search, parse, extract, hash) | `@concurrent` on static func |

### Swift 6.2 concurrency rules

1. **`@concurrent`** for explicit pool execution. This is the replacement for `Task.detached` and the correct way to say "run this on the cooperative pool, not on my caller's actor."
2. **`nonisolated async`** inherits caller isolation in Swift 6.2 (SE-0461). Do NOT use this expecting pool execution — it will run on MainActor if called from MainActor.
3. **No `Task.detached`** — strips priority and task-locals. `@concurrent` preserves structured concurrency.
4. **No `MainActor.run`** — the compiler handles actor hops when returning from `@concurrent` to `@MainActor`. Explicit `MainActor.run` is unnecessary and adds noise.
5. **All cross-boundary data is `Sendable`.** `PaneEventEnvelope`, all event types, all command types — `Sendable` is required for data that crosses actor boundaries.
6. **C callbacks use `@Sendable` trampolines** + `MainActor.assumeIsolated` for synchronous hops or `Task { @MainActor in }` for async work. No `DispatchQueue.main.async`.

## Hop Analysis

### Current system: 1 hop

```
C callback (arbitrary thread)
    │
    └──► @Sendable trampoline ──► MainActor.assumeIsolated
              HOP 1: ~2-6μs
                    │
                    ▼
         GhosttyAdapter.translate()     ~100ns
         TerminalRuntime.handleEvent()  ~500ns
         NotificationReducer.submit()   ~200ns
         PaneCoordinator.route()        ~200ns
                                        ────────
                                 Total: ~1μs + 1 hop
```

### EventBus system: 2-3 hops

```
C callback (arbitrary thread)
    │
    └──► @Sendable trampoline ──► MainActor
              HOP 1: ~2-6μs
                    │
                    ▼
         GhosttyAdapter.translate()     ~100ns
         TerminalRuntime:
           @Observable mutation         ~200ns (SwiftUI binding)
           await bus.post(envelope)
              HOP 2: ~2-6μs (MainActor → EventBus actor)
                    │
                    ▼
              EventBus.post() fan-out   ~100ns per subscriber
              HOP 3: ~2-6μs (EventBus → MainActor per consumer)
                    │
                    ▼
         NotificationReducer.submit()   ~200ns
         PaneCoordinator.route()        ~200ns
                                        ────────
                                 Total: ~1μs work + 2-3 hops (~4-18μs)
```

### Boundary actor path: 3 hops (justified by work)

```
FSEvents callback (arbitrary thread)
    │
    └──► FilesystemActor
              HOP 1: ~2-6μs
                    │
                    ▼
         Debounce + git status + diff   1-100ms (REAL WORK)
         @concurrent inner functions    (pool execution)
                    │
                    ▼
         await bus.post(envelope)
              HOP 2: ~2-6μs (FilesystemActor → EventBus)
                    │
                    ▼
         EventBus.post() fan-out
              HOP 3: ~2-6μs (EventBus → MainActor)
                    │
                    ▼
         @MainActor consumers           ~1μs
                                        ────────
                                 Total: 1-100ms work + 3 hops (~6-18μs)
```

### Break-even analysis

| Metric | Value | Note |
|--------|-------|------|
| Actor hop cost | ~2-6μs | Cooperative pool context switch |
| Frame budget | 16,000μs (16ms at 60fps) | AppKit event loop frame |
| Ghostty event work | ~1μs | Enum match + struct init |
| EventBus overhead per event | ~4-18μs (2-3 hops) | Acceptable: 0.1% of frame |
| Boundary actor justified when | work > ~20μs | Hop cost amortized by real work |
| FilesystemActor work | 1,000-100,000μs | Strongly justified |
| NetworkActor work | 100,000μs+ | Strongly justified |
| Ghostty translation work | ~0.1μs | NOT justified — stay on MainActor |

## Jank Risk Assessment

| Source | Risk | Why | Mitigation |
|--------|------|-----|------------|
| EventBus fan-out per event | Very low | ~100ns per subscriber × 3-5 subscribers = ~500ns | None needed |
| Actor hop overhead (2-3 hops) | Low | ~4-18μs per event, <0.1% of 16ms frame | Monitor if subscriber count grows beyond ~50 |
| Burst: 100 events in 1 frame | Low | 100 × 18μs = 1.8ms = 11% of frame | Lossy coalescing (C4 ActionPolicy) already dedupes |
| Filesystem git status on MainActor | **High (prevented)** | 10-100ms blocks UI | FilesystemActor keeps this off MainActor |
| Heavy scrollback search on MainActor | **High (prevented)** | 1-50ms blocks UI | `@concurrent` static function |
| Ghostty terminal rendering | **None** | Ghostty has its own Metal/GPU pipeline, independent of Swift event system | N/A — not in our control or concern |

**Key insight:** Ghostty renders on its own Metal pipeline. Terminal rendering cannot jank from Swift event processing — they are completely independent. Swift jank only happens if `@MainActor` blocks the AppKit event loop for >16ms. The EventBus adds ~4-18μs per event, well within budget.

## Adoption Plan

Incremental, each step independently shippable:

1. **Multi-subscriber fan-out on existing runtimes.** Replace single `AsyncStream.Continuation` with array of continuations. Runtime's `subscribe()` returns independent stream per caller. This is a prerequisite for the bus — it proves fan-out semantics work at the runtime level.

2. **Introduce `actor EventBus<PaneEventEnvelope>`.** Central merge point. Runtimes post to bus after `@Observable` mutation. Reducer and coordinator subscribe from bus instead of per-runtime streams.

3. **Migrate consumers to bus subscriptions.** `NotificationReducer`, `PaneCoordinator`, and any future consumers subscribe to the bus. Per-runtime subscriptions become an implementation detail (runtime → bus posting).

4. **Add `actor FilesystemActor`** when FSEvents watcher ships (LUNA-349). First real boundary actor. Posts enriched envelopes with `source = .system(.builtin(.filesystemWatcher))`.

5. **Add `actor NetworkActor`** when forge/container services ship. Second boundary actor. Same posting pattern.

6. **Migrate heavy per-pane work to `@concurrent`** as it appears. Scrollback search, artifact extraction, log parsing — each gets a `@concurrent static func` instead of inline MainActor processing. The D1 processing budget guidance in pane_runtime_architecture.md reflects this pattern.

## Verification Checklist

1. No MainActor frame stalls from event processing (benchmark: 100 events/frame stays under 2ms)
2. Every envelope reaches all subscribers (fan-out correctness: post once, N streams receive)
3. Events and commands flow in opposite directions (never share channel)
4. All cross-boundary payloads are `Sendable` (compiler-enforced)
5. `@concurrent` used for cooperative pool execution, not `nonisolated async` (which inherits caller in 6.2)
6. No `Task.detached` in new code (use `@concurrent` instead)
7. No `MainActor.run` in new code (compiler handles hops)
8. Coordinator remains sequencing-only (no domain logic in fan-out paths)
9. `@Observable` mutations happen synchronously on MainActor before bus posting (UI never lags behind coordination)
