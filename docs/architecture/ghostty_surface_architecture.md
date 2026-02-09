# Ghostty Surface Architecture

Agent Studio embeds Ghostty terminal surfaces via libghostty. The `SurfaceManager` provides lifecycle management with crash isolation and undo support.

## Core Design: Ownership Separation

The key architectural decision is **separation of ownership from display**:
- `SurfaceManager` **owns** all surfaces (creation, lifecycle, destruction)
- `AgentStudioTerminalView` containers only **display** surfaces
- `TerminalViewCoordinator` is the sole intermediary for surface/runtime lifecycle

```
┌─────────────────────────────────────────────────────────────────────┐
│                        SurfaceManager                               │
│                     (OWNS all surfaces)                             │
│                                                                     │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐       │
│  │ activeSurfaces  │ │ hiddenSurfaces  │ │   undoStack     │       │
│  │  [UUID: Surf]   │ │  [UUID: Surf]   │ │ [UndoEntry]     │       │
│  │                 │ │                 │ │                 │       │
│  │  Rendering: ON  │ │  Rendering: OFF │ │ TTL: 5 minutes  │       │
│  └────────┬────────┘ └────────┬────────┘ └────────┬────────┘       │
│           │                   │                   │                 │
│           └───────────────────┴───────────────────┘                 │
│                      Surface lives in ONE                           │
└─────────────────────────────────────────────────────────────────────┘
                              │
                    attach() / detach()
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    AgentStudioTerminalView                          │
│                  (DISPLAYS, does not own)                           │
│                                                                     │
│   sessionId: UUID    ←─ single identity across all layers           │
│   surfaceId: UUID?   ←─ which surface is displayed here             │
│                                                                     │
│   displaySurface(surfaceView)  ←─ called by coordinator             │
│   removeSurface()              ←─ called by coordinator             │
└─────────────────────────────────────────────────────────────────────┘
```

## State Machine

A surface exists in **exactly one** collection. The collection determines the state:

```
                          createSurface()
                               │
                               ▼
                    ┌──────────────────┐
                    │     HIDDEN       │ ← Surface starts here
                    │  hiddenSurfaces  │
                    │  (rendering OFF) │
                    └────────┬─────────┘
                             │
              attach()       │        detach(.hide)
              ┌──────────────┴──────────────┐
              │                             │
              ▼                             │
    ┌──────────────────┐                    │
    │     ACTIVE       │ ◄──────────────────┘
    │  activeSurfaces  │
    │  (rendering ON)  │
    └────────┬─────────┘
             │
             │ detach(.close)
             ▼
    ┌──────────────────┐
    │  PENDING UNDO    │ ← TTL = 5 minutes
    │    undoStack     │
    │  (rendering OFF) │
    └────────┬─────────┘
             │
    ┌────────┴─────────┐
    │                  │
    │ undoClose()      │ TTL expires
    │                  │ OR destroy()
    ▼                  ▼
    HIDDEN         DESTROYED
    (reattachable) (ARC freed)
```

## Tab Close → Undo Flow

```
User closes tab
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│ AgentStudioTerminalView.requestClose()                       │
│   └─► SurfaceManager.detach(surfaceId, reason: .close)       │
│         │                                                    │
│         ├─► Remove from activeSurfaces                       │
│         ├─► ghostty_surface_set_occlusion(false)  // pause   │
│         ├─► Create SurfaceUndoEntry with TTL                 │
│         ├─► Schedule expiration Task                         │
│         └─► Append to undoStack                              │
└──────────────────────────────────────────────────────────────┘

User presses Cmd+Shift+T
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│ TerminalTabViewController.handleUndoCloseTab()               │
│   └─► SurfaceManager.undoClose()                             │
│         │                                                    │
│         ├─► Pop from undoStack                               │
│         ├─► Cancel expiration Task                           │
│         └─► Move to hiddenSurfaces                           │
│                                                              │
│   └─► Create AgentStudioTerminalView(restoredSurfaceId:)     │
│         │  (does NOT create new surface!)                    │
│         │                                                    │
│   └─► SurfaceManager.attach(surfaceId, to: sessionId)        │
│         │                                                    │
│         ├─► Move from hiddenSurfaces → activeSurfaces        │
│         ├─► ghostty_surface_set_occlusion(true)  // resume   │
│         └─► Return surfaceView                               │
│                                                              │
│   └─► terminalView.displaySurface(surfaceView)               │
└──────────────────────────────────────────────────────────────┘
```

