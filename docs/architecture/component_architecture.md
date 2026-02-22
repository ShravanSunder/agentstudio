# Component Architecture

## TL;DR

State is distributed across independent `@Observable` stores (Jotai-style atomic stores) with `private(set)` for unidirectional flow (Valtio-style). `WorkspaceStore` owns workspace structure, `SurfaceManager` owns Ghostty surfaces, `SessionRuntime` owns backends. A coordinator sequences cross-store operations. `Pane` is the primary identity — referenced by UUID across every layer. Layouts are immutable value-type trees where leaves point to pane IDs. `@Observable` drives SwiftUI re-renders; persistence is debounced. Twelve invariants are enforced at all times.

---

## 1. Overview

### 1.1 Architecture Principles

1. **Pane as primary entity** — A `Pane` exists independently of layout, view, or surface. It can move between tabs, views, and layout positions while keeping the same identity.
2. **Atomic stores (Jotai-style)** — Each domain has its own `@Observable` store. `WorkspaceStore` owns workspace structure (tabs, layouts, views). `SurfaceManager` owns Ghostty surfaces. `SessionRuntime` owns backends. No god-store — each store has one domain, one reason to change, testable in isolation.
3. **Unidirectional flow (Valtio-style)** — All store state is `private(set)`. External code reads freely, mutates only through store methods. No action enums, no reducers — the compiler enforces the boundary.
4. **Coordinator for cross-store sequencing** — A coordinator sequences operations across multiple stores for a single user action. Owns no state, contains no domain logic. If a coordinator method contains an `if` that decides what to do with domain data, that logic belongs in a store.
5. **Explicit layout model** — The split tree is a structured, queryable `Layout` value type. Leaves reference panes by ID. No `NSView` references, no opaque blobs.
6. **View model** — Multiple named `ViewDefinition`s organize panes into tab arrangements. Switching views reattaches surfaces without recreation.
7. **Surface independence** — Ghostty surfaces are ephemeral runtime resources. The model layer never holds `NSView` references.
8. **Provider abstraction** — zmx is a headless restore backend. The model carries provider metadata without coupling to zmx specifics.
9. **AsyncStream over Combine/NotificationCenter** — All new event plumbing uses `AsyncStream` + `swift-async-algorithms`. Existing Combine/NotificationCenter migrated incrementally.
10. **Testability** — Core model and layout logic are pure value types. Injectable `Clock` for time-dependent logic. No real delays in tests.

Clock migration note (target pattern, not fully complete yet): remaining production `Task.sleep` call sites are in
`WorkspaceStore`, `SessionRuntime`, `SurfaceManager`, `MainSplitViewController`, and `AppDelegate`. The target is
constructor-injected clocks (`any Clock<Duration>`) for all store-level time-dependent behavior.

Configuration injection pattern: prefer constructor injection with defaults over mutable configuration vars. Example:
`init(clock: any Clock<Duration> = ContinuousClock(), ...)` and `private let` configuration fields.

### 1.2 High-Level System Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                            AppDelegate                               │
│                                                                      │
│   Persisted State            Runtime                   UI Bridge     │
│  ┌──────────────┐    ┌───────────────┐    ┌──────────────────────┐   │
│  │WorkspaceStore│    │SessionRuntime │    │    ViewRegistry       │   │
│  │ repos        │    │ statuses      │    │ paneId → NSView   │   │
│  │ panes        │◄───│ backends      │    │ renderTree()         │   │
│  │ views        │    └───────┬───────┘    └──────────┬───────────┘   │
│  │ activeViewId │            │                       │               │
│  └──────┬───────┘            │                       │               │
│         │            ┌───────┴───────────────────────┴────────┐      │
│         │            │      PaneCoordinator            │      │
│         │            │   (sole bridge: model ↔ view ↔ surface) │      │
│         │            └───────────────────┬────────────────────┘      │
│         │                                │                           │
│  ┌──────┴──────┐                ┌────────┴────────┐                  │
│  │   Action    │                │ SurfaceManager  │                  │
│  │  Executor   │                │   (singleton)   │                  │
│  │ (dispatch)  │                │ active|hidden   │                  │
│  └─────────────┘                │ |undoStack      │                  │
│                                 └─────────────────┘                  │
│  ┌─────────────┐  ┌────────────┐  ┌──────────────┐                  │
│  │TabBarAdapter│  │ Persistor  │  │WorktrunkSvc  │                  │
│  │(derived UI) │  │ (JSON I/O) │  │(git worktree)│                  │
│  └─────────────┘  └────────────┘  └──────────────┘                  │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 2. Data Model

