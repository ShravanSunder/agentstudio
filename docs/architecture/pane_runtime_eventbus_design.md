# Pane Runtime EventBus Design

> **Status:** Companion design for event coordination architecture
> **Target:** Swift 6.2 / macOS 26 (uses `@concurrent nonisolated`, not `Task.detached`)
> **Companion:** [Pane Runtime Architecture](pane_runtime_architecture.md) remains the contract source of truth
> **Governing model:** [Three Data Flow Planes](pane_runtime_architecture.md#three-data-flow-planes) — event plane (this doc), command plane (direct dispatch), UI plane (`@Observable`)

## TL;DR

One `actor EventBus` on cooperative pool. Domain boundary actors (FilesystemActor, ForgeActor, ContainerActor) for off-MainActor work — each owns its transport internally. `@MainActor` runtimes for `@Observable` state. `@Observable` for UI binding, bus for coordination — same event, multiplexed. `@concurrent` for heavy one-shot per-pane work. No core actor calls another core actor for event-plane data (command-plane request-response calls are direct). Plugin sources are actors with injected `PluginContext` for mediated bus access (deferred). Swift 6.2 / macOS 26.

## Why This Exists

The pane runtime architecture (C1-C16) defines **what** must be true. This document defines the concrete coordination **how** — the event bus that connects producers to consumers across actor boundaries.

Four problems drive this design:

1. **Multi-subscriber coordination.** Reducer, coordinator, and future analytics all need the same events. A single `AsyncStream` with one consumer doesn't broadcast. The bus provides fan-out: one `post()`, N independent subscriber streams.

2. **Off-MainActor producers.** Filesystem watchers (FSEvents + git status), forge integrations (PR polling, checks), container health monitors, and future plugin hosts do real work — 1ms to 100ms+ — that shouldn't block the UI thread. Domain boundary actors own this work and post enriched envelopes to the bus.

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

    BOUNDARY 1              BOUNDARY 2              BOUNDARY 3            BOUNDARY 4
    Terminal/FFI            Filesystem/Git          Forge                 Container (deferred)
    (~100ns translate)      (~1-100ms work)         (~100ms-2s I/O)       (~100ms+ I/O)

    C callback              FSEvents callback       gh CLI / HTTP         HTTP / Docker API
    → @Sendable trampoline  → FilesystemActor       → ForgeActor          → ContainerActor
    → MainActor translate   → batch facts + git projector → poll PR / checks    → poll health
    → runtime.emit()        → bus.post(envelope)    → bus.post(envelope)  → bus.post(envelope)
         │                        │                       │                     │
         │ bus.post(envelope)     │                       │                     │
         ▼                        ▼                       ▼                     ▼
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

**Actor inventory:** 4 named actors (EventBus, FilesystemActor, ForgeActor, ContainerActor) plus `@MainActor`. No core actor calls another core actor for event-plane data — all event-plane communication flows through the EventBus. Command-plane request-response calls (e.g., `forgeActor.refresh(repo:)`) are direct. Ghostty C callback translation does NOT need its own actor — the work is ~100ns (enum match + struct init), far below the actor hop cost threshold. Git CLI write commands (commit, push, stash) are stateless request-response via ProcessExecutor — no actor needed. Shared infrastructure (URLSession, ProcessExecutor) is injected utilities, not actors.

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
| `filesChanged` | FSEvents → `FilesystemActor` | 1-100ms (ingest + route + batch) | Batched, ~1/sec burst | Yes |
| `gitSnapshotChanged` | `GitWorkingDirectoryProjector` | 10-100ms (git status) | After filesystem batch | Yes |
| `branchChanged` | `GitWorkingDirectoryProjector` | 1-10ms | Rare | Yes |
| `diffAvailable` | `FilesystemActor` | 10-100ms (diff compute) | After git status | Yes |
| `securityEvent` | Security backend | Varies | Rare | Yes |
| Future: `prStatusChanged` | `ForgeActor` | 100ms-2s (`gh` CLI or HTTP) | Polling ~30-60s | Yes |
| Future: `checksUpdated` | `ForgeActor` | 100ms-2s (`gh` CLI or HTTP) | Polling ~30-60s | Yes |
| Future: `containerHealthChanged` | `ContainerActor` | 100ms+ (Docker API / HTTP) | Polling ~5-10s | Yes |

### Filesystem → Git Projector Decision Tree

1. **Need one app-wide filesystem source**
   `FilesystemActor` owns ingestion, ownership routing, filtering, debounce, max-latency, and chunking.
2. **Need local git state updates without overloading ingress**
   `GitWorkingDirectoryProjector` subscribes to filesystem facts and computes derived git facts.
3. **Need pane/worktree fan-out without duplicate subscriptions**
   Both source and projector publish facts to the shared EventBus; stores/projectors subscribe as needed.
4. **Need bounded behavior under bursts**
   `FilesystemActor` batches by path, `GitWorkingDirectoryProjector` coalesces by `worktreeId` (latest wins).
5. **Need clear ownership boundaries**
   Local working-directory projection lives here; remote GitHub/forge status remains with forge services.

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

**Buffer policy:** `AsyncStream.makeStream()` defaults to unbounded buffering. Under burst conditions (agent dumps 500 lines → 500 events in quick succession), subscriber streams can grow unbounded. Policy per subscriber tier:
- **Critical subscribers** (NotificationReducer, PaneCoordinator): unbounded. These must never drop events — correctness depends on completeness. They consume quickly on MainActor.
- **Lossy subscribers** (analytics, logging, future plugin sinks): use `.bufferingPolicy(.bufferingNewest(100))` on `makeStream()`. Dropping oldest events under burst is acceptable — these consumers don't need total recall.
- **The bus itself does not enforce buffer policy** — it yields to every continuation unconditionally. Buffer policy is chosen at `subscribe()` time by the caller, not imposed by the bus. This keeps the bus dumb.

**onTermination cleanup:** The `Task { await self?.removeSubscriber(id) }` in `onTermination` is intentionally unstructured. `onTermination` is a synchronous `@Sendable` closure — it cannot `await` directly. The unstructured Task is the only way to reach actor-isolated `removeSubscriber`. If the EventBus actor is deallocated before the cleanup Task runs, `self` is nil and the entry is harmless (dead actor's dictionary is already gone). This is an acceptable trade-off for the cleanup ergonomics.

**Why one bus, not per-pane:** Coordination consumers (reducer, coordinator, workflow engine) need events from ALL panes. Per-pane buses would require N subscriptions and a manual merge step — exactly the centralization problem the bus solves.

### `actor FilesystemActor` (LUNA-349)

App-wide singleton, keyed by worktree internally. Owns filesystem ingress only:
FSEvents ingestion, deepest-root ownership routing, path filtering (`.git/**` + ignore policy), debounce/max-latency scheduling, and chunked `filesChanged` fact emission.

### `actor GitWorkingDirectoryProjector` (LUNA-349)

App-wide projector actor keyed by worktree identity. Subscribes to filesystem facts and materializes local git working-directory state as facts (`gitSnapshotChanged`, optional `branchChanged`).

```swift
actor FilesystemActor {
    // Ingest + route + filter + batch only.
    func register(worktreeId: WorktreeId, rootPath: URL) async { ... }
    func unregister(worktreeId: WorktreeId) async { ... }
    func enqueueRawPaths(worktreeId: WorktreeId, paths: [String]) { ... }
}

actor GitWorkingDirectoryProjector {
    // Consume facts, coalesce by worktree, materialize git snapshot facts.
    func start() async { ... }
    func shutdown() { ... }
}
```

### `actor ForgeActor` (future)

App-wide singleton, keyed by repo internally. Owns git forge domain: PR status, checks, reviews, merge readiness. **Transport-agnostic** — uses `ProcessExecutor` (`gh` CLI) or `URLSession` (direct API) internally, whichever fits. The actor boundary is the domain, not the transport.

**Why separate from FilesystemActor:** Different I/O profile (network/CLI vs filesystem), different auth model (OAuth tokens vs none), different failure modes (rate limits vs disk errors), different state shape (per-repo vs per-worktree).

**Plugin extensibility (deferred):** When users have their own forge (GitLab, Bitbucket, self-hosted), ForgeActor becomes the integration point. Plugin-provided forge adapters conform to a protocol; ForgeActor dispatches to the right adapter per repo remote URL.

```swift
/// App-wide forge API actor, keyed by repo internally.
/// Polls PR/checks status and posts state changes to the EventBus.
///
/// Transport-agnostic: uses ProcessExecutor (gh CLI) today,
/// URLSession (direct HTTP) later, or both per-repo.
/// The actor boundary is the forge DOMAIN, not the transport.
actor ForgeActor {
    private var repoState: [RepoId: ForgeRepoState] = [:]
    private let processExecutor: ProcessExecutor  // injected utility
    private let bus: EventBus<PaneEventEnvelope>
    private let clock: any Clock<Duration>

    func register(repo: RepoId, remote: URL) { ... }
    func unregister(repo: RepoId) { ... }

    /// Self-driven polling loop — no inbound stream needed.
    func startPolling() async {
        for await _ in clock.timer(interval: .seconds(30)) {
            for (repo, state) in repoState {
                let status = await Self.fetchPRStatus(
                    repo, using: processExecutor
                )
                if status != state.prStatus {
                    repoState[repo]?.prStatus = status
                    await bus.post(PaneEventEnvelope(
                        source: .system(.service(.gitForge(provider: "github"))),
                        event: .forge(.prStatusChanged(repo, status))
                    ))
                }
            }
        }
    }

    /// On-demand refresh (e.g., after git push completes).
    func refresh(repo: RepoId) async { ... }

    @concurrent
    nonisolated private static func fetchPRStatus(
        _ repo: RepoId, using executor: ProcessExecutor
    ) async -> PRStatus {
        // gh pr view --json state,checks,reviews ...
        // or direct HTTP to GitHub API
        // 100ms-2s of I/O
    }
}
```

### `actor ContainerActor` (future, deferred)

Per-terminal actor for container lifecycle management during agent execution. Docker API, devcontainer status, resource usage. Different auth, cadence (~5-10s), and state shape (per-terminal) from ForgeActor. Created when a terminal enters container-backed execution mode; destroyed when the terminal exits it.

### Git CLI Write Commands — No Actor

Git mutations (`git commit`, `git stash`, `git push`, `git checkout`) are **stateless request-response**. They go through the existing command dispatch path:

```
User action → PaneCoordinator → ProcessExecutor → git commit → result
```

No ongoing state = no actor. ProcessExecutor already offloads to `DispatchQueue.global()`. The feedback loop is natural:

- **Local mutations** (commit, stash, checkout): FSEvents fires → FilesystemActor picks up → recomputes git status → `bus.post()` → consumers see updated state.
- **Remote mutations** (push): Coordinator signals `ForgeActor.refresh(repo:)` → ForgeActor re-polls PR status → `bus.post()` if changed.

The command doesn't post to the bus directly — the reactive system handles fanout.

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

Heavy per-pane work (scrollback search, artifact extraction, log parsing, diff computation) uses `@concurrent nonisolated` helpers. This is the Swift 6.2 pattern for explicit cooperative pool execution.

**Why we prefer `static`:** Inside a `@MainActor` class, accidental `self`/state access can pull work back into actor-isolated paths. The safest project pattern is `@concurrent nonisolated static` helpers with explicit value-type inputs (`ScrollbackSnapshot`, `URL`) so no actor-isolated state is captured. This makes pool execution intent obvious in reviews and keeps heavy work off MainActor.

### Swift 6.2 rules (SE-0461)

SE-0461 changes the default isolation behavior for `nonisolated async` functions. In Swift 6.0, `nonisolated async` ran on the cooperative pool. In Swift 6.2, `nonisolated async` inherits the caller's isolation — the new default is `nonisolated(nonsending)`. This means `@concurrent` is now required to explicitly opt into pool execution.

**Critical:** `@concurrent` is only valid on nonisolated declarations (SE-0461). In `@MainActor` types, helpers must first opt out of actor isolation (`nonisolated`) before using `@concurrent` to opt into pool execution.

- **`@concurrent nonisolated`** explicitly runs on cooperative pool. `nonisolated` opts out of the enclosing actor's isolation; `@concurrent` opts into pool execution. This is the project's preferred pattern for offloading CPU-bound work, replacing most uses of `Task.detached`.
- **NOT `nonisolated async` alone** — in Swift 6.2, `nonisolated async` means `nonisolated(nonsending)` by default: it inherits caller isolation. A `nonisolated async` method called from `@MainActor` runs ON MainActor in 6.2. This is a behavioral change from Swift 6.0.
- **Prefer `@concurrent` over `Task.detached`** (project policy) — `Task.detached` strips task priority, task-locals, and structured concurrency. `@concurrent` preserves all of these. Exception: `Task.detached` remains appropriate when you explicitly need to escape structured concurrency (e.g., fire-and-forget background work that must outlive the calling scope) or when you need to strip inherited task-locals intentionally.
- **PaneRuntimeEventChannel bus bridge is an explicit exception** — pane-local subscribers + replay are synchronous and ordered; global EventBus fanout uses a fire-and-forget `Task` so runtime emit paths stay non-blocking. This accepts best-effort cross-runtime fanout (no structured backpressure on that hop) in exchange for keeping pane command handling responsive.
- **Avoid `MainActor.run` in this architecture** — in the typical pattern of awaiting a `@concurrent nonisolated` function from a `@MainActor` caller, the compiler handles the hop back automatically. `MainActor.run` is still valid Swift when you genuinely need to hop TO MainActor from a non-MainActor isolated context (e.g., inside a `nonisolated` actor method that needs a one-off MainActor call), but in our architecture's common paths it adds unnecessary noise.

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
    /// nonisolated opts out of @MainActor; @concurrent opts into pool execution.
    @concurrent
    nonisolated private static func performSearch(
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
| `ShellGitWorkingTreeStatusProvider.computeStatus()` | Shell to `git status`, parse output | 10-100ms |
| `BridgeRuntime.computeDiffHunks()` | Diff computation for bridge display | 10-50ms |
| `BridgeRuntime.hashFileContent()` | SHA256 for file content dedup | 1-10ms per file |
| Future: artifact extraction from any runtime | File path extraction, URL detection, code block parsing | 1-20ms |

## Data Flow Summary

Two one-way channels. They never share infrastructure.

```
EVENTS (one-way, producers → bus → consumers):

  Runtimes (@MainActor)          Domain actors                 Deferred sources
  ├── TerminalRuntime            ├── FilesystemActor          ├── ContainerActor
  ├── BridgeRuntime              │   (app-wide ingestion,      │   (per-terminal)
  ├── WebviewRuntime             │    routing, batching)       ├── Plugin actors
  └── SwiftPaneRuntime           ├── GitWorkingDirectoryProjector │   (per-plugin, mediated)
                                 │   (local git projector       └── SecurityBackend
                                 │    keyed by worktree)
                                 ├── ForgeActor
                                 │   (app-wide, keyed by
                                 │    repo; PR, checks, reviews)
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

## Connection Patterns

Every edge in the architecture uses one of four patterns. The choice is mechanical — answer one question: **is the producer ongoing and decoupled from the consumer?**

```
 ┌─────────────────────────────────────────────────────────┐
 │  IS THE PRODUCER ONGOING AND DECOUPLED FROM CONSUMER?   │
 │                                                         │
 │  Yes + multiple consumers  →  Bus (AsyncStream out)     │
 │  Yes + one known consumer  →  Direct AsyncStream pipe   │
 │  No  + request-response    →  Direct await call         │
 │  No  + UI binding          →  @Observable               │
 │  No  + one-shot/finite     →  Continuation / array      │
 └─────────────────────────────────────────────────────────┘
```

### When to use each pattern

**AsyncStream** — ongoing, decoupled, pull-based:
1. **Bus → subscriber** — always. This is the bus's outbound interface. Decoupled, independent consumption.
2. **Bursty OS/system source → boundary actor** — FSEvents, process stdout, webhook streams. Natural buffering, composes with AsyncAlgorithms (debounce, throttle, merge).
3. **Per-runtime `subscribe()`** — for direct per-pane consumers and replay catch-up continuation.

**Direct `await` call** — known target, request-response, or one-shot:
1. **Any producer → bus** — `await bus.post(envelope)`. Producer knows the bus. One call, one destination.
2. **Adapter → runtime** — route by surfaceId, one target, synchronous on MainActor.
3. **Coordinator → runtime** — command dispatch returns `ActionResult`.
4. **Coordinator → stores** — known targets, domain mutations.
5. **User input → C API** — synchronous, one producer, one consumer.

**`@Observable`** — UI binding, zero overhead:
1. **Runtime state → SwiftUI view** — direct binding via `@Observable` macro tracking.
2. **Projection state → SwiftUI view** — C16 filesystem context, derived from bus events.
3. **Notification state → UI** — reducer writes `@Observable` properties, views bind.

**Never stream** — one-shot signals, bounded queries, lookups:
1. **Readiness gates** (C5a) — fires once, not ongoing. Use `Task.value` or continuation.
2. **Catch-up replay** (C14) — returns `[PaneEventEnvelope]` array, not a stream.
3. **Registry lookup** (C11) — dictionary access, not a flow.
4. **Config read** (C9) — immutable at creation time.

### Per-Contract Stream Decision

| Contract | Stream Decision | Pattern |
|----------|----------------|---------|
| C1 PaneRuntime | `subscribe()` returns AsyncStream; `handleCommand()` is direct call | Stream for outbound events, direct for inbound commands |
| C2 PaneKindEvent | No stream — protocol conformance | Events self-classify via protocol property |
| C3 PaneEventEnvelope | Carried ON streams, not a stream itself | Bus payload |
| C4 ActionPolicy | No stream — read from envelope | Direct property access |
| C5 Lifecycle | `@Observable` for UI; multiplexed to bus via `bus.post()` | Direct write + direct post |
| C5a Attach Readiness | **Not a stream** — one-shot readiness gate | `Task.value` or continuation. State machine transition, not ongoing. |
| C5b Restart Reconcile | **Not a stream** — one-shot at launch | Direct call during app startup |
| C6 Filesystem Batching | **AsyncStream inbound** (FSEvents → actor); direct `bus.post()` outbound | Stream for bursty OS events + debounce; direct for bus delivery |
| C7 GhosttyEvent FFI | **Not a stream** — individual C callback hops | Direct trampoline → direct call to runtime |
| C7a Action Coverage | No stream — compile-time exhaustiveness | Policy, not data flow |
| C8 Per-Kind Events | Flow through bus → AsyncStream from `bus.subscribe()` | Stream at bus boundary only |
| C9 Execution Backend | No stream — immutable config | Read-only at creation time |
| C10 Command Dispatch | **Not a stream** — request-response | `await runtime.handleCommand() -> ActionResult` |
| C11 Registry | No stream — synchronous lookup map | `registry[paneId]` |
| C12 NotificationReducer | **AsyncStream inbound** from `bus.subscribe()` | Stream from bus; @Observable outbound |
| C12a Visibility Tiers | No stream — policy lookup | Resolved from UI state |
| C13 Workflow Engine | **AsyncStream inbound** from `bus.subscribe()` | Stream from bus; may also post back to bus |
| C14 Replay Buffer | **Not a stream** — `eventsSince(seq:)` returns array | Catch-up is a bounded query, not ongoing consumption |
| C15 Process Channel | **AsyncStream for stdout**; direct call for stdin | Process output is ongoing and bursty → stream. Input is direct `await process.write()`. |
| C16 Filesystem Context | **Not a stream** — derived `@Observable` projection | Updates when C6 events arrive via bus subscription; UI binds via @Observable |

### Per-Actor Connection Inventory

#### EventBus actor

| Direction | Connection | Pattern | Why |
|-----------|-----------|---------|-----|
| **In** | Any producer → `bus.post(envelope)` | Direct `await` call | Producer knows the bus. One call, one destination. |
| **Out** | `bus.subscribe()` → any consumer | **AsyncStream** | Multiple independent consumers, pull at own pace. This IS the bus's value proposition. |

#### TerminalRuntime (@MainActor)

| Direction | Connection | Pattern | Why |
|-----------|-----------|---------|-----|
| **In** | GhosttyAdapter → `runtime.handleGhosttyEvent()` | Direct call | Adapter knows exact target (surfaceId → registry lookup). One producer, one consumer. |
| **In** | Coordinator → `runtime.handleCommand(envelope)` | Direct call | Request-response. Returns `ActionResult`. |
| **Out** | `@Observable` mutation | Direct property write | SwiftUI binding, synchronous, zero overhead. |
| **Out** | `await bus.post(envelope)` | Direct call to bus | Runtime knows the bus. No stream between runtime and bus. |
| **Out** | `subscribe()` → per-runtime stream | **AsyncStream** | For replay catch-up and per-pane direct subscription. Secondary to bus path. |

Same pattern applies to BridgeRuntime, WebviewRuntime, SwiftPaneRuntime — transport differs but connection patterns are identical.

#### FilesystemActor (app-wide singleton, LUNA-349)

| Direction | Connection | Pattern | Why |
|-----------|-----------|---------|-----|
| **In** | FSEvents callback → actor | **AsyncStream** | FSEvents fires rapid bursts. Stream buffers ingress and isolates callback thread from actor processing. |
| **In** | `register(worktree:path:)` / `unregister(worktree:)` | Direct call | Coordinator manages worktree registration lifecycle. |
| **Internal** | Route → filter → debounce/max-latency → chunk | Direct actor state transitions | Keeps ingress, batching, and suppression metadata in one place. |
| **Out** | `await bus.post(.filesystem(.filesChanged))` | Direct call to bus | Fact emission to shared stream. |

#### GitWorkingDirectoryProjector (app-wide projector, LUNA-349)

| Direction | Connection | Pattern | Why |
|-----------|-----------|---------|-----|
| **In** | `for await envelope in await bus.subscribe()` | **AsyncStream** | Consumes `.worktreeRegistered`/`.worktreeUnregistered`/`.filesChanged` facts. |
| **Internal** | per-worktree coalescing + git compute | Direct call (`await`) to provider | Last-writer-wins by `worktreeId`; compute uses off-actor helper in provider. |
| **Out** | `await bus.post(.filesystem(.gitSnapshotChanged))` | Direct call to bus | Publishes materialized local git state facts. |

#### ForgeActor (app-wide singleton, future)

| Direction | Connection | Pattern | Why |
|-----------|-----------|---------|-----|
| **In** | Timer-driven polling (`clock.timer(interval:)`) | No stream needed | Actor owns its own polling loop (~30-60s). No external producer. |
| **In** | `register(repo:remote:)` / `unregister(repo:)` | Direct call | Coordinator manages repo registration. |
| **In** | On-demand refresh (after `git push`) | Direct call from coordinator | `await forgeActor.refresh(repo:)` — known target, request-response. |
| **Internal** | `@concurrent nonisolated` via ProcessExecutor or URLSession | Direct call (await) | Transport-agnostic I/O. One request, one response. |
| **Out** | `await bus.post(envelope)` | Direct call to bus | Same pattern as every other producer. |

#### ContainerActor (per-terminal, deferred)

| Direction | Connection | Pattern | Why |
|-----------|-----------|---------|-----|
| **In** | Timer-driven polling (~5-10s) | No stream needed | Actor owns its polling loop. |
| **Out** | `await bus.post(envelope)` | Direct call to bus | Same pattern. |

#### Plugin Actor (per-plugin, deferred)

Each plugin is its own actor. It receives a `PluginContext` struct at registration that mediates bus access.

| Direction | Connection | Pattern | Why |
|-----------|-----------|---------|-----|
| **In** | `for await envelope in context.events` | **AsyncStream** (pre-filtered from bus) | Sink role — `PluginContext` subscribes to bus, filters to manifest-declared event types. |
| **Out** | `context.post(event)` → validates → `bus.post(envelope)` | Direct call (mediated by context) | Source role — context validates event type against manifest, checks rate limit, stamps `.system(.plugin(id))` source. |

#### GhosttyAdapter (@MainActor)

| Direction | Connection | Pattern | Why |
|-----------|-----------|---------|-----|
| **In** | C callback → `@Sendable` trampoline → MainActor | Direct hop | Individual function calls, not an iterable sequence. |
| **Out** | `runtime.handleGhosttyEvent()` | Direct call | Route by surfaceId to known target. |

No AsyncStream — wrapping individual C callbacks in a stream would yield one, consume one — pointless indirection.

#### NotificationReducer (@MainActor)

| Direction | Connection | Pattern | Why |
|-----------|-----------|---------|-----|
| **In** | `for await envelope in await bus.subscribe()` | **AsyncStream** (from bus) | Decoupled consumption. Reducer pulls at its own pace. |
| **Out** | `@Observable` mutations to notification state | Direct property write | SwiftUI binding. |

Pure sink. Consumes from bus stream, writes to @Observable.

#### PaneCoordinator (@MainActor)

| Direction | Connection | Pattern | Why |
|-----------|-----------|---------|-----|
| **In** | `for await envelope in await bus.subscribe()` | **AsyncStream** (from bus) | Decoupled consumption from bus. |
| **Out** | `runtime.handleCommand(envelope)` | Direct call | Command dispatch is request-response. |
| **Out** | Store mutations | Direct call | `workspace.closeTab()`, `surfaces.moveSurfacesToUndo()` — known targets. |

#### Sink+Source actors (CheckpointActor pattern, future)

A component that subscribes from the bus, accumulates state, and produces events when ready:

| Direction | Connection | Pattern | Why |
|-----------|-----------|---------|-----|
| **In** | `for await envelope in await bus.subscribe()` | **AsyncStream** (from bus) | Sink role — consumes coordination events. |
| **Out (multiple consumers)** | `await bus.post(checkpointReadyEnvelope)` | Direct call to bus | Coordination event — workflow engine, reducer, UI all might want it. |
| **Out (single known consumer)** | `@Observable` state | Direct property write | If only the checkpoint panel UI cares. |

Same multiplexing rule as runtimes: `@Observable` for UI binding, `bus.post()` for coordination consumers.

### Pattern Diagrams

#### AsyncStream patterns

```
BUS OUTBOUND (fan-out to independent consumers):

  Any producer
       │
       │  await bus.post(envelope)          ← direct call IN
       ▼
  ┌─────────────────────────────────────┐
  │         actor EventBus              │
  │                                     │
  │  subscribers: [UUID: Continuation]  │
  │                                     │
  │  post() { for c in subs { c.yield(envelope) } }
  └───────┬──────────┬──────────┬───────┘
          │          │          │
     AsyncStream  AsyncStream  AsyncStream   ← stream OUT (one per subscriber)
          │          │          │
          ▼          ▼          ▼
     Reducer    Coordinator   Workflow
     for await  for await     for await
     envelope   envelope      envelope


BURSTY OS SOURCE (FSEvents → FilesystemActor → GitWorkingDirectoryProjector):

  macOS FSEvents (arbitrary thread, 50 paths in 2s burst)
       │
       │  continuation.yield(paths)
       ▼
  ╔═══════════════════════════════════════════════╗
  ║  AsyncStream<[String]>                        ║
  ║  (buffered pipe between OS callback and actor)║
  ╚═══════════════╤═══════════════════════════════╝
                   │
                   │  for await paths in stream
                   ▼
  ┌─────────────────────────────────────┐
  │      actor FilesystemActor          │
  │                                     │
  │  route → filter → debounce/max-lat │
  │  → chunk filesChanged facts         │
  │                                     │
  │  await bus.post(.filesChanged)      │──── direct call to bus
  └─────────────────────────────────────┘
                   │
                   ▼
  ┌─────────────────────────────────────┐
  │ actor GitWorkingDirectoryProjector  │
  │                                     │
  │ consume filesChanged facts          │
  │ coalesce by worktreeId              │
  │ await git provider status()         │
  │                                     │
  │ await bus.post(.gitSnapshotChanged) │──── direct call to bus
  └─────────────────────────────────────┘


PROCESS STDOUT (C15, bidirectional — stream out, direct in):

  Agent process (PTY)
       │
       │  stdout bytes arrive continuously
       ▼
  ╔══════════════════════════════╗
  ║  AsyncStream<ProcessOutput>  ║
  ║  (ongoing, bursty)           ║
  ╚═══════════════╤══════════════╝
                   │  for await chunk in stdout
                   ▼
  ┌─────────────────────────────────┐
  │   TerminalRuntime (@MainActor)  │
  │                                 │
  │   parse → classify → emit       │
  └─────────────────────────────────┘
                   │
                   │  await bus.post(envelope)
                   ▼
              EventBus


  OPPOSITE DIRECTION (stdin — direct call, NOT stream):

  Coordinator                    Agent process
       │                              ▲
       │  await runtime               │  runtime calls
       │    .handleCommand(           │  ghostty_surface_write()
       │      .sendInput("yes\n"))    │
       ▼                              │
  TerminalRuntime ────────────────────┘
       direct call, request-response
```

#### Direct call patterns

```
ADAPTER → RUNTIME (C7: Ghostty FFI):

  C callback (arbitrary thread)
       │
       │  @Sendable static trampoline
       │  MainActor.assumeIsolated { }
       ▼
  GhosttyAdapter.translate(action)       ~100ns
       │
       │  RuntimeRegistry[surfaceId]     lookup, not stream
       │  runtime.handleGhosttyEvent()   direct call
       ▼
  TerminalRuntime (@MainActor)


COMMAND DISPATCH (C10: coordinator → runtime):

  User taps "Approve"
       │
       ▼
  PaneCoordinator (@MainActor)
       │
       │  let runtime = registry[paneId]       ← lookup
       │  let result = await runtime            ← direct call
       │      .handleCommand(envelope)
       ▼
  ActionResult
    .success(commandId)
    .failure(.runtimeNotReady)


COORDINATOR → STORES (cross-store sequencing):

  PaneCoordinator.closeTab(tabId)
       │
       ├──► workspace.removeTab(tabId)           direct call
       │         returns TabSnapshot
       │
       ├──► surfaces.moveSurfacesToUndo(ids)     direct call
       │
       └──► runtime.markSessionsPendingUndo(ids) direct call


ANY PRODUCER → BUS (inbound post):

  TerminalRuntime ──► await bus.post(envelope)   direct call
  FilesystemActor ──► await bus.post(envelope)   direct call
  ForgeActor      ──► await bus.post(envelope)   direct call
  ContainerActor  ──► await bus.post(envelope)   direct call
  Plugin actor    ──► context.post() → bus.post() mediated via PluginContext
  CheckpointActor ──► await bus.post(envelope)   direct call
```

#### @Observable patterns

```
RUNTIME → SWIFTUI VIEW (zero-overhead binding):

  TerminalRuntime (@MainActor, @Observable)
  ┌──────────────────────────────────────┐
  │  private(set) var title: String      │◄─── GhosttyAdapter writes
  │  private(set) var cwd: URL?          │     directly on MainActor
  │  private(set) var searchState: ...   │
  │  private(set) var scrollbarState: .. │
  └────────────┬─────────────────────────┘
               │
               │  SwiftUI @Observable tracking
               │  (compiler-generated, zero overhead)
               ▼
  ┌──────────────────────────────────────┐
  │  AgentStudioTerminalView             │
  │                                      │
  │  Text(runtime.title)       ← binds   │
  │  ScrollBar(runtime         ← binds   │
  │    .scrollbarState)                   │
  └──────────────────────────────────────┘


MULTIPLEXING (Categories 2 & 5 — @Observable AND bus):

  TerminalRuntime receives titleChanged("new title")
       │
       ├──► SYNC: self.title = "new title"          @Observable
       │         (SwiftUI re-renders immediately)
       │
       └──► ASYNC: await bus.post(envelope(          EventBus
                     .terminal(.titleChanged(...))
                   ))
                   (tab bar, notifications, dynamic views)

  The @Observable write happens FIRST, synchronously.
  The bus post happens AFTER, asynchronously.
  UI is never stale relative to coordination consumers.


PROJECTION (C16: filesystem context → view):

  EventBus
       │
       │  for await envelope in bus.subscribe()
       │  filter: source == .system(.builtin(.filesystemWatcher))
       │  filter: worktreeId matches pane's worktree
       ▼
  PaneFilesystemContext (@MainActor, @Observable)
  ┌──────────────────────────────────────┐
  │  private(set) var changedFiles: ...  │◄─── updated from C6 events
  │  private(set) var gitWorkingTree: ...│
  │  private(set) var lastDiff: ...      │
  └────────────┬─────────────────────────┘
               │  @Observable binding
               ▼
  DiffPaneView / SidebarFileTree / etc.
```

#### Never-stream patterns

```
ONE-SHOT SIGNAL (C5a: attach readiness gate):

  DeferredStartupReadiness
       │
       │  await readiness.wait()    ← suspends until ready
       │                            ← resumes once (not ongoing)
       ▼
  proceed with attach

  Implementation: AsyncStream.Continuation.yield() + finish(),
  or Task that resolves once. NOT an ongoing stream.


CATCH-UP REPLAY (C14: eventsSince):

  Late-joining consumer (e.g., new workflow subscriber)
       │
       │  let missed = await runtime.eventsSince(seq: lastSeen)
       │
       ▼
  EventReplayBuffer.ReplayResult
    .complete([envelope, envelope, envelope])    ← array, not stream
    .partial([envelope, ...], gapStart: seq)

  ┌──────────────────────────────────────────────┐
  │  CATCH-UP THEN LIVE:                         │
  │                                              │
  │  let missed = await runtime.eventsSince(42)  │  ← array
  │  process(missed)                             │
  │                                              │
  │  for await envelope in await bus.subscribe() │  ← stream
  │      where envelope.seq > missed.lastSeq     │
  │      process(envelope)                       │
  │  }                                           │
  └──────────────────────────────────────────────┘


LOOKUP (C11: RuntimeRegistry):

  registry[paneId]  →  TerminalRuntime?

  Dictionary lookup. Not a stream. Not async.


CONFIG READ (C9: ExecutionBackend):

  pane.metadata.executionBackend  →  .bareMetal | .docker | .gondolin

  Immutable at creation time. Read once, never changes.
```

### Bus Enrichment Rule

The bus is a dumb pipe. It never transforms, enriches, or filters payloads. Enrichment happens at the boundary before posting:

```
BOUNDARY does enrichment:
  FSEvents → FilesystemActor → enrich(worktree, git, diff) → bus.post(enriched)

BUS does fan-out only:
  bus.post(enriched) → subscriber1, subscriber2, subscriber3
```

If a sink+source needs to transform events for a different audience (e.g., CheckpointActor), it subscribes from the bus, transforms, and posts back. The bus itself never knows what the payload means.

## Threading Model

Concrete list of what runs where, with Swift 6.2 keywords:

| Isolation | Scope | What Runs Here | Swift 6.2 Keyword |
|-----------|-------|----------------|-------------------|
| `@MainActor` | App-wide | Runtimes, stores, coordinator, views, reducer, ViewRegistry | `@MainActor` on class/func |
| `actor EventBus` | App-wide singleton | Subscriber management, fan-out | `actor` (cooperative pool) |
| `actor FilesystemActor` | App-wide singleton (keyed by worktree) | FSEvents, debounce, git status, diff (future) | `actor` (cooperative pool) |
| `actor ForgeActor` | App-wide singleton (keyed by repo) | Forge PR status, checks, reviews (future) | `actor` (cooperative pool) |
| `actor ContainerActor` | Per-terminal (deferred) | Container health, devcontainer status | `actor` (cooperative pool) |
| Plugin actors | Per-plugin (deferred) | Plugin domain work; bus access mediated via `PluginContext` struct | `actor` (cooperative pool) |
| Cooperative pool (anonymous) | Per-call | Heavy per-pane one-shot work (search, parse, extract, hash) | `@concurrent nonisolated` on static func |

**Constraint:** No core actor calls another core actor directly for **event-plane** data. All event-plane communication flows through the EventBus — domain actors post events to the bus, `@MainActor` consumers subscribe from the bus. **Command-plane** request-response calls (e.g., coordinator calling `await forgeActor.refresh(repo:)`) are direct calls from the coordinator to the target actor. These are control-plane commands, not events, and don't flow through the bus. This separation prevents hidden coupling while keeping command dispatch simple and auditable.

### Swift 6.2 concurrency rules (SE-0461)

1. **`@concurrent nonisolated`** for explicit pool execution. `@concurrent` is only valid on nonisolated declarations (SE-0461). In `@MainActor` types, helpers must opt out of actor isolation (`nonisolated`) before using `@concurrent`.
2. **`nonisolated async` means `nonisolated(nonsending)` in Swift 6.2** (SE-0461). It inherits caller isolation. Do NOT use this expecting pool execution — it will run on MainActor if called from MainActor.
3. **Prefer `@concurrent` over `Task.detached`** (project policy) — `Task.detached` strips priority and task-locals; `@concurrent` preserves structured concurrency. Exception: `Task.detached` remains appropriate when you need to escape structured concurrency scope or intentionally strip task-locals.
4. **Avoid `MainActor.run` in this architecture's common paths** — the compiler handles actor hops when returning from `@concurrent nonisolated` to `@MainActor`. `MainActor.run` is still valid when genuinely needed (hopping TO MainActor from a non-main context), but our typical pattern doesn't require it.
5. **All cross-boundary data is `Sendable`.** `PaneEventEnvelope`, all event types, all command types — `Sendable` is required for data that crosses actor boundaries.
6. **C callbacks use `@Sendable` trampolines** + `MainActor.assumeIsolated` for synchronous hops or `Task { @MainActor in }` for async work. No `DispatchQueue.main.async`.

### Swift 6.2 Gotchas (quick reference)

Common traps in this codebase. Each is documented in detail above; this is the scannable checklist.

| Gotcha | Wrong | Right | Why |
|--------|-------|-------|-----|
| `nonisolated async` ≠ pool | `nonisolated func doWork() async` | `@concurrent nonisolated func doWork() async` | In 6.2, `nonisolated async` inherits caller isolation (runs on MainActor if called from MainActor) |
| `@concurrent` requires nonisolated context | `@concurrent func doWork()` while relying on actor-isolated state | `@concurrent nonisolated static func doWork()` | Use nonisolated helpers for explicit pool execution and clearer isolation boundaries |
| Avoid accidental actor capture | `@concurrent nonisolated func search()` that touches `self` members | `@concurrent nonisolated static func search(_ snapshot: T)` | `static` avoids `self` capture and makes isolation intent reviewable |
| `Task { }` inherits actor | `Task { heavyWork() }` inside `@MainActor` | `await Self.heavyWork(data)` where `heavyWork` is `@concurrent nonisolated static` | Unstructured `Task` inside `@MainActor` runs on MainActor |
| `Task.detached` strips context | `Task.detached { await doWork() }` | `@concurrent nonisolated static func doWork()` | Detached strips priority + task-locals; `@concurrent` preserves them |

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
         @concurrent nonisolated funcs (pool execution)
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
| FilesystemActor work | 1,000-100,000μs | Strongly justified (app-wide, keyed by worktree) |
| ForgeActor work | 100,000-2,000,000μs (100ms-2s) | Strongly justified (app-wide, keyed by repo) |
| ContainerActor work | 100,000μs+ | Strongly justified (per-terminal, deferred) |
| PluginContext validation | ~1-10μs (type check + rate limit) | Trivial vs plugin work; struct method, no actor hop |
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
| Bus fan-out scaling (50+ plugins) | Future risk | `post()` iterates N continuations on bus actor's serial executor; N > 50 → fan-out > ~1ms | Shard into topic-based buses (see below) |

**Bus scaling escape hatch:** The current single bus is sized for ~3-10 subscribers (~100ns per continuation × 10 = ~1μs per `post()`). If the plugin system scales to 50+ subscribers, `post()` iterates 50+ continuations on the bus actor's serial executor, potentially exceeding ~1ms per event. The escape hatch is **topic-based sharding**: split into `PaneEventBus`, `SystemEventBus`, `PluginEventBus` — each with its own actor. Producers post to the relevant bus; consumers that need multiple topics subscribe to multiple buses and merge client-side via `swift-async-algorithms`. This keeps per-bus fan-out bounded. Profile before sharding — the threshold is `post()` cost > ~1ms sustained.

**Key insight:** Ghostty renders on its own Metal pipeline. Terminal rendering cannot jank from Swift event processing — they are completely independent. Swift jank only happens if `@MainActor` blocks the AppKit event loop for >16ms. The EventBus adds ~4-18μs per event, well within budget.

**MainActor round-trip overhead:** When a `@MainActor` runtime posts to the pool-based bus and a `@MainActor` consumer reads from it, the event takes a round-trip: main → pool (hop to bus actor) → main (hop back to consumer). This is ~4-12μs of pure overhead for events that originate and terminate on MainActor. At current event volume (~1-10 coordination events per user action, ~10-100 events/sec sustained), this is negligible. The threshold where a `@MainActor` bus becomes worth evaluating: if 80%+ of producers AND consumers are `@MainActor`, and event throughput exceeds ~1000 events/sec sustained. Given that boundary actors (FilesystemActor, ForgeActor) post from the cooperative pool (~30-40% of events at scale), the pool-based bus is the correct default. Revisit if profiling shows bus hops consuming >1% of frame budget.

## Adoption Plan

Incremental, each step independently shippable:

1. **Multi-subscriber fan-out on existing runtimes.** Replace single `AsyncStream.Continuation` with array of continuations. Runtime's `subscribe()` returns independent stream per caller. This is a prerequisite for the bus — it proves fan-out semantics work at the runtime level.

2. **Introduce `actor EventBus<PaneEventEnvelope>`.** Central merge point. Runtimes post to bus after `@Observable` mutation. Reducer and coordinator subscribe from bus instead of per-runtime streams.

3. **Migrate consumers to bus subscriptions.** `NotificationReducer`, `PaneCoordinator`, and any future consumers subscribe to the bus. Per-runtime subscriptions become an implementation detail (runtime → bus posting).

4. **Add `actor FilesystemActor`** when FSEvents watcher ships (LUNA-349). First real boundary actor. Posts enriched envelopes with `source = .system(.builtin(.filesystemWatcher))`.

5. **Add `actor ForgeActor`** when forge integration ships. App-wide singleton, keyed by repo. Uses ProcessExecutor (`gh` CLI) or URLSession (direct API) as transport internally. Posts enriched envelopes with `source = .system(.service(.gitForge(provider:)))`.

6. **Add `actor ContainerActor`** (per-terminal) when container/agent execution ships. Polls Docker API / devcontainer status.

7. **Migrate heavy per-pane work to `@concurrent`** as it appears. Scrollback search, artifact extraction, log parsing — each gets a `@concurrent nonisolated static func` instead of inline MainActor processing. The D1 processing budget guidance in pane_runtime_architecture.md reflects this pattern.

8. **Add plugin integration** when plugin system ships. Each plugin is its own actor with injected `PluginContext` for mediated bus access. See [Plugin Integration Model](#plugin-integration-model-deferred).

## Plugin Integration Model (Deferred)

Plugin sources, sinks, and projections participate in the EventBus through a **mediated actor boundary**. The plugin never touches the bus directly.

### Mental Model

A plugin is ONE thing — a single Swift package. It IS its own actor. Roles (source, sink, projection) emerge from behavior, declared in a manifest. A developer doesn't think "I'm writing a source" — they think "I'm writing a Linear integration." If it posts events, it's a source. If it handles events, it's a sink. If it does both and projects derived state, it's a projection.

### Architecture

```
Plugin actor                          PluginContext (struct)              EventBus
┌────────────────────┐     calls     ┌─────────────────────────┐        ┌──────────┐
│ actor LinearPlugin │──────────────►│ validate type + rate    │───────►│ bus.post()│
│                    │  context.post │ stamp .system(.plugin(id))│        │          │
│ polls, processes,  │               └─────────────────────────┘        └──────────┘
│ posts when ready   │◄──────────────── context.events (pre-filtered AsyncStream)
└────────────────────┘
```

The plugin actor is the isolation boundary. `PluginContext` is a struct injected at registration — it mediates bus access with validation. No wrapper actor, no host actor.

### Isolation: Actor Boundary

Each plugin is its own actor, running in-process on the cooperative pool. The actor boundary provides concurrency safety. If plugin code throws, the plugin runtime (which manages registration) catches the error, logs a diagnostic, and disables the plugin. The app continues.

### Capability Model

The manifest declares what the plugin can do. `PluginContext` is configured at registration based on manifest + user approval.

```swift
let manifest = PluginManifest(
    name: "Linear",
    capabilities: [
        .produces([.integration(.issueStatusChanged)]),
        .consumes([.lifecycle(.paneClosed), .terminal(.commandFinished)]),
    ],
    resources: .network
)
```

- A source-only plugin's context has `post()` enabled but no event stream
- A sink-only plugin's context has an event stream but `post()` disabled
- A projection gets both, validated in both directions
- `PluginContext` stamps `source: .system(.plugin(pluginId))` on outbound envelopes — unforgeable by the plugin

### PluginContext: The Narrow Interface

The plugin sees `PluginContext`, not the bus. This struct is the capability boundary.

```swift
struct PluginContext: Sendable {
    let post: @Sendable (PluginEvent) async -> Void    // source — validates, stamps, posts to bus
    let events: AsyncStream<PaneEventEnvelope>          // sink — pre-filtered to manifest
    let clock: any Clock<Duration>                      // testable time
    // No direct bus, no stores, no coordinator, no runtimes
}
```

### Safety Invariants

1. **No direct bus access** — plugin never holds a reference to `EventBus`
2. **Declared capabilities are the ceiling** — can't escalate at runtime
3. **Source identity is unforgeable** — `.system(.plugin(id))` stamped by `PluginContext`, not by plugin code
4. **Rate limits enforced by context** — excess posts dropped with diagnostic. Mechanism: `PluginContext.post()` uses an **atomic token bucket** (`Atomics.ManagedAtomic<Int>` from SE-0410, not deprecated `OSAtomicIncrement`) embedded in the `PluginContext` struct. The bucket refills at a configured rate (e.g., 100 events/sec per plugin) and the `post()` closure checks tokens before forwarding to `bus.post()`. This keeps rate-limiting out of the bus actor's hot path — no per-post overhead for non-plugin producers. Dropped events increment a diagnostic counter exposed via the plugin health API. Implementation note: `ManagedAtomic` is a reference-counted heap allocation, so `PluginContext` remains a simple `Sendable` struct without non-copyable constraints — the atomic is shared by reference, not by value
5. **Backpressure is per-plugin** — if plugin's consumer falls behind, only its stream buffer fills; other bus subscribers unaffected
6. **Watchdog is mandatory** — no heartbeat within N seconds → cancel plugin task + restart with backoff

### What's Deferred

- Exact `PluginManifest` schema
- Plugin discovery and loading mechanism
- User approval UI for capabilities
- Plugin versioning and compatibility
- Forge adapter protocol (how ForgeActor dispatches to plugin-provided forge implementations)

## Implementation Migration Inventory

Current codebase patterns that need migration to align with this design. Audited from `Sources/AgentStudio/`.

### What's already clean

- **No `Task.detached`** in production code
- **No `MainActor.run`** in production code
- **No `DispatchQueue.main.async`** — only `DispatchQueue.global()` in ProcessExecutor (correct)
- **No Combine** (`import Combine`, `AnyCancellable`, `@Published`, `ObservableObject`) — already on `@Observable`
- **FileManager I/O** already isolated in WorkspacePersistor (not `@MainActor`)
- **C callback patterns** correctly use `@Sendable` trampolines + `Task { @MainActor in }`

### Phase 1: Core — NotificationCenter → typed EventBus

**~38 NotificationCenter calls** across the codebase form the current command/event dispatch system. These are the primary migration target.

| File | Pattern | Events | Severity |
|------|---------|--------|----------|
| `App/Panes/PaneTabViewController.swift` | 8 `for await` consumers, 3 `.post()` producers | selectTabById, extractPane, repairSurface, processTerminated, undoClose, refocusTerminal, webviewOpen, addRepo, filterSidebar, signIn | HIGH |
| `App/MainSplitViewController.swift` | 6 `for await` consumers, 1 `addObserver` | openWorktree, tabClose, selectTab, sidebarToggle, newTerminal, sidebarFilter, willTerminate | HIGH |
| `Features/CommandBar/CommandBarDataSource.swift` | 5 `.post()` producers | selectTabById, openWorktreeRequested | HIGH |
| `Features/Terminal/Ghostty/GhosttySurfaceView.swift` | 2 `.post()` producers | didUpdateWorkingDirectory, didUpdateRendererHealth | MEDIUM |
| `Features/Terminal/Ghostty/Ghostty.swift` | 2 `for await` consumers, 2 `.post()` | ghosttyNewWindow, ghosttyCloseSurface, didBecomeActive, didResignActive | MEDIUM |
| `Features/Terminal/Views/AgentStudioTerminalView.swift` | 2 `addObserver`, 2 `.post()` | surfaceClose, repairSurfaceRequested, terminalProcessTerminated | MEDIUM |
| `App/MainWindowController.swift` | 2 `.post()` | filterSidebarRequested, addRepoRequested | LOW |
| `App/AppDelegate.swift` | 1 `addObserver` | signIn OAuth callback | LOW |
| `Features/Terminal/Ghostty/SurfaceManager.swift` | 1 `addObserver`, 1 `removeObserver` | Health notifications | LOW |

**Target pattern:**
```swift
// Before: untyped, stringly-keyed
NotificationCenter.default.post(name: .selectTabById, userInfo: ["tabId": tabId])

// After: typed, compiler-checked
await bus.post(PaneEventEnvelope(source: .system(.builtin(.coordinator)), event: .lifecycle(.tabSwitched(tabId))))
```

### Phase 1: Core — JSON encoding off MainActor

**RPCRouter** (`Features/Bridge/Transport/RPCRouter.swift`) does JSON decode/encode on MainActor — performance-sensitive path for bridge RPC dispatch.

| Method | Line | Work | Target |
|--------|------|------|--------|
| `parseRequestEnvelope(from:)` | ~158 | `JSONDecoder().decode()` from raw string | `nonisolated` sync method or `@concurrent nonisolated` if payload is large |
| `decodeResultData(from:)` | ~391 | `JSONDecoder().decode()` | Same |
| `decodeParamsData(from:)` | ~431 | `JSONEncoder().encode()` | Same |

These methods don't need MainActor isolation — they take immutable input and return parsed results. Making them `nonisolated` is the simplest fix; `@concurrent nonisolated` if profiling shows >1ms per call.

### Phase 2: UI — Combine bridge patterns

3 `.onReceive(NotificationCenter.default.publisher(...))` in `MainSplitViewController.swift` (lines 395-404). These bridge NotificationCenter to SwiftUI. They can migrate to EventBus subscriptions or direct store method calls when Phase 1 completes.

### Phase 3: Polish — URLHistoryService JSON I/O

4 `JSONEncoder`/`JSONDecoder` calls in `URLHistoryService.swift` (lines 167-192). Low frequency, not on critical path. Can offload to `nonisolated` or `@concurrent nonisolated` for consistency.

### Not requiring migration

| Pattern | Location | Why it's fine |
|---------|----------|---------------|
| `DispatchQueue.global()` | ProcessExecutor.swift | Correct: offloads blocking pipe I/O |
| `NotificationCenter.notifications(named: .didBecomeActive)` | Ghostty.swift | System notification — stays as-is |
| `FileManager` operations | WorkspacePersistor | Already not `@MainActor` |
| `@concurrent` on plain structs | Slice.swift, EntitySlice.swift | No actor isolation to opt out of — `nonisolated` implicit |

## Verification Checklist

1. No MainActor frame stalls from event processing (benchmark: 100 events/frame stays under 2ms)
2. Every envelope reaches all subscribers (fan-out correctness: post once, N streams receive)
3. Events and commands flow in opposite directions (never share channel)
4. All cross-boundary payloads are `Sendable` (compiler-enforced)
5. `@concurrent nonisolated` used for cooperative pool execution — both keywords required inside `@MainActor` types (SE-0461, SE-0316)
6. Prefer `@concurrent` over `Task.detached` in new code (exception: escaping structured concurrency scope)
7. Avoid `MainActor.run` in common architecture paths (exception: hopping TO MainActor from non-main isolated context)
8. Coordinator remains sequencing-only (no domain logic in fan-out paths)
9. `@Observable` mutations happen synchronously on MainActor before bus posting (UI never lags behind coordination)
10. No core actor calls another core actor for event-plane data — command-plane request-response calls (e.g., `forgeActor.refresh(repo:)`) are direct
11. Domain actors own their transport internally — shared infrastructure (URLSession, ProcessExecutor) is injected, not wrapped in actors
12. Plugin events carry unforgeable `.system(.plugin(id))` source stamped by `PluginContext`, not by plugin code
