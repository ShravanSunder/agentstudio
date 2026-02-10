# Session Lifecycle Architecture

Agent Studio manages terminal session lifecycle through `WorkspaceStore` (persistence), `SessionRuntime` (health/state tracking), and `TerminalViewCoordinator` (view/surface lifecycle). The tmux backend (`TmuxBackend`) is available for future session persistence across app restarts.

## Current Architecture (Phase B)

```
+-------------------------------+
| App Launch                    |
| AppDelegate.didFinishLaunching|
+--------------+----------------+
               |
+--------------v-----------------+
| WorkspaceStore.restore()       |
| - Load persisted state         |
| - Filter temporary sessions    |
| - Prune dangling layout refs   |
| - Ensure main view exists      |
+---------------+----------------+
                |
                v
+-------------------------------+
| SessionRuntime.start()         |
| - Begin health monitoring      |
+---------------+----------------+
                |
                v
+-------------------------------+
| MainWindowController created   |
| - Store, Executor, Adapter,   |
|   ViewRegistry wired           |
+-------------------------------+
```

### Session Identity

A single `sessionId: UUID` is the identity used across ALL layers:
- `WorkspaceStore` — owns session records
- `Layout` / `Tab` / `ViewDefinition` — references sessions by ID
- `ViewRegistry` — maps sessionId → NSView
- `SurfaceManager` — keyed by sessionId
- `SessionRuntime` — health tracking by sessionId

### Terminal Creation Flow

```
ActionExecutor.execute(.openTerminal)
       │
       ├─► WorkspaceStore.createSession(source:)
       │     → Returns TerminalSession with new sessionId
       │
       ├─► TerminalViewCoordinator.createView(session:worktree:repo:)
       │     → Creates AgentStudioTerminalView
       │     → Creates Ghostty surface via SurfaceManager
       │     → Attaches surface to view
       │     → Registers in ViewRegistry
       │
       └─► WorkspaceStore.appendTab(Tab(sessionId:))
             → Adds tab to active view layout
```

### App Termination

```
AppDelegate.applicationWillTerminate
       │
       └─► WorkspaceStore.flush()
             → Cancels debounced save
             → Filters temporary sessions
             → Prunes dangling layout refs
             → Persists to disk
```

## Persistence

### WorkspaceStore Persistence

State is persisted via `WorkspacePersistor` as JSON. On save:
1. Temporary sessions (`.lifetime == .temporary`) are excluded
2. View layouts are pruned of dangling session IDs
3. State is serialized and written to disk

On restore:
1. State is loaded from disk
2. Temporary sessions are filtered out
3. View layouts are pruned of any dangling session IDs
4. Main view is ensured to exist

### Undo Close

`WorkspaceStore.snapshotForClose(tabId:)` captures a `CloseSnapshot` containing the tab, its sessions, view context, and tab index. `restoreFromSnapshot()` re-inserts the tab and sessions at the original position.

## Headless tmux Model (Future Phase 4)

The tmux backend is available for session persistence across app restarts. When enabled, terminal sessions will survive app crashes — the user sees only a Ghostty terminal surface while tmux preserves the PTY and scrollback in the background.

### Socket Isolation

tmux runs on a dedicated socket `-L agentstudio`, completely separate from any user-owned tmux server. The user's `~/.tmux.conf` and default server are never touched.

### ghost.conf Settings

| Setting | Value | Purpose |
|---------|-------|---------|
| `prefix` | `None` | No prefix key — tmux won't intercept any keystrokes |
| `status` | `off` | No status bar — tmux is invisible |
| `destroy-unattached` | `off` | Session persists when app disconnects |
| `exit-unattached` | `off` | tmux server stays running with no clients |
| `default-terminal` | `xterm-256color` | Avoids Kitty keyboard protocol conflicts between tmux and GhosttyKit (xterm-ghostty causes keystroke doubling) |
| `extended-keys` | `off` | Prevents additional keyboard protocol conflicts |
| `escape-time` | `0` | No escape delay — immediate key processing |
| `mouse` | `on` | Forward scroll/click events to Ghostty |
| `history-limit` | `50000` | Large scrollback preserved across restarts |
| `set-environment -g -u TMUX` | (unset) | Allows users to run their own tmux inside ghost sessions without nesting conflicts |

### Terminal Overrides

ghost.conf restores visual capabilities lost by using `xterm-256color` instead of `xterm-ghostty`:
- **RGB**: True color support via `RGB` terminal feature
- **Styled underlines**: `Smulx` for underline styles (curly, dotted, dashed)
- **Underline colors**: `Setulc` for colored underlines
- **Kitty keyboard protocol**: Deliberately **excluded** to prevent conflicts with GhosttyKit's native keyboard handling

## Session ID Format

```
agentstudio--<repo16hex>--<worktree16hex>--<pane16hex>
            |              |                |
            |              |                +-- First 16 hex chars of pane UUID (lowercase)
            |              +-- StableKey: 16 hex chars from SHA-256 of worktree path
            +-- StableKey: 16 hex chars from SHA-256 of repo path

Example: agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--a1b2c3d4e5f6a7b8
Length:  65 characters (fixed)
```

Generated by `TmuxBackend.sessionId(repoStableKey:worktreeStableKey:paneId:)`. Deterministic — same repo path + worktree path + pane UUID triple always produces the same session ID.

## Key Files

| File | Role |
|------|------|
| `Services/WorkspaceStore.swift` | Central state owner — sessions, views, tabs, layouts, persistence |
| `Services/WorkspacePersistor.swift` | JSON serialization/deserialization |
| `Services/SessionRuntime.swift` | Runtime health monitoring and state tracking |
| `App/ActionExecutor.swift` | Dispatches actions (open, close, split, etc.) |
| `App/TerminalViewCoordinator.swift` | Creates/restores views, sole intermediary for surface lifecycle |
| `Models/TerminalSession.swift` | Session identity with source, provider, lifetime, residency |
| `Models/Layout.swift` | Value-type split layout tree (Codable for persistence) |
| `Models/Tab.swift` | Tab with layout and active session |
| `Models/SessionConfiguration.swift` | Config detection from env vars |
| `Models/StateMachine/SessionStatus.swift` | State machine definition for session lifecycle |
| `Models/StateMachine/Machine.swift` | Generic state machine with effect handling |
| `Services/ProcessExecutor.swift` | Protocol + `DefaultProcessExecutor` for CLI execution |
| `Services/Backends/TmuxBackend.swift` | tmux CLI wrapper — session ID gen, create/destroy/healthCheck |
| `Resources/tmux/ghost.conf` | Headless tmux configuration |
| `Views/AgentStudioTerminalView.swift` | Terminal view (displays surfaces, does not own them) |
| `AppDelegate.swift` | Launch flow — restore workspace, create window |

## Related Documentation

- [Ghostty Surface Architecture](ghostty_surface_architecture.md) — Surface ownership, state machine, undo close, health monitoring
- [App Architecture](app_architecture.md) — AppKit + SwiftUI hybrid, lifecycle management