### 2.1 Entity Relationship Overview

```mermaid
erDiagram
    WorkspaceStore ||--o{ Repo : "repos[]"
    WorkspaceStore ||--o{ Pane : "panes[]"
    WorkspaceStore ||--o{ ViewDefinition : "views[]"
    WorkspaceStore ||--o| ViewDefinition : "activeViewId"

    Repo ||--o{ Worktree : "worktrees[]"

    Pane }o--o| Worktree : "source.worktreeId"
    Pane }o--o| Repo : "source.repoId"

    ViewDefinition ||--o{ Tab : "tabs[]"
    ViewDefinition ||--o| Tab : "activeTabId"

    Tab ||--|| Layout : "layout"
    Tab ||--o| Pane : "activePaneId"

    Layout ||--o| LayoutNode : "root"
    LayoutNode ||--o| Pane : "leaf → paneId"
    LayoutNode ||--o{ LayoutNode : "split → left, right"
```

### 2.2 Repo & Worktree

**`Repo`** — A git repository on disk. Contains discovered worktrees.

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | Primary key |
| `name` | `String` | Directory name |
| `repoPath` | `URL` | Filesystem path |
| `worktrees` | `[Worktree]` | Discovered git worktrees |
| `createdAt` | `Date` | When the repo was added |
| `updatedAt` | `Date` | Last modification timestamp |
| `stableKey` | `String` | SHA-256 of path (16 hex chars), deterministic across reinstalls |

**`Worktree`** — A git worktree within a repo.

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | Primary key |
| `name` | `String` | Branch-derived display name |
| `path` | `URL` | Filesystem path |
| `branch` | `String` | Git branch name |
| `agent` | `AgentType?` | Which AI agent is assigned (claude, codex, gemini, aider, custom) |
| `status` | `WorktreeStatus` | Agent status (idle, running, pendingReview, error) |
| `stableKey` | `String` | SHA-256 of path (16 hex chars) |

> **File:** `Core/Models/Repo.swift`, `Core/Models/Worktree.swift`

### 2.3 Pane

The **primary entity**. Stable identity for a pane, independent of layout position, view, or surface. The `id` (UUID) is used across every layer: `WorkspaceStore`, `Layout`, `ViewRegistry`, `SurfaceManager`, `SessionRuntime`.

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | Immutable primary key, never changes |
| `content` | `PaneContent` | Pane payload (`.terminal`, `.webview`, `.codeViewer`, `.bridgePanel`) |
| `metadata` | `PaneMetadata` | Source/title/cwd/agent/tags context |
| `residency` | `SessionResidency` | Lifecycle position |
| `kind` | `PaneKind` | `.layout(drawer)` or `.drawerChild(parentPaneId)` |

**`TerminalSource`** — What a pane is for:
- `.worktree(worktreeId: UUID, repoId: UUID)` — Pane for a specific worktree. References are **metadata, not foreign keys**: the pane survives worktree removal; UI shows fallback text.
- `.floating(workingDirectory: URL?, title: String?)` — Standalone pane not tied to a worktree.

**`SessionProvider`** — Backend type:
- `.ghostty` — Direct Ghostty surface, no session multiplexer
- `.zmx` — Headless zmx backend for persistence/restore across app restarts

**`SessionLifetime`** — Whether a terminal pane survives app restart:
- `.persistent` — Saved to disk and restored on launch. Temporary panes are filtered out during save and restore.
- `.temporary` — Ephemeral, never persisted.

**`SessionResidency`** — Where the pane currently lives in the app lifecycle. Prevents false-positive orphan detection:
- `.active` — In a layout, view exists, fully visible
- `.pendingUndo(expiresAt: Date)` — Closed but in the undo window. Not an orphan.
- `.backgrounded` — Alive but not visible in the current view. Not an orphan.

> **Files:** `Core/Models/TerminalSource.swift`, `Core/Models/SessionLifetime.swift`, `Core/Models/SessionResidency.swift`

### 2.4 ViewDefinition & ViewKind

A **named arrangement** of panes into tabs. Multiple views can reference the same panes.

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | Primary key |
| `name` | `String` | Display name |
| `kind` | `ViewKind` | Lifecycle/behavior type |
| `tabs` | `[Tab]` | Ordered tab array (position = index) |
| `activeTabId` | `UUID?` | Currently focused tab |
| `allPaneIds` | `[UUID]` | Derived: all pane IDs across all tabs |

