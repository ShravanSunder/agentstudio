# Phase B: Data Model Remodel — Specification

**Branch:** `beta-04`
**Baseline:** `beta-03` (Phase A complete — 281 tests, all passing)
**Approach:** Greenfield — no backward compatibility with beta-03 workspace format
**Integrates:** `claude/session-restore-2-XTfCs` (tmux session backend)

---

## 1. Problem Statement

Phase A stabilized persistence and pane UX, but the underlying data model has structural problems that will compound as features are added.

### 1.1 Current Pain Points

**State Fragmentation (3-way split)**
State lives in three disconnected systems that must be manually kept in sync:

| System | Owns | Persistence |
|--------|------|-------------|
| `SessionManager` | `[OpenTab]`, `[Repo]`, `activeTabId` | JSON to `~/.agentstudio/workspaces/` |
| `TabBarState` | `[TabItem]`, `activeTabId`, `draggingTabId` | In-memory only |
| `SurfaceManager` | `[ManagedSurface]`, `undoStack` | `~/.agentstudio/surface-checkpoint.json` |

Every structural mutation (open, close, split, merge, break up, extract, undo close, reorder) must update all three systems manually.

**No Session Identity**
There is no concept of a "terminal session" independent of its layout position. A terminal's identity is scattered across `OpenTab.worktreeId`, `TabItem.primaryWorktreeId`, `AgentStudioTerminalView.containerId`, and `ManagedSurface.id`. Closing a tab destroys the only reference to the terminal — there's no way to move a terminal between views or restore it in a different layout.

**Tab Identity Coupling**
`OpenTab` stores a single `worktreeId` + `repoId`, but tabs can contain multiple panes from different worktrees. The "primary" worktree concept (`TabItem.primaryWorktreeId`) is a workaround, not a model.

**Opaque Split Tree Serialization**
`OpenTab.splitTreeData` stores the entire `SplitTree<AgentStudioTerminalView>` as an opaque `Data?` blob. The split layout is invisible to queries, holds live `NSView` references, and decodes by calling `SessionManager.shared` for lookups.

