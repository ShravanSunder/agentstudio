# Pane Runtime Architecture

## Problem

Agent Studio is a **workspace for agent-assisted development** — an agent orchestration platform where terminal agents (Claude, Codex, aider) are the primary drivers and non-terminal panes (diff viewers, PR reviewers, code viewers) exist for human observation and control. This is the **inverse of Cursor**: agents drive the workspace, users observe and orchestrate.

The current Ghostty integration handles 12 of 40+ C API actions, uses `DispatchQueue.main.async` and `NotificationCenter` for event dispatch, and has no typed event contract. Non-terminal pane types (webview, diff viewer) have no runtime abstraction. There is no bidirectional communication system, no event batching, and no temporal coordination for multi-agent workflows.

This document defines the pane runtime communication architecture: how panes of all types produce events, receive commands, and coordinate through the workspace.

### Jobs This Architecture Solves

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

**Why not actor-per-pane:** Swift actors impose async boundaries on every property access. For a macOS UI app where all state feeds `@Observable` views on the main thread, this adds overhead without matching benefit. `@MainActor` already provides thread safety. If profiling shows contention (>1000 events/sec sustained), individual runtimes can be upgraded to actors without protocol changes because the protocol is already `async`.

**Why not single coordinator handling all events:** Becomes a god object as pane types grow. Per-type runtimes have clear ownership, are testable in isolation, and scale with new pane types.

**Reviewed by:** 4 independent opinions (Claude, Codex ×2, Gemini+Codex counsel). All converged on this choice.

### D2: Single typed event stream, not three separate planes

**User problem:** When agent A finishes a task and a diff appears, the user needs to know which agent produced it, what repo it's in, and the diff content — all consistently, with no missing context (JTBD 6, P6).

**Decision:** One `PaneRuntimeEvent` enum carried on one `AsyncStream` per runtime, with total ordering via per-pane sequence numbers. Events cover lifecycle, terminal, browser, filesystem, artifact, and error cases.

**Why not three planes (control/state/data):** Two independent reviewers identified an ordering hazard: if control events ("diff generated") and state events ("diff pane loaded") travel on separate streams, a late-joining consumer can observe inconsistent state — seeing a loaded diff without knowing which terminal produced it. Single stream with total ordering eliminates this.

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

**Decision:** Events classified as `critical` (never coalesced, immediate delivery) or `lossy` (batched on frame boundary, deduped). Priority tiers from LUNA-295: `p0_activePane → p1_activeDrawer → p2_visibleActiveTab → p3_background`.

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

### Contract 1: PaneRuntime Protocol

```swift
/// Every pane type (terminal, browser, diff, editor) conforms to this.
/// Coordinator only knows this protocol — never pane-type-specific types.
///
/// One instance per pane. All instances share @MainActor.
/// Adapters (GhosttyAdapter, WebKitAdapter) are shared singletons
/// that route events to the correct runtime instance.
@MainActor
protocol PaneRuntime: AnyObject {
    var paneId: PaneId { get }
    var metadata: PaneMetadata { get }
    var lifecycle: PaneRuntimeLifecycle { get }
    var capabilities: Set<PaneCapability> { get }

    /// Dispatch a command. Fails if lifecycle != .ready.
    func handleAction(_ envelope: PaneActionEnvelope) async -> ActionResult

    /// Current state snapshot for late-joining consumers.
    func snapshot() -> RuntimeSnapshot

    /// Bounded replay for catch-up. Returns events + next seq.
    func eventsSince(seq: UInt64) async -> ([PaneRuntimeEvent], UInt64)

    /// Subscribe to live coordination events.
    /// Raw events — the coordinator wraps these in PaneEventEnvelope
    /// and feeds them to the NotificationReducer for priority routing.
    func subscribe() -> AsyncStream<PaneRuntimeEvent>

    /// Graceful shutdown. Returns unfinished command IDs.
    func shutdown(timeout: Duration) async -> [UUID]
}

typealias PaneId = UUID
```

#### Supporting Types

