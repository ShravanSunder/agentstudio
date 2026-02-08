# Session Restore Architecture

Agent Studio uses tmux as an invisible session persistence daemon. Terminal sessions survive app crashes and restarts — the user sees only a Ghostty terminal surface while tmux preserves the PTY and scrollback in the background.

## Lifecycle Overview

```
+-------------------------------+
| App Launch                    |
| AppDelegate.didFinishLaunching|
+--------------+----------------+
               |
+--------------v-----------------+
| SessionRegistry.initialize()   |
| - SessionConfiguration.detect()|
| - if enabled + tmux found:     |
|   create TmuxBackend           |
| - load checkpoint, verify      |
|   surviving sessions           |
+---------------+----------------+
                |
      +---------+---------+
      |                   |
      v                   v
+------------+    +----------------+
| backend=nil|    | backend=tmux   |
| (degraded) |    | (operational)  |
+------+-----+    +-------+-------+
       |                  |
       v                  v
+------+------------------+------+
| Window created                 |
| Terminal views check           |
| isOperational on setup         |
+---------------+----------------+
                |
      +---------+---------+
      |                   |
      v                   v
+-----------+   +----------------------------+
| direct    |   | setupTerminalWith          |
| shell     |   | SessionRestore()           |
| (no tmux) |   +-------------+--------------+
+-----------+                 |
                              v
              +-------------------------------+
              | registerPaneSession(id, ...)  |
              | (tracking only, no tmux CLI)  |
              +---------------+---------------+
                              |
                              v
              +-------------------------------+
              | attachCommand() returns:      |
              | tmux -L agentstudio           |
              |   -f ghost.conf               |
              |   new-session -A              |
              |   -s <session-id>             |
              |   -c <working-dir>            |
              +---------------+---------------+
                              |
                              v
              +-------------------------------+
              | Ghostty Surface runs command  |
              | - creates session if missing  |
              | - attaches if already exists  |
              +---------------+---------------+
                              |
                              v
              +-------------------------------+
              | Background health checks      |
              | tmux has-session -t <id>      |
              | state machine transitions     |
              | recovery on failure           |
              +---------------+---------------+
                              |
                              v
              +-------------------------------+
              | App terminate                 |
              | saveCheckpoint()              |
              | stopHealthChecks()            |
              +-------------------------------+
```

## Headless tmux Model

```
+----------------------------------------------------------+
|                    What the user sees                     |
|                                                          |
|  +----------------------------------------------------+  |
|  |           Ghostty Terminal Surface                  |  |
|  |  (renders terminal output, handles keyboard/mouse) |  |
|  +----------------------------------------------------+  |
|                                                          |
+----------------------------------------------------------+

+----------------------------------------------------------+
|              What runs invisibly underneath               |
|                                                          |
|  tmux -L agentstudio (isolated socket)                   |
|    Session: agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--a1b2c3d4e5f6a7b8    |
|    Role: PTY holder + scrollback preservation            |
|    Config: ghost.conf (no UI, no prefix, no status bar)  |
|                                                          |
+----------------------------------------------------------+
```

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

Generated by `TmuxBackend.sessionId(repoStableKey:worktreeStableKey:paneId:)`. Deterministic — same repo path + worktree path + pane UUID triple always produces the same session ID. The repo and worktree segments are `StableKey` values (SHA-256 of resolved filesystem path, first 8 bytes as hex). The pane segment is the first 16 hex chars of the pane UUID from `AgentStudioTerminalView`, persisted through the split tree Codable chain. This ensures split panes get independent tmux sessions.

Validated by `PaneSessionHandle.hasValidId`: must start with `agentstudio--`, contain exactly 3 segments of exactly 16 lowercase hex chars each.

## Session Creation Paths

### Surface-Driven (Production Path)

Used by `AgentStudioTerminalView` for all terminal creation:

1. `registerPaneSession(id:...)` — registers the session for health tracking in `SessionRegistry.entries`
2. `attachCommand(for:in:paneId:)` — returns `tmux -L agentstudio -f ghost.conf new-session -A -s <id> -c <cwd>`
3. Ghostty surface executes the command — `new-session -A` creates the session if it doesn't exist, or attaches to it if it does
4. Health checks begin automatically

The `-A` flag is the key mechanism for transparent session reuse across app restarts.

### Registry-Driven (Background Creation)

Used by `getOrCreatePaneSession(for:in:paneId:)`:

1. Creates the tmux session via `tmux new-session -d` (detached/headless)
2. Registers the handle in `entries` with state `.alive`
3. Returns the `PaneEntry` for the caller to use

This path creates the session first, then the caller attaches. Not currently used by terminal views but available for programmatic session management.

## Checkpoint Persistence

### Format

`SessionCheckpoint` (version 3, JSON):