**`ViewKind`** — Determines lifecycle and behavior:
- `.main` — Default view, always exists, cannot be deleted
- `.saved` — User-persisted layout snapshot
- `.worktree(worktreeId: UUID)` — Auto-generated view for a specific worktree
- `.dynamic(rule: DynamicViewRule)` — Rule-based, resolved at runtime

**`DynamicViewRule`** — Rules for dynamic views:
- `.byRepo(repoId: UUID)` — All panes for a repo
- `.byAgent(AgentType)` — All panes running a specific agent
- `.custom(name: String)` — Future: user-defined filter

> **File:** `Core/Models/DynamicView.swift`

### 2.5 Tab

A tab within a view. Contains a layout and tracks which pane is focused. Order is implicit — array position in the parent `ViewDefinition.tabs`.

| Field | Type | Notes |
|-------|------|-------|
| `id` | `UUID` | Primary key |
| `layout` | `Layout` | Split tree of pane references |
| `activePaneId` | `UUID?` | Focused pane within this tab |
| `paneIds` | `[UUID]` | Derived: all leaf pane IDs (left-to-right) |
| `isSplit` | `Bool` | Derived: true if layout root is a split |

> **File:** `Core/Models/Tab.swift`

### 2.6 Layout (Pure Value Type)

An immutable binary split tree. Leaves reference panes by ID. All operations return **new** `Layout` instances — no in-place mutation.

```
Layout
└── root: Node?
    ├── .leaf(paneId: UUID)
    └── .split(Split)
        ├── id: UUID
        ├── direction: .horizontal | .vertical
        ├── ratio: Double  (clamped 0.1–0.9)
        ├── left: Node
        └── right: Node
```

**Immutable Operations** (all return new Layout):

| Operation | Description |
|-----------|-------------|
| `inserting(paneId:at:direction:position:)` | Insert a pane adjacent to a target |
| `removing(paneId:)` | Remove a pane; collapses single-child splits. Returns `nil` if layout becomes empty |
| `resizing(splitId:ratio:)` | Update a split's ratio |
| `equalized()` | Set all split ratios to 0.5 |

**Navigation:**

| Method | Description |
|--------|-------------|
| `neighbor(of:direction:)` | Find the pane in the given direction (left/right/up/down) |
| `next(after:)` | Next pane in left-to-right order (wraps) |
| `previous(before:)` | Previous pane in left-to-right order (wraps) |

> **File:** `Core/Models/Layout.swift`

### 2.7 Templates

Templates define the initial pane layout when opening a worktree. Not yet wired into the main flow (Phase B6, future).

**`TerminalTemplate`** — Blueprint for a single terminal pane:
- `title`, `agent`, `provider`, `relativeWorkingDir`
- `instantiate(worktreeId:repoId:)` → `Pane`

**`WorktreeTemplate`** — Blueprint for a multi-pane tab:
- `terminals: [TerminalTemplate]`, `createPolicy`, `splitDirection`
- `instantiate(worktreeId:repoId:)` → `([Pane], Tab)`

**`CreatePolicy`** — When templates auto-create panes:
- `.onCreate` — When the worktree is first opened
- `.onActivate` — When the worktree view is activated
- `.manual` — Only on explicit user action

> **File:** `Core/Models/Templates.swift`

---

## 3. Service Layer

### 3.1 Ownership Hierarchy

```
AppDelegate (creates all services in dependency order)
├── WorkspaceStore           ← workspace structure (atomic store)
├── SessionRuntime           ← runtime status tracking
├── ViewRegistry             ← paneId → NSView mapping
├── PaneCoordinator          ← action dispatch + model↔view↔surface orchestration
├── TabBarAdapter            ← derived display state
├── CommandBarPanelController ← command bar lifecycle (⌘P)
└── MainWindowController
    └── MainSplitViewController
        └── PaneTabViewController
            ├── DraggableTabBarHostingView (SwiftUI)
            └── terminalContainer (dynamic split hierarchy)

Singletons:
├── SurfaceManager.shared    ← Ghostty surface lifecycle
├── CommandDispatcher.shared ← command definitions + dispatch
├── WorktrunkService.shared  ← git worktree CLI
└── Ghostty.shared           ← Ghostty C API wrapper
```

### 3.2 WorkspaceStore

