# Ghostty Surface Architecture

## TL;DR

Agent Studio embeds Ghostty terminal surfaces via libghostty. `SurfaceManager` (singleton) **owns** all surfaces. `AgentStudioTerminalView` only **displays** them. `TerminalViewCoordinator` is the sole intermediary — views and the model layer never call `SurfaceManager` directly. Surfaces live in exactly one of three collections (active, hidden, undoStack), with dual-layer health monitoring and crash isolation per terminal.

---

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
                    (via TerminalViewCoordinator)
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

**Session-to-surface join key:** `SurfaceMetadata.sessionId` links a surface to its `TerminalSession`. This is used during undo restore to verify the correct surface is reattached to the correct session (multi-pane safety).

---

## Surface State Machine

A surface exists in **exactly one** collection. The collection determines the state:

```mermaid
stateDiagram-v2
    [*] --> HIDDEN: createSurface()
    HIDDEN --> ACTIVE: attach()
    ACTIVE --> HIDDEN: detach(.hide) / detach(.move)
    ACTIVE --> PENDING_UNDO: detach(.close)
    PENDING_UNDO --> HIDDEN: undoClose()
    PENDING_UNDO --> DESTROYED: TTL expires / destroy()
    HIDDEN --> DESTROYED: destroy()
    DESTROYED --> [*]
```

| State | Collection | Rendering | Notes |
|-------|-----------|-----------|-------|
| HIDDEN | `hiddenSurfaces` | OFF | Alive but not displayed |
| ACTIVE | `activeSurfaces` | ON | Visible in a container |
| PENDING_UNDO | `undoStack` | OFF | Closed, awaiting undo (5 min TTL) |
| DESTROYED | (freed) | N/A | Surface removed from all collections, ARC deallocated |

---

## Tab Close → Undo Flow

The close/undo flow is coordinated through `ActionExecutor` → `TerminalViewCoordinator` → `SurfaceManager`. Views never call `SurfaceManager` directly.

```
User closes tab
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│ ActionExecutor.executeCloseTab(tabId)                        │
│   ├─► store.snapshotForClose() → CloseSnapshot               │
│   ├─► Push to undo stack (max 10 entries)                    │
│   │                                                          │
│   ├─► For each sessionId in tab:                             │
│   │     coordinator.teardownView(sessionId)                  │
│   │       ├─► ViewRegistry.unregister(sessionId)             │
│   │       └─► SurfaceManager.detach(surfaceId, reason: .close)│
│   │             ├─► Remove from activeSurfaces               │
│   │             ├─► ghostty_surface_set_occlusion(false)     │
│   │             ├─► Create SurfaceUndoEntry with TTL         │
│   │             ├─► Schedule expiration Task                 │
│   │             └─► Append to undoStack                      │
│   │                                                          │
│   └─► store.removeTab(tabId)                                 │
└──────────────────────────────────────────────────────────────┘

User presses Cmd+Shift+T
       │
       ▼
┌──────────────────────────────────────────────────────────────┐
│ ActionExecutor.undoCloseTab()                                │
│   ├─► Pop CloseSnapshot from undo stack                      │
│   ├─► store.restoreFromSnapshot() → re-insert tab            │
│   │                                                          │
│   └─► For each session (reversed, matching LIFO order):      │
│         coordinator.restoreView(session, worktree, repo)     │
│           ├─► SurfaceManager.undoClose()                     │
│           │     ├─► Pop from undoStack                       │
│           │     ├─► Cancel expiration Task                   │
│           │     ├─► Verify metadata.sessionId matches        │
│           │     └─► Move to hiddenSurfaces                   │
│           │                                                  │
│           ├─► SurfaceManager.attach(surfaceId, sessionId)    │
│           │     ├─► Move to activeSurfaces                   │
│           │     ├─► ghostty_surface_set_occlusion(true)      │
│           │     └─► Return surfaceView                       │
│           │                                                  │
│           └─► ViewRegistry.register(view, sessionId)         │
└──────────────────────────────────────────────────────────────┘
```

---

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

---

## Detach Reasons

| Reason | Target | Expires | Rendering | Use Case |
|--------|--------|---------|-----------|----------|
| `.hide` | hiddenSurfaces | No | Paused | Background terminal / view switch |
| `.close` | undoStack | Yes (5 min) | Paused | Tab closed (undo-able) |
| `.move` | hiddenSurfaces | No | Paused | Tab drag reorder |

---

## Restore Initializer Pattern

```swift
// WRONG: Creates orphan surface
let view = AgentStudioTerminalView(worktree: w, project: p)
view.displaySurface(restoredSurface)  // Original surface from view is orphaned!

// RIGHT: Skip surface creation for restore
let view = AgentStudioTerminalView(worktree: w, project: p, restoredSurfaceId: id)
view.displaySurface(restoredSurface)  // No orphan, view has no surface yet
```

---

## Key APIs

| API | Purpose |
|-----|---------|
| `SurfaceManager.createSurface()` | Create with retry and error handling |
| `SurfaceManager.attach(to:)` | Attach to container, resume rendering |
| `SurfaceManager.detach(reason:)` | Hide, close (undo-able), or move |
| `SurfaceManager.undoClose()` | Restore last closed surface (LIFO) |
| `SurfaceManager.withSurface()` | Safe operation wrapper |

---

## Crash Isolation

**Goal:** One terminal crash must NEVER bring down the app.

| Layer | Mechanism |
|-------|-----------|
| **Prevention** | `withSurface()` wrapper validates pointers, retry on creation failure |
| **Detection** | Dual-layer health monitoring (events + polling) |
| **Recovery** | Error overlay in affected tab only, restart button, other tabs unaffected |

> **Limitation:** Zig panics on main thread will crash the app. We minimize this risk but can't eliminate it without IPC.

---

## Files

| File | Purpose |
|------|---------|
| `Ghostty/SurfaceManager.swift` | Singleton owner, lifecycle, health monitoring |
| `Ghostty/SurfaceTypes.swift` | SurfaceState, ManagedSurface, SurfaceMetadata, protocols |
| `Views/AgentStudioTerminalView.swift` | Container, implements SurfaceHealthDelegate |
| `Views/SurfaceErrorOverlay.swift` | Error state UI with restart/close |

---

## Related Documentation

- **[Architecture Overview](README.md)** — System overview and document index
- **[Component Architecture](component_architecture.md)** — Data model, service layer, ownership hierarchy
- **[Session Lifecycle](session_lifecycle.md)** — Session creation, close, undo, restore, tmux backend
- **[App Architecture](app_architecture.md)** — AppKit + SwiftUI hybrid, lifecycle management
