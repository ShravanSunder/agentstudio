# Session Lifecycle Architecture

## TL;DR

A pane's identity (`PaneId`) is stable across its entire lifecycle — creation, layout changes, view switches, close/undo, persistence, and restore. `WorkspaceStore` owns pane records. `SessionRuntime` tracks runtime health. `PaneCoordinator` bridges panes to surfaces. Panes can be undone via a `CloseEntry` stack. The zmx backend provides persistence across app restarts.

---

## Identity Contract (Canonical)

`PaneId` is the only primary identity. Backend session names are derived keys.
This section is the source of truth for identity, restore lookups, and zmx key
derivation.

### Identifier Types

| Identifier | Type | Owner | Persisted | Generation | Used For |
|------------|------|-------|-----------|------------|----------|
| `PaneId` | `PaneId` (`struct` wrapping `UUID`) | `WorkspaceStore` | Yes | `Pane.init(id: UUID = UUIDv7.generate(), ...)` with `PaneMetadata.paneId = PaneId(uuid: id)` | Universal pane identity across store/layout/view/runtime/surface |
| `RepoStableKey` | `String` (16 hex) | `Repo` | Derived | `StableKey.fromPath(repoPath)` | Deterministic zmx key segment |
| `WorktreeStableKey` | `String` (16 hex) | `Worktree` | Derived | `StableKey.fromPath(worktree.path)` | Deterministic zmx key segment |
| `MainZmxSessionId` | `String` (65 chars) | `ZmxBackend` | Derived | `agentstudio--<repo16>--<worktree16>--<pane16>` | zmx daemon/socket identity for layout panes |
| `DrawerZmxSessionId` | `String` (49 chars) | `ZmxBackend` | Derived | `agentstudio-d--<parentPane16>--<drawerPane16>` | zmx daemon/socket identity for drawer panes |

### Session Name Calculation Rules

1. `pane16 = first16hex(lowercase(removeHyphens(paneId.uuidString)))`
2. `mainSessionId = "agentstudio--" + repoStableKey + "--" + worktreeStableKey + "--" + pane16`
3. `drawerSessionId = "agentstudio-d--" + parentPane16 + "--" + drawerPane16`
4. `repoStableKey` and `worktreeStableKey` are deterministic SHA-256 path keys (16 hex chars each)

### PaneId Lifecycle (ASCII)

```text
USER ACTION (open terminal / split / drawer)
    |
    v
PaneCoordinator.create/open*
    |
    v
WorkspaceStore.createPane(...)
    -> Pane(id = UUIDv7.generate())      <-- PaneId minted once
    -> panes[paneId] = Pane
    |
    v
Tab/Layout references created
    -> Tab.panes[] contains paneId
    -> Layout.leaf(paneId)
    |
    v
Persist (WorkspacePersistor JSON)
    -> Pane.id stored
    -> Tab/Layout paneId references stored
    |
    v   app relaunch
Restore (WorkspaceStore.restore)
    -> panes = Dictionary(state.panes by pane.id)
    -> prune invalid paneId references
    -> repair invariants (activePaneId, duplicate pane IDs, etc.)
    |
    v
PaneCoordinator.restoreAllViews()
    -> lookup Pane by paneId
    -> create/reattach surface + register view by paneId
```

### zmx Interplay and Lookups (ASCII)

```text
PaneId + RepoStableKey + WorktreeStableKey
                  |
                  v
      ZmxBackend.sessionId(...)
                  |
                  v
  "agentstudio--repo16--wt16--pane16"
                  |
                  v
      zmx attach/list/kill (scoped by ZMX_DIR)
                  |
                  v
AppDelegate.cleanupOrphanZmxSessions()
  - derive known IDs from persisted panes
  - compare with one zmx list snapshot
  - classify runtime-only sessions as orphan candidates
  - apply grace TTL (60s), re-check liveness, then kill if still orphaned
```

### Lookup Ownership Table

| Lookup | Source of Truth | API/Path |
|--------|------------------|----------|
| `paneId -> Pane` | `WorkspaceStore.panes` | `store.pane(paneId)` / dictionary lookup |
| `paneId -> View` | `ViewRegistry` | `viewRegistry.view(for: paneId)` |
| `paneId -> RuntimeStatus` | `SessionRuntime.statuses` | `runtime.status(for: paneId)` |
| `paneId -> Surface` | `SurfaceManager` metadata/state | `SurfaceMetadata.paneId`, attach/detach paths |
| `paneId + repo/worktree -> zmx session name` | `ZmxBackend` deterministic function | `ZmxBackend.sessionId(...)` |
| `zmx session name -> live daemon` | zmx process state in `ZMX_DIR` | `zmx list` parse |