Owns all workspace structure state. `@Observable`, `@MainActor`. All properties are `private(set)` — external code mutates only through methods.

**Observable state** (drives SwiftUI via `@Observable` property tracking):
- `repos: [Repo]`, `panes: [UUID: Pane]`, `tabs: [Tab]`, `activeTabId: UUID?`
- Transient UI: `draggingTabId`, `dropTargetIndex`, `tabFrames`

Transient UI binding exception: `draggingTabId`, `dropTargetIndex`, `tabFrames`, and `isSplitResizing` are view-layer
interaction state and are intentionally writable by UI bindings. They are not domain state and do not relax the
`private(set)` boundary for domain-owned store data.

**Mutation API categories:**

| Category | Methods |
|----------|---------|
| Pane | `createPane()`, `removePane()`, `updatePaneTitle()`, `updatePaneAgent()`, `setResidency()` |
| View | `switchView()`, `createView()`, `deleteView()`, `saveCurrentViewAs()` |
| Tab | `appendTab()`, `removeTab()`, `insertTab()`, `moveTab()`, `setActiveTab()` |
| Layout | `insertPane()`, `removePaneFromLayout()`, `resizePane()`, `equalizePanes()`, `setActivePane()` |
| Compound | `breakUpTab()`, `mergeTab()` |
| Repo | `addRepo()`, `removeRepo()`, `updateRepoWorktrees()` |

**Derived state** (computed, not stored):
- `activeView`, `activeTabs`, `activeTabId`, `activePaneIds`
- `activeTab`, `activePaneIds`, `activePane`

> **File:** `Core/Stores/WorkspaceStore.swift`

### 3.3 SessionRuntime

Manages live runtime state. Does **not** own panes — reads pane records from `WorkspaceStore`. Tracks runtime status per pane, schedules health checks, and coordinates backends. `@Observable`, `@MainActor`.

**Runtime status:** `SessionRuntimeStatus` — `.initializing`, `.running`, `.exited`, `.unhealthy`

**Backend protocol:** `SessionBackendProtocol` — `start()`, `isAlive()`, `terminate()`, `restore()`

**Key operations:**
- `registerBackend()` — Register a backend (e.g., `ZmxBackend`) for a provider type
- `syncWithStore()` — Align tracked pane statuses with store panes
- `startHealthChecks()` / `runHealthCheck()` — Periodic backend liveness checks
- `startSession(for:)` / `restoreSession(for:)` / `terminateSession(for:)` — Backend lifecycle for terminal panes

> **Note:** A full `SessionStatus` state machine (7 states: unknown, verifying, alive, dead, missing, recovering, failed) exists in `Models/StateMachine/SessionStatus.swift` for future zmx health integration but is not yet wired into `SessionRuntime`. See [Session Lifecycle](session_lifecycle.md) for details.
>
> `ZmxBackend` conforms to a separate `SessionBackend` protocol (defined in `ZmxBackend.swift`) with its own method signatures. A future phase will wire `SessionRuntime` → `ZmxBackend` and consolidate the two protocols.

> **File:** `Core/Stores/SessionRuntime.swift`

### 3.4 ViewRegistry

Maps pane IDs to live `AgentStudioTerminalView` instances. Runtime-only (not persisted). `@MainActor`.

- `register(view, paneId)` / `unregister(paneId)` — View lifecycle
- `view(for: paneId)` — Lookup
- `renderTree(for: Layout) -> TerminalSplitTree?` — Traverse a `Layout` tree, resolve each leaf to a registered pane view, return a renderable split tree. Gracefully promotes single-child splits when one side's view is missing.

> **File:** `App/Panes/ViewRegistry.swift`

### 3.5 Dynamic View Resolution

Dynamic and worktree view selection is implemented in the pane composition flow.
There is no standalone `ViewResolver` type in code; this behavior is owned by the
`App/Panes` layer.

- `PaneTabViewController` observes app state and renders the active view arrangement.
- `ViewRegistry` provides pane-to-view mapping used by split rendering.

> **File:** `App/Panes/ViewRegistry.swift`

### 3.6 PaneCoordinator

The `PaneCoordinator` is the canonical orchestration boundary for action execution and model↔view↔surface coordination. It owns no domain state and performs only sequencing.

- Coordinates `WorkspaceStore`, `SessionRuntime`, `SurfaceManager`, and `ViewRegistry`.
- Applies action intent through command validation and mutation APIs.
- Manages undo sequencing with deterministic restore/reattach behavior.

