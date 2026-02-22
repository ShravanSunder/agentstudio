# Pane Runtime Architecture

## Problem

Agent Studio is a **workspace for agent-assisted development** — an agent orchestration platform where terminal agents (Claude, Codex, aider) are the primary drivers and non-terminal panes (diff viewers, PR reviewers, code viewers) exist for human observation and control. This is the **inverse of Cursor**: agents drive the workspace, users observe and orchestrate.

The current Ghostty integration handles 12 of 40+ C API actions, uses `DispatchQueue.main.async` and `NotificationCenter` for event dispatch, and has no typed event contract. Non-terminal pane types (webview, diff viewer) have no runtime abstraction. There is no bidirectional communication system, no event batching, and no temporal coordination for multi-agent workflows.

This document defines the pane runtime communication architecture: how panes of all types produce events, receive commands, and coordinate through the workspace.

### Jobs This Architecture Solves

> JTBD 1-8 and Pain Points P1-P8 are defined in [JTBD & Requirements](jtbd_and_requirements.md). This table maps the subset addressed by the pane runtime architecture.

| JTBD | How This Architecture Addresses It |
|------|-----------------------------------|
| **JTBD 1 — Context tracking** | Every event carries pane identity (paneId, worktreeId, agentType, CWD). Metadata changes from terminal CWD, webview URL, or diff file paths all flow through typed events with source identity. |
| **JTBD 2 — Ephemeral pane management** | Lifecycle state machine (`created → ready → draining → terminated`) with explicit shutdown and unfinished-command reporting. No orphaned runtimes, no ghost events. |
| **JTBD 3 — Agent-agnostic** | `PaneRuntime` protocol is pane-type-agnostic. Terminal, webview, diff, and future editors all conform to the same contract. Agents are processes in terminals; the runtime contract doesn't care which agent. |
| **JTBD 4 — Cross-project organization** | Event stream carries worktreeId and repo context on every event. Dynamic views can subscribe and filter by any metadata dimension. |
| **JTBD 5 — Dynamic composition** | Filesystem watcher + artifact events feed dynamic views with live grouping data. New changesets trigger view recomputation. |
| **JTBD 6 — Stay in flow** | Notifications route to exact pane via paneId. Diff artifacts flow from terminal → diff pane → approval without leaving the workspace. Priority system ensures active pane events are never delayed by background noise. |

---

## Design Decisions

Each decision links to the user problem it solves and the alternatives considered.

### D1: Per-pane-type runtimes, not actor-per-pane

**User problem:** Users run 5-10 agents simultaneously. The system must handle concurrent events without one pane poisoning others (JTBD 4, P8).

**Decision:** One `@MainActor` runtime CLASS per pane type. One runtime INSTANCE per pane. `TerminalRuntime` is the class; each terminal pane gets its own instance. All instances share `@MainActor` (same thread, no async boundaries between them). Protocol is `async` from day one to preserve the actor upgrade path.

**Instance model:**
```
CLASSES (one per pane type):        INSTANCES (one per pane):
  TerminalRuntime                     TerminalRuntime[pane-A]
  BrowserRuntime                      TerminalRuntime[pane-B]
  DiffRuntime                         BrowserRuntime[pane-C]
  EditorRuntime                       DiffRuntime[pane-D]
```

Adapters are shared — one `GhosttyAdapter` singleton handles all C callbacks and routes by surfaceId to the correct `TerminalRuntime` instance. One `WebKitAdapter` routes by webViewId to the correct `BrowserRuntime` instance.

```
ADAPTERS (shared, one per backend technology):
  GhosttyAdapter ──► routes by surfaceId ──► TerminalRuntime[pane-X]
  WebKitAdapter  ──► routes by webViewId ──► BrowserRuntime[pane-Y]

RUNTIMES (per-pane, registered in RuntimeRegistry):
  RuntimeRegistry[pane-A] → TerminalRuntime instance
  RuntimeRegistry[pane-B] → TerminalRuntime instance
  RuntimeRegistry[pane-C] → BrowserRuntime instance
```

**Why not actor-per-pane:** Swift actors impose async boundaries on every property access. For a macOS UI app where all state feeds `@Observable` views on the main thread, this adds overhead without matching benefit. `@MainActor` already provides thread safety.

**Actor migration path (honest cost):** The protocol is `async` from day one, which minimizes caller-side changes if a runtime is later moved to its own actor. However, `@MainActor` on the protocol itself and sync property access (`paneId`, `metadata`, `lifecycle`, `capabilities`, `snapshot()`) lock current conformers to main-actor isolation. Migrating to actor-per-pane would require: (1) removing `@MainActor` from the protocol, (2) making sync properties `async` or using `nonisolated`, (3) updating all callsites. This is a real migration cost — the protocol reduces it but does not eliminate it. Profile before deciding (>1000 events/sec sustained).

**MainActor processing budget:** Since `TerminalRuntime` is `@MainActor`, heavy processing of Ghostty output (regex searching, artifact extraction, log parsing) MUST happen on a detached background `Task` before yielding the result to the MainActor runtime. The runtime's event handler should be fast — classify the event, update `@Observable` state, emit the envelope. Anything that takes >1ms (string matching across scrollback, diff computation, file content hashing) must be offloaded to avoid UI stutters on the main thread.

**Why not single coordinator handling all events:** Becomes a god object as pane types grow. Per-type runtimes have clear ownership, are testable in isolation, and scale with new pane types.

**Reviewed by:** 4 independent opinions (Claude, Codex ×2, Gemini+Codex counsel). All converged on this choice.

### D2: Single typed event stream, not three separate planes

**User problem:** When agent A finishes a task and a diff appears, the user needs to know which agent produced it, what repo it's in, and the diff content — all consistently, with no missing context (JTBD 6, P6).

**Decision:** One `PaneRuntimeEvent` enum carried on one `AsyncStream` per runtime, with per-source sequence numbers (`seq` is monotonic within a single source — pane, worktree watcher, or system). Cross-source ordering is best-effort via `timestamp`. Events cover lifecycle, terminal, browser, filesystem, artifact, and error cases.

**Why not three planes (control/state/data):** Two independent reviewers identified an ordering hazard: if control events ("diff generated") and state events ("diff pane loaded") travel on separate streams, a late-joining consumer can observe inconsistent state — seeing a loaded diff without knowing which terminal produced it. Single stream with per-source ordering eliminates this within a pane. Cross-source ordering relies on timestamps — sufficient for UI rendering and workflow matching, not for strict causal ordering.

**Cross-source workflow example:** Terminal agent finishes (`source: .pane(agentA)`, `GhosttyEvent.commandFinished`) → filesystem watcher detects changes (`source: .worktree(wt1)`, `FilesystemEvent.filesChanged`) → coordinator creates diff pane. These events come from different sources, so `seq` is independent. The coordinator uses `correlationId` to link the workflow chain and `timestamp` to order them. This is sufficient: the coordinator doesn't need strict causal ordering — it only needs "commandFinished happened, then files changed" which timestamps guarantee within clock precision.

**Clarification:** `@Observable` state for UI binding remains separate from the event stream. Terminal views bind directly to `runtime.searchState` or `runtime.scrollbarState` via `@Observable`. The event stream carries coordination events only — things the workspace or other panes need to react to.

### D3: @Observable for UI state, event stream for coordination

**User problem:** Terminal UI must update at 60fps for scrollbar, search, mouse cursor. Workspace must react to "command finished" within one frame. These have different performance profiles (JTBD 6).

**Decision:** Two consumption paths:
- **UI binding:** `@Observable` properties on the runtime, views bind directly. High-frequency, low-latency, no event bus overhead.
- **Coordination:** `PaneRuntimeEvent` stream with envelopes. Cross-pane workflows, notifications, artifact routing.

**Why:** A scrollbar position update at 60fps should not flow through the same pipeline as "command finished with exit code 0." Direct `@Observable` binding is zero-overhead for UI. The event stream handles what needs routing, ordering, and batching.

### D4: GhosttyEvent enum at FFI boundary for exhaustive capture

**User problem:** Agent Studio currently ignores 28+ Ghostty actions (progress, bell, search, scrollbar, command finish, config reload, etc.). Users can't see command duration, progress bars, or respond to terminal notifications (JTBD 6, P6).

**Decision:** Every `ghostty_action_tag_e` maps to a case in a Swift `GhosttyEvent` enum. The adapter's switch is exhaustive. Unhandled events map to `.unhandled(tag)` with explicit logging — never silently dropped.

**Why:** Compile-time guarantee that adding a new Ghostty action forces a handler decision. The enum IS the documentation of "what Ghostty can tell us." Silent drops are how the current 12/40 gap happened.

### D5: Adapter → Runtime → Coordinator layering

**User problem:** Ghostty C callbacks arrive on arbitrary threads with C types. The system must be safe under Swift 6 strict concurrency and testable without real Ghostty surfaces (JTBD 3).

**Decision:** Three-layer pipeline:
1. **Adapter** — FFI boundary only. Translates C types to Swift enums. `@Sendable` trampolines hop to `MainActor`. No domain logic.
2. **Runtime** — Domain logic. Owns `@Observable` state. Produces coordination events. Pure Swift, testable with mock adapters.
3. **Coordinator** — Cross-store sequencing. Routes commands to runtimes. Consumes coordination events. No pane-type-specific logic.

### D6: Priority-aware event processing

**User problem:** When 5 agents are running, the active pane's "command finished" notification must not be delayed by background terminal telemetry (JTBD 6, P8).

**Decision:** Events self-classify as `critical` (never coalesced, immediate delivery) or `lossy` (batched on frame boundary, deduped by consolidation key). This is the **event classification** axis.

**Visibility tiers:** LUNA-295 defines a separate axis: `p0ActivePane → p1ActiveDrawer → p2VisibleActiveTab → p3Background`. This is a **delivery scheduling** concern — which pane's events get processed first when multiple events arrive in the same frame. The NotificationReducer resolves tier via an injected `VisibilityTierResolver` (coordinator-provided). Adding visibility tiers is additive — the event and envelope contracts are unchanged. See [Contract 12a: Visibility-Tier Scheduling](#contract-12a-visibility-tier-scheduling-luna-295) for the full specification.

### D7: Filesystem observation with batched artifact production

**User problem:** Agents edit 50 files in 2 seconds. The workspace needs to know "agent produced a changeset" without drowning in per-file events (JTBD 5, JTBD 6, P6).

**Decision:** Worktree-scoped `FSEvents` watcher → debounce window (500ms settle) → deduped batch → git status recompute. Max latency cap of 2 seconds ensures batches during sustained writes. Events flow on the same coordination stream as `FilesystemEvent` cases.

### D8: Execution backend as pane configuration, not pane type (JTBD 7, JTBD 8)

**User problem:** Users want security boundaries between agent contexts (JTBD 7). Later, they want to move sessions between machines (JTBD 8). The execution environment (bare metal, Docker, Gondolin VM, remote host) varies per pane.

**Decision:** `ExecutionBackend` is a per-pane configuration on `PaneMetadata`, not a pane type. A terminal pane can run on bare metal, Docker, or a Gondolin VM — same `TerminalRuntime`, different backend. Security events flow on the same event stream as all other events, scoped to worktreeId.

**Why not a separate pane type:** The sandbox is the execution environment, not the content. A sandboxed terminal is still a terminal. A sandboxed browser is still a browser. The runtime contract doesn't change — what changes is where the process runs.

**Why security events are cross-cutting:** A sandbox may back multiple panes in the same worktree. Security events (policy violations, secret access, network blocks) are scoped to worktreeId, not paneId. The coordinator fans out to affected panes.

**Deferred but reserved:** The `ExecutionBackend` type and `SecurityEvent` enum are defined now. Implementation ships when Gondolin or Docker integration begins. Zero cost to carry the types.

---

## Architecture Overview

```
USER INPUT / COMMAND BAR / KEYBOARD
              │
              v
┌─────────────────────────────────────────────────────────────────┐
│                      PANE COORDINATOR                           │
│  global orchestration only: tabs, layout, arrangement, undo     │
│  routes pane-scoped commands to runtimes                        │
│  consumes PaneRuntimeEvent stream for cross-pane workflows      │
│  owns NO domain state, NO pane-type-specific logic              │
├────────────┬─────────────────────┬──────────────────────────────┤
│            │                     │                              │
│    ┌───────┴──────┐    ┌────────┴────────┐    ┌──────────────┐ │
│    │ Workspace    │    │ Runtime         │    │ Surface      │ │
│    │ Store        │    │ Registry        │    │ Manager      │ │
│    │ (tabs,layout)│    │ (paneId→runtime)│    │ (C surfaces) │ │
│    └──────────────┘    └────────┬────────┘    └──────────────┘ │
└─────────────────────────────────┼──────────────────────────────┘
                                  │
        ┌─────────────────────────┼──────────────────────┐
        │                        │                       │
        v                        v                       v
┌───────────────┐    ┌────────────────┐    ┌──────────────────┐
│  TERMINAL     │    │   BROWSER      │    │    DIFF          │
│  RUNTIME      │    │   RUNTIME      │    │    RUNTIME       │
│               │    │                │    │                  │
│ @Observable   │    │ @Observable    │    │ @Observable      │
│ ┌───────────┐ │    │ ┌────────────┐ │    │ ┌──────────────┐ │
│ │ command   │ │    │ │ navigation │ │    │ │ hunk state   │ │
│ │ search    │ │    │ │ page       │ │    │ │ approval     │ │
│ │ scroll    │ │    │ │ console    │ │    │ │ comments     │ │
│ │ display   │ │    │ └────────────┘ │    │ └──────────────┘ │
│ │ input     │ │    │                │    │                  │
│ │ health    │ │    │ UI binds here  │    │ UI binds here    │
│ └───────────┘ │    │                │    │                  │
│               │    │                │    │                  │
│ UI binds here │    │   Produces:    │    │   Produces:      │
│               │    │ PaneRuntime-   │    │ PaneRuntime-     │
│  Produces:    │    │ Event stream   │    │ Event stream     │
│ PaneRuntime-  │    │                │    │                  │
│ Event stream  │    │                │    │                  │
└───────┬───────┘    └───────┬────────┘    └────────┬─────────┘
        │                    │                      │
        v                    v                      v
┌───────────────┐    ┌───────────────┐    ┌──────────────────┐
│ GHOSTTY       │    │ WEBKIT        │    │ ARTIFACT         │
│ ADAPTER       │    │ ADAPTER       │    │ COORDINATOR      │
│               │    │               │    │                  │
│ C callbacks   │    │ WKNavigation  │    │ fs/git diff/     │
│ → @Sendable   │    │ Delegate      │    │ snapshot         │
│ → MainActor   │    │ → typed       │    │ → typed          │
│ → GhosttyEvent│    │ → BrowserEvent│    │ → ArtifactEvent  │
└───────────────┘    └───────────────┘    └──────────────────┘
```

### Terminal-Driven Agent Workflow (the "inverse of Cursor" flow)

```
AGENT PROCESS (Claude/Codex)
  │
  ├── edits files via terminal ─────────────────────────────┐
  │                                                         │
  ├── PTY output ──► GhosttyAdapter                         │
  │                      │                                  │
  │                      ▼                                  ▼
  │                 TerminalRuntime              FilesystemWatcher
  │                      │                           │
  │                      │  GhosttyEvent:            │  debounce 500ms
  │                      │  .commandFinished         │  dedupe paths
  │                      │  .cwdChanged              │  max latency 2s
  │                      │  .progressReport          │
  │                      ▼                           ▼
  │              PaneRuntimeEvent              PaneRuntimeEvent
  │              .terminal(...)               .filesystem(...)
  │                      │                           │
  │                      └─────────┬─────────────────┘
  │                                │
  │                                ▼
  │                        PaneCoordinator
  │                                │
  │              ┌─────────────────┼─────────────────┐
  │              │                 │                  │
  │              ▼                 ▼                  ▼
  │     NotificationReducer   DiffRuntime      WorkspaceStore
  │     (badge on tab,        (show diff       (update tab
  │      toast, drawer)        to user)         metadata)
  │              │                 │
  │              ▼                 ▼
  │     User sees: "Agent A    User reviews diff
  │     finished (exit 0)"     in diff pane
  │                                │
  │                                ▼
  │                        User approves
  │                                │
  │                                ▼
  │                        PaneCoordinator
  │                        signals next agent
  │                                │
  └────────────────────────────────┘
```