## Health Monitoring Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                     Health Detection (2 layers)                    │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  Layer 1: Event-Driven (instant)                                   │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ Ghostty.Notification.didUpdateRendererHealth                │   │
│  │              │                                              │   │
│  │              ▼                                              │   │
│  │  surfaceViewToId[ObjectIdentifier] → UUID                   │   │
│  │              │                                              │   │
│  │              ▼                                              │   │
│  │  updateHealth(surfaceId, .healthy/.unhealthy)               │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                    │
│  Layer 2: Polling (every 2 seconds)                                │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │ Timer → checkAllSurfacesHealth()                            │   │
│  │              │                                              │   │
│  │              ├─► surface.surface == nil?  → .dead           │   │
│  │              ├─► ghostty_surface_process_exited? → .exited  │   │
│  │              └─► !surface.healthy? → .unhealthy             │   │
│  └─────────────────────────────────────────────────────────────┘   │
│                                                                    │
├────────────────────────────────────────────────────────────────────┤
│                   Health Delegate Pattern                          │
├────────────────────────────────────────────────────────────────────┤
│                                                                    │
│  SurfaceManager                                                    │
│    healthDelegates = NSHashTable<AnyObject>.weakObjects()          │
│                         │                                          │
│    notifyHealthDelegates(surfaceId, health)                        │
│                         │                                          │
│           ┌─────────────┼─────────────┐                            │
│           ▼             ▼             ▼                            │
│      Terminal 1    Terminal 2    Terminal 3                        │
│      (Tab A)       (Tab B)       (Tab C)                           │
│                                                                    │
│  Each tab filters: guard surfaceId == self.surfaceId               │
│  Weak refs: auto-cleanup when tabs close                           │
└────────────────────────────────────────────────────────────────────┘
```

## Detach Reasons

| Reason | Target | Expires | Rendering | Use Case |
|--------|--------|---------|-----------|----------|
| `.hide` | hiddenSurfaces | No | Paused | Background terminal |
| `.close` | undoStack | Yes (5 min) | Paused | Tab closed (undo-able) |
| `.move` | hiddenSurfaces | No | Paused | Tab drag reorder |

## Restore Initializer Pattern

```swift
// WRONG: Creates orphan surface
let view = AgentStudioTerminalView(worktree: w, project: p)
view.displaySurface(restoredSurface)  // Original surface from view is orphaned!

// RIGHT: Skip surface creation for restore
let view = AgentStudioTerminalView(worktree: w, project: p, restoredSurfaceId: id)
view.displaySurface(restoredSurface)  // No orphan, view has no surface yet
```

## Key APIs

| API | Purpose |
|-----|---------|
| `SurfaceManager.createSurface()` | Create with retry and error handling |
| `SurfaceManager.attach(to:)` | Attach to container, resume rendering |
| `SurfaceManager.detach(reason:)` | Hide, close (undo-able), or move |
| `SurfaceManager.undoClose()` | Restore last closed surface |
| `SurfaceManager.withSurface()` | Safe operation wrapper |

## Crash Isolation

**Goal:** One terminal crash must NEVER bring down the app.

| Layer | Mechanism |
|-------|-----------|
| **Prevention** | `withSurface()` wrapper validates pointers, retry on creation failure |
| **Detection** | Dual-layer health monitoring (events + polling) |
| **Recovery** | Error overlay in affected tab only, restart button, other tabs unaffected |

> **Limitation:** Zig panics on main thread will crash the app. We minimize this risk but can't eliminate it without IPC.

## Files

| File | Purpose |
|------|---------|
| `Ghostty/SurfaceManager.swift` | Singleton owner, lifecycle, health monitoring |
| `Ghostty/SurfaceTypes.swift` | SurfaceState, ManagedSurface, protocols |
| `Views/AgentStudioTerminalView.swift` | Container, implements SurfaceHealthDelegate |
| `Views/SurfaceErrorOverlay.swift` | Error state UI with restart/close |

## Session Restore

Terminal surfaces are backed by headless tmux sessions that persist across app restarts. When a surface restarts (via error overlay), it reattaches to its tmux session rather than spawning a new shell.

For the full session restore architecture, lifecycle flow, and tmux configuration, see:

**[Session Restore Architecture](session_lifecycle.md)**