**Worktree Scope Mismatch**
`Worktree` carries `agent: AgentType?` and `status: WorktreeStatus` — these are session-level concerns (what's running in a terminal right now), not worktree-level concerns (what branch is checked out where).

**No View Concept**
There is a single implicit view (one set of tabs). No way to save layouts, switch between arrangements, or auto-generate views per worktree/repo.

---

## 2. Design Goals

1. **Session as primary entity** — A `TerminalSession` is the stable identity for a running terminal. It exists independently of layout, view, or surface.
2. **Single ownership boundary** — `WorkspaceStore` owns all persisted state. Other services are collaborators, not peers.
3. **Explicit layout model** — Split tree stored as a structured, queryable model. Leaves reference sessions by ID.
4. **View model** — Multiple named views (main, saved, worktree, dynamic) organize sessions into layouts. Switching views reattaches surfaces — no recreation.
5. **Provider abstraction** — tmux is a headless restore backend. The model carries provider metadata without coupling to tmux specifics.
6. **Surface independence** — Surfaces are ephemeral runtime resources. Model layer never holds `NSView` references.
7. **Testability** — Core model and layout logic are pure value types. No singletons or `@MainActor` requirements.

---

## 3. Core Entities

### 3.1 Entity Relationship Diagram

```
Workspace (schemaVersion: 2)
├── repos: [Repo]
│   └── worktrees: [Worktree]         ← git branches on disk
│
├── sessions: [TerminalSession]        ← independent terminal identities
│   ├── id: UUID                       ← stable primary key
│   ├── source: TerminalSource         ← what this terminal is for
│   ├── containerId: UUID              ← stable surface container key
│   ├── provider: SessionProvider      ← .ghostty | .tmux
│   └── providerHandle: String?        ← opaque backend ID (e.g., tmux session name)
│
├── views: [ViewDefinition]            ← named arrangements of sessions
│   ├── kind: ViewKind                 ← main | saved | worktree | dynamic
│   └── tabs: [Tab]                    ← tab arrangement within this view
│       └── layout: Layout             ← split tree of session references
│           └── leaf: sessionId: UUID  ← pointer into sessions[]
│
├── activeViewId: UUID?
└── uiState: UIState                   ← transient persisted UI
```

### 3.2 TerminalSession

The primary entity. Stable identity for a terminal, independent of layout position, view, or surface.

```swift
struct TerminalSession: Codable, Identifiable, Hashable {
    let id: UUID
    var source: TerminalSource
    let containerId: UUID           // matches SurfaceContainer.containerId, never changes
    var title: String
    var agent: AgentType?
    var provider: SessionProvider
    var providerHandle: String?     // opaque to model (e.g., tmux session name)

    init(
        id: UUID = UUID(),
        source: TerminalSource,
        containerId: UUID = UUID(),
        title: String = "Terminal",
        agent: AgentType? = nil,
        provider: SessionProvider = .ghostty,
        providerHandle: String? = nil
    ) { ... }

    // Convenience accessors
    var worktreeId: UUID? { if case .worktree(let id, _) = source { return id }; return nil }
    var repoId: UUID? { if case .worktree(_, let id) = source { return id }; return nil }
}

enum SessionProvider: String, Codable, Hashable {
    case ghostty    // direct Ghostty surface, no session multiplexer
    case tmux       // headless tmux backend for persistence/restore
}
```

**Relationship to tmux branch:**
- `TerminalSession.id` = our primary key (UUID)
- `TerminalSession.providerHandle` = `PaneSessionHandle.id` (String, e.g., `"agentstudio--a1b2c3d4--e5f6g7h8"`)
- `SessionRegistry` manages runtime state machines per session (alive/dead/verifying) — that state is NOT persisted in `TerminalSession`, it's derived at runtime.

### 3.3 TerminalSource

```swift
enum TerminalSource: Codable, Hashable {
    case worktree(worktreeId: UUID, repoId: UUID)
    case floating(workingDirectory: URL?, title: String?)
}
```

`TerminalSource.worktree` references are **metadata, not foreign key constraints**. A session with `.worktree(id: X, repoId: Y)` continues to function if worktree X is removed from the workspace. The UI displays fallback text ("Unknown worktree"). The session's working directory and process are unaffected.

### 3.4 Layout

Pure value type split tree. Leaves reference sessions by ID. No NSView references, no embedded objects.

```swift
struct Layout: Codable, Hashable {
    let root: Node?

    indirect enum Node: Codable, Hashable {
        case leaf(sessionId: UUID)
        case split(Split)
    }

    struct Split: Codable, Hashable {
        let id: UUID
        let direction: SplitDirection
        var ratio: Double               // clamped: 0.1–0.9
        let left: Node
        let right: Node
    }

    enum SplitDirection: String, Codable, Hashable {
        case horizontal
        case vertical
    }

    // MARK: - Init
    init()
    init(root: Node?)
    init(sessionId: UUID)   // single-session layout

    // MARK: - Properties
    var isEmpty: Bool
    var isSplit: Bool
    var sessionIds: [UUID]  // all leaf session IDs (left-to-right traversal)

    // MARK: - Queries
    func contains(_ sessionId: UUID) -> Bool

    // MARK: - Immutable Operations (return new Layout)
    func inserting(sessionId: UUID, at target: UUID,
                   direction: SplitDirection, position: Position) -> Layout
    func removing(sessionId: UUID) -> Layout?
    func resizing(splitId: UUID, ratio: Double) -> Layout
    func equalized() -> Layout

    enum Position { case before, after }  // before=left/up, after=right/down

    // MARK: - Navigation
    func neighbor(of sessionId: UUID, direction: FocusDirection) -> UUID?
    func next(after sessionId: UUID) -> UUID?
    func previous(before sessionId: UUID) -> UUID?

    // MARK: - Codable (version-tagged)
    private static var currentVersion: Int { 1 }
}

enum FocusDirection: Equatable, Hashable {
    case left, right, up, down
}
```

### 3.5 Tab

A tab within a view. Contains a layout and tracks which session is focused. Order is implicit (array position in the parent view's `tabs` array).

```swift
struct Tab: Codable, Identifiable, Hashable {
    let id: UUID
    var layout: Layout
    var activeSessionId: UUID?   // focused session within this tab

    init(id: UUID = UUID(), sessionId: UUID) {
        self.id = id
        self.layout = Layout(sessionId: sessionId)
        self.activeSessionId = sessionId
    }

    init(id: UUID = UUID(), layout: Layout, activeSessionId: UUID?) {
        self.id = id
        self.layout = layout
        self.activeSessionId = activeSessionId
    }

    // Derived
    var sessionIds: [UUID] { layout.sessionIds }
    var isSplit: Bool { layout.isSplit }
}
```

No `order` field — order is the array index in `ViewDefinition.tabs`.

### 3.6 ViewDefinition

A named arrangement of sessions into tabs. Multiple views can reference the same sessions.

```swift
struct ViewDefinition: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var kind: ViewKind
    var tabs: [Tab]
    var activeTabId: UUID?

    // Derived
    var allSessionIds: [UUID] { tabs.flatMap(\.sessionIds) }
}

enum ViewKind: Codable, Hashable {
    case main                               // default view, always exists
    case saved                              // user-persisted layout
    case worktree(worktreeId: UUID)          // auto-generated for a worktree
    case dynamic(rule: DynamicViewRule)      // rule-based (resolved at runtime)
}

enum DynamicViewRule: Codable, Hashable {
    case byRepo(repoId: UUID)              // all sessions for a repo
    case byAgent(AgentType)                // all sessions running a specific agent
    case custom(name: String)              // future: user-defined filter
}
```

**View lifecycle:**
- `main` always exists. Created on first launch. Cannot be deleted.
- `saved` is created explicitly by the user ("Save current layout"). Persisted.
- `worktree` is auto-generated when a worktree view is requested. Shows sessions for that worktree.
- `dynamic` is resolved at runtime from rules. Ephemeral unless explicitly saved (→ becomes `saved`).

### 3.7 Worktree (slimmed)

```swift
struct Worktree: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var path: URL
    var branch: String
    // REMOVED: agent, status (now on TerminalSession)
}
```

### 3.8 Repo (unchanged)

```swift
struct Repo: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var repoPath: URL
    var worktrees: [Worktree]
    var createdAt: Date
    var updatedAt: Date
}
```

### 3.9 Workspace

```swift
struct Workspace: Codable, Identifiable {
    let id: UUID
    var schemaVersion: Int = 2
    var name: String
    var repos: [Repo]
    var sessions: [TerminalSession]
    var views: [ViewDefinition]
    var activeViewId: UUID?
    var sidebarWidth: CGFloat
    var windowFrame: CGRect?
    var createdAt: Date
    var updatedAt: Date
}
```

### 3.10 UIState (transient persisted state)

```swift
/// Persisted but non-structural UI state.
/// Saved to workspace but not part of the core model.
struct UIState: Codable {
    var sidebarWidth: CGFloat
    var windowFrame: CGRect?
}
```

---

## 4. Runtime Architecture

### 4.1 WorkspaceStore — Single Ownership Boundary

```swift
/// Owns ALL persisted workspace state.
/// Single source of truth. All mutations go through here.
/// Collaborators (ViewRegistry, SessionRuntime, WorkspacePersistor) are internal — not peers.
@MainActor
final class WorkspaceStore: ObservableObject {

    // MARK: - Persisted State (drives UI via @Published)

    @Published private(set) var repos: [Repo] = []
    @Published private(set) var sessions: [TerminalSession] = []
    @Published private(set) var views: [ViewDefinition] = []
    @Published private(set) var activeViewId: UUID?

    // MARK: - Transient UI State

    @Published var draggingTabId: UUID?
    @Published var dropTargetIndex: Int?
    @Published var tabFrames: [UUID: CGRect] = [:]

    // MARK: - Collaborators (internal, not public peers)

    private let persistor: WorkspacePersistor
    private let repoDiscovery: WorktrunkService

    // MARK: - Derived State

    var activeView: ViewDefinition? { views.first { $0.id == activeViewId } }
    var activeTabs: [Tab] { activeView?.tabs ?? [] }
    var activeTabId: UUID? { activeView?.activeTabId }

    /// All sessions visible in the active view.
    var activeSessionIds: Set<UUID> { Set(activeView?.allSessionIds ?? []) }

    /// Is a worktree active (has any session in any view)?
    func isWorktreeActive(_ worktreeId: UUID) -> Bool {
        sessions.contains { $0.worktreeId == worktreeId }
    }

    /// Count of active sessions for a worktree.
    func sessionCount(for worktreeId: UUID) -> Int {
        sessions.count { $0.worktreeId == worktreeId }
    }

    // MARK: - Session Mutations

    @discardableResult
    func createSession(source: TerminalSource, provider: SessionProvider = .ghostty) -> TerminalSession
    func removeSession(_ sessionId: UUID)
    func updateSessionTitle(_ sessionId: UUID, title: String)
    func updateSessionAgent(_ sessionId: UUID, agent: AgentType?)
    func setProviderHandle(_ sessionId: UUID, handle: String)

    // MARK: - View Mutations

    func switchView(_ viewId: UUID)
    @discardableResult
    func createView(name: String, kind: ViewKind) -> ViewDefinition
    func deleteView(_ viewId: UUID)  // cannot delete main
    func saveCurrentViewAs(name: String) -> ViewDefinition  // snapshot → saved

    // MARK: - Tab Mutations (within active view)

    func appendTab(_ tab: Tab)
    func removeTab(_ tabId: UUID)
    func insertTab(_ tab: Tab, at index: Int)
    func moveTab(fromId: UUID, toIndex: Int)
    func setActiveTab(_ tabId: UUID?)

    // MARK: - Layout Mutations (within a tab in the active view)

    func insertSession(_ sessionId: UUID, inTab tabId: UUID,
                        at targetSessionId: UUID,
                        direction: Layout.SplitDirection,
                        position: Layout.Position)
    func removeSessionFromLayout(_ sessionId: UUID, inTab tabId: UUID)
    func resizePane(tabId: UUID, splitId: UUID, ratio: Double)
    func equalizePanes(tabId: UUID)
    func setActiveSession(_ sessionId: UUID?, inTab tabId: UUID)

    // MARK: - Compound Operations

    func breakUpTab(_ tabId: UUID) -> [Tab]
    func extractSession(_ sessionId: UUID, fromTab tabId: UUID) -> Tab?
    func mergeTab(sourceId: UUID, intoTarget targetId: UUID,
                  at targetSessionId: UUID,
                  direction: Layout.SplitDirection,
                  position: Layout.Position)

    // MARK: - Repo Mutations

    @discardableResult
    func addRepo(at path: URL) -> Repo
    func removeRepo(_ repoId: UUID)
    func refreshWorktrees(for repoId: UUID)

    // MARK: - Queries

    func session(_ id: UUID) -> TerminalSession?
    func tab(_ id: UUID) -> Tab?
    func tabContaining(sessionId: UUID) -> Tab?
    func repo(_ id: UUID) -> Repo?
    func worktree(_ id: UUID) -> Worktree?
    func repo(containing worktreeId: UUID) -> Repo?
    func sessions(for worktreeId: UUID) -> [TerminalSession]

    // MARK: - Persistence

    func restore()   // load from disk on launch
    func save()      // immediate save (structural changes)

    /// Debounced save for high-frequency operations (resize, drag).
    /// Coalesces writes within a 500ms window.
    func debouncedSave()

    // MARK: - Undo

    /// Snapshot for undo close. Captures tab + layout + session references.
    struct CloseSnapshot: Codable {
        let tab: Tab
        let sessions: [TerminalSession]
        let viewId: UUID
        let tabIndex: Int
    }

    func snapshotForClose(tabId: UUID) -> CloseSnapshot?
    func restoreFromSnapshot(_ snapshot: CloseSnapshot)
}
```

### 4.2 ViewRegistry — NSView Bridge

```swift
/// Maps session IDs to live AgentStudioTerminalView instances.
/// Runtime only — not persisted. Collaborator of WorkspaceStore.
@MainActor
final class ViewRegistry {
    private var views: [UUID: AgentStudioTerminalView] = [:]

    func register(_ view: AgentStudioTerminalView, for sessionId: UUID)
    func unregister(_ sessionId: UUID)
    func view(for sessionId: UUID) -> AgentStudioTerminalView?
    var registeredSessionIds: Set<UUID>

    /// Build a renderable SplitTree from a Layout.
    /// Returns nil if any session lacks a registered view.
    func renderTree(for layout: Layout) -> TerminalSplitTree?
}
```

### 4.3 SessionRuntime — Live Session Management

Wraps the existing `SessionRegistry` from the tmux branch. Manages state machines, health checks, and provider interactions.

```swift
/// Manages runtime lifecycle of terminal sessions.
/// Not an owner — reads session list from WorkspaceStore,
/// manages ephemeral state (alive/dead/verifying) independently.
@MainActor
final class SessionRuntime {
    private let backend: (any SessionBackend)?
    private var stateMachines: [UUID: Machine<SessionStatus>] = [:]

    /// Runtime status of a session (not persisted).
    func status(for sessionId: UUID) -> SessionStatus

    /// Get or create a tmux session for a TerminalSession.
    func ensureBackendSession(for session: TerminalSession, worktree: Worktree) async throws -> String

    /// Get the attach command for Ghostty to connect to a session.
    func attachCommand(for session: TerminalSession) -> String?

    /// Start health checks for all alive sessions.
    func startHealthChecks()
    func stopHealthChecks()

    /// Verify sessions after restore (check which tmux sessions survived).
    func verifyRestoredSessions(_ sessions: [TerminalSession]) async
}
```

### 4.4 TerminalViewCoordinator — View/Surface Bridge

```swift
/// Creates and tears down AgentStudioTerminalView instances.
/// Bridges model (TerminalSession) ↔ view (AgentStudioTerminalView) ↔ surface (SurfaceManager).
@MainActor
final class TerminalViewCoordinator {
    private let viewRegistry: ViewRegistry
    private let sessionRuntime: SessionRuntime
    private let store: WorkspaceStore

    /// Create a new terminal view for a session and register it.
    func createView(for session: TerminalSession, worktree: Worktree, repo: Repo) -> AgentStudioTerminalView

    /// Create a restoring view (deferred setup, no surface creation).
    func createRestoringView(for session: TerminalSession, worktree: Worktree, repo: Repo) -> AgentStudioTerminalView

    /// Create view for undo close (reattach existing surface).
    func createUndoView(for session: TerminalSession, worktree: Worktree, repo: Repo, surfaceId: UUID) -> AgentStudioTerminalView

    /// Tear down a view and detach its surface.
    func teardownView(for sessionId: UUID, reason: SurfaceDetachReason)

    /// Attach/detach views when switching views.
    /// Detaches surfaces for sessions leaving the active view,
    /// attaches surfaces for sessions entering the active view.
    func handleViewSwitch(from oldView: ViewDefinition?, to newView: ViewDefinition)
}
```

### 4.5 ActionExecutor

```swift
/// Executes validated PaneActions by coordinating WorkspaceStore,
/// ViewRegistry, and TerminalViewCoordinator.
@MainActor
final class ActionExecutor {
    private let store: WorkspaceStore
    private let viewRegistry: ViewRegistry
    private let viewCoordinator: TerminalViewCoordinator

    func execute(_ action: PaneAction)
}
```

### 4.6 SurfaceManager (unchanged)

`SurfaceManager` continues to own Ghostty surfaces. API unchanged. `TerminalSession.containerId` is the join key to `SurfaceState.active(containerId:)`.

---

## 5. Data Flow

### 5.1 Mutation Flow

```
User Action (keyboard / mouse / drag)
        │
        ▼
  AppCommand / DropEvent
        │
        ▼
  ActionResolver.resolve()          ← pure function → PaneAction?
        │
        ▼
  ActionValidator.validate()        ← pure function, checks invariants
        │
        ▼
  ActionExecutor.execute()          ← coordinates store + views + surfaces
        │
        ├─► WorkspaceStore.mutate() ← single state mutation
        │     │
        │     ├── @Published fires  → SwiftUI re-renders
        │     └── save() or         → JSON to disk
        │         debouncedSave()
        │
        └─► TerminalViewCoordinator ← creates/destroys views + surfaces
              │
              ├── ViewRegistry.register/unregister
              └── SurfaceManager.attach/detach/create
```

### 5.2 Restore Flow

```
App Launch
    │
    ▼
WorkspacePersistor.load()   →  Workspace (schemaVersion: 2)
    │
    ▼
WorkspaceStore.restore()
    │
    ├── repos → WorktrunkService.discoverWorktrees() → merge
    │
    ├── sessions → For each TerminalSession:
    │     └── SessionRuntime.verifyRestoredSessions()
    │           └── If provider == .tmux: check backend.healthCheck()
    │
    └── views → Activate activeViewId
          └── For each Tab in active view:
                └── For each sessionId in tab.layout:
                      ├── TerminalViewCoordinator.createRestoringView()
                      ├── ViewRegistry.register()
                      └── SurfaceManager.createSurface() + attach()
```

### 5.3 View Switch Flow

```
User switches from View A to View B
    │
    ▼
WorkspaceStore.switchView(viewB.id)
    │
    ├── Set activeViewId = viewB.id
    ├── save()
    │
    └── TerminalViewCoordinator.handleViewSwitch(from: A, to: B)
          │
          ├── Sessions only in A (not in B):
          │     └── SurfaceManager.detach(reason: .hide)
          │         ViewRegistry.unregister()
          │
          ├── Sessions in both A and B:
          │     └── No surface change (already attached)
          │         ViewRegistry stays registered
          │
          └── Sessions only in B (not in A):
                └── TerminalViewCoordinator.createView()
                    ViewRegistry.register()
                    SurfaceManager.attach()
```

### 5.4 Undo Close Flow

```
User closes tab (or last pane in tab)
    │
    ├── WorkspaceStore.snapshotForClose() → CloseSnapshot
    │     (captures Tab, sessions, viewId, tabIndex)
    │
    ├── SurfaceManager.detach(reason: .close) for each session
    │     (surfaces enter undo stack with TTL)
    │
    ├── WorkspaceStore.removeTab()
    │     (sessions remain in workspace.sessions — NOT removed)
    │
    └── Push CloseSnapshot onto undo stack

User presses Cmd+Shift+T
    │
    ├── Pop CloseSnapshot
    │
    ├── WorkspaceStore.restoreFromSnapshot()
    │     (re-inserts Tab at original position in original view)
    │
    ├── SurfaceManager.undoClose() → get ManagedSurface back
    │
    └── TerminalViewCoordinator.createUndoView() for each session
          (reattaches existing surfaces — no recreation)
```

---

## 6. Persistence Policy

### 6.1 Write Strategy

| Operation Type | Write Timing | Examples |
|---|---|---|
| Structural | Immediate | Open/close tab, add/remove session, split, merge, break up, extract, view switch |
| High-frequency | Debounced (500ms) | Resize drag, tab reorder drag |
| Transient | On quit only | Window frame, sidebar width |

### 6.2 Schema Versioning

```swift
struct Workspace: Codable {
    var schemaVersion: Int = 2
    // ...
}
```

On load:
- `schemaVersion == 2` → decode normally
- `schemaVersion == 1` or missing → discard and start fresh (greenfield for beta-04)
- Unknown future version → fail safe, log error, start fresh

---

## 7. Invariants

1. **Session ID uniqueness** — Every `TerminalSession.id` is unique within the workspace.
2. **Container ID uniqueness** — Every `TerminalSession.containerId` is unique. No two sessions share a container.
3. **Tab minimum** — A `Tab` always has at least one session in its layout. Removing the last session closes the tab.
4. **Active session validity** — `Tab.activeSessionId` always references a session in that tab's layout, or is nil only during construction.
5. **Active tab validity** — `ViewDefinition.activeTabId` always references a tab in that view, or is nil when no tabs exist.
6. **Active view validity** — `Workspace.activeViewId` always references a view in `views`, or is nil.
7. **Main view always exists** — `views` always contains exactly one view with `kind == .main`. It cannot be deleted.
8. **Layout tree structure** — Every split has exactly two children. Leaves contain valid session IDs.
9. **Split ratios clamped** — `0.1 ≤ ratio ≤ 0.9`.
10. **Source is metadata** — `TerminalSource.worktree(id, repoId)` may reference a worktree that no longer exists. The session survives. UI shows fallback text.
11. **Session independence** — Removing a session from a layout does NOT remove it from `workspace.sessions`. Sessions are explicitly removed only when the user closes them (not when layouts change).
12. **No NSView in model** — No model type (`TerminalSession`, `Layout`, `Tab`, `ViewDefinition`, `Workspace`) holds NSView references.

---

## 8. Integration with tmux Branch

The `claude/session-restore-2-XTfCs` branch provides:

| Existing Type | Role | Integration |
|---|---|---|
| `SessionBackend` (protocol) | Provider abstraction | Used by `SessionRuntime` |
| `TmuxBackend` | tmux implementation | Concrete backend for `provider == .tmux` |
| `SessionStatus` (enum) | State machine states | Runtime state per session (not persisted) |
| `Machine<SessionStatus>` | Generic state machine | Used by `SessionRuntime` |
| `PaneSessionHandle` | Backend session identifier | `TerminalSession.providerHandle = handle.id` |
| `SessionCheckpoint` | Backend persistence | Merged into `Workspace` persistence (sessions array) |
| `SessionConfiguration` | Backend config | Used by `SessionRuntime` on init |
| `ProcessExecutor` | CLI abstraction | Unchanged, used by `TmuxBackend` |

**Key mapping:**
- `PaneSessionHandle.id` (String, e.g., `"agentstudio--a1b2--c3d4"`) → `TerminalSession.providerHandle`
- `SessionRegistry.entries` → `SessionRuntime.stateMachines` (keyed by `TerminalSession.id`, not String)
- `SessionCheckpoint` → no longer a separate file. Session metadata is in `Workspace.sessions`. Backend-specific state (tmux socket existence) is verified at runtime.

**What changes in the tmux branch code:**
- `SessionRegistry` is refactored into `SessionRuntime` (reads session list from `WorkspaceStore`, doesn't own it)
- `PaneSessionHandle` stays but is constructed from `TerminalSession` properties
- `SessionCheckpoint` as a separate file is eliminated — `WorkspaceStore` persists sessions
- `TmuxBackend`, `SessionBackend`, `SessionStatus`, `Machine`, `ProcessExecutor` — unchanged

---

## 9. Action Pipeline Alignment

### 9.1 PaneAction Updates

`PaneAction` cases stay the same, but semantic meaning shifts:

| Case | Before (Pane-centric) | After (Session-centric) |
|---|---|---|
| `.insertPane(source:...)` | Inserts an NSView-bearing pane | Inserts a session reference into a layout |
| `.closePane(tabId:paneId:)` | Destroys pane + surface | Removes session from layout; session survives if referenced elsewhere |
| `.extractPaneToTab(...)` | Creates new tab with pane's NSView | Moves session ID to new tab's layout |
| `.mergeTab(...)` | Moves NSViews between tabs | Moves session IDs between layouts |

The `paneId` parameters in `PaneAction` now refer to `sessionId` (since layout leaves ARE session references). No rename needed if we treat "pane" as the UI concept for "a session's position in a layout."

### 9.2 PaneSource Updates

```swift
enum PaneSource: Equatable, Hashable {
    case existingSession(sessionId: UUID, sourceTabId: UUID)  // was: existingPane
    case newTerminal
}
```

### 9.3 ActionResolver

Same resolution logic. Input type changes from generic `ResolvableTab` to concrete `Tab`:

```swift
extension Tab: ResolvableTab {
    var allPaneIds: [UUID] { sessionIds }
    var activePaneId: UUID? { activeSessionId }

    func neighborPaneId(of id: UUID, direction: SplitFocusDirection) -> UUID? {
        layout.neighbor(of: id, direction: ...)
    }
    func nextPaneId(after id: UUID) -> UUID? { layout.next(after: id) }
    func previousPaneId(before id: UUID) -> UUID? { layout.previous(before: id) }
}
```

---

## 10. Derived State (Runtime, Not Persisted)

All "is open" / "is active" state is derived from session and layout membership:

```swift
extension WorkspaceStore {
    /// Is this worktree active? (has any session)
    func isWorktreeActive(_ worktreeId: UUID) -> Bool {
        sessions.contains { $0.worktreeId == worktreeId }
    }

    /// Sessions for a worktree
    func sessions(for worktreeId: UUID) -> [TerminalSession] {
        sessions.filter { $0.worktreeId == worktreeId }
    }

    /// Is this session visible in the active view?
    func isSessionVisible(_ sessionId: UUID) -> Bool {
        activeView?.allSessionIds.contains(sessionId) ?? false
    }

    /// Runtime status of a session (from SessionRuntime state machine)
    func runtimeStatus(for sessionId: UUID) -> SessionStatus {
        sessionRuntime.status(for: sessionId)
    }
}
```

No persisted `isOpen` flags. No `WorktreeStatus` on `Worktree`. Sidebar derives everything from live data.

---

## 11. Decomposition Summary

### SessionManager → decomposed into:

| Responsibility | New Location |
|---|---|
| Persisted state ownership | `WorkspaceStore` |
| Tab lifecycle | `WorkspaceStore` |
| Repo management | `WorkspaceStore` |
| Worktree discovery | `WorktrunkService` (unchanged, called by `WorkspaceStore`) |
| Persistence I/O | `WorkspacePersistor` (collaborator of `WorkspaceStore`) |
| Lookup helpers | `WorkspaceStore` queries |

### TerminalTabViewController → decomposed into:

| Responsibility | New Location |
|---|---|
| State mutations | `WorkspaceStore` |
| Action dispatch | `ActionExecutor` |
| View creation/teardown | `TerminalViewCoordinator` |
| Tab bar setup, empty state | Stays in `TerminalTabViewController` |

### TabBarState → merged into:

| Field | New Location |
|---|---|
| `tabs`, `activeTabId` | `WorkspaceStore` (via active `ViewDefinition`) |
| `draggingTabId`, `dropTargetIndex`, `tabFrames` | `WorkspaceStore` (transient) |

### SplitTree<AgentStudioTerminalView> → split into:

| Concern | New Type |
|---|---|
| Model (what sessions are where) | `Layout` (value type, sessionId leaves) |
| View (what NSViews to render) | `TerminalSplitTree` (built by `ViewRegistry.renderTree()`) |

---

## 12. Test Strategy

### 12.1 Unit Tests (pure value types, no @MainActor)

| Target | Coverage |
|---|---|
| `Layout` | Insert, remove, resize, equalize, navigation, codable round-trip, version tag |
| `Tab` | Derived properties (`sessionIds`, `isSplit`, construction) |
| `TerminalSession` | Init, convenience accessors, codable |
| `ViewDefinition` | `allSessionIds`, kind, tab management |
| `Workspace` | Codable round-trip with all nested types, schema version |
| `ActionResolver` | Same tests, input type = `Tab` |
| `RepoService.mergeWorktrees` | Port from `SessionManagerTests` |

### 12.2 Integration Tests

| Target | Coverage |
|---|---|
| `WorkspaceStore` | Mutations, invariant enforcement, save triggers, derived state |
| `ViewRegistry` | Register/unregister, `renderTree` correctness |
| `WorkspacePersistor` | Save/load round-trip, schema version handling, missing file |
| `SessionRuntime` | State machine transitions, health check scheduling |
| `TerminalViewCoordinator` | View switch attach/detach, undo close restore |

### 12.3 Ported Tests

All 281 existing tests are ported to new locations. `SessionManagerTests` static helpers → `WorkspaceStore` or extracted pure functions.

---

## 13. File Inventory

### New Files

| File | Purpose |
|---|---|
| `Models/TerminalSession.swift` | `TerminalSession`, `SessionProvider` |
| `Models/Layout.swift` | `Layout`, `FocusDirection` |
| `Models/Tab.swift` | `Tab` |
| `Models/ViewDefinition.swift` | `ViewDefinition`, `ViewKind`, `DynamicViewRule` |
| `Services/WorkspaceStore.swift` | Single ownership boundary |
| `Services/WorkspacePersistor.swift` | Pure persistence I/O |
| `Services/ViewRegistry.swift` | Session ID → NSView mapping |
| `Services/SessionRuntime.swift` | Live session state machines (wraps tmux branch) |
| `App/ActionExecutor.swift` | Executes validated PaneActions |
| `App/TerminalViewCoordinator.swift` | View/surface lifecycle bridge |
| `Tests/.../LayoutTests.swift` | Layout tests |
| `Tests/.../TabTests.swift` | Tab tests |
| `Tests/.../TerminalSessionTests.swift` | Session tests |
| `Tests/.../ViewDefinitionTests.swift` | View tests |
| `Tests/.../WorkspaceStoreTests.swift` | Store integration tests |

### Modified Files

| File | Changes |
|---|---|
| `Models/Workspace.swift` | New shape: `sessions`, `views`, `schemaVersion`. Remove `OpenTab`. |
| `Models/Worktree.swift` | Remove `agent`, `status`. |
| `App/TerminalTabViewController.swift` | Delegate to `ActionExecutor` + `TerminalViewCoordinator`. |
| `Views/CustomTabBar.swift` | Read from `WorkspaceStore`. Remove `TabItem`, `TabBarState`. |
| `Views/DraggableTabBarHostingView.swift` | Read from `WorkspaceStore`. |
| `Actions/ActionResolver.swift` | `Tab` conforms to `ResolvableTab`. |
| `Actions/PaneAction.swift` | `PaneSource.existingSession` rename. |
| `App/MainSplitViewController.swift` | Use `WorkspaceStore` for repo operations + derived state. |
| `Views/AgentStudioTerminalView.swift` | Remove Codable self-decode via `SessionManager.shared`. |

### Deleted Files

| File | Replaced By |
|---|---|
| `Services/SessionManager.swift` | `WorkspaceStore` |

### Unchanged Files

| File | Reason |
|---|---|
| `Ghostty/SurfaceManager.swift` | Independent surface lifecycle |
| `Ghostty/SurfaceTypes.swift` | All types valid |
| `Ghostty/GhosttySurfaceView.swift` | Ghostty integration unchanged |
| `Services/Backends/TmuxBackend.swift` | Provider implementation unchanged |
| `Services/SessionBackend.swift` | Protocol unchanged |
| `Models/StateMachine/` | State machine unchanged |
| `Actions/ActionStateSnapshot.swift` | Validation unchanged |
| `Actions/ActionValidator.swift` | Validation unchanged |
| `App/AppCommand.swift` | Commands unchanged |
| `Views/Splits/SplitTree.swift` | Still used for rendering |
| `Views/Splits/TerminalSplitContainer.swift` | Rendering unchanged |
| `Views/Splits/TerminalPaneLeaf.swift` | Pane UI unchanged |

---

## 14. Implementation Phases

### Phase B1: Core Model Types
- `TerminalSession`, `Layout`, `Tab`, `ViewDefinition`, `Workspace` (v2)
- Unit tests for all model types
- Codable round-trips
- Layout tree operations + navigation

### Phase B2: WorkspaceStore + Persistence
- `WorkspaceStore` with all mutations
- `WorkspacePersistor` with schema versioning
- Immediate + debounced save paths
- Invariant enforcement
- Integration tests

### Phase B3: View + Surface Bridge
- `ViewRegistry`
- `TerminalViewCoordinator`
- `ActionExecutor`
- Wire to `TerminalTabViewController`
- Surface attach/detach on view switch

### Phase B4: SessionRuntime Integration
- Refactor `SessionRegistry` → `SessionRuntime`
- Wire tmux backend to `WorkspaceStore.sessions`
- Health checks, restore verification

### Phase B5: View Engine (can defer)
- View resolver for dynamic/worktree views
- "Save dynamic as saved" flow
- View switcher UI

### Phase B6: Templates (can defer)
- `WorktreeTemplate`, `TerminalTemplate`
- Create policies (onCreate, onActivate, manual)

---

## 15. Resolved Questions

1. **Tab order** — Implicit (array position). No `order` field on `Tab`.
2. **Undo close** — Restores exact `Tab` + `TerminalSession` model at original position in original view via `CloseSnapshot`.
3. **Workspace = window** — One workspace per window. Fine for now.
4. **Pane vs Session** — `TerminalSession` is the primary entity. Layout leaves reference `sessionId`. "Pane" is the UI concept for a session's position in a layout. 1:1 at any point in time, but a session can appear in different layout positions across views.
5. **tmux scope** — In scope as provider metadata (`SessionProvider`, `providerHandle`). tmux branch code integrates via `SessionRuntime`. tmux is fully headless — a restore backend, not a UI concept.
6. **Orphan handling** — `TerminalSource.worktree` references are metadata, not foreign keys. Sessions survive worktree removal.
7. **Persistence policy** — Structural = immediate. High-frequency (resize/drag) = debounced 500ms. Transient (window frame) = on quit.
8. **SSoT definition** — `WorkspaceStore` is the single ownership boundary. `ViewRegistry`, `SessionRuntime`, `WorkspacePersistor` are collaborators, not peers.