### LUNA-295 Attach Lifecycle (concrete instance of pane lifecycle)

```
                    ┌─────────┐
                    │  idle   │
                    └────┬────┘
                         │ surfaceCreated
                         ▼
                 ┌───────────────┐
                 │ surfaceReady  │  shell started (zsh -i -l)
                 └───────┬───────┘
                         │ not yet in window / size == 0
                         ▼
                  ┌──────────────┐
                  │ sizePending  │  DeferredStartupReadiness gate
                  └──────┬───────┘
                         │ in window + non-zero size + process alive
                         │ OR persisted size for background attach
                         ▼
                   ┌─────────────┐
                   │  sizeReady  │
                   └──────┬──────┘
                          │ deferred attach injected
                          ▼
                   ┌─────────────┐
                   │  attaching  │  zmx attach in progress
                   └──────┬──────┘
                          │
                    ┌─────┴──────┐
                    │            │
                    ▼            ▼
             ┌──────────┐  ┌────────────┐
             │ attached  │  │  failed    │
             │           │  │ (retry w/  │
             │           │  │  backoff)  │
             └──────────┘  └────────────┘

Priority tiers control scheduling order:
  p0: active pane in active tab        → immediate
  p1: active pane's drawer panes       → next
  p2: other visible panes in active tab → after p1
  p3: hidden/background panes          → bounded concurrency
```

---

## Locked Contracts

### Contract Vocabulary

Every contract has a **role** keyword that describes its relationship to the event system:

| Role | Produces events? | Derives from upstream? | Exposes subscription? | Example |
|---|---|---|---|---|
| **Source** | Yes (original) | No — produces from external signals (OS, C API, agent hooks) | Yes | Contract 6 (worktree watcher), Contract 7 (GhosttyAdapter), Contract 15 (agent RPC) |
| **Projection** | Yes (derived) | Yes — filters/transforms a source's output | Yes | Contract 16 (per-pane CWD filter of Contract 6) |
| **Sink** | No | N/A | No — terminal consumer | Contract 12 (NotificationReducer), Contract 14 (Replay Buffer) |

A projection is a source that depends on another source. It cannot exist without its upstream. "Projection of [source]" names the dependency.

Contracts without a role keyword are **structural** — they define types, protocols, or policies rather than event flow participants (e.g., Contract 1 defines the runtime protocol, Contract 4 defines the priority classification).

### Contract 1: PaneRuntime Protocol

```swift
/// Every pane type (terminal, browser, diff, editor) conforms to this.
/// Coordinator only knows this protocol — never pane-type-specific types.
///
/// One instance per pane. All instances share @MainActor.
/// Adapters (GhosttyAdapter, WebKitAdapter) are shared singletons
/// that route events to the correct runtime instance.
///
/// Runtime produces envelopes (not raw events) — routing identity
/// (EventSource) and sequencing (seq) are set by the runtime itself.
/// Coordinator consumes envelopes directly; no wrapping step needed.
@MainActor
protocol PaneRuntime: AnyObject {
    var paneId: PaneId { get }
    var metadata: PaneMetadata { get }
    var lifecycle: PaneRuntimeLifecycle { get }
    var capabilities: Set<PaneCapability> { get }

    /// Dispatch a command. Fails if lifecycle != .ready.
    func handleCommand(_ envelope: PaneCommandEnvelope) async -> ActionResult

    /// Current state snapshot for late-joining consumers.
    func snapshot() -> PaneRuntimeSnapshot

    /// Bounded replay for catch-up.
    func eventsSince(seq: UInt64) async -> EventReplayBuffer.ReplayResult

    /// Subscribe to live coordination events as envelopes.
    /// Envelope carries source identity, sequencing, and event payload.
    func subscribe() -> AsyncStream<PaneEventEnvelope>

    /// Graceful shutdown. Returns unfinished command IDs.
    func shutdown(timeout: Duration) async -> [UUID]
}

struct PaneId: Hashable, Codable, Sendable {
    let uuid: UUID
}
typealias WorktreeId = UUID
```