```swift
/// Rich pane identity — maps to R1 (Rich Pane Metadata from JTBD doc).
/// Fixed fields set at creation. Live fields updated from events.
struct PaneMetadata: Sendable {
    // Fixed at creation
    let paneId: PaneId
    let contentType: PaneContentType        // .terminal, .browser, .diff, .editor
    let source: PaneSource                  // .worktree(id), .floating
    let executionBackend: ExecutionBackend  // .local, .docker, .gondolin, .remote
    let createdAt: ContinuousClock.Instant

    // Live-updated (from runtime events → coordinator → store)
    var title: String?
    var cwd: URL?
    var repoId: UUID?
    var worktreeId: UUID?
    var agentType: AgentType?
    var tags: Set<String>

    // Computed: effective tags = repo tags ∪ pane tags
    // (repo tags resolved at query time by WorkspaceStore, not stored here)
}

/// Extensible content type. Built-in kinds have static constants.
/// Plugins register additional types at runtime.
struct PaneContentType: Hashable, Sendable {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }

    static let terminal = PaneContentType("terminal")
    static let browser  = PaneContentType("browser")
    static let diff     = PaneContentType("diff")
    static let editor   = PaneContentType("editor")
    // Plugins add: PaneContentType("logViewer"), PaneContentType("metrics"), etc.
}

enum PaneSource: Sendable {
    case worktree(worktreeId: UUID)
    case floating
}

/// What a runtime can do. Coordinator checks capabilities
/// before dispatching actions — avoids sending search commands
/// to a diff pane or approval actions to a terminal.
struct PaneCapability: Hashable, Sendable {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }

    // Content interaction
    static let textInput       = PaneCapability("textInput")
    static let search          = PaneCapability("search")
    static let scrollback      = PaneCapability("scrollback")
    static let navigation      = PaneCapability("navigation")
    static let codeEditing     = PaneCapability("codeEditing")

    // Workflow
    static let approval        = PaneCapability("approval")
    static let commenting      = PaneCapability("commenting")

    // Execution environment (from ExecutionBackend)
    static let sandboxed       = PaneCapability("sandboxed")
    static let networkIsolated = PaneCapability("networkIsolated")
    static let secretInjection = PaneCapability("secretInjection")

    // System
    static let undo            = PaneCapability("undo")
    static let replay          = PaneCapability("replay")
    static let splitZoom       = PaneCapability("splitZoom")
}

/// Snapshot for late-joining consumers (dynamic view opens, drawer expands).
/// Contains enough state to render the pane immediately without replaying
/// the full event history.
struct RuntimeSnapshot: Sendable {
    let paneId: PaneId
    let metadata: PaneMetadata
    let lifecycle: PaneRuntimeLifecycle
    let capabilities: Set<PaneCapability>
    let lastSeq: UInt64                     // sequence number of last emitted event
    let timestamp: ContinuousClock.Instant

    /// Key-value observable state. Shape varies by runtime kind.
    /// Terminal: ["title": "zsh", "cwd": "/Users/foo", "searchActive": false, ...]
    /// Browser:  ["url": "https://...", "loading": true, "title": "PR #42", ...]
    /// Diff:     ["filePath": "src/main.rs", "approvedHunks": 3, "totalHunks": 7, ...]
    let observableState: [String: String]
}

/// Result of dispatching a command to a runtime.
enum ActionResult: Sendable {
    case success(commandId: UUID)
    case queued(commandId: UUID, position: Int)
    case failure(ActionError)
}

enum ActionError: Error, Sendable {
    case runtimeNotReady(lifecycle: PaneRuntimeLifecycle)
    case unsupportedAction(action: String, required: PaneCapability)
    case invalidPayload(description: String)
    case backendUnavailable(backend: String)
    case timeout(commandId: UUID, after: Duration)
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
///   2. Workflow matching — eventName provides a stable string identity for
///      WorkflowTracker step predicates.
protocol PaneKindEvent: Sendable {
    /// Priority classification for this event.
    /// Critical = immediate delivery, never coalesced.
    /// Lossy = batched on frame boundary, deduped by consolidation key.
    var actionPolicy: ActionPolicy { get }

    /// Stable string name for workflow matching.
    /// e.g., "commandFinished", "navigationCompleted", "hunkApproved"
    var eventName: String { get }
}

/// Single typed event stream. Discriminated union with plugin escape hatch.
///
/// Built-in pane kinds get dedicated cases (type safety, pattern matching,
/// compiler-enforced handling). Plugin pane kinds use `.plugin` (protocol-
/// based, extensible, downcast for specific handling).
///
/// Two axes:
///   PANE-SCOPED (carry paneId): terminal, browser, diff, editor, plugin
///   CROSS-CUTTING (carry worktreeId or broader): lifecycle, filesystem,
///     artifact, security, error
enum PaneRuntimeEvent: Sendable {
    // ── Lifecycle — all pane types ──────────────────────
    case lifecycle(PaneLifecycleEvent)

    // ── First-class pane kinds: exhaustive, pattern-matchable ──
    case terminal(paneId: UUID, event: GhosttyEvent)
    case browser(paneId: UUID, event: BrowserEvent)
    case diff(paneId: UUID, event: DiffEvent)
    case editor(paneId: UUID, event: EditorEvent)

    // ── Plugin escape hatch: protocol-based, extensible ──
    // Plugin pane types (log viewer, metrics dashboard, etc.) use this.
    // Events conform to PaneKindEvent. Downcast for specific handling.
    // To promote a plugin to first-class: add a dedicated case above.
    case plugin(paneId: UUID, kind: PaneContentType, event: any PaneKindEvent)

    // ── Cross-cutting events ───────────────────────────
    case filesystem(FilesystemEvent)
    case artifact(ArtifactEvent)
    case security(SecurityEvent)

    // ── Runtime errors ─────────────────────────────────
    case error(paneId: UUID?, error: RuntimeError)
}

/// Computed priority from self-classifying events.
/// NotificationReducer reads this — no centralized classify() needed.
extension PaneRuntimeEvent {
    var actionPolicy: ActionPolicy {
        switch self {
        case .terminal(_, let e):       return e.actionPolicy
        case .browser(_, let e):        return e.actionPolicy
        case .diff(_, let e):           return e.actionPolicy
        case .editor(_, let e):         return e.actionPolicy
        case .plugin(_, _, let e):      return e.actionPolicy
        case .lifecycle, .filesystem, .artifact, .security, .error:
            return .critical
        }
    }
}

enum PaneLifecycleEvent: Sendable {
    case surfaceCreated(paneId: UUID)
    case sizeObserved(paneId: UUID, cols: Int, rows: Int)
    case sizeStabilized(paneId: UUID)
    case attachStarted(paneId: UUID)
    case attachSucceeded(paneId: UUID)
    case attachFailed(paneId: UUID, error: AttachError)
    case paneClosed(paneId: UUID)
    case tabSwitched(activeTabId: UUID)
    case activePaneChanged(paneId: UUID)
    case drawerExpanded(parentPaneId: UUID)
    case drawerCollapsed(parentPaneId: UUID)
}

enum FilesystemEvent: Sendable {
    case filesChanged(worktreeId: UUID, changeset: FileChangeset)
    case gitStatusChanged(worktreeId: UUID, summary: GitStatusSummary)
    case diffAvailable(worktreeId: UUID, diffId: UUID)
    case branchChanged(worktreeId: UUID, from: String, to: String)
}

enum ArtifactEvent: Sendable {
    case diffProduced(agentPaneId: UUID, worktreeId: UUID, artifact: DiffArtifact)
    case prCreated(agentPaneId: UUID, prUrl: String)
    case approvalRequested(paneId: UUID, request: ApprovalRequest)
    case approvalDecided(paneId: UUID, decision: ApprovalDecision)
}

/// Security events from execution backends (Gondolin, Docker, etc.).
/// Scoped to worktreeId — one sandbox may back multiple panes.
/// All cases are critical priority (user must know immediately).
enum SecurityEvent: Sendable {
    // Policy enforcement
    case networkEgressBlocked(worktreeId: UUID, destination: String, rule: String)
    case networkEgressAllowed(worktreeId: UUID, destination: String)
    case filesystemAccessDenied(worktreeId: UUID, path: String, operation: String)
    case secretAccessed(worktreeId: UUID, secretId: String, consumerId: String)
    case processSpawnBlocked(worktreeId: UUID, command: String, rule: String)

    // Sandbox lifecycle
    case sandboxStarted(worktreeId: UUID, backend: ExecutionBackend, policy: String)
    case sandboxStopped(worktreeId: UUID, reason: String)
    case sandboxHealthChanged(worktreeId: UUID, healthy: Bool)

    // Violations (always critical, always surfaced to user)
    case policyViolation(worktreeId: UUID, description: String, severity: ViolationSeverity)
    case credentialExfiltrationAttempt(worktreeId: UUID, targetHost: String)
}

enum ViolationSeverity: String, Sendable {
    case warning    // logged, user notified
    case critical   // process killed, user alerted
}

enum RuntimeError: Error, Sendable {
    case surfaceCrashed(reason: String)
    case commandTimeout(commandId: UUID, after: Duration)
    case actionDispatchFailed(action: String, underlyingError: Error)
    case adapterError(String)
    case resourceExhausted(resource: String)
    case internalStateCorrupted
}
```