### Socket Path Budget (Darwin)

`zmx` creates Unix socket paths as:
`socketPath = zmxDir + "/" + sessionName`

Darwin `sockaddr_un.sun_path` is 104 bytes, so practical max is:
`socketPath.count <= 103`

This makes session name length a hard runtime constraint, not just formatting.
`ZmxTestHarness` uses short `/tmp/zt-<id>` paths specifically to stay under this limit.

## Session Properties

Every pane carries metadata that determines its behavior:

```
Pane
├── id: UUID                    ← immutable primary key
├── content: PaneContent        ← .terminal/.webview/.codeViewer/.bridgePanel
├── metadata: PaneMetadata      ← title/source/cwd/tags
├── kind: PaneKind              ← .layout or .drawerChild
└── residency: SessionResidency ← .active/.pendingUndo/.backgrounded
```

---

## Session Lifecycle States

### Residency (Persisted)

`SessionResidency` tracks where a pane lives in the application lifecycle. This prevents false-positive orphan detection — a pane in `pendingUndo` is not an orphan.

```mermaid
stateDiagram-v2
    [*] --> active: createPane()
    active --> pendingUndo: closeTab (enters undo window)
    active --> backgrounded: view switch (pane leaves active view)
    pendingUndo --> active: undoCloseTab()
    pendingUndo --> [*]: undo expires / GC
    backgrounded --> active: view switch (pane enters active view)
    backgrounded --> [*]: explicit removal
```

### Runtime Status (Not Persisted)

`SessionRuntimeStatus` tracks live backend state per pane. Created fresh on each app launch.

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
    participant PC as PaneCoordinator
    participant Store as WorkspaceStore
    participant SM as SurfaceManager
    participant VR as ViewRegistry
    participant RT as SessionRuntime

    User->>PC: openTerminal(worktree, repo)
    PC->>PC: Check if worktree already has active pane
    alt Already open
        PC->>Store: setActiveTab(existingTab.id)
    else New session needed
        PC->>Store: createPane(source: .worktree, content: .terminal(.zmx))
        Store-->>PC: Pane (new UUID)
        PC->>SM: createSurface(config, metadata)
        SM-->>PC: ManagedSurface
        PC->>SM: attach(surfaceId, paneId)
        PC->>VR: register(view, paneId)
        PC->>RT: markRunning(paneId)

        alt Surface creation failed
            PC->>Store: removePane(pane.id)
            Note over PC: Rollback — no orphan pane
        else Success
            PC->>Store: appendTab(Tab(paneId))
            PC->>Store: setActiveTab(tab.id)
        end
    end
```

---

## Close & Undo Flow

### Close Tab

1. `PaneCoordinator.executeCloseTab(tabId)`:
   - `store.snapshotForClose(tabId)` → `TabCloseSnapshot` (tab, panes, tabIndex)
   - Push to `undoStack` (LIFO, max 10 entries)
   - For each pane in the tab: `coordinator.teardownView(paneId)`
     - `ViewRegistry.unregister(paneId)`
     - `SurfaceManager.detach(surfaceId, reason: .close)` → surface enters SurfaceManager undo stack with TTL (5 min)
   - `store.removeTab(tabId)` — panes remain in `store.panes` (not deleted)
   - `expireOldUndoEntries()` — GC entries beyond max, remove orphaned sessions

### Undo Close Tab (`Cmd+Shift+T`)

2. `PaneCoordinator.undoCloseTab()`:
   - Pop `WorkspaceStore.CloseEntry` from undo stack
   - `store.restoreFromSnapshot(snapshot)` — re-insert tab at original position
   - For each pane in **reversed** order (matching SurfaceManager LIFO):
     - `coordinator.restoreView(pane, worktree, repo)`
     - `SurfaceManager.undoClose()` → pop surface from undo stack
     - Verify `metadata.paneId` matches (multi-pane safety)
     - Reattach surface (no recreation)

### Close Pane (With Undo)

`executeClosePane(tabId, paneId)`:
- `store.snapshotForPaneClose(paneId, inTab: tabId)` creates a pane-level undo snapshot
- Push `.pane(PaneCloseSnapshot)` to `undoStack`
- `coordinator.teardownView(paneId)` detaches/destroys runtime view state
- `store.removePaneFromLayout(paneId, inTab: tabId)`; if last pane, close escalates to tab-close path
- Undo via `undoCloseTab()` restores the pane snapshot when its tab/parent context is still valid

---

## App Launch Restore

```mermaid
sequenceDiagram
    participant AD as AppDelegate
    participant Store as WorkspaceStore
    participant P as WorkspacePersistor
    participant Coord as PaneCoordinator

    AD->>Store: restore()
    Store->>P: load()
    P-->>Store: PersistableState (JSON)

    Note over Store: Filter out temporary panes
    Note over Store: Remove panes with deleted worktrees
    Note over Store: Prune dangling pane IDs from layouts
    Note over Store: Remove empty tabs, fix activeTabId

    AD->>Coord: restoreAllViews()
    loop each pane in active tabs
        Coord->>Coord: createViewForContent(pane) / restoreView(pane)
    end

    AD->>AD: Create MainWindowController