> Identity canonical: `PaneId` is the primary identity and backend session names
> are derived identities. See
> [Session Lifecycle — Identity Contract (Canonical)](session_lifecycle.md#identity-contract-canonical).
>
> **Current Code Status (LUNA-343 branch):**
> - `PaneRuntime` now includes replay wiring via `eventsSince(seq:)`.
> - `PaneMetadata` now includes rich identity fields (`contentType`, `executionBackend`, `createdAt`, `repoId`, `worktreeId`, `parentFolder`, `checkoutRef`).
> - `PaneId` is now a first-class value type (`struct`) with UUIDv7-backed generation for new panes and UUID compatibility decoding for persisted legacy workspaces.
> - Compatibility is preserved through a legacy initializer accepting `TerminalSource` and a compatibility `terminalSource` computed property.

#### Supporting Types

```swift
/// Rich pane identity used for routing, grouping, and projection.
///
/// In current code, fixed identity fields are mutable for migration
/// compatibility (`paneId`/`contentType` are normalized at pane creation).
/// This remains compatible with the architectural target of immutable
/// creation-time identity.
///
/// DYNAMIC VIEW CONTRACT: Live fields are ALL OPTIONAL because not every
/// pane has a repo, worktree, or agent. Dynamic views (R5) group panes
/// by these facets — a nil value means the pane doesn't participate in
/// that grouping dimension. This is intentional:
///   - A floating terminal has no repoId, no worktreeId → excluded from
///     "group by repo" and "group by worktree" views
///   - A browser pane showing docs has no agentType → excluded from
///     "group by agent" views
///   - A terminal cd'd into /tmp has cwd but no worktreeId → included
///     in "group by CWD" but not "group by worktree"
///
/// Dynamic view projector reads: repoId, worktreeId, cwd, parentFolder,
/// checkoutRef, agentType, tags.
/// Association fields can be nil independently. `tags` is always present as
/// a set (possibly empty).
struct PaneMetadata: Sendable {
    // ── Fixed-at-creation identity (currently mutable for migration) ──
    var paneId: PaneId?
    var contentType: PaneContentType
    var source: PaneMetadataSource
    var executionBackend: ExecutionBackend
    var createdAt: Date

    // ── Live-updated fields ───────────────────────────────
    var title: String
    var cwd: URL?
    var repoId: UUID?
    var worktreeId: UUID?
    var parentFolder: String?
    var checkoutRef: String?
    var agentType: AgentType?
    var tags: [String]
}

/// Core pane kinds are a closed set for exhaustive switching.
/// Plugins use the escape hatch.
enum PaneContentType: Hashable, Sendable {
    case terminal
    case browser
    case diff
    case editor
    case plugin(String)
}

enum PaneMetadataSource: Sendable {
    case worktree(worktreeId: UUID, repoId: UUID)
    case floating(workingDirectory: URL?, title: String?)
}

/// Capabilities are a closed built-in set with a plugin extension case.
/// Coordinator gates command dispatch using this type.
enum PaneCapability: Hashable, Sendable {
    case input
    case resize
    case search
    case navigation
    case diffReview
    case editorActions
    case plugin(String)
}

/// Snapshot for late-joining consumers.
struct PaneRuntimeSnapshot: Sendable {
    let paneId: PaneId
    let metadata: PaneMetadata
    let lifecycle: PaneRuntimeLifecycle
    let capabilities: Set<PaneCapability>
    let lastSeq: UInt64
    let timestamp: Date
}

/// Result of dispatching a command to a runtime.
enum ActionResult: Sendable {
    case success(commandId: UUID)
    case queued(commandId: UUID, position: Int)
    case failure(ActionError)
}

enum ActionError: Error, Sendable {
    case runtimeNotReady(lifecycle: PaneRuntimeLifecycle)
    case unsupportedCommand(command: String, required: PaneCapability)
    case invalidPayload(description: String)
    case backendUnavailable(backend: String)
    case timeout(commandId: UUID)
}
```

### Contract 2: PaneKindEvent Protocol + PaneRuntimeEvent Enum

```swift
/// Protocol for all per-kind events. Built-in enums (GhosttyEvent, BrowserEvent,
/// DiffEvent, EditorEvent) conform to this AND have dedicated cases in
/// PaneRuntimeEvent for pattern matching. Plugin event types conform to this
/// and use the `.plugin` escape hatch.
///
/// Two roles:
///   1. Self-classifying priority — each event knows its own ActionPolicy.
///      NotificationReducer reads this directly instead of centralized classify().
///   2. Workflow matching — eventName provides a stable typed identity for
///      WorkflowTracker step predicates.
protocol PaneKindEvent: Sendable {
    /// Priority classification for this event.
    /// Critical = immediate delivery, never coalesced.
    /// Lossy = batched on frame boundary, deduped by consolidation key.
    var actionPolicy: ActionPolicy { get }

/// Stable typed identity for workflow matching and logging.
/// Built-in events use enum cases. Plugins use an escape hatch.
var eventName: EventIdentifier { get }
}

/// Typed event identity — replaces bare String for type safety.
/// Core identifiers are exhaustive enum cases; plugins use `plugin(String)`.
enum EventIdentifier: Hashable, Sendable, CustomStringConvertible {
    case commandFinished
    case cwdChanged
    case titleChanged
    case bellRang
    case scrollbarChanged
    case navigationCompleted
    case pageLoaded
    case diffLoaded
    case hunkApproved
    case contentSaved
    case fileOpened
    case unhandled
    case consoleMessage
    case allApproved
    case diagnosticsUpdated
    case plugin(String)

    var description: String {
        switch self {
        case .commandFinished: return "commandFinished"
        case .cwdChanged: return "cwdChanged"
        case .titleChanged: return "titleChanged"
        case .bellRang: return "bellRang"
        case .scrollbarChanged: return "scrollbarChanged"
        case .navigationCompleted: return "navigationCompleted"
        case .pageLoaded: return "pageLoaded"
        case .diffLoaded: return "diffLoaded"
        case .hunkApproved: return "hunkApproved"
        case .contentSaved: return "contentSaved"
        case .fileOpened: return "fileOpened"
        case .unhandled: return "unhandled"
        case .consoleMessage: return "consoleMessage"
        case .allApproved: return "allApproved"
        case .diagnosticsUpdated: return "diagnosticsUpdated"
        case .plugin(let value): return value
        }
    }
}

/// Single typed event stream. Discriminated union with plugin escape hatch.
///
/// Built-in pane kinds get dedicated cases (type safety, pattern matching,
/// compiler-enforced handling). Plugin pane kinds use `.plugin` (protocol-
/// based, extensible, downcast for specific handling).
///
/// IMPORTANT: Event payloads carry DOMAIN SEMANTICS ONLY.
/// Routing identity (source pane/worktree/system) lives on the envelope.
/// No paneId in event cases — prevents identity drift between event and envelope.
///
/// Two axes:
///   PANE-SCOPED: terminal, browser, diff, editor, plugin
///     (envelope.source = .pane(id))
///   CROSS-CUTTING: lifecycle, filesystem, artifact, security, error
///     (envelope.source = .worktree(id) or .system(...))
enum PaneRuntimeEvent: Sendable {
    // ── Lifecycle — all pane types ──────────────────────
    case lifecycle(PaneLifecycleEvent)

    // ── First-class pane kinds: exhaustive, pattern-matchable ──
    case terminal(GhosttyEvent)
    case browser(BrowserEvent)
    case diff(DiffEvent)
    case editor(EditorEvent)

    // ── Plugin escape hatch: protocol-based, extensible ──
    // Plugin pane types (log viewer, metrics dashboard, etc.) use this.
    // Events conform to PaneKindEvent. Downcast for specific handling.
    // To promote a plugin to first-class: add a dedicated case above.
    case plugin(kind: PaneContentType, event: any PaneKindEvent)

    // ── Cross-cutting events ───────────────────────────
    case filesystem(FilesystemEvent)
    case artifact(ArtifactEvent)
    case security(SecurityEvent)

    // ── Runtime errors ─────────────────────────────────
    case error(RuntimeErrorEvent)
}

/// Computed priority from self-classifying events.
/// NotificationReducer reads this — no centralized classify() needed.
extension PaneRuntimeEvent {
    var actionPolicy: ActionPolicy {
        switch self {
        case .terminal(let e):      return e.actionPolicy
        case .browser(let e):       return e.actionPolicy
        case .diff(let e):          return e.actionPolicy
        case .editor(let e):        return e.actionPolicy
        case .plugin(_, let e):     return e.actionPolicy
        case .lifecycle, .filesystem, .artifact, .security, .error:
            return .critical
        }
    }
}

/// Event scoping rules — routing identity on envelope, domain data on event:
///
///   PANE-SCOPED: envelope.source = .pane(id)
///     Lifecycle (surface/attach/close), drawer toggle, active pane change.
///     No paneId in event payload — it's on the envelope.
///
///   WORKSPACE-SCOPED: envelope.source = .system(.coordinator)
///     Tab switch. The activeTabId IS domain data (which tab), not routing.
///
///   WORKTREE-SCOPED: envelope.source = .worktree(id)
///     Filesystem changes, security events. No worktreeId in event cases.
///     Exception: FileChangeset.worktreeId is a DENORMALIZED COPY of
///     envelope.source for convenience — envelope.source is authoritative.
///
///   AGENT-SCOPED: envelope.source = .pane(agentPaneId)
///     Artifact events. The producing agent is routing identity.
///     worktreeId in payload = WHERE the artifact belongs (domain data,
///     may differ from producer's worktree).
///
///   ERROR EVENTS: envelope.source = source of the error
///     RuntimeErrorEvent carries the source that produced the error.
///     surfaceCrashed → .pane(id). adapterError → .pane(id).
///     resourceExhausted/internalStateCorrupted → whatever source triggered it.
enum PaneLifecycleEvent: Sendable {
    // ── Pane-scoped: envelope.source = .pane(id) ────────
    case surfaceCreated
    case sizeObserved(cols: Int, rows: Int)
    case sizeStabilized
    case attachStarted
    case attachSucceeded
    case attachFailed(error: AttachError)
    case paneClosed
    case activePaneChanged
    case drawerExpanded               // envelope.source = .pane(parentPaneId)
    case drawerCollapsed              // envelope.source = .pane(parentPaneId)

    // ── Workspace-scoped: envelope.source = .system(.coordinator) ──
    case tabSwitched(activeTabId: UUID)   // tabId IS domain data, not routing
}

/// Typed attach failure — Sendable, no bare Error.
enum AttachError: Error, Sendable {
    case surfaceNotFound
    case surfaceAlreadyAttached
    case backendUnavailable(reason: String)
    case timeout(after: Duration)
}

/// Filesystem events. envelope.source = .worktree(id) — routing identity.
/// No worktreeId in event payloads (it's on the envelope).
enum FilesystemEvent: Sendable {
    case filesChanged(changeset: FileChangeset)
    case gitStatusChanged(summary: GitStatusSummary)
    case diffAvailable(diffId: UUID)
    case branchChanged(from: String, to: String)
}

/// Artifact events. envelope.source = .pane(producerPaneId) — who produced it.
/// worktreeId in payload = which worktree the artifact covers (domain data,
/// not routing — an artifact can be for a different worktree than the producer).
enum ArtifactEvent: Sendable {
    case diffProduced(worktreeId: UUID, artifact: DiffArtifact)
    case prCreated(prUrl: String)
    case approvalRequested(request: ApprovalRequest)
    case approvalDecided(decision: ApprovalDecision)
}

/// Security events from execution backends (Gondolin, Docker, etc.).
/// envelope.source = .worktree(id) — one sandbox may back multiple panes.
/// No worktreeId in event payloads (it's on the envelope).
/// All cases are critical priority (user must know immediately).
enum SecurityEvent: Sendable {
    // Policy enforcement
    case networkEgressBlocked(destination: String, rule: String)
    case networkEgressAllowed(destination: String)
    case filesystemAccessDenied(path: String, operation: String)
    case secretAccessed(secretId: String, consumerId: String)
    case processSpawnBlocked(command: String, rule: String)

    // Sandbox lifecycle
    case sandboxStarted(backend: ExecutionBackend, policy: String)
    case sandboxStopped(reason: String)
    case sandboxHealthChanged(healthy: Bool)

    // Violations (always critical, always surfaced to user)
    case policyViolation(description: String, severity: ViolationSeverity)
    case credentialExfiltrationAttempt(targetHost: String)
}

enum ViolationSeverity: String, Sendable {
    case warning    // logged, user notified
    case critical   // process killed, user alerted
}

/// Runtime error events. All payloads are Sendable — no bare `Error`
/// across async boundaries. Underlying errors serialized to String
/// descriptions at the point of capture.
enum RuntimeErrorEvent: Error, Sendable {
    case surfaceCrashed(reason: String)
    case commandTimeout(commandId: UUID, after: Duration)
    case actionDispatchFailed(action: String, underlyingDescription: String)
    case adapterError(String)
    case resourceExhausted(resource: String)
    case internalStateCorrupted
}
```

### Contract 3: PaneEventEnvelope

> **Role:** Structural (envelope shape). Carried by all sources, projections, and sinks.

> **Extensibility:** `EventSource` and `SystemSource` are enums designed to grow. Adding a new case is a one-line change plus exhaustive switch updates in consumers. Per-source isolation guarantees (A4: independent `seq`, A10: independent replay buffer) mean new sources cannot break ordering or replay for existing sources. No shared state to corrupt. Add new sources in the same commit as the code that produces events on them.

```swift
/// Metadata wrapper on every event for routing, ordering, and idempotency.
///
/// ROUTING IDENTITY LIVES HERE — not in event payloads.
/// Pane-scoped events: source = .pane(id), paneKind = .terminal/.browser/etc.
/// Cross-cutting events: source = .worktree(id) or .system(...), paneKind = nil.
///
/// Priority is NOT cached on the envelope. The event self-classifies via
/// event.actionPolicy (PaneKindEvent protocol). NotificationReducer reads
/// this directly. One classification authority, no drift.
struct PaneEventEnvelope: Sendable {
    let source: EventSource                  // who produced this event
    let paneKind: PaneContentType?           // nil for cross-cutting (filesystem, security)
    let seq: UInt64                          // monotonic per source, ordering guarantee
    let commandId: UUID?                     // idempotency for command-triggered events; nil for spontaneous
    let correlationId: UUID?                 // links workflow steps (agent finish → diff → approval)
    let timestamp: ContinuousClock.Instant
    let epoch: UInt64                        // reserved, 0 until runtime restart/reconnect
    let event: PaneRuntimeEvent
}

/// Who produced an event. Replaces required paneId on envelope.
/// Pane-scoped events carry .pane(id). Cross-cutting events carry
/// .worktree(id) or .system (filesystem watcher, security backend).
enum EventSource: Hashable, Sendable {
    case pane(PaneId)
    case worktree(WorktreeId)
    case system(SystemSource)
}

enum SystemSource: Hashable, Sendable {
    case filesystemWatcher
    case securityBackend
    case coordinator
}
```

#### Envelope Invariants (normative)

1. Sequence ownership: each runtime (or system producer) is the sole writer of `seq` for its own `EventSource`.
2. Monotonicity: `seq` is strictly increasing per `EventSource`. Gaps are allowed only due to bounded replay eviction.
3. Source/payload compatibility:
- Pane-scoped payloads (`.terminal`, `.browser`, `.diff`, `.editor`, `.plugin`) require `source = .pane(id)`.
- Filesystem and security payloads require `source = .worktree(id)` or explicit system producer.
- Workspace lifecycle events that are not pane-scoped require `source = .system(.coordinator)`.
4. Invalid source/payload combinations are contract violations and must emit a typed runtime error event.
5. `commandId` is optional and only present for command-correlated events.

### Contract 4: ActionPolicy (self-classifying priority)

```swift
/// Determines how each event is processed.
/// Critical events bypass coalescing. Lossy events batch on frame boundary.
///
/// SELF-CLASSIFYING: Each per-kind event enum implements actionPolicy
/// via PaneKindEvent conformance. The NotificationReducer reads
/// envelope.event.actionPolicy — no centralized classify() method.
/// This means plugin events self-classify without core code changes.
enum ActionPolicy: Sendable {
    case critical                             // immediate delivery, never dropped
    case lossy(consolidationKey: String)      // dedup + coalesce within frame window
}

/// Classification rules (implemented by each PaneKindEvent conformer):
///
/// Lifecycle / cross-cutting: always critical
/// Control actions (command finish, bell, notification): always critical
/// Metadata changes (title, CWD, URL): always critical
/// Viewport/telemetry (scroll, cursor, selection): lossy
/// Rendering (color, font): lossy, consolidate adjacent
///
/// NotificationReducer maintains two queues:
///   criticalQueue — emits immediately, wakes main loop
///   lossyQueue    — batches until next frame (16.67ms at 60fps)
///                   deduped by consolidation key
///                   max queue depth 1000, drops oldest on overflow
```

### Contract 5: PaneLifecycleStateMachine

```swift
/// Shared lifecycle contract for all pane types.
/// Every runtime transitions through these states.
enum PaneRuntimeLifecycle: Sendable {
    case created        // runtime initialized, waiting for first attach/ready
    case ready          // accepting commands, producing events
    case draining       // no new commands accepted, in-flight completing
    case terminated     // all resources released, streams closed
}

/// Lifecycle invariants:
///   1. created → ready (only transition forward)
///   2. ready → draining (on close request)
///   3. draining → terminated (after timeout or all commands complete)
///   4. handleCommand() returns .failure(.runtimeNotReady) if lifecycle != .ready
///   5. shutdown(timeout:) is idempotent — safe to call multiple times
///   6. After terminated, no events emitted, no commands accepted
///   7. Unfinished command IDs returned from shutdown() for logging/recovery
```

### Contract 5a: Attach Readiness Policy (LUNA-295)

Terminal panes require a readiness gate before zmx attach. This contract defines two normative policies based on pane visibility at attach time. Both policies implement the `sizePending → sizeReady → attaching → attached/failed` sub-states from the LUNA-295 attach lifecycle diagram above.

#### Ghostty Embedding Facts (normative)

These are verified behaviors of the Ghostty C API that the attach policy depends on:

1. **Geometry is independent of visibility.** `ghostty_surface_set_size(cols, rows)` updates terminal geometry even when the surface is occluded. The terminal reflows content at the new size regardless of whether the surface is rendering.
2. **Visibility is a separate occlusion signal.** `ghostty_surface_set_occlusion(true/false)` controls whether the surface renders. An occluded surface still accepts input and processes escape sequences — it just doesn't paint. Occlusion is not a proxy for geometry validity.
3. **Focus is a separate input signal.** `ghostty_surface_set_focus(true/false)` controls keyboard input routing. Focus, visibility, and geometry are three independent axes.
4. **zmx attach at placeholder size causes reflow.** If a surface is attached before stable geometry, the terminal reflows when the real size arrives. This produces visual flicker (content jumps, prompt redraws). For best UX, attach should use known-good geometry.

#### Policy 1: Active-Visible Attach (default for visible panes)

```swift
/// Readiness gate for panes that are visible at attach time.
/// This is the strict policy — requires real geometry from the view system.
///
/// Preconditions (ALL must be true):
///   1. Surface has a containing window (hasWindow == true)
///   2. Content size is non-zero (width > 0 && height > 0)
///   3. Shell process is alive (process has not exited)
///   4. Deferred attach has not already been sent
///
/// Sequence:
///   1. Pane starts shell (zsh -i -l) → surface created
///   2. Surface enters sizePending (DeferredStartupReadiness gate)
///   3. View system delivers stable frame → sizeReady
///   4. Runtime injects zmx attach text + sends Return key event
///   5. Transition to attaching → attached (or failed with retry)
///
/// Anti-flicker guarantee: attach never occurs against placeholder
/// geometry. The surface has real cols/rows from the view layout.
struct ActiveVisibleAttachPolicy: Sendable {
    /// All four conditions must be true simultaneously.
    static func isReady(
        hasWindow: Bool,
        contentSize: CGSize,
        processAlive: Bool,
        attachSent: Bool
    ) -> Bool {
        hasWindow
            && contentSize.width > 0
            && contentSize.height > 0
            && processAlive
            && !attachSent
    }
}
```

#### Policy 2: Background Prewarm Attach (for non-visible restored panes)

```swift
/// Readiness gate for panes that are NOT visible at attach time.
/// Used during session restore for background panes.
///
/// Background attach uses persisted geometry (cols/rows from the
/// previous session) instead of requiring a visible window. This
/// allows zmx attach to proceed immediately without waiting for
/// the view system to deliver a frame.
///
/// Preconditions (ALL must be true):
///   1. Persisted geometry is available (cols > 0 && rows > 0)
///   2. Shell process is alive
///   3. Deferred attach has not already been sent
///   Note: hasWindow is NOT required — that's the whole point.
///
/// Sequence:
///   1. App restore creates surface in background
///   2. ghostty_surface_set_size(persistedCols, persistedRows)
///   3. Surface enters sizeReady immediately (persisted geometry)
///   4. Runtime injects zmx attach (surface is occluded, no render cost)
///   5. On reveal: ghostty_surface_set_size(actualCols, actualRows)
///      + ghostty_surface_set_occlusion(false)
///   6. Terminal reflows to actual size (single reflow, not flicker)
///
/// Reconcile-on-reveal: when the pane becomes visible, the coordinator
/// delivers the actual frame size. If it differs from persisted
/// geometry, the terminal reflows once. This is a single, expected
/// reflow — not the multi-reflow flicker that placeholder attach causes.
///
/// Persisted geometry source: `PersistedSessionState.lastCols` and
/// `PersistedSessionState.lastRows`, saved by `WorkspacePersistor`
/// on debounced persist (every 500ms of workspace changes).
///
/// Fallback: if no persisted geometry exists (first launch, corrupted
/// state, or session created after last persist), fall back to
/// ActiveVisibleAttachPolicy (shell warms in background, attach
/// deferred until the pane becomes visible and passes the full gate).
struct BackgroundPrewarmAttachPolicy: Sendable {
    static func isReady(
        persistedCols: UInt16,
        persistedRows: UInt16,
        processAlive: Bool,
        attachSent: Bool
    ) -> Bool {
        persistedCols > 0
            && persistedRows > 0
            && processAlive
            && !attachSent
    }
}
```

#### Attach Policy Selection (coordinator responsibility)

```swift
/// The coordinator selects the attach policy based on pane visibility
/// at creation/restore time. This is a one-time decision — once a
/// policy is selected, it governs the pane's attach sequence.
///
/// Decision matrix:
///   - Pane created by user action (new tab, new split) → ActiveVisibleAttachPolicy
///     (pane is always visible when user creates it)
///   - Pane restored, currently active/visible → ActiveVisibleAttachPolicy
///     (pane is visible, use real geometry)
///   - Pane restored, background, has persisted geometry → BackgroundPrewarmAttachPolicy
///     (attach immediately with persisted size, reconcile on reveal)
///   - Pane restored, background, NO persisted geometry → ActiveVisibleAttachPolicy
///     (fallback: defer attach until visible)
///
/// After attach succeeds, the policy is consumed. Subsequent size
/// changes are normal resize events, not attach readiness gates.
```

#### Attach Readiness Invariants

1. **Attach is a one-time gate.** Once a pane transitions from `sizePending → sizeReady → attaching → attached`, the readiness policy is consumed. Subsequent size changes are resize events, not re-attach triggers.
2. **Geometry and visibility are independent signals.** `ghostty_surface_set_size` does not require `ghostty_surface_set_occlusion(false)`. A background pane can be sized without being visible.
3. **Persisted geometry is a best-effort optimization.** If persisted cols/rows are wrong, the terminal reflows on reveal. This is a single reflow, acceptable UX. If no persisted geometry exists, the pane falls back to active-visible policy.
4. **Shell starts before attach.** Both policies start the interactive shell (`zsh -i -l`) immediately. The attach command is deferred — the shell is warm and accepting input when attach arrives. This ensures no lost keystrokes during the attach injection sequence.
5. **Attach injection is text + Return key event.** The runtime writes the zmx attach command as text into the PTY, then sends a real Return key event via Ghostty input injection. This is deliberate — it appears in scrollback as a visible command, making the attach auditable.

### Contract 5b: Restart Reconcile Policy (LUNA-324)

On app launch, the restore flow reconciles persisted workspace state against live zmx daemons before creating any Ghostty surfaces. This prevents stale sessions from consuming resources and ensures orphaned zmx processes are cleaned up.

#### Reconcile Sequence

```swift
/// Executed once during AppDelegate.applicationDidFinishLaunching,
/// BEFORE surface creation or pane restoration.
///
/// Input:
///   - persisted: Set<SessionId> from WorkspacePersistor (last saved state)
///   - live: Set<SessionId> from `zmx list` with ZMX_DIR environment
///
/// Dependencies (injected on the owning coordinator/service):
///   - zmxBackend: ZmxBackend instance for session discovery
///   - persistor: WorkspacePersistor for retrieving persisted state
///   - clock: any Clock<Duration> for orphan discovery timestamps
///
/// The reconcile produces a classification for every known session.
/// Surface creation and attach proceed only for runnable sessions.
///
/// This is a SYNCHRONOUS operation — no surfaces exist yet, no races.

enum RestoreClassification: Sendable {
    /// Persisted AND live in zmx → safe to restore.
    /// Action: create surface, apply attach readiness policy.
    case runnable

    /// Persisted but NOT live in zmx → session died while app was closed.
    /// Action: show restart placeholder in the pane slot. User can
    /// restart manually or the pane can be auto-removed after confirmation.
    case expired(reason: String)

    /// Live in zmx but NOT persisted → orphan from a previous crash or
    /// incomplete shutdown. Subject to grace TTL before cleanup.
    case orphan(discoveredAt: ContinuousClock.Instant)
}

struct ReconcileResult: Sendable {
    let runnable: [SessionId: PersistedSessionState]
    let expired: [SessionId: String]  // sessionId → reason
    let orphans: [SessionId: ContinuousClock.Instant]  // sessionId → discoveredAt
}

@MainActor
func reconcileOnLaunch(
    persisted: Set<SessionId>,
    zmxDir: URL
) async -> ReconcileResult {
    // 1. Snapshot live sessions (single zmx list call)
    let live = await zmxBackend.listSessions(zmxDir: zmxDir)
    let liveSet = Set(live.map(\.sessionId))

    // 2. Classify persisted sessions
    var runnable: [SessionId: PersistedSessionState] = [:]
    var expired: [SessionId: String] = [:]
    for sessionId in persisted {
        if liveSet.contains(sessionId) {
            runnable[sessionId] = persistor.state(for: sessionId)
        } else {
            expired[sessionId] = "zmx session not found on launch"
        }
    }

    // 3. Classify runtime-only sessions (orphans)
    let orphanIds = liveSet.subtracting(persisted)
    let now = clock.now
    var orphans: [SessionId: ContinuousClock.Instant] = [:]
    for sessionId in orphanIds {
        orphans[sessionId] = now
    }

    return ReconcileResult(
        runnable: runnable,
        expired: expired,
        orphans: orphans
    )
}
```

#### Orphan Cleanup TTL Policy

```swift
/// Orphans are NEVER killed immediately at discovery. A grace period
/// prevents killing sessions that are legitimately running but not yet
/// persisted (e.g., race condition on previous shutdown).
///
/// Rules:
///   1. Grace TTL: 60 seconds from discovery time.
///   2. Re-check liveness before kill: call `zmx list` again at TTL
///      expiration. If the session is gone, no action needed.
///   3. Log: discovery time, kill attempt time, kill outcome.
///   4. One cleanup cycle per app launch. No continuous background reaping.
///
/// The TTL is injectable via Clock<Duration> for testability.

struct OrphanCleanupPolicy: Sendable {
    let graceTTL: Duration  // default: .seconds(60)
    let clock: any Clock<Duration>

    func shouldKill(
        discoveredAt: ContinuousClock.Instant,
        now: ContinuousClock.Instant
    ) -> Bool {
        now - discoveredAt >= graceTTL
    }
}
```

#### Health Monitoring (post-restore)

```swift
/// After reconcile completes and surfaces are created, periodic health
/// monitoring begins for all runnable sessions.
///
/// Rules:
///   1. Health check interval: 30 seconds (injectable).
///   2. Health check method: `zmx list` filtered to known sessions.
///   3. If a previously-runnable session disappears from zmx list:
///      emit PaneRuntimeEvent.lifecycle(.sessionLost(paneId))
///      → coordinator transitions pane to .draining → .terminated
///      → show restart placeholder
///   4. Health monitoring stops when the pane reaches .terminated.
```

#### Restart Reconcile Invariants

1. **Reconcile before surface creation.** No Ghostty surface is created until reconcile classifies all persisted sessions. This prevents creating surfaces for dead sessions.
2. **Single zmx list snapshot.** Reconcile calls `zmx list` exactly once at startup. Individual session health is checked during the health monitoring phase, not during reconcile.
3. **Orphans get a grace period.** Never kill on first discovery. The 60-second TTL protects against race conditions where a session is legitimate but not yet persisted.
4. **Expired sessions show UI.** An expired session is not silently removed — the user sees a restart placeholder in the pane slot. This is important because the user may have unsaved work context associated with that pane's position in the layout.
5. **ZMX_DIR scoping.** All zmx operations during reconcile use the same `ZMX_DIR` as session creation. This ensures reconcile only discovers sessions owned by this Agent Studio instance, not sessions from other installations.

### Contract 6: Filesystem Batching

> **Role:** Source. Produces `FilesystemEvent` on the coordination stream with `source = .worktree(id)`. One watcher instance per worktree — shared across all panes in that worktree. Contract 16 is a projection of this source.

```swift
/// Worktree-scoped filesystem observation contract.
///
/// Rules:
///   1. Debounce window: 500ms (wait for agent to finish writing)
///   2. Max latency cap: 2 seconds (emit at least one batch during sustained writes)
///   3. Dedupe key: file path within worktree (same file modified 5× → 1 event)
///   4. Max batch size: 500 paths (split into multiple batches if larger)
///   5. Settle detection: no new events for debounce window → flush
///   6. Git status recompute: only after batch flush, not per-file
///   7. Git status recomputes are SEQUENTIAL per worktree. If two batches
///      flush back-to-back for the same worktree, the second git status
///      waits for the first to complete. This prevents race conditions
///      where concurrent git status calls produce inconsistent diff state.
///      Cross-worktree git status calls are independent (different repos).
///   8. Identity: every batch carries worktreeId for routing
///   9. gitignore-aware exclusion: paths matching the worktree's
///      .gitignore rules are excluded BEFORE entering the batch.
///      This includes nested .gitignore files. The watcher reads
///      gitignore state from the same git context used for git status.
///      Excluded paths never appear in FileChangeset.paths —
///      downstream consumers (Contract 16, diff viewer) never see them.
///      This prevents .build/, node_modules/, .git/objects/ noise
///      from reaching the coordination stream.

/// Standalone data structure — may be serialized/stored independently.
/// worktreeId denormalized here for self-documenting data. Canonical
/// source is envelope.source = .worktree(id).
/// IDENTITY vs DOMAIN DATA clarification:
///
/// FileChangeset.worktreeId is a DENORMALIZED COPY of envelope.source's
/// WorktreeId. It exists for convenience — consumers can access worktreeId
/// without unwrapping the envelope. Routing decisions use envelope.source;
/// this field is a read-through copy, not a separate source of truth.
///
/// Same pattern as ArtifactEvent.diffProduced(worktreeId:) — worktreeId
/// in the payload is DOMAIN DATA ("which worktree this changeset covers"),
/// while envelope.source = .worktree(id) is ROUTING IDENTITY.
///
/// In practice, FileChangeset.worktreeId == envelope.source.worktreeId
/// always. If they ever diverge, envelope.source is authoritative.
struct FileChangeset: Sendable {
    let worktreeId: WorktreeId       // denormalized from envelope.source (domain data)
    let paths: Set<String>           // deduped relative paths
    let timestamp: ContinuousClock.Instant
    let batchSeq: UInt64             // monotonic per worktree
}
```

### Contract 7: GhosttyEvent FFI Enum

> **Role:** Source. GhosttyAdapter produces `GhosttyEvent` from C API callbacks, routed to `TerminalRuntime` instances by surfaceId. Events enter the coordination stream with `source = .pane(id)`.

```swift
/// Exhaustive mapping of ghostty_action_tag_e → Swift.
/// Every Ghostty action has exactly one case.
/// Adapter switch is exhaustive — compiler enforces coverage.
///
/// Conforms to PaneKindEvent — self-classifies priority via actionPolicy.
/// See "Where Priority Lives" section for implementation pattern.
enum GhosttyEvent: PaneKindEvent {
    // Workspace-facing (coordinator consumes, critical priority)
    case titleChanged(String)
    case cwdChanged(String)
    case commandFinished(exitCode: Int, duration: UInt64)
    case bellRang
    case desktopNotification(title: String, body: String)
    case progressReport(state: ProgressState, value: Int?)
    case childExited(exitCode: UInt32)
    case closeSurface(processAlive: Bool)

    // Tab/split requests (coordinator routes)
    case newTab
    case closeTab(CloseMode)
    case gotoTab(TabTarget)
    case moveTab(Int)
    case newSplit(SplitDirection)
    case gotoSplit(GotoDirection)
    case resizeSplit(amount: Int, direction: ResizeDirection)
    case equalizeSplits
    case toggleSplitZoom

    // Terminal-internal state (runtime @Observable, lossy priority)
    case scrollbarChanged(ScrollbarState)
    case searchStarted
    case searchEnded
    case searchTotal(Int)
    case searchSelected(Int)
    case mouseShapeChanged(MouseShape)
    case mouseVisibilityChanged(MouseVisibility)
    case linkHover(String?)
    case rendererHealth(RendererHealth)
    case cellSize(CellSize)
    case sizeLimits(SizeLimits)
    case initialSize(width: UInt32, height: UInt32)
    case readOnly(ReadOnlyState)

    // Config/system
    case configReload(soft: Bool)
    case configChanged(ConfigChangeToken)
    case colorChanged(kind: ColorKind, r: UInt8, g: UInt8, b: UInt8)
    case secureInput(SecureInputState)
    case keySequence(active: Bool, trigger: InputTrigger?)
    case keyTable(KeyTableAction)
    case openConfig
    case presentTerminal

    // Application-level
    case toggleFullscreen(FullscreenMode)
    case toggleWindowDecorations
    case toggleCommandPalette
    case toggleVisibility
    case floatWindow(FloatWindowState)
    case quitTimer(QuitTimerAction)
    case undo
    case redo

    // Explicit unhandled — logged with surface/pane context, never silent.
    // Log MUST include: tag value, paneId (from adapter routing), and
    // Ghostty surface pointer (for cross-referencing with C-level logs).
    // This identifies which runtime is receiving unmapped actions during
    // development and Ghostty version upgrades.
    case unhandled(tag: UInt32)
}
```

#### Contract 7a: Ghostty Action Coverage Policy (LUNA-325)

Every `ghostty_action_tag_e` case has a defined handling policy. The adapter's switch is exhaustive — the compiler enforces that adding a new Ghostty action forces a handler decision. This table covers all cases in the `GhosttyEvent` enum (Contract 7). During LUNA-325 implementation, the adapter's exhaustive switch against `ghostty_action_tag_e` will verify completeness at compile time — any Ghostty version with new actions produces a compile error until handled.

| GhosttyEvent Case | Handler | Routing | Priority | Notes |
|---|---|---|---|---|
| **Workspace-facing (coordinator consumes)** | | | | |
| `titleChanged` | Runtime → Coordinator | Updates `PaneMetadata.title` | critical | Tab title |
| `cwdChanged` | Runtime → Coordinator | Updates `PaneMetadata.cwd`, triggers repo/worktree resolution | critical | Dynamic view recomputation |
| `commandFinished` | Runtime → Coordinator | Workflow trigger, notification badge | critical | Agent completion signal |
| `bellRang` | Runtime → Coordinator | Notification toast/badge | critical | User attention request |
| `desktopNotification` | Runtime → Coordinator | System notification | critical | From OSC 777 / iTerm2 escape |
| `progressReport` | Runtime → Coordinator | Progress bar UI update | critical | From OSC 9;4 |
| `childExited` | Runtime → Coordinator | Lifecycle transition to draining | critical | Shell/process exit |
| `closeSurface` | Runtime → Coordinator | Pane close flow (with undo) | critical | User Cmd+W or process-initiated |
| **Tab/split requests (coordinator routes)** | | | | |
| `newTab` | Coordinator | Creates new tab via PaneAction | critical | Keyboard shortcut passthrough |
| `closeTab` | Coordinator | Closes tab via PaneAction (with undo) | critical | Keyboard shortcut passthrough |
| `gotoTab` | Coordinator | Tab navigation | critical | |
| `moveTab` | Coordinator | Tab reorder | critical | |
| `newSplit` | Coordinator | Creates split via PaneAction | critical | |
| `gotoSplit` | Coordinator | Focus navigation between splits | critical | |
| `resizeSplit` | Coordinator | Split resize | critical | |
| `equalizeSplits` | Coordinator | Reset split ratios | critical | |
| `toggleSplitZoom` | Coordinator | Zoom/unzoom split | critical | |
| **Terminal-internal state (runtime @Observable)** | | | | |
| `scrollbarChanged` | Runtime only | Updates `@Observable scrollbarState` | lossy("scroll") | 60fps UI binding |
| `searchStarted/Ended` | Runtime only | Updates `@Observable searchState` | critical | Mode transition |
| `searchTotal/Selected` | Runtime only | Updates `@Observable searchState` | lossy("search") | Result count |
| `mouseShapeChanged` | Runtime only | Updates cursor shape | lossy("mouse") | NSCursor update |
| `mouseVisibilityChanged` | Runtime only | Shows/hides cursor | lossy("mouse") | |
| `linkHover` | Runtime only | Shows link preview | lossy("mouse") | URL tooltip |
| `rendererHealth` | Runtime only | Updates `@Observable healthState` | critical | GPU/renderer status |
| `cellSize` | Runtime only | Cell metrics for layout | lossy("cell") | |
| `sizeLimits` | Runtime only | Min/max terminal size | critical | One-time on init |
| `initialSize` | Runtime only | First size report | critical | Attach readiness signal |
| `readOnly` | Runtime only | Read-only mode toggle | critical | |
| **Config/system** | | | | |
| `configReload` | Runtime → Coordinator | Re-apply terminal config | critical | Soft/hard reload |
| `configChanged` | Runtime only | Config delta | critical | |
| `colorChanged` | Runtime only | Terminal color change | lossy("color") | Theme update |
| `secureInput` | Runtime only | Secure input mode | critical | Password entry |
| `keySequence` | Runtime only | Key sequence mode | critical | Leader key |
| `keyTable` | Runtime only | Key table action | critical | |
| `openConfig` | Coordinator | Open config file/UI | critical | User action |
| `presentTerminal` | Coordinator | Bring terminal to front | critical | |
| **Application-level** | | | | |
| `toggleFullscreen` | Coordinator → Window | Window mode change | critical | |
| `toggleWindowDecorations` | Coordinator → Window | Chrome toggle | critical | |
| `toggleCommandPalette` | Coordinator → CommandBar | Open/close ⌘P | critical | |
| `toggleVisibility` | Coordinator → Window | Show/hide app | critical | |
| `floatWindow` | Coordinator → Window | Float/unfloat | critical | |
| `quitTimer` | Coordinator → App | Quit countdown | critical | |
| `undo/redo` | Coordinator → Undo Manager | Edit undo/redo | critical | |
| **Fallback** | | | | |
| `unhandled(tag)` | Adapter | Logged at warning level, never silently dropped | — | Compile-time coverage gap detector |

#### Coverage Invariants

1. **Exhaustive switch.** The adapter's `handleAction(_ action: ghostty_action_s)` switch is exhaustive over `ghostty_action_tag_e`. Adding a new Ghostty version with new actions produces a compile error until a case is added.
2. **No silent drops.** Every action either produces a typed `GhosttyEvent` case or maps to `.unhandled(tag)` which is logged. There is no `default:` branch. The current 12/40 coverage gap exists in the legacy code — this contract requires closing it.
3. **Handler is normative.** The "Handler" column in the table above defines where each event terminates. Runtime-only events do not reach the coordinator. Coordinator events do not mutate runtime state directly — they call store methods.
4. **Priority is per-case.** The "Priority" column matches the `actionPolicy` implementation in `GhosttyEvent.actionPolicy`. Changing priority requires updating both the table and the code.

### Contract 8: Per-Kind Event Enums

Each pane kind has its own event enum — exhaustive within that domain, just as `GhosttyEvent` is exhaustive for the Ghostty C API.

```swift
/// Browser/webview events — from WKNavigationDelegate and WKUIDelegate.
/// Conforms to PaneKindEvent — self-classifies priority via actionPolicy.
enum BrowserEvent: PaneKindEvent {
    // Navigation
    case navigationStarted(url: URL)
    case navigationCompleted(url: URL, statusCode: Int?)
    case navigationFailed(url: URL, error: String)
    case urlChanged(url: URL)
    case titleChanged(String)

    // Page lifecycle
    case pageLoaded(url: URL)
    case pageUnloaded
    case contentSizeChanged(width: Double, height: Double)

    // Console (from WKScriptMessageHandler)
    case consoleMessage(level: ConsoleLevel, message: String, source: String?, line: Int?)
    case consoleCleared

    // Interaction
    case linkClicked(url: URL, newWindow: Bool)
    case downloadRequested(url: URL, filename: String)
    case dialogRequested(kind: DialogKind, message: String)
    case dialogDismissed

    // Auth
    case authChallengeReceived(host: String, realm: String?)
}

enum ConsoleLevel: String, Sendable { case log, warn, error, debug, info }
enum DialogKind: String, Sendable { case alert, confirm, prompt }

/// Diff viewer events — hunk review, approval workflow, commenting.
/// Conforms to PaneKindEvent — self-classifies priority via actionPolicy.
enum DiffEvent: PaneKindEvent {
    // Navigation within diff
    case fileSelected(path: String, hunkIndex: Int?)
    case hunkNavigated(hunkId: String, direction: NavigationDirection)
    case fileListScrolled(visibleRange: Range<Int>)

    // Review actions
    case hunkApproved(hunkId: String)
    case hunkRejected(hunkId: String, reason: String?)
    case fileApproved(path: String)
    case allApproved
    case allRejected(reason: String?)

    // Comments
    case commentAdded(hunkId: String, lineRange: ClosedRange<Int>, text: String)
    case commentResolved(commentId: UUID)
    case commentDeleted(commentId: UUID)

    // State
    case diffLoaded(stats: DiffStats)
    case diffUpdated(stats: DiffStats)      // live reload from fs watcher
    case diffClosed
}

enum NavigationDirection: String, Sendable { case next, previous }

struct DiffStats: Sendable {
    let filesChanged: Int
    let insertions: Int
    let deletions: Int
    let hunks: Int
}

/// Code editor events — cursor, diagnostics, file lifecycle.
/// Conforms to PaneKindEvent — self-classifies priority via actionPolicy.
enum EditorEvent: PaneKindEvent {
    // Cursor/selection
    case cursorMoved(line: Int, column: Int)
    case selectionChanged(range: TextRange?)
    case visibleRangeChanged(firstLine: Int, lastLine: Int)

    // Content
    case contentModified(path: String, changeCount: Int)
    case contentSaved(path: String)
    case contentReverted(path: String)

    // Diagnostics
    case diagnosticsUpdated(path: String, errors: Int, warnings: Int)
    case diagnosticSelected(path: String, line: Int, severity: DiagnosticSeverity)

    // File lifecycle
    case fileOpened(path: String, language: String?)
    case fileClosed(path: String)
    case languageDetected(path: String, language: String)
}

struct TextRange: Sendable {
    let startLine: Int, startColumn: Int
    let endLine: Int, endColumn: Int
}

enum DiagnosticSeverity: String, Sendable { case error, warning, info, hint }
```

### Contract 9: Execution Backend

```swift
/// Execution environment for a pane's process.
/// Per-pane CONFIGURATION, not a pane type. A terminal pane can run
/// on any backend. The runtime contract doesn't change.
///
/// Stored on PaneMetadata. Set at pane creation, immutable for pane lifetime.
/// Live migration between backends is a FUTURE capability — no
/// SecurityEvent case exists for this yet. To change backends today,
/// close the pane and create a new one.
enum ExecutionBackend: Sendable {
    /// Direct host execution. No isolation. Default.
    case local

    /// Docker container with resource limits and network policy.
    case docker(DockerConfig)

    /// Gondolin VM with full sandbox policy.
    case gondolin(GondolinPolicy)

    /// Remote host via SSH or zmx tunnel (JTBD 8).
    case remote(RemoteConfig)
}

struct DockerConfig: Sendable {
    let image: String
    let networkMode: DockerNetworkMode
    let mounts: [MountSpec]
    let resourceLimits: ResourceLimits?
}

enum DockerNetworkMode: String, Sendable {
    case host, bridge, none
}

struct MountSpec: Sendable {
    let hostPath: String
    let containerPath: String
    let readOnly: Bool
}

struct ResourceLimits: Sendable {
    let cpuShares: Int?
    let memoryMB: Int?
    let pidsLimit: Int?
}

struct GondolinPolicy: Sendable {
    let policyId: String
    let networkEgress: EgressPolicy
    let secretIds: Set<String>              // injected as env vars, never in PTY
    let filesystemPolicy: FilesystemPolicy
}

enum EgressPolicy: Sendable {
    case allowAll
    case allow(domains: Set<String>)
    case deny(domains: Set<String>)
    case denyAll
}

enum FilesystemPolicy: Sendable {
    case worktreeOnly                       // r/w only within worktree root
    case readOnlyHost                       // r/o host fs, r/w worktree
    case custom(rules: [FilesystemRule])
}

struct FilesystemRule: Sendable {
    let path: String
    let access: FSAccess
}

enum FSAccess: String, Sendable { case readWrite, readOnly, deny }

struct RemoteConfig: Sendable {
    let host: String
    let port: Int
    let authMethod: RemoteAuthMethod
    let tunnelType: TunnelType
}

enum RemoteAuthMethod: Sendable {
    case sshKey(path: String)
    case sshAgent
    case password                           // stored in keychain, never hardcoded
}

enum TunnelType: String, Sendable { case ssh, zmx }
```

### Contract 10: Inbound Runtime Command Dispatch

```swift
/// Command envelope dispatched TO a runtime (inbound).
/// Mirror of PaneEventEnvelope (outbound from runtime → coordinator).
///
/// NOTE: "RuntimeCommand" is the runtime-level command vocabulary —
/// distinct from the workspace-level `PaneAction` in `Core/Actions/`
/// which handles tab/layout/arrangement mutations. RuntimeCommand tells
/// a runtime what to DO; PaneAction tells the workspace what to CHANGE.
struct RuntimeCommandEnvelope: Sendable {
    let commandId: UUID                     // idempotency
    let correlationId: UUID?                // links workflow steps
    let targetPaneId: UUID                  // sole routing field on the envelope
    let command: RuntimeCommand
    let timestamp: ContinuousClock.Instant
}

/// ROUTING vs DOMAIN DATA in commands (mirrors outbound envelope rule A1):
///   targetPaneId on RuntimeCommandEnvelope is the SOLE routing identity.
///   Domain data inside command payloads (e.g., DiffArtifact.worktreeId)
///   is NOT routing — it's "which worktree this diff covers."
///
/// COORDINATOR VALIDATION: Before dispatching DiffCommand.loadDiff(artifact),
///   the coordinator MUST validate:
///     artifact.worktreeId == targetRuntime.metadata.worktreeId
///   Mismatch is a contract violation — log and reject, don't silently
///   dispatch a diff to the wrong worktree context.

/// Protocol for per-kind commands. Same pattern as PaneKindEvent:
/// built-in command enums conform AND have dedicated cases.
/// Plugin commands conform and use the `.plugin` escape hatch.
protocol RuntimeKindCommand: Sendable {
    var commandName: String { get }
}

/// What the coordinator can tell any runtime to do.
/// Discriminated union with plugin escape hatch — same pattern as
/// PaneRuntimeEvent.
enum RuntimeCommand: Sendable {
    // Generic lifecycle — all runtimes handle these
    case activate                           // pane became visible/focused
    case deactivate                         // pane hidden/backgrounded
    case prepareForClose                    // begin draining

    // State queries
    case requestSnapshot                    // coordinator wants current state

    // ── First-class per-kind commands ──────────────────
    case terminal(TerminalCommand)
    case browser(BrowserCommand)
    case diff(DiffCommand)
    case editor(EditorCommand)

    // ── Plugin escape hatch ────────────────────────────
    case plugin(any RuntimeKindCommand)
}

enum TerminalCommand: Sendable {
    case sendInput(String)
    case sendKeySequence(KeySequence)
    case resize(cols: Int, rows: Int)
    case scrollTo(ScrollTarget)
    case searchStart(query: String)
    case searchNext
    case searchPrevious
    case searchEnd
    case copySelection
    case paste(String)
    case clearScrollback
    case toggleReadOnly
}

struct KeySequence: Sendable {
    let keys: [KeyPress]
}

struct KeyPress: Sendable {
    let keyCode: UInt16
    let modifiers: UInt
}

enum ScrollTarget: Sendable {
    case top, bottom, pageUp, pageDown
    case lines(Int)                         // positive = down, negative = up
    case toMark(String)
}

enum BrowserCommand: Sendable {
    case navigate(url: URL)
    case goBack
    case goForward
    case reload(hard: Bool)
    case stop
    case executeScript(String)
    case setZoom(Double)
}

enum DiffCommand: Sendable {
    case loadDiff(DiffArtifact)
    case navigateToFile(path: String)
    case navigateToHunk(hunkId: String)
    case approveHunk(hunkId: String)
    case rejectHunk(hunkId: String, reason: String?)
    case approveAll
    case addComment(hunkId: String, lineRange: ClosedRange<Int>, text: String)
    case resolveComment(commentId: UUID)
}

struct DiffArtifact: Sendable {
    let diffId: UUID
    let worktreeId: UUID
    let baseBranch: String
    let headBranch: String
    let patchData: Data                     // unified diff format
}

enum EditorCommand: Sendable {
    case openFile(path: String, line: Int?, column: Int?)
    case goToLine(Int)
    case find(query: String, regex: Bool, caseSensitive: Bool)
    case replaceAll(from: String, to: String)
    case save
    case revert
}
```

#### Command Flow: Coordinator → Runtime

```
USER ACTION (command bar, keyboard, menu)
       │
       ▼
  PaneCoordinator
       │
       ├─► resolve target paneId
       ├─► RuntimeRegistry.runtime(for: paneId)
       ├─► check runtime.lifecycle == .ready
       ├─► check runtime.capabilities ⊇ required
       │
       ▼
  RuntimeCommandEnvelope(commandId, correlationId, targetPaneId, command)
       │
       ▼
  runtime.handleCommand(envelope) async → ActionResult
       │
       ├─► .success(commandId)    → coordinator logs, advances workflow
       ├─► .queued(commandId, n)  → runtime will process in order
       └─► .failure(error)        → coordinator handles error
```

### Contract 11: Runtime Registry

```swift
/// Central paneId → runtime lookup. Owned by PaneCoordinator.
/// Pure lookup — no domain logic, no event processing.
@MainActor
final class RuntimeRegistry {
    private var runtimes: [PaneId: any PaneRuntime] = [:]
    private var kindIndex: [PaneContentType: Set<PaneId>] = [:]

    /// Register a new runtime. Called when pane is created.
    /// Precondition: paneId not already registered.
    func register(_ runtime: any PaneRuntime) {
        precondition(runtimes[runtime.paneId] == nil,
            "Duplicate registration for pane \(runtime.paneId)")
        runtimes[runtime.paneId] = runtime
        kindIndex[runtime.metadata.contentType, default: []]
            .insert(runtime.paneId)
    }

    /// Unregister after shutdown completes. Returns the runtime for cleanup.
    @discardableResult
    func unregister(_ paneId: PaneId) -> (any PaneRuntime)? {
        guard let runtime = runtimes.removeValue(forKey: paneId) else {
            return nil
        }
        kindIndex[runtime.metadata.contentType]?.remove(paneId)
        return runtime
    }

    /// Lookup by paneId. Returns nil if not registered.
    ///
    /// CONTRACT: Coordinator MUST call unregister() when a runtime reaches
    /// .terminated. This means terminated runtimes are never in the map.
    /// The registry does NOT check lifecycle internally — it is a pure
    /// lookup. Lifecycle enforcement is the coordinator's responsibility.
    func runtime(for paneId: PaneId) -> (any PaneRuntime)? {
        runtimes[paneId]
    }

    /// All runtimes of a given content type.
    func runtimes(ofType type: PaneContentType) -> [any PaneRuntime] {
        (kindIndex[type] ?? []).compactMap { runtimes[$0] }
    }

    /// All runtimes in ready state.
    var readyRuntimes: [any PaneRuntime] {
        runtimes.values.filter { $0.lifecycle == .ready }
    }

    /// Shutdown all runtimes. Returns unfinished command IDs across all panes.
    func shutdownAll(timeout: Duration) async -> [PaneId: [UUID]] {
        var unfinished: [PaneId: [UUID]] = [:]
        for (paneId, runtime) in runtimes {
            let ids = await runtime.shutdown(timeout: timeout)
            if !ids.isEmpty { unfinished[paneId] = ids }
        }
        runtimes.removeAll()
        kindIndex.removeAll()
        return unfinished
    }

    var count: Int { runtimes.count }
}
```

#### Cross-Pane Subscription (future extensibility)

The `RuntimeRegistry` + `PaneRuntime.subscribe()` infrastructure makes cross-pane event subscription cheap to add. A future contract could expose:

```swift
/// Subscribe to events from multiple panes matching a predicate.
/// Built on existing RuntimeRegistry lookup + per-runtime subscribe().
func subscribe(matching: @Sendable (PaneMetadata) -> Bool) -> AsyncStream<PaneEventEnvelope>
```

This enables use cases like "show all events from panes in worktree X" or "aggregate agent completion signals across repos." No existing contracts need to change — the subscription merges existing per-runtime streams. Deferred until dynamic view or multi-agent orchestration features require it.

### Contract 12: NotificationReducer

> **Role:** Sink. Consumes `PaneEventEnvelope` from the coordination stream, classifies by priority, and delivers to the coordinator's event loop. Terminal consumer — does not produce events back onto the stream.

```swift
/// Routes events through priority-aware processing.
/// Two completely separate paths — critical and lossy never interact.
///
/// Priority is SELF-CLASSIFIED: each event knows its own ActionPolicy
/// via the PaneKindEvent protocol. The reducer reads event.actionPolicy
/// directly — no centralized classify() method. This means plugin events
/// self-classify without any core code changes.
///
/// Event flow:
///   Runtime.subscribe() → PaneEventEnvelope (runtime produces envelopes)
///     → NotificationReducer.submit(envelope)
///       → reads envelope.event.actionPolicy (self-classifying)
///       → critical path: immediate yield to consumers
///       → lossy path: buffer until next frame, dedup by consolidation key
///     → Coordinator consumes from reducer's output streams
@MainActor
final class NotificationReducer {

    private let clock: any Clock<Duration>

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
        // ... stream initialization
    }

    // ── Critical path ───────────────────────────────────
    // Immediate delivery. Never coalesced. Never dropped.
    // Wakes the coordinator's event loop on every event.
    private let criticalContinuation: AsyncStream<PaneEventEnvelope>.Continuation
    let criticalEvents: AsyncStream<PaneEventEnvelope>

    // ── Lossy path ──────────────────────────────────────
    // Batched on frame boundary (16.67ms at 60fps).
    // Deduped by composite key: "{source}:{consolidationKey}"
    // Latest event for each key wins (overwrites previous in window).
    // Max buffer depth: 1000 entries. Drops oldest on overflow.
    private var lossyBuffer: [String: PaneEventEnvelope] = [:]
    private var frameTimer: Task<Void, Never>?
    private let batchContinuation: AsyncStream<[PaneEventEnvelope]>.Continuation
    let batchedEvents: AsyncStream<[PaneEventEnvelope]>

    /// Submit an envelope for processing.
    /// Priority is read from the event itself — self-classifying.
    /// Works for built-in AND plugin events without modification.
    func submit(_ envelope: PaneEventEnvelope) {
        switch envelope.event.actionPolicy {
        case .critical:
            criticalContinuation.yield(envelope)

        case .lossy(let consolidationKey):
            let key = "\(envelope.source):\(consolidationKey)"
            lossyBuffer[key] = envelope     // latest wins
            if lossyBuffer.count > 1000 {
                if let oldest = lossyBuffer.min(by: {
                    $0.value.timestamp < $1.value.timestamp
                }) {
                    lossyBuffer.removeValue(forKey: oldest.key)
                }
            }
            ensureFrameTimer()
        }
    }

    // ── Frame timer ─────────────────────────────────────
    // Flushes lossy buffer every 16.67ms (one frame at 60fps).
    // One timer shared across all panes. Timer starts on first
    // lossy event, stops when buffer is empty.
    // Uses injectable clock for testability — no hardwired Task.sleep.
    private func ensureFrameTimer() {
        guard frameTimer == nil else { return }
        frameTimer = Task { [weak self] in
            while let self, !self.lossyBuffer.isEmpty {
                try? await self.clock.sleep(for: .milliseconds(16))
                self.flushLossyBuffer()
            }
            self?.frameTimer = nil
        }
    }

    private func flushLossyBuffer() {
        guard !lossyBuffer.isEmpty else { return }
        // Sort by (source, seq) to preserve per-source ordering within batch.
        // Dictionary values have no inherent order — sorting is required to
        // uphold the per-source ordering guarantee from the envelope contract.
        let batch = lossyBuffer.values.sorted { a, b in
            if a.source == b.source { return a.seq < b.seq }
            return a.timestamp < b.timestamp  // cross-source: best-effort
        }
        lossyBuffer.removeAll(keepingCapacity: true)
        batchContinuation.yield(batch)
    }
}
```

#### Where Priority Lives (self-classifying events)

Priority is NOT centralized in the NotificationReducer. Each per-kind event enum implements `actionPolicy` via the `PaneKindEvent` protocol:

```swift
// Built-in: GhosttyEvent knows its own priority
enum GhosttyEvent: PaneKindEvent {
    case commandFinished(exitCode: Int, duration: UInt64)
    case scrollbarChanged(ScrollbarState)
    // ...

    var actionPolicy: ActionPolicy {
        switch self {
        case .commandFinished, .bellRang, .titleChanged, .cwdChanged,
             .newTab, .closeTab /* ... all workspace-facing actions */ :
            return .critical
        case .scrollbarChanged:
            return .lossy(consolidationKey: "scroll")
        case .mouseShapeChanged, .mouseVisibilityChanged, .linkHover:
            return .lossy(consolidationKey: "mouse")
        // ... exhaustive — compiler catches unhandled cases
        }
    }
}

// Plugin: LogViewerEvent knows its own priority too
struct LogViewerEvent: PaneKindEvent {
    enum Kind { case lineAppended, filterChanged, sourceRotated }
    let kind: Kind

    var actionPolicy: ActionPolicy {
        switch kind {
        case .lineAppended:  return .lossy(consolidationKey: "logLine")
        case .filterChanged: return .critical
        case .sourceRotated: return .critical
        }
    }
    // ...
}

// PaneRuntimeEvent delegates to the event (no paneId in cases — lives on envelope):
extension PaneRuntimeEvent {
    var actionPolicy: ActionPolicy {
        switch self {
        case .terminal(let e):      return e.actionPolicy
        case .browser(let e):       return e.actionPolicy
        case .diff(let e):          return e.actionPolicy
        case .editor(let e):        return e.actionPolicy
        case .plugin(_, let e):     return e.actionPolicy  // plugins just work
        case .lifecycle, .filesystem, .artifact, .security, .error:
            return .critical
        }
    }
}
```

#### Coordinator Event Loop (how it connects)

```
┌──────────────────────────────────────────────────────────┐
│ PaneCoordinator event consumption loop                    │
│                                                          │
│  for runtime in registry.readyRuntimes {                 │
│    Task {                                                │
│      for await envelope in runtime.subscribe() {         │
│        // Runtime produces envelopes directly — no       │
│        // wrapping step. source/seq/paneKind set by      │
│        // the runtime.                                   │
│        reducer.submit(envelope)  // self-classifying     │
│        replayBuffer[runtime.paneId].append(envelope)     │
│      }                                                   │
│    }                                                     │
│  }                                                       │
│                                                          │
│  // Critical consumer — handles immediately              │
│  // .userInitiated ensures critical events are resumed   │
│  // before lossy batches when both have pending work on  │
│  // the MainActor scheduler.                             │
│  Task(priority: .userInitiated) {                        │
│    for await envelope in reducer.criticalEvents {        │
│      routeToConsumers(envelope)                          │
│      workflowTracker.processEvent(envelope)              │
│    }                                                     │
│  }                                                       │
│                                                          │
│  // Lossy consumer — handles batched per frame           │
│  // .utility ensures lossy batches yield to critical     │
│  // events under MainActor contention.                   │
│  Task(priority: .utility) {                              │
│    for await batch in reducer.batchedEvents {            │
│      for envelope in batch {                             │
│        routeToConsumers(envelope)                        │
│      }                                                   │
│    }                                                     │
│  }                                                       │
└──────────────────────────────────────────────────────────┘
```

### Contract 12a: Visibility-Tier Scheduling (LUNA-295)

Visibility-tier scheduling is the **delivery scheduling** axis — orthogonal to event classification (critical/lossy from D6). Classification determines *how* an event is processed (immediate vs batched). Visibility tiers determine *which pane's events are processed first* when multiple events arrive in the same processing window.

#### Tier Definitions

```swift
/// Visibility tier determines delivery priority within the critical queue.
/// When multiple critical events arrive in the same processing cycle,
/// the coordinator processes them in tier order (p0 first, p3 last).
///
/// Tier assignment is based on pane visibility state at the time the
/// event is submitted to the NotificationReducer, NOT at event creation.
/// This means a pane that becomes visible between event creation and
/// submission gets the correct (higher) tier.
enum VisibilityTier: Int, Comparable, Sendable {
    case p0ActivePane = 0       // active pane in active tab → immediate
    case p1ActiveDrawer = 1     // active pane's drawer panes → next
    case p2VisibleActiveTab = 2 // other visible panes in active tab → after p1
    case p3Background = 3       // hidden/background panes → bounded concurrency

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
```

#### Tier Resolution

```swift
/// Tier assignment is a coordinator responsibility. The coordinator
/// knows the active tab, the active pane within that tab, and which
/// panes are in the active pane's drawer.
///
/// The reducer calls back to a tier resolver — it does not read
/// workspace state directly. This keeps the reducer testable without
/// a full workspace stack.
///
/// Contract:
///   1. Resolver MUST return a valid tier for any paneId. Unknown
///      paneIds default to .p3Background (safe: delayed, never lost).
///   2. Resolver reads workspace state at call time — tier can change
///      between events for the same pane (e.g., user switches tabs).
///   3. The resolver is injected into the NotificationReducer at
///      construction time.
protocol VisibilityTierResolver: Sendable {
    @MainActor func tier(for paneId: PaneId) -> VisibilityTier
}
```

#### Scheduling Behavior

| Tier | Critical Events | Lossy Events |
|------|----------------|--------------|
| `p0ActivePane` | Immediate delivery, processed first | Batched at frame rate, flushed first |
| `p1ActiveDrawer` | Immediate delivery, processed after p0 | Batched at frame rate, flushed after p0 |
| `p2VisibleActiveTab` | Immediate delivery, processed after p1 | Batched at frame rate, flushed after p1 |
| `p3Background` | Immediate delivery, processed after p2 | Batched at frame rate, flushed last. Bounded concurrency: max N background panes processed per frame cycle |

#### Integration with NotificationReducer

```swift
/// Extended submit() with visibility tier.
/// Tier is resolved at submission time from the pane's current
/// visibility state, not at event creation time.
///
/// Within each tier, ordering follows existing rules:
///   - Critical: per-source seq order (A4)
///   - Lossy: per-source seq within batch, cross-source by timestamp (A6)
///
/// This is ADDITIVE — the NotificationReducer gains a tierResolver
/// parameter and sorts output by tier. No existing contracts change.
func submit(_ envelope: PaneEventEnvelope) {
    let paneId = envelope.source.paneId  // nil for system events → p0
    let tier = paneId.map { tierResolver.tier(for: $0) } ?? .p0ActivePane

    switch envelope.event.actionPolicy {
    case .critical:
        criticalQueue.insert(envelope, at: tier)
        // yield in tier order on next processing cycle

    case .lossy(let consolidationKey):
        let key = "\(tier.rawValue):\(envelope.source):\(consolidationKey)"
        lossyBuffer[key] = (envelope, tier)
        ensureFrameTimer()
    }
}
```

#### Visibility-Tier Invariants

1. **Tier assignment is ephemeral.** Tiers are not stored on the envelope. They are resolved at submission time and used for ordering within the reducer's internal queues. A pane's tier can change between events (user switches tabs).
2. **System events are always p0.** Events with `source = .system(...)` have no paneId and default to `p0ActivePane`. System events are never deprioritized.
3. **Tier ordering does not affect classification.** A p3 critical event is still processed immediately — it just goes after p0/p1/p2 critical events in the same cycle. Classification (critical/lossy) and scheduling (visibility tier) are independent axes.
4. **Background bounded concurrency.** `p3Background` lossy events are rate-limited: at most N panes' worth of lossy events are flushed per frame cycle (N configurable, default 3). This prevents 20 background terminals from dominating frame budget.
5. **Unknown paneId defaults to p3.** If the resolver cannot find a paneId (pane closing, race condition), it returns `.p3Background`. Events are delayed, never dropped.

### Contract 13: Workflow Engine (deferred)

> Deferred workflow planning now lives in
> [Pane Runtime Ticket Mapping (Minimal)](../plans/2026-02-21-pane-runtime-luna-295-luna-325-mapping.md#deferred-workflow-engine).
>
> Tracks temporal workflows spanning multiple panes and events ("agent finishes → create diff → user approves → signal next agent"). Owned by PaneCoordinator. Implementation deferred until multi-agent orchestration (JTBD 6) moves to automated cross-agent handoffs.
>
> Key types: `WorkflowTracker`, `WorkflowStep`, `StepPredicate`, `WorkflowAdvance`. Integration points: `PaneEventEnvelope.correlationId`, `PaneKindEvent.eventName` for step matching, `EventReplayBuffer` for restart recovery.

### Contract 14: Replay Buffer

> **Role:** Sink. Consumes `PaneEventEnvelope` from the coordination stream and stores them in a bounded ring buffer for late-joining consumers. Terminal consumer — does not produce events back onto the stream.
>
> **Current Code Status (LUNA-342 branch):**
> - `EventReplayBuffer` now includes `Config` (`maxEvents`, `maxBytes`, `ttl`), `ReplayResult`, stale eviction, and gap detection.
> - `PaneRuntime.eventsSince(seq:)` is wired and used by runtime implementations.

```swift
/// Bounded event ring buffer per EventSource for late-joining consumers.
/// Used when: dynamic view opens (needs current state of all panes),
/// drawer expands (needs parent pane context), tab switches (catch up
/// on background events).
///
/// NOT a persistence mechanism — events are ephemeral.
/// Coordinator maintains one buffer per EventSource key:
///   .pane(id), .worktree(id), and relevant .system(...) producers.
@MainActor
final class EventReplayBuffer {

    struct Config: Sendable {
        let maxEvents: Int          // default: 1000
        let maxBytes: Int           // default: 1MB (1_048_576)
        let ttl: Duration           // default: 5 minutes
    }

    private var ring: [PaneEventEnvelope?]
    private var head: Int = 0
    private var count: Int = 0
    private var estimatedBytes: Int = 0
    private let config: Config
    private let clock: ContinuousClock

    /// Append event. Evicts oldest if capacity/bytes exceeded.
    func append(_ envelope: PaneEventEnvelope) {
        // Evict if at capacity
        if count >= config.maxEvents {
            evictOldest()
        }
        // Evict if bytes exceeded. Per-envelope size estimated by the
        // runtime at creation — not a fixed constant. Artifact/security
        // events carry larger payloads than viewport telemetry.
        let envelopeSize = Self.estimateSize(envelope)
        while estimatedBytes + envelopeSize > config.maxBytes, count > 0 {
            evictOldest()
        }
        ring[head] = envelope
        head = (head + 1) % ring.count
        count += 1
        estimatedBytes += envelopeSize
    }

    /// Replay events since a given sequence number.
    /// Returns:
    ///   events — ordered events with seq > requested seq
    ///   nextSeq — sequence number to pass on next call
    ///   gapDetected — true if requested seq was evicted (caller missed events)
    func eventsSince(seq: UInt64) -> ReplayResult {
        let available = orderedEvents()
        guard let first = available.first else {
            return ReplayResult(events: [], nextSeq: seq, gapDetected: false)
        }
        let nextExpected = seq == .max ? .max : seq + 1
        let gapDetected = nextExpected < first.seq
        let matching = available.filter { $0.seq > seq }
        let nextSeq = matching.last?.seq ?? seq
        return ReplayResult(events: matching, nextSeq: nextSeq, gapDetected: gapDetected)
    }

    struct ReplayResult: Sendable {
        let events: [PaneEventEnvelope]
        let nextSeq: UInt64
        let gapDetected: Bool       // true = caller missed events, use snapshot instead
    }

    /// CONSUMER CATCH-UP PROTOCOL:
    ///   1. Consumer calls snapshot() → gets PaneRuntimeSnapshot with lastSeq
    ///   2. Consumer calls eventsSince(snapshot.lastSeq)
    ///   3. If result.gapDetected == true:
    ///      → snapshot.lastSeq < buffer.oldestSeq → consumer missed events
    ///      → consumer MUST call snapshot() again for a fresh baseline
    ///      → do NOT attempt replay from the gap — state may be inconsistent
    ///   4. If result.gapDetected == false:
    ///      → events array is the complete catch-up set
    ///      → consumer uses result.nextSeq for subsequent calls

    /// Evict events older than TTL.
    func evictStale(now: ContinuousClock.Instant) { ... }

    /// Stats for diagnostics.
    var stats: BufferStats {
        BufferStats(eventCount: count, estimatedBytes: estimatedBytes,
                    oldestSeq: orderedEvents().first?.seq,
                    newestSeq: orderedEvents().last?.seq)
    }

    struct BufferStats: Sendable {
        let eventCount: Int
        let estimatedBytes: Int
        let oldestSeq: UInt64?
        let newestSeq: UInt64?
    }

    private func evictOldest() { ... }
    private func orderedEvents() -> [PaneEventEnvelope] { ... }
}
```

#### Late-Joining Consumer Flow

```
Dynamic view opens (e.g., "group by worktree")
       │
       ▼
  PaneCoordinator
       │
       ├─► For each pane in target worktree:
       │     runtime = registry.runtime(for: paneId)
       │     snapshot = runtime.snapshot()                 ← current state
       │     result = runtime.eventsSince(seq: 0)         ← returns ReplayResult
       │
       │     if result.gapDetected:
       │       // too old, just use snapshot (no replay)
       │       render from snapshot only
       │     else:
       │       // apply snapshot + replay envelopes
       │       render snapshot, then apply result.events   ← envelopes, not raw events
       │
       └─► runtime.subscribe() → live envelopes going forward
```

### Contract 15: Terminal Process Request/Response Channel (deferred)

> **Role:** Source. Produces `TerminalProcessEvent` on the coordination stream with `source = .pane(id)`. Milestone events only — actual request/response payloads travel on dedicated envelopes, not the coordination stream.

> **Extensibility:** This contract is the ingress point for agent-originated structured commands. Agent-specific protocols (Claude Code hooks, Codex CLI hooks, aider callbacks) are translated into typed `TerminalProcessRequestEnvelope` by **plugin adapters** — one adapter per agent protocol. Core Agent Studio never imports agent-specific formats. The plugin does the translation; this contract provides the typed pipe. Adding a new agent protocol means writing a new plugin adapter, not changing core contracts. See the Agent Harness Communication Model below for the adapter architecture.

> **Status:** Design intent only. Implementation deferred until agent coordination features (JTBD 3, JTBD 6) move beyond basic terminal usage.

This is NOT PTY/raw output. It is a typed request/response channel for agent↔harness coordination — structured commands sent by agents (via MCP or CLI) to Agent Studio, with structured responses back.

```swift
/// Coordination stream carries process milestones only.
/// Adds one case to PaneRuntimeEvent:
///   case terminalProcess(TerminalProcessEvent)
///
/// The coordination stream is NOT for bulk payload transport.
/// It carries: "request accepted," "response completed," "request failed,"
/// "process state changed." Actual data payloads travel on the
/// request/response envelopes below.
enum TerminalProcessEvent: PaneKindEvent {
    case requestAccepted(processSessionId: UUID, requestId: UUID,
                         operation: ProcessOperation)
    case responseCompleted(processSessionId: UUID, requestId: UUID,
                           status: ProcessStatus)
    case requestFailed(processSessionId: UUID, requestId: UUID,
                       reason: String)
    case processStateChanged(processSessionId: UUID,
                             state: ProcessLifecycleState)

    var actionPolicy: ActionPolicy { .critical }
    var eventName: EventIdentifier {
        switch self {
        case .requestAccepted:    return .init("process.requestAccepted")
        case .responseCompleted:  return .init("process.responseCompleted")
        case .requestFailed:      return .init("process.requestFailed")
        case .processStateChanged: return .init("process.stateChanged")
        }
    }
}

/// Inbound: agent → Agent Studio. Typed request envelope.
struct TerminalProcessRequestEnvelope: Sendable {
    let paneId: PaneId
    let processSessionId: UUID
    let requestId: UUID               // idempotency key
    let correlationId: UUID?
    let origin: ProcessOrigin         // which agent/tool produced this request
    let operation: ProcessOperation
    let cwd: URL?
    let timestamp: ContinuousClock.Instant
}

/// Identifies the agent or tool that produced a request.
/// String-based, not an enum — new agent protocols are additive.
/// The core never switches on provider values; plugins set them,
/// and the value flows through for logging, UI display, and
/// workflow correlation.
///
/// Convention: "claude-code", "codex", "aider", "cursor-cli",
/// or plugin-defined values like "custom-agent-v2".
struct ProcessOrigin: Hashable, Sendable {
    let provider: String              // agent protocol identifier
    let version: String?              // optional agent version
    init(provider: String, version: String? = nil) {
        self.provider = provider
        self.version = version
    }
}

/// Outbound: Agent Studio → agent. Typed response envelope.
struct TerminalProcessResponseEnvelope: Sendable {
    let paneId: PaneId
    let processSessionId: UUID
    let requestId: UUID               // matches request
    let success: Bool
    let result: ProcessResultPayload
    let timestamp: ContinuousClock.Instant
}
```

#### Contract 15 Invariants

1. **Request/response keyed by `requestId`, idempotent.** Duplicate requestIds return the cached response, not re-execution.
2. **Ordering guarantee is per `processSessionId`.** Within a process session, requests are processed in order. Cross-session ordering is best-effort.
3. **No PTY/raw output on this channel.** This is structured RPC, not terminal I/O.
4. **Core coordination stream carries milestones, not bulk payloads.** Data travels on request/response envelopes; the PaneRuntimeEvent stream gets milestone notifications only.

#### Agent Harness Communication Model (design intent)

The terminal process channel is the foundation for a broader agent harness architecture:

```
Agent (MCP client / CLI)
        │
        ▼
Harness Adapter Layer
(MCP server adapter, CLI adapter)
        │
        ▼
Single Harness Command Bus (typed JSON-RPC)
        │
        ▼
Agent Studio Command Gateway
(authz, scope checks, idempotency)
        │
        ▼
PaneCoordinator / WorkflowTracker / Stores
        │
        ▼
PaneRuntimeEvent stream → Harness Event Gateway → adapters → agent
```

**One core protocol, two adapters:**
- **CLI adapter** — fast, local, scriptable. For direct agent-to-harness communication.
- **MCP adapter** — tool-friendly for LLM agents. Exposes Agent Studio operations as MCP tools.
- Both map to the same internal command/event contracts.

**Plugin-as-adapter model:** Each agent protocol (Claude Code hooks, Codex CLI notifications, aider callbacks) gets a **plugin adapter** that translates agent-specific formats into typed `TerminalProcessRequestEnvelope` with a `ProcessOrigin` identifying the agent. Core Agent Studio is agent-agnostic — it never imports agent-specific hook formats. Plugins do the translation. This means supporting a new agent is a plugin change, not a core change.

**Use cases:** Work tracker with dependencies and sub-projects, agent status queries, cross-agent coordination, project state management. Agents interact with Agent Studio as a structured workspace, not just a terminal host.

### Contract 16: Pane Filesystem Context Stream (deferred)

> **Role:** Projection of Contract 6 (Filesystem Batching). Derives per-pane filesystem events by filtering the worktree watcher's output to the pane's current CWD subtree. Depends on Contract 6 as its upstream source — cannot exist without it.

> **Extensibility:** New per-pane derived streams (e.g., "pane git blame context", "pane dependency graph") follow the same projection pattern: filter an upstream source by pane-scoped criteria, expose a typed subscription. Adding a new projection does not change the upstream source or existing projections.

> **Status:** Design intent only. Implementation deferred until per-pane filesystem awareness features are built.

A derived, per-pane filesystem context stream based on the pane's current CWD. Separate from the terminal process request/response channel.

```swift
/// Per-pane filesystem context — derived from worktree watcher + pane CWD.
///
/// DESIGN PRINCIPLES:
///   1. One watcher per worktree/root (not per pane). Shared infrastructure.
///   2. Per-pane stream is a FILTERED VIEW of the worktree watcher,
///      scoped to the pane's current CWD subtree.
///   3. When pane CWD changes, the filter re-scopes automatically.
///   4. Batched events only (no per-file spam). Uses Contract 6 batching.
///   5. This is SEPARATE from terminal process request/response (Contract 15).
///
/// Relationship to existing contracts:
///   - Contract 6 (Filesystem Batching) provides the raw worktree-level batches
///   - Contract 16 derives per-pane views from those batches
///   - FilesystemEvent on the coordination stream is the worktree-level signal
///   - PaneFilesystemContext is the pane-level derived stream
struct PaneFilesystemContext: Sendable {
    let paneId: PaneId
    let cwd: URL                         // pane's current CWD
    let worktreeId: WorktreeId           // which worktree watcher provides data
}

/// Derived per-pane filesystem events — filtered from worktree watcher.
/// Only includes changes within the pane's CWD subtree.
enum PaneFilesystemContextEvent: PaneKindEvent {
    case cwdSubtreeChanged(paths: Set<String>, batchSeq: UInt64)
    case gitStatusInCwd(staged: Int, unstaged: Int, untracked: Int)

    var actionPolicy: ActionPolicy { .critical }
    var eventName: EventIdentifier {
        switch self {
        case .cwdSubtreeChanged: return .init("fs.cwdSubtreeChanged")
        case .gitStatusInCwd:    return .init("fs.gitStatusInCwd")
        }
    }
}
```

#### Contract 16 Invariants

1. **Filesystem context stream is derived, never primary.** Source of truth is the worktree watcher (Contract 6). Per-pane context is a filtered projection.
2. **One watcher per worktree, not per pane.** Multiple panes in the same worktree share the same watcher. Per-pane filtering happens at the stream level.
3. **CWD change re-scopes the filter.** When a pane's CWD changes (from CWD propagation), its filesystem context stream automatically re-filters.
4. **Batched events only.** Inherits Contract 6 batching (500ms debounce, 2s max latency). No per-file spam on the per-pane stream.

---

## Event Priority Classification

| Source | Category | Events | Priority | Consolidation |
|--------|----------|--------|----------|---------------|
| **All** | **Lifecycle** | surfaceCreated, attachSucceeded, attachFailed, paneClosed, tabSwitched, activePaneChanged | `critical` | never |
| **Terminal** | **Control** | commandFinished, bellRang, desktopNotification, progressReport, childExited, closeSurface | `critical` | never |
| **Terminal** | **Tab/Split** | newTab, closeTab, gotoTab, moveTab, newSplit, gotoSplit, resizeSplit | `critical` | never |
| **Terminal** | **Metadata** | titleChanged, cwdChanged | `critical` | never |
| **Terminal** | **Config** | configReload, configChanged, colorChanged, secureInput | `critical` | never |
| **Terminal** | **Viewport** | scrollbarChanged, cellSize, sizeLimits, initialSize | `lossy` | key: `scroll`, `size` |
| **Terminal** | **Search** | searchStarted, searchEnded, searchTotal, searchSelected | `lossy` | key: `search` |
| **Terminal** | **Mouse** | mouseShapeChanged, mouseVisibilityChanged, linkHover | `lossy` | key: `mouse` |
| **Terminal** | **Renderer** | rendererHealth | `lossy` | key: `health` |
| **Terminal** | **Input** | keySequence, keyTable, readOnly | `lossy` | key: `input` |
| **Browser** | **Navigation** | navigationStarted/Completed/Failed, urlChanged, titleChanged, pageLoaded/Unloaded, linkClicked, downloadRequested, dialog* | `critical` | never |
| **Browser** | **Console** | consoleMessage, consoleCleared | `lossy` | key: `console` |
| **Browser** | **Layout** | contentSizeChanged | `lossy` | key: `contentSize` |
| **Diff** | **Review** | hunkApproved/Rejected, fileApproved, allApproved/Rejected, comment*, diffLoaded/Updated/Closed | `critical` | never |
| **Diff** | **Navigation** | fileSelected, hunkNavigated, fileListScrolled | `lossy` | key: `diffNav` |
| **Editor** | **File ops** | contentSaved, contentReverted, fileOpened/Closed, languageDetected, diagnostics* | `critical` | never |
| **Editor** | **Cursor** | cursorMoved, selectionChanged, visibleRangeChanged | `lossy` | key: `cursor` |
| **Editor** | **Edits** | contentModified | `lossy` | key: `edit` |
| **Cross** | **Filesystem** | filesChanged, gitStatusChanged, diffAvailable, branchChanged | `critical` | pre-batched by watcher |
| **Cross** | **Artifacts** | diffProduced, prCreated, approvalRequested, approvalDecided | `critical` | never |
| **Cross** | **Security** | all SecurityEvent cases | `critical` | never |
| **Cross** | **Errors** | all RuntimeErrorEvent cases | `critical` | never |

---

## Sharp Edges & Mitigations

### 1. Global stream as choke point

**Risk:** One AsyncStream for all events can become a bottleneck with 10+ active terminals.

**Mitigation:** Ordering is per-source (`seq` field on envelope, monotonic within each `EventSource`), not one total global sequence. The stream is a merge of per-runtime streams. No global sequence number means no global serialization. Per-source ordering is the guarantee; cross-source ordering uses `timestamp` for best-effort. This is sufficient for UI rendering and workflow matching but not for strict causal ordering across panes.

### 2. Priority inversion in batching

**Risk:** High-frequency lossy events block critical events in the same coalesce window.

**Mitigation:** Hard rule: critical events bypass the coalescing path entirely. The `NotificationReducer` maintains two separate queues. Critical events emit immediately and wake the main loop. Lossy events batch until next frame. These paths never interact.

### 3. Event storm from filesystem watchers

**Risk:** Agent writes 500 files → FSEvents fires 500+ raw events → git status recomputes 500 times.

**Mitigation:** Worktree-scoped debounce (500ms settle window) + deduped path set + max batch size (500 paths) + max latency cap (2 seconds). Git status/diff recompute only after batch flush. Multiple worktrees have independent watchers — one noisy worktree doesn't delay another.

### 4. Replay buffer memory growth

**Risk:** Ring buffer per runtime accumulates unbounded memory if events are large or frequent.

**Mitigation:** Bounded ring buffer per `EventSource` key (`.pane`, `.worktree`, `.system`). Each source gets a 1000-event ring buffer with TTL (5 minutes) and max bytes cap (1MB). Oldest events evicted first. One noisy source doesn't starve replay for others.

### 5. Lifecycle leaks for background panes

**Risk:** Background pane closes but runtime keeps producing events, leaking resources.

**Mitigation:** Explicit lifecycle contract: `created → ready → draining → terminated`. `shutdown(timeout:)` drains in-flight commands (max 5 seconds), closes all event stream continuations, releases C API handles, and returns unfinished command IDs. Coordinator logs any unfinished commands. After `terminated`, the runtime rejects all interactions.

### 6. Idempotency gaps on temporal workflows

**Risk:** Coordinator restarts mid-workflow (crash, suspension). "Agent finished → create diff → wait for approval" loses its place.

**Mitigation:** Every workflow step carries `commandId` (idempotent per-step) and `correlationId` (links the full workflow chain). Coordinator can detect completed steps via commandId on replay.

**Limitation (v1):** Restart-safe replay requires `epoch` to distinguish "caught up in current runtime" from "new runtime, seq reset." Since `epoch` is `0` in v1, `eventsSince(seq:)` after a runtime restart may return events from the new epoch with overlapping seq numbers. **Consumers must use `snapshot()` after runtime restart, not `eventsSince()`.** True restart-safe replay requires activating epoch (see Sharp Edge #7).

### 7. Epoch field deferred but reserved

**Risk:** Adding `epoch` later requires protocol changes and migration.

**Mitigation:** `epoch` field is in the envelope now, set to `0`. Zero cost to carry. When activated, epoch increments on runtime restart/reconnect, enabling stale-view detection and safe seq comparison across restarts.

**v1 constraint:** With `epoch == 0`, `eventsSince(seq:)` is NOT safe across runtime restarts — seq resets but epoch doesn't increment, so the consumer can't detect the reset. **After runtime restart, consumers must call `snapshot()` to re-sync, not `eventsSince()`.** This is documented in Sharp Edge #6 and the Architectural Invariants (A9).

### 8. Execution backend lifecycle mismatch

**Risk:** Sandbox (Gondolin/Docker) starts before the runtime is ready, or crashes while the runtime is still producing events.

**Mitigation:** Execution backend lifecycle is independent of pane runtime lifecycle. The sandbox starts and becomes healthy before the runtime transitions to `ready`. If the sandbox dies, a `SecurityEvent.sandboxHealthChanged(healthy: false)` fires, and the coordinator can either restart the sandbox or transition the runtime to `draining`. The pane's `PaneMetadata.executionBackend` is immutable after creation — to change backends, close the pane and create a new one. Live backend migration is a future capability (no SecurityEvent case exists for it yet).

### 9. Bus becoming a god object

**Risk:** Event bus accumulates routing logic, filtering, batching, domain decisions, workflow branching.

**Mitigation:** Bus only routes, filters, and batches. It never makes domain decisions. Workflow logic lives in the coordinator. Domain logic lives in runtimes. The bus is infrastructure — a typed `AsyncStream` with merge, filter, and throttle operators from `swift-async-algorithms`. If the bus grows methods that aren't pure stream operations, it's doing too much.

---

## Migration: NotificationCenter/DispatchQueue → AsyncStream/Event Bus

The current codebase uses `NotificationCenter` and `DispatchQueue.main.async` for Ghostty C callback dispatch. This architecture replaces those mechanisms. This section documents the migration path — what changes, what stays, and what order.

### What Gets Replaced

| Current Mechanism | Replacement | Migrated By |
|---|---|---|
| `NotificationCenter.default.post(name: .ghosttyAction, ...)` | `GhosttyAdapter` → typed `GhosttyEvent` → `TerminalRuntime.handleEvent()` | LUNA-325 |
| `DispatchQueue.main.async { ... }` in C callback trampolines | `Task { @MainActor in ... }` or direct `@MainActor` calls | LUNA-342 (partial — wakeup_cb, initialize), LUNA-325 (remaining 23 instances) |
| `@objc` notification observers in `PaneCoordinator` | `for await envelope in runtime.subscribe()` in coordinator event loop | LUNA-325 |
| `userInfo` dictionaries on notifications | Typed `GhosttyEvent` enum cases with associated values | LUNA-325 |
| String-keyed notification names (`.ghosttyTitleChanged`, etc.) | Exhaustive `GhosttyEvent` enum switch (compile-time coverage) | LUNA-325 |

### What Stays (Not Migrated)

| Mechanism | Why It Stays |
|---|---|
| `NSApplication.shared` notifications (`.willTerminate`, etc.) | AppKit lifecycle — not event bus material |
| `NSWorkspace.shared.notificationCenter` (volume mount, screen changes) | System-level notifications — no benefit from typed events |
| Any Combine usage in third-party dependencies | Out of our control |

### Migration Order

1. **LUNA-327 (done):** `@Observable` migration, `private(set)` stores, `PaneCoordinator` consolidation. Foundation for the event bus. `DispatchQueue.main.async` → `MainActor` primitives where touched.
2. **LUNA-342 (done):** Contract freeze + Swift 6 language mode migration. `.swiftLanguageMode(.v6)` enforced, all `isolated deinit` migrations complete, `MainActor.assumeIsolated` removed from Sources, C callback trampolines partially migrated (`wakeup_cb` done), existential Sendable constraints added. SwiftLint concurrency rules added (44 violations marking LUNA-325 scope). See [migration spec](../plans/2026-02-22-swift6-language-mode-migration.md) and [mapping doc](../plans/2026-02-21-pane-runtime-luna-295-luna-325-mapping.md#luna-342-implementation-record) for details.
3. **LUNA-325 (next):** Build `GhosttyAdapter`, `TerminalRuntime`, `RuntimeRegistry`, `NotificationReducer`. Replace `NotificationCenter`-based dispatch with typed event stream. Resolve remaining 44 SwiftLint concurrency violations (23 DispatchQueue, 20 NotificationCenter selector, 1 Task.detached). This is the primary migration ticket.
4. **LUNA-295 (attach orchestration):** Build attach readiness policies and visibility-tier scheduling. Consumes the event stream infrastructure from LUNA-325.
5. **LUNA-324 (restart reconcile):** Build startup reconcile classification, orphan TTL cleanup, and post-restore health monitoring (Contract 5b).

### Migration Invariant

**No dual-path period.** When a notification is migrated to the event bus, the `NotificationCenter.post()` call is deleted in the same commit. There is no compatibility shim where both paths fire. This means the migration is per-action (one `GhosttyEvent` case at a time), not big-bang. But each individual action migrates atomically — old path removed, new path added, in one commit.

---

## Architectural Invariants

Structural guarantees that hold across all contracts. Each invariant is enforced at a specific layer and has a defined violation response. These are the rules implementation MUST uphold — not aspirational guidelines.

### Identity & Routing

**A1. Routing identity lives on the envelope, never in event payloads.** `EventSource` on `PaneEventEnvelope` is the single source of truth for "who produced this event." Event payloads carry domain data only (e.g., `ArtifactEvent.worktreeId` = "where the artifact belongs," not "who produced it"). If routing identity and domain data happen to match (e.g., `FileChangeset.worktreeId` == `envelope.source.worktreeId`), the envelope is authoritative on any divergence.

*Enforced by:* Code review + contract tests asserting no `paneId`/`worktreeId` routing fields in event enum cases.

**A2. One runtime instance per pane. One adapter instance per backend technology.** `RuntimeRegistry` enforces uniqueness via `precondition` on `register()`. Adapters (`GhosttyAdapter`, `WebKitAdapter`) are shared singletons that route by surface/webview ID to the correct runtime instance. No pane ever has two runtimes; no runtime ever serves two panes.

*Enforced by:* `RuntimeRegistry.register()` precondition. Violation = fatal assertion (programmer error).

**A3. RuntimeRegistry is the sole lookup for paneId → runtime.** No parallel maps, no caching of runtime references outside the registry. Coordinator, event bus, and all consumers go through `RuntimeRegistry.runtime(for:)`. Terminated runtimes are removed via `unregister()` — the registry never contains terminated entries.

*Enforced by:* `unregister()` called by coordinator as part of the termination sequence. Violation = leaked runtime (detected by periodic registry audit in debug builds).

### Ordering & Sequencing

**A4. `seq` is monotonic per `EventSource`.** Each runtime (or system producer) is the sole writer of its own sequence counter. `seq` values are strictly increasing within a single `EventSource`. Gaps are allowed only due to replay buffer eviction.

*Enforced by:* Runtime produces envelopes with `seq` from its own counter. No external code writes `seq`.

**A5. Cross-source ordering is best-effort via `timestamp`.** No global sequence number exists. Cross-source ordering uses `ContinuousClock.Instant` timestamps. This is sufficient for UI rendering and workflow matching but NOT for strict causal ordering across panes.

*Enforced by:* Design decision (D2). No global sequence counter to maintain.

**A6. Lossy batch ordering preserves per-source order.** When `NotificationReducer` flushes the lossy buffer, events are sorted by `(source, seq)` within the batch. Cross-source ordering within a batch uses timestamps (best-effort).

*Enforced by:* `flushLossyBuffer()` sorts before yielding. Unit tests verify per-source ordering in batched output.

### Classification & Priority

**A7. Self-classifying priority — single classification authority per event.** Each per-kind event enum implements `actionPolicy` via `PaneKindEvent` conformance. `NotificationReducer` reads `envelope.event.actionPolicy` — no centralized `classify()` method, no priority field cached on the envelope. Plugin events self-classify without core code changes.

*Enforced by:* `PaneKindEvent` protocol requirement. Compile error if `actionPolicy` is missing.

**A8. Critical and lossy paths never interact.** Critical events bypass coalescing entirely (immediate delivery, wake main loop). Lossy events batch on frame boundary (16.67ms). The `NotificationReducer` maintains two separate queues. No priority inversion is possible between these paths. The coordinator's critical consumer Task runs at `.userInitiated` priority; the lossy consumer runs at `.utility`. This ensures the MainActor scheduler resumes critical event processing before lossy batch processing when both have pending work.

*Enforced by:* `submit()` branches on `actionPolicy` at the top level. No shared buffer between paths. Task priority annotations on coordinator event loop consumers.

### Replay & Recovery

**A9. `eventsSince(seq:)` is NOT safe across runtime restarts in v1.** With `epoch == 0`, a runtime restart resets `seq` but epoch doesn't increment. Consumers cannot distinguish "caught up in current runtime" from "new epoch." **After runtime restart, consumers MUST call `snapshot()` to re-sync.** True restart-safe replay requires activating the epoch field (future).

*Enforced by:* Documentation. Implementation will add `precondition(epoch > 0)` guard when epoch is activated.

**A10. Replay buffer is bounded per `EventSource`.** Each source gets its own ring buffer (default: 1000 events, 1MB, 5-minute TTL). One noisy source cannot starve replay for others. Eviction is oldest-first. Gap detection via `ReplayResult.gapDetected` tells the consumer to fall back to `snapshot()`.

*Enforced by:* `EventReplayBuffer.Config` bounds. Buffer constructor validates config.

### Lifecycle

**A11. Lifecycle transitions are forward-only.** `created → ready → draining → terminated`. No backward transitions. No skipping states. `handleCommand()` rejects commands if `lifecycle != .ready`. After `terminated`, no events emitted, no commands accepted, runtime is unregistered from `RuntimeRegistry`.

*Enforced by:* `PaneRuntimeLifecycle` state machine with compile-time transition validation. Violation = `.failure(.runtimeNotReady)`.

**A12. `shutdown(timeout:)` is idempotent.** Safe to call multiple times. First call initiates draining. Subsequent calls are no-ops that return the same unfinished command list.

*Enforced by:* Guard on lifecycle state in `shutdown()` implementation.

### Metadata & Dynamic Views

**A13. PaneMetadata live fields are ALL OPTIONAL.** `repoId`, `worktreeId`, `parentFolder`, `cwd`, `agentType`, `tags` — each can be `nil` independently. Not every pane participates in every dynamic view grouping dimension. A `nil` value excludes the pane from that grouping. This is intentional, not a missing-data bug.

*Enforced by:* All live fields typed as optionals (`UUID?`, `URL?`, `String?`, `AgentType?`, `Set<String>` defaults empty). Dynamic view projector handles nil gracefully — nil means "excluded from this facet."

**A14. `PaneMetadata.executionBackend` is immutable after creation.** To change backends, close the pane and create a new one. Live migration is a future capability with no current SecurityEvent case.

*Enforced by:* `let executionBackend` (immutable). Compile error on mutation attempt.

### Event Scoping

**A15. Source/payload compatibility is a contract invariant.** Pane-scoped payloads (`.terminal`, `.browser`, `.diff`, `.editor`, `.plugin`) require `source = .pane(id)`. Filesystem/security payloads require `source = .worktree(id)`. Workspace lifecycle events not pane-scoped require `source = .system(.coordinator)`. Invalid combinations are contract violations — runtime emits `RuntimeErrorEvent` rather than silently misrouting.

*Enforced by:* Envelope invariant #3 and #4 (Contract 3). Validated at envelope creation in runtime.

---

## Swift 6 Type and Concurrency Invariants

Hard rules for all types in this architecture. Violations are compile errors, not style preferences.

1. **All cross-boundary payloads are `Sendable`.** Every struct, enum, and protocol in the event/action/envelope pipeline conforms to `Sendable`. No bare `Error` — use `any Error & Sendable` or serialize to typed payloads (see `RuntimeErrorEvent.underlyingDescription`).

2. **No stringly-typed event identity in core contracts.** `EventIdentifier`, `PaneContentType`, and `PaneCapability` are typed enums (with `.plugin(String)` escape hatches) instead of bare strings.

3. **No `DispatchQueue.main.async` / `NotificationCenter` selector patterns.** These are v5-era patterns incompatible with Swift 6 concurrency conventions. C API callbacks use `Task { @MainActor in }` for async work. Event transport uses `AsyncStream` + `swift-async-algorithms`. 23 `DispatchQueue.main.async` and 20 `NotificationCenter` selector instances remain as technical debt — tracked by SwiftLint concurrency rules (`no_dispatch_queue_main`, `no_notification_center_selector`) and migrated by LUNA-325.

4. **Callback handoff is explicitly actor-safe.** Static `@Sendable` trampolines at FFI boundary. No closures capturing mutable state across isolation boundaries. Adapters are `@MainActor` — the trampoline is the only non-isolated code.

5. **Clock/timer behavior is testable and migration-ready.** New time-dependent logic should use injectable clock boundaries; current replay implementation uses `ContinuousClock` with explicit constructor injection and store-level `Task.sleep` migration remains tracked.

6. **Existentials (`any`) are explicit and minimized.** `any PaneRuntime` at registry lookup boundaries and `any PaneKindEvent` at the plugin escape hatch. No implicit existential boxing — every `any` is a conscious decision at a boundary.

7. **`@MainActor` is the isolation domain for all runtime state.** All stores, runtimes, coordinators, and registries are `@MainActor`. Thread safety enforced at compile time. The protocol is `async` to reduce (not eliminate) actor-per-pane migration cost (D1). Sync protocol members would need conversion; see D1 for honest cost assessment.

8. **Envelope validity is enforced.** `source` + `event` compatibility and monotonic `seq` per `EventSource` are contract-level invariants, not best-effort behavior.

9. **macOS 26 primitives are mandatory for new plumbing.** Use Observation (`@Observable`) for UI-facing state, `AsyncStream` + `swift-async-algorithms` for transport, `Clock<Duration>` for timing, and `Task { @MainActor in }` for actor-safe callback handoff at C boundaries. See [Swift 6 Concurrency](appkit_swiftui_architecture.md#swift-6-concurrency) for full rules and common false positives.

---

## Tradeoff Summary

### Compared to coordinator-only routing (status quo)

You **gain** cleaner separation (adapter/runtime/coordinator layers), long-term maintainability (new pane types don't bloat the coordinator), typed event capture (no silent drops), and testability (mock adapters, test runtimes in isolation).

You **pay** more upfront contracts and stricter schemas. Every new event kind must be added to the enum and classified. Every new pane type must implement the protocol.

### Compared to actor-per-pane now

You **avoid** major complexity (actor async boundaries on every property access, mailbox lifecycle management, ordering challenges) and migration cost.

You **accept** the risk that `@MainActor` becomes a bottleneck for high-frequency terminals. Mitigation: protocol is `async` from day one, which minimizes (but does not eliminate) caller-side migration cost. Sync protocol members (`paneId`, `metadata`, `snapshot()`) would need conversion to `async` or `nonisolated`. Profile before deciding.

### Compared to three separate planes

You **reduce** ordering hazards (single stream, per-source ordering with cross-source best-effort) and operational complexity (one stream to debug, not three).

You **accept** the discipline of classifying every event kind (critical vs lossy) and maintaining the priority table. The event enum makes this explicit — you can't add an event without deciding its priority.

---

## Review Findings

This architecture was reviewed by four independent analyses:

| Reviewer | Key Finding | Impact on Design |
|----------|-------------|-----------------|
| **User's Codex** | Three planes + envelope design + NotificationReducer keyed by paneId+category+taskId | Adopted: NotificationReducer concept, correlationId, envelope fields |
| **Standalone Codex** | Staged approach is flawed (sync→async protocol change). Three planes over-vocabulary. Subprocess isolation preferred. | Partially adopted: make protocol async from day one. Rejected: subprocess isolation (Ghostty surfaces are in-process NSViews). Adopted: envelope simplification. |
| **Counsel (Gemini+Codex)** | Three planes create ordering hazards. Missing lifecycle state machine. Priority inversion in batching. Need bounded replay. | Adopted: single event stream, lifecycle contract, priority queues, ring buffer replay |
| **Claude (synthesis)** | Narrow waist: @Observable for UI, event stream for coordination. GhosttyEvent enum for compile-time exhaustiveness. | Adopted: dual consumption path, FFI enum contract |

**Convergence points** (all 4 agreed): per-pane-type runtimes, @MainActor sufficient, exhaustive Ghostty action capture, explicit error contract.

**Key disagreement resolved:** Three planes vs single stream. Two reviewers independently identified the ordering hazard. Adopted single stream.

---

## Relationship to Other Work

| Ticket | Relationship | Contracts Owned |
|--------|-------------|-----------------|
| **LUNA-295** (Pane Attach Orchestration) | Attach readiness policies, visibility-tier scheduling, anti-flicker. Consumes event stream from LUNA-325. | Contract 5a (Attach Readiness), Contract 12a (Visibility-Tier Scheduling), LUNA-295 attach lifecycle diagram |
| **LUNA-324** (Restart Reconcile) | zmx session reconcile on app launch, orphan cleanup, health monitoring. | Contract 5b (Restart Reconcile Policy) |
| **LUNA-325** (Bridge Pattern + Surface State Refactor) | Implements terminal runtime + Ghostty adapter + GhosttyEvent enum + surface registry. Primary implementation ticket. | Contract 1, 2, 3, 4, 7, 7a, 8, 10, 11, 12, 14 |
| **LUNA-326** (Native Scrollbar) | Consumes the terminal runtime contract. Scrollbar behavior binds to `TerminalRuntime.scrollbarState` via @Observable. Does not invent new transport. | None (consumer only) |
| **LUNA-327** (State Ownership + Observable Migration) | The current branch. Establishes @Observable store pattern, PaneCoordinator consolidation, `private(set)` unidirectional flow, and `DispatchQueue.main.async` → `MainActor` migration. | D1, D5, Swift 6 invariants, Migration section |
| **LUNA-342** (Contract Freeze) | Freeze gate — all design decisions, contracts, and invariants locked. No implementation. | All invariants (A1-A15), Swift 6 invariants (1-9), envelope/source shape |

---

## Directory Placement

Contract types are shared pane-system domain infrastructure — used by all features, not owned by any single feature. They live in `Core/PaneRuntime/`. Feature-specific implementations (adapters, concrete runtimes) live in each `Features/X/` directory. The coordinator stays in `App/` as the composition root.

See [Directory Structure](directory_structure.md) for the full decision process and import rules.

| Type | Directory | Rationale |
|------|-----------|-----------|
| **Contracts** (PaneRuntime protocol, PaneRuntimeEvent, PaneEventEnvelope, RuntimeCommand, RuntimeCommandEnvelope, PaneLifecycle, PaneMetadata, ActionPolicy, PaneCapability, per-kind event/command enums) | `Core/PaneRuntime/Contracts/` | Imported by all features and App; change driver is pane system contract, not any specific feature |
| **RuntimeRegistry** | `Core/PaneRuntime/Registry/` | Feature-agnostic lookup; consumed by PaneCoordinator in App/ |
| **NotificationReducer**, VisibilityTier types | `Core/PaneRuntime/Reduction/` | Feature-agnostic event processing; consumed by PaneCoordinator |
| **EventReplayBuffer** | `Core/PaneRuntime/Replay/` | Feature-agnostic buffering; consumed by PaneCoordinator |
| **GhosttyAdapter** | `Features/Terminal/Ghostty/` | FFI-specific; translates C callbacks into Core event types |
| **TerminalRuntime** | `Features/Terminal/Runtime/` | Terminal-specific `PaneRuntime` conformance |
| **BrowserRuntime** (future) | `Features/Webview/Runtime/` | Webview-specific `PaneRuntime` conformance |
| **PaneCoordinator** | `App/` | Imports from multiple features; composition root |

### Why per-kind event enums live in Core

`GhosttyEvent`, `BrowserEvent`, `DiffEvent`, `EditorEvent` are cases in the `PaneRuntimeEvent` discriminated union (Contract 2). Since `PaneRuntimeEvent` is in `Core/PaneRuntime/Contracts/` and Core cannot import Features, all per-kind event enums must also be in Core. These enums define the **domain event vocabulary** — what the system says about terminal/browser/diff/editor events. The adapters that *produce* these events from platform APIs live in Features.

### Naming: RuntimeCommand vs PaneAction

Two distinct action layers exist with different scopes:

| Layer | Type | Location | Purpose |
|-------|------|----------|---------|
| **Workspace** | `PaneAction` | `Core/Actions/` | Workspace structure mutations — selectTab, closePane, insertPane, toggleDrawer |
| **Runtime** | `RuntimeCommand` | `Core/PaneRuntime/Contracts/` | Commands to individual runtimes — sendInput, navigate, approveHunk |

`PaneAction` flows: User → ActionResolver → ActionValidator → PaneCoordinator → WorkspaceStore.
`RuntimeCommand` flows: PaneCoordinator → RuntimeRegistry → `runtime.handleCommand(envelope)`.

---

## Prior Art

| Project | Pattern Used | What We Took |
|---------|-------------|-------------|
| **Supacode** (supabitapp/supacode) | GhosttySurfaceBridge per surface, ~40 @Observable properties on flat GhosttySurfaceState, TCA TerminalClient dependency, 8-category action handlers | Bridge-per-surface pattern, exhaustive action handling, @Observable state for UI binding |
| **cmux** (manaflow-ai/cmux) | WebSocket PTY server, typed ServerEvent broadcast, server-authoritative state | Event broadcast model, typed event dispatch |
| **Zed** (zed-industries/zed) | Entity/component system (gpui), event log with total ordering, deterministic replay, per-entity error isolation | Single event log (not three planes), bounded replay for late-joining consumers, per-pane error isolation |
| **VS Code** | Extension host process isolation, RPC command dispatch, incremental state updates | Command ID + async result pattern, RPC dispatch model. NOTE: VS Code uses shared runtime per pane type; we chose per-pane instances instead (D1, A2). |