### Contract 3: PaneEventEnvelope

```swift
/// Metadata wrapper on every event for routing, ordering, and idempotency.
struct PaneEventEnvelope: Sendable {
    let paneId: UUID
    let runtimeKind: PaneRuntimeKind        // .terminal, .browser, .diff, .editor
    let seq: UInt64                          // monotonic per pane, ordering guarantee
    let commandId: UUID                      // idempotency for commands
    let correlationId: UUID?                 // links workflow steps (agent finish → diff → approval)
    let timestamp: ContinuousClock.Instant
    let priority: EventPriority
    let epoch: UInt64                        // reserved, 0 until runtime restart/reconnect
    let event: PaneRuntimeEvent
}

enum EventPriority: Sendable {
    case critical   // never coalesced, immediate delivery
    case lossy      // batched on frame boundary, deduped by consolidation key
}

/// Extensible runtime kind. Matches PaneContentType for pane-scoped events.
/// Also includes non-pane event sources (filesystem, security).
struct PaneRuntimeKind: Hashable, Sendable {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }

    static let terminal   = PaneRuntimeKind("terminal")
    static let browser    = PaneRuntimeKind("browser")
    static let diff       = PaneRuntimeKind("diff")
    static let editor     = PaneRuntimeKind("editor")
    static let filesystem = PaneRuntimeKind("filesystem")  // watcher, not a pane
    static let security   = PaneRuntimeKind("security")    // sandbox, not a pane
    // Plugins add their own kinds
}
```

