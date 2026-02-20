# Session Lifecycle Architecture

## TL;DR

A terminal session's identity (`UUID`) is stable across its entire lifecycle — creation, layout changes, view switches, close/undo, persistence, and restore. `WorkspaceStore` owns session records. `SessionRuntime` tracks runtime health. `TerminalViewCoordinator` bridges sessions to surfaces. Sessions survive layout removal (they persist in `store.sessions`) and can be undone via a `CloseSnapshot` stack. The zmx backend provides persistence across app restarts.

---

## Session Identity

A single `sessionId: UUID` is the identity used across **all** layers:

| Layer | Uses sessionId for |
|-------|--------------------|
| `WorkspaceStore` | Session record ownership |
| `Layout` / `Tab` / `ViewDefinition` | Leaf references in split trees |
| `ViewRegistry` | sessionId → live NSView mapping |
| `SurfaceManager` | `SurfaceMetadata.sessionId` — join key to session |
| `SessionRuntime` | Runtime status tracking |
| `ZmxBackend` | Part of deterministic zmx session name |

## Session Properties

Every session carries metadata that determines its behavior:

```
TerminalSession
├── id: UUID                    ← immutable primary key
├── source: TerminalSource      ← .worktree(wId, rId) or .floating(dir, title)
├── title: String               ← updated from shell title changes
├── agent: AgentType?           ← claude, codex, gemini, aider, custom
├── provider: SessionProvider   ← .ghostty (direct) or .zmx (persistent)
├── lifetime: SessionLifetime   ← .persistent (saved) or .temporary (ephemeral)
└── residency: SessionResidency ← .active, .pendingUndo(expiresAt), .backgrounded
```

---

## Session Lifecycle States

### Residency (Persisted)

`SessionResidency` tracks where a session lives in the application lifecycle. This prevents false-positive orphan detection — a session in `pendingUndo` is not an orphan.

```mermaid
stateDiagram-v2
    [*] --> active: createSession()
    active --> pendingUndo: closeTab (enters undo window)
    active --> backgrounded: view switch (session leaves active view)
    pendingUndo --> active: undoCloseTab()
    pendingUndo --> [*]: undo expires / GC
    backgrounded --> active: view switch (session enters active view)
    backgrounded --> [*]: explicit removal
```

### Runtime Status (Not Persisted)

`SessionRuntimeStatus` tracks the live backend state. Created fresh on each app launch.

```mermaid
stateDiagram-v2
    [*] --> initializing: initializeSession()
    initializing --> running: markRunning() / backend.start()
    running --> exited: markExited() / process exit
    running --> unhealthy: health check failed
    unhealthy --> exited: backend terminated
    exited --> [*]: session removed
```

| Status | Meaning |
|--------|---------|
| `.initializing` | Session created, backend not yet ready |
| `.running` | Backend is running and healthy |
| `.exited` | Backend process has exited |
| `.unhealthy` | Health check failed, session may be stale. Terminal until backend exits. |

---

## Terminal Creation Flow

```mermaid
sequenceDiagram
    participant User
    participant AE as ActionExecutor
    participant Store as WorkspaceStore
    participant Coord as TerminalViewCoordinator
    participant SM as SurfaceManager
    participant VR as ViewRegistry
    participant RT as SessionRuntime

    User->>AE: openTerminal(worktree, repo)
    AE->>AE: Check if worktree already has active session
    alt Already open
        AE->>Store: setActiveTab(existingTab.id)
    else New session needed
        AE->>Store: createSession(source: .worktree, provider: .zmx)
        Store-->>AE: TerminalSession (new UUID)
        AE->>Coord: createView(session, worktree, repo)
        Coord->>SM: createSurface(config, metadata)
        SM-->>Coord: ManagedSurface
        Coord->>SM: attach(surfaceId, sessionId)
        Coord->>VR: register(view, sessionId)
        Coord->>RT: markRunning(sessionId)
        Coord-->>AE: AgentStudioTerminalView

        alt Surface creation failed
            AE->>Store: removeSession(session.id)
            Note over AE: Rollback — no orphan session
        else Success
            AE->>Store: appendTab(Tab(sessionId))
            AE->>Store: setActiveTab(tab.id)
        end
    end
```

---

## Close & Undo Flow

### Close Tab

1. `ActionExecutor.executeCloseTab(tabId)`:
   - `store.snapshotForClose(tabId)` → `CloseSnapshot` (tab, sessions, viewId, tabIndex)
   - Push to `undoStack` (LIFO, max 10 entries)
   - For each session in the tab: `coordinator.teardownView(sessionId)`
     - `ViewRegistry.unregister(sessionId)`
     - `SurfaceManager.detach(surfaceId, reason: .close)` → surface enters SurfaceManager undo stack with TTL (5 min)
   - `store.removeTab(tabId)` — sessions remain in `store.sessions` (not deleted)
   - `expireOldUndoEntries()` — GC entries beyond max, remove orphaned sessions