```

**Restore filtering details:**
- **Temporary filtering**: Panes with `lifetime == .temporary` are removed
- **Worktree validation**: Panes referencing a `worktreeId` not in any repo's worktrees are removed (worktree was deleted between launches)
- **Layout pruning**: Pane IDs not in the valid pane set are removed from all layout nodes; single-child splits collapse; empty tabs removed
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
- Temporary panes never persisted
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

### Session Name Derivation

See **Identity Contract (Canonical)** above for the complete source of truth.

- Main panes: `ZmxBackend.sessionId(repoStableKey:worktreeStableKey:paneId:)`
- Drawer panes: `ZmxBackend.drawerSessionId(parentPaneId:drawerPaneId:)`
- Both are deterministic for a given input tuple and depend on stable path keys.

### Orphan Cleanup

On app launch, `AppDelegate.cleanupOrphanZmxSessions()` discovers zmx daemons
with Agent Studio prefixes that are not tracked by persisted panes and marks
them as orphan candidates.

Policy is TTL-based and never immediate:

1. Do not kill on discovery.
2. Apply a grace TTL (default 60 seconds).
3. Re-check `zmx list` at TTL expiration.
4. Kill only if the session is still orphaned.

This must stay aligned with:
- [Zmx Restore and Sizing — Orphan Cleanup TTL Policy](zmx_restore_and_sizing.md#orphan-cleanup-ttl-policy)
- [Pane Runtime Architecture — Contract 5b](pane_runtime_architecture.md#contract-5b-restart-reconcile-policy-luna-324)

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
| `Core/Stores/WorkspaceStore.swift` | Atomic store — workspace structure (panes, tabs, layouts, persistence) |
| `Core/Stores/WorkspacePersistor.swift` | JSON serialization/deserialization |
| `Core/Stores/SessionRuntime.swift` | Runtime health monitoring and status tracking |
| `App/PaneCoordinator.swift` | Dispatches actions (open, close, split, undo, etc.) and is the sole intermediary for view/surface orchestration |
| `Core/Models/Pane.swift` | Pane identity and content metadata |
| `Core/Models/SessionLifetime.swift` | `.persistent` / `.temporary` enum |
| `Core/Models/SessionResidency.swift` | `.active` / `.pendingUndo` / `.backgrounded` enum |
| `Core/Models/Layout.swift` | Value-type split layout tree (Codable for persistence) |
| `Core/Models/Tab.swift` | Tab with layout and active pane |
| `Core/Models/SessionConfiguration.swift` | Config detection from env vars |
| `Core/Models/StateMachine/SessionStatus.swift` | 7-state machine definition for future zmx health |
| `Infrastructure/StateMachine/StateMachine.swift` | Generic state machine with effect handling |
| `Infrastructure/ProcessExecutor.swift` | Protocol + `DefaultProcessExecutor` for CLI execution |
| `Core/Stores/ZmxBackend.swift` | zmx CLI wrapper — session ID gen, create/destroy/healthCheck |
| `Features/Terminal/Views/AgentStudioTerminalView.swift` | Terminal view (displays surfaces, does not own them) |
| `App/AppDelegate.swift` | Launch flow — restore workspace, create window |

## Related Documentation

- **[Architecture Overview](README.md)** — System overview and document index
- **[Component Architecture](component_architecture.md)** — Data model, service layer, data flow, persistence
- **[Surface Architecture](ghostty_surface_architecture.md)** — Surface ownership, state machine, undo close, health monitoring
- **[App Architecture](appkit_swiftui_architecture.md)** — AppKit + SwiftUI hybrid, lifecycle management