### Contract 4: NotificationReducer Policy

```swift
/// Determines how each event kind is processed.
/// Critical events bypass coalescing. Lossy events batch on frame boundary.
enum ActionPolicy: Sendable {
    case critical                             // immediate delivery, never dropped
    case lossy(consolidationKey: String)      // dedup + coalesce within frame window
}

/// Classification table for Ghostty actions.
/// Each action has exactly one policy. No ambiguity.
///
/// Lifecycle actions: always critical
/// Control actions (command finish, bell, notification): always critical
/// Viewport/telemetry (scroll, cursor, selection): lossy
/// Rendering (color, font): lossy, consolidate adjacent
///
/// Implementation: NotificationReducer maintains two queues:
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
///   4. handleAction() returns .failure(.runtimeNotReady) if lifecycle != .ready
///   5. shutdown(timeout:) is idempotent — safe to call multiple times
///   6. After terminated, no events emitted, no commands accepted
///   7. Unfinished command IDs returned from shutdown() for logging/recovery
```

### Contract 6: Filesystem Batching

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
///   7. Identity: every batch carries worktreeId for routing

struct FileChangeset: Sendable {
    let worktreeId: UUID
    let paths: Set<String>           // deduped relative paths
    let timestamp: ContinuousClock.Instant
    let batchSeq: UInt64             // monotonic per worktree
}
```

### Contract 7: GhosttyEvent FFI Enum

```swift
/// Exhaustive mapping of ghostty_action_tag_e → Swift.
/// Every Ghostty action has exactly one case.
/// Adapter switch is exhaustive — compiler enforces coverage.
enum GhosttyEvent: Sendable {
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

    // Explicit unhandled — logged, never silent
    case unhandled(tag: UInt32)
}
```

### Contract 8: Per-Kind Event Enums

Each pane kind has its own event enum — exhaustive within that domain, just as `GhosttyEvent` is exhaustive for the Ghostty C API.

```swift
/// Browser/webview events — from WKNavigationDelegate and WKUIDelegate.
enum BrowserEvent: Sendable {
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
enum DiffEvent: Sendable {
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
enum EditorEvent: Sendable {
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
/// Stored on PaneMetadata. Set at pane creation. Can be migrated
/// (sandboxMigrated event) but this is rare.
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

### Contract 10: Inbound Action Dispatch

```swift
/// Command envelope dispatched TO a runtime (inbound).
/// Mirror of PaneEventEnvelope (outbound from runtime → coordinator).
struct PaneActionEnvelope: Sendable {
    let commandId: UUID                     // idempotency
    let correlationId: UUID?                // links workflow steps
    let targetPaneId: UUID
    let action: PaneAction
    let timestamp: ContinuousClock.Instant
}

/// Protocol for per-kind actions. Same pattern as PaneKindEvent:
/// built-in action enums conform AND have dedicated cases.
/// Plugin actions conform and use the `.plugin` escape hatch.
protocol PaneKindAction: Sendable {
    var actionName: String { get }
}

/// What the coordinator can tell any runtime to do.
/// Discriminated union with plugin escape hatch — same pattern as
/// PaneRuntimeEvent.
enum PaneAction: Sendable {
    // Generic lifecycle — all runtimes handle these
    case activate                           // pane became visible/focused
    case deactivate                         // pane hidden/backgrounded
    case prepareForClose                    // begin draining

    // State queries
    case requestSnapshot                    // coordinator wants current state

    // ── First-class per-kind actions ───────────────────
    case terminal(TerminalAction)
    case browser(BrowserAction)
    case diff(DiffAction)
    case editor(EditorAction)

    // ── Plugin escape hatch ────────────────────────────
    case plugin(any PaneKindAction)
}

enum TerminalAction: Sendable {
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

enum BrowserAction: Sendable {
    case navigate(url: URL)
    case goBack
    case goForward
    case reload(hard: Bool)
    case stop
    case executeScript(String)
    case setZoom(Double)
}

enum DiffAction: Sendable {
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

enum EditorAction: Sendable {
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
  PaneActionEnvelope(commandId, correlationId, targetPaneId, action)
       │
       ▼
  runtime.handleAction(envelope) async → ActionResult
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

    /// Lookup by paneId. Returns nil if not registered or terminated.
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

### Contract 12: NotificationReducer

```swift
/// Routes events through priority-aware processing.
/// Two completely separate paths — critical and lossy never interact.
///
/// Event flow:
///   Runtime.subscribe() → PaneRuntimeEvent
///     → Coordinator wraps in PaneEventEnvelope (adds seq, priority, etc.)
///     → NotificationReducer.submit(envelope, policy)
///       → critical path: immediate yield to consumers
///       → lossy path: buffer until next frame, dedup by consolidation key
///     → Coordinator consumes from reducer's output streams
@MainActor
final class NotificationReducer {