> **Expansion (LUNA-325):** The coordinator gains event consumption responsibilities: it will own the `RuntimeRegistry`, subscribe to `PaneRuntimeEvent` streams from all runtimes, feed the `NotificationReducer` (priority-aware delivery), and maintain per-source replay buffers. The coordinator event loop processes critical events at `.userInitiated` priority and lossy batches at `.utility`. See [Pane Runtime Architecture — Coordinator Event Loop](pane_runtime_architecture.md#coordinator-event-loop-how-it-connects) for the target design.

**Key operations:**
- `execute(_ action: PaneAction)` — dispatch all pane actions (selectTab, closeTab, closePane, insertPane, extractPaneToTab, resizePane, equalizePanes, mergeTab, breakUpTab, focusPane, repair)
- `openTerminal(for:in:)` — Create pane + surface + tab. Rolls back pane if surface creation fails.
- `openWebview(url:)` — Open a webview pane and append it as a new tab
- `undoCloseTab()` — pop `WorkspaceStore.CloseEntry` from undo stack, restore to store, reattach surfaces in reverse order
- `createView(for:worktree:repo:)` — Create surface → attach → create `AgentStudioTerminalView` → register in `ViewRegistry`
- `createViewForContent(pane:)` — create/register non-terminal pane views (webview/code/bridge)
- `teardownView(for: paneId)` — Unregister → detach surface (with undo support)
- `restoreView(for:worktree:repo:)` — Pop surface from `SurfaceManager.undoClose()` LIFO stack → reattach
- `restoreAllViews()` — App launch: create views for all panes in active tabs

**Undo stack:**
- `undoStack: [WorkspaceStore.CloseEntry]` — in-memory LIFO, max 10 entries
- `TabCloseSnapshot` captures: `tab`, `panes`, `tabIndex`
- Oldest entries GC'd when stack exceeds limit; orphaned panes cleaned up

> **File:** `App/PaneCoordinator.swift`

### 3.7 TabBarAdapter

Derived state bridge between `WorkspaceStore` and the tab bar SwiftUI view. Bridges `@Observable` store state via `withObservationTracking` and transforms it into tab bar display items.

> **File:** `Core/Views/TabBarAdapter.swift`

### 3.9 WorkspacePersistor

Owned by `WorkspaceStore` as a `private let` member. Pure persistence I/O. No business logic.

- `PersistableState` — Codable struct mirroring workspace fields
- `save(state)` / `load()` — JSON serialization to `~/.agentstudio/workspaces/`
- `ensureDirectory()`, `hasWorkspaceFiles()`, `delete()`

> **File:** `Core/Stores/WorkspacePersistor.swift`

### 3.10 SurfaceManager

Singleton managing Ghostty surface lifecycle. Detailed in [Surface Architecture](ghostty_surface_architecture.md).

Key points relevant here:
- Surfaces are keyed by their own UUID, joined to panes via `SurfaceMetadata.paneId`
- Three collections: `activeSurfaces`, `hiddenSurfaces`, `undoStack`
- `attach()` / `detach(reason:)` / `undoClose()` / `destroy()`

> **File:** `Features/Terminal/Ghostty/SurfaceManager.swift`

### 3.11 WorktrunkService

Git worktree management via the `wt` CLI tool. Singleton.

- `discoverWorktrees(at:)` — Parse `git worktree list` output
- `createWorktree()` / `removeWorktree()` — Lifecycle

> **File:** `Infrastructure/WorktrunkService.swift`

### 3.12 Command Bar System

Keyboard-driven search/command palette (⌘P) providing unified access to tabs, panes, commands, and worktrees. Modeled after Linear's ⌘K.

**`CommandBarPanelController`** — Owns the panel lifecycle and state. Created by `AppDelegate` with references to `WorkspaceStore` and `CommandDispatcher`. Manages show/dismiss/toggle behavior, backdrop overlay, and animations.

**`CommandBarState`** — `@Observable` state for the command bar. Manages:
- `rawInput` with prefix parsing (`>` → commands scope, `@` → panes scope)
- Navigation stack for nested drill-in (max 1 level deep)
- Selection index with wrap-around navigation
- Recent item IDs persisted to `UserDefaults`

**`CommandBarDataSource`** — Builds `CommandBarItem` arrays from live app state. Scope-filtered:
- `.everything` — tabs, panes, commands, worktrees (all groups)
- `.commands` — commands grouped by category (Pane, Focus, Tab, Repo, Window)
- `.panes` — panes grouped by parent tab, tabs as selectable items

Also builds `CommandBarLevel` targets for drill-in commands (e.g., "Close Tab..." → list of open tabs).

**`CommandBarSearch`** — Custom fuzzy matching engine. Returns scores (0.0 = best) and character match ranges for highlighting. Weighted scoring: title (1.0), subtitle (0.8), keywords (0.6). Recency boost for recently used items.

**`CommandBarPanel`** — `NSPanel` subclass with `NSVisualEffectView` (`.sidebar` material) and `NSHostingView` for SwiftUI content. Child window of the main window.

**Key design decisions:**
- NSPanel over SwiftUI overlay — guarantees z-ordering above Ghostty `NSView` surfaces
- Custom fuzzy matcher over third-party — FuzzyMatchingSwift lacks character match ranges needed for highlighting
- Actions route through `CommandDispatcher` → full validation pipeline — the command bar never mutates `WorkspaceStore` directly
- Tab/pane navigation uses `selectTabById` notification — avoids accidental destructive command dispatch

> **Files:** `Features/CommandBar/CommandBarPanelController.swift`, `Features/CommandBar/CommandBarState.swift`, `Features/CommandBar/CommandBarDataSource.swift`, `Features/CommandBar/CommandBarSearch.swift`, `Features/CommandBar/CommandBarPanel.swift`, `Features/CommandBar/CommandBarItem.swift`, `Features/CommandBar/Views/*.swift`

---

## 4. Data Flow

### 4.1 Mutation Pipeline

> **Note:** This diagram shows the target `PaneCoordinator` flow.

Every state change follows this path:

```mermaid
sequenceDiagram
    participant User
    participant PaneTabViewController
    participant PC as PaneCoordinator
    participant Store as WorkspaceStore
    participant SM as SurfaceManager
    participant VR as ViewRegistry

    User->>PaneTabViewController: keyboard / mouse / drag
    PaneTabViewController->>PaneTabViewController: AppCommand / Notification
    PaneTabViewController->>PC: execute(PaneAction)
    PC->>Store: mutate state (private(set))
    Store-->>Store: @Observable tracks
    Store-->>PaneTabViewController: SwiftUI re-renders
    Store->>Store: markDirty()
    Note over Store: debounced 500ms
    Store->>Store: persistNow() → JSON

    alt Surface creation needed
        PC->>SM: createSurface() + attach()
        PC->>VR: register(view, paneId)
    end

    alt Surface teardown needed
        PC->>VR: unregister(paneId)
        PC->>SM: detach(surfaceId, reason)
    end
```

### 4.2 Restore Flow

```mermaid
sequenceDiagram
    participant AD as AppDelegate
    participant Store as WorkspaceStore
    participant P as WorkspacePersistor
    participant Coord as PaneCoordinator
    participant RT as SessionRuntime
    participant SM as SurfaceManager
    participant VR as ViewRegistry

    AD->>Store: restore()
    Store->>P: load()
    P-->>Store: PersistableState (JSON)
    Store->>Store: filter temporary panes
    Store->>Store: prune dangling worktree refs
    Store->>Store: prune invalid layout pane IDs
    Store->>Store: ensureMainView()

    AD->>Coord: restoreAllViews()
    loop each pane in active view
        Coord->>SM: createSurface() + attach()
        Coord->>VR: register(view, paneId)
        Coord->>RT: markRunning(paneId)
    end
```

### 4.3 View Switch Flow

When switching from View A to View B:

1. `WorkspaceStore.switchView(viewB.id)` sets `activeViewId`
2. `PaneCoordinator.handleViewSwitch(from: A, to: B)`:
   - **Sessions only in A**: `SurfaceManager.detach(.hide)`, `ViewRegistry.unregister()`
   - **Sessions in both A and B**: No change (surface stays attached)
   - **Sessions only in B**: `PaneCoordinator.createView()`, `ViewRegistry.register()`, `SurfaceManager.attach()`

### 4.4 Undo Close Flow

1. **Close**: `PaneCoordinator.executeCloseTab(tabId)`
   - `store.snapshotForClose()` → `TabCloseSnapshot` (tab + panes + tabIndex)
   - Push snapshot to `undoStack` (max 10)
   - `coordinator.teardownView()` for each pane → `SurfaceManager.detach(.close)` (surfaces enter undo stack with TTL)
   - `store.removeTab(tabId)` — panes remain in `store.panes` until explicit cleanup
   - GC oldest undo entries if stack > 10

2. **Undo** (`Cmd+Shift+T`): `PaneCoordinator.undoCloseTab()`
   - Pop `WorkspaceStore.CloseEntry` from undo stack
   - `store.restoreFromSnapshot()` → re-insert tab at original position
   - `coordinator.restoreView()` for each pane (reversed order, matching SurfaceManager LIFO)
   - `SurfaceManager.undoClose()` pops surface → reattach (no recreation)

### 4.5 Command Bar Execution Flow

When a user selects an item from the command bar:

```
CommandBarView.executeItem(item)
│
├─ If dimmed (canDispatch == false) → blocked, no action
│
├─ .dispatch(command)
│   └─ onDismiss() → CommandDispatcher.dispatch(command)
│       → CommandHandler.execute(command)
│         → ActionResolver → ActionValidator → PaneCoordinator → WorkspaceStore
│
├─ .dispatchTargeted(command, target: UUID, targetType)
│   └─ onDismiss() → CommandDispatcher.dispatch(command, target, targetType)
│       → CommandHandler.execute(command, target, targetType)
│         → ActionResolver (with explicit target) → ActionValidator → PaneCoordinator
│
├─ .navigate(level)
│   └─ state.pushLevel(level) — drill into nested target picker
│
└─ .custom(closure)
    └─ onDismiss() → closure() — e.g., NotificationCenter.post(.selectTabById)
```

The command bar records the selected item ID in `recentItemIds` (persisted to `UserDefaults`) before executing. Dimmed items (commands where `dispatcher.canDispatch()` returns false) are blocked from execution on both click and Enter key.

---

## 5. Persistence

### 5.1 Write Strategy

All mutations call `markDirty()`, which:
1. Sets `isDirty = true`
2. Calls `ProcessInfo.disableSuddenTermination()` (prevents macOS kill during write)
3. Schedules debounced save (500ms window, cancels previous)
4. After 500ms with no new mutations: `persistNow()` → JSON to disk
5. Resets `isDirty`, re-enables sudden termination

**On app termination:** `flush()` cancels any pending debounce and persists immediately.

**Window frame:** Not debounced — only saved on quit via `flush()`. `setWindowFrame()` does not call `markDirty()`.

### 5.2 Save Filtering

Before writing to disk:
- Temporary panes (`lifetime == .temporary`) are **excluded** from the persisted copy
- View layouts are pruned: any pane ID not in the persisted pane set is removed from layout nodes
- Empty tabs (all panes pruned) are removed
- `activeTabId` pointers are fixed if they reference removed tabs
- The in-memory `views` state is **not** mutated — only the serialized output is cleaned

### 5.3 Restore Filtering

On app launch:
1. Load JSON from disk
2. Filter out `.temporary` panes
3. Remove panes whose worktree no longer exists on disk
4. Prune dangling pane IDs from all view layouts
5. Remove empty tabs, fix `activeTabId` pointers
6. Ensure main view exists (create if missing)

---

## 6. Invariants

These rules are enforced by `WorkspaceStore` and model types at all times:

1. **Pane ID uniqueness** — Every `Pane.id` is unique within the workspace
2. **Tab minimum** — A `Tab` always has at least one pane in its layout. Removing the last pane closes the tab.
3. **Active pane validity** — `Tab.activePaneId` references a pane in that tab's layout, or is nil during construction
4. **Active tab validity** — `ViewDefinition.activeTabId` references a tab in that view, or is nil when no tabs exist
5. **Active view validity** — `activeViewId` references a view in `views`, or is nil
6. **Main view always exists** — `views` always contains exactly one view with `kind == .main`. It cannot be deleted.
7. **Layout tree structure** — Every split has exactly two children. Leaves contain valid pane IDs.
8. **Split ratios clamped** — `0.1 <= ratio <= 0.9`
9. **Source is metadata** — `TerminalSource.worktree(id, repoId)` may reference a worktree that no longer exists. The pane survives; UI shows fallback text.
10. **Pane independence** — Removing a pane from a layout does NOT remove it from `panes`. Panes are explicitly removed only on user close or GC.
11. **No NSView in model** — No model type holds `NSView` references
12. **Persistence safety** — `disableSuddenTermination()` while dirty; `flush()` on quit

---

## 7. Key Files

| File | Purpose |
|------|---------|
| **Core/Models** | |
| `Core/Models/TerminalSource.swift` | `TerminalSource` enum |
| `Core/Models/SessionLifetime.swift` | `.persistent` / `.temporary` |
| `Core/Models/SessionResidency.swift` | `.active` / `.pendingUndo` / `.backgrounded` |
| `Core/Models/Layout.swift` | Pure value-type split tree, `FocusDirection` |
| `Core/Models/Tab.swift` | Tab with layout and active pane |
| `Core/Models/DynamicView.swift` | `DynamicView`, `ViewKind`, `DynamicViewRule` |
| `Core/Models/Repo.swift` | `Repo` entity |
| `Core/Models/Worktree.swift` | `Worktree`, `WorktreeStatus`, `AgentType` |
| `Core/Models/Templates.swift` | `WorktreeTemplate`, `TerminalTemplate`, `CreatePolicy` |
| `Core/Models/StableKey.swift` | SHA-256 path hashing for deterministic IDs |
| `Infrastructure/StateMachine/StateMachine.swift` | Generic state machine with effect handling |
| `Core/Models/SessionStatus.swift` | 7-state session lifecycle machine (future zmx health) |
| **Core/Stores** | |
| `Core/Stores/WorkspaceStore.swift` | Atomic store for workspace structure (tabs, layouts, views) |
| `Core/Stores/WorkspacePersistor.swift` | JSON persistence I/O |
| `Core/Stores/SessionRuntime.swift` | Runtime status tracking and health checks |
| `App/Panes/ViewRegistry.swift` | Pane ID → NSView mapping |
| `Core/Stores/ZmxBackend.swift` | zmx CLI wrapper — session create/destroy/health |
| **Infrastructure** | |
| `Infrastructure/WorktrunkService.swift` | Git worktree CLI wrapper |
| `Infrastructure/ProcessExecutor.swift` | Protocol + default impl for CLI execution |
| **App** | |
| `App/PaneCoordinator.swift` | Action dispatch, orchestration, and undo sequencing |
| `App/MainWindowController.swift` | Primary window management |
| `App/MainSplitViewController.swift` | Split view: sidebar + terminal panes |
| `App/Panes/PaneTabViewController.swift` | Tab controller, observes store via @Observable |
| **Core/Actions** | |
| `Core/Actions/PaneAction.swift` | Action enum for all pane operations |
| `Core/Actions/ActionResolver.swift` | Resolves user input → PaneAction |
| `Core/Actions/ActionValidator.swift` | Validates actions before execution |
| `Core/Actions/ActionStateSnapshot.swift` | Captures state for validation |
| **Features/CommandBar** | |
| `Features/CommandBar/CommandBarPanelController.swift` | Panel lifecycle: show/dismiss/toggle, backdrop, animation |
| `Features/CommandBar/CommandBarState.swift` | Observable state: prefix parsing, navigation, selection, recents |
| `Features/CommandBar/CommandBarDataSource.swift` | Builds items from `WorkspaceStore` + `CommandDispatcher`, scope-filtered |
| `Features/CommandBar/CommandBarSearch.swift` | Custom fuzzy matching with score + character match ranges |
| `Features/CommandBar/CommandBarPanel.swift` | `NSPanel` subclass with `NSVisualEffectView` + `NSHostingView` |
| `Features/CommandBar/CommandBarItem.swift` | Data models: `CommandBarItem`, `CommandBarLevel`, `CommandBarAction`, `ShortcutKey` |
| `Features/CommandBar/Views/CommandBarView.swift` | Root SwiftUI view — composes search, results, scope pill, footer |
| `Features/CommandBar/Views/CommandBarTextField.swift` | `NSViewRepresentable` wrapping `NSTextField` for keyboard interception |
| `Features/CommandBar/Views/CommandBarResultsList.swift` | Grouped scrollable list with flattened index tracking |
| `Features/CommandBar/Views/CommandBarResultRow.swift` | Result row with fuzzy match highlighting and dimming |

---

## 8. Cross-References

- **[Architecture Overview](README.md)** — System overview and document index
- **[Session Lifecycle](session_lifecycle.md)** — Pane identity contract, creation, close, undo, restore flows; runtime status; zmx backend
- **[Surface Architecture](ghostty_surface_architecture.md)** — Ghostty surface ownership, state machine, health monitoring, crash isolation
- **[App Architecture](appkit_swiftui_architecture.md)** — AppKit+SwiftUI hybrid patterns, window/controller hierarchy