### Undo Close Tab (`Cmd+Shift+T`)

2. `ActionExecutor.undoCloseTab()`:
   - Pop `CloseSnapshot` from undo stack
   - `store.restoreFromSnapshot(snapshot)` — re-insert tab at original position
   - For each session in **reversed** order (matching SurfaceManager LIFO):
     - `coordinator.restoreView(session, worktree, repo)`
     - `SurfaceManager.undoClose()` → pop surface from undo stack
     - Verify `metadata.sessionId` matches (multi-pane safety)
     - Reattach surface (no recreation)

### Close Pane (No Undo)

`executeClosePane(tabId, sessionId)`:
- `coordinator.teardownView(sessionId)` — surface destroyed (not undo-able)
- `store.removeSessionFromLayout(sessionId, inTab: tabId)` — if last session, removes the tab
- If session is no longer in any layout across all views, `store.removeSession(sessionId)`

---

## App Launch Restore

```mermaid
sequenceDiagram
    participant AD as AppDelegate
    participant Store as WorkspaceStore
    participant P as WorkspacePersistor
    participant Coord as TerminalViewCoordinator

    AD->>Store: restore()
    Store->>P: load()
    P-->>Store: PersistableState (JSON)

    Note over Store: 1. Filter out .temporary sessions
    Note over Store: 3. Remove sessions with deleted worktrees
    Note over Store: 4. Prune dangling session IDs from layouts
    Note over Store: 5. Remove empty tabs, fix activeTabId
    Note over Store: 6. Ensure main view exists

    AD->>Coord: restoreAllViews()
    loop each session in active view tabs
        Coord->>Coord: createView(session) → surface + attach + register
    end

    AD->>AD: Create MainWindowController
```

**Restore filtering details:**
- **Temporary filtering**: Sessions with `lifetime == .temporary` are removed
- **Worktree validation**: Sessions referencing a `worktreeId` not in any repo's worktrees are removed (worktree was deleted between launches)
- **Layout pruning**: Session IDs not in the valid session set are removed from all layout nodes; single-child splits collapse; empty tabs removed
- **Main view guarantee**: If no `.main` view exists, one is created

---

## App Termination

```
AppDelegate.applicationWillTerminate / applicationShouldTerminate
  └── WorkspaceStore.flush()
        ├── Cancel pending debounced save
        ├── Filter temporary sessions from output
        ├── Prune layouts in the serialized copy
        └── Write JSON to disk immediately
```

---

## Persistence