    // ── Critical path ───────────────────────────────────
    // Immediate delivery. Never coalesced. Never dropped.
    // Wakes the coordinator's event loop on every event.
    private let criticalContinuation: AsyncStream<PaneEventEnvelope>.Continuation
    let criticalEvents: AsyncStream<PaneEventEnvelope>

    // ── Lossy path ──────────────────────────────────────
    // Batched on frame boundary (16.67ms at 60fps).
    // Deduped by composite key: "{paneId}:{consolidationKey}"
    // Latest event for each key wins (overwrites previous in window).
    // Max buffer depth: 1000 entries. Drops oldest on overflow.
    private var lossyBuffer: [String: PaneEventEnvelope] = [:]
    private var frameTimer: Task<Void, Never>?
    private let batchContinuation: AsyncStream<[PaneEventEnvelope]>.Continuation
    let batchedEvents: AsyncStream<[PaneEventEnvelope]>

    /// Submit an envelope for processing.
    /// The coordinator calls this after wrapping raw runtime events.
    func submit(_ envelope: PaneEventEnvelope, policy: ActionPolicy) {
        switch policy {
        case .critical:
            criticalContinuation.yield(envelope)

        case .lossy(let consolidationKey):
            let key = "\(envelope.paneId):\(consolidationKey)"
            lossyBuffer[key] = envelope     // latest wins
            if lossyBuffer.count > 1000 {
                // drop oldest by timestamp
                if let oldest = lossyBuffer.min(by: { $0.value.timestamp < $1.value.timestamp }) {
                    lossyBuffer.removeValue(forKey: oldest.key)
                }
            }
            ensureFrameTimer()
        }
    }

    /// Classify any PaneRuntimeEvent to its ActionPolicy.
    /// Centralized — runtimes don't decide their own priority.
    static func classify(_ event: PaneRuntimeEvent) -> ActionPolicy {
        switch event {
        // Always critical
        case .lifecycle:                    return .critical
        case .filesystem:                   return .critical
        case .artifact:                     return .critical
        case .security:                     return .critical
        case .error:                        return .critical

        // Per-kind classification
        case .terminal(_, let e):           return classifyTerminal(e)
        case .browser(_, let e):            return classifyBrowser(e)
        case .diff(_, let e):               return classifyDiff(e)
        case .editor(_, let e):             return classifyEditor(e)
        }
    }

    private static func classifyTerminal(_ e: GhosttyEvent) -> ActionPolicy {
        switch e {
        // Critical: workspace-facing, tab/split, metadata, config
        case .titleChanged, .cwdChanged, .commandFinished, .bellRang,
             .desktopNotification, .progressReport, .childExited, .closeSurface,
             .newTab, .closeTab, .gotoTab, .moveTab, .newSplit, .gotoSplit,
             .resizeSplit, .equalizeSplits, .toggleSplitZoom,
             .configReload, .configChanged, .colorChanged, .secureInput,
             .openConfig, .presentTerminal, .toggleFullscreen,
             .toggleWindowDecorations, .toggleCommandPalette,
             .toggleVisibility, .floatWindow, .quitTimer, .undo, .redo:
            return .critical

        // Lossy: high-frequency viewport/telemetry
        case .scrollbarChanged:             return .lossy(consolidationKey: "scroll")
        case .cellSize, .sizeLimits,
             .initialSize:                  return .lossy(consolidationKey: "size")
        case .searchStarted, .searchEnded,
             .searchTotal, .searchSelected: return .lossy(consolidationKey: "search")
        case .mouseShapeChanged,
             .mouseVisibilityChanged,
             .linkHover:                    return .lossy(consolidationKey: "mouse")
        case .rendererHealth:               return .lossy(consolidationKey: "health")
        case .keySequence, .keyTable,
             .readOnly:                     return .lossy(consolidationKey: "input")
        case .unhandled:                    return .lossy(consolidationKey: "unhandled")
        }
    }

    private static func classifyBrowser(_ e: BrowserEvent) -> ActionPolicy {
        switch e {
        case .navigationStarted, .navigationCompleted, .navigationFailed,
             .urlChanged, .titleChanged, .pageLoaded, .pageUnloaded,
             .linkClicked, .downloadRequested, .dialogRequested,
             .dialogDismissed, .authChallengeReceived:
            return .critical
        case .consoleMessage, .consoleCleared:
            return .lossy(consolidationKey: "console")
        case .contentSizeChanged:
            return .lossy(consolidationKey: "contentSize")
        }
    }

    private static func classifyDiff(_ e: DiffEvent) -> ActionPolicy {
        switch e {
        case .hunkApproved, .hunkRejected, .fileApproved,
             .allApproved, .allRejected,
             .commentAdded, .commentResolved, .commentDeleted,
             .diffLoaded, .diffUpdated, .diffClosed:
            return .critical
        case .fileSelected, .hunkNavigated, .fileListScrolled:
            return .lossy(consolidationKey: "diffNav")
        }
    }