```json
{
  "version": 3,
  "timestamp": "2026-02-08T15:11:03Z",
  "sessions": [
    {
      "sessionId": "agentstudio--a1b2c3d4e5f6a7b8--00112233aabbccdd--a1b2c3d4e5f6a7b8",
      "paneId": "A1B2C3D4-E5F6-A7B8-0011-2233AABBCCDD",
      "projectId": "A1B2C3D4-...",
      "worktreeId": "E5F6A7B8-...",
      "displayName": "main",
      "workingDirectory": "/path/to/worktree",
      "lastKnownAlive": "2026-02-08T15:11:03Z"
    }
  ]
}
```

### Save

`SessionRegistry.saveCheckpoint()` is called:
- After every `registerPaneSession` / `unregisterPaneSession` / `getOrCreatePaneSession`
- On `applicationWillTerminate` via `AppDelegate`

### Load + Verify

On app launch, `SessionRegistry.initialize()`:
1. Loads checkpoint from disk
2. Checks staleness (max age: 1 week)
3. Sessions with invalid IDs (not matching 3-segment 16-hex format) are destroyed via `destroySessionById()` and skipped
4. For each valid session, calls `backend.sessionExists()` (`tmux has-session`)
5. Only sessions that are still alive in tmux are added to `entries`
6. Dead sessions are silently skipped

## Health Monitoring

Each tracked session gets a periodic health check task:

```
                    scheduleHealthCheck(for: sessionId)
                              |
                    +---------v---------+
                    | Task.sleep(30s)   |  (configurable via AGENTSTUDIO_HEALTH_INTERVAL)
                    +---------+---------+
                              |
                    +---------v---------+
                    | tmux has-session  |
                    | -t <session-id>   |
                    +---------+---------+
                              |
                    +---------+---------+
                    |                   |
                    v                   v
              +----------+      +-----------+
              | alive    |      | dead      |
              | → .alive |      | → .dead   |
              | (loop)   |      | (cancel   |
              +----------+      |  checks)  |
                                +-----------+
```

### State Machine

Sessions use `Machine<SessionStatus>` with states:

| State | Meaning |
|-------|---------|
| `.unknown` | Initial state before verification |
| `.verifying` | Checking socket and session existence |
| `.alive` | Session is running and healthy |
| `.dead` | Health check failed, session may be recoverable |
| `.recovering` | Attempting recovery |
| `.failed(reason:)` | Unrecoverable failure |

### Effect Handlers

State transitions trigger effects handled by `SessionRegistry`:

| Effect | Action |
|--------|--------|
| `.checkSocket` | Verify tmux socket exists |
| `.checkSessionExists` | Run `tmux has-session` |
| `.scheduleHealthCheck` | Start periodic health monitoring |
| `.cancelHealthCheck` | Stop health monitoring |
| `.attemptRecovery` | Try to recover dead session |
| `.destroySession` | Kill tmux session via backend |
| `.notifyAlive` / `.notifyDead` / `.notifyFailed` | Logging |

## Tab Restore Flow

When the app relaunches with saved tab state:

1. `AgentStudioTerminalView.init(from: Decoder)` — decodes worktree/repo IDs, calls `init(worktree:repo:restoring:true)`
2. Terminal setup is **deferred** — no shell process spawned during decode
3. When the view enters a window (`viewDidMoveToWindow`), if `surfaceId == nil && !isSettingUp`:
   - If `isOperational`: calls `setupTerminalWithSessionRestore()` → registers + attaches via `new-session -A`
   - If not operational: calls `setupTerminal()` with direct shell

The `isSettingUp` guard prevents a race condition where the async setup from `init()` hasn't completed when `viewDidMoveToWindow` fires, which would create duplicate surfaces. This deferred pattern prevents orphaned processes when restoring many tabs.

## Key Files

| File | Role |
|------|------|
| `Models/SessionRegistry.swift` | Central orchestrator — owns entries, drives state machines, persists checkpoints |
| `Models/SessionConfiguration.swift` | Config detection from env vars, `isOperational` check |
| `Models/SessionCheckpoint.swift` | Codable checkpoint model (v3 JSON) |
| `Models/StateMachine/SessionStatus.swift` | State machine definition for session lifecycle |
| `Models/StateMachine/Machine.swift` | Generic state machine with effect handling |
| `Services/SessionBackend.swift` | Protocol + `DefaultProcessExecutor` (pipe-drain-then-wait) |
| `Services/Backends/TmuxBackend.swift` | tmux CLI wrapper — session ID gen, create/destroy/healthCheck |
| `Resources/tmux/ghost.conf` | Headless tmux configuration |
| `Views/AgentStudioTerminalView.swift` | Terminal view with session restore integration |
| `AppDelegate.swift` | Launch flow — initialize registry before window creation |

## Related Documentation

- [Ghostty Surface Architecture](ghostty_surface_architecture.md) — Surface ownership, state machine, undo close, health monitoring
- [App Architecture](app_architecture.md) — AppKit + SwiftUI hybrid, lifecycle management