State is persisted via `WorkspacePersistor` as JSON. See [Component Architecture — Persistence](component_architecture.md#5-persistence) for the full write strategy, filtering, and schema details.

Key points:
- All mutations debounced at 500ms via `markDirty()`
- `flush()` on termination for immediate write
- Temporary sessions never persisted
- Window frame saved only on quit

---

## zmx Session Persistence

The zmx backend provides session persistence across app restarts. When enabled, terminal sessions survive app crashes — the user sees only a Ghostty terminal surface while zmx preserves the PTY and scrollback in the background via raw byte passthrough daemons.

For the startup sequencing details (deferred attach, geometry readiness, and test coverage), see [Zmx Restore and Sizing](zmx_restore_and_sizing.md).

### Architecture

zmx is a ~1000 LOC Zig tool that provides raw byte passthrough with zero terminal emulation. It uses libghostty-vt for state tracking, meaning `TERM=xterm-ghostty` flows through natively:
- **No config file** needed
- **No terminal emulation layer** (no keyboard/mouse protocol conflicts)
- **No custom terminfo** needed (xterm-ghostty works natively)
- One daemon per session (no shared server)

### ZMX_DIR Isolation

All zmx calls use `ZMX_DIR=~/.agentstudio/zmx/` to isolate Agent Studio sessions from any user-owned zmx sessions.

- Destroy/list/health paths pass `ZMX_DIR` via process environment.
- Attach path passes `ZMX_DIR` through Ghostty surface environment variables.

### zmx CLI Commands

| Command | Purpose |
|---------|---------|
| `zmx attach <name> <cmd...>` | Attach to (or create) a session with the given name |
| `zmx kill <name>` | Kill a session by name |
| `zmx list` | List all active sessions (tab-delimited key=value pairs) |

### Testing

The zmx path is covered by layered tests:

1. unit tests for backend command/session behavior,
2. integration tests against a real zmx binary with isolated `ZMX_DIR`,
3. end-to-end tests for full lifecycle and backend recreation restore semantics.

### zmx Binary Resolution

The zmx binary is resolved via a fallback chain:
1. **Bundled binary**: `Contents/MacOS/zmx` (same directory as app executable)
2. **Well-known PATH locations**: `/opt/homebrew/bin/zmx`, `/usr/local/bin/zmx`
3. **`which zmx`** fallback
4. If none found: fall back to ephemeral `.ghostty` provider (no persistence)

### Session ID Format

```
agentstudio--<repo16hex>--<worktree16hex>--<pane16hex>
            |              |                |
            |              |                +-- First 16 hex chars of pane UUID
            |              +-- StableKey: SHA-256 of worktree path (16 hex)
            +-- StableKey: SHA-256 of repo path (16 hex)

Length: 65 characters (fixed)
```

Generated by `ZmxBackend.sessionId(repoStableKey:worktreeStableKey:paneId:)`. Deterministic — same repo path + worktree path + pane UUID triple always produces the same session ID.

### Orphan Cleanup

On app launch, `AppDelegate.cleanupOrphanZmxSessions()` discovers zmx daemons with `agentstudio--` prefix that are not tracked by any persisted session, and kills them. This prevents stale daemons from accumulating across app restarts.

---

## SessionStatus State Machine (Dormant)

A full 7-state machine exists in `Models/StateMachine/SessionStatus.swift` for future integration with zmx backend health monitoring. It is **not yet wired** into `SessionRuntime` (which uses the simpler `SessionRuntimeStatus` enum above).

```mermaid
stateDiagram-v2
    [*] --> unknown
    unknown --> verifying: verify / create
    verifying --> verifying: socketFound (checkSessionExists)
    verifying --> alive: sessionDetected / created
    verifying --> missing: socketMissing / sessionNotDetected
    verifying --> failed: createFailed
    alive --> alive: healthCheckPassed
    alive --> dead: healthCheckFailed / sessionDied
    alive --> verifying: verify (re-check)
    dead --> recovering: attemptRecovery
    dead --> verifying: create
    missing --> verifying: create
    missing --> recovering: attemptRecovery
    recovering --> alive: recoverySucceeded
    recovering --> failed: recoveryFailed
    failed --> verifying: create / verify
```

**States:** `unknown`, `verifying`, `alive`, `dead`, `missing`, `recovering`, `failed(reason)`

**Effects:** Each transition can trigger effects (e.g., `checkSocket`, `createSession`, `scheduleHealthCheck`, `notifyAlive`, `notifyDead`) that are executed by the `Machine<SessionStatus>` effect handler.

---

## Key Files

| File | Role |
|------|------|
| `Services/WorkspaceStore.swift` | Central state owner — sessions, views, tabs, layouts, persistence |
| `Services/WorkspacePersistor.swift` | JSON serialization/deserialization |
| `Services/SessionRuntime.swift` | Runtime health monitoring and status tracking |
| `App/ActionExecutor.swift` | Dispatches actions (open, close, split, undo, etc.) |
| `App/TerminalViewCoordinator.swift` | Creates/restores views, sole intermediary for surface lifecycle |
| `Models/TerminalSession.swift` | Session identity with source, provider, lifetime, residency |
| `Models/SessionLifetime.swift` | `.persistent` / `.temporary` enum |
| `Models/SessionResidency.swift` | `.active` / `.pendingUndo` / `.backgrounded` enum |
| `Models/Layout.swift` | Value-type split layout tree (Codable for persistence) |
| `Models/Tab.swift` | Tab with layout and active session |
| `Models/Templates.swift` | Worktree/terminal templates for session creation |
| `Models/SessionConfiguration.swift` | Config detection from env vars |
| `Models/StateMachine/SessionStatus.swift` | 7-state machine definition for future zmx health |
| `Models/StateMachine/StateMachine.swift` | Generic state machine with effect handling |
| `Services/ProcessExecutor.swift` | Protocol + `DefaultProcessExecutor` for CLI execution |
| `Services/Backends/ZmxBackend.swift` | zmx CLI wrapper — session ID gen, create/destroy/healthCheck |
| `Views/AgentStudioTerminalView.swift` | Terminal view (displays surfaces, does not own them) |
| `AppDelegate.swift` | Launch flow — restore workspace, create window |

## Related Documentation

- **[Architecture Overview](README.md)** — System overview and document index
- **[Component Architecture](component_architecture.md)** — Data model, service layer, data flow, persistence
- **[Surface Architecture](ghostty_surface_architecture.md)** — Surface ownership, state machine, undo close, health monitoring
- **[App Architecture](appkit_swiftui_architecture.md)** — AppKit + SwiftUI hybrid, lifecycle management