    private static func classifyEditor(_ e: EditorEvent) -> ActionPolicy {
        switch e {
        case .contentSaved, .contentReverted,
             .fileOpened, .fileClosed, .languageDetected,
             .diagnosticsUpdated, .diagnosticSelected:
            return .critical
        case .cursorMoved, .selectionChanged, .visibleRangeChanged:
            return .lossy(consolidationKey: "cursor")
        case .contentModified:
            return .lossy(consolidationKey: "edit")
        }
    }

    // ── Frame timer ─────────────────────────────────────
    // Flushes lossy buffer every 16.67ms (one frame at 60fps).
    // One timer shared across all panes. Timer starts on first
    // lossy event, stops when buffer is empty.
    private func ensureFrameTimer() {
        guard frameTimer == nil else { return }
        frameTimer = Task { [weak self] in
            while let self, !self.lossyBuffer.isEmpty {
                try? await Task.sleep(for: .milliseconds(16))
                self.flushLossyBuffer()
            }
            self?.frameTimer = nil
        }
    }

    private func flushLossyBuffer() {
        guard !lossyBuffer.isEmpty else { return }
        let batch = Array(lossyBuffer.values)
        lossyBuffer.removeAll(keepingCapacity: true)
        batchContinuation.yield(batch)
    }
}
```

#### Coordinator Event Loop (how it connects)

```
┌──────────────────────────────────────────────────────────┐
│ PaneCoordinator event consumption loop                    │
│                                                          │
│  for await runtime in registry.readyRuntimes {           │
│    Task {                                                │
│      for await event in runtime.subscribe() {            │
│        let envelope = wrap(event, runtime, nextSeq())    │
│        let policy = NotificationReducer.classify(event)  │
│        reducer.submit(envelope, policy: policy)          │
│        replayBuffer[runtime.paneId].append(envelope)     │
│      }                                                   │
│    }                                                     │
│  }                                                       │
│                                                          │
│  // Critical consumer — handles immediately              │
│  Task {                                                  │
│    for await envelope in reducer.criticalEvents {        │
│      routeToConsumers(envelope)                          │
│      workflowTracker.processEvent(envelope)              │
│    }                                                     │
│  }                                                       │
│                                                          │
│  // Lossy consumer — handles batched per frame           │
│  Task {                                                  │
│    for await batch in reducer.batchedEvents {            │
│      for envelope in batch {                             │
│        routeToConsumers(envelope)                        │
│      }                                                   │
│    }                                                     │
│  }                                                       │
└──────────────────────────────────────────────────────────┘
```

### Contract 13: Workflow Engine

```swift
/// Tracks temporal workflows that span multiple panes and events.
/// "Agent finishes → create diff → user approves → signal next agent"
///
/// Owned by PaneCoordinator. Pure state tracking — no domain logic.
/// The coordinator uses this to know which workflow step to advance
/// when a matching event arrives.
///
/// Restart-safe: on coordinator recovery, replay events from replay
/// buffers to find the current position of each active workflow.
@MainActor
final class WorkflowTracker {

    struct Workflow: Sendable {
        let correlationId: UUID
        let steps: [WorkflowStep]
        var currentStepIndex: Int
        var state: WorkflowState
        let createdAt: ContinuousClock.Instant
    }

    struct WorkflowStep: Sendable {
        let commandId: UUID
        let description: String
        /// What event completes this step. Matched by the tracker.
        let completionPredicate: StepPredicate
        var completed: Bool
    }

    /// How a step is considered complete.
    enum StepPredicate: Sendable {
        /// Any event with this commandId
        case commandCompleted(UUID)
        /// A specific event kind on a specific pane
        case eventMatch(paneId: UUID, eventKind: String)
        /// Approval decision on a specific pane
        case approvalDecided(paneId: UUID)
    }

    enum WorkflowState: Sendable {
        case active
        case waitingForEvent(stepIndex: Int)
        case completed
        case failed(reason: String)
        case timedOut
    }

    private var activeWorkflows: [UUID: Workflow] = [:]

    /// Start tracking a new workflow. Returns correlationId.
    func startWorkflow(steps: [WorkflowStep]) -> UUID { ... }

    /// Process an incoming event. If it matches a step predicate,
    /// advance the workflow and return what action to take next.
    func processEvent(_ envelope: PaneEventEnvelope) -> WorkflowAdvance? { ... }

    /// Recovery: replay events to reconstruct workflow positions.
    /// Called on coordinator restart.
    func recover(from events: [PaneEventEnvelope]) { ... }

    /// Expire workflows older than TTL. Returns expired correlationIds.
    func expireStale(ttl: Duration, now: ContinuousClock.Instant) -> [UUID] { ... }
}

enum WorkflowAdvance: Sendable {
    /// Step completed, workflow still active. No action needed.
    case stepCompleted(correlationId: UUID, stepIndex: Int)
    /// Workflow fully completed. Clean up.
    case workflowCompleted(correlationId: UUID)
    /// Step completed, trigger next step's action.
    case triggerNext(correlationId: UUID, action: PaneActionEnvelope)
}
```

#### Workflow Example: Agent Finish → Diff → Approval

```
Workflow correlationId: abc-123
Steps:
  [0] commandFinished on pane-A (terminal)    ← completed by GhosttyEvent
  [1] loadDiff on pane-D (diff viewer)        ← triggered by coordinator
  [2] approvalDecided on pane-D               ← completed by user action
  [3] sendInput on pane-B (next terminal)     ← triggered by coordinator

Event arrives: .terminal(pane-A, .commandFinished(exitCode: 0))
  → WorkflowTracker matches step [0]
  → returns .triggerNext(abc-123, loadDiff action on pane-D)
  → coordinator dispatches DiffAction.loadDiff to pane-D

Event arrives: .diff(pane-D, .diffLoaded(stats))
  → step [1] marked complete (event match)
  → returns .stepCompleted (waiting for approval)

Event arrives: .artifact(.approvalDecided(pane-D, .approved))
  → step [2] matched
  → returns .triggerNext(abc-123, sendInput action on pane-B)
  → coordinator sends TerminalAction.sendInput to next agent
```

### Contract 14: Replay Buffer

```swift
/// Bounded event ring buffer per pane for late-joining consumers.
/// Used when: dynamic view opens (needs current state of all panes),
/// drawer expands (needs parent pane context), tab switches (catch up
/// on background events).
///
/// NOT a persistence mechanism — events are ephemeral.
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
    private let clock: any Clock<Duration>

    /// Append event. Evicts oldest if capacity/bytes exceeded.
    func append(_ envelope: PaneEventEnvelope) {
        // Evict if at capacity
        if count >= config.maxEvents {
            evictOldest()
        }
        // Evict if bytes exceeded (rough estimate: 128 bytes per envelope)
        while estimatedBytes > config.maxBytes, count > 0 {
            evictOldest()
        }
        ring[head] = envelope
        head = (head + 1) % ring.count
        count += 1
        estimatedBytes += 128
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
        let gapDetected = seq < first.seq
        let matching = available.filter { $0.seq > seq }
        let nextSeq = matching.last?.seq ?? seq
        return ReplayResult(events: matching, nextSeq: nextSeq, gapDetected: gapDetected)
    }

    struct ReplayResult: Sendable {
        let events: [PaneEventEnvelope]
        let nextSeq: UInt64
        let gapDetected: Bool       // true = caller missed events, use snapshot instead
    }

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
       │     replay = replayBuffer[paneId].eventsSince(0) ← recent history
       │
       │     if replay.gapDetected:
       │       // too old, just use snapshot (no replay)
       │       render from snapshot only
       │     else:
       │       // apply snapshot + replay events
       │       render snapshot, then apply replay.events
       │
       └─► Subscribe to live events going forward
```

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
| **Cross** | **Errors** | all RuntimeError cases | `critical` | never |

---

## Sharp Edges & Mitigations

### 1. Global stream as choke point

**Risk:** One AsyncStream for all events can become a bottleneck with 10+ active terminals.

**Mitigation:** Ordering is per-paneId (`seq` field), not one total global sequence. The stream is a merge of per-runtime streams. No global sequence number means no global serialization. Per-pane ordering is the guarantee; cross-pane ordering uses `timestamp` for best-effort.

### 2. Priority inversion in batching

**Risk:** High-frequency lossy events block critical events in the same coalesce window.

**Mitigation:** Hard rule: critical events bypass the coalescing path entirely. The `NotificationReducer` maintains two separate queues. Critical events emit immediately and wake the main loop. Lossy events batch until next frame. These paths never interact.

### 3. Event storm from filesystem watchers

**Risk:** Agent writes 500 files → FSEvents fires 500+ raw events → git status recomputes 500 times.

**Mitigation:** Worktree-scoped debounce (500ms settle window) + deduped path set + max batch size (500 paths) + max latency cap (2 seconds). Git status/diff recompute only after batch flush. Multiple worktrees have independent watchers — one noisy worktree doesn't delay another.

### 4. Replay buffer memory growth

**Risk:** Ring buffer per runtime accumulates unbounded memory if events are large or frequent.

**Mitigation:** Bounded ring buffer per PANE (not per runtime). Each pane gets a 1000-event ring buffer with TTL (5 minutes) and max bytes cap (1MB). Oldest events evicted first. One noisy terminal doesn't starve replay for other panes.

### 5. Lifecycle leaks for background panes

**Risk:** Background pane closes but runtime keeps producing events, leaking resources.

**Mitigation:** Explicit lifecycle contract: `created → ready → draining → terminated`. `shutdown(timeout:)` drains in-flight commands (max 5 seconds), closes all event stream continuations, releases C API handles, and returns unfinished command IDs. Coordinator logs any unfinished commands. After `terminated`, the runtime rejects all interactions.

### 6. Idempotency gaps on temporal workflows

**Risk:** Coordinator restarts mid-workflow (crash, suspension). "Agent finished → create diff → wait for approval" loses its place.

**Mitigation:** Every workflow step carries `commandId` (idempotent per-step) and `correlationId` (links the full workflow chain). Coordinator must be restart-safe: on recovery, replay events since last known sequence, detect completed steps via commandId, resume from the correct point.

### 7. Epoch field deferred but reserved

**Risk:** Adding `epoch` later requires protocol changes and migration.

**Mitigation:** `epoch` field is in the envelope now, set to `0`. Comment: "reserved — increments on runtime restart/reconnect for stale-view detection." Zero cost to carry. Activated when late-joining consumer semantics or app-restore replay are implemented.

### 8. Execution backend lifecycle mismatch

**Risk:** Sandbox (Gondolin/Docker) starts before the runtime is ready, or crashes while the runtime is still producing events.

**Mitigation:** Execution backend lifecycle is independent of pane runtime lifecycle. The sandbox starts and becomes healthy before the runtime transitions to `ready`. If the sandbox dies, a `SecurityEvent.sandboxHealthChanged(healthy: false)` fires, and the coordinator can either restart the sandbox or transition the runtime to `draining`. The pane's `PaneMetadata.executionBackend` is immutable after creation — to change backends, close the pane and create a new one (or use the reserved `sandboxMigrated` event for live migration later).

### 9. Bus becoming a god object

**Risk:** Event bus accumulates routing logic, filtering, batching, domain decisions, workflow branching.

**Mitigation:** Bus only routes, filters, and batches. It never makes domain decisions. Workflow logic lives in the coordinator. Domain logic lives in runtimes. The bus is infrastructure — a typed `AsyncStream` with merge, filter, and throttle operators from `swift-async-algorithms`. If the bus grows methods that aren't pure stream operations, it's doing too much.

---

## Tradeoff Summary

### Compared to coordinator-only routing (status quo)

You **gain** cleaner separation (adapter/runtime/coordinator layers), long-term maintainability (new pane types don't bloat the coordinator), typed event capture (no silent drops), and testability (mock adapters, test runtimes in isolation).

You **pay** more upfront contracts and stricter schemas. Every new event kind must be added to the enum and classified. Every new pane type must implement the protocol.

### Compared to actor-per-pane now

You **avoid** major complexity (actor async boundaries on every property access, mailbox lifecycle management, ordering challenges) and migration cost.

You **accept** the risk that `@MainActor` becomes a bottleneck for high-frequency terminals. Mitigation: protocol is async from day one, so upgrading a single runtime to an actor later doesn't change callers. Profile before deciding.

### Compared to three separate planes

You **reduce** ordering hazards (single stream, total per-pane ordering) and operational complexity (one stream to debug, not three).

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

| Ticket | Relationship |
|--------|-------------|
| **LUNA-295** (Pane Attach Orchestration) | Concrete instance of the lifecycle contract. Its `PaneAttachStateMachine` + priority tiers + event types are the first implementation of this architecture for the attach lifecycle. |
| **LUNA-325** (Bridge Pattern + Surface State Refactor) | Implements the terminal runtime + Ghostty adapter + GhosttyEvent enum + surface registry. The primary LUNA ticket for this architecture. |
| **LUNA-326** (Native Scrollbar) | Consumes the terminal runtime contract. Scrollbar behavior binds to `TerminalRuntime.scrollbarState` via @Observable. Does not invent new transport. |
| **LUNA-327** (State Ownership + Observable Migration) | The current branch. Establishes the @Observable store pattern, PaneCoordinator consolidation, and private(set) unidirectional flow that this architecture builds on. |

---

## Prior Art

| Project | Pattern Used | What We Took |
|---------|-------------|-------------|
| **Supacode** (supabitapp/supacode) | GhosttySurfaceBridge per surface, ~40 @Observable properties on flat GhosttySurfaceState, TCA TerminalClient dependency, 8-category action handlers | Bridge-per-surface pattern, exhaustive action handling, @Observable state for UI binding |
| **cmux** (manaflow-ai/cmux) | WebSocket PTY server, typed ServerEvent broadcast, server-authoritative state | Event broadcast model, typed event dispatch |
| **Zed** (zed-industries/zed) | Entity/component system (gpui), event log with total ordering, deterministic replay, per-entity error isolation | Single event log (not three planes), bounded replay for late-joining consumers, per-pane error isolation |
| **VS Code** | Extension host process isolation, RPC command dispatch, incremental state updates | Shared runtime per pane TYPE (not per instance), command ID + async result pattern |
